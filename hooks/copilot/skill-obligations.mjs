import { enforceSkillObligations } from "./skill-obligations-core.mjs";

const unavailable = "INCOMPLETE: mandatory-skill enforcement is unavailable; no successful guidance load/read can be claimed.";
const phases = { onUserPromptSubmitted: "prompt", onPreToolUse: "pre",
    onPostToolUse: "post", onAgentStop: "stop", onSessionEnd: "end" };

function argumentsOf(raw) {
    if (typeof raw === "string") {
        if (raw.length > 65536) throw Error("oversized_arguments");
        raw = JSON.parse(raw);
    }
    return raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
}

export function withSkillObligations(hooks, { root, home, sessionId, notify }) {
    const wrapped = { ...hooks };
    let continuing = false;
    for (const [hook, event] of Object.entries(phases)) {
        wrapped[hook] = async (input = {}, invocation = {}) => {
            const sid = sessionId() || invocation.sessionId || input.sessionId;
            if (!sid || (input.sessionId && input.sessionId !== sid) ||
                (event === "prompt" && typeof input.prompt !== "string")) {
                return hooks[hook]?.(input, invocation);
            }
            if (event === "stop") continuing = false;
            let output;
            try {
                output = await enforceSkillObligations({
                    host: "copilot", sessionId: sid, event, prompt: input.prompt,
                    toolName: input.toolName, args: event === "post" ? argumentsOf(input.toolArgs) : undefined,
                    // This native hook is success-only; an explicit non-success never fulfills.
                    success: event === "post" && Boolean(input.toolResult) &&
                        (input.toolResult.resultType === undefined || input.toolResult.resultType === "success"),
                }, { root, home });
            } catch (error) {
                process.stderr.write("[roberdan-os skills] enforcement_unavailable\n");
                await notify(unavailable);
                if (event === "stop") return undefined;
                if (event === "pre") return { permissionDecision: "deny", permissionDecisionReason: unavailable };
                output = { context: unavailable };
            }
            if (output.status && !["inactive", "ended"].includes(output.status)) {
                process.stderr.write("[roberdan-os skills] " + JSON.stringify({
                    event, status: output.status, receipts: output.receipts, blocks: output.blocks,
                }) + "\n");
            }
            if (output.block) { continuing = true; await notify(output.notice); return { decision: "block", reason: output.block }; }
            if (output.warning) { await notify(output.warning); return undefined; }
            // The host emits end between retries; inherited cleanup would disable audit/bus.
            if (event === "end" && continuing && output.status === "required") return undefined;
            const prior = await hooks[hook]?.(input, invocation);
            if (output.deny) return { ...prior, permissionDecision: "deny", permissionDecisionReason: output.deny };
            if (output.context) return { ...prior,
                additionalContext: [prior?.additionalContext, output.context].filter(Boolean).join("\n") };
            return prior;
        };
    }
    return wrapped;
}
