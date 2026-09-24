# ADR-0005 - Twin decision ledger and shadow mode

**Status:** Proposed, 2026-09-24 (card 260924-085106, plan 2026-09-24 § Fase 4, items 4.1-4.3 and 4.6).
**Decision owner:** Roberto.
**Scope:** a local-only decision ledger, the twin's hidden predictions on `kb pending`, a
weekly agreement figure, and a read-only sorted view of the pending list.
**Not authorized here:** the twin approving, rejecting or starting anything; any change to a
human gate; sending ledger content to gbrain, Jev or any remote store; automatic spend.

## Context

The twin is meant to "take the decision Roberto would take" (identity/twin-persona.md), but
nothing recorded his decisions or measured how often the twin matched them (plan § 2.E,
findings 17, 18, 20). The approvals waiting in `kb pending` are exactly that missing data,
and they were lost once decided.

## Decision

**Ledger.** One JSONL line per decision in `~/.roberdan-os/private/decisions/ledger.jsonl`
(`RDA_HOME`, dir 700, file 600). Fields: `id`, `date`, `category`
(tecnico|priorita|comunicazione|soldi|persone|altro), `situation`, `options`,
`twin_prediction` (choice, confidence, category, why, model, at), `jev_prediction` (optional),
`roberto_choice`, `reason` (optional), `source` (kb-pending|draft-edit|override), plus
`decided_at`, `decided_by`, `interactive`, `attributed`, `shown_at`.

**Shadow mode.** `bin/twin-shadow.sh predict` asks the local host (`claude -p`, model resolved
through `bin/models.sh`, no tools, no MCP, no settings, a replacement system prompt,
`--max-budget-usd 0.05`, at most 5 cards per run) and stores the prediction without printing it.
No host, a failure or unreadable output records "no prediction"; nothing is invented. The
scheduled digest runs predictions only after Roberto opts in by creating
`<ledger dir>/auto-predict`, because every prediction spends. One measured call cost $0.0026.

**Outcome.** `kb start` calls `twin-shadow.sh outcome` on one line. It is update-only (it
writes only when an open prediction for that board and card exists), local, silent, and
guarded by `|| true`, so kb behaves identically when the helper fails or is missing.
`reconcile`, run by the pending digest, records approvals the hook missed and cards that
vanished.

**Agreement.** `bin/twin-agreement.sh` prints N and % agreement per category and overall, for
the twin and separately for Jev, over the last 7 days (or `--days`, `--all`). Below 5 decisions
it says "dati insufficienti". The pending digest prints that weekly figure (aggregates only).

**Batch view (4.6, rescoped).** `twin-shadow.sh batch` lists pending cards sorted by the
twin's advice with the category's historical agreement. It approves nothing. Each shown item
gets `shown_at`, and a decision taken after seeing the advice is excluded from agreement,
because an anchored choice is not an independent one.

## What counts as Roberto's choice

`--by` is honor-system (kanban/kb.sh). Only a plain `--by roberto` from an interactive terminal
counts. Queue approvals (`roberto (coda autorizzata…)`), non-interactive starts and vanished cards
are recorded but excluded, and the output says how many. Consequences, stated plainly:
- rejections are undercounted (kb has no reject verb; a deleted card has no actor), unless
  Roberto records one with `twin-shadow.sh decide --choice reject`;
- an agent that forges `--by roberto` from a terminal is indistinguishable from Roberto.

## Privacy boundary

- The ledger path is refused (exit 3) whenever it resolves inside any git work tree; the test
  suite proves it and greps the whole repo tree, ignored files included, for a canary.
- Card text goes only to the same local host CLI Roberto already uses, never to Jev: cards are
  private, and ADR-0003 limits Jev to public or synthetic input. `jev_prediction` stays empty
  until such an item exists.
- Nothing is indexed in gbrain. Moving ledger content anywhere else is Roberto's decision.

## Autonomy, later

This ADR grants the twin no authority. Loosening any gate on the strength of these numbers is
a gate-#7 decision that only Roberto can open, only with data: a category with enough attributed,
unanchored decisions, an agreement figure he considers sufficient, and the list of cases where
the twin was wrong. No threshold is set here.

## Evidence

`test/test-twin-shadow.sh` (registered in `test/validate.sh`): hidden prediction recorded,
outcome through the real `kb start`, kb unaffected by a failing, missing or refused helper,
update-only outcome, reconcile, agreement math, "dati insufficienti", Jev measured separately,
batch approves nothing and marks what it showed, digest shows the percentage, ledger refused
inside git, and no canary anywhere in the repo.
