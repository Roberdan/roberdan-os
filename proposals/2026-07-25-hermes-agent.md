# Proposal — 2026-07-25 — hermes-agent

## Source citation (URL + version + date)
- https://github.com/NousResearch/hermes-agent/releases (checked 2026-07-28)
- https://api.github.com/repos/NousResearch/hermes-agent/releases?per_page=20 (checked 2026-07-28)
- v2026.7.20 / Hermes Agent v0.19.0 “The Quicksilver Release” (published 2026-07-20T18:35:55Z; release date July 20, 2026)

## Novelties + impact
1. v0.19.0 made background delegation observable and durable: `delegate_task` returns live transcript files, and background completions survive process restarts through an ownership-checked ledger.
2. v0.19.0 added smart approvals, user-defined deny rules, `/deny <reason>`, password-manager secret sources, session export, profile routing, and broad UI/provider improvements. Most are good reference material, not direct roberdan-os changes.
3. roberdan-os already has `factory/run.sh` logs and card annotations, but the dormant external-runner dispatcher has no explicit “live transcript + durable completion ledger” acceptance contract.

## Suggested patch (draft only)
- Before re-enabling any factory external-CLI dispatch, add a factory contract/test requiring each runner adapter to expose a live transcript path and a durable final-result ledger entry that can be recovered after restart; keep the native Claude factory’s existing log path as the minimum compliant implementation. Citation: https://github.com/NousResearch/hermes-agent/releases/tag/v2026.7.20 — v2026.7.20 / Hermes Agent v0.19.0, published 2026-07-20T18:35:55Z.

