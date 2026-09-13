#!/usr/bin/env bash
# kanban/snapshot.sh — raccoglie lo stato del progetto corrente e lo scrive in un file.
#
# Perche' esiste separato dal disegno: il giro completo (git, copie di lavoro, card, agenti,
# controlli automatici, spesa) costa secondi, e una finestrella che si ridisegna ogni due
# secondi non puo' pagarlo. Qui si paga una volta ogni N secondi, in sottofondo; `top.sh`
# legge solo questo file e non lancia mai un comando lento nel ciclo di disegno.
#
# Formato: righe `chiave<TAB>valore`, lette con `while read`. Nessun JSON: niente da
# installare, e un file che si legge a occhio quando qualcosa non torna.
#
# LIMITE DICHIARATO, ed e' il piu' importante: le voci che si possono MISURARE sono misurate;
# dove non c'e' una misura si scrive `-`. Mai una stima plausibile al posto di un dato: il
# cruscotto delle card segue gia' questa regola, e qui vale doppio perche' "quanto manca"
# e' esattamente cio' che verrebbe voglia di inventare.
set -uo pipefail
RDA_HOME="${RDA_HOME:-$HOME/.roberdan-os}"
mkdir -p "$RDA_HOME" 2>/dev/null || true
STORE="${RDA_COPILOT_STORE:-$HOME/.copilot/session-store.db}"

# Il progetto e' quello della cartella da cui si guarda: `kb top` mostra dove stai lavorando,
# non tutto il parco (decisione di Roberto, 2026-09-13: "solo quello in cui sto lavorando").
# Dentro una COPIA DI LAVORO, `--show-toplevel` risponde la copia: il progetto si chiamerebbe
# "260913-140813" e le card, che vivono nel checkout principale, risulterebbero zero. Il
# checkout principale si trova sempre da `--git-common-dir`, che in una copia punta al .git
# vero. Misurato: senza questo, 4 delle 6 sezioni erano vuote e sembravano "tutto a posto".
_common="$(git rev-parse --git-common-dir 2>/dev/null)"
case "$_common" in
  "") REPO_PATH="$(pwd)" ;;
  /*) REPO_PATH="$(dirname "$_common")" ;;
  *)  REPO_PATH="$(cd "$(dirname "$_common")" && pwd)" ;;
esac
REPO="$(basename "$REPO_PATH")"
# La cartella da cui stai guardando: e' questa che finisce in cima alla finestrella, perche'
# sapere di stare in una copia e non nel checkout principale cambia cosa ti aspetti di vedere.
HERE="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
OUT="${1:-$RDA_HOME/top-$REPO.snap}"
TMP="$OUT.tmp.$$"
: > "$TMP"
p() { printf '%s\t%s\n' "$1" "${2:--}" >> "$TMP"; }

p ts "$(date +%s)"
p repo "$REPO"
p repo_path "$REPO_PATH"
p qui "$(basename "$HERE")"

# --- git: ramo e cose non salvate --------------------------------------------------------
p branch "$(git -C "$HERE" rev-parse --abbrev-ref HEAD 2>/dev/null)"
p dirty "$(git -C "$HERE" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
p unpushed "$(git -C "$HERE" log --oneline '@{u}..HEAD' 2>/dev/null | wc -l | tr -d ' ')"

# --- copie di lavoro di QUESTO progetto --------------------------------------------------
# Solo git, mai una chiamata di rete: qui si conta, non si decide cosa togliere (quello e'
# `kb wt`, che puo' permettersi di essere lento perche' lo lanci tu).
WTS="$HOME/GitHub/worktrees/$REPO"
n_wt=0; n_wt_work=0; wt_lines=""
if [ -d "$WTS" ]; then
  for d in "$WTS"/*/; do
    d="${d%/}"; [ -e "$d/.git" ] || continue
    n_wt=$((n_wt+1))
    br="$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null)"
    dty="$(git -C "$d" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    ah="$(git -C "$d" log --oneline "origin/$(git -C "$REPO_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null)..HEAD" 2>/dev/null | wc -l | tr -d ' ')"
    [ "${dty:-0}" -gt 0 ] || [ "${ah:-0}" -gt 0 ] && n_wt_work=$((n_wt_work+1))
    wt_lines="$wt_lines$(basename "$d")|$br|${dty:-0}|${ah:-0}"$'\n'
  done
fi
p worktrees "$n_wt"
p worktrees_con_lavoro "$n_wt_work"
printf '%s' "$wt_lines" | while IFS= read -r l; do [ -n "$l" ] && p wt "$l"; done

# --- card ---------------------------------------------------------------------------------
BOARD="${RDA_KANBAN:-$REPO_PATH/kanban}"
n_doing=0; n_todo=0
if [ -d "$BOARD" ]; then
  for f in "$BOARD"/doing/*.md; do
    [ -f "$f" ] || continue
    grep -q "^repo: $REPO\$" "$f" 2>/dev/null || continue
    n_doing=$((n_doing+1))
    ti="$(grep -m1 '^title:' "$f" 2>/dev/null | cut -d' ' -f2- )"
    st="$(grep -m1 '^started_epoch:' "$f" 2>/dev/null | tr -dc '0-9')"
    p card "$(basename "$f" .md)|${ti:--}|${st:--}"
  done
  for f in "$BOARD"/todo/*.md; do
    [ -f "$f" ] || continue
    grep -q "^repo: $REPO\$" "$f" 2>/dev/null && n_todo=$((n_todo+1))
  done
fi
p card_doing "$n_doing"
p card_todo "$n_todo"

# --- agenti vivi: cosa stanno facendo DAVVERO ---------------------------------------------
# Non si chiede all'agente come va: si legge il registro che il motore scrive comunque. Da li'
# arrivano il passo raggiunto, quanto ha consumato, da quanti secondi non fa nulla e — la cosa
# che Roberto chiedeva ogni volta a voce — l'ULTIMO COMANDO realmente eseguito.
# `agent_id` valorizzato = sotto-agente: compaiono anche quelli, con il loro padre accanto.
# Il filtro sul tempo usa julianday e non un confronto di stringhe: le date qui finiscono con
# la Z e `datetime('now')` no, quindi un `>=` fra stringhe non scarta niente (misurato: davano
# per vive sessioni ferme da due ore e mezza).
AGE_MAX="${RDA_TOP_AGENT_WINDOW:-1800}"   # oltre questo, un agente non e' piu' "vivo"
n_ag=0
if [ -r "$STORE" ] && command -v sqlite3 >/dev/null 2>&1; then
  while IFS='|' read -r sid kind step units age where; do
    [ -n "${sid:-}" ] || continue
    n_ag=$((n_ag+1))
    cmd="$(sqlite3 -separator '|' "$STORE" "select replace(substr(command,1,70),char(10),' ') from forge_trajectory_events where session_id like '$sid%' and event_type='command' order by id desc limit 1" 2>/dev/null)"
    # La sessione che sta guardando e' riconoscibile: l'ambiente la dichiara. Vedere "io"
    # invece di otto caratteri esadecimali evita la domanda "e quello chi e'?".
    case "${COPILOT_AGENT_SESSION_ID:-}" in "$sid"*) kind="io · $kind" ;; esac
    p agent "$sid|$kind|${step:--}|${units:--}|${age:--}|${where:--}|${cmd:--}"
  done <<EOF
$(sqlite3 -separator '|' "$STORE" "
select substr(e.session_id,1,8),
       case when e.agent_id is null then 'principale' else 'sotto-agente' end,
       max(e.turn_index), printf('%.0f',sum(e.total_nano_aiu)/1e9),
       cast((julianday('now')-julianday(max(e.created_at)))*86400 as int),
       replace(replace(coalesce(s.cwd,'?'),'$HOME/GitHub/worktrees/',''),'$HOME/GitHub/','')
from assistant_usage_events e left join sessions s on s.id=e.session_id
where julianday('now')-julianday(e.created_at) < $AGE_MAX/86400.0
  and coalesce(s.cwd,'') like '%$REPO%'
group by e.session_id, e.agent_id order by max(e.created_at) desc limit 8" 2>/dev/null)
EOF
fi
p agenti "$n_ag"

# --- spesa: misurata dal registro del motore, mai stimata ---------------------------------
if [ -r "$STORE" ] && command -v sqlite3 >/dev/null 2>&1; then
  # Unita' onesta: il registro del motore conta in `nano_aiu`, e nessuno qui sa convertirle in
  # euro. Si mostra quindi il NUMERO DI RICHIESTE (un dato che vuol dire una cosa sola) e le
  # unita' grezze, senza simbolo di valuta: un "$" davanti a un numero che non e' un prezzo e'
  # esattamente il tipo di numero plausibile-e-falso che questa finestrella non deve produrre.
  p richieste_oggi "$(sqlite3 "$STORE" "select count(*) from assistant_usage_events where created_at >= date('now')" 2>/dev/null)"
  spesa="$(sqlite3 "$STORE" "select printf('%.0f', sum(total_nano_aiu)/1e9) from assistant_usage_events where created_at >= date('now')" 2>/dev/null)"
  p unita_oggi "${spesa:--}"
  p modello "$(sqlite3 "$STORE" "select model from assistant_usage_events order by id desc limit 1" 2>/dev/null)"
else
  p richieste_oggi "-"; p unita_oggi "-"; p modello "-"
fi

# --- controlli automatici in corso o rossi ------------------------------------------------
# L'unica voce che costa rete. Salta con RDA_TOP_NO_NET=1 (ambienti di prova e CI).
if [ "${RDA_TOP_NO_NET:-0}" != "1" ] && command -v gh >/dev/null 2>&1; then
  while IFS='|' read -r st cc nm; do
    [ -n "${nm:-}" ] && p ci "${st:--}|${cc:--}|$nm"
  done <<EOF
$(cd "$REPO_PATH" && gh run list --limit 3 --json status,conclusion,displayTitle -q '.[] | .status + "|" + (.conclusion // "-") + "|" + (.displayTitle|.[0:28])' 2>/dev/null)
EOF
fi

# --- messaggi fra agenti non letti ---------------------------------------------------------
if [ -f "$REPO_PATH/bus/bus.sh" ]; then
  # `bus count` non stampa niente quando non c'e' niente: un campo vuoto qui diventerebbe "-",
  # cioe' "non lo so", che e' una cosa diversa da "zero". Silenzio con esito buono = zero.
  _b="$(bash "$REPO_PATH/bus/bus.sh" count --repo "$REPO" 2>/dev/null | tr -dc '0-9')"
  p bus "${_b:-0}"
else
  p bus "-"
fi

# --- i pezzi della richiesta di Roberto ----------------------------------------------------
# Scritti dall'agente con `kb ask`, non indovinati qui: questa sezione esiste perche' lui
# vedesse da solo quando un pezzo viene dimenticato, e un file che l'agente non ha aggiornato
# deve restare VUOTO invece di inventarsi un elenco plausibile.
ASK="$RDA_HOME/ask-$REPO.txt"
if [ -f "$ASK" ]; then
  while IFS= read -r l; do [ -n "$l" ] && p ask "$l"; done < "$ASK"
fi

mv -f "$TMP" "$OUT" 2>/dev/null || { rm -f "$TMP"; exit 1; }
[ "${RDA_TOP_QUIET:-0}" = "1" ] || echo "$OUT"
