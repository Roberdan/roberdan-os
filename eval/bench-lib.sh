#!/usr/bin/env bash
# eval/bench-lib.sh — shared helpers for the MODEL-choice bench (bench-derive.sh, bench-run.sh).
# Sourced, not executed. This is a SIBLING concern to the A/B canon eval (run-eval.sh/judge.sh):
# that eval asks "does the canon change output?"; this bench asks "which MODEL is Pareto-optimal
# on our own real work?" — the Uber method (build the benchmark from the agent's real tasks, run
# them across models behind one interface, score quality AND cost, move to the Pareto frontier).
#
# It reuses eval/lib.sh wholesale (frontmatter/field/section parsing, the agent-invocation path,
# billing safety, timeout resolution) so the bench does not invent a second dialect for problems
# the eval harness already solved.

# shellcheck source=eval/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# --- difficulty grading (Uber graded their PR benchmark easy/medium/hard) -------------------
# A card's difficulty is inferred, honestly and crudely, from how much it asks for: the combined
# length of its Definition-of-Done and acceptance text, plus how many distinct clauses those
# carry (';' and ' e ' / ' and ' as separators). This is a HEURISTIC, not a truth — a short DoD
# can hide a hard task and a verbose one can restate an easy one. Stated as a limit in the README.
bench_grade_difficulty() {
  local dod="$1" acceptance="$2" combined len clauses
  combined="${dod} ${acceptance}"
  len="${#combined}"
  # clause count: separators that usually mark an additional required condition
  clauses="$(printf '%s' "$combined" | grep -oE ';|( e )|( and )|( AND )' | wc -l | tr -d ' ')"
  if [ "$len" -lt 160 ] && [ "$clauses" -lt 2 ]; then
    printf 'easy'
  elif [ "$len" -lt 400 ] && [ "$clauses" -lt 5 ]; then
    printf 'medium'
  else
    printf 'hard'
  fi
}

# --- one interface, several models ----------------------------------------------------------
# bench_invoke_model MODEL PROMPT OUTFILE ROOT TIMEOUT_S TIMEOUT_BIN CLAUDE_BIN
# The single seam every model goes through on a REAL run. It is a thin wrapper over the eval
# harness's own eval_invoke_agent, adding the per-call --model switch (exactly how factory/run.sh
# selects a model). When RDA_EVAL_AGENT_CMD points at a non-claude CLI, the model id is exported
# as RDA_BENCH_MODEL for that CLI to honor in its own dialect, and no claude --model flag is used.
# NB: never called on a dry-run — the dry-run path reads fixtures and never reaches here.
bench_invoke_model() {
  local model="$1" prompt="$2" outfile="$3" root="$4" timeout_s="$5" timeout_bin="$6" claude_bin="$7"
  local rc=0
  set +e
  if eval_agent_configured; then
    # Non-claude agent: it owns its own model dialect; we only surface the requested id to it.
    RDA_BENCH_MODEL="$model" eval_invoke_agent "$prompt" "$outfile" "$root" "$timeout_s" "$timeout_bin" "$claude_bin"
    rc=$?
  else
    if [ -n "$timeout_bin" ]; then
      "$timeout_bin" "$timeout_s" "$claude_bin" -p "$prompt" --model "$model" \
        --dangerously-skip-permissions --add-dir "$root" > "$outfile" 2>&1
    else
      "$claude_bin" -p "$prompt" --model "$model" \
        --dangerously-skip-permissions --add-dir "$root" > "$outfile" 2>&1
    fi
    rc=$?
  fi
  set -e
  return $rc
}

# --- model price table ----------------------------------------------------------------------
# bench_models_file — the committed price assumptions (public list prices, an ESTIMATE, labelled
# as such in the file and the README). Override with RDA_BENCH_MODELS for a private/updated table.
bench_models_file() {
  printf '%s' "${RDA_BENCH_MODELS:-$(dirname "${BASH_SOURCE[0]}")/bench-models.tsv}"
}

# bench_fixture_file — the committed SYNTHETIC dry-run result records (task x model x outcome x
# duration x tokens). Synthetic on purpose: it carries NO real card content, so it is safe to
# commit and lets the dry-run produce a full Pareto table with zero model calls and zero spend.
bench_fixture_file() {
  printf '%s' "${RDA_BENCH_FIXTURE:-$(dirname "${BASH_SOURCE[0]}")/bench-fixtures/dry-run.tsv}"
}
