#!/usr/bin/env bash
# eval/test-model-bench.sh — end-to-end test of the MODEL-choice bench (eval/bench-*), the
# card's single acceptance condition: the bench runs end-to-end in DRY-RUN without calling any
# model. It asserts on the FIXTURE PATH being the data source (not merely a zero exit), that no
# agent CLI is ever invoked on a dry run, that the Pareto frontier is computed correctly, that the
# real-run path refuses to spend without explicit confirmation, and that the deriver refuses to
# write real card content anywhere git does not ignore. Same stubbing technique as
# eval/test-eval-pipeline.sh (a fake agent on a minimal PATH via env -i). Wired into validate.sh.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
section() { printf "\n=== %s ===\n" "$1"; }
ok()      { printf "  ok: %s\n" "$1"; }
err()     { printf "  FAIL: %s\n" "$1"; FAIL=1; }

TMP="$(mktemp -d)"
trap '[ -n "${RDA_BENCH_KEEP_TMP:-}" ] || rm -rf "$TMP"' EXIT

BIN="$TMP/bin"; mkdir -p "$BIN"
# A fake agent CLI that records every invocation. On a dry run it must NEVER be touched: the whole
# safety property is that a dry run cannot spend, so it cannot call an agent. Named `claude`
# because bench-run resolves that by default when RDA_EVAL_AGENT_CMD is unset.
COUNTER="$TMP/agent-invocations.log"; : > "$COUNTER"
cat > "$BIN/claude" <<STUBEOF
#!/usr/bin/env bash
echo "invoked" >> "$COUNTER"
echo "STUB-AGENT-RESPONSE (should never appear on a dry run)"
exit 0
STUBEOF
chmod +x "$BIN/claude"

# Deterministic, self-contained fixtures so the assertions do not depend on the committed table:
# model `fast` beats model `slow` on BOTH quality and cost -> slow is DOMINATED, fast is frontier.
FIX="$TMP/fix.tsv"
{
  printf '# test fixture\n'
  printf 't1\teasy\tfast\tpass\t10\t1000\t500\n'
  printf 't2\teasy\tfast\tpass\t12\t1000\t500\n'
  printf 't1\teasy\tslow\tpass\t20\t1000\t500\n'
  printf 't2\teasy\tslow\tfail\t22\t1000\t500\n'
} > "$FIX"
MODELS="$TMP/models.tsv"
{ printf '# test prices\n'; printf 'fast\t1.00\t2.00\n'; printf 'slow\t5.00\t10.00\n'; } > "$MODELS"
OUT="$TMP/pareto.md"

run_env() {
  env -i PATH="$BIN:/usr/local/bin:/usr/bin:/bin" HOME="$HOME" \
    RDA_BENCH_FIXTURE="$FIX" RDA_BENCH_MODELS="$MODELS" RDA_BENCH_RESULTS="$OUT" \
    "$@"
}

# ---------------------------------------------------------------------------
section "dry-run is the default and reads from the fixture path (not a live model)"
run_env bash eval/bench-run.sh >"$TMP/dry.log" 2>&1
dry_rc=$?
[ "$dry_rc" -eq 0 ] && ok "dry-run exited 0" || err "dry-run exited $dry_rc — see $TMP/dry.log"
if grep -qF "reading result records from fixtures: $FIX" "$TMP/dry.log"; then
  ok "dry-run announced the exact fixture path as its data source"
else
  err "dry-run did not name the fixture path — the acceptance is 'runs from fixtures', assert it"
fi
[ -f "$OUT" ] && ok "Pareto table written to the results path" || err "no Pareto table written"

section "THE acceptance: no agent/model was invoked on the dry run"
n_calls="$(wc -l < "$COUNTER" | tr -d ' ')"
if [ "$n_calls" -eq 0 ]; then
  ok "the agent stub was invoked 0 times on a dry run (zero spend, guaranteed)"
else
  err "the agent stub was invoked $n_calls time(s) on a DRY run — spend safety is broken"
fi
if grep -q "STUB-AGENT-RESPONSE" "$OUT" "$TMP/dry.log" 2>/dev/null; then
  err "stub agent output leaked into the dry-run result — a model WAS called"
else
  ok "no stub-agent output anywhere in the dry-run result (confirms the fixture path, not a model)"
fi

section "Pareto logic: the dominated model is marked, the frontier is correct"
if grep -qE '^\| fast \| \*\*frontier\*\*' "$OUT"; then ok "fast is on the frontier"; else err "fast not marked frontier"; fi
if grep -qE '^\| slow \| dominated' "$OUT"; then ok "slow is marked dominated"; else err "slow not marked dominated"; fi
if grep -q "Dominated (another model is at least as good on every axis): slow" "$OUT"; then
  ok "the dominated-models line names slow explicitly"
else
  err "the dominated summary line is missing or wrong"
fi
# cost per completed task: fast = (2 tasks * (1000/1e6*1 + 500/1e6*2)) / 2 completed = $0.0020
if grep -qF '$0.0020' "$OUT"; then ok "cost-per-completed-task is computed from tokens x prices"; else err "cost-per-completed-task figure wrong"; fi
if grep -qF '| 100% |' "$OUT" && grep -qF '| 50% |' "$OUT"; then ok "pass-rate quality axis rendered (100% fast, 50% slow)"; else err "quality axis wrong"; fi

section "the committed fixture also runs end-to-end and marks opus dominated"
run_env2() { env -i PATH="$BIN:/usr/local/bin:/usr/bin:/bin" HOME="$HOME" RDA_BENCH_RESULTS="$TMP/committed.md" "$@"; }
run_env2 bash eval/bench-run.sh --dry-run >"$TMP/dry2.log" 2>&1
if grep -qE '^\| claude-opus \| dominated' "$TMP/committed.md" && grep -qE '^\| claude-sonnet \| \*\*frontier\*\*' "$TMP/committed.md"; then
  ok "committed dry-run fixture: opus dominated, sonnet on the frontier (Uber's own finding shape)"
else
  err "committed fixture did not produce the expected frontier — see $TMP/committed.md"
fi
n_calls2="$(wc -l < "$COUNTER" | tr -d ' ')"
[ "$n_calls2" -eq 0 ] && ok "still zero agent invocations after the committed-fixture dry run" || err "an agent was invoked ($n_calls2)"

# ---------------------------------------------------------------------------
section "real-run guard: --real without --confirm-spend prints an estimate and REFUSES to spend"
TASKS="$TMP/tasks"; mkdir -p "$TASKS"
printf -- '---\nid: r1\ndifficulty: easy\n---\n\n## Prompt\n\ndo the thing\n' > "$TASKS/r1.md"
set +e
env -i PATH="$BIN:/usr/local/bin:/usr/bin:/bin" HOME="$HOME" \
  RDA_BENCH_MODELS="$MODELS" RDA_BENCH_RESULTS="$TMP/real.md" \
  bash eval/bench-run.sh --real --tasks "$TASKS" >"$TMP/real.log" 2>&1
real_rc=$?
set -e
[ "$real_rc" -eq 3 ] && ok "--real without --confirm-spend exits 3 (the human-gate exit)" || err "expected exit 3, got $real_rc"
if grep -q "ESTIMATED COST" "$TMP/real.log"; then ok "an estimated cost was printed BEFORE any spend"; else err "no cost estimate printed"; fi
if grep -q "Human gates" "$TMP/real.log"; then ok "the refusal cites the human gate"; else err "refusal does not cite the human gate"; fi
n_calls3="$(wc -l < "$COUNTER" | tr -d ' ')"
[ "$n_calls3" -eq 0 ] && ok "the guarded --real path invoked NO agent (estimate only)" || err "an agent was invoked on the guarded path ($n_calls3)"

# ---------------------------------------------------------------------------
section "deriver: derives real cards ONLY into a gitignored dir, refuses a tracked one"
CARDS="$TMP/cards"; mkdir -p "$CARDS"
cat > "$CARDS/fake-card-01.md" <<'CARDEOF'
---
title: A synthetic card for the self-test
repo: roberdan-os
dod: "Do a small clearly-bounded thing and show it works"
acceptance: "a test exits 0 proving the thing"
status: done
---
CARDEOF

# (a) refuses a NON-ignored output dir under the repo (the 2026-08-24 privacy scar guard)
set +e
bash eval/bench-derive.sh --cards "$CARDS" --out "eval/selftest-tracked-$$" >"$TMP/der-bad.log" 2>&1
der_bad_rc=$?
set -e
if [ "$der_bad_rc" -eq 2 ] && grep -q "REFUSING" "$TMP/der-bad.log"; then
  ok "deriver refuses to write card content into a NON-gitignored dir (exit 2)"
else
  err "deriver did NOT refuse a tracked output dir (rc=$der_bad_rc) — privacy guard is broken"
fi

# (b) accepts a gitignored dir; the derived task carries the do-not-commit marker + a difficulty
GOOD="eval/bench-tasks-local/.selftest-$$"
git -C "$ROOT" check-ignore -q "$GOOD/.derived" || { err "self-test out dir is not gitignored — fix the test"; }
bash eval/bench-derive.sh --cards "$CARDS" --out "$GOOD" >"$TMP/der-good.log" 2>&1
if [ -f "$GOOD/fake-card-01.md" ] && grep -q "Do NOT commit" "$GOOD/fake-card-01.md" && grep -q '^difficulty:' "$GOOD/fake-card-01.md"; then
  ok "deriver writes into the gitignored dir with a do-not-commit marker and a difficulty grade"
else
  err "derived task missing, or lacks the marker/difficulty — see $TMP/der-good.log"
fi
# the derived files must be invisible to git (gitignored) — the whole point of the split
if [ -z "$(git -C "$ROOT" status --porcelain -- "$GOOD" 2>/dev/null)" ]; then
  ok "the derived card content is invisible to git status (gitignored, cannot be committed by accident)"
else
  err "derived card content shows up in git status — it could be committed"
fi
rm -rf "$ROOT/${GOOD:?}"

# ---------------------------------------------------------------------------
printf "\n"
if [ "$FAIL" -eq 0 ]; then echo "test-model-bench: ✅ ALL GREEN"; exit 0; else echo "test-model-bench: ❌ FAIL (see above)"; exit 1; fi
