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

## The two gates (no rubber-stamping)
- **`todo → doing`** is a **human gate** — only Roberto approves what becomes active.
- **`doing → done`** needs **`@thor`** (the done-gate agent) to validate against the card's
  **acceptance criteria**, with **evidence** (commit/test/output). No rubber-stamps.

## Every card has (mandatory)
`dod:` — a clear **Definition of Done** · `acceptance:` — **acceptance criteria** (how @thor verifies).
A card cannot `start` until both are filled.

## Honest limit: `--by` is a DISCIPLINE gate, not a security boundary

`kb start <id> --by roberto` does **not** verify the caller actually is Roberto — any process
that can run `kb.sh` can pass `--by roberto`. There is deliberately **no blocking check** here:
one would break the documented "do all the todos" autonomous flow, where an agent is expected
to work through queued cards without stopping for interactive confirmation on every single one.

What `kb start` does instead: it appends an audit line to the card on **every call**, including
refused ones — `kb_start_audit: "at=<UTC timestamp> by=<value given> interactive=<yes/no>"` (see
`kanban/kb.sh`). This doesn't stop a bypass, but it makes one **visible** in the card's own
history — a card that was "approved by roberto" from a non-interactive process, or with an
`--by` value that doesn't match who's actually driving the session, is a signal to look closer,
not proof of anything on its own. Treat `--by`/`approved_by` as an honor-system claim the same
way you'd treat a commit's author field — attributable, reviewable, not cryptographically bound.

Only `todo`+`doing` are loaded at session start (auto-injected by `hooks/context-inject.sh`); `done`
is the audit archive → the board never bloats the context.
