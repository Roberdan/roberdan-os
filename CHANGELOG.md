# Changelog

All notable changes to roberdan-os. Format: [Keep a Changelog](https://keepachangelog.com);
versioning: semver on the system's behavior/tooling (the paper has its own version).

## [v2.0.0] - 2026-07-05

### Changed (BREAKING)
- **Engine / identity split.** All forker-editable identity now lives in one place:
  `identity/` (voice, operator profile, twin persona, `identity.conf`). Engine files no
  longer embed identity, so `git merge upstream/main` stays conflict-free on engine files
  forever. See docs/plan-2026-07-05-engine-identity-split.md.
- **`behavior/roberto-voice.md` → `identity/voice.md`** (moved, content byte-identical).
  Update any local reference.
- **`agents/roberdan-twin.md` → `agents/twin.md`**, invoked as **`@twin`** (was
  `@roberdan-twin`). The role prose is now operator-neutral engine; the persona moved to
  `identity/twin-persona.md`.
- **`behavior/roberto-mode.md`** keeps its name but is now pure engine discipline; the
  operator profile (who he is, how he communicates, the Italian phrase table, named-agent
  ecosystem, tool stack) moved to `identity/operator.md`.
- **`RDA_HOME`** env var introduced (default `~/.roberdan-os`) — set it once to relocate the
  runtime home. The `RDA_` prefix is now documented as a **fixed engine namespace**, not
  identity, and is intentionally not parametrized.
- `bin/sync.sh` reads `identity/identity.conf` at generation time (deterministic) to inject
  the operator's name into the generated wrappers; behavior references in the wrappers point
  at the new `identity/` paths. Eval `canon:` wiring repointed to `identity/voice.md`
  (fixture prose itself unchanged — it stays instance test data).

### Removed
- **`bin/fork-identity.sh`** (shipped v1.3.0) — its `git mv`+`sed` rename model is exactly
  what caused perpetual merge conflicts; deprecated after one minor version because the
  model was wrong, not because it was buggy. Replaced by `bin/identity-init.sh`, which
  scaffolds `identity/` and renames no engine file.

### Added
- `identity/` — the ONLY forker-editable surface (`README.md` ownership contract,
  `identity.conf`, `voice.md`, `operator.md`, `twin-persona.md`, `profile-pointer.md`).
- `bin/identity-init.sh` — dry-run-by-default fork scaffolder (`--slug`/`--name`/`--apply`,
  same origin-refusal rail as its predecessor).
- `test/test-fork-merge.sh` — the merge-clean proof, wired into `test/validate.sh`:
  an identity-only fork merges simulated upstream engine edits with **zero conflicts**;
  the soft guarantee (an `identity/` file both sides edit can still conflict, small and
  localized) is documented in the test, not asserted.
- `docs/QUICKSTART-for-forkers.md` rewritten for the `identity/` workflow.

### Migration
- Run `bin/bootstrap.sh` (re-symlinks agents incl. `twin.md`, prunes the stale
  `roberdan-twin` symlink). `RDA_HOME` defaults to today's path, so existing factory/dossier
  state is untouched. Full steps: docs/plan-2026-07-05-engine-identity-split.md § Migration.

### Note
- `claude-ai-skill/roberto-mode/` (packaged skill) is unchanged — a published named artifact,
  out of split scope.

## [v1.3.0] - 2026-07-05

Feedback from an external review of the public repo (via Grok) converged with the earlier
focus-group finding: forking this for yourself was underspecified as "adapt one file."

### Added
- `bin/fork-identity.sh` — dry-run-by-default script that renames the `roberdan-twin` agent,
  `RDA_` env prefix, `~/.roberdan-os` home dir and `behavior/roberto-voice.md` across the live
  canon for a fork, in one pass. Refuses `--apply` against the real `Roberdan/roberdan-os` origin
  without `--force`. Deliberately leaves `docs/archive/`, dated plan/report docs, `eval/tasks/`
  fixtures and `claude-ai-skill/roberto-mode/` untouched (mechanical rename would corrupt them) —
  prints them as a manual-review checklist instead. Tested end-to-end on a scratch clone
  (renamed + `test/validate.sh` still ALL GREEN afterward).
- `docs/QUICKSTART-for-forkers.md` — the 5-step fast path (clone → bootstrap → fork-identity.sh →
  write your own voice/privacy files → validate).

## [v1.2.0] - 2026-07-04

Prepared the repo for public release.

### Changed
- **Kanban card content is gitignored** (`kanban/todo/`, `kanban/doing/`, `kanban/done/`) — same
  split as `private/`. The `kb` tool and protocol stay versioned; the live task/business content
  in individual cards never enters git. `kanban/README.md`/`AGENTS.md`/`README.md` updated to
  document the split.
- **History purged** of all previously-committed kanban card content (`git filter-repo`), including
  three cards with unredacted product-compliance detail that should never have been committed —
  found and removed before the repo went public. A stale, already-merged remote branch carrying
  the same pre-purge history was deleted rather than rewritten.
- Added `LICENSE` (MIT) and a public-facing README (prerequisites, install, gstack/gbrain setup).

### Fixed
- Same class of privacy incident as the one noted in v1.0.0 — cards from a different session
  slipped past denylist-based leak-check (which only catches known terms, not business-sensitive
  prose it was never told about) and reached `main`. Structural fix this time: the content class
  is gitignored, not just its exact known strings.

## [v1.1.0] - 2026-07-03

Kanban cards now say what they're about, not just what they're called.

### Added
- **`repo:` mandatory field on every kanban card** — names the `~/GitHub` repo/scope the card
  is about (or `personal` for non-code work). `kb add` requires `--repo`; `kb start` refuses a
  card whose `repo:` is missing or still `FILL:`, same discipline as `dod:`/`acceptance:`.
- Board/`kb list`/`kb history` render `(repo)` next to every card so scope is visible at a
  glance — the board never truncates the id itself (the key you pass to `show`/`start`/`finish`),
  it only appends the repo tag when it fits the column width; legacy cards with no `repo:`
  degrade to `(—)` instead of crashing.
- `test/validate.sh` gained a frontmatter lint for `kanban/todo`+`kanban/doing` cards (mirrors
  the existing agents/skills sections), scoped to active cards only.

### Fixed
- `_board` crashed (`set -e` + `pipefail`) on a kanban with zero archive files — the bare
  `_archive-*.md` glob passed straight to `grep` failed to open the literal non-matching
  pattern and killed the whole script. Never seen on the real board (always has ≥1 archive);
  found while testing the `repo:` display against a clean fixture.

## [v1.0.0] - 2026-07-03

First tagged release: the system graduates from "under construction" to versioned operation.
Everything below was verified end-to-end (test/validate.sh, 10 gate sections) and, where noted,
reviewed by @rex and validated by @thor with evidence.

### Added
- **Cross-tool canon distribution** (tool-independence pass): global `AGENTS.md` pointer fabric
  (`~/GitHub`, `~/.codex`, `~/.config/opencode`) installed by `bin/sync.sh --install`; roberdan-os
  skills distributed to Claude *and* Copilot CLI (`~/.copilot/skills`, SKILL.md portable standard);
  hermes + Warp documented (both read AGENTS.md natively); ownership-aware tool-coverage gate in
  `test/validate.sh`.
- **Gated kanban** (`kb`): DoD+acceptance per card, human gate todo→doing, @thor+evidence gate
  doing→done, `kb block`, audit trail on every start attempt; detail-on-demand views
  (`history`, `archive`, `plans`/`plan`, `sched` — launchd schedules + factory state in one place).
- **Agent factory**: unattended headless task queue with retry → `failed/` escalation (a failing
  task can never be filed as done), headless @thor verify pass against the card's DoD, result
  sync back onto the kanban card, and a hard model policy (sonnet default, `model: opus` opt-in,
  allowlist-clamped — never the account default).
- **Eval harness** (`eval/`): A/B canon-vs-no-canon with blind judging, 12 fixtures (2 derived
  from this system's own real failures), agent-agnostic via `RDA_EVAL_AGENT_CMD`.
- **Meta-loop**: learn (capture→distill→quarantine, daily), evolve (weekly changelog watcher over
  claude/copilot/codex/hermes-agent/warp, draft-only proposals), all launchd-scheduled.
- **Privacy enforcement**: 3-tier leak-check (local denylist / salted hashes in CI / no-op) wired
  as a blocking git pre-commit hook; `private/` never in git.
- **Local-first memory**: Obsidian vault + gbrain (Postgres, `ollama:bge-m3` on-device embedding),
  MCP for Claude and Copilot, `bin/check-embedder.sh` durability guard.
- Operator guide (`docs/USAGE.md`), scientific paper v1.2 (`docs/roberdan-os-paper-en.md`).

### Fixed
- Factory silent-failure bug (exit-127 tasks filed as done) + wrong-cwd dispatch bug
  (`--add-dir` grants access, doesn't chdir) — both found by live, non-stub testing.
- kb `set -e`/pipefail silent-death bugs; double-zero DONE count; BSD-only `sed -i ''`.
- A real privacy incident (confidential names committed and briefly pushed) — remediated and
  closed structurally with the pre-commit gate.
- CI-vs-local drift in the tool-coverage gate (`~/GitHub` check now layout-gated).

### Changed
- English is canonical; generated `platforms/` wrappers are no longer committed (deterministic
  emission checked in CI instead); dated session artifacts roll up into `docs/archive/` and
  `kanban/done/_archive-*.md` (documentation budget).
