#!/bin/bash
# ONE ffmpeg pass: base + 4 alpha overlays -> renders/final.mp4 (~5s).
# eof_action=pass on every overlay (the 1-in-4 dup-frame trap), windows from parts.json.
set -euo pipefail
cd "$(dirname "$0")"
BASE="../outputs/five-stage-client-process.mp4"
mkdir -p renders

ffmpeg -y -v error \
  -i "$BASE" \
  -itsoffset 0.8  -i renders/parts/g1.mov \
  -itsoffset 9.8  -i renders/parts/g2.mov \
  -itsoffset 17.6 -i renders/parts/g3.mov \
  -itsoffset 26.8 -i renders/parts/g4.mov \
  -filter_complex "\
[0:v][1:v]overlay=enable='between(t,0.8,9.0)':eof_action=pass[v1];\
[v1][2:v]overlay=enable='between(t,9.8,15.4)':eof_action=pass[v2];\
[v2][3:v]overlay=enable='between(t,17.6,24.4)':eof_action=pass[v3];\
[v3][4:v]overlay=enable='between(t,26.8,33.4)':eof_action=pass[vout]" \
  -map "[vout]" -map 0:a -c:v h264_videotoolbox -b:v 30M -c:a copy \
  renders/final.mp4

# Smoothness guardrail: duplicate-frame tally (YDIF=0). Clean ~0-3%; the overlay
# scheduler bug reads ~25%. Fail hard at >=8%.
DUPS=$(ffmpeg -i renders/final.mp4 -vf "signalstats,metadata=print:key=lavfi.signalstats.YDIF:file=-" -f null - 2>/dev/null \
  | grep -c 'YDIF=0.000000' || true)
TOTAL=$(ffmpeg -i renders/final.mp4 -vf "signalstats,metadata=print:key=lavfi.signalstats.YDIF:file=-" -f null - 2>/dev/null \
  | grep -c 'YDIF=' || true)
PCT=$(( TOTAL > 0 ? DUPS * 100 / TOTAL : 0 ))
echo "[assemble] dup frames: ${DUPS}/${TOTAL} (${PCT}%)"
if [ "$PCT" -ge 8 ]; then
  echo "[assemble] ✗ duplicate-frame ratio >= 8% — overlay scheduler stutter, do not ship" >&2
  exit 1
fi
echo "[assemble] renders/final.mp4 ready"
