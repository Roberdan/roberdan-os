#!/usr/bin/env bash
# test-bus-lock.sh — un lucchetto orfano si riusa, uno vivo si rispetta (suite e log del bus).
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

# ---------------------------------------------------------------------------
# Lo STESSO principio sul lucchetto dei log del bus (_with_lock, bus/bus-lock.sh).
# 2026-10-16: una cartella lock senza owner, lasciata alle 14:49 da un processo
# ucciso fra mkdir e la scrittura di owner, faceva morire ogni `bus team` dopo
# 10 s e scadere l'hook UserPromptSubmit a ogni prompt. Il caso giovane senza
# owner (dentro la grazia, quindi rifiutato) e' il check 36 di test-bus.sh.
BUS="$ROOT/bus/bus.sh"; export RDA_HOME="$TMP/home" RDA_BUS_HOME="$TMP/bus"
mkdir -p "$RDA_BUS_HOME/r"; echo "una nota" > "$TMP/body"
send() { RDA_BUS_LOCK_TRIES="${TRIES:-3}" bash "$BUS" send --repo r --card "$1" --from implementer \
           --to sol-gate --body-file "${2:-$TMP/body}" 2>&1; }
stale() { mkdir -p "$1"; [ -z "${2:-}" ] || printf 'pid %s at 2020-01-01T00:00:00Z\n' "$2" > "$1/owner"
          touch -t 202001010000 "$1"; }

printf '\n=== log del bus: un lucchetto VECCHIO SENZA owner o con owner MORTO si riprende ===\n'
( : ) & DEAD=$!; wait "$DEAD" 2>/dev/null || true
for k in ownerless dead; do
  l="$RDA_BUS_HOME/r/$k.jsonl.lock"; stale "$l" "$([ "$k" = dead ] && echo "$DEAD")"
  out="$(send "$k")" && grep -q "reclaimed the stale lock" <<<"$out" \
    && ok "$k: ripreso, e lo dice su stderr" || err "$k: non ripreso o in silenzio: $out"
  [ "$(wc -l < "$RDA_BUS_HOME/r/$k.jsonl" | tr -d ' ')" = 1 ] && [ ! -e "$l" ] \
    && ! ls -d "$l".* >/dev/null 2>&1 && ok "$k: messaggio scritto, niente lock/guard/tombstone" \
    || err "$k: messaggio perso o resti del lucchetto"
done

printf '\n=== log del bus: un owner VIVO non si riprende mai, anche se il lucchetto e vecchio ===\n'
# pid 1 e' vivo ma non nostro: `kill -0` li' fallisce con EPERM e lo ruberebbe.
( sleep 30 ) & LIVE=$!
for p in "$LIVE" 1; do
  l="$RDA_BUS_HOME/r/live.jsonl.lock"; stale "$l" "$p"
  out="$(send live)" && err "owner vivo (pid $p) ripreso: $out"
  grep -q "could not acquire the log lock" <<<"$out" && [ -f "$l/owner" ] \
    && [ ! -s "$RDA_BUS_HOME/r/live.jsonl" ] && ok "owner vivo (pid $p) -> scade come prima" \
    || err "owner vivo (pid $p): non e' scaduto, o ha scritto: $out"
  rm -rf "$l"
done
kill "$LIVE" 2>/dev/null; wait "$LIVE" 2>/dev/null || true

printf '\n=== log del bus: 16 mittenti partono dietro un lucchetto orfano ===\n'
# Tutti lo giudicano insieme; uno solo puo' riprenderlo, o un ritardatario
# rinominerebbe il lucchetto VIVO del vincitore e due append si mescolerebbero.
head -c 60000 < /dev/zero | tr '\0' 'x' > "$TMP/big"
stale "$RDA_BUS_HOME/r/conc.jsonl.lock"
for i in $(seq 1 16); do TRIES=600 send conc "$TMP/big" > "$TMP/conc.$i" & done; wait
jq -e . "$RDA_BUS_HOME/r/conc.jsonl" >/dev/null 2>&1 \
  && [ "$(wc -l < "$RDA_BUS_HOME/r/conc.jsonl" | tr -d ' ')" = 16 ] \
  && ok "16 append interi, nessuno mescolato o perso" || err "append mescolati o persi dietro un lucchetto ripreso"
# Un append da 60KB e' spesso una write sola, quindi un furto puo' non mescolare
# niente: si conta il furto stesso. Una seconda ripresa e' un lucchetto vivo rubato.
n="$(cat "$TMP"/conc.* | grep -c "reclaimed the stale lock")"
[ "$n" = 1 ] && ok "ripreso una volta sola" || err "ripreso $n volte: un ritardatario ha rubato un lucchetto vivo"

[ "$FAIL" -eq 0 ] && { echo "test-bus-lock: PASS"; exit 0; }
echo "test-bus-lock: FAIL"; exit 1
