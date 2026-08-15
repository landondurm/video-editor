#!/usr/bin/env bash
# splice.sh — cuts + concatenates clips per cuts.json
# usage: splice.sh <job_dir>
# reads:  /tmp/video-editor/<job-name>/cuts.json
# writes: projects/<job-name>/outputs/<job-name>.mp4

set -euo pipefail

# Python launcher, probed by RUNNING it: macOS/Linux have `python3`; Windows installs it
# as `python` (and ships a fake `python3` Store stub that only opens the Microsoft Store,
# which `command -v` can't see through).
PY=python3; "$PY" -c '' 2>/dev/null || PY=python
# Windows pipes default python stdio to cp1252, which can't encode the ⚠/→/✓ glyphs the
# pipeline's status lines use; export-transcript.py died mid-splice on a real job
# (2026-08-13). UTF-8 mode fixes stdio AND default open() encoding; no-op on macOS/Linux.
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8

JOB_DIR="${1:?usage: splice.sh <job_dir>}"
JOB_DIR="$(cd "$JOB_DIR" && pwd)"
JOB_NAME="$(basename "$JOB_DIR")"
WORK="/tmp/video-editor/$JOB_NAME"
MEDIA_DIR="$JOB_DIR"
[ -d "$JOB_DIR/raw" ] && MEDIA_DIR="$JOB_DIR/raw"
OUT="$JOB_DIR/outputs"
CUTS="$WORK/cuts.json"
mkdir -p "$WORK" "$OUT"

[ -f "$CUTS" ] || { echo "missing $CUTS" >&2; exit 1; }

# BOUNDARY REFINE — measured onset/offset dial-in (refine-cuts.py). WhisperX word
# START timestamps run ~50-100 ms late vs the real acoustic attack, so cuts authored
# at word.start-minus-pad still land INSIDE the word and clip its onset (a real job
# shipped a sentence-opening word with its first 48 ms missing); word ENDS run
# early the same way and clip decays. The refiner measures each chosen word's
# acoustic edge on the raw audio (5 ms RMS envelope) and moves the cut just outside
# it — in = onset−40 ms, out = offset+50 ms — clamped inside the local gap so it can
# never cross an adjacent word. Cut CHOICE stays Claude's; this only dials the
# boundary of the word already chosen (unlike the parked snap_silence.py — the
# "don't auto-snap to silence" gotcha still stands). REFINE=0 skips the pass;
# "no_refine": true on a segment skips just that segment.
WORDS_SRC="$JOB_DIR/transcript/words.json"; [ -f "$WORDS_SRC" ] || WORDS_SRC="$WORK/words.json"
if [ "${REFINE:-1}" != "0" ] && [ -f "$WORDS_SRC" ]; then
  if "$PY" "$(dirname "$0")/refine-cuts.py" "$MEDIA_DIR" "$WORDS_SRC" "$CUTS" "$WORK/cuts.refined.json"; then
    CUTS="$WORK/cuts.refined.json"
  else
    echo "[splice] ⚠ refine-cuts failed — splicing authored cuts.json unrefined" >&2
  fi
fi

# cuts.json schema:
# { "segments": [ { "clip": "clip-01.mov", "start": 1.2, "end": 4.8 }, ... ] }

# SINGLE-PASS CLEAN SPLICE — cut + concat happen in ONE ffmpeg filtergraph, and the audio
# polish (static gain → hard limiter) is applied exactly ONCE to the assembled track, then
# encoded to AAC exactly ONCE. This is the "cut from raw, master once at the end" order:
#   • Audio rides through the cut LOSSLESS (PCM in the filtergraph) — NEVER encoded per-segment.
#     The old approach encoded each segment to AAC, copy-concatenated those AAC chunks (each join
#     splices in ~1024+ samples of AAC encoder priming = a tiny CLICK at every cut), then encoded
#     AAC a 2nd time. Two lossy generations + a click per boundary on pristine PCM source audio.
#     Processing per-segment before assembly is the bug; processing once after assembly is the fix.
#   • A/V stay LOCKED by construction: video and audio are trimmed from the SAME in/out points in
#     the same graph and concatenated together — no independent rebuild that could drift.
#   • trim/setpts rebases the first frame to pts 0 (no empty edit / QuickTime black-flash), verified.
#
# Audio chain — STATIC gain + hard limiter (your Premiere move). NOT loudnorm: single-pass
#   loudnorm runs DYNAMIC (rides gain over time) and PUMPS. This is static + transparent: constant
#   +AMPLIFY_DB gain, peaks brickwalled at −6 dBFS, zero time-varying leveling. Raw record level is
#   ~−30 dB mean, which is what the gain is calibrated against. `level=disabled` is REQUIRED —
#   alimiter's auto-level defaults ON and re-normalizes loud (clips to +TP / crushes LRA);
#   limit=0.501 = −6 dBFS. AMPLIFY_DB (default 10) is the only loudness knob — +10 over raw lands
#   ~−21 dB mean with peaks just kissing the limiter; +15 limited transients too hard (your call).
"$PY" - "$MEDIA_DIR" "$CUTS" "$OUT/${JOB_NAME}.mp4" <<'PY'
import json, os, sys, subprocess, platform
media_dir, cuts_path, out_path = sys.argv[1:]
amp = os.environ.get("AMPLIFY_DB", "10")
with open(cuts_path) as f:
    segs = json.load(f)["segments"]
if not segs:
    raise SystemExit("cuts.json has no segments")

# One -i per unique clip; segments reference the right input index.
inputs, idx = [], {}
def input_index(clip):
    p = clip if os.path.isabs(clip) else os.path.join(media_dir, clip)
    if not os.path.exists(p):
        raise SystemExit(f"clip not found: {p}")
    if p not in idx:
        idx[p] = len(inputs); inputs.append(p)
    return idx[p]

# FRAME-GRID SNAP — the silence-gap fix. Video trim keeps whole frames while atrim cuts
# sample-exact, so un-snapped fractional cut times give every segment a video duration up
# to ±1 frame different from its audio duration. concat (v=1:a=1) then pads the shorter
# audio with DIGITAL ZEROS at each joint — measured +120 ms of inserted silence across one
# real 16-segment job: audible room-tone dropouts, extra click edges, and a progressive
# timeline stretch that desyncs the transcript/captions (the long-standing "render cut
# drift"). Snapping every boundary to the video frame grid makes video and audio durations
# IDENTICAL per segment: concat pads nothing, joints are pure (faded) butt-joins, and the
# output timeline equals the snapped cuts.json exactly.
def video_fps(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                          "-show_entries", "stream=r_frame_rate", "-of", "csv=p=0", path],
                         capture_output=True, text=True).stdout.strip()
    # iPhone .MOV footage carries stream side data, which the csv writer emits as extra
    # elements/rows: the value arrives as "30000/1001," (trailing comma) or with an
    # extra line, and a naive split("/") crashed on int("1001,") (2026-08-13, real job).
    # Keep only the first r_frame_rate token.
    tok = out.splitlines()[0].split(",")[0].strip()
    num, den = tok.split("/")
    return int(num), int(den)

parts, vlabels = [], []
# Joint treatment: J-CUT CROSSFADES, not fades-to-zero. A butt-splice clicks whenever a
# joint misses a zero crossing (measured 1-sample jumps up to ~80x local signal), but
# fading each edge down to silence trades the click for a ~20 ms ROOM-TONE HOLE at every
# joint — measured 8-13 dB ambience dips, still audible on headphones. The editorial fix:
# each segment's AUDIO runs XF seconds PAST its video cut (real continuing room tone from
# the raw) and equal-power crossfades into the next segment's head. Ambience never dips,
# a step discontinuity is impossible, and the chain arithmetic keeps timing exact:
# sum((dur_i + XF)) - (n-1)*XF == sum(dur_i) == video duration. The rising head gain also
# softens mouth/lip transients that sit a few ms after cut-ins (word starts run late vs
# acoustic onsets). This is part of the CUT (a DAW's auto-crossfade), NOT per-segment
# mastering — the gain->limiter->encode chain still runs exactly once on the whole track.
XF = 0.015          # default crossfade at each joint (min word padding ~31 ms, speech untouched)
EDGE = 0.005        # tiny fade from/to silence at the very start and end of the file
# Per-joint override: a segment may carry "xfade": <seconds> in cuts.json — the crossfade
# INTO that segment uses it instead of XF. Use when a cut-in clips an already-in-progress
# acoustic onset (word attacks often start tens of ms before the word timestamp): a longer
# ramp (e.g. 0.06) rebuilds a natural attack without moving the timeline.
def xf_into(i):
    return float(segs[i].get("xfade", XF)) if 0 < i < len(segs) else 0.0
max_shift = 0.0
n = len(segs)
for i, seg in enumerate(segs):
    a, b = float(seg["start"]), float(seg["end"])
    if b <= a:
        raise SystemExit(f"segment {i} has end <= start: {seg}")
    k = input_index(seg["clip"])
    fn, fd = video_fps(inputs[k])
    sa = round(a * fn / fd) * fd / fn
    sb = round(b * fn / fd) * fd / fn
    if sb <= sa:
        sb = sa + fd / fn
    max_shift = max(max_shift, abs(sa - a), abs(sb - b))
    seg["start"], seg["end"] = a, b = sa, sb
    parts.append(f"[{k}:v]trim={a}:{b},setpts=PTS-STARTPTS[v{i}]")
    ext = xf_into(i + 1) if i < n - 1 else 0.0   # tail extension feeds the next joint's crossfade
    edge = ""
    if i == 0:
        edge += f",afade=t=in:st=0:d={EDGE}"
    if i == n - 1:
        edge += f",afade=t=out:st={max(0.0, (b - a) - EDGE):.6f}:d={EDGE}"
    parts.append(f"[{k}:a]atrim={a}:{b + ext},asetpts=PTS-STARTPTS,aresample=48000:ochl=stereo{edge}[a{i}]")
    vlabels.append(f"[v{i}]")
parts.append("".join(vlabels) + f"concat=n={n}:v=1:a=0[vc]")
cur = "a0"
for i in range(1, n):
    nxt = "ac" if i == n - 1 else f"ax{i}"
    parts.append(f"[{cur}][a{i}]acrossfade=d={xf_into(i)}:c1=qsin:c2=qsin[{nxt}]")
    cur = nxt
if n == 1:
    parts.append("[a0]anull[ac]")
# latency=1: alimiter's 5 ms lookahead otherwise delays the audio 239 samples relative
# to video (measured) — compensation keeps A/V aligned by construction.
parts.append(f"[ac]volume={amp}dB,"
             "alimiter=level_in=1:level_out=1:limit=0.501:attack=5:release=50:level=disabled:latency=1[ao]")
fc = ";".join(parts)

# Video encoder, cross-platform: Apple's hardware encoder (videotoolbox) on macOS for speed;
# libx264 everywhere else (Windows/Linux) — always present in any ffmpeg build, no GPU needed.
# CRF 18 is visually ≈ the 8 Mbps videotoolbox target for a talking-head source.
if platform.system() == "Darwin":
    venc = ["-c:v", "h264_videotoolbox", "-b:v", "8M"]
else:
    venc = ["-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p"]

# NO-DUPLICATE-FRAMES GUARD. Two boundaries of one joint are measured independently
# (refine-cuts.py) and can cross, which lays the same source frames down twice — a
# 1-15 frame stutter that is invisible in every per-segment check (each segment is
# individually fine; only the PAIR is wrong) and that propagates into the flat render
# AND every EDL replay downstream. refine-cuts.py resolves joints pairwise now, but the
# EDL can also be hand-authored or come in with REFINE=0, so the invariant is asserted
# HERE, on the exact times that ship, after the snap. Fail loud: a stutter that reaches
# a timeline costs a rebuild, and on a hand-edited timeline there is no clean rebuild.
bad = []
for i in range(len(segs) - 1):
    x, y = segs[i], segs[i + 1]
    if os.path.basename(x["clip"]) != os.path.basename(y["clip"]):
        continue
    if x["start"] < y["start"] < x["end"]:
        xn, xd = video_fps(inputs[input_index(x["clip"])])
        bad.append((i, x["end"], y["start"], xn / xd))
if bad:
    lines = "\n".join(
        f"    seg{i} ends {e:.3f} but seg{i + 1} starts {s:.3f} "
        f"— {(e - s) * 1000:.0f} ms ({(e - s) * r:.1f} frames) played twice"
        for i, e, s, r in bad)
    raise SystemExit(
        f"[splice] ABORT — {len(bad)} joint(s) reuse the same source frames:\n{lines}\n"
        "    Overlapping segments duplicate footage at the cut and read as a stutter.\n"
        "    A continuous split (nothing removed between two segments) must share ONE\n"
        "    boundary time, not a padded end AND a padded start. Fix cuts.json, or let\n"
        "    refine-cuts.py resolve it (this ran with REFINE=0, or BOTH sides of the\n"
        "    joint are no_refine-pinned — joint resolution never moves a pinned boundary).")

# persist the SNAPPED cut times — the canonical EDL and the caption transcript must
# describe the timeline that actually shipped, not the pre-snap request.
snapped = os.path.join(os.path.dirname(cuts_path), "cuts.snapped.json")
with open(snapped, "w") as f:
    json.dump({"segments": segs}, f, indent=1)
print(f"[splice] frame-grid snap: max boundary shift {max_shift*1000:.1f} ms -> {snapped}",
      file=sys.stderr)

# RENDER=0 — EDL-only mode (Premiere-finish jobs): the timeline replay + canonical
# transcript need only the refined/snapped EDL, so skip the flat render entirely.
if os.environ.get("RENDER", "1") == "0":
    print("[splice] RENDER=0 — EDL-only: skipping the flat render", file=sys.stderr)
    sys.exit(0)

cmd = ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y"]
for p in inputs:
    cmd += ["-i", p]
cmd += ["-filter_complex", fc, "-map", "[vc]", "-map", "[ao]",
        *venc,
        "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2",
        "-video_track_timescale", "90000", "-movflags", "+faststart",
        out_path]
sys.exit(subprocess.run(cmd).returncode)
PY

if [ "${RENDER:-1}" != "0" ]; then
  echo "[splice] wrote $OUT/${JOB_NAME}.mp4" >&2
  ffprobe -hide_banner -loglevel error -show_entries format=duration -of default=nw=1:nk=1 "$OUT/${JOB_NAME}.mp4"
fi

# Persist the EDL durably alongside the canonical raw-timeline transcript.
# cuts.json otherwise lives only in /tmp (macOS clears it). The `premiere-pro`
# app-finish replay rebuilds the cut as separate timeline clips FROM this EDL, so it must
# survive past this session — same raw-timeline domain as transcript/words.json.
mkdir -p "$JOB_DIR/transcript"
# the frame-snapped EDL is the canonical one — it describes the timeline that shipped
EDL="$WORK/cuts.snapped.json"; [ -f "$EDL" ] || EDL="$CUTS"
cp "$EDL" "$JOB_DIR/transcript/cuts.json" \
  && echo "[splice] persisted EDL (frame-snapped) → $JOB_DIR/transcript/cuts.json" >&2

# Derive the cut-aligned caption transcript from the SAME large-v3 words — no re-transcription.
# The locked caption presets + graphics-plan consume this instead of running their own whisper.
WORDS="$JOB_DIR/transcript/words.json"; [ -f "$WORDS" ] || WORDS="$WORK/words.json"
if [ -f "$WORDS" ]; then
  "$PY" "$(dirname "$0")/export-transcript.py" "$WORDS" "$EDL" "$OUT/${JOB_NAME}.transcript.json" >&2 \
    && echo "[splice] derived caption transcript → $OUT/${JOB_NAME}.transcript.json" >&2
fi

# Audio self-check: joint declick verification + limiter-pressure report (advisory).
# Needs the rendered file — skipped in EDL-only mode.
if [ "${RENDER:-1}" != "0" ]; then
  "$PY" "$(dirname "$0")/audio-qa.py" "$JOB_DIR" >&2 || true
fi
