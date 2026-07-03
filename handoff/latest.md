# Handoff — session 2026-07-03 (tool-independence pass)

**For a fresh agent:** read this + `kanban/todo/` + `MEMORY.md`, then `gbrain search` what you
need. Full plan + analysis of this pass: `docs/plan-2026-07-03-tool-independence.md`.

## What this session did

Roberto's /goal: the system must work **independently of model or tool** (Claude, Copilot, local
ollama, opencode, hermes, codex, Warp, anything agentic). Fable analyzed the repo + the machine's
real tool inventory against 2026 best practices (web research with primary sources), produced an
8-item plan, sonnet agents executed it (sequential on shared files — the 07-02 git-index race
lesson), rex (opus) reviewed, thor validated, card `T-tool-independence` closed.

**Key finding:** the AGENTS.md bet is industry-validated — Codex, Copilot, Cursor, opencode,
Warp, Jules and hermes all read it natively now; SKILL.md is the portable skill format. The gap
was never architecture, it was **distribution**: wrappers generated but only Claude consumed them.

## What changed (all committed, main)

- **Pointer fabric**: `~/GitHub/AGENTS.md` (new), `~/.codex/AGENTS.md` (0-byte file filled),
  `~/.config/opencode/AGENTS.md` — all installed live by `bin/sync.sh --install`, which now
  detects installed tools (never overwrites, explicit SKIP otherwise).
- **Copilot CLI fully wired**: all 8 roberdan-os skills symlinked into `~/.copilot/skills/`
  (68 total there, zero collisions — gstack uses its prefix in Copilot, so Copilot gets
  `review`/`ship` too, unlike Claude where those names collide). gbrain was already in its MCP.
- **hermes**: `platforms/hermes` stub replaced with verified reality (v0.18.0 auto-injects
  AGENTS.md; exact `hermes cron create --workdir` / `hermes mcp add gbrain --command` syntax
  checked against its own --help). Config untouched — commands documented, self-proposing.
- **Eval harness agent-agnostic**: `RDA_EVAL_AGENT_CMD` (prompt via stdin) + 2 new fixtures
  derived from this system's REAL failures (exit-0-is-not-done; looks-wired-but-never-ran).
- **evolve/** now watches hermes-agent releases + Warp changelog too.
- **validate.sh tool-coverage gate** (ownership-aware: symlinks must resolve into
  roberdan-os/platforms/): on its first run it caught a real half-wired tool (opencode config
  dir present, pointer missing) — fixed by its own printed remediation.
- **rex review**: APPROVE, 0 CRITICAL/HIGH; LOW-1/2/3+INFO-4 remediated (no out-of-repo dir
  creation, installer/gate detection symmetry, dangling-symlink doc, ownership-aware gate);
  INFO-5/6 deliberately annotated only. **thor: PASS** (live evidence, 39 green checks).

## Open threads / gates on Roberto (unchanged from before, still the honest next step)

1. **The 5 todo cards all wait on Roberto's decisions**: FtS-ingest (corpus A/B/C),
   G5-always-on (ADR ready — note hermes' cron/Slack/serve makes it a concrete always-on
   candidate worth weighing in that decision), X-convergio-decision / X-fts-initiative /
   X-msft-triage (scoping). The system's internal backlog remains structurally exhausted —
   by design, not stall.
2. **review/ship skill-name collision in Claude** (gstack owns those names there) — Roberto's
   call, documented in `docs/report-2026-07-02-realistic-testing.md` §5.
3. **Eval real run against a second agent CLI** (e.g. `RDA_EVAL_AGENT_CMD` + Copilot headless):
   harness is ready; running it is cheap but burns real tokens — worth doing when the canon
   changes next, not as ritual.
4. **Canon-preference human sample**: still the missing, non-delegable eval step (Roberto's
   eyes on real transcripts).

## Scars this session (don't repeat)

- An isolation fix broke idempotency (two runs got two different fake HOMEs — idempotency needs
  the SAME environment twice). Caught by the test suite immediately.
- The legacy test sections were writing to the real `$HOME` during test runs (pre-existing;
  found by P6's CI simulation, fixed with md5-verified hermeticity). Same class as 07-02's
  copilot-skills leak: **every out-of-repo path in a test needs an override, and the cheap
  proof is snapshotting real targets across the run.**
