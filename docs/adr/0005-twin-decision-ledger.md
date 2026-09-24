# ADR-0005 - Twin decision ledger and shadow mode

**Status:** Proposed, 2026-09-24 (card 260924-085106, plan 2026-09-24 § Fase 4, items 4.1-4.6 and 4.8).
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
`twin_prediction` (choice, confidence, category, why, model, at), `jev_observation` (optional),
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

**Precedents (4.5).** Before asking the host, `predict` retrieves up to 3 past decisions
attributed to Roberto that share meaningful words with the card (same category ranks higher)
and puts them, with his real choice and reason, in the prompt. Local lexical match only: no
gbrain, no network. `twin-shadow.sh similar --card C` shows what the prompt would carry.

**Values (4.4).** `twin-shadow.sh values` writes `values-proposal.md` next to the ledger (600):
values ordered by how many attributed decisions cite the same reason, conflict rules from the
categories where Roberto repeatedly chose differently from the twin, with counts. Below 10
attributed decisions it says "dati insufficienti" and writes nothing. It never edits
`identity/`: making a proposal canon is material in his name (gate #6), so he does it.

**Jev.** A card reaches Jev only if it declares `jev: public` or `jev: synthetic`; otherwise the
ledger records `jev_observation: non inviato: privato`. Declared cards get a `bin/jev.py`
dry-run (payload hash, no network, no spend). Going live stays the operator's payload approval
under ADR-0003. Jev's twin profile returns separate signals, not a choice, so it is never scored
as a prediction of Roberto: the plan's "Jev vs Roberto" percentage is dropped on purpose.

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
  private, and ADR-0003 limits Jev to declared public or synthetic input (see Jev above).
- Nothing is indexed in gbrain. Moving ledger content anywhere else is Roberto's decision.

## Autonomy, later

This ADR grants the twin no authority. Loosening any gate on the strength of these numbers is
a gate-#7 decision that only Roberto can open, only with data: a category with enough attributed,
unanchored decisions, an agreement figure he considers sufficient, and the list of cases where
the twin was wrong. No threshold is set here.

## Evidence

`test/test-twin-shadow.sh` (registered in `test/validate.sh`): hidden prediction recorded,
outcome through the real `kb start`, kb unaffected by a failing, missing or refused helper,
update-only outcome, reconcile, agreement math, "dati insufficienti", Jev never scored as a prediction,
batch approves nothing and marks what it showed, digest shows the percentage, ledger refused
inside git, and no canary anywhere in the repo. `test/test-twin-learning.sh`: similar attributed
precedents reach the prompt and unrelated or unattributed ones do not, no network import in the
twin code, private cards never reach Jev, declared ones get a dry-run only, `values` writes a
proposal outside the repo with counts and never touches `identity/`, and the next step is
printed when data is insufficient.
