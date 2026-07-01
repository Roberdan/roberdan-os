# Plan — `roberdan-os`: single, cross-platform, loop-autonomous agentic system

## Context

Roberto has ~200+ skills, ~300+ agents, hooks and personas scattered across 13+ repos, in 3+ formats, with no canonical source. The same agent (baccio, ali…) exists in 4-6 diverging copies; the global `~/.claude` config isn't even versioned. Two audits (2026-06-28 skill/agent, 2026-06-29 strategic Opus) mapped the problem: it isn't scarcity, it's **maintenance surface vs. real usage** — you probably use ~6 agents out of 87.

**Decision made with the user:** create a **new dedicated git repo `~/GitHub/roberdan-os`** as the single canonical source. Rebuild from scratch *only what's needed* (greenfield), cutting dead references — **without touching or removing anything from the legacy repos** (they keep working as they are). The new system must work on **Claude Code, GitHub Copilot (CLI + VS Code), Codex, ChatGPT / Claude web** (primary targets). **Hermes deprioritized** (didn't show up in the system scan; format unverified) — out of the must-work set for now, reactivatable with a "verify capabilities" gate. Every agent must operate in an **autonomous loop** aligned with Roberto's way of working (total autonomy + evidence-first + empirical verification).

### Two hemispheres of the behavioral canon
The system captures **two complementary faces** of Roberto, not one:
- **Operating / engineering** (`behavior/roberto-mode.md`, already built from 15,849 messages): how agents *operate* on code — autonomy, evidence-first, done-criteria, quality gates.
- **Voice / relationship** (new, from the Microsoft corporate Copilot — `~/Downloads/SKILL.md` + `profile.md`): how agents *communicate in his voice* and *decide like him* — drafting email/Teams, client follow-up, triage, decision-lens (relationship-before-transaction, bias-to-action, protect family/teaching, right-altitude), M.I.R.R.O.R.S., sign-off "Roberdan"/"Roberto", bilingual IT/EN/ES.

**Privacy gate (user decision — "split"):** the *style/voice* (non-sensitive) goes into the committed canon (`behavior/roberto-voice.md`); the *dossier* with Microsoft-confidential clients/deals/people (real names — clients, deals, contracts, UPN — stay only in the dossier) **does NOT enter git** — it lives only in `~/.roberdan-os/private/roberto-profile.md` (gitignored, local-only), read at runtime but never committed nor included in any public bundle. The concrete denylist lives in `private/.denylist` (also local-only).

**Expected outcome:** a single versioned source from which every tool consumes the same behavior; agents that self-verify and self-relaunch without manual polling; reliability guaranteed by durable state on file (Convergio remains an *optional* orchestrator, not a dependency).

### Architectural principle
**Centralized knowledge, per-platform execution, behavior unified by `roberto-mode`.**
`AGENTS.md` is the universal standard (Codex, Copilot, Hermes, Cursor read it natively); CLAUDE.md and copilot-instructions.md become thin pointers (the `convergio` repo already uses the CLAUDE.md→AGENTS.md symlink pattern — we adopt it as the model). The logic lives once; the runtime wrappers are generated for each tool.

### On reliability without Convergio (answer to the question)
The loop is reliable if state is **durable on file** (SQLite/jsonl at a known path) + **idempotent resume** + **terminal-condition** verified by hooks against ground truth (git/gh/cargo). No daemon required for the single-agent case. Convergio v3 (`:8420`, 36 MCP actions) enters only as an **optional observer/orchestrator** that *reads* the same state file — adoptable at zero cost in the future for cross-agent dispatch, but never a single point of failure. Daemon-optional design.

---

## Target structure of the `~/GitHub/roberdan-os` repo

```
roberdan-os/
  README.md                    # what it is, how each tool consumes it, install command
  AGENTS.md                    # universal entry point — every tool reads this
  behavior/
    roberto-mode.md            # ENGINEERING hemisphere (from ~/.claude/skills/roberto-mode)
    roberto-voice.md           # VOICE/relationship hemisphere (from Downloads/SKILL.md, scrubbed)
  agents/                      # minimal curated set — provider-neutral prose + optional claude frontmatter
    baccio.md  rex.md  luca.md  thor.md  socrates.md  wanda.md  roberdan-twin.md
  private/                     # NOT in git (.gitignore) — installed at ~/.roberdan-os/private/
    roberto-profile.md         # Microsoft-confidential dossier (clients/deals/people) — local-only
  rules/
    best-practices.md          # canonical quality rules (from ~/.claude/rules/best-practices.md)
    constitution.md            # slim ethical root (distilled from MyConvergio CONSTITUTION.md)
  skills/                      # logic in plain markdown; wrappers are generated
    verify-done/skill.md  ship/skill.md  review/skill.md  sync/skill.md  auto-checkpoint/skill.md
  loop/
    loop-protocol.md           # standard loop contract (state, terminal-condition, escalation, resume)
  hooks/                       # parametrized global guards (no hardcoded paths)
    main-guard.sh  bash-guard.sh  verify-done.sh  autofmt.sh  post-task-sync.sh
  platforms/                   # thin wrappers, generated by bin/sync.sh
    claude/   copilot/   codex/   chatgpt/   hermes/
  bin/
    sync.sh                    # generates wrappers from the canon + installs into ~/.claude and target tools
    make-bundle.sh             # concatenates ONLY the committed canon → 1 pasteable doc (excludes private/)
  test/
    validate.sh                # CI: frontmatter lint, link check, wrapper-vs-canon drift
```

---

## Implementation phases

### Phase 0 — Repo bootstrap
- `git init ~/GitHub/roberdan-os`, folder structure, `README.md`, `.gitignore`.
- Root `AGENTS.md`: index + `## Behavior` sections (`→ behavior/roberto-mode.md` + `→ behavior/roberto-voice.md`), `## Agents`, `## Rules`, `## Loop Protocol`. This is the file every tool reads.
- `.gitignore`: excludes `private/` (the confidential dossier must never enter git history).
- Apply best-practices repo-settings (merge-commit only) once it goes on GitHub.

### Phase 1 — Canonical content (the single source)
- **behavior/roberto-mode.md** ← canonical copy from `~/.claude/skills/roberto-mode/SKILL.md` (already built from 15,849 messages). *Engineering* hemisphere; all runtimes reference it.
- **behavior/roberto-voice.md** ← distilled from `~/Downloads/SKILL.md` (*voice/relationship* hemisphere): the 6 sections (voice non-negotiables, language, decision-lens, delegation playbooks, guardrails, few-shot) **with the few-shot scrubbed** of real client/person names → replaced with generic placeholders (`[Partner]`, `[Colleague]`). The style stays, the confidential data doesn't.
- **private/roberto-profile.md** (NOT committed) ← full copy of `~/Downloads/profile.md` (identity, FY26 portfolio, key people, M.I.R.R.O.R.S., "Good Morning"/"clawpilot"). Installed by `sync.sh` at `~/.roberdan-os/private/`; the twin reads it at runtime if present, otherwise degrades gracefully with a warning. Never in git, never in any bundle.
- **agents/** — 7 curated personas, schema from `rex.md` (the cleanest). Normalized frontmatter: `name, description, model, tools, providers, constraints, version, maturity`. `model` always quoted. Shared ethical block → reference to `rules/constitution.md`, not copy-pasted.
  | Canonical | Role | Consolidates |
  |---|---|---|
  | baccio | Architect + coding | — |
  | rex | Code + ecosystem review | rex(235r) + sentinel(249r) |
  | luca | Security | — |
  | thor | QA / verify-done guardian | — |
  | socrates | First-principles (pre-decision) | antonio/domik/matteo |
  | wanda | Loop orchestrator | ali |
  | **roberdan-twin** | Digital twin: drafting/triage/deciding in Roberto's voice | from `Downloads/SKILL.md` |
  - **roberdan-twin** reads `behavior/roberto-voice.md` (voice canon) + `private/roberto-profile.md` (dossier, if present). Own guardrails: **draft-not-send** for external/contractual/leadership matters, **never invent** names/dates/figures, respects personal blocks (evening/family/Polimi). Inherits human gates #3/#6.
  - The C-suite personas (amy/satya/dan…) are **not recreated** in roberdan-os (they remain intact in legacy). Real-usage verification command in the Appendix if you ever want to recover one.
- **rules/best-practices.md** ← canonical from `~/.claude/rules/best-practices.md`.
- **rules/constitution.md** ← distilled slim from `MyConvergio/.claude/agents/core_utility/CONSTITUTION.md` (8 articles → essence: Identity Lock, evidence-based Done, Thor-only done, accessibility). No `MICROSOFT_VALUES.md` (Convergio isn't Microsoft).

### Phase 2 — Canonical skills (only the cross-platform-worthy ones)
Logic in `skills/<name>/skill.md` (plain markdown, tool-agnostic checklist). Only porting the high-use, low-runtime-coupling ones:
- **verify-done** (evidence-first gate — your cardinal principle)
- **ship** (git+gh, platform-agnostic)
- **review** (code review)
- **sync** (aligns the 3 systems vault+cvg+repo)
- **auto-checkpoint** (the portable "loop kit" — see Phase 5)

NOT porting the CC-runtime-bound ones (browse, qa, ios-*, design-*, connect-chrome): they remain gstack on Claude Code.

### Phase 3 — Parametrized global hooks
Promoting to `roberdan-os/hooks/` (then installed into `~/.claude/settings.json`), removing hardcoded paths. Reconciling with the already-existing `pre-completion-gate.sh` on Stop and with the hook suite MyConvergio already references.
| Hook | Origin | Change |
|---|---|---|
| `main-guard.sh` | MirrorBuddy | rename env-var escape → generic; already worktree-aware |
| `bash-guard.sh` | MirrorBuddy | keep only the universal half of git/gh-safety; npm-rules stay per-repo |
| `verify-done.sh` | VirtualBPM | parametrize version-file location |
| `autofmt.sh` | VirtualBPM | repo-root detection instead of hardcoded frontend path |
| `post-task-sync.sh` | **new** | Stop/SubagentStop: regenerates repo-docs + cvg plan from vault, commits `chore(sync)` — mechanizes anti-drift across the 3 systems |
Protocol: JSON-decision (`hookSpecificOutput`) for the guards; silent style for formatter/notifier. Stay repo-local: `notify-app.sh`, `post-edit-ts.sh`.

### Phase 4 — Per-platform projections + `bin/sync.sh`
`sync.sh` generates the wrappers from the canon and installs them. No knowledge copied by hand — only generated.
| Platform | How it consumes | Generated wrapper |
|---|---|---|
| **Claude Code** | native | `~/.claude/skills/*/SKILL.md` (thin → `read skills/X/skill.md`), `~/.claude/agents/*.md` (symlink), `settings.json` hook snippet, `~/.claude/CLAUDE.md` → points to AGENTS.md |
| **Copilot CLI + VS Code** | no runtime SKILL.md | `.github/copilot-instructions.md` (thin → AGENTS.md), skill as `.prompt.md` |
| **Copilot standalone app** | to be verified | **verify at first install** whether it consumes a repo-level instructions file; until confirmed, treated as "to be verified" (no silent assumption) → fallback pasteable bundle |
| **Codex** | native AGENTS.md | `AGENTS.md` read directly; config snippet |
| **ChatGPT / Claude web** | no filesystem | `bin/make-bundle.sh` → 1 pasteable doc (roberto-mode + **roberto-voice** + best-practices + agents index) for Custom Instructions / Project. **Never** includes `private/roberto-profile.md` |
| **Hermes** | _deferred_ | not built now — "verify capabilities" gate before projecting to it. AGENTS.md remains already compatible if it reads it natively in the future |
For repos: every repo adopts the `CLAUDE.md → AGENTS.md` symlink pattern (the `convergio` model), and `AGENTS.md` references `roberdan-os` via the `## Behavior: [[roberto-mode]]` block.

### Phase 5 — Loop autonomy
- **loop/loop-protocol.md** — standard contract included in every loop-aware AGENTS.md:
  ```
  state: <state.db structured> + .agent-state/<task>.jsonl (cursor)
  terminal-condition: <job-specific empirical check, e.g. "cargo test green + CI #N pass">
  checkpoint: 1 commit per phase, evidence-first message (SHA/PR/CI in every update)
  escalation: 2 failed attempts on the same problem → opus, log reason
  sync-on-iteration: post-task-sync (vault+cvg+repo) at the end of EVERY phase
  resume: read state on startup, restart from the last done step, never redo
  stuck: 2 passes with no progress → STOP, report what's wedged, don't loop
  ```
- **skills/auto-checkpoint** — kit injectable into any session: writes/reads durable state, defines terminal-condition, enables auto-resume + auto-escalation.
- **Daemon-optional state store:** SQLite at a known path (`~/.convergio/v3/state.db` if present, otherwise `~/.roberdan-os/state.db`). RFC3339 timestamps. Readable by both hooks and Convergio if active — but the loop doesn't depend on the daemon.
- **Per-platform driver:**
  - Claude Code: `/loop` + `ScheduleWakeup` for external waits (CI/deploy/embed) — `submit → wakeup +Nmin → check terminal-condition → done | re-arm`.
  - Others: launchd/cron read the same checkpoint file.
- **Proactive reporting:** every checkpoint = evidence-first update (`[phase 3/7 ✓] commit a1b2c3d · CI #4821 green · next: …`), never "working on it".

### Phase 6 — Validation + CI + dogfood
- **test/validate.sh**: agent frontmatter lint, link check, **drift check** (regenerated wrappers == committed ones), hook shellcheck, **leak check** (no confidential client/person name in the committed canon or in the bundles — denylist from `private/`).
- GitHub Actions: runs validate.sh on every PR; merge-commit only.
- **Dogfood:** run a real task end-to-end in loop on Claude Code (e.g. a fix with `/loop`) verifying checkpoint, resume after kill, post-task-sync, evidence-first reporting.

---

## Human gates (what NOT to automate)
Autonomy ≠ black box. These **always** go through Roberto (direct message, not a coordinator relay):
1. Merge to `main` impacting branch-protection / security / license / release-infra
2. Force-push to `main`
3. Real spend / external emails / public publications
4. Deletion of non-regenerable data (vault notes, gbrain sources, repo history)
5. Strategic/product decisions with non-obvious tradeoffs (agent proposes with evidence, Roberto decides)
6. Material published in Roberto's / Fight the Stroke's name
7. Architectural changes >4 files with cross-cutting invariants

---

## Key files to create (representative)
- `~/GitHub/roberdan-os/AGENTS.md` — universal entry point
- `~/GitHub/roberdan-os/behavior/roberto-mode.md` — from `~/.claude/skills/roberto-mode/SKILL.md`
- `~/GitHub/roberdan-os/behavior/roberto-voice.md` — from `~/Downloads/SKILL.md` (few-shot scrubbed)
- `~/GitHub/roberdan-os/private/roberto-profile.md` — from `~/Downloads/profile.md` (gitignored, local-only)
- `~/GitHub/roberdan-os/agents/{baccio,rex,luca,thor,socrates,wanda,roberdan-twin}.md`
- `~/GitHub/roberdan-os/rules/{best-practices,constitution}.md`
- `~/GitHub/roberdan-os/loop/loop-protocol.md`
- `~/GitHub/roberdan-os/skills/{verify-done,ship,review,sync,auto-checkpoint}/skill.md`
- `~/GitHub/roberdan-os/hooks/{main-guard,bash-guard,verify-done,autofmt,post-task-sync}.sh`
- `~/GitHub/roberdan-os/bin/{sync.sh,make-bundle.sh}`
- `~/GitHub/roberdan-os/test/validate.sh`

## Reuse (don't reinvent)
- `~/.claude/skills/roberto-mode/SKILL.md` (behavioral canon already ready)
- `~/Downloads/SKILL.md` + `~/Downloads/profile.md` (Microsoft digital twin — voice + dossier, to split canon/private)
- `~/.claude/rules/best-practices.md` (quality rules already written)
- `MyConvergio/.claude/agents/core_utility/CONSTITUTION.md` (ethical root to distill)
- `MyConvergio/.../technical_development/rex.md` (canonical frontmatter schema)
- Existing MirrorBuddy/VirtualBPM hooks (to parametrize, not rewrite)
- `convergio` CLAUDE.md→AGENTS.md symlink pattern (model to propagate)
- `~/.claude/hooks/pre-completion-gate.sh` (already active on Stop — reconcile)

## End-to-end verification
1. **Install:** `roberdan-os/bin/sync.sh` → check that `~/.claude/skills/`, `~/.claude/agents/`, `settings.json` hooks are generated and valid (`claude` starts without errors).
2. **Claude Code:** invoke `/roberto-mode` and an agent (e.g. `@rex`) → verify they read from the canon.
3. **Copilot:** open a repo with a generated `.github/copilot-instructions.md` → confirm Copilot CLI loads the profile.
4. **Codex:** in a repo with `AGENTS.md` → confirm Codex honors it.
5. **ChatGPT/Claude web:** `make-bundle.sh` → paste the bundle into a Project → confirm aligned behavior. **Privacy check:** `grep` on the generated bundle confirms 0 real client/person names (no leak from `private/`).
6. **Twin:** invoke `roberdan-twin` with a drafting task → confirm correct voice (warm-open, next-step, sign-off), draft-not-send honored, dossier read from `~/.roberdan-os/private/` (or clean degradation if absent).
7. **Privacy gate:** `git status`/`git log` of roberdan-os never show `private/`; `.gitignore` excludes it; `test/leak-check.sh` (grep `-iE -f private/.denylist`) = 0 hits on canon and bundles.
8. **Loop:** real task with `/loop` on Claude Code → kill the process midway → verify resume from checkpoint, post-task-sync, and evidence-first update.
9. **Drift:** `test/validate.sh` green (wrapper in sync with the canon).
