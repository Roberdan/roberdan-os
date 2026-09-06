#!/usr/bin/env bash
# Exercise real checkpoint storage; no model calls or personal state.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export RDA_HOME="$TMP/home"
export RDA_KANBAN="$TMP/project/kanban"
mkdir -p "$RDA_KANBAN/doing"
KB="$ROOT/kanban/kb.sh"
RF="$TMP/project/handoff/resume.md"
git -C "$TMP/project" init -q -b main
git -C "$TMP/project" config user.email test@example.com
git -C "$TMP/project" config user.name "Checkpoint test"
printf '/kanban/\n/handoff/\n' > "$TMP/project/.gitignore"
git -C "$TMP/project" add .gitignore
git -C "$TMP/project" commit -qm init
git -C "$TMP/project" worktree add -qb card/test "$TMP/card"
cd "$TMP/card"
printf 'phase\n' > artifact.txt
git add artifact.txt
git commit -qm phase
revision="$(git rev-parse --short HEAD)"
printf 'title: Other task\nrepo: unrelated\n' > "$RDA_KANBAN/doing/aaa.md"
printf 'title: Recovery task\nrepo: project\n' > "$RDA_KANBAN/doing/own.md"

capsule='{"goal":"Card own: recover without replay","acceptance":"Artifact matches expected revision","constraints":["Approval required for external send"],"decisions":["Do not retry failed variant"],"evidence":["artifact.txt @ phase: passed"],"pending":["agent-7 owns report; await notification","owned worktree: retain until integrated"],"next":"Read artifact.txt before any effects"}'
bash "$KB" pause --context "$capsule" >/dev/null
grep -q "Capsule origin: $TMP/card @ $revision" "$RF"
grep -q 'doing card: own' "$RF"
if grep -q 'Other task' "$RF"; then echo "FAIL: unrelated card leaked" >&2; exit 1; fi
cp "$RF" "$TMP/before"
before_capsule="$(sed -n '/^Capsule origin:/,/^```$/p' "$RF")"
before_json="$(sed -n '/^```json$/,/^```$/p' "$RF")"
for _ in $(seq 1 30); do bash "$KB" pause --auto >/dev/null; done
[ "$(sed -n '/^Capsule origin:/,/^```$/p' "$RF")" = "$before_capsule" ]
[ "$(sed -n '/^```json$/,/^```$/p' "$RF")" = "$before_json" ]
[ "$(wc -c < "$RF")" -le 16384 ]
[ "$(grep -c '^Capsule origin:' "$RF")" -eq 1 ]
grep -q 'agent-7' "$RF"
grep -q 'Approval required' "$RF"
echo "PASS: 30 autosaves preserve capsule, gates, job IDs and correct worktree revision"

cp "$RF" "$TMP/before"
refuse_unchanged() {
  if bash "$KB" pause --context "$1" >"$TMP/out" 2>"$TMP/err"; then
    echo "FAIL: invalid context accepted" >&2; exit 1
  fi
  [ -s "$TMP/err" ]
  cmp "$RF" "$TMP/before"
}
refuse_unchanged '{"goal":"missing fields"}'
refuse_unchanged "$(printf '%s' "$capsule" | jq '.pending = [42]')"
refuse_unchanged "$(printf '%s' "$capsule" | jq '.next = ""')"
refuse_unchanged "$(printf '%s' "$capsule" | jq '.extra = true')"
refuse_unchanged "$(printf '%s' "$capsule" | jq '.goal = ("x" * 13000)')"
echo "PASS: malformed, missing, mistyped and oversized capsules preserve previous checkpoint"

out="$(bash "$KB" resume --context)"
[[ "$out" == *UNVERIFIED* && "$out" == *agent-7* && "$out" != *"live backlog"* ]]
printf '%s\n' "$TMP/project" > "$TMP/registry"
natural="$(env -u RDA_KANBAN RDA_KANBAN_REGISTRY="$TMP/registry" bash "$KB" resume --context)"
[[ "$natural" == *agent-7* ]]
grep -q 'agent-7' "$RF"
# Saved evidence stays at its origin even after a new revision is observed mechanically.
git commit --allow-empty -qm later
later="$(git rev-parse --short HEAD)"
bash "$KB" pause --auto >/dev/null
grep -q "Capsule origin: $TMP/card @ $revision" "$RF"
grep -q -- "- HEAD: $later" "$RF"
echo "PASS: bounded recovery does not replay jobs or relabel old evidence as current"

# Pre-existing oversized data is not truncated or injected automatically.
awk 'BEGIN {for(i=0;i<20000;i++) printf "x"}' > "$RF"
cp "$RF" "$TMP/large"
if bash "$KB" pause --auto >"$TMP/out" 2>"$TMP/err"; then exit 1; fi
cmp "$RF" "$TMP/large"
if bash "$KB" resume --context >"$TMP/out" 2>"$TMP/err"; then exit 1; fi
[ ! -s "$TMP/out" ] && [ -s "$TMP/err" ]
bash "$KB" resume --done >/dev/null
[[ "$(bash "$KB" resume --context)" == *"No checkpoint"* ]]
echo "PASS: oversized existing checkpoint retained, missing checkpoint explicitly reported"

git -C "$TMP/project" worktree remove "$TMP/card"
echo "test-context-recovery: PASS"
