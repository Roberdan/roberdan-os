# memory-protocol — durable cross-platform memory

Single memory contract for **every** platform (Claude/Copilot/Codex/web). Memory does
NOT live in per-tool silos. See [[ADR-0001]].

## Where it lives

| Layer | Path | Role |
|---|---|---|
| Source-of-truth | **vault** `~/Obsidian/Roberdan's Vault`, notes `type: agent-learning`, folder `agent-learnings/` | Durable, typed, versioned, cross-tool |
| Staging | `~/.roberdan-os/learnings/inbox/*.md` | Per-session capture, no lock |
| Index/recall | gbrain (semantic + keyword) | On-demand retrieval, never loaded whole into context |
| Hot-core | `agent-learnings/_core.md` (≤20 lines) | The few truths loaded everywhere |

`~/.claude/.../memory/` = **deprecated cache**. Content migrated to the vault; it is no
longer the source-of-truth.

## Taxonomy (5 classes)

| Class | What it is | Auto-eligible? |
|---|---|---|
| `tool-quirk` | a tool behaves differently than expected | yes, if reproduced ≥2x |
| `correction` | the user corrected a behavior | yes, with direct quote |
| `decision` | a choice made with the user, not derivable from the code | yes, if multi-session impact |
| `capability-gap` | something is missing in the system | **no — human gate** |
| `voice` | how the user communicates/decides | **no — gate #6, never auto-evolved** |

## Recall (operating rule)

1. **`gbrain search` keyword FIRST** (reliable). Semantic `query` drops sparse topics —
   see [[reference-gbrain-semantic-recall-gap]].
2. Scope to the right source (`vault` for memory), `--detail low`, small limit.
3. Greppable markdown as fallback until semantic recall is fixed.

## Privacy (hard gate, like code)

Never write to memory content from `~/.roberdan-os/private/` or personal/medical data
of Fight the Stroke / third-party names. Check the pattern **before** the write, not at
discretion.
