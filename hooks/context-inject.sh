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

# --- perf: cache + background refresh for the calls that dominate this hook's wall time -------
# Measured 2026-09-24 (card 260924-085104, this repo's real board): `kb pending --count` ~0.6s
# (it aggregates EVERY registered board, not just this one), `kb doing` ~0.86s (0.05s user — it's
# waiting, not computing), `bus hello --arrival` ~2-2.5s — a SessionStart hook that used to take
# 4-5s wall, almost all of it waiting on these three subprocess chains, none of which this file
# is allowed to speed up from the inside (kb.sh and bus/bus.sh belong to other cards). The lever
# left here is: never make THIS run wait for them.
#
# Pattern (same idiom kanban/worktree-sweep.sh already uses for `wt count --cached`): read the
# last computed value NOW (a plain file read, no subprocess), and if it looks stale, kick a
# refresh in the BACKGROUND for the *next* run — this run never blocks on it. A cold cache (never
# run before) shows nothing for that one section rather than block; every run after the first is
# warm. Cache lives outside the repo ($RDA_HOME, same convention as kb.sh/bus.sh), so it is never
# committed and never shared between machines.
_ci_home="${RDA_HOME:-$HOME/.roberdan-os}"
_ci_cache="$_ci_home/context-inject-cache"
mkdir -p "$_ci_cache" 2>/dev/null || true

# _ci_bg <cache-file> -- <command...> — run <command...> in the background, atomically replacing
# <cache-file> with its stdout on success (never on failure/empty, so a transient error keeps the
# last good value rather than blanking it). stdin/stdout/stderr all redirected away from the
# hook's own — a background child that inherited any of them would make whatever reads this
# hook's output wait for it anyway, defeating the point. No `disown`: this hook has no job
# control (non-interactive), so `disown` just errors; the parenthesized subshell already detaches
# it, same as the existing autosweep line further down.
_ci_bg() {
  local f="$1"; shift; [ "${1:-}" = "--" ] && shift
  ( if "$@" > "$f.new.$$" 2>/dev/null; then mv -f "$f.new.$$" "$f"; else rm -f "$f.new.$$"; fi ) </dev/null >/dev/null 2>&1 &
}

# _ci_stale <cache-file> <ttl-minutes> <anchor-path...> — true (0) when <cache-file> should be
# refreshed: missing, older than <ttl-minutes>, or an anchor path changed since the cache was
# written. `-maxdepth 1`, deliberately: a card lives directly inside todo/doing/done, so adding
# or removing one touches that directory's OWN mtime — checking depth 1 catches that in a
# handful of stat()s. Measured on the real board (469 files under kanban/, mostly done/'s
# archive): unbounded `find kanban -newer <cache>` cost ~0.6s by itself whenever nothing
# recent enough matched and it had to walk the whole tree — more than this entire hook's
# 1s budget, for a check that exists to keep it fast. `-maxdepth 1` doesn't see a card's
# title being edited in place without also being added/removed; the short TTL is the
# backstop for that, same trade-off the task that introduced this accepted elsewhere.
_ci_stale() {
  local f="$1" ttl="$2"; shift 2
  [ -s "$f" ] || return 0
  [ -n "$(find "$f" -mmin "+$ttl" 2>/dev/null)" ] && return 0
  # One `find` for every anchor together, not one per anchor — each spawned process is real
  # money on a loaded machine (measured ~30-70ms apiece here), and `find` already accepts
  # multiple starting paths in a single call.
  local -a existing=()
  local p
  for p in "$@"; do [ -e "$p" ] && existing+=("$p"); done
  [ "${#existing[@]}" -eq 0 ] && return 1
  [ -n "$(find "${existing[@]}" -maxdepth 1 -newer "$f" -print -quit 2>/dev/null)" ] && return 0
  return 1
}

echo "## roberdan-os — session context (auto-injected)"
# Approval inbox at the very top — a fresh session must SEE what's waiting on Roberto
# without being asked. Fast local count only (todo + unapproved learning, no gh). See kb pending.
#
# CACHED (see _ci_stale/_ci_bg above): `kb pending --count` walks every board in the registry,
# not just this one, and cost ~0.6s of the ~4-5s this hook used to take. This run reads the last
# count on disk (instant); a stale-but-existing cache still prints it (a slightly old "41
# pending" beats hiding it behind a wait) and separately kicks a background refresh for next
# time — this run never blocks either way. Only a true cold start (no cache anywhere yet) prints
# nothing for this one banner, once.
if [ -x "$HOME/.local/bin/kb" ]; then
  _pend_cache="$_ci_cache/pending-count"
  _ci_stale "$_pend_cache" 5 \
    "${RDA_KANBAN_REGISTRY:-$_ci_home/kanban-registry}" "$ROOT/kanban/todo" \
    "${RDA_QUARANTINE:-$_ci_home/learnings/quarantine}" \
    && _ci_bg "$_pend_cache" -- env RDA_KANBAN="$ROOT/kanban" "$HOME/.local/bin/kb" pending --count
  _pend="$(cat "$_pend_cache" 2>/dev/null || true)"
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
# STALE HANDOFF, 2026-09-24 (card 260924-085104): this pointer used to tell every session to
# read handoff/latest.md as current context even when it was weeks old, about a different repo
# entirely. The file's own MTIME can't tell staleness apart from freshness here — a `git`
# checkout or `git worktree add` resets a tracked file's mtime to "now" regardless of when its
# content was actually written (this very hook runs from a worktree right now) — so the date
# comes from the file's own first line ("# Handoff — YYYY-MM-DD ..."), never the filesystem.
_hf="$ROOT/handoff/latest.md"
_hf_stale=""
if [ -f "$_hf" ]; then
  _hf_date="$(head -1 "$_hf" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)"
  if [ -n "$_hf_date" ]; then
    # $OSTYPE is a bash builtin (no subprocess) — picks the right `date` dialect first try
    # instead of always paying for one guaranteed-to-fail attempt before the one that works.
    case "$OSTYPE" in
      darwin*) _hf_epoch="$(date -jf '%Y-%m-%d' "$_hf_date" +%s 2>/dev/null || true)" ;;
      *) _hf_epoch="$(date -d "$_hf_date" +%s 2>/dev/null || date -jf '%Y-%m-%d' "$_hf_date" +%s 2>/dev/null || true)" ;;
    esac
    if [ -n "$_hf_epoch" ]; then
      _hf_days=$(( ( $(date +%s) - _hf_epoch ) / 86400 ))
      [ "$_hf_days" -gt 7 ] 2>/dev/null && _hf_stale="$_hf_days"
    fi
  fi
fi
if [ -n "$_hf_stale" ]; then
  echo "- \`$_hf\` is $_hf_stale days old (dated $_hf_date) — STALE, likely about other work now; don't treat it as current"
else
  echo "- \`$_hf\` — current thread, decisions, open threads"
fi
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
  #
  # CACHED, 2026-09-24: `kb doing` alone still measured ~0.86s on a board with several in-flight
  # cards (8, the real count today) — 0.05s of that is user time, so it's waiting on kb.sh's own
  # startup, not computing, and this file cannot change what it waits on. Same pattern as the
  # pending count above: read the last render now, refresh in the background keyed off the
  # kanban dir's own mtime (a card moving between columns touches it).
  _doing_cache="$_ci_cache/board-doing"
  _counts_cache="$_ci_cache/board-counts"
  _ci_stale "$_doing_cache" 3 "$ROOT/kanban" \
    && _ci_bg "$_doing_cache" -- env RDA_KANBAN="$ROOT/kanban" "$HOME/.local/bin/kb" doing
  _ci_stale "$_counts_cache" 3 "$ROOT/kanban" \
    && _ci_bg "$_counts_cache" -- env RDA_KANBAN="$ROOT/kanban" "$HOME/.local/bin/kb" counts
  [ -s "$_doing_cache" ] && sed '1d' "$_doing_cache" | sed 's/^ */  in corso: /' | head -6
  if [ -s "$_counts_cache" ]; then
    sed 's/^/  /' "$_counts_cache"
  else
    echo "  (contando ancora — prima volta o cache scaduta: \`kb counts\` per il numero subito)"
  fi
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
  # headless (factory, @thor): un compito solo — la foto della coda non si tocca
  { [ "${RDA_HEADLESS:-0}" = "1" ] || [ "${RDA_IN_THOR_VERIFY:-0}" = "1" ]; } && _qarg=""
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

# --- il bus: presentarsi, una volta, all'inizio ------------------------------
# Roberto, 2026-09-22: "ogni sessione all'inizio deve presentarsi sul bus con un nome univoco
# e dichiarare su che repo sta lavorando, senno come cazzo fanno a sapere chi sta facendo cosa?"
#
# Fino a oggi nessuno si presentava, e `bus who` rispondeva deducendo dall'ultimo messaggio
# scritto: diceva "qualcuno e' passato di qui", mai "ci sono io, su questa card". Misurato sul
# negozio vero: 167 messaggi, 31 conversazioni, 14 delle quali nessuno ha MAI aperto.
#
# Qui la presentazione avviene da sola. Tre limiti, dichiarati perche' sono veri:
#  - un hook gira in un processo suo, quindi NON puo' esportare variabili nella sessione: il
#    nome se lo deve ricordare l'agente, e per questo glielo scriviamo qui sotto in chiaro.
#  - il ruolo predefinito e' `implementer` (chi lavora sulla card). Un agente che ne ha un altro
#    lo dichiara da se' con `bus hello --as <ruolo>`; la seconda presentazione e' un altro record,
#    non un conflitto.
#  - nessun hook affidabile esiste per la FINE di una sessione, quindi il congedo resta un
#    comando che l'agente esegue (`bus bye`). Una presenza mai chiusa resta dichiarata: per
#    questo `bus who` la stampa accanto all'ultima attivita' osservata, mai al posto di quella.
#
# BACKGROUNDED, 2026-09-24 (card 260924-085104): `bus hello --arrival` alone measured ~2-2.5s
# (bus/bus.sh belongs to another card — not this file's to speed up from the inside; it does
# NOT use `timeout`, since killing it mid-write to the shared presence log could leave a
# damaged line other sessions then can't parse). The role/session/repo this run announces are
# already known right here without asking bus.sh anything, so that part prints instantly. The
# real `bus hello --arrival` call still runs, for real, with its real side effect (the presence
# record other sessions read) — just fully detached, so THIS run never waits on it. The "who
# else / owed / unread" facts in that call's own output are the only part that genuinely can't
# be known without asking it, so those come from the LAST such call's cached output (may be a
# session or two behind — "dichiarazioni, non prove" already, per the comment above), not from
# this run's own call, which by construction isn't back yet when this prints.
if [ -r "$ROOT/bus/bus.sh" ] && command -v jq >/dev/null 2>&1; then
  # Il nome del repo e' quello del CHECKOUT PRINCIPALE, mai quello della copia di lavoro.
  # `kb start` apre una copia per ogni card (~/GitHub/worktrees/<repo>/<card-id>) ed e' li'
  # che il canone dice di lavorare: dentro, `--show-toplevel` risponde <card-id>, e due agenti
  # sullo stesso progetto ma su card diverse finivano in due bus diversi senza vedersi mai.
  # `--git-common-dir` punta al .git PRINCIPALE da qualunque copia, quindi il suo genitore
  # e' il progetto.
  _bcommon="$(git -C "$PWD" rev-parse --git-common-dir 2>/dev/null || true)"
  _btop=""
  if [ -n "$_bcommon" ]; then
    case "$_bcommon" in /*) : ;; *) _bcommon="$PWD/$_bcommon";; esac
    _btop="$(cd "$_bcommon/.." 2>/dev/null && pwd || true)"
  fi
  [ -n "$_btop" ] || _btop="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"
  _brepo="$(basename "${_btop:-$PWD}")"
  case "$_brepo" in
    ''|.|..) _brepo="" ;;
  esac
  if [ -n "$_brepo" ]; then
    _brole="${RDA_BUS_ROLE:-implementer}"
    _bsess="${RDA_BUS_SESSION:-${_sid:-sess-$$}}"
    # UNA CHIAMATA SOLA. Prima erano quattro (hello, who, owed, count) e ognuna e
    # un processo nuovo con la sua validazione del ruolo: l apertura di una
    # sessione era passata da 2,28s a 3,71s, cioe 1,4s pagati ogni volta che
    # Roberto apre qualcosa. Questo file porta gia scritta la cicatrice dei 2,5s
    # pagati all avvio. `--arrival` calcola le quattro risposte dove i dati sono
    # gia aperti, e stampa solo FATTI: niente prosa scritta da un altro agente.
    # Su ripresa/compattazione non ci si ripresenta — e la stessa sessione — ma il
    # benvenuto si ristampa lo stesso, perche il contesto e andato e chi riprende
    # deve sapere chi e. (Questa chiamata ora parte in sottofondo: vedi sopra.)
    _bus_cache="$_ci_cache/bus-arrival-$_brepo"
    case "$_src" in
      resume|compact|fork)
        _ci_bg "$_bus_cache" -- bash "$ROOT/bus/bus.sh" hello --repo "$_brepo" --as "$_brole" \
          --session "$_bsess" --arrival ;;
      *)
        _ci_bg "$_bus_cache" -- bash "$ROOT/bus/bus.sh" hello --repo "$_brepo" --as "$_brole" \
          --session "$_bsess" --doing "sessione aperta" --arrival ;;
    esac
    echo
    printf '### 📻 Sul bus sei **@%s** (sessione `%s`, repo `%s`).\n' "$_brole" "$_bsess" "$_brepo"
    printf '  Passalo ai tuoi sotto-agenti (con un nome di sessione LORO, non il tuo):\n'
    printf '    export RDA_BUS_ROLE=%s RDA_BUS_SESSION=%s RDA_BUS_REPO=%s\n' "$_brole" "$_bsess" "$_brepo"
    if [ -s "$_bus_cache" ]; then
      # bus.sh's own --arrival output is always: header, "passalo ai sotto-agenti", export
      # (lines 1-3, about WHOEVER ran the cached call — another session, discard, never
      # reprint as if it were this one), then "chi altro / owed / unread" (the part worth
      # keeping), then a final "Quando hai finito: bus bye" line (dropped here too — printed
      # fresh below, with THIS run's own repo, not the cached one's).
      sed -n '4,$p' "$_bus_cache" | sed '$d'
    else
      printf '  Nessuna istantanea in cache ancora (prima volta, o appena scaduta): `bus who --repo %s`\n' "$_brepo"
    fi
    printf '  Quando hai finito: `bus bye --repo %s` (senno risulti ancora qui a chi arriva dopo).\n' "$_brepo"
  fi
fi

exit 0
