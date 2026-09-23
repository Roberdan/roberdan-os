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
# Le occasioni sono coppie uniche di sessioni sovrapposte sullo stesso progetto.
# Le menzioni sono sessioni/turni: unita' diverse, non un rapporto di utilizzo.
#
# PRIVACY. Si contano righe, mai se ne stampa il contenuto. Lo storico delle
# sessioni contiene le conversazioni di Roberto per intero: questo comando puo'
# dire QUANTE volte una parola compare, mai mostrare righe, nomi di progetti
# o percorsi locali. Stessa regola del campanello del bus, per la stessa ragione.
#
# LIMITE DICHIARATO, e non e' piccolo: cercare un comando nel testo di una
# sessione dice che e' stato SCRITTO, non che sia servito a qualcosa. Nessuna
# delle cifre qui dentro misura il VALORE; misurano l'uso e l'occasione, che sono
# le due cose senza le quali il valore non si puo' nemmeno discutere.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RDA_HOME="${RDA_HOME:-$HOME/.roberdan-os}"
BUS_HOME="${RDA_BUS_HOME:-$RDA_HOME/bus}"
STORE="${RDA_SESSION_STORE:-$HOME/.copilot/session-store.db}"
CLAUDE_HISTORY="${RDA_CLAUDE_HISTORY:-$HOME/.claude/history.jsonl}"
GIORNI="${RDA_TELEMETRY_DAYS-30}"
WRITE=0
FINDINGS="${RDA_TELEMETRY_FINDINGS-$ROOT/docs/findings.md}"
_fail() { echo "telemetry: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --write)  WRITE=1; shift;;
    --giorni|--days)
      [ $# -ge 2 ] || _fail "--giorni/--days richiede un numero di giorni"
      GIORNI="$2"; shift 2;;
    -h|--help)
      cat <<'USAGE'
telemetry — quanto si usa ogni pezzo, su quante occasioni, e chi sa che esiste.

  bin/telemetry.sh [--giorni N] [--write]

  --giorni N   finestra di osservazione, 1..999999 giorni (default 30; alias --days)
  --write      aggiunge il referto datato a docs/findings.md
               RDA_TELEMETRY_FINDINGS cambia il file di destinazione

Non raccoglie niente: legge gli artefatti che esistono gia' (il registro del bus)
e lo storico che l'ospite scrive comunque. Conta righe, non ne stampa mai il
contenuto. Dice da dove viene ogni cifra, e non somma mai fonti di qualita'
diversa in un numero solo.
USAGE
      exit 0;;
    *) _fail "argomento sconosciuto";;
  esac
done
[[ "$GIORNI" =~ ^[0-9]{1,6}$ ]] && [ "$((10#$GIORNI))" -gt 0 ] \
  || _fail "--giorni/--days: giorni non validi (intero da 1 a 999999)"
GIORNI=$((10#$GIORNI))

_hr() { printf '\n\033[1m%s\033[0m\n' "$1"; }
_riga() { printf '  %-14s %s\n' "$1" "$2"; }
_grep() {
  local rc=0
  grep "$@" 2>/dev/null || rc=$?
  [ "$rc" -le 1 ] || _fail "registro o copertura non disponibile: lettura fallita"
}

_sql() {
  # SQLite puo' includere dati nell'errore: segnala il fallimento, non quel testo.
  sqlite3 -readonly -batch -noheader "$STORE" "$1" 2>/dev/null \
    || _fail "storico non disponibile: lettura SQLite fallita (database o schema)"
}

# Conta menzioni testuali per sessione e per turno, non esecuzioni di comandi.
_uso_storico() {
  local pattern="$1"
  _sql "SELECT count(DISTINCT session_id) || ' sessioni · ' || count(*) || ' turni'
        FROM turns
        WHERE (assistant_response LIKE '%$pattern%' OR user_message LIKE '%$pattern%')
          AND julianday(timestamp) >= julianday(date('now','-$GIORNI days'))
          AND julianday(timestamp) <= julianday('now');"
}

_ultimo_storico() {
  local pattern="$1"
  _sql "SELECT date(max(julianday(timestamp))) FROM turns
        WHERE (assistant_response LIKE '%$pattern%' OR user_message LIKE '%$pattern%');"
}

_report() {
storico=0
if [ -e "$STORE" ]; then
  [ -f "$STORE" ] && [ -r "$STORE" ] || _fail "storico non disponibile: file non leggibile"
  if command -v sqlite3 >/dev/null 2>&1; then
    invalidi="$(_sql "SELECT
      (SELECT count(*) FROM sessions WHERE julianday(created_at) IS NULL
        OR julianday(updated_at) IS NULL OR julianday(updated_at) < julianday(created_at))
      + (SELECT count(*) FROM turns WHERE julianday(timestamp) IS NULL);")"
    [ "$invalidi" = 0 ] || _fail "storico non disponibile: date mancanti, non valide o intervalli invertiti"
    storico=1
  fi
fi
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
      n="$(_grep -c . "$f")"; msg=$((msg + n))
      mittenti="$mittenti $(_grep -o '"from":"[^"]*"' "$f" | sort -u | tr '\n' ' ')"
    done
  done
  ruoli_unici="$(printf '%s' "$mittenti" | tr ' ' '\n' | sort -u | _grep -c . | tr -d ' ')"
  presenze=0
  for p in "$BUS_HOME"/*/.presence.jsonl; do
    [ -e "$p" ] || continue
    n="$(_grep -c '"event":"hello"' "$p")"; presenze=$((presenze + n))
  done
  # DALL'INIZIO e NELLA FINESTRA, separati. Il registro non dimentica, quindi il
  # totale storico non dice niente su oggi: le due cifre insieme distinguono un
  # canale vivo da un archivio, e una sola delle due non lo fa.
  taglio="$(date -u -v-"${GIORNI}"d +%Y-%m-%d 2>/dev/null || date -u -d "-${GIORNI} days" +%Y-%m-%d)"
  recenti=0
  for d in "$BUS_HOME"/*/; do
    [ -d "$d" ] || continue
    for f in "$d"*.jsonl; do
      [ -e "$f" ] && [ -s "$f" ] || continue
      n="$(_grep -o '"ts":"[0-9-]\{10\}' "$f" | sed 's/.*"//' | awk -v t="$taglio" '$1 >= t' | wc -l | tr -d ' ')"
      recenti=$((recenti + n))
    done
  done
  _riga "bus" "$msg messaggi in tutto · $recenti negli ultimi $GIORNI giorni"
  _riga "" "$thread conversazioni · $repo progetti · $ruoli_unici ruoli diversi hanno scritto"
  _riga "" "$presenze presentazioni registrate (bus hello)"
else
  [ ! -e "$BUS_HOME" ] || _fail "bus non disponibile: il registro non e' una directory"
  _riga "bus" "non disponibile: nessun registro"
fi
if [ -d "$RDA_HOME/evolve" ]; then
  n_evolve="$(ls "$RDA_HOME/evolve" 2>/dev/null | wc -l | tr -d ' ')"
  _riga "evolve" "$n_evolve referti prodotti"
else
  [ ! -e "$RDA_HOME/evolve" ] || _fail "evolve non disponibile: archivio non leggibile"
  _riga "evolve" "non disponibile: nessun archivio"
fi

# --- 2) USO, dallo storico delle sessioni ------------------------------------
# Approssimato: dice che e' stato SCRITTO, non che sia servito.
_hr "2. Uso — cercato nello storico delle sessioni (approssimato: menzioni testuali, non invocazioni)"
if [ "$storico" = 1 ]; then
  for coppia in "jev|jev.py" "twin|roberdan-twin" "kb checkup|kb checkup" "premortem|premortem" "focus-group|focus-group" "bus|bus.sh"; do
    nome="${coppia%%|*}"; pat="${coppia##*|}"
    u="$(_uso_storico "$pat")"
    ult="$(_ultimo_storico "$pat")"
    _riga "$nome" "$u${ult:+ · ultimo: $ult}"
  done
else
  _riga "(storico)" "non disponibile: database assente o sqlite3 non installato"
fi
if [ -e "$CLAUDE_HISTORY" ]; then
  [ -f "$CLAUDE_HISTORY" ] && [ -r "$CLAUDE_HISTORY" ] || _fail "storico Claude non disponibile: file non leggibile"
  n="$( (wc -l < "$CLAUDE_HISTORY") 2>/dev/null | tr -d ' ')"
  _riga "(claude)" "$n righe di storico presenti, non analizzate qui"
fi

# --- 3) OCCASIONI: quante volte sarebbe servito ------------------------------
# LA PARTE CHE DI SOLITO MANCA. "Usato 20 volte" non risponde a niente finche'
# non si sa su quante occasioni. Per un canale fra agenti l'occasione e'
# misurabile: due sessioni sullo stesso progetto nello stesso momento.
_hr "3. Occasioni — quante volte due sessioni hanno lavorato insieme allo stesso progetto"
if [ "$storico" = 1 ]; then
  occ="$(_sql "
    WITH s AS (SELECT id, repository, julianday(created_at) AS start, julianday(updated_at) AS end
               FROM sessions WHERE repository IS NOT NULL
                 AND julianday(updated_at) > julianday(date('now','-$GIORNI days'))
                 AND julianday(created_at) < julianday('now')
                 AND julianday(updated_at) > julianday(created_at))
    SELECT count(*) || '|' || count(DISTINCT a.repository)
    FROM s a JOIN s b ON a.repository = b.repository AND a.id < b.id
         AND a.start < b.end AND b.start < a.end;")"
  IFS='|' read -r tot progetti <<< "$occ"
  if [ "$tot" -gt 0 ]; then
    _riga "TOTALE" "$tot coppie sovrapposte su $progetti progetti"
    _riga "(limite)" "le menzioni non misurano l'uso del canale fra le coppie"
  else
    _riga "(nessuna)" "nessuna sovrapposizione osservata nello storico nella finestra"
  fi
else
  _riga "(storico)" "non disponibile: le occasioni non sono calcolabili, e non si stimano"
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
  na="$(_grep -rlE "$pat" "$ROOT"/agents/*.md | wc -l | tr -d " ")"
  ns="$(_grep -rlE "$pat" "$ROOT"/skills/*/skill.md | wc -l | tr -d " ")"
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
}

REPORT="$(set -eE; trap '_fail "referto non disponibile: errore durante la lettura delle fonti"' ERR; _report)"
printf '%s\n' "$REPORT"

if [ "$WRITE" = "1" ]; then
  stamp="$(date +%Y-%m-%d)"
  plain="$(printf '%s\n' "$REPORT" | sed $'s/\033\\[[0-9;]*m//g')"
  if ! {
    printf '\n### %s — telemetria del valore (generata da bin/telemetry.sh)\n\n%s\n%s\n\n```\n%s\n```\n' \
      "$stamp" "Finestra: ultimi $GIORNI giorni. Nessuna raccolta: letto dagli artefatti esistenti e" \
      "dallo storico delle sessioni. Le due fonti non si sommano." "$plain" >> "$FINDINGS"
  } 2>/dev/null; then _fail "scrittura del referto fallita"; fi
  echo
  if [ "$FINDINGS" = "$ROOT/docs/findings.md" ]; then
    echo "referto aggiunto a docs/findings.md"
  else
    echo "referto aggiunto alla destinazione configurata"
  fi
fi
