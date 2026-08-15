#!/usr/bin/env python3
"""make-clips.py: scaffold and build clip sub-jobs from a clips-plan.json.

Part of the clipper skill. Reads projects/<parent>/clips-plan.json (authored by
the skill's selection pass) and turns each approved clip into a standard job
folder under projects/<parent>/clips/<name>/, then (with --build) runs the full
lane per clip: rough-cut splice, 9:16 face-centered reframe, locked tiktok-raw
captions, deliverable + export copy.

Usage:
  python3 .claude/skills/clipper/scripts/make-clips.py <parent_job_dir>              # scaffold only
  python3 .claude/skills/clipper/scripts/make-clips.py <parent_job_dir> --build      # scaffold + build all
  python3 .claude/skills/clipper/scripts/make-clips.py <parent_job_dir> --build --only <name> [<name> ...]

Env:
  AMPLIFY_DB   passes through to splice.sh (re-run a clip with 8 when audio-qa warns)
  VE_EXPORT_DIR  overrides the ~/Downloads export-copy target

Per clip, --build does:
  1. splice.sh on the clip folder  -> outputs/<name>.mp4 (16:9) + canonical transcript
  2. face-frame.py measures the face -> face-centered crop to 1080x1920
     (center crop when no face is detectable, e.g. screencast-heavy clips);
     the 16:9 original is kept as outputs/<name>-169.mp4
  3. presets/tiktok-raw/build.py  -> outputs/<name>.final.mp4 (captions always on,
     hook card only when the plan gives hook_text)
  4. export copy of the deliverable into ~/Downloads (or VE_EXPORT_DIR)
"""

import json
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path
# Windows consoles/pipes default to cp1252, which can't encode the {glyphs} glyphs in this
# script's status lines: a cosmetic print must never kill a pipeline step (it did once,
# 2026-08-13, mid-splice on a real Windows job). Force UTF-8; no-op on macOS/Linux.
for _s in (sys.stdout, sys.stderr):
    try:
        if (getattr(_s, "encoding", "") or "").lower().replace("-", "") != "utf8":
            _s.reconfigure(encoding="utf-8")
    except AttributeError:
        pass

REPO = Path(__file__).resolve().parents[4]
SPLICE = REPO / ".claude/skills/rough-cut/scripts/splice.sh"
FACE_FRAME = REPO / "workflows/face-frame.py"
TIKTOK_BUILD = REPO / "presets/tiktok-raw/build.py"


def die(msg):
    sys.exit(f"make-clips: {msg}")


def run(cmd, **kw):
    """Run a child streaming its output (audio-qa warnings must stay visible)."""
    print(f"  $ {' '.join(str(c) for c in cmd)}", flush=True)
    return subprocess.run([str(c) for c in cmd], **kw).returncode


def probe_wh(video):
    out = subprocess.check_output([
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=width,height", "-of", "csv=p=0", str(video)])
    # iPhone footage carries stream side data that the csv writer emits as extra
    # elements/rows ("1920,1080," or an extra line): keep the first two real tokens.
    tok = [t for t in out.decode().strip().splitlines()[0].split(",") if t.strip()]
    return int(tok[0]), int(tok[1])


def encoder_args():
    if platform.system() == "Darwin":
        return ["-c:v", "h264_videotoolbox", "-b:v", "10M"]
    return ["-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p"]


def scaffold(parent, clip, source, words):
    """Create the clip's standard job folder + authored cuts (durable and /tmp)."""
    name = clip["name"]
    cdir = parent / "clips" / name
    for sub in ("raw", "transcript", "outputs"):
        (cdir / sub).mkdir(parents=True, exist_ok=True)

    link = cdir / "raw" / source.name
    if not link.exists():
        try:
            os.link(source, link)          # same volume: zero bytes copied
        except OSError:
            shutil.copy2(source, link)     # cross-volume fallback

    wcopy = cdir / "transcript" / "words.json"
    if not wcopy.exists():
        shutil.copy2(words, wcopy)

    segments = []
    for seg in clip["segments"]:
        s = dict(seg)
        s.setdefault("clip", source.name)
        segments.append(s)
    cuts = {"segments": segments}

    # Durable authored copy (macOS wipes /tmp) + the /tmp copy splice.sh reads.
    (cdir / "transcript" / "cuts.authored.json").write_text(
        json.dumps(cuts, indent=1) + "\n")
    work = Path("/tmp/video-editor") / name
    work.mkdir(parents=True, exist_ok=True)
    (work / "cuts.json").write_text(json.dumps(cuts, indent=1) + "\n")

    dur = sum(s["end"] - s["start"] for s in segments)
    print(f"  scaffolded clips/{name}  ({len(segments)} segment(s), {dur:.1f}s)")
    return cdir


def reframe(cdir, name):
    """Face-centered crop of the spliced 16:9 base to the 1080x1920 clean base."""
    base = cdir / "outputs" / f"{name}.mp4"
    if not base.exists():
        die(f"{name}: splice produced no {base}")
    w, h = probe_wh(base)
    if (w, h) == (1080, 1920):
        print(f"  {name}: already 1080x1920, no reframe needed")
        return

    vf = None
    rc = run(["uv", "run", FACE_FRAME, base])
    ff_json = cdir / "face-frame.json"
    if rc == 0 and ff_json.exists():
        data = json.loads(ff_json.read_text())
        vf = data.get("reframe", {}).get("ffmpeg")
    if vf is None:
        crop_w = round(h * 9 / 16 / 2) * 2
        crop_x = max(0, (w - crop_w) // 2 // 2 * 2)
        vf = f"crop={crop_w}:{h}:{crop_x}:0,scale=1080:1920"
        print(f"  {name}: no measurable face, using center crop")

    wide = cdir / "outputs" / f"{name}-169.mp4"
    shutil.move(base, wide)
    rc = run(["ffmpeg", "-y", "-v", "error", "-i", wide, "-vf", vf,
              *encoder_args(), "-c:a", "copy", "-movflags", "+faststart", base])
    if rc != 0:
        shutil.move(wide, base)   # restore the base so a re-run starts clean
        die(f"{name}: reframe ffmpeg failed")
    print(f"  {name}: reframed to 1080x1920 ({vf})")


def captions(cdir, name, clip):
    final = cdir / "outputs" / f"{name}.final.mp4"
    # sys.executable, never "python3": Windows has no real python3 name (only a fake
    # Store stub), and this script is already running under a working interpreter.
    cmd = [sys.executable, TIKTOK_BUILD, cdir,
           "--hook-text", clip.get("hook_text", ""), "--out", final]
    if clip.get("hook_end") is not None:
        cmd += ["--hook-end", str(clip["hook_end"])]
    if run(cmd) != 0:
        die(f"{name}: caption build failed")
    return final


def export_copy(final, name):
    dl = Path(os.environ.get("VE_EXPORT_DIR") or Path.home() / "Downloads")
    if dl.is_dir():
        shutil.copy2(final, dl / final.name)
        print(f"  {name}: export copy -> {dl / final.name}")
    else:
        print(f"  {name}: export dir {dl} missing, skipped copy")


def main():
    args = sys.argv[1:]
    if not args:
        die("usage: make-clips.py <parent_job_dir> [--build] [--only <name> ...]")
    parent = Path(args[0]).resolve()
    build = "--build" in args
    only = args[args.index("--only") + 1:] if "--only" in args else None

    plan_path = parent / "clips-plan.json"
    if not plan_path.exists():
        die(f"missing {plan_path} (run the clipper selection pass first)")
    plan = json.loads(plan_path.read_text())

    source = parent / plan["source"]
    if not source.exists():
        die(f"plan source not found: {source}")
    words = parent / "transcript" / "words.json"
    if not words.exists():
        die(f"missing {words} (transcribe the parent first)")

    clips = [c for c in plan["clips"] if only is None or c["name"] in only]
    if not clips:
        die("no clips matched")

    failed = []
    for clip in clips:
        name = clip["name"]
        print(f"\n=== {name} ===")
        cdir = scaffold(parent, clip, source, words)
        if not build:
            continue
        try:
            if run(["bash", SPLICE, cdir]) != 0:
                raise RuntimeError("splice failed (see output above)")
            reframe(cdir, name)
            final = captions(cdir, name, clip)
            export_copy(final, name)
            print(f"  ✓ {name}: {final}")
        except (RuntimeError, SystemExit) as e:
            print(f"  ✗ {name}: {e}")
            failed.append(name)

    if not build:
        print("\nScaffold done. Build with:  make-clips.py <parent> --build")
    elif failed:
        die(f"failed clips: {', '.join(failed)}")
    else:
        print(f"\nAll {len(clips)} clip(s) built.")


if __name__ == "__main__":
    main()
