# ontology-protocol — promotion + memory hygiene (single-writer)

**Extends** the vault's ontology (Tolaria), not a new store. A single serial process
touches the vault (AutoGit lock). See [[ADR-0001]], [[memory-protocol]].

## Promotion (quarantine → vault)

`ontology/curate.sh` (launchd, single-writer):
1. Reads `~/.roberdan-os/learnings/quarantine/`.
2. For each eligible candidate (see [[learn-protocol]] gate): creates/updates a
   `type: agent-learning` note in `agent-learnings/`, with Tolaria frontmatter
   (`belongs_to`/`workspace`/`supersedes`) → filterable/deletable in bulk.
3. Single AutoGit commit, retry on `.git/index.lock`. Never concurrent.
4. Refresh gbrain (index the new note).

## Periodic hygiene (triggered, human-gated)

NO auto-merge/auto-delete (lossy + irreversible, gate #4). The job **proposes**:
- semantic **dedup** (gbrain near-dup) → list of merge candidates.
- **tombstone retire**: facts that are `RESOLVED`/pre-v3 → archive to
  `agent-learnings/_archive/`.
- **hot-core compression**: `_core.md` ≤20 lines, dead lines cost tokens everywhere.
Merge/delete remain a human decision. Output = a report of proposals, not actions.

## Boundaries (what it does NOT do)

No auto-generated relations between learnings (spurious edges — see
[[reference-gbrain-wikilink-gap]]). No bespoke ontology engine. No real-time
auto-update. **Reuse > new structure.**
