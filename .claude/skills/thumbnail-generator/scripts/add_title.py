#!/usr/bin/env python3
"""
add_title.py — overlay a tilted block-style title on a thumbnail,
matching 'The Codex Era' aesthetic from the reference.

Usage:
    add_title.py <base.png> <out.png> [--blocks JSON]

Block schema (list of dicts):
  text:       string to render
  bg:         hex "#FFD600" (yellow accent), "#FFFFFF" (white), etc.
  fg:         hex text color, default "#000000"
  rotation:   degrees, positive = ccw (left tilt)
  scale:      relative font height vs image height. Big blocks ~0.15, small accent ~0.10
  pad_x/pad_y: block padding around text, in font-height units (default 0.35 / 0.20)

Layout: blocks are placed in a horizontal row near the top of the image,
centered horizontally. Rotated blocks overlap the row by their visual lean.
"""
import argparse, json, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

HELVETICA = "/System/Library/Fonts/Helvetica.ttc"
HELVETICA_BOLD_INDEX = 1  # face 1 in the .ttc is Bold
_FALLBACK_FONT = Path(__file__).resolve().parents[4] / "assets" / "fonts" / "Inter-Black.otf"

def load_font(px: int) -> ImageFont.FreeTypeFont:
    try:
        return ImageFont.truetype(HELVETICA, size=px, index=HELVETICA_BOLD_INDEX)
    except OSError:
        return ImageFont.truetype(str(_FALLBACK_FONT), size=px)  # Helvetica.ttc absent → bundled Inter

def render_block(text: str, bg: str, fg: str, font_px: int,
                 pad_x_ratio: float, pad_y_ratio: float, rotation: float) -> Image.Image:
    font = load_font(font_px)
    # Measure
    tmp = Image.new("RGBA", (4, 4), (0, 0, 0, 0))
    d = ImageDraw.Draw(tmp)
    bbox = d.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    # Vertical bearing offset — top of bbox isn't at y=0 for some fonts
    tx_off, ty_off = -bbox[0], -bbox[1]
    pad_x = int(font_px * pad_x_ratio)
    pad_y = int(font_px * pad_y_ratio)
    w = tw + 2 * pad_x
    h = th + 2 * pad_y
    block = Image.new("RGBA", (w, h), bg)
    bd = ImageDraw.Draw(block)
    bd.text((pad_x + tx_off, pad_y + ty_off), text, font=font, fill=fg)
    if rotation:
        block = block.rotate(rotation, resample=Image.BICUBIC, expand=True)
    return block

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("base")
    ap.add_argument("out")
    ap.add_argument("--blocks", required=True, help="JSON list of block specs")
    ap.add_argument("--top-margin", type=float, default=0.04,
                    help="Row top edge as fraction of image height. Default 0.04 (4%%).")
    ap.add_argument("--gap", type=float, default=0.01,
                    help="Horizontal gap between blocks as fraction of image width.")
    args = ap.parse_args()

    base = Image.open(args.base).convert("RGBA")
    W, H = base.size
    specs = json.loads(args.blocks)

    rendered = []
    for s in specs:
        scale = float(s.get("scale", 0.15))
        font_px = int(H * scale)
        b = render_block(
            text=s["text"],
            bg=s.get("bg", "#FFFFFF"),
            fg=s.get("fg", "#000000"),
            font_px=font_px,
            pad_x_ratio=float(s.get("pad_x", 0.35)),
            pad_y_ratio=float(s.get("pad_y", 0.20)),
            rotation=float(s.get("rotation", 0)),
        )
        rendered.append((b, s))

    # Horizontal layout: total width = sum of block widths + gaps
    gap_px = int(W * args.gap)
    total_w = sum(b.size[0] for b, _ in rendered) + gap_px * (len(rendered) - 1)
    x = (W - total_w) // 2
    y_anchor = int(H * args.top_margin)

    # Find the tallest non-rotated block height as row baseline
    base_heights = [b.size[1] for b, s in rendered if not s.get("rotation")]
    row_h = max(base_heights) if base_heights else max(b.size[1] for b, _ in rendered)
    row_center_y = y_anchor + row_h // 2

    for b, s in rendered:
        bw, bh = b.size
        # Vertically center each block on the row baseline center
        py = row_center_y - bh // 2
        # Optional per-block dx/dy nudges (fraction of image dim)
        dx = int(W * float(s.get("offset_x", 0)))
        dy = int(H * float(s.get("offset_y", 0)))
        base.alpha_composite(b, (x + dx, py + dy))
        x += bw + gap_px

    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    base.convert("RGB").save(args.out, "PNG")
    sys.stderr.write(f"[title] wrote {args.out}\n")

if __name__ == "__main__":
    main()
