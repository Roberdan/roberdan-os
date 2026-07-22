# Changelog

All notable changes to roberdan-os. Format: [Keep a Changelog](https://keepachangelog.com);
versioning: semver on the system's behavior/tooling (the paper has its own version).

## [v2.18.0] - 2026-07-22

### Added
- **Plain language toward Roberto is now a NON-NEGOTIABLE rule, enforced at the system-prompt
  level.** The § Communicating contract existed since v2.x but was advisory prose buried in a
  222-line JIT-loaded file, and Roberto reported — plainly — that he still struggled to follow
  what agents told him and asked of him. The rule is now a row in `behavior/roberto-mode.md`
  § NON-NEGOTIABLE (answer first in plain words → what's needed from him and why → technical
  detail below), backed in Claude Code by a new output style (`~/.claude/output-styles/
  roberto-plain.md`, activated via `outputStyle`), which edits the system prompt every turn
  instead of hoping a prose rule survives context-rot. Honest limit: the output style is
  Claude-Code-only; Copilot/Codex/web carry the rule through the canon alone.
- **`kb cover` — the plan→card gate the canon promised.** Fails red on any normative clause in a
  plan with no card and no written decision, wired into `test/validate.sh`. Companion to the new
  `rules/best-practices.md` § Carded End-to-End (a requirement that never becomes a card is
  invisible to `kb`, `@thor`, the merge-gate and CI simultaneously) and § the three structural
  holes that let a false done through.
- **Train/val split gate in `eval/`** so a canon change can't be judged by the fixtures it was
  written against.
- **Rejected-proposal buffer in `evolve/`** — the changelog watcher stops re-proposing what was
  already declined.
- **`bin/copilot-local`** — opt-in Copilot CLI against a local Ollama model (BYOK).

### Fixed
- **`kb` done-gate is mechanical, not rhetorical**: `--thor` evidence must actually resolve
  (commit/file/test output), not merely be non-empty.
- `kb add` refuses unknown flags instead of silently swallowing them into the card title.
- `kb pending` hardened; card-ID collisions handled.
- `kb` warns when `RDA_KANBAN` silently points at a board other than the repo's own.
- `leak-check`: plain-word terms are anchored and binaries skipped — fewer false positives
  without loosening the gate.
- Copilot's kanban tool now reads the same board source as the `kb` CLI.

### Changed
- The `CLAUDE.md` pointer block is now the canonical slim source, killing drift between the
  global pointer and the repo canon.

_Release hygiene note: `v2.16.0` and `v2.17.0` were written to the changelog but never tagged.
This release tags `v2.18.0` at HEAD; the two intermediate versions remain changelog-only._

## [v2.17.0] - 2026-07-11

### Added
- **Session-lifecycle contract (session-cost efficiency pilot, 2-week measurement window).**
  Following measured Copilot session-cost signal (247.4:1 input:output token ratio, top-session
  concentration, 18/47 sessions growing ≥1.5x across quartiles; Baccio/Board convergence:
  phase-as-session is the key lever), `loop/loop-protocol.md` § "Session-as-phase-container" is
  now the **single canonical home** for the lifecycle contract: `/compact` continues the same
  phase; `/new` at natural phase boundaries, before a heavy skill/attachment-bearing step, or
  before changing model/effort; cutting a session changes the *container*, not the task (a small
  durable handoff packet — see `handoff/handoff-protocol.md` — carries the task across the cut).
  `rules/best-practices.md` now carries a one-line pointer instead of restating the contract,
  removing the duplication an independent @rex review flagged.
- **Owned always-loaded context footprint reduced.** The prior commit (6763bb3) touching this
  contract landed net *larger* than its parent (296+28=324 lines across the two files
  `bin/make-bundle.sh` and Copilot actually load unconditionally: `rules/best-practices.md` +
  `.github/copilot-instructions.md`) despite the stated goal being context slimming. This release
  corrects that: the same two files now total 319 lines — tied with the pre-session-lifecycle
  parent (96c1cf5) and down 5 lines from 6763bb3, while the full contract detail still lives in
  full in `loop/loop-protocol.md` (JIT-loaded only, not part of the always-on budget).
  `rules/best-practices.md` remains above its own internal ≤200-line aspirational target
  (291 lines) — that overage predates this change and 6763bb3; a full prune is out of scope here.
- **`test/validate.sh`: mechanical invariant for the shortened `.github/copilot-instructions.md`
  pointer.** That pointer now reads "full 7-item list is AGENTS.md § Human gates" instead of
  restating all seven gates inline (safer — the old inline copy had silently drifted and omitted
  gate #7). A new deterministic assertion proves root `AGENTS.md` exists and its `## Human gates`
  section still lists exactly seven sequentially-numbered gates, so the pointer can never again
  silently point at a stale or incomplete list.

### Fixed
- **`hooks/copilot/extension.template.mjs`: corrected an inaccurate SDK comment.** The prior
  comment claimed Copilot hooks "expose only workingDirectory, toolName, toolArgs and error" —
  contradicted by `@github/copilot-sdk@1.0.6`'s own types (`onSessionStart` carries
  `sessionId`/`timestamp`/`source`/`initialPrompt`; `onSessionEnd` carries
  `reason`/`finalMessage`/`error`; `onPostToolUse` carries a `toolResult` with
  `textResultForLlm`/`resultType`/optional `sessionLog`/`toolTelemetry`). The comment now states
  only the defensible fact: none of that is a *validated* token/usage field — tool-result bytes
  and `toolTelemetry` are proxies at best, not a verified correlation to context size — so this
  release still ships **no** telemetry, threshold, or warning built on top of them (deferred, as
  originally scoped; not a walk-back).
- **`test/test-pending.sh`: deterministic SIGPIPE false failure.** Under `set -o pipefail`,
  `printf ... | grep -q ...` can legitimately exit 141 (grep exits at first match, killing
  `printf` mid-write via SIGPIPE) — not a flake, a guaranteed race between two specific
  constructs. Rewritten as here-strings (`grep -q ... <<<"..."`), which never pipe. Verified
  deterministic pass across repeated runs.
- **`test/test-federated-kb.sh`: credential-vacuum probe read contaminated ambient env.** The
  CI/sandbox environment can inject its own `GIT_CONFIG_PARAMETERS`/`GIT_CONFIG_*` (e.g. a
  `gh`-auth git-credential trampoline); the test's "outside" canary leg didn't strip these before
  asserting no vacuum, so it could pass or fail on unrelated ambient config rather than the
  `factory/runner-sandbox.sh` isolation actually under test. Both probe legs now strip ambient
  `GIT_CONFIG_*` first. `factory/runner-sandbox.sh`'s real isolation logic was unchanged and
  independently confirmed sound — this was a test-harness hygiene bug, not a security defect.
  Both of the above were previously, incorrectly, called "flaky"/reported as the sole failure in
  kanban evidence; they are deterministic and both are now fixed. Corrected record: full
  `bash test/validate.sh` is genuinely green, confirmed across repeated consecutive runs.

### Note (accurate version citation)
- The parent commit's message referenced "Copilot CLI v2.16" — that conflated roberdan-os's own
  version (2.16.0) with the installed GitHub Copilot CLI binary (1.0.70 at the time). Corrected
  here rather than by amending the already-pushed/reviewed commit: roberdan-os and the Copilot CLI
  binary version independently; the AGENTS.md-native-loading behavior itself was accurately
  documented and is unaffected.

### Reviewed
- **@rex:** original APPROVE-WITH-FINDINGS (context-budget self-violation + duplicate policy
  HIGH; inaccurate SDK comment MEDIUM; version citation LOW; missing mechanical invariant for the
  shortened human-gates pointer LOW/high-value; validation-truth and kanban-evidence findings).
  All findings addressed in this release; see items above.

### Pilot caveat
- This is a **2-week measurement pilot** for the session-lifecycle contract. No token or dollar
  savings are claimed yet — that requires the pilot's own before/after session data.

## [v2.16.0] - 2026-07-10

### Added
- **Native GitHub Copilot adapter — operational near-parity in stock Copilot CLI, no separate
  SDK host.** roberdan-os now drives Copilot through its own first-class extension surface
  instead of relying on skills + a global instructions pointer alone. Generated deterministically
  from the canon by `bin/sync.sh`, installed collision-safely (never overwrites, always symlinks
  so it tracks the canon):
  - **Copilot custom agents** — one wrapper per `agents/*.md` that lists provider `copilot`,
    in Copilot's authoritative frontmatter (description required; canonical tools mapped to
    Copilot aliases `read/edit/execute/search/web`; coarse model tier mapped to a concrete id,
    which degrades gracefully to the session model if unavailable). Symlinked into
    `~/.copilot/agents/<name>.md`, skipping any pre-existing same-named file.
  - **User-scoped extension** `~/.copilot/extensions/roberdan-os/extension.mjs` — the native
    binding of the provider-neutral `hooks/`, sourced from `hooks/copilot/extension.template.mjs`
    (repo root baked at emit time; a runtime `RDA_OS` env still overrides for forks):
    - `onSessionStart` → `hooks/context-inject.sh` (fresh durable context injection).
    - `onPreToolUse` → `hooks/main-guard.sh` + `hooks/bash-guard.sh`, mapped to Copilot
      `allow/ask/deny`. A guard can only tighten, never loosen (safe actions defer to Copilot's
      own permission flow). **A guard failure maps to `ask`, never a silent success-shaped allow.**
    - `onPostToolUse` → `hooks/autofmt.sh` (best-effort format after edits, never blocks).
    - `onPostToolUseFailure` → ephemeral observability log (no hidden model steering).
    - `session.idle` / `onSessionEnd` → the Claude "Stop" chain (pre-completion-gate → verify-done
      → post-task-sync → always-on auto-checkpoint), throttled + serialized to avoid duplicate/
      reentrant runs.
    - Safe, globally-unique namespaced tools: `roberdanos_kanban` (board reads + gated
      add/start/finish/block — the todo→doing Roberto gate and doing→done @thor evidence gate are
      enforced by `kb.sh` itself, never bypassed), `roberdanos_pause`, `roberdanos_resume`,
      `roberdanos_verify_done`, `roberdanos_doctor` (wiring diagnostic; reports gbrain MCP presence
      without ever reading/echoing the secret-bearing `mcp-config.json`). No arbitrary shell proxy.
  - `bin/sync.sh --install` extends to `~/.copilot/agents` (`RDA_COPILOT_AGENTS_DIR`) and
    `~/.copilot/extensions` (`RDA_COPILOT_EXT_DIR`), same no-silent-overwrite posture as the skills
    install; a total no-op when `~/.copilot` is absent. `mcp-config.json` remains read-only (WARN if
    gbrain missing) — Copilot owns that file and it holds secrets.
  - `test/test-copilot-adapter.sh` (wired into `validate.sh` + the tool-coverage gate): deterministic
    emission, frontmatter/tool/model mappings, collision-safe install, no-write-when-absent,
    real ESM load against a stubbed SDK, PreToolUse guard mapping (deny/ask/allow + fail-safe),
    idle dedup/throttle wiring, and the privacy check on `mcp-config.json`.

### Known limitation (operational near-parity, stated honestly)
- **No bit-for-bit Claude `Stop` parity.** Copilot exposes `session.idle`/`onSessionEnd` only
  *after* a turn's final assistant message is produced, and there is no proven Copilot hook that
  can block or rewrite that message. So `verify-done` / `pre-completion-gate` run as **advisory
  warnings + side effects** in Copilot — they cannot hold back a premature "done" claim the way the
  Claude Stop hook's blocking output can. The always-on pause/resume checkpoint, the PreToolUse
  guards (which *can* deny/ask before execution), context injection, custom agents, and the native
  tools are full-fidelity; the completion gate is advisory only.

### Reviewed
- **@luca (security):** no high-confidence vulnerabilities — command-injection (argv-only spawn,
  no shell string, no exec proxy), secret exposure (`mcp-config.json` probed only for the `gbrain`
  token, never read out), install safety (collision-safe, no-op when `~/.copilot` absent), human-gate
  preservation, and path/symlink handling all refuted.
- **@rex (ecosystem/code):** two findings, both resolved before commit — (Medium) `onPreToolUse`
  did not forward the session `workingDirectory`, so `main-guard.sh` could fail *open* on a relative
  path when the extension cwd ≠ the session repo → fixed by threading `cwd` into `applyGuard`, with a
  relative-path-on-`main` regression test; (Low) the `validate.sh` tool-coverage asserts hardcoded the
  substring `roberdan-os/platforms/`, false-failing worktree/fork installs → fixed to a structural
  `…/platforms/copilot/{agents,extension}/…` match.
- **@thor (done-gate, fresh context):** round 1 REJECTED on empty/broad catches + a silently-dropped
  autofmt failure in the extension (criterion 3 "no hidden failures"). Resolved: every catch now binds
  the error and routes it to a single stderr `diag()` sink (stdout stays JSON-RPC-only), autofmt
  non-zero exits are reported (not swallowed), and `test-copilot-adapter.sh` gained a guard against any
  bare empty catch / silent no-op handler regressing.

## [v2.15.1] - 2026-07-09

### Fixed
- **`pre-completion-gate.sh` promoted from private `~/.claude` to canon** (`/doctor` run
  found it: the Stop-event done-gate hook — checks open PRs, orphan worktrees, rogue
  convergio runners, uncommitted changes before a completion claim — existed only in
  Roberto's local `~/.claude/hooks/`, hardcoded to that path, invisible to a fresh
  `roberdan-os` clone despite firing on every turn. Now lives in `hooks/`, wired into
  `bin/sync.sh`'s generated Stop-hook chain (first hook, matching its live position).
  `~/.claude/hooks/pre-completion-gate.sh` and `~/.claude/rules/best-practices.md` (a
  second drifted private copy found the same way, stale since May) are now symlinks
  into this repo — no more silent divergence between what Roberto's machine runs and
  what the canon documents.
- **`test-factory-kb.sh` flaky under system load — root cause fixed.** `validate.sh` failed
  once, then passed clean standalone and on a full re-run: the test fixtures dispatch a
  trivial mock `claude` binary (`exit 0`/`exit 5`) through the real `factory/run.sh`, which
  wraps it in a hard wall-clock `timeout`/`gtimeout` — fixtures set `timeout: 5`, tight enough
  that ordinary scheduler contention (many concurrent processes, as in this very session) can
  occasionally exceed it even though the mock exits instantly. Bumped all 14 fixture
  `timeout:` values from 5s to 30s (pure test-data slack, doesn't change what's asserted);
  confirmed with 3 consecutive full `validate.sh` green runs, including one running
  concurrently with other load.

## [v2.15.0] - 2026-07-09

### Added
- **Plain-language gate — agents must communicate FOR Roberto, not for a log** (Roberto's
  observation: explanations, updates, and the decisions he's asked to make are often too dense or
  jargon-heavy to follow, with implications left unstated). A first-class behavioral rule, on par
  with "No False Done", in `AGENTS.md § Behavior` + `behavior/roberto-mode.md § Communicating`,
  so it travels to every tool (Claude, Copilot, Codex):
  - **no unexplained jargon** — when Roberto will read it, say what a SHA / flag / term *means*;
  - **every decision carries its implications in his terms** — what A vs B leads to, cost, risk,
    and a recommendation; a question he can't answer for lack of context is the agent's failure to
    explain, not his to understand;
  - **end-of-task = one plain sentence** (what happened + what's needed from him and why), technical
    detail below, never as the headline;
  - **answer first, depth after** (progressive disclosure);
  - **"I don't understand" is feedback about the writing** — re-say it simpler, not louder.
  Framed as an accessibility and respect commitment.

## [v2.14.2] - 2026-07-09

### Changed
- **A couple of the coaching methodologies now live in the default way of thinking** (Roberto's
  question "does it make sense to add some of these to how roberdan-os itself thinks?"). Two were
  worth it and are **integrated into the existing mother-rule steps**, not added as new rituals:
  - step 2 (first principles) gains **distrust of absolutes** — "always / never / impossible / we
    have to" is a System-1 shortcut, not a fact; test it;
  - step 4 (prove yourself wrong) gains a **Kahneman bias-check** — a fast, confident answer is
    exactly when to slow down and name the likely bias.
  Deliberately *not* added to the default: GROW, reframing, one-question-at-a-time — those are
  interpersonal *coaching* moves; making them default would turn every reasoning into a ceremony,
  which is the "pretend to think" the mother-rule exists to prevent. Discipline is adding *little*.

## [v2.14.1] - 2026-07-09

### Changed
- **`@coach` now composes with the whole roberdan-os arsenal instead of being an island** (v1.1,
  Roberto's point: "doesn't it make sense to put in the coach things we already have, used this
  way?"). New "Compose — don't reinvent" section makes the coach a conductor that reaches, *in
  coaching form (as questions)*, for what already exists:
  - **Roberto's own decision-lens first** (`identity/voice.md`) — reflect *his* criteria back
    (relationship-first, bias-to-action, purpose/impact, protect family, right-altitude) instead
    of importing external ones. The best coaching question is often his own value made explicit.
  - the **`thinking-toolkit` repertoire turned into questions** (one/two-way door, base rates,
    regret-minimization, Cynefin, theory-of-constraints, Chesterton's fence);
  - the **discovery/validation skills** when they fit (`premortem`, `problem-validation`,
    `focus-group`); and the other **agents** called in (`@board`, `@socrates`) — not replaced.

## [v2.14.0] - 2026-07-09

### Added
- **`@coach` — a maieutic thinking coach** (Roberto's /goal). Helps him reason, decide, and
  challenge himself *by drawing the answer out* — a light GROW loop (Goal → Reality → Options →
  Will), one good question at a time. Deliberately distinct from the reasoning agents it sits
  beside: `@socrates` deconstructs (cold), `@board` red-teams (adversarial), `@coach` is the
  warm inside voice that **guides, never decides** (the call stays Roberto's, gate #5) and never
  red-teams. Registered in AGENTS.md + the global `~/.claude/CLAUDE.md` block, symlinked into
  `~/.claude/agents` (invokable now). @thor-gated PASS.
- **`thinking-toolkit` enriched with Kahneman + coaching tools.** The bias section is now framed
  around **Kahneman's System 1 / System 2** (*Thinking, Fast and Slow* — Nobel, empirical) with
  the catalogue extended (availability/recency, loss aversion/framing, overconfidence/planning
  fallacy). New **Coaching & reframing** section: GROW, well-formed outcome, meta-model (language
  discipline against "everyone/never/I have to/impossible"), reframing. Feynman first-principles
  kept as before.
  - **Honesty (evidence-first):** the reframing/meta-model techniques have NLP roots but are kept
    for what they *demonstrably do* (grounded in CBT / goal-setting), **not** given NLP's
    scientific authority, whose theoretical claims don't hold. Neither cargo-culted in nor
    scrubbed out — the honest middle.
- **`kb repo <name>` — a per-repo dashboard** on top of the kanban: git state (branch, dirty,
  last commit, ahead/behind vs origin), open non-bot PRs, and that repo's cards grouped
  doing/todo/done. Handles local-only repos (no origin) without aborting. Test-covered.

### Changed
- **Canon: `kb start` at the BEGINNING of the work, not retrospectively** (AGENTS.md +
  kanban/README). A card should *live* in `doing` for the duration of the task so `doing` shows
  what's actually in progress — instead of the observed pattern where agents batch add+start+finish
  at the end and `doing` is always empty.

### Known follow-up (non-blocking, from @thor)
- `claude-ai-skill/roberto-mode/THINKING.md` (a hand-curated, intentionally non-sync'd web export)
  is now stale vs the Kahneman/coaching toolkit — re-derive by hand on a future pass.

## [v2.13.0] - 2026-07-09

### Added
- **`kb` board now shows what each card is, not just its ID.** The 3-column box stays compact
  (ID + repo, for the at-a-glance layout), and a **legend below it** lists every *active* card
  (todo + doing) as `<id> (<repo>) — <title>`. The legend lives outside the box on purpose:
  titles are long and may be non-ASCII (accents), which would desync the box's fixed-width
  column separators if placed inside a cell. Done cards are omitted (many, and finished). So
  the aggregated board is now readable — you can tell `260708-120132` is "Decidere: OS-isolation
  floor (ADR-0002)" without opening the card.

## [v2.12.1] - 2026-07-08

### Fixed
- **`kb init` pre-commit hook hung and scanned the wrong repo.** The generated hook called
  `leak-check.sh` with no args, and leak-check's *default* target is roberdan-os's own tree
  (`git ls-files` in its own ROOT) — so on every commit of *another* federated repo it
  re-scanned all ~200 roberdan-os files (slow, hung past 2 min on repos with large blobs) AND
  never actually checked the committing repo's files. Two-part fix:
  - `test/leak-check.sh` gains an **`--only <files…>`** flag: scan exactly the given files, not
    the default tree. Backward-compatible — validate.sh and `make-bundle.sh` (no flag) are
    unchanged.
  - the `kb init` hook template now passes the repo's **staged files** (`git diff --cached`,
    absolute paths) to `leak-check.sh --only`, so it checks the right files, fast (0.2s vs a
    2-minute hang), and skips cleanly when nothing is staged.
  - Regenerated the already-installed hook in every kb-init'd repo (Fabrica, the-standing-egg,
    MirrorBuddy, trading-os). Verified: a commit's pre-commit now runs in ~0.24s.

### Note (machine ops)
- **AGENTS.md/CLAUDE.md pointers added to the personal federated repos** (Fabrica,
  ConvergioEdu2030, the-standing-egg, trading-os): thin pointers to the canon that tell any agent
  working there to operate in roberto-mode and **track the plan on the `kb` board**. The shared
  team repos (convergio, MirrorBuddy) were left untouched — they have their own project canon and
  imposing a personal workflow on a team repo isn't appropriate.

## [v2.12.0] - 2026-07-08

### Changed
- **gbrain: dropped the local fork — now runs the official upstream.** The "fork"
  (`Roberdan/gbrain`, commit `f7376b11`) was just a 2-line patch adding `bge-m3` to the ollama
  recipe. It's no longer needed: `~/.gbrain/config.json` declares `embedding_dimensions: 1024`
  explicitly and the official `garrytan/gbrain` respects it, so `ollama:bge-m3` embeds fine with
  **zero code changes**. Verified end-to-end on the real DB (11.769 pages, untouched): search
  returns identical-score results and embed writes 1024-dim chunks. The `~/gbrain` clone now
  tracks only the official remote (fork remote removed), pinned to the `official` branch @
  v0.42.53. **Honest caveat:** upgrading to the latest official (v0.42.57) is blocked by a failing
  DB migration (v0.32.2) on this DB — a separate, unresolved gbrain issue, not forced.
- **`bin/check-embedder.sh` rewritten** for the fork-free world: instead of looking for a code
  patch (there is none), it now verifies the three things that actually keep local-first recall
  working — config declares `bge-m3` + `1024` dims, ollama serves `bge-m3` at 1024 via its
  OpenAI-compatible endpoint, and the clone has no fork remote. Shellcheck-clean, green.

### Note (machine ops, not repo code)
- **`trading-os` integrated into both memory systems**: registered + indexed in gbrain (93 pages,
  auto-scoped via `.gbrain-source` pin) and federated into the kanban (`kb init` — board
  scaffolded, card columns excluded via `.git/info/exclude`, leak-check pre-commit hook). It was
  absent simply because both systems are explicit opt-in and it had never been registered.

## [v2.11.0] - 2026-07-08

### Added
- **Approval inbox — the system now tells Roberto when he's needed (push, not just pull).**
  Answers the standing question "how do I know when something waits on me?". Three parts:
  - **`kb pending [--count]`** — one place aggregating, across every registered repo: gated todo
    cards + unapproved learning candidates + open PRs awaiting review/merge (**bot PRs excluded** —
    Dependabot/renovate/actions are noise, not decisions; an agent-authored PR like copilot-swe-agent
    is *kept*, it needs a merge decision). `--count` is a fast LOCAL total (todo+learning, no `gh`).
  - **`bin/pending-digest.sh`** + launchd `com.roberdan.rda-pending-digest` (twice daily, 09:00 +
    18:00) — pushes a macOS notification + refreshes `~/.roberdan-os/pending-digest.txt` with the
    full picture (PRs included) when something waits. Runs from no cwd, iterates the registry.
  - **SessionStart badge** — `📥 N in attesa` at the top of every fresh session (fast local count).
  - `test/test-pending.sh` (validate §8e): count correctness, approved-learning excluded, digest
    writes+exits-0, PR bot-filter predicate. @thor-gated (twice — see below).
- **First real meta-loop promotion.** With the v2.10.0 loop live, the 2 genuine learnings that
  surfaced (the leak-check "a safety check you must remember to run is not a control" scar + the
  "recurring gap is DISTRIBUTION not architecture" lesson) were human-approved and promoted to the
  vault — the loop's first end-to-end cycle in production. The 619-item boilerplate backlog was
  archived (not promoted).

### Fixed
- **@thor caught two real defects the green tests didn't** (the qualitative done-gate earning its
  keep): (1) an eval-limitation framing that was quantitatively fine but interpretively one-sided
  (immunized the canon from its null result) → made symmetric; (2) the approval inbox's PR leg was
  dead on the *push* path (digest runs from no repo, so a cwd-scoped `gh` check always failed) and
  the docs over-claimed PR coverage → PRs now aggregate registry-wide, bot-filtered, and the docs
  match what the code delivers.

### Known follow-ups (honest, non-blocking — from @thor's PASS)
- `test/test-pending.sh` §5 pins a *copy* of the bot-filter jq predicate rather than asserting
  against `kanban/kb.sh` directly; extract it to a shared var so a future filter edit can't drift.
- `kb pending` PR discovery iterates repos that have a `kanban/` dir, not raw registry membership;
  a registered repo without a board would have its PRs silently skipped (no miss today).

## [v2.10.0] - 2026-07-07

Two parallel worktree+PR streams (the new norm — see below), each @rex-reviewed and @thor
qualitative-gated, merged into main. Addresses two of the honest gaps the v2.7.1 README disclosed.

### Added
- **The self-improving meta-loop now actually promotes** (PR #2, closes the biggest prose-vs-reality
  gap). Before: `learn→ontology` captured only boilerplate, `distill` wrote `class: TODO` always,
  `curate` skipped TODO → **zero promotions ever**. Now: `learn/classify.sh` is a real deterministic
  classifier over ADR-0001's 5-class taxonomy (no network/LLM, CI-safe); `distill` emits a real
  class; `curate` promotes human-approved candidates. Promotion stays **human-gated** (`approved:
  true` is Roberto's). `test/test-metaloop.sh` proves capture→distill→approve→promote end-to-end.
  - **Approval gate hardened** (rex HIGH): the gate now reads the YAML frontmatter block only
    (`_frontmatter()`), so a captured signal whose body begins `approved: true …` can no longer
    self-promote past the human gate. Regression-tested.
  - **Backlog unstuck** (rex MED): `learn/backfill-classify.sh` re-classified the real 619-item
    `class: TODO` backlog — 617 legacy `- session … cwd=` boilerplate pings archived, 2 real
    learnings surfaced for approval, **0 promotions, vault untouched** (backup taken first).
  - **Ephemera filter fixed**: it missed the bulleted legacy form (`- session … cwd=`), so pings
    slipped into quarantine misclassified — now dropped, with a unit case that also proves it
    doesn't over-match a real sentence mentioning "session"/"cwd".
- **Realistic eval fixtures + honest mechanism limit** (PR #1). 5 new task fixtures
  (`eval/tasks/13-17`) grounded in real public repo work (release-confirm-CI, resume-whole-plan,
  surgical-edit, review-comment, warm-intro), privacy-safe. `eval/README.md` now states plainly
  that the harness injects the canon as *passive prepended text* — which under-represents the live
  system (selective activation, hooks, subagents) — and **holds both hypotheses open**: the null
  result may be an impoverished measurement OR the canon genuinely adding less value than hoped.
  Honest state: "we don't know yet." No numbers fudged (the 4–6 result stands). Fixture inventory
  reconciled: 17 exist, 10 ever run, 7 not-yet-run.
- **Parallel-work norm** (`rules/best-practices.md` v3.6.0): parallelizing inside one repo = one
  `git worktree` + branch + PR per stream, disjoint file ownership, shared merge-prone files bumped
  once sequentially, each stream ends in a PR (CI → @rex → @thor → merge). Never two writers on one
  checkout. Born from today's concurrent-session scar.
- **Intake gate + qualitative done-gate** (v2.9.0, folded in): clarify ambiguous goals before
  executing; @thor validates goal fulfilment in substance, not just green tests. Both proved their
  worth this release — @thor rejected an eval framing that was quantitatively fine but
  interpretively one-sided, catching a dishonesty the mechanical checks couldn't.

### Changed
- README "Real vs. aspirational" map updated: the `learn→ontology` meta-loop moves from
  *scaffolding* to *works (human-gated)*; only `evolve` (never fired) and deliberate auto-promotion
  remain in the scaffolding column.

## [v2.9.0] - 2026-07-07

### Added
- **Intake gate — clarify ambiguous goals before executing (default behavior, every tool).**
  Roberto's directive: when a goal/prompt/command is ambiguous or under-specified in a way that
  would change the result, ask targeted clarifying questions **before** starting, so the output
  is precise. Canonized in `behavior/roberto-mode.md` (new § Intake + workflow step 0 + the
  NON-NEGOTIABLE row reworded from "Ask when unclear" to "Clarify at intake"), surfaced in
  `AGENTS.md § Behavior`, and in the `roberdan-os` block of the global `~/.claude/CLAUDE.md`
  (so it's live in every session without opening roberto-mode). Balanced against total autonomy:
  it's an **entry** gate, not a permission gate — resolve what evidence or an obvious default can
  answer (state the assumption), batch the rest into 2-4 sharp questions, and once the goal is
  clear execute autonomously without asking again. Propagates to Copilot/Codex via `AGENTS.md`.
- **@thor validates goal fulfilment qualitatively, not just quantitatively** (thor v1.3 + the
  `verify-done` skill). The done-gate's cardinal question, run *before* the mechanical gates: did
  the work fulfil the goal/order **in substance and with quality** — not just "N tasks done,
  tests green"? Map each goal-clause ↔ what was delivered; a silent gap, a thinner-than-asked
  result, or "the letter not the spirit" is a FALSE done even with every box ticked. The
  judgment stays evidence-bound (goal-clause ↔ artifact mapping, never a vibe-pass, never
  satisfied by volume of output). Closes the loop with the intake gate: intake defines the goal
  precisely, thor validates the outcome against that precise intent.

## [v2.8.0] - 2026-07-07

### Added
- **`bin/install-hooks.sh` — the repo now self-installs its Claude Code hooks.** Closes the last
  "manual step" gap in reusability: `clone → bootstrap → install-hooks --apply → sync --install`
  is a complete, zero-hand-edit setup on a fresh machine. The script merges the *generated*
  five-event hook snippet (`platforms/claude/settings-hooks.json`) into the real
  `~/.claude/settings.json` **additively** (only adds roberdan-os entries not already present,
  dedup by command — never touches the user's other hooks), **idempotently** (second run is a
  no-op), with a timestamped **backup** first and a post-write JSON-validity check. Dry-run by
  default; `--apply` writes. `RDA_CLAUDE_SETTINGS` overrides the target for testing.
  `test/test-install-hooks.sh` proves all five properties; wired into validate.sh §8d.
- **bootstrap + README + QUICKSTART** now present the three-command install (bootstrap →
  install-hooks → sync --install) instead of hand-editing JSON. The only remaining manual step
  is the one-line pointer block in the operator's *personal* `~/.claude/CLAUDE.md` (curated
  config the engine deliberately never overwrites).

### Note on the reusability boundary
Three layers, made explicit: **(1) public engine** (agents, skills, hooks, kb, canon, install
scripts) — fully in-repo, installed by the three commands; **(2) forker identity** (`identity/`)
— the one directory a fork edits; **(3) operator's personal machine config** (the global
`~/.claude/CLAUDE.md` with absolute paths / gbrain fork / launchd job names, the `gbrain-ops`
runbook, the confidential dossier) — deliberately *not* in the public repo, by the
privacy/identity split. Replicating layer 3 across the operator's *own* machines is a separate
private overlay, not a defect in the public repo.

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
