# scheduling — launchd lane of the meta-loop

OS-level scheduler (fires even with Claude closed). Cron-swappable. See [`docs/adr/0001-self-improving.md`](../docs/adr/0001-self-improving.md).

| Job | Cadence | Runs |
|---|---|---|
| `com.roberdan.rda-evolve` | weekly (Mon 09:00) | `evolve/watch.sh` → draft proposals |
| `com.roberdan.rda-learn` | daily (02:30) | `learn/distill.sh` + `ontology/curate.sh` |

## Install

```sh
cp scheduling/*.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.roberdan.rda-evolve.plist
launchctl load ~/Library/LaunchAgents/com.roberdan.rda-learn.plist
```

Capture (per-session) is separate: opt-in `Stop` hook (`RDA_LEARN=1`) or `learn/capture.sh` by hand.
Logs in `/tmp/rda-*.log`. `curate` promotes **only** `approved: true` candidates (human gate).
