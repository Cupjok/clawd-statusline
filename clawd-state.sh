#!/usr/bin/env bash
# Hook helper: marks a session busy or idle, so the status line knows when
# Clawd should type. Usage: clawd-state.sh busy|idle (hook JSON on stdin).

STATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/state"
sid=$(jq -r '.session_id // empty' 2>/dev/null)
[ -z "$sid" ] && exit 0

# Session ids are UUIDs; refuse anything that could leave the state folder.
case "$sid" in
  */* | *..* ) exit 0 ;;
esac

mkdir -p "$STATE_DIR"
case "$1" in
  busy) touch "$STATE_DIR/$sid" ;;
  idle) rm -f "$STATE_DIR/$sid" ;;
esac
exit 0
