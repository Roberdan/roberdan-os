#!/usr/bin/env bash
# system-health.sh — un rapporto settimanale che unisce le misure sparse in un solo posto,
# scritto per Roberto (italiano, numeri concreti, ogni numero dice la sua fonte, sommario
# breve prima del dettaglio — vedi ~/.claude/CLAUDE.md § formato).
#
# Sezioni: costo (bin/cost-report.sh, con la finestra precedente), probe di ricerca gbrain,
# coda/embedding gbrain, copie di lavoro (worktree) rimovibili, token fissi a inizio sessione
# Claude Code, approvazioni in attesa, telemetria del valore (bin/telemetry.sh). OGNI sezione
# degrada a "non disponibile: <perche'>" se la sua fonte manca o fallisce — una sezione rossa
# non deve mai far sparire le altre (set -u, mai set -e).
#
# Ogni soglia superata (vedi le costanti T_* sotto) diventa una RIGA DI PROPOSTA con il comando
# `kb add` esatto — mai una card gia' aperta: il gate resta a Roberto.
#
# Scrive il referto in $RDA_HOME/reports/system-health-YYYY-MM-DD.md e lo stampa su stdout.
# Chiamato da bin/pending-digest.sh quando l'ultimo referto ha piu' di 7 giorni.
set -uo pipefail

# launchd (com.roberdan.rda-pending-digest, /bin/bash -lc) NON eredita la funzione shell
# `gbrain`: solo il binario vero, sotto ~/.bun/bin, non e' sulla PATH di un login shell pulito
# (verificato 2026-09-24: `env -i HOME=$HOME /bin/bash -lc 'command -v gbrain'` non trova nulla).
# Il binario e' eseguibile da solo (shebang #!/usr/bin/env bun) e la probe gia' fa da se' i due
# passi che la funzione farebbe (cd ~/.gbrain, unset DATABASE_URL) — basta metterlo in PATH qui.
# APPENDED, mai anteposto: un test che mette un gbrain finto davanti sulla PATH deve continuare
# a vincere lui (isolamento dei test) — sotto il vero launchd, dove non c'e' nient'altro, il
# risultato e' identico perche' e' l'unico candidato comunque.
[ -d "$HOME/.bun/bin" ] && PATH="$PATH:$HOME/.bun/bin"
[ -d /opt/homebrew/bin ] && PATH="$PATH:/opt/homebrew/bin"
export PATH
# Nello stesso ambiente spoglio gbrain risolve la connessione al suo database per ruolo
# utente: senza USER/LOGNAME il ruolo torna "unknown" e ogni query fallisce in silenzio
# (verificato 2026-09-24: stesso comando, con e senza queste due variabili). whoami e' l'unica
# fonte affidabile quando l'ambiente non le porta gia'.
if [ -z "${USER:-}" ] || [ -z "${LOGNAME:-}" ]; then
  _who="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"
  [ -n "$_who" ] && { USER="${USER:-$_who}"; LOGNAME="${LOGNAME:-$_who}"; export USER LOGNAME; }
  unset _who
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RDA_HOME="${RDA_HOME:-$HOME/.roberdan-os}"
DAYS="${RDA_HEALTH_DAYS:-7}"
REPORTS_DIR="${RDA_HEALTH_REPORTS_DIR:-$RDA_HOME/reports}"
KB="${RDA_HEALTH_KB:-$ROOT/kanban/kb.sh}"
COST_CMD="${RDA_HEALTH_COST_CMD:-$ROOT/bin/cost-report.sh}"
PROBE_CMD="${RDA_HEALTH_PROBE_CMD:-$ROOT/bin/gbrain-search-probe.sh}"
PROBE_MIN="${RDA_HEALTH_PROBE_MIN:-9}"
PROBE_TIMEOUT="${RDA_HEALTH_PROBE_TIMEOUT:-300}"
TELEMETRY_CMD="${RDA_HEALTH_TELEMETRY_CMD:-$ROOT/bin/telemetry.sh}"
TELEMETRY_TIMEOUT="${RDA_HEALTH_TELEMETRY_TIMEOUT:-180}"
CLAUDE_HOME="${RDA_CLAUDE_HOME:-$HOME/.claude}"
AGENTS_MD="${RDA_HEALTH_AGENTS_MD:-$ROOT/AGENTS.md}"

# Soglie documentate (card 260924-085116): superarle apre una PROPOSTA, mai una card gia' avviata.
T_PROBE="${RDA_HEALTH_THRESH_PROBE:-9}"                            # rosso se hit < soglia
T_SUBAGENT_FRONTIER="${RDA_HEALTH_THRESH_SUBAGENT_FRONTIER:-30}"   # rosso se % > soglia
T_WORKTREES="${RDA_HEALTH_THRESH_WORKTREES:-0}"                    # rosso se N > soglia
T_TOKENS="${RDA_HEALTH_THRESH_TOKENS:-10000}"                      # rosso se N > soglia

_bounded() { # <timeout-seconds> <cmd...> — non fallisce mai il chiamante, solo l'output
  local t="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$t" "$@"; else "$@"; fi
}

PROPOSALS=()
_propose() { PROPOSALS+=("$1"); }
# Titoli brevi per il sommario (max ~6 righe, vedi il formato di risposta): ogni sezione li
# valorizza come effetto collaterale — MAI ricatturando l'output di una sezione una seconda
# volta con $(...), che aprirebbe un'altra subshell e perderebbe le _propose fatte li' dentro.
HL_COST="spesa Copilot: non disponibile"; HL_PROBE="probe gbrain: non disponibile"
HL_WT="copie di lavoro rimovibili: non disponibile"; HL_TOK="token fissi a inizio sessione: non disponibile"

# --- 1) Costo -----------------------------------------------------------------
_sec_cost() {
  local out rc=0
  out="$(_bounded 60 bash "$COST_CMD" --days "$DAYS" 2>&1)" || rc=$?
  if [ $rc -ne 0 ] || [ -z "$out" ]; then
    echo "  non disponibile: bin/cost-report.sh ha fallito o e' scaduto"
    return
  fi
  echo "  fonte: session-store.db tabella assistant_usage_events [Copilot]; ~/.claude/projects/*/*.jsonl + */subagents/ [Claude Code]"
  local frontier
  frontier="$(printf '%s\n' "$out" | sed -n 's/^@@METRIC subagent_frontier_share_pct //p' | tail -1)"
  printf '%s\n' "$out" | grep -v '^@@METRIC '
  HL_COST="$(printf '%s\n' "$out" | grep -m1 'spesa a listino totale' | sed 's/^ *Copilot — /Copilot: /')"
  [ -n "$HL_COST" ] || HL_COST="spesa Copilot: non disponibile"
  if [ -n "$frontier" ]; then
    awk -v f="$frontier" -v t="$T_SUBAGENT_FRONTIER" 'BEGIN{exit !(f>t)}' && \
      _propose "quota di spesa dei sotto-agenti Copilot su modelli frontier al ${frontier}% (soglia ${T_SUBAGENT_FRONTIER}%): kb add \"sotto-agenti Copilot su modello non-frontier\" --repo roberdan-os \"i sotto-agenti general-purpose girano su un modello di classe mid o cheap del registro\" \"cost-report.sh mostra la quota frontier sotto ${T_SUBAGENT_FRONTIER}%\""
  fi
}

# --- 2) Probe di ricerca gbrain -------------------------------------------------
_sec_probe() {
  if ! command -v gbrain >/dev/null 2>&1 || ! command -v timeout >/dev/null 2>&1; then
    echo "  non disponibile: gbrain o timeout non disponibili in questa shell"
    return
  fi
  echo "  fonte: bin/gbrain-search-probe.sh (10 domande fisse in un file privato, MIN=$PROBE_MIN)"
  local out rc=0
  out="$(_bounded "$PROBE_TIMEOUT" env MIN="$PROBE_MIN" bash "$PROBE_CMD" 2>&1)" || rc=$?
  # rc=2 + "non configurata" = nessun file di domande su questa macchina (mai committato: vedi
  # bin/gbrain-search-probe.example.tsv). Non e' un fallimento della probe — niente proposta.
  if [ "$rc" -eq 2 ] && printf '%s\n' "$out" | grep -q "non configurata"; then
    echo "  probe non configurata (nessun file privato di domande — vedi bin/gbrain-search-probe.example.tsv)"
    HL_PROBE="probe gbrain: non configurata"
    return
  fi
  printf '%s\n' "$out" | grep -E '^(HIT|MISS|gbrain-search-probe:)'
  local hits total
  hits="$(printf '%s\n' "$out" | sed -n 's#.*gbrain-search-probe: \([0-9]*\)/\([0-9]*\).*#\1#p' | tail -1)"
  total="$(printf '%s\n' "$out" | sed -n 's#.*gbrain-search-probe: \([0-9]*\)/\([0-9]*\).*#\2#p' | tail -1)"
  if [ -z "$hits" ]; then
    echo "  non disponibile: la probe non ha prodotto un risultato leggibile (timeout o errore)"
    return
  fi
  HL_PROBE="probe gbrain: $hits/$total nei primi 3"
  [ "$hits" -lt "$T_PROBE" ] && \
    _propose "probe di ricerca gbrain a ${hits}/${total} (soglia ${T_PROBE}): kb add \"probe gbrain sotto soglia\" --repo roberdan-os \"le domande MISS della probe tornano a trovare la pagina attesa nei primi 3 risultati\" \"bin/gbrain-search-probe.sh torna a >=${T_PROBE}/10\""
}

# --- 3) Coda/embedding gbrain (a buon mercato: --fast, un timeout corto) -------
_sec_gbrain_queue() {
  if ! command -v gbrain >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
    echo "  non disponibile: gbrain o python3 non disponibili in questa shell"
    return
  fi
  echo "  fonte: gbrain doctor --json --fast"
  local out
  # rc ignorato di proposito: `gbrain doctor` esce non-zero quando lo stato e' "unhealthy",
  # che e' esattamente il caso che questa sezione deve poter riportare — il segnale di
  # fallimento vero e' l'output vuoto/non-JSON, controllato sotto.
  out="$(_bounded 30 gbrain doctor --json --fast 2>/dev/null)"
  if [ -z "$out" ]; then
    echo "  non disponibile: gbrain doctor --fast ha fallito o e' scaduto"
    return
  fi
  printf '%s' "$out" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("  non disponibile: risposta di gbrain doctor non leggibile"); sys.exit(0)
score = d.get("health_score")
issues = [i.get("name") for i in (d.get("top_issues") or []) if i.get("status") == "fail"][:3]
print("  punteggio di salute: %s/100" % (score if score is not None else "non disponibile"))
print("  problemi principali: " + (", ".join(issues) if issues else "nessuno in stato fail"))
'
}

# --- 4) Copie di lavoro (worktree) non rimosse ----------------------------------
_sec_worktrees() {
  echo "  fonte: kb wt --all (RDA_WT_FAST=1: solo git, mai --yes, mai una chiamata di rete)"
  local out rc=0
  # RDA_WT_FAST=1 puo' SOLO SOTTOSTIMARE (un ramo integrato via gh che git da solo non vede
  # ancora come antenato), mai sovrastimare: l'unico verso in cui questo contatore puo'
  # sbagliare senza indurre una pulizia sbagliata in un rapporto settimanale.
  out="$(_bounded 60 env RDA_WT_FAST=1 bash "$KB" wt --all 2>&1)" || rc=$?
  local n
  n="$(printf '%s\n' "$out" | sed -n 's/.* \([0-9]*\) rimovibili .*/\1/p' | tail -1)"
  if [ -z "$n" ]; then
    echo "  non disponibile: kb wt --all ha fallito o e' scaduto"
    return
  fi
  echo "  $n copie di lavoro rimovibili (puo' solo sottostimare; kb wt --yes rimuove)"
  HL_WT="copie di lavoro rimovibili: $n"
  [ "$n" -gt "$T_WORKTREES" ] && \
    _propose "copie di lavoro rimovibili: $n (soglia $T_WORKTREES): kb add \"copie di lavoro da rimuovere\" --repo roberdan-os \"kb wt --all mostra 0 copie rimovibili dopo la pulizia\" \"Roberto approva ed esegue kb wt --yes\""
}

# --- 5) Token fissi a inizio sessione [C] ---------------------------------------
_sec_tokens() {
  echo "  fonte: wc -c di CLAUDE.md + rules/*.md + output style attivo + AGENTS.md, diviso 4"
  local style_name style_file bytes=0 f
  for f in "$CLAUDE_HOME/CLAUDE.md" "$CLAUDE_HOME/rules"/*.md "$AGENTS_MD"; do
    [ -f "$f" ] || continue
    bytes=$((bytes + $(wc -c < "$f" 2>/dev/null || echo 0)))
  done
  if [ -f "$CLAUDE_HOME/settings.json" ] && command -v python3 >/dev/null 2>&1; then
    style_name="$(python3 -c '
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("outputStyle") or "")
except Exception:
    print("")
' "$CLAUDE_HOME/settings.json" 2>/dev/null)"
    if [ -n "$style_name" ]; then
      style_file="$CLAUDE_HOME/output-styles/$(printf '%s' "$style_name" | tr '[:upper:] ' '[:lower:]-').md"
      [ -f "$style_file" ] && bytes=$((bytes + $(wc -c < "$style_file" 2>/dev/null || echo 0)))
    fi
  fi
  if [ "$bytes" -eq 0 ]; then
    echo "  non disponibile: nessuna delle fonti (CLAUDE.md, rules/, output style, AGENTS.md) e' leggibile"
    return
  fi
  local tokens=$((bytes / 4))
  echo "  ~$tokens token stimati ($bytes byte / 4)"
  HL_TOK="token fissi a inizio sessione: ~$tokens"
  [ "$tokens" -gt "$T_TOKENS" ] && \
    _propose "token fissi a inizio sessione ~$tokens (soglia $T_TOKENS): kb add \"testo fisso di inizio sessione sopra soglia\" --repo roberdan-os \"il canone sempre caricato (CLAUDE.md + rules + output style + AGENTS.md) scende sotto ${T_TOKENS} token stimati\" \"system-health.sh misura sotto ${T_TOKENS}\""
}

# --- 6) Approvazioni in attesa ---------------------------------------------------
_sec_pending() {
  echo "  fonte: kb pending --count"
  local n rc=0
  n="$(_bounded 30 bash "$KB" pending --count 2>/dev/null)" || rc=$?
  if [ $rc -ne 0 ] || ! [[ "$n" =~ ^[0-9]+$ ]]; then
    echo "  non disponibile: kb pending --count ha fallito"
    return
  fi
  echo "  $n in attesa (kb pending per il dettaglio)"
}

# --- 7) Telemetria del valore (bin/telemetry.sh) --------------------------------
_sec_telemetry() {
  echo "  fonte: bin/telemetry.sh --giorni $DAYS"
  local out rc=0 line
  out="$(_bounded "$TELEMETRY_TIMEOUT" bash "$TELEMETRY_CMD" --giorni "$DAYS" 2>&1)" || rc=$?
  line="$(printf '%s\n' "$out" | sed -E 's/\x1b\[[0-9;]*m//g' | grep -m1 '^  Voci con cambiamenti:')"
  if [ $rc -ne 0 ] || [ -z "$line" ]; then
    echo "  non disponibile: bin/telemetry.sh ha fallito o e' scaduto"
    return
  fi
  printf '%s\n' "$line"
}

# --- assemblaggio ----------------------------------------------------------------
# Corpo scritto DIRETTAMENTE (mai attraverso un pipe/subshell) cosi' le _propose fatte dalle
# sezioni sopra restano visibili qui sotto — un pipe a `tee` costringerebbe il blocco in una
# subshell la cui copia di PROPOSALS morirebbe con lei.
mkdir -p "$REPORTS_DIR" 2>/dev/null || true
DATE_STR="$(date +%Y-%m-%d)"
REPORT_FILE="$REPORTS_DIR/system-health-$DATE_STR.md"
BODY_FILE="$(mktemp "${TMPDIR:-/tmp}/rda-health-body.XXXXXX")"
trap 'rm -f "$BODY_FILE"' EXIT

{
  echo "## Costo (Copilot + Claude Code)"
  _sec_cost
  echo
  echo "## Ricerca gbrain — probe (10 domande fisse, risposta nota)"
  _sec_probe
  echo
  echo "## Coda/embedding gbrain"
  _sec_gbrain_queue
  echo
  echo "## Copie di lavoro (worktree) non rimosse"
  _sec_worktrees
  echo
  echo "## Token fissi a inizio sessione [C]"
  _sec_tokens
  echo
  echo "## Approvazioni in attesa"
  _sec_pending
  echo
  echo "## Telemetria del valore"
  _sec_telemetry
  echo
  echo "## Proposte (da approvare)"
  if [ "${#PROPOSALS[@]}" -eq 0 ]; then
    echo "Nessuna proposta: nessuna soglia documentata e' stata superata."
  else
    for p in "${PROPOSALS[@]}"; do
      echo "- $p"
    done
  fi
} > "$BODY_FILE"

{
  echo "# roberdan-os — salute del sistema ($DATE_STR)"
  echo
  echo "Finestra: ultimi $DAYS giorni. $HL_COST. $HL_PROBE. $HL_TOK. $HL_WT."
  echo "${#PROPOSALS[@]} proposte in attesa di approvazione (dettaglio sotto)."
  echo
  cat "$BODY_FILE"
} | tee "$REPORT_FILE"

echo
echo "system-health: referto scritto in $REPORT_FILE" >&2
exit 0
