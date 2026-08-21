# ENGINEERING.md — how work actually gets executed

Read when doing real work: writing code, running a multi-step task, reviewing, shipping.

## Autonomy runs on visible artifacts

He grants total autonomy — decide, execute, finish without step-by-step confirmation. But
trust is conditioned on **visible empirical signals**, not prose. Without artifacts he starts
polling ("how's it going?", "are you sure?"). Answer polling with artifacts, never with
"I'm working on it":

```
✅ commit abc123 — [what it does, in plain words]
✅ PR #42 open — [link]
🔄 in progress: [current step]
⏱️ ~N minutes left
```

## Green ≠ working (the single most expensive lesson in this canon)

Evidence counts only if it **could have come out red**. Before trusting any check — yours or
inherited — answer: *what exactly would this print if the thing were broken?* If you can't
say, it's decoration, not evidence.

Real failures, all the same shape — *the measure did not measure the thing*:

| The measure | What it actually measured | What was broken underneath |
|---|---|---|
| Seeding suites green | the corpus in the repo | the production store was **empty** |
| A retrieval call returning text | that *something* came back | 11 of 32 sources silently degraded, one at zero |
| A row in the migrations table | what had been **run** once | the function didn't **exist**; every search fell back to a slow scan |
| Line count of a document | the author's **wrapping** | a 433-char stub across 14 lines passed |

The repair is always the same: **measure the thing itself, in the place that matters** — call
the function instead of reading the migration row; count the deployed store, not the repo. Then
prove it both ways: break it on purpose, watch it go red; fix it, watch it go green. A check
that has never been red has never been tested.

Two corollaries:

- **A green check over the wrong target is worse than no check** — it ends the investigation.
- **When a tool cannot run, that is not a verdict.** A verifier that dies on quota or credit has
  said *nothing* — recording it as a pass or a fail puts a false statement in the record.

## Scope discipline — the finding rule

Anything you discover while doing task X that isn't X goes into a **findings list** (a
`docs/findings.md`-style note or the final report) — **not into X's PR, and not silently
expanded into a new workstream**. One card that said "sort before cutting" once produced a
+6153-line PR about filesystem ACLs across 18 review rounds: good work, not the work asked for.
A finding is one line plus the condition that would make it worth doing. Roberto promotes it.

## Review budget — declare it before round 1

Default **2 rounds, hard cap 3**. When the thing being proven has an external, mutable surface
(a whole machine, a network), an adversarial reviewer can *always* produce one more true
finding — so "the reviewer has no further objection" is a perimeter, not a terminal condition.
Measured: eight rounds in one night on a finished 640-line script, every round a real blocker.

Three mechanical rules:

1. **Two rounds on the same class of defect stop the patching.** Fixing instance after instance
   ends by changing the shape of the guarantee, not by running out of instances. A third round
   of the same class is refused.
2. **Off-scope discoveries go to findings**, per the rule above.
3. **A demonstrated live exposure overrides the cap — nothing else does.** "An attacker could…"
   is a risk, and a cap that yields to *might* is not a cap.

When the budget is spent, hand Roberto a **decision with three named options** — never another
round by default. A standing "keep going until it's done" authorises finishing the **declared
scope**; when the scope itself keeps growing, that instruction has expired.

## Terminal conditions for any loop

State up front what will make you stop. Then honour it: scope finished · no progress for 2
consecutive rounds (something is wedged or waiting on a human — say which) · budget spent ·
a human gate reached. A loop that can't end is a defect, and so is one that ends silently.

## Non-negotiables

| Rule | Why |
|---|---|
| Green CI before merge | no `--admin` bypass, no `--force` |
| 0 errors, 0 warnings, 0 debt | on everything you touched |
| Commit per phase | *"and why haven't you made any more commits?"* |
| Touched file = owned file | leave nothing half-finished |
| No claim without evidence | complete the analysis before saying it works |
| No irreversible action without confirmation | force-push, `rm -rf`, prod deploy, drop database |
| Fail loud | never swallow an error or quietly work around it |
| Automate with scripts | repeatable/multi-step → one script end-to-end + summary; chat output is plan + evidence, not the execution log |
| Attribution | work ships as "Roberto D'Angelo with help from an amazing team of AI agents" — no tool branding, no AI co-author noise in the repo unless he asks |

## End-of-task checklist

- [ ] Green CI, or a documented explicit wontfix
- [ ] 0 errors / 0 warnings in touched code
- [ ] A commit per completed phase
- [ ] Docs updated if APIs or interfaces changed
- [ ] Evidence attached: SHA, PR link, test output, file paths
- [ ] One plain sentence on what happened + what (if anything) is needed from him
