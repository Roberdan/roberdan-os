#!/usr/bin/env bash
# test-kb-precheck.sh — le tre domande da fare a una card prima di eseguirla, e il silenzio.
#
# Il 2026-07-30 cinque card si sono rivelate sbagliate NEL MOMENTO in cui qualcuno le ha prese
# in mano: una aperta da venti giorni su lavoro gia' fatto e reso inutile da una decisione
# successiva; una che chiedeva cio' che le sue card sorelle dovevano fare; due sullo stesso
# problema; quattro sullo stesso lavoro. Non e' sfortuna: mancava un controllo al momento giusto.
#
# LA DIREZIONE PIU' IMPORTANTE E' IL SILENZIO. Un avviso che compare su ogni card e' rumore che
# si impara a saltare, e allora il giorno che dice qualcosa di vero nessuno lo legge. Meta' delle
# asserzioni qui verificano che il precheck NON parli quando non ha niente da dire.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KBSH="$ROOT/kanban/kb.sh"
FAIL=0
ok()  { printf '  ok: %s\n' "$1"; }
err() { printf '  FAIL: %s\n' "$1"; FAIL=1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
KB="$TMP/board"; mkdir -p "$KB/todo" "$KB/doing" "$KB/done"
kb() { RDA_KANBAN="$KB" RDA_KANBAN_REGISTRY="$TMP/registry" bash "$KBSH" "$@" 2>&1; }
_dice() { local atteso="$1"; shift; shift; local o; o="$("$@")"; case "$o" in *"$atteso"*) return 0 ;; *) return 1 ;; esac; }

_card() { # _card <colonna> <id> <titolo> <dod> <data>
  cat > "$KB/$1/$2.md" <<CARD
---
title: $3
repo: provarepo
dod: "$4"
acceptance: "il comando stampa il risultato"
status: $1
created: $5
---
CARD
}
_oggi() { date +%Y-%m-%d; }
_giorni_fa() { date -j -v-"$1"d +%Y-%m-%d 2>/dev/null || date -d "$1 days ago" +%Y-%m-%d; }

printf '\n=== 1. eta: una card vecchia va riletta, non eseguita a scatola chiusa ===\n'

_card todo VECCHIA "Argomento del tutto isolato alfa" "risultato isolato alfa" "$(_giorni_fa 20)"
if _dice "ETA'" -- kb start VECCHIA --by roberto --no-worktree t; then
  ok "una card di 20 giorni viene segnalata per eta'"
else
  err "una card di 20 giorni passa senza un avviso: e' il caso MCAPS, venti giorni su lavoro gia' fatto"
fi

_card todo FRESCA "Argomento del tutto isolato beta" "risultato isolato beta" "$(_oggi)"
if _dice "ETA'" -- kb start FRESCA --by roberto --no-worktree t; then
  err "una card di OGGI viene segnalata per eta': l'avviso comparirebbe sempre e diventerebbe rumore"
else
  ok "una card di oggi NON viene segnalata: nessun rumore"
fi

printf '\n=== 2. sovrapposizione: due card aperte che dicono la stessa cosa ===\n'

rm -f "$KB"/doing/*.md
_card todo APERTA1 "Identita reali dentro il sorgente tracciato" "nessun file tracciato porta identita reali" "$(_oggi)"
_card todo APERTA2 "Sostituire identita reali nei fixture tracciati" "nessun fixture tracciato porta identita reali" "$(_oggi)"
out="$(kb start APERTA1 --by roberto --no-worktree t)"
case "$out" in
  *SOVRAPPOSIZIONE*APERTA2*) ok "la sovrapposizione fra card aperte viene nominata, con l'id dell'altra" ;;
  *) err "due card aperte sullo stesso problema partono senza avviso: $(printf '%s' "$out" | head -2)" ;;
esac

printf '\n=== 3. forse gia fatta: il caso MCAPS ===\n'

rm -f "$KB"/doing/*.md "$KB"/todo/*.md
_card "done" FATTA "Sistemare la coda dei lavori bloccata" "supervisore attivo e coda drenata" "$(_giorni_fa 19)"
_card todo GEMELLA "Sistemare la coda dei lavori ancora bloccata" "supervisore attivo e coda drenata" "$(_oggi)"
out="$(kb start GEMELLA --by roberto --no-worktree t)"
case "$out" in
  *"FORSE GIA'"*FATTA*) ok "una card gemella di una GIA' CHIUSA viene segnalata, con l'id da guardare" ;;
  *) err "il caso MCAPS non viene preso: lavoro gia' fatto, nessun avviso" ;;
esac

printf '\n=== 4. IL SILENZIO: una card pulita non deve far comparire niente ===\n'

rm -f "$KB"/doing/*.md "$KB"/todo/*.md
_card todo PULITA "Grafica del pulsante rotondo" "il pulsante appare rotondo" "$(_oggi)"
out="$(kb start PULITA --by roberto --no-worktree t)"
case "$out" in
  *"PRIMA DI PARTIRE"*) err "il precheck parla su una card senza parentele: e' rumore, e il rumore si impara a saltare" ;;
  *) ok "su una card nuova e senza parentele il precheck STA ZITTO" ;;
esac
case "$out" in
  *"doing/PULITA started"*) ok "e la card parte comunque: il precheck non blocca" ;;
  *) err "il precheck ha BLOCCATO l'avvio: non deve, un gate che blocca su un sospetto viene aggirato" ;;
esac

printf '\n=== 5. gli avvisi restano SULLA CARD, non solo a schermo ===\n'

rm -f "$KB"/doing/*.md "$KB"/todo/*.md
_card "done" FATTA2 "Riparare il condotto dei messaggi rotto" "il condotto dei messaggi funziona" "$(_giorni_fa 19)"
_card todo SCRITTA "Riparare il condotto dei messaggi ancora rotto" "il condotto dei messaggi funziona" "$(_giorni_fa 20)"
kb start SCRITTA --by roberto --no-worktree t >/dev/null
if grep -q 'Avvisi del precheck' "$KB/doing/SCRITTA.md" 2>/dev/null; then
  ok "gli avvisi sono scritti sulla card: chi ci lavora se li trova davanti"
else
  err "gli avvisi vivono solo a schermo: chi apre la card fra un'ora non li vede piu'"
fi

printf '\n=== 6. si puo spegnere ===\n'
rm -f "$KB"/doing/*.md "$KB"/todo/*.md
_card todo SPENTA "Riparare il condotto dei messaggi di nuovo" "il condotto dei messaggi funziona" "$(_giorni_fa 20)"
out="$(RDA_NO_PRECHECK=1 kb start SPENTA --by roberto --no-worktree t)"
case "$out" in
  *"PRIMA DI PARTIRE"*) err "RDA_NO_PRECHECK non spegne niente" ;;
  *) ok "RDA_NO_PRECHECK lo spegne, per gli usi in cui darebbe fastidio" ;;
esac

printf '\n'
[ "$FAIL" -eq 0 ] && echo "test-kb-precheck: PASS" || echo "test-kb-precheck: FAIL"
exit "$FAIL"
