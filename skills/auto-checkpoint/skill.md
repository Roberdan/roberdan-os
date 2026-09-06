---
name: auto-checkpoint
description: Portable "loop kit" — inject durable state, terminal-condition, auto-resume and auto-escalation into any session. Makes the loop reliable without a daemon.
providers: [claude, copilot, codex]
---

# auto-checkpoint — bounded working context, durable work

Use the existing work state, not another memory store. In roberdan-os, `kb` owns the card
and `handoff/resume.md` owns the recovery capsule. Existing job databases/cursors remain
authoritative for their jobs; this skill does not create `state.db` or a scheduler.
Outside this installation, use one local session/workspace checkpoint with the same
fields. Never put confidential notes in a public working tree.

## When to checkpoint

- At each completed phase, before a large read/output, before compaction, and when a job
  starts, finishes or becomes uncertain. A whole turn can be long: end-of-turn saving is
  not sufficient.
- If the host reports context pressure, save before doing more broad exploration.
  Do not estimate percentages from conversation length. Without a measured signal, use
  phase boundaries and symptoms: rereading the same material, losing a constraint,
  repeating a failed approach, or inability to restate the next step.
- Save only conclusions, constraints and evidence references. Keep raw tool output in
  files and retrieve bounded ranges on demand. Delegate independent investigations to
  fresh contexts with explicit scope, required model profile and a bounded result.

## Recovery capsule

`kb pause --context '<JSON>'` validates these seven fields and atomically replaces the
existing checkpoint. Input is at most 12000 UTF-8 bytes; the complete checkpoint is at
most 16384 bytes. Oversized/invalid input is refused, never silently truncated. Use
references when the working set does not fit.

```json
{
  "goal": "Current authorized objective and card ID",
  "acceptance": "Exact observable terminal condition; reference the full criteria",
  "constraints": ["Scope exclusions, human gates, remaining review budget"],
  "decisions": ["Choice and reason; rejected approach and why not to retry it"],
  "evidence": ["Artifact path plus revision and observed result; unverified claims labelled"],
  "pending": ["Job/agent ID, owner, scope, state, artifact, next observation; unresolved approval"],
  "next": "One exact safe action from the correct working directory"
}
```

`goal`, `acceptance`, `next` are nonempty strings; the other fields are arrays of up to
12 nonempty strings. Empty arrays mean none, not unknown: record uncertainty explicitly.
Never put credentials or transcripts in the capsule. Its origin revision stays frozen
when `kb pause --auto` updates mechanical state; newer HEAD does not revalidate old evidence.
Include owned worktree paths in `pending` until cleanup is complete. At task close, prove
they have no active users, unsaved/untracked/ignored data to preserve or unmerged commits;
remove only those exact owned paths via `kb finish` / `git worktree remove`, never force.
If any check is uncertain, retain the path with its reason and next check.

## Compaction and recovery

1. Reach a safe boundary and save the capsule. Compaction must not cancel healthy jobs,
   reset review budgets, grant approvals, change models/effort or increase paid limits.
2. Let the host's native compaction manage its window. Use a supported compact operation
   when available; do not send `/compact` to Bash or pretend that printing it executes it.
   Never substitute `/clear` or `/new`, which can lose live task/session handles.
3. After compaction/resume, read `kb resume --context`, the current card and only the
   referenced artifacts needed next. Recheck working directory, current revision/dirty
   state, approvals and live jobs. The capsule is a set of claims, not new authority.
4. State the goal, constraints and next action from that evidence. If any essential fact
   is missing, recover it from its source before effects. Ask only for genuinely missing
   human decisions; do not reopen settled choices just because the conversation shrank.
5. Resume the outstanding step, not the whole job. A cancelled/timeout result can have
   side effects: reconcile it first. Two observations without progress stop that step,
   not launch a third identical attempt. See [[long-running-jobs]].

## Actual platform behavior

- **Claude Code:** installed `PreCompact` runs the mechanical checkpoint; `SessionStart`
  reloads context after compact. The agent still writes semantic decisions at phase ends.
- **Copilot CLI 1.0.84-1:** the adapter uses typed root `session.usage_info` to request one
  mechanical save at 65% (rearmed below 50%), plus `session.compaction_start`. It never changes
  the host's compaction thresholds. On successful `session.compaction_complete`, the next
  prompt/tool receives one bounded `kb resume --context` result. Child events are ignored.
  Idle/end saves remain. Event callbacks cannot hold up compaction or capture thoughts:
  the saved capsule must already exist. Missing events on older hosts mean phase saves,
  not a fabricated automation guarantee.
- **Other hosts:** use their declared tools only. Manual capsule recovery remains valid;
  no automatic `launchd`, `cron`, factory or wakeup loop is installed by this skill.

## Quality boundary

A bigger window is not a remedy for accumulated noise. Preserve required model profiles
and reasoning effort; [[model-selection-policy]] governs any change. Recheck acceptance
against real artifacts after recovery. Fresh reviewers receive scope, current diff and
evidence, not a transcript or the author's verdict.

These controls bound replay/context overhead and preserve recorded state. They cannot
guarantee unchanged model accuracy for arbitrarily long sessions. Existing regression
tests exercise storage and lifecycle behavior, not a paid outcome benchmark.
