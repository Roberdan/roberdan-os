---
name: scars
version: "1.0.0"
last_updated: "2026-08-29"
---

# Scars — the failures the rules are made of

Not loaded in every session. `rules/best-practices.md` carries the rules and points here; this
file carries the full account of what went wrong, so a rule can be understood (and defended)
instead of merely obeyed. Read it when a rule looks like overhead, when you are about to argue
that a gate does not apply, or when writing a new rule — the shape of these is the shape of the
next one. **Never delete an entry: a rule whose scar is forgotten is the next rule to be dropped.**

## Gates — a promise is not a proof

### Gates — a declared gate that was never measured (2026-07-14)

Real failure, 2026-07-14: a plan declared "all views on the design system"; six phases shipped, all "green", and that one gate was never measured. It was at 72/98, with 54 raw colours still in the app. The user found it by asking.

### Gates — a counter that looked good while the work was undone (2026-07-14)

Same failure: the gate counted "files that mention the design system", so a file with one token and thirty raw colours counted as done, and 26 views that colour nothing at all were counted as debt. The metric was wrong in both directions.

### Gates — the green suite that pinned nothing (2026-07-14)

Real failure, same campaign: the most important fix of the whole effort — a clock that froze while the phone slept, making a monitor claim "updated a moment ago" over a child unwatched for six hours — was pinned by NOTHING. The done-gate reintroduced the bug and all 620 tests stayed green. The test's own comment claimed it would catch exactly that.


## Released-on-a-push

### Released-on-a-push — "v2.4.0 released" while CI was red (2026-07-06)

**Real failure this rule exists to prevent** (2026-07-06): an agent announced "v2.4.0 released,
all set" while the release commit's CI was in fact **red** — a `--auto` change had been left
uncommitted, so `main` was broken. "Released" had been claimed on "I pushed", not on a confirmed
green CI run. The fix that should have been the habit: wait for the CI conclusion, read it, THEN
say released.


## Blanket-add

### Blanket-add — a mutation test swept into a docs commit and pushed (2026-07-14)

Real scar, 2026-07-14, and the worst of the campaign: `@thor` was running a mutation test — deliberately reintroducing a clock bug to prove the test caught it — in the same checkout where the orchestrator ran `git add -A && git commit` to update a plan. The mutation was swept into a commit titled `docs(p3): ...` and **pushed to `Development`**. A clinical-safety regression shipped inside a documentation commit, and every gate stayed green because no test covered that line. Thor spotted it and restored it. Two rules, both cheap: **stage docs by path**, and **mutation testing only ever in a throwaway worktree**.

### Blanket-add — a live agent declared dead, two worktrees lost (2026-07-14)

Same session: a live F4 agent was declared dead and had its worktree pulled from under it; it recreated it, and in doing so reset a second agent's worktree, destroying that one's work. The orchestrator caused both.


## Secret-backup

### Secret-backup — .gitignore covered .env* but not *.bak (2026-08-20)

Reason, measured on MirrorBuddy 2026-08-20:
`.gitignore` covered `.env*` but not `*.bak`, so `cp .env.production.local .env.production.local.bak`
produced a file full of live database URLs, Stripe and Supabase keys that `git status` listed as
untracked — one `git add .` from being committed. The original was ignored, the backup was not,
and nothing warned. Two consequences:


## Stale-model-id

### Stale-model-id — verification subagents launched on a previous generation (2026-08-28)

**Precedent, 2026-08-28 (audit MirrorScopio):** four verification subagents were launched on
`claude-sonnet-4.6` while `claude-sonnet-5` and `claude-opus-5` were both in the tool's own
model list. Roberto caught it and the whole pass had to be redone. Nothing in the canon was
wrong — the mapping above was already correct — the id was simply typed from memory. That is
the failure mode this rule exists to stop.

## Unwired — features that exist but nothing reaches

Four shapes seen in this repo or its work: a config field written in one file but read from a
*different* file the runtime uses (a `provider:` key set in a tool's native profile but not in the
profile the dispatcher reads → silently ignored); a generated wrapper on disk that no tool is
pointed at (the `tool-coverage` gate in `test/validate.sh` exists to prove skills resolve into the
canon, not just exist); code that "looks wired but never ran" (an entire eval fixture class is
named after this); a new env var or flag added to a script but never branched on, an agent file
never referenced from `AGENTS.md`, a skill never symlinked into the tool's skills dir.

## How to use these

Each entry pairs with a rule in `rules/best-practices.md`. When a gate feels like ceremony, find
the scar that made it: every one of these cost real work, and four of the five shipped **green**.
