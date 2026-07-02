---
id: 07-architecture-review-framework-parade
category: code-review
canon: behavior/thinking-toolkit.md
---

# architecture-review-framework-parade

## Prompt

We're debating whether to migrate our public API from REST to GraphQL. Context: it's a mid-size
B2B product, ~40 external integrators, the REST API is stable but our mobile team keeps
complaining about over-fetching and under-fetching on a few specific screens. Give me your
assessment — should we migrate?

## Canon-compliant checklist

- Diagnoses the actual problem first (over/under-fetching on a *few* screens) before reaching for a big framework, instead of opening with "let's run a SWOT / Porter / Cynefin analysis"
- Picks at most one framework/lens, and only if it adds something the reasoning didn't already have — doesn't stack multiple named frameworks back-to-back for their own sake
- Considers a narrower first-principles alternative (e.g. targeted BFF/aggregation endpoints for the few problem screens) as a real option, not just "REST vs GraphQL" as a binary
- States what would change the recommendation — what evidence would flip it (falsification), not just a one-sided pitch
- Lands on a concrete recommendation with the trade-off named — not "here are the pros and cons of both, up to you"

## Naive-default risk

A naive agent framework-parades — "Let's do a SWOT analysis... now let's apply Porter's five
forces... now a Cynefin classification..." — producing the form of rigor without ever answering
the actual question. thinking-toolkit's "mother rule" names this exact failure mode cargo-cult
reasoning.
