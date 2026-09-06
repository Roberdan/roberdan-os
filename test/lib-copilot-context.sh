# shellcheck shell=bash
# Sourced by test-copilot-adapter.sh: reuse its isolated SDK/import fixtures.
section "context lifecycle — measured saves, bounded one-shot recovery, guards preserved"
CTX_OS="$TMP/context-os"; mkdir -p "$CTX_OS/hooks"
CTX_COUNT="$TMP/context-count"; : > "$CTX_COUNT"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$PWD" >> "$RDA_TEST_COUNTER"\n' > "$CTX_OS/hooks/auto-checkpoint.sh"
printf '#!/usr/bin/env bash\necho '\''{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"test guard"}}'\''\n' > "$CTX_OS/hooks/main-guard.sh"
cat > "$TMP/context-kb" <<'SH'
#!/usr/bin/env bash
[ "$1" = resume ] && [ "$2" = --context ] || exit 2
case "${RDA_TEST_RESUME_MODE:-ok}" in
  fail) echo "checkpoint unavailable" >&2; exit 2 ;;
  large) awk 'BEGIN {for(i=0;i<20000;i++) printf "x"}' ;;
  *) echo "UNVERIFIED capsule: goal-7; approval-required; agent-7; artifact@old-revision; owned-worktree" ;;
esac
SH
chmod +x "$TMP/context-kb"
cat > "$STAGE/driver-context.mjs" <<'JS'
import assert from "node:assert/strict";
import { readFileSync, realpathSync } from "node:fs";
import "./extension.mjs";
const hooks = globalThis.__RDA_CFG.hooks;
const events = globalThis.__H;
const usage = events["session.usage_info"];
const start = events["session.compaction_start"];
const complete = events["session.compaction_complete"];
const count = () => readFileSync(process.env.RDA_TEST_COUNTER, "utf8").trim().split("\n").filter(Boolean).length;
assert.equal(typeof usage, "function");
assert.equal(typeof start, "function");
assert.equal(typeof complete, "function");
await hooks.onUserPromptSubmitted({ workingDirectory: process.env.RDA_TEST_CWD });
for (const data of [{}, {currentTokens: 90, tokenLimit: 0},
                    {currentTokens: "90", tokenLimit: 100},
                    {currentTokens: -1, tokenLimit: 100},
                    {currentTokens: 64, tokenLimit: 100}]) await usage({data});
await usage({agentId:"child", data:{currentTokens:90, tokenLimit:100}});
assert.equal(count(), 0, "invalid, below threshold or child usage must not save");
for (let i=0;i<200;i++) await usage({data:{currentTokens:80,tokenLimit:100}});
assert.equal(count(), 1, "200 pressure events save once, not 200 times");
assert.equal(realpathSync(readFileSync(process.env.RDA_TEST_COUNTER,"utf8").trim()), realpathSync(process.env.RDA_TEST_CWD));
await usage({data:{currentTokens:40,tokenLimit:100}});
await usage({data:{currentTokens:65,tokenLimit:100}});
assert.equal(count(), 2, "lower usage rearms the measured save");
await start({agentId:"child",data:{}});
assert.equal(count(), 2);
await start({data:{}});
assert.equal(count(), 3);
complete({data:{success:false}});
assert.equal(await hooks.onPreToolUse({toolName:"view"}), undefined);
complete({agentId:"child",data:{success:true}});
assert.equal(await hooks.onPreToolUse({toolName:"view"}), undefined);
for (let i=0;i<20;i++) {
  complete({data:{success:true}});
  const r = await hooks.onPreToolUse({toolName:"edit",toolArgs:{path:"x"}});
  assert.equal(r.permissionDecision,"deny","recovery must not weaken an existing guard");
  for (const marker of ["goal-7","approval-required","agent-7","artifact@old-revision","owned-worktree"])
    assert.ok(r.additionalContext.includes(marker), marker);
  assert.ok(r.additionalContext.length < 17408);
  assert.equal(await hooks.onPreToolUse({toolName:"view"}), undefined, "only once per compact");
}
complete({data:{success:true}});
assert.ok((await hooks.onUserPromptSubmitted({})).additionalContext.includes("goal-7"));
assert.ok(!(await hooks.onUserPromptSubmitted({})).additionalContext.includes("goal-7"));
for (const mode of ["fail","large"]) {
  process.env.RDA_TEST_RESUME_MODE=mode;
  complete({data:{success:true}});
  const r = await hooks.onPreToolUse({toolName:"view"});
  assert.ok(r.additionalContext.includes("could not be loaded safely"));
  assert.ok(r.additionalContext.length < 400, "reject huge output rather than inject it");
}
console.log("PASS: repeated compaction recovers bounded state without replay or guard changes");
JS
if (cd "$STAGE" && RDA_OS="$CTX_OS" RDA_KB_CMD="$TMP/context-kb" RDA_TEST_COUNTER="$CTX_COUNT" \
    RDA_TEST_CWD="$MREPO" node driver-context.mjs >"$TMP/context-result" 2>"$TMP/context-stderr"); then
  ok "200 usage events + 20 compactions: bounded recovery, preserved guards/IDs/revisions, failure paths"
else
  err "context lifecycle regression"
  cat "$TMP/context-result" "$TMP/context-stderr"
fi
