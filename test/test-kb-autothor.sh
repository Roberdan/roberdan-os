#!/usr/bin/env bash
# test-kb-autothor.sh — @thor verifica da solo, e quando non puo' farlo kb NON dice che l'ha
# fatto. Il cancello doing->done e' il piu' importante del sistema e fino al 2026-07-31
# dipendeva dalla buona volonta' di chi lo attraversava: `kb finish --thor "<evidenza>"`
# accettava la frase di chi chiudeva e il sistema stampava "verified by @thor" comunque.
#
# Qui NON si esegue la verifica vera: lancerebbe un processo `claude` per card, minuti e denaro
# per una card finta. Si prova il CABLAGGIO — che kb chiami thor, che si fidi del suo verdetto
# nei due sensi, e soprattutto che uno SKIP non venga scambiato per un PASS. Quest'ultimo e' il
# caso che conta: "non ho potuto verificare" e "ho verificato e va bene" sono fatti diversi, e
# confonderli e' il modo in cui un cancello torna a essere un timbro.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export RDA_KANBAN="$TMP/board"; export RDA_KANBAN_REGISTRY="$TMP/reg"; : > "$RDA_KANBAN_REGISTRY"
mkdir -p "$RDA_KANBAN"/{todo,doing,done}
EV="test/test-kb-autothor.sh: 6 passed, exit 0"
fails=0
ok()  { printf '  ok   — %s\n' "$1"; }
err() { printf '  FAIL — %s\n' "$1"; fails=$((fails+1)); }
card() { printf 'id: %s\nstatus: doing\ntitle: "fixture autothor"\n' "$1" > "$RDA_KANBAN/doing/$1.md"; }
in_doing() { [ -e "$RDA_KANBAN/doing/$1.md" ]; }
in_done()  { [ -e "$RDA_KANBAN/done/$1.md" ]; }

# Un finto thor sul PATH di kb: kb chiama kanban/thor-verify.sh, quindi lo si sostituisce
# con uno stub che stampa il verdetto che vogliamo provare.
STUB="$TMP/stub"; mkdir -p "$STUB"
fake_thor() { printf '#!/usr/bin/env bash\nprintf "%s\\n"\n' "$1" > "$TMP/thor-verify.sh"; chmod +x "$TMP/thor-verify.sh"; }
# kb invoca "$ROOT/kanban/thor-verify.sh": si lavora su una COPIA del repo per non toccarlo.
REPO="$TMP/repo"; mkdir -p "$REPO/kanban" "$REPO/factory"
cp "$ROOT/kanban/kb.sh" "$REPO/kanban/"; cp -R "$ROOT/kanban/"*.sh "$REPO/kanban/" 2>/dev/null || true
cp "$ROOT/factory/lib.sh" "$REPO/factory/" 2>/dev/null || true
KBC="$REPO/kanban/kb.sh"

# --- 1. PASS: thor dice si', la card si chiude e il verdetto FINISCE sulla card -------------
printf '#!/usr/bin/env bash\nprintf "PASS\\tho controllato i criteri: file presenti, suite verde\\n"\n' > "$REPO/kanban/thor-verify.sh"
chmod +x "$REPO/kanban/thor-verify.sh"
card P1
out="$(bash "$KBC" finish P1 --thor "$EV" 2>&1 | grep -v '^kb: ' || true)"
if in_done P1; then ok "PASS di @thor: la card si chiude"; else err "PASS di @thor: la card NON si e' chiusa — $out"; fi
if grep -q '^verified_by: thor' "$RDA_KANBAN/done/P1.md" 2>/dev/null; then
  ok "e la card registra verified_by: thor (stavolta e' vero)"
else err "la card non registra thor: $(grep '^verified_by' "$RDA_KANBAN/done/P1.md" 2>/dev/null)"; fi
if grep -q 'ho controllato i criteri' "$RDA_KANBAN/done/P1.md" 2>/dev/null; then
  ok "e l'evidenza di @thor e' scritta sulla card, non solo la frase di chi chiudeva"
else err "l'evidenza di @thor non compare sulla card"; fi

# --- 2. FAIL: thor dice no. La card NON si chiude, e il motivo si legge ----------------------
printf '#!/usr/bin/env bash\nprintf "FAIL\\til criterio 2 non e soddisfatto: manca il test\\n"\n' > "$REPO/kanban/thor-verify.sh"
card F1
out="$(bash "$KBC" finish F1 --thor "$EV" 2>&1 | grep -v '^kb: ' || true)"
if in_doing F1 && ! in_done F1; then ok "FAIL di @thor: la card resta in doing"; else err "FAIL di @thor: la card si e' chiusa lo stesso"; fi
case "$out" in *"manca il test"*) ok "e il motivo di @thor viene riportato a chi chiude" ;;
  *) err "il motivo di @thor non compare: $out" ;; esac

# --- 3. SKIP: il caso che conta. Non e' un verdetto, e non deve diventare un PASS -----------
printf '#!/usr/bin/env bash\nprintf "SKIP\\tbinario claude non trovato\\n"\n' > "$REPO/kanban/thor-verify.sh"
card S1
out="$(bash "$KBC" finish S1 --thor "$EV" 2>&1 | grep -v '^kb: ' || true)"
if in_doing S1 && ! in_done S1; then ok "SKIP: la card resta in doing (non si chiude su una verifica mai avvenuta)"; else err "SKIP trattato come un PASS: la card si e' chiusa"; fi

# --- 3b. UN TIMEOUT NON E' UN VERDETTO. verify_card() torna FAIL sia per "ho guardato e dico
#     no" sia per "non sono arrivato in fondo" (timeout, output illeggibile). Il 2026-07-31 una
#     verifica uscita in timeout e' arrivata a chi chiudeva come "@thor dice NO": stessa
#     sostituzione che il caso 3 rifiuta, nell'altro verso. Qui si prova la traduzione fatta da
#     kanban/thor-verify.sh, chiamandolo con un verify_card finto.
FAKELIB="$TMP/fakerepo"; mkdir -p "$FAKELIB/kanban" "$FAKELIB/factory"
cp "$ROOT/kanban/thor-verify.sh" "$FAKELIB/kanban/"
printf 'verify_card() { printf "FAIL\\tunparseable thor-verify output (exit=124) — see /tmp/x.log\\n"; }\n' > "$FAKELIB/factory/lib.sh"
tvout="$(CLAUDE=/bin/echo bash "$FAKELIB/kanban/thor-verify.sh" QUALSIASI 2>/dev/null || true)"
case "$tvout" in
  SKIP*) ok "un timeout di @thor viene tradotto in SKIP, non in un verdetto" ;;
  FAIL*) err "un timeout viene ancora riportato come 'thor dice NO': $tvout" ;;
  *)     err "esito inatteso dal traduttore: $tvout" ;;
esac
printf 'verify_card() { printf "FAIL\\til criterio 2 non e soddisfatto\\n"; }\n' > "$FAKELIB/factory/lib.sh"
tvout2="$(CLAUDE=/bin/echo bash "$FAKELIB/kanban/thor-verify.sh" QUALSIASI 2>/dev/null || true)"
case "$tvout2" in
  FAIL*) ok "e un FAIL vero resta un FAIL (la traduzione non ingoia i verdetti)" ;;
  *)     err "un verdetto FAIL vero e' stato trasformato in: $tvout2" ;;
esac

# --- 4. --by resta la via esplicita: chi dichiara chi ha verificato non convoca thor ---------
printf '#!/usr/bin/env bash\nprintf "FAIL\\tnon dovrei nemmeno essere chiamato\\n"\n' > "$REPO/kanban/thor-verify.sh"
card B1
out="$(bash "$KBC" finish B1 --thor "$EV" --by claude 2>&1 | grep -v '^kb: ' || true)"
if in_done B1; then ok "--by chiude senza convocare @thor (chi verifica e' gia' dichiarato)"; else err "--by non ha chiuso: $out"; fi
case "$out" in *"non dovrei nemmeno"*) err "--by ha convocato @thor lo stesso" ;; *) ok "e infatti @thor non e' stato chiamato" ;; esac

echo
if [ "$fails" -eq 0 ]; then echo "test-kb-autothor: PASS"; exit 0; fi
echo "test-kb-autothor: FAIL ($fails)"; exit 1
