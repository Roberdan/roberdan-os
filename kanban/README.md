# kanban — durable, auditable, token-bounded goal tracking

Three files (a real kanban board), replacing the old "ledger" naming:
- [`todo.md`](todo.md) — queued goals
- [`doing.md`](doing.md) — in progress now
- [`done.md`](done.md) — completed/verified (append-only, read on demand → can grow without burning tokens)

**Rule:** read `todo`+`doing` at session start; move cards left→right per phase; a card reaches `done` only when `verified` by `@thor`. Only `todo`+`doing` are "hot" (small, loaded); `done` is the audit archive.
