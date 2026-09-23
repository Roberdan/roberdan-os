#!/usr/bin/env bash
# test-telemetry.sh — il referto sul valore misura, non stima, e non spia.
#
# PERCHE' QUESTE TRE PROPRIETA' E NON ALTRE. Un lettore di telemetria e' il posto
# dove e' piu' facile mentire senza accorgersene: basta un contatore che sbaglia a
# zero, una fonte incerta presentata come esatta, o una riga di conversazione che
# finisce nel referto. Tutte e tre sono gia' successe qui mentre lo scrivevo —
# il conteggio "agenti 0\n0/9" e' durato tre esecuzioni.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo/bin" "$TMP/repo/docs" "$TMP/tools"
cp "$ROOT/bin/telemetry.sh" "$TMP/repo/bin/"
cp -R "$ROOT/agents" "$ROOT/skills" "$TMP/repo/"
cp "$ROOT/AGENTS.md" "$TMP/repo/"
T="$TMP/repo/bin/telemetry.sh"
export RDA_HOME="$TMP/home" RDA_BUS_HOME="$TMP/bus"
export RDA_SESSION_STORE="$TMP/store.db" RDA_CLAUDE_HISTORY="$TMP/history.jsonl"
export RDA_TELEMETRY_DAYS=30
unset RDA_TELEMETRY_FINDINGS
export TELEMETRY_SQLITE
TELEMETRY_SQLITE="$(command -v sqlite3)"
export TELEMETRY_CALLS="$TMP/calls"
cat > "$TMP/tools/sqlite3" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
args=()
now="'now'"; clock="'2026-09-23 12:00:00'"
for arg in "$@"; do
  args+=("${arg//$now/$clock}")
done
printf 'query\n' >> "$TELEMETRY_CALLS"
if [ "${TELEMETRY_FAIL_QUERY:-0}" = 1 ] && [[ "${args[*]}" == *"FROM s a JOIN"* ]]; then
  echo "PRIVATE_SQL_ERROR" >&2
  exit 1
fi
exec "$TELEMETRY_SQLITE" "${args[@]}"
SH
cat > "$TMP/tools/date" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *-v-30d*|*"-30 days"*) echo 2026-08-24;;
  *+%Y-%m-%d*) echo 2026-09-23;;
  *) echo "unexpected fixture date arguments" >&2; exit 1;;
esac
SH
chmod +x "$TMP/tools/sqlite3" "$TMP/tools/date"
export PATH="$TMP/tools:$PATH"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }
has()  { grep -qE "$1" <<< "$out" || fail "$2"; }

echo "== telemetria: misura, non stima, e non spia =="

[ -x "$T" ] || fail "bin/telemetry.sh non e' eseguibile"
out="$(bash "$T" 2>&1)" || fail "il referto esce non-zero su un sistema senza dati"
has 'non disponibile' "lo storico assente non e' dichiarato indisponibile"
[ ! -e "$RDA_SESSION_STORE" ] || fail "la lettura ha creato uno storico assente"
grep -q '0 sessioni\|nessuna sovrapposizione' <<< "$out" \
  && fail "lo storico assente e' presentato come zero"
ok "fonti assenti dichiarate indisponibili, senza creare database o inventare zeri"

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
ok "dallo storico si contano righe e si leggono date, mai testo di conversazione"

mkdir -p "$RDA_BUS_HOME/fixture"
: > "$RDA_BUS_HOME/fixture/empty.jsonl"
: > "$RDA_BUS_HOME/fixture/.presence.jsonl"
out="$(bash "$T" 2>&1)" || fail "registro vuoto non leggibile"
has '0 messaggi in tutto · 0 negli ultimi 30 giorni' "conteggio del registro vuoto errato"
has '0 presentazioni registrate' "presenze vuote non valgono zero"
printf '%s\n' '{"event":"bye","session":"PRIVATE_SESSION"}' > "$RDA_BUS_HOME/fixture/.presence.jsonl"
out="$(bash "$T" 2>&1)" || fail "registro di sole uscite non leggibile"
has '0 presentazioni registrate' "una uscita e' contata come presentazione"
printf '%s\n' '{"event":"hello","session":"PRIVATE_SESSION"}' >> "$RDA_BUS_HOME/fixture/.presence.jsonl"
printf '%s\n' '{"ts":"2026-09-22T09:00:00Z","from":"architect","body":"PRIVATE_BUS_BODY"}' \
  '{"ts":"2026-01-01T09:00:00Z","from":"architect","body":"PRIVATE_BUS_BODY"}' \
  > "$RDA_BUS_HOME/fixture/card.jsonl"
out="$(bash "$T" 2>&1)" || fail "registro con messaggi non leggibile"
has '2 messaggi in tutto · 1 negli ultimi 30 giorni' "finestra del bus errata"
has '1 conversazioni · 1 progetti · 1 ruoli' "presenze contate come messaggi"
has '1 presentazioni registrate' "hello non contato esattamente una volta"
ok "registri vuoti, sole uscite, presentazioni e messaggi hanno conteggi stabili"

"$TELEMETRY_SQLITE" "$RDA_SESSION_STORE" <<'SQL'
CREATE TABLE sessions(id TEXT PRIMARY KEY, repository TEXT, created_at TEXT, updated_at TEXT);
CREATE TABLE turns(session_id TEXT, timestamp TEXT, user_message TEXT, assistant_response TEXT);
INSERT INTO sessions VALUES
 ('a','overlap','2026-09-22T10:00:00Z','2026-09-22T12:00:00Z'),
 ('b','overlap','2026-09-22 11:00:00','2026-09-22 13:00:00'),
 ('c','separate','2026-09-22 10:00:00','2026-09-22 11:00:00'),
 ('d','separate','2026-09-22T12:00:00Z','2026-09-22T13:00:00Z'),
 ('e','offset','2026-09-22T10:00:00+02:00','2026-09-22T11:00:00+02:00'),
 ('f','offset','2026-09-22T08:30:00Z','2026-09-22T09:30:00Z'),
 ('g','crossing','2026-08-01T00:00:00Z','2026-08-25T00:00:00Z'),
 ('h','crossing','2026-08-24 12:00:00','2026-08-26 00:00:00'),
 ('i','touching','2026-09-22 10:00:00','2026-09-22 11:00:00'),
 ('j','touching','2026-09-22T11:00:00Z','2026-09-22T12:00:00Z'),
 ('k','old','2026-08-01 00:00:00','2026-08-02 00:00:00'),
 ('l','old','2026-08-01 00:00:00','2026-08-02 00:00:00'),
 ('m','future','2026-10-01 00:00:00','2026-10-02 00:00:00'),
 ('n','future','2026-10-01 00:00:00','2026-10-02 00:00:00'),
 ('o','instant','2026-09-22 10:00:00','2026-09-22 10:00:00'),
 ('p','instant','2026-09-22 09:00:00','2026-09-22 11:00:00');
INSERT INTO turns VALUES
 ('a','2026-09-22T22:30:00-02:00','PRIVATE_USER bus.sh','PRIVATE_RESPONSE'),
 ('b','2026-09-22 23:00:00','PRIVATE_USER','PRIVATE_RESPONSE bus.sh'),
 ('b','2026-08-23T23:30:00-02:00','PRIVATE_USER bus.sh','PRIVATE_RESPONSE'),
 ('c','2026-08-24T00:30:00+02:00','PRIVATE_USER bus.sh','PRIVATE_RESPONSE');
SQL
: > "$TELEMETRY_CALLS"
out="$(bash "$T" 2>&1)" || fail "database valido non leggibile"
has 'overlap +1 coppie sovrapposte' "due sessioni sovrapposte non danno una sola coppia"
has 'offset +1 coppie sovrapposte' "fusi orari non normalizzati"
has 'crossing +1 coppie sovrapposte' "sessione iniziata prima della finestra esclusa"
has 'TOTALE +3 coppie sovrapposte' "totale delle coppie errato"
grep -qE '(separate|touching|old|future|instant) +[0-9]+ coppie' <<< "$out" \
  && fail "intervalli disgiunti o fuori finestra contati"
has 'bus +2 sessioni · 3 turni · ultimo: 2026-09-23' "menzioni o ultima data non normalizzate"
has 'menzioni testuali, non invocazioni' "menzioni presentate come invocazioni"
grep -q 'RAPPORTO' <<< "$out" && fail "coppie e sessioni usate come rapporto"
grep -q 'PRIVATE_' <<< "$out" && fail "contenuto privato nel referto"
ok "coppie uniche, date UTC, confini e menzioni testuali misurati su dati isolati"
query_count="$(wc -l < "$TELEMETRY_CALLS")"

printf 'sentinella: dati preesistenti\n' > "$TMP/repo/docs/findings.md"
cp "$TMP/repo/docs/findings.md" "$TMP/before"
: > "$TELEMETRY_CALLS"
out="$(bash "$T" --write 2>&1)" || fail "--write fallisce"
[ "$(wc -l < "$TELEMETRY_CALLS")" = "$query_count" ] || fail "--write ripete la misura"
head -n 1 "$TMP/repo/docs/findings.md" > "$TMP/prefix"
cmp -s "$TMP/before" "$TMP/prefix" || fail "--write tronca dati preesistenti"
printf '%s\n' "${out%$'\n\nreferto aggiunto a docs/findings.md'}" | sed $'s/\033\\[[0-9;]*m//g' \
  > "$TMP/displayed"
awk '/^```$/ {inside=!inside; next} inside' "$TMP/repo/docs/findings.md" > "$TMP/appended"
cmp -s "$TMP/displayed" "$TMP/appended" || fail "referto salvato diverso da quello mostrato"
ok "--write aggiunge senza troncare e salva la stessa misura, senza rieseguirla"

cp "$TMP/repo/docs/findings.md" "$TMP/default-before"
redirected="$TMP/redirected findings.md"
printf 'sentinella: destinazione alternativa\n' > "$redirected"
cp "$redirected" "$TMP/redirected-before"
out="$(RDA_TELEMETRY_FINDINGS="$redirected" bash "$T" 2>&1)" || fail "override senza --write fallisce"
cmp -s "$redirected" "$TMP/redirected-before" || fail "override scrive senza --write"
out="$(RDA_TELEMETRY_FINDINGS="$redirected" bash "$T" --write 2>&1)" || fail "override --write fallisce"
cmp -s "$TMP/default-before" "$TMP/repo/docs/findings.md" || fail "override modifica findings predefinito"
head -n 1 "$redirected" > "$TMP/prefix"
cmp -s "$TMP/redirected-before" "$TMP/prefix" || fail "override tronca la destinazione"
awk '/^```$/ {inside=!inside; next} inside' "$redirected" > "$TMP/redirected-report"
cmp -s "$TMP/appended" "$TMP/redirected-report" || fail "override salva un referto diverso"
grep -Fq "referto aggiunto a $redirected" <<< "$out" || fail "override indica una destinazione errata"
for invalid_destination in "" "$TMP/missing-parent/findings.md"; do
  if out="$(RDA_TELEMETRY_FINDINGS="$invalid_destination" bash "$T" --write 2>&1)"; then
    fail "destinazione override invalida accettata"
  fi
  has 'scrittura del referto fallita' "errore di destinazione override non dichiarato"
  cmp -s "$TMP/default-before" "$TMP/repo/docs/findings.md" || fail "override invalido ricade sul default"
done
ok "RDA_TELEMETRY_FINDINGS isola la scrittura, preserva i dati e non ricade sul default"

out="$(bash "$T" --giorni 030 2>&1)" || fail "alias --giorni o numero con zero iniziale rifiutato"
has 'TOTALE +3 coppie sovrapposte' "alias --giorni cambia le misure"
out="$(bash "$T" --help 2>&1)" || fail "--help fallisce"
has 'telemetry' "help non disponibile"

cp "$TMP/repo/docs/findings.md" "$TMP/before"
if out="$(TELEMETRY_FAIL_QUERY=1 bash "$T" --write 2>&1)"; then
  fail "errore nella query delle occasioni restituito come successo"
fi
has 'non disponibile' "errore SQLite non dichiarato"
grep -q 'PRIVATE_\|nessuna sovrapposizione' <<< "$out" && fail "errore mascherato o contenuto esposto"
cmp -s "$TMP/before" "$TMP/repo/docs/findings.md" || fail "referto fallito salvato comunque"
printf 'PRIVATE_NOT_A_DATABASE\n' > "$TMP/corrupt.db"
"$TELEMETRY_SQLITE" "$TMP/schema.db" 'CREATE TABLE other(value TEXT);'
for bad in "$TMP/corrupt.db" "$TMP/schema.db"; do
  if out="$(RDA_SESSION_STORE="$bad" bash "$T" 2>&1)"; then
    fail "database corrotto o schema mancante restituito come successo"
  fi
  has 'non disponibile' "database corrotto non dichiarato indisponibile"
  grep -q '0 sessioni\|PRIVATE_' <<< "$out" && fail "database corrotto: zero inventato o contenuto esposto"
done
"$TELEMETRY_SQLITE" "$RDA_SESSION_STORE" "UPDATE sessions SET updated_at='invalid' WHERE id='a';"
if out="$(bash "$T" 2>&1)"; then fail "data non interpretabile ignorata"; fi
has 'non disponibile' "data non valida non dichiarata"
"$TELEMETRY_SQLITE" "$RDA_SESSION_STORE" "UPDATE sessions SET updated_at='2026-09-21' WHERE id='a';"
if out="$(bash "$T" 2>&1)"; then fail "intervallo invertito ignorato"; fi
"$TELEMETRY_SQLITE" "$RDA_SESSION_STORE" "DELETE FROM sessions; UPDATE turns SET timestamp=NULL;"
if out="$(bash "$T" 2>&1)"; then fail "data del turno mancante ignorata"; fi
ok "errori di query, database, schema e date sono espliciti, senza zeri o testo privato"

calls_before="$(wc -l < "$TELEMETRY_CALLS")"
python3 - "$T" <<'PY'
import os
import subprocess
import sys

script = sys.argv[1]
invalid = ["", "0", "-1", "1.5", "abc", "99999999999999999999", "30'); SELECT 1; --"]
cases = [(["--days"], {}), (["--giorni"], {}), (["--days", "--write"], {})]
cases += [(["--days", value], {}) for value in invalid]
cases += [([], {"RDA_TELEMETRY_DAYS": value}) for value in invalid]
for args, overrides in cases:
    result = subprocess.run(["bash", script, *args], env={**os.environ, **overrides},
                            capture_output=True, text=True, timeout=3)
    assert result.returncode != 0, (args, overrides, "invalid input accepted")
    assert "giorni" in result.stderr, (args, overrides, "no explicit days error")
PY
[ "$(wc -l < "$TELEMETRY_CALLS")" = "$calls_before" ] || fail "giorni invalidi arrivano a SQLite"
ok "argomenti mancanti, giorni invalidi e tentativi SQL falliscono esplicitamente entro 3s"

"$TELEMETRY_SQLITE" "$RDA_SESSION_STORE" "DELETE FROM turns;"
out="$(bash "$T" 2>&1)" || fail "database valido vuoto rifiutato"
has 'bus +0 sessioni · 0 turni' "database vuoto non restituisce zero menzioni"
has 'nessuna sovrapposizione osservata' "zero occasioni osservate non dichiarato"
ok "database valido vuoto distinto da database assente o corrotto"
mv "$TMP/repo/docs/findings.md" "$TMP/report-saved"
mkdir "$TMP/repo/docs/findings.md"
if out="$(bash "$T" --write 2>&1)"; then fail "scrittura fallita restituita come successo"; fi
grep -q 'referto aggiunto' <<< "$out" && fail "scrittura fallita dichiarata riuscita"
ok "errore di scrittura restituito esplicitamente senza dichiarare salvataggio"

echo "PASS: test-telemetry.sh"
