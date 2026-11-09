#!/usr/bin/env bash
# Install the Clawd status line into a Claude Code config folder.
#
#   ./install.sh                       install into ~/.claude (or $CLAUDE_CONFIG_DIR)
#   ./install.sh --config-dir DIR      install into another config folder
#   ./install.sh --uninstall           remove it again
#
# settings.json is backed up first. Other hooks and settings are kept.

set -euo pipefail

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
UNINSTALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --config-dir) CONFIG_DIR="${2:?--config-dir needs a folder}"; shift 2 ;;
    --uninstall)  UNINSTALL=1; shift ;;
    -h|--help)    sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required. Install it first:" >&2
  echo "  macOS:   brew install jq" >&2
  echo "  Linux:   sudo apt install jq   (or your package manager)" >&2
  echo "  Windows: winget install jqlang.jq" >&2
  exit 1
fi

SRC_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Hooks run from the project folder, so settings.json needs an absolute path.
mkdir -p "$CONFIG_DIR"
CONFIG_DIR=$(cd "$CONFIG_DIR" && pwd)
DEST="$CONFIG_DIR/clawd-statusline"
SETTINGS="$CONFIG_DIR/settings.json"
MARK="clawd-statusline/clawd-state.sh"

# On Windows (Git Bash), write C:/... paths so any shell can run the command.
native_path() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

mkdir -p "$CONFIG_DIR"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
jq empty "$SETTINGS" 2>/dev/null || { echo "$SETTINGS is not valid JSON. Fix it first." >&2; exit 1; }

backup="$SETTINGS.bak-clawd-$(date +%Y%m%d-%H%M%S)"
cp "$SETTINGS" "$backup"
tmp="$SETTINGS.tmp.$$"
trap 'rm -f "$tmp"' EXIT

# Drop our hooks from every event, and drop groups and events left empty.
STRIP_HOOKS='
  if .hooks then
    .hooks |= (with_entries(.value |= (
        map(.hooks |= map(select((.command // "") | contains($mark) | not)))
        | map(select((.hooks | length) > 0))))
      | with_entries(select((.value | length) > 0)))
    | if (.hooks | length) == 0 then del(.hooks) else . end
  else . end'

if [ "$UNINSTALL" = 1 ]; then
  # Touch statusLine only while it is still ours: then put back the one from
  # before the install, or remove it if there was none.
  prev="$DEST/previous-statusline.json"
  [ -f "$prev" ] || echo 'null' > "$prev"
  jq --arg mark "$MARK" --slurpfile prev "$prev" "$STRIP_HOOKS"'
    | if ((.statusLine.command // "") | contains("clawd-statusline/statusline.sh")) then
        (if $prev[0] == null then del(.statusLine) else .statusLine = $prev[0] end)
      else . end' "$SETTINGS" > "$tmp"
  mv "$tmp" "$SETTINGS"
  rm -rf "$DEST"
  echo "Clawd status line removed from $CONFIG_DIR"
  echo "Backup of the old settings: $backup"
  exit 0
fi

mkdir -p "$DEST/state"
cp "$SRC_DIR/statusline.sh" "$SRC_DIR/clawd-state.sh" "$DEST/"
chmod +x "$DEST/statusline.sh" "$DEST/clawd-state.sh"

# Keep a status line that was there before, so --uninstall can put it back.
if jq -e '.statusLine and ((.statusLine.command // "") | contains("clawd-statusline/") | not)' "$SETTINGS" >/dev/null; then
  jq '.statusLine' "$SETTINGS" > "$DEST/previous-statusline.json"
fi

sl_cmd="bash \"$(native_path "$DEST/statusline.sh")\""
hook_cmd="bash \"$(native_path "$DEST/clawd-state.sh")\""

jq --arg mark "$MARK" --arg sl "$sl_cmd" --arg h "$hook_cmd" "$STRIP_HOOKS"'
  | .statusLine = {type: "command", command: $sl, refreshInterval: 1}
  | reduce (
      ["UserPromptSubmit", "busy"], ["PreToolUse", "busy"], ["PostToolUse", "busy"],
      ["Stop", "idle"], ["StopFailure", "idle"], ["SessionEnd", "idle"]
    ) as [$event, $state] (.;
      .hooks[$event] = ((.hooks[$event] // []) + [{hooks: [{type: "command", command: ($h + " " + $state)}]}]))
' "$SETTINGS" > "$tmp"
mv "$tmp" "$SETTINGS"

echo "Clawd status line installed in $CONFIG_DIR"
echo "Backup of the old settings: $backup"
echo "Start a new Claude Code session to see it."
