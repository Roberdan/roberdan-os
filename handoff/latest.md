# Handoff — session 2026-07-01 → 07-02 (factory reliability + privacy hardening)

**For a fresh agent:** read this + `kanban/todo/`+`doing/` + `MEMORY.md`, then `gbrain search`
what you need. You'll have the full working context without the (huge) original conversation.

## What this session did (the story so far)

Started from a deep-analysis pass (model: Fable) over the whole system + the todo/doing kanban,
which surfaced a real incident: the previous session's first overnight factory run had failed
silently 4/4 (`exit 127`, `claude`/`timeout` binaries unresolved under launchd's minimal PATH) and
`run_task()` filed every failed task as `done/` anyway — the kanban board kept showing two cards as
"doing" for over an hour with no signal anything had broken. Fixed and verified end-to-end under a
minimal, launchd-like PATH (`env -i`). Consolidated the overlapping `T-adversarial-judge` card with
this session's own analyses instead of re-running it blind overnight.

**Mid-session privacy incident (see Honest scars):** a subagent verifying the privacy split wrote
real confidential client names into a committed doc; it was committed AND pushed to the private
GitHub remote before being caught by `test/leak-check.sh` on a later, unrelated run. Remediated
(amended the commit, human-confirmed + human-executed force-push to fix remote history) and closed
structurally: `leak-check.sh` was never enforced at commit time, only run manually via
`test/validate.sh` — now `hooks/pre-commit` (installed via `bin/install-git-hooks.sh`) blocks the
commit itself on any hit. Verified: a probe commit with a denylisted term is refused.

## Key decisions (with rationale)

- **A factory task only reaches `done/` on exit 0**; failures retry once then land in `failed/`
  with `escalate: true`. **Exit 0 ≠ kanban-done** — it only proves the process didn't crash, not
  that the DoD/acceptance was met. `@thor` still gates `doing→done`. (Confirmed independently by
  two adversarial reviews this session as the system's biggest unverified-autonomy risk.)
- Factory tasks can declare `card: <id>` so results sync back onto the kanban card automatically —
  closes the "two sources of truth" gap that let cards go stale silently.
- Factory's default `--add-dir` is now scoped to `roberdan-os`, not all of `~/GitHub`
  (`--dangerously-skip-permissions` grants write to whatever it points at).
- Global `~/.claude/CLAUDE.md` claims gbrain's embedder "must stay `openai:text-embedding-3-large`"
  — **verified wrong**: the live config is `ollama:bge-m3` (matches this repo's canon). Needs a
  human-confirmed edit to that file (out of this repo's scope to change unilaterally).
- `docs/adversarial-judgment-2026-07-01.md`: two independent adversarial passes agree the system's
  core (kanban gates, privacy split, `validate.sh`) is honest and worth keeping; the
  factory/meta-loop layer is unproven scaffolding, not yet earned trust. Also flagged (not yet
  acted on): `behavior/roberto-mode.md` still names a Convergio sync step as a done-gate criterion
  despite Convergio being stopped, a cargo-cult Convergio-agent roster in the same file, and a
  "WCAG 2.2 AA" principle inherited from Convergio's product context that nothing in this personal
  OS actually implements.
- `docs/adr/adr-always-on-security.md`: G5-always-on's real security boundary is gbrain's
  **per-remote source allowlist**, not a `workspace:` tag (not enforced at the data layer). FtS
  confidential docs should land in an isolated `vault-fts` source, not the general `vault` source,
  before any remote MCP endpoint is exposed.

## Current state (what's built/running)

- `test/validate.sh` green, now including a real `test/test-factory-kb.sh` (was smoke-test only).
- `hooks/pre-commit` installed in this working copy — blocks confidential-term commits.
- `bin/check-embedder.sh` — read-only durability check for the bge-m3 patch (verified OK now).
- `docs/USAGE.md` — day-to-day operator guide, linked from README.
- Commits this session (local `main`, some already pushed — see below): factory failure-semantics
  fix, kanban state correction + `kb block`, security ADR, factory+kb test suite (+ 2 pre-existing
  `kb.sh` bugs found and fixed under `set -e`/`pipefail`), adversarial judgment doc, factory→kanban
  sync, pre-commit privacy gate, embedder check, usage guide.

## Open threads / pending human gates (batched, not yet resolved)

1. **`kb start --by roberto`** for `T-tests-factory-kb` and `T-usage-guide` — the work (test suite,
   USAGE.md) is done and verified; only the kanban transition needs Roberto's approval.
2. **`kb finish --thor`** for the same two cards, plus re-annotated `T-adversarial-judge` /
   `T-system-tests` — needs a `@thor` pass against each card's acceptance criteria.
3. **FtS-ingest** — corrected root cause (it's an 8-15 min foreground job, not a TCC/background
   problem), but confidential data entering the vault should happen with Roberto present. Not run
   this session.
4. **Global `~/.claude/CLAUDE.md` embedder correction** — diff ready, needs Roberto's confirmation
   before editing a file outside this repo.
5. **G5-always-on decision** — threat model now exists (`docs/adr/adr-always-on-security.md`);
   decision itself is still Roberto's (spend + architecture + memory-exposure gate).
6. **Push to remote** — most of this session's commits are local-only; confirm before pushing.

## Honest scars (don't repeat)

Wiped the gbrain brain chasing bge-m3 (recovered, prior session). Called a bug "interesting" (prior
session). Mistook "committed" for "active-by-default" (prior session, and recurred THIS session as
"fix committed" ≠ "fix verified end-to-end" until actually tested under a launchd-like PATH).
**New this session:** a safety check that isn't wired to run automatically is not a control — it's
a hope. `leak-check.sh` existed the whole time and would have caught the leak; nothing forced it to
run before the confidential commit was made and pushed. Any gate meant to prevent an
irreversible/external-facing action must execute automatically at the point of that action.
