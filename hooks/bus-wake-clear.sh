#!/usr/bin/env bash
# UserPromptSubmit — clears the wake-origin marker the moment Roberto types for
# real. Card 260924-142220, item C. Fires ONLY on genuine user input (the
# harness never synthesises this event for a hook or a Monitor notification),
# so the marker written by `bus mark-wake` is scoped to exactly the window
# between a wake and the next real keystroke — see bus/bus-brakes.sh and
# hooks/bus-guard.sh for the two ends of this control, and bus-protocol.md for
# the declared limit (this side is a recipe the agent follows, not a harness
# guarantee — unlike Copilot's, which controls session.send in code).
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0

input="$(cat 2>/dev/null || true)"
sid="$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null | tr -cd 'A-Za-z0-9._-')"
[ -n "$sid" ] || exit 0

RDA_HOME="${RDA_HOME:-$HOME/.roberdan-os}"
WAKE_HOME="${RDA_BUS_WAKE:-$RDA_HOME/bus-wake}"
rm -f "$WAKE_HOME/$sid" 2>/dev/null || true
exit 0
