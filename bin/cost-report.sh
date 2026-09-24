#!/usr/bin/env bash
# cost-report.sh — costo/spesa per host+modello, finestra + finestra precedente (per la freccia).
# Legge, non scrive: ~/.copilot/session-store.db in sola lettura e i transcript di Claude Code.
# Se una fonte manca o non si legge, quella sezione dice "non disponibile" — non blocca l'altra.
#
#   bin/cost-report.sh [--days N]
#
#   --days N   ampiezza della finestra corrente e di quella precedente (default 7, 1..3650)
#
# Il calcolo vive in bin/cost_report.py + bin/cost_report_copilot.py + bin/cost_report_claude.py
# (definizioni USD/premium/contesto/sotto-agente commentate li'). Questo file e' solo l'ingresso
# da riga di comando: validazione argomenti, risoluzione percorsi, ricerca di python3.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DAYS="${RDA_COST_DAYS:-7}"
STORE="${RDA_COPILOT_STORE:-$HOME/.copilot/session-store.db}"
PROJECTS="${RDA_CLAUDE_PROJECTS:-$HOME/.claude/projects}"

usage() {
  cat <<'EOF'
cost-report.sh — spesa/costo per host+modello negli ultimi N giorni, con la finestra precedente.

Usage: bin/cost-report.sh [--days N]

  --days N   ampiezza della finestra (default 7). RDA_COST_DAYS fa lo stesso.
  RDA_COPILOT_STORE    sovrascrive ~/.copilot/session-store.db (per i test)
  RDA_CLAUDE_PROJECTS  sovrascrive ~/.claude/projects (per i test)

Legge in sola lettura (sqlite3 file:...?mode=ro + lettura di file). Se una fonte manca dice
"non disponibile" invece di fallire. Non stampa mai i due host sommati in un unico numero.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --days) [ $# -ge 2 ] || { echo "cost-report: --days richiede un numero" >&2; exit 2; }
            DAYS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "cost-report: argomento sconosciuto: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$DAYS" =~ ^[0-9]{1,4}$ ]] && [ "$((10#$DAYS))" -ge 1 ] \
  || { echo "cost-report: --days deve essere un intero da 1 a 3650" >&2; exit 2; }

command -v python3 >/dev/null 2>&1 || { echo "cost-report: python3 non disponibile" >&2; exit 1; }

exec python3 "$ROOT/bin/cost_report.py" --days "$((10#$DAYS))" \
  --store "$STORE" --projects "$PROJECTS" --root "$ROOT"
