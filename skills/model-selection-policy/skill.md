---
name: model-selection-policy
description: Which model to give a subagent — tier decision table, reasoning-effort knob, and the hard rule that the id must always be the newest generation of that tier. Read before spawning any non-trivial subagent.
providers: [claude, copilot, codex]
---

# model-selection-policy — which brain, how new, how hard it thinks

Two knobs, decided separately: **tier** (which brain) and **effort** (how hard it thinks).
A third thing is not a knob at all but a rule: **the generation is always the newest**.

## The subagent default — cheap/mid model unless a written reason justifies frontier

**The most impactful cost lever** (Uber Engineering, 2026 — 52% cost cut per session at 7×
usage): *"The primary model handles task decomposition and evaluation while subagents execute
the work."* So the default splits by role:

- **Deciders / reasoners** — task decomposition, architecture and ADRs, security judgment,
  adversarial red-teams, first-principles deconstruction, thinking in Roberto's voice. Output
  quality *is* the product and creativity+correctness both matter → the **frontier** tier
  (today `opus`) is legitimate.
- **Executors** — well-scoped work with specified inputs (review to a checklist, QA to explicit
  acceptance criteria, orchestration to a protocol, standard feature/bug/test/doc work). These
  **default to the cheap/mid tier** (`sonnet`, or `haiku` for pure orientation) and do **not**
  require frontier-level reasoning.

**Binding rule:** a subagent runs on the cheap/mid tier **unless a written reason justifies
frontier**. In canon that reason is the `model_rationale:` frontmatter field on the agent — an
executor pinned to a frontier model **without** that field is a policy violation the gate
rejects (`test/test-model-economy.sh`). Manual per-invocation overrides to frontier are always
allowed (Uber keeps that escape too); the *default* is the point.

## The hard rule — newest generation of the tier, always, explicitly

- **Always pass `model` explicitly** when spawning a subagent. The default may be a previous
  generation.
- **Never type a version number from memory.** The mapping tier → concrete id lives in
  `copilot_model()` in `bin/sync.sh` and is the single source of truth:

  | Tier | Concrete id (canon mapping) |
  |---|---|
  | `haiku` | `claude-haiku-4.5` |
  | `sonnet` | `claude-sonnet-5` |
  | `opus` | `claude-opus-5` |

- **If the tool's own model list shows a higher generation than that table, the list wins** —
  use it, and update `copilot_model()` in the same session. The table is a snapshot; the rule
  is "newest".
- **Unsure between two generations? Go up.** A previous generation at the same tier usually
  costs the same and reasons worse.

**Precedent, 2026-08-28 (audit MirrorScopio).** Four read-only verification subagents were
launched on `claude-sonnet-4.6` while `claude-sonnet-5` and `claude-opus-5` were both listed
by the tool. Roberto caught it; the whole pass was thrown away and redone. The canon mapping
was already correct — the id was typed by hand. This rule exists to stop exactly that.

## Decision table — which tier

| Tier | When to use |
|---|---|
| **haiku** | Pure orientation: file reads, grep, git log/status, counting lines, lookups with no synthesis. Never for writing code, plans or decisions. |
| **sonnet** | Default subagent tier for anything that fits in one session: standard feature work, clear-scope bug fixes, test additions, doc updates, single-file refactors, CI triage. Effort `medium` by default (raise with a written reason). |
| **opus** | Complex but bounded: multi-file architectural refactors, hard-to-reproduce bugs, ADR drafting, performance root-cause, review of a specific module, security analysis of a component. Also full assurance passes and system-wide reviews. Also **any read-only pass whose output a human will rely on to decide** — an audit verification is not "just reading". Effort up to `max`. |
| **frontier** | Novel design where creativity and correctness both matter, ambiguous high-stakes decisions, adversarial red-teams, long autonomous runs. Today this is `opus` with effort `xhigh`/`max`. |

## Upgrade triggers — escalate mid-task if any fire

- The same section has been rewritten 3+ times without converging → **opus**.
- The task spans >4 files **and** needs cross-cutting invariants → **opus** minimum.
- The output is a compliance / security / architecture artefact a human will rely on → **opus**.
- Two designs, non-obvious tradeoffs → **opus**.
- A prior attempt produced plausible-but-wrong output (hallucinated API, wrong invariant) → **opus**.

## Efficiency rules

- Orientation before writing (reading, searching, counting): **haiku** or **sonnet** — don't
  burn the top tier on a step whose output nobody reasons over.
- Parallel independent subagents each pick their own tier; don't force them all to one.
- "veloce" / "quick" / "just check" → **sonnet** maximum, don't over-engineer.
- "assicurati" / "verifica bene" / "qualità" / "scala a opus" → honour it literally.

## Effort — the second knob

Effort trades the chosen brain's intelligence against latency and cost. **The default is
`medium`** — output/reasoning tokens bill at a multiple of input tokens, and Medium balances
cost against quality for a large class of tasks (Uber Engineering, 2026). Going **above medium**
(`high`/`xhigh`/`max`) needs a **written reason**, the same escape as the model rule: in canon
that is the `effort_rationale:` frontmatter field. `xhigh`/`max` are for the hardest
capability-sensitive calls (a `@board` red-team, a `@socrates` deconstruction); `low`/`medium`
for routine. It is a run-time parameter **and** an agent frontmatter field (`effort:` next to
`model:`).
