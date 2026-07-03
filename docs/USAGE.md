# USAGE — day-to-day operator guide

Concise reference for running roberdan-os day to day. For the full canon, start at
[`AGENTS.md`](../AGENTS.md); this doc is the "how do I actually do X" cheat sheet.

## Kanban (`kb`)

Goal tracking lives in [`kanban/`](../kanban/) as files, not a chat thread — file state is
durable, the conversation is not.

```
kb                            # view the board (todo / doing / done, last 10)
kb todo | kb doing | kb done  # view one column
kb show <id>                        # print a card
kb add "<title>" --repo <r> [dod] [acc]  # new card in todo/ (repo required; fill dod/acceptance, or `kb edit <id>` after)
kb start <id> --by roberto          # GATE: todo -> doing, needs Roberto's approval
kb finish <id> --thor "<ev>"        # GATE: doing -> done, needs @thor + evidence (never a rubber-stamp)
kb block <id> "<reason>"            # mark a card blocked, move it back to todo/
```

Every card needs a `repo:` (which repo/scope it's about — a `~/GitHub` dir-name, or `personal`
for non-code work), a `dod:` (Definition of Done) and `acceptance:` (how @thor verifies) before
it can leave `todo/` — `kb start` refuses cards with `repo:` missing or a `FILL:` placeholder
still in any of the three fields. The board and `kb list`/`kb history` show `(repo)` next to
every card so scope is visible at a glance, not just buried in the card body.

**Detail on demand** (never loaded at session start, only when asked):

```
kb history          # ALL work: every done/ card + every archived goal, newest first
kb archive [date]   # list archive files (goal counts) | cat one archive
kb plans            # list docs/plan-*.md (+ docs/archive/) with H1 + line count
kb plan <match>     # print the plan whose filename contains <match>
kb sched            # launchd jobs + schedules + factory queue/failed + evolve proposals
```

## Agent factory (unattended overnight work)

`factory/` runs queued tasks through headless `claude -p` agents, one after another, tracked on
the filesystem — see [`factory/factory-protocol.md`](../factory/factory-protocol.md) for the full
model.

```
factory/enqueue.sh "<task text or file>" [name]   # add a task to the queue
factory/run.sh                                     # process the queue now (also runs nightly via launchd)
```

Runs on the Max subscription (`run.sh` unsets `ANTHROPIC_API_KEY`/`ANTHROPIC_AUTH_TOKEN`) — no
per-token API billing. Task files can set `card: <kanban-id>` so the result gets written back onto
that card automatically.

- **Model policy**: `sonnet` by default, always explicit (never inherits the account's
  interactive default). Set `model: opus` in a task's frontmatter to scale up when needed;
  `RDA_FACTORY_MODEL` overrides the default globally. Hardcoded allowlist `sonnet|opus` only —
  any other value (fable, typo) clamps to sonnet with a `WARN`. The headless `@thor` verify pass
  is always `sonnet`, regardless of the task's model.

- **A task only reaches `~/.roberdan-os/factory/done/` on exit 0.** On failure it's retried once;
  a second failure moves it to `failed/` with `escalate: true` — never silently marked done.
- **Exit 0 is not kanban-done.** It only proves the process didn't crash, not that the DoD was
  met. `@thor` still has to validate before `kb finish`.
- **Check `failed/` in the morning.** An empty queue does not mean everything succeeded — check
  `~/.roberdan-os/factory/{done,failed}/` and, if any task failed, `handoff/latest.md` (a run with
  failures appends a summary there automatically).

## Meta-loop (self-improvement)

Runs on `launchd`, unattended, self-**proposing** never self-**applying** on behavior:

- `rda-learn` (daily) — captures signals to `~/.roberdan-os/learnings/inbox/`, distills into
  classified candidates in quarantine. Nothing reaches the vault without human/gated promotion.
- `rda-evolve` (weekly) — watches Claude/Copilot/Codex changelogs, drafts proposals into
  `proposals/`. Draft-only, never auto-applied.
- `rda-factory` (nightly, 01:00) — see above.

See [`learn/learn-protocol.md`](../learn/learn-protocol.md), [`evolve/evolve-protocol.md`](../evolve/evolve-protocol.md).

## Recall (the vault, via gbrain)

Durable memory lives in the Obsidian vault, not in any single tool's chat history.

```
gbrain search "<terms>" --source vault    # keyword search (prefer this first — semantic drops scattered topics)
gbrain query "<question>" --source vault  # semantic search
```

Embedding is local-first (`ollama:bge-m3`) for privacy + zero cost. `bin/check-embedder.sh` verifies
that patch is still intact after a `gbrain` upgrade — run it if recall quality seems to drop.

## The human gates (never automated)

These always go through Roberto directly — an agent proposes, never executes:

1. Merge to `main` impacting branch-protection/security/release
2. Force-push to `main`
3. Real spend / external emails / public publications
4. Deletion of non-regenerable data (vault notes, gbrain sources, repo history)
5. Strategic/product decisions with non-obvious tradeoffs
6. Material published in Roberto's / Fight the Stroke's name
7. Architectural changes touching >4 files with cross-cutting invariants

In practice, the two you'll hit constantly are `kb start <id> --by roberto` (todo→doing) and
`kb finish <id> --thor "<evidence>"` (doing→done) — everything else in the loop runs autonomously
inside those two gates.

## Other agentic tools

- **Copilot CLI** — skills installed via `bin/sync.sh --install` (symlinked into
  `~/.copilot/skills/`); gbrain is already registered in its MCP config; `AGENTS.md`
  is read natively per-repo.
- **codex / opencode** — global pointers installed by `bin/sync.sh --install` when
  the tool is present on the machine (skipped cleanly otherwise).
- **Warp** — reads `AGENTS.md` natively (precedence: subdirectory > repo root >
  Global Rules; `WARP.md` is legacy). Just open a repo that has `AGENTS.md`; add
  Global Rules by hand via the Warp UI only if you want extra machine-wide context.
- **Hermes (Nous Research hermes-agent)** — reads `AGENTS.md` natively as workspace
  instructions; no wrapper, only documented setup commands. See the generated
  `platforms/hermes/README.md` (run `bin/sync.sh --emit-only` first — `platforms/` is not in git).

## Verify the system itself

```
bash test/validate.sh          # full CI gate: frontmatter, links, drift, shellcheck, leak-check, factory+kb
bash test/test-factory-kb.sh   # factory + kb gate assertions only
bash bin/check-embedder.sh     # gbrain bge-m3 patch durability
```

`bin/install-git-hooks.sh` installs `hooks/pre-commit` (blocks any commit containing a
denylisted confidential term) — run once per clone/worktree; `.git/hooks/` is not versioned by git.
