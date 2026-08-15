#!/usr/bin/env python3
"""Tiny range-aware server that streams the latest edited clip into Claude's preview panel.

Auto-picks the most recently modified video under projects/*/outputs/ at request time,
so re-opening always shows whatever cut we're currently working on.
"""
import http.server
import os
import re
import socketserver
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent  # project root (.claude/..)
PORT = 7842
VIDEO_EXTS = (".mp4", ".mov", ".m4v", ".webm")


def latest_clip():
    candidates = []
    for outputs in ROOT.glob("projects/*/outputs"):
        for f in outputs.iterdir():
            if f.suffix.lower() in VIDEO_EXTS:
                candidates.append(f)
    if not candidates:
        return None
    return max(candidates, key=lambda p: p.stat().st_mtime)


def human_size(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        clip = latest_clip()
        if self.path.startswith("/video"):
            return self.serve_video(clip)
        return self.serve_page(clip)

    def serve_page(self, clip):
        if not clip:
            body = b"<h1 style='font:600 18px system-ui;color:#fff'>No clip found under projects/*/outputs/</h1>"
        else:
            st = clip.stat()
            from datetime import datetime
            name = clip.name
            meta = f"{human_size(st.st_size)} · {datetime.fromtimestamp(st.st_mtime).strftime('%b %-d, %-I:%M %p')}"
            html = f"""<!doctype html><html><head><meta charset=utf-8>
<title>{name}</title><style>
*{{margin:0;box-sizing:border-box}}
html,body{{height:100%;background:#0c0c0f;font-family:-apple-system,system-ui,sans-serif}}
.wrap{{height:100%;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:14px;padding:16px}}
video{{max-width:100%;max-height:calc(100% - 48px);border-radius:10px;box-shadow:0 12px 48px rgba(0,0,0,.6);background:#000}}
.bar{{color:#e9e9ee;font-size:13px;letter-spacing:.2px}}
.bar b{{font-weight:600}} .bar span{{color:#8a8a96;margin-left:8px}}
</style></head><body><div class=wrap>
<video src="/video.mp4" controls autoplay muted playsinline></video>
<div class=bar><b>{name}</b><span>{meta}</span></div>
</div></body></html>"""
            body = html.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def serve_video(self, clip):
        if not clip or not clip.exists():
            self.send_error(404)
            return
        size = clip.stat().st_size
        rng = self.headers.get("Range")
        start, end = 0, size - 1
        status = 200
        if rng:
            m = re.match(r"bytes=(\d*)-(\d*)", rng)
            if m:
                if m.group(1):
                    start = int(m.group(1))
                if m.group(2):
                    end = int(m.group(2))
                status = 206
        length = end - start + 1
        self.send_response(status)
        self.send_header("Content-Type", "video/mp4")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(length))
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        with open(clip, "rb") as f:
            f.seek(start)
            remaining = length
            while remaining > 0:
                chunk = f.read(min(65536, remaining))
                if not chunk:
                    break
                try:
                    self.wfile.write(chunk)
                except (BrokenPipeError, ConnectionResetError):
                    break
                remaining -= len(chunk)


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    os.chdir(ROOT)
    with Server(("127.0.0.1", PORT), Handler) as httpd:
        print(f"preview server on http://127.0.0.1:{PORT}")
        httpd.serve_forever()
