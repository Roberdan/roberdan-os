# roberdan-os

**One person's agentic operating manual — the behavioral canon, tooling, and guardrails that make
AI coding agents work the way Roberto D'Angelo works — published as a worked example you can fork.**

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![validate](https://github.com/Roberdan/roberdan-os/actions/workflows/validate.yml/badge.svg)](https://github.com/Roberdan/roberdan-os/actions/workflows/validate.yml)

## What this actually is

Concretely: **~140 tracked files (~215 on a working machine, incl. local state a clone won't
have) — Markdown + Bash. No server, no account, no compiled code, no runtime engine.** The
Markdown is a *behavioral canon* that any [AGENTS.md](https://agents.md)-reading AI
tool (primarily [Claude Code](https://claude.com/claude-code)) reads to behave as Roberto's
assistant — how to operate on code (autonomy, evidence-first, done-gates), how to write and decide
in his voice, when to ask before acting. The Bash is the machinery around it: a gated kanban CLI,
Claude Code hooks, an install/sync generator, a headless-agent "factory", a privacy leak-gate, and
an eval harness. `AGENTS.md` is the single source; every per-tool wrapper is *generated* from it,
never hand-copied.

It **is**: one individual's daily-used agentic configuration, versioned and published openly, that
you can fork by editing one directory ([`identity/`](identity/README.md)).

It is **not**: a product, a framework, a chatbot, a prompt library, or a hosted service. There's
nothing to run as a server. It configures the agent tools you already use, around one identity.

## Real vs. aspirational — the honest map

This project's own cardinal rule is *"no claim without evidence."* Applied to itself: a disciplined
core genuinely works; some ambitious layers are scaffolding that runs but doesn't yet do the thing
it advertises. Stated plainly so you can trust the rest.

**Works, verified (the core):**
- **The canon is read and generated deterministically.** Root `CLAUDE.md` → `AGENTS.md` symlink;
  `bin/sync.sh` regenerates every per-tool wrapper from the canon (CI proves it's deterministic).
- **`kb`** — the gated kanban CLI (view/add/start/finish/pause/resume/lint, cross-repo federation
  read-path). Durable card files, human gate on `todo→doing`, `@thor` gate on `doing→done`.
- **Hooks that fire** on Claude Code: `bash-guard` (blocks force-push/reset — real deny),
  `context-inject` (session primer), `auto-checkpoint` (pause/resume state + receipts every turn),
  a git `pre-commit` **leak gate** that actually blocks a commit containing a confidential term.
- **`bin/install-hooks.sh` / `bin/sync.sh --install`** — idempotent, non-destructive install of the
  hook set and skill wrappers into `~/.claude`.
- **Native Copilot adapter** (v2.16.0) — `bin/sync.sh --install` also generates, deterministically
  and collision-safe, **Copilot custom agents** (`~/.copilot/agents/`) and a **user-scoped extension**
  (`~/.copilot/extensions/roberdan-os/`) that binds the provider-neutral `hooks/` to Copilot's
  lifecycle: context-injection on session start, the `main`/`bash` guards on pre-tool-use (real
  deny/ask, fail-safe on error), autofmt, and an always-on pause/resume checkpoint — plus namespaced
  tools (`roberdanos_kanban/pause/resume/verify-done/doctor`). Its completion gate is **advisory**
  (Copilot can't block an already-produced final response — see limitations).
- **factory** — bounded headless `claude -p` runs (timeout, model clamp, OAuth billing). Bounded,
  **not OS-sandboxed** (`--dangerously-skip-permissions`, scoped to one dir).
- **eval harness** — a real with/without-canon A/B + blind-judge pipeline. CI-gated. (See the
  caveat on its *results* below.)
- **Self-improving meta-loop** (`learn/` → `ontology/`) — as of v2.10.0 it actually promotes:
  a deterministic classifier (not the old `TODO` stub), a frontmatter-scoped approval gate that
  can't be spoofed by body text, and a backfill that unstuck the real 619-item backlog (617
  boilerplate pings archived, real learnings surfaced for approval). Promotion stays **human-gated
  by design** (`approved: true` is Roberto's to flip); test-proven end-to-end.
- **CI** (`test/validate.sh`) — frontmatter, links, deterministic generation, shellcheck,
  leak-check, kb/factory/federation/receipts/install/meta-loop regression, fork-merge proof.

**Advisory only (prose an LLM chooses to follow, not enforced):** most of `behavior/`, `rules/`,
`identity/`, and the agent personas. Compliance depends on the model following instructions —
roughly four things are *mechanically* enforced (pre-commit leak gate, bash-guard, deterministic
generation, CI). The `verify-done` **hook** only warns; the real done-gate is the `@thor` agent.

**Scaffolding — runs, but hasn't produced its output yet (honest gaps):**
- **`evolve/`** (weekly upstream-changelog watcher): real bounded code, but **has never fired** yet.
- **factory external-CLI dispatch** (multi-tool runners): **dormant by design** — hard-refuses every
  dispatch until an OS-isolation floor lands via a reviewed code edit. Zero external-runner risk today.
- **Auto-promotion in the meta-loop** (skipping the human `approved:` flip for high-confidence
  classes): the taxonomy records the intended policy, but every class still requires Roberto's
  approval — auto-eligibility is deliberately **not** wired.

**Doesn't validate the canon (yet):** the eval *harness* is real, but its one real run (10 of 12
tasks, 2026-07-02, against a live `claude`) **did not show the canon winning**. It tied 4–4 on the
8 core behavior/rules tasks; the 2 skill-type tasks (excluded from that aggregate for a documented
reason — prepending an invocable skill file as passive context is a known mismatch) *both* favored
no-canon, so across all 10 judged runs no-canon actually led **4–6**. Result self-flagged stale.
Honest framing: *we built the instrument; on a small sample it hasn't shown a win — if anything the
opposite.* Not "the canon is proven to work."

## How it's structured

| Component | Where | Status |
|---|---|---|
| Universal entry | [`AGENTS.md`](AGENTS.md) | real |
| Layer map | [`ARCHITECTURE.md`](ARCHITECTURE.md) | real |
| Identity (the one directory a fork edits) | [`identity/`](identity/README.md) — voice, operator, twin persona, `identity.conf` | real |
| Behavior canon | `behavior/roberto-mode.md` + `identity/voice.md` + `behavior/thinking-toolkit.md` | advisory prose |
| Rules | `rules/constitution.md` + `rules/best-practices.md` | advisory prose |
| Agents (9) | `agents/` — thor, twin, baccio, rex, luca, socrates, board, coach, wanda | real subagents on Claude Code **and Copilot CLI** (native custom agents, v2.16.0); prose personas on Codex/others |
| Skills | `skills/` — verify-done, ship, review, sync, auto-checkpoint, focus-group, premortem, problem-validation | real; some build on external gstack |
| Hooks | `hooks/` — bash-guard, context-inject, auto-checkpoint, autofmt, verify-done, main-guard, post-task-sync, pre-commit | mixed — see the honest map above for which fire (also bound to Copilot's lifecycle via the native extension, v2.16.0) |
| Kanban / goal ledger | `kanban/` — the `kb` CLI. Card content is gitignored, local-only | real |
| Agent factory | `factory/` — bounded headless `claude -p` (native path real; external dispatch dormant) | mixed |
| Meta-loop | `learn/` (capture+classify) + `ontology/` (promote, human-gated) + `evolve/` | learn→ontology real (v2.10.0); evolve not-yet-fired |
| Eval | [`eval/README.md`](eval/README.md) — A/B + blind judge harness | harness real; result favored no-canon (4–6 over 10 runs) |
| Install | `bin/bootstrap.sh` · `bin/install-hooks.sh --apply` · `bin/sync.sh --install` | real |
| Per-platform wrappers | `platforms/` — generated by `bin/sync.sh --emit-only`, gitignored, never committed (Claude, Copilot agents + extension, Codex, …) | real |
| Web bundle | `bin/make-bundle.sh` → pasteable canon (excludes `private/`) | real |

## Getting started

```
git clone https://github.com/Roberdan/roberdan-os.git
cd roberdan-os
bin/bootstrap.sh                    # generate wrappers, symlink agents (~/.claude/agents) + kb
                                     # (~/.local/bin), run validate
bin/install-hooks.sh --apply        # merge the hook set into ~/.claude/settings.json
                                     # (idempotent, non-destructive, backs up first)
bin/sync.sh --install               # symlink the skill wrappers into ~/.claude/skills
                                     # (also installs Copilot agents + extension + skills
                                     #  into ~/.copilot when Copilot CLI is present)
```

Those three commands install the engine with no JSON hand-editing. **One manual step remains**: add
the one-line pointer block that `bootstrap.sh` prints to your *personal* `~/.claude/CLAUDE.md`
(curated config the engine deliberately never overwrites). Re-run `install-hooks.sh --apply` after
the hook canon changes — nothing alarms you if the live wiring drifts from the canon.

Pass `--dossier /path/to/profile.md` to `bootstrap.sh` only if you have Roberto's own confidential
profile; everyone else omits it and the twin degrades gracefully to `[placeholder]`.

## Prerequisites

Required: `git`, `jq`, `bash`, `python3` (the eval pipeline needs it — CI won't be fully green
without it; the leak-check hash tier degrades to a silent WARN-and-skip rather than failing), and
an AGENTS.md-reading agent CLI (Claude Code is the primary target; Codex, Copilot CLI/VS Code,
Cursor, opencode, Warp, hermes read the same file natively).

Optional, feature-gated (everything degrades cleanly without them):
- `shellcheck` — the lint gate (falls back to `bash -n`).
- `prettier` — without it, `autofmt` silently no-ops on JS/TS/MD/CSS (Python/Rust still format).
- [gstack](https://github.com/garrytan/gstack) — backs the `problem-validation` skill (which
  orchestrates the self-contained `focus-group` + `premortem` skills; those two exist precisely
  because gstack lacks them).
- [gbrain](https://github.com/garrytan/gbrain) — local-first semantic memory for recall. Roberto
  runs a **personal patched fork** ([`github.com/Roberdan/gbrain`](https://github.com/Roberdan/gbrain))
  pinned to `ollama:bge-m3`; needs [Ollama](https://ollama.com) for that embedder.

Reading the canon needs none of these — they only power the automation (recall, factory, some skills).

## Honest limitations

- **Single-person system, not a framework.** It configures *your* agent tools around one identity.
- **Human gates are discipline, not security.** `--by roberto` / `--thor` are unenforced strings —
  any caller can pass them. They're an honor-system audit trail, not a blocking boundary.
- **Cross-tool parity is partial.** `AGENTS.md` behavior propagates everywhere. On **Claude Code**
  the subagents and hooks are fully native; on **Copilot CLI** the 9 agents are now real invokable
  custom agents and the hooks are bound via the native adapter (v2.16.0), **except** the completion
  gate is advisory — Copilot can't block an already-produced final response. On **Codex** and other
  AGENTS.md tools the agents remain prose personas, not invokable.
- **Full function depends on external, personal tooling** (the gbrain fork, gstack). Without them,
  recall and some skills degrade.
- **`evolve` hasn't fired yet, and meta-loop auto-promotion is deliberately un-wired** (see the
  honest map). The `learn→ontology` promotion path itself is real and human-gated as of v2.10.0.
- **The eval hasn't shown the canon wins — if anything, the opposite.** Small sample, no-canon led
  4–6 across 10 judged runs (4–4 on the core subset), self-flagged stale.

## Forking

Since v2.0.0 the fork story is one directory: everything editable lives in
[`identity/`](identity/README.md); engine files never embed identity, so `git merge upstream/main`
stays conflict-free on them by construction — proven, not asserted, by `test/test-fork-merge.sh`.
Start with [`docs/QUICKSTART-for-forkers.md`](docs/QUICKSTART-for-forkers.md): `bin/identity-init.sh`
scaffolds your `identity/` (dry-run by default), then you rewrite the prose in your own words and set
`RDA_HOME=~/.<you>-os`. You inherit a working canon + `kb` + hooks + eval harness; the memory/recall
and meta-loop automation require rebuilding the external tooling above.

## Relationship to Convergio

[Convergio](https://github.com/Roberdan/convergio) is the same philosophy at platform scale —
evidence-first discipline, done-gates, human gates on irreversible actions, enforced by a Rust daemon
with hash-chained audit. roberdan-os is the personal-scale instance of those principles. Convergio is
the municipality; roberdan-os is one citizen's house built to the same codes. Neither depends on the
other — Convergio is an optional observer of the loop, never a single point of failure.

## Privacy

Two things are gitignored and never enter git or any bundle:
- `private/` — the confidential dossier (clients, deals, people). Only the non-sensitive voice/style
  (`identity/voice.md`) is committed.
- `kanban/todo/ doing/ done/` — live task/business content. Only the `kb` tool and protocol are versioned.

Everything else is intentionally public and attributed to Roberto D'Angelo by name — a personal system
published under his own identity. If you fork it, run `bin/update-denylist-hashes.sh` against your own
`private/.denylist` before your first commit (see [`test/leak-check.sh`](test/leak-check.sh)).

## License

[MIT](LICENSE). The canon, tooling and guardrails are generic and reusable; the identity is one
directory you replace. Not a technical read? See [`docs/roberdan-os-paper-en.md`](docs/roberdan-os-paper-en.md)
(versioned separately; some file paths it cites predate the v2.0.0 `identity/` split).
