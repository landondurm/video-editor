#!/bin/bash
# premiere-up.sh — bring Premiere Pro + the MCP bridge up with no human clicks.
#
#   ./workflows/premiere-up.sh                          # launch, wait for bridge
#   ./workflows/premiere-up.sh projects/<job>/premiere/<job>.prproj
#   ./workflows/premiere-up.sh --restart                # quit first, then relaunch
#
# Relies on the autostart patch in the CEP panel (bridge-cep.js, marked
# "REPO-PATCH: autostart") plus <StartOn> in CSXS/manifest.xml, which together
# load the panel and start the bridge when Premiere activates. If the panel is
# ever re-copied from vendor/premiere-mcp/cep-plugin/ those patches ride along,
# because the vendored copy carries them too.
#
# Exits 0 once `ping` answers, non-zero on timeout. bash 3.2 clean.

set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP="Adobe Premiere Pro 2026"
TIMEOUT="${TIMEOUT:-180}"
PROJECT=""
RESTART=0

for arg in "$@"; do
  case "$arg" in
    --restart) RESTART=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) PROJECT="$arg" ;;
  esac
done

log() { echo "[premiere-up] $*"; }

bridge_ping() {
  node "$REPO/workflows/premiere-bridge.mjs" ping '{}' 2>/dev/null \
    | grep -q '"connected": *true'
}

# --- 0. already up? -----------------------------------------------------------
if [ "$RESTART" -eq 0 ] && bridge_ping; then
  log "bridge already connected — nothing to do"
  node "$REPO/workflows/premiere-bridge.mjs" ping '{}' 2>/dev/null | grep -v '^\[' | tail -12
  exit 0
fi

# --- 1. quit if restarting ----------------------------------------------------
# A bare `tell application ... to quit` is NOT reliable here: Premiere can accept
# the AppleEvent, fail to complete it (-1712 timeout), and leave its ExtendScript
# thread WEDGED (the CEP panel keeps rendering "Connected" from its own CEF
# process while every bridge command times out). So: save through the bridge
# first (while it still answers), then a graceful quit, then WAIT. NEVER
# SIGTERM/SIGKILL (see the block below): Premiere logs any non-graceful exit as
# a crash, the crash dialog blocks the CEP panel next launch, and timeline state
# comes back subtly wrong. If it will not quit, stop and hand it to the user.
pid_of() { pgrep -f "$APP.app/Contents/MacOS" 2>/dev/null | head -1; }

if [ "$RESTART" -eq 1 ] && [ -n "$(pid_of)" ]; then
  if bridge_ping; then
    log "saving project through the bridge before quit"
    node "$REPO/workflows/premiere-bridge.mjs" save_project '{}' >/dev/null 2>&1 || \
      log "  WARN: save_project failed — continuing (unsaved work may be lost)"
  else
    log "WARN: bridge not answering — cannot save first; quitting anyway"
  fi

  log "quitting Premiere (graceful)"
  osascript -e "with timeout of 15 seconds
    tell application \"$APP\" to quit
  end timeout" >/dev/null 2>&1 || true

  waited=0
  while [ -n "$(pid_of)" ] && [ "$waited" -lt 30 ]; do sleep 2; waited=$((waited + 2)); done

  # NEVER escalate to kill/kill -9. Premiere treats any non-graceful exit as a
  # CRASH and greets the next launch with a modal "Sorry, an error occurred"
  # report dialog — which then blocks the CEP panel from loading and defeats the
  # whole point of this script. A wedged Premiere is the user's to quit by hand.
  if [ -n "$(pid_of)" ]; then
    log "  graceful quit did NOT take (Premiere's scripting thread may be wedged)."
    log "  Quit it by hand (Cmd-Q, or Force Quit), then re-run this script."
    log "  Not force-killing: an unclean exit makes Premiere show a crash dialog on next launch."
    exit 1
  fi
  log "  Premiere down"
  rm -f /tmp/premiere-mcp-bridge/command-*.json /tmp/premiere-mcp-bridge/response-*.json 2>/dev/null || true
fi

# --- 2. verify the autostart patches are in place -----------------------------
CEP="$HOME/Library/Application Support/Adobe/CEP/extensions/MCPBridgeCEP"
if [ ! -d "$CEP" ]; then
  log "ERROR: CEP panel not installed at $CEP"
  log "  fix: cp -R '$REPO/vendor/premiere-mcp/cep-plugin/' '$CEP'"
  exit 1
fi
grep -q "REPO-PATCH: autostart" "$CEP/bridge-cep.js" \
  || log "WARN: autostart patch missing from installed panel — you may have to click Start Bridge (re-apply workflows/premiere-templates/cep-bridge-autostart.patch)"
grep -q "StartOn" "$CEP/CSXS/manifest.xml" \
  || log "WARN: <StartOn> missing from manifest — panel may not auto-open"

# --- 3. launch ----------------------------------------------------------------
if [ -n "$PROJECT" ]; then
  case "$PROJECT" in /*) ABS="$PROJECT" ;; *) ABS="$REPO/$PROJECT" ;; esac
  [ -f "$ABS" ] || { log "ERROR: no such project: $ABS"; exit 1; }
  log "launching $APP with $(basename "$ABS")"
  open -a "$APP" "$ABS"
else
  log "launching $APP"
  open -a "$APP"
fi

# --- 4. wait for the bridge ---------------------------------------------------
# NOTE: bridge_ping itself BLOCKS (it writes a command file and waits for the
# panel to answer), so elapsed time is measured off the wall clock, not off the
# sleep counter — otherwise a boot spent inside the first ping reports as 0s.
log "waiting for bridge (timeout ${TIMEOUT}s)..."
START=$SECONDS
waited=0
while [ "$waited" -lt "$TIMEOUT" ]; do
  if bridge_ping; then
    log "bridge UP after $((SECONDS - START))s"
    node "$REPO/workflows/premiere-bridge.mjs" ping '{}' 2>/dev/null | grep -v '^\[' | tail -12
    exit 0
  fi
  sleep 3
  waited=$((SECONDS - START))
  [ $((waited % 30)) -lt 3 ] && log "  still waiting (${waited}s)..."
done

log "TIMED OUT after $((SECONDS - START))s"
log "  Premiere may be sitting on the Home screen (no project open = no panel host),"
log "  or waiting on a dialog. Open a project, then re-run this script."
exit 1
