#!/usr/bin/env bash
# test-main-guard.sh — the PreToolUse Edit|Write guard that blocks writes on main/master.
#
# Real hole, found 2026-08-29 while assessing claude-code v2.1.251 (which fixed the same class
# of bug in Claude Code's own file tools): the guard decided on the UNRESOLVED path string, so
# a symlink named `notes.md` pointing at `src/lib.rs` satisfied the "*.md is meta/docs, editable
# on main" carve-out and let a source-file write through on main. Reproduced with @thor before
# the fix: original guard allowed it, patched guard denies it, no false positive on a real .md.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$ROOT/hooks/main-guard.sh"
fails=0
ok()  { printf '  ok   — %s\n' "$1"; }
err() { printf '  FAIL — %s\n' "$1"; fails=$((fails+1)); }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed (the guard requires it)"; exit 0; }

# Throwaway repo, never the shared checkout: on branch main, exactly what the guard is for.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git init -q "$tmp/repo"
git -C "$tmp/repo" checkout -q -b main 2>/dev/null || true
echo "fn main(){}" > "$tmp/repo/lib.rs"
git -C "$tmp/repo" add lib.rs
git -C "$tmp/repo" -c user.email=t@t -c user.name=t commit -q -m init  # HEAD must not be unborn

decide() { # decide <file_path>
  local out
  out="$(jq -n --arg fp "$1" '{tool_input:{file_path:$fp}}' | bash "$GUARD" 2>/dev/null)" \
    || { echo "ERROR"; return; }
  [ -z "$out" ] && { echo "allow"; return; }
  printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"'
}

echo "=== the hole this pins ==="
ln -sf lib.rs "$tmp/repo/notes.md"
got="$(decide "$tmp/repo/notes.md")"
[ "$got" = "deny" ] && ok "symlink notes.md -> lib.rs on main -> deny (resolved before the carve-out)" \
  || err "symlink notes.md -> lib.rs on main -> got '$got', expected deny — THE HOLE IS BACK"

echo "=== must not over-block: a real .md and a not-yet-created file still pass ==="
echo "# real notes" > "$tmp/repo/README.md"
got="$(decide "$tmp/repo/README.md")"
[ "$got" = "allow" ] && ok "genuine README.md on main -> allow" \
  || err "genuine README.md on main -> got '$got', expected allow (false positive)"

got="$(decide "$tmp/repo/brandnew.md")"
[ "$got" = "allow" ] && ok "not-yet-existing brandnew.md on main -> allow (Write case, nothing to resolve)" \
  || err "not-yet-existing brandnew.md on main -> got '$got', expected allow"

echo "=== source files still blocked on main, symlink or not ==="
got="$(decide "$tmp/repo/lib.rs")"
[ "$got" = "deny" ] && ok "lib.rs on main -> deny (unchanged behaviour)" \
  || err "lib.rs on main -> got '$got', expected deny"

if [ "$fails" -eq 0 ]; then printf '\ntest-main-guard: ✅ ALL GREEN\n'; else printf '\ntest-main-guard: ❌ FAIL (see above)\n'; fi
exit "$fails"
