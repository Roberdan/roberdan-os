# evolve-protocol — weekly tool watcher (draft-only)

Keeps roberdan-os current on what's new in Claude Code / GitHub Copilot / Codex,
**proposing** patches — never applying them to behavior. See [[ADR-0001]].

## Cadence

launchd `com.roberdan.rda-evolve`, **weekly**. Fires regardless of which tool is open.

## Cadence detail

launchd `com.roberdan.rda-evolve`, **Saturday 02:00**. `StartCalendarInterval` means a missed
run (Mac off/asleep) fires at the next boot/wake — not skipped like cron.

## Flow

`evolve/watch.sh` **detects; it does not analyze.** It never launches a headless agent
(no `claude -p`) — the analysis is handed off as a kanban card any CLI can execute:

1. **Fetch** changelogs/release notes from sources (versioned URLs) → compare a content
   fingerprint against the last seen state (`~/.roberdan-os/evolve/seen`).
2. **Drop a card** per novel source into `kanban/todo/` (gitignored, local-only): id
   `<ts>-<name>`, standard frontmatter (title/repo/dod/acceptance/status/created), body
   carrying the source URL + the 4-step task. The card IS the handoff.
3. **Any agent picks it up** on its next run (Claude, Copilot — Roberto launches one, it reads
   the board, does the work): extract the concrete novelties, assess impact on what roberdan-os
   uses (hook/skill/agent/scheduling/MCP/memory/factory/loop), and **propose** in
   `roberdan-os/proposals/<YYYY-MM-DD>-<slug>.md` with **source citation (URL + version + date)**.
   No citation → no proposal. Then `@thor` + `kb finish` per the normal gate.

## Rejected-proposal buffer

The watcher fingerprints a **whole changelog page**, so any page change drops a card — but the
novelties an agent then extracts are often ones already assessed and declined. Measured
2026-07-21: `proposals/2026-07-{11,18,19}-claude-code.md` each re-raised the same two items,
each reworded, each concluding *"no additional patch required now"*. Three weeks, one question.

`evolve/declined.sh` records what was assessed-and-declined, per source, and step 2 of the flow
injects it into every card body. Step 5 of the card asks the agent to record its own declines,
so the loop closes instead of resetting every Saturday.

- Matching is **fuzzy on purpose** (token overlap coefficient ≥ 0.5 with ≥3 shared tokens), because
  the real repeats were reworded every week and exact hashing missed all of them.
- It **informs, it never blocks.** A fuzzy matcher that could silently drop a genuine novelty
  would be worse than the repetition it fixes: the card shows the declined list and asks the
  agent to say explicitly that it skipped them.
- Gate: `test/test-evolve-declined.sh` (in `test/validate.sh`) pins all three properties —
  reworded repeats match, unrelated novelties don't, and the block actually reaches the card.

## Invariants (hard)

- **Never** auto-commit to `behavior/ rules/ agents/ AGENTS.md` — draft only in
  `proposals/`.
- Mechanical enforcement: `hooks/post-task-sync.sh` (opt-in `RDA_AUTOSYNC=1`) only
  regenerates the gitignored `platforms/` wrappers on disk — it commits nothing
  (`platforms/` is not tracked; see `.gitignore`). `test/validate.sh` checks that
  generation is deterministic, not a wrapper-vs-canon diff.
- No-hallucination: every claim has a verifiable source.

## Done

A proposal is "ready" when Roberto reviews it and promotes it to a PR/commit. The
watcher never closes the loop on the canon by itself.
