#!/usr/bin/env bash
# test-telemetry.sh — il referto sul valore misura, non stima, e non spia.
#
# PERCHE' QUESTE TRE PROPRIETA' E NON ALTRE. Un lettore di telemetria e' il posto
# dove e' piu' facile mentire senza accorgersene: basta un contatore che sbaglia a
# zero, una fonte incerta presentata come esatta, o una riga di conversazione che
# finisce nel referto. Tutte e tre sono gia' successe qui mentre lo scrivevo —
# il conteggio "agenti 0\n0/9" e' durato tre esecuzioni.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$ROOT/bin/telemetry.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== telemetria: misura, non stima, e non spia =="

[ -x "$T" ] || fail "bin/telemetry.sh non e' eseguibile"
out="$(RDA_BUS_HOME="$TMP/vuoto" bash "$T" 2>&1)" || fail "il referto esce non-zero su un sistema senza dati"

# 1. NESSUN CONTATORE ROTTO A ZERO. `grep -c . || echo 0` stampa DUE zeri quando
#    non trova niente, perche' grep esce 1: la riga diventava "agenti 0\n0/9".
#    Un contatore che sbaglia proprio a zero sbaglia nel caso che interessa —
#    "questa cosa non la usa nessuno" e' la risposta che si sta cercando.
grep -qE '^[0-9]+/[0-9]+' <<<"$out" \
  && fail "una cifra e' finita a capo: c'e' un contatore che stampa due valori"
grep -qE 'agenti [0-9]+/[0-9]+ · skill [0-9]+/[0-9]+' <<<"$out" \
  || fail "la copertura non e' nella forma attesa: $(grep -m1 agenti <<<"$out")"
ok "nessun contatore stampa due valori quando il conto e' zero"

# 2. LE DUE FONTI RESTANO SEPARATE. Un conteggio esatto preso dal registro di un
#    componente e una ricerca di testo nello storico non sono la stessa prova, e
#    sommarli in una cifra sola e' la bugia che questo sistema rifiuta altrove.
grep -q "misurato sull'artefatto" <<<"$out" || fail "manca la sezione della fonte esatta"
grep -q "cercato nello storico"   <<<"$out" || fail "manca la sezione della fonte approssimata"
grep -q "approssimato"            <<<"$out" || fail "la fonte incerta non si dichiara tale"
ok "la fonte esatta e quella approssimata sono dichiarate e separate"

# 3. IL DENOMINATORE C'E'. "Usato 20 volte" non risponde a niente finche' non si
#    sa su quante occasioni: e' l'unica cifra che distingue uno strumento inutile
#    da uno che nessuno sa di avere.
grep -qi "occasioni" <<<"$out" || fail "il referto non dice su quante occasioni"
ok "il referto porta il denominatore, non solo il numero di usi"

# 4. NON SI FINGE DI SAPERE IL PERCHE'. La copertura e' una causa candidata, e il
#    referto deve dirlo: presentarla come spiegazione sarebbe una dichiarazione
#    spacciata per evidenza.
grep -qi "non sa perche'\|causa CANDIDATA" <<<"$out" \
  || fail "il referto non dichiara di non sapere il perche': allora lo sta insinuando"
ok "dichiara cosa misura e dove si ferma"

# 5. NON SPIA. Lo storico contiene le conversazioni per intero. Il referto puo'
#    dire QUANTE volte una parola compare e non deve avere modo di mostrare la
#    riga in cui compare — stessa regola del campanello del bus.
if grep -nE "SELECT[^;]*(user_message|assistant_response)[^;]*FROM turns" "$T" \
   | grep -vE "count\(|LIKE" >/dev/null 2>&1; then
  fail "una query legge il testo delle conversazioni invece di contarlo"
fi
grep -q "substr(max(timestamp)" "$T" || true   # le date sono ammesse: non sono contenuto
ok "dallo storico si contano righe e si leggono date, mai testo di conversazione"

# 6. --write AGGIUNGE, NON RISCRIVE. Il referto va in coda a un file che contiene
#    il lavoro di mesi: un lettore che lo sovrascrivesse sarebbe la cosa peggiore
#    che possa fare uno strumento di sola lettura.
cp "$ROOT/docs/findings.md" "$TMP/prima.md"
righe_prima="$(wc -l < "$TMP/prima.md" | tr -d ' ')"
ok "findings.md contiene $righe_prima righe prima della prova (non viene toccato qui)"
grep -q '>> "\$FINDINGS"' "$T" || fail "--write non aggiunge in coda: potrebbe sovrascrivere findings.md"
# Il modello deve escludere `>>`, che CONTIENE `>`: la prima versione di questa
# riga accusava l'aggiunta in coda di essere un troncamento, cioe' falliva sul
# comportamento corretto. Un controllo che si sbaglia da solo e' rumore.
grep -qE '[^>]> *"\$FINDINGS"' "$T" && fail "c'e' una scrittura che TRONCA findings.md"
ok "--write puo' solo aggiungere in coda, mai troncare"

echo "PASS: test-telemetry.sh"
