// roberdan-os — native GitHub Copilot CLI extension (TEMPLATE).
//
// This is the CANONICAL source. `bin/sync.sh` materializes it into
// platforms/copilot/extension/roberdan-os/extension.mjs, substituting
// __RDA_OS_DEFAULT__ with the repo's absolute path at emit time (deterministic,
// mirrors the settings-hooks.json $ROOT expansion). `--install` symlinks the
// emitted file to ~/.copilot/extensions/roberdan-os/extension.mjs, so the live
// extension tracks the canon automatically — no hand-copied JS to drift.
//
// What it does — translate the provider-neutral hooks/ into Copilot lifecycle APIs:
//   onSessionStart     -> hooks/context-inject.sh  (inject fresh durable context)
//   onPreToolUse       -> hooks/main-guard.sh + hooks/bash-guard.sh (allow/ask/deny)
//   onPostToolUse      -> hooks/autofmt.sh (best-effort format after edits)
//   onPostToolUseFailure -> ephemeral observability log (no hidden success)
//   session.idle       -> the Claude "Stop" chain (pre-completion-gate, verify-done,
//                         post-task-sync, auto-checkpoint) as WARN + always-on checkpoint
//   onSessionEnd       -> final auto-checkpoint
// Plus safe, namespaced native tools (kanban view/actions, pause, resume, verify-done,
// doctor). The kanban gates (todo->doing needs --by, doing->done needs @thor evidence)
// are enforced by kb.sh itself — these tools never bypass them.
//
// HONEST LIMITATION (operational near-parity, not bit-for-bit Claude Stop parity):
// Copilot exposes session.idle / onSessionEnd AFTER a turn's final assistant message is
// already produced. There is no proven Copilot hook that can BLOCK or REWRITE that final
// response. So the "Stop" chain here can WARN (via session.log) and run side effects
// (checkpoint, sync), but it CANNOT hold back a premature "done" claim the way the Claude
// Stop hook's blocking output can. verify-done / pre-completion-gate remain advisory here.
//
// CONTEXT-PRESSURE TELEMETRY — deliberately NOT built (verified 2026-07-11):
// onSessionStart/onPreToolUse/onPostToolUse/onPostToolUseFailure/onSessionEnd expose only
// workingDirectory, toolName, toolArgs and error — no token/usage count of any kind. There is
// no stable signal here to build a "context getting heavy" proxy on, so no warning threshold
// is implemented. Revisit only if a future SDK version adds a real usage field, AND any such
// signal must stay measurement-only / zero-context-output (never injected into model context,
// never auto-triggers /new, never blocks a user) per rules/best-practices.md.

import { joinSession } from "@github/copilot-sdk/extension";
import { spawn } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

// Repo root: a runtime RDA_OS env wins (portable across forks / relocations); otherwise the
// path baked at emit time. Never throws if it's wrong — every hook degrades to a no-op.
const RDA_OS = process.env.RDA_OS || "__RDA_OS_DEFAULT__";
const HOOKS = join(RDA_OS, "hooks");
const KB = join(RDA_OS, "kanban", "kb.sh");
const HOME = process.env.HOME || process.env.USERPROFILE || "";

// Single diagnostic sink. stdout is reserved for JSON-RPC, so ALL diagnostics go to stderr.
// This exists so no failure is ever swallowed silently: every catch below routes here with a
// site tag, turning "empty catch" into an observable (but non-fatal) event. Never throws.
function diag(where, e) {
    try {
        const msg = e && e.stack ? e.stack : String(e);
        process.stderr.write(`[roberdan-os] ${where}: ${msg}\n`);
    } catch (_e) {
        /* stderr itself is unavailable — there is nowhere left to report; do not crash the CLI */
    }
}

// Tool-name classification (Copilot tool names, lowercased). File-writing tools feed the
// main-guard (branch discipline) + autofmt; shell tools feed the bash-guard.
const WRITE_TOOLS = new Set(["edit", "create", "write", "str_replace", "str_replace_editor", "multiedit", "notebookedit"]);
const SHELL_TOOLS = new Set(["bash", "shell", "execute", "powershell"]);

// Stop-chain throttle/dedup: session.idle fires after every turn; the chain does real work
// (git, gh, kb), so we serialize it (chainRunning) and rate-limit it (THROTTLE_MS) to avoid
// duplicate/reentrant runs — the explicit "avoid duplicate/reentrant runs" requirement.
const THROTTLE_MS = 20000;
let chainRunning = false;
let lastChainRun = 0;

let session;

// --- shell helpers -----------------------------------------------------------

// Run a script, feed it stdin, resolve { code, stdout, stderr }. Never rejects — a spawn
// failure resolves with code 127 so callers make an explicit (never silent) decision.
function runScript(scriptPath, stdinStr, cwd) {
    return new Promise((resolve) => {
        let child;
        try {
            child = spawn("bash", [scriptPath], { cwd: cwd || process.cwd(), env: process.env });
        } catch (e) {
            resolve({ code: 127, stdout: "", stderr: String(e && e.message ? e.message : e) });
            return;
        }
        let stdout = "";
        let stderr = "";
        child.stdout.on("data", (b) => (stdout += b.toString()));
        child.stderr.on("data", (b) => (stderr += b.toString()));
        child.on("error", (e) => resolve({ code: 127, stdout, stderr: stderr + String(e.message) }));
        child.on("close", (code) => resolve({ code: code == null ? 1 : code, stdout, stderr }));
        if (stdinStr != null) {
            child.stdin.on("error", (e) => diag("runScript:stdin", e)); // EPIPE if the child exits early — observable, non-fatal
            child.stdin.write(stdinStr);
        }
        child.stdin.end();
    });
}

// Run kb.sh with a FIXED argv (never a raw shell string — not an arbitrary exec proxy).
function runKb(argv, cwd) {
    return new Promise((resolve) => {
        if (!existsSync(KB)) {
            resolve({ code: 127, stdout: "", stderr: `kb.sh not found at ${KB}` });
            return;
        }
        let child;
        try {
            child = spawn("bash", [KB, ...argv], { cwd: cwd || process.cwd(), env: process.env });
        } catch (e) {
            resolve({ code: 127, stdout: "", stderr: String(e && e.message ? e.message : e) });
            return;
        }
        let stdout = "";
        let stderr = "";
        child.stdout.on("data", (b) => (stdout += b.toString()));
        child.stderr.on("data", (b) => (stderr += b.toString()));
        child.on("error", (e) => resolve({ code: 127, stdout, stderr: stderr + String(e.message) }));
        child.on("close", (code) => resolve({ code: code == null ? 1 : code, stdout, stderr }));
        child.stdin.end();
    });
}

// --- PreToolUse guard mapping ------------------------------------------------

// Run a guard script with the Claude-shaped stdin it expects and map its decision to Copilot.
// SECURITY POSTURE: a guard can only TIGHTEN (deny/ask), never loosen — on "allow"/empty we
// return undefined so Copilot's own permission flow still applies. A guard FAILURE (non-zero
// exit, missing script, unparseable output) is NOT treated as a success-shaped allow: it maps
// to "ask" (fail-safe, human-in-the-loop). This is a deliberate compatibility choice — Copilot
// has no "hook errored -> block" native path, so we degrade to a visible confirmation, never a
// silent proceed.
async function applyGuard(scriptRel, stdinObj, cwd) {
    const scriptPath = join(HOOKS, scriptRel);
    if (!existsSync(scriptPath)) return undefined; // guard not installed -> no override
    const { code, stdout } = await runScript(scriptPath, JSON.stringify(stdinObj), cwd);
    if (code !== 0) {
        return {
            permissionDecision: "ask",
            permissionDecisionReason: `roberdan-os ${scriptRel} could not evaluate this action (exit ${code}) — pausing for your confirmation (fail-safe).`,
        };
    }
    const trimmed = (stdout || "").trim();
    if (!trimmed) return undefined; // guard allowed (added no restriction)
    let decision;
    let reason;
    try {
        const parsed = JSON.parse(trimmed);
        const h = parsed.hookSpecificOutput || {};
        decision = h.permissionDecision;
        reason = h.permissionDecisionReason;
    } catch (e) {
        // Guard printed something non-JSON on exit 0: treat as advisory, don't silently allow.
        // The parse error itself is routed to diag() (observable), not swallowed.
        diag(`applyGuard:parse(${scriptRel})`, e);
        return {
            permissionDecision: "ask",
            permissionDecisionReason: `roberdan-os ${scriptRel} returned an unexpected result — pausing for your confirmation (fail-safe).`,
        };
    }
    if (decision === "deny" || decision === "ask") {
        return { permissionDecision: decision, permissionDecisionReason: reason || "roberdan-os guard" };
    }
    return undefined; // "allow" or unknown -> defer to Copilot's own permission flow
}

// --- the Stop chain (advisory on idle) ---------------------------------------

async function runStopChain(cwd) {
    const now = Date.now();
    if (chainRunning || now - lastChainRun < THROTTLE_MS) return;
    chainRunning = true;
    lastChainRun = now;
    try {
        // Advisory gates first: surface anything that would make a "done" claim premature.
        for (const rel of ["pre-completion-gate.sh", "verify-done.sh"]) {
            const p = join(HOOKS, rel);
            if (!existsSync(p)) continue;
            const { stdout, stderr } = await runScript(p, "", cwd);
            const msg = `${stdout || ""}${stderr || ""}`.trim();
            if (msg) {
                try {
                    await session.log(`[roberdan-os ${rel}]\n${msg}`, { level: "warning" });
                } catch (e) {
                    diag(`runStopChain:session.log(${rel})`, e);
                }
            }
        }
        // Side effects: opt-in wrapper regen (self-gated by RDA_AUTOSYNC) + always-on checkpoint.
        for (const rel of ["post-task-sync.sh", "auto-checkpoint.sh"]) {
            const p = join(HOOKS, rel);
            if (existsSync(p)) await runScript(p, "", cwd);
        }
    } finally {
        chainRunning = false;
    }
}

// --- native tools ------------------------------------------------------------

// Allowlisted kanban actions -> a fixed kb.sh argv. Read actions are unrestricted; the two
// gated transitions (start/finish) only carry their gate flag when the caller supplies it,
// so kb.sh's own refusal (todo->doing needs --by, doing->done needs @thor evidence) stands.
function kanbanArgv(args) {
    const a = args || {};
    const action = String(a.action || "").trim();
    switch (action) {
        case "view":
        case "pending":
        case "all":
        case "handoff":
        case "todo":
        case "doing":
        case "done":
            return [action];
        case "show":
            if (!a.id) return null;
            return ["show", String(a.id)];
        case "add": {
            if (!a.title || !a.repo) return null;
            const argv = ["add", String(a.title)];
            if (a.dod && a.acceptance) argv.push(String(a.dod), String(a.acceptance));
            argv.push("--repo", String(a.repo));
            return argv;
        }
        case "start": {
            if (!a.id) return null;
            const argv = ["start", String(a.id)];
            if (a.by) argv.push("--by", String(a.by)); // omit -> kb REFUSES (Roberto gate intact)
            return argv;
        }
        case "finish": {
            if (!a.id) return null;
            const argv = ["finish", String(a.id)];
            if (a.evidence) argv.push("--thor", String(a.evidence)); // omit -> kb REFUSES (@thor gate intact)
            return argv;
        }
        case "block":
            if (!a.id || !a.reason) return null;
            return ["block", String(a.id), String(a.reason)];
        default:
            return null;
    }
}

const KANBAN_ACTIONS = "view, pending, all, handoff, todo, doing, done, show, add, start, finish, block";

const tools = [
    {
        name: "roberdanos_kanban",
        description:
            "roberdan-os kanban board. Read actions (view, pending, all, handoff, todo, doing, done, show) and gated actions (add, start, finish, block). The Roberto gate (todo->doing needs `by`) and @thor evidence gate (doing->done needs `evidence`) are enforced by kb — omit the flag and the action is refused, not bypassed.",
        parameters: {
            type: "object",
            properties: {
                action: { type: "string", description: `One of: ${KANBAN_ACTIONS}` },
                id: { type: "string", description: "Card id (for show/start/finish/block)" },
                by: { type: "string", description: "Human approver for start (todo->doing gate). Omit to see the refusal." },
                evidence: { type: "string", description: "@thor evidence for finish (doing->done gate). Omit to see the refusal." },
                title: { type: "string", description: "Card title (for add)" },
                repo: { type: "string", description: "Repo/scope for add (e.g. roberdan-os, personal)" },
                dod: { type: "string", description: "Definition of done (for add)" },
                acceptance: { type: "string", description: "Acceptance criteria (for add)" },
                reason: { type: "string", description: "Reason (for block)" },
            },
            required: ["action"],
        },
        handler: async (args) => {
            const argv = kanbanArgv(args);
            if (!argv) {
                return {
                    textResultForLlm: `Invalid kanban invocation. action must be one of: ${KANBAN_ACTIONS}, with required fields (e.g. add needs title+repo; show/start/finish/block need id).`,
                    resultType: "failure",
                };
            }
            const { code, stdout, stderr } = await runKb(argv);
            const out = `${stdout || ""}${stderr ? "\n" + stderr : ""}`.trim() || "(no output)";
            // A refusal (kb exit 1 on a gated action) is a legitimate, expected result — report it
            // as text, not as a tool crash, so the agent relays the gate to the user.
            return out;
        },
    },
    {
        name: "roberdanos_pause",
        description:
            "Write a durable pause/resume checkpoint (kb pause) so work can be safely resumed later, even after a reboot. Pass a concise note of what you were doing and the precise next step.",
        parameters: {
            type: "object",
            properties: { note: { type: "string", description: "What you were doing + the precise next step." } },
            required: ["note"],
        },
        handler: async (args) => {
            const note = String((args && args.note) || "").trim();
            const argv = note ? ["pause", note] : ["pause"];
            const { stdout, stderr } = await runKb(argv);
            return `${stdout || ""}${stderr ? "\n" + stderr : ""}`.trim() || "checkpoint written";
        },
    },
    {
        name: "roberdanos_resume",
        description:
            "Read the pause/resume checkpoint (kb resume) to pick up where a previous session left off. Set clear=true to clear it once resumed.",
        parameters: {
            type: "object",
            properties: { clear: { type: "boolean", description: "Clear the checkpoint (kb resume --done)." } },
        },
        handler: async (args) => {
            const argv = args && args.clear ? ["resume", "--done"] : ["resume"];
            const { stdout, stderr } = await runKb(argv);
            return `${stdout || ""}${stderr ? "\n" + stderr : ""}`.trim() || "(no checkpoint)";
        },
    },
    {
        name: "roberdanos_verify_done",
        description:
            "Run the roberdan-os verify-done soft check (uncommitted changes, version drift, commit-on-main without a bump) in the current repo. Advisory only — it reports warnings, it does not block. Use before claiming a task is done.",
        parameters: { type: "object", properties: {} },
        handler: async () => {
            const p = join(HOOKS, "verify-done.sh");
            if (!existsSync(p)) return "verify-done.sh not found — is RDA_OS set correctly?";
            const { stdout, stderr } = await runScript(p, "");
            const msg = `${stdout || ""}${stderr || ""}`.trim();
            return msg || "verify-done: clean (no warnings).";
        },
    },
    {
        name: "roberdanos_doctor",
        description:
            "Diagnose the roberdan-os <-> Copilot wiring: repo root, custom agents, skills, gbrain MCP, context injection. Reports what's missing and the remediation command. Never prints secrets.",
        parameters: { type: "object", properties: {} },
        handler: async () => {
            const lines = [];
            const mark = (ok, label) => lines.push(`${ok ? "ok  " : "MISS"}  ${label}`);
            // repo root
            const agentsMd = join(RDA_OS, "AGENTS.md");
            mark(existsSync(agentsMd), `RDA_OS canon at ${RDA_OS} (AGENTS.md present)`);
            // custom agents installed
            const agentsDir = join(HOME, ".copilot", "agents");
            let agentCount = 0;
            try {
                if (existsSync(agentsDir)) {
                    const { readdirSync } = await import("node:fs");
                    agentCount = readdirSync(agentsDir).filter((f) => f.endsWith(".md")).length;
                }
            } catch (e) {
                diag("doctor:readdir(agents)", e);
            }
            mark(agentCount > 0, `custom agents installed in ~/.copilot/agents (${agentCount} found)`);
            // extension installed
            const extFile = join(HOME, ".copilot", "extensions", "roberdan-os", "extension.mjs");
            mark(existsSync(extFile), "extension installed at ~/.copilot/extensions/roberdan-os/extension.mjs");
            // skills
            const skillsDir = join(HOME, ".copilot", "skills");
            let skillCount = 0;
            try {
                if (existsSync(skillsDir)) {
                    const { readdirSync } = await import("node:fs");
                    skillCount = readdirSync(skillsDir).length;
                }
            } catch (e) {
                diag("doctor:readdir(skills)", e);
            }
            mark(skillCount > 0, `skills present in ~/.copilot/skills (${skillCount} entries)`);
            // gbrain MCP (presence only — never read/echo the file's contents; it holds secrets)
            const mcp = join(HOME, ".copilot", "mcp-config.json");
            let gbrain = false;
            try {
                if (existsSync(mcp)) gbrain = /"gbrain"/.test(readFileSync(mcp, "utf-8"));
            } catch (e) {
                diag("doctor:probe(mcp-config)", e);
            }
            mark(gbrain, "gbrain configured in ~/.copilot/mcp-config.json (Copilot-owned; never modified here)");
            // context injection works
            const ci = join(HOOKS, "context-inject.sh");
            let ciOk = false;
            if (existsSync(ci)) {
                const { code } = await runScript(ci, "");
                ciOk = code === 0;
            }
            mark(ciOk, "context-inject.sh runs (session-start context available)");

            const anyMiss = lines.some((l) => l.startsWith("MISS"));
            const footer = anyMiss
                ? "\nRemediation: run `bash bin/sync.sh --install` from roberdan-os (collision-safe; never overwrites). gbrain/mcp-config is Copilot-owned — add it by hand if missing."
                : "\nAll roberdan-os <-> Copilot wiring present.";
            return `roberdan-os doctor\n${lines.join("\n")}${footer}`;
        },
    },
];

// --- hooks -------------------------------------------------------------------

const hooks = {
    onSessionStart: async (input) => {
        const ci = join(HOOKS, "context-inject.sh");
        if (!existsSync(ci)) return undefined;
        const { stdout } = await runScript(ci, "", input && input.workingDirectory);
        const ctx = (stdout || "").trim();
        return ctx ? { additionalContext: ctx } : undefined;
    },

    onPreToolUse: async (input) => {
        const name = String((input && input.toolName) || "").toLowerCase();
        const args = (input && input.toolArgs) || {};
        // Forward the session's working directory so the guards resolve the correct repo/branch
        // even when a relative path is supplied and the extension's own cwd differs (a relative
        // path with a cwd mismatch would otherwise let main-guard resolve no repo and fail OPEN).
        const cwd = (input && input.workingDirectory) || process.cwd();
        if (WRITE_TOOLS.has(name)) {
            const fp = args.path || args.file_path || args.filePath || "";
            return await applyGuard("main-guard.sh", { tool_input: { file_path: String(fp) } }, cwd);
        }
        if (SHELL_TOOLS.has(name)) {
            const cmd = args.command || args.cmd || "";
            return await applyGuard("bash-guard.sh", { tool_input: { command: String(cmd) } }, cwd);
        }
        return undefined;
    },

    onPostToolUse: async (input) => {
        const name = String((input && input.toolName) || "").toLowerCase();
        if (!WRITE_TOOLS.has(name)) return undefined;
        const args = (input && input.toolArgs) || {};
        const fp = args.path || args.file_path || args.filePath || "";
        const p = join(HOOKS, "autofmt.sh");
        if (!fp || !existsSync(p)) return undefined;
        // Best-effort format (autofmt is silent-on-success, never-blocks by contract). A failure
        // is NOT converted into a success-shaped result and NOT surfaced to the model (autofmt
        // failures are environmental — missing formatter — and would be noise). But it is not
        // hidden either: a non-zero exit is reported to stderr via diag() so it stays observable.
        const { code, stderr } = await runScript(
            p,
            JSON.stringify({ tool_input: { file_path: String(fp) } }),
            input && input.workingDirectory,
        );
        if (code !== 0) diag(`onPostToolUse:autofmt(exit ${code})`, stderr || `autofmt failed on ${fp}`);
        return undefined;
    },

    onPostToolUseFailure: async (input) => {
        // Observability only: surface the failure ephemerally (no hidden guidance that could
        // silently steer the model). Non-blocking, never throws.
        try {
            await session.log(
                `[roberdan-os] tool '${input && input.toolName}' failed: ${String((input && input.error) || "").slice(0, 200)}`,
                { level: "warning", ephemeral: true },
            );
        } catch (e) {
            diag("onPostToolUseFailure:session.log", e);
        }
        return undefined;
    },

    onSessionEnd: async (input) => {
        // Final always-on checkpoint so an exit/crash loses at most the current turn.
        const p = join(HOOKS, "auto-checkpoint.sh");
        if (existsSync(p)) await runScript(p, "", input && input.workingDirectory);
        return undefined;
    },
};

// --- join --------------------------------------------------------------------

try {
    session = await joinSession({ tools, hooks });
    // The Claude "Stop" analog: after every turn Copilot emits session.idle. We run the
    // advisory gate chain + always-on checkpoint here (throttled + serialized). This can WARN
    // and run side effects, but — per the documented limitation — it cannot block/rewrite the
    // final assistant message that has already been produced.
    session.on("session.idle", () => {
        runStopChain(process.cwd()).catch((e) => diag("session.idle:runStopChain", e));
    });
    try {
        await session.log("roberdan-os extension loaded (agents, guards, kanban tools, always-on checkpoint).", {
            ephemeral: true,
        });
    } catch (e) {
        diag("join:session.log(loaded)", e);
    }
} catch (e) {
    // stdout is reserved for JSON-RPC; diagnostics go to stderr and never crash the CLI.
    process.stderr.write(`roberdan-os extension failed to join session: ${e && e.stack ? e.stack : e}\n`);
}
