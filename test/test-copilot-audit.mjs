import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync, copyFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { AUDIT_EVENTS, AUDIT_LIMITS, createAuditObserver, normalizeAuditEvent } from "../hooks/copilot/audit.mjs";

let serial = 0;
const native = (type, data, extra = {}) => ({
    type, data, id: `event-${++serial}`, timestamp: "2026-09-17T09:00:00.000Z", ...extra,
});
const start = (id, skill = "roberdan-twin") => native("tool.execution_start", {
    toolCallId: id, toolName: "skill", arguments: { skill, prompt: "PRIVATE_PROMPT_CANARY" },
});
function fixture(runScript) {
    const writes = [], warnings = [], handlers = new Map();
    const observer = createAuditObserver({
        root: "/fixture", sessionId: "session-1", report: (code) => warnings.push(code),
        runScript: runScript || (async (path, input) => { writes.push(JSON.parse(input)); return { code: 0 }; }),
    });
    observer.register({ on: (name, handler) => {
        handlers.set(name, handler);
        return () => handlers.delete(name);
    } });
    return { observer, writes, warnings, handlers };
}

test("projects native identifiers, not prompts, results, hidden reasoning or raw shell arguments", () => {
    const event = start("call-1");
    event.data.model = "test-model";
    event.agentId = "child-1";
    event.data.parentToolCallId = "parent-1";
    event.data.reasoning = "PRIVATE_REASONING_CANARY";
    const safe = normalizeAuditEvent(event, "session-1");
    assert.deepEqual(safe.data, { agentId: "child-1", model: "test-model",
        toolCallId: "call-1", parentToolCallId: "parent-1", toolName: "skill",
        arguments: { skill: "roberdan-twin" } });
    const shell = normalizeAuditEvent(native("tool.execution_start", {
        toolCallId: "shell-1", toolName: "bash",
        arguments: { command: "PRIVATE_SHELL_CANARY", name: "PRIVATE_NAME_CANARY" },
    }), "session-1");
    assert.equal(shell.data.arguments, undefined);
    const complete = normalizeAuditEvent(native("tool.execution_complete", {
        toolCallId: "call-1", success: false,
        error: { code: "not_found", message: "PRIVATE_ERROR_CANARY" },
        result: { content: "PRIVATE_RESULT_CANARY" }, requestId: "unverified-request",
    }), "session-1");
    assert.deepEqual(complete.data, { toolCallId: "call-1", success: false, error: { code: "not_found" } });
    assert.doesNotMatch(JSON.stringify([safe, shell, complete]), /PRIVATE|requestId/);
});

test("discovery snapshots never turn a failed skill attempt into success", async () => {
    const { observer, writes, handlers } = fixture();
    assert.deepEqual([...handlers.keys()], AUDIT_EVENTS);
    for (const names of [["roberdan-twin"], []]) observer.observe(native("session.skills_loaded", {
        skills: names.map((name) => ({ name, content: "PRIVATE_SKILL_CANARY" })),
    }));
    observer.observe(start("attempt-1"));
    observer.observe(native("tool.execution_complete", {
        toolCallId: "attempt-1", success: false, error: { code: "not_found", message: "PRIVATE_ERROR_CANARY" },
    }));
    observer.observe(native("session.skills_loaded", { skills: [{ name: "roberdan-twin" }] }));
    observer.observe(start("attempt-2"));
    observer.observe(native("tool.execution_complete", { toolCallId: "attempt-2", success: true }));
    observer.observe(start("missing-terminal"));
    assert.equal(await observer.stop(), true);
    const terminals = writes.filter((event) => event.type === "tool.execution_complete");
    assert.deepEqual(terminals.map((event) => [event.data.toolCallId, event.data.success]),
        [["attempt-1", false], ["attempt-2", true]]);
    assert.equal(writes.filter((event) => event.type === "session.skills_loaded").length, 3);
    assert.equal(writes.at(-1).type, "observer.end");
    assert.doesNotMatch(JSON.stringify(writes), /PRIVATE|consultation_completed/);
    assert.ok(writes.every((event) => !/decision|recommendation|human_response/.test(event.type)));
    assert.equal(handlers.size, 0);
});

test("only twin skill aliases and explicit task selectors are projected; child correlation is native", () => {
    for (const name of ["roberdan-twin", "roberto-twin"]) {
        assert.deepEqual(normalizeAuditEvent(start("call", name), "session").data.arguments, { skill: name });
    }
    assert.equal(normalizeAuditEvent(start("call", "other-skill"), "session").data.arguments, undefined);
    const task = normalizeAuditEvent(native("tool.execution_start", {
        toolCallId: "task-1", toolName: "task", arguments: { agent_type: "twin", name: "twin", prompt: "PRIVATE" },
    }), "session");
    assert.deepEqual(task.data.arguments, { agent_type: "twin", name: "twin" });
    const child = normalizeAuditEvent(native("subagent.started", {
        agentName: "twin", model: "test-model", agentDescription: "PRIVATE",
    }, { agentId: "child-1", parentId: "chronological-not-parent-tool" }), "session");
    assert.equal(child.data.agentId, "child-1");
    assert.equal(child.data.model, "test-model");
    assert.equal(child.data.agentName, "twin");
    assert.equal(child.data.toolCallId, undefined);
    assert.equal(child.data.parentToolCallId, undefined);
    const cancel = normalizeAuditEvent(native("subagent.completed", {
        agentName: "twin", cancelled: true,
    }), "session");
    assert.equal(cancel.data.success, false);
    assert.equal(cancel.data.error.code, "cancelled");
});

test("malformed and oversized metadata produce a gap, with no private canary in writes or diagnostics", async () => {
    const { observer, writes, warnings } = fixture();
    await observer.flush();
    const malformed = [
        { type: "user.message", data: { content: "PRIVATE_CANARY" } },
        native("tool.execution_start", { toolName: "skill", arguments: { skill: "roberdan-twin" } }),
        native("tool.execution_start", { toolCallId: "call", toolName: "skill", arguments: "PRIVATE_CANARY".repeat(2000) }),
        native("tool.execution_start", { toolCallId: "call", toolName: "task", arguments: { name: "PRIVATE CANARY" } }),
        native("tool.execution_complete", { toolCallId: "call", error: "PRIVATE_CANARY" }),
        native("session.skills_loaded", { skills: Array(257).fill({ name: "roberdan-twin" }) }),
        native("session.shutdown", {}, { id: "PRIVATE CANARY" }),
    ];
    for (const event of malformed) observer.observe(event);
    observer.observe(start("valid"));
    await observer.stop();
    assert.ok(writes.some((event) => event.type === "observer.gap"));
    assert.ok(warnings.length);
    assert.doesNotMatch(JSON.stringify([writes, warnings]), /PRIVATE_CANARY|PRIVATE CANARY/);
    assert.equal(writes.filter((event) => event.type === "tool.execution_start").length, 1);
    assert.throws(() => normalizeAuditEvent(start("call"), "../invalid session"), /invalid_session_id/);
});

test("queue is bounded including the active write, serialized, and next success records loss", async () => {
    let release, active = 0, maximum = 0;
    const writes = [];
    const { observer, warnings } = fixture(async (path, input) => {
        maximum = Math.max(maximum, ++active);
        if (!release) await new Promise((resolve) => { release = resolve; });
        writes.push(JSON.parse(input));
        active--;
        return { code: 0 };
    });
    for (let index = 0; index < 1000; index++) observer.observe(start(`call-${index}`));
    assert.equal(observer.status().pending, AUDIT_LIMITS.pending);
    assert.equal(observer.status().gap, true);
    assert.equal(warnings.filter((code) => code === "queue_full").length, 1);
    release();
    assert.equal(await observer.stop(), true);
    assert.equal(maximum, 1);
    assert.ok(writes.some((event) => event.type === "observer.gap"));
    assert.ok(writes.length <= AUDIT_LIMITS.pending + 2);
});

test("ingest rejection is sanitized and the next successful write is a coverage gap", async () => {
    let fail = true;
    const writes = [];
    const { observer, warnings } = fixture(async (path, input) => {
        if (fail) { fail = false; throw Error("PRIVATE_LOGGER_CANARY"); }
        writes.push(JSON.parse(input));
        return { code: 0 };
    });
    await observer.flush();
    observer.observe(start("after-error"));
    await observer.stop();
    assert.equal(writes[0].type, "observer.gap");
    assert.ok(warnings.includes("ingest_failed"));
    assert.doesNotMatch(JSON.stringify([writes, warnings]), /PRIVATE/);
});

test("shutdown is bounded even if an injected writer ignores cancellation", async () => {
    let calls = 0;
    const { observer, warnings } = fixture(async (path, input) => {
        if (JSON.parse(input).type.startsWith("observer.")) return { code: 0 };
        calls++;
        await new Promise(() => {});
    });
    await observer.flush();
    observer.observe(start("waiting"));
    const before = Date.now();
    assert.equal(await observer.stop(), false);
    assert.ok(Date.now() - before < AUDIT_LIMITS.flushMs + 500);
    assert.equal(calls, 1);
    assert.equal(observer.status().closed, true);
    assert.ok(warnings.includes("flush_timeout"));
});

test("real subprocess ingest uses stdin, discards logger output, and kills a stuck writer", async () => {
    const root = mkdtempSync(join(tmpdir(), "rda-audit-node-"));
    try {
        mkdirSync(join(root, "kanban"));
        const captured = join(root, "captured.json");
        writeFileSync(join(root, "kanban", "audit.py"),
            `import sys, pathlib\npathlib.Path(${JSON.stringify(captured)}).write_text(sys.stdin.read())\n`);
        const warnings = [];
        const observer = createAuditObserver({ root, sessionId: "real-session", report: (code) => warnings.push(code) });
        observer.observe(start("real-call"));
        assert.equal(await observer.flush(), true);
        assert.equal(JSON.parse(readFileSync(captured, "utf8")).data.toolCallId, "real-call");
        writeFileSync(join(root, "kanban", "audit.py"), "import time\nprint('PRIVATE_CANARY', flush=True)\ntime.sleep(30)\n");
        observer.observe(start("stuck"));
        const before = Date.now();
        assert.equal(await observer.flush(), false);
        assert.ok(Date.now() - before < AUDIT_LIMITS.flushMs + 500);
        assert.ok(warnings.includes("ingest_timeout"));
        assert.doesNotMatch(JSON.stringify(warnings), /PRIVATE/);
        assert.equal(await observer.stop(), false);
    } finally {
        rmSync(root, { recursive: true });
    }
});

test("extension observes native events independently of unchanged guard permission outputs", () => {
    const root = mkdtempSync(join(tmpdir(), "rda-audit-extension-"));
    try {
        mkdirSync(join(root, "hooks"));
        mkdirSync(join(root, "kanban"));
        mkdirSync(join(root, "node_modules", "@github", "copilot-sdk"), { recursive: true });
        const source = new URL("../hooks/copilot/", import.meta.url);
        for (const file of ["audit.mjs", "context-recovery.mjs"]) copyFileSync(new URL(file, source), join(root, file));
        copyFileSync(new URL("extension.template.mjs", source), join(root, "extension.mjs"));
        writeFileSync(join(root, "node_modules", "@github", "copilot-sdk", "package.json"),
            JSON.stringify({ type: "module", exports: { "./extension": "./extension.mjs" } }));
        writeFileSync(join(root, "node_modules", "@github", "copilot-sdk", "extension.mjs"), `
export async function joinSession(config) {
    globalThis.config = config;
    globalThis.events = {};
    return { sessionId: "native-session", on: (type, handler) => {
        globalThis.events[type] = handler; return () => {};
    }, log: async () => {} };
}`);
        writeFileSync(join(root, "kanban", "audit.py"), "import sys\nprint('PRIVATE_LOGGER_CANARY', file=sys.stderr)\nsys.exit(7)\n");
        writeFileSync(join(root, "hooks", "bash-guard.sh"),
            "#!/bin/bash\ncat >/dev/null\nprintf '%s' '{\"hookSpecificOutput\":{\"permissionDecision\":\"ask\"}}'\n");
        writeFileSync(join(root, "driver.mjs"), `
import "./extension.mjs";
const hooks = globalThis.config.hooks;
globalThis.events["tool.execution_start"](${JSON.stringify(start("native-call"))});
const ask = await hooks.onPreToolUse({ toolName: "bash", toolArgs: { command: "echo safe" } });
const deny = await hooks.onPreToolUse({ toolName: "store_memory", toolArgs: {} });
const allow = await hooks.onPreToolUse({ toolName: "read", toolArgs: {} });
await hooks.onSessionEnd({});
process.stdout.write(JSON.stringify({ ask: ask.permissionDecision, deny: deny.permissionDecision,
    allow: allow === undefined, events: Object.keys(globalThis.events) }));
`);
        const result = spawnSync(process.execPath, [join(root, "driver.mjs")], {
            env: { ...process.env, RDA_OS: root, RDA_HOME: join(root, "home") }, encoding: "utf8", timeout: 5000,
        });
        assert.equal(result.status, 0, result.stderr);
        const output = JSON.parse(result.stdout);
        assert.equal(output.ask, "ask");
        assert.equal(output.deny, "deny");
        assert.equal(output.allow, true);
        for (const type of AUDIT_EVENTS) assert.ok(output.events.includes(type));
        assert.match(result.stderr, /ingest_failed/);
        assert.doesNotMatch(result.stdout + result.stderr, /PRIVATE_LOGGER_CANARY/);
    } finally {
        rmSync(root, { recursive: true });
    }
});
