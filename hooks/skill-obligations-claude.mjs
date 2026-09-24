#!/usr/bin/env node
// Claude Code hooks reference: UserPromptSubmit, success-only PostToolUse and bounded Stop.
import { fileURLToPath } from "node:url";
import { enforceSkillObligations } from "./copilot/skill-obligations-core.mjs";

const phases = { UserPromptSubmit: "prompt", PreToolUse: "pre", PostToolUse: "post",
    Stop: "stop", SessionEnd: "end" };
const warning = "INCOMPLETE: mandatory-skill enforcement is unavailable; no successful guidance load/read can be claimed.";
let raw;
try {
    let payload = "";
    for await (const chunk of process.stdin) {
        payload += chunk.toString();
        if (Buffer.byteLength(payload) > 65536) throw Error("oversized_input");
    }
    raw = JSON.parse(payload);
    if (raw.agent_id) process.exit(0);
    // Never read transcript_path, response content, or arbitrary files named in a callback.
    const output = await enforceSkillObligations({
        host: "claude", sessionId: raw.session_id, event: phases[raw.hook_event_name],
        prompt: raw.prompt, toolName: raw.tool_name, args: raw.tool_input,
        success: raw.hook_event_name === "PostToolUse",
    }, { root: process.env.RDA_OS || fileURLToPath(new URL("../", import.meta.url)) });
    const result = {};
    if (output.context) result.hookSpecificOutput = { hookEventName: raw.hook_event_name, additionalContext: output.context };
    if (output.deny) result.hookSpecificOutput = { hookEventName: "PreToolUse",
        permissionDecision: "deny", permissionDecisionReason: output.deny };
    if (output.block) Object.assign(result, { decision: "block", reason: output.block });
    if (output.notice || output.warning) result.systemMessage = output.notice || output.warning;
    if (Object.keys(result).length) process.stdout.write(JSON.stringify(result));
    if (output.status !== "inactive" && output.status !== "ended") {
        process.stderr.write("[roberdan-os skills] " + JSON.stringify({
            event: phases[raw.hook_event_name], status: output.status, receipts: output.receipts, blocks: output.blocks,
        }) + "\n");
    }
} catch (error) {
    process.stderr.write("[roberdan-os skills] enforcement_unavailable\n");
    const result = { systemMessage: warning };
    if (raw?.hook_event_name === "PreToolUse") result.hookSpecificOutput = {
        hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: warning,
    };
    process.stdout.write(JSON.stringify(result));
}
