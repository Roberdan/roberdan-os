#!/usr/bin/env bash
# test/test-kb-board.sh — the board must SAY what each card is.
#
# Why its own suite: the regression it pins is not a kb "view" plumbing question but a
# rendering contract — one line per card, id never truncated, columns aligned across the
# three sections, a summary even for a legacy card with no title:. test-kb-views.sh is
# already at its size-ratchet baseline, and this is a different property anyway.
#
# What Roberto saw before this file existed: three 34-wide columns that could only fit
# "id (repo)", so DONE was a wall of timestamps and learning what 260802-135739 was cost
# one `kb show` per card.
set -u
export RDA_KB_AUTOTHOR=0
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
section() { printf "\n=== %s ===\n" "$1"; }
ok()      { printf "  ok: %s\n" "$1"; }
err()     { printf "  FAIL: %s\n" "$1"; FAIL=1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
EMPTY="$TMP/empty"; mkdir -p "$EMPTY"/{todo,doing,done}

# ---------------------------------------------------------------------------
section "kb view: every card is described by a complete sentence, in aligned columns"
# The regression this pins is the board Roberto actually saw: three 34-wide columns could
# only hold "id (repo)", so DONE was a wall of opaque timestamps. Then the first fix cut the
# sentence at the column width, which he rejected for the same reason — half a sentence is
# not a synthesis. What must hold now:
#   (a) every card carries its sentence starting on the id's own line,
#   (b) NOTHING is truncated: a long sentence WRAPS under its own column,
#   (c) todo/doing also state the condition that finishes them ("Fatta quando: <dod>"),
#   (d) DONE stays compact (sentence only — it is history, not work ahead),
#   (e) the id is never cut, and columns line up ACROSS the three sections.
_RB="$TMP/readable"; mkdir -p "$_RB"/{todo,doing,done}
_LONG="Sort before cutting, perche la coda deve restare stabile anche quando arrivano molte card nuove nello stesso giorno e il taglio non deve perdere niente"
printf -- '---\ntitle: %s\nrepo: VirtualBPMFy27\ndod: "La coda resta stabile sotto carico; clausola due ignorata"\nstatus: todo\n---\n' "$_LONG" > "$_RB/todo/260802-135739.md"
printf -- '---\ntitle: Rifare la TUI del kb\nrepo: roberdan-os\nstatus: doing\n---\n'                                     > "$_RB/doing/260824-1.md"
printf -- '---\nrepo: VirtualBPMFy27\ndod: "Legacy senza title; seconda clausola ignorata"\nstatus: done\n---\n'          > "$_RB/done/260731-170534-2.md"
_W=110
_rb_out="$(COLUMNS=$_W RDA_KANBAN="$_RB" bash kanban/kb.sh view 2>/dev/null)"

if printf '%s\n' "$_rb_out" | grep -qE '^ +260802-135739 +\(VirtualBPMFy27\) +Sort before cutting' \
   && printf '%s\n' "$_rb_out" | grep -qE '^ +260824-1 +\(roberdan-os\) +Rifare la TUI del kb\.$'; then
  ok "each card opens with id + (repo) + the start of its sentence"
else
  err "a card lost its summary line on the board — got: $_rb_out"
fi

# (b) NOT truncated: the tail of a sentence too long for the column is still on the board,
# on a continuation line — and no line ends in the ellipsis the old renderer used to cut with.
# the tail of the sentence is on the board (on a later line — hence the two greps, not one
# phrase spanning the wrap), and no line was closed with the ellipsis the old renderer cut with.
if printf '%s\n' "$_rb_out" | grep -q 'perdere niente\.' \
   && ! printf '%s\n' "$_rb_out" | grep -q '…'; then
  ok "a long sentence wraps in full instead of being cut at the column width"
else
  err "the summary was truncated instead of wrapped — got: $_rb_out"
fi

# ...and the wrap is a CONTINUATION of the same column, not a line drifting left under the id.
_c_head="$(printf '%s\n' "$_rb_out" | grep -n 'Sort before cutting' | head -1 | cut -d: -f1)"
_head_col="$(printf '%s\n' "$_rb_out" | sed -n "${_c_head}p" | grep -bo 'Sort before' | cut -d: -f1)"
_cont_col="$(printf '%s\n' "$_rb_out" | sed -n "$((_c_head+1))p" | grep -bo '[^ ]' | head -1 | cut -d: -f1)"
if [ -n "$_head_col" ] && [ "$_head_col" = "$_cont_col" ]; then
  ok "continuation lines start exactly under the summary column"
else
  err "a wrapped line did not align with its column (head=$_head_col cont=$_cont_col) — got: $_rb_out"
fi

# (c) todo/doing say when they are finished; (d) DONE does not repeat its dod.
if printf '%s\n' "$_rb_out" | grep -q 'Fatta quando: La coda resta stabile sotto carico\.' \
   && ! printf '%s\n' "$_rb_out" | grep -q 'clausola due ignorata'; then
  ok "a todo card states its dod: as a second paragraph, first clause only"
else
  err "the dod: paragraph is missing or leaked its later clauses — got: $_rb_out"
fi

# (e) The longest id must appear in full: it is the key you type back into show/start/finish.
if printf '%s\n' "$_rb_out" | grep -q '260731-170534-2'; then
  ok "the id is printed whole (never truncated to fit)"
else
  err "the board truncated a card id — got: $_rb_out"
fi

# Legacy card, no title: — the board says what it SHOULD do (dod:) rather than nothing.
if printf '%s\n' "$_rb_out" | grep -qE '260731-170534-2 +\(VirtualBPMFy27\) +Fatta quando: Legacy senza title\.$'; then
  ok "a card with no title: is described by its dod: instead of printing nothing"
else
  err "no-title card printed no summary (or leaked the whole dod) — got: $_rb_out"
fi

# Alignment: a TODO sentence and a DONE sentence start at the same column, which is the whole
# point of measuring the widths across all three sections instead of per-section.
_c1="$(printf '%s\n' "$_rb_out" | grep '260802-135739'   | head -1 | grep -bo 'Sort before'   | cut -d: -f1)"
_c2="$(printf '%s\n' "$_rb_out" | grep '260731-170534-2' | head -1 | grep -bo 'Fatta quando'  | cut -d: -f1)"
if [ -n "$_c1" ] && [ "$_c1" = "$_c2" ]; then
  ok "summaries start at the same column in every section (aligned as one table)"
else
  err "the summary column is not aligned across sections (todo=$_c1 done=$_c2) — got: $_rb_out"
fi

# An empty column must SAY it is empty: a blank gap looks like a render that died.
if printf '%s\n' "$_rb_out" | grep -qE 'DOING \(1\)' \
   && COLUMNS=$_W RDA_KANBAN="$EMPTY" bash kanban/kb.sh view 2>/dev/null | grep -q '(vuota)'; then
  ok "an empty column renders (vuota) instead of a blank gap"
else
  err "empty column did not announce itself"
fi

# A narrow terminal must wrap to ITS width, not overflow it. Width is measured in CHARACTERS
# (${#line}); awk/wc count bytes, and the box rule is 3 bytes per glyph — a byte check would
# call a correct 60-column rule "over-wide".
_narrow="$(COLUMNS=62 RDA_KANBAN="$_RB" bash kanban/kb.sh view 2>/dev/null)"
_over=0
while IFS= read -r _l; do [ "${#_l}" -gt 70 ] && _over=1; done <<< "$_narrow"
if [ -n "$_narrow" ] && [ "$_over" -eq 0 ] && printf '%s\n' "$_narrow" | grep -q 'perdere niente'; then
  ok "at COLUMNS=62 the text wraps inside the width instead of overflowing or being cut"
else
  err "narrow terminal produced over-wide lines or lost text — got: $_narrow"
fi

if [ "$FAIL" -eq 0 ]; then printf "\ntest-kb-board: ✅ ALL GREEN\n"; else printf "\ntest-kb-board: ❌ FAIL (see above)\n"; fi
exit "$FAIL"
