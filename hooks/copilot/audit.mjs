import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

// SDK 1.0.86-2 session-events.d.ts. Hook invocation context has no toolCallId.
export const AUDIT_LIMITS = Object.freeze({ pending: 64, metadataBytes: 16384, writeMs: 1000, flushMs: 1500 });
export const AUDIT_EVENTS = Object.freeze([
    "tool.execution_start", "tool.execution_complete", "subagent.started",
    "subagent.completed", "subagent.failed", "subagent.configured",
    "session.skills_loaded", "session.shutdown",
]);
const identifiers = /^[A-Za-z0-9][A-Za-z0-9_.:/-]{0,127}$/;
const policy = "public_allowlist_v1";
const catalogs = new Map();
const object = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const identifier = (value) => typeof value === "string" && identifiers.test(value);

function publicSkillNames(root) {
    if (catalogs.has(root)) return catalogs.get(root);
    const payload = readFileSync(join(root, "kanban", "audit_skill_names.json"));
    if (payload.length > AUDIT_LIMITS.metadataBytes) throw Error("skill_policy_unavailable");
    const data = JSON.parse(payload);
    if (!object(data) || Object.keys(data).sort().join() !== "canonical,compatibility,providers" ||
        Object.values(data).some((names) => !Array.isArray(names) || names.length > 64 ||
            names.some((name) => typeof name !== "string" || !/^[a-z][a-z0-9-]{0,63}$/.test(name)))) {
        throw Error("skill_policy_unavailable");
    }
    const names = new Set([...data.canonical, ...data.canonical.map((name) => `rdos-${name}`),
        ...data.compatibility, ...data.providers]);
    catalogs.set(root, names);
    return names;
}

// Project before serializing: no traversal of prompts, results, errors, or shell arguments.
export function normalizeAuditEvent(event, sessionId,
    names = publicSkillNames(fileURLToPath(new URL("../../", import.meta.url)))) {
    if (!identifier(sessionId)) throw Error("invalid_session_id");
    if (!object(event) || !AUDIT_EVENTS.includes(event.type) || !object(event.data)) throw Error("unsupported_event");
    const data = {};
    const put = (key, value) => {
        if (value === undefined) return;
        if (!identifier(value)) throw Error("invalid_metadata");
        data[key] = value;
    };
    const source = event.data;
    put("agentId", event.agentId);
    if (event.type.startsWith("tool.")) {
        put("model", source.model);
        if (!identifier(source.toolCallId)) throw Error("missing_tool_call_id");
        put("toolCallId", source.toolCallId);
    }
    if (event.type.startsWith("tool.")) put("parentToolCallId", source.parentToolCallId);
    if (event.type === "tool.execution_start") {
        if (names) data.skillNamePolicy = policy;
        if (!identifier(source.toolName)) throw Error("invalid_tool_name");
        put("toolName", source.toolName);
        let args = source.arguments;
        if (typeof args === "string" && ["skill", "task"].includes(source.toolName)) {
            if (args.length > AUDIT_LIMITS.metadataBytes) throw Error("oversized_arguments");
            try { args = JSON.parse(args); } catch (e) { throw Error("invalid_arguments"); }
        }
        if (object(args)) {
            if (source.toolName === "skill" && names?.has(args.skill)) data.arguments = { skill: args.skill };
            if (source.toolName === "task") {
                for (const key of ["agent_type", "name"]) {
                    if (args[key] !== undefined) {
                        if (!identifier(args[key])) throw Error("invalid_metadata");
                        (data.arguments ??= {})[key] = args[key];
                    }
                }
            }
        }
        if (source.toolName === "skill" && !data.arguments) data.skillNameStatus = "omitted";
    }
    if (event.type === "tool.execution_complete") {
        if (typeof source.success !== "boolean") throw Error("missing_terminal_status");
        data.success = source.success;
        if (object(source.error) && source.error.code !== undefined) {
            if (!identifier(source.error.code)) throw Error("invalid_error_code");
            data.error = { code: source.error.code };
        }
    }
    if (event.type.startsWith("subagent.")) {
        put("model", source.model);
        put("agentName", source.agentName);
        if (event.type === "subagent.completed") {
            if (source.cancelled !== undefined && typeof source.cancelled !== "boolean") throw Error("invalid_metadata");
            data.success = source.cancelled !== true;
            if (source.cancelled === true) data.error = { code: "cancelled" };
        }
        if (event.type === "subagent.failed") data.success = false;
    }
    if (event.type === "session.skills_loaded") {
        if (!Array.isArray(source.skills) || source.skills.length > 256) throw Error("oversized_discovery");
        data.skills = [...new Set(source.skills.filter((skill) => object(skill) && names?.has(skill.name))
            .map((skill) => skill.name))].sort();
        if (source.skills.some((skill) => !object(skill) || !names?.has(skill.name))) data.skillNameStatus = "omitted";
    }
    const envelope = { type: event.type, session_id: sessionId, data };
    if (event.id !== undefined) {
        if (!identifier(event.id)) throw Error("invalid_event_id");
        envelope.id = event.id;
    }
    if (event.timestamp !== undefined) {
        if (typeof event.timestamp !== "string" || event.timestamp.length > 40 ||
            !/^\d{4}-\d\d-\d\dT[\d:.]+(?:Z|[+-]\d\d:\d\d)$/.test(event.timestamp) ||
            !Number.isFinite(Date.parse(event.timestamp))) throw Error("invalid_timestamp");
        envelope.timestamp = event.timestamp;
    }
    if (JSON.stringify(envelope).length > AUDIT_LIMITS.metadataBytes) throw Error("oversized_metadata");
    return envelope;
}

function ingest(script, stdin, { signal }) {
    return new Promise((resolve) => {
        const child = spawn("python3", [script, "ingest", "--host", "copilot"], {
            stdio: ["pipe", "ignore", "ignore"], signal, killSignal: "SIGKILL",
        });
        let failed = false;
        child.on("error", () => { failed = true; });
        child.stdin.on("error", () => { failed = true; });
        child.on("close", (code) => resolve({ code: failed ? 1 : code }));
        child.stdin.end(stdin);
    });
}

// Injected writers receive (scriptPath, safeJSON, {signal}) and must honor cancellation.
export function createAuditObserver({ root, sessionId, runScript = ingest, report = (code) =>
    process.stderr.write(`[roberdan-os audit] ${code}\n`) }) {
    const queue = [];
    let active;
    let running;
    let closing = false;
    let closed = false;
    let gap = false;
    let started = false;
    let shutdown;
    const subscriptions = [];
    const diagnostic = (code) => {
        try { report(code); } catch (e) {
            process.stderr.write("[roberdan-os audit] diagnostic_failed\n");
        }
    };
    let names = null;
    try { names = publicSkillNames(root); } catch (e) { diagnostic("skill_policy_unavailable"); }
    const coverage = (type, code) => ({
        type, session_id: sessionId, data: code ? { error: { code } } : {},
    });
    function lost(code) {
        if (!gap) diagnostic(code);
        gap = true;
    }
    async function write(envelope) {
        const controller = new AbortController();
        active = controller;
        const timer = setTimeout(() => controller.abort(), AUDIT_LIMITS.writeMs);
        try {
            const result = await runScript(join(root, "kanban", "audit.py"), JSON.stringify(envelope), { signal: controller.signal });
            if (!result || result.code !== 0 || controller.signal.aborted) {
                lost(controller.signal.aborted ? "ingest_timeout" : "ingest_failed");
                return false;
            }
            return true;
        } catch (e) {
            lost("ingest_failed");
            return false;
        } finally {
            clearTimeout(timer);
            active = undefined;
        }
    }
    function pump() {
        if (running || closed) return;
        running = (async () => {
            while (queue.length && !closed) {
                const envelope = queue.shift();
                if (gap) {
                    gap = false;
                    if (!await write(coverage("observer.gap", "events_lost"))) continue;
                }
                await write(envelope);
            }
        })().finally(() => { running = undefined; });
    }
    function enqueue(envelope) {
        if (queue.length + Number(Boolean(active)) >= AUDIT_LIMITS.pending) {
            lost("queue_full");
            return;
        }
        queue.push(envelope);
        pump();
    }
    function observe(event) {
        if (closing || closed) return;
        try { enqueue(normalizeAuditEvent(event, sessionId, names)); } catch (e) {
            // Only codes created by this normalizer are diagnostic; never echo host exceptions.
            const codes = new Set(["unsupported_event", "missing_tool_call_id", "oversized_arguments",
                "invalid_arguments", "invalid_metadata", "invalid_tool_name", "missing_terminal_status",
                "invalid_error_code", "oversized_discovery", "invalid_event_id", "invalid_timestamp",
                "oversized_metadata", "invalid_session_id"]);
            lost(codes.has(e.message) ? e.message : "invalid_event");
        }
    }
    function register(session) {
        if (started) return;
        started = true;
        if (!identifier(sessionId)) { closed = true; diagnostic("invalid_session_id"); return; }
        for (const type of AUDIT_EVENTS) {
            try { subscriptions.push(session.on(type, observe)); } catch (e) { lost("subscription_failed"); }
        }
        enqueue(coverage("observer.start", "live_events_only"));
        enqueue(coverage("observer.unsupported", "semantic_decisions_require_explicit_records"));
        enqueue(coverage("observer.unsupported", "permission_consent_not_observed"));
        enqueue(coverage("observer.unsupported", "skill_invoked_has_no_tool_call_id"));
        enqueue(coverage("observer.unsupported", names ? "public_skill_names_only" : "skill_policy_unavailable"));
    }
    async function flush() {
        pump();
        if (!running) return !gap;
        const pending = queue.length + Number(Boolean(active));
        const budget = Math.max(AUDIT_LIMITS.flushMs, pending * AUDIT_LIMITS.writeMs);
        let timer;
        const drained = await Promise.race([
            running.then(() => true),
            new Promise((resolve) => { timer = setTimeout(() => resolve(false), budget); }),
        ]);
        clearTimeout(timer);
        if (!drained) { lost("flush_timeout"); active?.abort(); }
        return drained && !gap;
    }
    function stop() {
        if (shutdown) return shutdown;
        closing = true;
        for (const unsubscribe of subscriptions) {
            try { unsubscribe(); } catch (e) { lost("unsubscribe_failed"); }
        }
        shutdown = (async () => {
            if (!closed && identifier(sessionId)) {
                const drained = await flush();
                if (!drained) {
                    queue.length = 0;
                    // No end marker can claim a clean shutdown while a writer is still running.
                    closed = true;
                    return false;
                }
                enqueue(coverage("observer.end"));
                const ended = await flush();
                closed = true;
                queue.length = 0;
                return ended;
            }
            return false;
        })();
        return shutdown;
    }
    return { observe, register, flush, stop,
        status: () => ({ pending: queue.length + Number(Boolean(active)), gap, closed }) };
}
