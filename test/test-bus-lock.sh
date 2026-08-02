#!/usr/bin/env bash
# test-bus-lock.sh — un lucchetto orfano si riusa, uno vivo si rispetta.
#
# Il difetto che questo file esiste per impedire (rilievo 23, DUE volte il 2 agosto 2026): il
# lucchetto veniva rilasciato solo da un `trap EXIT`, che non gira se il processo viene ucciso.
# Una verifica di @thor finita male lo lasciava li', e il `validate.sh` successivo usciva ROSSO
# SU test-bus, che non c'entrava niente. Un rosso su un innocente insegna a cancellare i
# lucchetti a mano, cioe' a disarmare la protezione.
#
# Il difetto OPPOSTO e' peggio e ha altrettante asserzioni qui: se un lucchetto vivo venisse
# riusato, due suite scriverebbero sullo stesso $HOME e si corromperebbero le prove a vicenda —
# esattamente cio' che il lucchetto esiste per impedire. "Riusa gli orfani" non deve mai
# diventare "riusa sempre".
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/test/lib-lock.sh"
FAIL=0
ok()  { printf '  ok: %s\n' "$1"; }
err() { printf '  FAIL: %s\n' "$1"; FAIL=1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
L="$TMP/lock"

printf '\n=== il caso normale ===\n'
bus_lock_acquire "$L" && ok "lucchetto libero -> preso" || err "lucchetto libero: rifiutato"
[ "$(bus_lock_owner "$L")" = "$$" ] && ok "dentro c'e' il PID di chi lo tiene" \
                                    || err "il PID scritto e' '$(bus_lock_owner "$L")', atteso $$"

printf '\n=== un lucchetto VIVO si rispetta (il difetto opposto, il piu grave) ===\n'
# lo tiene questo stesso processo, che e' vivo per definizione
bus_lock_acquire "$L" && err "ha riusato un lucchetto il cui proprietario e' VIVO" \
                      || ok "proprietario vivo -> rifiutato"

# ora un altro processo, vivo davvero
rm -rf "$L"; mkdir "$L"
( sleep 30 ) & LIVE=$!
echo "$LIVE" > "$L/pid"
bus_lock_acquire "$L" && err "ha riusato il lucchetto di un processo vivo (pid $LIVE)" \
                      || ok "processo terzo vivo -> rifiutato"
kill "$LIVE" 2>/dev/null; wait "$LIVE" 2>/dev/null || true

printf '\n=== un lucchetto ORFANO si riusa (la riparazione) ===\n'
rm -rf "$L"; mkdir "$L"
( : ) & DEAD=$!; wait "$DEAD" 2>/dev/null || true      # un PID che esisteva e non esiste piu'
echo "$DEAD" > "$L/pid"
bus_lock_acquire "$L" && ok "proprietario morto -> lucchetto riusato" \
                      || err "un lucchetto orfano (pid $DEAD morto) ha bloccato lo stesso"
[ "$(bus_lock_owner "$L")" = "$$" ] && ok "e il nuovo proprietario e' scritto dentro" \
                                    || err "dopo il riuso il PID non e' aggiornato"

printf '\n=== un lucchetto SENZA pid: orfano, ma non subito ===\n'
rm -rf "$L"; mkdir "$L"     # nessun file pid: versione vecchia, o ucciso fra mkdir e write
t0=$(date +%s)
bus_lock_acquire "$L" && ok "senza PID -> riusato (nessuno puo' rivendicarlo)" \
                      || err "un lucchetto senza PID ha bloccato per sempre"
t1=$(date +%s)
[ $((t1-t0)) -ge 1 ] && ok "ma prima aspetta, per non rubare un lucchetto nato un istante fa" \
                     || err "non ha aspettato: una corsa fra mkdir e la scrittura del PID lo farebbe rubare"

printf '\n=== il PID scritto non e un numero: trattato come assente, non come vivo ===\n'
rm -rf "$L"; mkdir "$L"; printf 'non-un-numero\n' > "$L/pid"
bus_lock_acquire "$L" && ok "PID illeggibile -> orfano, riusato" \
                      || err "un PID illeggibile ha bloccato per sempre"

[ "$FAIL" -eq 0 ] && { echo "test-bus-lock: PASS"; exit 0; }
echo "test-bus-lock: FAIL"; exit 1
