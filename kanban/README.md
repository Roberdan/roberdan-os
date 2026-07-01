# kanban — durable, auditable, token-bounded, GATED goal tracking

Card-files (one file per card) in three columns, driven by the fast **`kb`** CLI:
- `todo/` — queued · `doing/` — in progress · `done/` — completed/verified (append-only, read on demand)

## Fast commands (`kb`)
```
kb                             # view the board (fast)
kb show <id>                   # show a card
kb add "<title>" [dod] [acc]   # new card in todo/
kb edit <id>                   # fill Definition of Done + Acceptance
kb start <id> --by roberto     # GATE: todo->doing (needs Roberto's approval)
kb finish <id> --thor "<ev>"   # GATE: doing->done (@thor validates with evidence)
```

## The two gates (not "a cazzo")
- **`todo → doing`** is a **human gate** — only Roberto approves what becomes active.
- **`doing → done`** needs **`@thor`** (the done-gate agent) to validate against the card's
  **acceptance criteria**, with **evidence** (commit/test/output). No rubber-stamps.

## Every card has (mandatory)
`dod:` — a clear **Definition of Done** · `acceptance:` — **acceptance criteria** (how @thor verifies).
A card cannot `start` until both are filled.

Only `todo`+`doing` are loaded at session start (auto-injected by `hooks/context-inject.sh`); `done`
is the audit archive → the board never bloats the context.
