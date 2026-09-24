#!/usr/bin/env bash
# twin-shadow.sh — the twin's shadow mode on `kb pending` (docs/adr/0005-twin-decision-ledger.md).
#
#   bin/twin-shadow.sh predict [--max N]   hidden prediction per todo card (host optional, capped)
#   bin/twin-shadow.sh reconcile           record approvals/vanished cards the kb hook missed
#   bin/twin-shadow.sh decide --card C --choice approve|reject|defer [--reason R]
#   bin/twin-shadow.sh batch               pending sorted by the twin's advice — approves NOTHING
#   bin/twin-shadow.sh agreement [--days N | --all]
#   (outcome: called by `kb start`, update-only, never blocks kb)
#
# The ledger is local-only under RDA_HOME/private/decisions and refused inside any git tree.
set -uo pipefail
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/twin_shadow.py" "$@"
