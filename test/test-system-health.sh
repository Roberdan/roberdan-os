#!/usr/bin/env bash
# test-system-health.sh — bin/cost-report.sh + bin/system-health.sh against FIXTURE data only
# (mktemp sqlite db + mktemp jsonl transcripts), never the real ~/.copilot or ~/.claude.
# Covers: numbers correct on the fixture, missing sources degrade, a proposal fires when a
# threshold is crossed (and stays silent when green), and the digest triggers a stale report.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
# Built via python3's sqlite3 MODULE, not the `sqlite3` CLI binary — python3 is already a hard
# dependency of this suite (and of bin/cost_report_copilot.py itself), so this gate is never a
# silent skip on a runner that lacks the separate CLI tool.
_sqlite() { python3 -c 'import sqlite3, sys
c = sqlite3.connect(sys.argv[1]); c.executescript(sys.stdin.read()); c.commit(); c.close()' "$1"; }

# --- fixture timestamps (computed at run time, never hardcoded) --------------
read -r _ CUR PREV OUTSIDE < <(python3 -c '
from datetime import datetime, timedelta, timezone
n = datetime.now(timezone.utc)
f = lambda dt, ms: dt.strftime("%Y-%m-%dT%H:%M:%S" + (".000Z" if ms else "Z"))
print(f(n,1), f(n-timedelta(hours=2),1), f(n-timedelta(hours=30),1), f(n-timedelta(days=3),0))
')

# --- fixture 1: Copilot session-store.db (schema matches the real store) -----
STORE="$TMP/session-store.db"
_sqlite "$STORE" <<SQL
CREATE TABLE sessions (id TEXT PRIMARY KEY, cwd TEXT, repository TEXT, host_type TEXT,
  branch TEXT, summary TEXT, created_at TEXT, updated_at TEXT);
CREATE TABLE assistant_usage_events (id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT,
  turn_index INTEGER, agent_id TEXT, parent_tool_call_id TEXT, model TEXT,
  input_tokens INTEGER, output_tokens INTEGER, cache_read_tokens INTEGER,
  cache_write_tokens INTEGER, reasoning_tokens INTEGER, total_nano_aiu INTEGER,
  request_multiplier REAL, duration_ms INTEGER, time_to_first_token_ms INTEGER,
  inter_token_latency_ms INTEGER, initiator TEXT, api_endpoint TEXT, reasoning_effort TEXT,
  finish_reason TEXT, content_filter_triggered INTEGER, token_details_json TEXT,
  created_at TEXT);
INSERT INTO sessions VALUES ('s1','/x','org/repoA','copilot','main','', '$CUR','$CUR');
-- current window: one user call (\$1.00) + one sub-agent call on a FRONTIER model (\$0.50)
INSERT INTO assistant_usage_events (session_id, model, input_tokens, output_tokens,
  cache_read_tokens, cache_write_tokens, total_nano_aiu, request_multiplier, duration_ms,
  initiator, created_at) VALUES
  ('s1','gpt-6-astra',1000,500,200,0,100000000000,1.0,2000,'user','$CUR'),
  ('s1','gpt-6-astra',2000,300,100,0, 50000000000,0.0,1000,'sub-agent','$CUR');
-- previous window: the same user call at double the price, so the arrow is a clean ↓50%
INSERT INTO assistant_usage_events (session_id, model, input_tokens, output_tokens,
  cache_read_tokens, cache_write_tokens, total_nano_aiu, request_multiplier, duration_ms,
  initiator, created_at) VALUES
  ('s1','gpt-6-astra',1000,500,200,0,200000000000,1.0,2000,'user','$PREV');
SQL

# --- fixture 2: Claude Code transcripts (dedup + subagent dir + repo from cwd) -
PROJ="$TMP/claude-projects/-fake-project"
SESS="a1111111-1111-1111-1111-111111111111"
mkdir -p "$PROJ/$SESS/subagents"
CWD="/Users/x/GitHub/roberdan-os"
# main file: msg-1 split across TWO lines (must dedupe to ONE), msg-2 distinct, msg-3 outside
# the window (must be excluded), msg-4 on the synthetic pseudo-model (must be skipped).
{
  printf '{"type":"assistant","cwd":"%s","timestamp":"%s","message":{"id":"msg-1","model":"claude-sonnet-5","usage":{"input_tokens":1000,"output_tokens":100,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' "$CWD" "$CUR"
  printf '{"type":"assistant","cwd":"%s","timestamp":"%s","message":{"id":"msg-1","model":"claude-sonnet-5","usage":{"input_tokens":1000,"output_tokens":100,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' "$CWD" "$CUR"
  printf '{"type":"assistant","cwd":"%s","timestamp":"%s","message":{"id":"msg-2","model":"claude-sonnet-5","usage":{"input_tokens":500,"output_tokens":50,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' "$CWD" "$CUR"
  printf '{"type":"assistant","cwd":"%s","timestamp":"%s","message":{"id":"msg-3-old","model":"claude-sonnet-5","usage":{"input_tokens":9999,"output_tokens":9999,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' "$CWD" "$OUTSIDE"
  printf '{"type":"assistant","cwd":"%s","timestamp":"%s","message":{"id":"msg-4","model":"<synthetic>","usage":{"input_tokens":7777,"output_tokens":7777,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' "$CWD" "$CUR"
} > "$PROJ/$SESS.jsonl"
printf '{"type":"assistant","cwd":"%s","timestamp":"%s","message":{"id":"msg-sub-1","model":"claude-sonnet-5","usage":{"input_tokens":300,"output_tokens":30,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' "$CWD" "$CUR" \
  > "$PROJ/$SESS/subagents/agent-1.jsonl"

# === T1: cost-report.sh numbers on the fixture ================================
out="$(RDA_COPILOT_STORE="$STORE" RDA_CLAUDE_PROJECTS="$TMP/claude-projects" \
  bash "$ROOT/bin/cost-report.sh" --days 1 2>&1)" \
  || fail "cost-report.sh exited non-zero on a clean fixture"

grep -q 'spesa a listino totale: \$1\.50' <<<"$out" || fail "Copilot USD total wrong, want \$1.50: $out"
# cur \$1.50 (user \$1.00 + sub-agent \$0.50) vs prev \$2.00 (user only) = -25%.
grep -q '↓ 25%' <<<"$out" || fail "Copilot USD arrow vs previous window wrong (want ↓ 25%): $out"
grep -qE 'quota sotto-agenti sulla spesa: 33%' <<<"$out" || fail "Copilot sub-agent USD share wrong (want 33%, 0.50/1.50)"
grep -q 'quota sotto-agenti su modelli frontier (spesa): 100%' <<<"$out" \
  || fail "frontier sub-agent share wrong: the only sub-agent row is on gpt-6-astra (frontier)"
grep -q 'org/repoA (\$1.50)' <<<"$out" || fail "Copilot top-repo line wrong"
grep -qE '@@METRIC subagent_frontier_share_pct 100\.0' <<<"$out" || fail "machine-readable frontier metric missing/wrong"

# msg-1 deduped to ONE (1000+100) despite appearing on two lines, msg-2 (500+50), msg-4 (the
# synthetic pseudo-model) skipped, msg-3-old (outside the window) skipped -> main file contributes
# 1650 tokens over 2 calls; the subagents/ file adds 300+30=330 over 1 call -> 1980 total, 3 calls.
grep -qE 'claude-sonnet-5 *3 *1k' <<<"$out" || fail "Claude calls/tokens wrong (want 3 calls, ~1980->1k tokens): $out"
grep -q 'quota sotto-agenti sui token: 17%' <<<"$out" || fail "Claude sub-agent token share wrong (want 330/1980=17%)"
grep -q 'roberdan-os (1k)' <<<"$out" || fail "Claude top-repo (from cwd, worktree-normalized) line wrong"

# === T2: missing sources degrade instead of crashing ===========================
out2="$(RDA_COPILOT_STORE="$TMP/no-such.db" RDA_CLAUDE_PROJECTS="$TMP/no-such-dir" \
  bash "$ROOT/bin/cost-report.sh" --days 1 2>&1)" \
  || fail "cost-report.sh must exit 0 even when both sources are missing"
grep -q 'non disponibile: file assente' <<<"$out2" || fail "missing Copilot store must say non disponibile"
grep -q 'non disponibile: cartella assente' <<<"$out2" || fail "missing Claude projects dir must say non disponibile"

echo "PASS(1/4): cost-report numbers correct on fixture; missing sources degrade"

# === T3: system-health.sh — a crossed threshold proposes, a green one stays silent ============
FAKEBIN="$TMP/fakebin"; mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/gbrain" <<'EOF'
#!/usr/bin/env bash
# Fake gbrain: only serves `doctor --json --fast` (the queue/embedding section). The probe
# itself is exercised through RDA_HEALTH_PROBE_CMD, not through this binary.
[ "${1:-}" = "doctor" ] && echo '{"health_score":77,"top_issues":[{"name":"minions_migration","status":"fail"}]}'
exit 1
EOF
chmod +x "$FAKEBIN/gbrain"
# _sec_probe requires `command -v timeout` (bin/system-health.sh) — a pass-through shim keeps
# this scenario hermetic to whatever the runner does or doesn't have (e.g. a CI image without
# GNU coreutils' timeout), instead of silently depending on this machine's real one.
printf '#!/usr/bin/env bash\nshift; exec "$@"\n' > "$FAKEBIN/timeout"; chmod +x "$FAKEBIN/timeout"

KB_STUB="$TMP/kb-stub.sh"
YES_MARKER="$TMP/yes-was-passed"
cat > "$KB_STUB" <<EOF
#!/usr/bin/env bash
case "\$*" in *--yes*) : > "$YES_MARKER" ;; esac
case "\$1 \$2" in
  "wt --all") printf '5 copie esaminate · 5 rimovibili · 0 da tenere -- per rimuoverle: kb wt --yes\n' ;;
  "pending --count") echo 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$KB_STUB"

PROBE_STUB="$TMP/probe-stub.sh"
printf '#!/usr/bin/env bash\necho "gbrain-search-probe: 3/10 nei primi 3 (soglia 9)"\n' > "$PROBE_STUB"
chmod +x "$PROBE_STUB"

TELEMETRY_STUB="$TMP/telemetry-stub.sh"
printf '#!/usr/bin/env bash\necho "  Voci con cambiamenti: 0. Non confrontabile non significa invariato."\n' > "$TELEMETRY_STUB"
chmod +x "$TELEMETRY_STUB"

CLAUDE_HOME="$TMP/claude_home"; mkdir -p "$CLAUDE_HOME/rules"
echo "some fixed canon text" > "$CLAUDE_HOME/CLAUDE.md"
AGENTS_FIXTURE="$TMP/agents.md"; echo "agents canon" > "$AGENTS_FIXTURE"
RDA_HOME_RED="$TMP/rda-home-red"

report_red="$(PATH="$FAKEBIN:$PATH" RDA_HOME="$RDA_HOME_RED" \
  RDA_COPILOT_STORE="$STORE" RDA_CLAUDE_PROJECTS="$TMP/claude-projects" \
  RDA_HEALTH_KB="$KB_STUB" RDA_HEALTH_PROBE_CMD="$PROBE_STUB" RDA_HEALTH_PROBE_TIMEOUT=10 \
  RDA_HEALTH_TELEMETRY_CMD="$TELEMETRY_STUB" RDA_CLAUDE_HOME="$CLAUDE_HOME" \
  RDA_HEALTH_AGENTS_MD="$AGENTS_FIXTURE" RDA_HEALTH_THRESH_TOKENS=1 \
  bash "$ROOT/bin/system-health.sh" 2>&1)" || fail "system-health.sh must exit 0 even with red sections"

[ -f "$YES_MARKER" ] && fail "system-health.sh must NEVER pass --yes to kb wt"
grep -q 'quota sotto-agenti su modelli frontier (spesa): 100%' <<<"$report_red" || fail "frontier metric missing from the woven report"
grep -q '## Proposte' <<<"$report_red" || fail "report missing the Proposte section"
n_prop="$(sed -n '/^## Proposte/,$p' <<<"$report_red" | grep -c '^- ')"
[ "$n_prop" -eq 4 ] || fail "expected 4 proposals (frontier, probe, worktrees, tokens), got $n_prop:
$report_red"
grep -q 'quota di spesa dei sotto-agenti Copilot su modelli frontier' <<<"$report_red" || fail "missing frontier proposal"
grep -q 'probe di ricerca gbrain a 3/10' <<<"$report_red" || fail "missing probe proposal"
grep -q 'copie di lavoro rimovibili: 5' <<<"$report_red" || fail "missing worktree proposal"
grep -q 'token fissi a inizio sessione' <<<"$report_red" || fail "missing tokens proposal"
# PATH is APPENDED with ~/.bun/bin, never prepended (bin/system-health.sh) — FAKEBIN, put first
# on PATH by this test, must still win. 77 is the fake gbrain's own score: seeing it here proves
# the section talked to FAKEBIN, not to a real gbrain that might happen to exist on this machine.
grep -q 'punteggio di salute: 77/100' <<<"$report_red" || fail "gbrain doctor section did not use the fake gbrain (PATH isolation broken)"

# Every emitted `kb add …` line must be ACCEPTED by the real gate against an isolated board —
# a proposal Roberto can't actually run would be worse than no proposal.
KB_REAL="$ROOT/kanban/kb.sh"
KB_BOARD="$TMP/kb-board"; mkdir -p "$KB_BOARD"/{todo,doing,done}
: > "$TMP/kb-registry"
n_accepted=0
while IFS= read -r cmdline; do
  [ -n "$cmdline" ] || continue
  n_accepted=$((n_accepted + 1))
  # cmdline is literally "kb add \"...\" --repo ..." — drop the leading "kb " so the real
  # kb.sh (invoked directly as `bash kb.sh add ...`) sees "add" as its first argument.
  RDA_KANBAN="$KB_BOARD" RDA_KANBAN_REGISTRY="$TMP/kb-registry" \
    bash -c "bash \"$KB_REAL\" ${cmdline#kb }" >/dev/null 2>&1 \
    || fail "a proposed kb add command was REFUSED by the real gate: $cmdline"
done < <(grep -oE 'kb add ".*"$' <<<"$report_red")
[ "$n_accepted" -eq 4 ] || fail "expected to run+accept 4 kb add proposals, ran $n_accepted"
n_landed=0; for f in "$KB_BOARD/todo"/*.md; do [ -e "$f" ] && n_landed=$((n_landed + 1)); done
[ "$n_landed" -eq 4 ] || fail "accepted proposals did not land 4 cards on the isolated board (got $n_landed)"

echo "PASS(2/4): red thresholds each propose a card, no auto kb add, every proposal is accepted by the real gate, never --yes"

# The counterpart: an all-green run proposes NOTHING (silence is the other half of the gate).
KB_STUB_GREEN="$TMP/kb-stub-green.sh"
cat > "$KB_STUB_GREEN" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "wt --all") printf '3 copie esaminate · 0 rimovibili · 3 da tenere -- per rimuoverle: kb wt --yes\n' ;;
  "pending --count") echo 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$KB_STUB_GREEN"
PROBE_STUB_GREEN="$TMP/probe-stub-green.sh"
printf '#!/usr/bin/env bash\necho "gbrain-search-probe: 10/10 nei primi 3 (soglia 9)"\n' > "$PROBE_STUB_GREEN"
chmod +x "$PROBE_STUB_GREEN"
RDA_HOME_GREEN="$TMP/rda-home-green"
report_green="$(PATH="$FAKEBIN:$PATH" RDA_HOME="$RDA_HOME_GREEN" \
  RDA_COPILOT_STORE="$TMP/no-such.db" RDA_CLAUDE_PROJECTS="$TMP/no-such-dir" \
  RDA_HEALTH_KB="$KB_STUB_GREEN" RDA_HEALTH_PROBE_CMD="$PROBE_STUB_GREEN" RDA_HEALTH_PROBE_TIMEOUT=10 \
  RDA_HEALTH_TELEMETRY_CMD="$TELEMETRY_STUB" RDA_CLAUDE_HOME="$CLAUDE_HOME" \
  RDA_HEALTH_AGENTS_MD="$AGENTS_FIXTURE" \
  bash "$ROOT/bin/system-health.sh" 2>&1)" || fail "system-health.sh must exit 0 when green"
grep -q 'Nessuna proposta' <<<"$report_green" || fail "an all-green run must propose nothing: $report_green"

echo "PASS(3/4): an all-green run proposes nothing (the silent direction matters too)"

# === T4: digest integration triggers a stale/absent report, skips a fresh one =================
DIGEST="$ROOT/bin/pending-digest.sh"
HEALTH_STUB="$TMP/health-stub.sh"
RAN_MARKER="$TMP/health-ran"
cat > "$HEALTH_STUB" <<EOF
#!/usr/bin/env bash
: >> "$RAN_MARKER"
mkdir -p "\$RDA_HOME/reports"
{ echo "# roberdan-os -- salute del sistema (\$(date +%Y-%m-%d))"; echo; echo "## Proposte (da approvare)"; echo "Nessuna proposta: nessuna soglia documentata e' stata superata."; } \\
  > "\$RDA_HOME/reports/system-health-\$(date +%Y-%m-%d).md"
EOF
chmod +x "$HEALTH_STUB"

RDA_HOME_DIGEST="$TMP/rda-home-digest"
mkdir -p "$RDA_HOME_DIGEST/reports" "$TMP/empty-board"/{todo,doing,done} "$TMP/empty-quar"
: > "$TMP/kb-registry"
rm -f "$RAN_MARKER"
RDA_KANBAN="$TMP/empty-board" RDA_KANBAN_REGISTRY="$TMP/kb-registry" RDA_QUARANTINE="$TMP/empty-quar" \
  RDA_HOME="$RDA_HOME_DIGEST" RDA_KB="$KB_STUB_GREEN" RDA_HEALTH_CMD="$HEALTH_STUB" bash "$DIGEST" >/dev/null 2>&1
[ -f "$RAN_MARKER" ] || fail "digest must run system-health.sh when NO report exists yet"
grep -q '## Salute del sistema' "$RDA_HOME_DIGEST/pending-digest.txt" || fail "digest missing the health section after a real run"

rm -f "$RAN_MARKER"
RDA_KANBAN="$TMP/empty-board" RDA_KANBAN_REGISTRY="$TMP/kb-registry" RDA_QUARANTINE="$TMP/empty-quar" \
  RDA_HOME="$RDA_HOME_DIGEST" RDA_KB="$KB_STUB_GREEN" RDA_HEALTH_CMD="$HEALTH_STUB" bash "$DIGEST" >/dev/null 2>&1
[ -f "$RAN_MARKER" ] && fail "digest must SKIP system-health.sh when today's report is already fresh"

touch -d "8 days ago" "$RDA_HOME_DIGEST/reports/system-health-$(date +%Y-%m-%d).md" 2>/dev/null \
  || find "$RDA_HOME_DIGEST/reports" -name '*.md' -exec touch -t "$(date -v-8d +%Y%m%d0000 2>/dev/null || date -d '8 days ago' +%Y%m%d0000)" {} \;
rm -f "$RAN_MARKER"
RDA_KANBAN="$TMP/empty-board" RDA_KANBAN_REGISTRY="$TMP/kb-registry" RDA_QUARANTINE="$TMP/empty-quar" \
  RDA_HOME="$RDA_HOME_DIGEST" RDA_KB="$KB_STUB_GREEN" RDA_HEALTH_CMD="$HEALTH_STUB" bash "$DIGEST" >/dev/null 2>&1
[ -f "$RAN_MARKER" ] || fail "digest must re-run system-health.sh once the latest report is >7 days stale"

echo "PASS(4/4): digest runs system-health.sh only when the latest report is missing/stale, never on a fresh one"
