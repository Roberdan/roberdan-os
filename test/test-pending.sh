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
#    NOTE: use here-strings (<<<), not `printf | grep -q`. Under `set -o pipefail`, grep -q exits
#    the instant it matches, SIGPIPE-killing the producer — the pipeline's exit status becomes the
#    producer's 141 (broken pipe), not grep's 0, so a real match still triggers `|| fail`. This is
#    deterministic (reproduces every run on this harness), not flaky. A here-string has no pipe, so
#    no SIGPIPE race is possible.
report="$(bash "$KB" pending)"
grep -q "first pending thing" <<<"$report" || fail "todo card missing from report"
grep -q "a real learning awaiting approval" <<<"$report" || fail "unapproved learning missing"
grep -q "already approved, not pending" <<<"$report" && fail "approved learning must NOT appear"
grep -qE "^PENDING: $((base + 3))\$" <<<"$report" || fail "report must end with PENDING: $((base + 3))"

# 3) removing the test cards returns the count to baseline.
rm -f "$RDA_KANBAN/todo/"*.md "$RDA_QUARANTINE/"*.md
[ "$(bash "$KB" pending --count)" = "$base" ] || fail "removing test cards must return count to base ($base)"

# 4) digest writes its file and exits 0 (whatever the real board's pending total is).
bash "$DIGEST" --always >/dev/null 2>&1 || fail "digest must exit 0"
[ -s "$RDA_HOME/pending-digest.txt" ] || fail "digest did not write its file"
grep -qE '^PENDING: [0-9]+$' "$RDA_HOME/pending-digest.txt" || fail "digest file missing PENDING total"

# 5) PR bot-filter: the exact regex _pending uses must drop bot authors, keep humans.
#    (Full gh integration is best-effort/network — this locks the filter logic that decides
#     "which PRs need Roberto", the part thor flagged as the judgment call.)
pr_json='[{"number":99,"title":"human PR","author":{"login":"Roberdan"}},{"number":100,"title":"bump","author":{"login":"dependabot[bot]"}},{"number":101,"title":"bump2","author":{"login":"renovate[bot]"}},{"number":102,"title":"ci","author":{"login":"github-actions[bot]"}}]'
bot_re="$(bash "$KB" bot-filter-regex)"
kept="$(printf '%s' "$pr_json" | jq -r --arg re "$bot_re" '.[]|select((.author.login // "")|test($re)|not)|.number' | tr '\n' ' ' | sed 's/ $//')"
[ "$kept" = "99" ] || fail "PR bot-filter wrong: expected only human #99, got '$kept'"

# 6) Pending PR scan must include registry repos even when they have no kanban/ directory.
ext_repo="$TMP/external-no-board"
mkdir -p "$ext_repo"
git -C "$ext_repo" init -q
printf '%s\n' "$ext_repo" >> "$RDA_KANBAN_REGISTRY"
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "list" ]; then
  [ "$(basename "$PWD")" = "external-no-board" ] && printf '777\tregistry-only repo PR\n'
  exit 0
fi
exit 1
EOF
chmod +x "$TMP/bin/gh"
report_with_registry_pr="$(PATH="$TMP/bin:$PATH" bash "$KB" pending)"
grep -q "external-no-board#777 — registry-only repo PR" <<<"$report_with_registry_pr" \
  || fail "pending did not include PRs from registry repo without kanban/"

echo "PASS: approval inbox (kb pending, --count, approved-excluded, digest writes + exits 0, PR bot-filter + registry-only PR scan)"
