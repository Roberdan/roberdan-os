#!/usr/bin/env bash
# test-fork-merge.sh — the merge-clean proof that justifies the v2.0.0 engine/identity
# split (docs/plan-2026-07-05-engine-identity-split.md § Acceptance test 4).
#
# Scenario, on a scratch clone (never touches this repo):
#   1. "jane fork": bin/identity-init.sh --apply, then edits ONLY identity/* — committed.
#   2. simulated upstream: a second branch from the same base commits edits to ENGINE
#      files (behavior/roberto-mode.md, agents/twin.md, hooks/bash-guard.sh).
#   3. jane merges upstream → must complete with ZERO conflicts, because jane touched
#      only identity/ and upstream touched only engine files.
#
# Contrast baseline (documented, not run): the same scenario under v1.3.0's
# fork-identity.sh — which renamed agents/roberdan-twin.md and behavior/roberto-voice.md
# and sed-rewrote RDA_/.roberdan-os tokens across ~30 live files — conflicted on every
# renamed/rewritten file that upstream later touched. That is the merge war the split
# removes.
#
# SOFT GUARANTEE (documented, deliberately NOT asserted — § Acceptance test 5): if
# upstream also edits an identity/* file the forker rewrote, that ONE file conflicts —
# a small, localized, expected conflict (identity/ is the forker's to own; upstream
# rarely touches it), versus the pervasive engine-file war it replaces. Asserting on it
# would freeze upstream's right to ever improve the reference identity files.
#
# Uses the repo's committed HEAD (git clone of $ROOT) — run after committing.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FAIL=0
ok()  { printf '  ok: %s\n' "$1"; }
err() { printf '  FAIL: %s\n' "$1"; FAIL=1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/rda-fork-merge.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

FORK="$TMP/jane-fork"
git clone --quiet "$ROOT" "$FORK" 2>/dev/null
cd "$FORK"
git config user.email "jane@example.com"
git config user.name "Jane Doe"
BASE_BRANCH="$(git rev-parse --abbrev-ref HEAD)"

# --- simulated upstream: engine-only edits on a branch from the same base -------------
git checkout --quiet -b upstream-main
for f in behavior/roberto-mode.md agents/twin.md hooks/bash-guard.sh; do
  [ -f "$f" ] || { err "engine file missing in clone: $f"; exit 1; }
  printf '\n# upstream engine improvement (simulated)\n' >> "$f"
done
git commit --quiet -am "feat(engine): simulated upstream engine edits"

# --- jane's fork: identity-only changes on the base branch ----------------------------
git checkout --quiet "$BASE_BRANCH"
if ! bash bin/identity-init.sh --slug jane --name "Jane Doe" --apply --force >/dev/null 2>&1; then
  err "bin/identity-init.sh --apply failed on the scratch clone"
  exit 1
fi
printf '\nJane always signs off with "cheers, Jane".\n' >> identity/voice.md
printf '\n- Jane ships on Fridays.\n' >> identity/operator.md
printf '\n- Jane prefers async threads over calls.\n' >> identity/twin-persona.md
git commit --quiet -am "feat(identity): jane rewrites her identity"

# Assert the fork's commit touched ONLY identity/ (the acceptance-3 invariant).
non_identity="$(git show --name-only --pretty=format: HEAD | grep -v '^$' | grep -v '^identity/' || true)"
if [ -z "$non_identity" ]; then
  ok "jane's fork commit touches identity/* only"
else
  err "jane's fork commit leaked outside identity/: $non_identity"
fi

# --- the merge: jane pulls upstream engine edits ---------------------------------------
if git merge --no-edit upstream-main >/dev/null 2>&1; then
  ok "git merge upstream-main completed"
else
  err "git merge upstream-main FAILED (conflict?) — the split's core guarantee is broken"
fi

conflicts="$(git ls-files -u | wc -l | tr -d ' ')"
if [ "$conflicts" -eq 0 ]; then
  ok "zero merge conflicts (identity-only fork vs engine-only upstream)"
else
  err "$conflicts unmerged path(s): $(git ls-files -u | awk '{print $4}' | sort -u | tr '\n' ' ')"
fi

# Post-merge sanity: both sides' content present.
grep -q "upstream engine improvement" behavior/roberto-mode.md \
  && ok "upstream engine edit survived the merge" \
  || err "upstream engine edit missing after merge"
grep -q "cheers, Jane" identity/voice.md \
  && ok "jane's identity edit survived the merge" \
  || err "jane's identity edit missing after merge"

# No engine file was renamed anywhere in the process (acceptance-3 invariant).
[ -f agents/twin.md ] && [ ! -e agents/jane-twin.md ] \
  && ok "no engine rename (agents/twin.md intact, no agents/jane-twin.md)" \
  || err "engine rename detected"

echo ""
if [ "$FAIL" -eq 0 ]; then echo "test-fork-merge: PASS"; exit 0; else echo "test-fork-merge: FAIL"; exit 1; fi
