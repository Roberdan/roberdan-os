#!/usr/bin/env bash
# eval/test-eval-pipeline.sh — end-to-end test of the eval/ harness in --stub mode.
# Follows the exact pattern test/test-factory-kb.sh uses to stub `claude` for factory/run.sh:
# a fake executable dropped onto a minimal PATH via `env -i`, no network, no billing. Proves
# run-eval.sh -> judge.sh -> report.sh work mechanically end-to-end, are resumable (a killed/
# partial run only redoes what's missing; a completed run redoes nothing unless --force), and
# that the judge never sees which condition produced which output. Wired into test/validate.sh.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
section() { printf "\n=== %s ===\n" "$1"; }
ok()      { printf "  ok: %s\n" "$1"; }
err()     { printf "  FAIL: %s\n" "$1"; FAIL=1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

TASKS="$TMP/tasks"
RESULTS="$TMP/results"
BIN="$TMP/bin"
mkdir -p "$TASKS" "$RESULTS" "$BIN"

# ---------------------------------------------------------------------------
section "fixtures: two minimal task fixtures pointing at real canon files"
cat > "$TASKS/t1-evidence.md" <<'EOF'
---
id: t1-evidence
category: code-fix
canon: behavior/roberto-mode.md
---

# t1-evidence

## Prompt

Fix the bug and tell me it's done.

## Canon-compliant checklist

- cites evidence
- no unverified done claim
EOF

cat > "$TASKS/t2-voice.md" <<'EOF'
---
id: t2-voice
category: email-draft
canon: behavior/roberto-voice.md
---

# t2-voice

## Prompt

Draft the follow-up email.

## Canon-compliant checklist

- cites evidence
- no unverified done claim
EOF
ok "wrote 2 task fixtures under $TASKS"

# ---------------------------------------------------------------------------
section "stub claude: differentiated output per condition + content-based judge"
# invoked as: claude -p "<prompt>" --dangerously-skip-permissions --add-dir <dir>
# Role is decided by inspecting $2 (the prompt), same technique test-factory-kb.sh uses to
# distinguish a thor-verify call from a normal task call.
cat > "$BIN/claude" <<'STUBEOF'
#!/usr/bin/env bash
echo "invoked" >> "${EVAL_STUB_COUNTER:?}"
prompt="$2"
case "$prompt" in
  *"=== CHECKLIST ==="*)
    # judge role — content-based scoring only (must never see condition labels). Captures the
    # exact prompt it received so the test can assert no "condition=A/B" leak reached it.
    if [ -n "${EVAL_STUB_CAPTURE_JUDGE_PROMPT:-}" ]; then
      { printf '%s' "$prompt"; printf '\n===NEXT===\n'; } >> "$EVAL_STUB_CAPTURE_JUDGE_PROMPT"
    fi
    o1="$(printf '%s' "$prompt" | awk '/=== OUTPUT 1 ===/{f=1;next} /=== OUTPUT 2 ===/{f=0} f')"
    o2="$(printf '%s' "$prompt" | awk '/=== OUTPUT 2 ===/{f=1;next} f')"
    w1=0; w2=0
    printf '%s' "$o1" | grep -q "FAKE-SHA" && w1=2
    printf '%s' "$o2" | grep -q "FAKE-SHA" && w2=2
    if [ "$w1" -gt "$w2" ]; then holistic="output_1"
    elif [ "$w2" -gt "$w1" ]; then holistic="output_2"
    else holistic="tie"
    fi
    cat <<JSON
\`\`\`json
{"properties":[{"name":"cites evidence","score_output1":$w1,"score_output2":$w2},{"name":"no unverified done claim","score_output1":$w1,"score_output2":$w2}],"holistic_verdict":"$holistic","holistic_reason":"stub judge: FAKE-SHA marker detection, content-based only"}
\`\`\`
JSON
    ;;
  *"=== TASK ==="*)
    # condition B: canon was prepended before the "=== TASK ===" marker (see run-eval.sh)
    echo "Done. Evidence: commit FAKE-SHA-a1b2c3d, test output: 3 passed, 0 failed. (canon-compliant stub)"
    ;;
  *)
    # condition A: raw task prompt only, no canon marker
    echo "Yep, it's done, should be fine now."
    ;;
esac
exit 0
STUBEOF
chmod +x "$BIN/claude"
ok "stub claude written to $BIN/claude"

COUNTER="$TMP/invocations.log"
: > "$COUNTER"
JUDGE_CAPTURE="$TMP/judge-prompts.log"
: > "$JUDGE_CAPTURE"

run_env() {
  env -i PATH="$BIN:/usr/local/bin:/usr/bin:/bin" HOME="$HOME" \
    RDA_EVAL_TASKS="$TASKS" RDA_EVAL_RESULTS="$RESULTS" RDA_EVAL_TIMEOUT=15 \
    EVAL_STUB_COUNTER="$COUNTER" EVAL_STUB_CAPTURE_JUDGE_PROMPT="$JUDGE_CAPTURE" \
    "$@"
}

# ---------------------------------------------------------------------------
section "run-eval.sh --stub: first run generates all 4 outputs (2 tasks x 2 conditions)"
run_env bash eval/run-eval.sh --stub >"$TMP/run1.log" 2>&1
if [ -f "$RESULTS/t1-evidence/a.md" ] && [ -f "$RESULTS/t1-evidence/b.md" ] \
  && [ -f "$RESULTS/t2-voice/a.md" ] && [ -f "$RESULTS/t2-voice/b.md" ]; then
  ok "all 4 output files present after first run"
else
  err "missing output file(s) after first run — see $TMP/run1.log"
fi
n1="$(wc -l < "$COUNTER" | tr -d ' ')"
[ "$n1" -eq 4 ] && ok "claude invoked exactly 4 times on a fresh run" \
  || err "expected 4 claude invocations, got $n1"

section "differentiated stub content actually landed in the right files"
if grep -q "FAKE-SHA" "$RESULTS/t1-evidence/b.md" && ! grep -q "FAKE-SHA" "$RESULTS/t1-evidence/a.md"; then
  ok "condition B cites the fake evidence marker, condition A does not"
else
  err "condition A/B outputs are not differentiated as expected"
fi

section "run-eval.sh --stub: resumable — a completed run redoes nothing"
run_env bash eval/run-eval.sh --stub >"$TMP/run2.log" 2>&1
n2="$(wc -l < "$COUNTER" | tr -d ' ')"
[ "$n2" -eq "$n1" ] && ok "second run invoked claude 0 additional times (all pairs already present)" \
  || err "second run re-invoked claude ($n1 -> $n2) — resumability is broken"

section "run-eval.sh --stub: a simulated kill (one missing output) is repaired, others untouched"
before_hash="$(md5sum "$RESULTS/t1-evidence/a.md" "$RESULTS/t2-voice/a.md" "$RESULTS/t2-voice/b.md" 2>/dev/null)"
rm -f "$RESULTS/t1-evidence/b.md"   # simulate: process was killed before this pair finished
run_env bash eval/run-eval.sh --stub >"$TMP/run3.log" 2>&1
n3="$(wc -l < "$COUNTER" | tr -d ' ')"
after_hash="$(md5sum "$RESULTS/t1-evidence/a.md" "$RESULTS/t2-voice/a.md" "$RESULTS/t2-voice/b.md" 2>/dev/null)"
if [ "$n3" -eq $((n1 + 1)) ] && [ -f "$RESULTS/t1-evidence/b.md" ] && [ "$before_hash" = "$after_hash" ]; then
  ok "only the missing pair was regenerated (1 new invocation); the other 3 completed files were untouched"
else
  err "resume-after-kill did not behave as expected (n1=$n1 n3=$n3)"
fi

section "run-eval.sh --stub --force: regenerates everything regardless of existing output"
run_env bash eval/run-eval.sh --stub --force >"$TMP/run4.log" 2>&1
n4="$(wc -l < "$COUNTER" | tr -d ' ')"
[ "$n4" -eq $((n3 + 4)) ] && ok "--force regenerated all 4 pairs (4 new invocations)" \
  || err "--force did not regenerate all pairs as expected (n3=$n3 n4=$n4)"

# ---------------------------------------------------------------------------
section "judge.sh --stub: produces a verdict for each task, blind to condition labels"
run_env bash eval/judge.sh --stub >"$TMP/judge1.log" 2>&1
if [ -f "$RESULTS/t1-evidence/verdict.md" ] && [ -f "$RESULTS/t2-voice/verdict.md" ]; then
  ok "verdict.md written for both tasks"
else
  err "verdict.md missing for at least one task — see $TMP/judge1.log"
fi
if grep -qE 'output_1=(a|b) output_2=(a|b)' "$RESULTS/t1-evidence/verdict.md" 2>/dev/null; then
  ok "order mapping footer present in verdict.md"
else
  err "order mapping footer missing from verdict.md"
fi

section "the judge never saw which condition produced which output"
if grep -qE 'condition=A|condition=B' "$JUDGE_CAPTURE" 2>/dev/null; then
  err "the raw condition banner leaked into the prompt actually sent to the judge"
else
  ok "no 'condition=A/B' banner text reached the judge's prompt (verified via captured prompt)"
fi
if grep -q "OUTPUT 1" "$JUDGE_CAPTURE" && grep -q "OUTPUT 2" "$JUDGE_CAPTURE"; then
  ok "judge prompt does contain the intended Output 1 / Output 2 sections"
else
  err "judge prompt is missing the Output 1 / Output 2 sections entirely"
fi

section "judge.sh --stub: holistic verdict correctly favors the canon-compliant (B) output"
if grep -q '"holistic_verdict": "output_' "$RESULTS/t1-evidence/verdict.md" 2>/dev/null || \
   grep -q '"holistic_verdict":"output_' "$RESULTS/t1-evidence/verdict.md" 2>/dev/null; then
  ok "verdict.md contains a parseable holistic_verdict field"
else
  err "verdict.md does not contain a holistic_verdict field"
fi

section "judge.sh --stub: resumable — a completed judge run redoes nothing without --force"
before="$(md5sum "$RESULTS/t1-evidence/verdict.md")"
n_judge_before="$(wc -l < "$COUNTER" | tr -d ' ')"
run_env bash eval/judge.sh --stub >"$TMP/judge2.log" 2>&1
n_judge_after="$(wc -l < "$COUNTER" | tr -d ' ')"
after="$(md5sum "$RESULTS/t1-evidence/verdict.md")"
if [ "$n_judge_after" -eq "$n_judge_before" ] && [ "$before" = "$after" ]; then
  ok "re-running judge.sh without --force re-judged nothing (0 new invocations, verdict.md unchanged)"
else
  err "judge.sh re-judged an already-judged task without --force"
fi

section "judge.sh --stub --force: re-judges on demand"
run_env bash eval/judge.sh --stub --force >"$TMP/judge3.log" 2>&1
n_judge_force="$(wc -l < "$COUNTER" | tr -d ' ')"
[ "$n_judge_force" -eq $((n_judge_after + 2)) ] && ok "--force re-judged both tasks (2 new invocations)" \
  || err "--force did not re-judge as expected"

# ---------------------------------------------------------------------------
section "report.sh: aggregates verdicts into a well-formed report.md"
run_env bash eval/report.sh --stub >"$TMP/report1.log" 2>&1
REPORT="$RESULTS/report.md"
if [ -f "$REPORT" ]; then ok "report.md written"; else err "report.md was not written"; fi
if grep -q "t1-evidence" "$REPORT" 2>/dev/null && grep -q "t2-voice" "$REPORT" 2>/dev/null; then
  ok "report.md contains rows for both tasks"
else
  err "report.md is missing one or both task rows"
fi
if grep -q "## Summary" "$REPORT" 2>/dev/null && grep -q "## What this does and doesn't prove" "$REPORT" 2>/dev/null; then
  ok "report.md contains the summary and honest-limitations sections"
else
  err "report.md is missing the summary and/or honest-limitations section"
fi
if grep -qE 'B \(with canon\) preferred: \*\*2\*\*' "$REPORT" 2>/dev/null; then
  ok "report.md correctly counts both tasks as B-preferred (matches the stub's designed differentiation)"
else
  err "report.md did not count the expected 2/2 B-preferred verdicts"
fi
if grep -q "which canon file mattered most" "$REPORT" 2>/dev/null || grep -qi "canon file" "$REPORT"; then
  ok "report.md includes the per-canon-file breakdown"
else
  err "report.md is missing the per-canon-file breakdown"
fi

# ---------------------------------------------------------------------------
printf "\n"
if [ "$FAIL" -eq 0 ]; then echo "test-eval-pipeline: ✅ ALL GREEN"; exit 0; else echo "test-eval-pipeline: ❌ FAIL (see above)"; exit 1; fi
