#!/usr/bin/env bash
# bin/telemetry.sh — quanto vale davvero ogni pezzo di questo sistema.
#
# LA DOMANDA, nelle parole di Roberto (2026-09-23): "voglio un sistema di
# telemetria che permetta di valutare il valore di queste singole funzionalita'
# anche capendo se stiamo usando bene questi strumenti o se sono poco usati e
# perche'".
#
# COSA NON FA, ed e' la scelta di progetto piu' importante: NON RACCOGLIE NIENTE.
# Non c'e' nessun nuovo file di eventi, nessun contatore da tenere aggiornato,
# nessun hook che scrive a ogni turno. Un secondo archivio di misure diverge da
# cio' che misura, e quello che diverge e' sempre quello che nessuno legge finche'
# non sbaglia. Qui si LEGGE cio' che esiste gia':
#
#   - l'ARTEFATTO della funzionalita' stessa, dove ne ha uno. Il bus e' un
#     registro append-only: i suoi messaggi SONO la sua telemetria, esatti, senza
#     campionamento e senza un collezionista che possa perdere un evento.
#   - lo STORICO DELLE SESSIONI che l'ospite scrive comunque
#     (~/.copilot/session-store.db, ~/.claude/history.jsonl): li' si vede cosa e'
#     stato davvero digitato, per le funzionalita' che non lasciano traccia.
#
# LE DUE FONTI NON SI SOMMANO MAI in un numero solo, e ogni riga dice da dove
# viene. Un conteggio esatto preso dal registro di un componente e una ricerca di
# testo nello storico non sono la stessa qualita' di prova, e presentarli come un
# unico numero e' la stessa bugia che questo sistema rifiuta altrove quando
# stampa la presenza dichiarata accanto a quella osservata invece che al posto.
#
# IL DENOMINATORE, che e' la parte che di solito manca. "Usato 20 volte" non dice
# niente: venti volte su quante in cui sarebbe servito? Per un canale fra agenti
# l'occasione e' misurabile — due sessioni sullo stesso progetto nello stesso
# momento — e il rapporto fra le due cifre e' l'unica che risponda alla domanda.
# Misurato la prima volta che questo comando e' esistito: 44 coppie di sessioni
# sovrapposte in 30 giorni, il canale usato in 1 sessione su 94.
#
# PRIVACY. Si contano righe, mai se ne stampa il contenuto. Lo storico delle
# sessioni contiene le conversazioni di Roberto per intero: questo comando puo'
# dire QUANTE volte una parola compare e non ha nessun modo di mostrare la riga
# in cui compare. Stessa regola del campanello del bus, per la stessa ragione.
#
# LIMITE DICHIARATO, e non e' piccolo: cercare un comando nel testo di una
# sessione dice che e' stato SCRITTO, non che sia servito a qualcosa. Nessuna
# delle cifre qui dentro misura il VALORE; misurano l'uso e l'occasione, che sono
# le due cose senza le quali il valore non si puo' nemmeno discutere.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RDA_HOME="${RDA_HOME:-$HOME/.roberdan-os}"
BUS_HOME="${RDA_BUS_HOME:-$RDA_HOME/bus}"
STORE="${RDA_SESSION_STORE:-$HOME/.copilot/session-store.db}"
CLAUDE_HISTORY="${RDA_CLAUDE_HISTORY:-$HOME/.claude/history.jsonl}"
GIORNI="${RDA_TELEMETRY_DAYS:-30}"
WRITE=0
FINDINGS="$ROOT/docs/findings.md"

while [ $# -gt 0 ]; do
  case "$1" in
    --write)  WRITE=1; shift;;
    --giorni|--days) GIORNI="$2"; shift 2;;
    -h|--help)
      cat <<'USAGE'
telemetry — quanto si usa ogni pezzo, su quante occasioni, e chi sa che esiste.

  bin/telemetry.sh [--giorni N] [--write]

  --giorni N   finestra di osservazione (default 30)
  --write      aggiunge il referto datato a docs/findings.md

Non raccoglie niente: legge gli artefatti che esistono gia' (il registro del bus)
e lo storico che l'ospite scrive comunque. Conta righe, non ne stampa mai il
contenuto. Dice da dove viene ogni cifra, e non somma mai fonti di qualita'
diversa in un numero solo.
USAGE
      exit 0;;
    *) echo "telemetry: argomento sconosciuto '$1'" >&2; exit 1;;
  esac
done

_hr() { printf '\n\033[1m%s\033[0m\n' "$1"; }
_riga() { printf '  %-14s %s\n' "$1" "$2"; }

_sql() {  # una query sullo storico delle sessioni, o niente se non c'e'
  [ -r "$STORE" ] || return 1
  command -v sqlite3 >/dev/null 2>&1 || return 1
  sqlite3 -noheader "$STORE" "$1" 2>/dev/null
}

# Quante SESSIONI hanno scritto questo testo, e quante volte. Il conteggio e' per
# sessione e non per riga: dieci comandi nella stessa sessione sono un uso, non
# dieci — la domanda e' "quante volte qualcuno se n'e' ricordato".
_uso_storico() {
  local pattern="$1"
  _sql "SELECT count(DISTINCT session_id) || ' sessioni · ' || count(*) || ' turni'
        FROM turns
        WHERE (assistant_response LIKE '%$pattern%' OR user_message LIKE '%$pattern%')
          AND substr(timestamp,1,10) >= date('now','-$GIORNI days');"
}

_ultimo_storico() {
  local pattern="$1"
  _sql "SELECT substr(max(timestamp),1,10) FROM turns
        WHERE (assistant_response LIKE '%$pattern%' OR user_message LIKE '%$pattern%');"
}

echo "TELEMETRIA — finestra: ultimi $GIORNI giorni"
echo "Nessuna raccolta: si legge cio' che esiste gia'. Ogni riga dice da dove viene."

# --- 1) USO, dall'artefatto della funzionalita' stessa -----------------------
# Esatto: il registro del bus e' append-only e non campiona niente.
_hr "1. Uso — misurato sull'artefatto della funzionalita' (esatto)"
if [ -d "$BUS_HOME" ]; then
  msg=0; thread=0; repo=0; mittenti=""
  for d in "$BUS_HOME"/*/; do
    [ -d "$d" ] || continue
    repo=$((repo + 1))
    for f in "$d"*.jsonl; do
      [ -e "$f" ] && [ -s "$f" ] || continue
      thread=$((thread + 1))
      msg=$((msg + $(grep -c . "$f" 2>/dev/null || echo 0)))
      mittenti="$mittenti $(grep -o '"from":"[^"]*"' "$f" 2>/dev/null | sort -u | tr '\n' ' ')"
    done
  done
  ruoli_unici="$(printf '%s' "$mittenti" | tr ' ' '\n' | sort -u | grep -c . | tr -d ' ')"
  presenze=0
  for p in "$BUS_HOME"/*/.presence.jsonl; do
    [ -e "$p" ] || continue
    presenze=$((presenze + $(grep -c '"event":"hello"' "$p" 2>/dev/null || echo 0)))
  done
  # DALL'INIZIO e NELLA FINESTRA, separati. Il registro non dimentica, quindi il
  # totale storico non dice niente su oggi: le due cifre insieme distinguono un
  # canale vivo da un archivio, e una sola delle due non lo fa.
  taglio="$(date -u -v-"${GIORNI}"d +%Y-%m-%d 2>/dev/null || date -u -d "-${GIORNI} days" +%Y-%m-%d 2>/dev/null || echo 0000-00-00)"
  recenti=0
  for d in "$BUS_HOME"/*/; do
    [ -d "$d" ] || continue
    for f in "$d"*.jsonl; do
      [ -e "$f" ] && [ -s "$f" ] || continue
      recenti=$((recenti + $(grep -o '"ts":"[0-9-]\{10\}' "$f" 2>/dev/null | sed 's/.*"//' | awk -v t="$taglio" '$1 >= t' | wc -l | tr -d ' ')))
    done
  done
  _riga "bus" "$msg messaggi in tutto · $recenti negli ultimi $GIORNI giorni"
  _riga "" "$thread conversazioni · $repo progetti · $ruoli_unici ruoli diversi hanno scritto"
  _riga "" "$presenze presentazioni registrate (bus hello)"
else
  _riga "bus" "nessun registro: mai usato su questa macchina"
fi
n_evolve="$(ls "$RDA_HOME/evolve" 2>/dev/null | wc -l | tr -d ' ')"
_riga "evolve" "$n_evolve referti prodotti"

# --- 2) USO, dallo storico delle sessioni ------------------------------------
# Approssimato: dice che e' stato SCRITTO, non che sia servito.
_hr "2. Uso — cercato nello storico delle sessioni (approssimato: dice che e' stato scritto)"
if [ -r "$STORE" ] && command -v sqlite3 >/dev/null 2>&1; then
  for coppia in "jev|jev.py" "twin|roberdan-twin" "kb checkup|kb checkup" "premortem|premortem" "focus-group|focus-group" "bus|bus.sh"; do
    nome="${coppia%%|*}"; pat="${coppia##*|}"
    u="$(_uso_storico "$pat")"
    ult="$(_ultimo_storico "$pat")"
    _riga "$nome" "${u:-0 sessioni · 0 turni}${ult:+ · ultimo: $ult}"
  done
else
  _riga "(storico)" "non leggibile in $STORE — questa sezione non ha dati, e non li inventa"
fi
if [ -r "$CLAUDE_HISTORY" ]; then
  _riga "(claude)" "$(wc -l < "$CLAUDE_HISTORY" 2>/dev/null | tr -d ' ') righe di storico presenti, non analizzate qui"
fi

# --- 3) OCCASIONI: quante volte sarebbe servito ------------------------------
# LA PARTE CHE DI SOLITO MANCA. "Usato 20 volte" non risponde a niente finche'
# non si sa su quante occasioni. Per un canale fra agenti l'occasione e'
# misurabile: due sessioni sullo stesso progetto nello stesso momento.
_hr "3. Occasioni — quante volte due sessioni hanno lavorato insieme allo stesso progetto"
if [ -r "$STORE" ] && command -v sqlite3 >/dev/null 2>&1; then
  occ="$(_sql "
    WITH s AS (SELECT id, repository, created_at, updated_at FROM sessions
               WHERE repository IS NOT NULL AND substr(created_at,1,10) >= date('now','-$GIORNI days'))
    SELECT a.repository || '|' || count(*)
    FROM s a JOIN s b ON a.repository = b.repository AND a.id <> b.id
         AND a.created_at < b.updated_at AND b.created_at < a.updated_at
    GROUP BY a.repository ORDER BY count(*) DESC;")"
  if [ -n "$occ" ]; then
    tot=0
    while IFS='|' read -r r n; do
      [ -n "$r" ] || continue
      tot=$((tot + n))
      _riga "${r##*/}" "$n coppie sovrapposte"
    done <<< "$occ"
    usate="$(_sql "SELECT count(DISTINCT session_id) FROM turns
                   WHERE assistant_response LIKE '%bus.sh%'
                     AND substr(timestamp,1,10) >= date('now','-$GIORNI days');")"
    echo
    _riga "RAPPORTO" "$tot occasioni di lavoro in parallelo · il canale e' comparso in ${usate:-0} sessioni"
  else
    _riga "(nessuna)" "nessuna sovrapposizione nella finestra: il canale non aveva occasioni"
  fi
else
  _riga "(storico)" "non leggibile: il denominatore non e' calcolabile, e non si stima"
fi

# --- 4) COPERTURA: chi sa che la funzionalita' esiste ------------------------
# Un ipotesi sul perche', non una misura del perche'. Se nessun file la nomina,
# nessuno puo' ricordarsene: e' la causa candidata piu' economica da escludere.
_hr "4. Copertura — quanti agenti e skill spiegano come si usa"
# Il modello cerca un uso CONCRETO, non la parola. "bus" compare dentro
# "business" e "busy": contarle direbbe che quattro skill spiegano il canale
# mentre nessuna lo nomina. Una misura di copertura che si lascia ingannare da
# una sottostringa e' peggio di nessuna misura, perche' rassicura.
#
# E i conteggi passano da wc, non da `grep -c . || echo 0`: grep esce 1 quando
# non trova niente, quindi quella forma stampava lo zero di grep E lo zero del
# fallback, e la riga diventava "agenti 0\n0/9". Un contatore che sbaglia a zero
# sbaglia esattamente nel caso che interessa.
# LE SKILL CHE COORDINANO PIU' AGENTI, dichiarate qui e in un posto solo. Sedici
# skill su sedici NON e' il denominatore giusto per un canale fra agenti: una
# skill che dirige un video non ha nessuno con cui parlare, e pretendere che lo
# spieghi lo stesso produce righe che la gente impara a saltare — cioe' lo stesso
# danno del campanello che suonava per posta di nessuno. Il referto stampa
# ENTRAMBI i denominatori, cosi' il numero non si puo' aggiustare scegliendo
# quello comodo.
SKILL_COORD="review ship verify-done long-running-jobs auto-checkpoint"

_copertura() {
  local nome="$1" pat="$2" na ns ta ts nc tc k
  ta="$(ls "$ROOT"/agents/*.md 2>/dev/null | wc -l | tr -d " ")"
  ts="$(ls -d "$ROOT"/skills/*/ 2>/dev/null | wc -l | tr -d " ")"
  na="$(grep -rlE "$pat" "$ROOT"/agents/*.md 2>/dev/null | wc -l | tr -d " ")"
  ns="$(grep -rlE "$pat" "$ROOT"/skills/*/skill.md 2>/dev/null | wc -l | tr -d " ")"
  nc=0; tc=0
  for k in $SKILL_COORD; do
    [ -f "$ROOT/skills/$k/skill.md" ] || continue
    tc=$((tc + 1))
    grep -qE "$pat" "$ROOT/skills/$k/skill.md" 2>/dev/null && nc=$((nc + 1))
  done
  local canone="no"
  grep -qE "$pat" "$ROOT/AGENTS.md" 2>/dev/null && canone="si"
  _riga "$nome" "agenti $na/$ta · skill $ns/$ts (di cui quelle che coordinano: $nc/$tc) · canone: $canone"
}
_copertura "bus"  'bus (hello|read|send|owed|who|tidy)|bus/bus[.]sh'
_copertura "jev"  'bin/jev[.]py|jev evaluate|skills/jev'
_copertura "twin" 'roberdan-twin|@twin'

# --- 5) VERDETTO -------------------------------------------------------------
# Dice cosa e' vero, e si ferma prima del perche'. Il perche' non e' misurato qui
# e affermarlo lo stesso sarebbe la stessa cosa che questo file rifiuta: una
# dichiarazione presentata come evidenza.
_hr "5. Cosa si puo' dire, e dove ci si ferma"
echo "  Questo referto misura USO e OCCASIONI. Non misura il valore, e non sa perche'"
echo "  qualcosa non viene usato: la copertura qui sopra e' una causa CANDIDATA, la piu'"
echo "  economica da escludere, non una spiegazione. Una funzionalita' ben documentata e"
echo "  mai usata su molte occasioni e' un'altra storia, e va guardata da vicino."

if [ "$WRITE" = "1" ]; then
  {
    printf '\n### %s — telemetria del valore (generata da bin/telemetry.sh)\n\n' "$(date +%Y-%m-%d)"
    printf 'Finestra: ultimi %s giorni. Nessuna raccolta: letto dagli artefatti esistenti e\n' "$GIORNI"
    printf 'dallo storico delle sessioni. Le due fonti non si sommano.\n\n```\n'
    RDA_TELEMETRY_DAYS="$GIORNI" bash "$0" --giorni "$GIORNI" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g'
    printf '```\n'
  } >> "$FINDINGS"
  echo
  echo "referto aggiunto a docs/findings.md"
fi
