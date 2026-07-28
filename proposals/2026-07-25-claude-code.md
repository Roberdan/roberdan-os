# Proposal — 2026-07-25 — claude-code

## Source citation (URL + version + date)
- https://docs.anthropic.com/en/release-notes/claude-code (checked 2026-07-28; redirects to https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md (checked 2026-07-28)
- @anthropic-ai/claude-code v2.1.216 (published 2026-07-20T20:19:37Z, npm metadata checked 2026-07-28)

## Novelties + impact
1. v2.1.216 hardened shell permission parsing around non-ASCII shell word boundaries and invisible Unicode in PowerShell commands. roberdan-os has its own `hooks/bash-guard.sh` regex gate, so the same class should be blocked before the guard tries to classify a command.
2. v2.1.216 also shipped sandbox and worktree fixes, but the current factory is already documented as bounded-not-sandboxed and external dispatch is dormant; that is not enough by itself to patch live canon today.

## Suggested patch (draft only)
- Add a `bash-guard.sh` prefilter that refuses shell commands containing invisible/bidi/control Unicode in the command head before the existing `git push`, `git reset`, and docs-staging regexes run. Citation: https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md — @anthropic-ai/claude-code v2.1.216, published 2026-07-20T20:19:37Z; checked 2026-07-28.

