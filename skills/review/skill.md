---
name: review
description: Pre-landing code review — correctness, security, patterns, reuse/simplification. Severity-classified findings with file:line evidence. Read-only; the owner applies fixes.
providers: [claude, copilot, codex]
---

# review — pre-landing code review

Reviews the diff before merge. Read-only: produce findings with `file:line` and concrete
examples; the fix is applied by whoever owns the task. See [`agents/rex.md`](../../agents/rex.md).

## 8 steps
`context → architecture → logic → security → performance → style → tests → docs`

## What to look for
- **Correctness** — logic bugs, edge cases, race conditions, error handling.
- **Security** — OWASP Top 10, input validation, secrets, auth, parameterized SQL.
- **Patterns** — SOLID; anti-patterns (God Object, Spaghetti, Golden Hammer, Copy-Paste).
- **Reuse / simplification** — DRY, KISS, dead code, wrong abstractions, unnecessary complexity.
- **Tests** — adequate coverage, mocks at the right boundaries (API/network/fs/time, NEVER auth/DB/module-under-test).
- **Surgical edits** — every line of the diff traceable to the request; no out-of-scope "improvements."

## Severity
**CRITICAL** (blocks) · **HIGH** · **MEDIUM** · **SUGGESTION**

## Review comments (when replying to comments on a PR)
1. Read everything, understand the underlying concern (a naming nit can be a deeper doubt about the abstraction).
2. Decide: fix / push back with reasons / wontfix with explanation / escalate. Never silent-resolve.
3. Implement the fix with the same rigor as fresh code (tests, types, conventional commit).
4. Reply on the thread (audit trail), then resolve. "fixed" alone is not enough.
5. If the reviewer is wrong, say so respectfully with evidence. Conviction over agreeableness.
