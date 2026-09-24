# shellcheck shell=bash
# bus/bus-unread.sh — "da leggere": messages of ANY kind, unread by cursor, for a role.
#
# Split out of bus.sh because test/file-size-baseline.txt freezes bus.sh's length; new
# logic goes in a new small file instead. Sourced by bus.sh near the top, so BUS_HOME,
# BROADCAST, _cursor_path and _thread_state are already defined by the time any of this
# runs — they are called at request time, from _cmd_owed, never at source time.
#
# WHY THIS EXISTS, distinct from _owed_records: that one is scoped to
# kind=="question"/"request" on purpose — an ANSWER is owed only for those. A note or a
# verdict never appears there, so an unread one was invisible forever. Card 260924-120127:
# an agent checked only `bus owed` and read an important note late, and three threads of
# already-closed cards were still open because nothing ever closed them (see _cmd_close,
# unchanged, and kanban/kb-finish-bus.sh, which now calls it from `kb finish`).
#
# So this is gated on the READ CURSOR (same one `bus read` advances) instead of on a
# citation: any kind, unread, addressed to me or to `all`, and never something I sent
# myself — a note I wrote is not a debt I owe myself.
#
# NEVER RENDERS A BODY, not even in the non-brief form of `bus owed` — unlike
# _owed_records. A question can be BOTH owed (unanswered) and unread (uncleared cursor)
# at once, so a body preview here would print the same body a second time in one `bus
# owed` call. test-bus-owed.sh's 3c/3d checks count exact occurrences of a body fragment
# to prove citation and --brief semantics hold; a second occurrence from this section
# would make both wrong. Card/seq/sender/kind/time is enough to say "this exists, unread".

_unread_jq='
  if ((map(select(.kind == "closed" or .kind == "opened")) | last | .kind?) == "closed")
  then empty
  else
  to_entries
  | map(select((.value.to == $me or .value.to == $all) and .value.from != $me))
  | map(select((.key + 1) > $seen))
  | .[]
  | [$card, (.key + 1), .value.from, .value.kind, .value.ts]
  | @tsv
  end'

# Emits one TSV line per unread record: card, seq, from, kind, ts. No body — see header.
_unread_records() {
  local repo="$1" only_card="$2" me="$3" f card cur seen
  local dir="$BUS_HOME/$repo"
  [ -d "$dir" ] || return 0
  for f in "$dir"/*.jsonl; do
    [ -e "$f" ] || continue
    [ -s "$f" ] || continue
    card="${f##*/}"; card="${card%.jsonl}"
    [ -z "$only_card" ] || [ "$card" = "$only_card" ] || continue
    cur="$(_cursor_path "$repo" "$card" "$me")"
    seen=0
    if [ -f "$cur" ]; then
      seen="$(tr -d '[:space:]' < "$cur")"
      if ! [[ "$seen" =~ ^[0-9]+$ ]]; then
        echo "bus: WARNING — the cursor $cur is corrupt; counting from the start." >&2
        seen=0
      fi
    fi
    jq -r -s --arg me "$me" --arg all "$BROADCAST" --arg card "$card" --argjson seen "$seen" \
        "$_unread_jq" "$f" 2>/dev/null \
      || echo "bus: WARNING — $f is damaged and was skipped by owed." >&2
  done
}

# Printed as the second half of `bus owed`, AFTER the answer-owed section: a reader
# should see what they must ANSWER before what they merely have not READ.
_print_unread_section() {
  local repo="$1" card="$2" as="$3"
  local out; out="$(mktemp)"
  _unread_records "$repo" "$card" "$as" > "$out"
  echo
  if [ ! -s "$out" ]; then
    rm -f "$out"
    echo "bus: @$as has nothing unread on $repo${card:+/$card}."
    return 0
  fi
  echo "bus: $(grep -c . < "$out") message(s) are unread and addressed to @$as on $repo${card:+/$card} — DA LEGGERE, not necessarily owed an answer:"
  awk -F'\t' '{ printf "  %s #%s  from @%s (%s, %s)\n", $1, $2, $3, $4, $5 }' "$out"
  echo "Read them (nothing here is the body): bus read --repo $repo --card <CARD> --as $as"
  rm -f "$out"
}
