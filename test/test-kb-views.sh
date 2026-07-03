#!/usr/bin/env bash
# test/test-kb-views.sh — real assertions for the read-only "see everything" kb
# commands (history/archive/plans/plan/sched). Separate file from
# test/test-factory-kb.sh on purpose: that file is owned by another
# workstream touching factory/ in parallel — this one only exercises the new
# detail/ops views added on top of kb.sh and must not collide with it.
# history/archive use temp fixtures via RDA_KANBAN (never the real board).
# plans/plan read the real docs/ tree (no env indirection in kb.sh for that)
# so assertions there are structural, not content-pinned. sched is
# environment-dependent (launchctl/plist/factory dir vary by machine) — it is
# only asserted to exit 0 and never crash.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
section() { printf "\n=== %s ===\n" "$1"; }
ok()      { printf "  ok: %s\n" "$1"; }
err()     { printf "  FAIL: %s\n" "$1"; FAIL=1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
section "kb history: individual done/ cards appear with title + verified date"
KB="$TMP/kanban"
mkdir -p "$KB/todo" "$KB/doing" "$KB/done"
cat > "$KB/done/probe-a.md" <<'EOF'
---
title: Probe A card
repo: roberdan-os
dod: "real dod"
acceptance: "real acceptance"
status: done
verified_by: thor
verified_evidence: "test evidence A"
verified_at: 2026-07-02
---
body
EOF
out="$(RDA_KANBAN="$KB" bash kanban/kb.sh history 2>&1)"
echo "$out" | grep -q '\[probe-a\] (roberdan-os) Probe A card (verified 2026-07-02)' \
  && ok "history lists the individual done card with id/repo/title/verified date" \
  || err "history did not list probe-a as expected — got: $out"

section "kb history: a done card with no repo: (legacy) degrades gracefully instead of crashing"
cat > "$KB/done/probe-legacy.md" <<'EOF'
---
title: Legacy probe card (no repo field)
dod: "real dod"
acceptance: "real acceptance"
status: done
verified_by: thor
verified_evidence: "test evidence legacy"
verified_at: 2026-07-01
---
body
EOF
out="$(RDA_KANBAN="$KB" bash kanban/kb.sh history 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q '\[probe-legacy\] (—) Legacy probe card (no repo field) (verified 2026-07-01)'; then
  ok "history degrades a missing repo: to (—) instead of crashing"
else
  err "history did not degrade gracefully on a card with no repo: — got: $out"
fi

section "kb history: archived goal rows are extracted and grouped by archive file"
cat > "$KB/done/_archive-2026-06-01.md" <<'EOF'
# Ledger Archive — Done / Verified

## 2026-06-01 batch (2/2 verified)

| # | Goal | Status | Evidence |
|---|---|---|---|
| 1 | First archived goal | verified | evidence one |
| 2 | Second archived goal | verified | evidence two |
EOF
out="$(RDA_KANBAN="$KB" bash kanban/kb.sh history 2>&1)"
if echo "$out" | grep -q -- "-- _archive-2026-06-01.md --" \
  && echo "$out" | grep -q '1\. First archived goal \[verified\] — evidence one' \
  && echo "$out" | grep -q '2\. Second archived goal \[verified\] — evidence two'; then
  ok "history extracts numbered archive goal rows grouped under their archive file"
else
  err "history did not extract archive rows as expected — got: $out"
fi

section "kb history: empty board (no done cards, no archives) does not crash"
EMPTY="$TMP/empty-kanban"
mkdir -p "$EMPTY/todo" "$EMPTY/doing" "$EMPTY/done"
if RDA_KANBAN="$EMPTY" bash kanban/kb.sh history >/dev/null 2>&1; then
  ok "kb history on an empty board exits 0"
else
  err "kb history on an empty board crashed (exit != 0)"
fi

# ---------------------------------------------------------------------------
section "kb list/todo: shows [id] (repo) title so scope + objective are visible at a glance"
LKB="$TMP/list-kanban"
mkdir -p "$LKB/todo" "$LKB/doing" "$LKB/done"
cat > "$LKB/todo/list-probe.md" <<'EOF'
---
title: List probe objective
repo: convergio
dod: "real dod"
acceptance: "real acceptance"
status: todo
created: 2026-07-01
---
body
EOF
out="$(RDA_KANBAN="$LKB" bash kanban/kb.sh list 2>&1)"
echo "$out" | grep -q '\[list-probe\] (convergio) List probe objective' \
  && ok "kb list shows [id] (repo) title" \
  || err "kb list did not show repo+title as expected — got: $out"

section "kb todo: a card with no repo: (legacy) degrades to (—) instead of crashing"
cat > "$LKB/todo/list-legacy.md" <<'EOF'
---
title: Legacy list card
dod: "real dod"
acceptance: "real acceptance"
status: todo
created: 2026-07-01
---
body
EOF
out="$(RDA_KANBAN="$LKB" bash kanban/kb.sh todo 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q '\[list-legacy\] (—) Legacy list card'; then
  ok "kb todo degrades a missing repo: to (—) instead of crashing"
else
  err "kb todo did not degrade gracefully on a card with no repo: — got: $out"
fi

# ---------------------------------------------------------------------------
section "kb archive: no-arg mode lists archive files with goal counts"
out="$(RDA_KANBAN="$KB" bash kanban/kb.sh archive 2>&1)"
echo "$out" | grep -q '_archive-2026-06-01.md.*2 goal(s)' \
  && ok "kb archive lists _archive-2026-06-01.md with count 2" \
  || err "kb archive did not report the right goal count — got: $out"

section "kb archive <date>: prints the matching archive file"
out="$(RDA_KANBAN="$KB" bash kanban/kb.sh archive 2026-06-01 2>&1)"
echo "$out" | grep -q 'First archived goal' \
  && ok "kb archive 2026-06-01 cats the matching archive" \
  || err "kb archive 2026-06-01 did not print expected content — got: $out"

section "kb archive <date>: unknown date reports an error instead of dying silently"
if RDA_KANBAN="$KB" bash kanban/kb.sh archive 1999-01-01 >/dev/null 2>&1; then
  err "kb archive 1999-01-01 (nonexistent) was ACCEPTED — should exit non-zero"
else
  ok "kb archive on an unknown date exits non-zero with a clear message"
fi

section "kb archive: no archives at all does not crash"
if RDA_KANBAN="$EMPTY" bash kanban/kb.sh archive >/dev/null 2>&1; then
  ok "kb archive with zero archive files exits 0"
else
  err "kb archive with zero archive files crashed"
fi

# ---------------------------------------------------------------------------
section "kb plans: lists at least one real plan with an H1 and a line count"
out="$(bash kanban/kb.sh plans 2>&1)"
if echo "$out" | grep -q '^PLANS:' && echo "$out" | grep -qE 'docs/(archive/)?plan-.*\.md +[0-9]+ +lines'; then
  ok "kb plans lists docs/plan-*.md with line counts"
else
  err "kb plans did not produce the expected structure — got: $out"
fi

section "kb plan <match>: a real, known plan filename fragment resolves to one file"
if bash kanban/kb.sh plan tool-independence >/dev/null 2>&1; then
  ok "kb plan tool-independence resolves and prints (exit 0)"
else
  err "kb plan tool-independence failed to resolve a real plan file"
fi

section "kb plan <match>: no match reports an error instead of dying silently"
if bash kanban/kb.sh plan zzz-does-not-exist-zzz >/dev/null 2>&1; then
  err "kb plan on a nonexistent match was ACCEPTED — should exit non-zero"
else
  ok "kb plan on a nonexistent match exits non-zero"
fi

# ---------------------------------------------------------------------------
section "kb sched: environment-dependent — only asserted to never crash"
if bash kanban/kb.sh sched >/dev/null 2>&1; then
  ok "kb sched exits 0 on this machine"
else
  err "kb sched crashed (exit != 0) — should degrade to n/a per-section, never fail"
fi

# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo; echo "test-kb-views: ✅ ALL GREEN"; exit 0
else
  echo; echo "test-kb-views: ❌ FAIL (see above)"; exit 1
fi
