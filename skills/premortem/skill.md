---
name: premortem
description: "Premortem on a plan/launch/product/assumption/strategy/decision. Assumes it has ALREADY failed 6 months from now and works backward to find every cause. Produces a revised plan with the blind spots exposed. MANDATORY TRIGGERS: 'premortem this/questo', 'what could kill it', 'cosa può ucciderlo', 'stress-test this plan', 'stress-test questo piano', 'what am I missing', 'cosa mi sto perdendo', 'find the blind spots', 'trova i blind spot'. STRONG TRIGGERS: 'what could go wrong', 'cosa può andare storto', 'poke holes in this plan', 'buca questo piano', 'where does it break', 'dove si rompe', 'play devil's advocate', 'fai l'avvocato del diavolo'. Do NOT activate on simple feedback, factual questions. YES when there's a plan/commitment where being wrong is costly."
providers: [claude, copilot, codex]
---

# premortem

The opposite of a postmortem: instead of understanding what went wrong after the failure,
**you imagine it has already failed** and figure out why, before you start. Gary Klein's method
(HBR); Kahneman called it his most valuable decision-making technique. Mechanism:
"this is dead, explain how" → the brain generates specific and honest causes, while
"is this a good plan?" → produces complacent answers. **It breaks the LLM's default agreeableness.**

## When (and when not)

**Yes:** a product/feature to build, a launch with money/reputation on the line, a pricing/model
change, an assumption, a positioning pivot, a partnership/deal, any commitment where being wrong
is costly. **No:** vague ideas with no plan (help plan first), questions with one answer,
feedback on a draft (that's editing), decisions already made and irreversible (a premortem only
helps if you can still change course).

## Minimum context threshold (mandatory)

A premortem is only as good as its context. Before launching one you need 3 things — look for
them first in context (conversation, `AGENTS.md`, memory/vault, cited files), then ask only for
the single most important missing piece, **one question at a time**:
1. **What is it?** (describable in one sentence)
2. **For whom / who does it impact?** (failures depend on who's involved)
3. **What does success look like?** (failure is inverted success)

## Session

1. **Explicit frame:** *"It's 6 months from now. [The plan] has failed. It's over. Let's look
   back and understand what went wrong."* — this is the psychological mechanism, don't skip it.
2. **Raw premortem:** generate **every** genuine reason it died — specific, anchored to real
   details, a true threat (not an edge case). However many are real: 4 or 9, no padding.
3. **Parallel deep-dives:** **one agent per reason, all in parallel** (Agent tool, a single
   message with multiple tool-use blocks). Each agent gets the full context + its reason and produces:
   (a) **failure story** (2-3 paragraphs, like a real case study), (b) **underlying assumption**
   (1 sentence), (c) **early-warning signal** (1-2 observable/measurable signs). <300 words, no hedging.
4. **Synthesis (this is the product):**
   - **Most likely failure** (to focus on first)
   - **Most dangerous failure** (most damage if it happens, even if less likely)
   - **Hidden assumption** (the biggest one the user hasn't questioned — often where the value lives)
   - **Revised plan** — **concrete** changes, each mapped to a failure ("test pricing at $X with 20 people before launching it," not "consider pricing")
   - **Pre-launch checklist** (3-5 things to verify/put in place, each one preventing/detecting a failure)

## Output

- `~/.claude/reports/premortem-<slug>-<date>.md` — full transcript (context, raw reasons, deep-dives, synthesis).
- Optional visual HTML report (dark, scan-friendly, one card per failure) if the user wants to see one.
- In chat: 3 sentences max — most likely failure, hidden assumption, most important revision.

## Notes

- **Always parallel agents** (sequential wastes time and contaminates results). **Always the
  "it's already failed" frame**. **Thorough but not padded.** **Don't sugarcoat** — say the
  uncomfortable things before reality does. **Concrete revisions**, doable this week.
- **Composes with `@board`** (multi-perspective red-team *now*) and with [[problem-validation]]
  (where the premortem is the "would solving it work?" stage). Different mechanism, different output.
- Respects **human gates**: the premortem informs the decision, it doesn't make it.
