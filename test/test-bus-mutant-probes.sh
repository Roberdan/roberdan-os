#!/usr/bin/env bash
# test-bus-mutant-probes.sh — a standing guard for the leak test-bus-mutants.sh
# proved it could make: a probe planted on the REAL machine and never swept.
# It does NOT run the mutation harness (a full pass is ~an hour and is not a
# release gate — see the comment in validate.sh); it only asks a cheap
# question every run of this gate can afford: is a probe sitting on the real
# machine or in this checkout right now.
#
# The root list is never retyped here — it comes straight from
# test-bus-mutants.sh via `--list-probe-roots`, a read-only mode that touches
# no lock and builds no mutant. Two lists of the same roots drifting apart is
# exactly how the leak this guard exists for happened.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# bash 3.2 (macOS default) has no `mapfile`, so the roots are read one line at
# a time rather than into an array in one shot.
root_count=0
found=""
while IFS= read -r root; do
  root_count=$((root_count + 1))
  [ -d "$root" ] || continue
  while IFS= read -r hit; do
    found="$found
  $hit"
  done < <(find "$root" -name "RDA-MUTANT-PROBE*" 2>/dev/null)
done < <(bash "$ROOT/test/test-bus-mutants.sh" --list-probe-roots)
[ "$root_count" -gt 0 ] || { echo "FAIL: test-bus-mutants.sh --list-probe-roots printed nothing — the source of truth for the sweep roots is broken" >&2; exit 1; }

if [ -n "$found" ]; then
  echo "FAIL: RDA-MUTANT-PROBE artifact(s) found on the real machine or in this checkout:$found" >&2
  echo "  test-bus-mutants.sh leaked a probe — every mutant run must sandbox HOME (and ROOT," >&2
  echo "  which is already sandboxed by construction) and sweep with a trap. Confirm each path" >&2
  echo "  is exactly RDA-MUTANT-PROBE* junk, then delete it." >&2
  exit 1
fi

echo "PASS: test-bus-mutant-probes.sh — no RDA-MUTANT-PROBE artifact under any swept root ($root_count roots checked)"
