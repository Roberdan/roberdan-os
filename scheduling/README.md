# scheduling — launchd lane of the meta-loop

OS-level scheduler (fires even with Claude closed). Cron-swappable. See [`docs/adr/0001-self-improving.md`](../docs/adr/0001-self-improving.md).

| Job | Cadence | Runs |
|---|---|---|
| `com.roberdan.rda-evolve` | weekly (Sat 02:00, launchd catch-up if the Mac is off) | `evolve/watch.sh` → kanban cards |
| `com.roberdan.rda-learn` | daily (02:30) | `learn/distill.sh` + `ontology/curate.sh` |
| `com.roberdan.rda-factory` | nightly (01:00) — plist lives in [`factory/`](../factory/) | `factory/run.sh` (queued headless tasks) |

## Install

```sh
cp scheduling/*.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.roberdan.rda-evolve.plist
launchctl load ~/Library/LaunchAgents/com.roberdan.rda-learn.plist
```

Capture (per-session) is separate: opt-in `Stop` hook (`RDA_LEARN=1`) or `learn/capture.sh` by hand.
Logs in `/tmp/rda-*.log`. `curate` promotes **only** `approved: true` candidates (human gate).
