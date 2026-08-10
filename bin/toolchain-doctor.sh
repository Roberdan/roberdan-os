#!/usr/bin/env bash
# toolchain-doctor.sh — catch the agent-toolchain failures that are SILENT.
#
# doctor.sh answers "is the dependency installed?". This answers a different
# question: "is the thing that IS installed actually doing its job?". Every
# check here corresponds to a failure that shipped no error message and was
# only found by accident:
#
#   - gstack's setup never links lib/, so 13 binaries die on import and every
#     learning, decision and question-log write is lost without a warning.
#   - artifacts_sync_mode can say "full" while ~/.gstack is not a git repo,
#     so the sync silently does nothing and nothing is ever backed up.
#   - gbrain code-def can return 0 for every symbol while code-refs still
#     works, which reads as "no results" rather than "the index is damaged".
#   - /sync-gbrain leaves _capability_check_<pid>.md files inside repos.
#
# Never installs or repairs anything: prints the exact command and lets a
# human run it, same contract as doctor.sh.
#
# Exit codes: 0 = nothing broken, 1 = at least one silent failure found.
#
# Usage:
#   bin/toolchain-doctor.sh            # human-readable report
#   bin/toolchain-doctor.sh --quiet    # only problems
#   bin/toolchain-doctor.sh --json     # machine-readable, for CI or a hook
#   bin/toolchain-doctor.sh --symbol X # probe gbrain code-def with symbol X

set -uo pipefail

PATH="$HOME/.bun/bin:$HOME/.local/bin:$PATH"

MODE="report"
SYMBOL="validateAuth"
while [ $# -gt 0 ]; do
  case "$1" in
    --json)   MODE="json" ;;
    --quiet)  MODE="quiet" ;;
    --symbol) SYMBOL="${2:-}"; shift ;;
    -h|--help)
      sed -n '2,27p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) printf 'toolchain-doctor: unknown flag %s (try --help)\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

if [ -t 1 ] && [ "$MODE" != "json" ]; then
  C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_BAD=$'\033[31m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_OK=""; C_WARN=""; C_BAD=""; C_DIM=""; C_OFF=""
fi

BROKEN=0
DEGRADED=0
JSON_ROWS=""

# emit NAME STATUS DETAIL IMPACT FIX
# status: ok | broken | degraded
emit() {
  local name="$1" status="$2" detail="${3:-}" impact="${4:-}" fix="${5:-}"
  case "$status" in
    broken)   BROKEN=$((BROKEN+1)) ;;
    degraded) DEGRADED=$((DEGRADED+1)) ;;
  esac

  if [ "$MODE" = json ]; then
    local row
    row=$(printf '{"name":"%s","status":"%s","detail":"%s","impact":"%s","fix":"%s"}' \
      "$name" "$status" "${detail//\"/\\\"}" "${impact//\"/\\\"}" "${fix//\"/\\\"}")
    JSON_ROWS="${JSON_ROWS:+$JSON_ROWS,}$row"
    return
  fi

  if [ "$MODE" = quiet ] && [ "$status" = ok ]; then return; fi

  local mark colour
  case "$status" in
    ok)       mark="ok   "; colour="$C_OK" ;;
    broken)   mark="BROKE"; colour="$C_BAD" ;;
    degraded) mark="warn "; colour="$C_WARN" ;;
    *)        mark="?    "; colour="$C_WARN" ;;
  esac

  printf '%s%s%s %-18s %s\n' "$colour" "$mark" "$C_OFF" "$name" "${C_DIM}${detail}${C_OFF}"
  if [ "$status" != ok ]; then
    [ -n "$impact" ] && printf '       %sbreaks:%s %s\n' "$C_DIM" "$C_OFF" "$impact"
    [ -n "$fix" ]    && printf '       %sfix:%s    %s\n' "$C_DIM" "$C_OFF" "$fix"
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

if [ "$MODE" != json ]; then
  printf '\n%stoolchain doctor%s  %ssilent-failure checks%s\n\n' "$C_OFF" "$C_OFF" "$C_DIM" "$C_OFF"
fi

# --- 1. gstack lib/ symlink -------------------------------------------------
# ~/.copilot/skills/gstack is itself a symlink to ~/.codex/skills/gstack, so
# resolve before reporting or one install is counted twice.
CANON="$HOME/.claude/skills/gstack"
SEEN=""
ROOTS=""
for root in "$HOME/.codex/skills/gstack" "$HOME/.copilot/skills/gstack"; do
  [ -e "$root" ] || continue
  real=$(cd "$root" 2>/dev/null && pwd -P) || continue
  case " $SEEN " in *" $real "*) continue ;; esac
  SEEN="$SEEN $real"
  ROOTS="$ROOTS $root"
  name=$(basename "$(dirname "$(dirname "$root")")")
  if [ -e "$root/lib" ]; then
    emit "gstack-lib[$name]" ok "lib/ present"
  else
    emit "gstack-lib[$name]" broken "lib/ missing" \
      "13 gstack binaries fail on import: learnings, decisions, question-log and telemetry are lost silently" \
      "ln -s $CANON/lib $root/lib"
  fi
done

# --- 2. lib/ resolves on the LOGICAL path bun uses --------------------------
# Binaries resolve ../lib against the logical path, not the resolved symlink,
# so "the file exists" is not the same as "bun can import it". Running a
# binary with no arguments is NOT a valid probe: gstack-learnings-log dies on
# an unbound variable before it ever reaches the import.
for root in $ROOTS; do
  name=$(basename "$(dirname "$(dirname "$root")")")
  [ -x "$root/bin/gstack-learnings-log" ] || continue
  if ! have bun; then
    emit "gstack-import[$name]" degraded "bun not on PATH, cannot probe" \
      "the import check is skipped; a broken lib/ would go unnoticed" \
      "install bun, then re-run"
    continue
  fi
  if bun -e "await import(process.argv[1])" "$root/bin/../lib/jsonl-store.ts" >/dev/null 2>&1; then
    emit "gstack-import[$name]" ok "lib/jsonl-store.ts imports"
  else
    emit "gstack-import[$name]" broken "cannot import lib/jsonl-store.ts" \
      "same 13 binaries are dead even though the path looks right" \
      "ln -s $CANON/lib $root/lib"
  fi
done

# --- 3. learnings durability ------------------------------------------------
MODE_CFG="off"
[ -x "$CANON/bin/gstack-config" ] && \
  MODE_CFG=$("$CANON/bin/gstack-config" get artifacts_sync_mode 2>/dev/null || echo off)
if [ -d "$HOME/.gstack/.git" ]; then
  emit "learnings-backup" ok "$HOME/.gstack is a git repo (mode=$MODE_CFG)"
elif [ "$MODE_CFG" != "off" ]; then
  emit "learnings-backup" broken "artifacts_sync_mode=$MODE_CFG but $HOME/.gstack is not a git repo" \
    "every learning, decision and plan artifact lives on this Mac only; the config claims otherwise" \
    "gstack-artifacts-init  (or: gstack-config set artifacts_sync_mode off)"
else
  emit "learnings-backup" degraded "local-only, sync off (config is at least honest)" \
    "nothing is backed up; a disk failure loses every learning" \
    "gstack-artifacts-init"
fi

# --- 4. gbrain symbol extraction --------------------------------------------
# gbrain embed used to NULL every tree-sitter metadata column on conflict
# (garrytan/gbrain#3705, fixed 2026-08-01). The fix stops new damage but does
# not repair indexes already wiped, and code-def just returns 0 results.
if ! have gbrain; then
  emit "gbrain-symbols" degraded "gbrain not on PATH" \
    "semantic and symbol lookup unavailable; skills fall back to grep" \
    "install gbrain, expected at $HOME/.bun/bin/gbrain"
elif [ ! -f .gbrain-source ]; then
  emit "gbrain-symbols" degraded "no .gbrain-source pin in $(pwd)" \
    "cannot tell which source to probe; run from a pinned worktree" \
    "cd into a worktree pinned by /sync-gbrain --full"
else
  PIN=$(cat .gbrain-source)
  CNT=$(timeout 90 gbrain code-def "$SYMBOL" 2>/dev/null \
        | python3 -c 'import sys,json;print(json.load(sys.stdin).get("count",0))' 2>/dev/null || echo 0)
  if [ "${CNT:-0}" -gt 0 ] 2>/dev/null; then
    emit "gbrain-symbols" ok "code-def resolves on '$PIN' ($SYMBOL: $CNT)"
  else
    emit "gbrain-symbols" broken "code-def returns 0 for '$SYMBOL' on '$PIN'" \
      "symbol metadata was wiped (gbrain#3705); code-refs still works so this reads as 'no results'" \
      "gbrain reindex-code --source $PIN --force --yes   (--force is absent from gbrain --help)"
  fi
fi

# --- 5. capability-check litter ---------------------------------------------
if TOP=$(git rev-parse --show-toplevel 2>/dev/null); then
  LITTER=$(find "$TOP" -maxdepth 1 -name '_capability_check_*.md' 2>/dev/null | wc -l | tr -d ' ')
  if [ "$LITTER" = "0" ]; then
    emit "capability-litter" ok "no stray files in $(basename "$TOP")"
  else
    emit "capability-litter" degraded "$LITTER stray _capability_check_*.md in $(basename "$TOP")" \
      "/sync-gbrain writes them via gbrain put and gbrain delete does not remove them from disk" \
      "rm $TOP/_capability_check_*.md"
  fi
else
  emit "capability-litter" ok "not inside a git repo, nothing to check"
fi

if [ "$MODE" = json ]; then
  printf '{"broken":%d,"degraded":%d,"checks":[%s]}\n' "$BROKEN" "$DEGRADED" "$JSON_ROWS"
elif [ "$BROKEN" -gt 0 ]; then
  printf '\n%s%d silent failure(s).%s %d degraded.\n\n' "$C_BAD" "$BROKEN" "$C_OFF" "$DEGRADED"
else
  printf '\n%snothing silently broken.%s %d degraded.\n\n' "$C_OK" "$C_OFF" "$DEGRADED"
fi

[ "$BROKEN" -eq 0 ]
