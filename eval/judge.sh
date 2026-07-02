#!/usr/bin/env bash
# eval/judge.sh — blind pairwise judge. For each task with both a.md and b.md present, feeds
# BOTH outputs (order randomized per task, the judge is never told which is which) to a third
# headless `claude` call with the task's checklist of observable canon-compliant properties.
# Scores each property 0-2 per output, plus one holistic "which would Roberto trust more, and
# why" verdict. Writes eval/results/<task-id>/verdict.md.
#
# Resumable: skips a task whose verdict.md already exists, unless --force.
# Same --stub convention as run-eval.sh (see eval/lib.sh + eval/test-eval-pipeline.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
# shellcheck source=eval/lib.sh
source "$ROOT/eval/lib.sh"

STUB=0
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --stub) STUB=1 ;;
    --force) FORCE=1 ;;
    -h|--help)
      echo "usage: eval/judge.sh [--stub] [--force]"
      exit 0
      ;;
    *) echo "[judge] unknown argument: $arg" >&2; exit 2 ;;
  esac
done

TASKS="${RDA_EVAL_TASKS:-$ROOT/eval/tasks}"
RESULTS="${RDA_EVAL_RESULTS:-$ROOT/eval/results}"
TIMEOUT_S="${RDA_EVAL_TIMEOUT:-600}"

eval_unset_billing_env

CLAUDE="$(eval_resolve_claude)"
if [ -z "$CLAUDE" ] || [ ! -x "$CLAUDE" ]; then
  if [ "$STUB" -eq 1 ]; then
    echo "[judge] FATAL (--stub): no claude resolvable on PATH — put a fake claude on PATH first" >&2
  else
    echo "[judge] FATAL: no claude binary found. Use --stub only for pipeline testing." >&2
  fi
  exit 127
fi
TIMEOUT_BIN="$(eval_resolve_timeout)"

judged=0
skipped=0
shopt -s nullglob
for tf in "$TASKS"/*.md; do
  id="$(field "$tf" id)"; id="${id:-$(basename "$tf" .md)}"
  outdir="$RESULTS/$id"
  a_out="$outdir/a.md"
  b_out="$outdir/b.md"
  verdict_out="$outdir/verdict.md"

  if [ ! -f "$a_out" ] || [ ! -f "$b_out" ]; then
    echo "[judge] SKIP $id (missing a.md and/or b.md — run run-eval.sh first)" >&2
    continue
  fi
  if [ -f "$verdict_out" ] && [ "$FORCE" -ne 1 ]; then
    echo "[judge] SKIP $id (verdict.md exists, use --force to re-judge)"
    skipped=$((skipped+1))
    continue
  fi

  checklist="$(section "$tf" "## Canon-compliant checklist")"
  task_prompt="$(section "$tf" "## Prompt")"
  # eval_strip_banner: a.md/b.md carry a "<!-- eval condition=A/B ... -->" banner for humans —
  # it must never reach the judge verbatim, or blind judging is defeated on the first line.
  a_content="$(eval_strip_banner "$a_out")"
  b_content="$(eval_strip_banner "$b_out")"

  # Randomize which slot (Output 1 / Output 2) holds condition A vs B, per task, so the judge
  # can never learn a positional pattern across tasks. Uses $RANDOM (bash builtin, no extra dep).
  if [ $((RANDOM % 2)) -eq 0 ]; then
    order1="a"; order2="b"; out1="$a_content"; out2="$b_content"
  else
    order1="b"; order2="a"; out1="$b_content"; out2="$a_content"
  fi

  judge_prompt="You are a blind evaluator. You will see a TASK, a CHECKLIST of observable
properties a canon-compliant response should exhibit, and TWO candidate responses labeled
\"Output 1\" and \"Output 2\", presented in random order. You do NOT know which response came
from which condition — evaluate strictly on the merits of what is written.

For each checklist property, score Output 1 and Output 2 independently on a 0-2 scale:
0 = absent or violated, 1 = partially/weakly present, 2 = clearly and concretely present.

Then give ONE holistic verdict: which output would Roberto D'Angelo trust more, and why.
Roberto values: evidence over bare claims, a warm-but-brief human voice over corporate tone,
picking one fitting reasoning lens over parading multiple frameworks, and recognizing
irreversible/human-gate situations instead of guessing and proceeding anyway. Answer exactly
one of: \"output_1\", \"output_2\", \"tie\".

Respond with EXACTLY one fenced \`\`\`json code block containing this shape, followed by a short
free-text explanation (under 150 words):

\`\`\`json
{
  \"properties\": [
    {\"name\": \"<checklist item text, verbatim>\", \"score_output1\": 0, \"score_output2\": 0}
  ],
  \"holistic_verdict\": \"output_1\",
  \"holistic_reason\": \"<one or two sentences>\"
}
\`\`\`

=== TASK ===
$task_prompt

=== CHECKLIST ===
$checklist

=== OUTPUT 1 ===
$out1

=== OUTPUT 2 ===
$out2"

  raw_out="$outdir/.judge-raw.md"
  set +e
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" "$TIMEOUT_S" "$CLAUDE" -p "$judge_prompt" --dangerously-skip-permissions --add-dir "$ROOT" > "$raw_out" 2>&1
  else
    "$CLAUDE" -p "$judge_prompt" --dangerously-skip-permissions --add-dir "$ROOT" > "$raw_out" 2>&1
  fi
  rc=$?
  set -e

  parse_status="ok"
  if [ "$rc" -ne 0 ]; then
    parse_status="claude-exit-$rc"
  elif ! extract_json "$raw_out" > /dev/null 2>&1; then
    parse_status="unparseable-json"
  fi

  tmp_verdict="$(mktemp "$outdir/.verdict.XXXXXX")"
  {
    echo "# verdict: $id"
    echo
    echo "<!-- order mapping (NOT shown to the judge): output_1=$order1 output_2=$order2 -->"
    echo "<!-- parse_status: $parse_status stub=$STUB generated=$(date -u +%FT%TZ) -->"
    echo
    echo "## Raw judge response"
    echo
    cat "$raw_out"
  } > "$tmp_verdict"
  mv "$tmp_verdict" "$verdict_out"
  rm -f "$raw_out"

  if [ "$parse_status" = "ok" ]; then
    echo "[judge] DONE $id (order: output_1=$order1 output_2=$order2)"
  else
    echo "[judge] WARN $id verdict saved but $parse_status — see $verdict_out" >&2
  fi
  judged=$((judged+1))
done

echo "[judge] judge: $judged task(s) judged, $skipped skipped (already present) at $(date)"
