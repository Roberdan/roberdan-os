# shellcheck shell=bash
# kanban/kb-finish-bus.sh — close a card's bus thread when `kb finish` succeeds.
#
# Split out of kb.sh: test/file-size-baseline.txt freezes kb.sh's length, so new
# logic goes in a new small sourced file instead. Sourced by kb.sh near the top,
# called once, right before the card is moved to done/.
#
# WHY. Card 260924-120127: threads of already-closed cards stayed open forever,
# because nothing ever closed them — `bus tidy` exists to catch the backlog by
# hand, but the card finishing is the one moment the system already KNOWS the
# work is done, and it said nothing to the bus. `bus/bus.sh close` already exists
# (adds one record, deletes nothing — `bus log` still reads every word); this
# only wires the call.
#
# GUARDED, NEVER FAILING kb finish. A card with no bus thread is the common
# case (most cards never used the bus at all); a repo with no bus store, or no
# `repo:` field, is legitimate too. Every one of those is a silent no-op — the
# caller (kb.sh) never checks this function's exit status.
_kb_close_bus_thread() {
  local root="$1" repo="$2" id="$3" by="$4"
  local bus="$root/bus/bus.sh"
  [ -x "$bus" ] || [ -f "$bus" ] || return 0
  case "$repo" in
    '') return 0 ;;
    -*) return 0 ;;                       # looks like a flag, not a repo slug
    *[!A-Za-z0-9._-]*) return 0 ;;        # bus.sh would refuse it as a slug anyway
    *..*) return 0 ;;
  esac
  bash "$bus" close --repo "$repo" --card "$id" --by "${by:-orchestrator}" \
    >/dev/null 2>&1 || true
}
