#!/usr/bin/env bash
# test-session-waste.sh — bin/session-waste.sh flags a real waste on synthetic traces AND stays
# SILENT on a clean one. The silent half is not decoration: kanban/README.md's scar says an
# alert that always fires is noise you learn to skip, and the day it says something true nobody
# reads it. So half of this test asserts the tool says NOTHING.
#
# Fixtures are entirely synthetic (fake session ids, invented numbers, no trace content) — the
# tool reads locally and never needs real data to be exercised.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/bin/session-waste.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 not installed"; exit 0; }
[ -x "$TOOL" ] || fail "bin/session-waste.sh is not executable"

# --- fixture 1: a session that triggers EXACTLY one detector (model-routing) --
# A 1-turn, tiny-output session run entirely on an expensive (opus) model. Every other
# detector's fields are deliberately absent/below threshold so only model-routing fires.
d1="$TMP/dirty/aaaaaaaa-0000-0000-0000-000000000001"; mkdir -p "$d1"
cat > "$d1/events.jsonl" <<'EOF'
{"type":"session.start","sessionId":"aaaaaaaa-0000-0000-0000-000000000001","timestamp":"2026-09-01T10:00:00.000Z","data":{"reasoningEffort":"high"}}
{"type":"user.message","sessionId":"aaaaaaaa-0000-0000-0000-000000000001","timestamp":"2026-09-01T10:00:01.000Z","data":{"content":"x"}}
{"type":"assistant.message","sessionId":"aaaaaaaa-0000-0000-0000-000000000001","timestamp":"2026-09-01T10:00:02.000Z","data":{"model":"claude-opus-5","outputTokens":60}}
{"type":"assistant.message","sessionId":"aaaaaaaa-0000-0000-0000-000000000001","timestamp":"2026-09-01T10:00:03.000Z","data":{"model":"claude-opus-5","outputTokens":60}}
{"type":"session.shutdown","sessionId":"aaaaaaaa-0000-0000-0000-000000000001","timestamp":"2026-09-01T10:00:04.000Z","data":{"systemTokens":1000,"currentTokens":8000,"modelMetrics":{"claude-opus-5":{"requests":{"count":2,"cost":5},"totalNanoAiu":6000000000,"usage":{"outputTokens":120,"cacheReadTokens":1000,"cacheWriteTokens":1000}}}}}
EOF

out1="$(bash "$TOOL" --dir "$TMP/dirty" 2>/dev/null)" || fail "tool exited non-zero on the dirty fixture"
[ -n "$out1" ] || fail "tool was silent on a session that should trigger model-routing"
grep -q "model-routing" <<<"$out1" || fail "model-routing not reported; got:\n$out1"
grep -q "aaaaaaaa" <<<"$out1" || fail "finding did not name the (synthetic) session id"
grep -qi "impact (estimate)" <<<"$out1" || fail "finding did not label its impact as an estimate"
grep -qi "remedy:" <<<"$out1" || fail "finding did not include a remedy"
# It must flag ONLY model-routing here — the other four detectors' fields are absent/sub-threshold.
for other in prompt-init-overhead context-bloat cache-expiration cache-churn; do
  grep -q "$other" <<<"$out1" && fail "unexpected detector fired on the model-routing fixture: $other"
done
echo "  ok: flags model-routing (with impact-estimate + remedy) and nothing else on the dirty fixture"

# --- fixture 2: a clean session — the tool MUST be silent ---------------------
# Multi-turn on a cheap model, no oversized payload, turns seconds apart, balanced cache,
# fixed prompt a tiny share of context. Nothing here is wasteful, so nothing must be printed.
d2="$TMP/clean/bbbbbbbb-0000-0000-0000-000000000002"; mkdir -p "$d2"
cat > "$d2/events.jsonl" <<'EOF'
{"type":"session.start","sessionId":"bbbbbbbb-0000-0000-0000-000000000002","timestamp":"2026-09-01T11:00:00.000Z","data":{"reasoningEffort":"medium"}}
{"type":"user.message","sessionId":"bbbbbbbb-0000-0000-0000-000000000002","timestamp":"2026-09-01T11:00:01.000Z","data":{"content":"x"}}
{"type":"assistant.message","sessionId":"bbbbbbbb-0000-0000-0000-000000000002","timestamp":"2026-09-01T11:00:02.000Z","data":{"model":"claude-sonnet-5","outputTokens":400}}
{"type":"tool.execution_complete","sessionId":"bbbbbbbb-0000-0000-0000-000000000002","timestamp":"2026-09-01T11:00:03.000Z","data":{"model":"claude-sonnet-5","result":{"ok":true}}}
{"type":"user.message","sessionId":"bbbbbbbb-0000-0000-0000-000000000002","timestamp":"2026-09-01T11:00:20.000Z","data":{"content":"y"}}
{"type":"assistant.message","sessionId":"bbbbbbbb-0000-0000-0000-000000000002","timestamp":"2026-09-01T11:00:25.000Z","data":{"model":"claude-sonnet-5","outputTokens":500}}
{"type":"session.shutdown","sessionId":"bbbbbbbb-0000-0000-0000-000000000002","timestamp":"2026-09-01T11:00:30.000Z","data":{"systemTokens":1200,"toolDefinitionsTokens":1500,"currentTokens":120000,"modelMetrics":{"claude-sonnet-5":{"requests":{"count":2,"cost":2},"totalNanoAiu":2000000000,"usage":{"outputTokens":900,"cacheReadTokens":80000,"cacheWriteTokens":4000}}}}}
EOF

out2="$(bash "$TOOL" --dir "$TMP/clean" 2>/dev/null)" || fail "tool exited non-zero on the clean fixture"
[ -z "$out2" ] || fail "SILENCE VIOLATED: tool printed on a clean session:\n$out2"
echo "  ok: silent (no stdout) on a clean session"

# --- fixture 3: an empty directory — silent, exit 0, never a crash -----------
mkdir -p "$TMP/empty"
out3="$(bash "$TOOL" --dir "$TMP/empty" 2>/dev/null)" || fail "tool exited non-zero on an empty dir"
[ -z "$out3" ] || fail "tool printed something on an empty dir:\n$out3"
echo "  ok: silent + exit 0 on an empty directory (no traces at all)"

# --- fixture 4: a malformed line must be skipped, not fatal ------------------
d4="$TMP/mixed/cccccccc-0000-0000-0000-000000000003"; mkdir -p "$d4"
{ echo 'not json at all {{{'; cat "$d1/events.jsonl"; } > "$d4/events.jsonl"
out4="$(bash "$TOOL" --dir "$TMP/mixed" 2>/dev/null)" || fail "tool exited non-zero on a file with a malformed line"
grep -q "model-routing" <<<"$out4" || fail "malformed line broke parsing; expected model-routing still reported"
echo "  ok: skips a malformed line and still analyses the rest"

echo "PASS: session-waste flags a real waste (impact-estimate + remedy) AND stays silent on clean/empty input"
