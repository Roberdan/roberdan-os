# Proposal — 2026-08-29 — claude-code

## Source citation (URL + version + date)

- Changelog: <https://cdn.jsdelivr.net/gh/anthropics/claude-code@main/CHANGELOG.md> (fetched 2026-08-29).
- Baseline: `proposals/2026-08-22-claude-code.md` assessed through **v2.1.250** (2026-08-28).
- Release dates: <https://api.github.com/repos/anthropics/claude-code/releases> — **v2.1.251
  published 2026-08-28T18:19:32Z** (v2.1.250: 2026-08-28T00:49:16Z).
- New version assessed: **v2.1.251** (2026-08-28) — the only entry above the baseline in the changelog
  (`grep '^## ' CHANGELOG.md` → `2.1.251`, `2.1.250`, `2.1.248`, …). Single release, 74 changelog
  lines; the ~40 UI / Bedrock / Vertex / provider-gateway fixes in it are out of scope for
  roberdan-os and are not itemised below.

## Already assessed and skipped

The declined buffer stays declined. Two carried items touch this release and are re-checked, not re-raised:

- *v2.1.238 self-hosted runner + cross-session messaging* (declined 2026-08-21 and 2026-08-28): v2.1.251
  adds a self-hosted-runner fix (stuck Bash processes after force-stop) and `SendMessage` delivery
  through Claude Desktop. The factory still runs on launchd (`factory/com.roberdan.rda-factory.plist`),
  not on a Claude self-hosted runner, and the durable ledger is still the bus. Unchanged → still declined.
- *v2.1.243 `promptCacheTtl` / `subagentPromptCacheTtl`* (proposed 2026-08-22, since adopted): v2.1.251
  adds a per-session prompt-cache line to `/cost` and a `prompt_cache` status-line object. Observability
  only — `bin/sync.sh:246` already emits `"promptCacheTtl": "1h", "subagentPromptCacheTtl": "5m"`.
  No patch.

## Novelties + impact

### 1. v2.1.251 — `SessionStart` resume hooks now receive session staleness and estimated re-cache cost

**Evidence.** v2.1.251: "Added `PreModelSwitch` and `PostModelSwitch` hook events …; `SessionStart`
resume hooks now receive session staleness and the estimated re-cache cost".

**Impact on roberdan-os.** `bin/sync.sh:248-250` wires `hooks/context-inject.sh` as the only
`SessionStart` hook, deliberately with no matcher ("it fires on startup/resume/clear/compact",
`bin/sync.sh:237`). **That hook never reads its stdin**: `grep -n 'stdin\|jq\|read \|cat' hooks/context-inject.sh`
returns no input read at all — it only `echo`s. So it injects the same full block (pending count,
checkpoint, kanban, authorised queue) on every one of those four triggers, including a resume two
minutes after the session was backgrounded, where the whole block is already in the window and is
paid for twice.

The new fields make a cheap branch possible for the first time: on a **fresh** resume, print one line;
on a **stale** resume (or startup/clear/compact), print the full block.

**Suggested patch, awaiting Roberto.** Read stdin in `hooks/context-inject.sh` and branch on the new
fields, keeping the current behaviour as the fallback when the fields are absent (older Claude Code,
Copilot's emulated chain):

```sh
input="$(cat 2>/dev/null || true)"
src="$(printf '%s' "$input" | jq -r '.source // ""' 2>/dev/null || echo "")"
stale="$(printf '%s' "$input" | jq -r '.session_staleness // empty' 2>/dev/null || echo "")"
# fresh resume → one line; everything else → the full block (today's behaviour)
```

Field names must be confirmed against the live payload before writing the patch (log one payload to a
file first); the changelog names the capability, not the schema. Citation: changelog v2.1.251.

### 2. v2.1.251 — file tools no longer follow a symlink swapped after the permission check; Grep/Glob now apply `Read(...)` deny rules through symlinked paths

**Evidence.** v2.1.251: "Fixed file tools (Read, Write, Edit) following a symlink swapped inside the
working directory after the permission check, which could read or write outside the approved location"
and "Fixed Grep and Glob not applying `Read(...)` deny rules to files reached through a symlinked
search path".

**Impact on roberdan-os — the same class of hole exists in our own guard.** `hooks/main-guard.sh:11`
reads `.tool_input.file_path` and decides **on the path text**, never resolving it:

```
hooks/main-guard.sh:22-26   case "$fp" in *.md|*/.claude/*|*/docs/*|…) exit 0 ;; esac
```

A symlink named `notes.md` pointing at `src/lib.rs` satisfies the `*.md` carve-out, so a write to source
on `main` is allowed by the guard. Claude Code's own fix hardens Claude's permission layer; it does not
harden ours, because our guard makes its own decision on the unresolved string.

**Suggested patch, awaiting Roberto.** Resolve the path before the carve-out in `hooks/main-guard.sh`,
falling back to the literal path when the file does not exist yet (Write of a new file is the common case):

```diff
 fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""')"
+# Decide on the RESOLVED path: a symlink named *.md pointing at source would otherwise
+# satisfy the meta/docs carve-out below. Same class as claude-code v2.1.251.
+if [ -e "$fp" ]; then fp="$(/bin/realpath "$fp" 2>/dev/null || printf '%s' "$fp")"; fi
```

`/bin/realpath` is present on stock macOS in its BSD flavour (verified: usage string is
`realpath [-q] [path ...]`, and `--version` fails with "illegal option" — so no GNU long options;
`codesign -dv /bin/realpath` gives `Identifier=com.apple.realpath`), so no interpreter start is paid
on a hook that fires on every edit. A test in `test/` should pin it: symlink `x.md → x.rs` on `main` must be denied.
Citation: changelog v2.1.251 (2026-08-28).

### 3. v2.1.251 — new `PreModelSwitch` / `PostModelSwitch` hook events

**Evidence.** v2.1.251: "Added `PreModelSwitch` and `PostModelSwitch` hook events (block, confirm, or
annotate a model switch)".

**Impact on roberdan-os.** The generated settings declare five events — `SessionStart`, `PreToolUse`,
`PostToolUse`, `PreCompact`, `Stop` (`bin/sync.sh:248-268`) — and no model event. Two canon rules are
today advisory prose with no mechanical gate: the `model-selection-policy` skill (which tier) and
`rules/best-practices.md` § *Subagent models* (always the newest generation of the tier), whose own
recorded scar is exactly a wrong model id typed from memory (2026-08-28, MirrorScopio). A
`PreModelSwitch` hook is the first surface where that rule could become a check instead of a sentence —
and § *Cache discipline* in the same file warns that a mid-session model switch invalidates the prompt
cache, which this event can annotate.

**Suggested patch, awaiting Roberto.** Draft only; this adds a new gate and is a scope decision.
Shape: a `hooks/model-guard.sh` that on `PreModelSwitch` warns (never blocks) when the target model is
not in `copilot_model()`'s table in `bin/sync.sh:118` or a newer generation, plus one line in
`bin/sync.sh` wiring the event. Recommend deferring until the payload schema is documented.
Citation: changelog v2.1.251.

### 4. v2.1.251 — Bash permission checks no longer auto-approve `VAR=<arithmetic>` assignments

**Evidence.** v2.1.251: "Fixed Bash permission checks auto-approving commands that assign an arithmetic
expression to an integer shell variable (e.g. `OPTIND=1/0`, `RANDOM=2+2`); these now prompt for approval".

**Impact on roberdan-os: checked, none.** `hooks/bash-guard.sh` never auto-approves — it only ever
returns `deny`/`ask` and otherwise `exit 0` (line 65), leaving the decision to Claude. Its rules match
`git[[:space:]]+push…` anywhere in the normalised string (`hooks/bash-guard.sh:39-47`), so an assignment
prefix (`RANDOM=2+2 git push --force`) does not shift the match. Verified by reading the guard, not assumed.

**Suggested patch.** None. Recorded so next week's card does not re-derive it.

## Not applicable — verified, not assumed

- *"Fixed background sessions and their subagents being unable to edit files inside a git worktree they
  created with `git worktree add`"* — the factory does not use background sessions or self-created
  worktrees: `grep -n 'worktree\|--bg\|background' factory/run.sh factory/lib.sh` returns only a prose
  line in `factory/lib.sh:126`. No impact.
- *"Fixed Opus 5 requests failing with 'effort … is not supported when thinking is disabled' when effort
  was xhigh/max"* — this one touches a canon-declared field, so it was checked rather than skipped:
  `agents/board.md:5` and `agents/socrates.md:5` are the only two agents declaring `effort: "xhigh"`,
  and `behavior/thinking-toolkit.md` makes that deliberate. Nothing in the canon or in
  `~/.claude/settings.json` disables thinking, so the failing combination is never produced. No patch.
- *"Changed `CLAUDE_CODE_SUBAGENT_MODEL` to set the default subagent model rather than override
  everything: an agent definition's `model:` and an explicit per-spawn model now take precedence"* —
  checked: the variable is set nowhere in the repo or in `~/.claude/settings.json`, and all nine
  `agents/*.md` declare `model:`. The change moves precedence toward what `rules/best-practices.md`
  § *Subagent models* already requires. No patch.
- *Spend-limit bar, `/usage`, `/cost`, `/radio`, Remote Control streaming, install size, TUI/tmux/screen
  rendering, Bedrock/Vertex/Foundry gateway fixes* — human-UI or provider surface, no canon change.

## Draft-only

Nothing in `behavior/`, `rules/`, `agents/` or `AGENTS.md` was touched (evolve-protocol § Invariants).
