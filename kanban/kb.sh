#!/usr/bin/env bash
# kb — fast, GATED kanban CLI for roberdan-os. Cards are files in todo/ doing/ done/.
# Gates: todo->doing needs Roberto approval; doing->done needs @thor validation + evidence.
# Every card carries a Definition of Done + Acceptance criteria. See kanban/README.md.
set -euo pipefail

RDA_HOME="${RDA_HOME:-$HOME/.roberdan-os}"
# repo ROOT (independent of $KB, which under tests points at a temp fixture
# dir) — needed so `kb plans`/`kb plan`/`kb sched` resolve docs/ and
# proposals/ from the real repo no matter what directory `kb` is invoked from.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- Federation read-path (design §2a/§2b) ---------------------------------
# The registry (~/.roberdan-os/kanban-registry, local-only, one repo path per
# line, written by `kb init`) is the source of truth for "which repos have a
# federated, privacy-initialized board". A blind filesystem scan cannot tell an
# initialized board (gitignored + leak-check) from a raw kanban/ dir made by
# hand (the MirrorBuddy hazard) — so discovery is the explicit registry, never a
# scan. Parsing degrades to empty, never crashes.
REGISTRY="${RDA_KANBAN_REGISTRY:-$RDA_HOME/kanban-registry}"
_registry_repos() {
  [ -f "$REGISTRY" ] || return 0
  grep -vE '^[[:space:]]*(#|$)' "$REGISTRY" 2>/dev/null || true
}
_in_registry() {
  local p="$1" line
  while IFS= read -r line; do
    [ -n "$line" ] && [ "$line" = "$p" ] && return 0
  done < <(_registry_repos)
  return 1
}
# Board resolution (gbrain-pin style, design §2b):
#   RDA_KANBAN env  →  cwd's git repo IF it is roberdan-os itself OR registered
#                   →  else roberdan-os's own board (today's default — additive).
# KB_MATCHED=1: cwd resolved to a concrete recognized board (home or registered)
# or RDA_KANBAN was set. KB_MATCHED=0: we fell back — so the default `view`
# outside any recognized repo shows the aggregated board instead of home.
KB_MATCHED=0
KB=""
# Assigns the globals KB + KB_MATCHED directly (NOT via command substitution —
# a $(...) subshell would discard the KB_MATCHED assignment).
_resolve_kb() {
  if [ -n "${RDA_KANBAN:-}" ]; then KB_MATCHED=1; KB="$RDA_KANBAN"; return 0; fi
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$root" ] && { [ "$root" = "$ROOT" ] || _in_registry "$root"; }; then
    KB_MATCHED=1; KB="$root/kanban"; return 0
  fi
  KB_MATCHED=0; KB="$ROOT/kanban"
}
_resolve_kb
mkdir -p "$KB/todo" "$KB/doing" "$KB/done"
cmd="${1:-view}"; [ $# -gt 0 ] && shift || true

# portable mtime (macOS BSD stat first, GNU stat fallback, else 0)
# GNU (-c) FIRST: on macOS `stat -c` fails cleanly (unknown flag → exit 1, empty stdout) so the
# BSD `-f` fallback runs; the reverse order breaks on Linux, where `stat -f` means --file-system
# and prints multi-line garbage for `%m`+file instead of failing (CI-only bug, seen 2026-07-06).
_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }
# unique repo roots for aggregation: roberdan-os home first, then registry entries.
_board_roots() {
  printf '%s\n' "$ROOT"
  _registry_repos | while IFS= read -r r; do
    [ -n "$r" ] && [ "$r" != "$ROOT" ] && printf '%s\n' "$r"
  done
}

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
_repo_tag() {
  local repo; repo="$(_field "$1" repo)"
  printf '%s' "${repo:-—}"
}
# board cells are id-first (the id is the key you pass to show/start/finish — it must
# never be truncated). Append " (repo)" only when it fits within the column's content
# width; otherwise degrade to the bare id rather than corrupt it. Full repo+title is
# always available via `kb list`/`kb show`.
_board_cell() {
  local f="$1" w="$2" id repo cell
  id="$(basename "$f" .md)"
  repo="$(_repo_tag "$f")"
  cell="$id ($repo)"
  if [ "${#cell}" -le "$w" ]; then printf '%s' "$cell"; else printf '%s' "$id"; fi
}
_list() {
  local c="$1" any=0 f
  for f in "$KB/$c"/*.md; do
    [ -e "$f" ] || continue
    case "$(basename "$f")" in _*) continue;; esac
    any=1
    printf '  [%s] (%s) %s\n' "$(basename "$f" .md)" "$(_repo_tag "$f")" "$(_field "$f" title)"
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

# visual kanban: three columns side by side. Default: the current-repo board ($KB). With
# --all: the SAME three-column shape but aggregated across every registered board (home +
# registry), each card still tagged with its repo: via _board_cell. This is what `kb all`
# and `kb` outside a repo render — a real kanban, not a flat list.
_board() {
  local W=34 f i bd
  local w=$((W-2))
  local -a boards=()
  if [ "${1:-}" = "--all" ]; then
    echo "=== AGGREGATED BOARD — active cards across all registered repos ==="
    while IFS= read -r bd; do
      [ -n "$bd" ] && [ -d "$bd/kanban" ] && boards+=("$bd/kanban")
    done < <(_board_roots)
  fi
  [ "${#boards[@]}" -eq 0 ] && boards=("$KB")
  local -a T=() D=() N=()
  for bd in "${boards[@]}"; do
    for f in "$bd/todo"/*.md;  do [ -e "$f" ] || continue; case "$(basename "$f")" in _*) continue;; esac; T+=("$(_board_cell "$f" "$w")"); done
    for f in "$bd/doing"/*.md; do [ -e "$f" ] || continue; case "$(basename "$f")" in _*) continue;; esac; D+=("$(_board_cell "$f" "$w")"); done
  done
  # done: newest 10 across ALL selected boards, by mtime desc (cross-repo when aggregated)
  local -a drows=()
  for bd in "${boards[@]}"; do
    for f in "$bd/done"/*.md; do
      [ -e "$f" ] || continue
      case "$(basename "$f")" in _*) continue;; esac
      drows+=("$(_mtime "$f")|$f")
    done
  done
  local ntot=${#drows[@]}
  if [ "$ntot" -gt 0 ]; then
    while IFS='|' read -r _ f; do [ -n "$f" ] && N+=("$(_board_cell "$f" "$w")"); done \
      < <(printf '%s\n' "${drows[@]}" | sort -t'|' -k1,1 -rn | head -10)
  fi
  # archived goals: one numbered table row each in _archive-*.md (rolled-up history).
  # Pre-existing bug found while testing this function on a fixture with zero archive
  # files: the bare glob passed straight to grep/pipefail died under `set -e` when it
  # didn't match anything (grep tried to open the literal string "_archive-*.md",
  # failed, and pipefail propagated that failure into killing the whole script) — never
  # triggered on the real board because it always has at least one archive file. Loop
  # with an existence check instead, same convention as _archive_hint/_archive_cmd below.
  local narch=0 _af
  for bd in "${boards[@]}"; do
    for _af in "$bd/done"/_archive-*.md; do
      [ -e "$_af" ] || continue
      narch=$((narch + $(grep -cE '^\| [0-9]+ \|' "$_af" 2>/dev/null || true)))
    done
  done
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
  echo '  kb                            view whole board (todo+doing+done); aggregate if outside a repo'
  echo '  kb all | kb g                 AGGREGATED view across every registered board (cards tagged repo:)'
  echo '  kb handoff                    per-repo handoff/latest.md (in a repo) or aggregated (outside)'
  echo '  kb list | kb ls                plain vertical list, all columns'
  echo '  kb todo | kb doing | kb done  view one column'
  echo '  kb show <id>                  show a card'
  echo ' federation:'
  echo '  kb init [repo]                make a repo safe to hold cards (gitignore+de-track+hook+register; idempotent)'
  echo '  kb lint                       schema lint: runner: grammar + human_gates:↔human-only'
  echo '  kb dispatch <id> [cli]        restricted external-CLI dispatcher — DORMANT (hard-wired to refuse)'
  echo ' gates:'
  echo '  kb add "<title>" --repo <r> [dod] [acc]  new card in todo (repo = ~/GitHub dir-name, or "personal")'
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
  local f rows=() vat title id repo
  for f in "$KB/done"/*.md; do
    [ -e "$f" ] || continue
    case "$(basename "$f")" in _*) continue;; esac
    vat="$(_field "$f" verified_at)"; [ -n "$vat" ] || vat="$(_field "$f" created)"
    title="$(_field "$f" title)"
    repo="$(_repo_tag "$f")"
    id="$(basename "$f" .md)"
    rows+=("${vat:-0000-00-00}|$id|$repo|$title")
  done
  if [ "${#rows[@]}" -eq 0 ]; then
    echo "  (no individual done cards right now — see archives below)"
  else
    printf '%s\n' "${rows[@]}" | sort -t'|' -k1,1 -r | while IFS='|' read -r vat id repo title; do
      printf '  [%s] (%s) %s (verified %s)\n' "$id" "$repo" "$title" "$vat"
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
  local fdir="${RDA_FACTORY:-$RDA_HOME/factory}" qn fn
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

# kb all / kb g — the aggregated view is `_board --all` (real three-column kanban across
# every registered board, cards tagged with repo:). A flat-list variant used to live here;
# it was replaced by the board shape (design §2b, @rex #2; Roberto's preference for the
# kanban form). `kb list`/`kb ls` remains the plain vertical list.

# kb handoff — inside a recognized repo: that repo's handoff/latest.md. Otherwise
# (aggregate): concatenate every registered repo's handoff/latest.md newest-first
# by mtime, each section tagged with its repo (design §2b). handoff-protocol.md /
# context-primer.md stay versioned canon and are not touched here.
_handoff() {
  if [ "$KB_MATCHED" -eq 1 ]; then
    local root="${KB%/kanban}" hf
    hf="$root/handoff/latest.md"
    if [ -f "$hf" ]; then cat "$hf"; else echo "(no handoff/latest.md in $(basename "$root"))"; fi
    return 0
  fi
  local root hf rows=() any=0
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    hf="$root/handoff/latest.md"
    [ -f "$hf" ] || continue
    any=1
    rows+=("$(_mtime "$hf")|$root")
  done < <(_board_roots)
  if [ "$any" -eq 0 ]; then echo "(no handoff/latest.md across registered boards)"; return 0; fi
  printf '%s\n' "${rows[@]}" | sort -t'|' -k1,1 -r | while IFS='|' read -r _ root; do
    echo "=== handoff — $(basename "$root") ==="
    cat "$root/handoff/latest.md"
    echo
  done
  return 0
}

# kb init [repo] — the single act that makes a repo safe to hold federated cards
# (design §2e). Idempotent. GATE: never point this at a shared external repo
# (MirrorBuddy / FightTheStroke) — federating those is a human decision. It only
# scaffolds the repo path you pass (default: roberdan-os itself).
_kb_init() {
  local target="${1:-$ROOT}" root gi line f tracked_handoff=0
  root="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -z "$root" ]; then echo "kb init: '$target' is not inside a git repo" >&2; return 1; fi
  echo "kb init: initializing federated board in $root"

  # 1) scaffold
  mkdir -p "$root/kanban/todo" "$root/kanban/doing" "$root/kanban/done" "$root/handoff"

  # CARD content lives ONLY in the three column subdirs — NEVER bare kanban/,
  # which in roberdan-os also holds tracked tooling (kb.sh, README.md). De-track
  # and the history scan therefore target the columns, not kanban/.
  local -a card_paths=(kanban/todo/ kanban/doing/ kanban/done/)

  # is handoff/latest.md already TRACKED? roberdan-os tracks it as canon-ish live
  # state — design §5 note: do NOT silently change that tracking. When tracked we
  # FLAG it and leave gitignore/de-track/history-scan of it alone.
  if git -C "$root" ls-files --error-unmatch handoff/latest.md >/dev/null 2>&1; then
    tracked_handoff=1
  fi

  # 2) gitignore-append (idempotent; never rewrite the target's gitignore wholesale)
  gi="$root/.gitignore"; touch "$gi"
  local -a need=(kanban/todo/ kanban/doing/ kanban/done/)
  [ "$tracked_handoff" -eq 0 ] && need+=(handoff/latest.md)
  for line in "${need[@]}"; do
    if ! grep -qxF "$line" "$gi" 2>/dev/null; then
      printf '%s\n' "$line" >> "$gi"; echo "  gitignore += $line"
    fi
  done
  if [ "$tracked_handoff" -eq 1 ]; then
    echo "  FLAG: handoff/latest.md is TRACKED in $(basename "$root") — federating it as"
    echo "        gitignored state is a SEPARATE human decision (design §5 note); NOT changed."
  fi

  # 3) de-track already-committed CARD content (git rm --cached, keep working copy)
  local tracked
  tracked="$(git -C "$root" ls-files "${card_paths[@]}" 2>/dev/null || true)"
  if [ -n "$tracked" ]; then
    printf '%s\n' "$tracked" | while IFS= read -r f; do
      [ -n "$f" ] && git -C "$root" rm --cached --quiet "$f" 2>/dev/null || true
    done
    echo "  de-tracked already-committed card content (working copies kept)"
  fi
  if [ "$tracked_handoff" -eq 0 ] && git -C "$root" ls-files --error-unmatch handoff/latest.md >/dev/null 2>&1; then
    git -C "$root" rm --cached --quiet handoff/latest.md 2>/dev/null || true
    echo "  de-tracked handoff/latest.md"
  fi

  # 4) scan LOCAL history for card content already committed (the blob survives
  #    git rm --cached). pushed -> HUMAN GATE #4 (refuse); local-only -> loud warn.
  local -a scan_paths=("${card_paths[@]}")
  [ "$tracked_handoff" -eq 0 ] && scan_paths+=(handoff/latest.md)
  local hits pushed_hits="" local_hits="" sha
  hits="$(git -C "$root" log --all --pretty=%H -- "${scan_paths[@]}" 2>/dev/null || true)"
  if [ -n "$hits" ]; then
    while IFS= read -r sha; do
      [ -n "$sha" ] || continue
      if [ -n "$(git -C "$root" branch -r --contains "$sha" 2>/dev/null)" ]; then
        pushed_hits="$pushed_hits $sha"
      else
        local_hits="$local_hits $sha"
      fi
    done <<EOF_SCAN
$hits
EOF_SCAN
  fi
  if [ -n "$pushed_hits" ]; then
    {
      echo ""
      echo "kb init: REFUSED — card/handoff content is in PUSHED history (human gate #4):"
      for sha in $pushed_hits; do git -C "$root" --no-pager log -1 --oneline "$sha"; done
      echo "  This is deletion of already-published data — escalate to Roberto (git filter-repo"
      echo "  or repo recreate). kb init does NOT scrub published history automatically."
    } >&2
    return 1
  fi
  if [ -n "$local_hits" ]; then
    {
      echo ""
      echo "kb init: WARNING — card/handoff content in LOCAL-ONLY (un-pushed) commits:"
      for sha in $local_hits; do git -C "$root" --no-pager log -1 --oneline "$sha"; done
      echo "  git rm --cached de-tracks forward, but the blob REMAINS in local history."
      echo "  Do NOT push these branches; scrub (git filter-repo / rebase) before any push."
    } >&2
  fi

  # 5) pre-commit hook: roberdan-os leak-check on the staged tree (interactive
  #    safety; --no-verify-bypassable, so NOT the runner's gate — design §2e#5).
  #    Idempotent — never clobber an existing leak-check hook.
  local hookdir hook
  hookdir="$(git -C "$root" rev-parse --absolute-git-dir 2>/dev/null)/hooks"; hook="$hookdir/pre-commit"
  mkdir -p "$hookdir"
  if [ -f "$hook" ] && grep -q 'leak-check' "$hook" 2>/dev/null; then
    echo "  pre-commit hook already runs leak-check (left as-is)"
  else
    cat > "$hook" <<HOOK
#!/usr/bin/env bash
# installed by roberdan-os \`kb init\` — runs roberdan-os leak-check on the staged
# tree before every commit (interactive safety; bypassable with --no-verify, so
# it is NOT the runner's gate — that lives in the dispatcher, design §2e#5).
set -euo pipefail
RDA_LEAKCHECK="$ROOT/test/leak-check.sh"
if [ -x "\$RDA_LEAKCHECK" ]; then
  if ! bash "\$RDA_LEAKCHECK"; then
    echo "pre-commit: BLOCKED — confidential term(s) detected (see above)." >&2
    exit 1
  fi
fi
HOOK
    chmod +x "$hook"
    echo "  installed pre-commit leak-check hook -> $hook"
  fi

  # 6) register (idempotent)
  mkdir -p "$(dirname "$REGISTRY")"; touch "$REGISTRY"
  if ! grep -qxF "$root" "$REGISTRY" 2>/dev/null; then
    printf '%s\n' "$root" >> "$REGISTRY"; echo "  registered $root in $REGISTRY"
  else
    echo "  already registered in $REGISTRY"
  fi
  echo "kb init: done (idempotent). This does NOT make the repo runner-eligible"
  echo "         (that is the separate, narrower runner-allowlist)."
  return 0
}

case "$cmd" in
  view|board|"")                   # visual kanban (default); aggregate if cwd
    if [ "$KB_MATCHED" -eq 0 ]; then _board --all; else _board; fi
    ;;
  init) _kb_init "${1:-$ROOT}" ;;  # scaffold + privatize a repo's board (idempotent)
  lint) RDA_KANBAN="$KB" bash "$ROOT/kanban/lint-cards.sh" ;;  # runner/human_gates schema lint
  dispatch) bash "$ROOT/factory/dispatch-runner.sh" "$@" ;;   # restricted external-CLI dispatcher (DORMANT — always refuses)
  all|g) _board --all ;;           # aggregated three-column board across the registry
  handoff) _handoff ;;             # per-repo (in a repo) or aggregated live state
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
    # --repo can appear anywhere among the args; everything else stays positional
    # (title, then optional dod, then optional acceptance), same as before.
    repo=""; args=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --repo) repo="${2:-}"; shift 2 ;;
        *) args+=("$1"); shift ;;
      esac
    done
    title="${args[0]:?title required}"; dod="${args[1]:-FILL: definition of done}"; acc="${args[2]:-FILL: acceptance criteria (how @thor verifies)}"
    if [ -z "$repo" ]; then
      echo "REFUSED: --repo required — which repo/scope is this card about? e.g.:" >&2
      echo "  kb add \"$title\" --repo roberdan-os [dod] [acc]" >&2
      echo "  (use the ~/GitHub dir-name for a code repo, or 'personal' for non-repo work)" >&2
      exit 1
    fi
    id="$(date +%y%m%d-%H%M%S)"
    { echo '---'; echo "title: $title"; echo "repo: $repo"; echo "dod: \"$dod\""; echo "acceptance: \"$acc\""; echo 'status: todo'; echo "created: $(date +%Y-%m-%d)"; echo '---'; } > "$KB/todo/$id.md"
    echo "added todo/$id (repo: $repo)"
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
    repo_val="$(_field "$f" repo)"
    if [ -z "$repo_val" ] || printf '%s' "$repo_val" | grep -q 'FILL:'; then
      echo "REFUSED: fill repo first (kb edit $id) — e.g. repo: roberdan-os, repo: convergio, repo: personal" >&2; exit 1
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
