#!/usr/bin/env bash
# eval/bench-derive.sh — derive model-bench TASKS from REAL closed kanban cards. Runs LOCALLY;
# its output is card content (Roberto's private operational state) and therefore NEVER committed
# — exactly the split kanban/ already uses (the tool is versioned, the data is gitignored). This
# script IS the deriver that ships; the derived tasks land in a gitignored local directory.
#
# A task = a real card's title + Definition of Done + acceptance criteria + an inferred difficulty
# grade (easy|medium|hard, see bench_grade_difficulty in bench-lib.sh). That mirrors Uber's method:
# build the benchmark out of the agent's REAL work, graded by difficulty — not synthetic puzzles.
#
# Usage: eval/bench-derive.sh [--cards DIR] [--out DIR] [--limit N]
#   --cards DIR   where the closed cards are (default: kanban/done, or $RDA_BENCH_CARDS)
#   --out   DIR   where to write derived tasks (default: eval/bench-tasks-local — GITIGNORED)
#   --limit N     derive at most N tasks (default: all)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
# shellcheck source=eval/bench-lib.sh
source "$ROOT/eval/bench-lib.sh"

CARDS="${RDA_BENCH_CARDS:-$ROOT/kanban/done}"
OUT="${RDA_BENCH_TASKS:-$ROOT/eval/bench-tasks-local}"
LIMIT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --cards) CARDS="$2"; shift 2 ;;
    --out)   OUT="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    -h|--help) echo "usage: eval/bench-derive.sh [--cards DIR] [--out DIR] [--limit N]"; exit 0 ;;
    *) echo "[bench-derive] unknown argument: $1" >&2; exit 2 ;;
  esac
done

# GUARDRAIL: the output directory must be one git ignores. Deriving real card content into a
# committed path is precisely the 2026-08-24 privacy scar (a generator wrote private notes into a
# tracked area). Refuse rather than trust the caller. `git check-ignore` is the authority — probe
# a path INSIDE the dir (a trailing component), because a dir-only ignore pattern (`foo/`) does
# not match the bare dir path, only something under it.
probe="${OUT%/}/.derived"
if ! git -C "$ROOT" check-ignore -q "$probe" 2>/dev/null; then
  echo "[bench-derive] REFUSING: output dir '$OUT' is NOT gitignored." >&2
  echo "               Derived tasks contain private card content and must never be committed." >&2
  echo "               Add it to .gitignore (eval/bench-tasks-local/ already is) or pass --out into one." >&2
  exit 2
fi

if [ ! -d "$CARDS" ]; then
  echo "[bench-derive] FATAL: cards dir '$CARDS' does not exist." >&2
  echo "               Closed cards live in kanban/done (gitignored, present locally). If this is a" >&2
  echo "               clean checkout there are none — that is expected; the dry-run uses fixtures." >&2
  exit 2
fi

mkdir -p "$OUT"
n=0
shopt -s nullglob
for cf in "$CARDS"/*.md; do
  base="$(basename "$cf" .md)"
  case "$base" in _archive*) continue ;; esac
  title="$(field "$cf" title)"
  dod="$(field "$cf" dod)"
  acceptance="$(field "$cf" acceptance)"
  # A task needs all three to be a fair benchmark item; a card missing any is skipped, not faked.
  if [ -z "$title" ] || [ -z "$dod" ] || [ -z "$acceptance" ]; then
    echo "[bench-derive] skip $base (missing title/dod/acceptance)" >&2
    continue
  fi
  difficulty="$(bench_grade_difficulty "$dod" "$acceptance")"
  out="$OUT/$base.md"
  {
    echo "---"
    echo "id: $base"
    echo "difficulty: $difficulty"
    echo "source_card: $base"
    echo "# LOCAL ONLY — derived from a private kanban card. Do NOT commit."
    echo "---"
    echo
    echo "# $title"
    echo
    echo "## Prompt"
    echo
    echo "You are picking up a real, already-closed task from Roberto's board. Do the work to meet"
    echo "its Definition of Done, and stop when the acceptance criteria are demonstrably met."
    echo
    echo "TITLE: $title"
    echo
    echo "DEFINITION OF DONE: $dod"
    echo
    echo "ACCEPTANCE: $acceptance"
    echo
    echo "## Acceptance"
    echo
    echo "$acceptance"
  } > "$out"
  n=$((n+1))
  if [ "$LIMIT" -gt 0 ] && [ "$n" -ge "$LIMIT" ]; then break; fi
done

echo "[bench-derive] derived $n task(s) from $CARDS -> $OUT (gitignored, local only)"
if [ "$n" -eq 0 ]; then
  echo "[bench-derive] NOTE: 0 tasks derived. On a clean checkout kanban/done is empty by design;" >&2
  echo "               use the committed fixtures for the dry-run instead (bench-run.sh --dry-run)." >&2
fi
