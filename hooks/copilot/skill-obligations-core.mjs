import { createHash } from "node:crypto";
import { constants, closeSync, existsSync, fstatSync, mkdirSync, openSync, readFileSync,
    renameSync, rmdirSync, unlinkSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { isAbsolute, join, resolve } from "node:path";

export const ROUTES = Object.freeze({
    "film-director": "skills/film-director/skill.md",
    "apple-designer": "skills/apple-designer/skill.md",
});
export const RETRIES = 2;
const PAUSE = /^(?:stop|pause|pausa|fermati|metti in pausa|devo andare|vado|cancel|annulla)[.!?\s]*$/iu;
const ACTION = /^\s*(?:(?:please|per favore)[,\s]+)?(?:prepara|crea|scrivi|descrivi|progetta|realizza|produci|rivedi|modifica|monta|create|write|describe|design|produce|make|review|edit|build)\b/iu;
const NOTIFICATION = /^\s*<(?:task-notification|teammate-message|system[-_]notification|system[-_]reminder)\b/iu;
const VIDEO = /\b(?:video|film|trailer|storyboard|animazione|animation|moving.image|motion.design|spot)\b|\.(?:mp4|mov)\b/iu;
const APPLE = /\b(?:iphone|ipad|macos|ios|ipados|watchos|tvos|visionos|swiftui|uikit|appkit|apple.watch)\b/iu;
const UI = /\b(?:ui|ux|schermat\w*|interfacci\w*|screen|interface|layout|view|app|application|applicazion\w*)\b/iu;
const NEGATED = /\b(?:non|don't|do not|no need to)\s+(?:\w+\s+){0,2}(?:creare|crea|produrre|produci|scrivere|scrivi|realizzare|make|create|produce|write|design|build)\b[^.!?;\n]*/giu;

// Bounded explicit Italian/English requests, not a semantic classifier of every paraphrase.
export function classify(prompt) {
    if (typeof prompt !== "string" || prompt.length > 32768) throw Error("invalid_prompt");
    if (PAUSE.test(prompt.trim()) || NOTIFICATION.test(prompt)) return [];
    const text = prompt.replace(NEGATED, "").replace(/\b(?:rdos-)?(?:film-director|apple-designer)\b/giu, "");
    if (!ACTION.test(text)) return [];
    const routes = [];
    const backend = /\b(?:backend|back.end|server|database|api|background.sync)\b/iu.test(text);
    if (VIDEO.test(text) && (!backend || /\b(?:concept|trailer|storyboard|film|montaggio|animation)\b/iu.test(text))) {
        routes.push("film-director");
    }
    if (APPLE.test(text) && UI.test(text) && (!backend || /\b(?:ui|ux|schermat\w*|interface|interfacci\w*|layout)\b/iu.test(text))) {
        routes.push("apple-designer");
    }
    return routes;
}

function empty() {
    return { required: [], receipts: {}, blocks: 0, paused: false };
}

function valid(state) {
    return state && Array.isArray(state.required) && state.required.length <= 2 &&
        state.required.every((name) => Object.hasOwn(ROUTES, name)) &&
        state.receipts && typeof state.receipts === "object" && !Array.isArray(state.receipts) &&
        Object.entries(state.receipts).every(([name, source]) => state.required.includes(name) &&
            ["native_skill", "canonical_read"].includes(source)) &&
        Number.isInteger(state.blocks) && state.blocks >= 0 && state.blocks <= RETRIES &&
        typeof state.paused === "boolean" &&
        Object.keys(state).sort().join() === "blocks,paused,receipts,required";
}

function pending(state) {
    return state.required.filter((name) => !state.receipts[name]);
}

function guidance(state, root) {
    return "[RDA mandatory skill checkpoint]\nBefore continuing this request, load the required guidance: " +
        pending(state).map((name) => `${name} (or rdos-${name}, ONLY if actually declared by this host)`).join("; ") +
        ". Prefer the host's Skill tool with its exact declared name. If unavailable, read the FULL canonical file: " +
        pending(state).map((name) => join(root, ROUTES[name])).join("; ") +
        ". A canonical read is a fallback, not a Skill invocation. Then finish the original request. " +
        "If access is unavailable, explicitly report INCOMPLETE; do not claim the requirement was satisfied.";
}

function receipt(input, state, root) {
    if (input.success !== true || !input.args || typeof input.args !== "object") return;
    const name = String(input.toolName || "").toLowerCase();
    for (const route of pending(state)) {
        if (name === "skill" && [route, `rdos-${route}`].includes(input.args.skill)) {
            state.receipts[route] = "native_skill";
        } else if (["read", "view"].includes(name)) {
            const path = input.args.file_path ?? input.args.path;
            if (typeof path !== "string" || !isAbsolute(path)) continue;
            const canonical = join(root, ROUTES[route]);
            if (resolve(path) !== resolve(canonical) || !existsSync(canonical)) continue;
            const lines = readFileSync(canonical, "utf8").split("\n").length;
            const range = input.args.view_range;
            const complete = name === "read"
                ? (input.args.offset === undefined || input.args.offset === 1) &&
                    (input.args.limit === undefined ? lines <= 2000 : input.args.limit >= lines)
                : range === undefined
                    ? (Buffer.byteLength(readFileSync(canonical)) <= 20000 || input.args.forceReadLargeFiles === true)
                    : Array.isArray(range) && range[0] === 1 && (range[1] === -1 || range[1] >= lines);
            if (complete) state.receipts[route] = "canonical_read";
        }
    }
}

function transition(input, state, root) {
    if (input.event === "prompt") {
        if (typeof input.prompt === "string" && NOTIFICATION.test(input.prompt)) {
            return { state, output: { status: "notification" } };
        }
        // Native stop feedback is a follow-up user message, not a new user request.
        if (pending(state).length && input.prompt === guidance(state, root)) return { state, output: {} };
        state = { ...empty(), required: classify(input.prompt), paused: PAUSE.test(input.prompt.trim()) };
    } else if (input.event === "post") {
        receipt(input, state, root);
    }
    const missing = pending(state);
    const output = { status: state.paused ? "paused" : missing.length ? "required" :
        state.required.length ? "fulfilled" : "inactive", receipts: state.receipts, blocks: state.blocks };
    if (!missing.length) return { state, output };
    if (input.event === "prompt") output.context = guidance(state, root);
    if (input.event === "pre") {
        const tool = String(input.toolName || "").toLowerCase();
        // Read/discovery retain the host's own permissions; no tool is granted approval here.
        if (!["skill", "read", "view", "glob", "rg", "grep"].includes(tool)) output.deny = guidance(state, root);
    }
    if (input.event === "stop") {
        if (state.blocks < RETRIES) {
            state.blocks++;
            output.block = guidance(state, root);
            output.notice = "INCOMPLETE: mandatory guidance not yet observed for " + missing.join(", ") +
                `; bounded retry ${state.blocks}/${RETRIES}.`;
        } else {
            output.status = "incomplete";
            output.warning = "INCOMPLETE: mandatory guidance was not observed for " + missing.join(", ") +
                ". The bounded skill check has stopped retrying; no successful load/read is claimed.";
        }
        output.blocks = state.blocks;
    }
    return { state, output };
}

export async function enforceSkillObligations(input, { root, home = process.env.RDA_HOME || join(homedir(), ".roberdan-os") }) {
    if (!["copilot", "claude"].includes(input.host) || typeof input.sessionId !== "string" ||
        !/^[A-Za-z0-9_.:-]{1,256}$/.test(input.sessionId) ||
        !["prompt", "pre", "post", "stop", "end"].includes(input.event)) throw Error("invalid_obligation_event");
    root = resolve(root);
    const directory = join(home, "skill-obligations");
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    const key = createHash("sha256").update(`${input.host}\0${root}\0${input.sessionId}`).digest("hex");
    const file = join(directory, key + ".json"), lock = join(directory, key + ".lock");
    let acquired = false;
    for (let retry = 0; retry < 20; retry++) {
        try { mkdirSync(lock, { mode: 0o700 }); acquired = true; break; } catch (error) {
            if (error.code !== "EEXIST") throw Error("obligation_state_unavailable");
            await new Promise((done) => setTimeout(done, 10));
        }
    }
    if (!acquired) throw Error("obligation_state_busy");
    try {
        let state = empty();
        if (existsSync(file)) {
            const fd = openSync(file, constants.O_RDONLY | constants.O_NOFOLLOW);
            try {
                if (fstatSync(fd).size > 2048) throw Error("invalid_obligation_state");
                state = JSON.parse(readFileSync(fd, "utf8"));
            } finally { closeSync(fd); }
            if (!valid(state)) throw Error("invalid_obligation_state");
        }
        if (input.event === "end") {
            // An end callback is not proof that the host will not deliver stop feedback next.
            if (pending(state).length) return { status: "required", receipts: state.receipts, blocks: state.blocks };
            if (existsSync(file)) unlinkSync(file);
            return { status: "ended" };
        }
        const result = transition(input, state, root);
        const temp = file + ".tmp";
        const fd = openSync(temp, constants.O_CREAT | constants.O_TRUNC | constants.O_WRONLY | constants.O_NOFOLLOW, 0o600);
        try { writeFileSync(fd, JSON.stringify(result.state)); } finally { closeSync(fd); }
        renameSync(temp, file);
        return result.output;
    } finally { rmdirSync(lock); }
}
