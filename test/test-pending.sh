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

# DELTA-based: _pending correctly aggregates the REAL roberdan-os board too (via _board_roots,
# which always includes $ROOT — that's the right behavior for a user). So the test can't assume
# an absolute total; it measures the CHANGE when it adds isolated test cards. Baseline first,
# BEFORE creating any test card.
base="$(bash "$KB" pending --count)"

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

# 1) --count grows by exactly 3 (2 todo + 1 unapproved learning; the approved one is excluded).
count="$(bash "$KB" pending --count)"
[ "$count" = "$((base + 3))" ] || fail "expected base+3 ($((base + 3))), got '$count'"

# 2) full report lists the test cards + learning, excludes the approved one, ends with PENDING: base+3.
report="$(bash "$KB" pending)"
printf '%s\n' "$report" | grep -q "first pending thing" || fail "todo card missing from report"
printf '%s\n' "$report" | grep -q "a real learning awaiting approval" || fail "unapproved learning missing"
printf '%s\n' "$report" | grep -q "already approved, not pending" && fail "approved learning must NOT appear"
printf '%s\n' "$report" | grep -qE "^PENDING: $((base + 3))\$" || fail "report must end with PENDING: $((base + 3))"

# 3) removing the test cards returns the count to baseline.
rm -f "$RDA_KANBAN/todo/"*.md "$RDA_QUARANTINE/"*.md
[ "$(bash "$KB" pending --count)" = "$base" ] || fail "removing test cards must return count to base ($base)"

# 4) digest writes its file and exits 0 (whatever the real board's pending total is).
bash "$DIGEST" --always >/dev/null 2>&1 || fail "digest must exit 0"
[ -s "$RDA_HOME/pending-digest.txt" ] || fail "digest did not write its file"
grep -qE '^PENDING: [0-9]+$' "$RDA_HOME/pending-digest.txt" || fail "digest file missing PENDING total"

# 5) PR bot-filter: the exact jq expression _pending uses must drop bot authors, keep humans.
#    (Full gh integration is best-effort/network — this locks the filter logic that decides
#     "which PRs need Roberto", the part thor flagged as the judgment call.)
pr_json='[{"number":99,"title":"human PR","author":{"login":"Roberdan"}},{"number":100,"title":"bump","author":{"login":"dependabot[bot]"}},{"number":101,"title":"bump2","author":{"login":"renovate[bot]"}},{"number":102,"title":"ci","author":{"login":"github-actions[bot]"}}]'
kept="$(printf '%s' "$pr_json" | jq -r '.[]|select((.author.login // "")|test("dependabot|renovate|github-actions|\\[bot\\]|-bot$")|not)|.number' | tr '\n' ' ' | sed 's/ $//')"
[ "$kept" = "99" ] || fail "PR bot-filter wrong: expected only human #99, got '$kept'"

echo "PASS: approval inbox (kb pending, --count, approved-excluded, digest writes + exits 0, PR bot-filter)"
