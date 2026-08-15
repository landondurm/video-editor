#!/usr/bin/env bash
# SessionStart hook: on a fresh install, inject a reminder telling Claude to run the
# onboarding/setup flow (CLAUDE.md "FIRST RUN" gate) before doing anything else. Emits NOTHING once
# setup is done. Always exits 0 so it can never break a session.
#
# Pure bash + printf on purpose (NO jq / python dependency), because on a brand-new machine those may
# not be installed yet, and this is the very hook that's supposed to get them installed. Runs on macOS,
# Linux, and Windows (Claude Code on Windows runs hooks through Git Bash, which ships with Git for
# Windows). If Git Bash itself is missing the hook can't fire — that front door lives in CLAUDE.md.
#
# cwd is the project root. "Setup done" = the .setup-complete marker exists (written by ./setup.sh
# once every core tool verifies). Personalization (brand-kit.md) is OPTIONAL and never gates this;
# the editor works out of the box with the neutral bundled look.

if [ ! -f .setup-complete ] && [ -f check-setup.sh ]; then
  # NOTE: newlines below are the literal two-character sequence \n (valid JSON string escapes); printf %s
  # passes them through verbatim, and there are no " or \ or apostrophe chars in the message to break the JSON.
  msg='⚠️ FRESH INSTALL: setup has not finished yet (no .setup-complete marker).\n\nFollow the FIRST RUN onboarding gate in CLAUDE.md before editing anything:\n  1. Run ./setup.sh yourself (no need to ask). It detects the OS, installs every missing tool, bootstraps the render engine, verifies with ./check-setup.sh, then auto-detects an installed editing app (Premiere / Resolve / CapCut) and wires its lane. It is idempotent; re-run it any time.\n  2. Handle its exit codes: 2 = walk the user through restarting Claude Code, then re-run it. 3 = an MCP lane was wired: walk the user through restarting Claude Code, then verify the lane. 1 = read the output and fix what it names (Homebrew one-liner on macOS, apt commands on Linux, or a lane installer error). 0 with an ACTION FOR CLAUDE line = ask the user which editing app to wire, in one line.\n  3. Brand kit is OPTIONAL: offer it once after tools pass; never block editing on it.\n\nIf the user asks to edit a video right now, run setup first (an edit cannot run without ffmpeg).'
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$msg"
fi

exit 0
