#!/usr/bin/env bash
# prune.sh — reclaim space in projects without touching raw footage or finals.
#
# Deletes only regenerable / dead weight:
#   1. raw/archive/**            superseded source-clip versions you already replaced
#   2. work-*/ dirs              HyperFrames render scratch (frame dumps) left behind
#   3. node_modules/             reinstallable deps that leaked into a project
#   4. renders/*draft* + old vN  intermediate render iterations (keeps final/graphics + highest vN)
#   5. hf-graphics/renders/ + assets video files   the incremental-graphics render cache + footage
#                                slices (regenerable from the hf-graphics build source — see that
#                                folder's PROJECT.md; only pruned when a rebuild script exists)
#   6. premiere/ preview caches  Adobe Premiere Pro Video/Audio Previews dirs (Premiere rebuilds
#                                on demand; the .prproj, Auto-Save, .epr presets, masks are KEPT)
#
# ALWAYS KEPT: raw/*.mp4 (source), outputs/* (shipped finals), audio, assets, broll, thumbnails,
#   and the hf-graphics SOURCE (build.py, compositions/, *.sh, parts.json, PROJECT.md) — that's the progress.
#
# Default is a DRY RUN — it only reports. Add --apply to actually delete.
#   ./prune.sh            # show what would be freed
#   ./prune.sh --apply    # delete it

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/projects"
APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1

[[ -d "$ROOT" ]] || { echo "No projects dir at $ROOT"; exit 1; }

freed_kb=0
human() { du -sk "$1" 2>/dev/null | cut -f1; }

act() { # $1 = path to remove, $2 = reason
  local path="$1" reason="$2" kb
  kb=$(human "$path"); kb=${kb:-0}
  freed_kb=$(( freed_kb + kb ))
  printf '  %-7s %s\n' "$(echo "$kb" | awk '{printf "%.0fM", $1/1024}')" "${path#"$ROOT"/}  ($reason)"
  [[ $APPLY -eq 1 ]] && rm -rf "$path"
  return 0
}

echo "=== raw/archive (old clip versions) ==="
while IFS= read -r d; do act "$d" "superseded raw"; done \
  < <(find "$ROOT" -type d -path '*/raw/archive')

echo "=== HyperFrames work-* scratch ==="
while IFS= read -r d; do act "$d" "render scratch"; done \
  < <(find "$ROOT" -type d -name 'work-*' -prune)

echo "=== stray node_modules ==="
while IFS= read -r d; do act "$d" "reinstallable"; done \
  < <(find "$ROOT" -type d -name node_modules -prune)

echo "=== hf-graphics render cache + footage slices (regenerable from build.py) ==="
# The render cache (~hundreds of MB/job) and the cut footage slices rebuild from build.py:
#   ./setup-assets.sh && ./render-all.sh   (see each job's hf-graphics/PROJECT.md)
# The tiny SOURCE next to them (build.py, compositions/, scripts, parts.json, PROJECT.md) is NEVER touched.
while IFS= read -r d; do act "$d" "regenerable render cache"; done \
  < <(find "$ROOT" -type d -path '*/hf-graphics/renders')
# Video files under hf-graphics/assets/ are cut slices / staged footage the build source
# regenerates; only prune them when a rebuild entry point actually exists beside the assets dir
# (jobs vary: setup-assets.sh, assemble.sh, or build.py — see each PROJECT.md).
while IFS= read -r d; do
  src="$(dirname "$d")"
  [[ -f "$src/setup-assets.sh" || -f "$src/assemble.sh" || -f "$src/build.py" ]] || continue
  while IFS= read -r f; do act "$f" "regenerable footage slice"; done \
    < <(find "$d" -type f \( -name '*.mp4' -o -name '*.mov' \))
done < <(find "$ROOT" -type d -path '*/hf-graphics/assets')

echo "=== Premiere preview caches (regenerable by Premiere) ==="
while IFS= read -r d; do act "$d" "regenerable preview cache"; done \
  < <(find "$ROOT" -type d \( -name 'Adobe Premiere Pro Video Previews' -o -name 'Adobe Premiere Pro Audio Previews' \) -path '*/premiere/*' -prune)

echo "=== superseded renders (keep final/graphics + highest vN) ==="
while IFS= read -r rdir; do
  # Build the keep-set for this renders/ dir.
  # (while-read, not `mapfile` — mapfile is bash 4+, absent in macOS's default /bin/bash 3.2.)
  vids=()
  while IFS= read -r f; do vids+=("$f"); done < <(find "$rdir" -maxdepth 1 -type f -name '*.mp4')
  [[ ${#vids[@]} -le 1 ]] && continue          # never thin a dir with one video
  keep=()
  highest_v=""; highest_n=-1
  for f in "${vids[@]}"; do
    b=$(basename "$f")
    [[ "$b" == *final* || "$b" == *graphics* ]] && keep+=("$f")
    if [[ "$b" =~ -v([0-9]+)\.mp4$ ]]; then
      n=${BASH_REMATCH[1]}
      (( n > highest_n )) && { highest_n=$n; highest_v="$f"; }
    fi
  done
  [[ -n "$highest_v" ]] && keep+=("$highest_v")
  [[ ${#keep[@]} -eq 0 ]] && continue           # nothing recognized → leave dir alone
  for f in "${vids[@]}"; do
    skip=0; for k in "${keep[@]}"; do [[ "$f" == "$k" ]] && skip=1; done
    [[ $skip -eq 0 ]] && act "$f" "intermediate render"
  done
done < <(find "$ROOT" -type d -name renders -not -path '*/hf-graphics/*')
# (hf-graphics/renders dirs are excluded here: the cache pass above already counts and deletes
# them wholesale — scanning them again double-counted their mp4s in the dry-run total)

echo
total=$(echo "$freed_kb" | awk '{printf "%.2f GB", $1/1024/1024}')
if [[ $APPLY -eq 1 ]]; then
  echo "Freed $total."
else
  echo "DRY RUN — $total would be freed. Re-run with --apply to delete."
fi
