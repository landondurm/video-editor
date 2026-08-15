#!/usr/bin/env bash
# check-setup.sh — verify the tools the VIDEO-EDITOR pipeline needs (raw → exported cut).
#
# Report-only: checks what's installed and prints the install command for anything
# missing. Installs NOTHING and touches nothing. Run it once before editing.
#
#   ./check-setup.sh
#
# Cross-platform: macOS, Windows (native — runs in Git Bash, the shell Claude Code uses on
# Windows; see SETUP.md "Windows"), or plain Linux. The Python side (WhisperX large-v3 + torch)
# is NOT installed here — the rough-cut skill builds its own isolated venv on first run
# (~3–5 GB, several minutes).
set -uo pipefail

# ── platform detection ──────────────────────────────────────────────────────
UNAME="$(uname -s 2>/dev/null || echo unknown)"
case "$UNAME" in
  Darwin)               OS=mac;     OSLABEL="macOS" ;;
  Linux)                OS=linux;   OSLABEL="Linux" ;;
  MINGW*|MSYS*|CYGWIN*) OS=windows; OSLABEL="Windows (Git Bash)" ;;
  *)                    OS=other;   OSLABEL="$UNAME" ;;
esac
IS_WSL=0
if [ "$OS" = linux ] && grep -qi microsoft /proc/version 2>/dev/null; then
  IS_WSL=1; OSLABEL="Windows · WSL2 (works, but native Windows is the supported path — see SETUP.md)"
fi

# install-command hint for a given tool, per platform (bash 3.2-safe: case, no assoc arrays)
hint() {  # hint <tool-key>
  case "$OS:$1" in
    mac:ffmpeg)    echo "brew install ffmpeg" ;;
    mac:uv)        echo "brew install uv" ;;
    mac:node)      echo "brew install node" ;;
    mac:python3)   echo "brew install python" ;;
    mac:pillow)    echo "brew install pillow" ;;
    linux:ffmpeg)  echo "sudo apt install -y ffmpeg" ;;
    linux:uv)      echo "curl -LsSf https://astral.sh/uv/install.sh | sh" ;;
    linux:node)    echo "curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt install -y nodejs" ;;
    linux:python3) echo "sudo apt install -y python3 python3-pip" ;;
    linux:pillow)  echo "sudo apt install -y python3-pil" ;;
    windows:ffmpeg)  echo "winget install Gyan.FFmpeg          (then open a NEW terminal)" ;;
    windows:uv)      echo "winget install astral-sh.uv         (then open a NEW terminal)" ;;
    windows:node)    echo "winget install OpenJS.NodeJS.LTS    (then open a NEW terminal)" ;;
    windows:python3) echo "winget install Python.Python.3.12   (then open a NEW terminal)" ;;
    windows:pillow)  echo "python -m pip install pillow" ;;
    *:higgsfield)  echo "curl -fsSL https://raw.githubusercontent.com/higgsfield-ai/cli/main/install.sh | sh" ;;
    *)             echo "install $1" ;;
  esac
}

if [ -t 1 ]; then
  G=$(tput setaf 2); R=$(tput setaf 1); Y=$(tput setaf 3); D=$(tput setaf 8); B=$(tput bold); N=$(tput sgr0)
else
  G=; R=; Y=; D=; B=; N=
fi

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
missing=0

check() {  # check <cmd> <label> <tool-key> <used-by>
  local cmd="$1" label="$2" key="$3" used="$4"
  if command -v "$cmd" >/dev/null 2>&1; then
    printf "  ${G}✓${N} %-12s ${D}%s${N}\n" "$label" "$used"
  else
    printf "  ${R}✗${N} %-12s ${Y}%s${N}  ${D}(needed by %s)${N}\n" "$label" "$(hint "$key")" "$used"
    missing=$((missing + 1))
  fi
}

note() { printf "  ${Y}!${N} %-12s ${D}%s${N}\n" "$1" "$2"; }
ok()   { printf "  ${G}✓${N} %-12s ${D}%s${N}\n" "$1" "$2"; }

printf "\n${B}video-editor — prerequisites${N}  ${D}(%s)${N}\n\n" "$OSLABEL"

if [ "$OS" = other ]; then
  printf "  ${R}Unsupported shell/OS detected ($UNAME).${N}\n"
  printf "  ${Y}On Windows, run this from Git Bash (installed with Git for Windows), not PowerShell/cmd. See SETUP.md \"Windows\".${N}\n\n"
fi

# Package-manager preamble
if [ "$OS" = mac ] && ! command -v brew >/dev/null 2>&1; then
  printf "  ${Y}Homebrew not found${N} — most installs below use it. Install it first:\n"
  printf "    ${B}/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"${N}\n\n"
elif [ "$OS" = linux ]; then
  printf "  ${D}Installs below use apt. Refresh the index once first:${N}  ${B}sudo apt update${N}\n\n"
elif [ "$OS" = windows ]; then
  printf "  ${D}Installs below use winget (built into Windows 11 / App Installer). After each install,${N}\n"
  printf "  ${D}open a NEW terminal (and restart Claude Code once) so PATH picks the tool up.${N}\n\n"
fi

printf "${B}Core${N} (the raw → exported pipeline — every job needs these):\n"
check ffmpeg  ffmpeg  ffmpeg  "every audio/video pass: rough-cut, captions, music"
check ffprobe ffprobe ffmpeg  "duration/format probing"
check uv      uv      uv      "rough-cut — builds the WhisperX transcribe venv (also gives uvx)"
check node    node    node    "graphics render engine — npx hyperframes"
check npx     npx     node    "runs the hyperframes CLI"

# Python — probed by RUNNING it, not command -v: Windows installs Python as `python`
# (no python3 name), and ships a fake `python3` Store stub that only opens the Microsoft
# Store. Every pipeline script uses this same python3-then-python probe.
PYBIN=""
if python3 -c '' >/dev/null 2>&1; then PYBIN=python3
elif python -c '' >/dev/null 2>&1; then PYBIN=python; fi
if [ -n "$PYBIN" ]; then
  ok "python" "TikTok/raw captions + thumbnail text overlays (runs as \`$PYBIN\`)"
else
  printf "  ${R}✗${N} %-12s ${Y}%s${N}  ${D}(needed by %s)${N}\n" "python" "$(hint python3)" "TikTok/raw captions + thumbnail text overlays"
  missing=$((missing + 1))
fi

# node version (HyperFrames CLI wants a modern node; 22+)
if command -v node >/dev/null 2>&1; then
  NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
  if [ "${NODE_MAJOR:-0}" -lt 22 ]; then
    if [ "$OS" = mac ]; then up="brew upgrade node"; else up="$(hint node)"; fi
    note "node version" "found v$(node -v | tr -d v) — HyperFrames wants node ≥ 22 ($up)"
    missing=$((missing + 1))
  fi
fi

# Pillow (PIL) — the TikTok/raw caption + thumbnail PNG overlays. ffmpeg here has no drawtext/libass, so
# PIL is mandatory for those. (Explainer captions render through HyperFrames, not PIL.)
if [ -n "$PYBIN" ]; then
  if "$PYBIN" -c "import PIL" >/dev/null 2>&1; then
    ok "Pillow (PIL)" "TikTok/raw captions + thumbnail text overlays"
  else
    note "Pillow (PIL)" "missing — run: $(hint pillow)   (TikTok/raw captions + thumbnail overlays)"
    missing=$((missing + 1))
  fi
fi

# Hardware is informational only: the pipeline auto-picks the fastest reliable
# path per machine (rough-cut's transcribe.sh does the same probe at run time,
# with a full runtime fallback to CPU), so nothing here can count as "missing".
printf "\n${B}Hardware${N}  ${D}(auto-detected; transcription picks the fastest reliable path)${N}:\n"
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
  GPUNAME="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1)"
  ok "GPU" "NVIDIA${GPUNAME:+ · $GPUNAME}: WhisperX runs CUDA float16 (automatic, with CPU fallback)"
elif [ "$OS" = mac ]; then
  ok "GPU" "Apple Silicon: WhisperX runs CPU int8 (the reliable path; GPU torch is still flaky here)"
else
  ok "GPU" "no NVIDIA GPU: WhisperX runs CPU int8 (works everywhere, just slower)"
fi

printf "\n${B}Fonts${N}  ${D}(all bundled — nothing to install)${N}:\n"
if [ -f "$REPO/assets/fonts/Coolvetica-Rg.otf" ]; then
  ok "Coolvetica" "bundled in assets/fonts/ — explainer captions"
else
  note "Coolvetica" "missing from assets/fonts/ — explainer captions need Coolvetica-Rg.otf"
  missing=$((missing + 1))
fi
if [ -f "$REPO/assets/fonts/Inter-Regular.otf" ]; then
  ok "Inter" "bundled in assets/fonts/ — signature-style + liquid-glass + TikTok/raw graphics"
else
  note "Inter" "missing from assets/fonts/ — graphics display font. Re-download from https://rsms.me/inter"
  missing=$((missing + 1))
fi
if [ "$OS" = mac ]; then
  if ls /Library/Fonts/SF-Pro-Display-*.otf >/dev/null 2>&1 || [ -f /System/Library/Fonts/SFNS.ttf ]; then
    ok "SF Pro (system)" "installed — optional; bundled Inter is the default look"
  else
    note "SF Pro (system)" "not installed (optional) — bundled Inter is the default. Prefer SF Pro? https://developer.apple.com/fonts"
  fi
else
  ok "display font" "bundled Inter is the default on $OSLABEL (SF Pro is macOS-only, not needed)"
fi

printf "\n${B}Optional${N} (only if you use the feature):\n"
# Optional items report with ok/note, NEVER with check(): check() increments the CORE
# missing counter, which made an all-green install report "1 core item(s) missing" and
# exit non-zero (breaking setup.sh's verify step) over a thumbnails-only tool.
if command -v higgsfield >/dev/null 2>&1; then
  ok "higgsfield" "thumbnail-generator (long-form thumbnails)"
else
  note "higgsfield" "not installed; only needed for long-form thumbnails: $(hint higgsfield)"
fi
# Premiere finishing lane: the pinned vendored engine, installed by ./setup-premiere.sh.
# NEVER suggest the retired premiere-pro-mcp npm package (knockoff republish, broken CEP shim).
if [ -d "$(dirname "$0")/vendor/premiere-mcp" ]; then
  ok "premiere-mcp" "vendored engine present (Premiere finishing lane)"
else
  note "premiere-mcp" "not installed — the Premiere finishing lane needs it. Run: ./setup-premiere.sh"
fi
# Resolve finishing lane: the pinned vendored MCP, installed by ./setup-resolve.sh.
if [ -d "$(dirname "$0")/vendor/davinci-resolve-mcp" ]; then
  ok "davinci-resolve-mcp" "vendored engine present (Resolve finishing lane)"
else
  note "davinci-resolve-mcp" "not installed — the Resolve finishing lane needs it. Run: ./setup-resolve.sh"
fi
# transcript-QA wordlist (the suspect scan in rough-cut). macOS ships one; minimal Ubuntu doesn't;
# Windows has no system wordlist at all (the scan just skips — it's advisory).
if [ -f /usr/share/dict/words ] || [ -f /usr/share/dict/web2 ] || [ -f /usr/share/dict/american-english ]; then
  ok "wordlist" "present — rough-cut transcript-QA suspect scan"
elif [ "$OS" = linux ]; then
  note "wordlist" "absent — transcript-QA scan will skip. Enable it: sudo apt install -y wamerican"
elif [ "$OS" = windows ]; then
  ok "wordlist" "none on Windows — transcript-QA suspect scan skips (advisory only, everything else works)"
fi

printf "\n"
if [ "$missing" -eq 0 ]; then
  printf "${G}${B}Core tools present.${N} You're ready to edit.\n"
else
  printf "${R}${B}%d core item(s) missing.${N} Run the commands shown above, then re-run this script.\n" "$missing"
fi

printf "\n${B}One-time, on first use${N} (not installed here — happens automatically / once):\n"
printf "  ${D}•${N} ${B}WhisperX transcription${N} — rough-cut builds its venv + downloads large-v3 (~3–5 GB) on the first edit. Needs network + a few minutes. One time.\n"
printf "  ${D}•${N} ${B}Render engine bootstrap${N} — run once from the project root:  ${B}npx hyperframes@0.7.92 doctor${N}  (downloads the headless browser the graphics renderer uses; pinned to the version the locked presets were built against).\n"
if [ "$IS_WSL" -eq 1 ]; then
  printf "      ${D}On WSL, if the renderer reports a missing shared library, install the headless-Chrome deps it names, e.g.:${N}\n"
  printf "      ${B}sudo apt install -y libnss3 libatk-bridge2.0-0 libgtk-3-0 libgbm1 libasound2t64${N}\n"
fi
printf "  ${D}•${N} ${B}Brand + face refs${N} (optional): the editor works out of the box with the bundled neutral look. Whenever you want captions/graphics/thumbnails to carry YOUR brand, fill in ${B}brand-kit.md${N} and drop photos into ${B}assets/face-refs/${N} (see SETUP.md).\n\n"

[ "$missing" -eq 0 ]
