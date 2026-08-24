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
section "kb view: every card gets ONE line saying what it does, in aligned columns"
# The regression this pins is the board Roberto actually saw: three 34-wide columns could
# only hold "id (repo)", so DONE was a wall of opaque timestamps. What must hold now is
# (a) every printed card carries its summary on the same line as its id, (b) the id is never
# truncated, (c) a legacy card with no title: falls back to dod: instead of printing nothing,
# (d) the ids/repos are padded into columns that line up ACROSS sections.
_RB="$TMP/readable"; mkdir -p "$_RB"/{todo,doing,done}
printf -- '---\ntitle: Sort before cutting, perche la coda deve restare stabile\nrepo: VirtualBPMFy27\nstatus: todo\n---\n' > "$_RB/todo/260802-135739.md"
printf -- '---\ntitle: Rifare la TUI del kb\nrepo: roberdan-os\nstatus: doing\n---\n'                                     > "$_RB/doing/260824-1.md"
printf -- '---\nrepo: VirtualBPMFy27\ndod: "Legacy senza title; seconda clausola ignorata"\nstatus: done\n---\n'          > "$_RB/done/260731-170534-2.md"
_rb_out="$(COLUMNS=120 RDA_KANBAN="$_RB" bash kanban/kb.sh view 2>/dev/null)"

if printf '%s\n' "$_rb_out" | grep -qE '^ +260802-135739 +\(VirtualBPMFy27\) +Sort before cutting' \
   && printf '%s\n' "$_rb_out" | grep -qE '^ +260824-1 +\(roberdan-os\) +Rifare la TUI del kb'; then
  ok "todo/doing cards print id + (repo) + their title on one line"
else
  err "a card lost its summary line on the board — got: $_rb_out"
fi

# The longest id must appear in full: it is the key you type back into show/start/finish.
if printf '%s\n' "$_rb_out" | grep -q '260731-170534-2'; then
  ok "the id is printed whole (never truncated to fit)"
else
  err "the board truncated a card id — got: $_rb_out"
fi

# Legacy card, no title: — the board says what it SHOULD do (dod:) rather than nothing.
if printf '%s\n' "$_rb_out" | grep -qE '260731-170534-2 +\(VirtualBPMFy27\) +dod: Legacy senza title$'; then
  ok "a card with no title: falls back to the first clause of dod:"
else
  err "no-title card printed no summary (or leaked the whole dod) — got: $_rb_out"
fi

# Alignment: the summary of a TODO card and of a DONE card start at the same column, which
# is the whole point of measuring the widths across all three sections instead of per-section.
_c1="$(printf '%s\n' "$_rb_out" | grep    '260802-135739'  | head -1 | grep -bo 'Sort before' | cut -d: -f1)"
_c2="$(printf '%s\n' "$_rb_out" | grep    '260731-170534-2'| head -1 | grep -bo 'dod: Legacy' | cut -d: -f1)"
if [ -n "$_c1" ] && [ "$_c1" = "$_c2" ]; then
  ok "summaries start at the same column in every section (aligned as one table)"
else
  err "the summary column is not aligned across sections (todo=$_c1 done=$_c2) — got: $_rb_out"
fi

# An empty column must SAY it is empty: a blank gap looks like a render that died.
if printf '%s\n' "$_rb_out" | grep -qE 'DOING \(1\)' \
   && COLUMNS=120 RDA_KANBAN="$EMPTY" bash kanban/kb.sh view 2>/dev/null | grep -q '(vuota)'; then
  ok "an empty column renders (vuota) instead of a blank gap"
else
  err "empty column did not announce itself"
fi

# A narrow terminal must still produce ONE line per card (no wrapping, no crash).
_narrow="$(COLUMNS=62 RDA_KANBAN="$_RB" bash kanban/kb.sh view 2>/dev/null)"
# Width is measured in CHARACTERS (${#line}); awk/wc count bytes, and the box-drawing rule
# is 3 bytes per glyph — a byte check would call a correct 60-column rule "over-wide".
_over=0
while IFS= read -r _l; do [ "${#_l}" -gt 70 ] && _over=1; done <<< "$_narrow"
if [ -n "$_narrow" ] && [ "$_over" -eq 0 ]; then
  ok "at COLUMNS=62 every line is cut to width instead of wrapping"
else
  err "narrow terminal produced over-wide lines — got: $_narrow"
fi

if [ "$FAIL" -eq 0 ]; then printf "\ntest-kb-board: ✅ ALL GREEN\n"; else printf "\ntest-kb-board: ❌ FAIL (see above)\n"; fi
exit "$FAIL"
