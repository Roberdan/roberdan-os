#!/usr/bin/env bash
# hooks/auto-checkpoint.sh — Stop hook. After every agent turn, keep the pause/resume checkpoint
# current so an unannounced crash/reboot loses nothing. Lean by construction: `kb pause --auto`
# overwrites one file (handoff/resume.md), refreshing only mechanical state and PRESERVING the
# human next-step note. Never fail the turn — guard everything, always exit 0.
#
# Wire as a Stop (and PreCompact) hook in ~/.claude/settings.json — merge the generated
# snippet platforms/claude/settings-hooks.json (bin/sync.sh --emit-only regenerates it;
# bootstrap's "Manual steps" point at it).
KB="${RDA_KB:-$HOME/GitHub/roberdan-os/kanban/kb.sh}"
[ -x "$KB" ] || exit 0
# kb resolves the current repo from cwd (registered board) else falls back to roberdan-os —
# same resolution as `kb`/`kb handoff`. --auto is fast (git rev-parse/status) and self-guarded.
bash "$KB" pause --auto >/dev/null 2>&1 || true
# Mechanical per-turn receipt into the loop cursor (loop/receipt.sh decides the safe target:
# in-repo .agent-state/ only where it's already ignored, else $RDA_HOME/state/receipts/).
# This is the automatic emitter behind loop-protocol § tool receipts — zero agent discipline.
RCPT="${RDA_RECEIPT:-$HOME/GitHub/roberdan-os/loop/receipt.sh}"
if [ -x "$RCPT" ]; then
  head_sha="$(git rev-parse --short HEAD 2>/dev/null || echo no-git)"
  dirty="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  bash "$RCPT" session "turn-checkpoint" 0 "$head_sha" "dirty=$dirty" >/dev/null 2>&1 || true
fi
exit 0
