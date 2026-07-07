# ARCHITECTURE — the layer map

roberdan-os is an **Agentic Digital Twin**: a persistent, versioned representation of how one
person works, writes, decides and delegates, consumed identically by every AI tool they use.
This file maps that idea onto the actual directories — nothing here is aspirational; every row
points at code or prose that exists and is exercised by `test/validate.sh`.

The one structural rule (since v2.0.0): **`identity/` is the only forker-editable surface.**
Everything else is engine — upstream-owned, merge-clean for forks by construction
(`test/test-fork-merge.sh` proves it, not just asserts it).

## Layers

| Layer | What it holds | Where it lives |
|---|---|---|
| **Identity** | Who the operator is: voice, profile, twin persona, machine-readable config | [`identity/`](identity/README.md) (public part) + `~/.roberdan-os/private/` (confidential dossier, never in git) |
| **Values** | The ethical root (8 articles) + canonical quality rules | [`rules/constitution.md`](rules/constitution.md) · [`rules/best-practices.md`](rules/best-practices.md) |
| **Behavior** | How agents operate (autonomy, evidence-first, done-criteria) and reason (first-principles, Feynman) | [`behavior/roberto-mode.md`](behavior/roberto-mode.md) · [`behavior/thinking-toolkit.md`](behavior/thinking-toolkit.md) |
| **Memory** | Durable cross-platform recall: Obsidian vault + gbrain (local embeddings), never a per-tool silo | [`memory/memory-protocol.md`](memory/memory-protocol.md) · [`ontology/`](ontology/ontology-protocol.md) (gated promotion into the vault) |
| **Goals** | Durable, auditable, human-gated task ledger (`kb`); card content local-only | [`kanban/`](kanban/README.md) |
| **Agents** | The curated roster: architect, reviewer, security, done-gate, first-principles, board, orchestrator, twin | [`agents/`](agents/) — role prose is engine; the twin's persona is identity |
| **Execution** | The loop contract, unattended overnight factory, per-tool wrapper generation | [`loop/loop-protocol.md`](loop/loop-protocol.md) · [`factory/`](factory/factory-protocol.md) · [`bin/sync.sh`](bin/sync.sh) · [`skills/`](skills/) · [`hooks/`](hooks/) |
| **Reflection** | Self-improvement that proposes, never self-applies: capture→distill→quarantine, weekly upstream watch | [`learn/`](learn/learn-protocol.md) · [`evolve/`](evolve/evolve-protocol.md) |
| **Governance** | The seven human gates, 3-tier privacy leak-check, guard hooks, audit trail on gate crossings | [`AGENTS.md § Human gates`](AGENTS.md) · [`test/leak-check.sh`](test/leak-check.sh) · [`hooks/`](hooks/) |
| **Metrics** | Does the canon actually change agent output? A/B with-/without-canon + blind pairwise judging | [`eval/`](eval/README.md) |

## How a request flows

```
Operator (or a schedule)
  │
  ├─ Identity + Values + Behavior  →  every agent session starts from the same canon (AGENTS.md)
  │
  ├─ Goals (kb)                    →  work is a gated card, not a chat thread
  │
  ├─ Agents + Execution            →  the loop runs; @twin drafts, @baccio designs, @rex reviews …
  │       │
  │       └─ Governance            →  human gates block merges/spend/publication/deletion
  │
  ├─ @thor                         →  "done" only with evidence against the card's acceptance
  │
  └─ Memory + Reflection           →  outcomes land in the vault / learn-inbox, proposals come back
```

## Design invariants

1. **One canon, many runtimes.** `AGENTS.md` is the single source; per-tool wrappers are
   generated (`bin/sync.sh`), never hand-copied, never committed. Drift is a CI failure.
   Exception by design: Claude Code reads the canon **natively** in-repo via the root
   `CLAUDE.md → AGENTS.md` symlink (v2.7.0) — no wrapper on that path. Agent frontmatter
   carries `model:` **and `effort:`** (2026) so cost/quality tiering travels with the canon.
2. **Engine/identity split.** Forkers edit `identity/` only; engine files never embed identity.
   See [`docs/plan-2026-07-05-engine-identity-split.md`](docs/plan-2026-07-05-engine-identity-split.md).
3. **Human gates are not advisory.** The seven gates in `AGENTS.md` are enforced by hooks and
   discipline, and every crossing is attributable (audit lines, `--by`, `--thor` evidence).
4. **Evidence over claims.** Nothing is "done" because an agent says so — `@thor` verifies
   against acceptance criteria; the eval harness holds the canon itself to the same standard.
5. **Local-first privacy.** The dossier and live task content never enter git; embeddings run
   on-device; the leak-check gate runs on every commit (3-tier, works even in CI without the
   plaintext denylist).
6. **Self-proposing, never self-applying.** The meta-loop drafts changes to its own behavior;
   a human merges them. `behavior/ rules/ agents/ AGENTS.md` are never auto-committed.
