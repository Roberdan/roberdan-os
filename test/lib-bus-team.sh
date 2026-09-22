#!/usr/bin/env bash
# lib-bus-team.sh — the fixture the two team suites share.
#
# SPLIT OUT 2026-09-22, and not by choice: the single file reached 431 lines and
# test/file-size-baseline.txt refuses a NEW file born over 300. The rule is right
# and it is mine to obey — a suite nobody can hold in their head is a suite whose
# checks stop being read. The seam is the subject, not the line count: one suite
# is about WHO IS HERE, the other about WHAT IS OWED and the noise that buried it.
# test-bus-team.sh — the bus works as a TEAM CHANNEL, not as a noticeboard.
#
# WHY THIS FILE EXISTS. test-bus.sh proves the bus is SAFE: it never starts an
# agent, never writes kanban state, never loses a message. Every one of those
# checks passed on 2026-09-22, on a store where the channel was not being used
# as a channel at all. Measured that morning, before anything here was written:
#
#     167 messages across 31 threads
#     13 threads with exactly ONE sender      — somebody talked, nobody answered
#     14 threads with NO reader cursor at all — nobody ever opened them
#      1 thread where a role read 37 of 38 messages and sent one
#
# Roberto's verdict, and it is the specification this file tests: "either they
# talk and nobody listens, or they listen and nobody talks."
#
# So this suite asserts the properties that make a conversation possible, and
# each check names the failure it would have caught. Safety stays in test-bus.sh;
# nothing here weakens it, and the two run together in validate.sh.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUS="$ROOT/bus/bus.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# RUN FROM THE TEMP DIRECTORY, NOT FROM THE CHECKOUT. `bus hello` leaves a
# `.bus-role` at the top of the worktree it is run in — that is the whole point
# of it — so a suite that ran from the repo would write into the real checkout,
# and when that checkout is a per-card worktree it also trips
# test-worktree-sweep.sh, which asserts that no suite creates or removes anything
# under ~/GitHub/worktrees. Caught exactly that way, by that suite, not by review.
cd "$TMP" || exit 1

export RDA_BUS_HOME="$TMP/bus"
R="team-repo"
C="260922-card"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

# Every call goes through a CLEAN environment. The identity features are the
# point of this suite, so inheriting the identity of the shell that runs the
# tests would make half of it pass for the wrong reason.
b() { env -u RDA_BUS_ROLE -u RDA_BUS_SESSION -u RDA_BUS_REPO \
        RDA_BUS_HOME="$RDA_BUS_HOME" bash "$BUS" "$@"; }
# A session: identity in the environment, the way a sub-process inherits it.
as() {
  local role="$1" sess="$2"; shift 2
  env RDA_BUS_ROLE="$role" RDA_BUS_SESSION="$sess" RDA_BUS_REPO="$R" \
      RDA_BUS_HOME="$RDA_BUS_HOME" bash "$BUS" "$@"
}

