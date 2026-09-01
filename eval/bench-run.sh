#!/usr/bin/env bash
# eval/bench-run.sh — the MODEL-choice bench (Uber leva #2). Runs the same tasks across several
# models behind ONE interface and emits a Pareto table (cost per completed task, outcome, duration),
# marking dominated models. Then you move to the frontier and keep moving, because it shifts.
#
#   DRY-RUN IS THE DEFAULT.  A dry run reads committed SYNTHETIC fixtures and produces the FULL
#   table with ZERO model calls and ZERO spend — accidental spend is impossible without an
#   explicit flag. A REAL run needs BOTH --real AND --confirm-spend, and prints its estimated
#   cost first. Real spend is a hard human gate (AGENTS.md § Human gates #3) — this script will
#   not cross it for you.
#
# Usage:
#   eval/bench-run.sh [--dry-run]                 # DEFAULT: Pareto table from fixtures, no spend
#   eval/bench-run.sh --real --confirm-spend      # real benchmark (needs Roberto's approval)
#   eval/bench-run.sh --real                       # prints the cost estimate ONLY, then stops
# Options:
#   --models "a,b,c"   restrict to these model ids (default: every model in the price table)
#   --fixture FILE     dry-run result records (default: eval/bench-fixtures/dry-run.tsv)
#   --tasks DIR        real-run task dir (default: eval/bench-tasks-local, from bench-derive.sh)
#   --tokens N         real-run cost estimate: assumed tokens PER task PER model (default 30000)
#   --out FILE         where to also write the table (default: eval/bench-results/pareto.md)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
# shellcheck source=eval/bench-lib.sh
source "$ROOT/eval/bench-lib.sh"

MODE="dry-run"
CONFIRM=0
MODELS_FILTER=""
FIXTURE="$(bench_fixture_file)"
TASKS="${RDA_BENCH_TASKS:-$ROOT/eval/bench-tasks-local}"
TOKENS_PER_TASK="${RDA_BENCH_TOKENS:-30000}"
OUT="${RDA_BENCH_RESULTS:-$ROOT/eval/bench-results/pareto.md}"
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) MODE="dry-run"; shift ;;
    --real) MODE="real"; shift ;;
    --confirm-spend) CONFIRM=1; shift ;;
    --models) MODELS_FILTER="$2"; shift 2 ;;
    --fixture) FIXTURE="$2"; shift 2 ;;
    --tasks) TASKS="$2"; shift 2 ;;
    --tokens) TOKENS_PER_TASK="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "[bench] unknown argument: $1" >&2; exit 2 ;;
  esac
done

MODELS_FILE="$(bench_models_file)"
[ -f "$MODELS_FILE" ] || { echo "[bench] FATAL: price table not found: $MODELS_FILE" >&2; exit 2; }
mkdir -p "$(dirname "$OUT")"

# aggregate_and_pareto FIXTURE MODELS_FILE FILTER OUT SOURCE_LABEL
# One inline python3 block (python3 is already a repo dependency — see eval/report.sh) turns the
# per-(task,model) records into a per-model aggregate and marks the Pareto frontier. Used by BOTH
# the dry-run (records = fixtures) and a real run (records = measured), so the table is defined in
# exactly one place. It NEVER invokes a model — it only reads records that already exist.
aggregate_and_pareto() {
  python3 - "$1" "$2" "$3" "$4" "$5" <<'PY'
import sys
records_path, models_path, model_filter, out_path, source_label = sys.argv[1:6]

def rows(path):
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        yield line.split("\t")

prices = {}
for c in rows(models_path):
    if len(c) >= 3:
        prices[c[0]] = (float(c[1]), float(c[2]))

allow = set(x.strip() for x in model_filter.split(",") if x.strip()) if model_filter else None

# per model: attempted, passed, total_cost, total_duration, timeouts, errors, fails
agg = {}
seen_tasks = set()
for c in rows(records_path):
    if len(c) < 7:
        continue
    task, _diff, model, outcome, dur, itok, otok = c[0], c[1], c[2], c[3], float(c[4]), float(c[5]), float(c[6])
    if allow is not None and model not in allow:
        continue
    seen_tasks.add(task)
    a = agg.setdefault(model, dict(att=0, ok=0, cost=0.0, dur=0.0, to=0, err=0, fail=0))
    a["att"] += 1
    ip, op = prices.get(model, (0.0, 0.0))
    a["cost"] += itok / 1e6 * ip + otok / 1e6 * op
    a["dur"] += dur
    if outcome == "pass":
        a["ok"] += 1
    elif outcome == "timeout":
        a["to"] += 1
    elif outcome == "error":
        a["err"] += 1
    else:
        a["fail"] += 1

if not agg:
    open(out_path, "w").write("# model bench — no records matched\n")
    print("[bench] no records matched (empty fixture or filter excluded everything)", file=sys.stderr)
    sys.exit(0)

# derived metrics
M = {}
for model, a in agg.items():
    quality = a["ok"] / a["att"] if a["att"] else 0.0
    cost_per_done = (a["cost"] / a["ok"]) if a["ok"] else float("inf")
    avg_dur = a["dur"] / a["att"] if a["att"] else 0.0
    M[model] = dict(quality=quality, cost_per_done=cost_per_done, avg_dur=avg_dur,
                    att=a["att"], ok=a["ok"], to=a["to"], err=a["err"], fail=a["fail"], cost=a["cost"])

# Pareto: model X is dominated if some Y is >= on quality AND <= on cost-per-done AND <= on avg
# duration, with at least one strict. Higher quality better; lower cost and duration better.
def dominates(y, x):
    ge = y["quality"] >= x["quality"] and y["cost_per_done"] <= x["cost_per_done"] and y["avg_dur"] <= x["avg_dur"]
    strict = y["quality"] > x["quality"] or y["cost_per_done"] < x["cost_per_done"] or y["avg_dur"] < x["avg_dur"]
    return ge and strict

dominated = {}
for x in M:
    dominated[x] = any(dominates(M[y], M[x]) for y in M if y != x)

order = sorted(M, key=lambda m: (dominated[m], -M[m]["quality"], M[m]["cost_per_done"]))

def fcost(v):
    return "n/a" if v == float("inf") else f"${v:,.4f}"

lines = []
lines.append("# Model-choice Pareto bench")
lines.append("")
lines.append(f"- source: **{source_label}**")
lines.append(f"- tasks: **{len(seen_tasks)}**  ·  models: **{len(M)}**")
lines.append("- axes: quality = pass rate (higher better) · cost per completed task (lower better) · avg duration (lower better)")
lines.append("")
lines.append("| model | frontier | quality (pass rate) | cost/completed task | avg duration | pass/att | timeouts | errors | total cost |")
lines.append("|---|---|---|---|---|---|---|---|---|")
for m in order:
    d = M[m]
    mark = "dominated" if dominated[m] else "**frontier**"
    lines.append("| {m} | {mark} | {q:.0%} | {cpd} | {dur:.0f}s | {ok}/{att} | {to} | {err} | {cost} |".format(
        m=m, mark=mark, q=d["quality"], cpd=fcost(d["cost_per_done"]), dur=d["avg_dur"],
        ok=d["ok"], att=d["att"], to=d["to"], err=d["err"], cost=fcost(d["cost"])))
lines.append("")
frontier = [m for m in order if not dominated[m]]
lines.append("Pareto-optimal (not dominated by any other model): **" + ", ".join(frontier) + "**.")
dom = [m for m in order if dominated[m]]
if dom:
    lines.append("Dominated (another model is at least as good on every axis): " + ", ".join(dom) + ".")
lines.append("")
out = "\n".join(lines) + "\n"
open(out_path, "w", encoding="utf-8").write(out)
sys.stdout.write(out)
PY
}

if [ "$MODE" = "dry-run" ]; then
  [ -f "$FIXTURE" ] || { echo "[bench] FATAL: fixture not found: $FIXTURE" >&2; exit 2; }
  echo "[bench] DRY-RUN (default): no model will be called, no spend possible." >&2
  echo "[bench] dry-run: reading result records from fixtures: $FIXTURE" >&2
  aggregate_and_pareto "$FIXTURE" "$MODELS_FILE" "$MODELS_FILTER" "$OUT" "DRY-RUN (synthetic fixtures: $FIXTURE)"
  echo "[bench] dry-run: Pareto table written to $OUT (no model was invoked)" >&2
  exit 0
fi

# ---- REAL run path (guarded) ---------------------------------------------------------------
# Count tasks + models, print the estimate, and STOP unless --confirm-spend was passed.
task_count=0
if [ -d "$TASKS" ]; then task_count="$(find "$TASKS" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"; fi
if [ "$MODELS_FILTER" != "" ]; then
  model_count="$(printf '%s' "$MODELS_FILTER" | tr ',' '\n' | grep -c .)"
else
  model_count="$(grep -vcE '^\s*#|^\s*$' "$MODELS_FILE")"
fi
estimate="$(python3 - "$MODELS_FILE" "$MODELS_FILTER" "$task_count" "$TOKENS_PER_TASK" <<'PY'
import sys
models_path, mfilter, task_count, tokens = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
allow = set(x.strip() for x in mfilter.split(",") if x.strip()) if mfilter else None
tot = 0.0
half = tokens / 2.0  # crude split: half input, half output
for line in open(models_path):
    line = line.rstrip("\n")
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    c = line.split("\t")
    if len(c) < 3:
        continue
    if allow is not None and c[0] not in allow:
        continue
    ip, op = float(c[1]), float(c[2])
    tot += task_count * (half / 1e6 * ip + half / 1e6 * op)
print(f"{tot:.2f}")
PY
)"
echo "[bench] REAL run requested."
echo "[bench] estimate: $task_count task(s) x $model_count model(s), assuming ${TOKENS_PER_TASK} tokens/task/model"
echo "[bench] ESTIMATED COST (list-price assumption, NOT actual billing): \$${estimate}"
if [ "$task_count" -eq 0 ]; then
  echo "[bench] no derived tasks in $TASKS — run eval/bench-derive.sh first (it reads real closed cards)." >&2
  exit 2
fi
if [ "$CONFIRM" -ne 1 ]; then
  echo "[bench] STOP: real spend is a human gate (AGENTS.md § Human gates #3)." >&2
  echo "[bench] Re-run with --real --confirm-spend ONLY after Roberto approves the estimate above." >&2
  exit 3
fi

echo "[bench] --confirm-spend given: proceeding with a REAL benchmark run." >&2
eval_unset_billing_env
CLAUDE=""; eval_agent_configured || CLAUDE="$(eval_resolve_claude)"
if ! eval_agent_configured && { [ -z "$CLAUDE" ] || [ ! -x "$CLAUDE" ]; }; then
  echo "[bench] FATAL: no agent CLI resolvable (install Claude Code or set RDA_EVAL_AGENT_CMD)." >&2
  exit 127
fi
TIMEOUT_BIN="$(eval_resolve_timeout)"
TIMEOUT_S="${RDA_BENCH_TIMEOUT:-1800}"
RESULTS_TSV="${OUT%.md}-records.tsv"
: > "$RESULTS_TSV"
IFS=',' read -ra RUN_MODELS <<< "${MODELS_FILTER:-$(grep -vE '^\s*#|^\s*$' "$MODELS_FILE" | cut -f1 | paste -sd, -)}"
shopt -s nullglob
for tf in "$TASKS"/*.md; do
  id="$(field "$tf" id)"; id="${id:-$(basename "$tf" .md)}"
  diff="$(field "$tf" difficulty)"; diff="${diff:-medium}"
  prompt="$(section "$tf" "## Prompt")"
  for model in "${RUN_MODELS[@]}"; do
    model="$(echo "$model" | tr -d '[:space:]')"; [ -z "$model" ] && continue
    tmp="$(mktemp)"; start="$(date +%s)"
    set +e
    bench_invoke_model "$model" "$prompt" "$tmp" "$ROOT" "$TIMEOUT_S" "$TIMEOUT_BIN" "$CLAUDE"
    rc=$?
    set -e
    dur=$(( $(date +%s) - start ))
    # A real run would score outcome via the existing blind judge; without a token meter here it
    # records rc-based outcome and 0 tokens as an honest placeholder (see README honest limit).
    outcome="pass"; [ "$rc" -eq 124 ] && outcome="timeout"; [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ] && outcome="error"
    printf '%s\t%s\t%s\t%s\t%s\t0\t0\n' "$id" "$diff" "$model" "$outcome" "$dur" >> "$RESULTS_TSV"
    rm -f "$tmp"
  done
done
aggregate_and_pareto "$RESULTS_TSV" "$MODELS_FILE" "$MODELS_FILTER" "$OUT" "REAL run (measured: $RESULTS_TSV)"
echo "[bench] real run: Pareto table written to $OUT" >&2
