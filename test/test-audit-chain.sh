#!/usr/bin/env bash
# test-audit-chain.sh — la catena vera, non due metà che si dichiarano compatibili.
#
# Le prove esistenti verificano l'observer Copilot con uno scrittore iniettato e il registro
# con eventi scritti a mano. Nessuna delle due esegue l'altra: il 17 settembre questo ha
# lasciato passare un contratto disallineato (nomi nativi Claude e observer.* classificati
# "non supportati"). Qui gli eventi nativi entrano dall'observer reale, passano per il vero
# kanban/audit.py e vengono riletti dal registro, insieme a una catena decisione→esito.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STORE="$(mktemp -d "${TMPDIR:-/tmp}/rda-audit-chain-XXXXXX")"
trap 'rm -rf "$STORE"' EXIT
export RDA_AUDIT_HOME="$STORE/audit" RDA_HOME="$STORE/home" RDA_OS="$ROOT"
export PYTHONDONTWRITEBYTECODE=1
FAIL=0
ok()  { printf '  ok: %s\n' "$1"; }
err() { printf '  FAIL: %s\n' "$1"; FAIL=1; }

audit() { python3 "$ROOT/kanban/audit.py" "$@"; }

# --- 1. osservazione nativa Copilot attraverso l'observer reale -----------------------------
node --input-type=module <<'JS' || err "l'observer Copilot non ha scritto nel registro reale"
const { createAuditObserver } = await import(process.env.RDA_OS + "/hooks/copilot/audit.mjs");
const observer = createAuditObserver({ root: process.env.RDA_OS, sessionId: "chain-copilot" });
// Sessione finta: serve solo a far partire l'observer, gli eventi li consegniamo noi.
observer.register({ on: () => () => {} });
if (!await observer.flush()) throw Error("coverage declarations lost");
const timeline = [
    ["session.skills_loaded", { skills: [{ name: "roberdan-twin" }, { name: "pdf" }] }],
    ["tool.execution_start", { toolCallId: "call-twin", toolName: "skill",
                               arguments: JSON.stringify({ skill: "roberdan-twin" }) }],
    ["tool.execution_complete", { toolCallId: "call-twin", success: true }],
    ["tool.execution_start", { toolCallId: "call-other", toolName: "skill",
                               arguments: JSON.stringify({ skill: "pdf" }) }],
    ["tool.execution_complete", { toolCallId: "call-other", success: true }],
    ["subagent.started", { agentName: "twin", model: "opus" }, { agentId: "agent-1" }],
    ["subagent.completed", { cancelled: true }, { agentId: "agent-1" }],
    ["session.shutdown", {}],
];
for (const [type, data, extra = {}] of timeline) {
    observer.observe({ type, data, ...extra });
    if (!await observer.flush()) throw Error(`lost ${type}`);
}
if (!await observer.stop()) throw Error("observer end not recorded");
JS

# --- 2. osservazione nativa Claude attraverso il vero hook di comando -----------------------
claude_event() { printf '%s' "$1" | bash "$ROOT/hooks/audit.sh" 2>/dev/null; }
claude_event '{"hook_event_name":"SessionStart","session_id":"chain-claude","model":"sonnet"}'
claude_event '{"hook_event_name":"PreToolUse","session_id":"chain-claude","tool_use_id":"cc-1","tool_name":"Skill","tool_input":{"skill":"roberdan-twin"}}'
claude_event '{"hook_event_name":"PostToolUse","session_id":"chain-claude","tool_use_id":"cc-1","tool_name":"Skill"}'
claude_event '{"hook_event_name":"SubagentStart","session_id":"chain-claude","agent_id":"cc-agent","agent_type":"twin"}'
claude_event '{"hook_event_name":"SubagentStop","session_id":"chain-claude","agent_id":"cc-agent"}'
claude_event '{"hook_event_name":"SessionEnd","session_id":"chain-claude"}'

# --- 3. catena semantica: richiesta, decisione, consulto, raccomandazione, esito ------------
record() { audit record "$1" --json "$2" >/dev/null; }
record request '{"id":"req-1","summary":"Which observer contract do we ship"}'
record decision '{"id":"dec-1","request_id":"req-1","summary":"Ship native names or adapt the registry"}'
record bind '{"decision_id":"dec-1","host":"copilot","session_id":"chain-copilot","tool_call_id":"call-twin"}'
record consultation_requested '{"id":"con-0","decision_id":"dec-1","summary":"Ask the twin"}'
record consultation_completed '{"id":"con-1","decision_id":"dec-1","consultation_id":"con-0"}'
record recommendation '{"id":"rec-1","decision_id":"dec-1","consultation_id":"con-1","option_id":"adapt","summary":"Adapt the registry to the hosts","evidence":["test:test-audit-chain"]}'
record human_response '{"decision_id":"dec-1","recommendation_id":"rec-1","response":"yes"}'
record execution_started '{"id":"exe-1","decision_id":"dec-1","recommendation_id":"rec-1"}'
record execution_completed '{"id":"exe-2","decision_id":"dec-1","execution_id":"exe-1"}'
record outcome '{"decision_id":"dec-1","execution_id":"exe-2","summary":"Chain observed end to end","evidence":["test:test-audit-chain"]}'

# --- 4. rilettura: quello che il registro sa davvero ----------------------------------------
python3 - <<'PY' || FAIL=1
import json
import os
import subprocess
import sys

root = os.environ["RDA_OS"]


def run(*args):
    result = subprocess.run([sys.executable, root + "/kanban/audit.py", *args],
                            capture_output=True, text=True, timeout=20)
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def ok(condition, message):
    print(("  ok: " if condition else "  FAIL: ") + message)
    return condition


passed = True
stats, cover = run("stats", "--json"), run("coverage", "--json")
kinds = stats["by_kind"]
passed &= ok(cover["unsupported_events"] == [], "nessun evento nativo resta non classificato")
passed &= ok(cover["observer_gaps"] == [], "nessun buco di osservazione dichiarato")
passed &= ok(len(cover["observer_limitations"]) == 6,
             "i limiti dichiarati dagli observer sono registrati, non dedotti")
passed &= ok(cover["unlinked_native_events"] == [], "ogni evento nativo di chiamata e' correlato")
passed &= ok(kinds.get("skill_invocation_succeeded") == 2,
             "la skill del twin e' riuscita su Copilot e su Claude")
passed &= ok("skill_invocation_started" in kinds and kinds["skill_invocation_started"] == 2
         and kinds.get("execution_started") == 2,
             "una skill qualsiasi resta esecuzione ordinaria, non consultazione del twin")
by_agent = {item["agent_id"]: item["status"] for item in stats["attempts"] if item["agent_id"]}
passed &= ok(by_agent.get("agent-1") == "failed",
             "un subagent annullato non diventa un successo")
passed &= ok(by_agent.get("cc-agent") == "terminal_status_unknown",
             "SubagentStop non porta esito: resta sconosciuto, non riuscito")
passed &= ok(stats["unanswered_recommendations"] == [] and stats["decisions_without_outcome"] == [],
             "la catena decisione -> raccomandazione -> esito e' chiusa")
passed &= ok(stats["verified_human_responses"] == 0 and stats["agreement_rate"] is None
             and cover["permission_authority"] is False,
             "un si' registrato non diventa consenso verificato ne' autorizzazione")
bound = [item for item in stats["attempts"] if item["tool_call_id"] == "call-twin"]
passed &= ok(len(bound) == 1 and bound[0]["decision_id"] == "dec-1",
             "la chiamata nativa e' legata alla decisione dal bind, non da un'euristica")
sys.exit(0 if passed else 1)
PY

[ "$FAIL" -eq 0 ] && echo "test-audit-chain: PASS (osservazione nativa reale, registro reale, catena chiusa)"
exit "$FAIL"
