# shellcheck shell=bash
# bus/bus-brakes.sh — hop/TTL cap, hourly budget, taking-collision, pause, wait.
#
# Split out of bus.sh for the same reason as bus-unread.sh and bus-trust.sh:
# test/file-size-baseline.txt freezes bus.sh's length. Sourced by bus.sh near the
# top, so BUS_HOME, RDA_HOME, `die`, `now`, `_log_path`, `_cursor_path`,
# `_ident_repo`, `_ident_role`, `_assert_role` already exist by call time.
#
# Card 260924-142220, @luca's threat model risk #5 (runaway swarm) and #6 (work
# collisions), plus item E of the card (kill switch) and F (the wake plumbing's
# data-only half). Everything here EXECUTES NOTHING beyond what bus.sh already
# does (jq, date, sleep, grep) — property 1 (bus never starts anyone) is
# untouched: the wake itself lives in the host (Monitor recipe / Copilot
# extension), never here. See bus-protocol.md for the recorded decision.

# --- pause -------------------------------------------------------------------
# An append-only log, same shape as thread close/open and presence hello/bye:
# state is DERIVED from the last event, never from a mutable flag whose deletion
# would silently undo it. `RDA_BUS_PAUSE_LOG` lets tests sandbox this like every
# other path here; the real one lives outside BUS_HOME (it is not a message, not
# presence) and outside any worktree (nothing to `git add` by accident).
PAUSE_LOG="${RDA_BUS_PAUSE_LOG:-$RDA_HOME/bus-pausa.jsonl}"

_brakes_pause_append() {
  local event="$1" by="$2" why="$3"
  mkdir -p "$(dirname "$PAUSE_LOG")" 2>/dev/null
  jq -cn --arg ts "$(now)" --arg event "$event" --arg by "$by" --arg why "$why" \
    '{ts:$ts,event:$event,by:$by,why:(if $why=="" then null else $why end)}' >> "$PAUSE_LOG" \
    || die "pausa: could not encode the record — nothing was appended"
}

# 0 = paused, 1 = not paused. Reads the LAST line only — cheap enough for a
# PreToolUse hook to call on every single tool call.
_brakes_paused() {
  [ -s "$PAUSE_LOG" ] || return 1
  [ "$(tail -n 1 "$PAUSE_LOG" | jq -r '.event' 2>/dev/null)" = "pausa" ]
}

_brakes_assert_not_paused() {
  _brakes_paused || return 0
  die "the bus is PAUSED (bus pausa) — nothing sends until: bus riprendi --by <role>"
}

# Pause also stops the queue-walking gate (goal-gate.sh), and riprendi undoes
# ONLY the flag this command itself created — never a goal-gate.off Roberto set
# for an unrelated reason. Provenance is one word written inside the file.
_cmd_pausa() {
  local by="" why=""
  while [ $# -gt 0 ]; do case "$1" in
    --by) _need $# "--by"; by="$2"; shift 2;;
    --why) _need $# "--why"; why="$2"; shift 2;;
    *) die "pausa: unknown argument '$1'";; esac done
  [ -n "$by" ] || by="$(_ident_role "$by" "pausa")"
  _assert_role "$by"
  _brakes_pause_append pausa "$by" "$why"
  local gg="$RDA_HOME/goal-gate.off"
  if [ ! -e "$gg" ]; then printf 'bus-pausa\n' > "$gg" 2>/dev/null || true; fi
  echo "bus: PAUSED by @$by${why:+ ($why)}. No sends, no wakes, every tool call denied until: bus riprendi --by <role>" >&2
}

_cmd_riprendi() {
  local by="" why=""
  while [ $# -gt 0 ]; do case "$1" in
    --by) _need $# "--by"; by="$2"; shift 2;;
    --why) _need $# "--why"; why="$2"; shift 2;;
    *) die "riprendi: unknown argument '$1'";; esac done
  [ -n "$by" ] || by="$(_ident_role "$by" "riprendi")"
  _assert_role "$by"
  local was_tampered=""
  if _brakes_paused; then :; else
    [ -s "$PAUSE_LOG" ] && was_tampered="the pause record already said resumed, or the log was never written — resuming anyway"
  fi
  local gg="$RDA_HOME/goal-gate.off"
  if [ -e "$gg" ] && [ "$(cat "$gg" 2>/dev/null)" = "bus-pausa" ]; then rm -f "$gg"; fi
  _brakes_pause_append riprendi "$by" "$why"
  echo "bus: RESUMED by @$by${why:+ ($why)}.${was_tampered:+ NOTE: $was_tampered — tell Roberto.}" >&2
}

_cmd_paused() {
  if _brakes_paused; then echo "1"; return 0; else echo "0"; return 1; fi
}

# --- wake-origin marker (item C) --------------------------------------------
# Claude Code has no harness signal a PreToolUse hook can read that says "this
# turn began from a Monitor notification, not from Roberto typing" — unlike
# Copilot, where the extension controls `session.send` directly. This is the
# declared, weaker half: the documented wake recipe (bus-protocol.md) has the
# agent call `bus mark-wake` the moment it acts on a wake, and
# hooks/bus-wake-clear.sh (UserPromptSubmit) deletes the marker the moment
# Roberto genuinely types — so the window this control covers is "between a
# wake and the next real keystroke", not the whole session, and it depends on
# the agent following the recipe rather than on the harness enforcing it.
WAKE_HOME="${RDA_BUS_WAKE:-$RDA_HOME/bus-wake}"
_cmd_mark_wake() {
  local session=""
  while [ $# -gt 0 ]; do case "$1" in
    --session) _need $# "--session"; session="$2"; shift 2;;
    *) die "mark-wake: unknown argument '$1'";; esac done
  session="$(_slug "--session" "$(_ident_session "$session")")"
  mkdir -p "$WAKE_HOME" 2>/dev/null || die "mark-wake: could not create $WAKE_HOME"
  printf '%s\n' "$(now)" > "$WAKE_HOME/$session" 2>/dev/null || die "mark-wake: could not write the marker"
  echo "bus: session $session marked wake-origin — gate-class tool calls are denied until Roberto types for real." >&2
}

# --- hop / TTL -----------------------------------------------------------
# A chain of replies (--re pointing at a --re pointing at a --re ...) is the
# shape a runaway ping-pong takes on this channel. Capped at 3, per the threat
# model. Bounded walk (10 links) against a corrupt or cyclic `re` graph — the
# cap fires either way, a hang never does.
_brakes_check_hops() {
  local log="$1" re="$2"
  [ -n "$re" ] || return 0
  local depth=0 cur="$re" guard=0
  while [ -n "$cur" ] && [ "$cur" != "null" ]; do
    depth=$((depth + 1)); guard=$((guard + 1))
    [ "$guard" -le 10 ] || break
    [ "$depth" -le 3 ] \
      || die "send: this reply chain is more than 3 hops deep (--re $re) — hop/TTL brake, bus-protocol.md. Take it to a human round, not another bus hop."
    cur="$(jq -s ".[$((cur - 1))].re // empty" "$log" 2>/dev/null)"
  done
}

# --- hourly budget ---------------------------------------------------------
# Derived from the append-only log itself — nothing counted or stored anywhere
# else, so there is no second number that can drift from the thread.
_brakes_check_hourly() {
  local log="$1" from="$2"
  [ -s "$log" ] || return 0
  local cap="${RDA_BUS_HOURLY_CAP:-20}" cutoff
  cutoff=$(( $(date -u +%s) - 3600 ))
  local n; n="$(jq -s --arg from "$from" --argjson cutoff "$cutoff" \
    '[.[] | select(.from == $from and ((.ts | fromdateiso8601) >= $cutoff))] | length' "$log" 2>/dev/null)"
  [ -n "$n" ] || n=0
  [ "$n" -lt "$cap" ] \
    || die "send: @$from has sent $n message(s) on this thread in the last hour (cap $cap, RDA_BUS_HOURLY_CAP) — runaway brake, bus-protocol.md."
}

# --- taking (work collisions) ----------------------------------------------
# Advisory-turned-structural: reading the log before writing to it is the same
# shape as the --re bounds check bus.sh already does, not a new kind of
# enforcement. First taker wins; a second `bus taking` on the same --re is
# refused outright, which is what makes "exactly one taking record" provable
# instead of merely likely.
_brakes_check_taking() {
  local log="$1" re="$2" as="$3"
  [ -s "$log" ] || return 0
  local prior; prior="$(jq -r --arg re "$re" --arg marker "TAKING #$re" --arg as "$as" \
    'select(.kind=="note" and (.body | startswith($marker)) and .from != $as) | .from' "$log" 2>/dev/null | head -1)"
  [ -z "$prior" ] \
    || die "send: @$prior is already taking #$re (bus log --repo <repo> --card <card>) — back off, this is a collision brake."
}

_cmd_taking() {
  local repo="" card="" as="" re=""
  while [ $# -gt 0 ]; do case "$1" in
    --repo) _need $# "--repo"; repo="$2"; shift 2;;
    --card) _need $# "--card"; card="$2"; shift 2;;
    --as)   _need $# "--as";   as="$2";   shift 2;;
    --re)   _need $# "--re";   re="$2";   shift 2;;
    *) die "taking: unknown argument '$1'";; esac done
  [ -n "$re" ] || die "taking: --re is required — which record are you taking"
  repo="$(_ident_repo "$repo")"; [ -n "$as" ] || as="$(_ident_role "$as" "taking")"
  repo="$(_slug "--repo" "$repo")"; card="$(_slug "--card" "$card")"
  _brakes_check_taking "$(_log_path "$repo" "$card")" "$re" "$as"
  printf 'TAKING #%s\n' "$re" | _cmd_send --repo "$repo" --card "$card" --from "$as" --to all --kind note --re "$re"
}

# --- wake: direct-unread count, never a body ------------------------------
# Same shape as _count_unread in bus.sh, narrowed to what the threat model says
# is allowed to wake anyone: a DIRECT (never broadcast) request or question.
_brakes_direct_unread() {
  local repo="$1" only_card="$2" me="$3" dir total=0 f card cur seen n
  dir="$BUS_HOME/$repo"
  [ -d "$dir" ] || { echo 0; return 0; }
  for f in "$dir"/*.jsonl; do
    [ -e "$f" ] || continue; [ -s "$f" ] || continue
    card="${f##*/}"; card="${card%.jsonl}"
    [ -z "$only_card" ] || [ "$card" = "$only_card" ] || continue
    cur="$(_cursor_path "$repo" "$card" "$me")"
    seen=0
    [ -f "$cur" ] && seen="$(tr -d '[:space:]' < "$cur")"
    [[ "$seen" =~ ^[0-9]+$ ]] || seen=0
    n="$(jq -s --arg me "$me" --argjson seen "$seen" \
      '[.[$seen:][] | select(.to == $me and (.kind == "request" or .kind == "question"))] | length' "$f" 2>/dev/null)"
    [ -n "$n" ] || n=0
    total=$((total + n))
  done
  echo "$total"
}

# One-shot version of the same count `bus wait` polls for — for a caller that
# already has its own event loop (the Copilot extension's `session.idle`) and
# must never block a process that also has to keep answering JSON-RPC.
_cmd_unread_direct() {
  local repo="" as="" card=""
  while [ $# -gt 0 ]; do case "$1" in
    --repo) _need $# "--repo"; repo="$2"; shift 2;;
    --card) _need $# "--card"; card="$2"; shift 2;;
    --as)   _need $# "--as";   as="$2";   shift 2;;
    *) die "unread-direct: unknown argument '$1'";; esac done
  repo="$(_ident_repo "$repo")"
  [ -n "$as" ] || as="$(_ident_role "$as" "unread-direct")"
  [ -n "$repo" ] || die "unread-direct: could not work out which repo this is — pass --repo"
  repo="$(_slug "--repo" "$repo")"; [ -z "$card" ] || card="$(_slug "--card" "$card")"
  _assert_role "$as"
  _brakes_direct_unread "$repo" "$card" "$as"
}

_cmd_wait() {
  local repo="" as="" card="" interval="${RDA_BUS_WAIT_INTERVAL:-5}" timeout="${RDA_BUS_WAIT_TIMEOUT:-0}"
  while [ $# -gt 0 ]; do case "$1" in
    --repo) _need $# "--repo"; repo="$2"; shift 2;;
    --card) _need $# "--card"; card="$2"; shift 2;;
    --as)   _need $# "--as";   as="$2";   shift 2;;
    *) die "wait: unknown argument '$1'";; esac done
  repo="$(_ident_repo "$repo")"
  [ -n "$as" ] || as="$(_ident_role "$as" "wait")"
  [ -n "$repo" ] || die "wait: could not work out which repo this is — pass --repo"
  repo="$(_slug "--repo" "$repo")"; [ -z "$card" ] || card="$(_slug "--card" "$card")"
  _assert_role "$as"
  local start; start=$(date -u +%s)
  while :; do
    local n; n="$(_brakes_direct_unread "$repo" "$card" "$as")"
    if [ "${n:-0}" -gt 0 ]; then
      echo "bus: $n new direct message(s) for @$as on $repo${card:+/$card} — bus read --repo $repo --card <CARD> --as $as"
      return 0
    fi
    if [ "$timeout" -gt 0 ]; then
      local elapsed; elapsed=$(( $(date -u +%s) - start ))
      [ "$elapsed" -lt "$timeout" ] || { echo "bus: wait timed out after ${timeout}s — nothing new for @$as."; return 1; }
    fi
    sleep "$interval"
  done
}
