#!/usr/bin/env bash
# twin-agreement.sh — how often the twin predicted Roberto's real choice, per category and
# overall, from the local decision ledger. "dati insufficienti" below 5 decisions.
#
#   bin/twin-agreement.sh              ultimi 7 giorni (the weekly summary)
#   bin/twin-agreement.sh --days 30    another window
#   bin/twin-agreement.sh --all        da sempre
set -uo pipefail
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/twin_shadow.py" agreement "$@"
