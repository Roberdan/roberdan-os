---
name: ship
description: Platform-agnostic ship workflow — local CI gate, commit per phase, push, PR with Summary + Test plan, watch CI, merge-commit only. Honors human gates on main.
providers: [claude, copilot, codex]
---

# ship — get the work into production (git + gh)

Platform-independent ship workflow. No bypasses, no shortcuts.

## Pre-push: local CI pipeline (everything green before pushing)
1. **Format** — `cargo fmt --check` / `prettier --check` / `ruff format --check`
2. **Lint** — `cargo clippy -- -D warnings` / `eslint` / `ruff check`
3. **Type-check** — `cargo check` / `npx tsc --noEmit`
4. **Test** — `cargo test` / `npm test` / `pytest` (output shown)
5. **Build** — `cargo build` / `npm run build`

If a step fails: fix and **re-run all** checks. Never push with known failures.

## Sequence
1. Dedicated branch (never work directly on `main`).
2. Commit **per phase**, conventional + evidence-first messages (SHA/PR/CI).
3. `git push` the branch.
4. Open PR: **Summary + Test plan** (5-section template if the repo uses one).
5. Watch CI: `gh pr checks <n>` — all SUCCESS before proceeding.
6. Merge: **merge-commit only** (never squash, never rebase — preserves history for parallel agents).
7. Post-merge: delete the branch, fast-forward local `main`, report the merge commit SHA.

## Human gates (STOP — ask first)
- Merge to `main` impacting branch-protection / security / license / release-infra (#1)
- Force-push to `main` (#2) — **always forbidden without explicit confirmation**
- CI not fully green → don't merge anything pending/failing

## Review comments
Every comment (human or bot) must be analyzed, understood, and resolved well — never
silent-resolve, never a "fix" that only touches the quoted line while ignoring the substance.
Reply on the thread with what you did and why, then resolve. See [`skills/review`](../review/skill.md).
