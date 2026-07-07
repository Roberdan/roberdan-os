# Multi-CLI / multi-model orchestration — research + plan (decided)

> **Status:** decided 2026-07-05 — CAO parked; Roberto chose federated kanban + sandboxed runners.
> **Superseded by v2.2.0** (shipped 2026-07-06; see CHANGELOG). Design of the chosen direction:
> `docs/plan-2026-07-05-federated-kanban-multi-cli.md`. The research/evidence below stands as the record.
> Question that triggered this: can each phase of a task use the best-suited CLI/model —
> e.g. Claude (Fable/Opus) to plan, Copilot CLI to execute, local Ollama (Qwen3/Kimi) to verify
> — instead of everything running through one tool?

## Verdict: yes, buildable, and don't build it from scratch

There is an actively maintained open-source project that already does almost exactly this:
**[AWS Labs' CLI Agent Orchestrator (CAO)](https://github.com/awslabs/cli-agent-orchestrator)**
(790 stars, v2.2.0, supervisor/worker pattern over a local MCP server). It already supports
**Claude Code and GitHub Copilot CLI** as first-class providers, and reaches Ollama indirectly
through its (experimental) OpenCode provider support. Building a bespoke `factory/` extension
with per-CLI adapters would duplicate this. **Recommendation: evaluate CAO in a sandbox before
writing any custom orchestration code.**

## What I verified, live, on this machine (not just docs)

| Path | Command that works | Evidence |
|---|---|---|
| Claude Code headless | `claude -p --model <id>` | Already production-used in `factory/run.sh`; confirmed still subscription-billed (Anthropic announced a switch to API billing for `claude -p` effective 2026-06-15, then **paused it before it took effect** — still draws from Max plan as of today). |
| Copilot CLI headless | `copilot -p "..." --model claude-sonnet-4.6 --allow-all-tools` | Ran it twice, live: default routed to **Claude Opus 4.8** (22 AI credits, 35.2k tokens for a 1-line reply — real per-call overhead), explicit `--model claude-sonnet-4.6` worked and cost less (9.66 credits). Both exit 0. |
| Ollama direct | `ollama run qwen3:14b "..."` | Works, fast (8.9s incl. reasoning trace — it's a thinking model, tokens spent on `Thinking...` block before the answer), GPU-resident (`ollama ps` shows 100% GPU, 40960 ctx already configured). |
| Ollama **as an agent** (file edits, tools) via OpenCode | `opencode run "..." -m ollama/qwen3:14b` | Connected (`llm.provider=ollama llm.model=qwen3:14b` confirmed in logs), but **timed out at 120s** in my test where raw `ollama run` took 9s. Likely opencode's larger system-prompt/tool-schema injection + qwen3's reasoning overhead compounding — not a dead end, but **not yet proven reliable**, needs a longer timeout budget and/or a non-reasoning model variant for snappy phases before this is trustworthy in a pipeline. |

## Corrections to the original idea (worth knowing before deciding)

1. **Kimi K2 is not realistically "local" on this machine.** The real model is a 1T-parameter
   MoE needing ~250GB combined RAM/VRAM at 1-bit quant — this Mac has 64GB (M5 Max). The
   `kimi-k2.6:cloud` Ollama tag exists, but that routes inference to Moonshot/Ollama's cloud
   servers — same privacy/cost profile as any other cloud API, not a local model. If "local and
   private" is the point, **Qwen3-Coder (already partly on this machine: `qwen3:30b`/`qwen3:14b`)
   is the realistic local option** — benchmarks show Qwen3-Coder-30B (3B active/MoE) hitting
   50-71% SWE-bench depending on harness, runs fine on far less than 64GB.
2. **Claude Fable 5 is real and available**, but it's Anthropic's most expensive model
   ($10/$50 per M tokens, 1M context) — a "Mythos-class" flagship, not a cheap planning tool.
   It fits the idea (spend the expensive model where reasoning quality matters most: planning,
   architecture, ambiguous decisions) but budget-consciously, not as a default for every phase.
3. **Copilot CLI bills per-prompt against a monthly premium-request quota** — an automated
   multi-phase pipeline that fires many Copilot calls needs a budget/backoff plan, the same way
   `factory/run.sh` already has a model-policy allowlist for Claude.
4. **Ollama's default context window (4K) is useless for agentic coding** — must be raised
   (≥16K, ideally much higher for repo-scale work) via a custom Modelfile or opencode provider
   config; the `40960` already configured on this machine for `qwen3:14b` suggests this was
   already tuned once, worth checking where/why.

## Recommended plan (phased, cheapest-first)

**Phase 0 — sandbox CAO (no roberdan-os changes, ~half a day).**
Install CAO in an isolated dir, wire 3 providers (Claude Code, Copilot CLI, OpenCode→Ollama),
run one real trivial 3-phase pipeline (plan → execute → verify) on a throwaway toy task. Goal:
answer "does the supervisor/worker handoff actually preserve enough context, and is the
per-phase cost/latency acceptable" with evidence, before touching the real system.

**Phase 1 — decide the integration shape (a design gate, like today's split).**
Based on Phase 0 evidence, choose one of:
- **(a) Adopt CAO as-is**, invoked by `factory/` for tasks that declare a multi-provider
  pipeline (a new `pipeline:` frontmatter field alongside today's `model:`/`repo:`).
- **(b) Borrow CAO's primitives (Handoff/Assign) but implement thinly** inside `factory/` if
  CAO turns out to be too heavy/opinionated (tmux dependency, Python/uv prerequisite) for a
  bash-first repo.
- **(c) Don't integrate — keep it manual**, if Phase 0 shows the overhead (cost, latency,
  context loss between phases) outweighs the benefit for roberdan-os's actual workload.

**Phase 2 — if (a) or (b): implement + gate.** Same discipline as the engine/identity split:
@baccio design doc, phased commits, `@rex` review, `@thor` acceptance, honest CHANGELOG.
Estimate: comparable scope to the v2.0.0 split (~20-30 files: factory/, a new pipeline schema,
docs) — **this is a real project, not a config tweak.**

## What this is NOT (scope guard)

Not a replacement for the existing per-agent `model:` policy (Claude-only, already works,
already gates sonnet/opus via `resolve_model()`). This is additive: a way to route a *phase*
to a *different CLI entirely*, for the cases where that CLI/model combination is genuinely
better suited — not a default posture for every task.

## Phase 0 — DONE (2026-07-05), empirical result

Installed CAO in a scratch dir (`uv tool install` — put binaries in `~/.local`, profiles/db in
`~/.aws/cli-agent-orchestrator/`, and a Copilot agent file in `~/.copilot/agents/developer.agent.md`;
prereqs tmux/python/uv were all already present). Ran a toy 3-line-haiku task with a **Claude Code
supervisor delegating to a Copilot CLI worker**. Findings, from the actual tmux panes:

- **The base orchestration launches correctly.** CAO spun up the supervisor (Claude, native
  interactive `claude --remote-control` — NOT `claude -p`, so it draws the normal Max pool) and a
  separate Copilot CLI worker window (Copilot v1.0.69, custom agent "developer", Opus 4.8, 1M ctx).
- **Cross-provider handoff FAILED — twice.** The supervisor called the handoff MCP tool; the worker
  window was created but **the task was never injected into it** — the Copilot worker sat at its
  idle prompt with "0 AIC used", and the handoff **timed out after 600s** with no file produced.
- **Isolation test — the worker itself is fine.** I manually typed the same task into the Copilot
  worker pane; it produced `haiku.txt` correctly in seconds. **So the worker CLI works; what's
  broken is CAO's status-detection/injection for the `copilot_cli` provider** — it can't tell when
  the Copilot worker is ready-for-input, so it never delivers the task. This matches CAO's own docs
  flagging copilot/opencode callbacks as fallback/experimental.
- **Ollama-via-opencode** (from the earlier pre-plan probe) also timed out at 120s where raw
  `ollama run` took 9s — same class of immaturity on the non-flagship providers.

**Verdict:** CAO's *architecture* is right and the Claude-native path is solid, but the exact thing
this whole idea needs — **reliable cross-provider handoff to Copilot/Ollama** — does **not** work
out-of-the-box today. Making it reliable means debugging CAO's per-provider status detection (or
waiting for upstream to mature it), which is real work, not a config tweak. Kimi-local remains
infeasible on 64GB regardless.

**Honest recommendation:** do NOT adopt/document CAO in the repo yet — documenting a broken
cross-provider path would be worse than nothing. Two viable next moves, Roberto's call:
- **(i) Park it.** Re-test when CAO's copilot/opencode providers mature (watch the repo). The
  Claude-native multi-model need (Fable-plan → Sonnet-exec) is *already met* by `agents/*.md` +
  `model:` frontmatter — no new infra needed.
- **(ii) Invest.** Spend a focused session debugging CAO's `copilot_cli`/`opencode` status
  detection (opus subagent), get one cross-provider pipeline reliable, THEN document + integrate.

## Cleanup note

Phase-0 left these outside the repo (remove if parking): `~/.aws/cli-agent-orchestrator/`,
`~/.copilot/agents/developer.agent.md`, the `cao*` uv tools (`uv tool uninstall
cli-agent-orchestrator`), and the scratch clone. Nothing was committed to any repo.
**Done 2026-07-05: CAO fully removed** (uv tools uninstalled, both state dirs deleted, tmux
sessions/server killed, scratch clones wiped). Roberto's call: park CAO.

## The pivot — kanban IS the cross-tool handoff (Roberto's insight, validated)

Roberto's redirect: instead of a fragile runtime orchestrator, use the **durable kanban card as
the handoff unit** — any CLI reads a card and starts. No process piloting another process; context
passes via files, the pattern roberdan-os already rests on.

**Validated live (2026-07-05):** a toy card ("create greeting.txt with one exact line") in a
scratch `kanban/todo/` was handed to `copilot -p "read the card, execute it"` — Copilot **read the
card, understood its DoD/acceptance, created the file, AND self-verified against the acceptance
criteria**, one-shot, 29.8 credits / 28s. This is the whole idea working with zero orchestration
infra: the markdown card is a universal, CLI-agnostic work unit. (Ollama-as-agent stays the weak
leg — it needs opencode, which timed out — but that's an Ollama-agentic-harness limit, not a
kanban-pattern limit.)

**New direction (Roberto's choices):** federate the kanban — cards live in each repo
(`~/GitHub/<repo>/kanban/`), a global `kb` discovers and aggregates them; handoff follows the same
per-repo model. Plus a `runner:` field (CLI+model per card) and a bash dispatcher that launches
each CLI in yolo to auto-execute its cards.

## Adversarial review of the yolo-dispatch idea (Fable + @board + @baccio, 2026-07-05)

Three independent analyses converged hard. **The kanban-as-handoff pattern survives; the
`yolo + weak external models + gates-as-prose + shared repos` combination is rejected as
specified.**

- **Fable (thesis stress-test):** the "AGENTS.md governs any model" thesis is TRUE declaratively,
  FALSE executively. AGENTS.md is a real 2026 standard (Linux Foundation, 28+ tools, 60k+ repos) —
  behavior travels with the repo. But 2026 papers (IHEval, The Compliance Gap, ODCV-Bench) measure
  that gate-adherence collapses under goal-pressure and with weaker models — exactly the cheap
  local runners the federation wants to use. An 8B model goes 53%→99% on agentic tasks only with
  *external structural guardrails*, not better prompts. roberdan-os already admits this: AGENTS.md
  itself calls `--by roberto` "a discipline gate, not a security boundary." **Defensible
  reformulation: AGENTS.md unifies behavior above a capability floor; only intercepting CODE
  guarantees the gates.** Two layers — canon for behavior (cheap to get wrong), code for
  governance (irreversible to get wrong).
- **@board (red-team):** `--yolo` deletes the only deterministic gate you have and replaces it
  with prose a weak/injected model can ignore. Five concrete failure modes: dossier exfiltration
  (runner reads `~/.roberdan-os/private/` → writes to a card → card committed), prompt-injection
  via a card or a teammate's file in a shared repo, irreversible push/force-push/merge/rm by a
  confused weak model, multi-runner `.git/index.lock` collision (the vault's documented
  "one agent at a time" bug, re-introduced ×N), fake "done" from a local model (@thor detective
  gate can't undo a push already made). Non-negotiable mitigations, all BELOW the model: runner
  env with NO push/merge credentials + shell deny-list on destructive git; runner works only in an
  isolated worktree/branch → PR (merge stays human gate); per-repo allowlist (shared/sensitive
  repos like MirrorBuddy → never an external yolo runner); one-runner-per-repo lock; mandatory
  leak-check before any card commit. Verdict: **build only in restricted form, reject as
  specified.** The deciding question: *what real task is worth an external yolo runner that you
  can't already do with Claude-native + `model:` frontmatter?* No concrete answer → park it.
- **@baccio (fact that closes it):** MirrorBuddy has a *standalone* `AGENTS.md` (not a pointer to
  roberdan-os) and does not gitignore `kanban/`. So the "gates inherited via AGENTS.md" premise is
  empirically false for at least one real target repo — the inheritance the whole idea leans on
  isn't there by default.

## Recommendation (synthesized)

Separate three pieces by risk:
1. **Kanban federation** (cards per-repo + aggregating `kb`) — organizational value, real; needs a
   serious per-repo privacy model (gitignore + leak-check per repo, since MirrorBuddy proves it's
   not automatic). Roberto already chose this.
2. **`runner:` as declarative metadata** (a card states its ideal CLI/model) — zero risk, it's a
   label; execution still defaults to Claude-native (Agent tool + `model:` frontmatter, which
   already works and keeps native gates).
3. **Dispatcher executing external runners in yolo** — high risk, rejected as specified. Only a
   sandboxed form (isolated worktree, no credentials, PR-only, allowlist of non-sensitive
   own-repos) is defensible, and only if a concrete use-case emerges that Claude-native can't cover.

Park (3) until there's both a real use-case and a proven-reliable Ollama-agent leg. Build (1)+(2).
