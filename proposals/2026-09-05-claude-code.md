# Proposal — 2026-09-05 — claude-code

*Card `260905-021023-claude-code` (opened 2026-09-05, refreshed 2026-09-11). Assessed 2026-09-12, so this
file covers both changelog changes the card accumulated.*

## Source citation (URL + version + date)

- Changelog: <https://cdn.jsdelivr.net/gh/anthropics/claude-code@main/CHANGELOG.md> (fetched 2026-09-12).
- Release dates: <https://api.github.com/repos/anthropics/claude-code/releases>.
- Baseline: `proposals/2026-08-29-claude-code.md`, assessed through **v2.1.251** (2026-08-28).
- Assessed now: **v2.1.252** (08-31), **v2.1.257** (09-01), **v2.1.258** (09-01), **v2.1.259** (09-02),
  **v2.1.260** (09-03), **v2.1.261** (09-04), **v2.1.263** (09-06), **v2.1.265** / **v2.1.266** (09-08),
  **v2.1.267** (09-09), **v2.1.268** (09-10), **v2.1.269** (09-11) — 617 changelog lines. Version of each
  item below confirmed by extracting that release's block, not by line position.
- Local CLI: `claude --version` → **2.1.269**, the newest release (native installer; `npm view` still says
  2.1.261). No upgrade needed.

## Already assessed and skipped

- The declined buffer in the card stands; nothing in this window reopens it except item 3 below, which the
  buffer rule allows because it is materially new.
- *2026-08-29 #1, `SessionStart` staleness branch* — **already adopted**: `hooks/context-inject.sh:19-22`
  reads stdin and branches on `prompt_cache_likely_expired`. Closed, not re-raised.
- *v2.1.268 task-tracking tools offered only on older models* — same substance as the declined v2.1.233
  item: `kb` stays the ledger.

## Novelties + impact

### 1. v2.1.259 — `--permission-prompts none` for unattended headless hosts  ← worth Roberto's decision

**Evidence.** v2.1.259: "Added `--permission-prompts none` for unattended headless hosts: anything that
would prompt is denied automatically while the active permission mode (including auto mode) keeps
deciding". Confirmed on the local binary: `claude --help` lists `--permission-prompts <target>` ("host" or
"none", with `--print`) and `--permission-mode` choices include `auto`.

**Impact on roberdan-os.** The factory runs every task with
`claude -p … --dangerously-skip-permissions --add-dir "$dir"` (`factory/run.sh:84` and `:87`). Its
guardrail that the agent "won't merge to main, push, spend, or delete" is prose — the agent reads
`AGENTS.md` (`factory/factory-protocol.md:119`). `rules/best-practices.md` § Security says the opposite
control is required: *assume prompt injection eventually succeeds; the control is blast radius, not
prose*. Until v2.1.259 there was no unattended alternative, because any prompt would hang a headless run.
Now there is: auto mode keeps approving routine work, and whatever it would have asked about is refused.

This is not the declined 2026-07-31 sandbox item: no sandbox, no network allowlist, same `--add-dir`
scope — only the permission decision moves from "everything allowed" to "the auto-mode classifier decides,
prompts become denials".

**Suggested patch, awaiting Roberto** (two lines, `factory/run.sh:84,87`):

```sh
# before
"$CLAUDE" -p "$full" --model "$model" --dangerously-skip-permissions --add-dir "$dir"
# after
"$CLAUDE" -p "$full" --model "$model" --permission-mode auto --permission-prompts none --add-dir "$dir"
```

Plus the matching sentence in `factory/factory-protocol.md:26,113`. **Risk:** a task that legitimately
needs an action auto mode would ask about now fails instead of running; it lands in the existing
retry → `failed/` path with the log, so the failure is visible, not silent. **Test before adopting:** run
one queued additive task (write a file + a test) through the new line and one that attempts `git push`,
and read both logs.

### 2. v2.1.261 — `/skill-doctor`: which loaded skills go unused and what they cost in context

**Evidence.** v2.1.261: "Added `/skill-doctor` to show which loaded skills go unused and what they cost in
context, so you can prune them".

**Impact on roberdan-os.** `~/.claude/skills/` holds **74** entries; `~/.claude/settings.json` already
turns ~50 off by hand (`skillOverrides`) and caps the listing at `skillListingBudgetFraction: 0.035`. That
pruning was done by judgment. `/skill-doctor` is the measurement the Context & Token Economy rule asks
for. It is a read-only report.

**Suggested patch.** None up front. Roberto (or a session) types `/skill-doctor` once; only if it names
skills that are both costly and unused does a `skillOverrides` patch follow, as a separate proposal.

### 3. v2.1.257 — `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` (re-check of a declined item, materially new)

**Evidence.** v2.1.257: "Added `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` to apply `CLAUDE_CODE_SUBAGENT_MODEL` (or
the main model) to every subagent, ignoring per-spawn and agent-definition model overrides".

**Impact.** The opposite of what the canon wants: all nine `agents/*.md` declare `model:` with a written
rationale, and `~/.claude/agents/*.md` carry it (`socrates.md:4` → `opus`). Forcing one model would erase
the registry-based class choice. Checked: the variable is set nowhere in the repo or in
`~/.claude/settings.json`. **No patch** — recorded as declined.

## Not applicable — verified, not assumed

- *v2.1.267 `effort:` frontmatter was ignored on models with a pinned default effort (Opus 4.7, Opus 4.8,
  Fable 5)* — checked because nine agents declare `effort:`. They pin `opus`/`sonnet` (Opus 5 / Sonnet 5),
  not the affected models, and no skill declares `effort:` or `model:`. The rationales were not
  decorative. No patch.
- *v2.1.259 frontmatter `model:` on commands/skills ignored in interactive sessions* — no skill declares
  `model:`. No patch.
- *v2.1.267 `maxEffortLevel`* — the canon's policy is "above medium needs a written rationale", not a cap;
  a cap at `xhigh` only blocks `max`, which nothing declares. No patch.
- *v2.1.257 `permissions.blockReadsOutsideWorkingDirectories`* — Roberto's sessions read the vault,
  `~/.claude` and sibling repos by design; it would add prompts, not safety. No patch.
- *v2.1.257 Claude Fable 5.1 becomes the default Fable* — the `fable` alias follows it automatically; the
  Copilot registry row for `claude-fable-5.1` is a copilot-side question (see the copilot proposal).
- *v2.1.261 `bashOutputMaxChars`/`taskOutputMaxChars`, v2.1.269 `bashEditDiffEnabled`* — both put more
  output into context; against the token-economy rule. No patch.
- *v2.1.260 likely cause of prompt-cache misses in `/cost` and the status line* — observability only;
  `~/.claude/statusline.sh` shows no cache field today. Optional, not proposed.
- *v2.1.269 `claude plugin eval`, `/output-style` switching, v2.1.269 attribution-reminder fix, v2.1.268
  faster `--resume` (no wait on SessionStart hooks), v2.1.267 subagent prompt-cache stability* — plugin
  surface roberdan-os does not ship, or Claude-side improvements that apply with no repo change.
- *Gateway, Bedrock/Vertex/Foundry, managed-settings, VS Code, TUI and rendering entries* — provider or UI
  surface.

## Draft-only

Nothing in `behavior/`, `rules/`, `agents/`, `factory/` or `AGENTS.md` was touched (evolve-protocol §
Invariants).
