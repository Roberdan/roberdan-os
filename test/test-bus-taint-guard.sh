#!/usr/bin/env bash
# test-bus-taint-guard.sh — hooks/bus-taint.sh (item B) and hooks/bus-guard.sh
# (items C and E), card 260924-142220. Behavioural: fed real hook-shaped JSON on
# stdin, the same input shape Claude Code and the Copilot extension hand these
# scripts. Red-then-green: run against the pre-card hooks directory (neither
# file exists) and every check below fails at the `[ -x "$TAINT" ]`/`[ -x
# "$GUARD" ]` guard — this file is the green, repeatable form.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUS="$ROOT/bus/bus.sh"
TAINT="$ROOT/hooks/bus-taint.sh"
GUARD="$ROOT/hooks/bus-guard.sh"
WAKECLEAR="$ROOT/hooks/bus-wake-clear.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

[ -x "$TAINT" ] || fail "hooks/bus-taint.sh missing or not executable"
[ -x "$GUARD" ] || fail "hooks/bus-guard.sh missing or not executable"
[ -x "$WAKECLEAR" ] || fail "hooks/bus-wake-clear.sh missing or not executable"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export RDA_HOME="$HOME/.roberdan-os"
export RDA_BUS_HOME="$RDA_HOME/bus"
mkdir -p "$HOME" "$TMP/cwd"
runbus() ( cd "$TMP/cwd" && bash "$BUS" "$@" )

# --- B: taint marking, sticky, monotonic, provider-neutral tool naming ------
echo '{"session_id":"sessA","tool_name":"WebFetch","tool_input":{"url":"http://x"}}' | bash "$TAINT"
[ "$(cat "$RDA_HOME/bus-taint/sessA" 2>/dev/null)" = "external" ] \
  || fail "WebFetch did not mark the session external-tainted"
ok "a WebFetch call marks the session external-tainted"

echo '{"session_id":"sessA","tool_name":"Read","tool_input":{"file_path":"/x/.roberdan-os/private/roberto-profile.md"}}' | bash "$TAINT"
[ "$(cat "$RDA_HOME/bus-taint/sessA")" = "confidential" ] \
  || fail "reading private/ did not mark the session confidential-tainted"
ok "reading ~/.roberdan-os/private/ marks the session confidential-tainted"

echo '{"session_id":"sessA","tool_name":"WebFetch","tool_input":{"url":"http://x"}}' | bash "$TAINT"
[ "$(cat "$RDA_HOME/bus-taint/sessA")" = "confidential" ] \
  || fail "taint downgraded from confidential back to external"
ok "taint never downgrades: confidential stays confidential"

echo '{"session_id":"sessB","tool_name":"bash","tool_input":{"command":"curl http://x"}}' | bash "$TAINT"
[ "$(cat "$RDA_HOME/bus-taint/sessB" 2>/dev/null)" = "external" ] \
  || fail "Copilot's lowercase 'bash' tool name with curl did not taint (provider-neutral matching)"
ok "provider-neutral: Copilot's lowercase tool names taint the same as Claude's"

# --- taint reaches a real send: a tainted sender renders UNVERIFIED ---------
REPO=taint-repo
mkdir -p "$RDA_BUS_HOME/$REPO"
echo "leaked context" | RDA_BUS_SESSION=sessA runbus send --repo "$REPO" --card c1 --from implementer --to reviewer --kind note >/dev/null
runbus log --repo "$REPO" --card c1 > "$TMP/tainted.out" 2>&1
grep -q "tainted: confidential" "$TMP/tainted.out" \
  || fail "a confidential-tainted sender's message did not render tainted-UNVERIFIED"
ok "a tainted session's message renders UNVERIFIED (tainted: ...), whatever it claims"

# --- confidential egress refused cross-provider (opt-in manifest field) -----
ROLES2="$TMP/roles"; mkdir -p "$ROLES2"
cp "$ROOT/bus/roles/reviewer.json" "$ROLES2/reviewer.json"
jq '. + {provider:"copilot"}' "$ROLES2/reviewer.json" > "$ROLES2/reviewer.json.tmp" && mv "$ROLES2/reviewer.json.tmp" "$ROLES2/reviewer.json"
cp "$ROOT/bus/roles/implementer.json" "$ROLES2/implementer.json"
echo "leak?" | RDA_BUS_ROLES="$ROLES2" RDA_BUS_SESSION=sessA RDA_BUS_PROVIDER=claude \
  runbus send --repo "$REPO" --card c1 --from implementer --to reviewer --kind note 2>"$TMP/egress.err" \
  && fail "confidential-tainted egress to a cross-provider role was accepted"
grep -q "cross-provider egress" "$TMP/egress.err" || fail "egress refusal did not explain why"
ok "confidential-tainted session -> role on another provider: refused"

# --- no manifest opts in: NOTHING changes for the shipped roles -------------
echo "fine, no provider declared" | RDA_BUS_SESSION=sessA runbus send --repo "$REPO" --card c1 --from implementer --to reviewer --kind note >/dev/null \
  || fail "a confidential-tainted send to a role with NO declared provider was refused (should only refuse opt-in roles)"
ok "a role manifest with no provider field is unaffected (opt-in, not a behavior change for shipped roles)"

# --- E: bus pausa -> bus-guard.sh denies the very next tool call ------------
runbus pausa --by implementer --why "guard test" >/dev/null 2>&1
out="$(echo '{"session_id":"sessC","tool_name":"Bash","tool_input":{"command":"echo hi"}}' | RDA_BUS_SH="$BUS" bash "$GUARD")"
echo "$out" | grep -q '"permissionDecision":"deny"' || fail "bus-guard.sh did not deny a tool call while paused"
echo "$out" | grep -qi "pausa" || fail "the pause deny reason did not mention pausa"
runbus riprendi --by implementer >/dev/null 2>&1
out2="$(echo '{"session_id":"sessC","tool_name":"Bash","tool_input":{"command":"echo hi"}}' | RDA_BUS_SH="$BUS" bash "$GUARD")"
[ -z "$out2" ] || fail "bus-guard.sh still denied a plain command after riprendi: $out2"
ok "bus pausa: the very next tool call is denied; bus riprendi restores it"

# --- C: wake-origin turns deny gate-class actions, allow everything else ----
runbus mark-wake --session sessD >/dev/null 2>&1
denygit="$(echo '{"session_id":"sessD","tool_name":"Bash","tool_input":{"command":"git push origin main"}}' | RDA_BUS_SH="$BUS" bash "$GUARD")"
echo "$denygit" | grep -q '"permissionDecision":"deny"' || fail "a wake-origin turn was allowed to git push"
denykb="$(echo '{"session_id":"sessD","tool_name":"Bash","tool_input":{"command":"kb finish 123 --thor x"}}' | RDA_BUS_SH="$BUS" bash "$GUARD")"
echo "$denykb" | grep -q '"permissionDecision":"deny"' || fail "a wake-origin turn was allowed to kb finish"
denypriv="$(echo '{"session_id":"sessD","tool_name":"Read","tool_input":{"file_path":"/x/.roberdan-os/private/y.md"}}' | RDA_BUS_SH="$BUS" bash "$GUARD")"
echo "$denypriv" | grep -q '"permissionDecision":"deny"' || fail "a wake-origin turn was allowed to read private/"
allowplain="$(echo '{"session_id":"sessD","tool_name":"Bash","tool_input":{"command":"echo fine"}}' | RDA_BUS_SH="$BUS" bash "$GUARD")"
[ -z "$allowplain" ] || fail "a wake-origin turn denied an ordinary command: $allowplain"
ok "a wake-origin turn: git push / kb finish / reading private/ denied, ordinary commands allowed"

# --- C: a genuine UserPromptSubmit clears the marker -------------------------
echo '{"session_id":"sessD"}' | bash "$WAKECLEAR"
allowafter="$(echo '{"session_id":"sessD","tool_name":"Bash","tool_input":{"command":"git push origin main"}}' | RDA_BUS_SH="$BUS" bash "$GUARD")"
[ -z "$allowafter" ] || fail "git push was still denied after a genuine prompt cleared the wake marker"
ok "a real UserPromptSubmit clears the wake-origin marker — the next turn is unrestricted again"

echo "test-bus-taint-guard: PASS"
