---
name: focus-group
description: "Simulates a focus group / validation with real users: creates a pool of persona-agents matching the requested profile + a moderator + a consolidator. Validates problems, definitions, hypotheses, apps, features, usability, feedback. Multi-mode (focus group, 1:1 interviews, usability test, micro-survey). TRIGGER: 'validate this hypothesis/idea/feature', 'valida questa ipotesi/idea/feature', 'what do users think', 'cosa ne pensano gli utenti', 'simulate a focus group', 'simula un focus group', 'test the usability', 'testa l'usabilità', 'create an early adopter panel', 'crea un panel di early adopter', 'real user feedback on X', 'feedback da utenti reali su X'. YES when you need the user's voice before building/deciding."
providers: [claude, copilot, codex]
---

# focus-group

Given a **topic + context**, generates a panel of **persona-agents** that behave like real
users of the requested profile, a **moderator** who runs the session, and a **consolidator**
who synthesizes. Used to bring the user's voice *before* building or deciding.

## Risk #1 — anti-sycophancy (non-negotiable)

Simulated users are **sycophantic by default**: they'd say "nice app!". That's useless theater.
Every persona MUST be anchored to:
- **real frustrations, alternatives already in use, budget, time, skepticism**, switching cost;
- the right to say "I wouldn't use this," "I don't see why I would," "I already do this with X";
- **no praise without a concrete reason** — an "I like it" only counts with the why and the use context.
The moderator **digs for friction**, not applause. The consolidator **weighs negative signal**
more than positive (specific negatives are more informative).

## Panel: persistent + ad-hoc

- **Persistent** (reusable, cross-session consistency): saved in the vault as
  `type: focus-persona` notes in `focus-panels/<panel>/` (e.g. `caregiver-fts`, `early-adopter-tech`).
  Reuse an existing panel when the topic matches → longitudinal comparisons.
- **Ad-hoc:** generate fresh personas from the topic/context when no matching panel exists.
  At the end of the session, **propose** (human gate) promoting useful personas to a persistent panel.

### Generating personas (diverse, not clones)
From an audience spec if provided (e.g. "caregivers of children with disabilities, 30-45, Italy"),
otherwise derived from the topic. Diversify along axes that matter: need/job-to-be-done,
technical competence, budget, use context, **skepticism level**, current alternative.
Default **5-8** personas. Each one: name, 1-line background, real goal, frustration,
current alternative, what would make them say no. Ground in the vault where relevant (gbrain).

## Modes (choose based on intent)

| Mode | When | How |
|---|---|---|
| **Moderated focus group** | exploring perceptions, surfacing themes, group dynamics | moderator poses prompts, personas respond and **react to each other** (agree/disagree) |
| **1:1 interviews** | depth, avoiding groupthink, sensitive topics | moderator ↔ one person at a time, in parallel (Agent tool) |
| **Task-based usability test** | testing app/feature/flow | give a concrete task; the persona "tries," reports friction/blockers/confusion, not opinions |
| **Quant micro-survey** | quick numeric signal | closed questions to all personas → distribution (e.g. 6/8 wouldn't pay) |

## Flow

1. **Setup:** clarify topic, intent (validating a problem? a definition? a hypothesis? usability?),
   audience, and **what counts as success/kill**. Choose the mode. Look for an existing panel.
2. **Panel:** reuse or generate personas (in parallel if there are many).
3. **Session:** the moderator runs it in the chosen mode. Personas stay **in-character**, anchored,
   free to disagree. Group mode: surface real agreements/disagreements.
4. **Consolidation:** the consolidator produces the report.

## Output — structured report

`~/.claude/reports/focus-group-<topic>-<date>.md`:
- **Verdict** in 3 lines: does the problem/hypothesis hold up? net signal.
- **Themes** (ranked by signal strength) with **verbatim quotes** from personas.
- **Agreements vs disagreements** (where the panel diverges — often the interesting part).
- **Severity/frequency** of the perceived problem; **willingness** (would use it? pay for it?).
- **Kill signals** that emerged (what would make the idea fail).
- **Actions** concrete + **confidence** (it's a simulation: say so — it guides, doesn't replace real users).

## Notes

- **Honesty about the limit:** it's a simulation. Great for *discovering questions, hypotheses,
  blind spots and friction*; **not** a substitute for real users for conversion numbers. Say so in the report.
- Composes with [[premortem]] (stress-testing the solution) inside [[problem-validation]].
- Personas must never be based on identifiable real people without consent; respect privacy blocks.
