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
2. Scope to one source (`vault` for memory), with a small limit and bounded snippets.
   Current CLI: `gbrain search "<terms>" --source-id vault --limit 3 --snippet-chars 300`.
   Check installed help before using version-specific flags; `--detail` is not supported by
   gbrain 0.50's search command. Missing MCP tools do not imply the CLI is unavailable.
3. Greppable markdown as fallback until semantic recall is fixed.

## Decision recall: evidence, not permission

Before a preference-dependent decision, Twin retrieves a few relevant explicit preferences,
comparable past decisions and their **observed outcomes**, not a dump of the vault. Start with
known names/terms; read the actual source note when a snippet is insufficient. A retrieval
score is relevance, not truth or proof that the search was complete.

For each fact used, retain its note identifier, date if known, provenance, scope and applicability.
Distinguish operator-confirmed statements from model hypotheses or unconfirmed summaries.
Current explicit instructions and applicable approvals outrank stale or conflicting recollections;
an old decision for one project does not authorize an action on another. Unknown dates,
contradictory notes and missing outcomes remain explicit uncertainty, never invented facts.

Memory informs **how** to choose within authority; it cannot grant spend, disclosure, sending,
publication or access rights. Do not store Jev scores or Twin guesses as Roberto's preferences,
and never learn an authorization from a model-generated outcome.

If gbrain is unavailable, try the known local source note when accessible. Otherwise disclose
that recall was unavailable and use current instructions plus a reversible in-scope default.
Do not block routine authorized work solely because recall failed; hold only decisions that
genuinely need missing critical facts or authority. Continue other authorized work.

Private memory and sensitive-derived summaries remain local and outside Git. Never pass them
to Jev or treat a clean Gitleaks scan as declassification. Capture durable corrections/decisions
through the existing taxonomy and privacy rules below, keeping observed outcomes separate from
recommendations; do not create another per-agent memory store.

## Privacy (hard gate, like code)

Never write to memory content from `~/.roberdan-os/private/` or personal/medical data
of Fight the Stroke / third-party names. Check the pattern **before** the write, not at
discretion.
