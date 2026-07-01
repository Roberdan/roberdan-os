# evolve-protocol — weekly tool watcher (draft-only)

Keeps roberdan-os current on what's new in Claude Code / GitHub Copilot / Codex,
**proposing** patches — never applying them to behavior. See [[ADR-0001]].

## Cadence

launchd `com.roberdan.rda-evolve`, **weekly**. Fires regardless of which tool is open.

## Flow

`evolve/watch.sh`:
1. **Fetch** changelogs/release notes from sources (versioned URLs) → compare against
   the last seen version (durable state `~/.roberdan-os/evolve/seen.json`).
2. **Diff capability:** for each novelty, assess whether it touches something
   roberdan-os uses (hook, skill, agent, scheduling, MCP, memory).
3. **Propose** in `roberdan-os/proposals/<YYYY-MM-DD>-<slug>.md`: what changes, why,
   the suggested patch, **source citation (URL + version + date)**. No citation →
   no proposal.

## Invariants (hard)

- **Never** auto-commit to `behavior/ rules/ agents/ AGENTS.md` — draft only in
  `proposals/`.
- Mechanical enforcement: `hooks/post-task-sync.sh` auto-commits **only**
  `platforms/` (scoped git add, opt-in). `test/validate.sh` does the drift-check.
- No-hallucination: every claim has a verifiable source.

## Done

A proposal is "ready" when Roberto reviews it and promotes it to a PR/commit. The
watcher never closes the loop on the canon by itself.
