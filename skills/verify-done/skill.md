---
name: verify-done
description: Evidence-first done-gate. Refuses to mark work complete without concrete artifacts (commit SHA, PR link, file path, test output) verified empirically. The cardinal principle.
providers: [claude, copilot, codex]
---

# verify-done — the evidence-first done-gate

**Done is not "should work."** It's Roberto's cardinal principle. Use this
skill before declaring any task complete.

## The 3 mandatory conditions
1. **Evidence** — concrete artifacts attached: commit SHA, PR link, file path, test output.
2. **Verified empirically** — actually tested, not estimated. Show the output, not the estimate.
3. **Systems in sync** — vault (Obsidian) + Convergio twin plan + in-repo docs aligned.

## Checklist (NON-NEGOTIABLE)
- [ ] 0 build errors
- [ ] 0 warnings (treated as errors)
- [ ] 0 technical debt left open
- [ ] Coverage ≥ 80% on business logic, 100% on critical paths
- [ ] Tests run — **output shown**, not described
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
