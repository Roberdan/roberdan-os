#!/usr/bin/env bash
# test-bus-doorbell-matcher.sh — the PostToolUse registration for bus-doorbell.sh must
# carry matcher "Bash|Edit|Write", and re-installing over an OLD unmatched entry must
# upgrade it in place, never duplicate it.
#
# WHY THIS EXISTS. bus-doorbell.sh used to be registered with matcher "*" (or no matcher
# at all, which Claude Code treats the same way): it ran after EVERY tool call, including
# read-only ones (Read/Glob/Grep/WebSearch/...) that cannot change bus or repo state —
# paying its ~0.55s cost for nothing. Only Bash/Edit/Write can actually change that state,
# so those are the only tools it needs to run after.
#
# THIS CANNOT RESTART A LIVE CLAUDE CODE SESSION to prove the hook stops firing on Read —
# that proof needs a fresh session (next session, per the card). What this DOES prove,
# empirically, in this process:
#   1. the CANON snippet (bin/sync.sh) generates the doorbell entry with the narrowed
#      matcher, and ONLY the doorbell moved — audit.sh, which legitimately needs every
#      tool call, is untouched;
#   2. bin/install-hooks.sh, run against a settings.json holding the OLD unmatched form
#      (the exact shape found on this machine before this card), converts it to the new
#      matcher instead of adding a second, duplicate entry;
#   3. Claude Code's own documented matcher semantics (code.claude.com/docs/en/hooks,
#      "matcher" field: exact-string-list for [A-Za-z0-9_ ,|-]-only patterns, not a
#      substring regex) applied to the matcher string this generates: "Read" does not
#      match, "Bash" does, and neither does a substring look-alike like "TodoWrite".
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0
ok()  { printf '  ok: %s\n' "$1"; }
err() { printf '  FAIL: %s\n' "$1"; FAIL=1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent"; echo "test-bus-doorbell-matcher: PASS"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 absent"; echo "test-bus-doorbell-matcher: PASS"; exit 0; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

printf '\n=== 1. the generated snippet: doorbell narrowed, audit.sh untouched ===\n'
RDA_SYNC_OUT="$TMP/platforms" bash "$ROOT/bin/sync.sh" --emit-only >/dev/null
SNIPPET="$TMP/platforms/claude/settings-hooks.json"
[ -f "$SNIPPET" ] || { err "generated snippet missing"; echo "test-bus-doorbell-matcher: FAIL"; exit 1; }

doorbell_matcher="$(jq -r '.hooks.PostToolUse[] | select(.hooks[]?.command | test("bus-doorbell")) | .matcher' "$SNIPPET")"
[ "$doorbell_matcher" = "Bash|Edit|Write" ] \
  && ok "bus-doorbell.sh entry carries matcher \"Bash|Edit|Write\"" \
  || err "bus-doorbell.sh matcher is '$doorbell_matcher', expected 'Bash|Edit|Write'"

audit_matcher="$(jq -r '.hooks.PostToolUse[] | select(.hooks[]?.command | test("audit\\.sh")) | .matcher' "$SNIPPET")"
[ "$audit_matcher" = "*" ] \
  && ok "audit.sh stays on matcher \"*\" (still needs every tool call)" \
  || err "audit.sh matcher changed to '$audit_matcher' — only the doorbell should narrow"

doorbell_count="$(jq '[.hooks.PostToolUse[] | select(.hooks[]?.command | test("bus-doorbell"))] | length' "$SNIPPET")"
[ "$doorbell_count" = "1" ] \
  && ok "exactly one PostToolUse entry carries the doorbell (no duplicate)" \
  || err "expected exactly 1 doorbell entry in the generated snippet, found $doorbell_count"

printf '\n=== 2. re-install over the OLD unmatched entry upgrades it, does not duplicate ===\n'
# The exact shape install-hooks.sh must upgrade: an entry with NO "matcher" key at all
# (Claude Code treats a missing matcher the same as "*") holding only the doorbell command,
# written the way sync.sh wrote it before this card, at THIS worktree's own root (so the
# command-normalization in install-hooks.sh matches it — a fixture from a different
# checkout root would look like an unrelated command, not an old form of the same one).
ROOT_REL="${ROOT#"$HOME"/}"
S="$TMP/settings.json"
cat > "$S" <<JSON
{ "hooks": { "PostToolUse": [
  { "matcher": "Edit|Write", "hooks": [ { "type": "command", "command": "bash \$HOME/$ROOT_REL/hooks/autofmt.sh", "timeout": 30 } ] },
  { "hooks": [ { "type": "command", "command": "bash \$HOME/$ROOT_REL/hooks/bus-doorbell.sh 2>/dev/null || true", "timeout": 5 } ] },
  { "hooks": [ { "type": "command", "command": "foreign-hook-must-survive.sh" } ] }
] } }
JSON

RDA_CLAUDE_SETTINGS="$S" bash "$ROOT/bin/install-hooks.sh" --apply >/dev/null

new_matcher="$(jq -r '.hooks.PostToolUse[] | select(.hooks[]?.command | test("bus-doorbell")) | .matcher' "$S")"
[ "$new_matcher" = "Bash|Edit|Write" ] \
  && ok "the old unmatched entry was upgraded to matcher \"Bash|Edit|Write\"" \
  || err "expected the upgraded matcher, got '$new_matcher'"

count_after="$(jq '[.hooks.PostToolUse[] | select(.hooks[]?.command | test("bus-doorbell"))] | length' "$S")"
[ "$count_after" = "1" ] \
  && ok "no duplicate: still exactly one doorbell entry after upgrade" \
  || err "upgrade duplicated the entry instead of converting it in place — found $count_after"

jq -e '.hooks.PostToolUse[] | select(.hooks[]?.command == "foreign-hook-must-survive.sh")' "$S" >/dev/null \
  && ok "a foreign, unrelated hook entry survives the upgrade untouched" \
  || err "the upgrade pass dropped a foreign hook entry — it must touch only its own commands"

before="$(jq -S .hooks "$S")"
RDA_CLAUDE_SETTINGS="$S" bash "$ROOT/bin/install-hooks.sh" --apply >/dev/null
after="$(jq -S .hooks "$S")"
[ "$before" = "$after" ] \
  && ok "a second --apply after the upgrade is a byte-identical no-op (idempotent)" \
  || err "second --apply after upgrade changed the file — not idempotent"

printf '\n=== 3. Claude Code matcher semantics: applied to real tool names ===\n'
# Claude Code evaluates "matcher" three ways depending on its characters
# (code.claude.com/docs/en/hooks, "How matchers work"):
#   "*", "", omitted        -> match all
#   only [A-Za-z0-9_ ,|-]   -> EXACT string, or list of exact strings split on '|'/','
#   anything else           -> unanchored JS regex
# "Bash|Edit|Write" is letters and '|' only, so it is the EXACT-list case: it must match
# the tool named exactly "Bash", "Edit" or "Write" and must NOT match "TodoWrite" or
# "NotebookEdit" by substring — getting this wrong would mean the doorbell still fires
# on tools it was never meant to run after, just under a different-looking rule.
python3 - "$doorbell_matcher" <<'PY'
import re, sys
pattern = sys.argv[1]

def claude_matches(pattern, tool):
    if pattern in ("", "*"):
        return True
    if re.fullmatch(r"[A-Za-z0-9_\- ,|]+", pattern):
        return tool in {p.strip() for p in re.split(r"[|,]", pattern)}
    return re.search(pattern, tool) is not None  # unanchored regex case

cases = {"Read": False, "Glob": False, "Grep": False, "WebFetch": False,
         "TodoWrite": False, "NotebookEdit": False,
         "Bash": True, "Edit": True, "Write": True}
fail = False
for tool, should_match in cases.items():
    got = claude_matches(pattern, tool)
    mark = "ok" if got == should_match else "FAIL"
    if got != should_match:
        fail = True
    print(f"  {mark}: matcher '{pattern}' vs tool_name '{tool}' -> match={got} (expected {should_match})")
sys.exit(1 if fail else 0)
PY
if [ $? -eq 0 ]; then
  ok "matcher behaves correctly on the real tool-name set, including the exact-vs-substring case (TodoWrite/NotebookEdit excluded)"
else
  err "matcher did not behave as expected against Claude Code's own documented semantics"
fi

[ "$FAIL" -eq 0 ] && { echo "test-bus-doorbell-matcher: PASS"; exit 0; }
echo "test-bus-doorbell-matcher: FAIL"; exit 1
