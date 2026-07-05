# Federated-kanban migration record — 2026-07-05

Phase 4 of [`plan-2026-07-05-federated-kanban-multi-cli.md`](plan-2026-07-05-federated-kanban-multi-cli.md)
(§7.4). Records what moved to the federated model and — explicitly — the gate **not** crossed.
Privacy was activated **first** (phase 2 `kb init`), before this migration, per the mandate.

## roberdan-os — migrated in place (it is now a federated board)

roberdan-os keeps its own `kanban/` and behaves exactly as before; the change is that it is now a
**registered** federated board, discovered by the global `kb`:

- `kb init` ran against roberdan-os (phase 2): it registered the repo in
  `~/.roberdan-os/kanban-registry` (local-only), confirmed the card columns are gitignored, and
  left the existing leak-check pre-commit hook in place.
- roberdan-os's own `handoff/latest.md` is **tracked** canon-ish live state. `kb init` **flagged**
  it and did **not** change that tracking (design §5 note). Whether to federate it as gitignored
  per-repo state is a separate, low-risk human decision, deliberately left open.
- roberdan-os card content stays gitignored and uncommitted (unchanged). No card was moved.

## MirrorBuddy — GATE NOT CROSSED (documented, deliberate)

Two MirrorBuddy cards currently live in **roberdan-os**'s board, gitignored, with `repo: MirrorBuddy`:

| id | title (abridged) |
|---|---|
| `260703-224312` | MirrorBuddy AI-Act P2 — gaps (watermark, Trial age-verify, data-governance, …) |
| `260703-224313` | MirrorBuddy AI-Act — checklist: legal sign-off + open nodes |

These **remain exactly where they are** — not moved, not physically federated into
`~/GitHub/MirrorBuddy`. The reasons are hard gates:

- **`kb init` on MirrorBuddy is a human gate, not crossed.** MirrorBuddy is a shared
  (Fight the Stroke) repo with a **standalone** `AGENTS.md` and does **not** gitignore `kanban/`
  (verified in the design, 2026-07-05). Running `kb init` there would append to its `.gitignore`
  and install a hook — i.e. modify a shared external repo. That is a human decision (AGENTS.md
  §gate-umani: "cambi … su repo condivisi"). This session did **not** touch MirrorBuddy.
- **Physical migration of the cards to `~/GitHub/MirrorBuddy/kanban/` is therefore also gated.**
  Moving them requires `kb init`'ing MirrorBuddy first (to open the privacy window there), which is
  the un-crossed gate above. Until a human runs `kb init` on MirrorBuddy, the cards stay in
  roberdan-os, gitignored, tagged `repo: MirrorBuddy` — visible via `kb all` with their true repo.

## Runner eligibility

Federation (a board being registered) is **orthogonal** to runner-eligibility. Neither roberdan-os
nor MirrorBuddy is in `~/.roberdan-os/runner-allowlist` — and MirrorBuddy is excluded **by policy**.
`kb init` never grants runner-eligibility (design §2e). The external dispatcher is dormant regardless
(phase 6, preflight #5 hard-wired).

## What remains for a human

- Decide whether to `kb init` MirrorBuddy (opens its privacy window) and then physically move the
  two cards into `~/GitHub/MirrorBuddy/kanban/`. Both are gated on Roberto.
- Decide whether roberdan-os's `handoff/latest.md` should become gitignored per-repo state.
