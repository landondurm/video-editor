#!/usr/bin/env bash
# setup-premiere.sh: one-command setup for the OPTIONAL Premiere Pro finishing lane.
# Installs the Premiere MCP engine (pinned build), the MCP Bridge panel, and
# wires .mcp.json. Safe to re-run; it verifies each piece and skips what's done.
#
#   macOS:            fully supported.
#   Windows (native): supported — run from Git Bash (the shell Claude Code uses
#                     on Windows). Panel installs under %APPDATA%, CEP debug
#                     mode via the registry, bridge folder under %TEMP%.
#   Linux:            no Premiere exists; use the default chat-only pipeline.
#
# After it finishes: restart Premiere, open Window > Extensions > MCP Bridge
# (CEP), click Start Bridge, then restart Claude Code once so it picks up
# .mcp.json. Verify with: node workflows/premiere-bridge.mjs ping
set -euo pipefail
# Resolve the PROJECT root. In the shipped package this script sits at the root;
# in the source repo it lives under packaging/overlay/. The marker file decides.
HERE="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$HERE/workflows/premiere-bridge.mjs" ]]; then
  ROOT="$HERE"
elif [[ -f "$HERE/../../workflows/premiere-bridge.mjs" ]]; then
  ROOT="$(cd "$HERE/../.." && pwd)"
else
  printf 'ERROR: cannot locate the project root (workflows/premiere-bridge.mjs not found)\n' >&2
  exit 1
fi
cd "$ROOT"

REPO_URL="https://github.com/hetpatel-11/Adobe_Premiere_Pro_MCP.git"
PIN="cc57eb409e6fe2d2e2c99ad32bf112c7e61039c7"   # verified 2026-07-18 on Premiere 26.3
VENDOR="$ROOT/vendor/premiere-mcp"

say()  { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ---- OS detection ----------------------------------------------------------
OS="$(uname -s)"
IS_WINDOWS=0
case "$OS" in MINGW*|MSYS*) IS_WINDOWS=1 ;; esac
if [[ "$OS" == "Linux" ]] && grep -qi microsoft /proc/version 2>/dev/null; then
  fail "WSL is not a supported path anymore — run this natively on Windows from Git Bash (see SETUP.md \"Windows\")."
elif [[ "$OS" == "Linux" ]]; then
  fail "Premiere Pro does not run on Linux. Use the default chat-only pipeline instead."
elif [[ "$OS" != "Darwin" && "$IS_WINDOWS" -eq 0 ]]; then
  fail "unsupported OS: $OS (on Windows, run this from Git Bash — see SETUP.md)"
fi

# ---- prerequisites ---------------------------------------------------------
command -v git  >/dev/null 2>&1 || fail "git is required. Install it and re-run."
command -v node >/dev/null 2>&1 || fail "Node.js 18+ is required. Install it (see SETUP.md) and re-run."
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
[[ "$NODE_MAJOR" -ge 18 ]] || fail "Node.js 18+ required, found $(node -v)."

# ---- engine: clone at the pin + build --------------------------------------
if [[ ! -d "$VENDOR/.git" ]]; then
  say "[engine] cloning premiere-mcp..."
  git clone "$REPO_URL" "$VENDOR"
fi
HEAD="$(git -C "$VENDOR" rev-parse HEAD)"
if [[ "$HEAD" != "$PIN" ]]; then
  say "[engine] checking out pinned build ${PIN:0:7}..."
  git -C "$VENDOR" fetch --quiet origin
  git -C "$VENDOR" -c advice.detachedHead=false checkout --quiet "$PIN"
fi
if [[ ! -f "$VENDOR/dist/index.js" || ! -d "$VENDOR/node_modules" ]]; then
  say "[engine] installing dependencies + building (one time, a minute or two)..."
  (cd "$VENDOR" && npm install --no-fund --no-audit && npm run build)
fi
[[ -f "$VENDOR/dist/index.js" ]] || fail "engine build did not produce dist/index.js"
say "[engine] ready at vendor/premiere-mcp (pinned ${PIN:0:7})"

# ---- panel install + bridge temp dir (per OS) ------------------------------
if [[ "$OS" == "Darwin" ]]; then
  EXT_DIR="$HOME/Library/Application Support/Adobe/CEP/extensions/MCPBridgeCEP"
  mkdir -p "$(dirname "$EXT_DIR")"
  rm -rf "$EXT_DIR"
  cp -R "$VENDOR/cep-plugin" "$EXT_DIR"
  say "[panel] installed to CEP extensions"
  for v in 10 11 12; do defaults write "com.adobe.CSXS.$v" PlayerDebugMode 1; done
  say "[panel] CEP debug mode enabled"
  BRIDGE_DIR_SERVER="/tmp/premiere-mcp-bridge"
  TIMEOUT_MS=60000
  mkdir -p "$BRIDGE_DIR_SERVER"
else
  # Native Windows (Git Bash): panel under %APPDATA%, CEP debug mode via the
  # registry, bridge folder = the panel's Windows default %TEMP%\premiere-mcp-bridge.
  [[ -n "${APPDATA:-}" ]] || fail "APPDATA is not set — run this from Git Bash on Windows."
  EXT_DIR="$(cygpath -u "$APPDATA")/Adobe/CEP/extensions/MCPBridgeCEP"
  mkdir -p "$(dirname "$EXT_DIR")"
  rm -rf "$EXT_DIR"
  cp -R "$VENDOR/cep-plugin" "$EXT_DIR"
  say "[panel] installed to CEP extensions (%APPDATA%\\Adobe\\CEP\\extensions)"
  # MSYS_NO_PATHCONV: stop Git Bash rewriting /v /t /d /f into filesystem paths.
  for v in 10 11 12; do
    MSYS_NO_PATHCONV=1 reg.exe add "HKCU\\Software\\Adobe\\CSXS.$v" /v PlayerDebugMode /t REG_SZ /d 1 /f >/dev/null
  done
  say "[panel] CEP debug mode enabled (registry)"
  # .mcp.json needs the WINDOWS spelling of the bridge dir — Claude Code spawns the
  # node server natively, not through Git Bash. %TEMP% defaults to %LOCALAPPDATA%\Temp.
  BRIDGE_DIR_SERVER="$(cygpath -m "$LOCALAPPDATA")/Temp/premiere-mcp-bridge"
  TIMEOUT_MS=60000
  mkdir -p "$(cygpath -u "$BRIDGE_DIR_SERVER")"
  say "[bridge] folder: $BRIDGE_DIR_SERVER"
fi

# Engine path for .mcp.json — Windows spelling on Windows (see above).
ENGINE_JS="$VENDOR/dist/index.js"
[[ "$IS_WINDOWS" -eq 1 ]] && ENGINE_JS="$(cygpath -m "$ENGINE_JS")"

# ---- .mcp.json: merge the premiere-pro entry in place ----------------------
# A JSON merge (via node, already a hard prereq above), NOT an overwrite and NOT
# a skip: the old "already exists, leaving it alone" behavior silently dropped
# the premiere-pro entry when another lane (e.g. setup-resolve.sh) had created
# .mcp.json first. Other servers are left untouched.
MCP_JSON="$ROOT/.mcp.json"
node -e '
const fs = require("fs");
const [path, engine, bridgeDir, timeoutMs] = process.argv.slice(1);
let cfg = { mcpServers: {} };
if (fs.existsSync(path)) cfg = JSON.parse(fs.readFileSync(path, "utf8"));
cfg.mcpServers = cfg.mcpServers || {};
cfg.mcpServers["premiere-pro"] = {
  command: "node",
  args: [engine],
  env: { PREMIERE_TEMP_DIR: bridgeDir, PREMIERE_TIMEOUT_MS: String(timeoutMs) }
};
fs.writeFileSync(path, JSON.stringify(cfg, null, 2) + "\n");
console.log("[config] premiere-pro entry written to .mcp.json (other servers untouched)");
' "$MCP_JSON" "$ENGINE_JS" "$BRIDGE_DIR_SERVER" "$TIMEOUT_MS"

# ---- done ------------------------------------------------------------------
say ""
say "Setup complete. Finish with these three steps:"
say "  1. Restart Premiere Pro (the panel is discovered at launch)."
say "  2. In Premiere: Window > Extensions > MCP Bridge (CEP) > Start Bridge."
say "  3. Restart Claude Code (quit it fully, then reopen this project folder) so it"
say "     loads the new premiere-pro MCP, and say \"continue setup\"."
say "Verify after the restart:  node workflows/premiere-bridge.mjs ping"
if [[ "$IS_WINDOWS" -eq 1 ]]; then
  say ""
  say "Windows note:"
  say "  - If the panel shows a different Temp Directory than $BRIDGE_DIR_SERVER,"
  say "    set it to match and click Start Bridge again."
fi
