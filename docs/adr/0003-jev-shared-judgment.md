# ADR-0003 - Optional shared Jev judgments, never delegated authority

**Status:** Accepted for implementation, 2026-09-20.
**Decision owner:** Roberto, following an independent Claude Opus 5 adversarial review.
**Scope:** shared runtime, four consumers, agent/skill routing, documentation and release.
**Not authorized by this ADR:** recurring provider spend, disclosure of confidential data,
or replacing human approvals. Paid activation remains a separate operator decision.

## Context

The TypeSafe skill teaches an agent how to build typed judgments; installing it does not
connect the agent to Jev. Jev is a remote model, not an autonomous local agent. It evaluates
independent Choice, Score and Noul questions against a shared state. It does not run tools,
generate a rationale, or prove that a test executed.

The provider documents USD 0.042 per million input tokens, free output tokens, and weaker
non-English performance. These facts justify exploring repeated semantic judgments, not
claims of measured savings or correctness. No successful local inference or preference
validation was available when this decision was made. An authenticated model-list request
succeeded after correcting the client's missing Bearer authentication scheme.

The alternative of an extra model call on every turn adds latency and trust dependencies
without necessarily replacing work. An indefinitely isolated demonstration does not satisfy
the operator's request for useful system-wide integration either.

## Decision

Implement one standard-library Python client, `bin/jev.py`, with a versioned profile registry.
The canonical `jev` skill describes when each agent should reach the client. Existing
`bin/sync.sh` generates platform wrappers; upstream TypeSafe skill files remain untouched.
No provider network call is added to a lifecycle hook, privacy scanner or blocking gate.

### Four reachable consumers

| Profile | Trigger and output | Non-negotiable boundary |
| --- | --- | --- |
| `twin` | Compare eligible public/synthetic options across relationship, reversibility, mission and focus criteria. Return individual signals. | Observation only: no combined recommendation or claim to predict Roberto. |
| `retrieval` | Score relevance of already-retrieved public/synthetic candidates. Return a stable ordering of every candidate ID. | Preserve original order separately and protect exact matches; never discard candidates. |
| `wanda` | Classify public/synthetic updates into progress, blocked, decision needed or unknown. | Suggestions only; no task starts, model changes or review-budget decisions. |
| `thor` | After independent criteria enumeration, examine supplied requirement/evidence links. Produce non-exhaustive follow-up questions. | No verdict, aggregate pass score, invented evidence or removal of criteria. |

The Twin first reasons locally using its normal sources and produces an independent
recommendation. The orchestrator can then invoke Jev and return the separate observations.
The Twin agent does not acquire broader shell privileges just to invoke this helper.
Jev never replaces the mandatory Twin consultation.

Public default criteria are an explicit, reviewable starting rubric, not a learned personality.
Private memory remains local. Synthetic choices test mechanics; only genuinely operator-labeled
choices can test preference agreement. Absence of a label means unknown, not consent.
Changing the Twin into a score-combining recommender is outside this release.

### Invocation and disclosure

`evaluate PROFILE --input FILE` validates and prepares a dry-run without credentials or
network. It shows the outbound payload and its canonical SHA-256 for local review.
`--live --approved-sha256 HASH` additionally requires private configuration enabling that
profile with an explicit request allowance, budget and approval reference.

Only declared `public` or `synthetic` inputs are accepted. Unknown fields and common secret
patterns are rejected; each profile selects its allowed fields rather than dumping context.
Names replaced by placeholders do not establish safety. No raw prompt, repository, vault,
dossier, customer material or sensitive-derived summary is automatically ingested.

**Honest limit:** classification and the approval reference are declarations, not proof of
data provenance or human identity. The hash binds the reviewed bytes to a request; it does
not authenticate the reviewer. This is not a sandbox against a malicious same-user process.
Agents must not manufacture approval, enable profiles themselves, or treat a key as consent.

### Runtime and failure semantics

- Pin `jev-1.13.0` and version the public rubric and policy. Batch independent questions;
  keep exact calculations, hard constraints and permissions in local code.
- Bound input size, item counts, response size and wait time. Bytes are a transport limit,
  not a claim about provider tokenization. Never retry a possibly billed POST automatically.
- Use Bearer authentication to the fixed HTTPS endpoint. Reject redirects instead of
  forwarding a credential. No endpoint override from submitted content.
- Validate answer IDs, types, numeric ranges, distributions, model and usage before consumption.
  State missing evidence explicitly; do not confuse confidence with completeness or truth.
- Disabled mode performs zero calls. An unavailable or malformed evaluation returns
  `not_evaluated` with a safe reason. The original workflow remains in force, visibly.
- Keep credentials/configuration/state outside Git, owner-only. Never persist request text,
  raw response text or the key in logs. Cache only validated, bounded judgment data/metadata.
- Cache identity includes state, questions, model, rubric and policy; changed inputs invalidate
  reuse. A cached judgment does not grant authority.
- Serialize budget reservations before sending. Failed/uncertain calls retain a reservation.
  Request and estimated-spend limits are application controls, not a provider billing guarantee;
  provider usage and billing remain authoritative.
- Reported usage above the reservation blocks further network calls, not valid cache reads.
  Resumption requires explicit local operator acknowledgement; it never resets cumulative
  consumption or expands an allowance. Changing configuration alone cannot clear the stop.
- Expose collection/text limits in `profiles`. Oversized reviews retain the complete matrix
  locally and use explicitly scoped batches, never silent truncation or automatic paid fan-out.

## Delivery and activation

This release implements all four concrete command consumers, their canonical instructions,
synthetic examples and offline transport tests. It does not claim that a host model will
always follow a skill instruction. Routing is instruction-driven, not an always-running daemon.

Live mode defaults off everywhere, including after installation. The release can be accepted
without spending on inference. Subsequent live activation needs a bounded operator-approved
budget and payload review; it is not implied by publishing this code.

Before increasing reliance, compare the existing workflow and assisted workflow on held-out
public/operator-labeled material, including Italian, ambiguous cases and intentionally missing
evidence. Record false alarms, missed issues, end-to-end time and observed usage. Do not invent
a universal accuracy threshold, benchmark outcome, fixed waiting period or savings percentage.
For Twin, keep observations separate until preference agreement is actually established.
For Thor, keep the profile optional and non-authoritative permanently.

## Alternatives and consequences

- **Only install the upstream skill:** rejected; it does not provide a runtime consumer.
- **Replace agent reasoning or hard gates:** rejected; typed probabilities are not evidence,
  authorization or a faithful digital identity.
- **Model routing as the first use:** rejected; configured agent roles are policy, not ground
  truth about optimal per-task models. Existing required model selections remain unchanged.
- **Every-turn cloud classification:** rejected; confidential context and avoidable latency.
- **Shared optional runtime:** accepted; one implementation to audit and disable, with real
  consumers. Maintenance and false reassurance can outweigh token savings; retire a profile
  if measured benefit fails to cover these costs.

## Release acceptance matrix

These are implementation tests, not claims about Jev model quality.

| ID | Required evidence |
| --- | --- |
| J01 | All four CLI profiles prepare the shipped examples without network or credential access. |
| J02 | Disabled/missing configuration and missing payload approval cannot reach transport. |
| J03 | Allowed fields/classifications and bounded inputs reject unknown/private/secret-bearing data. |
| J04 | Fake-transport live tests exercise correct Bearer auth, pinned model and all four consumers. |
| J05 | Malformed answers, wrong IDs/models, invalid numbers and failures yield no success verdict. |
| J06 | Credentials and runtime state are owner-only, outside Git; errors/logs do not echo secrets or input. |
| J07 | Request/spend reservations serialize; exhausted limits prevent calls; uncertain calls stay charged locally. |
| J08 | Cache reuse is input/version-specific, with no raw source text persisted. |
| J09 | Twin keeps observations separate and excludes ineligible options from the outbound state. |
| J10 | Retrieval returns every ID and original order; exact matches and ties remain stable. |
| J11 | Wanda cannot change work state; Thor requires prior enumeration and never emits approval. |
| J12 | Canon, Twin export, three agents and verification skill route to the shared skill; generated wrappers expose it. |
| J13 | Tests run in normal validation; fault/mutation checks demonstrate refusal boundaries, not only happy paths. |
| J14 | README, changelog, version and release identify disabled-by-default live mode and unmeasured benefits. |

The verifier reads this matrix itself. Live provider availability, Italian accuracy and
personal preference agreement are activation evidence, not falsely marked passing by mocks.

## References

- [TypeSafe model contract, limits and pricing](https://docs.typesafe.ai/models)
- [System One](https://docs.typesafe.ai/concepts/system-one)
- [API](https://docs.typesafe.ai/api)
- [Official JavaScript client authentication](https://github.com/typesafe-ai/typesafe-sdk-js/blob/v0.6.0/src/client.ts)
- [Operating skill](../../skills/jev/skill.md)
- [Human gates](../../AGENTS.md#human-gates)
