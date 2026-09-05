---
name: model-selection-policy
description: Which model a subagent runs on, how hard it thinks, and how much context it gets — resolved from one reviewed registry, never typed from memory. Read before spawning any non-trivial subagent or pinning a model in an agent file.
providers: [claude, copilot, codex]
---

# model-selection-policy — which brain, how hard, how much context

Three knobs, decided separately, and **one place that knows the answers**:
[`models.tsv`](models.tsv), read through `bin/lib-models.sh`.

| Knob | What it decides | Where it is really set |
|---|---|---|
| **model** | which brain | Copilot: `--model <id>` · agent frontmatter `model:` / `copilot_model:` |
| **effort** | how hard it thinks | Copilot: `--effort <level>` · `subagents.agents.<name>.effortLevel` |
| **context** | how much window it gets | Copilot: `--context <tier>` · `subagents.agents.<name>.contextTier` |

**Never type a model id from memory.** Ask the registry:

```
bin/models.sh list                       # the reviewed table
bin/models.sh resolve opus               # -> claude-opus-5   (host copilot)
bin/models.sh resolve opus --host claude # -> opus            (Claude Code takes the tier alias)
bin/models.sh class gpt-6-astra          # -> frontier
bin/models.sh validate --model gpt-6-astra --effort xhigh --context long_context
bin/models.sh agents                     # every canon agent's resolved knobs
bin/copilot-agent.sh baccio -p "..."     # launches with those flags actually passed
```

A token the registry does not know **does not resolve** — no pass-through, no guess. That is
the point: the map this replaced passed any unknown string straight to `--model`, so a typo
reached the CLI as a model name. Precedent, 2026-08-28: four subagents ran on
`claude-sonnet-4.6` while `-5` was listed, because the id was typed by hand. The whole pass was
thrown away and redone.

## Two facts about the registry that keep people honest

1. **It is a snapshot, not a probe.** CLI ids came from `copilot help config` on 1.0.84-1;
   effort/context metadata came from the session's delegation tool schema. It cannot tell
   you a model is *enabled for your account* — availability
   is per-account and per-flight. Never say "available" on the strength of this file.
2. **A host's model catalog is not one list.** On Copilot CLI 1.0.84-1 the `--model` catalog and
   the task/agent tool's catalog **differ** — each holds ids the other does not. Rows distinguish
   `copilot` and `copilot-task`: a task-only model cannot resolve for a CLI launcher.
   `bin/models.sh snapshot` prints provenance. Never infer capabilities from an id alone.

The `class` column (frontier / mid / cheap) is a **conservative budget-and-risk policy band,
deliberately independent of brand**. It is not a quality ranking and not a price — this repo
holds no price data, and nothing here measures one model against another.

## Every spawn, including a subagent's children

Choose for the actual work: quality and task fit first, cost among suitable choices.
Always pass `model` explicitly; on Copilot's `task` tool use `reasoning_effort` and
`context_tier` only when supported. Repeat this instruction in every delegated prompt.
Never fall back to a built-in's old default, including `explore` called by `general-purpose`.

[`delegation.tsv`](delegation.tsv) assigns current profiles to the six native built-ins.
`subagents-json` combines these with the custom agents and emits `modelPolicy: required`.
Copilot CLI 1.0.84-1 exposes this native setting through `/subagents`; it prevents silent
model substitution. To use another current model for a role, change its profile or
`/subagents` selection deliberately. The registry refuses legacy ids.

Settings affect new spawns, not agents already running. Restart old sessions, inspect their
effective `/subagents` settings, and check the selected model when delegation starts.
Repository/session overrides can supersede user settings. No static registry can guarantee
the objectively best model on an unmeasured task, or future account availability.

## The subagent default — cheap/mid unless a written reason justifies frontier

**The most impactful cost lever** (Uber Engineering, 2026 — 52% cost cut per session at 7×
usage): *"The primary model handles task decomposition and evaluation while subagents execute
the work."*

- **Deciders / reasoners** — decomposition, architecture and ADRs, security judgment,
  adversarial red-teams, first-principles work, thinking in Roberto's voice. Output quality
  *is* the product → the **frontier** class is legitimate.
- **Executors** — well-scoped work with specified inputs (review to a checklist, QA to explicit
  acceptance criteria, orchestration to a protocol, standard feature/bug/test/doc work) →
  **mid or cheap** class, by default.

**Binding rule:** a subagent runs on a mid/cheap-class model **unless a written reason justifies
frontier** — the `model_rationale:` field on the agent file, and `copilot_model_rationale:` for
a Copilot-only pin. A per-host pin is a *second* pin and needs its own reason: sharing the canon
one would let a rationale written for one model silently cover a different model on a different
host. Enforced by `test/test-model-economy.sh`, which asks the registry for the class.

**An unreviewed id classes as `unknown`, and `unknown` is treated exactly like `frontier`.**
Erring toward "this needs a written reason" is the only safe direction: the other error is a
silent expensive default nobody notices.

Manual per-invocation overrides to frontier are always allowed (Uber keeps that escape too).
The *default* is what this rule is about.

## Effort — the second knob

**Default `medium`.** Output/reasoning tokens bill at a multiple of input tokens, and medium
balances cost against quality for a large class of tasks (Uber Engineering, 2026). Going above
medium (`high`/`xhigh`/`max`) needs a written `effort_rationale:` on the agent.

Two things that are not the same, and conflating them is how a knob silently does nothing:

- what the **CLI parses** — `none | minimal | low | medium | high | xhigh | max`;
- what **this model** exposes — the `efforts` column. Some models have **no reasoning knob at
  all**, and passing `--effort` to one of those is a claim about it that is not true.

`bin/models.sh validate` checks both. `bin/copilot-agent.sh` omits the flag entirely when the
model has no knob, instead of sending a level that would be ignored.

## Context tier — the third knob, and where it is NOT

`default` unless the work genuinely needs the long window (a long transcript, a large diff, a
whole-repo pass). Only some models are tiered; for the rest the tier is not a choice and the
flag is left off.

Three surfaces, easy to mix up:

- **`--context <tier>`** — a Copilot CLI flag, for one run. `bin/copilot-agent.sh` passes it.
- **`subagents.agents.<name>.contextTier`** — the persisted per-subagent setting in Copilot's
  own `settings.json`. Generated as a fragment (`platforms/copilot/subagents.json`) and applied
  only by the explicit, atomic, backed-up `bin/models.sh apply-subagents --yes`. `sync.sh
  --install` never writes it: that file belongs to Copilot.
- **agent frontmatter** — **there is no such field.** Copilot's custom-agent schema has no
  effort and no context key, and it ignores unknown keys *in silence* (the `metadata:` scar).
  Writing one there looks like configuration and behaves like a comment — worse than nothing,
  because it stops the next person from looking for the setting that works.

## Copilot-first, without breaking the other two

- **Copilot CLI** is the primary host: concrete ids, all three knobs, native custom agents.
- **Claude Code** keeps the **tier alias** (`opus`/`sonnet`/`haiku`) — `resolve --host claude`
  returns the alias, and a Copilot id is refused rather than handed over to be rejected later.
  A `copilot_model:` override changes the Copilot side only; the canon `model:` is untouched.
- **Codex** has no model pin in this canon; resolving for it is refused, not faked.
- **`factory/`** runs `claude -p` and is deliberately untouched by all of this: it is a
  Claude-only runtime with its own isolation and permission posture. Do not point it at a
  non-Claude id.
- **Third-party skills (gstack) are upstream's, not ours.** gstack v1.79.0 pins concrete Claude
  ids in its own shipped code (`lib/eval-model.ts`, `lib/context-bill.ts`, `scripts/models.ts`,
  `scripts/preflight-agent-sdk.ts`), and its `/plan-*`, `/office-hours`, `/ship` skills run on
  that runtime. **Never hand-edit the installed copy under `~/.claude/skills/gstack/`** — the
  next `gstack` update overwrites it and the divergence is invisible until something breaks.
  A model default that is wrong for us there is an **upstream issue/PR**, or an env override
  where gstack already exposes one (`EVALS_MODEL`). This canon's registry governs *our* agents
  and skills only.

## Where this policy is enforced (so it can't quietly rot)

Canon skills that delegate — [[premortem]], [[focus-group]], [[problem-validation]],
[[long-running-jobs]] — say "the host's delegation tool" and point here for model/effort/context,
instead of naming one vendor's tool or one vendor's model. Their reports land in
`~/.roberdan-os/reports/`, not in a single CLI's home directory.

## Decision table — which class, when

| Class | When |
|---|---|
| **cheap** | Pure orientation: reads, grep, git log/status, counting, lookups with no synthesis. Never for writing code, plans or decisions. |
| **mid** | Default subagent class: standard feature work, clear-scope bug fixes, test additions, doc updates, single-file refactors, CI triage. Effort `medium`. |
| **frontier** | Complex but bounded: multi-file architectural refactors, hard-to-reproduce bugs, ADR drafting, performance root-cause, security analysis. Also **any read-only pass a human will rely on to decide** — an audit verification is not "just reading". Also novel design, ambiguous high-stakes calls, adversarial red-teams, long autonomous runs. Effort up to `max`. |

**Escalate mid-task if any of these fire:** the same section rewritten 3+ times without
converging · the task spans >4 files *and* needs cross-cutting invariants · the output is a
compliance/security/architecture artefact a human will rely on · two designs with non-obvious
tradeoffs · a prior attempt produced plausible-but-wrong output.

**Honour the words literally:** "veloce" / "quick" / "just check" → mid class, don't
over-engineer. "assicurati" / "verifica bene" / "qualità" / "scala a opus" → escalate.

## Adding or promoting a model

A new id appearing in a host's list is **not** a promotion. Add a reviewed row to `models.tsv`:
id, family, class, the efforts and contexts you actually verified, and where you read them. A
family may hold **exactly one `current` row**, so promoting a new generation forces demoting the
old one *in the same diff* — "always the newest of the tier" becomes a mechanism instead of a
sentence. `test/test-model-registry.sh` enforces it.
