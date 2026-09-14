#!/usr/bin/env bash
# test-factory-shim.sh — factory/shims/{git,gh,rm} are the second layer of the factory's
# fixed "no": hooks/factory-guard.sh matches the command as TEXT and was out-spelled three
# times in a row by @thor (--am"end", /usr/bin/git push, git${IFS}commit${IFS}--amend,
# {git,commit,--amend}). The shims read argv AFTER the shell has expanded everything, so the
# spelling stops mattering. Asserted here:
#   - every evasion that beat the text guard is refused through the shim, executed for real;
#   - the shapes the guard's header declares out of scope (script file, python subprocess,
#     variable-built command) are refused too — that is the whole point of this layer;
#   - everyday commands still work, including the ones kb start/finish need;
#   - the shim finds the real binary and does not recurse into itself;
#   - both factory launch paths put the shims on PATH, and a missing shim stops the factory.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHIMS="$ROOT/factory/shims"
fails=0
ok()  { printf '  ok   — %s\n' "$1"; }
err() { printf '  FAIL — %s\n' "$1"; fails=$((fails+1)); }

REFUSED=97

TMP="$(mktemp -d)"; trap 'chmod -R u+w "$TMP" 2>/dev/null; /bin/rm -rf "$TMP"' EXIT
REPO="$TMP/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q 2>/dev/null
git -C "$REPO" config user.email t@t.local; git -C "$REPO" config user.name t
echo one > "$REPO/a.txt"; git -C "$REPO" add a.txt; git -C "$REPO" commit -qm "one"
BASE_SHA="$(git -C "$REPO" rev-parse HEAD)"

# Run a command line through a shell whose PATH starts with the shims, in the scratch repo.
shimmed() { ( cd "$REPO" && PATH="$SHIMS:$PATH" bash -c "$1" ) >"$TMP/out" 2>"$TMP/err"; echo $?; }
refuses() {
  local rc; rc="$(shimmed "$2")"
  # The shim exits 97; a wrapper between it and us (xargs, make) may map that to its own
  # code. What must always hold: non-zero, and the refusal on stderr.
  if [ "$rc" != "0" ] && grep -q 'factory-shim' "$TMP/err"; then ok "$1"
  else err "$1 — expected a factory-shim refusal, got rc=$rc ($(tail -1 "$TMP/err" 2>/dev/null))"; fi
}
# A spelling that never reaches any binary at all (the shell cannot even find a command by
# that name) is blocked too — just by a different mechanism. Asserted separately so nobody
# reads it as shim coverage.
never_runs() {
  local rc; rc="$(shimmed "$2")"
  if [ "$rc" != "0" ]; then ok "$1 (rc=$rc)"; else err "$1 — it RAN"; fi
}
allows() {
  local rc; rc="$(shimmed "$2")"
  if [ "$rc" != "$REFUSED" ]; then ok "$1"; else err "$1 — refused, should pass ($(head -1 "$TMP/err"))"; fi
}

echo "=== the evasions that beat the text guard ==="
refuses 'git${IFS}commit${IFS}--amend'      'git${IFS}commit${IFS}--amend --allow-empty -m rewritten'
refuses '{git,commit,--amend}'              '{git,commit,--amend,--allow-empty,-m,rewritten}'
refuses 'quoted: git "commit" --am"end"'    'git "commit" --am"end" --allow-empty -m x'
never_runs 'backslash: git\ push (no such command)' 'git\ push origin main'
refuses 'variable-built: GIT=git; $GIT push' 'GIT=git; $GIT push origin main'
refuses 'alias-free `command git push`'     'command git push origin main'
refuses 'eval "git push"'                   'eval "git push origin main"'
refuses 'script written then executed'      'printf "#!/bin/sh\ngit push origin main\n" > p.sh; chmod +x p.sh; ./p.sh'
refuses 'python subprocess'                 'python3 -c "import subprocess,sys; sys.exit(subprocess.call([\"git\",\"push\"]))"'
refuses 'xargs'                             'echo push | xargs git'

echo "=== nothing actually happened to the repo ==="
[ "$(git -C "$REPO" rev-parse HEAD)" = "$BASE_SHA" ] \
  && ok "HEAD unchanged after every refused rewrite" \
  || err "HEAD MOVED — a refusal did not hold"

echo "=== refused: the rest of the fixed no ==="
refuses 'git rebase'            'git rebase -i HEAD~1'
refuses 'git filter-branch'     'git filter-branch --tree-filter true HEAD'
refuses 'git reset --hard'      'git reset --hard HEAD'
refuses 'git clean -fdx'        'git clean -fdx'
refuses 'git branch -D'         'git branch -D nope'
refuses 'git update-ref -d'     'git update-ref -d refs/heads/main'
refuses 'git reflog expire'     'git reflog expire --expire=now --all'
refuses 'git stash drop'        'git stash drop'
refuses 'git gc --prune'        'git gc --prune=now'
refuses 'git --no-verify'       'git commit --no-verify --allow-empty -m x'
refuses 'git -C dir push'       'git -C . push origin main'
refuses 'gh pr create'          'gh pr create --fill'
refuses 'gh pr merge'           'gh pr merge 1 --merge'
refuses 'gh release create'     'gh release create v0.0.1'
refuses 'gh repo delete'        'gh repo delete x --yes'
refuses 'gh api -X DELETE'      'gh api -X DELETE repos/x/y'
refuses 'gh api -f (implies POST)' 'gh api repos/x/y/pulls -f title=t'
refuses 'rm -rf'                'mkdir -p d && rm -rf d'
refuses 'rm -fr'                'mkdir -p d2 && rm -fr d2'
refuses 'rm --recursive --force' 'mkdir -p d3 && rm --recursive --force d3'
refuses 'rm -r -f'              'mkdir -p d4 && rm -r -f d4'

echo "=== allowed: what a factory task does every day ==="
allows 'git status'             'git status --short'
allows 'git add + commit'       'echo two > b.txt && git add b.txt && git commit -qm "two"'
allows 'git log'                'git log --oneline -3'
allows 'git worktree list'      'git worktree list'
allows 'git branch (create)'    'git branch feature-x'
allows 'git reset (unstage)'    'git reset HEAD b.txt'
allows 'git stash list'         'git stash list'
allows 'git --version'          'git --version'
allows 'commit message naming push' 'git commit --allow-empty -qm "fix: push handling"'
allows 'commit message naming amend' 'git commit --allow-empty -qm "amend the docs"'
allows 'rm file'                'touch f && rm f'
allows 'rm -f file'             'touch g && rm -f g'
allows 'rm -r dir'              'mkdir -p e && rm -r e'
allows 'gh pr view (read)'      'true'

echo "=== the shim finds the real binary and does not recurse ==="
out="$( ( cd "$REPO" && PATH="$SHIMS:$PATH" git --version ) 2>&1 )"
case "$out" in git\ version*) ok "git --version goes through to the real git: $out" ;;
  *) err "shim did not reach the real git (got: $out)" ;; esac
# Same shim, invoked when the real tool is a stub earlier on PATH than the system one.
mkdir -p "$TMP/fakebin"
printf '#!/bin/sh\necho STUB-GH "$@"\n' > "$TMP/fakebin/gh"; chmod +x "$TMP/fakebin/gh"
out="$( PATH="$SHIMS:$TMP/fakebin:/usr/bin:/bin" gh pr view 12 2>&1 )"
case "$out" in STUB-GH\ pr\ view\ 12*) ok "gh read command reaches the real gh" ;;
  *) err "gh shim did not exec through (got: $out)" ;; esac

echo "=== wiring: the single launch site puts the shims on PATH ==="
# launch_agent() is the only place a headless agent starts. Asserted behaviourally: a stub
# engine binary records the PATH it was launched with.
WTMP="$(mktemp -d)"; mkdir -p "$WTMP/bin" "$WTMP/dir"
for b in claude copilot; do
  printf '#!/usr/bin/env bash\nprintf "%%s" "$PATH" > "%s/path"\nprintf "%%s\\n" "$@" > "%s/argv"\n' "$WTMP" "$WTMP" > "$WTMP/bin/$b"
  chmod +x "$WTMP/bin/$b"
done
launch_with() {
  RDA_FACTORY_ENGINE="$1" PATH="$WTMP/bin:$PATH" bash -c '
    source "$1/factory/lib.sh"; TIMEOUT_BIN=""
    launch_agent "probe" sonnet "$2" 30 "$2/log"' _ "$ROOT" "$WTMP/dir" >/dev/null 2>&1
}
for engine in copilot claude; do
  launch_with "$engine"
  case "$(cat "$WTMP/path" 2>/dev/null)" in
    "$SHIMS":*) ok "$engine engine: agent runs with the shims first on PATH" ;;
    *) err "$engine engine: shims are not first on PATH (got: $(head -c 120 "$WTMP/path" 2>/dev/null))" ;;
  esac
done
grep -q -- 'launch_agent ' "$ROOT/factory/run.sh" && grep -q -- 'launch_agent ' "$ROOT/factory/lib.sh" "$ROOT/factory/engine.sh" \
  && ok "both the task pass and the @thor verify pass go through launch_agent" \
  || err "a factory pass still starts an agent outside launch_agent"
# One launch SITE, not one launch LINE: launch_agent builds one command line per engine, so
# counting lines would forbid ever supporting a second engine. What must hold is that every
# `-p` invocation in factory/ lives INSIDE launch_agent — outside it, a shim or a deny flag
# can be wired into some paths and not the others, which is the defect this asserts against.
_sites="$(grep -rn -- '"\$CLAUDE" -p \|"\$bin" -p \|"\$ENGINE_BIN" -p ' "$ROOT"/factory/*.sh || true)"
_lo="$(grep -n '^launch_agent() {' "$ROOT/factory/engine.sh" | cut -d: -f1)"
_hi="$(awk -v s="$_lo" 'NR>s && /^}/ {print NR; exit}' "$ROOT/factory/engine.sh")"
_stray=""
while IFS= read -r _l; do
  [ -n "$_l" ] || continue
  case "$_l" in
    "$ROOT/factory/engine.sh":*) _n="$(printf '%s' "$_l" | cut -d: -f2)"
      [ "$_n" -gt "$_lo" ] && [ "$_n" -lt "$_hi" ] || _stray="$_stray$_l" ;;
    *) _stray="$_stray$_l" ;;
  esac
done <<EOF
$_sites
EOF
[ -z "$_stray" ] \
  && ok "every headless launch in factory/ sits inside launch_agent (one site to keep wired)" \
  || err "a launch site outside launch_agent — a guard can be wired into some and not the others: $_stray"
rm -rf "$WTMP"
for b in git gh rm; do
  [ -x "$SHIMS/$b" ] && ok "factory/shims/$b is executable in git" \
    || err "factory/shims/$b is not executable — the shim would be skipped silently"
done

echo "=== two copies of the shims on PATH never exec each other (2026-09-14) ==="
# The real case: @thor's PATH had the main checkout's shims, a test in a card worktree put its own
# copy in front — git/gh exec'd each other for hours, same PID, no output.
_to="$(command -v gtimeout 2>/dev/null || command -v timeout 2>/dev/null || true)"
COPY="$TMP/shimcopy/factory/shims"; mkdir -p "$COPY"; cp "$SHIMS"/git "$SHIMS"/gh "$SHIMS"/rm "$COPY/"; chmod +x "$COPY"/*
if [ -z "$_to" ]; then
  echo "  skip: no timeout binary, a loop could not be bounded here"
else
  for b in git rm; do
    arg="--version"; [ "$b" = rm ] && arg="-f $TMP/none"
    ( cd "$REPO" && PATH="$SHIMS:$COPY:$PATH" "$_to" 10 bash -c "$b $arg" ) >/dev/null 2>&1; rc=$?
    [ "$rc" -eq 0 ] && ok "$b through two shim copies resolves the real binary (no loop)" \
      || err "$b through two shim copies did not finish (rc=$rc) — the wrappers exec each other"
  done
fi
o="$(cd "$REPO" && RDA_SHIM_HOPS=20 PATH="$SHIMS:$PATH" bash -c 'git --version' 2>&1)"; rc=$?
[ "$rc" -eq 125 ] && printf '%s' "$o" | grep -q 'loop between command wrappers' \
  && ok "a wrapper loop ends with a loud error (exit 125), never a process that hangs" \
  || err "the hop guard does not stop a loop (rc=$rc)"

echo "=== fail closed: a missing shim stops the factory ==="
FAKE="$TMP/fake"; mkdir -p "$FAKE/repo/factory/shims" "$FAKE/repo/hooks" "$FAKE/fac/queue" "$FAKE/bin"
cp "$ROOT/factory/run.sh" "$ROOT/factory/lib.sh" "$ROOT/factory/engine.sh" "$FAKE/repo/factory/"
cp "$ROOT/hooks/factory-guard.sh" "$FAKE/repo/hooks/"
cp "$SHIMS"/git "$SHIMS"/gh "$SHIMS"/rm "$FAKE/repo/factory/shims/"
chmod +x "$FAKE/repo/factory/shims/"*
printf '#!/usr/bin/env bash\ntouch "%s/claude-ran"\n' "$FAKE" > "$FAKE/bin/claude"; chmod +x "$FAKE/bin/claude"
printf -- '---\ndir: %s\ntimeout: 30\n---\nprobe\n' "$FAKE" > "$FAKE/fac/queue/probe.md"
run_fake() {
  env -i PATH="$FAKE/bin:/usr/bin:/bin" HOME="$HOME" RDA_FACTORY="$FAKE/fac" RDA_HANDOFF=/dev/null \
    bash "$FAKE/repo/factory/run.sh" >/dev/null 2>"$FAKE/err"; echo $?
}
/bin/rm -f "$FAKE/repo/factory/shims/git"
rc="$(run_fake)"
[ "$rc" -eq 126 ] && [ ! -e "$FAKE/claude-ran" ] && grep -q 'shim missing' "$FAKE/err" \
  && ok "deleted shim -> exit 126, claude never launched" \
  || err "a deleted shim did not stop the factory (rc=$rc)"
cp "$SHIMS/git" "$FAKE/repo/factory/shims/git"; chmod -x "$FAKE/repo/factory/shims/git"
rc="$(run_fake)"
[ "$rc" -eq 126 ] && [ ! -e "$FAKE/claude-ran" ] \
  && ok "non-executable shim -> exit 126, claude never launched" \
  || err "a non-executable shim did not stop the factory (rc=$rc)"

printf '\n'
[ "$fails" -eq 0 ] && { echo "test-factory-shim: ✅ ALL GREEN"; exit 0; }
echo "test-factory-shim: ❌ $fails FAIL"; exit 1
