# Proposal — 2026-08-08 — claude-code

## Source citation (URL + version + date)

- Changelog: <https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md> (checked 2026-08-21).
- Release metadata: <https://api.github.com/repos/anthropics/claude-code/releases?per_page=10> (checked 2026-08-21).
- Baseline: `proposals/2026-07-31-claude-code.md` assessed through **v2.1.220**.
- New versions assessed from the official changelog: **v2.1.223** through **v2.1.238**. GitHub release metadata verifies **v2.1.238** was published **2026-08-20T20:33:51Z**. The changelog itself does not carry per-version dates, so dates below come from the official GitHub release metadata where available; when not individually fetched, the version is cited without an invented date.

## Already assessed and skipped

The declined items carried by the card stay declined unless the source says something materially new:

- v2.1.218 background code-review, v2.1.217 budget caps, v2.1.216 sandbox/worktree fixes, v2.1.219 nested-subagent depth, v2.1.218 agent frontmatter hooks, v2.1.218 `context: fork`, and v2.1.219 `sandbox.network.strictAllowlist` / `workflowSizeGuideline` were already assessed in July. No new changelog text changes those decisions.

## Novelties + impact

### 1. v2.1.238 — plugin `headersHelper` can mint HTTP headers for marketplace/catalog/archive fetches

**Evidence.** v2.1.238 adds `headersHelper` on URL marketplaces or catalog entries; the helper runs a command to mint HTTP headers for catalog and same-origin archive fetches. The same entry says install/update prompts with `[y/N]` unless `-y` is passed. It also says MCP `headersHelper` in project `.mcp.json`, and inline MCP servers in project or `--add-dir` agent files, now require that folder's trust dialog, and project/plugin/agent helpers run without inherited credential environment variables.

**Impact on roberdan-os.** This touches the same surface as roberdan-os's supply-chain posture: skills, plugins, MCP, and generated wrappers. The repo does not currently package a Claude plugin marketplace, so there is no immediate behavior to change. If Roberto later promotes roberdan-os from generated per-client wrappers to a portable plugin, any helper command becomes executable supply-chain code and must be declared as a human-approved trust boundary.

**Suggested patch, awaiting Roberto.** Add a short rule to `rules/best-practices.md` or `evolve/evolve-protocol.md`: roberdan-os plugins/marketplaces may not use `headersHelper` unless the proposal names the exact command, the credential source, the network destination, and the revocation path. Do not auto-apply: it changes allowed future behavior.

### 2. v2.1.238 — `self-hosted-runner` gained graceful SIGTERM parking and proxy auth hooks

**Evidence.** v2.1.238 adds `claude self-hosted-runner --defer-shutdown-max-min <minutes>` and `--proxy-authorization-command` / `--proxy-authorization-file` for egress proxies that need fresh `Proxy-Authorization` headers.

**Impact on roberdan-os.** roberdan-os `factory/factory-protocol.md` is explicitly `claude -p` plus launchd and a durable queue, not Claude Code self-hosted runner. This is relevant if the dormant external runner path ever becomes a managed Claude runner, but it does not touch today’s factory commands.

**Suggested patch.** None now. Record as a design note only: if factory moves to self-hosted runner, evaluate `--defer-shutdown-max-min` so shutdown parks instead of losing attached sessions. No citation-free patch.

### 3. v2.1.236/v2.1.238 — cross-session messaging got one-shot idle notices and better refusal/backpressure errors

**Evidence.** v2.1.236 adds `notify_when_idle` to cross-session `SendMessage`; v2.1.238 says cross-session messaging now reports `refused` when a recipient refuses inbound messages and reports rate-limit/full-queue drops instead of silently succeeding.

**Impact on roberdan-os.** roberdan-os already owns multi-session coordination through `bus/bus-protocol.md`: bus messages are claims, opt-in, and never start anyone. Claude Code's `SendMessage` improvements overlap with the same problem but not the same durable ledger. The new `notify_when_idle` is useful for human ergonomics, but adopting it in canon would introduce a second messaging lane.

**Suggested patch, awaiting Roberto.** Add a proposal-only note to `bus/bus-protocol.md`: native same-machine `SendMessage notify_when_idle` may be used only as a transient nudge that points back to the bus thread; the bus remains the source of truth. Do not apply without Roberto because it changes coordination behavior.

### 4. v2.1.233 — todo/task-tracking tools are disabled by default on newer Claude models

**Evidence.** v2.1.233 says TaskCreate/Get/Update/List and TodoWrite are no longer available on Opus 4.8, Sonnet 5, Fable 5, Mythos 5 and newer models, unless `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` is set.

**Impact on roberdan-os.** roberdan-os uses `kb` card files as the durable goal ledger and explicitly avoids trusting per-tool task silos. This change reinforces the existing design: do not depend on Claude's native todo tools for kanban state.

**Suggested patch.** None. Keep `kb` as the single durable work ledger.

### 5. v2.1.232-v2.1.224 — sandbox, permission and trust hardening fixes

**Evidence.** v2.1.232 includes fixes for a PowerShell permission bypass, nested git repos inheriting parent trust, project-level sandbox binary override hardening, and Linux sandbox bypass hardening. v2.1.224 fixes trailing-slash sandbox deny bypasses, adds sandbox credential-masking options, and removes the 200-subagent spawn cap while preserving concurrency/depth limits.

**Impact on roberdan-os.** These entries touch security, subagents, and factory. The repo already documents the factory as bounded but not OS-sandboxed, clamps models, and uses `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` on Roberto's machine. No repo patch can safely assume a user's Claude Code sandbox settings. The important operational implication is to keep the factory documented as not sandboxed.

**Suggested patch.** None now. If Roberto wants a future hardening card, propose a separate audited design for sandbox settings, not a silent canon edit.

## Applied vs awaiting Roberto

Applied in this PR: this proposal document only.

Awaiting Roberto:

1. A future rule for plugin/marketplace `headersHelper` trust requirements in `rules/best-practices.md` or `evolve/evolve-protocol.md`.
2. A future `bus/bus-protocol.md` note on using native `SendMessage notify_when_idle` only as a transient pointer back to bus state.
3. A future factory design review if self-hosted runner replaces the current launchd + `claude -p` queue.
