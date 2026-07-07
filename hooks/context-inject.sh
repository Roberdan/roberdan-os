#!/usr/bin/env bash
# SessionStart hook — inject fresh, optimized roberdan-os context at every session start,
# so the session (especially the orchestrator) begins ORIENTED, not blank. Token-bounded:
# it prints only pointers + the small active kanban, never the whole memory. See handoff/.
# Opt-in via RDA_CONTEXT=1 (default on). Non-blocking.
[ "${RDA_CONTEXT:-1}" = "1" ] || exit 0

ROOT="$HOME/GitHub/roberdan-os"
echo "## roberdan-os — session context (auto-injected)"
# A pending pause/resume checkpoint takes top billing — a fresh session (e.g. after a reboot)
# must notice it immediately. See kb pause/resume + AGENTS.md § Pause & Resume.
if [ -f "$ROOT/handoff/resume.md" ]; then
  echo
  # An auto-checkpoint (Stop-hook default note) is routine — don't cry wolf every session.
  # Only an EXPLICIT `kb pause "<note>"` gets the loud PAUSED banner.
  if grep -q 'auto-checkpoint — no explicit note yet' "$ROOT/handoff/resume.md"; then
    echo "### Standing auto-checkpoint (routine — not an explicit pause)."
    sed -n '/^## Mechanical state/,$p' "$ROOT/handoff/resume.md" | sed 's/^/  /'
  else
    echo "### ⏸️ PAUSED — a resume checkpoint is waiting. Roberto likely wants \"continua\"."
    sed 's/^/  /' "$ROOT/handoff/resume.md"
  fi
  echo "  (full: \`kb resume\` · clear when resumed: \`kb resume --done\`)"
  echo
fi
echo "You are the orchestrator. For full context read (durable, not this chat):"
echo "- \`$ROOT/handoff/latest.md\` — current thread, decisions, open threads"
echo "- \`$ROOT/handoff/context-primer.md\` — how to load task-specific context (gbrain search)"
echo "- \`$ROOT/AGENTS.md\` — canon + human gates"
echo
echo "### Active kanban (gated: todo->doing needs your approval; doing->done needs @thor):"
if [ -x "$HOME/.local/bin/kb" ]; then
  RDA_KANBAN="$ROOT/kanban" "$HOME/.local/bin/kb" view 2>/dev/null | sed 's/^/  /' | head -24
fi
exit 0
