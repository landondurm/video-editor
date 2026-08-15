#!/usr/bin/env bash
# normalize-sections.sh — measure every source recording in a job, gain each one to a
# common loudness target, limit true peaks, and verify nothing shifted in time.
#
#   usage: normalize-sections.sh <job_dir> [target_LUFS]     (default target: -16)
#          DRY=1 normalize-sections.sh <job_dir>             measure only, render nothing
#
# Writes normalized copies to <job_dir>/audio-normalized/. NEVER touches the raws.
# Swap them into Resolve afterwards with replace-clips.py — see README.md.
#
# Locks (full rationale in README.md):
#   · -c:v copy          video is stream-copied, so the picture stays bit-identical
#   · level=disabled     alimiter auto-level otherwise defeats the measured static gain
#   · latency=1          compensates the limiter's own lookahead so nothing moves in time
#   · 320k AAC           downstream-bitrate lock: never re-encode voice below 256k
#   · NEVER loudnorm     dynamic normalization pumps
#
# Bash 3.2 clean (stock macOS) and Linux clean — no mapfile, no associative arrays.
set -euo pipefail

JOB="${1:?usage: normalize-sections.sh <job_dir> [target_LUFS]}"
TARGET="${2:--16}"
OUT="$JOB/audio-normalized"
CEIL="0.891251"          # -1.0 dBFS

[ -d "$JOB" ] || { echo "no such job dir: $JOB" >&2; exit 1; }
mkdir -p "$OUT"

# every raw recording in the job: the top-level raw/ plus each section's raw/
SRCS=$(find "$JOB/raw" "$JOB/sections" -type f -name '*.mp4' -path '*/raw/*' 2>/dev/null | sort)
[ -n "$SRCS" ] || { echo "no raws found under $JOB" >&2; exit 1; }

measure() {   # $1=file -> "I LRA PEAK"
  ffmpeg -nostdin -hide_banner -i "$1" -af ebur128=peak=true -f null - 2>&1 \
    | sed -n '/Summary:/,$p' \
    | awk '/^ *I:/{i=$2} /^ *LRA:/{l=$2} /^ *Peak:/{p=$2} END{print i, l, p}'
}

probe() {     # $1=file -> "dur vframes aframes astart"
  d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$1")
  v=$(ffprobe -v error -select_streams v:0 -show_entries stream=nb_frames -of csv=p=0 "$1")
  a=$(ffprobe -v error -select_streams a:0 -show_entries stream=nb_frames -of csv=p=0 "$1")
  s=$(ffprobe -v error -select_streams a:0 -show_entries stream=start_time -of csv=p=0 "$1")
  echo "$d $v $a $s"
}

echo "target: ${TARGET} LUFS   ceiling: -1.0 dBFS   out: $OUT"
printf "\n%-26s %9s %7s %8s %7s %9s %8s  %s\n" \
  SECTION IN_LUFS LRA IN_PEAK GAIN OUT_LUFS OUT_PEAK CHECK
fail=0
echo "$SRCS" | while read -r src; do
  [ -n "$src" ] || continue
  name=$(basename "$src" .mp4)
  set -- $(measure "$src")
  I="$1"; L="$2"; P="$3"
  GAIN=$(awk -v t="$TARGET" -v i="$I" 'BEGIN{printf "%.1f", t - i}')

  if [ "${DRY:-0}" = "1" ]; then
    printf "%-26s %9s %7s %8s %+7s %9s %8s  %s\n" "$name" "$I" "$L" "$P" "$GAIN" - - "dry-run"
    continue
  fi

  dst="$OUT/$name.mp4"
  ffmpeg -nostdin -v error -y -i "$src" -c:v copy \
    -af "volume=${GAIN}dB,alimiter=limit=${CEIL}:level=disabled:latency=1" \
    -c:a aac -b:a 320k "$dst"

  # DRIFT GATE — duration, video frames, audio frames and audio start must all match.
  # An AAC re-encode can shift audio a frame via encoder priming; that would break sync
  # across every cut, and it is invisible until someone watches the whole video.
  if [ "$(probe "$src")" = "$(probe "$dst")" ]; then chk="OK"; else chk="*** DRIFT ***"; fail=1; fi
  set -- $(measure "$dst")
  printf "%-26s %9s %7s %8s %+7s %9s %8s  %s\n" "$name" "$I" "$L" "$P" "$GAIN" "$1" "$3" "$chk"
done

echo
if [ "${DRY:-0}" = "1" ]; then
  echo "dry run — nothing written. Re-run without DRY=1 to render."
else
  echo "Any *** DRIFT *** line above means DO NOT REPLACE that file — investigate first."
  echo "Next: replace-clips.py to swap them into the Resolve timeline."
fi
