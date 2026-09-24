import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { classify, enforceSkillObligations, RETRIES } from "../hooks/copilot/skill-obligations-core.mjs";
import { withSkillObligations } from "../hooks/copilot/skill-obligations.mjs";

const video = "Prepara soltanto un concept scritto di tre frasi per un trailer video di 15 secondi di un'app fittizia. Non produrre file, immagini o video e non chiamare servizi esterni.";
const apple = "Descrivi in tre frasi una schermata iPhone accessibile per un timer fittizio.";
const secret = "PRIVATE_SENTINEL_do_not_persist";
test("emitted mandatory skills contain the complete guidance, not just a pointer", {
    skip: !process.env.RDA_TEST_SKILL_EMISSION,
}, () => {
    for (const name of ["film-director", "apple-designer"]) {
        const canonical = readFileSync(new URL(`../skills/${name}/skill.md`, import.meta.url), "utf8")
            .replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n/, "");
        const emitted = readFileSync(join(process.env.RDA_TEST_SKILL_EMISSION,
            "claude/skills", name, "SKILL.md"), "utf8");
        assert.ok(emitted.includes(canonical), `${name}: native loading must deliver ALL canonical guidance`);
    }
});

function fixture(t) {
    const base = mkdtempSync(join(tmpdir(), "rda-skill-obligation-"));
    t.after(() => rmSync(base, { recursive: true }));
    const root = join(base, "public"), home = join(base, "state");
    for (const name of ["film-director", "apple-designer"]) {
        mkdirSync(join(root, "skills", name), { recursive: true });
        writeFileSync(join(root, "skills", name, "skill.md"), "public guidance\nsecond line\n");
    }
    return { root, home, call: (event, fields = {}) => enforceSkillObligations({
        host: "copilot", sessionId: "session-1", event, ...fields,
    }, { root, home }) };
}

test("actual text-only video and Apple UI requests create obligations, ordinary/backend/negated requests do not", () => {
    for (const prompt of [video, "Write a storyboard for a product film.", "Review this demo video."]) {
        assert.deepEqual(classify(prompt), ["film-director"]);
    }
    assert.deepEqual(classify(apple), ["apple-designer"]);
    assert.deepEqual(classify("Design an iPad UI and create a trailer video."), ["film-director", "apple-designer"]);
    for (const prompt of ["Quanto fa 17 per 19?", "Do not create a video.", "Non creare un video.",
        "Design a video-upload API backend.", "Build an iOS background sync app.",
        "Report: review completata del test video; nessun lavoro creativo richiesto.",
        "Review the test-audit-chain regression for film-director.",
        "<task-notification>Write a storyboard for a product film.</task-notification>",
        "<system_notification>Review this demo video.</system_notification>",
        "Spiega cosa significa film-director.", "stop", "annulla"]) assert.deepEqual(classify(prompt), [], prompt);
});

test("native notifications do not create or clear a user's pending obligation", async (t) => {
    const f = fixture(t), prompt = "<task-notification>Write a trailer video.</task-notification>";
    await f.call("prompt", { prompt });
    assert.equal((await f.call("pre", { toolName: "bash" })).deny, undefined);
    await f.call("prompt", { prompt: video });
    await f.call("prompt", { prompt: "<system_notification>Agent finished.</system_notification>" });
    assert.match((await f.call("pre", { toolName: "bash" })).deny, /film-director/);
});

test("native success alone fulfills the exact route; failure/discovery/wrong names never do", async (t) => {
    const f = fixture(t);
    assert.equal((await f.call("prompt", { prompt: video })).status, "required");
    for (const fields of [{ toolName: "skill", args: { skill: "film-director" }, success: false },
        { toolName: "skill", args: { skill: "unknown-film-director" }, success: true },
        { toolName: "session.skills_loaded", args: { skill: "film-director" }, success: true }]) {
        assert.equal((await f.call("post", fields)).status, "required");
    }
    const success = await f.call("post", { toolName: "skill", args: { skill: "rdos-film-director", prompt: secret }, success: true });
    assert.deepEqual(success.receipts, { "film-director": "native_skill" });
    assert.equal(success.status, "fulfilled");
    assert.equal((await f.call("stop")).block, undefined);
});

test("full canonical fallback has distinct provenance; partial or unrelated reads cannot fulfill", async (t) => {
    const f = fixture(t);
    await f.call("prompt", { prompt: apple });
    const path = join(f.root, "skills/apple-designer/skill.md");
    for (const args of [{ path, view_range: [2, -1] }, { path, view_range: [1, 1] }, { path: "/PRIVATE/path" }]) {
        assert.equal((await f.call("post", { toolName: "view", args, success: true })).status, "required");
    }
    const result = await f.call("post", { toolName: "view", args: { path, view_range: [1, -1] }, success: true });
    assert.deepEqual(result.receipts, { "apple-designer": "canonical_read" });
    assert.equal((await f.call("stop")).block, undefined);
});

test("bounded stops survive native feedback without reset; exhausted guard is visibly incomplete", async (t) => {
    const f = fixture(t);
    await f.call("prompt", { prompt: video });
    for (let i = 0; i < RETRIES; i++) {
        const output = await f.call("stop");
        assert.match(output.block, /film-director/);
        await f.call("prompt", { prompt: output.block });
    }
    const exhausted = await f.call("stop");
    assert.equal(exhausted.block, undefined);
    assert.equal(exhausted.status, "incomplete");
    assert.match(exhausted.warning, /INCOMPLETE/);
    assert.equal((await f.call("stop")).block, undefined);
});

test("a host end callback between native continuation turns cannot erase an unmet obligation", async (t) => {
    const f = fixture(t);
    await f.call("prompt", { prompt: video });
    const first = await f.call("stop");
    await f.call("end");
    await f.call("prompt", { prompt: first.block });
    const second = await f.call("stop");
    assert.equal(second.blocks, 2);
    assert.match(second.block, /film-director/);
});

test("pause/cancel and new unrelated user requests release obligations; fresh requests rearm", async (t) => {
    const f = fixture(t);
    for (const prompt of ["stop", "cancel", "pausa", "Quanto fa 17 per 19?"]) {
        await f.call("prompt", { prompt: video });
        await f.call("prompt", { prompt });
        assert.equal((await f.call("stop")).block, undefined);
    }
    await f.call("prompt", { prompt: apple });
    assert.match((await f.call("pre", { toolName: "edit" })).deny, /apple-designer/);
    for (const toolName of ["skill", "view", "read", "glob", "rg"]) {
        assert.equal((await f.call("pre", { toolName })).deny, undefined);
    }
});

test("state is isolated, bounded and contains no raw prompt, tool args, path or content", async (t) => {
    const f = fixture(t);
    await f.call("prompt", { prompt: video + secret });
    await f.call("post", { toolName: "skill", args: { skill: secret, nested: { token: secret } }, success: true });
    assert.equal((await f.call("stop", { sessionId: "other" })).block, undefined);
    assert.equal((await f.call("stop", { host: "claude" })).block, undefined);
    for (const file of readdirSync(join(f.home, "skill-obligations"))) {
        const data = readFileSync(join(f.home, "skill-obligations", file), "utf8");
        assert.doesNotMatch(data, /PRIVATE|session-1|prompt|token/);
        assert.ok(data.length < 2048);
    }
});

test("concurrent successful required loads preserve both receipts", async (t) => {
    const f = fixture(t);
    await f.call("prompt", { prompt: video + " " + apple });
    await Promise.all(["film-director", "apple-designer"].map((skill) =>
        f.call("post", { toolName: "skill", args: { skill }, success: true })));
    assert.equal((await f.call("stop")).status, "fulfilled");
});

test("corrupt state is explicit failure, never a satisfied obligation", async (t) => {
    const f = fixture(t);
    await f.call("prompt", { prompt: video });
    const directory = join(f.home, "skill-obligations");
    const file = join(directory, readdirSync(directory).find((name) => name.endsWith(".json")));
    writeFileSync(file, JSON.stringify({ required: [secret] }));
    await assert.rejects(f.call("stop"), /invalid_obligation_state/);
});

test("generated Claude registration preserves existing guards and adds every required native surface", (t) => {
    const f = fixture(t);
    const file = join(f.home, "settings.json");
    mkdirSync(f.home, { recursive: true });
    const guard = { matcher: "Bash", hooks: [{ type: "command", command: "existing-guard" }] };
    writeFileSync(file, JSON.stringify({ hooks: { PreToolUse: [guard] } }));
    const result = spawnSync(process.execPath,
        [new URL("../hooks/skill-obligations-config.mjs", import.meta.url).pathname, file], { encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr);
    const hooks = JSON.parse(readFileSync(file)).hooks;
    assert.deepEqual(hooks.PreToolUse[0], guard);
    for (const name of ["UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "SessionEnd"]) {
        assert.equal(hooks[name].at(-1).hooks[0].command, "node $RDA_OS/hooks/skill-obligations-claude.mjs");
    }
});

test("real Claude callback adapter emits native block and success-only fallback receipt without leaking content", (t) => {
    const f = fixture(t);
    const invoke = (event) => {
        const result = spawnSync(process.execPath, [new URL("../hooks/skill-obligations-claude.mjs", import.meta.url).pathname], {
            input: JSON.stringify({ session_id: "claude-1", ...event }), encoding: "utf8",
            env: { ...process.env, RDA_OS: f.root, RDA_HOME: f.home },
        });
        assert.equal(result.status, 0, result.stderr);
        assert.doesNotMatch(result.stdout + result.stderr, /PRIVATE/);
        return result.stdout ? JSON.parse(result.stdout) : {};
    };
    const context = invoke({ hook_event_name: "UserPromptSubmit", prompt: video + secret });
    assert.match(context.hookSpecificOutput.additionalContext, /film-director/);
    assert.equal(invoke({ hook_event_name: "Stop", stop_hook_active: false }).decision, "block");
    invoke({ hook_event_name: "PostToolUse", agent_id: "child-1", tool_name: "Skill",
        tool_input: { skill: "film-director" } });
    assert.equal(invoke({ hook_event_name: "Stop", stop_hook_active: true }).decision, "block");
    invoke({ hook_event_name: "PostToolUse", tool_name: "Read",
        tool_input: { file_path: join(f.root, "skills/film-director/skill.md") },
        tool_response: { content: secret } });
    assert.deepEqual(invoke({ hook_event_name: "Stop", stop_hook_active: true }), {});
});

test("unrelated freeform tool results do not break ordinary native observation", async (t) => {
    const f = fixture(t), notices = [];
    let observed = 0;
    const hooks = withSkillObligations({
        onPostToolUse: () => { observed++; },
    }, { ...f, sessionId: () => "session-1", notify: async (text) => notices.push(text) });
    await hooks.onUserPromptSubmitted({ prompt: "Quanto fa 17 per 19?" });
    await hooks.onPostToolUse({ toolName: "apply_patch", toolArgs: "*** Begin Patch\n*** End Patch",
        toolResult: { resultType: "success" } });
    assert.deepEqual(notices, []);
    assert.equal(observed, 1, "ordinary tools must retain their existing callbacks");
    await hooks.onUserPromptSubmitted({ prompt: video });
    await hooks.onPostToolUse({ toolName: "apply_patch", toolArgs: "*** Begin Patch\n*** End Patch",
        toolResult: { resultType: "success" } });
    assert.deepEqual(notices, []);
    assert.equal(observed, 2);
    assert.equal((await hooks.onAgentStop({})).decision, "block",
        "an unrelated success cannot fulfill required guidance");
});

test("native continuation keeps inherited observers alive until its terminal end", async (t) => {
    const f = fixture(t);
    let ended = 0;
    const hooks = withSkillObligations({
        onSessionEnd: () => { ended++; },
    }, { ...f, sessionId: () => "session-1", notify: async () => {} });
    await hooks.onUserPromptSubmitted({ prompt: video });
    assert.equal((await hooks.onAgentStop({})).decision, "block");
    await hooks.onSessionEnd({});
    assert.equal(ended, 0, "a continuation must not stop inherited audit/bus observers");
    await hooks.onPostToolUse({ toolName: "skill", toolArgs: { skill: "film-director" },
        toolResult: { resultType: "success" } });
    await hooks.onAgentStop({});
    await hooks.onSessionEnd({});
    assert.equal(ended, 1);
    await hooks.onUserPromptSubmitted({ prompt: video });
    for (let i = 0; i < RETRIES; i++) {
        assert.equal((await hooks.onAgentStop({})).decision, "block");
        await hooks.onSessionEnd({});
        assert.equal(ended, 1);
    }
    await hooks.onAgentStop({});
    await hooks.onSessionEnd({});
    assert.equal(ended, 2, "exhausted retries still deliver terminal cleanup");
    await hooks.onUserPromptSubmitted({ prompt: video });
    await hooks.onAgentStop({});
    await hooks.onUserPromptSubmitted({ prompt: "stop" });
    await hooks.onSessionEnd({});
    assert.equal(ended, 3, "user pause still delivers cleanup");
});

test("native Copilot composition enforces a skipped load, retains guards, and never starts its own model turn", async (t) => {
    const f = fixture(t), notices = [];
    let queueCalls = 0;
    const hooks = withSkillObligations({
        onUserPromptSubmitted: () => ({ additionalContext: "existing format" }),
        onPreToolUse: () => ({ permissionDecision: "ask", permissionDecisionReason: "existing guard" }),
        onAgentStop: () => { queueCalls++; },
    }, { ...f, sessionId: () => "session-1", notify: async (text) => notices.push(text) });
    const context = await hooks.onUserPromptSubmitted({ prompt: video, sessionId: "session-1" });
    assert.match(context.additionalContext, /existing format[\s\S]*film-director/);
    assert.equal((await hooks.onPreToolUse({ toolName: "read" })).permissionDecision, "ask");
    assert.equal((await hooks.onPreToolUse({ toolName: "edit" })).permissionDecision, "deny");
    await hooks.onPostToolUse({ sessionId: "child", toolName: "skill",
        toolArgs: { skill: "film-director" }, toolResult: { resultType: "success" } });
    for (let i = 0; i < RETRIES; i++) {
        const stop = await hooks.onAgentStop({ sessionId: "session-1" });
        assert.equal(stop.decision, "block", "negative control: without wrapper a skipped load stops cleanly");
        await hooks.onUserPromptSubmitted({ sessionId: "session-1", prompt: stop.reason });
    }
    assert.equal(await hooks.onAgentStop({}), undefined);
    assert.match(notices[0], /INCOMPLETE/);
    assert.equal(queueCalls, 0, "independent queue must not reset or multiply the skill retry budget");
    await hooks.onUserPromptSubmitted({ prompt: "Quanto fa 17 per 19?" });
    await hooks.onAgentStop({});
    assert.equal(queueCalls, 1);
    await hooks.onUserPromptSubmitted({ prompt: video });
    await hooks.onPostToolUse({ toolName: "skill", toolArgs: JSON.stringify({ skill: "film-director" }),
        toolResult: { resultType: "success", textResultForLlm: secret } });
    await hooks.onAgentStop({});
    assert.equal(queueCalls, 2);
    assert.doesNotMatch(JSON.stringify(notices), /PRIVATE/);
});
