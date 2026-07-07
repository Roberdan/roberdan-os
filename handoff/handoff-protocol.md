# handoff — continue any conversation with a fresh, clean agent (no context loss)

The problem: a session grows huge and slow; you want to start a **fresh agent** without re-explaining
everything. The fix: durable context lives in **three durable layers** (not the chat), so any new
session — local or cloud, Claude or Copilot — resumes from ground truth:

1. **Persistent memory** — `MEMORY.md` (loaded every session) + the vault (gbrain recall). The
   *durable facts* (who you are, decisions, tool-quirks). This is what compounds over time.
2. **Kanban** — [`kanban/`](../kanban/) `todo`/`doing`/`done`. The *durable goals* and their state.
3. **Handoff brief** — [`handoff/latest.md`](latest.md). The *durable narrative* of the current
   thread: what we're doing, why, decisions made, open threads, next step. This is the piece the
   other two don't capture — the "story so far."

## To hand off (end of a long session)

Write/refresh `handoff/latest.md` with: the goal, key decisions + rationale, current state (what's
built/running), open threads, and the single next action. Commit + push (private remote) so it's
reachable from anywhere, including a cloud/web session or the iPhone Claude app.

## To resume (fresh agent)

A new agent's first move: read `handoff/latest.md` + the board (`kb`, card files in
`kanban/todo/ doing/`) + **`kb resume`** (the pending pause checkpoint `handoff/resume.md`,
kept fresh every turn by the Stop-hook auto-checkpoint — see AGENTS.md § Pause & Resume) +
`MEMORY.md`, and `gbrain search` for anything referenced. That reconstructs the working context
in seconds, from durable state — no dependency on the previous (huge) conversation. This is the
compounding loop: each session ends by leaving the next one smarter.
