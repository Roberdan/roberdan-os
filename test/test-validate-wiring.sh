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
ENG="$ROOT/test/lib-suites.sh"   # il motore vive qui dal 2026-08-01
fails=0
ok()  { printf '  ok   — %s\n' "$1"; }
err() { printf '  FAIL — %s\n' "$1"; fails=$((fails+1)); }

[ -f "$V" ] || { echo "  FAIL: $V non esiste"; exit 1; }
[ -f "$ENG" ] || { echo "  FAIL: $ENG non esiste — il motore e' stato spostato di nuovo?"; exit 1; }

# Extract the launcher/collector block: from the _PARDIR assignment down to _suite_out.
# If validate.sh is ever restructured this extraction fails LOUDLY rather than silently
# testing nothing — that is the point of asserting on the extracted text first.
harness="$(awk '/^_PARDIR=/{f=1} f{print} /^_suite_out\(\)/{exit}' "$ENG")"
for needed in '_spawn()' '_suite()' '_SPAWNED'; do
  case "$harness" in
    *"$needed"*) ;;
    *) err "estrazione fallita: '$needed' non trovato in lib-suites.sh — il test non sta provando niente"; echo "test-validate-wiring: FAIL"; exit 1 ;;
  esac
done
ok "funzioni _spawn/_suite estratte da lib-suites.sh (non riscritte)"

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

_collection_names() {
  awk '{
    sub(/[[:space:]]*#.*/, "")
    if ($0 ~ /(^|[^_[:alnum:]])_suite[[:space:]]/) print
  }' "$@" | grep -oE 'test-[a-z0-9-]+' | sort -u
}

# 3) Every real collection site must have a matching launch. A helper contributes
# only when validate.sh actively sources it; reading detached helper files would
# let a removed source line hide launched-but-ignored suites.
collection_files=("$V")
privacy_active=0
while IFS= read -r helper; do
  helper_path="$ROOT/test/$helper"
  if [ ! -f "$helper_path" ]; then
    err "modulo di validazione incluso ma assente: $helper"
    continue
  fi
  collection_files+=("$helper_path")
  [ "$helper" != "validate-privacy.sh" ] || privacy_active=1
done < <(sed -n 's@^[[:space:]]*\.[[:space:]]*"\$ROOT/test/\(validate-[a-z0-9-]*\.sh\)".*@\1@p' "$V")
awaited="$( {
  _collection_names "${collection_files[@]}"
  [ "$privacy_active" -eq 0 ] \
    || awk -F'|' '/^[a-z-]+\|test-[a-z0-9-]+\|/{print $2}' "$ROOT/test/validate-privacy.sh"
} | sort -u )"
# Lanciate = i token test-* che compaiono nella lista del for e sulle righe _spawn*.
spawn_lines="$(awk '{
  sub(/[[:space:]]*#.*/, "")
  if ($0 ~ /(^|[^_[:alnum:]])_spawn(_serial_group)?[[:space:]]/) print
}' "${collection_files[@]}")"
have="$( { awk '/^for _s in /,/do$/' "$V"; printf '%s\n' "$spawn_lines"; } \
        | grep -oE 'test-[a-z0-9-]+' | sort -u )"
bad_dynamic="$(printf '%s\n' "$spawn_lines" | grep -F '$' \
  | grep -vE '^[[:space:]]*_spawn[[:space:]]+"\$_s"[[:space:]]*$' || true)"
if [ -z "$bad_dynamic" ]; then
  ok "gli spawn dinamici usano solo la lista dichiarata for _s"
else
  err "spawn dinamici non analizzabili:$bad_dynamic"
fi
missing=""
for a in $awaited; do
  printf '%s\n' "$have" | grep -qx "$a" || missing="$missing $a"
done
if [ -z "$missing" ]; then
  ok "ogni suite attesa in validate.sh compare anche fra quelle lanciate"
else
  err "attese ma mai lanciate:$missing"
fi

# 4) The inverse matters just as much: a suite can be launched successfully and
# never collected, leaving validate.sh green even when that child exits red.
collected="$awaited"
ignored=""
for a in $have; do
  printf '%s\n' "$collected" | grep -qx "$a" || ignored="$ignored $a"
done
if [ -z "$ignored" ]; then
  ok "ogni suite lanciata in validate.sh viene anche raccolta nel verdetto"
else
  err "lanciate ma mai raccolte:$ignored"
fi

required="test-kb-board-resolution test-kb-board-hostile test-worktree-registry test-validate-wiring"
missing_required=""
for a in $required; do
  printf '%s\n' "$have" | grep -qx "$a" \
    && printf '%s\n' "$collected" | grep -qx "$a" \
    || missing_required="$missing_required $a"
done
if [ -z "$missing_required" ]; then
  ok "le suite di sicurezza kb restano obbligatorie, non ritirabili in blocco"
else
  err "suite di sicurezza kb mancanti dal contratto:$missing_required"
fi

swallowed="$(awk '{
  sub(/[[:space:]]*#.*/, "")
  if ($0 ~ /_suite[[:space:]].*(\|\|[[:space:]]*(true|:)|;[[:space:]]*true)/) print
}' "${collection_files[@]}")"
if [ -z "$swallowed" ]; then
  ok "nessuna raccolta _suite puo' scartare il proprio fallimento con true"
else
  err "fallimenti _suite esplicitamente scartati:$swallowed"
fi

# A diagnostic-only mention must never satisfy the collection test.
probe="$(mktemp "${TMPDIR:-/tmp}/validate-wiring-probe.XXXXXX")"
trap 'rm -f "$probe"' EXIT
printf '%s\n' '# _suite test-comment-only' '_suite_out test-output-only' > "$probe"
if [ -z "$(_collection_names "$probe")" ]; then
  ok "commenti e _suite_out non possono mascherare una suite ignorata"
else
  err "il parser considera ancora raccolti commenti o sole stampe diagnostiche"
fi
rm -f "$probe"
trap - EXIT

echo
if python3 -B "$ROOT/test/test-validation-scheduling.py"; then
  ok "limite concorrente, gruppo seriale e codici reali provati sul motore"
else
  err "scheduler: concorrenza o propagazione degli errori non rispettata"
fi
if [ "$fails" -eq 0 ]; then echo "test-validate-wiring: PASS"; exit 0; fi
echo "test-validate-wiring: FAIL ($fails)"; exit 1
