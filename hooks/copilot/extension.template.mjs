// roberdan-os — native GitHub Copilot CLI extension (TEMPLATE).
//
// Canonical source: sync.sh emits extension.mjs, context-recovery.mjs and audit.mjs, baking ROOT.
// --install symlinks the emitted extension into ~/.copilot/extensions/roberdan-os/.
//
// Shell hooks own context, tool guards, checkpoints and kanban gates; tools never bypass them.
// onAgentStop alone requests native bounded continuation; idle is advisory with an older-host fallback.
// Usage/compaction events save and recover context; session end makes a final checkpoint.
//
// Native stop support was checked against CLI 1.0.84-5 AgentStopHookOutput.
// Registration is not execution evidence. Queue continuation and skill obligations are separate.
// See docs/USAGE.md for installation, explicit pause commands and runtime limitations.

import { joinSession } from "@github/copilot-sdk/extension";
import { spawn } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { createContextRecovery } from "./context-recovery.mjs";
import { createAuditObserver } from "./audit.mjs";
import { withSkillObligations } from "./skill-obligations.mjs";

// Repo root: a runtime RDA_OS env wins (portable across forks / relocations); otherwise the
// path baked at emit time. Never throws if it's wrong — every hook degrades to a no-op.
const RDA_OS = process.env.RDA_OS || "__RDA_OS_DEFAULT__";
const HOOKS = join(RDA_OS, "hooks");
const KB = join(RDA_OS, "kanban", "kb.sh");
const KB_CMD = process.env.RDA_KB_CMD || "kb";
const HOME =
    process.env.HOME ||
    process.env.USERPROFILE ||
    homedir() ||
    // Last-resort fallback for odd extension launch envs without HOME/USERPROFILE.
    // __RDA_OS_DEFAULT__ resolves to <home>/GitHub/roberdan-os in normal installs.
    dirname(dirname(dirname(RDA_OS))) ||
    "";
const RDA_HOME = process.env.RDA_HOME || (HOME ? join(HOME, ".roberdan-os") : "");
const RDA_KANBAN_REGISTRY = process.env.RDA_KANBAN_REGISTRY || (RDA_HOME ? join(RDA_HOME, "kanban-registry") : "");

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
// Host-native memory tools. AGENTS.md forbids them: durable memory belongs in the local
// vault (~/Obsidian), never in a vendor-hosted store. The vendor's own `memory.enabled`
// setting is the primary switch, but it lives outside this repo and can be flipped back by
// an update or a stray `/memory` toggle — so we deny here too, in something we control.
const MEMORY_TOOLS = new Set(["store_memory", "vote_memory", "create_memory", "update_memory"]);

// Hook inputs carry `toolArgs` as `unknown`, and the session-event schema marks it
// `x-opaque-json`: the host may deliver it as an already-parsed object OR as a JSON
// *string*. Treating the string form as an object silently yields an empty file_path,
// which makes main-guard fall back to the session cwd - over-blocking every write (even
// outside any repo) whenever that cwd sits on main, and skipping the path carve-outs
// entirely. Normalize once, here, so every hook sees a real object.
function toolArgsOf(input) {
    const raw = input && input.toolArgs;
    if (!raw) return {};
    if (typeof raw === "object") return raw;
    if (typeof raw === "string") {
        try {
            const parsed = JSON.parse(raw);
            return parsed && typeof parsed === "object" ? parsed : {};
        } catch (e) {
            diag("toolArgsOf:parse", e);
            return {};
        }
    }
    return {};
}

// Target path of a write tool, across the argument-naming variants.
function writePathOf(args) {
    return args.path || args.file_path || args.filePath || args.notebook_path || "";
}

// Stop-chain throttle/dedup: session.idle fires after every turn; the chain does real work
// (git, gh, kb), so we serialize it (chainRunning) and rate-limit it (THROTTLE_MS) to avoid
// duplicate/reentrant runs — the explicit "avoid duplicate/reentrant runs" requirement.
const THROTTLE_MS = 20000;
let chainRunning = false;
let lastChainRun = 0;

let session;
let auditObserver;
let agentStopObserved = false;
let userPauseRequested = false;
const contextRecovery = createContextRecovery({ hooksDirectory: HOOKS, runScript, runKb, hookPayload, diag });

// Queue counters and doorbell stamps require the joined session's readonly sessionId;
// omitting it collapses every session onto the hooks' shared "nosession" fallback.
function sessionId() {
    try {
        return String((session && session.sessionId) || "");
    } catch (e) {
        diag("sessionId", e);
        return "";
    }
}

// The stdin payload shape Claude Code hands its hooks. Keep the key names identical — the hooks
// are provider-neutral and parse these names directly.
function hookPayload(cwd) {
    const sid = sessionId();
    const payload = { cwd: cwd || process.cwd() };
    if (sid) payload.session_id = sid;
    return JSON.stringify(payload);
}

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

// Run kb with a FIXED argv (never a raw shell string — not an arbitrary exec proxy).
// Prefer the installed `kb` command for parity with interactive CLI behavior; if unavailable,
// fall back to the repo-local kb.sh shipped with roberdan-os.
function runKb(argv, cwd) {
    return new Promise((resolve) => {
        const launch = (cmd, args) => {
            let child;
            try {
                child = spawn(cmd, args, {
                    cwd: cwd || process.cwd(),
                    env: {
                        ...process.env,
                        ...(HOME ? { HOME } : {}),
                        ...(process.env.USERPROFILE ? {} : HOME ? { USERPROFILE: HOME } : {}),
                        ...(process.env.RDA_HOME ? {} : RDA_HOME ? { RDA_HOME } : {}),
                        ...(process.env.RDA_KANBAN_REGISTRY ? {} : RDA_KANBAN_REGISTRY ? { RDA_KANBAN_REGISTRY } : {}),
                    },
                });
            } catch (e) {
                resolve({ code: 127, stdout: "", stderr: String(e && e.message ? e.message : e) });
                return;
            }
            let stdout = "";
            let stderr = "";
            let errored = false;
            child.stdout.on("data", (b) => (stdout += b.toString()));
            child.stderr.on("data", (b) => (stderr += b.toString()));
            child.on("error", (e) => {
                const msg = String(e && e.message ? e.message : e);
                // If `kb` command is not present, fall back to the repo-local kb.sh.
                if (!errored && cmd === KB_CMD && existsSync(KB)) {
                    errored = true;
                    launch("bash", [KB, ...argv]);
                    return;
                }
                resolve({ code: 127, stdout, stderr: stderr + msg });
            });
            child.on("close", (code) => {
                if (errored) return;
                resolve({ code: code == null ? 1 : code, stdout, stderr });
            });
            child.stdin.end();
        };

        launch(KB_CMD, argv);
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

async function warn(where, message) {
    try {
        await session.log(`[roberdan-os ${where}]\n${message}`, { level: "warning" });
    } catch (e) {
        diag(`${where}:session.log`, e);
    }
}

async function runStopChain(cwd) {
    const now = Date.now();
    if (chainRunning || now - lastChainRun < THROTTLE_MS) return;
    chainRunning = true;
    lastChainRun = now;
    try {
        // Do not consume queue retry/stall counters twice on hosts delivering onAgentStop.
        for (const rel of ["pre-completion-gate.sh", "verify-done.sh", "goal-gate.sh"]) {
            if (rel === "goal-gate.sh" && (agentStopObserved || userPauseRequested)) continue;
            const p = join(HOOKS, rel);
            if (!existsSync(p)) continue;
            const { stdout, stderr } = await runScript(p, hookPayload(cwd), cwd);
            const msg = `${stdout || ""}${stderr || ""}`.trim();
            if (msg) {
                const limit = rel === "goal-gate.sh"
                    ? "Continuation NOT enforced: onAgentStop has not been observed. This idle warning cannot restart work; a checkpoint is not an executor.\n"
                    : "";
                await warn(rel, limit + msg);
            }
        }
        // Side effects: opt-in wrapper regen (self-gated by RDA_AUTOSYNC) + always-on checkpoint.
        // These get the same payload as the gates — Claude Code hands every Stop hook the identical
        // stdin object, and a hook that ignores it costs nothing.
        for (const rel of ["post-task-sync.sh", "auto-checkpoint.sh"]) {
            const p = join(HOOKS, rel);
            if (existsSync(p)) await runScript(p, hookPayload(cwd), cwd);
        }
    } finally {
        chainRunning = false;
    }
}

// --- the bus doorbell (PostToolUse, every tool) ------------------------------

// Ring, never deliver. hooks/bus-doorbell.sh prints its count as JSON on
// `hookSpecificOutput.additionalContext` because that is the only channel Claude Code injects
// next to a PostToolUse result. Copilot's onPostToolUse has no verified additionalContext
// equivalent, so the text is surfaced through the same ephemeral session.log channel already
// used by onPostToolUseFailure: the user and the model see the COUNT, and the message bodies
// still only ever arrive through an explicit `bus read`. Never throws, never blocks.
async function ringDoorbell(cwd) {
    try {
        const p = join(HOOKS, "bus-doorbell.sh");
        if (!existsSync(p)) return;
        const { stdout } = await runScript(p, hookPayload(cwd), cwd);
        const trimmed = (stdout || "").trim();
        if (!trimmed) return; // fast path: no traffic for this repo, or nothing new since last ring
        let text = "";
        try {
            const parsed = JSON.parse(trimmed);
            text = String((parsed.hookSpecificOutput && parsed.hookSpecificOutput.additionalContext) || "").trim();
        } catch (e) {
            // Non-JSON output is not silently dropped: it is still a ring, just an unshaped one.
            diag("ringDoorbell:parse", e);
            text = trimmed;
        }
        if (!text) return;
        await session.log(`[roberdan-os bus]\n${text}`, { level: "warning", ephemeral: true });
    } catch (e) {
        diag("ringDoorbell", e);
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
                : "\nInstallation files present; context-inject.sh runs.";
            return `roberdan-os doctor\n${lines.join("\n")}${footer}\nRuntime agent/skill discovery and MCP connectivity are NOT verified. If installed tools are unavailable, reload extensions, then invoke an agent and load a skill; if still unavailable, checkpoint and restart Copilot. See docs/USAGE.md.`;
        },
    },
];

// --- response shaping ------------------------------------------------------------

// The executive response format, sliced from the canon between the exec-format markers.
// Returns a SystemMessageConfig (mode "append" — keeps every SDK guardrail) or undefined if
// the canon is unreadable / the markers are gone. Never throws.
function execFormatSystemMessage() {
    try {
        const md = readFileSync(join(RDA_OS, "behavior", "roberto-mode.md"), "utf-8");
        const m = md.match(/<!-- exec-format:begin[\s\S]*?-->([\s\S]*?)<!-- exec-format:end -->/);
        const body = m && m[1] ? m[1].trim() : "";
        if (!body) {
            // Markers renamed/removed by a canon edit: degrade to the per-turn reminder only,
            // but never silently — this feature is an accessibility commitment.
            diag("execFormatSystemMessage:markers-missing", "exec-format markers not found in roberto-mode.md");
            return undefined;
        }
        return {
            mode: "append",
            content: `## Communicating with Roberto — the fixed response format (non-negotiable)\n\n${body}`,
        };
    } catch (e) {
        diag("execFormatSystemMessage:read", e);
        return undefined;
    }
}

// Rides on every user turn (a systemMessage append can be diluted in a very long session, this
// cannot) — and is paid EVERY turn, so it has two forms: short when the full contract is already
// in the systemMessage, long when it is the only carrier. The cheap form is never the fallback.
const EXEC_FMT_SECTIONS = '(1) Stato, (2) Sto facendo, (3) Manca, (4) Mi serve da te';
const EXEC_FMT_TAIL = 'every finished item marked inline "fatto e provato" or "fatto, non ancora provato" — never a bare "done". Detail (commands, paths, numbers) in a short tail at the bottom. Delete empty sections. No unexplained jargon. Max ~6 lines before the detail.';
const EXEC_FORMAT_TURN_REMINDER_SHORT = `Roberto's fixed executive format (full contract in the system message): ${EXEC_FMT_SECTIONS} — ${EXEC_FMT_TAIL}`;
const EXEC_FORMAT_TURN_REMINDER_FULL = `Reply to Roberto in the fixed executive format: ${EXEC_FMT_SECTIONS}. "Stato" opens with one sentence, no preamble, and states where the work actually stands; "Sto facendo" is the one thing in hand right now; "Manca" is the remaining steps, numbered, in order; "Mi serve da te" carries the options with their consequences + your recommendation first, or "Nulla". In "Stato", ${EXEC_FMT_TAIL}`;
let execFormatInSystemMessage = false; // false ⇒ the long form, on every unexpected path

// --- hooks -------------------------------------------------------------------

const hooks = withSkillObligations({
    onSessionStart: async (input) => {
        contextRecovery.rememberDirectory(input);
        const ci = join(HOOKS, "context-inject.sh");
        if (!existsSync(ci)) return undefined;
        // session_id + source (CLI 1.0.84-5 SessionStartHookInput) renew the queue on a NEW session only.
        const sid = String((input && input.sessionId) || sessionId() || "");
        const stdin = sid ? JSON.stringify({ session_id: sid, source: String((input && input.source) || "") }) : "";
        const { stdout } = await runScript(ci, stdin, input && input.workingDirectory);
        const ctx = (stdout || "").trim();
        return ctx ? { additionalContext: ctx } : undefined;
    },

    // Per-turn reinforcement of the executive format (see the REMINDER constants). additionalContext only — never rewrites the prompt.
    onUserPromptSubmitted: async (input) => {
        if ((!input.sessionId || input.sessionId === sessionId()) && typeof input.prompt === "string") {
            userPauseRequested = /^(?:stop|pause|pausa|fermati|metti in pausa|devo andare|vado)[.!?\s]*$/iu.test(input.prompt.trim());
        }
        const recovery = await contextRecovery.takeRecovery(contextRecovery.rememberDirectory(input));
        const format = execFormatInSystemMessage ? EXEC_FORMAT_TURN_REMINDER_SHORT : EXEC_FORMAT_TURN_REMINDER_FULL;
        return { additionalContext: recovery ? `${format}\n${recovery}` : format };
    },

    onPreToolUse: async (input) => {
        const name = String((input && input.toolName) || "").toLowerCase();
        const args = toolArgsOf(input);
        // Forward the session's working directory so the guards resolve the correct repo/branch
        // even when a relative path is supplied and the extension's own cwd differs (a relative
        // path with a cwd mismatch would otherwise let main-guard resolve no repo and fail OPEN).
        const cwd = contextRecovery.rememberDirectory(input);
        const recovery = await contextRecovery.takeRecovery(cwd);
        const finish = (decision) => recovery ? { ...decision, additionalContext: recovery } : decision;
        // Sensitive knowledge never leaves the machine: refuse host-native memory writes
        // outright. This is a hard deny (not "ask") because there is no legitimate case —
        // the durable store is the local vault, and a prompt would only invite a mistake.
        if (MEMORY_TOOLS.has(name)) {
            return finish({
                permissionDecision: "deny",
                permissionDecisionReason:
                    `roberdan-os: '${name}' writes to a vendor-hosted memory store. Durable memory stays local — ` +
                    `write a note under ~/Obsidian/Roberdan's Vault/agent-learnings/ instead (type: agent-learning).`,
            });
        }
        if (WRITE_TOOLS.has(name)) {
            const fp = writePathOf(args);
            return finish(await applyGuard("main-guard.sh", { tool_input: { file_path: String(fp) } }, cwd));
        }
        if (SHELL_TOOLS.has(name)) {
            const cmd = args.command || args.cmd || "";
            return finish(await applyGuard("bash-guard.sh", { tool_input: { command: String(cmd) } }, cwd));
        }
        return finish(undefined);
    },

    onPostToolUse: async (input) => {
        const cwd = input && input.workingDirectory;
        const name = String((input && input.toolName) || "").toLowerCase();
        // Doorbell first, but only for tools that can change bus/repo state — Claude wires
        // bus-doorbell.sh on PostToolUse with matcher "Bash|Edit|Write", not "*": a read-only
        // turn (view/search/…) cannot make the bus state stale, so it doesn't pay the ~0.55s
        // doorbell cost either. Parity with Claude means matching that filter, not ignoring it.
        if (WRITE_TOOLS.has(name) || SHELL_TOOLS.has(name)) await ringDoorbell(cwd);

        if (!WRITE_TOOLS.has(name)) return undefined;
        const args = toolArgsOf(input);
        const fp = writePathOf(args);
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
        // Best effort on graceful exit; crashes may never deliver this callback.
        if (auditObserver) await auditObserver.stop();
        const p = join(HOOKS, "auto-checkpoint.sh");
        if (existsSync(p)) await runScript(p, hookPayload(input && input.workingDirectory), input && input.workingDirectory);
        // Say goodbye on the agent bus, so whoever arrives next is not addressing
        // a session that is gone. This is the counterpart of the `hello` that
        // context-inject.sh writes at SessionStart, and it is deliberately wired
        // HERE and not on onAgentStop/Stop: those fire at the end of every turn,
        // and a session that declared itself finished after every turn would be a
        // presence view made entirely of ghosts.
        // BEST EFFORT, AND IT IS ONLY THAT: a crash, a kill or a closed lid never
        // delivers this callback. So a declared presence that is never withdrawn
        // is a normal state, which is exactly why `bus who` prints the
        // declaration next to the last observed action instead of believing it.
        // Claude runs the same script from its own SessionEnd (bin/sync.sh).
        const bye = join(HOOKS, "bus-bye.sh");
        if (existsSync(bye)) await runScript(bye, hookPayload(input && input.workingDirectory), input && input.workingDirectory);
        return undefined;
    },

    onAgentStop: async (input) => {
        if (input && input.sessionId && input.sessionId !== sessionId()) return undefined;
        agentStopObserved = true;
        const cwd = contextRecovery.rememberDirectory(input);
        const checkpoint = join(HOOKS, "auto-checkpoint.sh");
        if (existsSync(checkpoint)) {
            const saved = await runScript(checkpoint, hookPayload(cwd), cwd);
            if (saved.code !== 0 || saved.stderr) await warn("checkpoint", saved.stderr || `exit ${saved.code}`);
        }
        if (userPauseRequested) {
            diag("onAgentStop", JSON.stringify({ sessionId: sessionId(), decision: "allow", paused: true }));
            return undefined;
        }
        const gate = join(HOOKS, "goal-gate.sh");
        if (!existsSync(gate)) {
            await warn("continuation", "No queue continuation check installed; unfinished work is NOT protected. Checkpointing cannot restart it.");
            return undefined;
        }
        const { code, stdout, stderr } = await runScript(gate, hookPayload(cwd), cwd);
        const reason = `${stdout || ""}${stderr || ""}`.trim();
        diag("onAgentStop", JSON.stringify({
            sessionId: sessionId(), gateExit: code, decision: code === 2 && reason ? "block" : "allow",
        }));
        if (code === 2 && reason) {
            return {
                decision: "block",
                reason: "Observed onAgentStop: continue the authorized queue in this live CLI runtime only. " +
                    "Respect human gates, two no-progress rounds and the restart budget; no shutdown/reboot survival.\n" + reason,
            };
        }
        if (code !== 0) await warn("continuation", `Queue continuation could not be evaluated (exit ${code}); no restart requested. ${reason}`);
        else if (reason) await warn("continuation", `Continuation stopped (queue brake): ${reason}`);
        return undefined;
    },
}, { root: RDA_OS, sessionId, notify: (message) => warn("skills", message) });
// --- join --------------------------------------------------------------------

try {
    // Join once: retrying would put two JSON-RPC readers on stdin. A rejected join stays inert.
    const systemMessage = execFormatSystemMessage();
    session = await joinSession(systemMessage ? { tools, hooks, systemMessage } : { tools, hooks });
    execFormatInSystemMessage = Boolean(systemMessage); // after join: a throw leaves the long form
    auditObserver = createAuditObserver({ root: RDA_OS, sessionId: sessionId() });
    auditObserver.register(session);
    // Idle remains advisory. Only the typed onAgentStop return asks the runtime to continue.
    session.on("session.idle", (event) => {
        if (event && event.agentId) return;
        return runStopChain(contextRecovery.directory).catch((e) => diag("session.idle:runStopChain", e));
    });
    contextRecovery.register(session);
    // Host plugin reconciliation can restart us repeatedly; readiness belongs in the extension log.
    diag("lifecycle", "extension ready (tools, guards, checkpoint).");
} catch (e) {
    // stdout is reserved for JSON-RPC; diagnostics go to stderr and never crash the CLI.
    process.stderr.write(`roberdan-os extension failed to join session: ${e && e.stack ? e.stack : e}\n`);
}
