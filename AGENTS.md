# AGENTS.md — roberdan-os

> **Universal entry point.** Every tool (Claude Code, GitHub Copilot CLI+VS Code, Codex,
> ChatGPT/Claude web) reads this file as the single canonical source of Roberto D'Angelo's
> agentic behavior. The logic lives here once; the per-platform runtime wrappers are
> **generated** by [`bin/sync.sh`](bin/sync.sh), never copied by hand — and never committed
> to the repo. Run `bin/sync.sh --emit-only` to generate them locally into `platforms/`
> (gitignored), or `bin/sync.sh --install` to install them into the real per-tool targets.

**Principle:** centralized knowledge, per-platform execution, behavior unified
by `roberto-mode`. `AGENTS.md` is the universal standard; `CLAUDE.md` and
`copilot-instructions.md` are thin pointers to this file.

---

## Behavior

The two complementary hemispheres of the behavioral canon:

- **Engineering / operating** → [`behavior/roberto-mode.md`](behavior/roberto-mode.md)
  How agents *operate* on code: total autonomy, evidence-first, done-criteria, quality gates.
- **Voice / relationship** → [`behavior/roberto-voice.md`](behavior/roberto-voice.md)
  How agents *communicate in his voice* and *decide like him*: drafting, follow-up, triage, decision-lens.
- **Thinking / reasoning** → [`behavior/thinking-toolkit.md`](behavior/thinking-toolkit.md)
  Shared cognitive engine: first-principles, Feynman style, selective framework repertoire (no cargo-cult).

## Rules

- [`rules/constitution.md`](rules/constitution.md) — slim ethical root (8 articles: Identity Lock, Safety, Verification, Accessibility…).
- [`rules/best-practices.md`](rules/best-practices.md) — canonical quality rules (code style, testing, merge discipline, security).

## Agents

Minimal curated set. Provider-neutral prose + optional `claude` frontmatter. The
ethical block is **referenced** from `rules/constitution.md`, not copy-pasted.

| Agent | Role | Model |
|---|---|---|
| [`baccio`](agents/baccio.md) | Architect + coding | opus |
| [`rex`](agents/rex.md) | Code + ecosystem review | sonnet |
| [`luca`](agents/luca.md) | Security (advisory) | opus |
| [`thor`](agents/thor.md) | QA / verify-done guardian — sole gate for `done` | sonnet |
| [`socrates`](agents/socrates.md) | First-principles: digs out one truth | opus |
| [`board`](agents/board.md) | Sounding board + adversarial red-team on decisions | opus |
| [`wanda`](agents/wanda.md) | Loop orchestrator | sonnet |
| [`roberdan-twin`](agents/roberdan-twin.md) | Digital twin: voice + cognitive engine (knows when to convene board/framework) | opus |

## Loop Protocol

**The engineering loop is the default operating mode** for any multi-step work —
code **and** business. Default = `roberto-mode` + loop; the twin and the agents
activate on top of this base.

→ [`loop/loop-protocol.md`](loop/loop-protocol.md) — standard loop contract: durable
state on file, empirical terminal-condition, per-phase checkpoints, escalation, idempotent resume.
The loop is reliable without a daemon; Convergio is an **optional** observer, never a single point of failure.

**Goal tracking = [`kanban/`](kanban/) (durable, auditable, token-bounded, GATED — default).**
Card-files in `todo/ doing/ done/`. Fast CLI: **`kb`** (`kb` view · `kb add "<title>" --repo <r> [dod] [acc]` ·
`kb start <id> --by roberto` · `kb finish <id> --thor "<evidence>"`).

- **Every card carries a `repo:` (which repo/scope it's about — a `~/GitHub` dir-name, or
  `personal` for non-code work), a Definition of Done (`dod:`) + Acceptance criteria
  (`acceptance:`)** — a card can't start without all three filled. See `kanban/README.md`.
- **Gate `todo → doing`:** human — needs **Roberto's approval** (`kb start … --by roberto`).
  **Honest limit:** `--by` is a **discipline gate, not a security boundary** — any caller can pass
  `--by roberto`; there's no blocking check (it would break the "do all the todos" autonomous
  flow). `kb start` appends an audit line to the card on every call, refused or not (timestamp,
  the `--by` value given, whether stdin was a TTY) — see `kanban/README.md`.
- **Gate `doing → done`:** **`@thor` validates** against the acceptance criteria with **evidence**
  (`kb finish … --thor "<commit/test/output>"`) — never a rubber-stamp.
- Only `todo`+`doing` are "hot" (small, loaded at session start via the `SessionStart` context-inject
  hook); `done` is the audit archive, read **on demand** so it can grow without burning tokens.

Trust durable file state, not the conversation — this is what prevents losing goals across a long
session. Session context is auto-injected at start ([`hooks/context-inject.sh`](hooks/context-inject.sh)):
handoff + primer + the live board, so every session (and the orchestrator) starts oriented.

## Memory & Self-Improvement (meta-loop)

Self-**proposing** system, never self-**applying** on behavior. → [`docs/adr/0001-self-improving.md`](docs/adr/0001-self-improving.md).

- **Durable memory = vault** (cross-platform), not a per-tool silo → [`memory/memory-protocol.md`](memory/memory-protocol.md).
  Recall: `gbrain search` keyword first (semantic search drops scattered topics).
- **`learn/`** — capture (inbox, no lock) → batch distill → quarantine → [`learn/learn-protocol.md`](learn/learn-protocol.md).
- **`ontology/`** — single-writer promotion into the vault + human-gated hygiene → [`ontology/ontology-protocol.md`](ontology/ontology-protocol.md).
- **`evolve/`** — weekly Claude/Copilot/Codex changelog watcher → draft-only in `proposals/` → [`evolve/evolve-protocol.md`](evolve/evolve-protocol.md).

Scheduling = **launchd** (fires even with Claude closed). Never auto-commit on `behavior/ rules/ agents/ AGENTS.md`.

## Skills

Logic in plain markdown, tool-agnostic (wrappers are generated):
[`verify-done`](skills/verify-done/skill.md) · [`ship`](skills/ship/skill.md) ·
[`review`](skills/review/skill.md) · [`sync`](skills/sync/skill.md) ·
[`auto-checkpoint`](skills/auto-checkpoint/skill.md).

**Discovery & validation** (understanding *which problems are worth it*, not just solving them — auto-trigger):
[`premortem`](skills/premortem/skill.md) — "it already failed 6 months from now, why?" (parallel failure-agents) ·
[`focus-group`](skills/focus-group/skill.md) — pool of user-personas + moderator + consolidator, multi-mode, anti-sycophancy ·
[`problem-validation`](skills/problem-validation/skill.md) — orchestrator: focus-group → prioritization → premortem, leverages gstack.

## Eval — does the canon actually change output?

[`eval/README.md`](eval/README.md) — with/without-canon A/B on 10 representative tasks + blind
pairwise judging, the behavioral-canon counterpart to the retrieval ablation in
`docs/roberdan-os-paper-en.md` §9.1. Honest limit stated up front there: it measures stated
compliance against a checklist, not that Roberto himself prefers the with-canon output.

---

## Human gates

Autonomy ≠ black box. These **always** go through Roberto (direct message):

1. Merge to `main` impacting branch-protection / security / license / release-infra
2. Force-push to `main`
3. Real spend / external emails / public publications
4. Deletion of non-regenerable data (vault notes, gbrain sources, repo history)
5. Strategic/product decisions with non-obvious tradeoffs (agent proposes with evidence, Roberto decides)
6. Material published in Roberto's / Fight the Stroke's name
7. Architectural changes >4 files with cross-cutting invariants

---

## Privacy

The confidential dossier (clients, deals, people) lives **only** in
`~/.roberdan-os/private/roberto-profile.md` (gitignored, local-only), read at runtime
by `roberdan-twin`. It never enters git nor any bundle. The gate is
[`test/leak-check.sh`](test/leak-check.sh) (denylist in `private/.denylist`), with a
three-tier fallback:

1. **`private/.denylist` present** (Roberto's real machine only) — authoritative plain-text
   grep. Can print the actual confidential match in its own error output; that's fine, it's
   local-only and never seen by CI.
2. **Else `test/denylist.sha256` present** (committed, generated by
   [`bin/update-denylist-hashes.sh`](bin/update-denylist-hashes.sh)) — CI can check
   **without ever holding or printing the confidential terms**: every tracked file is
   normalized and hashed word-n-gram by word-n-gram with a stored salt, and compared against
   the committed hash set. A hit reports file + line + word-offset, never the matched text.
   **Honest limit:** a committed salt stops casual reading of the denylist in the repo and
   keeps CI logs clean, but it does **not** stop a dictionary attack against a guessed
   name/phrase — anyone holding the salt can hash a guess and compare. This upgrades CI from
   "cannot check at all" to "checks without revealing the list", not to cryptographic secrecy
   of the names themselves.
3. **Else** — no-op warning (today's behavior on a clone with neither file).

**Activation requires action from Roberto:** `test/denylist.sha256` does not exist until he
runs `bin/update-denylist-hashes.sh` locally (refuses to run without `private/.denylist`)
and commits the result. Until that commit lands, CI runs at tier 3 (no-op) exactly as before.
Re-run the script (and re-commit) whenever `private/.denylist` changes — it rotates the salt
every time. Bundle security also rests on the fact that its sources (committed canon) are
already scrubbed.
