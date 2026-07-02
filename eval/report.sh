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


# --- skill-type canon detection --------------------------------------------------------
# A task whose `canon:` points at a skills/<name>/skill.md (or SKILL.md) file is measured
# differently from one pointing at behavior/*.md or rules/*.md. A skill file is a PROCEDURAL
# WORKFLOW meant to be EXECUTED (Skill tool invocation: multi-step ritual, often parallel
# sub-agents, file outputs) — not passive context meant to be READ before answering. run-eval.sh
# still prepends the whole skill file verbatim as condition-B context (same injection as
# behavior/rules canon, for mechanical uniformity), but that is a known mismatch: an agent that
# faithfully follows a skill file read as context will perform the skill's *intake ritual*
# (e.g. premortem's "clarify what success looks like first") even when the task calls for a
# direct, single-shot answer — which is exactly what a real Skill-tool invocation would NOT do
# for a task like "talk me through it" (the skill system decides whether/how to invoke, a raw
# text prepend cannot). Scoring that against a checklist built for a direct answer isn't a fair
# test of "does the canon help" — it's a test of "does dumping a workflow as text derail a
# single-shot answer," which is a different, already-known-true claim. See eval/README.md.
#
# So: skill-type tasks are EXCLUDED from the aggregate summary and the per-canon-file ranking
# (they would otherwise dominate/distort "which canon file mattered most" with a signal that
# isn't about the canon's content). They are still run and judged (real, non-stub data) and
# reported in a separate table below, for qualitative reference and to keep this limitation
# visible rather than silently averaged away.
#
# Simplification: if a task lists MULTIPLE canon files and ANY of them is skill-type, the WHOLE
# task is treated as skill-type (none of the 10 current fixtures mixes skill + non-skill canon,
# so this doesn't currently bite — flagged here so it doesn't surprise a future fixture author).
SKILL_CANON_RE = re.compile(r"^skills/[^/]+/skill\.md$", re.IGNORECASE)


def is_skill_canon(canon_files):
    return any(SKILL_CANON_RE.match(cf) for cf in canon_files)


rows = []           # per-task summary rows (core, i.e. non-skill-type canon)
skill_rows = []      # per-task summary rows for skill-type canon tasks (qualitative only)
canon_stats = {}     # canon file -> {"n":..,"gap_sum":..,"b_wins":..,"a_wins":..,"ties":..} (core only)
holistic_counts = {"output_b": 0, "output_a": 0, "tie": 0, "unparsed": 0}  # core only
had_stub_marker = False

task_files = sorted(glob.glob(os.path.join(tasks_dir, "*.md")))
for tf in task_files:
    fm = read_frontmatter(tf)
    tid = fm.get("id", os.path.splitext(os.path.basename(tf))[0])
    category = fm.get("category", "?")
    canon = fm.get("canon", "")
    canon_files = [c.strip() for c in canon.split(",") if c.strip()]
    skill_type = is_skill_canon(canon_files)
    target_rows = skill_rows if skill_type else rows

    verdict_path = os.path.join(results_dir, tid, "verdict.md")
    a_path = os.path.join(results_dir, tid, "a.md")
    b_path = os.path.join(results_dir, tid, "b.md")

    if not os.path.exists(verdict_path):
        target_rows.append({"id": tid, "category": category, "canon": canon,
                            "score_a": "-", "score_b": "-", "winner": "no verdict"})
        continue

    vtext = open(verdict_path, encoding="utf-8", errors="replace").read()
    if "stub=1" in vtext:
        had_stub_marker = True
    om = re.search(r"output_1=(\w+)\s+output_2=(\w+)", vtext)
    order1, order2 = (om.group(1), om.group(2)) if om else (None, None)

    obj = extract_json_block(vtext)
    if not obj or not order1:
        target_rows.append({"id": tid, "category": category, "canon": canon,
                            "score_a": "-", "score_b": "-", "winner": "unparseable"})
        if not skill_type:
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
        if not skill_type:
            holistic_counts["output_b"] += 1
    elif winner_cond == "a":
        winner = "A (no canon)"
        if not skill_type:
            holistic_counts["output_a"] += 1
    elif hv == "tie":
        winner = "tie"
        if not skill_type:
            holistic_counts["tie"] += 1
    else:
        winner = "unparsed"
        if not skill_type:
            holistic_counts["unparsed"] += 1

    target_rows.append({"id": tid, "category": category, "canon": canon,
                        "score_a": f"{score_a}/{max_possible}", "score_b": f"{score_b}/{max_possible}",
                        "winner": winner})

    if not skill_type:
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
lines.append("## Per-task results (core — behavior/rules canon, aggregated below)")
lines.append("")
lines.append("| Task | Category | Canon file(s) | Score A (no canon) | Score B (with canon) | Holistic winner |")
lines.append("|---|---|---|---|---|---|")
for r in rows:
    lines.append(f"| {r['id']} | {r['category']} | {r['canon']} | {r['score_a']} | {r['score_b']} | {r['winner']} |")

judged = holistic_counts["output_a"] + holistic_counts["output_b"] + holistic_counts["tie"]
core_n = len(rows)
lines.append("")
lines.append("## Summary (core tasks only)")
lines.append("")
lines.append(f"- Core tasks with a parsed verdict: **{judged}** / {core_n}")
lines.append(f"- B (with canon) preferred: **{holistic_counts['output_b']}**")
lines.append(f"- A (no canon) preferred: **{holistic_counts['output_a']}**")
lines.append(f"- Tie: **{holistic_counts['tie']}**")
if holistic_counts["unparsed"]:
    lines.append(f"- Unparseable / missing verdicts: **{holistic_counts['unparsed']}**")
if skill_rows:
    lines.append(f"- Plus **{len(skill_rows)}** skill-type canon task(s), judged but excluded from this")
    lines.append("  summary and from the per-canon-file ranking below — see \"Skill-type canon tasks\" section.")
lines.append("")
lines.append("### Which canon file mattered most (avg score gap, B minus A)")
lines.append("")
lines.append("_Core (`behavior/*.md`, `rules/*.md`, `AGENTS.md`) canon files only — see methodology note below")
lines.append("for why skill files are excluded from this ranking._")
lines.append("")
if canon_stats:
    lines.append("| Canon file | Tasks | Avg gap (B-A) | B wins | A wins | Tie |")
    lines.append("|---|---|---|---|---|---|")
    for cf, st in sorted(canon_stats.items(), key=lambda kv: -(kv[1]["gap_sum"] / max(kv[1]["n"], 1))):
        avg_gap = st["gap_sum"] / st["n"] if st["n"] else 0
        lines.append(f"| {cf} | {st['n']} | {avg_gap:+.2f} | {st['b_wins']} | {st['a_wins']} | {st['ties']} |")
else:
    lines.append("_No judged core tasks yet — run `eval/run-eval.sh` then `eval/judge.sh` first._")

lines.append("")
lines.append("## Skill-type canon tasks (qualitative only — NOT in the aggregate above)")
lines.append("")
lines.append("Tasks whose `canon:` points at a `skills/<name>/skill.md` file. Excluded from the")
lines.append("core summary and per-canon-file ranking above — see the methodology note immediately")
lines.append("below for why. Still run and judged for real (not stubbed out), and shown here so the")
lines.append("data isn't hidden, just kept from silently distorting the aggregate.")
lines.append("")
if skill_rows:
    lines.append("| Task | Category | Canon file(s) | Score A (no canon) | Score B (with canon) | Holistic winner |")
    lines.append("|---|---|---|---|---|---|")
    for r in skill_rows:
        lines.append(f"| {r['id']} | {r['category']} | {r['canon']} | {r['score_a']} | {r['score_b']} | {r['winner']} |")
else:
    lines.append("_No skill-type canon tasks in this run._")
lines.append("")
lines.append("### Methodology note: why skill-type canon is excluded from the aggregate")
lines.append("")
lines.append("A file under `behavior/` or `rules/` is written to be **read as context** — prose")
lines.append("guidance an agent should keep in mind while answering. A file under `skills/*/skill.md`")
lines.append("is written to be **executed as a procedure** (a named Skill invocation: an explicit")
lines.append("multi-step ritual, often parallel sub-agents, file outputs to `~/.claude/reports/`).")
lines.append("Condition B in this harness prepends the canon file verbatim as passive text before")
lines.append("the task — a faithful mirror of how `behavior/`/`rules/` canon actually reaches a real")
lines.append("session, but NOT how a skill actually reaches one (a skill is invoked, not pasted).")
lines.append("")
lines.append("Observed effect on real (non-stub) runs: for `09-feature-bet-premortem`")
lines.append("(canon: `skills/premortem/skill.md`), the agent followed the skill's intake ritual —")
lines.append("which requires clarifying \"what does success look like\" before proceeding — and")
lines.append("answered with a clarifying question instead of the direct, substantial take the task")
lines.append("(\"Talk me through it\") asked for. Same dynamic suspected for")
lines.append("`08-product-launch-signoff` (canon: `skills/focus-group/skill.md`). Both score A over B")
lines.append("as a result. That is real signal, but about **the injection method**, not about")
lines.append("whether the premortem/focus-group skills are good canon — it would recur for any")
lines.append("procedural skill file pasted as passive context ahead of a single-shot-answer task.")
lines.append("Treat these two rows as a demonstrated known limitation of prepend-as-context for")
lines.append("skill-type canon, not as \"the canon lost.\"")
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
lines.append("- Anything about skill-type canon (`skills/*/skill.md`) — see the dedicated section")
lines.append("  above. Prepend-as-context is a known-bad fit for a file meant to be invoked, so")
lines.append("  those 2 fixtures are reported qualitatively only, never averaged into the 8 above.")
lines.append("")

with open(out_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")

print("\n".join(lines))
PY

echo
echo "[report] wrote $OUT"
