# Changelog

All notable changes to roberdan-os. Format: [Keep a Changelog](https://keepachangelog.com);
versioning: semver on the system's behavior/tooling (the paper has its own version).

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
