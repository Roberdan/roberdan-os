---
name: engineering-reference
description: Lookup reference for executing a task already decided on — code style per language, test/mock boundaries, API conventions, the local CI sequence before push, merge discipline, how to resolve review comments, repo settings and git hooks, plan→card coverage discipline, documentation and meta-documentation budget. Read it when you are about to push, merge, review, set up a repo, turn a plan into cards, or write docs; not before.
providers: [claude, copilot, codex]
---

# Engineering reference

Consultation material, pulled out of `rules/best-practices.md` (2026-07-14). It lived in the
always-loaded canon and cost tokens on every turn of every session in every repo, while none of it
changes what an agent **decides** — it tells you **how** to execute a task you have already chosen.
The canon's own rule sends exactly this to a skill: *"knowledge that applies sometimes belongs in a
skill (progressive disclosure), never in the canon."*

What stayed in the canon is what changes behaviour without being asked: No False Done, Wired
End-to-End, Surgical Edits, the Persuasion Guardrails, token economy, and the parallel-work rule.
Those must be in the room before you know you need them. This must not.

A second batch moved here on 2026-07-30, for the same reason: Carded End-to-End (its control is the
`kb cover` gate, not the prose) plus the documentation conventions and the documentation budget.
They apply when you translate a plan into cards or write docs — not before.

## Code Style

| Lang | Standard |
|---|---|
| Rust | `cargo fmt`, `cargo clippy -- -D warnings`, edition workspace, `?` over `unwrap`, `Result` over panics |
| TS/JS | ESLint + Prettier, semicolons, single quotes, 100 chars, `const` > `let`, async/await, `interface` > `type`, `.test.ts` AAA |
| Python | Black 88, Google docstrings, type hints, pytest + fixtures |
| Bash | `set -euo pipefail`, quote vars, `local`, `trap cleanup EXIT` |
| CSS | Modules / BEM, `rem` / `px` borders, mobile-first, max 3 nesting levels |
| Config | 2-space indent |

## Testing

**Mock boundaries** — ALLOWED: external APIs, network, filesystem, time. **FORBIDDEN**: auth, DB (use a test DB), the module under test.

**Integration**: new endpoint → real middleware. New consumer → realistic shape. Interface change → ALL consumers.

**Test data**: real names / shapes. No `Studio A` / `Test Studio`. Domains: `example.com` / `example.org` only.

**Schema change**: migration in the same PR. Field addition → update ALL fixtures.

**Coverage**: 80% business logic / 100% critical paths. Parameterized SQL.

## API Conventions

Methods: GET / POST / PUT / PATCH / DELETE | Plural nouns `/api/users` | kebab-case | Max 3 levels.
Status: 200 / 201 / 204 | 400 / 401 / 403 / 404 / 409 / 422 / 429 / 500 / 503.
Error: `{error: {code, message, details?, requestId, timestamp}}`.
Pagination: `?page=1&limit=20` (max 100). Rate limit: 429 + headers. Auth: OAuth 2.0 / JWT.

## Local CI Before Push

Before `git push` or PR creation, run the full local pipeline:

1. Format: `cargo fmt --check` / `prettier --check` / `ruff format --check`
2. Lint: `cargo clippy -- -D warnings` / `eslint` / `ruff check`
3. Type-check: `cargo check` / `npx tsc --noEmit`
4. Tests: `cargo test` / `npm test` / `pytest`
5. Build: `cargo build` / `npm run build`

If any step fails, fix and re-run ALL checks. Do NOT push with known failures.

## Merge Discipline

You are autonomous on merges — but **only after careful evaluation**. Before merging:

1. CI must be fully green (all required checks pass; never merge with anything pending or failing).
2. PR must be `mergeable=MERGEABLE` and `mergeStateStatus=CLEAN`.
3. Diff must match the PR description (no surprises).
4. **Every review comment must be properly resolved** — see § Review Comments below. No unresolved comments, no `requested-changes` reviews, no "resolved a cazzo".
5. Local pipeline (fmt / lint / type-check / tests / build) must have run clean before push.
6. Merge type is **merge commit only** — never squash, never rebase (preserves history; parallel agents depend on it).
7. If the PR touches `main` branch protection, security policy, license, or release infrastructure → STOP and ask first.
8. Force-pushes to `main` are ALWAYS forbidden without explicit user confirmation.

After merging: delete the source branch, fast-forward `main` locally, and report the merge commit SHA. If anything in the eight checks above is uncertain, ask before merging — uncertainty is a signal to pause.

## Review Comments

Every comment on a PR — human or bot — must be **analyzed, understood, and resolved well**, not dismissed.

For each comment:

1. **Read it fully.** Don't skim. Re-read if the intent is unclear.
2. **Understand the underlying concern.** A nitpick on naming may be a deeper concern about the abstraction; a "did you consider X?" is asking for evidence, not approval.
3. **Decide the right action**: fix the code, push back with reasoning, mark wontfix with explanation, or escalate to the user. Never silent-resolve.
4. **Implement the fix correctly** — same rigor as fresh work: tests, types, conventional commit, no half-measures. Don't game the comment with a token edit.
5. **Reply on the comment thread** explaining what you did and why, then mark it resolved. The reply is the audit trail; "fixed" alone is not enough.
6. **Re-run the local pipeline** before pushing the fix — review fixes break things as often as fresh code.
7. **If the reviewer is wrong**, say so respectfully with evidence (link to docs / code / tests). Conviction over agreeableness; the reviewer would rather be corrected than silently overruled.

Never:

- Resolve a comment without addressing its substance.
- Push a "fix" that only touches the comment's quoted line while ignoring its actual point.
- Batch-resolve comments at the end as a clean-up gesture.
- Merge a PR with any unresolved comment, even one you believe is invalid — write the rebuttal first.

If you cannot resolve a comment yourself (architectural disagreement, scope question, missing context), STOP and ask the user. Better to pause than to merge over the disagreement.

## Repository Setup

| Setting | Value | Why |
|---|---|---|
| Squash merge | DISABLED | Loses history; parallel agents overwrite each other's work |
| Rebase merge | DISABLED | Rewrites history, breaks parallel branch refs |
| Merge commit | ENABLED (only) | Preserves full history, safe for parallel agents |
| Branch protection | Require PR + CI pass | No direct push to `main` |

Apply to a repo: `gh api repos/OWNER/REPO -X PATCH -f allow_squash_merge=false -f allow_rebase_merge=false -f allow_merge_commit=true`

## Recommended Git Hooks

Install per-repo when relevant:

| Hook | Blocks |
|---|---|
| `pre-commit` MainGuard | commits on `main` in main checkout |
| `pre-commit` FileSizeGuard | new hand-written source/test files >300 lines; unjustified growth in oversized legacy files (technical artifacts exempt) |
| `pre-commit` SecretScan | commits containing API keys, tokens, passwords |
| `commit-msg` CommitLint | non-conventional commit messages |

## Carded End-to-End (requirements must become cards, not just prose)

The twin of § Wired End-to-End, one level up: **a requirement that lives in a plan but never becomes
a card is not planned — it's a wish that looks planned.**

Every gate we have — `kb`, `@thor`, the merge-gate, CI — operates **downstream of the card**. A
requirement that never became one is invisible to all four *simultaneously*. They are not broken;
they faithfully verify an input that was already amputated. The plan→card translation is the only
link in the chain with **no gate**, and it is exactly where requirements die.

- **Walk from the plan, never from the board.** A board can only show you the cards that exist. It
  cannot show you the **absence** of one — which is the entire failure mode.
- **A card may not weaken the clause it claims to satisfy.** Plan says "X, Y **and** Z are
  mandatory"; card says "at least one of X/Y/Z" — that closes green while deleting Y and Z from the
  product. **Quantifiers are where requirements go to die.**
- **The gate, not this paragraph, is the control:** `kb cover <plan.md>` fails red on any clause with
  no card and no written decision (`<plan>.coverage`). It runs inside `test/validate.sh`. Prose did
  not stop this from happening — a gate does.

*(Scar: trading-os 2026-07-13. The signed plan mandated "SEC EDGAR/RSS, company IR and GDELT"; the
one card that could have delivered it read "at least one mandatory free live source", closed honestly
green, and the news evaporated. The system then built the news graph, the news UI and news realtime
freshness — and nothing that fetches a news item. A full plan→DAG audit found **77 of 149 normative
clauses never reached the product**. Full report: `trading-os/docs/execution/plan-coverage-audit.md`.)*

## Documentation

JSDoc / docstrings for public APIs (WHY, not WHAT). CHANGELOG: `## [vX.Y.Z] - date` → `### Added | Changed | Fixed`. Keep TROUBLESHOOTING.md current.

## Documentation Budget

A system that documents itself more than it does the work is a smell. Keep meta-documentation to:

- **One living plan**: `docs/plan.md`. Not a plan per session — the plan, updated in place.
- **One living handoff**: `handoff/latest.md`. Not a handoff per session — overwritten each time, git history is the log.
- **Dated session artifacts** (plans, judgments, test reports tied to a specific date) move to `docs/archive/` once their actions are closed. They stay for reference; nothing there is maintained going forward.
- **No build artifacts** (PDF, generated bundles, compiled output) committed to git. Regenerate from source; git history keeps old copies if ever needed.

The behavioral canon (`AGENTS.md`, `behavior/`, `rules/`, `agents/`) must always outweigh the system's self-documentation. If a repo has more words describing its own process than governing actual behavior, that's a sign the process writing has run away — prune it back to the living plan + living handoff, archive the rest.
