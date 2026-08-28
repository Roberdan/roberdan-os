---
name: model-selection-policy
description: Which model to give a subagent — tier decision table, reasoning-effort knob, and the hard rule that the id must always be the newest generation of that tier. Read before spawning any non-trivial subagent.
providers: [claude, copilot, codex]
---

# model-selection-policy — which brain, how new, how hard it thinks

Two knobs, decided separately: **tier** (which brain) and **effort** (how hard it thinks).
A third thing is not a knob at all but a rule: **the generation is always the newest**.

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
| **sonnet** | Default subagent tier for anything that fits in one session: standard feature work, clear-scope bug fixes, test additions, doc updates, single-file refactors, CI triage. Effort `high` by default. |
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

Effort trades the chosen brain's intelligence against latency and cost. `high` by default,
`xhigh`/`max` for the hardest capability-sensitive calls (a `@board` red-team, a `@socrates`
deconstruction), `low`/`medium` for routine. It is a run-time parameter **and** an agent
frontmatter field (`effort:` next to `model:`).
