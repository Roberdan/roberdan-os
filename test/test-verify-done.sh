#!/usr/bin/env bash
# A release merge must expose VERSION changes without hiding genuine warnings.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git -C "$TMP" init -q -b main
git -C "$TMP" config user.email test@example.com
git -C "$TMP" config user.name "Release check"
printf '1.0.0\n' > "$TMP/VERSION"
git -C "$TMP" add VERSION
git -C "$TMP" commit -qm initial
git -C "$TMP" checkout -qb release-test
printf '1.1.0\n' > "$TMP/VERSION"
git -C "$TMP" commit -qam version
git -C "$TMP" checkout -q main
git -C "$TMP" merge --no-ff -qm release release-test

out="$(cd "$TMP" && bash "$ROOT/hooks/verify-done.sh" 2>&1)"
[ -z "$out" ] || { printf 'FAIL: valid release merge warned: %s\n' "$out" >&2; exit 1; }

printf 'change\n' > "$TMP/feature.txt"
git -C "$TMP" add feature.txt
git -C "$TMP" commit -qm feature
out="$(cd "$TMP" && bash "$ROOT/hooks/verify-done.sh" 2>&1)"
[[ "$out" == *"without a VERSION/CHANGELOG update"* ]] ||
  { echo 'FAIL: missing-version warning was suppressed' >&2; exit 1; }
printf 'unsaved\n' >> "$TMP/feature.txt"
out="$(cd "$TMP" && bash "$ROOT/hooks/verify-done.sh" 2>&1)"
[[ "$out" == *"uncommitted changes present"* ]] ||
  { echo 'FAIL: uncommitted-change warning was suppressed' >&2; exit 1; }
echo 'test-verify-done: PASS (release merge accepted, real warnings preserved)'
