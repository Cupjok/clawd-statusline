# clawd-statusline

A three-line status line for [Claude Code](https://claude.com/claude-code) with Clawd, the Claude Code mascot, on the left. Clawd types on a laptop while Claude is working and rests when the turn ends.

```
 ▐▛███▜▌  @you | my-project on main | Opus (high) | Ctx ████▎░░░░░ 42% (84k/200k)
▝▜█████▛▘ Session ███████▌░░ 75% (resets Sun 21:53) | Week █▎░░░░░░░░ 12%
  ▘▘ ▝▝   Lines +5 -0 | Git 2 changed ↑1
```

It shows:

- **Line 1:** your Claude account, the folder, the git branch, the model with its effort level, and context window use.
- **Line 2:** 5-hour session use and 7-day use, with reset times. These only appear when you sign in with a Claude.ai subscription.
- **Line 3:** lines edited in this session, and git status (changed, untracked, ahead or behind, stashes).

Bars turn yellow at 70% and red at 90%.

The account name is read from your own Claude Code login on your machine. Nothing is sent anywhere.

## Requirements

- Claude Code
- `bash`, `git` and [`jq`](https://jqlang.org/download/)
  - macOS: `brew install jq`
  - Linux: `sudo apt install jq` (or your package manager)
  - Windows: `winget install jqlang.jq`, and run the installer from Git Bash (comes with [Git for Windows](https://git-scm.com/download/win))
- A terminal font with Unicode block characters (most have them)

## Install

```bash
git clone https://github.com/OWNER/clawd-statusline.git
cd clawd-statusline
./install.sh
```

Start a new Claude Code session to see it.

The installer copies two scripts to `~/.claude/clawd-statusline/` and adds `statusLine` and hooks to `~/.claude/settings.json`. It makes a backup of `settings.json` first and keeps your other hooks and settings. If you already had a status line, it is saved and comes back when you uninstall.

### More than one Claude config folder

If you use `CLAUDE_CONFIG_DIR` for a second account, install into each folder:

```bash
./install.sh --config-dir ~/.claude-work
```

Each folder shows its own account and usage.

## Options

Set these environment variables before you start Claude Code:

| Variable | Effect |
| --- | --- |
| `CLAWD_SHOW_ACCOUNT=0` | Hide the account name (useful for screenshots and streams) |
| `CLAWD_ANIMATE=0` | Keep Clawd still |

## Uninstall

```bash
./install.sh --uninstall
# or, for another config folder:
./install.sh --config-dir ~/.claude-work --uninstall
```

## How the animation works

Claude Code hooks call `clawd-state.sh busy` when you send a prompt or a tool runs, and `clawd-state.sh idle` when the turn stops, a permission prompt opens, or the session ends. The hook writes or deletes a small flag file named after the session id. The status line checks that flag, and `refreshInterval: 1` redraws it every second. A flag older than 10 minutes is ignored, so Clawd stops typing if a turn is cancelled.

Apple Terminal leaves gaps between rows of block characters, so there Clawd is drawn with background colour instead.

## Tested on

- macOS (Terminal, iTerm2) with bash 3.2

Linux and Windows (Git Bash) use the same script with GNU `date` and `stat` fallbacks. Please open an issue if something looks wrong on your system.

## Notes

This is an unofficial fan project. It is not made or endorsed by Anthropic. Clawd and Claude are Anthropic's.

## License

[MIT](LICENSE)
