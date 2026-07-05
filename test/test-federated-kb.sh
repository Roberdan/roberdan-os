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

# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo; echo "test-federated-kb: ✅ ALL GREEN"; exit 0
else
  echo; echo "test-federated-kb: ❌ FAIL (see above)"; exit 1
fi
