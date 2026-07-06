#!/usr/bin/env bash
# hooks/auto-checkpoint.sh — Stop hook. After every agent turn, keep the pause/resume checkpoint
# current so an unannounced crash/reboot loses nothing. Lean by construction: `kb pause --auto`
# overwrites one file (handoff/resume.md), refreshing only mechanical state and PRESERVING the
# human next-step note. Never fail the turn — guard everything, always exit 0.
#
# Wire as a Stop hook in ~/.claude/settings.json (bin/bootstrap.sh prints the block):
#   { "matcher": "", "hooks": [{ "type": "command",
#       "command": "bash $HOME/GitHub/roberdan-os/hooks/auto-checkpoint.sh" }] }
KB="${RDA_KB:-$HOME/GitHub/roberdan-os/kanban/kb.sh}"
[ -x "$KB" ] || exit 0
# kb resolves the current repo from cwd (registered board) else falls back to roberdan-os —
# same resolution as `kb`/`kb handoff`. --auto is fast (git rev-parse/status) and self-guarded.
bash "$KB" pause --auto >/dev/null 2>&1 || true
exit 0
