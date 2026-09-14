# shellcheck shell=bash
# Sourced by test-copilot-adapter.sh: real queue gate, fake host transport only.
section "continuation - native stop return, real queue brakes, honest idle fallback"
CONT_OS="$TMP/continuity-os"; CONT_REPO="$TMP/continuity-repo"
mkdir -p "$CONT_OS/hooks" "$CONT_OS/behavior" "$CONT_REPO/kanban/todo" "$CONT_REPO/kanban/done"
git -C "$CONT_REPO" init -q
cp "$ROOT/kanban/kb.sh" "$CONT_REPO/kanban/"
cp "$ROOT/behavior/roberto-mode.md" "$CONT_OS/behavior/"
cat > "$CONT_OS/hooks/goal-gate.sh" <<'SH'
#!/usr/bin/env bash
payload="$(cat)"
printf '%s\n' "$payload" >> "$RDA_TEST_GATE_CALLS"
printf '%s\n' "$payload" | bash "$RDA_TEST_REAL_GATE"
SH
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$PWD" >> "$RDA_TEST_SAVES"\n' > "$CONT_OS/hooks/auto-checkpoint.sh"
cat > "$STAGE/driver-continuity.mjs" <<'JS'
import assert from "node:assert/strict";
import { writeFileSync, readFileSync, mkdirSync, renameSync, rmSync, existsSync } from "node:fs";
import { join } from "node:path";
const repo = process.env.RDA_TEST_CONT_REPO;
const os = process.env.RDA_OS;
const board = join(repo, "kanban");
const queue = join(board, ".coda-continuity-repo.md");
const gate = join(os, "hooks/goal-gate.sh");
const calls = () => existsSync(process.env.RDA_TEST_GATE_CALLS)
    ? readFileSync(process.env.RDA_TEST_GATE_CALLS, "utf8").trim().split("\n").length : 0;
const card = (id) => writeFileSync(join(board, "todo", `${id}.md`),
    "---\ntitle: continuity\nrepo: continuity-repo\nstatus: todo\ndod: output\nacceptance: observed output\n---\n");
const makeQueue = (...ids) => { ids.forEach(card); writeFileSync(queue, "# authorized\n" + ids.join("\n") + "\n"); };
let serial = 0;
async function load() {
    globalThis.__LOG = [];
    await import(`./extension.mjs?continuity=${++serial}`);
    return globalThis.__RDA_CFG.hooks;
}
const logs = () => globalThis.__LOG.join("\n");
makeQueue("C1", "C2");
let hooks = await load();
const stop = () => hooks.onAgentStop({workingDirectory:repo, stopReason:"end_turn", stopHookActive:true});
let r = await stop();
assert.equal(r.decision, "block", "unfinished authorized queue must request native continuation");
assert.match(r.reason, /live CLI runtime only/);
assert.match(r.reason, /kb next/);
assert.match(readFileSync(process.env.RDA_TEST_GATE_CALLS,"utf8"), /rda-test-session/);
assert.ok(readFileSync(process.env.RDA_TEST_SAVES,"utf8").includes(repo), "save before continuation");
await globalThis.__H["session.idle"]();
assert.equal(calls(), 1, "idle must not consume a second queue retry");
for (const prompt of ["stop", "pausa!", "fermati", "metti in pausa", "devo andare", "vado"]) {
    await hooks.onUserPromptSubmitted({workingDirectory:repo, prompt, sessionId:"rda-test-session"});
    assert.equal(await stop(), undefined, "an explicit user pause cannot be restarted");
    assert.equal(calls(), 1, "pause must not spend queue counters");
}
await hooks.onUserPromptSubmitted({workingDirectory:repo, prompt:"continua", sessionId:"rda-test-session"});
await hooks.onUserPromptSubmitted({workingDirectory:repo, prompt:"stop", sessionId:"child"});
assert.equal(await hooks.onAgentStop({workingDirectory:repo, sessionId:"child"}), undefined);
assert.equal(calls(), 1, "child stops cannot consume the root queue");
assert.equal((await stop()).decision, "block");
assert.equal(await stop(), undefined, "two no-progress comparisons release");
assert.match(logs(), /non si accorcia/);
for (const id of ["C1", "C2"]) renameSync(join(board,"todo",id+".md"), join(board,"done",id+".md"));
assert.equal(await stop(), undefined, "finished queue releases");
rmSync(queue);
card("NEW");
assert.equal(await stop(), undefined, "unapproved work cannot trigger continuation");

makeQueue("P1","P2","P3");
process.env.RDA_GOAL_GATE_STATE = join(os, "budget-state");
process.env.RDA_GOAL_GATE_MAX = "1";
assert.equal((await stop()).decision, "block");
renameSync(join(board,"todo/P1.md"),join(board,"done/P1.md"));
assert.equal(await stop(), undefined, "budget releases even with progress");
assert.match(logs(), /tetto/);
delete process.env.RDA_GOAL_GATE_MAX;
process.env.RDA_GOAL_GATE_STATE = join(os, "switch-state");
process.env.RDA_NO_GOAL_GATE = "1";
assert.equal(await stop(), undefined, "explicit stop switch releases");
delete process.env.RDA_NO_GOAL_GATE;
mkdirSync(process.env.RDA_HOME,{recursive:true});
writeFileSync(join(process.env.RDA_HOME,"goal-gate.off"),"");
assert.equal(await stop(), undefined, "file stop switch releases");
rmSync(join(process.env.RDA_HOME,"goal-gate.off"));

// Reload simulates a host that never invokes the registered stop callback.
hooks = await load();
await hooks.onUserPromptSubmitted({workingDirectory:repo});
const beforeChild = calls();
await globalThis.__H["session.idle"]({agentId:"child"});
assert.equal(calls(), beforeChild, "child idle cannot advance parent queue counters");
await globalThis.__H["session.idle"]();
assert.match(logs(), /Continuation NOT enforced/);
assert.match(logs(), /checkpoint is not an executor/);
for (const code of [3, 2]) {
    writeFileSync(gate, `#!/usr/bin/env bash\nexit ${code}\n`);
    assert.equal(await stop(), undefined, "failed or empty blocking result never fabricates restart");
    assert.match(logs(), /could not be evaluated/);
}
rmSync(gate);
assert.equal(await stop(), undefined);
assert.match(logs(), /unfinished work is NOT protected/);
console.log("PASS: native continuation, checkpoint, identity, idle dedup, stall, budget, switches, no queue, failures, old host");
JS
if (cd "$STAGE" && RDA_OS="$CONT_OS" RDA_HOME="$TMP/continuity-home" \
    RDA_GOAL_GATE_STATE="$TMP/continuity-state" RDA_TEST_CONT_REPO="$CONT_REPO" \
    RDA_TEST_REAL_GATE="$ROOT/hooks/goal-gate.sh" \
    RDA_TEST_GATE_CALLS="$TMP/continuity-calls" RDA_TEST_SAVES="$TMP/continuity-saves" \
    node driver-continuity.mjs >"$TMP/continuity-result" 2>"$TMP/continuity-stderr"); then
  ok "native stop mapping and real queue terminal conditions; no model calls or schedules"
else
  err "continuation regression"
  cat "$TMP/continuity-result" "$TMP/continuity-stderr"
fi
for marker in 'unfinished, no active' 'Registration or markdown is not proof.' 'two no-progress'; do
  grep -qF "$marker" "$ROOT/AGENTS.md" || err "missing canonical continuation contract: $marker"
done

# G2) onSessionStart must hand context-inject the session id AND the source, or the authorized
# queue is never re-photographed on Copilot (2026-09-14: the photo froze at 2026-07-30).
printf '#!/usr/bin/env bash\nprintf "%%s|%%s\\n" "context-inject.sh" "$(cat)" >> "%s"\nexit 0\n' "$SID_OUT" > "$SID_OS/hooks/context-inject.sh"
chmod +x "$SID_OS/hooks/context-inject.sh"
cat > "$STAGE/driver-start.mjs" <<JS
import "./extension.mjs";
const cfg = globalThis.__RDA_CFG;
await cfg.hooks.onSessionStart({ sessionId: "cp-start-1", source: "new", workingDirectory: process.cwd() });
await cfg.hooks.onSessionStart({ sessionId: "cp-start-1", source: "resume", workingDirectory: process.cwd() });
console.log("DONE");
JS
( cd "$STAGE" && RDA_OS="$SID_OS" node driver-start.mjs >/dev/null 2>&1 )
grep -q '^context-inject.sh|.*"session_id":"cp-start-1".*"source":"new"' "$SID_OUT" \
  && grep -q '^context-inject.sh|.*"session_id":"cp-start-1".*"source":"resume"' "$SID_OUT" \
  && ok "onSessionStart passes session_id + source to context-inject (queue renews on a new Copilot session only)" \
  || err "onSessionStart does not pass session_id/source: Copilot never renews the authorized queue"
