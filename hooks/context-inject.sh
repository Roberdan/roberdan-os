#!/usr/bin/env bash
# SessionStart hook — inject fresh, optimized roberdan-os context at every session start,
# so the session (especially the orchestrator) begins ORIENTED, not blank. Token-bounded:
# it prints only pointers + the small active kanban, never the whole memory. See handoff/.
# Opt-in via RDA_CONTEXT=1 (default on). Non-blocking.
[ "${RDA_CONTEXT:-1}" = "1" ] || exit 0

ROOT="$HOME/GitHub/roberdan-os"
echo "## roberdan-os — session context (auto-injected)"
# Approval inbox at the very top — a fresh session must SEE what's waiting on Roberto
# without being asked. Fast local count only (todo + unapproved learning, no gh). See kb pending.
if [ -x "$HOME/.local/bin/kb" ]; then
  _pend="$(RDA_KANBAN="$ROOT/kanban" "$HOME/.local/bin/kb" pending --count 2>/dev/null || echo 0)"
  case "$_pend" in ''|0) : ;; *[!0-9]*) : ;; *)
    echo
    echo "### 📥 $_pend in attesa della tua approvazione — \`kb pending\` per il dettaglio."
  ;; esac
fi
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
  # Compact by design: the full board + per-card descriptions is ~40 lines of agent-facing
  # context that Roberto reads too, every single session, and it drowns the two things he
  # actually needs (what's in flight, what's waiting on him). Print only what's DOING plus
  # counts; run `kb view` on demand for the board. See behavior/roberto-mode.md § volume.
  RDA_KANBAN="$ROOT/kanban" "$HOME/.local/bin/kb" list 2>/dev/null \
    | sed -n '/^DOING:/,/^DONE/p' | sed '1d;$d' | sed 's/^ */  in corso: /' | head -6
  RDA_KANBAN="$ROOT/kanban" "$HOME/.local/bin/kb" view 2>/dev/null \
    | grep -o '\(TO DO\|DOING\|DONE\) ([^)]*)' | paste -sd' · ' - | sed 's/^/  /'
  echo "  (board completo: \`kb view\` · dettaglio card: \`kb show <id>\`)"
fi

# --- la coda autorizzata di questa sessione ---------------------------------------------------
# DECISIONE DI ROBERTO, 2026-07-30: "completa tutte le card che ci sono quando comincia una
# sessione, poi fermati, così io vedo solo se hai aggiunto altro." Lo scatto va QUI e non a mano,
# perché "quando comincia una sessione" è un momento che solo questo hook conosce.
#
# NOTA sul board: qui NON si forza RDA_KANBAN come fa il blocco sopra. Quel blocco mostra sempre
# roberdan-os di proposito (è il board di casa); la coda invece deve essere quella del repo in cui
# la sessione è aperta, altrimenti fotograferebbe il lavoro di un altro progetto.
if [ -x "$HOME/.local/bin/kb" ]; then
  _coda="$("$HOME/.local/bin/kb" queue 2>/dev/null)"
  if [ -n "$_coda" ]; then
    echo
    echo "### 🎫 Coda autorizzata di questa sessione (Roberto ha già detto sì a queste):"
    printf '%s\n' "$_coda" | sed 's/^/  /'
    echo "  Vai avanti con \`kb next\` fino a LISTA FINITA. Non chiedere approvazione per queste."
    echo "  Quello che nasce dopo NON è autorizzato: resta per Roberto, ed è l'unica cosa che vuole vedere."
  fi
fi
exit 0
