// Typed lifecycle events in Copilot CLI 1.0.84-1; no model calls or model/limit changes.
import { existsSync } from "node:fs";
import { join } from "node:path";

export function createContextRecovery({ hooksDirectory, runScript, runKb, hookPayload, diag }) {
    let directory = process.cwd();
    let pressureSaved = false;
    let recoveryPending = false;
    let checkpointInFlight;

    function rememberDirectory(input) {
        if (input && input.workingDirectory) directory = input.workingDirectory;
        return directory;
    }

    function checkpoint() {
        if (checkpointInFlight) return checkpointInFlight;
        checkpointInFlight = (async () => {
            const script = join(hooksDirectory, "auto-checkpoint.sh");
            if (!existsSync(script)) {
                diag("context-checkpoint", "auto-checkpoint.sh is not installed");
                return;
            }
            const { code, stderr } = await runScript(script, hookPayload(directory), directory);
            if (code !== 0 || stderr) diag("context-checkpoint", stderr || `exit ${code}`);
        })().finally(() => { checkpointInFlight = undefined; });
        return checkpointInFlight;
    }

    async function takeRecovery(cwd) {
        if (!recoveryPending) return "";
        recoveryPending = false;
        await checkpointInFlight;
        const { code, stdout, stderr } = await runKb(["resume", "--context"], cwd);
        if (code !== 0 || Buffer.byteLength(stdout, "utf8") > 17408) {
            diag("context-recovery", stderr || `exit ${code}; recovery output rejected`);
            return "Context was compacted, but the durable checkpoint could not be loaded safely. Read kb resume and the current card before further effects; do not infer completed work.";
        }
        return stdout.trim();
    }

    function register(session) {
        session.on("session.usage_info", (event) => {
            if (!event || event.agentId) return;
            const { currentTokens, tokenLimit } = event.data || {};
            if (!Number.isFinite(currentTokens) || currentTokens < 0 ||
                !Number.isFinite(tokenLimit) || tokenLimit <= 0) return;
            const ratio = currentTokens / tokenLimit;
            if (ratio < 0.5) pressureSaved = false;
            if (ratio >= 0.65 && !pressureSaved) {
                pressureSaved = true;
                return checkpoint().catch((e) => diag("session.usage_info:checkpoint", e));
            }
        });
        session.on("session.compaction_start", (event) => {
            if (!event || event.agentId) return;
            return checkpoint().catch((e) => diag("session.compaction_start:checkpoint", e));
        });
        session.on("session.compaction_complete", (event) => {
            if (!event || event.agentId) return;
            if (event.data && event.data.success === true) recoveryPending = true;
            else diag("session.compaction_complete", "compaction did not succeed; checkpoint retained");
        });
    }

    return { rememberDirectory, takeRecovery, register, get directory() { return directory; } };
}
