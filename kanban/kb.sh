#!/usr/bin/env bash
# kb — fast, GATED kanban CLI for roberdan-os. Cards are files in todo/ doing/ done/.
# Gates: todo->doing needs Roberto approval; doing->done needs @thor validation + evidence.
# Every card carries a Definition of Done + Acceptance criteria. See kanban/README.md.
set -euo pipefail

KB="${RDA_KANBAN:-$HOME/GitHub/roberdan-os/kanban}"
mkdir -p "$KB/todo" "$KB/doing" "$KB/done"
cmd="${1:-view}"; [ $# -gt 0 ] && shift || true

_field() { grep -m1 "^$2:" "$1" 2>/dev/null | sed "s/^$2:[[:space:]]*//; s/^\"//; s/\"\$//"; }
# Portable in-place status edit: `sed -i ''` is BSD-only syntax (macOS) and breaks under
# GNU sed (Linux) — it treats the empty string as the script and the real script as a
# filename, dying with "No such file or directory". Redirect-to-temp-then-move works
# identically on both.
_set_status() {
  local f="$1" v="$2" tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/rda-kb.XXXXXX")"
  sed "s/^status:.*/status: $v/" "$f" > "$tmp" && mv "$tmp" "$f"
}
_list() {
  local c="$1" any=0 f
  for f in "$KB/$c"/*.md; do
    [ -e "$f" ] || continue
    case "$(basename "$f")" in _*) continue;; esac
    any=1
    printf '  [%s] %s\n' "$(basename "$f" .md)" "$(_field "$f" title)"
  done
  if [ "$any" -eq 0 ]; then echo "  (empty)"; fi
  return 0
}

# DONE (0) doesn't mean "nothing was ever done" — closed cards get periodically rolled up
# into _archive-*.md (audit trail, not loaded every session) and removed as individual files.
# Print a one-line pointer so a 0 count isn't mistaken for an empty history.
_archive_hint() {
  local f archives=()
  for f in "$KB/done"/_*.md; do [ -e "$f" ] && archives+=("$(basename "$f")"); done
  [ "${#archives[@]}" -eq 0 ] && return 0
  echo "  (past work archived in kanban/done/${archives[*]} — read on demand, not counted above)"
}

# visual kanban: three columns side by side
_board() {
  local W=26 f i
  local -a T=() D=() N=()
  for f in "$KB/todo"/*.md;  do [ -e "$f" ] && T+=("$(basename "$f" .md)"); done
  for f in "$KB/doing"/*.md; do [ -e "$f" ] && D+=("$(basename "$f" .md)"); done
  # done: show last 10 (newest first), skip the _archive narrative file
  while IFS= read -r f; do [ -n "$f" ] && N+=("$(basename "$f" .md)"); done \
    < <(ls -t "$KB/done"/*.md 2>/dev/null | grep -v '/_' | head -10)
  local ntot; ntot=$(ls "$KB/done"/*.md 2>/dev/null | grep -vc '/_' || true)
  local nt=${#T[@]} nd=${#D[@]} nn=${#N[@]} rows
  rows=$nt; [ $nd -gt $rows ] && rows=$nd; [ $nn -gt $rows ] && rows=$nn
  [ $rows -eq 0 ] && rows=1
  local ln; ln="$(printf '─%.0s' $(seq 1 $W))"
  printf '┌%s┬%s┬%s┐\n' "$ln" "$ln" "$ln"
  printf '│%-*s│%-*s│%-*s│\n' $W " 📋 TO DO ($nt)" $W " 🔵 DOING ($nd)" $W " ✅ DONE ($ntot, last 10)"
  printf '├%s┼%s┼%s┤\n' "$ln" "$ln" "$ln"
  local w=$((W-2))
  for ((i=0; i<rows; i++)); do
    printf '│ %-*.*s │ %-*.*s │ %-*.*s │\n' \
      $w $w "${T[$i]:-}" $w $w "${D[$i]:-}" $w $w "${N[$i]:-}"
  done
  printf '└%s┴%s┴%s┘\n' "$ln" "$ln" "$ln"
  _archive_hint
}

usage() {
  echo 'kb — gated kanban. Commands:'
  echo '  kb                            view whole board (todo+doing+done)'
  echo '  kb todo | kb doing | kb done  view one column'
  echo '  kb show <id>                  show a card'
  echo '  kb add "<title>" [dod] [acc]  new card in todo'
  echo '  kb edit <id>                  edit a card (fill dod/acceptance)'
  echo '  kb start <id> --by roberto    GATE: todo->doing (needs your approval)'
  echo '  kb finish <id> --thor "<ev>"  GATE: doing->done (@thor validates + evidence)'
  echo '  kb block <id> "<reason>"      mark a card blocked, move back to todo/'
}

case "$cmd" in
  view|board|"") _board ;;        # visual kanban (default)
  list|ls)                         # plain vertical list
    echo "TO DO:";  _list todo
    echo "DOING:";  _list doing
    n=$(ls "$KB/done"/*.md 2>/dev/null | grep -vc '/_' || true)
    echo "DONE ($n):"; _list done; _archive_hint
    ;;

  show)
    id="${1:?id required}"; f=""
    for c in todo doing done; do [ -e "$KB/$c/$id.md" ] && f="$KB/$c/$id.md"; done
    [ -n "$f" ] && cat "$f" || { echo "no card $id" >&2; exit 1; }
    ;;

  add)
    title="${1:?title required}"; dod="${2:-FILL: definition of done}"; acc="${3:-FILL: acceptance criteria (how @thor verifies)}"
    id="$(date +%y%m%d-%H%M%S)"
    { echo '---'; echo "title: $title"; echo "dod: \"$dod\""; echo "acceptance: \"$acc\""; echo 'status: todo'; echo "created: $(date +%Y-%m-%d)"; echo '---'; } > "$KB/todo/$id.md"
    echo "added todo/$id"
    ;;

  start)
    id="${1:?id required}"; by=""; [ "${2:-}" = "--by" ] && by="${3:-}"
    f="$KB/todo/$id.md"; [ -e "$f" ] || { echo "no todo card $id" >&2; exit 1; }
    # DISCIPLINE gate, not a security boundary: --by is honor-system — any caller can pass
    # `--by roberto`. There is deliberately no blocking check here (that would break the
    # documented "do all the todos" autonomous flow). Instead, every kb start ATTEMPT — even
    # a refused one — gets an audit line appended to the card: who claimed it, when, and
    # whether it came from an interactive terminal. Bypasses are honor-system but not
    # invisible; see kanban/README.md.
    interactive=no; [ -t 0 ] && interactive=yes
    printf 'kb_start_audit: "at=%s by=%s interactive=%s"\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${by:-(unset)}" "$interactive" >> "$f"
    if [ -z "$by" ]; then echo "REFUSED: todo->doing is a human gate. Approve with: kb start $id --by roberto" >&2; exit 1; fi
    if _field "$f" dod | grep -q 'FILL:' || _field "$f" acceptance | grep -q 'FILL:'; then
      echo "REFUSED: fill Definition of Done + Acceptance first (kb edit $id)" >&2; exit 1
    fi
    _set_status "$f" doing
    { echo "approved_by: $by"; echo "approved_at: $(date +%Y-%m-%d)"; } >> "$f"
    mv "$f" "$KB/doing/"; echo "doing/$id started (approved by $by)"
    ;;

  block)
    id="${1:?id required}"; reason="${2:?reason required}"
    f=""
    [ -e "$KB/todo/$id.md" ] && f="$KB/todo/$id.md"
    [ -e "$KB/doing/$id.md" ] && f="$KB/doing/$id.md"
    [ -n "$f" ] || { echo "no todo/doing card $id" >&2; exit 1; }
    _set_status "$f" blocked
    { echo "blocked_reason: \"$reason\""; echo "blocked_at: $(date +%Y-%m-%d)"; } >> "$f"
    [ "$(dirname "$f")" = "$KB/todo" ] || mv "$f" "$KB/todo/"
    echo "todo/$id blocked: $reason"
    ;;

  todo|doing) echo "$(echo "$cmd" | tr a-z A-Z):"; _list "$cmd" ;;
  done) n=$(ls "$KB/done"/*.md 2>/dev/null | grep -vc '/_' || true); echo "DONE ($n):"; _list done; _archive_hint ;;

  finish)
    id="${1:?id required}"; ev=""; [ "${2:-}" = "--thor" ] && ev="${3:-}"
    f="$KB/doing/$id.md"; [ -e "$f" ] || { echo "no doing card $id" >&2; exit 1; }
    if [ -z "$ev" ]; then
      echo "REFUSED: doing->done needs @thor validation with EVIDENCE (not a rubber-stamp)." >&2
      echo "  Run @thor vs the acceptance criteria, then: kb finish $id --thor '<commit/test/output>'" >&2
      exit 1
    fi
    _set_status "$f" done
    { echo 'verified_by: thor'; echo "verified_evidence: $ev"; echo "verified_at: $(date +%Y-%m-%d)"; } >> "$f"
    mv "$f" "$KB/done/"; echo "done/$id verified by @thor ($ev)"
    ;;

  edit)
    id="${1:?id required}"; f=""
    for c in todo doing done; do [ -e "$KB/$c/$id.md" ] && f="$KB/$c/$id.md"; done
    [ -n "$f" ] || { echo "no card $id" >&2; exit 1; }
    "${EDITOR:-open}" "$f"
    ;;

  *) usage ;;
esac
