# Handoff — session 2026-07-07 (v2.6.0; best-practices audit in flight)

> Previous handoff (04→06 July: public release → v2.3.0, federated kanban, engine/identity
> split, scars) is superseded — retrievable via `git log -- handoff/latest.md`.

## ⏸️ RESUME POINT (updated 2026-07-07)

**One thing in flight:** `kanban/doing/260707-bestpractices-audit.md` — 2026 best-practices
review + apply + full repo audit (efficiency/effectiveness/autonomy/reliability/cost-tokens),
commissioned by Roberto via /goal. Phase state lives in the card. Everything else is committed
+ pushed, main == origin, latest release **v2.6.0**.

## Shipped since last handoff (all on main, CI green)

- **v2.4.0→2.4.2** — pause/resume + auto-checkpoint (`kb pause/resume`, Stop-hook auto-save);
  fixes: unstaged `kb pause --auto`, YAML quoting that broke generated skill wrappers.
- **v2.5.0** — **No False Done** cardinal rule (best-practices v3.4.0 + verify-done skill).
- **v2.6.0** — `kb resume` surfaces the WHOLE plan (checkpoint + backlog); `kb init` writes
  federation ignores to `.git/info/exclude` (stops polluting shared repos' `.gitignore`).
- **Federation `.gitignore` landed on every repo** (07-06/07): convergio `e91f386e`,
  Fabrica `59d82b6` (local-only repo), MirrorBuddy on main `f091417c`, the-standing-egg,
  ConvergioEdu2030 (reconciled). Cards are local-only everywhere.
- **ConvergioEdu2030 done-gate CLOSED** — @thor DONE on green SHA (15/15 matrix), `4e2b8cc`.

## Open threads / human gates (Roberto's, by design)

1. **gh token rotation** — a live `gho_` hit a subagent transcript on 07-06 (repo clean;
   gitleaks 0). Revoke "GitHub CLI" OAuth + re-login when convenient.
2. **PR Convergio #511** — still OPEN, 1 CI check failing (RUSTSEC on `anyhow` upstream),
   auto-merge NOT set. Waits on the team's dep fix.
3. **MirrorBuddy AI-Act cards** — `260703-224312` (P2 gaps roadmap) + `260703-224313`
   (legal sign-off, owner Francesca). Legal/product decisions, not agent work.
4. **Federated-kanban phase 7** — dispatcher stays DORMANT until the OS-isolation floor
   lands via a reviewed code edit (+ @rex/@luca). Working as designed.
5. **the-standing-egg** — uncommitted content edits NOT made by an agent: README pivot to
   "forward-deployed venture builder" + 4 deleted stale exports. Roberto commits or discards.

## Known debt (agent-workable, next canon touch)

- **eval/** — report stale (2026-07-02), tasks 11-12 unjudged, task 04 still names the
  pre-split canon file (`roberto-voice` → now `identity/voice.md`). Re-run eval on next
  canon change.
- **memory/** — protocol doc only, no executable path since 07-01.
- `handoff/context-primer.md` — verify it matches the v2.6.0 pointer set.

## Next action

Finish the best-practices audit card: research distilled → gap analysis → apply (commit per
phase, human gates respected) → @rex + @thor → report to Roberto with measured before/after.

**For a fresh agent:** read this + `kb` + `MEMORY.md`; `gbrain search` anything referenced.
