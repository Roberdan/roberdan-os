# scheduling — launchd lane of the meta-loop

OS-level scheduler (fires even with Claude closed). Cron-swappable. See [`docs/adr/0001-self-improving.md`](../docs/adr/0001-self-improving.md).

| Job | Cadence | Runs |
|---|---|---|
| `com.roberdan.rda-evolve` | weekly (Sat 02:00, launchd catch-up if the Mac is off) | `evolve/watch.sh` → kanban cards |
| `com.roberdan.rda-learn` | daily (02:30) | `learn/distill.sh` + `ontology/curate.sh` |
| `com.roberdan.rda-factory` | nightly (01:00) — plist lives in [`factory/`](../factory/) | `factory/run.sh` (queued headless tasks) |
| `com.roberdan.rda-worktrees` | daily (03:10) | `kanban/worktree-sweep.sh sweep --yes` → rimuove le copie di lavoro che non hanno piu' niente dentro (log `/tmp/rda-worktrees.log`). La pulizia *a monte* gira gia' a ogni fine turno (`hooks/auto-checkpoint.sh` → `autosweep`, ambito: repo corrente): questo job e' la rete di sicurezza sui repo che nessuno ha aperto |
| `com.roberdan.rda-pending-digest` | twice daily (09:00 + 18:00) | `bin/pending-digest.sh` → macOS notification + `~/.roberdan-os/pending-digest.txt` when something waits on Roberto (see `kb pending`) |

## Install

```sh
cp scheduling/*.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.roberdan.rda-evolve.plist
launchctl load ~/Library/LaunchAgents/com.roberdan.rda-learn.plist
```

Capture (per-session) is separate: opt-in `Stop` hook (`RDA_LEARN=1`) or `learn/capture.sh` by hand.
Logs in `/tmp/rda-*.log`. `curate` promotes **only** `approved: true` candidates (human gate).
