---
name: best-practices
version: "3.7.0"
last_updated: "2026-07-25"
---

# Best Practices

Guidelines for quality across every project. These are expectations, not hooks.
The failures behind them — full accounts, one per rule — live in `rules/scars.md`, read on
demand: this file carries the rule, that one carries the reason.

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
   forgot is still a gate: silence on it is a false done, not an omission. *(scar 2026-07-14 — a forgotten gate: `rules/scars.md` § Gates)*

2. **The one who declares done must NOT be the one who chooses what gets verified.** If you write
   the plan, then brief the verifier on which gates to check, you will hand them the gates you
   already passed. `@thor` must **read the plan itself** and verify every gate it declares — never
   only the list the orchestrator pasted into the prompt. A verifier fed its own checklist by the
   party under audit is theatre.

3. **A gate that can be satisfied without doing the work is worse than no gate.** Before trusting a
   counter, ask: *what would make this number look good while the work is undone?* Count what the
   user would see, not what is convenient to grep. *(scar 2026-07-14 — a metric wrong in both directions: `rules/scars.md` § Gates)*

4. **A green suite proves you didn't break what the tests already watched — nothing more.**
   Before claiming an invariant is protected, **put the bug back and watch the test go red**. An
   invariant asserted in a comment but not enforced by code — or "covered" by a test that never
   exercises it — is *worse* than an absent one: it manufactures unearned confidence. *(scar 2026-07-14 — 620 green tests pinning nothing: `rules/scars.md` § Gates)*

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

**Why this is the top rule** — scar 2026-07-06: "released" claimed on a push while the release
commit's CI was red. Full account: `rules/scars.md` § Released-on-a-push.

## Surgical Edits

Every changed line in a diff should trace directly to the user's request. Don't "improve" adjacent code, comments, or formatting you happen to pass through. Match existing style even if you'd do it differently. If you notice unrelated dead code, mention it — don't delete it.

## Wired End-to-End (features must be reachable, not just present)

A feature that exists but is never invoked from a live path is **not done — it's dead code that
looks done**. Every feature, field, flag, option, hook, agent, or skill you add must be **wired
end-to-end**: defined **and** consumed **and** reachable from the real entry point (CLI arg, hook
trigger, entry file, config the runtime actually reads). "The file/function/field exists" is not
the bar; "a live caller reaches it" is.

**Verify by tracing the path**, not by confirming the definition. Start at the entry point and
follow the call/read chain to the feature. No caller on a live path → not wired → not done.

The four shapes this catches — a field read from a different file than it is written to, a
generated wrapper nothing points at, code that looks wired but never ran, a flag never branched
on: `rules/scars.md` § Unwired.

**Prefer a mechanical proof.** Where feasible, add a check that fails when a feature is unwired
(a coverage gate, a grep-for-caller test, a link check) rather than relying on a human to notice.
An unwired feature that ships green is worse than one that fails loudly.

## Context & Token Economy

Context is a finite resource with diminishing returns ("context rot"): every always-loaded token
competes with the tokens that matter. (Anthropic — effective context engineering 2025-09; Claude
Code best practices, current 2026.)

- **Bounded hand-written files.** New hand-written source and test files target **≤300 lines**;
  split by responsibility first. Existing oversized files may grow only with explicit,
  task-relevant justification; never force unrelated refactors or micro-files.
  Generated, vendored, lock, snapshot, data, and migration artifacts are exempt.
- **Always-loaded instruction files stay lean** — target ≤200 lines each. Remove any line whose
  absence would not cause mistakes; repeated violations need a deterministic hook, not more
  advisory prose. Claude loads this file every session (`~/.claude/rules/` symlink) and the
  ChatGPT/web bundle includes it verbatim. This file is at 215 lines, still over: the reasons
  moved to `rules/scars.md` and the mechanics to the `engineering-reference` skill — prune the
  same way before adding, never by dropping a rule.
- **Just-in-time retrieval over pre-loading.** Keep pointers (paths, queries, `[[wikilinks]]`) in
  context; pull content on demand (gbrain, grep). Knowledge that applies *sometimes* belongs in a
  skill (progressive disclosure: only name+description load at startup), never in the canon.
- **Delegate by default — the orchestrator keeps conclusions, not transcripts.** Reading to find
  out is a subagent's job; deciding and editing is yours. Delegate when answering means sweeping
  files you cannot name in advance, auditing a claim, or reading more than ~3 files; ask for the
  finding + `file:line` evidence + what was ruled out (≲2k tokens), never the raw dump. Delegate
  EARLY — a fresh window reasons better than a full one, and past roughly half the window the
  next exploration goes out by default (if it must stay in, say why in one line). *Why: accuracy
  falls as context grows even when every needed fact is still present — "context rot"; a subagent
  spends tens of thousands of tokens and returns 1-2k. Anthropic,* Effective context engineering
  for AI agents. **Not delegated:** a lookup whose file and symbol you already know; a step
  dictated by output you just read; anything needing this session's uncommitted state. Delegation
  never moves a gate — a subagent's report is evidence to check, and only @thor closes a
  done-gate (§ No False Done).
- **Cache discipline.** Static content first and byte-stable (no timestamps/volatile state in
  always-loaded files); pick model + effort once, early — mid-session switches invalidate the
  prompt cache and recompute everything.
- **Subagents default to the cheap/mid model; frontier needs a written reason.** The single most
  impactful cost lever (Uber Engineering, 2026 — 52% cost cut per session at 7× usage): the
  orchestrator decomposes and evaluates on the strong model, **executors** (well-scoped work with
  specified inputs) run on `sonnet`/`haiku`. **Deciders/reasoners** (architecture, security
  judgment, adversarial red-team, first-principles, thinking) may use the frontier tier only with
  a written `model_rationale:` on the agent. Reasoning **effort defaults to `medium`**; above
  medium needs a written `effort_rationale:`. Enforced by `test/test-model-economy.sh`; full
  policy in `skills/model-selection-policy/skill.md`.
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

## Parallel work — worktree + PR, never concurrent commits on one checkout

**When work is parallelized inside a single repo, each parallel stream gets its own `git worktree`
+ branch + PR. Never run two agents/sessions committing to the same working checkout.** This is a
hard rule, born from a real scar (2026-07-07: two sessions on the same checkout re-edited each
other's files — duplicate frontmatter keys, interleaved commits, a near-collision on the release).

- **`git add -A` is a loaded gun whenever anything else can write to the checkout. Stage by
  explicit path.** A blanket `git add` does not stage *your* work — it stages *whatever is in the
  tree right now*, including another process's in-flight edits. **A `docs(...)` commit must never
  contain source.** Second rule from the same
  scar: **mutation testing only ever in a throwaway worktree**. *(scar 2026-07-14 — a safety
  regression shipped inside a `docs(...)` commit: `rules/scars.md` § Blanket-add)*
- **Before removing a worktree, prove the agent is dead — `0 modified files` is not proof.** An
  agent between edits looks identical to a corpse. *(scar 2026-07-14 — two worktrees destroyed on
  one wrong death certificate: `rules/scars.md` § Blanket-add)*

- **Sequential work on a personal repo may still commit to the base branch directly** (that's the
  normal solo flow). The worktree+PR rule triggers specifically when you *parallelize* — the moment
  there is more than one writer, isolation is mandatory.
- The mechanics — one worktree per stream, disjoint file ownership, shared files kept out of
  parallel branches, PR-per-stream merged one at a time, cleanup after merge — are in the
  `engineering-reference` skill § Parallel streams.

## Security & Privacy

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

**Never write a backup of a secret-bearing file inside the repo.** Before editing anything that
holds credentials (`.env*`, `*.pem`, service-account JSON, a `vercel env pull` dump), the copy
goes **outside the working tree** — `~/.<repo>-env-backups/`, `chmod 600` — never `.env.bak`,
`.env.local.old`, `.env.copy` next to the original. *(scar 2026-08-20 — a `.bak` full of live keys, one
`git add .` from being committed: `rules/scars.md` § Secret-backup)*. Two consequences:

- After creating any such copy, **verify** it: `git check-ignore -q <file>` must succeed, or the
  file does not belong there.
- Widening `.gitignore` is not the fix. An ignore rule protects this repo, on this machine, for
  the patterns someone thought of; keeping the file outside the tree protects it everywhere.

## Subagent models — always the newest generation of the tier, never a hand-picked old id

When you spawn a subagent you **must** pass `model` explicitly, and it must be the **newest
generation of the tier you chose**. Never leave it to the default (which may be a previous
generation) and never type a version number from memory.

**The single source of truth is `copilot_model()` in `bin/sync.sh`** — canon tiers → concrete
ids (`opus` → `claude-opus-5`, `sonnet` → `claude-sonnet-5`, `haiku` → `claude-haiku-4.5`).
If you are about to write a concrete id in a tool call, it must match that table, or a newer
generation you can see in the tool's own model list. When the tool's list shows a higher
generation than the table, **the list wins and the table gets updated** in the same session.

Which tier: read the `model-selection-policy` skill. The rule here is only *how new*, not
*how big*. If unsure between two generations, **go up** — a previous generation at the same
tier usually costs the same and reasons worse.

*(scar 2026-08-28 — a whole verification pass redone because an id was typed from memory:
`rules/scars.md` § Stale-model-id)*

## Execution Defaults
**Browser:** Playwright = Microsoft Edge (`msedge`) only; no Chrome/Chromium fallback. If Edge is unavailable, stop and report the blocker; override only for Roberto-requested cross-browser tests. **Writing:** Tables > prose; commands > descriptions; comments WHY-only; conventional commits; PR = summary + test plan.

## Moved to the `engineering-reference` skill (loaded on demand, not canon)

How to do a thing you already chose to do never belongs in the canon. Loaded on demand:
execution reference (code style, test/mock boundaries, API conventions, local CI before push,
merge discipline, resolving review comments, repo settings & git hooks) · **Carded End-to-End**
(gate: `kb cover <plan.md>` in `test/validate.sh`) · documentation & documentation budget.
