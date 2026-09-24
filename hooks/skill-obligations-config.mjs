#!/usr/bin/env node
// Extend generated Claude settings; never reads or modifies installed user settings.
import { readFileSync, writeFileSync } from "node:fs";

const file = process.argv[2];
const settings = JSON.parse(readFileSync(file, "utf8"));
for (const event of ["UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "SessionEnd"]) {
    const entry = { hooks: [{ type: "command",
        command: "node $RDA_OS/hooks/skill-obligations-claude.mjs", timeout: 5 }] };
    if (event === "PreToolUse" || event === "PostToolUse") entry.matcher = "*";
    (settings.hooks[event] ??= []).push(entry);
}
writeFileSync(file, JSON.stringify(settings, null, 2) + "\n");
