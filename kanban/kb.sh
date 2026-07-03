#!/usr/bin/env bash
# kb — fast, GATED kanban CLI for roberdan-os. Cards are files in todo/ doing/ done/.
# Gates: todo->doing needs Roberto approval; doing->done needs @thor validation + evidence.
# Every card carries a Definition of Done + Acceptance criteria. See kanban/README.md.
set -euo pipefail

KB="${RDA_KANBAN:-$HOME/GitHub/roberdan-os/kanban}"
mkdir -p "$KB/todo" "$KB/doing" "$KB/done"
# repo ROOT (independent of $KB, which under tests points at a temp fixture
# dir) — needed so `kb plans`/`kb plan`/`kb sched` resolve docs/ and
# proposals/ from the real repo no matter what directory `kb` is invoked from.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
  # archived goals: one numbered table row each in _archive-*.md (rolled-up history)
  local narch; narch=$(grep -hE '^\| [0-9]+ \|' "$KB/done"/_archive-*.md 2>/dev/null | wc -l | tr -d ' ')
  local done_label=" ✅ DONE ($ntot"
  [ "$narch" -gt 0 ] && done_label="$done_label +$narch arch"
  done_label="$done_label)"
  local nt=${#T[@]} nd=${#D[@]} nn=${#N[@]} rows
  rows=$nt; [ $nd -gt $rows ] && rows=$nd; [ $nn -gt $rows ] && rows=$nn
  [ $rows -eq 0 ] && rows=1
  local ln; ln="$(printf '─%.0s' $(seq 1 $W))"
  printf '┌%s┬%s┬%s┐\n' "$ln" "$ln" "$ln"
  printf '│%-*s│%-*s│%-*s│\n' $W " 📋 TO DO ($nt)" $W " 🔵 DOING ($nd)" $W "$done_label"
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
  echo ' view:'
  echo '  kb                            view whole board (todo+doing+done)'
  echo '  kb list | kb ls                plain vertical list, all columns'
  echo '  kb todo | kb doing | kb done  view one column'
  echo '  kb show <id>                  show a card'
  echo ' gates:'
  echo '  kb add "<title>" [dod] [acc]  new card in todo'
  echo '  kb edit <id>                  edit a card (fill dod/acceptance)'
  echo '  kb start <id> --by roberto    GATE: todo->doing (needs your approval)'
  echo '  kb finish <id> --thor "<ev>"  GATE: doing->done (@thor validates + evidence)'
  echo '  kb block <id> "<reason>"      mark a card blocked, move back to todo/'
  echo ' detail (everything ever done, on demand):'
  echo '  kb history                    ALL work: done/ cards + every archived goal, newest first'
  echo '  kb archive [YYYY-MM-DD]       list archive files (counts) | cat one archive'
  echo '  kb plans                      list docs/plan-*.md (+ docs/archive/) with H1 + line count'
  echo '  kb plan <match>               print the plan whose filename contains <match>'
  echo ' ops:'
  echo '  kb sched                      launchd jobs + schedules + factory queue/failed + evolve proposals'
}

# ---------------------------------------------------------------------------
# kb history — everything ever done: individual done/ cards + every row rolled
# up into done/_archive-*.md. Most recent first. Read-only, on-demand detail
# (never loaded at session start — that budget is owned by todo/doing only).
_history() {
  echo "=== HISTORY — individual done/ cards (most recent verified first) ==="
  local f rows=() vat title id
  for f in "$KB/done"/*.md; do
    [ -e "$f" ] || continue
    case "$(basename "$f")" in _*) continue;; esac
    vat="$(_field "$f" verified_at)"; [ -n "$vat" ] || vat="$(_field "$f" created)"
    title="$(_field "$f" title)"
    id="$(basename "$f" .md)"
    rows+=("${vat:-0000-00-00}|$id|$title")
  done
  if [ "${#rows[@]}" -eq 0 ]; then
    echo "  (no individual done cards right now — see archives below)"
  else
    printf '%s\n' "${rows[@]}" | sort -t'|' -k1,1 -r | while IFS='|' read -r vat id title; do
      printf '  [%s] %s (verified %s)\n' "$id" "$title" "$vat"
    done || true
  fi
  echo
  echo "=== HISTORY — archived goals (newest archive first) ==="
  local afiles=()
  for f in "$KB/done"/_archive-*.md; do [ -e "$f" ] && afiles+=("$f"); done
  if [ "${#afiles[@]}" -eq 0 ]; then
    echo "  (no archives yet)"
    return 0
  fi
  local num goal status evidence
  for f in $(printf '%s\n' "${afiles[@]}" | sort -r); do
    echo
    echo "-- $(basename "$f") --"
    grep -E '^\| [0-9]+ \|' "$f" 2>/dev/null | while IFS='|' read -r _ num goal status evidence _; do
      num="$(echo "$num" | tr -d ' ')"
      goal="$(echo "$goal" | sed 's/^ *//; s/ *$//')"
      status="$(echo "$status" | sed 's/^ *//; s/ *$//')"
      evidence="$(echo "$evidence" | sed 's/^ *//; s/ *$//')"
      printf '  %s. %s [%s] — %s\n' "$num" "$goal" "$status" "$evidence"
    done || true
  done
  return 0
}

# kb archive [DATE] — list archive files with goal counts, or cat one by date.
_archive_cmd() {
  local date="${1:-}"
  if [ -z "$date" ]; then
    echo "ARCHIVES:"
    local f found=0 n
    for f in "$KB/done"/_archive-*.md; do
      [ -e "$f" ] || continue
      found=1
      n="$(grep -cE '^\| [0-9]+ \|' "$f" 2>/dev/null || true)"
      printf '  %-32s %s goal(s)\n' "$(basename "$f")" "${n:-0}"
    done
    [ "$found" -eq 0 ] && echo "  (no archives yet)"
    return 0
  fi
  local f="$KB/done/_archive-$date.md"
  if [ -e "$f" ]; then cat "$f"; else echo "no archive for '$date' (looked for $f)" >&2; return 1; fi
}

# kb plans — list docs/plan-*.md + docs/archive/plan-*.md (name, H1, line count).
_plans_list() {
  echo "PLANS:"
  local f h1 lines found=0
  for f in "$ROOT"/docs/plan-*.md "$ROOT"/docs/archive/plan-*.md; do
    [ -e "$f" ] || continue
    found=1
    h1="$(grep -m1 '^# ' "$f" 2>/dev/null || true)"; h1="${h1#\# }"
    lines="$(wc -l < "$f" | tr -d ' ')"
    printf '  %-60s %-4s lines  %s\n' "${f#"$ROOT"/}" "$lines" "$h1"
  done
  [ "$found" -eq 0 ] && echo "  (no plans found under docs/plan-*.md or docs/archive/plan-*.md)"
}

# kb plan <match> — print the plan whose filename contains <match>.
_plan_show() {
  local match="${1:?match required (e.g. kb plan tool-ind)}" f
  local -a matches=()
  for f in "$ROOT"/docs/plan-*.md "$ROOT"/docs/archive/plan-*.md; do
    [ -e "$f" ] || continue
    case "$f" in *"$match"*) matches+=("$f") ;; esac
  done
  case "${#matches[@]}" in
    0) echo "no plan matches '$match'" >&2; return 1 ;;
    1) cat "${matches[0]}" ;;
    *) echo "multiple plans match '$match':"; for f in "${matches[@]}"; do printf '  %s\n' "${f#"$ROOT"/}"; done ;;
  esac
}

# kb sched — one operative view of everything scheduled: launchd jobs +
# their human-readable schedule (from the plist) + factory queue/failed +
# latest evolve proposals. Every piece degrades to "n/a", never crashes.
_sched() {
  echo "=== SCHEDULED JOBS (launchctl) ==="
  local found=0
  if command -v launchctl >/dev/null 2>&1; then
    while IFS=$'\t' read -r pid exitcode label; do
      [ -n "${label:-}" ] || continue
      found=1
      printf '  %-8s exit=%-5s %s\n' "${pid:-?}" "${exitcode:-?}" "$label"
    done < <(launchctl list 2>/dev/null | awk -F'\t' '$3 ~ /^com\.roberdan\./' || true)
  fi
  [ "$found" -eq 0 ] && echo "  n/a (no com.roberdan.* jobs visible via launchctl list)"

  echo
  echo "=== SCHEDULES (from ~/Library/LaunchAgents plists) ==="
  local plist_dir="$HOME/Library/LaunchAgents" p label sched hour minute weekday interval hh mm
  if [ -d "$plist_dir" ] && command -v plutil >/dev/null 2>&1; then
    found=0
    for p in "$plist_dir"/com.roberdan.*.plist; do
      [ -e "$p" ] || continue
      found=1
      label="$(basename "$p" .plist)"
      hour="$(plutil -extract StartCalendarInterval.Hour raw "$p" 2>/dev/null || true)"
      minute="$(plutil -extract StartCalendarInterval.Minute raw "$p" 2>/dev/null || true)"
      weekday="$(plutil -extract StartCalendarInterval.Weekday raw "$p" 2>/dev/null || true)"
      interval="$(plutil -extract StartInterval raw "$p" 2>/dev/null || true)"
      if [ -n "$hour" ] || [ -n "$minute" ]; then
        hh="$(printf '%02d' "${hour:-0}")"; mm="$(printf '%02d' "${minute:-0}")"
        if [ -n "$weekday" ]; then sched="weekly (dow=$weekday) $hh:$mm"; else sched="daily $hh:$mm"; fi
      elif [ -n "$interval" ]; then
        sched="every ${interval}s"
      else
        sched="n/a (no StartCalendarInterval/StartInterval)"
      fi
      printf '  %-38s %s\n' "$label" "$sched"
    done
    [ "$found" -eq 0 ] && echo "  n/a (no com.roberdan.*.plist in $plist_dir)"
  else
    echo "  n/a (no $plist_dir or plutil unavailable)"
  fi

  echo
  echo "=== FACTORY STATE ==="
  local fdir="${RDA_FACTORY:-$HOME/.roberdan-os/factory}" qn fn
  if [ -d "$fdir" ]; then
    qn="$(ls "$fdir/queue" 2>/dev/null | wc -l | tr -d ' ' || true)"
    fn="$(ls "$fdir/failed" 2>/dev/null | wc -l | tr -d ' ' || true)"
    printf '  queue:  %s file(s) — %s\n' "${qn:-0}" "$fdir/queue"
    printf '  failed: %s file(s) — %s\n' "${fn:-0}" "$fdir/failed"
  else
    echo "  n/a (no factory dir at $fdir)"
  fi

  echo
  echo "=== EVOLVE PROPOSALS (latest 3) ==="
  if [ -d "$ROOT/proposals" ]; then
    local any=0 x
    for x in $(ls -t "$ROOT/proposals/" 2>/dev/null | head -3 || true); do any=1; echo "  $x"; done
    [ "$any" -eq 0 ] && echo "  n/a (proposals/ empty)"
  else
    echo "  n/a (no proposals/ dir at $ROOT/proposals)"
  fi
  return 0
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

  history) _history ;;
  archive) _archive_cmd "${1:-}" ;;
  plans)   _plans_list ;;
  plan)    _plan_show "${1:-}" ;;
  sched)   _sched ;;

  *) usage ;;
esac
