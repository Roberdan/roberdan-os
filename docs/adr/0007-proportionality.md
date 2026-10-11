# ADR-0007 - Proportionality

**Status:** Accepted, 2026-10-11 (card 261011-143726).
**Decision owner:** Roberto. His approval, verbatim, 2026-10-11: «ok proporzionalità».
**Scope:** the safety kernel and Behavior in `AGENTS.md`, `behavior/roberto-mode.md` § Intake,
and the portable twin skill `.github/skills/roberdan-twin/SKILL.md` with everything generated
from it (`claude-ai-skill/`, `cowork-skill/`, `.github/copilot-instructions.md`).
**Not authorized here:** relaxing any human gate, `verify-done`/thor evidence or ADR-0006.

## Context

Agents drifted into process for its own sake: repeated permission after an explicit
instruction, extra records because a model had the fields, "evidence missing" declared from a
stale index, a secondary missing detail blocking the authorized rest. Source: commit e456180
(Copilot, 2026-10-09), rebased onto v2.60.0.

## Decision

Protect correctness, money, privacy and irreversible consequences, not implementation
preferences. Choose the simplest complete result that keeps the user's unit of work. Resolve
routine details from evidence, check the real source when an index may be stale, reuse matching
explicit approval through the supported mechanism, never reopen a settled choice. Ask only for
a material unresolved risk or a required human gate.

## Consequences

Fewer questions and records. Proof is not trimmed: human gates, verify-done/thor and the
ADR-0006 test rules still apply. `test/test-canon-guardrails.sh` pins the rule in the kernel,
roberto-mode and the twin skill.
