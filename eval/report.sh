#!/usr/bin/env bash
# eval/report.sh — aggregates every eval/results/<task-id>/verdict.md into a single
# eval/results/report.md: a task x property-scores-A x property-scores-B x holistic-verdict
# table, a win/loss/tie summary, a "which canon FILE mattered most" breakdown, and an honest
# "what this does and doesn't prove" closing section.
#
# Aggregation logic lives in an inline python3 block (python3 is already a dependency of
# test/leak-check.sh, so this doesn't add a new one) — JSON parsing + grouping in bash would be
# unreadable. report.sh itself just resolves paths and prints the summary to stdout too.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

STUB=0
for arg in "$@"; do
  case "$arg" in
    --stub) STUB=1 ;;
    -h|--help)
      echo "usage: eval/report.sh [--stub]"
      exit 0
      ;;
    *) echo "[report] unknown argument: $arg" >&2; exit 2 ;;
  esac
done

TASKS="${RDA_EVAL_TASKS:-$ROOT/eval/tasks}"
RESULTS="${RDA_EVAL_RESULTS:-$ROOT/eval/results}"
OUT="$RESULTS/report.md"
mkdir -p "$RESULTS"

python3 - "$TASKS" "$RESULTS" "$OUT" "$STUB" <<'PY'
import sys, re, json, glob, os
from datetime import datetime, timezone

tasks_dir, results_dir, out_path, stub = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1"


def read_frontmatter(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    m = re.search(r"^---\n(.*?)\n---\n", text, re.S)
    fm = {}
    if m:
        for line in m.group(1).splitlines():
            mm = re.match(r"^([a-zA-Z_]+):\s*(.*)$", line)
            if mm:
                fm[mm.group(1)] = mm.group(2).strip().strip('"')
    return fm


def extract_json_block(text):
    m = re.search(r"```json\s*(\{.*?\})\s*```", text, re.S)
    if not m:
        m = re.search(r"(\{.*\})", text, re.S)
    if not m:
        return None
    try:
        return json.loads(m.group(1))
    except Exception:
        return None


rows = []          # per-task summary rows
canon_stats = {}    # canon file -> {"n":..,"gap_sum":..,"b_wins":..,"a_wins":..,"ties":..}
holistic_counts = {"output_b": 0, "output_a": 0, "tie": 0, "unparsed": 0}
had_stub_marker = False

task_files = sorted(glob.glob(os.path.join(tasks_dir, "*.md")))
for tf in task_files:
    fm = read_frontmatter(tf)
    tid = fm.get("id", os.path.splitext(os.path.basename(tf))[0])
    category = fm.get("category", "?")
    canon = fm.get("canon", "")
    canon_files = [c.strip() for c in canon.split(",") if c.strip()]

    verdict_path = os.path.join(results_dir, tid, "verdict.md")
    a_path = os.path.join(results_dir, tid, "a.md")
    b_path = os.path.join(results_dir, tid, "b.md")

    if not os.path.exists(verdict_path):
        rows.append({"id": tid, "category": category, "canon": canon,
                     "score_a": "-", "score_b": "-", "winner": "no verdict"})
        continue

    vtext = open(verdict_path, encoding="utf-8", errors="replace").read()
    if "stub=1" in vtext:
        had_stub_marker = True
    om = re.search(r"output_1=(\w+)\s+output_2=(\w+)", vtext)
    order1, order2 = (om.group(1), om.group(2)) if om else (None, None)

    obj = extract_json_block(vtext)
    if not obj or not order1:
        rows.append({"id": tid, "category": category, "canon": canon,
                     "score_a": "-", "score_b": "-", "winner": "unparseable"})
        holistic_counts["unparsed"] += 1
        continue

    props = obj.get("properties", [])
    slot_sum = {"1": 0, "2": 0}
    for p in props:
        slot_sum["1"] += int(p.get("score_output1", 0) or 0)
        slot_sum["2"] += int(p.get("score_output2", 0) or 0)
    score_by_cond = {order1: slot_sum["1"], order2: slot_sum["2"]}
    score_a = score_by_cond.get("a", 0)
    score_b = score_by_cond.get("b", 0)
    max_possible = 2 * len(props) if props else 0

    hv = obj.get("holistic_verdict", "").strip().lower()
    slot_to_cond = {"output_1": order1, "output_2": order2}
    winner_cond = slot_to_cond.get(hv)
    if winner_cond == "b":
        winner = "B (with canon)"
        holistic_counts["output_b"] += 1
    elif winner_cond == "a":
        winner = "A (no canon)"
        holistic_counts["output_a"] += 1
    elif hv == "tie":
        winner = "tie"
        holistic_counts["tie"] += 1
    else:
        winner = "unparsed"
        holistic_counts["unparsed"] += 1

    rows.append({"id": tid, "category": category, "canon": canon,
                 "score_a": f"{score_a}/{max_possible}", "score_b": f"{score_b}/{max_possible}",
                 "winner": winner})

    for cf in canon_files:
        st = canon_stats.setdefault(cf, {"n": 0, "gap_sum": 0, "b_wins": 0, "a_wins": 0, "ties": 0})
        st["n"] += 1
        st["gap_sum"] += (score_b - score_a)
        if winner_cond == "b":
            st["b_wins"] += 1
        elif winner_cond == "a":
            st["a_wins"] += 1
        elif hv == "tie":
            st["ties"] += 1

lines = []
lines.append("# eval report")
lines.append("")
lines.append(f"Generated {datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}.")
if stub or had_stub_marker:
    lines.append("")
    lines.append("> **STUB MODE.** These numbers come from a fake `claude` used to test the")
    lines.append("> harness mechanics (see `eval/test-eval-pipeline.sh`). They are NOT a real")
    lines.append("> behavioral measurement — see `eval/README.md` for what has and hasn't been run.")
lines.append("")
lines.append("## Per-task results")
lines.append("")
lines.append("| Task | Category | Canon file(s) | Score A (no canon) | Score B (with canon) | Holistic winner |")
lines.append("|---|---|---|---|---|---|")
for r in rows:
    lines.append(f"| {r['id']} | {r['category']} | {r['canon']} | {r['score_a']} | {r['score_b']} | {r['winner']} |")

judged = holistic_counts["output_a"] + holistic_counts["output_b"] + holistic_counts["tie"]
lines.append("")
lines.append("## Summary")
lines.append("")
lines.append(f"- Tasks with a parsed verdict: **{judged}** / {len(task_files)}")
lines.append(f"- B (with canon) preferred: **{holistic_counts['output_b']}**")
lines.append(f"- A (no canon) preferred: **{holistic_counts['output_a']}**")
lines.append(f"- Tie: **{holistic_counts['tie']}**")
if holistic_counts["unparsed"]:
    lines.append(f"- Unparseable / missing verdicts: **{holistic_counts['unparsed']}**")
lines.append("")
lines.append("### Which canon file mattered most (avg score gap, B minus A)")
lines.append("")
if canon_stats:
    lines.append("| Canon file | Tasks | Avg gap (B-A) | B wins | A wins | Tie |")
    lines.append("|---|---|---|---|---|---|")
    for cf, st in sorted(canon_stats.items(), key=lambda kv: -(kv[1]["gap_sum"] / max(kv[1]["n"], 1))):
        avg_gap = st["gap_sum"] / st["n"] if st["n"] else 0
        lines.append(f"| {cf} | {st['n']} | {avg_gap:+.2f} | {st['b_wins']} | {st['a_wins']} | {st['ties']} |")
else:
    lines.append("_No judged tasks yet — run `eval/run-eval.sh` then `eval/judge.sh` first._")

lines.append("")
lines.append("## What this does and doesn't prove")
lines.append("")
lines.append("**Does show:** whether prepending the relevant canon file(s) changes a headless")
lines.append("Claude Code response on these specific fixtures, in which direction, and on which")
lines.append("checklist properties — a mechanical, reproducible A/B signal, the same species of")
lines.append("evidence as the retrieval ablation in `docs/roberdan-os-paper-en.md` §9.1.")
lines.append("")
lines.append("**Does not show:**")
lines.append("- That Roberto himself would prefer the with-canon output — the judge is a third")
lines.append("  `claude` call, not Roberto. A sample of real transcripts still needs his eyes.")
lines.append("- Generalization beyond these 10 fixtures — small N, hand-written to make the gap")
lines.append("  visible; real tasks are messier and the gap may be smaller (or larger).")
lines.append("- Independence between judge and subject — both are the same underlying model")
lines.append("  family, so shared blind spots/biases in one may not be caught by the other. This")
lines.append("  is the same caveat the paper makes about focus-group persona sycophancy: a")
lines.append("  simulated evaluator can still be systematically wrong in ways it can't see.")
lines.append("- Robustness — each task ran once; no repeated trials to measure variance across")
lines.append("  runs, and only one judge model was used (no cross-model judging).")
lines.append("")

with open(out_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")

print("\n".join(lines))
PY

echo
echo "[report] wrote $OUT"
