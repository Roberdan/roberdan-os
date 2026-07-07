---
name: verify-done
description: Evidence-first done-gate. Refuses to mark work complete without concrete artifacts (commit SHA, PR link, file path, test output) verified empirically. The cardinal principle.
providers: [claude, copilot, codex]
---

# verify-done — the evidence-first done-gate

**Done is not "should work."** It's Roberto's cardinal principle. Use this
skill before declaring any task complete.

**No false done (see `rules/best-practices.md § No False Done`).** Never say done / verified /
working / green / released until you've observed the evidence for THAT claim, end-to-end,
yourself. A claim needs evidence for the claim itself ("released" ⇒ CI green on the release commit
confirmed, not "I pushed"); whole-system, not just the part you touched; "should/probably" is not
"is". A confident-but-wrong "all good" is the most damaging thing you can do — it breaks trust in
the whole system. Prefer a mechanical gate that carries the evidence over your own assurance.

## The cardinal question — did it achieve the goal (qualitatively, not just quantitatively)?
Before the mechanical checks: **did the work fulfil the goal/order that was given, in substance
and with quality — not just "N tasks done, tests green"?** Map each thing the goal asked ↔ what
was delivered; a silent gap, a thinner-than-asked result, or "the letter not the spirit" is a
FALSE done even with every box ticked. Green checkboxes are necessary, not sufficient. Judge the
outcome against the original intent (the goal as clarified at intake + acceptance), cite the
goal-clause ↔ artifact mapping as evidence — never a vibe-pass, never satisfied by volume of
output. (This is the qualitative half; the checklist below is the quantitative half. Both, or
not done.)

## The 3 mandatory conditions
1. **Evidence** — concrete artifacts attached: commit SHA, PR link, file path, test output.
2. **Verified empirically** — actually tested, not estimated. Show the output, not the estimate.
3. **Systems in sync** — vault (Obsidian) + Convergio twin plan + in-repo docs aligned.

## Zero-progress screen (cheapest check, run it FIRST)
Before the checklist: **did any durable state actually change since the task started?**
Compare git (`log`/`status`), produced artifacts, or the tracked task state against the
start point. If nothing durable changed, the "done" claim is rejected outright — no need
for finer checks. Most false dones are declared at **zero** verifiable progress, not on
near-misses (observed 65–88% across agent benchmarks, arXiv:2606.09863), so this one
cheap predicate catches the majority of them.

## Checklist (NON-NEGOTIABLE)
- [ ] 0 build errors
- [ ] 0 warnings (treated as errors)
- [ ] 0 technical debt left open
- [ ] Coverage ≥ 80% on business logic, 100% on critical paths
- [ ] Tests run — **output shown**, not described
- [ ] **Feature wired end-to-end** — reached from a live path (entry point → caller → feature), not just present on disk. Trace the path; a definition with no live caller is not done. See `rules/best-practices.md § Wired End-to-End`.
- [ ] Docs updated if you changed an API/interface
- [ ] Commit for every completed phase
- [ ] CI green (or explicit documented wontfix)

## Verification per claim type
| Claim | Evidence required |
|---|---|
| "It builds" | build output |
| "Tests pass" | test output |
| "It works" | demonstrated execution |
| "It's secure" | security scan |
| "It's deployed" | confirmed deploy |

**Claims without evidence are rejected.** In Convergio: only `thor` sets `done`
(executors propose `submitted`). See [`agents/thor.md`](../../agents/thor.md).

## If you got it wrong
Acknowledge, fix, don't justify:
`Done — that was my mistake. Fixed X. Commit abc123.`
