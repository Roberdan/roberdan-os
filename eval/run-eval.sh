#!/usr/bin/env bash
# eval/run-eval.sh — condition A (no canon) vs condition B (task + relevant canon file(s)
# prepended, matching how AGENTS.md would actually inject them) for every task fixture in
# eval/tasks/. Saves both raw outputs to eval/results/<task-id>/{a,b}.md.
#
# Resumable: skips a task+condition pair whose output file already exists, unless --force.
# Binary resolution + billing safety mirror factory/run.sh exactly (see eval/lib.sh). By default
# the agent is headless Claude Code; set RDA_EVAL_AGENT_CMD to drive a different headless agent
# CLI instead (e.g. `copilot -p`, `hermes chat -z`) — see eval_invoke_agent in eval/lib.sh for
# the full convention (prompt delivered via stdin, no claude-specific flags passed through).
#
# KNOWN LIMITATION — canon: skills/*/skill.md: this script prepends ANY declared canon file
# verbatim as passive text, including skill files, purely for mechanical uniformity (one
# injection code path for every canon type). That is a faithful mirror of how behavior/*.md and
# rules/*.md canon actually reaches a real session, but NOT of how a skill file does — a skill is
# meant to be INVOKED (Skill-tool procedure), not read as prose context. Prepending a skill file's
# full procedural body ahead of a task can make the agent perform the skill's own intake ritual
# (e.g. "clarify what success looks like first") even when the task wants a direct single-shot
# answer. This is a known, already-observed effect (see eval/README.md and the "Skill-type canon
# tasks" section of eval/report.sh's output) — it is not fixed here because the fix lives in
# aggregation, not injection: eval/report.sh runs and judges these tasks like any other but
# reports them separately and excludes them from the aggregate, rather than pretending
# prepend-as-context is a fair test of a file meant to be invoked.
#
# --stub    : label outputs as stub runs. Does NOT itself provide a fake `claude` — the caller
#             (a human, or eval/test-eval-pipeline.sh) is expected to have already put a fake
#             `claude` earlier on PATH, exactly the way test/test-factory-kb.sh stubs
#             factory/run.sh. Without a real (or stubbed) `claude` resolvable, this script exits
#             127 with a clear message rather than silently doing nothing.
# --force   : regenerate outputs even if a,b.md already exist for a task.
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
      echo "usage: eval/run-eval.sh [--stub] [--force]"
      exit 0
      ;;
    *) echo "[eval] unknown argument: $arg" >&2; exit 2 ;;
  esac
done

TASKS="${RDA_EVAL_TASKS:-$ROOT/eval/tasks}"
RESULTS="${RDA_EVAL_RESULTS:-$ROOT/eval/results}"
TIMEOUT_S="${RDA_EVAL_TIMEOUT:-600}"
mkdir -p "$RESULTS"

# --- split preflight: the fixtures a rule was written from cannot be the ones that judge it ---
# Every fixture declares `split: train|val`. `train` may be read while writing or revising canon;
# `val` is held out — never opened during a canon edit, only used for the final measure. Without
# this, re-measuring after a canon change on the same fixtures is overfitting dressed as evidence.
# A missing/invalid split is a HARD refusal: an unlabelled fixture silently defaults to nothing,
# and a gate that runs anyway is a gate that can be satisfied without doing the work.
# RDA_EVAL_MIN_VAL mirrors SkillOpt's own D_sel<5 refusal (arXiv 2605.23904): a validation set
# too small to separate signal from judge noise is worse than an honest "not measured".
MIN_VAL="${RDA_EVAL_MIN_VAL:-5}"
split_train=0; split_val=0; split_bad=0
shopt -s nullglob
for tf in "${RDA_EVAL_TASKS:-$ROOT/eval/tasks}"/*.md; do
  sp="$(field "$tf" split)"
  case "$sp" in
    train) split_train=$((split_train+1)) ;;
    val)   split_val=$((split_val+1)) ;;
    *)     echo "[eval] FATAL: $tf declares split='${sp:-<missing>}' (expected train|val)" >&2
           split_bad=$((split_bad+1)) ;;
  esac
done
if [ "$split_bad" -gt 0 ]; then
  echo "[eval] refusing to run: $split_bad fixture(s) without a valid split. See eval/README.md § Train/val split." >&2
  exit 2
fi
if [ "$((split_train + split_val))" -eq 0 ]; then
  echo "[eval] FATAL: no task fixtures found in ${RDA_EVAL_TASKS:-$ROOT/eval/tasks}" >&2
  exit 2
fi
if [ "$split_val" -lt "$MIN_VAL" ]; then
  echo "[eval] refusing to run: val split has $split_val fixture(s), minimum $MIN_VAL." >&2
  echo "       A validation set this small cannot separate signal from judge noise." >&2
  exit 2
fi
echo "[eval] split preflight: $split_train train / $split_val val (min val: $MIN_VAL)" >&2

eval_unset_billing_env

# CLAUDE stays unresolved when RDA_EVAL_AGENT_CMD overrides the agent — see eval_invoke_agent
# in eval/lib.sh for the override convention (prompt via stdin, no claude-specific flags).
CLAUDE=""
if eval_agent_configured; then
  echo "[eval] RDA_EVAL_AGENT_CMD override active: $RDA_EVAL_AGENT_CMD" >&2
else
  CLAUDE="$(eval_resolve_claude)"
  if [ -z "$CLAUDE" ] || [ ! -x "$CLAUDE" ]; then
    if [ "$STUB" -eq 1 ]; then
      echo "[eval] FATAL (--stub): no claude resolvable on PATH. --stub expects the caller to have" >&2
      echo "       already prepended a fake claude script to PATH (see eval/test-eval-pipeline.sh)." >&2
      echo "       (or set RDA_EVAL_AGENT_CMD to stub a different agent CLI instead.)" >&2
    else
      echo "[eval] FATAL: no claude binary found. Run with --stub only after putting a fake claude" >&2
      echo "       on PATH for pipeline testing; for a REAL run, install Claude Code, or set" >&2
      echo "       RDA_EVAL_AGENT_CMD to drive a different headless agent CLI instead." >&2
    fi
    exit 127
  fi
fi

TIMEOUT_BIN="$(eval_resolve_timeout)"

invoke_claude() {
  # invoke_claude PROMPT OUTFILE — thin wrapper over eval_invoke_agent (eval/lib.sh), which
  # branches on RDA_EVAL_AGENT_CMD.
  local prompt="$1" outfile="$2"
  eval_invoke_agent "$prompt" "$outfile" "$ROOT" "$TIMEOUT_S" "$TIMEOUT_BIN" "$CLAUDE"
}

n=0
skipped=0
shopt -s nullglob
for tf in "$TASKS"/*.md; do
  id="$(field "$tf" id)"; id="${id:-$(basename "$tf" .md)}"
  canon_field="$(field "$tf" canon)"
  prompt_body="$(section "$tf" "## Prompt")"
  if [ -z "$prompt_body" ]; then
    echo "[eval] WARN: $tf has no '## Prompt' section, skipping" >&2
    continue
  fi

  outdir="$RESULTS/$id"
  mkdir -p "$outdir"

  # --- Condition A: task only, no canon ------------------------------------------------
  a_out="$outdir/a.md"
  if [ -f "$a_out" ] && [ "$FORCE" -ne 1 ]; then
    echo "[eval] SKIP $id/a (exists, use --force to regenerate)"
    skipped=$((skipped+1))
  else
    banner="<!-- eval condition=A (no canon) task=$id stub=$STUB generated=$(date -u +%FT%TZ) -->"$'\n\n'
    tmp="$(mktemp "$outdir/.a.XXXXXX")"
    if invoke_claude "$prompt_body" "$tmp.raw"; then
      { printf '%s' "$banner"; cat "$tmp.raw"; } > "$tmp"
      mv "$tmp" "$a_out"
      rm -f "$tmp.raw"
      echo "[eval] DONE $id/a"
    else
      rc=$?
      { printf '%s' "$banner"; echo "[eval] claude exited $rc"; cat "$tmp.raw" 2>/dev/null; } > "$tmp"
      mv "$tmp" "$a_out"
      rm -f "$tmp.raw"
      echo "[eval] WARN $id/a exited $rc (saved anyway, see $a_out)" >&2
    fi
    n=$((n+1))
  fi

  # --- Condition B: canon file(s) prepended, then task -------------------------------
  b_out="$outdir/b.md"
  if [ -f "$b_out" ] && [ "$FORCE" -ne 1 ]; then
    echo "[eval] SKIP $id/b (exists, use --force to regenerate)"
    skipped=$((skipped+1))
  else
    canon_content=""
    if [ -n "$canon_field" ]; then
      IFS=',' read -ra canon_paths <<< "$canon_field"
      for cp in "${canon_paths[@]}"; do
        cp="$(echo "$cp" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        [ -z "$cp" ] && continue
        if [ -f "$ROOT/$cp" ]; then
          canon_content="${canon_content}=== CANON FILE: ${cp} ===
$(cat "$ROOT/$cp")

"
        else
          echo "[eval] WARN: $tf declares canon file '$cp' which does not exist" >&2
        fi
      done
    fi
    full_prompt="${canon_content}=== TASK ===
${prompt_body}"
    banner="<!-- eval condition=B (with canon: ${canon_field:-none}) task=$id stub=$STUB generated=$(date -u +%FT%TZ) -->"$'\n\n'
    tmp="$(mktemp "$outdir/.b.XXXXXX")"
    if invoke_claude "$full_prompt" "$tmp.raw"; then
      { printf '%s' "$banner"; cat "$tmp.raw"; } > "$tmp"
      mv "$tmp" "$b_out"
      rm -f "$tmp.raw"
      echo "[eval] DONE $id/b"
    else
      rc=$?
      { printf '%s' "$banner"; echo "[eval] claude exited $rc"; cat "$tmp.raw" 2>/dev/null; } > "$tmp"
      mv "$tmp" "$b_out"
      rm -f "$tmp.raw"
      echo "[eval] WARN $id/b exited $rc (saved anyway, see $b_out)" >&2
    fi
    n=$((n+1))
  fi
done

echo "[eval] run-eval: $n invocation(s), $skipped skipped (already present) at $(date)"
