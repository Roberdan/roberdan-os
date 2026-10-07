# Runtime ledger

Machine-runtime truth for the AI work system. This is an observed snapshot, not a promise that
a scheduled job will remain healthy forever.

**Observed:** 2026-10-07. **Classification rule:** `supported` requires a loaded schedule or
running process, an executable target, and no observed non-zero exit. `dormant` means installed
but without an active execution path. `broken` requires direct failure evidence.
`intentionally-disabled` requires an explicit disabled state. `execution unproven` means the
wiring is valid but no useful receipt was available.

## Providers and execution engines

| Component | State | Evidence | Failure mode / owner |
|---|---|---|---|
| Claude Code | supported | Native `2.1.292`; `claude doctor` exit 0 | Anthropic native updater; Homebrew `2.1.285` retained only as rollback |
| Copilot CLI | supported | `1.0.92`; generated agents and extension pass adapter tests | GitHub CLI runtime; settings remain Copilot-owned |
| Codex CLI | supported, embedded; execution unproven | `0.160.1` inside ChatGPT app; not on shell `PATH`; no running process observed | OpenAI/ChatGPT app owns the binary; shell workflows must use an explicit path or add a deliberate wrapper |
| gbrain | supported | `0.60.102.0` equals latest; doctor exit 0; positive/negative code controls pass | Local gbrain jobs; exact lookup falls back to `rg` |
| Factory | supported | `com.roberdan.rda-factory` loaded and scheduled; executable target; exit 0; receipt files present | `factory/`; fail-closed guard blocks when prerequisites are missing |

## Scheduled jobs

Idle scheduled jobs are not dormant: launchd normally starts them only when their interval or
calendar fires.

| Label | Owner | Trigger | State | Evidence |
|---|---|---|---|---|
| `com.roberdan.gbrain-jobs-window` | gbrain | calendar | supported | loaded, executable, exit 0, receipt present |
| `com.roberdan.gbrain-refresh-code` | gbrain | every 10,800 s | supported | loaded, executable, exit 0, receipt present |
| `com.roberdan.gbrain-vault-sync` | gbrain | calendar | supported | loaded, executable, exit 0 |
| `com.roberdan.rda-factory` | factory | calendar | supported | loaded, executable, exit 0, receipt present |
| `com.roberdan.rda-learn` | learning pipeline | calendar | supported | loaded, executable, exit 0, receipt present |
| `com.roberdan.rda-evolve` | provider watcher | calendar | supported, execution unproven | loaded, executable, exit 0 |
| `com.roberdan.rda-pending-digest` | pending digest | calendar | supported | loaded, executable, exit 0, receipt present |
| `com.roberdan.copilot-log-sweep` | Copilot hygiene | calendar | supported | loaded, executable, exit 0 |
| `com.roberdan.buongiorno` | daily briefing | calendar | supported, execution unproven | loaded, executable, exit 0 |
| `com.roberdan.rustsweep` | Rust workspace hygiene | calendar | supported, execution unproven | loaded, executable, exit 0 |
| `com.roberdan.rusty-mac-backup` | machine backup | hourly + run-at-load | supported | loaded, executable, exit 0, receipts present |
| `com.roberdan.tmux-autosave` | terminal recovery | every 900 s | supported | loaded, executable, exit 0 |
| `com.roberdan.virtualbpm-refresh` | VirtualBPM data refresh | calendar | supported | loaded, executable, exit 0 |
| `com.roberdan.virtualbpm-runner-watchdog` | VirtualBPM runner | every 180 s + run-at-load | supported | loaded, executable, exit 0 |
| `actions.runner.roberdan_microsoft-VirtualBPMFy27.roberto-mac-virtualbpm` | GitHub Actions | persistent | supported | loaded and running |
| `actions.runner.roberdan_microsoft-VirtualBPMFy27.roberto-mac-virtualbpm-2` | GitHub Actions | persistent | supported | loaded and running |

No listed G0 job was explicitly disabled or observably broken. The inventory read only plist
metadata, process state, exit status, executable mode, and receipt sizes/timestamps; it did not
read logs, environment values, command payloads, or private content.

## Verification and receipts

- Provider/source receipts:
  `~/.roberdan-os/archive/g0-provider-update-2026-10-07/`
- G1 decision evidence:
  [`capability ledger`](evidence/capability-ledger.tsv),
  [`hook parity`](evidence/hook-parity.tsv), and
  [`recovery matrix`](evidence/recovery-matrix.tsv).
- Refresh this ledger from live metadata before using it for a removal decision.
- A zero-byte receipt is wiring evidence only, not proof that useful work happened.
