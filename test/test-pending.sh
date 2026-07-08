#!/usr/bin/env bash
# test-pending.sh — the approval inbox (kb pending + --count + digest) aggregates what's
# waiting on Roberto, counts it correctly, and the digest writes its file without failing.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KB="$ROOT/kanban/kb.sh"
DIGEST="$ROOT/bin/pending-digest.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# Isolated board + quarantine + home — never touches the real ones.
export RDA_HOME="$TMP/home"
export RDA_KANBAN="$TMP/board"
export RDA_QUARANTINE="$TMP/quar"
export RDA_KANBAN_REGISTRY="$TMP/registry"   # empty → only the local board
mkdir -p "$RDA_KANBAN"/{todo,doing,done} "$RDA_QUARANTINE" "$RDA_HOME"
: > "$RDA_KANBAN_REGISTRY"

# 2 todo cards + 1 unapproved learning + 1 already-approved learning (must NOT count).
cat > "$RDA_KANBAN/todo/T-1.md" <<'EOF'
---
title: first pending thing
repo: roberdan-os
status: todo
---
EOF
cp "$RDA_KANBAN/todo/T-1.md" "$RDA_KANBAN/todo/T-2.md"
printf -- '---\nclass: correction\napproved: false\n---\n\n## Signal\na real learning awaiting approval\n' > "$RDA_QUARANTINE/L-1.md"
printf -- '---\nclass: decision\napproved: true\n---\n\n## Signal\nalready approved, not pending\n' > "$RDA_QUARANTINE/L-2.md"

# 1) --count = 3 (2 todo + 1 unapproved learning; the approved one is excluded).
count="$(bash "$KB" pending --count)"
[ "$count" = "3" ] || fail "expected count 3 (2 todo + 1 unapproved learning), got '$count'"

# 2) full report lists the cards + learning and ends with PENDING: 3.
report="$(bash "$KB" pending)"
printf '%s\n' "$report" | grep -q "first pending thing" || fail "todo card missing from report"
printf '%s\n' "$report" | grep -q "a real learning awaiting approval" || fail "unapproved learning missing"
printf '%s\n' "$report" | grep -q "already approved, not pending" && fail "approved learning must NOT appear"
printf '%s\n' "$report" | grep -qE '^PENDING: 3$' || fail "report must end with PENDING: 3"

# 3) empty board → count 0.
rm -f "$RDA_KANBAN/todo/"*.md "$RDA_QUARANTINE/"*.md
[ "$(bash "$KB" pending --count)" = "0" ] || fail "empty board must count 0"

# 4) digest writes its file and exits 0 even with nothing pending.
bash "$DIGEST" --always >/dev/null 2>&1 || fail "digest must exit 0"
[ -s "$RDA_HOME/pending-digest.txt" ] || fail "digest did not write its file"
grep -qE '^PENDING: 0$' "$RDA_HOME/pending-digest.txt" || fail "digest file missing PENDING total"

echo "PASS: approval inbox (kb pending, --count, approved-excluded, digest writes + exits 0)"
