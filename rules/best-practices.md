---
name: best-practices
version: "3.3.0"
last_updated: "2026-07-05"
---

# Best Practices

Guidelines for quality across every project. These are expectations, not hooks.

## Code Style

| Lang | Standard |
|---|---|
| Rust | `cargo fmt`, `cargo clippy -- -D warnings`, edition workspace, `?` over `unwrap`, `Result` over panics |
| TS/JS | ESLint + Prettier, semicolons, single quotes, 100 chars, `const` > `let`, async/await, `interface` > `type`, `.test.ts` AAA |
| Python | Black 88, Google docstrings, type hints, pytest + fixtures |
| Bash | `set -euo pipefail`, quote vars, `local`, `trap cleanup EXIT` |
| CSS | Modules / BEM, `rem` / `px` borders, mobile-first, max 3 nesting levels |
| Config | 2-space indent |

## Surgical Edits

Every changed line in a diff should trace directly to the user's request. Don't "improve" adjacent code, comments, or formatting you happen to pass through. Match existing style even if you'd do it differently. If you notice unrelated dead code, mention it — don't delete it.

## Testing

**Mock boundaries** — ALLOWED: external APIs, network, filesystem, time. **FORBIDDEN**: auth, DB (use a test DB), the module under test.

**Integration**: new endpoint → real middleware. New consumer → realistic shape. Interface change → ALL consumers.

**Test data**: real names / shapes. No `Studio A` / `Test Studio`. Domains: `example.com` / `example.org` only.

**Schema change**: migration in the same PR. Field addition → update ALL fixtures.

**Coverage**: 80% business logic / 100% critical paths. Parameterized SQL.

## Wired End-to-End (features must be reachable, not just present)

A feature that exists but is never invoked from a live path is **not done — it's dead code that
looks done**. Every feature, field, flag, option, hook, agent, or skill you add must be **wired
end-to-end**: defined **and** consumed **and** reachable from the real entry point (CLI arg, hook
trigger, entry file, config the runtime actually reads). "The file/function/field exists" is not
the bar; "a live caller reaches it" is.

**Verify by tracing the path**, not by confirming the definition. Start at the entry point and
follow the call/read chain to the feature. No caller on a live path → not wired → not done.

Concrete failure modes this rule exists to catch (all seen in this repo or its work):
- A config field written in one file but read from a *different* file the runtime uses (e.g. a
  `provider:` key set in a tool's native profile but not in the profile the dispatcher actually
  reads → silently ignored).
- A generated wrapper on disk that no tool is pointed at (the `tool-coverage` gate in
  `test/validate.sh` exists precisely to prove skills resolve into the canon, not just exist).
- Code that "looks wired but never ran" (an entire eval fixture class is named after this).
- A new env var / flag added to a script but never branched on; a new agent file never referenced
  from `AGENTS.md`; a new skill never symlinked into the tool's skills dir.

**Prefer a mechanical proof.** Where feasible, add a check that fails when a feature is unwired
(a coverage gate, a grep-for-caller test, a link check) rather than relying on a human to notice.
An unwired feature that ships green is worse than one that fails loudly.

## Persuasion Guardrails

| Blocked phrase | Response |
|---|---|
| "too simple to test" | Write the test |
| "tests after / later" | RED first |
| "out of scope" (touched file) | Touch = own |
| "pre-existing issue" | Own it or escalate |
| "it works, trust me" | Run tests, attach output |
| "refactor later" | Now or tracked issue |

## Documentation

JSDoc / docstrings for public APIs (WHY, not WHAT). CHANGELOG: `## [vX.Y.Z] - date` → `### Added | Changed | Fixed`. Keep TROUBLESHOOTING.md current.

## Documentation Budget

A system that documents itself more than it does the work is a smell. Keep meta-documentation to:

- **One living plan**: `docs/plan.md`. Not a plan per session — the plan, updated in place.
- **One living handoff**: `handoff/latest.md`. Not a handoff per session — overwritten each time, git history is the log.
- **Dated session artifacts** (plans, judgments, test reports tied to a specific date) move to `docs/archive/` once their actions are closed. They stay for reference; nothing there is maintained going forward.
- **No build artifacts** (PDF, generated bundles, compiled output) committed to git. Regenerate from source; git history keeps old copies if ever needed.

The behavioral canon (`AGENTS.md`, `behavior/`, `rules/`, `agents/`) must always outweigh the system's self-documentation. If a repo has more words describing its own process than governing actual behavior, that's a sign the process writing has run away — prune it back to the living plan + living handoff, archive the rest.

## Meta-Card Budget

The same self-referential-runaway risk applies to the kanban board, not just to docs. In
`roberdan-os`, every card closed so far (`kanban/done/`) has been the system building, auditing,
or improving *itself* — none has produced value in Roberto's actual external work. Left
unbounded, self-improvement work crowds out external use, because it's always easier to find
one more thing to polish about the system than to go do the harder, less legible work outside it.

**Rule:** whenever at least one external-facing card (a card whose DoD produces a verifiable
artifact outside roberdan-os — e.g. in Convergio, Fight the Stroke, or Microsoft work) sits in
`kanban/todo/`, keep **at most 1** active meta/self-improvement card (a card about roberdan-os
itself — its infra, docs, tests, or agents) across `kanban/todo/` + `kanban/doing/` combined.

This is a **discipline norm for whoever proposes new cards** (Roberto or an agent) — not a
mechanically enforced gate. `kb.sh` does not check or block on this; nothing stops a second
meta-card from being added. Treat it the same way as the `--by`/`approved_by` honor-system
gates in `kanban/README.md`: reviewable, not cryptographically bound. If you're about to add a
second active meta-card while an external-facing card is sitting in `todo/`, that's the signal
to either finish/park one of the meta-cards first, or make the case out loud for why this
meta-card is the exception.

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

## Security & Privacy

Input: validate client + server, allowlists, sanitize. XSS: escape, CSP, DOMPurify.
Secrets: env vars, `.env` gitignored. Auth: OAuth 2.0 / OIDC, RBAC server-side.
Transport: HTTPS, HSTS, secure cookies, TLS 1.2+. Privacy: GDPR, data minimization, consent.
Inclusive language: gender-neutral, allowlist / blocklist, primary / replica, person-first.

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
| `pre-commit` FileSizeGuard | commits with files > 300 lines (.rs/.ts/.js/.sh) |
| `pre-commit` SecretScan | commits containing API keys, tokens, passwords |
| `commit-msg` CommitLint | non-conventional commit messages |

## Writing

Tables > prose. Commands > descriptions. No preambles. Comments: WHY only, < 5%. Commits: conventional. PRs: Summary + Test plan.
