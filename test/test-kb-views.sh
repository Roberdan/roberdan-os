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
if [ "$rc" -eq 0 ] && echo "$out" | grep -q '\[probe-legacy\] (-) Legacy probe card (no repo field) (verified 2026-07-01)'; then
  ok "history degrades a missing repo: to (-) instead of crashing"
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

section "kb todo: a card with no repo: (legacy) degrades to (-) instead of crashing"
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
if [ "$rc" -eq 0 ] && echo "$out" | grep -q '\[list-legacy\] (-) Legacy list card'; then
  ok "kb todo degrades a missing repo: to (-) instead of crashing"
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
section "kb repo <name>: per-repo dashboard (git + PRs + cards)"
# Isolated repo with a board + one card per column; assert the view groups them.
_rp="$TMP/repoview"; mkdir -p "$_rp/kanban"/{todo,doing,done}
( cd "$_rp" && git init -q && git config user.email t@example.com && git config user.name t \
  && git commit -q --allow-empty -m "init" )
printf -- '---\ntitle: a todo thing\nrepo: repoview\nstatus: todo\n---\n' > "$_rp/kanban/todo/T-1.md"
printf -- '---\ntitle: an in-progress thing\nrepo: repoview\nstatus: doing\n---\n' > "$_rp/kanban/doing/D-1.md"
printf -- '---\ntitle: a finished thing\nrepo: repoview\nstatus: done\n---\n' > "$_rp/kanban/done/F-1.md"
# _repo_path falls back to ~/GitHub/<name>; point HOME so ~/GitHub/repoview resolves to our fixture
: > "$TMP/reg-empty"; mkdir -p "$TMP/GitHub" && ln -sf "$_rp" "$TMP/GitHub/repoview" 2>/dev/null
_rv="$(HOME="$TMP" RDA_KANBAN_REGISTRY="$TMP/reg-empty" bash kanban/kb.sh repo repoview 2>&1 || true)"
if printf '%s' "$_rv" | grep -q "an in-progress thing" \
   && printf '%s' "$_rv" | grep -q "a todo thing" \
   && printf '%s' "$_rv" | grep -q "a finished thing" \
   && printf '%s' "$_rv" | grep -qi "git"; then
  ok "kb repo groups git + doing/todo/done cards"
else
  err "kb repo view missing a section or card (got: $(printf '%s' "$_rv" | tr '\n' '¶'))"
fi

# ---------------------------------------------------------------------------
section "kb dash: local times + elapsed for DOING, and NO fabricated numbers for old cards"
_DB="$TMP/dashboard"; mkdir -p "$_DB"/{todo,doing,done}
# A card started under today's kb (epoch stamp) and one closed long before this command existed
# (date-only stamps, no worktree, no spend) — the two cases that must never look alike.
{ printf -- '---\ntitle: nuova con orario\nrepo: roberdan-os\nstatus: doing\n---\n'
  printf 'started_at: 2026-07-28 08:00:00 CEST\nstarted_epoch: %s\n' "$(( $(date +%s) - 7200 ))"
} > "$_DB/doing/DASH-NEW.md"
printf -- '---\ntitle: vecchia senza orario\nrepo: roberdan-os\nstatus: done\n---\napproved_at: 2026-01-01\nverified_evidence: commit deadbeef1234; PR #42; 148 passed\nverified_at: 2026-01-02\n' \
  > "$_DB/done/DASH-OLD.md"
_dash_out="$(HOME="$TMP" bash kanban/dash.sh "$_DB" 2>&1 || true)"
if printf '%s' "$_dash_out" | grep -q 'gira da 2h'; then
  ok "dash: a DOING card shows how long it has been running"
else
  err "dash: elapsed missing (got: $(printf '%s' "$_dash_out" | tr '\n' '¶'))"
fi
if printf '%s' "$_dash_out" | grep -q 'solo data'; then
  ok "dash: a date-only card says so instead of inventing a time"
else
  err "dash: date-only card did not degrade honestly"
fi
# The regression this pins: a closed card with no recorded spend prints "-", never a number
# recomputed over its window — that would bill it for every other card open at the same time.
if printf '%s' "$_dash_out" | grep -q 'non misurata'; then
  ok "dash: an old closed card reports no spend rather than a plausible wrong one"
else
  err "dash: old closed card printed a spend it cannot know"
fi
if printf '%s' "$_dash_out" | grep -q '#42'; then
  ok "dash: PR ref extracted from the evidence the card already carries"
else
  err "dash: PR ref not surfaced"
fi

section "kb dash makes NO network call (gh stub with a canary)"
# Same technique as test-bus.sh: the canary lives OUTSIDE the tree the command is told about,
# so a stub firing anywhere is visible. gh is the only network-shaped dependency kb has.
_CAN="$(mktemp -d)"; _BIN="$TMP/stubbin"; mkdir -p "$_BIN"
printf '#!/usr/bin/env bash\ntouch "%s/gh-was-called"\nexit 0\n' "$_CAN" > "$_BIN/gh"
chmod +x "$_BIN/gh"
PATH="$_BIN:$PATH" HOME="$TMP" bash kanban/dash.sh "$_DB" >/dev/null 2>&1 || true
if [ -e "$_CAN/gh-was-called" ]; then
  err "dash called gh — the dashboard must stay offline (PR refs come from the card)"
else
  ok "dash never invoked gh"
fi
rm -rf "$_CAN"

section "kb counts: the same three numbers the box prints, without rendering the box"
# WHY THIS IS PINNED. `kb counts` exists so the SessionStart hook stops paying a full board
# render (stat on every done card, newest-ten sort, legend) for three integers. That is only
# safe while the two agree: a human reads the box, the hook prints the counter line, and if
# they drift the session is told a number nobody can see. So the assertion is EQUALITY with
# kb view's own header, never a hardcoded triple — a fixture-pinned number would still pass
# on the day _board changes what it counts, which is exactly the failure worth catching.
_CB="$TMP/counts"; mkdir -p "$_CB"/{todo,doing,done}
printf -- '---\ntitle: t1\nrepo: r\nstatus: todo\n---\n'  > "$_CB/todo/C-T1.md"
printf -- '---\ntitle: t2\nrepo: r\nstatus: todo\n---\n'  > "$_CB/todo/C-T2.md"
printf -- '---\ntitle: d1\nrepo: r\nstatus: doing\n---\n' > "$_CB/doing/C-D1.md"
printf -- '---\ntitle: n1\nrepo: r\nstatus: done\n---\n'  > "$_CB/done/C-N1.md"
printf -- '---\ntitle: n2\nrepo: r\nstatus: done\n---\n'  > "$_CB/done/C-N2.md"
printf -- '---\ntitle: n3\nrepo: r\nstatus: done\n---\n'  > "$_CB/done/C-N3.md"
cat > "$_CB/done/_archive-2026-05-01.md" <<'EOF'
| # | Goal | Status | Evidence |
|---|---|---|---|
| 1 | archived one | verified | ev |
| 2 | archived two | verified | ev |
EOF
# Normalize both sides to the bare numbers: the box spaces its labels for a human, the
# counter line for a log. What must match is the NUMBERS, not the punctuation between them.
# stderr is dropped on purpose — RDA_KANBAN prints a legitimate "you are overriding this
# repo's board" warning here, and folding it into the parse would compare noise.
_nums() { grep -oE '\([0-9]+( \+[0-9]+ arch)?\)' | tr -cd '0-9\n' | paste -sd' ' -; }
_c_line="$(RDA_KANBAN="$_CB" bash kanban/kb.sh counts 2>/dev/null)"
_c_from_counts="$(printf '%s\n' "$_c_line" | _nums)"
_c_from_view="$(RDA_KANBAN="$_CB" bash kanban/kb.sh view 2>/dev/null | grep -m1 'TO DO (' | _nums)"
if [ -n "$_c_from_counts" ] && [ "$_c_from_counts" = "$_c_from_view" ]; then
  ok "kb counts agrees with the box kb view renders ($_c_line)"
else
  err "kb counts disagrees with kb view — counts='$_c_from_counts' view='$_c_from_view' line='$_c_line'"
fi
# The archive roll-up is counted, not silently dropped: DONE (3 +2 arch) on this fixture.
if printf '%s' "$_c_line" | grep -q 'DONE (3 +2 arch)'; then
  ok "kb counts reports archived goals alongside the live done count"
else
  err "kb counts lost the archive roll-up — got: $_c_line"
fi
# The hook reads this on a board with cards; an empty board must still print, not crash.
if _e="$(RDA_KANBAN="$EMPTY" bash kanban/kb.sh counts 2>&1)" && printf '%s' "$_e" | grep -q 'TO DO (0)'; then
  ok "kb counts on an empty board prints zeros instead of crashing"
else
  err "kb counts on an empty board misbehaved — got: ${_e:-<crash>}"
fi

section "the SessionStart hook asks for columns, never for the whole board"
# The regression this pins is a PERFORMANCE one that no output diff would show: reverting
# these two calls to `kb list`/`kb view` reproduces the same text and silently puts ~2.5 s
# back on every session start in every repo (measured 2026-07-30, 96 done cards).
if grep -qE '"\$HOME/\.local/bin/kb" (list|view)' hooks/context-inject.sh; then
  err "context-inject.sh calls kb list/view again — it renders the whole board to print 3 numbers"
else
  ok "context-inject.sh uses the cheap per-column commands"
fi
if grep -q '"\$HOME/\.local/bin/kb" doing' hooks/context-inject.sh \
   && grep -q '"\$HOME/\.local/bin/kb" counts' hooks/context-inject.sh; then
  ok "context-inject.sh asks kb for doing + counts"
else
  err "context-inject.sh no longer asks for doing + counts — the injected board block is broken"
fi

section "kb view stays lean (the SessionStart hook injects it into every session)"
_view_out="$(RDA_KANBAN="$_DB" bash kanban/kb.sh view 2>&1 || true)"
if printf '%s' "$_view_out" | grep -qE 'gira da|spesa'; then
  err "kb view grew dashboard detail — that is a token tax on every session in every repo"
else
  ok "kb view unchanged: board only, no dashboard blocks"
fi

# ---------------------------------------------------------------------------
section "one worktree per card: kb start creates it, kb finish demands it clean"
_WR="$TMP/GitHub/wtrepo"; mkdir -p "$_WR"
( cd "$_WR" && git init -q -b main && git config user.email t@example.com && git config user.name t \
  && echo seed > seed.txt && git add seed.txt && git commit -qm init ) >/dev/null 2>&1
_KB2="$TMP/kb2"; mkdir -p "$_KB2"/{todo,doing,done}
: > "$TMP/reg-empty2"
_kbrun() { env HOME="$TMP" RDA_KANBAN="$_KB2" RDA_KANBAN_REGISTRY="$TMP/reg-empty2" \
                RDA_WORKTREES="$TMP/wt" "$@" ; }
_kbrun RDA_KB_ID_BASE=WT-1 bash kanban/kb.sh add "card con worktree" --repo wtrepo "d" "a" >/dev/null 2>&1
_kbrun bash kanban/kb.sh start WT-1 --by roberto >/dev/null 2>&1
if [ -e "$TMP/wt/wtrepo/WT-1/seed.txt" ] && grep -q '^worktree: ' "$_KB2/doing/WT-1.md" 2>/dev/null; then
  ok "kb start created the card's worktree and wrote it on the card"
else
  err "kb start did not create/record the worktree"
fi
if grep -q '^started_epoch: ' "$_KB2/doing/WT-1.md" 2>/dev/null; then
  ok "kb start stamped a machine-readable start time"
else
  err "kb start did not stamp started_epoch — durations would be unknowable"
fi
echo "sporco" > "$TMP/wt/wtrepo/WT-1/dirty.txt"
if _kbrun bash kanban/kb.sh finish WT-1 --thor "kanban/dash.sh 148 passed" >/dev/null 2>&1; then
  err "kb finish closed a card whose worktree still had uncommitted work"
else
  ok "kb finish REFUSES while the card's worktree is dirty"
fi
if [ -e "$_KB2/doing/WT-1.md" ]; then
  ok "a refused finish leaves the card in doing, worktree intact"
else
  err "a refused finish still moved the card"
fi
rm -f "$TMP/wt/wtrepo/WT-1/dirty.txt"
if _kbrun bash kanban/kb.sh finish WT-1 --thor "kanban/dash.sh 148 passed" >/dev/null 2>&1; then
  ok "kb finish accepts a clean worktree"
else
  err "kb finish refused a clean worktree"
fi
if [ ! -d "$TMP/wt/wtrepo/WT-1" ] && grep -q '^worktree_removed_at: ' "$_KB2/done/WT-1.md" 2>/dev/null; then
  ok "closing the card removed its worktree and recorded it — nothing left behind"
else
  err "worktree survived the close (or was not recorded on the card)"
fi
# The escape hatch exists, costs a written reason, and is visible on the card.
_kbrun RDA_KB_ID_BASE=WT-2 bash kanban/kb.sh add "card tenuta aperta" --repo wtrepo "d" "a" >/dev/null 2>&1
_kbrun bash kanban/kb.sh start WT-2 --by roberto >/dev/null 2>&1
echo "sporco" > "$TMP/wt/wtrepo/WT-2/dirty.txt"
if _kbrun bash kanban/kb.sh finish WT-2 --thor "kanban/dash.sh 148 passed" --keep-worktree "review in corso" >/dev/null 2>&1 \
   && [ -d "$TMP/wt/wtrepo/WT-2" ] && grep -q 'worktree_kept_why' "$_KB2/done/WT-2.md" 2>/dev/null; then
  ok "--keep-worktree closes the card and writes the reason on it"
else
  err "--keep-worktree did not behave as declared"
fi
# A card that is not code work must still start — without a worktree, with the reason recorded.
_kbrun RDA_KB_ID_BASE=WT-3 bash kanban/kb.sh add "non-code" --repo personal "d" "a" >/dev/null 2>&1
_kbrun bash kanban/kb.sh start WT-3 --by roberto --no-worktree "decisione, niente codice" >/dev/null 2>&1
if [ -e "$_KB2/doing/WT-3.md" ] && grep -q 'worktree_none' "$_KB2/doing/WT-3.md" 2>/dev/null; then
  ok "--no-worktree starts the card and records why it has none"
else
  err "--no-worktree card did not start cleanly"
fi

# ---------------------------------------------------------------------------
section "kb migrate: recovers what is already on disk, invents nothing, writes only with --apply"
_MG="$TMP/migrate"; mkdir -p "$_MG"/{todo,doing,done}
# One card with an audit line (its start time IS on disk, just unparsed) and one without
# (nothing to recover — it must be reported, never backfilled with "now").
printf -- '---\ntitle: con audit\nrepo: roberdan-os\nstatus: doing\n---\nkb_start_audit: "at=2026-07-25T18:18:15Z by=roberto interactive=no"\n' \
  > "$_MG/doing/MG-1.md"
printf -- '---\ntitle: senza audit\nrepo: roberdan-os\nstatus: doing\n---\n' > "$_MG/doing/MG-2.md"
printf -- '---\ntitle: chiusa\nrepo: roberdan-os\nstatus: done\n---\n' > "$_MG/done/MG-3.md"
_before="$(cat "$_MG/doing/MG-1.md")"
RDA_KANBAN="$_MG" bash kanban/kb.sh migrate >/dev/null 2>&1
if [ "$_before" = "$(cat "$_MG/doing/MG-1.md")" ]; then
  ok "migrate without --apply writes nothing"
else
  err "migrate wrote to a card in dry-run mode"
fi
RDA_KANBAN="$_MG" bash kanban/kb.sh migrate --apply >/dev/null 2>&1
if grep -q '^started_epoch: 1785003495' "$_MG/doing/MG-1.md"; then
  ok "migrate --apply backfills the start time already recorded in the audit line"
else
  err "migrate did not recover the start time (got: $(grep started_epoch "$_MG/doing/MG-1.md" || echo none))"
fi
if grep -q 'started_epoch' "$_MG/doing/MG-2.md" 2>/dev/null; then
  err "migrate INVENTED a start time for a card that has none — the exact thing it must not do"
else
  ok "a card with nothing to recover is left alone, not backfilled with a fabricated time"
fi
if grep -qE 'started_epoch|worktree' "$_MG/done/MG-3.md" 2>/dev/null; then
  err "migrate touched done/ — that column is the append-only audit archive"
else
  ok "migrate never touches done/"
fi
# Attaching a worktree made by hand: accepted when it is real, refused when it is not.
if RDA_KANBAN="$_MG" bash kanban/kb.sh wt attach MG-2 "$TMP/GitHub/wtrepo" >/dev/null 2>&1 \
   && grep -q '^worktree: ' "$_MG/doing/MG-2.md"; then
  ok "kb wt attach records an existing worktree on the card"
else
  err "kb wt attach did not record a real worktree"
fi
if RDA_KANBAN="$_MG" bash kanban/kb.sh wt attach MG-1 "$TMP/not-a-worktree-at-all" >/dev/null 2>&1; then
  err "kb wt attach accepted a path that is not a worktree — kb finish would then refuse forever"
else
  ok "kb wt attach refuses a path that is not a git worktree"
fi

# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo; echo "test-kb-views: ✅ ALL GREEN"; exit 0
else
  echo; echo "test-kb-views: ❌ FAIL (see above)"; exit 1
fi
