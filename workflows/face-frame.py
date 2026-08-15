# /// script
# requires-python = ">=3.10"
# dependencies = ["opencv-python-headless"]
# ///
"""
face-frame.py — compute the explainer bottom-box face crop. Measured, not guessed.

LOCKED framing standard (Preset A talking-head explainer, graphics top / face
bottom): the median hair top sits 50px below the y960 seam. First pass must
get this right with zero hand-tuning.

How: sample ~12 frames of the base cut, detect the face (OpenCV YuNet, model
vendored in assets/models/), then find the true hair top with median-background
subtraction (the head moves, the room doesn't — robust against dark hair on a
dark background). Median across frames rides out take-to-take drift.

Usage (top of Graphics, before building anything):
  uv run workflows/face-frame.py projects/<job>/outputs/<job>.mp4
      → prints the #head object-position line, writes projects/<job>/face-frame.json
  uv run workflows/face-frame.py --verify <draft-render.mp4>
      → re-measures the composite; must PASS before review (exit 1 on fail)
  add --annotate out.png to either for an eyeball frame

Fallback when hair can't be measured (hood, hat, detection failure): face-box
center → y1385 (equivalent framing, derived from the same approved reference).
"""
import argparse, json, os, statistics, subprocess, sys, tempfile
# Windows consoles/pipes default to cp1252, which can't encode the ✓/✗/⚠/→ glyphs in this
# script's status lines: a cosmetic print must never kill a pipeline step (it did once,
# 2026-08-13, mid-splice on a real Windows job). Force UTF-8; no-op on macOS/Linux.
for _s in (sys.stdout, sys.stderr):
    try:
        if (getattr(_s, "encoding", "") or "").lower().replace("-", "") != "utf8":
            _s.reconfigure(encoding="utf-8")
    except AttributeError:
        pass

FRAME_W, FRAME_H = 1080, 1920
SEAM_Y = 960                  # graphics/face split
BOX_H = FRAME_H - SEAM_Y      # bottom box height (960)
HAIR_GAP = 50                 # LOCKED: hair top sits this far below the seam
FACE_CY_FALLBACK = 1385       # face-box center target if hair is unmeasurable
VERIFY_TOL = 40               # px tolerance in verify mode
SAMPLES = 12
SPREAD_WARN = 150             # px of face drift across takes worth flagging

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL = os.path.join(REPO, "assets", "models", "face_detection_yunet_2023mar.onnx")


def probe(video):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height,duration", "-of", "csv=p=0", video],
        capture_output=True, text=True, check=True).stdout
    # iPhone footage carries stream side data that the csv writer emits as extra
    # elements/rows (trailing comma or an extra line): keep the first three real tokens.
    out = [t for t in out.strip().splitlines()[0].split(",") if t.strip()]
    return int(out[0]), int(out[1]), float(out[2])


def sample_frames(video, dur, n=SAMPLES):
    import cv2
    tmp = tempfile.mkdtemp()
    imgs = []
    for i in range(n):
        t = dur * (i + 0.5) / n
        f = os.path.join(tmp, f"f{i}.png")
        subprocess.run(["ffmpeg", "-v", "error", "-ss", str(t), "-i", video,
                        "-frames:v", "1", "-y", f], capture_output=True)
        img = cv2.imread(f)
        if img is not None:
            imgs.append(img)
    return imgs


def detect_faces(imgs, w, h):
    import cv2
    det = cv2.FaceDetectorYN_create(MODEL, "", (w, h), score_threshold=0.6)
    boxes = []
    for img in imgs:
        _, dets = det.detect(img)
        if dets is None or len(dets) == 0:
            continue
        x, y, bw, bh = max(((d[0], d[1], d[2], d[3]) for d in dets),
                           key=lambda d: d[2] * d[3])
        boxes.append((float(x), float(y), float(bw), float(bh)))
    return boxes


def median_box(boxes):
    cx = statistics.median(x + w / 2 for x, y, w, h in boxes)
    cy = statistics.median(y + h / 2 for x, y, w, h in boxes)
    fw = statistics.median(w for x, y, w, h in boxes)
    fh = statistics.median(h for x, y, w, h in boxes)
    top = statistics.median(y for x, y, w, h in boxes)
    return cx, cy, fw, fh, top


def hair_tops(imgs, face_cx, face_top, y_floor=0):
    """Topmost moving-person row per frame via median-background subtraction."""
    import cv2, numpy as np
    stack = np.stack([i.astype(np.float32) for i in imgs])
    plate = np.median(stack, axis=0)
    x0 = max(0, int(face_cx - 300))
    x1 = min(imgs[0].shape[1], int(face_cx + 300))
    y0 = max(y_floor, int(face_top - 350))
    y1 = int(face_top)
    tops = []
    for img in imgs:
        diff = np.abs(img.astype(np.float32) - plate).mean(axis=2)
        mask = (diff > 14).astype(np.uint8)
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
        band = mask[y0:y1, x0:x1]
        rows = np.where(band.sum(axis=1) > 25)[0]
        if len(rows):
            tops.append(y0 + int(rows[0]))
    return tops


def measure(video, annotate=None):
    w, h, dur = probe(video)
    print(f"source: {w}x{h}  {dur:.1f}s")
    imgs = sample_frames(video, dur)
    boxes = detect_faces(imgs, w, h)
    if len(boxes) < len(imgs) / 2:
        print(f"✗ face detected in only {len(boxes)}/{len(imgs)} frames — "
              f"not writing a crop. Eyeball the framing manually.")
        sys.exit(1)
    cx, cy, fw, fh, ftop = median_box(boxes)
    spread = (max(y + h_ / 2 for x, y, w_, h_ in boxes)
              - min(y + h_ / 2 for x, y, w_, h_ in boxes))
    print(f"face: center=({cx:.0f},{cy:.0f})  box={fw:.0f}x{fh:.0f}  "
          f"drift across takes: {spread:.0f}px")
    if spread > SPREAD_WARN:
        print(f"⚠ framing varies {spread:.0f}px across takes (> {SPREAD_WARN}) — "
              f"median crop may not fit every take; review the draft closely.")

    result = {"video": os.path.abspath(video), "source": {"w": w, "h": h},
              "face": {"cx": round(cx), "cy": round(cy), "w": round(fw),
                       "h": round(fh), "spread_y": round(spread),
                       "frames": len(boxes)}}

    # horizontal: if the source isn't 9:16 yet, the reframe crop centers the face
    if (w, h) != (FRAME_W, FRAME_H):
        crop_w = round(h * 9 / 16 / 2) * 2
        crop_x = max(0, min(w - crop_w, round(cx - crop_w / 2)))
        result["reframe"] = {"crop_w": crop_w, "crop_h": h, "crop_x": crop_x,
                             "ffmpeg": f"crop={crop_w}:{h}:{crop_x}:0,scale={FRAME_W}:{FRAME_H}"}
        print(f"reframe 9:16 first: ffmpeg -vf \"{result['reframe']['ffmpeg']}\"")
        s = FRAME_W / crop_w
        cy, fh, ftop, cx = cy * s, fh * s, ftop * s, FRAME_W / 2

    # vertical anchor: hair top 50px below the seam
    tops = hair_tops(imgs, cx, ftop)
    if len(tops) >= len(imgs) / 2:
        hair = statistics.median(tops)
        result["hair_top"] = round(hair)
        win_top = hair - HAIR_GAP
        anchor = f"hair top y{hair:.0f} → {HAIR_GAP}px below seam"
    else:
        print("⚠ hair top unmeasurable — falling back to face-center anchor")
        win_top = cy - (FACE_CY_FALLBACK - SEAM_Y)
        anchor = f"face center y{cy:.0f} → frame y{FACE_CY_FALLBACK}"

    p = win_top / (FRAME_H - BOX_H)
    clamped = min(1.0, max(0.0, p))
    if clamped != p:
        print(f"⚠ ideal crop clamps at frame edge ({p:.1%} → {clamped:.1%}) — "
              f"face sits {abs(p - clamped) * (FRAME_H - BOX_H):.0f}px off target.")
    result["object_position_y"] = round(clamped * 100, 1)
    result["anchor"] = anchor
    print(f"anchor: {anchor}")
    print(f"→ #head {{ object-fit:cover; object-position:50% {result['object_position_y']}%; }}")

    vdir = os.path.dirname(os.path.abspath(video))
    if os.path.basename(vdir) == "outputs":
        out = os.path.join(os.path.dirname(vdir), "face-frame.json")
        with open(out, "w") as fp:
            json.dump(result, fp, indent=2)
        print(f"wrote {out}")

    if annotate:
        annotate_frame(imgs[len(imgs) // 2], result, annotate)
    return result


def annotate_frame(img, result, out):
    import cv2
    f = result["face"]
    x, y = f["cx"] - f["w"] // 2, f["cy"] - f["h"] // 2
    cv2.rectangle(img, (x, y), (x + f["w"], y + f["h"]), (0, 0, 255), 6)
    if "hair_top" in result:
        cv2.line(img, (0, result["hair_top"]), (img.shape[1], result["hair_top"]),
                 (0, 255, 255), 3)
    cv2.imwrite(out, img)
    print(f"annotated frame → {out}")


def verify(render, annotate=None):
    w, h, dur = probe(render)
    if (w, h) != (FRAME_W, FRAME_H):
        print(f"✗ render is {w}x{h}, expected {FRAME_W}x{FRAME_H}")
        sys.exit(1)
    imgs = sample_frames(render, dur)
    boxes = detect_faces(imgs, w, h)
    if not boxes:
        print("✗ no face detected in the render")
        sys.exit(1)
    cx, cy, fw, fh, ftop = median_box(boxes)
    tops = hair_tops(imgs, cx, ftop, y_floor=SEAM_Y + 4)  # ignore graphics motion above the seam
    if len(tops) >= len(imgs) / 2:
        hair = statistics.median(tops)
        target = SEAM_Y + HAIR_GAP
        off = hair - target
        label = f"hair top y{hair:.0f}  target y{target}"
    else:
        off = cy - FACE_CY_FALLBACK
        label = f"hair unmeasurable; face center y{cy:.0f}  target y{FACE_CY_FALLBACK}"
    ok = abs(off) <= VERIFY_TOL
    print(f"{label}  offset {off:+.0f}px  (tolerance ±{VERIFY_TOL})")
    print("✓ PASS — face framed on the locked standard" if ok
          else "✗ FAIL — face off the locked standard; re-run measure and rebuild")
    if annotate:
        import cv2
        img = imgs[len(imgs) // 2]
        cv2.line(img, (0, SEAM_Y), (w, SEAM_Y), (255, 0, 0), 4)
        cv2.line(img, (0, SEAM_Y + HAIR_GAP), (w, SEAM_Y + HAIR_GAP), (0, 255, 255), 3)
        cv2.imwrite(annotate, img)
        print(f"annotated frame → {annotate}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("video", nargs="?")
    ap.add_argument("--verify", metavar="RENDER")
    ap.add_argument("--annotate", metavar="OUT_PNG")
    a = ap.parse_args()
    if a.verify:
        verify(a.verify, annotate=a.annotate)
    elif a.video:
        measure(a.video, annotate=a.annotate)
    else:
        ap.error("give a base cut to measure, or --verify RENDER")
