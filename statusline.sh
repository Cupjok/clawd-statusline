#!/usr/bin/env bash
# Clawd status line for Claude Code.
#
# Line 1: Clawd, account, folder, git branch, model (effort), context usage
# Line 2: Clawd, 5-hour session and 7-day usage with reset times
# Line 3: Clawd, lines edited this session, git working-tree status
#
# Clawd types on a laptop while the session is working. The hooks in
# clawd-state.sh keep a per-session flag file next to this script.
#
# Options (environment variables):
#   CLAWD_SHOW_ACCOUNT=0   hide the account name
#   CLAWD_ANIMATE=0        never animate Clawd

input=$(cat)

# Numbers need a dot as the decimal mark (printf %.0f, awk). LC_ALL would
# override LC_NUMERIC, so move it to LC_CTYPE to keep UTF-8 working.
if [ -n "$LC_ALL" ]; then
  export LC_CTYPE="$LC_ALL"
  unset LC_ALL
fi
export LC_NUMERIC=C

# The output goes through printf %b, so double any backslash in names
# (folder, branch, model, account) to print them as they are.
esc() { printf '%s' "${1//\\/\\\\}"; }

if ! command -v jq >/dev/null 2>&1; then
  printf 'clawd-statusline: install jq to see the status line'
  exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STATE_DIR="$SCRIPT_DIR/state"
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

DIM="\033[2m"
CYAN="\033[36m"
MAGENTA="\033[35m"
YELLOW="\033[33m"
GREEN="\033[32m"
RED="\033[31m"
RESET_C="\033[0m"
RESET="\033[0m"

# Read every field with one jq call. Fields are split on the unit separator
# (0x1f), because tab is whitespace in IFS and empty fields would collapse.
US=$'\x1f'
IFS="$US" read -r cwd model effort model_id ctx_pct ctx_used ctx_size \
  five_pct five_reset week_pct week_reset added removed sid <<EOF
$(printf '%s' "$input" | jq -r '
  def s: if . == null then "" else tostring end;
  [ (.workspace.current_dir // .cwd),
    .model.display_name,
    (if (.effort | type) == "object" then .effort.level
     elif (.effort | type) == "string" then .effort
     else .model.effort end),
    .model.id,
    .context_window.used_percentage,
    .context_window.total_input_tokens,
    .context_window.context_window_size,
    .rate_limits.five_hour.used_percentage,
    .rate_limits.five_hour.resets_at,
    .rate_limits.seven_day.used_percentage,
    .rate_limits.seven_day.resets_at,
    .cost.total_lines_added,
    .cost.total_lines_removed,
    .session_id
  ] | map(s) | join("\u001f")' 2>/dev/null)
EOF

dir_label="~"
[ -n "$cwd" ] && dir_label=$(basename "$cwd")

# Git: one status call gives branch, ahead/behind, changes and stashes.
# --show-stash needs git 2.35+, so retry without it on older git.
branch=""
if [ -n "$cwd" ]; then
  gs=$(git -C "$cwd" --no-optional-locks status --porcelain=v2 --branch --show-stash 2>/dev/null) ||
    gs=$(git -C "$cwd" --no-optional-locks status --porcelain=v2 --branch 2>/dev/null) || gs=""
  if [ -n "$gs" ]; then
    IFS="$US" read -r branch ahead behind changed untracked stashes <<EOF
$(printf '%s\n' "$gs" | awk -v us="$US" '
  /^# branch.oid / { oid = $3 }
  /^# branch.head / { head = $3 }
  /^# branch.ab /  { ahead = substr($3, 2); behind = substr($4, 2) }
  /^# stash /      { stash = $3 }
  /^[12u] /        { changed++ }
  /^\? /           { untracked++ }
  END {
    if (head == "(detached)") head = substr(oid, 1, 7)
    printf "%s%s%s%s%s%s%d%s%d%s%d", head, us, ahead, us, behind, us, changed, us, untracked, us, stash
  }')
EOF
  fi
fi

top=$(printf "${CYAN}%s${RESET_C}" "$(esc "$dir_label")")
[ -n "$branch" ] && top="$top ${DIM}on${RESET_C} ${MAGENTA}$(esc "$branch")${RESET_C}"

# Effort: status line input first, then CLAUDE_EFFORT, then settings.json.
[ -z "$effort" ] && effort="$CLAUDE_EFFORT"
if [ -z "$effort" ] && [ -f "$CONFIG_DIR/settings.json" ]; then
  effort=$(jq -r --arg m "$model_id" '.modelSettings[$m].effortLevel // .effortLevel // empty' "$CONFIG_DIR/settings.json" 2>/dev/null)
fi

if [ -n "$model" ]; then
  top="$top ${DIM}|${RESET_C} $(esc "$model")"
  [ -n "$effort" ] && top="$top ${DIM}($(esc "$effort"))${RESET_C}"
fi

# Logged-in Claude account (display name, falling back to email).
# Claude Code keeps it in ~/.claude.json, or in $CLAUDE_CONFIG_DIR/.claude.json.
if [ "${CLAWD_SHOW_ACCOUNT:-1}" != 0 ]; then
  account_file="$HOME/.claude.json"
  [ -n "$CLAUDE_CONFIG_DIR" ] && account_file="$CLAUDE_CONFIG_DIR/.claude.json"
  account=$(jq -r '.oauthAccount | .displayName // .emailAddress // empty' "$account_file" 2>/dev/null)
  [ -n "$account" ] && top="${YELLOW}@$(esc "$account")${RESET_C} ${DIM}|${RESET_C} $top"
fi

# Pick a color based on how close to the limit usage is.
color_for_pct() {
  awk -v p="$1" 'BEGIN {
    if (p >= 90) print "\033[31m";      # red
    else if (p >= 70) print "\033[33m"; # yellow
    else print "\033[32m";              # green
  }'
}

# Format a unix epoch timestamp as a short local time.
# GNU date (Linux, Git Bash) takes -d @N; BSD date (macOS) takes -r N.
format_reset() {
  [ -z "$1" ] && return
  date -d "@$1" "+%a %H:%M" 2>/dev/null || date -r "$1" "+%a %H:%M" 2>/dev/null
}

# Format a token count compactly, e.g. 43797 -> 43.8k, 1000000 -> 1M.
# The M cut-off is 999500, because anything above would round to "1000k".
format_tokens() {
  [ -z "$1" ] && return
  awk -v n="$1" 'BEGIN {
    if (n >= 999500) { v = n / 1000000; u = "M" }
    else if (n >= 1000) { v = n / 1000; u = "k" }
    else { printf "%d", n; exit }
    if (v >= 100) printf "%.0f%s", v, u;
    else printf "%.1f%s", v, u;
  }' | sed 's/\.0\([kM]\)$/\1/'
}

# Render a smooth bar with eighth-block precision, e.g. ███▌░░░░░░.
# Filled part uses the given color; the empty track is dimmed.
bar_for_pct() {
  awk -v p="$1" -v w=10 -v c="$2" 'BEGIN {
    split("▏ ▎ ▍ ▌ ▋ ▊ ▉", part, " ");
    if (p > 100) p = 100;
    if (p < 0) p = 0;
    eighths = int((p / 100) * w * 8 + 0.5);
    full = int(eighths / 8);
    rem = eighths % 8;
    bar = c;
    for (i = 0; i < full; i++) bar = bar "█";
    used = full;
    if (rem > 0 && used < w) { bar = bar part[rem]; used++ }
    bar = bar "\033[0m\033[2m";
    for (i = used; i < w; i++) bar = bar "░";
    bar = bar "\033[0m";
    printf "%s", bar;
  }'
}

# Append a usage segment ("Session ███░░ 30% (resets Mon 14:00)") to $out.
out=""
add_usage() {
  label="$1"; pct="$2"; reset_ts="$3"
  [ -z "$pct" ] && return
  c=$(color_for_pct "$pct")
  seg=$(printf "${c}%s${RESET} %s ${c}%.0f%%${RESET}" "$label" "$(bar_for_pct "$pct" "$c")" "$pct")
  reset_fmt=$(format_reset "$reset_ts")
  [ -n "$reset_fmt" ] && seg="$seg (resets $reset_fmt)"
  if [ -n "$out" ]; then out="$out ${DIM}|${RESET_C} $seg"; else out="$seg"; fi
}

if [ -n "$ctx_pct" ]; then
  c=$(color_for_pct "$ctx_pct")
  seg=$(printf "${c}Ctx${RESET} %s ${c}%.0f%%${RESET}" "$(bar_for_pct "$ctx_pct" "$c")" "$ctx_pct")
  if [ -n "$ctx_used" ] && [ -n "$ctx_size" ]; then
    seg="$seg ($(format_tokens "$ctx_used")/$(format_tokens "$ctx_size"))"
  fi
  top="$top ${DIM}|${RESET_C} $seg"
fi

# Usage limits only appear for Claude.ai subscription logins.
add_usage "Session" "$five_pct" "$five_reset"
add_usage "Week" "$week_pct" "$week_reset"

# Third line: lines edited this session, plus git working-tree status.
line3=""
if [ -n "$added" ] || [ -n "$removed" ]; then
  line3="${DIM}Lines${RESET_C} ${GREEN}+${added:-0}${RESET_C} ${RED}-${removed:-0}${RESET_C}"
fi

if [ -n "$branch" ]; then
  g="${DIM}Git${RESET_C}"
  if [ "$changed" -eq 0 ] && [ "$untracked" -eq 0 ]; then
    g="$g ${GREEN}clean${RESET_C}"
  else
    [ "$changed" -gt 0 ] && g="$g ${YELLOW}${changed} changed${RESET_C}"
    [ "$untracked" -gt 0 ] && g="$g ${DIM}${untracked} untracked${RESET_C}"
  fi
  [ "${ahead:-0}" -gt 0 ] && g="$g ${CYAN}↑${ahead}${RESET_C}"
  [ "${behind:-0}" -gt 0 ] && g="$g ${MAGENTA}↓${behind}${RESET_C}"
  [ "$stashes" -gt 0 ] && g="$g ${DIM}stash ${stashes}${RESET_C}"
  if [ -n "$line3" ]; then line3="$line3 ${DIM}|${RESET_C} $g"; else line3="$g"; fi
fi

# File modification time in epoch seconds: GNU stat -c, then BSD stat -f.
mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null
}

# Animate only while the session is working. Ignore flags older than 10 min
# (for example after Esc, when no Stop hook fires).
busy=0
if [ "${CLAWD_ANIMATE:-1}" != 0 ] && [ -n "$sid" ] && [ -f "$STATE_DIR/$sid" ]; then
  m=$(mtime "$STATE_DIR/$sid")
  [ -n "$m" ] && [ $(( $(date +%s) - m )) -lt 600 ] && busy=1
fi

# Clawd mascot on the left; while busy it types on a laptop, frame from the clock.
# statusLine.refreshInterval in settings.json re-runs this every second.
O="\033[38;2;215;119;87m"  # Clawd orange
G="\033[38;2;140;140;150m" # laptop grey
frame=$(( $(date +%s) % 4 ))
if [ "$busy" = 1 ]; then
  # Typing on a laptop: lid in front of the body, hands alternate on the keys.
  m3="${G} ▀▀▀▀▀▀▀ "
  case $frame in
    0|2) m1="${O} ▐▛███▜▌ "; m2="${O}▝▜${G}█████${O}▛▖" ;; # right hand down
    1)   m1="${O} ▐▛███▜▌ "; m2="${O}▗▜${G}█████${O}▛▘" ;; # left hand down
    3)   m1="${O} ▐█████▌ "; m2="${O}▗▜${G}█████${O}▛▘" ;; # blink
  esac
else
  m1="${O} ▐▛███▜▌ "; m2="${O}▝▜█████▛▘"; m3="${O}  ▘▘ ▝▝  "
fi

# Apple Terminal leaves gaps between rows of block glyphs, so paint the body
# with a background colour and cut the eyes out of it.
if [ "$TERM_PROGRAM" = "Apple_Terminal" ]; then
  OB="\033[48;2;215;119;87m" # body as background
  EYE="\033[38;2;0;0;0m"
  eyes=" ▗   ▖ "
  m1="${O}▗${OB}${EYE}${eyes}${RESET_C}${O}▖"
  # Leading pad is a Braille blank (U+2800): Claude Code trims leading spaces, NBSP included.
  m2="⠀${OB}       ${RESET_C} "
  m3="⠀${O}▘▘   ▝▝ "
  if [ "$busy" = 1 ]; then
    # Grey lid in front of the body, keyboard base below, hands alternate
    # on the keys, eyes look down at the screen.
    eyes=" ▖   ▖ "
    case $frame in
      0|2) hl="▝"; hr="▖" ;;                  # right hand down
      1)   hl="▗"; hr="▘" ;;                  # left hand down
      3)   hl="▗"; hr="▘"; eyes=" ▂   ▂ " ;;  # blink
    esac
    # No side nubs on the head row: the hands on row 2 are the only two arms.
    m1="⠀${OB}${EYE}${eyes}${RESET_C} "
    m2="${O}${hl}${OB} ${G}█████${OB} ${RESET_C}${O}${hr}"
    m3="⠀${G}▀▀▀▀▀▀▀ "
  fi
fi

printf "%b" "${m1}${RESET_C} $top\n${m2}${RESET_C} $out\n${m3}${RESET_C} $line3"
