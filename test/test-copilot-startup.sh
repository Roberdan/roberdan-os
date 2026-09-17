#!/usr/bin/env bash
# Repeated host reloads keep readiness in stderr, not in the conversation.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/node_modules/@github/copilot-sdk"
cp "$ROOT/hooks/copilot/extension.template.mjs" "$STAGE/extension.mjs"
cp "$ROOT/hooks/copilot/context-recovery.mjs" "$STAGE/context-recovery.mjs"
cp "$ROOT/hooks/copilot/audit.mjs" "$STAGE/audit.mjs"
cat > "$STAGE/node_modules/@github/copilot-sdk/package.json" <<'JSON'
{"type":"module","exports":{"./extension":"./extension.mjs"}}
JSON
cat > "$STAGE/node_modules/@github/copilot-sdk/extension.mjs" <<'JS'
export async function joinSession(config) {
    globalThis.config = config;
    if (process.env.FAIL_JOIN === "1") throw new Error("startup-test rejected join");
    return {
        sessionId: "same-session-across-reloads",
        on: () => () => {},
        log: async (text) => { globalThis.timeline.push(text); },
        rpc: {},
    };
}
JS
cat > "$STAGE/driver.mjs" <<'JS'
globalThis.timeline = [];
await import("./extension.mjs");
console.log(JSON.stringify({
    timeline: globalThis.timeline,
    tools: globalThis.config.tools.map((tool) => tool.name),
    hooks: Object.keys(globalThis.config.hooks),
}));
JS

RDA_OS="$ROOT" STAGE="$STAGE" node --input-type=module <<'JS'
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { join } from "node:path";

function launch(fail = false) {
    const result = spawnSync(process.execPath, [join(process.env.STAGE, "driver.mjs")], {
        env: { ...process.env, FAIL_JOIN: fail ? "1" : "0" },
        encoding: "utf8",
        timeout: 10000,
    });
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stderr);
    return { ...result, output: JSON.parse(result.stdout) };
}

for (let reload = 0; reload < 3; reload++) {
    const { output, stderr } = launch();
    assert.deepEqual(output.timeline, [], "startup must not add conversation notices");
    assert.equal((stderr.match(/\[roberdan-os\] lifecycle: extension ready/g) || []).length, 1);
    assert.equal(output.tools.length, 5);
    assert.ok(output.tools.includes("roberdanos_kanban"));
    for (const hook of ["onPreToolUse", "onPostToolUse", "onSessionEnd", "onAgentStop"]) {
        assert.ok(output.hooks.includes(hook), `missing ${hook}`);
    }
}
const failed = launch(true);
assert.deepEqual(failed.output.timeline, []);
assert.match(failed.stderr, /extension failed to join session: Error: startup-test rejected join/);
assert.doesNotMatch(failed.stderr, /extension ready/);
console.log("test-copilot-startup: PASS (3 fresh processes, failed join, hooks/tools retained)");
JS
