#!/usr/bin/env bash
# setup-resolve.sh: one-command setup for the OPTIONAL DaVinci Resolve lane.
# Installs the pinned Resolve MCP server (official Resolve scripting API) and
# wires .mcp.json. Safe to re-run; it verifies each piece and skips what's done.
#
#   macOS:            fully supported.
#   Windows (native): supported — run from Git Bash (the shell Claude Code uses
#                     on Windows). The server talks to the Windows-side Resolve
#                     through fusionscript.dll.
#   Linux:            supported (native Resolve install at /opt/resolve).
#   WSL2:             NOT supported — Resolve's scripting library loads
#                     in-process, so a Linux-side server can't reach a
#                     Windows-side Resolve. Run this natively instead (above).
#
# Requirements: DaVinci Resolve (Studio recommended; external scripting is a
# Studio feature, and the free edition needs the MCP's in-app bridge script
# instead: see vendor/davinci-resolve-mcp docs), git, python (3.9+).
#
# After it finishes: restart Claude Code once so it picks up .mcp.json, then
# verify by asking Claude to get the Resolve version. (External scripting = Local
# is Resolve's default; check that preference only if the connection fails.)
set -euo pipefail

# The vendored installer prints Unicode box-drawing characters; Windows consoles
# default to cp1252 and the print crashes with UnicodeEncodeError AFTER the venv
# built fine, aborting the .mcp.json wiring below (hit 2026-08-13). Force UTF-8
# for every python this script runs; no-op on macOS/Linux. Fixing it here keeps
# the pinned vendor clone unpatched (a re-clone would silently drop a patch).
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8

# Resolve the PROJECT root. In the shipped package this script sits at the root;
# in the source repo it lives under packaging/overlay/. The marker file decides.
HERE="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$HERE/check-setup.sh" ]]; then
  ROOT="$HERE"
elif [[ -f "$HERE/../../check-setup.sh" ]]; then
  ROOT="$(cd "$HERE/../.." && pwd)"
else
  printf 'ERROR: cannot locate the project root (check-setup.sh not found)\n' >&2
  exit 1
fi
cd "$ROOT"

REPO_URL="https://github.com/samuelgursky/davinci-resolve-mcp.git"
PIN="a9fd831ba301e8268bdf03277ef4de4b289e3bfc"   # v2.72.0, verified 2026-08-03 on Resolve Studio 21.0.3.7
VENDOR="$ROOT/vendor/davinci-resolve-mcp"

say()  { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ---- OS detection ----------------------------------------------------------
OS="$(uname -s)"
IS_WINDOWS=0
if [[ "$OS" == "Linux" ]] && grep -qi microsoft /proc/version 2>/dev/null; then
  fail "WSL2 can't drive a Windows-side Resolve (the scripting library is in-process). Run this natively on Windows instead: Git for Windows + Claude Code on Windows, then re-run from Git Bash (see SETUP.md \"Windows\")."
fi

case "$OS" in
  Darwin)
    APP_PATH="/Applications/DaVinci Resolve/DaVinci Resolve.app"
    SCRIPT_API="/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting"
    SCRIPT_LIB="$APP_PATH/Contents/Libraries/Fusion/fusionscript.so"
    ;;
  Linux)
    APP_PATH="/opt/resolve"
    SCRIPT_API="/opt/resolve/Developer/Scripting"
    SCRIPT_LIB="/opt/resolve/libs/Fusion/fusionscript.so"
    ;;
  MINGW*|MSYS*)
    IS_WINDOWS=1
    # Git Bash spellings here; converted to C:/ form for .mcp.json below (Claude Code
    # spawns the server as a native Windows process, which can't read /c/... paths).
    APP_PATH="/c/Program Files/Blackmagic Design/DaVinci Resolve/Resolve.exe"
    SCRIPT_API="/c/ProgramData/Blackmagic Design/DaVinci Resolve/Support/Developer/Scripting"
    SCRIPT_LIB="/c/Program Files/Blackmagic Design/DaVinci Resolve/fusionscript.dll"
    ;;
  *)
    fail "unsupported OS: $OS (on Windows, run this from Git Bash — see SETUP.md)"
    ;;
esac
[[ -e "$APP_PATH" ]] || say "WARNING: DaVinci Resolve not found at $APP_PATH. Install it, then re-run this script (continuing so the server is at least staged)."

# ---- prerequisites ---------------------------------------------------------
command -v git >/dev/null 2>&1 || fail "git is required. Install it and re-run."
# python3 on macOS/Linux; `python` on Windows (python3 there is a fake Store stub) —
# probe by RUNNING it, not command -v.
PY=python3; "$PY" -c '' 2>/dev/null || PY=python
"$PY" -c '' 2>/dev/null || fail "python is required. Install it (see SETUP.md) and re-run."

# ---- server: clone at the pin + build the venv -----------------------------
if [[ ! -d "$VENDOR/.git" ]]; then
  say "[server] cloning davinci-resolve-mcp..."
  git clone "$REPO_URL" "$VENDOR"
fi
HEAD="$(git -C "$VENDOR" rev-parse HEAD)"
if [[ "$HEAD" != "$PIN" ]]; then
  say "[server] checking out pinned build ${PIN:0:7}..."
  git -C "$VENDOR" fetch --quiet origin
  git -C "$VENDOR" -c advice.detachedHead=false checkout --quiet "$PIN"
fi
# venv layout differs by OS: bin/python (macOS/Linux) vs Scripts/python.exe (Windows)
venv_py() {
  if [[ -e "$VENDOR/venv/Scripts/python.exe" ]]; then echo "$VENDOR/venv/Scripts/python.exe"
  else echo "$VENDOR/venv/bin/python"; fi
}
if [[ ! -x "$(venv_py)" ]]; then
  say "[server] building the Python environment (one time, a minute or two)..."
  (cd "$VENDOR" && "$PY" install.py --clients manual)
fi
VENV_PY="$(venv_py)"
[[ -x "$VENV_PY" ]] || fail "venv build did not produce a venv python (re-run '$PY install.py --clients manual' inside vendor/davinci-resolve-mcp and read its output)"
say "[server] ready at vendor/davinci-resolve-mcp (pinned ${PIN:0:7})"

# ---- .mcp.json: merge the davinci-resolve entry in place -------------------
# On Windows every path must be written in C:/ form — Claude Code launches the
# server natively (not through Git Bash), so /c/... spellings would not resolve.
if [[ "$IS_WINDOWS" -eq 1 ]]; then
  J_PY="$(cygpath -m "$VENV_PY")"
  J_SERVER="$(cygpath -m "$VENDOR/src/server.py")"
  J_API="$(cygpath -m "$SCRIPT_API")"
  J_LIB="$(cygpath -m "$SCRIPT_LIB")"
else
  J_PY="$VENV_PY"; J_SERVER="$VENDOR/src/server.py"; J_API="$SCRIPT_API"; J_LIB="$SCRIPT_LIB"
fi
MCP_JSON="$ROOT/.mcp.json"
"$PY" - "$MCP_JSON" "$J_PY" "$J_SERVER" "$J_API" "$J_LIB" <<'PY'
import json, os, sys
path, py, server, api, lib = sys.argv[1:6]
cfg = {"mcpServers": {}}
if os.path.exists(path):
    with open(path) as fh:
        cfg = json.load(fh)
cfg.setdefault("mcpServers", {})["davinci-resolve"] = {
    "command": py,
    "args": [server],
    "env": {
        "RESOLVE_SCRIPT_API": api,
        "RESOLVE_SCRIPT_LIB": lib,
        "PYTHONPATH": api + "/Modules",
    },
}
with open(path, "w") as fh:
    json.dump(cfg, fh, indent=2)
    fh.write("\n")
print("[config] davinci-resolve entry written to .mcp.json (other servers untouched)")
PY

# ---- done ------------------------------------------------------------------
say ""
say "Setup complete. One step left:"
say "  Restart Claude Code (quit it fully, reopen this project) so it loads the new"
say "  davinci-resolve MCP, then say \"continue setup\"."
say "Verify after the restart: ask Claude to \"get the Resolve version\"; Resolve must"
say "be running (Claude can launch it)."
say "Troubleshooting (only if that fails): check Resolve Preferences > System > General >"
say "External scripting = Local. That IS the shipped default, so don't change it up front;"
say "free-edition (non-Studio) users need the in-app bridge script instead; see"
say "vendor/davinci-resolve-mcp docs."
