#!/usr/bin/env bash
# lib-suites.sh — il MOTORE del gate: lancia le suite in parallelo (_spawn) e le raccoglie in
# ordine (_suite), cosi' il rapporto che legge un umano resta sequenziale mentre l'attesa sparisce.
#
# Vive in un file suo dal 2026-08-01: test/validate.sh era arrivato a 623 righe ed era cresciuto
# quattro volte in un giorno solo. Separare il motore dall'indice e' la meta' del taglio; l'altra
# meta' sono i controlli, che ora stanno ognuno nel proprio test/test-*.sh.
#
# SI SOURCEA, non si esegue: chi lo sourcea possiede `set -u`, $ROOT e le funzioni ok/err.
# --- the suites run CONCURRENTLY, the report stays sequential ----------------
# Every test/test-*.sh below is a separate process with its own fixtures under
# its own temp dir; nothing they do depends on the order they run in. The old
# sequential invocation therefore bought nothing but wall clock: measured on
# this machine, the same 17 suites take 289s one after another and 47s started
# together — the wall clock was the ORDERING, not the tests.
#
# A bounded pool avoids starving the tests' own timing assertions as the suite
# inventory grows. The report stays ordered; no test timeout is increased.
# A suite that needs its output (not just its exit code) reads _suite_out.
# Dentro @thor, con la CI gia' verde sullo stesso commit, la suite non riparte: 15 minuti per
# ridire cio' che GitHub ha gia' detto (2026-09-14, due verifiche, una in timeout).
if [ "${RDA_IN_THOR_VERIFY:-0}" = "1" ] && [ -n "${RDA_THOR_CI_GREEN:-}" ] \
   && [ "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)" = "$RDA_THOR_CI_GREEN" ]; then
  echo "validate: CI GitHub gia' verde su $RDA_THOR_CI_GREEN — dentro @thor non si rilancia, usa quella prova."
  exit 0
fi
_PARDIR="$(mktemp -d "${TMPDIR:-/tmp}/rda-validate.XXXXXX")"
trap 'rm -rf "$_PARDIR"' EXIT INT TERM
_MAX_JOBS="${RDA_VALIDATE_JOBS-4}"
case "$_MAX_JOBS" in [1-9]|[12][0-9]|3[0-2]) ;;
  *) printf 'validate: RDA_VALIDATE_JOBS must be an integer from 1 to 32\n' >&2; exit 2 ;;
esac

# Launched names land here; _suite refuses any name missing from it. On 2026-07-31 a _suite
# without its _spawn stalled the gate 15 minutes — twice, since a stall reads as a slow suite.
_SPAWNED=""
_wait_slot() {
  local running _pid progress="" observed="" since=$SECONDS
  while :; do
    running=0
    for _pid in $(jobs -pr); do running=$((running+1)); done
    [ "$running" -lt "$_MAX_JOBS" ] && return 0
    if [ -f "$_PARDIR/progress" ]; then
      IFS= read -r progress < "$_PARDIR/progress"
    fi
    if [ "$progress" != "$observed" ]; then
      observed="$progress"; since=$SECONDS
    fi
    if [ "$((SECONDS-since))" -ge 900 ]; then
      printf '  FAIL: validation workers made no scheduling progress within 15 minutes (hung)\n' >&2
      exit 1
    fi
    sleep 0.1
  done
}
_run_suite() {
  local name="$1" rc=0
  printf '%s' "$(date +%s)" > "$_PARDIR/$name.start"
  printf '%s\n' "$name" > "$_PARDIR/$name.progress"
  mv "$_PARDIR/$name.progress" "$_PARDIR/progress"
  bash "test/$name.sh" > "$_PARDIR/$name.out" 2>&1 || rc=$?
  printf '%s' "$rc" > "$_PARDIR/$name.rc.part" && mv "$_PARDIR/$name.rc.part" "$_PARDIR/$name.rc"
}
_spawn() {
  _wait_slot
  _SPAWNED="$_SPAWNED $1"
  # Write the exit code LAST and atomically: _suite treats the .rc file as the
  # signal that the .out file is complete, so a half-written .out must never be
  # reachable through a present .rc.
  ( _run_suite "$1" ) &
}

# Some suites are NOT independent of each other, and pretending otherwise is how
# a parallel gate becomes a flaky gate. test-sync-install and test-copilot-adapter
# both call `bin/sync.sh --install` without RDA_SYNC_OUT, so both regenerate
# platforms/ INSIDE THE CHECKOUT. Their shared state is the working tree, not
# $HOME (both isolate $HOME correctly). Run together they raced and
# test-sync-install went red — observed, not theorised.
#
# So they are pinned into one background job and run sequentially INSIDE it:
# they still overlap every other suite, they just never overlap each other.
# The honest alternative is to teach both to emit into a private directory; that
# is a change to what the tests exercise, and it does not belong in a commit
# about wall clock.
_spawn_serial_group() {
  _wait_slot
  _SPAWNED="$_SPAWNED $*"
  ( for _g in "$@"; do
      # QUANDO QUESTA SUITE E' PARTITA DAVVERO. Le cinque del gruppo girano in
      # FILA, e senza questo segnale il budget di 15 minuti di _suite partiva da
      # quando si comincia ad aspettare: l'ultima della fila pagava anche l'attesa
      # delle altre quattro e veniva dichiarata "hung". Misurato il 2026-09-22:
      # test-twin-install passa da solo in 2m48s e veniva riportato bloccato in
      # tre validazioni di fila. Un limite che scatta sul caso sano non e' un
      # margine, e' un rosso a caso — e un rosso a caso su un innocente insegna a
      # non leggere piu' il referto.
      _run_suite "$_g"
    done ) &
}

_suite() {
  local rc_file="$_PARDIR/$1.rc" waited=0
  # Never wait for something nobody launched: a bug in this file, not a slow suite.
  case " $_SPAWNED " in *" $1 "*) ;;
    *) printf '  FAIL: %s is awaited by _suite but was never handed to _spawn — add it to the launch list in this file\n' "$1"; return 1 ;;
  esac
  local started=0
  while [ ! -f "$rc_file" ]; do
    sleep 0.2
    waited=$((waited+1))
    # 15 minutes OF ITS OWN RUN. A suite queued behind others in a serial group
    # has not started yet, and counting that queue against it turns a slow
    # neighbour into its failure. The countdown restarts the moment this suite
    # actually begins; both launch paths publish the same start marker.
    if [ "$started" = "0" ] && [ -f "$_PARDIR/$1.start" ]; then
      started=1; waited=0
    fi
    if [ "$waited" -gt 4500 ]; then
      printf '  FAIL: %s did not finish within 15 minutes (hung)\n' "$1"
      return 1
    fi
  done
  return "$(cat "$rc_file")"
}

_suite_out() { cat "$_PARDIR/$1.out" 2>/dev/null; }
