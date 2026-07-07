# Changelog

All notable changes to roberdan-os. Format: [Keep a Changelog](https://keepachangelog.com);
versioning: semver on the system's behavior/tooling (the paper has its own version).

## [v2.7.1] - 2026-07-07

### Fixed
- **H1 (rex, HIGH): generated `settings-hooks.json` carried literal `$RDA_OS`** — a variable
  defined nowhere. A verbatim merge on a fresh install/fork expanded it empty
  (`/hooks/main-guard.sh`) and the security guards died silently. `bin/sync.sh` now expands
  the repo root at generation time (as `bootstrap.sh` already did); same expansion for the
  codex README snippet. New `validate.sh` guard: the emitted snippet must contain no
  unexpanded `$VAR` (`ok: settings-hooks.json fully expanded`).

### Added
- **Audit addendum §5** in `docs/report-2026-07-07-best-practices-2026.md` — third-session
  independent verification of the v2.7.0 release claims: actor map corrected (THREE concurrent
  sessions, not two), 6/6 release claims re-verified empirically, AGENTS.md session-tax measure
  updated to the post-compression truth (161 lines / ~1.259 words ≈ ~1.7k tokens; the §4 table
  reported the pre-compression 183 / ~2.9k).
- **Tool-receipts emitter wired for real** (closes the rex HIGH "declared but unwired" gap,
  Roberto's go): `loop/receipt.sh` appends JSONL receipts `{ts, task, cmd, exit, artifact,
  note}` to the loop cursor; the Stop-hook auto-checkpoint emits a mechanical per-turn receipt
  (`session.jsonl`) automatically. Placement is opt-in-safe (in-repo `.agent-state/` only where
  already ignored; else `$RDA_HOME/state/receipts/<repo>/`). `test/test-receipts.sh` (5 cases)
  wired into validate.sh §8c; loop-protocol + thor gate #10 updated to the real contract.
- **Docs freshness pass** (audit H1-H4/M1-M10/L1-L4, all findings verified): bootstrap now
  installs the `kb` symlink and points its manual steps at the generated five-event hook
  snippet; QUICKSTART adds the `bin/sync.sh --install` step (its ALL-GREEN promise was false
  for forkers); README status/tables/prerequisites refreshed (python3 required); `docs/plan.md`
  banner'd as historical; kanban/USAGE document `kb pause/resume` + federation; scheduling
  cadence corrected (evolve = Sat 02:00); factory-protocol dead flag `RDA_FACTORY_PARALLEL`
  marked planned-not-implemented; ARCHITECTURE notes the native CLAUDE.md symlink path.
- **validate.sh**: agent frontmatter lint now requires `effort:` (so the new field can't
  silently drift off an agent) + §8c receipts gate.

## [v2.7.0] - 2026-07-07

### Added
- **Context & Token Economy** section in `rules/best-practices.md` (v3.5.0): always-loaded
  instruction files ≤200 lines with the "would removing this cause mistakes?" per-line test,
  just-in-time retrieval over pre-loading, subagent exploration isolation, prompt-cache
  discipline (stable prefix, model+effort picked once), durable state on disk over
  in-conversation state, runaway loop = cost incident. (Anthropic context-engineering +
  Claude Code best practices, 2026.)
- **Agent supply-chain rules** in `rules/best-practices.md` § Security: third-party skills/MCP
  servers reviewed before install and re-reviewed on update; no unreviewed MCP server in a
  session that can read `private/`; blast-radius over prompt-level pleading. (Snyk ToxicSkills
  2026-02; OWASP Agentic Top 10 2025-12.)
- **Provenance gate in @thor** (v1.1, gate #10): verify *how* an artifact came to exist (git
  history, re-run/traceable test output, loop-cursor receipts), not just that it exists — anti
  reward-hacking. (EvilGenie benchmark + Anthropic evals guidance, 2026.)
- **Tool receipts in the loop cursor** (`loop/loop-protocol.md`): each step records what ran and
  what it returned (command, exit code, artifact SHA) — a transcript is context, not a recovery
  log; verification probes live state, never grades the transcript. (Managed Agents, 2026-04.)
- **Delegation-not-impersonation guardrail in @twin** (v2.1): machine-readable trails sign as
  the operator's assistant; EU AI Act Art. 50 disclosure norm (operative 2026-08-02) if a fully
  automated external interaction is ever enabled — draft-not-send unchanged.
- **Root `CLAUDE.md → AGENTS.md` symlink**: Claude Code loads the canon natively in-repo
  (official recommendation for AGENTS.md-native repos); forkers get oriented without the
  SessionStart hook installed.
- **`effort: xhigh` frontmatter** on board/socrates (subagent frontmatter supports effort in
  2026) — the effort doctrine's hardest capability-sensitive calls, now wired.

### Fixed
- **`hooks/autofmt.sh` was a silent no-op**: it read `CLAUDE_FILE_PATH`, an env var the modern
  hook API never sets (hooks receive JSON on stdin). Now parses `.tool_input.file_path` from
  stdin, legacy env var kept as manual-run fallback.
- **`settings-hooks.json` snippet drifted from the canon**: it lacked the SessionStart
  context-inject and the Stop auto-checkpoint that AGENTS.md § Pause & Resume declares
  always-on. Now emitted complete, plus a PreCompact checkpoint so durable state is saved
  *before* the context window is compressed (SessionStart with no matcher re-injects after
  compact too).

### Changed
- Best-practices research pass 2026-07-07 documented in
  `docs/report-2026-07-07-best-practices-2026.md` (research synthesis, gap analysis, applied
  vs proposed — incl. the ~6.4k-token global `~/.claude/CLAUDE.md` slimming proposal left to
  Roberto), with the full-repo audit (efficiency, effectiveness, autonomy, reliability,
  cost/token). **Two sessions ran the same goal concurrently** and converged: session B's
  disjoint-file pass (`docs/report-2026-07-07-best-practices-2026-session-b.md`) landed the
  complements below; @rex audited both (APPROVE-WITH-CONCERNS → concerns fixed in this release).
- **Session B (same pass, disjoint files):** AGENTS.md § Pause & Resume + § Privacy compressed
  ~30% at equal contract; **zero-progress screen** as gate #0 in @thor (v1.2) and
  `verify-done.sh` (cheapest predicate first: durable state must have changed at all);
  explicit hook timeouts + `disable-model-invocation` passthrough in generated skill wrappers
  (ship gated); Convergio demoted to optional observer everywhere in roberto-mode (no
  done-gate deadlock on a daemon that isn't running); context-inject cry-wolf fix (loud
  PAUSED banner only on explicit `kb pause`); `curate.sh` atomic per-candidate vault commits;
  `verify-done.sh` parses the real top-level manifest version; `effort:` frontmatter across
  all agents (baccio/luca/rex/thor/twin high, wanda medium, board/socrates xhigh).
- **@rex concerns closed:** duplicate `effort:` keys deduped (concurrent-edit artifact);
  loop-protocol receipts + thor provenance gate now state the honest wiring
  (`.agent-state/*.jsonl` is a declared format with **no in-repo emitter yet** — phase-commit
  evidence + kb audit lines are today's receipts); the ≤200-line rule carries its own scope
  note (this file is bundled verbatim for ChatGPT/web → prune-before-add duty);
  `test/test-autofmt.sh` added and wired into validate.sh (the silent-no-op class of bug now
  has a regression gate).

## [v2.6.0] - 2026-07-07

### Changed
- **Resume the WHOLE plan, not just the paused task.** The pause checkpoint is single-task by
  design, and on a session restart the agent tunneled on it — it drove only the checkpointed
  next-step and looked at the rest of the backlog only when prompted. Fixed on two levers: (1)
  `kb resume` now prints the checkpoint **plus the live backlog** (todo + doing) with a reminder
  that the checkpoint is the re-entry *point*, the board + `handoff/latest.md` are the *scope*; (2)
  AGENTS.md § Pause & Resume reworded — "continua/riprendi" means re-hydrate and drive the whole
  plan forward, every open thread and pending decision, with human gates still applying on resume
  (`todo->doing` stays Roberto's; never auto-cross a gate).

### Fixed
- **`kb init` no longer pollutes a shared repo's history, and ignores the right file.** Two coupled
  bugs (Roberto's decision, option B): (1) it appended federation ignores to the committed
  `.gitignore`, so federating a repo wrote Roberto-machine-only noise into shared history — now they
  go to the **local `.git/info/exclude`** (self-sufficient on any machine, unlike a global
  `core.excludesfile`, without touching shared git state; shared across worktrees via the common git
  dir). (2) It ignored `handoff/latest.md` (roberdan-os's *tracked* canon file) instead of
  `handoff/resume.md` (the ephemeral per-repo pause checkpoint `kb pause` actually writes) — so the
  rule matched a file that never exists in siblings. This was the exact stale-rule mess found in
  Fabrica/MirrorBuddy/convergio, whose committed `.gitignore` lines came from the old `kb init`.
  Test strengthened: asserts `resume.md` is excluded and the committed `.gitignore` is never touched.
  Federation design + migration docs aligned to the new mechanism (the gate to federate a *shared*
  team repo stands — it's now an organizational, not a git-history, decision).

## [v2.5.0] - 2026-07-06

### Added
- **"No False Done" — the cardinal reliability rule** (`rules/best-practices.md` v3.4.0, top of
  file; reinforced in the `verify-done` skill). Never claim done/verified/working/green/released
  until the evidence for THAT claim is observed end-to-end: a claim needs evidence for itself
  ("released" ⇒ CI green on the release commit confirmed, not "I pushed"), whole-system not just
  the touched part, "should/probably" ≠ "is", prefer a mechanical gate that carries the evidence,
  and on a wrong claim say so first with the fact. Documents the real 2026-07-06 miss (v2.4.0
  announced released while its CI was red). The lever is verification + gates, not temperature.

## [v2.4.2] - 2026-07-06

### Fixed
- **Skill/agent wrappers broke skill loading in Copilot CLI.** `bin/sync.sh` wrote the frontmatter
  `description:` as an *unquoted* YAML scalar. Descriptions contain `: ` (colon+space) and
  apostrophes, so any such description failed to parse (`mapping values are not allowed`) — silently
  dropping the affected skills at load time (`focus-group`, `premortem`, `problem-validation` were
  the casualties). The generator now emits every description as a double-quoted, escaped scalar
  (new `yaml_dq` helper, applied to both skill and agent wrappers). Added a regression guard in
  `test/test-sync-install.sh` that emits into a clean temp dir and asserts every generated wrapper
  description is a quoted YAML scalar.

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
