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
    doctor: process.env.PROBE_DOCTOR === "1"
        ? await globalThis.config.tools.find((tool) => tool.name === "roberdanos_doctor").handler()
        : null,
}));
JS

RDA_OS="$ROOT" STAGE="$STAGE" node --input-type=module <<'JS'
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { join } from "node:path";
import { mkdirSync, writeFileSync } from "node:fs";

function launch(fail = false, env = {}) {
    const result = spawnSync(process.execPath, [join(process.env.STAGE, "driver.mjs")], {
        env: { ...process.env, FAIL_JOIN: fail ? "1" : "0", ...env },
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

const home = join(process.env.STAGE, "doctor-home");
const root = join(process.env.STAGE, "doctor-root");
mkdirSync(home);
mkdirSync(root);
const doctorEnv = { HOME: home, RDA_OS: root, PROBE_DOCTOR: "1" };
const missing = launch(false, doctorEnv).output.doctor;
assert.match(missing, /MISS/);
assert.match(missing, /Remediation:/);
for (const directory of [".copilot/agents", ".copilot/skills/test",
                         ".copilot/extensions/roberdan-os"]) {
    mkdirSync(join(home, directory), { recursive: true });
}
writeFileSync(join(home, ".copilot/agents/test.md"), "# fixture");
writeFileSync(join(home, ".copilot/extensions/roberdan-os/extension.mjs"), "// fixture");
writeFileSync(join(home, ".copilot/mcp-config.json"),
              '{"gbrain": {"secret": "doctor-must-not-print-this"}}');
writeFileSync(join(root, "AGENTS.md"), "# fixture");
mkdirSync(join(root, "hooks"));
writeFileSync(join(root, "hooks/context-inject.sh"), "#!/bin/sh\nexit 0\n");
const present = launch(false, doctorEnv).output.doctor;
assert.doesNotMatch(present, /MISS|All roberdan-os.*wiring present/);
assert.match(present, /Installation files present/);
for (const result of [missing, present]) {
    assert.match(result, /Runtime agent\/skill discovery and MCP connectivity are NOT verified/);
    assert.match(result, /reload extensions/);
    assert.doesNotMatch(result, /doctor-must-not-print-this/);
}
console.log("test-copilot-startup: PASS (reloads, failed join, hooks/tools, doctor scope)");
JS
