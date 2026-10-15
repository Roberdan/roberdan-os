#!/usr/bin/env bash
# Extends the presence suite with root-session election and native hook observations.
echo "== automatic mixed-host coordination =="
team() { b team --repo automatic --json "$@"; }
identity_before="$(cat "$TMP/.bus-role" 2>/dev/null || true)"
a="$(team --session cp-A --host copilot)" || fail "Copilot registration failed"
bstate="$(team --session cc-B --host claude)" || fail "Claude registration failed"
jq -e '.coordinator=="cp-A" and .mode=="solo"' <<<"$a" >/dev/null || fail "first session did not lead"
jq -e '.coordinator=="cp-A" and .mode=="worker" and (.members|length)==2' <<<"$bstate" >/dev/null \
  || fail "second host stole leadership or could not see the first"
[ "$(cat "$TMP/.bus-role" 2>/dev/null || true)" = "$identity_before" ] \
  || fail "automatic registration overwrote checkout-wide identity"
ok "mixed hosts elect one sticky coordinator with per-session roles"

for s in 1 2 3 4 5 6; do
  team --session "parallel-$s" --host copilot > "$TMP/result-$s" &
done
wait
for s in 1 2 3 4 5 6; do
  jq -e '.coordinator=="cp-A"' "$TMP/result-$s" >/dev/null || fail "concurrent join changed the leader"
done
final="$(team --session cp-A --status)"
jq -e '(.members|length)==8' <<<"$final" >/dev/null || fail "parallel registrations lost a session"
jq -s -e 'all(.[]; .coordinator=="cp-A")' "$RDA_BUS_HOME/automatic/.team.jsonl" >/dev/null \
  || fail "concurrent appends elected multiple leaders or damaged the log"
ok "parallel arrivals serialize without loss or multiple leaders"

echo "task ownership" | b send --repo automatic --card coordination \
  --from implementer--cp-A --to implementer--cc-B --kind request >/dev/null || fail "alias addressing failed"
counts="$(b count --repo automatic --present)"
grep -q 'implementer--cc-B' <<<"$counts" || fail "present-only count omitted automatic workers"
wrong="$(b read --repo automatic --card coordination --as implementer--parallel-1)"
grep -q "task ownership" <<<"$wrong" && fail "one worker received another worker's message"
right="$(b read --repo automatic --card coordination --as implementer--cc-B)"
grep -q "task ownership" <<<"$right" || fail "another worker's read consumed the actual addressee's mail"
echo "ownership confirmed" | b send --repo automatic --card coordination \
  --from implementer--cc-B --to implementer--cp-A --kind verdict --re 1 >/dev/null || fail "worker reply failed"
[ "$(b owed --repo automatic --as implementer--cc-B --brief | grep -c '^  coordination' || true)" = "0" ] \
  || fail "reply to coordinator did not discharge the debt"
ok "distinct worker cursors and cited replies preserve a real conversation"

team --session cp-A --leave >/dev/null || fail "departure failed"
after="$(team --session cc-B --status)"
[ "$(jq -r '.coordinator' <<<"$after")" != "cp-A" ] || fail "departed leader still owns coordination"
# Simulate interrupted/idle host observations by aging only that session's records.
leader="$(jq -r '.coordinator' <<<"$after")"
jq -c --arg s "$leader" 'if .session==$s then .seen-=1000 else . end' \
  "$RDA_BUS_HOME/automatic/.team.jsonl" > "$TMP/aged"
cp "$TMP/aged" "$RDA_BUS_HOME/automatic/.team.jsonl"
after="$(team --session replacement --host claude)"
[ "$(jq -r '.coordinator' <<<"$after")" != "$leader" ] || fail "inactive leader did not yield"
incumbent="$(jq -r '.coordinator' <<<"$after")"
after="$(team --session cp-A --host copilot)"
[ "$(jq -r '.coordinator' <<<"$after")" = "$incumbent" ] || fail "returning old leader preempted the new leader"
ok "departure, inactivity and returning sessions preserve one incumbent"

other="$(b team --repo another-project --session cp-A --host copilot --json)"
jq -e '.mode=="solo" and (.members|length)==1' <<<"$other" >/dev/null || fail "repositories leaked membership"
from_main="$(cd "$MAIN" && b team --session main-host --host claude --json)"
from_wt="$(cd "$TMP/wt-card" && b team --session worktree-host --host copilot --json)"
[ "$(jq -r '.repo' <<<"$from_main")" = "$(jq -r '.repo' <<<"$from_wt")" ] || fail "worktrees elected separate teams"
ok "different repositories isolate teams; linked worktrees share the project"

env RDA_HEADLESS=1 RDA_BUS_HOME="$RDA_BUS_HOME" bash "$BUS" team --repo automatic --session headless >/dev/null 2>&1 \
  && fail "headless session entered the election"
team --session '../invalid' >/dev/null 2>&1 && fail "session traversal accepted"
env RDA_BUS_TEAM_TTL=invalid RDA_BUS_HOME="$RDA_BUS_HOME" bash "$BUS" team --repo automatic --session invalid >/dev/null 2>&1 \
  && fail "invalid inactivity setting was silently defaulted"
printf 'not JSON\n' > "$RDA_BUS_HOME/broken-team.jsonl"
mkdir -p "$RDA_BUS_HOME/broken"
cp "$RDA_BUS_HOME/broken-team.jsonl" "$RDA_BUS_HOME/broken/.team.jsonl"
b team --repo broken --session broken --json >/dev/null 2>&1 && fail "damaged election reported success"
ok "invalid inputs, headless sessions and corrupt observations fail explicitly"

export TMPDIR="$TMP/coordination-stamps"; mkdir -p "$TMPDIR"
HOOK="$ROOT/hooks/bus-coordination.sh"
hook() {
  jq -cn --arg sid "$1" --arg event "$2" --arg cwd "$WORK" \
    '{session_id:$sid,cwd:$cwd,hook_event_name:$event,host:"claude"}' \
    | RDA_OS="$ROOT" RDA_BUS_COORDINATION=1 bash "$HOOK"
}
# Use an untouched repository directory so manual presence fixtures do not affect membership.
WORK="$TMP/hook-project"; mkdir -p "$WORK"
one="$(hook live-A SessionStart)"
grep -q "No second recently observed" <<<"$one" || fail "solo hook falsely claimed a team"
two="$(hook live-B SessionStart)"
grep -q "YOU are a worker" <<<"$two" || fail "second session got no worker instruction"
promoted="$(hook live-A PreToolUse)"
jq -e '.hookSpecificOutput.hookEventName=="PreToolUse"' <<<"$promoted" >/dev/null \
  || fail "Claude cannot receive coordination context at PreToolUse"
grep -q "YOU coordinate" <<<"$promoted" || fail "first host never learned it is coordinating"
grep -q "UNVERIFIED" <<<"$promoted" || fail "coordination advice forgot provenance and authority boundaries"
[ -z "$(hook live-A PreToolUse)" ] || fail "unchanged membership spammed every tool call"
# Announced bodies never travel through the hook and cursors remain untouched.
echo "PRIVATE-BODY-NOT-AUTO-CONTEXT" | b send --repo hook-project --card coordination \
  --from implementer--live-B --to implementer--live-A >/dev/null
notification="$(hook live-A PreToolUse)"
grep -q "coordination" <<<"$notification" || fail "read-only worker missed new coordination mail"
grep -q "PRIVATE-BODY" <<<"$notification" && fail "mail notification leaked the body"
third="$(hook live-C SessionStart)"
grep -q "PRIVATE-BODY" <<<"$third" && fail "hook auto-delivered a message body"
[ ! -e "$RDA_BUS_HOME/hook-project/.cursor/coordination/implementer--live-A" ] \
  || fail "hook consumed mail"
hook live-A SessionEnd >/dev/null
takeover="$(hook live-B PreToolUse)"
grep -q "YOU coordinate" <<<"$takeover" || fail "native departure did not transfer coordination"
grep -q "bus log --repo" <<<"$takeover" || fail "new coordinator forgot prior assignments"
ok "native hooks inject role changes, never bodies or cursor advances, and suppress noise"

before="$(wc -l < "$RDA_BUS_HOME/hook-project/.team.jsonl")"
jq -cn --arg cwd "$WORK" '{session_id:"verifier",cwd:$cwd}' \
  | RDA_OS="$ROOT" RDA_HEADLESS=1 bash "$HOOK" >/dev/null
jq -cn --arg cwd "$WORK" '{session_id:"disabled",cwd:$cwd}' \
  | RDA_OS="$ROOT" RDA_BUS_COORDINATION=0 bash "$HOOK" >/dev/null
[ "$(wc -l < "$RDA_BUS_HOME/hook-project/.team.jsonl")" = "$before" ] \
  || fail "disabled/headless hook registered a participant"
ok "headless and explicitly disabled hooks leave membership untouched"

WORK="$TMP/solo-project"; mkdir -p "$WORK"
hook solo-A SessionStart >/dev/null
hook solo-B SessionStart >/dev/null
echo "SOLO-REQUEST-BODY-MUST-STAY-PRIVATE" | b send --repo solo-project --card coordination \
  --from implementer--solo-A --to implementer--solo-B --kind request >/dev/null
hook solo-A SessionEnd >/dev/null
solo_notice="$(hook solo-B PreToolUse)"
grep -q "No second recently observed" <<<"$solo_notice" || fail "surviving worker did not become solo"
grep -q "QUESTIONS/REQUESTS" <<<"$solo_notice" || fail "solo takeover dropped the pending request notification"
grep -q "SOLO-REQUEST-BODY" <<<"$solo_notice" && fail "solo notification leaked the request body"
[ ! -e "$RDA_BUS_HOME/solo-project/.cursor/coordination/implementer--solo-B" ] \
  || fail "solo notification consumed the request"
ok "a worker becoming solo still receives pending mail without bodies or cursor advances"
