#!/usr/bin/env bash
# test/test-federated-kb.sh — real assertions for the federated kanban + the
# dormant restricted multi-CLI dispatcher. Center is a HOSTILE STUB (a script
# that actively attempts every forbidden action): a happy-path test proves
# nothing about gates. See docs/plan-2026-07-05-federated-kanban-multi-cli.md §6.
#
# Every fixture uses temp dirs via RDA_KANBAN / RDA_KANBAN_REGISTRY / RDA_HOME /
# RDA_LOCKS — never the real board, registry, locks, or any external repo.
# No real external CLI and no network: `validate.sh` stays green offline.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
section() { printf "\n=== %s ===\n" "$1"; }
ok()      { printf "  ok: %s\n" "$1"; }
err()     { printf "  FAIL: %s\n" "$1"; FAIL=1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

KB="kanban/kb.sh"

# make a minimal privacy-initialized-looking repo board with a card
mk_board() {  # $1=root  $2=id  $3=repo  $4=title  [$5=col]
  local root="$1" id="$2" repo="$3" title="$4" col="${5:-todo}"
  mkdir -p "$root/kanban/todo" "$root/kanban/doing" "$root/kanban/done" "$root/handoff"
  cat > "$root/kanban/$col/$id.md" <<EOF
---
title: $title
repo: $repo
dod: "d"
acceptance: "a"
status: $col
created: 2026-07-05
---
body
EOF
}

# =====================================================================
# PHASE 1 — federation read-path (cwd-scoping, kb all, kb handoff, registry)
# =====================================================================

section "phase1: registry parsing degrades to empty (no registry file) — kb all does not crash"
REG="$TMP/no-such-registry"
out="$(RDA_KANBAN_REGISTRY="$REG" bash "$KB" all 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q 'AGGREGATED BOARD'; then
  ok "kb all with an absent registry exits 0 and prints the aggregated header"
else
  err "kb all crashed or misbehaved on an absent registry (rc=$rc) — got: $out"
fi

section "phase1: kb all aggregates cards from every registered board, each tagged with its repo"
R1="$TMP/repoAlpha"; R2="$TMP/repoBeta"
mk_board "$R1" 260705-100000 alpha "Alpha objective" todo
mk_board "$R2" 260705-100001 beta  "Beta objective"  doing
REG="$TMP/registry"; printf '%s\n%s\n' "$R1" "$R2" > "$REG"
out="$(RDA_KANBAN_REGISTRY="$REG" bash "$KB" all 2>&1)"
if echo "$out" | grep -q '\[260705-100000\] (alpha) Alpha objective' \
  && echo "$out" | grep -q '\[260705-100001\] (beta) Beta objective'; then
  ok "kb all shows cards from both registered boards, tagged with repo:"
else
  err "kb all did not aggregate both boards — got: $out"
fi

section "phase1: kb g is an alias for kb all"
out="$(RDA_KANBAN_REGISTRY="$REG" bash "$KB" g 2>&1)"
echo "$out" | grep -q '\[260705-100000\] (alpha) Alpha objective' \
  && ok "kb g aggregates like kb all" \
  || err "kb g did not behave as kb all — got: $out"

section "phase1: same bare id in two different repos both appear (per-repo id, @rex #2)"
R3="$TMP/repoGamma"; R4="$TMP/repoDelta"
mk_board "$R3" 260705-200000 gamma "Gamma card" todo
mk_board "$R4" 260705-200000 delta "Delta card" todo   # SAME id, different repo
REG2="$TMP/registry2"; printf '%s\n%s\n' "$R3" "$R4" > "$REG2"
out="$(RDA_KANBAN_REGISTRY="$REG2" bash "$KB" all 2>&1)"
if echo "$out" | grep -q '(gamma) Gamma card' && echo "$out" | grep -q '(delta) Delta card'; then
  ok "a bare id shared by two repos renders both, disambiguated by repo:"
else
  err "same-id-different-repo was not rendered independently — got: $out"
fi

section "phase1: RDA_KANBAN override still wins (existing tests/fixtures unaffected)"
OKB="$TMP/override/kanban"; mkdir -p "$OKB/todo" "$OKB/doing" "$OKB/done"
cat > "$OKB/todo/260705-300000.md" <<'EOF'
---
title: Override-scoped card
repo: roberdan-os
dod: "d"
acceptance: "a"
status: todo
created: 2026-07-05
---
EOF
out="$(RDA_KANBAN="$OKB" bash "$KB" list 2>&1)"
echo "$out" | grep -q '\[260705-300000\] (roberdan-os) Override-scoped card' \
  && ok "RDA_KANBAN still forces the board (resolution order: env wins)" \
  || err "RDA_KANBAN override was not honored — got: $out"

section "phase1: kb handoff (in a repo, via RDA_KANBAN root) shows that repo's latest.md"
HR="$TMP/handoffRepo"; mkdir -p "$HR/kanban/todo" "$HR/kanban/doing" "$HR/kanban/done" "$HR/handoff"
echo "ALPHA-HANDOFF-STATE" > "$HR/handoff/latest.md"
out="$(RDA_KANBAN="$HR/kanban" bash "$KB" handoff 2>&1)"
echo "$out" | grep -q 'ALPHA-HANDOFF-STATE' \
  && ok "kb handoff prints the resolved repo's handoff/latest.md" \
  || err "kb handoff did not show the repo's latest.md — got: $out"

section "phase1: kb handoff (aggregate, outside a repo) concatenates registered repos newest-first"
HA="$TMP/hA"; HB="$TMP/hB"
mkdir -p "$HA/kanban/todo" "$HA/handoff" "$HB/kanban/todo" "$HB/handoff"
echo "OLDER-HANDOFF" > "$HA/handoff/latest.md"
echo "NEWER-HANDOFF" > "$HB/handoff/latest.md"
# ensure HB is newer than HA
touch -t 202607050000 "$HA/handoff/latest.md"
touch -t 202607051200 "$HB/handoff/latest.md"
REG3="$TMP/registry3"; printf '%s\n%s\n' "$HA" "$HB" > "$REG3"
# run from a NON-repo cwd so KB_MATCHED=0 -> aggregate
out="$(cd "$TMP" && RDA_KANBAN_REGISTRY="$REG3" bash "$ROOT/$KB" handoff 2>&1)"
if echo "$out" | grep -q 'NEWER-HANDOFF' && echo "$out" | grep -q 'OLDER-HANDOFF'; then
  newer_line=$(echo "$out" | grep -n 'NEWER-HANDOFF' | head -1 | cut -d: -f1)
  older_line=$(echo "$out" | grep -n 'OLDER-HANDOFF' | head -1 | cut -d: -f1)
  if [ "$newer_line" -lt "$older_line" ]; then
    ok "aggregated handoff concatenates registered repos newest-first"
  else
    err "aggregated handoff order was not newest-first — got: $out"
  fi
else
  err "aggregated handoff did not include both repos — got: $out"
fi

# =====================================================================
# PHASE 2 — kb init + per-repo privacy
# =====================================================================

mk_gitrepo() {  # $1=root
  local root="$1"
  mkdir -p "$root"
  git -C "$root" init -q
  git -C "$root" config user.email "t@example.com"
  git -C "$root" config user.name "Test"
  git -C "$root" config commit.gpgsign false
}

section "phase2: kb init scaffolds gitignore + pre-commit hook + registry entry"
GR="$TMP/initRepo"; mk_gitrepo "$GR"
GR="$(cd "$GR" && pwd -P)"   # canonicalize (git --show-toplevel resolves symlinks; registry stores the physical path)
REGI="$TMP/reg-init"
out="$(RDA_KANBAN_REGISTRY="$REGI" bash "$KB" init "$GR" 2>&1)"; rc=$?
gi_ok=0; git -C "$GR" check-ignore kanban/todo/x.md >/dev/null 2>&1 && gi_ok=1
hook_ok=0; [ -f "$GR/.git/hooks/pre-commit" ] && grep -q 'leak-check' "$GR/.git/hooks/pre-commit" && hook_ok=1
reg_ok=0; grep -qxF "$GR" "$REGI" 2>/dev/null && reg_ok=1
if [ "$rc" -eq 0 ] && [ "$gi_ok" -eq 1 ] && [ "$hook_ok" -eq 1 ] && [ "$reg_ok" -eq 1 ]; then
  ok "kb init: card paths gitignored + leak-check hook installed + repo registered"
else
  err "kb init incomplete (rc=$rc gitignore=$gi_ok hook=$hook_ok registry=$reg_ok) — got: $out"
fi

section "phase2: kb init is idempotent (re-run adds no duplicate gitignore/registry lines)"
RDA_KANBAN_REGISTRY="$REGI" bash "$KB" init "$GR" >/dev/null 2>&1; rc=$?
reg_count="$(grep -cxF "$GR" "$REGI" 2>/dev/null || echo 0)"
gi_count="$(grep -cxF 'kanban/todo/' "$GR/.gitignore" 2>/dev/null || echo 0)"
if [ "$rc" -eq 0 ] && [ "$reg_count" -eq 1 ] && [ "$gi_count" -eq 1 ]; then
  ok "kb init re-run is idempotent (registry x$reg_count, gitignore line x$gi_count)"
else
  err "kb init not idempotent (rc=$rc registry=$reg_count gitignore=$gi_count)"
fi

section "phase2: kb init de-tracks already-committed card content AND flags local history"
DR="$TMP/detrackRepo"; mk_gitrepo "$DR"
mkdir -p "$DR/kanban/todo"
cat > "$DR/kanban/todo/260705-999999.md" <<'EOF'
---
title: Committed card that must be de-tracked
repo: detrack
dod: "d"
acceptance: "a"
status: todo
created: 2026-07-05
---
EOF
git -C "$DR" add -f kanban/todo/260705-999999.md >/dev/null 2>&1
git -C "$DR" commit -q -m "accidentally committed a card" --no-verify
out="$(RDA_KANBAN_REGISTRY="$TMP/reg-dt" bash "$KB" init "$DR" 2>&1)"; rc=$?
still_tracked="$(git -C "$DR" ls-files kanban/todo/ 2>/dev/null)"
wc_kept=0; [ -f "$DR/kanban/todo/260705-999999.md" ] && wc_kept=1
warned=0; echo "$out" | grep -q 'LOCAL-ONLY' && warned=1
if [ "$rc" -eq 0 ] && [ -z "$still_tracked" ] && [ "$wc_kept" -eq 1 ] && [ "$warned" -eq 1 ]; then
  ok "de-tracked from index (ls-files empty), working copy kept, local-history warned (not silent)"
else
  err "de-track/history-flag failed (rc=$rc tracked='$still_tracked' wc=$wc_kept warned=$warned) — got: $out"
fi

section "phase2: kb init REFUSES when card content is in PUSHED history (human gate #4)"
PR="$TMP/pushedRepo"; mk_gitrepo "$PR"
BARE="$TMP/pushedRepo.git"; git init -q --bare "$BARE"
mkdir -p "$PR/kanban/todo"; printf 'card body\n' > "$PR/kanban/todo/260705-888888.md"
git -C "$PR" add -f kanban/todo/260705-888888.md >/dev/null 2>&1
git -C "$PR" commit -q -m "card in pushed history" --no-verify
br="$(git -C "$PR" rev-parse --abbrev-ref HEAD)"
git -C "$PR" remote add origin "$BARE"
git -C "$PR" push -q origin "$br" >/dev/null 2>&1
out="$(RDA_KANBAN_REGISTRY="$TMP/reg-pushed" bash "$KB" init "$PR" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q 'PUSHED history'; then
  ok "kb init refuses (non-zero) on card content in pushed history, escalating to a human"
else
  err "kb init did NOT refuse on pushed card history (rc=$rc) — got: $out"
fi

section "phase2: kb init FLAGS a tracked handoff/latest.md instead of silently de-tracking it (§5 note)"
HRR="$TMP/handoffTrackedRepo"; mk_gitrepo "$HRR"
mkdir -p "$HRR/handoff"; echo "live state" > "$HRR/handoff/latest.md"
git -C "$HRR" add handoff/latest.md >/dev/null 2>&1
git -C "$HRR" commit -q -m "track handoff/latest.md (canon-ish live state)" --no-verify
out="$(RDA_KANBAN_REGISTRY="$TMP/reg-htrack" bash "$KB" init "$HRR" 2>&1)"; rc=$?
flagged=0; echo "$out" | grep -q 'handoff/latest.md is TRACKED' && flagged=1
still_tracked=0; git -C "$HRR" ls-files --error-unmatch handoff/latest.md >/dev/null 2>&1 && still_tracked=1
not_ignored=1; grep -qxF 'handoff/latest.md' "$HRR/.gitignore" 2>/dev/null && not_ignored=0
if [ "$rc" -eq 0 ] && [ "$flagged" -eq 1 ] && [ "$still_tracked" -eq 1 ] && [ "$not_ignored" -eq 1 ]; then
  ok "tracked handoff/latest.md is flagged, left tracked + un-gitignored, no false pushed-refuse"
else
  err "handoff tracked-flag wrong (rc=$rc flagged=$flagged tracked=$still_tracked not_ignored=$not_ignored) — got: $out"
fi

# =====================================================================
# PHASE 3 — runner: metadata + schema lint (Layer-1 label only)
# =====================================================================

mk_card() {  # $1=board $2=id  then heredoc body on stdin
  local board="$1" id="$2"
  mkdir -p "$board/todo" "$board/doing" "$board/done"
  cat > "$board/todo/$id.md"
}

section "phase3: a plain card (no runner:/human_gates:) passes lint (fields are optional)"
LB="$TMP/lintBoard"
mk_card "$LB" 260705-400000 <<'EOF'
---
title: Plain card, no federated fields
repo: roberdan-os
dod: "d"
acceptance: "a"
status: todo
created: 2026-07-05
---
EOF
if RDA_KANBAN="$LB" bash kanban/lint-cards.sh >/dev/null 2>&1; then
  ok "existing-shape card with no runner:/human_gates: passes lint unchanged"
else
  err "lint rejected a plain card (should be a no-op — all new fields optional)"
fi

section "phase3: runner: human-only is valid; a well-formed <cli>/<model> is valid"
mk_card "$LB" 260705-400001 <<'EOF'
---
title: Human-only gated card
repo: roberdan-os
dod: "d"
acceptance: "a"
status: todo
created: 2026-07-05
runner: human-only
human_gates: merge, push
---
EOF
mk_card "$LB" 260705-400002 <<'EOF'
---
title: Copilot-runnable card
repo: orca
dod: "d"
acceptance: "a"
status: todo
created: 2026-07-05
runner: copilot-cli/opus
---
EOF
if RDA_KANBAN="$LB" bash kanban/lint-cards.sh >/dev/null 2>&1; then
  ok "runner: human-only (with human_gates) + runner: copilot-cli/opus both pass"
else
  err "lint rejected valid runner: values"
fi

section "phase3: human_gates: set but runner: NOT human-only is a LINT ERROR (§6.6)"
BAD="$TMP/lintBad"
mk_card "$BAD" 260705-400003 <<'EOF'
---
title: Gated surface wrongly marked runner-eligible
repo: orca
dod: "d"
acceptance: "a"
status: todo
created: 2026-07-05
runner: copilot-cli/opus
human_gates: push
---
EOF
if RDA_KANBAN="$BAD" bash kanban/lint-cards.sh >/dev/null 2>&1; then
  err "lint ACCEPTED a card with human_gates: but runner: != human-only (must fail)"
else
  ok "lint fails a card declaring human_gates: while not runner: human-only"
fi

section "phase3: an invalid runner: value (unknown cli) is a LINT ERROR"
BAD2="$TMP/lintBad2"
mk_card "$BAD2" 260705-400004 <<'EOF'
---
title: Bogus runner cli
repo: orca
dod: "d"
acceptance: "a"
status: todo
created: 2026-07-05
runner: gpt-cli/whatever
---
EOF
if RDA_KANBAN="$BAD2" bash kanban/lint-cards.sh >/dev/null 2>&1; then
  err "lint ACCEPTED an unknown runner cli (gpt-cli) — must fail"
else
  ok "lint fails an unknown runner: cli (grammar enforced)"
fi

section "phase3: kb lint routes to lint-cards.sh on the resolved board"
if RDA_KANBAN="$LB" bash "$KB" lint >/dev/null 2>&1 \
   && ! RDA_KANBAN="$BAD" bash "$KB" lint >/dev/null 2>&1; then
  ok "kb lint passes a clean board and fails a bad board"
else
  err "kb lint did not route to lint-cards.sh correctly"
fi

# =====================================================================
# PHASE 5 — Node 1 atomic claim + repo locks (factory/lib.sh)
# =====================================================================
LIB="$ROOT/factory/lib.sh"

# run claim_card in a SEPARATE process (a real filesystem race), writing WON/LOST.
# bash -c: $0=lib path, $1=repo, $2=id.
race_claim() {  # $1=locksdir $2=repo $3=id $4=outfile
  RDA_LOCKS="$1" bash -c 'source "$0"; if claim_card "$1" "$2"; then echo WON; else echo LOST; fi' \
    "$LIB" "$2" "$3" > "$4" 2>/dev/null
}

section "phase5: two parallel claimers on the same <repo>+<id> → exactly one WON, one LOST"
RL="$TMP/locks-race"
race_claim "$RL" repoRace 260705-777 "$TMP/c1" &
race_claim "$RL" repoRace 260705-777 "$TMP/c2" &
wait
won=$(grep -l WON "$TMP/c1" "$TMP/c2" 2>/dev/null | wc -l | tr -d ' ')
lost=$(grep -l LOST "$TMP/c1" "$TMP/c2" 2>/dev/null | wc -l | tr -d ' ')
if [ "$won" = "1" ] && [ "$lost" = "1" ]; then
  ok "atomic claim: exactly one winner, one clean skip (no double-claim)"
else
  err "claim race not exclusive (won=$won lost=$lost) — got: $(cat "$TMP/c1" "$TMP/c2" 2>/dev/null)"
fi

section "phase5: the SAME bare id in two DIFFERENT repos is independently claimable (@rex #2)"
RL2="$TMP/locks-sameid"
race_claim "$RL2" repoOne 260705-SAME "$TMP/s1" &
race_claim "$RL2" repoTwo 260705-SAME "$TMP/s2" &
wait
if grep -q WON "$TMP/s1" && grep -q WON "$TMP/s2"; then
  ok "same id, different repo → BOTH win (locks are keyed on <repo>+<id>, not bare id)"
else
  err "same-id-different-repo were not independently claimable — s1=$(cat "$TMP/s1") s2=$(cat "$TMP/s2")"
fi

section "phase5: repo lock is one-runner-per-repo; a second acquire is refused"
RL3="$TMP/locks-repo"
out=$(RDA_LOCKS="$RL3" bash -c 'source "$0"; acquire_repo_lock repoLock && echo A1; acquire_repo_lock repoLock && echo A2 || echo A2-REFUSED' "$LIB" 2>/dev/null)
if echo "$out" | grep -q 'A1' && echo "$out" | grep -q 'A2-REFUSED'; then
  ok "repo lock: first acquire wins, second is refused (structural one-runner-per-repo)"
else
  err "repo lock did not enforce single holder — got: $out"
fi

section "phase5: stale sweep reclaims a dead-pid + old-heartbeat lock, keeps a live one"
RL4="$TMP/locks-stale"; mkdir -p "$RL4"
# stale: pid that cannot be alive, heartbeat far in the past
mkdir -p "$RL4/card-deadrepo-stale.lock"
echo 999999999 > "$RL4/card-deadrepo-stale.lock/pid"
: > "$RL4/card-deadrepo-stale.lock/heartbeat"; touch -t 202001010000 "$RL4/card-deadrepo-stale.lock/heartbeat"
# fresh: current process pid, new heartbeat
mkdir -p "$RL4/card-liverepo-fresh.lock"
echo "$$" > "$RL4/card-liverepo-fresh.lock/pid"
date -u +%Y-%m-%dT%H:%M:%SZ > "$RL4/card-liverepo-fresh.lock/heartbeat"
RDA_LOCKS="$RL4" RDA_LOCK_TIMEOUT=1 bash -c 'source "$0"; sweep_stale_locks' "$LIB" 2>/dev/null
gone=1; [ -d "$RL4/card-deadrepo-stale.lock" ] && gone=0
kept=0; [ -d "$RL4/card-liverepo-fresh.lock" ] && kept=1
if [ "$gone" -eq 1 ] && [ "$kept" -eq 1 ]; then
  ok "stale sweep reclaims dead-pid+old-heartbeat, preserves the live lock"
else
  err "stale sweep misbehaved (stale-gone=$gone live-kept=$kept)"
fi

# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo; echo "test-federated-kb: ✅ ALL GREEN"; exit 0
else
  echo; echo "test-federated-kb: ❌ FAIL (see above)"; exit 1
fi
