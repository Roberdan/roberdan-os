#!/usr/bin/env bash
# test-file-size-ratchet.sh — la regola delle 300 righe smette di essere un consiglio.
#
# `rules/best-practices.md § Context & Token Economy` dice da tempo che un file scritto a mano
# punta a **≤300 righe**. Era prosa: nessuno la misurava, e undici file l'avevano superata — uno
# a 1606 righe. Una regola che nessuno misura non è una regola, è un'opinione ben scritta.
#
# È un RATCHET, non una retroattività, ed è la stessa scelta fatta lo stesso giorno per le
# clausole di acceptance: i file già oltre soglia sono congelati in una baseline e passano;
# quello che il gate rifiuta è **un file nuovo oltre soglia** e **un file baselinato che
# CRESCE**. Un gate rosso il giorno in cui nasce viene aggirato — in questo repo è successo tre
# volte in due giorni, e ogni volta la riparazione è stata la stessa: rendere il gate onesto
# sul presente e severo sul futuro.
#
# Cosa NON fa, di proposito: non chiede di spezzare i file esistenti. La card lo dice
# esplicitamente ("existing oversized files are not forced into unrelated refactors"), e un
# refactor imposto da un contatore è esattamente il tipo di lavoro non richiesto che questo
# repo ha passato la giornata del 2026-07-30 a smettere di generare.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
LIMITE=300
BASELINE="$ROOT/test/file-size-baseline.txt"
FAIL=0
ok()  { printf '  ok: %s\n' "$1"; }
err() { printf '  FAIL: %s\n' "$1"; FAIL=1; }

# Solo file SCRITTI A MANO. Le esenzioni sono quelle che il canone già dichiara: generato,
# vendorizzato, lock, snapshot, dati, migrazioni. Qui si traducono in percorsi, perché un gate
# che ispeziona il contenuto per indovinare "è generato?" sbaglia in silenzio.
_a_mano() {
  git ls-files '*.sh' '*.mjs' '*.js' 2>/dev/null | grep -vE '^(platforms/|vendor/|node_modules/|.*\.lock$|.*/snapshots?/|.*/fixtures?/|.*/migrations?/)'
}

[ -f "$BASELINE" ] || { echo "  FAIL: manca $BASELINE — senza baseline questo gate sarebbe retroattivo"; exit 1; }

nuovi=0; cresciuti=0; misurati=0
while read -r f; do
  [ -f "$f" ] || continue
  misurati=$((misurati+1))
  n=$(wc -l < "$f" | tr -d ' ')
  [ "$n" -le "$LIMITE" ] && continue
  base="$(awk -v p="$f" '/^[0-9]/ && $2==p{print $1}' "$BASELINE")"
  if [ -z "$base" ]; then
    err "$f è a $n righe (limite $LIMITE) e non è nella baseline: un file NUOVO non nasce oltre soglia"
    nuovi=$((nuovi+1))
  elif [ "$n" -gt "$base" ]; then
    err "$f è cresciuto da $base a $n righe: un file già oltre soglia non si allarga"
    cresciuti=$((cresciuti+1))
  fi
done <<EOF
$(_a_mano)
EOF

[ "$nuovi" -eq 0 ] && ok "nessun file nuovo oltre le $LIMITE righe ($misurati file misurati)"
[ "$cresciuti" -eq 0 ] && ok "nessun file della baseline è cresciuto"

# La baseline non deve poter essere allargata di nascosto per far passare un file: una riga in
# più qui è una decisione, e va vista in un diff. Il conteggio è scritto nel file stesso.
attesi="$(grep -c '^[0-9]' "$BASELINE" 2>/dev/null || echo 0)"
dichiarati="$(grep -oE '^# file in baseline: [0-9]+' "$BASELINE" | grep -oE '[0-9]+$' || echo -1)"
if [ "$attesi" = "$dichiarati" ]; then
  ok "la baseline dichiara il proprio numero di righe ($attesi) e coincide"
else
  err "la baseline ha $attesi voci ma ne dichiara $dichiarati: qualcuno l'ha allargata senza dirlo"
fi

printf '\n'
[ "$FAIL" -eq 0 ] && echo "test-file-size-ratchet: PASS" || echo "test-file-size-ratchet: FAIL"
exit "$FAIL"
