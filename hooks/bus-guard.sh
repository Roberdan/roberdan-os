#!/usr/bin/env bash
# PreToolUse — E (bus pausa: deny EVERYTHING) + C (wake-origin: deny gate-class
# actions only). Card 260924-142220, @luca's threat model risk #1 (gate
# laundering) and #9 (kill switch). Modelled on hooks/factory-guard.sh's
# normalise-then-match shape — same denylist discipline, same "fail toward
# asking a human" posture, applied to an INTERACTIVE session instead of a
# headless one.
#
# Requires jq; without it this fails OPEN (exit 0) rather than dying, because it
# is a SECOND layer on top of the one that already exists for every session
# (main-guard/bash-guard/factory-guard) — losing this one narrows coverage, it
# does not remove the floor.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0

input="$(cat 2>/dev/null || true)"
deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

RDA_HOME="${RDA_HOME:-$HOME/.roberdan-os}"
sid="$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null | tr -cd 'A-Za-z0-9._-')"

# --- E: paused = deny everything, no carve-outs. Checked via `bus paused`,
# which reads the append-only pause log, never a flag whose deletion could be
# silently believed as "not paused" (bus/bus-brakes.sh).
BUS="${RDA_BUS_SH:-}"
if [ -z "$BUS" ]; then
  _top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$_top" ] && [ -x "$_top/bus/bus.sh" ] && BUS="$_top/bus/bus.sh"
fi
if [ -n "$BUS" ] && [ -x "$BUS" ]; then
  if [ "$(bash "$BUS" paused 2>/dev/null)" = "1" ]; then
    deny "bus pausa is active — every tool call is denied until: bus riprendi --by <role>. If you did not expect this, tell Roberto."
  fi
fi

# --- C: wake-origin turns never get a gate-class action, whatever the tool
# call looks like otherwise. The marker (bus mark-wake) is documented in
# bus-protocol.md as a recipe the agent follows on a wake, and
# hooks/bus-wake-clear.sh removes it the moment Roberto types for real.
WAKE_HOME="${RDA_BUS_WAKE:-$RDA_HOME/bus-wake}"
[ -n "$sid" ] && [ -e "$WAKE_HOME/$sid" ] || exit 0

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)"
fpath="$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""' 2>/dev/null)"
why="This turn was started by a bus wake, never typed by Roberto — gate-class actions are refused here (AGENTS.md human gates). Wait for Roberto, or ask on the bus and let a human-started turn act on the answer."

case "$fpath" in *"/.roberdan-os/private/"*) deny "$why (reading private/)";; esac
case "$cmd" in *"/.roberdan-os/private/"*) deny "$why (reading private/)";; esac

norm="$(printf '%s' "$cmd" | tr -d "\"'\\\\" | tr -s ' \t\n\r' ' ')"
hit() { printf '%s' "$norm" | grep -qE -- "$1"; }

hit '(^|[^[:alnum:]_-])(kb|kb\.sh)[[:space:]]+(start|finish)([[:space:]]|$)' \
  && deny "$why (kb start/finish)"
hit '(^|[^[:alnum:]_-])git([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+)*[[:space:]]+push([^[:alnum:]_-]|$)' \
  && deny "$why (git push)"
hit '(^|[^[:alnum:]_-])gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)' \
  && deny "$why (gh pr merge)"
hit '(^|[^[:alnum:]_-])rm[[:space:]]+(.*[[:space:]])?(-[[:alpha:]]*[rR][[:alpha:]]*f|-[[:alpha:]]*f[[:alpha:]]*[rR])' \
  && deny "$why (rm -rf / non-regenerable deletion)"
hit '(^|[^[:alnum:]_-])find[[:space:]].*[[:space:]]-delete([[:space:]]|$)' \
  && deny "$why (find -delete)"
hit '(^|[^[:alnum:]_-])(sendmail|mail)([[:space:]]|$)' \
  && deny "$why (mail/send)"
hit '(^|[^[:alnum:]_-])(npm[[:space:]]+publish|gh[[:space:]]+release|gem[[:space:]]+push)([[:space:]]|$)' \
  && deny "$why (publish)"

exit 0
