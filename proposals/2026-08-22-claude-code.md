# Proposal — 2026-08-22 — claude-code

## Source citation (URL + version + date)

- Changelog: <https://cdn.jsdelivr.net/gh/anthropics/claude-code@main/CHANGELOG.md> (fetched 2026-08-28).
- Release metadata: <https://api.github.com/repos/anthropics/claude-code/releases?per_page=20> (fetched 2026-08-28).
- Baseline: `proposals/2026-08-08-claude-code.md` assessed through **v2.1.238** (published 2026-08-20).
- New versions assessed: **v2.1.239** (2026-08-21) through **v2.1.250** (2026-08-28). Versions 2.1.240, 2.1.241 are bug-fix-only per changelog; 2.1.245 is a Linux glibc crash fix. Dates from GitHub release metadata where available; v2.1.243 is changelog-only (not separately published as a GitHub release between v2.1.241 on 2026-08-23 and v2.1.245 on 2026-08-25).

## Already assessed and skipped

The declined buffer items from all prior proposals stay declined. The card body carried items through v2.1.238 — none of those changelog entries show material change in this range:

- v2.1.238 self-hosted-runner defer/proxy and cross-session `notify_when_idle`/backpressure (declined 2026-08-21): v2.1.248 adds `--client-label` to self-hosted runner and extends cross-session messaging to Bedrock/Vertex/Foundry; these remain unrelated to today's launchd + `claude -p` factory and to the bus-protocol ledger.
- v2.1.233 Claude native todo tools disabled by default (declined 2026-08-21): v2.1.248 adds no new signals; `kb` remains the sole durable ledger.

## Novelties + impact

### 1. v2.1.247 — `claude -p` (headless) sessions now auto-continue after a mid-stream API cutoff

**Evidence.** v2.1.247 says: "Improved non-interactive sessions (`-p`, SDK, cloud sessions) to automatically continue a response cut off mid-stream by a server error, connection loss, or stall instead of ending with an error."

**Impact on roberdan-os.** The factory (`factory/run.sh` line 84–87, `factory/lib.sh` line 144–147) runs every task and verification job as `claude -p ... --model <model> --dangerously-skip-permissions`. Previously, a mid-stream cutoff terminated the process with an error, logged to the job's `LOG` directory, and the job moved to `FAILED`. From v2.1.247, the same scenario auto-recovers. This is a reliability improvement — factory jobs are less likely to land in `FAILED` on transient API issues. No code change is needed.

`factory/factory-protocol.md` § error handling says a failure surfaces in the log and the job goes to `FAILED/`. That description is still accurate for hard errors, but silent about mid-stream recoveries. The doc doesn't need to change urgently, but a clarifying note would prevent future confusion.

**Suggested patch, awaiting Roberto.** One-line addition to `factory/factory-protocol.md` under the error-handling section: note that since claude-code ≥ 2.1.247, mid-stream API cutoffs auto-recover in `-p` mode; only hard failures (non-zero exit) reach `FAILED/`. No behavior change — documentation update only.

### 2. v2.1.248 — `experimental.cacheTtl` in agent frontmatter for per-agent prompt cache TTL

**Evidence.** v2.1.248 says: "Added `experimental.cacheTtl` (`"5m"` or `"1h"`) to agent frontmatter: a per-agent prompt cache TTL used when no subagent TTL setting is configured."

**Impact on roberdan-os.** Every file under `agents/` declares Claude frontmatter (confirmed: `agents/baccio.md`, `agents/thor.md`, etc. all carry `name`, `model`, `effort`, `tools`, `providers` keys). None currently declares `cacheTtl`. The expensive agents — `baccio` (opus/high), `luca` (opus), `socrates` (opus), `twin` (opus) — have substantial system prompts that are re-rendered at every subagent invocation. Adding `cacheTtl: "1h"` to these agents would extend the prompt cache window from the API default (5 min) to 1 hour, reducing cost on sessions where the same agent is invoked repeatedly (typical in a review loop or a long card).

**Grounding.** Searched `agents/` for any existing `cacheTtl` key → none found. The frontmatter is Claude-specific (field is consumed by Claude Code when running an `--agent` session or a factory subagent). Copilot and Codex ignore unknown frontmatter keys (the `providers:` key already handles this split).

**Suggested patch, awaiting Roberto.**

Add `cacheTtl: "1h"` to the frontmatter of the four expensive agents:

```diff
--- a/agents/baccio.md
+++ b/agents/baccio.md
@@ -3,6 +3,7 @@ name: baccio
 model: "opus"
 effort: "high"
 tools: Read, Write, Bash, Grep, Glob, WebSearch, WebFetch
+cacheTtl: "1h"
```

Same one-liner for `luca.md`, `socrates.md`, `twin.md`. The lighter agents (`thor`, `rex`, `coach`, `wanda`, `board`) are sonnet/lower-effort and invoked for shorter tasks; leave them at the default (5 min) for now.

Citation: changelog v2.1.248, published 2026-08-27.

### 3. v2.1.243 — `promptCacheTtl` and `subagentPromptCacheTtl` settings for the main session and its subagents

**Evidence.** v2.1.243 says: "Added `promptCacheTtl` and `subagentPromptCacheTtl` settings so API-key and cloud-provider users can keep a 1-hour prompt cache on the main conversation while subagents stay at 5 minutes."

**Impact on roberdan-os.** The generated `platforms/claude/settings-hooks.json` (built by `bin/sync.sh`) feeds `~/.claude/settings.json`. Neither that file nor `~/.claude/settings.json` currently declares `promptCacheTtl` (confirmed: checked the live `~/.claude/settings.json` — no matching keys). Setting `promptCacheTtl: "1h"` in the user settings would extend the main session's cache to 1 hour, reducing cost on long cards. Setting `subagentPromptCacheTtl: "5m"` explicitly pins subagents to the narrow window (avoids accidental spillover).

This complements proposal 2 above: `cacheTtl` in agent frontmatter overrides the setting only for that agent's session; the setting governs the default for everything else.

**Suggested patch, awaiting Roberto.** Add to the generated settings snippet in `bin/sync.sh` (or to `platforms/claude/settings-hooks.json` directly, whichever is canonical):

```json
"promptCacheTtl": "1h",
"subagentPromptCacheTtl": "5m"
```

This goes in the user settings file, not the repo — it is per-machine. The right place is `platforms/claude/settings-hooks.json` so `--install` keeps it applied, and the generated file (gitignored) carries it to `~/.claude/settings.json`.

Citation: changelog v2.1.243, between 2026-08-23 and 2026-08-25.

### 4. v2.1.248 — Hook JSON parse errors now surfaced as errors (not silently passed as plain text)

**Evidence.** v2.1.248 says: "Fixed hooks silently treating a stdout `{…}` object that isn't valid JSON as plain text; it's now reported as a hook error with the parse message."

**Impact on roberdan-os.** Searched `hooks/` for JSON-emitting hooks. Confirmed: `hooks/bash-guard.sh` generates all `deny`/`ask` decisions with `jq -cn '{hookSpecificOutput:{…}}'`. Well-formed JSON via `jq` — this fix does not break anything today. It is a monitor point: if any future hook emits a hand-rolled `{…}` string (e.g. with `echo`) and that string has a typo, Claude Code will now surface the error instead of treating it as allowed text. The fix is defensive for us.

**Suggested patch.** None. Existing hooks use `jq` correctly. Worth including in the next hooks health check.

### 5. v2.1.248 — `--restricted` flag: removes run/code/WebFetch tools and restricts writes to CWD

**Evidence.** v2.1.248 says: "Added `--restricted` (or `CLAUDE_CODE_RESTRICTED=1`): removes the built-in tools that run commands or code and `WebFetch` (unless named in `--tools`), keeps file tools inside the working directory, refuses `bypassPermissions`, and ignores user, project and local settings files."

**Impact on roberdan-os.** The factory currently runs `claude -p … --dangerously-skip-permissions` — the opposite pole. `--restricted` is relevant as a future hardening option for read-only verification jobs in the factory (e.g. `lib.sh` verification runs which only need to read outputs, not execute code). It was proposed as a design note in the previous assessment of sandbox hardening (v2.1.232-v2.1.224, declined 2026-08-21). Nothing changes today.

**Suggested patch.** None now. If Roberto wants to harden verification jobs, `--restricted` is the right lever and replaces the current `--dangerously-skip-permissions` on the `lib.sh` verification path. That would be a separate card.

## Applied vs awaiting Roberto

Applied in this PR: this proposal document only.

Awaiting Roberto:

1. One-line note in `factory/factory-protocol.md`: mid-stream cutoffs auto-recover in `-p` mode since v2.1.247. Documentation only.
2. `cacheTtl: "1h"` added to `agents/baccio.md`, `agents/luca.md`, `agents/socrates.md`, `agents/twin.md`.
3. `promptCacheTtl: "1h"` + `subagentPromptCacheTtl: "5m"` added to the platforms/claude settings snippet (applies to `~/.claude/settings.json` via `--install`).
4. Future factory hardening card: evaluate `--restricted` for verification-only jobs (`lib.sh` verification path) as a replacement for `--dangerously-skip-permissions`.
