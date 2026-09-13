#!/usr/bin/env bash
# test-factory-guard.sh — hooks/factory-guard.sh is the fixed "no" list for unattended factory
# runs, added because auto mode's classifier let `git commit --amend` through 5 times out of 7
# (2026-09-12). Asserted here:
#   - every rule denies the command it exists for, including the evasions an injected task
#     would try first (git global options, `bash -c "..."`, split rm flags);
#   - the everyday commands a factory task needs still pass — a guard that blocks `git commit`
#     or `rm file` would make every task fail, and would get removed;
#   - both factory launch paths actually load it (the wiring, not just the file);
#   - a missing guard stops the factory instead of running unguarded.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$ROOT/hooks/factory-guard.sh"
fails=0
ok()  { printf '  ok   — %s\n' "$1"; }
err() { printf '  FAIL — %s\n' "$1"; fails=$((fails+1)); }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed (the guard requires it)"; exit 0; }

decide() {
  local out
  out="$(jq -n --arg c "$1" '{tool_input:{command:$c}}' | bash "$GUARD" 2>/dev/null)" || { echo "ERROR"; return; }
  [ -z "$out" ] && { echo "allow"; return; }
  printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"'
}
expect() { local got; got="$(decide "$2")"; [ "$got" = "$1" ] && ok "$1: $2" || err "expected $1, got $got: $2"; }

echo "=== denied: publishing ==="
expect deny 'git push origin main'
expect deny 'git push'
expect deny 'git -C /tmp/repo push origin HEAD'
expect deny 'git -c core.hooksPath=/dev/null push'
expect deny 'bash -c "git push origin main"'
expect deny '/usr/bin/git push'
expect deny './git commit --amend'
expect deny 'command git push'
expect deny '(git push)'
expect deny '$(git push)'
expect deny 'git -C "my dir" push'
expect deny "git -C 'my dir' commit --amend"
expect deny 'cd repo && git push -u origin feat'
expect deny 'gh pr merge 12 --merge'
expect deny 'gh pr create --fill'
expect deny 'gh release create v1.0.0'
expect deny 'gh repo delete Roberdan/x --yes'
expect deny 'gh api -X DELETE repos/Roberdan/x'
expect deny 'gh api repos/Roberdan/x/pulls --method POST -f title=t'

echo "=== denied: rewriting or deleting history ==="
expect deny 'git commit --amend --allow-empty -m rewritten'
expect deny 'git commit -a --amend --no-edit'
expect deny 'git commit --am --allow-empty -m x'
expect deny 'git "commit" --amend'
expect deny 'git commit --am"end" -m x'
expect deny 'git pu\sh origin main'
expect deny 'git rebase -i HEAD~3'
expect deny 'git reset --hard HEAD~1'
expect deny 'git filter-branch --tree-filter x HEAD'
expect deny 'git branch -D feature'
expect deny 'git update-ref -d refs/heads/main'
expect deny 'git reflog expire --expire=now --all'
expect deny 'git stash drop'
expect deny 'git gc --prune=now'
expect deny 'git clean -fdx'
expect deny 'git commit -m wip --no-verify'

echo "=== denied: forced deletion ==="
expect deny 'rm -rf build'
expect deny 'rm -fr /tmp/x'
expect deny 'rm -Rf node_modules'
expect deny 'rm -r -f dist'
expect deny 'rm --force --recursive dist'
expect deny 'sudo rm -rf /'
expect deny 'find . -name "*.log" -delete'

echo "=== allowed: what a factory task does every day ==="
expect allow 'git status'
expect allow 'git add factory/run.sh test/test-factory-guard.sh'
expect allow 'git commit -m "feat: add guard"'
expect allow 'git log --oneline -5'
expect allow 'git diff HEAD~1'
expect allow 'git branch feature-x'
expect allow 'git stash list'
expect allow 'git reset HEAD file.txt'
expect allow 'rm out.txt'
expect allow 'rm -r empty-dir'
expect allow 'rm -f stale.lock'
expect allow 'gh pr view 12'
expect allow 'gh api repos/Roberdan/x/pulls'
expect allow 'bash test/validate.sh'
expect allow 'npm run format'
expect allow 'git commit -m "fix: push handling"'
expect allow 'git commit -m "amend the docs"'
expect allow 'git log --grep=push'
expect allow 'git checkout push-branch'
expect allow 'ls .git && cat .gitignore'
# Out of scope by design (see the guard's header): shell expansion builds the command at run
# time, so no text match can see it. Pinned as ALLOW so nobody mistakes this for coverage.
expect allow 'GIT=git; $GIT push'

echo "=== wiring: both factory launch paths load the guard ==="
# shellcheck source=factory/lib.sh
settings="$(bash -c 'source "$1/factory/lib.sh"; printf %s "$FACTORY_SETTINGS"' _ "$ROOT")"
cmdline="$(printf '%s' "$settings" | jq -r '.hooks.PreToolUse[] | select(.matcher=="Bash") | .hooks[].command' 2>/dev/null)"
[ "$cmdline" = "bash \"$GUARD\"" ] && ok "FACTORY_SETTINGS is valid JSON and runs $GUARD" \
  || err "FACTORY_SETTINGS does not wire the guard (got: $cmdline)"
sites="$(grep -hc -- '-p "\$[a-z]*" --model [^ ]* --permission-mode auto --permission-prompts none --settings "\$FACTORY_SETTINGS"' "$ROOT"/factory/*.sh | paste -sd+ - | bc)"
total="$(grep -hc -- '"\$CLAUDE" -p ' "$ROOT"/factory/*.sh | paste -sd+ - | bc)"
[ "$total" -ge 4 ] && [ "$sites" = "$total" ] && ok "all $total claude -p launch sites pass --settings \"\$FACTORY_SETTINGS\"" \
  || err "only $sites of $total claude -p launch sites load the guard"

echo "=== fail closed: a missing guard stops the factory ==="
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo/factory" "$TMP/repo/hooks" "$TMP/fac/queue" "$TMP/bin"
cp "$ROOT/factory/run.sh" "$ROOT/factory/lib.sh" "$TMP/repo/factory/"
printf '#!/usr/bin/env bash\ntouch "%s/claude-ran"\n' "$TMP" > "$TMP/bin/claude"; chmod +x "$TMP/bin/claude"
printf -- '---\ndir: %s\ntimeout: 30\n---\nprobe\n' "$TMP" > "$TMP/fac/queue/probe.md"
env -i PATH="$TMP/bin:/usr/bin:/bin" HOME="$HOME" RDA_FACTORY="$TMP/fac" RDA_HANDOFF=/dev/null \
  bash "$TMP/repo/factory/run.sh" >/dev/null 2>"$TMP/err"; rc=$?
[ "$rc" -eq 126 ] && [ ! -e "$TMP/claude-ran" ] && grep -q 'guard not found' "$TMP/err" \
  && ok "no hooks/factory-guard.sh -> exit 126, claude never launched" \
  || err "missing guard did not stop the factory (rc=$rc, claude ran: $([ -e "$TMP/claude-ran" ] && echo yes || echo no))"

printf '\n'
[ "$fails" -eq 0 ] && { echo "test-factory-guard: ✅ ALL GREEN"; exit 0; }
echo "test-factory-guard: ❌ $fails FAIL"; exit 1
