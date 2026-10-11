# ADR-0006 - Tests: budget, place, shape

**Status:** Accepted, 2026-10-11 (card 261011-112938).
**Decision owner:** Roberto. His approval, verbatim, 2026-10-11: «ok regole test, sistema tutto».
**Scope:** the canon (`rules/best-practices.md` § Tests, `AGENTS.md` § Rules), `agents/thor.md`
gate 8/8b, the skills `verify-done`, `ship`, `review`, `engineering-reference`,
`behavior/roberto-mode.md` quality gate, and the repo template `docs/testing-template.md`.
**Not authorized here:** migrating any repo (casa-caccini, MirrorBuddy, VirtualBPMFy27 and the
rest each get their own PR); changing the shared guest hook; any human gate.

## Context

A census on 2026-10-11 (`rules/scars.md` § Test sprawl) found test suites growing by file count
and wall time in every active repo — casa-caccini at ~45 new test files a day, 128 of them named
after an audit round, and a ~19-minute pre-push. The cause was in the canon, not in the agents:
six rules said "add a test" or "run every test" (best-practices "too simple to test → write the
test", the 300-line cap pushing each fix into a new file, thor gate 8 "TDD — tests present",
verify-done "coverage ≥ 80%", every review comment fixed "with tests", engineering-reference and
ship running the whole suite before each push) and none said where, when, how many or how long.

## Decision

Roberto's binding constraints, 2026-10-11:

1. Each change pays only for **fast checks and the tests of the files it touched**.
2. **Changes are batched.**
3. The **full suite runs at night**, on request, or before merging a change to a **critical path**.
4. **Critical paths are declared per repo** (`.test-critical`).
5. **Extend instead of adding**: a fix is a new case in the existing test.
6. **Monthly pruning**, never on critical paths.
7. A **self-recalibrating ceiling**: more than +10% suite time or test files without a written
   reason is red (`.test-budget`).

Applied as: five rules in `rules/best-practices.md` § Tests; three replaced Persuasion
Guardrail rows; the 300-line cap now counts test logic only (case tables and fixture data exempt);
thor gate 8 asks for a pinned behaviour and rejects round-named test files, gate 8b scoped to
critical invariants; verify-done drops the global 80% coverage target; engineering-reference and
ship run related tests before push and re-run only the failing step; review fixes add a case, not
a file.

**Safe default:** a repo with no `.test-critical`, or with no nightly actually running, is
entirely critical — full suite before every merge, as before. So this ADR loosens nothing in a
repo until that repo adopts the template.

## Consequences

- A non-critical change can sit broken on `main` for up to one night. Countermeasures: it cannot
  touch money, rules, migrations or approval gates (those are critical); the escape list forces
  the full suite on lockfile/config/schema/harness changes; the nightly bisect names the merge.
- `rules/best-practices.md` grows past its 200-line target (now ~222). The rule is always-loaded
  on purpose: it must change behaviour before anyone looks it up. Mechanics went to
  `engineering-reference` and `docs/testing-template.md`, the reason to `rules/scars.md`.
- Anti-regrowth check 5 (roberdan-os verifies adopted repos carry the two files) is described but
  not wired until the first repo adopts.
- `test/test-canon-guardrails.sh` now fails if any of the replaced phrases comes back.
