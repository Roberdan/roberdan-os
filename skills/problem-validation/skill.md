---
name: problem-validation
description: "Helps figure out WHICH problems are worth solving, not just how to solve them. Orchestrates: problem discovery/validation with users (focus-group) → prioritization (severity×frequency×reachability×fit) → solution stress-test (premortem). TRIGGER: 'is it worth solving X', 'vale la pena risolvere X', 'is this a real problem', 'è un problema vero', 'which problem should I attack', 'quale problema attacco', 'should I build this', 'dovrei costruire questo', 'validate before building', 'validiamo prima di costruire', 'prioritize these problems', 'prioritizza questi problemi', 'is this worth building'. YES upstream of any non-trivial build/investment."
providers: [claude, copilot, codex]
---

# problem-validation

The system shouldn't just solve problems, it should say **which ones are worth it**. This skill
is the upstream orchestrator: before building, it validates that the problem is real, that it's
worth solving, and that the solution would hold up. Composed from the other two skills + gstack.

## When

Before any non-trivial build/investment/pivot. If someone says "let's build X" → first ask
"is the problem behind X real, frequent, and worth it?". If it's a vague idea → first
`gstack:spec` to make it concrete, then validate.

## Pipeline (3 stages, human gate between the important stages)

### 1. Does the problem exist? → [[focus-group]]
Brings the user's voice on the **problem**, not the solution. Typical mode: focus group +
1:1 interviews. Questions: does the problem really exist? how much does it hurt? how do people
solve it today? Output: the problem is **real/imagined**, with evidence (quotes, disagreements,
kill-signals). *If the problem doesn't hold up here → STOP. You just saved a useless build.*

### 2. Is it worth it? → prioritization rubric
If there are multiple candidate problems, score each (1-5) and make the trade-off explicit:

| Criterion | Question |
|---|---|
| **Severity** | how much does it hurt when it happens? |
| **Frequency** | how often does it happen / how many people? |
| **Reachability** | can I actually reach and serve the people who have it? |
| **Strategic fit** | is it within my mission/unique leverage? (for Roberto: disability/inclusion, Fight the Stroke) |
| **Willingness** | would they pay / change behavior? (from the focus-group) |
| **Cost of being wrong** | if I attack the wrong problem, how much do I lose? |

Low score on Reachability or Fit → usually a no, even if Severity is high.
Don't sum blindly: make visible *where* the risk lies.

### 3. Would the solution hold up? → [[premortem]]
On the winning problem + the proposed solution, launch the premortem: "it's 6 months from now,
the solution has failed, why?". Exposes assumptions and produces the revised plan + checklist.

## Leverage gstack (don't duplicate)

- **`gstack:spec`** — turns vague intent into an executable spec *before* validating.
- **`gstack:office-hours`** — YC-style pressure on the business/go-to-market *after* validation.
- **`gstack:plan-ceo-review` / `plan-eng-review`** — once validation becomes a plan.
This skill sits **upstream** (is the problem worth it?); gstack helps downstream (how to execute it).

## Output

`~/.claude/reports/problem-validation-<topic>-<date>.md`:
- **Clear recommendation:** build / don't build / refine first — with the why.
- Evidence from the focus-group, prioritization table, premortem synthesis.
- **The irreducible truth:** what's the real thing to decide (first-principles style / `@socrates`).

## Notes

- **Bias-to-kill:** this skill's default is **skeptical** — it's more valuable to say "not worth it"
  than to confirm. Compose it with `@socrates` (irreducible truth) and `@board` (red-team).
- It's simulation + framework: **guides the decision, doesn't make it** (human gate).
- Voice/decision "as Roberto" → composes with the twin ([[roberdan-twin]]).
