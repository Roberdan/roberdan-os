#!/usr/bin/env bash
# test-bash-guard.sh — the PreToolUse Bash guard is the only thing standing between an agent
# and three scars this repo actually took (a force-push, a `reset --hard`, a source file swept
# into a docs commit). Until 2026-07-31 it had NO test: every rule was a promise, and putting
# any of them back would have stayed green forever.
#
# Two things are asserted here, and the second one is why the file exists:
#   - each rule fires on the command it is meant to catch;
#   - each rule does NOT fire on the neighbouring command it must let through — an
#     over-blocking guard gets disabled by the first person it annoys, which is the same
#     outcome as no guard at all.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$ROOT/hooks/bash-guard.sh"
fails=0
ok()   { printf '  ok   — %s\n' "$1"; }
err()  { printf '  FAIL — %s\n' "$1"; fails=$((fails+1)); }

# Feed one command through the guard and print its decision (allow when it stays silent).
decide() {
  local out
  out="$(jq -n --arg c "$1" '{tool_input:{command:$c}}' | bash "$GUARD" 2>/dev/null)" \
    || { echo "ERROR"; return; }
  [ -z "$out" ] && { echo "allow"; return; }
  printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"'
}

expect() { # expect <decision> <command> <label>
  local got; got="$(decide "$2")"
  [ "$got" = "$1" ] && ok "$3" || err "$3 (expected $1, got $got)"
}

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed (the guard requires it)"; exit 0; }

echo "=== rule 0: invisible / bidi / control characters ==="
# U+200B zero-width space wedged inside the command token.
expect deny "$(printf 'git pu​sh origin main')" "zero-width space inside a command token -> deny"
# U+202E right-to-left override: reverses how the tail of the line renders.
expect deny "$(printf 'rm -rf /tmp/x ‮')" "bidi override in the command head -> deny"
# U+00AD soft hyphen: invisible, and a legal filename byte.
expect deny "$(printf 'git­ push origin main')" "soft hyphen between tokens -> deny"
# The false positive that would make this rule unusable in THIS repo.
expect allow "$(printf 'git commit -m "perché la verifica è già passata"')" \
  "accented Italian inside a quoted commit message -> allowed (no over-block)"
expect allow "echo 'città, però, qualità' > /tmp/x" "accented Italian in a quoted argument -> allowed"
# Out of scope by design: inside quotes it is data, and data is not classified.
expect allow "$(printf 'echo "zero​width"')" "zero-width INSIDE a quoted string -> allowed (declared scope)"
expect allow "printf 'ok\n' && ls -la" "plain multi-token command -> allowed"

echo
echo "=== rule 1: force / no-verify push (the 2026-07 scar) ==="
expect deny  "git push --force origin main"      "git push --force -> deny"
expect deny  "git push -f origin main"           "git push -f -> deny"
expect deny  "git push --no-verify"              "git push --no-verify -> deny"
expect allow "git push origin main"              "ordinary git push -> allowed"
expect allow "git commit -m 'never use git push --force here'" \
  "the flag NAMED inside a quoted message -> allowed (message is data, not a command)"
# Tradeoff dichiarato dalla riparazione: stringhe fra virgolette = dati, quindi un flag
# nascosto fra virgolette non viene piu' intercettato. Asserito perche' sia visibile.
expect allow "git push \"--force\" origin main" \
  "flag NASCOSTO fra virgolette -> allowed (tradeoff dichiarato: dato, non comando)"

echo
echo "=== rule 3: destructive reset / clean -> ask, never silent ==="
expect ask   "git reset --hard HEAD~1"           "git reset --hard -> ask"
expect ask   "git clean -fd"                     "git clean -fd -> ask"
expect allow "git reset --soft HEAD~1"           "git reset --soft -> allowed"

echo
echo "=== rule 4: a docs commit must not be staged with a blanket add (the 2026-07-14 scar) ==="
expect deny  "git add -A && git commit -m 'docs(evolve): note'" "git add -A + docs commit -> deny"
expect deny  "git add . && git commit -m \"docs: x\""           "git add . + docs commit -> deny"
expect allow "git add docs/findings.md && git commit -m 'docs(evolve): note'" \
  "docs commit staged BY PATH -> allowed (the whole point of the rule)"
expect allow "git add -A && git commit -m 'feat(evolve): code change'" \
  "blanket add on a non-docs commit -> allowed (rule is scoped to docs)"

echo
if [ "$fails" -eq 0 ]; then echo "test-bash-guard: PASS"; exit 0; fi
echo "test-bash-guard: FAIL ($fails)"; exit 1
