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
# So they are all started here, at once, and each section below then blocks on
# its own result and prints exactly the line it printed before. The report a
# human reads is unchanged and still deterministic; only the waiting is gone.
# A suite that needs its output (not just its exit code) reads _suite_out.
_PARDIR="$(mktemp -d "${TMPDIR:-/tmp}/rda-validate.XXXXXX")"
trap 'rm -rf "$_PARDIR"' EXIT INT TERM

# Launched names land here; _suite refuses any name missing from it. On 2026-07-31 a _suite
# without its _spawn stalled the gate 15 minutes — twice, since a stall reads as a slow suite.
_SPAWNED=""
_spawn() {
  _SPAWNED="$_SPAWNED $1"
  # Write the exit code LAST and atomically: _suite treats the .rc file as the
  # signal that the .out file is complete, so a half-written .out must never be
  # reachable through a present .rc.
  ( bash "test/$1.sh" > "$_PARDIR/$1.out" 2>&1
    printf '%s' "$?" > "$_PARDIR/$1.rc.part" && mv "$_PARDIR/$1.rc.part" "$_PARDIR/$1.rc" ) &
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
  _SPAWNED="$_SPAWNED $*"
  ( for _g in "$@"; do
      bash "test/$_g.sh" > "$_PARDIR/$_g.out" 2>&1
      printf '%s' "$?" > "$_PARDIR/$_g.rc.part" && mv "$_PARDIR/$_g.rc.part" "$_PARDIR/$_g.rc"
    done ) &
}

_suite() {
  local rc_file="$_PARDIR/$1.rc" waited=0
  # Never wait for something nobody launched: a bug in this file, not a slow suite.
  case " $_SPAWNED " in *" $1 "*) ;;
    *) printf '  FAIL: %s is awaited by _suite but was never handed to _spawn — add it to the launch list in this file\n' "$1"; return 1 ;;
  esac
  while [ ! -f "$rc_file" ]; do
    sleep 0.2
    waited=$((waited+1))
    # 15 minutes. A suite that has not finished by then is hung, and hanging
    # forever inside a CI gate is the one failure mode nobody ever debugs.
    if [ "$waited" -gt 4500 ]; then
      printf '  FAIL: %s did not finish within 15 minutes (hung)\n' "$1"
      return 1
    fi
  done
  return "$(cat "$rc_file")"
}

_suite_out() { cat "$_PARDIR/$1.out" 2>/dev/null; }
