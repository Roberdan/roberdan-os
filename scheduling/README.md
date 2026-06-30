# scheduling — launchd lane del meta-loop

Scheduler OS-level (scatta anche con Claude chiuso). Cron-swappable. Vedi [`docs/adr/0001-self-improving.md`](../docs/adr/0001-self-improving.md).

| Job | Cadenza | Esegue |
|---|---|---|
| `com.roberdan.rda-evolve` | settimanale (lun 09:00) | `evolve/watch.sh` → draft proposte |
| `com.roberdan.rda-learn` | giornaliero (02:30) | `learn/distill.sh` + `ontology/curate.sh` |

## Install

```sh
cp scheduling/*.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.roberdan.rda-evolve.plist
launchctl load ~/Library/LaunchAgents/com.roberdan.rda-learn.plist
```

Capture (per-sessione) è separato: hook `Stop` opt-in (`RDA_LEARN=1`) o `learn/capture.sh` a mano.
Log in `/tmp/rda-*.log`. `curate` promuove **solo** candidati `approved: true` (gate umano).
