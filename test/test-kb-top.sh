#!/usr/bin/env bash
# test-kb-top.sh — la finestrella di stato: raccolta, disegno, e le due regole che la rendono
# affidabile invece che carina.
#
# 1) Il disegno non paga mai un comando lento. Se `top.sh` chiama git, gh o sqlite3 nel suo
#    ciclo, la finestrella si impalla appena la rete rallenta: qui si verifica sul CODICE, non
#    sul tempo, perche' una prova a cronometro passa sulla macchina veloce e mente sull'altra.
# 2) Dove non c'e' una misura si scrive "-". E' la regola che Roberto ha chiesto esplicitamente
#    per "quanto manca": meglio un trattino di una stima plausibile.
set -u
cd "$(dirname "$0")/.." || exit 1
FAILS=0
ok()   { printf '  ok   — %s\n' "$1"; }
fail() { printf '  FAIL — %s\n' "$1"; FAILS=$((FAILS+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export RDA_HOME="$TMP/rdahome"; mkdir -p "$RDA_HOME"
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
git config -f "$GIT_CONFIG_GLOBAL" user.email t@t; git config -f "$GIT_CONFIG_GLOBAL" user.name t
export RDA_TOP_NO_NET=1     # niente rete nelle prove: i controlli automatici si saltano
# La prova non guarda dentro le sessioni vere della macchina: conterebbe le richieste di oggi
# di Roberto e darebbe un numero diverso a ogni giro. Un archivio che non esiste da' zero.
export RDA_COPILOT_STORE="$TMP/nessun-archivio.db"
export RDA_TOP_NO_COLOR=1
SNAP="$TMP/snap"
ROOT="$(pwd)"

# --- un progetto finto con una copia di lavoro --------------------------------------------
REPO="$TMP/demo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main; echo uno > "$REPO/f"; git -C "$REPO" add f; git -C "$REPO" commit -qm primo
mkdir -p "$REPO/kanban/doing" "$REPO/kanban/todo"
printf -- '---\ntitle: una card viva\nrepo: demo\nstarted_epoch: 1\n---\n' > "$REPO/kanban/doing/VIVA.md"
printf -- '---\ntitle: una in attesa\nrepo: demo\n---\n' > "$REPO/kanban/todo/ATTESA.md"
WT="$TMP/wt"; git -C "$REPO" worktree add -q -b card/x "$WT" main

echo "== la raccolta vede il progetto, non la cartella da cui guardi =="
# Il difetto vero trovato il 2026-09-13: da dentro una copia di lavoro, --show-toplevel
# risponde la COPIA, quindi il progetto si chiamava "card/x", le card erano zero e sembrava
# tutto a posto. Si risolve dal .git comune, e questa prova e' li' per impedire il ritorno.
(cd "$WT" && RDA_KANBAN="$REPO/kanban" bash "$ROOT/kanban/snapshot.sh" "$SNAP" >/dev/null 2>&1)
v() { awk -F'\t' -v k="$1" '$1==k{print $2; exit}' "$SNAP"; }
[ "$(v repo)" = "demo" ] && ok "da dentro una copia, il progetto e' 'demo' e non la copia" \
  || fail "il progetto e' stato letto come '$(v repo)' invece di 'demo'"
[ "$(v qui)" = "wt" ] && ok "dice anche in quale copia ti trovi" || fail "non dice dove sei ($(v qui))"
[ "$(v card_doing)" = "1" ] && ok "conta la card in lavorazione del progetto" || fail "card in lavorazione: $(v card_doing)"
[ "$(v card_todo)" = "1" ] && ok "conta la card in attesa" || fail "card in attesa: $(v card_todo)"
[ "$(v branch)" = "card/x" ] && ok "il ramo e' quello della copia in cui stai" || fail "ramo: $(v branch)"

echo "== il disegno non paga mai un comando lento =="
# Sul codice, non a cronometro. `git rev-parse` una volta sola all'avvio e' ammesso: serve a
# sapere di quale progetto e' la fotografia, costa millisecondi e non e' nel ciclo.
ciclo="$(sed -n '/^while :; do/,/^done/p' "$ROOT/kanban/top.sh")"
case "$ciclo" in
  *" gh "*|*sqlite3*|*" git "*) fail "il ciclo di disegno chiama un comando lento" ;;
  *) ok "nel ciclo di disegno non c'e' ne' rete ne' database ne' git" ;;
esac
grep -q 'snapshot.sh' "$ROOT/kanban/top.sh" && ok "la raccolta viene lanciata in sottofondo" || fail "non lancia mai la raccolta"
grep -q 'refresh_if_stale' "$ROOT/kanban/top.sh" && ok "rinfresca solo quando la foto e' vecchia" || fail "rinfresca sempre"

echo "== disegna una volta sola quando non c'e' un terminale =="
d="$(cd "$WT" && RDA_TOP_SNAP="$SNAP" timeout 20 bash "$ROOT/kanban/top.sh" --once 2>&1)"
case "$d" in *LAVORO*) ok "mostra il lavoro" ;; *) fail "manca la sezione del lavoro" ;; esac
case "$d" in *AGENTI*) ok "mostra gli agenti" ;; *) fail "manca la sezione degli agenti" ;; esac
case "$d" in *GIT*) ok "mostra lo stato di git" ;; *) fail "manca lo stato di git" ;; esac
case "$d" in *"una card viva"*) ok "scrive il titolo della card, non il suo codice" ;; *) fail "non scrive il titolo della card" ;; esac

echo "== l'impaginazione sta dentro il riquadro e non spezza le parole =="
# Il primo difetto visto a occhio: larghezza fissa a 34 dentro un riquadro piu' largo, con le
# parole tagliate a meta' ("...sul repo p") e meta' schermo vuoto. Qui si misura in CARATTERI,
# non in byte: un accento o un pallino occupano piu' byte di quanto occupino di schermo, e una
# prova che conta i byte griderebbe al rosso su un disegno perfetto.
printf 'aperto|una richiesta scritta per bene con parole lunghe da mandare a capo\n' > "$RDA_HOME/ask-demo.txt"
(cd "$WT" && RDA_KANBAN="$REPO/kanban" bash "$ROOT/kanban/snapshot.sh" "$SNAP" >/dev/null 2>&1)
d40="$(cd "$WT" && RDA_TOP_SNAP="$SNAP" RDA_TOP_WIDTH=40 timeout 20 bash "$ROOT/kanban/top.sh" --once 2>&1)"
# `awk` qui conta BYTE, e un trattino lungo o un pallino ne occupano tre: misurerebbe 120 su
# una riga larga 40 e griderebbe al rosso su un disegno perfetto. I caratteri li conta python3.
maxlen() { python3 -c 'import sys;print(max((len(l.rstrip(chr(10))) for l in sys.stdin),default=0))'; }
lunga="$(printf '%s\n' "$d40" | maxlen)"; [ "$lunga" -le 40 ] && lunga=""
[ -z "$lunga" ] && ok "nessuna riga esce dal riquadro a 40 colonne" || fail "una riga e' lunga $lunga caratteri su 40"
case "$d40" in *"parole lunghe da mandare a"*) ok "la frase lunga va a capo sulle parole, non tagliata a meta'" ;;
  *) fail "la frase lunga non e' andata a capo" ;; esac
d24="$(cd "$WT" && RDA_TOP_SNAP="$SNAP" RDA_TOP_WIDTH=24 timeout 20 bash "$ROOT/kanban/top.sh" --once 2>&1)"
l24="$(printf '%s\n' "$d24" | maxlen)"; [ "$l24" -le 24 ] && l24=""
if [ -z "$l24" ]; then ok "e nemmeno a 24 colonne, che e' il caso stretto vero"
else fail "a 24 colonne una riga e' lunga $l24"; printf '%s\n' "$d24" | python3 -c 'import sys
for l in sys.stdin:
    l=l.rstrip(chr(10))
    if len(l)>24: print("   >>", len(l), repr(l))'; fi
grep -q 'tput cols' "$ROOT/kanban/top.sh" && ok "la larghezza la chiede al terminale, non e' un numero fisso" || fail "la larghezza e' ancora fissa"
grep -q "trap 'term_size' WINCH" "$ROOT/kanban/top.sh" && ok "e la ri-legge quando ridimensioni il riquadro" || fail "non si accorge del ridimensionamento"

echo "== il ridisegno sta fermo: niente sfarfallio, niente scorrimento =="
# Pulire tutto lo schermo a ogni giro fa sfarfallare, e un disegno alto una riga piu' del
# riquadro lo fa SCORRERE: e' quello che si vedeva. Si riscrive sul posto cancellando la coda
# di ogni riga, e non si scrive mai sull'ultima riga — scrivere li' e' cio' che fa scorrere.
case "$ciclo" in *'[2J'*) fail "il ciclo pulisce tutto lo schermo a ogni giro (sfarfallio)" ;;
  *) ok "il ciclo non pulisce tutto lo schermo a ogni giro" ;; esac
case "$ciclo" in *'[K'*) ok "riscrive sul posto cancellando solo la coda di ogni riga" ;;
  *) fail "non cancella la coda delle righe: restano pezzi del disegno vecchio" ;; esac
case "$ciclo" in *'-ge "$H"'*) ok "non scrive mai sull'ultima riga del riquadro" ;;
  *) fail "puo' scrivere sull'ultima riga, e allora il terminale scorre" ;; esac

echo "== senza elenco della richiesta, la sezione NON esiste =="
# Un elenco inventato qui sarebbe il peggiore dei difetti: e' il posto dove Roberto va a
# vedere se un pezzo e' stato dimenticato. Vuoto vuol dire vuoto.
case "$d" in *"LA TUA RICHIESTA"*) fail "ha disegnato una richiesta che nessuno ha scritto" ;; *) ok "niente richiesta scritta, niente sezione" ;; esac

echo "== i pezzi della richiesta: si scrivono, si spuntano, non si perdono =="
export RDA_ASK_FILE="$TMP/ask.txt"
bash "$ROOT/kanban/ask.sh" set "pezzo uno" "pezzo due" >/dev/null
bash "$ROOT/kanban/ask.sh" "done" 1 >/dev/null
l="$(bash "$ROOT/kanban/ask.sh" list)"
case "$l" in *"[fatto] pezzo uno"*) ok "un pezzo fatto risulta fatto" ;; *) fail "il pezzo fatto non risulta" ;; esac
case "$l" in *"1/2 fatti"*) ok "conta quanti pezzi mancano" ;; *) fail "non conta i pezzi" ;; esac
bash "$ROOT/kanban/ask.sh" "done" 9 >/dev/null 2>&1 && fail "ha accettato un pezzo che non esiste" || ok "rifiuta un pezzo che non esiste"
bash "$ROOT/kanban/ask.sh" "done" abc >/dev/null 2>&1 && fail "ha accettato un numero che non e' un numero" || ok "rifiuta un numero che non e' un numero"
[ "$(grep -c . "$RDA_ASK_FILE")" = "2" ] && ok "nessun pezzo sparisce quando lo si spunta" || fail "spuntare un pezzo ne ha persi"

# e ora la sezione compare, con il conteggio giusto
cp "$RDA_ASK_FILE" "$RDA_HOME/ask-demo.txt"
(cd "$WT" && RDA_KANBAN="$REPO/kanban" bash "$ROOT/kanban/snapshot.sh" "$SNAP" >/dev/null 2>&1)
d2="$(cd "$WT" && RDA_TOP_SNAP="$SNAP" timeout 20 bash "$ROOT/kanban/top.sh" --once 2>&1)"
case "$d2" in *"LA TUA RICHIESTA"*"1/2"*) ok "con l'elenco scritto, la sezione compare con il conteggio" ;; *) fail "la sezione della richiesta non compare" ;; esac

echo "== dove non c'e' una misura si scrive un trattino, mai un numero inventato =="
grep -q "printf -- '-'" "$ROOT/kanban/top.sh" && ok "la durata senza misura stampa '-'" || fail "la durata inventa qualcosa"
grep -q 'p() { printf .*"${1}\|.*:--' "$ROOT/kanban/snapshot.sh" 2>/dev/null \
  || grep -q ':--}' "$ROOT/kanban/snapshot.sh" && ok "la raccolta scrive '-' per ogni valore che non ha" || fail "la raccolta puo' scrivere un campo vuoto"
grep -q 'unita' "$ROOT/kanban/top.sh" && ok "la spesa e' in unita del motore, senza simbolo di valuta" || fail "manca l'unita dichiarata"
# La spesa arriva dal motore in una unita' il cui cambio in euro nessuno qui conosce: per un
# giorno intero faceva "$373833.34", che non era una cifra sbagliata ma una cifra SENZA
# SIGNIFICATO. Un simbolo di valuta la farebbe leggere come denaro, quindi non ce ne sono.
if grep -F -q '$%' "$ROOT/kanban/top.sh" || grep -F -q '€' "$ROOT/kanban/top.sh" || grep -q 'euro' "$ROOT/kanban/top.sh"; then
  fail "stampa la spesa come se fosse denaro convertito"
else
  ok "non stampa mai un prezzo che nessuno sa convertire"
fi

python3 "$ROOT/test/test-kb-top-pty.py" || fail "terminale interattivo: resize, ridisegno, uscita"
echo ""
if [ "$FAILS" -eq 0 ]; then echo "test-kb-top: ✅ ALL GREEN"; else
  echo "--- disegno prodotto (per capire il rosso senza un altro giro) ---"; printf '%s\n' "$d2"
  echo "test-kb-top: ❌ $FAILS FAIL"; exit 1; fi
