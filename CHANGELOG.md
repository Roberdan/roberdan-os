# Changelog

All notable changes to roberdan-os. Format: [Keep a Changelog](https://keepachangelog.com);
versioning: semver on the system's behavior/tooling (the paper has its own version).

## [v2.4.1] - 2026-07-06

### Fixed
- Completed v2.4.0: `kb pause --auto` (the lean variant the Stop hook and the test depend on) was
  added to `kanban/kb.sh` but left unstaged in the phase-2 commit, so on `main` the auto-checkpoint
  hook and its CI test were broken (green locally, red in CI). Now committed.

## [v2.4.0] - 2026-07-06

### Added
- **Pause / Resume — never lose work on a break or reboot.** A canonical, cross-tool contract
  (any `AGENTS.md` reader inherits it) plus tooling:
  - **`kb pause ["next step"]`** writes a lean, per-repo, gitignored checkpoint
    (`<repo>/handoff/resume.md`, cwd-scoped like `kb`/`kb handoff`): the next-step note + mechanical
    state (HEAD, dirty count, doing card). **`kb resume`** reads it (`--all` aggregates across repos,
    `--done` clears it). Per-repo by design — same shape as the federated kanban.
  - **Always-on lean auto-save:** a `Stop` hook (`hooks/auto-checkpoint.sh`) runs `kb pause --auto`
    after every turn — refreshes mechanical state, **preserves the human note**, overwrites one file
    (fixed sections, never a growing log). Even an unannounced crash loses at most the current turn.
  - The `SessionStart` context hook surfaces a pending checkpoint at the top, so a fresh session
    (post-reboot) immediately notices "continua" work.
  - Canon: `AGENTS.md § Pause & Resume` (trigger phrases, safe-point rule). Design:
    `docs/plan-2026-07-06-pause-resume-checkpoint.md`.

## [v2.3.0] - 2026-07-06

### Added
- **The aggregated `kb` view is a real three-column kanban.** `kb all` / `kb g` (and `kb` run
  outside any repo) now render the TO DO / DOING / DONE board shape aggregated across every
  registered board — each card still tagged with its `repo:` — instead of a flat list. `_board`
  gained `--all`: it collects all columns from home + the registry, sorts DONE newest-first
  cross-repo, and sums archived-goal counts. The flat-list `_all` was removed (dead code once
  both dispatch sites route to `_board --all`). `kb list`/`ls` stays the plain vertical list.

### Fixed
- **Font-independent board alignment.** The board's `│` separators didn't line up with the rows:
  the header used emoji (📋 🔵 ✅), which render 2 cells wide but `printf %-*s` counts as 1, and a
  missing `repo:` rendered as an em-dash (`—`, 3 bytes / 1 cell) — both desync the columns and both
  are font/terminal-dependent. The board is now ASCII-only (1 byte = 1 char = 1 cell), so alignment
  holds on any font, terminal, or bash version (verified: every `│` column at an identical position).

## [v2.2.1] - 2026-07-06

### Fixed
- **CI-only failure of `test-federated-kb` (green on macOS, red on Linux CI).** `_mtime`
  (`kanban/kb.sh`) and `_lock_epoch` (`factory/lib.sh`) tried BSD `stat -f %m` before GNU
  `stat -c %Y`. That order is fine on macOS but broken on Linux, where `stat -f` means
  `--file-system` and prints multi-line garbage for `%m`+file instead of failing cleanly — so
  `_mtime` returned junk, the `mtime|root` row corrupted, and `kb handoff`'s aggregated view
  rendered empty, failing the gate only in CI. Inverted to GNU-first (macOS's `stat -c` fails
  cleanly, so the BSD fallback still runs). `test/validate.sh` now also surfaces the
  `test-federated-kb` output on failure instead of hiding it behind a "see …" pointer — a
  failing gate must show its evidence, which is what pinned this down.

## [v2.2.0] - 2026-07-06

Non-breaking: the kanban goes federated and a multi-CLI dispatcher lands **wired but provably
dormant** (external-runner risk stays zero — it is hard-wired to refuse until a reviewed
OS-isolation floor exists). Reviewed by @rex (APPROVE) + @thor (PASS), every design fix proven
empirically.

### Added
- **Federated kanban + dormant multi-CLI dispatcher** (phases 1–6 of
  `docs/plan-2026-07-05-federated-kanban-multi-cli.md`). All additive; external-runner risk stays
  **zero** (the dispatcher is wired but hard-wired to refuse).
  - **Read-path** (`kanban/kb.sh`): cwd board resolution, `kb all`/`kb g` aggregated view across a
    local-only registry (`~/.roberdan-os/kanban-registry`), `kb handoff` (per-repo or aggregated).
  - **`kb init`**: idempotent per-repo privacy scaffolding — gitignore card columns, de-track
    already-committed card content, scan local history (pushed → refuse/human-gate #4, local-only →
    warn), install a leak-check pre-commit hook, register the board.
  - **`runner:`/`human_gates:` fields + `kb lint`** (`kanban/lint-cards.sh`): declarative CLI/model
    intent label (no execution change) + a lint enforcing `human_gates: ⇒ runner: human-only`.
  - **Atomic claim + repo locks** (`factory/lib.sh`): `mkdir`-based, keyed `<repo>+<id>`, with a
    stale sweep. `verify_card`/`note_card`/`resolve_model` extracted from `run.sh` into `lib.sh`
    (behavior-preserving), sourced by both `run.sh` and the dispatcher.
  - **Restricted dispatcher, dormant** (`factory/dispatch-runner.sh`, `factory/runner-sandbox.sh`,
    `factory/runner-shims/`): reachable via `kb dispatch`, with a fail-closed preflight. Preflight
    #5 (OS-isolation floor) and #8 (leak-check tier active) are **hard-wired to refuse** — #5 is a
    code constant no config can flip — so **every** external dispatch refuses until a reviewed code
    edit (phase 7) lands the OS floor.
- **Migration record** (`docs/federated-kanban-migration-2026-07-05.md`): roberdan-os migrated in
  place; MirrorBuddy cards kept in place with `kb init` on MirrorBuddy left as an un-crossed human
  gate.

## [v2.1.0] - 2026-07-05

Non-breaking follow-up to v2.0.0: a new quality rule, a rewired weekly watcher, and
Fable-5 reasoning guidance — all additive.

### Added
- **"Wired End-to-End" rule** (`rules/best-practices.md` v3.3.0 + `verify-done` skill): a feature
  that exists but is never reached from a live path is not done — it's dead code that looks done.
  Trace entry→caller→feature; prefer a mechanical proof (coverage gate) over human vigilance.
  Grounded in real failure modes from this repo's work.
- **Fable-5-scoped reasoning guidance** (`behavior/thinking-toolkit.md § Running on Fable 5`):
  effort doctrine (`high` default / `xhigh` for the hardest `board`/`socrates` calls / `low`
  routine), act-sooner-survey-less, clean final output, and a `reasoning_extraction` landmine
  note. Deliberately scoped — NOT written into the `model:opus` agent bodies where it would
  misfire. Effort knob also documented in the global model policy. From Anthropic's
  Prompting-Claude-Fable-5 doc, which validates the repo on 5 axes; addyosmani/agent-skills
  linked as a reference (not imported — redundant + over-prescription degrades Fable).
- Research + design docs for the multi-CLI thread (`docs/plan-2026-07-05-*`): CAO tested and
  rejected, kanban-as-handoff validated, the federated-kanban + sandboxed-dispatcher design
  (reviewed by @rex + @luca; dispatcher stays dormant until OS isolation).

### Changed
- **evolve watcher** (`evolve/watch.sh`): moved to **Saturday 02:00** (launchd catch-up runs a
  missed job at next boot/wake if the Mac was off) and now **drops a kanban card** per changelog
  novelty instead of a skeleton draft — any CLI (Claude, Copilot) executes it on its next run.
  No headless `claude -p`; the card is the cross-tool handoff. `RDA_KANBAN_TODO` override added
  for testability. Tested end-to-end (5 sources → 5 lint-clean cards).

## [v2.0.0] - 2026-07-05

### Changed (BREAKING)
- **Engine / identity split.** All forker-editable identity now lives in one place:
  `identity/` (voice, operator profile, twin persona, `identity.conf`). Engine files no
  longer embed identity, so `git merge upstream/main` stays conflict-free on engine files
  forever. See docs/plan-2026-07-05-engine-identity-split.md.
- **`behavior/roberto-voice.md` → `identity/voice.md`** (moved; content unchanged except
  one internal self-reference, `roberdan-twin` → `twin`). Update any local reference.
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
