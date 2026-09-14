#!/usr/bin/env bash
# SessionStart hook — inject fresh, optimized roberdan-os context at every session start,
# so the session (especially the orchestrator) begins ORIENTED, not blank. Token-bounded:
# it prints only pointers + the small active kanban, never the whole memory. See handoff/.
# Opt-in via RDA_CONTEXT=1 (default on). Non-blocking.
[ "${RDA_CONTEXT:-1}" = "1" ] || exit 0

ROOT="$HOME/GitHub/roberdan-os"

# claude-code v2.1.251: a SessionStart resume/fork hook now receives whether the resumed
# transcript's prompt cache is still warm (prompt_cache_likely_expired=false means the window
# just went away for a couple of minutes — everything below is still in it). On a FRESH resume
# only, skip the full block and print one line instead: this hook has no matcher on purpose
# (fires on startup/resume/clear/compact/fork alike, see bin/sync.sh), so a resume two minutes
# after backgrounding used to re-print the whole board on top of a window that already has it.
# Fallback is the full block, unconditionally, when the field is absent or unparseable — older
# Claude Code, and Copilot's emulated chain, which calls this hook with empty stdin (see
# hooks/copilot/extension.template.mjs onSessionStart: runScript(ci, "", ...)).
_stdin="$(cat 2>/dev/null || true)"
_src=""; _sid=""
if command -v jq >/dev/null 2>&1 && [ -n "$_stdin" ]; then
  _src="$(printf '%s' "$_stdin" | jq -r '.source // ""' 2>/dev/null || echo "")"
  _sid="$(printf '%s' "$_stdin" | jq -r '.session_id // ""' 2>/dev/null | tr -cd 'A-Za-z0-9._-' || echo "")"
  _fresh="$(printf '%s' "$_stdin" | jq -r 'if .prompt_cache_likely_expired == false then "1" else "" end' 2>/dev/null || echo "")"
  if { [ "$_src" = "resume" ] || [ "$_src" = "fork" ]; } && [ -n "$_fresh" ]; then
    echo "## roberdan-os — resumed, cache still warm (context unchanged since last turn)"
    exit 0
  fi
fi

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
  #
  # ASK FOR THE COLUMN, NOT THE BOARD. These two lines used to be `kb list` (all three
  # columns, then sed out DOING) and `kb view` (render the whole board, then grep three
  # numbers back out of it) — so both walked all 96 done cards, spawning grep+sed+basename
  # per card, in order to print two card titles and one counter line. Measured on the real
  # board 2026-07-30 (96 done cards), A/B alternated at the same machine load, 3 rounds:
  # old pair 2.534 / 2.917 / 2.579 s, new pair 0.074 / 0.075 / 0.074 s — ~34x, ~2.5 s off
  # every session start. Byte-identical output but for the counter separator. A
  # SessionStart hook is paid before the human can type, in every session, in every repo.
  RDA_KANBAN="$ROOT/kanban" "$HOME/.local/bin/kb" doing 2>/dev/null \
    | sed '1d' | sed 's/^ */  in corso: /' | head -6
  RDA_KANBAN="$ROOT/kanban" "$HOME/.local/bin/kb" counts 2>/dev/null | sed 's/^/  /'
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
#
# REVISIONE 2026-09-14: la foto si rifà a ogni sessione NUOVA (`--sessione <id>`). Senza, la prima
# foto restava per sempre — roberdan-os aveva quella del 30 luglio, tutta chiusa, e l'agente non
# veniva mai trattenuto. Compattazione, ripresa e fork tengono la foto che c'è: dentro una
# sessione ciò che nasce dopo non parte. Copilot passa session_id e source (startup|resume|new)
# da hooks/copilot/extension.template.mjs onSessionStart; stdin vuoto = nessun id = foto intatta.
if [ -x "$HOME/.local/bin/kb" ]; then
  _qarg=""
  case "$_src" in resume|compact|fork) : ;; *) [ -n "$_sid" ] && _qarg="--sessione $_sid" ;; esac
  # shellcheck disable=SC2086  # _qarg è vuoto o due parole già ripulite
  _coda="$("$HOME/.local/bin/kb" queue $_qarg 2>/dev/null)"
  if [ -n "$_coda" ]; then
    echo
    echo "### 🎫 Coda autorizzata di questa sessione (Roberto ha già detto sì a queste):"
    printf '%s\n' "$_coda" | sed 's/^/  /'
    echo "  Vai avanti con \`kb next\` fino a LISTA FINITA. Non chiedere approvazione per queste."
    echo "  Quello che nasce dopo NON è autorizzato: resta per Roberto, ed è l'unica cosa che vuole vedere."
  fi
fi

# Copie di lavoro rimaste in giro: un CONTATORE, non un elenco e non una pulizia. Il 2026-09-13
# ce n'erano 99 vive, di 4 repo, nessuna chiusa da chi l'aveva aperta — invisibili perche'
# nessuna schermata le nominava mai. Una riga a ogni sessione e' cio' che mancava; la rimozione
# resta un comando che qualcuno digita, mai un effetto dell'apertura di una sessione.
# La pulizia A MONTE invece parte qui in sottofondo (autosweep, solo il repo corrente): cio' che
# e' stato integrato mentre non c'eri sparisce senza che nessuno debba ricordarsene.
[ -r "$ROOT/kanban/worktree-sweep.sh" ] && ( bash "$ROOT/kanban/worktree-sweep.sh" autosweep >/dev/null 2>&1 & ) >/dev/null 2>&1
_wt="$ROOT/kanban/worktree.sh"
if [ -r "$_wt" ]; then
  # --cached: LEGGE un numero gia' calcolato. Contarlo davvero costa ~10s, e un'attesa del
  # genere a ogni apertura di sessione verrebbe tolta entro la settimana.
  _n="$(bash "$_wt" count --cached 2>/dev/null || echo 0)"
  if [ "${_n:-0}" -gt 0 ] 2>/dev/null; then
    echo
    echo "### 🧹 $_n copie di lavoro sono rimaste in giro e non hanno piu' niente dentro."
    echo "  Guardare tutto il sistema: \`kb checkup\` — solo queste: \`kb wt\` (con \`--yes\` le toglie)."
  fi
fi

exit 0
