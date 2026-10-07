#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 "$ROOT/test/test-g1-evidence-ledgers.py"
python3 "$ROOT/test/test-job-slo-report.py"
python3 "$ROOT/test/test-graph-parity-report.py"
python3 "$ROOT/test/test-activated-arms.py"
python3 "$ROOT/test/test-telemetry-positive-control.py"

echo "test-g1-evidence: PASS"
