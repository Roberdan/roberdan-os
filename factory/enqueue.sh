#!/usr/bin/env bash
# factory/enqueue.sh — add a task to the autonomous agent factory queue.
# Usage: enqueue.sh "<task text>" [name]   |   enqueue.sh <task-file.md> [name]
# See factory/factory-protocol.md.
set -euo pipefail

RDA_HOME="${RDA_HOME:-$HOME/.roberdan-os}"
FACTORY="${RDA_FACTORY:-$RDA_HOME/factory}"
Q="$FACTORY/queue"; mkdir -p "$Q"
task="${1:?task text or file required}"
name="${2:-task-$(date +%Y%m%d-%H%M%S)}"
dest="$Q/${name}.md"

if [ -f "$task" ]; then
  cp "$task" "$dest"
else
  printf -- '---\ndir: ~/GitHub\n---\n%s\n' "$task" > "$dest"
fi
echo "enqueued → $dest"
echo "run now: factory/run.sh   |   or wait for launchd com.roberdan.rda-factory"
