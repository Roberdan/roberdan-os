# factory — autonomous agent factory (Convergio's job, without Convergio)

Runs queued tasks through **headless Claude Code agents**, one after another, unattended and
resumable — the "agent factory" that keeps going while you sleep. Built on the current architecture
only: `claude -p` (headless) + a durable file queue + `launchd` + the loop-protocol. No daemon, no
Convergio, daemon-optional.

## How it works

```
~/.roberdan-os/factory/
  queue/   *.md   ← drop a task here (one file = one autonomous task)
  done/    *.md   ← finished tasks (moved here with result + log pointer)
  logs/    *.log  ← full agent transcript per task
```

- `factory/enqueue.sh "<task text or file>" [name]` — add a task to the queue.
- `factory/run.sh` — process the queue: for each task, dispatch a headless agent
  (`claude -p "<task>" --dangerously-skip-permissions --add-dir <dir>`), capture the log, move the
  task to `done/` with its exit code. **Resumable:** state lives in the filesystem (queue/ → done/),
  so a killed run just re-processes what's left. Loops until the queue is empty or `MAX` is hit.
- launchd `com.roberdan.rda-factory` runs `run.sh` nightly (or on demand).

## Task file format

```
---
dir: ~/GitHub/roberdan-os      # working dir the agent gets (--add-dir); default ~/GitHub
timeout: 1800                  # seconds (optional)
---
<the task / goal, in natural language — the agent reads AGENTS.md and works in roberto-mode>
```

## Guardrails (autonomous ≠ reckless)

- Each task is **scoped** to a dir (`--add-dir`) and has a **timeout**.
- The dispatched agent still reads `AGENTS.md` → **human gates hold** (it won't merge to main, push,
  spend, or delete non-regenerable data autonomously; it leaves those as proposals).
- Everything is **logged** (`logs/`); nothing is silent.
- Prefer tasks that are **additive + verifiable** (write code + tests, draft a doc, research).
  Do NOT queue irreversible/outward-facing tasks for unattended runs.
- Parallel tasks that mutate the same repo should use `git worktree` isolation (flag `RDA_FACTORY_PARALLEL`).

## Config (env)

`RDA_FACTORY` (default `~/.roberdan-os/factory`) · `RDA_FACTORY_WORKDIR` (default `~/GitHub`) ·
`RDA_FACTORY_MAX` (tasks/run, default 8) · `RDA_FACTORY_TIMEOUT` (default 1800s).
