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
| Private brain | **`~/.roberdan-os/private/brain/`** — gbrain source `default` (`people/ projects/ orgs/`) | Facts about clients, deals and open work, marked `visibility: private` |

**Why the private brain is a separate row and not "just the vault".** The vault is an
Obsidian vault: it syncs to a cloud, and `memory-protocol` reserves it for `type:
agent-learning` — how to work, not who pays what. A client's margin percentage in a
cloud-synced vault is a *different* exposure, not a fix. `~/.roberdan-os/private/` is
local-only and sits outside every git worktree, which is the one property that makes an
accidental `git add -A` unable to reach it. This became a rule on 2026-08-24, when the
`default` source turned out to have **no `local_path` at all** and gbrain had been writing
its notes relative to the CWD — which that day was a **public** repo. A generator with no
declared destination does not decline to write; it writes wherever it happens to be
standing. See [`docs/privacy-leak-check.md`](../docs/privacy-leak-check.md).

**Refresh it with `gbrain import`, never `gbrain sync`.** `sync` requires a git repo — and
the private brain is deliberately outside one, so following gbrain's own
`⚠ default: never synced — run gbrain sync` hint ends in a `git init` that undoes the whole
point. `sync` also *reconciles* a directory against the source, so 3 files in front of 354
pages are 351 deletion candidates; `import` only adds and updates (measured: 354 → 357, none
deleted).

```
cd ~/.roberdan-os/private/brain && gbrain import .
```

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
