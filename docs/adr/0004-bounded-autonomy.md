# ADR-0004 - Memory-informed decisions inside standing authorization

**Status:** Accepted, 2026-09-20.
**Decision owner:** Roberto, explicitly requesting fewer routine interruptions, useful
memory-backed decisions and a consolidated release after the first real Jev activation.
**Scope:** behavioral canon, Twin/portable routes, Jev consent semantics and publication checks.
**Not authorized here:** new spend, confidential disclosure, unsolicited messages or business
system writes, access changes, irreversible destruction or permission bypasses.

## Context and decision

Repeated consent questions for unchanged synthetic inputs inside an approved allowance
stalled work without protecting a new boundary. Meanwhile, passing fixture-only tests did
not establish compatibility with real Jev answers: the first four authorized requests exposed
missing answer-type support and an incorrect assumption about Choice confidence. Four
corrected requests, one per profile, subsequently returned validated evaluations.

Adopt the [standing authorization contract](../../behavior/roberto-mode.md#standing-authorization-decide-inside-the-boundary-2026-09-20):
act on the listed routine classes inside the requested scope; reuse existing matching
authorization, rather than creating another confirmation ritual. Preserve every human gate
and host consent control. Record an isolated authority gap and continue independent authorized
work. Public local edits are not public push/tag/release. A private/demo label is not proof
that data can leave the machine or an action can be reversed.

Twin may select an authorized next step; the orchestrator executes it. For decisions involving
preferences, consult [durable memory](../../memory/memory-protocol.md#decision-recall-evidence-not-permission)
for explicit preferences, applicable precedents and observed outcomes. Keep provenance,
date/applicability and uncertainty. Current instructions outrank conflicting recollections;
memory is not consent. Missing recall does not halt ordinary authorized work. Do not learn
preferences from model guesses or move private notes/sensitive-derived summaries into Jev.

Jev stays an optional separate judgment, never a permission or identity oracle. Disclosure
approval can cover a reviewed public/synthetic class, not only one immutable example. Each
actual payload is still reviewed and hash-bound. Every attempt counts against the existing
cumulative allowance, including controlled replays after fixing a diagnosed local bug.
No allowance transfers to a different purpose; no session reset, inferred top-up, automatic
transport retry or indefinite repair loop is added. Honor the actual approval's scope/lifetime,
not an invented per-session expiry. See [ADR-0003](0003-jev-shared-judgment.md) for the runtime.

## Publication check

Before publishing an already-authorized Git artifact, run
`bash bin/publication-check.sh <reviewed-base>` from this repository, or invoke its canonical
path from another target repository. The helper scans the complete outgoing commit range
with Gitleaks, redacts diagnostics, disables inline `gitleaks:allow` bypasses and refuses an
invalid/empty range, dirty tracked files, missing/failed scanner or a changed HEAD.
Gitleaks must already be installed; the check never installs tools or weakens host prompts.
The command does not push, tag, release or provide disclosure authorization.

The universal entry point and shipping skill route publication through this check, including
when another installed skill supplies the shipping sequence. This is instruction-based
routing, not an unbypassable Git hook. Gitleaks recognizes some secret patterns: a clean scan
does not establish that proprietary content, personal data or a private memory is public.
Keep the existing privacy checks and inspect actual content/provenance separately.

## Decision examples

| Situation | Expected behavior |
| --- | --- |
| In-scope local refactor/tests in an approved private/demo project | Execute without a preference question. |
| Local commit in a public repository | Execute if in scope; publication remains separate. |
| Same approved synthetic payload after repairing a diagnosed local defect | Review/replay within the same remaining allowance; no new routine consent. |
| Eleventh request under a ten-request allowance | Refuse further network use; report the local cap, not exhausted provider credit. |
| Unused allowance proposed for a different provider or purpose | Require applicable approval; no transfer by analogy. |
| Relevant old memory conflicts with today's instruction | Prefer today's instruction; record the conflict, do not invent permission. |
| Memory lookup fails during an ordinary implementation choice | Use current instructions and a reversible in-scope default; continue. |
| One step needs an external message or internal-system write | Hold that action; continue independent authorized work. |
| Gitleaks passes but the artifact contains confidential business prose | Do not publish; a secret scan is not declassification. |
| Public push/release already expressly authorized for this artifact/destination | Review contents, pass publication check and proceed; do not re-ask. |

## Acceptance matrix

Review every row separately. Structural text tests prove routing/contract presence, **not**
that every host model obeys instructions; synthetic/live tests do not establish judgment
quality, preference prediction, Italian accuracy or savings.

| ID | Requirement | Evidence |
| --- | --- | --- |
| A01 | Documented typed answers and independent Choice confidence accepted; malformed answers rejected | Jev response regressions and mutation checks |
| A02 | Credit/payment/local-cap alerts are distinct, bounded and do not expose raw provider text | Credit tests, including missing/oversized/unreadable errors |
| A03 | Failure accounting, request/spend caps, cache identity and no automatic retries remain intact | Full offline Jev suite and operator-owned status/receipts |
| A04 | All four profiles have performed successful real inference after the protocol fix | Four operator-owned corrected activation receipts; never read credentials or make new paid calls for acceptance |
| A05 | Canonical, global, agent and portable Twin routes carry standing authorization without removing human gates | Twin drift, canonical guardrail/structure checks; review decision examples above |
| A06 | Memory informs preferences with provenance, conflict handling, local privacy and graceful unavailability, never consent | Memory protocol, Twin route/drift checks and a scoped read-only recall probe |
| A07 | New/over-cap spending, messages/business writes, sensitive egress and consequential unapproved actions still require authority | Canonical/portable boundaries and decision examples; no claim of new host enforcement |
| A08 | Publication scanner fails closed and is reachable from universal/ship instructions | Isolated publication tests, routing tests and a real redacted scan of the outgoing release range |
| A09 | Documentation/version explain installation versus live activation and limitations honestly | README, changelog, ADRs, VERSION, links/frontmatter checks |
| A10 | Release is integrated, published, installed and reachable, with green checks on the actual release revision | PR, merge/tag/release identity, installed skill/runtime probe and CI |
| A11 | Existing private allowance/state is preserved and installed approved cache reuse causes no new network charge | Safe status and cached approved fixture probe; never reset the ledger |
| A12 | Independent review precedes closure; task-owned work is clean/integrated and ready for automatic cleanup | Thor verifies pre-closure readiness; after `kb finish`, the orchestrator verifies the closed card and actual worktree/branch removal before reporting completion |
