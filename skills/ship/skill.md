---
name: ship
description: Platform-agnostic ship workflow — local CI gate, commit per phase, push, PR with Summary + Test plan, watch CI, merge-commit only. Honors human gates on main.
providers: [claude, copilot, codex]
---

# ship — porta il lavoro in produzione (git + gh)

Workflow di ship indipendente dalla piattaforma. Niente bypass, niente scorciatoie.

## Pre-push: pipeline CI locale (tutto verde prima di pushare)
1. **Format** — `cargo fmt --check` / `prettier --check` / `ruff format --check`
2. **Lint** — `cargo clippy -- -D warnings` / `eslint` / `ruff check`
3. **Type-check** — `cargo check` / `npx tsc --noEmit`
4. **Test** — `cargo test` / `npm test` / `pytest` (output mostrato)
5. **Build** — `cargo build` / `npm run build`

Se un passo fallisce: fixa e **ri-esegui tutti** i check. Mai pushare con failure noti.

## Sequenza
1. Branch dedicato (mai lavorare direttamente su `main`).
2. Commit **per fase**, messaggi conventional + evidence-first (SHA/PR/CI).
3. `git push` del branch.
4. Apri PR: **Summary + Test plan** (template a 5 sezioni se il repo lo usa).
5. Watch CI: `gh pr checks <n>` — tutti SUCCESS prima di procedere.
6. Merge: **merge-commit only** (mai squash, mai rebase — preserva la history per gli agenti paralleli).
7. Post-merge: cancella il branch, fast-forward `main` locale, riporta lo SHA del merge commit.

## Gate umani (STOP — chiedi prima)
- Merge su `main` con impatto su branch-protection / security / license / release-infra (#1)
- Force-push su `main` (#2) — **sempre vietato senza conferma esplicita**
- CI non completamente verde → non mergiare nulla di pending/failing

## Review comments
Ogni commento (umano o bot) va analizzato, capito e risolto bene — mai silent-resolve,
mai "fix" che tocca solo la riga citata ignorando la sostanza. Rispondi sul thread con
cosa hai fatto e perché, poi risolvi. Vedi [`skills/review`](../review/skill.md).
