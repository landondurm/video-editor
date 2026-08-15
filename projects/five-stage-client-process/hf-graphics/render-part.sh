#!/bin/bash
# Render ONE overlay part to alpha ProRes .mov at 4K (comp space is 1920x1080, DPR 2x).
# Usage: ./render-part.sh g1
set -euo pipefail
cd "$(dirname "$0")"
ID="$1"
mkdir -p renders/parts
npx hyperframes@0.7.92 render . -c "compositions/${ID}.html" \
  -o "renders/parts/${ID}.mov" --format mov --fps 60000/1001 \
  -q standard --quiet
shasum -a 256 "compositions/${ID}.html" | cut -c1-12 > "renders/parts/${ID}.sha"
echo "[render-part] ${ID} done"
