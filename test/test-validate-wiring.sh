#!/usr/bin/env bash
# test-validate-wiring.sh — validate.sh launches its suites in parallel (`_spawn`) and collects
# them later (`_suite`). The two lists must stay in step, and nothing used to check that: on
# 2026-07-31 a `_suite test-bash-guard` was written without the matching `_spawn`, and the gate
# waited 15 minutes before declaring it hung. Twice — because a fifteen-minute stall looks like
# a slow suite, not like a bug in the gate itself.
#
# This runs the real functions out of validate.sh (extracted, not reimplemented: a copy would
# pass while the original rots) and asserts the missing name is reported in the first second.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
V="$ROOT/test/validate.sh"
fails=0
ok()  { printf '  ok   — %s\n' "$1"; }
err() { printf '  FAIL — %s\n' "$1"; fails=$((fails+1)); }

[ -f "$V" ] || { echo "  FAIL: $V non esiste"; exit 1; }

# Extract the launcher/collector block: from the _PARDIR assignment down to _suite_out.
# If validate.sh is ever restructured this extraction fails LOUDLY rather than silently
# testing nothing — that is the point of asserting on the extracted text first.
harness="$(awk '/^_PARDIR=/{f=1} f{print} /^_suite_out\(\)/{exit}' "$V")"
for needed in '_spawn()' '_suite()' '_SPAWNED'; do
  case "$harness" in
    *"$needed"*) ;;
    *) err "estrazione fallita: '$needed' non trovato in validate.sh — il test non sta provando niente"; echo "test-validate-wiring: FAIL"; exit 1 ;;
  esac
done
ok "funzioni _spawn/_suite estratte da validate.sh (non riscritte)"

run_case() { # run_case <script-body> -> prints "<seconds> <output>"
  local out start end
  start="$(date +%s)"
  out="$(bash -c "$harness
$1" 2>&1)"
  end="$(date +%s)"
  printf '%s\n%s' "$((end - start))" "$out"
}

# 1) The failure this file exists for: awaited, never launched.
res="$(run_case '_suite ghost-suite; echo "rc=$?"')"
secs="$(printf '%s' "$res" | head -1)"
body="$(printf '%s' "$res" | tail -n +2)"
case "$body" in
  *"never handed to _spawn"*) ok "una suite mai lanciata viene nominata esplicitamente" ;;
  *) err "nessun messaggio sul nome mai lanciato; output: $body" ;;
esac
case "$body" in
  *"rc=1"*) ok "e il gate fallisce (rc=1), non passa" ;;
  *) err "rc atteso 1; output: $body" ;;
esac
if [ "$secs" -le 5 ]; then
  ok "risponde in ${secs}s (soglia 5s; prima erano 900)"
else
  err "ci ha messo ${secs}s: la soglia dichiarata nella card e' 5s"
fi

# 2) The counterweight — the guard must not break the normal path. A suite that IS spawned
#    must still be waited for and must still return its own exit code, pass or fail.
res="$(run_case 'printf "#!/usr/bin/env bash\nexit 0\n" > "$_PARDIR/../fake-ok.sh"; _spawn_stub() { :; }; _SPAWNED="$_SPAWNED vera-suite"; printf "0" > "$_PARDIR/vera-suite.rc"; _suite vera-suite; echo "rc=$?"')"
case "$(printf '%s' "$res" | tail -n +2)" in
  *"rc=0"*) ok "una suite lanciata e conclusa con successo torna rc=0 (nessun blocco introdotto)" ;;
  *) err "una suite regolare non torna rc=0: $(printf '%s' "$res" | tail -n +2)" ;;
esac

res="$(run_case '_SPAWNED="$_SPAWNED rossa"; printf "1" > "$_PARDIR/rossa.rc"; _suite rossa; echo "rc=$?"')"
case "$(printf '%s' "$res" | tail -n +2)" in
  *"rc=1"*) ok "una suite lanciata e fallita torna rc=1 (il verdetto vero passa ancora)" ;;
  *) err "una suite fallita non torna rc=1: $(printf '%s' "$res" | tail -n +2)" ;;
esac

# 3) Ogni nome atteso dentro validate.sh e' davvero nella lista di lancio. Questo e' il
#    controllo statico che avrebbe preso l'errore del 31 luglio prima di eseguirlo.
# Solo nomi di suite vere (`test-...`): cosi' la prosa dei commenti che nomina _suite non
# viene scambiata per una chiamata.
awaited="$(grep -oE '_suite (test-[a-z0-9-]+)' "$V" | awk '{print $2}' | sort -u)"
# Lanciate = i token test-* che compaiono nella lista del for e sulle righe _spawn*.
have="$( { awk '/^for _s in /,/do$/' "$V"; grep -E '^_spawn(_serial_group)? ' "$V"; grep -E '^ *_spawn_serial_group ' "$V"; } \
        | grep -oE 'test-[a-z0-9-]+' | sort -u )"
missing=""
for a in $awaited; do
  printf '%s\n' "$have" | grep -qx "$a" || missing="$missing $a"
done
if [ -z "$missing" ]; then
  ok "ogni suite attesa in validate.sh compare anche fra quelle lanciate"
else
  err "attese ma mai lanciate:$missing"
fi

echo
if [ "$fails" -eq 0 ]; then echo "test-validate-wiring: PASS"; exit 0; fi
echo "test-validate-wiring: FAIL ($fails)"; exit 1
