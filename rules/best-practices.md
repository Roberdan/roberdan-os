---
name: best-practices
version: "3.6.0"
last_updated: "2026-07-07"
---

# Best Practices

Guidelines for quality across every project. These are expectations, not hooks.

## No False Done (the cardinal reliability rule)

**Never claim something is done, verified, working, green, released, or "a posto" until you have
observed the evidence for THAT claim, end-to-end, yourself.** This is the top rule because a
confident-but-wrong "all good" is the single most damaging thing an agent can do — it makes the
whole system untrustworthy. It outranks speed, tidiness, and looking competent.

### The gate you wrote is a promise, not a proof — and you don't get to pick which ones get checked

The three failure modes below all shipped a false "done" **while every claim made was individually
true**. Honesty is not enough; these are structural.

1. **Check EVERY gate the plan declares, not the ones you remember.** If the plan lists gates
   G1…G11, "done" requires **all eleven measured**, each one printed. A gate you defined and then
   forgot is still a gate: silence on it is a false done, not an omission. *(Real failure,
   2026-07-14: a plan declared "all views on the design system"; six phases shipped, all "green",
   and that one gate was never measured. It was at 72/98, with 54 raw colours still in the app.
   The user found it by asking.)*

2. **The one who declares done must NOT be the one who chooses what gets verified.** If you write
   the plan, then brief the verifier on which gates to check, you will hand them the gates you
   already passed. `@thor` must **read the plan itself** and verify every gate it declares — never
   only the list the orchestrator pasted into the prompt. A verifier fed its own checklist by the
   party under audit is theatre.

3. **A gate that can be satisfied without doing the work is worse than no gate.** Before trusting a
   counter, ask: *what would make this number look good while the work is undone?* Count what the
   user would see, not what is convenient to grep. *(Same failure: the gate counted "files that
   mention the design system", so a file with one token and thirty raw colours counted as done, and
   26 views that colour nothing at all were counted as debt. The metric was wrong in both
   directions.)*

4. **A green suite proves you didn't break what the tests already watched — nothing more.**
   Before claiming an invariant is protected, **put the bug back and watch the test go red**. An
   invariant asserted in a comment but not enforced by code — or "covered" by a test that never
   exercises it — is *worse* than an absent one: it manufactures unearned confidence. *(Real
   failure, same campaign: the most important fix of the whole effort — a clock that froze while
   the phone slept, making a monitor claim "updated a moment ago" over a child unwatched for six
   hours — was pinned by NOTHING. The done-gate reintroduced the bug and all 620 tests stayed
   green. The test's own comment claimed it would catch exactly that.)*

- **A claim needs evidence for the claim itself, not for a neighbour.** "Released" ⇒ the CI run
  on the release commit is confirmed green (not "I pushed"). "Tests pass" ⇒ you ran them and read
  the output (not "they should"). "It works" ⇒ you drove the real path and saw it. "Done" ⇒ every
  acceptance criterion checked.
- **Whole-system, not the part you touched.** If you verified piece A but B/C are unchecked, you
  are NOT done — say exactly what is verified and what isn't. Partial truth stated as total is a
  false done.
- **"Should / probably / I think it's fine" ≠ "is".** Never present an inference or a hope as a
  verified fact. If you haven't checked, say "not verified yet" and go check — or say plainly you
  can't.
- **Prefer a mechanical gate over your own assurance.** Move the evidence OUT of your words: a CI
  check, a test run, a `git status`, a grep for the caller. The gate's GREEN is the claim, not your
  sentence. (Pairs with § Wired End-to-End.)
- **When you got it wrong, say so first, with the fact.** No burying, no "as I said". Acknowledge,
  show the evidence, fix. Conviction over agreeableness — a correction now beats a false "done".
- **The lever is verification + gates, not model temperature.** Temperature governs output
  variety, not honesty; a cold model states falsehoods just as confidently. Reliability comes from
  checking before claiming and from gates that carry the evidence, never from a sampling knob.

**Real failure this rule exists to prevent** (2026-07-06): an agent announced "v2.4.0 released,
all set" while the release commit's CI was in fact **red** — a `--auto` change had been left
uncommitted, so `main` was broken. "Released" had been claimed on "I pushed", not on a confirmed
green CI run. The fix that should have been the habit: wait for the CI conclusion, read it, THEN
say released.

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

## Carded End-to-End (requirements must become cards, not just prose)

The twin of § Wired End-to-End, one level up. That rule says code with no live caller is dead code
that looks done. This one says: **a requirement that lives in a plan but never becomes a card is
not planned — it's a wish that looks planned.** Same failure shape, earlier in the chain, and far
more expensive: unwired code wastes the work; an uncarded requirement means the work never happened
and nobody noticed.

**Every gate we have operates downstream of the card.** `kb` (todo→doing→done), `@thor` (done-gate),
the merge-gate (`allowed_paths` from the card), CI (the card's tests) — all four verify *a card*.
So a requirement that never became a card is invisible to all of them **simultaneously**. They are
not broken; they are faithfully verifying an input that was already amputated. The translation
**plan → cards is the only link in the chain with no gate**, and it is exactly where requirements
die.

**Rules:**
- **A plan is not executable until every normative clause maps to ≥1 card**, or to an explicit,
  written refusal ("out of scope because X"). Silence is not a decision — an unmapped clause is a
  bug in the plan, not an omission you can discover later.
- **A card may not weaken the clause it claims to satisfy.** If the plan says "the mandatory path is
  X, Y and Z", a terminal condition of *"at least one of X/Y/Z"* is a **downgrade**, and it will
  close green while silently deleting Y and Z from the product. Diff the card's terminal condition
  against the clause's actual demand — quantifiers (`at least one`, `almeno una`, `one or more`) are
  where requirements go to die.
- **Verify by walking from the plan, never from the board.** The board can only show you the cards
  that exist. Enumerate the plan's clauses and ask "which card covers this?" — the reverse direction
  (reading the cards and feeling covered) cannot detect the absence of a card, which is the whole
  failure mode.
- **Prefer a mechanical proof** (same as § Wired End-to-End): a `plan-coverage` gate that maps every
  numbered clause to a card ID and fails red on an unmapped one. Where the plan and its task DAG are
  both committed (the normal case for a code repo), this belongs in CI. Where the board is local-only
  (roberdan-os itself), `kb cover <plan>` is the operational equivalent — run it, don't trust memory.

**Real failure this rule exists to prevent** (2026-07-13, trading-os): the signed plan §28 mandated
"SEC EDGAR/RSS, official company IR and GDELT" as the required source path. **No card ever ingested a
news item.** The one card that could have (F9-03) had the terminal condition *"At least one mandatory
free live source is adopted"* — SEC EDGAR alone satisfied it, so the card closed **honestly green**
and RSS + GDELT evaporated. Weeks later the system had built the news *graph*, the news *UI* and the
news *realtime freshness handling* — **and nothing that fetches a news item**. The consumer without
the producer. A full plan→DAG audit then found the same evaporation had happened to `novelty` (zero
occurrences in every card and all code, though the plan makes it normative) and to the
action-window comparators (the anti-multiple-testing guard). Three requirements, silently deleted in
translation, all four gates green throughout.

## Context & Token Economy

Context is a finite resource with diminishing returns ("context rot"): every always-loaded token
competes with the tokens that matter. (Anthropic — effective context engineering 2025-09; Claude
Code best practices, current 2026.)

- **Always-loaded instruction files stay lean** — target ≤200 lines each. Per-line test: *would
  removing this cause the agent to make mistakes? If not, cut it.* A rule the agent keeps
  violating inside a long file means the file is too long: convert that rule into a **hook**
  (deterministic), don't add more prose (advisory). *Scope note:* in Claude Code this file is
  JIT-loaded, but the ChatGPT/web **bundle** (`bin/make-bundle.sh`) concatenates it verbatim
  into an always-loaded context — this file is over the bar itself, so the standing duty here
  is **prune before adding**, and trim on the next canon pass.
- **Just-in-time retrieval over pre-loading.** Keep pointers (paths, queries, `[[wikilinks]]`) in
  context; pull content on demand (gbrain, grep). Knowledge that applies *sometimes* belongs in a
  skill (progressive disclosure: only name+description load at startup), never in the canon.
- **Subagents isolate exploration.** Burn search tokens inside the subagent, return a condensed
  summary; never dump raw exploration into the orchestrator's context.
- **Cache discipline.** Static content first and byte-stable (no timestamps/volatile state in
  always-loaded files); pick model + effort once, early — mid-session switches invalidate the
  prompt cache and recompute everything.
- **A loop phase is the session container, not the whole task** — canonical contract lives in `loop/loop-protocol.md` § Session-as-phase-container; don't restate it here.
- **Durable state on disk beats in-conversation state — for cost too.** A kanban card / checkpoint
  file is read once per resume; conversation state is re-paid every turn. Prefer CLIs (`gh`, `kb`)
  over verbose API dumps — the most context-efficient interface to external services.
- **A runaway loop is a cost incident before it's a quality incident.** Two consecutive passes
  with no progress → stop and surface what's wedged (loop-protocol); meter long jobs against
  their terminal condition, never "keep trying".

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

## Parallel work — worktree + PR, never concurrent commits on one checkout

**When work is parallelized inside a single repo, each parallel stream gets its own `git worktree`
+ branch + PR. Never run two agents/sessions committing to the same working checkout.** This is a
hard rule, born from a real scar (2026-07-07: two sessions on the same checkout re-edited each
other's files — duplicate frontmatter keys, interleaved commits, a near-collision on the release).

- **`git add -A` is a loaded gun whenever anything else can write to the checkout. Stage by
  explicit path.** A blanket `git add` does not stage *your* work — it stages *whatever is in the
  tree right now*, including another process's in-flight edits. **A `docs(...)` commit must never
  contain source.** *(Real scar, 2026-07-14, and the worst of the campaign: `@thor` was running a
  mutation test — deliberately reintroducing a clock bug to prove the test caught it — in the same
  checkout where the orchestrator ran `git add -A && git commit` to update a plan. The mutation was
  swept into a commit titled `docs(p3): ...` and **pushed to `Development`**. A clinical-safety
  regression shipped inside a documentation commit, and every gate stayed green because no test
  covered that line. Thor spotted it and restored it. Two rules, both cheap: **stage docs by path**,
  and **mutation testing only ever in a throwaway worktree**.)*
- **Before removing a worktree, prove the agent is dead — `0 modified files` is not proof.** An
  agent between edits looks identical to a corpse. *(Same session: a live F4 agent was declared dead
  and had its worktree pulled from under it; it recreated it, and in doing so reset a second agent's
  worktree, destroying that one's work. The orchestrator caused both.)*

- **One worktree per stream:** `git worktree add ../<repo>-<feature> -b <type>/<feature>` off the
  base branch. Each worktree has its own index and HEAD, so parallel writers can't fight
  `.git/index.lock` or clobber each other's staged work — this is exactly what worktrees are for.
- **Disjoint file ownership:** give each stream a non-overlapping file set. Keep shared, merge-prone
  files (`VERSION`, `CHANGELOG.md`, `README.md`) OUT of the parallel branches — bump/write them once,
  sequentially, at merge/release time, so PRs stay conflict-free.
- **Each stream ends in a PR**, not a direct push to the shared branch: push the branch, let CI go
  green, `@rex` reviews, `@thor` runs the qualitative done-gate, then merge (merge commit only).
  Merge PRs **one at a time** and re-check CI between merges.
- **Sequential work on a personal repo may still commit to the base branch directly** (that's the
  normal solo flow). The worktree+PR rule triggers specifically when you *parallelize* — the moment
  there is more than one writer, isolation is mandatory.
- After merge: `git worktree remove` the stream's worktree and delete its branch.

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

**Agent supply chain.** Skills, MCP servers and plugins are an active attack surface (Snyk
ToxicSkills 2026-02: 36.8% of 3,984 marketplace skills had ≥1 flaw, 76 confirmed malicious;
malicious MCP servers can inject via tool *descriptions* alone). Rules:

- No third-party skill/MCP server enters the stack without a review of its SKILL.md + bundled
  scripts; **re-review on every update** (same habit as `check-embedder.sh` after gbrain upgrades).
- A session that can read `private/` never gets an unreviewed MCP server attached.
- Assume prompt injection eventually succeeds; the control is **blast radius**, not prose: least-
  privilege tools (read-mail ≠ send-mail), draft-not-send as a *security* boundary, secrets
  physically unreachable from where generated code runs.

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
