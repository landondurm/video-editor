#!/usr/bin/env bash
# setup.sh — ONE-COMMAND auto-setup. Detects your OS (macOS or Windows), installs
# everything the pipeline needs, bootstraps the render engine, verifies with
# check-setup.sh, then auto-detects your editing app (Premiere / Resolve / CapCut)
# and wires its lane. Safe to re-run any time: it skips what's already done and
# picks up where it left off (e.g. after a restart that refreshed PATH).
#
#   ./setup.sh
#
# macOS:   installs via Homebrew (if Homebrew itself is missing, you run its one-liner
#          once (it needs your password), then re-run this).
# Windows: run from Git Bash (the shell Claude Code uses on Windows); installs via
#          winget. Newly installed tools sometimes need a new terminal before they're
#          on PATH; this script pulls in their well-known install dirs so most setups
#          finish in ONE run; if anything is still pending it says exactly what to do.
# Linux:   tools are not auto-installed (./check-setup.sh prints the apt command
#          for each missing one), but everything else runs: verify, render-engine
#          bootstrap, Resolve lane detection (/opt/resolve), the done marker.
#
# Exit codes (Claude reads these; each prints exactly what to do):
#   0  done (output may carry a which-app question for the user)
#   1  something needs fixing before continuing; the output says what (Homebrew
#      missing on macOS, apt installs on Linux, a lane installer that failed)
#   2  restart needed: freshly installed tools aren't on this session's PATH yet.
#      Restart Claude Code, then re-run ./setup.sh; it finishes the rest.
#   3  an editing-app MCP lane was just wired into .mcp.json. Restart Claude Code
#      so it loads the new MCP, then verify the lane.
#
# This handles tools + the editing-app lane. Personalization (brand-kit.md) is
# OPTIONAL and separate: the editor works out of the box with the neutral bundled
# look; fill the brand kit in whenever (or never).
set -uo pipefail

# Resolve the PROJECT root. In the shipped package this script sits at the root;
# in the source repo it lives under packaging/overlay/. The marker file decides.
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$HERE/check-setup.sh" ]; then
  ROOT="$HERE"
elif [ -f "$HERE/../../check-setup.sh" ]; then
  ROOT="$(cd "$HERE/../.." && pwd)"
else
  printf 'ERROR: cannot locate the project root (check-setup.sh not found)\n' >&2
  exit 1
fi
cd "$ROOT"

HF_PIN="0.7.92"   # keep in sync with the pin in CLAUDE.md / SETUP.md

say()  { printf '%s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

UNAME="$(uname -s 2>/dev/null || echo unknown)"
case "$UNAME" in
  Darwin)               OS=mac ;;
  MINGW*|MSYS*|CYGWIN*) OS=windows ;;
  Linux)                OS=linux ;;
  *)                    OS=other ;;
esac

# Python probe: Windows installs Python as `python` (its `python3` is a fake
# Microsoft Store stub), so probe by RUNNING it, never by `command -v`.
pybin() {
  if python3 -c '' >/dev/null 2>&1; then echo python3
  elif python -c '' >/dev/null 2>&1; then echo python
  else echo ""; fi
}

# ─────────────────────────────────────────────────────────────────────────────
if [ "$OS" = other ]; then
  say "Unrecognized shell/OS ($UNAME)."
  say "On Windows, run this from Git Bash (installed with Git for Windows: winget install Git.Git)."
  exit 1
fi

case "$OS" in mac) OSLBL="macOS" ;; windows) OSLBL="Windows · Git Bash" ;; *) OSLBL="Linux" ;; esac
say "== video-editor auto-setup ($OSLBL) =="
say ""
if [ "$OS" = linux ]; then
  say "Linux: tools are not auto-installed here. If the verify below finds anything"
  say "missing, run the exact apt commands it prints, then re-run ./setup.sh."
  say ""
fi

PENDING=0   # set to 1 when something needs a restart/new terminal before it's usable

# ─── macOS: Homebrew installs ────────────────────────────────────────────────
if [ "$OS" = mac ]; then
  if ! have brew; then
    say "Homebrew is missing: it's the one step that needs YOUR password, so run this"
    say "in your terminal, then re-run ./setup.sh:"
    say ''
    say '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    exit 1
  fi
  for pkg in ffmpeg uv node python pillow; do
    case "$pkg" in
      ffmpeg) probe=ffmpeg ;;
      uv)     probe=uv ;;
      node)   probe=node ;;
      python) probe="" ;;   # probed via pybin below
      pillow) probe="" ;;   # probed via import below
    esac
    if [ "$pkg" = python ]; then
      [ -n "$(pybin)" ] && { say "  ✓ python present"; continue; }
    elif [ "$pkg" = pillow ]; then
      P="$(pybin)"; [ -n "$P" ] && "$P" -c "import PIL" >/dev/null 2>&1 && { say "  ✓ Pillow present"; continue; }
    elif have "$probe"; then
      say "  ✓ $pkg present"; continue
    fi
    say "  ▸ installing $pkg (brew)…"
    brew install "$pkg" || say "  ⚠ brew install $pkg failed; re-run ./setup.sh after fixing the error above"
  done
  # node too old? HyperFrames wants ≥22.
  if have node; then
    NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
    if [ "${NODE_MAJOR:-0}" -lt 22 ]; then
      say "  ▸ node v$(node -v | tr -d v) is too old; upgrading (brew)…"
      brew upgrade node || true
    fi
  fi
fi

# ─── Windows: winget installs + same-session PATH pickup ─────────────────────
if [ "$OS" = windows ]; then
  if ! have winget && ! have winget.exe; then
    say "winget is missing. Install 'App Installer' from the Microsoft Store, then re-run ./setup.sh."
    exit 1
  fi
  wg() {  # wg <winget-id>: quiet, license-accepted, exact-id install
    winget install --exact --id "$1" --accept-source-agreements --accept-package-agreements \
      --disable-interactivity >/dev/null 2>&1
    rc=$?
    # 0 = installed; winget uses distinct nonzero codes for "already installed"; treat
    # any rc as fine here and let the probe after PATH refresh be the real check.
    return 0
  }
  # Pull freshly installed tools into THIS session's PATH (winget updates the user PATH,
  # but only new terminals see that). Best-effort: well-known install dirs + winget's
  # portable-package folder. Makes one-run setup possible.
  refresh_path() {
    local d
    for d in "/c/Program Files/nodejs" \
             "$(cygpath -u "${LOCALAPPDATA:-}" 2>/dev/null)/Programs/Python/Python312" \
             "$(cygpath -u "${LOCALAPPDATA:-}" 2>/dev/null)/Programs/Python/Python312/Scripts" \
             "$(cygpath -u "${USERPROFILE:-}" 2>/dev/null)/.local/bin"; do
      [ -d "$d" ] && PATH="$d:$PATH"
    done
    # Gyan.FFmpeg is a winget "portable" package; its bin lands under WinGet/Packages
    for d in "$(cygpath -u "${LOCALAPPDATA:-}" 2>/dev/null)/Microsoft/WinGet/Packages"/Gyan.FFmpeg*/ffmpeg-*/bin; do
      [ -d "$d" ] && PATH="$d:$PATH"
    done
    export PATH
  }

  if have ffmpeg; then say "  ✓ ffmpeg present"; else say "  ▸ installing ffmpeg (winget)…";  wg Gyan.FFmpeg; fi
  if have node;   then say "  ✓ node present";   else say "  ▸ installing node (winget)…";    wg OpenJS.NodeJS.LTS; fi
  if have uv;     then say "  ✓ uv present";     else say "  ▸ installing uv (winget)…";      wg astral-sh.uv; fi
  if [ -n "$(pybin)" ]; then say "  ✓ python present"; else say "  ▸ installing python (winget)…"; wg Python.Python.3.12; fi

  refresh_path

  P="$(pybin)"
  if [ -n "$P" ]; then
    if "$P" -c "import PIL" >/dev/null 2>&1; then
      say "  ✓ Pillow present"
    else
      say "  ▸ installing Pillow (pip)…"
      "$P" -m pip install --quiet pillow || say "  ⚠ pip install pillow failed; re-run ./setup.sh"
    fi
  else
    say "  ⚠ python not visible yet in this session"
    PENDING=1
  fi
  for t in ffmpeg node uv; do
    have "$t" || { say "  ⚠ $t not visible yet in this session"; PENDING=1; }
  done
fi

# ─── Render-engine bootstrap (both OSes) ─────────────────────────────────────
say ""
if have npx; then
  if [ -f ".setup-hyperframes-ok" ]; then
    say "  ✓ render engine already bootstrapped (npx hyperframes@$HF_PIN)"
  else
    say "  ▸ bootstrapping the render engine (npx hyperframes@$HF_PIN doctor; one time, downloads its headless browser)…"
    if npx -y "hyperframes@$HF_PIN" doctor; then
      touch ".setup-hyperframes-ok"
    else
      say "  ⚠ hyperframes doctor reported a problem; read its output above, then re-run ./setup.sh"
    fi
  fi
else
  say "  ⚠ npx not available yet; the render-engine bootstrap runs on the next ./setup.sh"
  PENDING=1
fi

# ─── Restart gate (Windows PATH) ─────────────────────────────────────────────
say ""
if [ "$PENDING" -eq 1 ]; then
  say "== Almost done: some just-installed tools need a fresh environment =="
  say "One step for you: RESTART Claude Code (quit it fully, then reopen this folder)"
  say "and say \"continue setup\"; it re-runs ./setup.sh, which skips everything"
  say "already done and finishes the rest."
  exit 2
fi

say "== Verifying with check-setup.sh =="
./check-setup.sh || { say ""; say "Fix the items above, then re-run ./setup.sh"; exit 1; }

# Core tools verified: record it so the fresh-install reminder stops firing.
# (The editing-app lane below and the brand kit are optional layers on top.)
touch ".setup-complete"

# ─── Editing-app lane (auto-detected, optional) ──────────────────────────────
# If an editing app is installed, wire its lane now so rough cuts can land on a
# real timeline: exactly one app → wire it without asking; several → Claude asks
# the user which they edit in (a script can't); none → chat-only finish, done.
say ""
say "== Editing apps =="
DET_PREMIERE=0; DET_RESOLVE=0; DET_CAPCUT=0
if [ "$OS" = mac ]; then
  compgen -G "/Applications/Adobe Premiere Pro*" >/dev/null 2>&1 && DET_PREMIERE=1
  [ -d "/Applications/DaVinci Resolve/DaVinci Resolve.app" ] && DET_RESOLVE=1
  [ -d "/Applications/CapCut.app" ] && DET_CAPCUT=1
elif [ "$OS" = windows ]; then
  compgen -G "/c/Program Files/Adobe/Adobe Premiere Pro*" >/dev/null 2>&1 && DET_PREMIERE=1
  [ -e "/c/Program Files/Blackmagic Design/DaVinci Resolve/Resolve.exe" ] && DET_RESOLVE=1
  # (CapCut lane is macOS-only; its bridge drives the macOS accessibility tree.)
else
  # Linux: Resolve is the only app lane here (native install at /opt/resolve)
  [ -d /opt/resolve ] && DET_RESOLVE=1
fi
# Auto-wiring is gated on how many apps are INSTALLED, not how many are unwired:
# on a several-app machine the user picks one, and a later re-run must never
# silently wire the app they did not choose.
N_DET=$((DET_PREMIERE + DET_RESOLVE))

# Already wired? (engine built + entry present in .mcp.json)
WIRED_PREMIERE=0; WIRED_RESOLVE=0
[ -f "$ROOT/vendor/premiere-mcp/dist/index.js" ] && grep -qs '"premiere-pro"' "$ROOT/.mcp.json" && WIRED_PREMIERE=1
{ [ -e "$ROOT/vendor/davinci-resolve-mcp/venv/bin/python" ] || [ -e "$ROOT/vendor/davinci-resolve-mcp/venv/Scripts/python.exe" ]; } \
  && grep -qs '"davinci-resolve"' "$ROOT/.mcp.json" && WIRED_RESOLVE=1

# Find the lane installers (package root, or packaging/overlay/ in the source repo)
lane_script() { if [ -f "$ROOT/$1" ]; then echo "$ROOT/$1"; else echo "$HERE/$1"; fi; }

[ "$DET_CAPCUT" -eq 1 ] && say "  ✓ CapCut detected: nothing to install for it (its lane works out of the box)"
[ "$DET_PREMIERE" -eq 1 ] && [ "$WIRED_PREMIERE" -eq 1 ] && say "  ✓ Premiere Pro detected, lane already wired"
[ "$DET_RESOLVE"  -eq 1 ] && [ "$WIRED_RESOLVE"  -eq 1 ] && say "  ✓ DaVinci Resolve detected, lane already wired"

TO_WIRE=""
[ "$DET_PREMIERE" -eq 1 ] && [ "$WIRED_PREMIERE" -eq 0 ] && TO_WIRE="$TO_WIRE premiere"
[ "$DET_RESOLVE"  -eq 1 ] && [ "$WIRED_RESOLVE"  -eq 0 ] && TO_WIRE="$TO_WIRE resolve"
TO_WIRE="${TO_WIRE# }"

WIRED_NOW=""
case "$TO_WIRE" in
  "")
    if [ "$DET_PREMIERE" -eq 0 ] && [ "$DET_RESOLVE" -eq 0 ] && [ "$DET_CAPCUT" -eq 0 ]; then
      say "  · no editing app detected: the chat-only pipeline is the finish (nothing to set up)"
    fi
    ;;
  premiere)
    if [ "$N_DET" -eq 1 ]; then
      say "  ▸ Premiere Pro detected, wiring its lane (./setup-premiere.sh)…"
      if bash "$(lane_script setup-premiere.sh)"; then WIRED_NOW=premiere
      else say "  ⚠ setup-premiere.sh failed; read its output above"; WIRE_FAILED=premiere; fi
    else
      say "  · Premiere Pro is also installed but its lane isn't wired. That's fine;"
      say "    wire it any time with ./setup-premiere.sh (only if the user asks for it)."
    fi
    ;;
  resolve)
    if [ "$N_DET" -eq 1 ]; then
      say "  ▸ DaVinci Resolve detected, wiring its lane (./setup-resolve.sh)…"
      if bash "$(lane_script setup-resolve.sh)"; then WIRED_NOW=resolve
      else say "  ⚠ setup-resolve.sh failed; read its output above"; WIRE_FAILED=resolve; fi
    else
      say "  · DaVinci Resolve is also installed but its lane isn't wired. That's fine;"
      say "    wire it any time with ./setup-resolve.sh (only if the user asks for it)."
    fi
    ;;
  *)
    ASK_APP=1
    say "  ? MULTIPLE editing apps detected:$(printf ' %s' $TO_WIRE)"
    say "    ACTION FOR CLAUDE: ask the user in ONE line which app they edit in, then run"
    say "    ./setup-premiere.sh or ./setup-resolve.sh for their pick (each ends with a"
    say "    clear restart-Claude-Code step)."
    ;;
esac

# ─── Done ────────────────────────────────────────────────────────────────────
say ""
if [ -n "${WIRE_FAILED:-}" ]; then
  say "== Tools done, but the $WIRE_FAILED lane FAILED to wire =="
  say "ACTION FOR CLAUDE: read the installer error above, fix it, then re-run"
  say "./setup.sh (tools stay installed; the re-run skips them and retries the lane)."
  exit 1
fi
if [ -n "$WIRED_NOW" ]; then
  say "== Tools done + $WIRED_NOW lane wired =="
  say "One step for you: RESTART Claude Code (quit it fully, then reopen this folder)"
  say "so it loads the new MCP, and say \"continue setup\"; Claude then verifies the"
  say "$WIRED_NOW lane with you."
  say ""
  say "Optional, whenever you like: personalize the look/voice via brand-kit.md"
  say "(tell Claude \"apply my brand kit\"). The editor already works without it."
  exit 3
fi

if [ "${ASK_APP:-0}" -eq 1 ]; then
  say "== Tools done; one question left (the app pick above, Claude asks it) =="
else
  say "== Setup done =="
  say "Drop a raw clip and tell Claude to edit it. First edit also downloads the"
  say "WhisperX speech model (~3-5 GB, one time)."
fi
say "Optional, whenever you like: personalize the look/voice via brand-kit.md"
say "(tell Claude \"apply my brand kit\"). The editor already works without it."
