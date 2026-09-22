#!/usr/bin/env bash
# test-bus-team.sh — the bus works as a TEAM CHANNEL, not as a noticeboard.
#
# WHY THIS FILE EXISTS. test-bus.sh proves the bus is SAFE: it never starts an
# agent, never writes kanban state, never loses a message. Every one of those
# checks passed on 2026-09-22, on a store where the channel was not being used
# as a channel at all. Measured that morning, before anything here was written:
#
#     167 messages across 31 threads
#     13 threads with exactly ONE sender      — somebody talked, nobody answered
#     14 threads with NO reader cursor at all — nobody ever opened them
#      1 thread where a role read 37 of 38 messages and sent one
#
# Roberto's verdict, and it is the specification this file tests: "either they
# talk and nobody listens, or they listen and nobody talks."
#
# So this suite asserts the properties that make a conversation possible, and
# each check names the failure it would have caught. Safety stays in test-bus.sh;
# nothing here weakens it, and the two run together in validate.sh.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUS="$ROOT/bus/bus.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# RUN FROM THE TEMP DIRECTORY, NOT FROM THE CHECKOUT. `bus hello` leaves a
# `.bus-role` at the top of the worktree it is run in — that is the whole point
# of it — so a suite that ran from the repo would write into the real checkout,
# and when that checkout is a per-card worktree it also trips
# test-worktree-sweep.sh, which asserts that no suite creates or removes anything
# under ~/GitHub/worktrees. Caught exactly that way, by that suite, not by review.
cd "$TMP" || exit 1

export RDA_BUS_HOME="$TMP/bus"
R="team-repo"
C="260922-card"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

# Every call goes through a CLEAN environment. The identity features are the
# point of this suite, so inheriting the identity of the shell that runs the
# tests would make half of it pass for the wrong reason.
b() { env -u RDA_BUS_ROLE -u RDA_BUS_SESSION -u RDA_BUS_REPO \
        RDA_BUS_HOME="$RDA_BUS_HOME" bash "$BUS" "$@"; }
# A session: identity in the environment, the way a sub-process inherits it.
as() {
  local role="$1" sess="$2"; shift 2
  env RDA_BUS_ROLE="$role" RDA_BUS_SESSION="$sess" RDA_BUS_REPO="$R" \
      RDA_BUS_HOME="$RDA_BUS_HOME" bash "$BUS" "$@"
}

echo "== the bus as a team channel =="

# ---------------------------------------------------------------------------
# 1. TWO SESSIONS ANNOUNCE THEMSELVES AND CAN SEE EACH OTHER.
#    Before: presence was inferred from the last append, so an agent could only
#    learn that somebody had once been there — never who is here now, on what.
#    An agent with nobody to address addresses nobody.
# ---------------------------------------------------------------------------
as architect   sess-A hello --repo "$R" --card "$C" --doing "weighing two options" >/dev/null 2>&1 \
  || fail "a session could not announce itself"
as implementer sess-B hello --repo "$R" --card "$C" --doing "writing the code"     >/dev/null 2>&1 \
  || fail "a second session could not announce itself"

who="$(b who --repo "$R" 2>/dev/null)"
grep -q "DECLARED" <<<"$who"    || fail "who does not report declared presence at all"
grep -q "sess-A"   <<<"$who"    || fail "who does not show the first session that announced itself"
grep -q "sess-B"   <<<"$who"    || fail "who does not show the second session: two agents on one repo still cannot see each other"
grep -q "weighing two options" <<<"$who" \
  || fail "who shows a session but not what it said it is doing — 'who is here' without 'on what' is what we already had"
ok "two sessions announce themselves and both appear, with what they are doing"

# 1b. DECLARED IS NEVER MERGED INTO OBSERVED. A session that was killed cannot
#     retract its hello, so a view that presents a declaration as evidence is a
#     lie with a timestamp on it.
grep -q "OBSERVED" <<<"$who" \
  || fail "who no longer separates observed activity from declared presence"
[ "$(grep -n 'OBSERVED' <<<"$who" | cut -d: -f1)" -lt "$(grep -n 'DECLARED' <<<"$who" | cut -d: -f1)" ] \
  || fail "the claim is printed before the evidence"
ok "declared presence is printed next to observed activity, never instead of it"

# 1c. PRESENCE IS NOT A LEASE. The 2026-07 board cut leases because they bind a
#     role to N instances and because a stray session renews them behind your
#     back. An append-only event log has neither property — and test 12 of
#     test-bus.sh forbids the registry shape outright.
[ ! -e "$RDA_BUS_HOME/$R/subscribers" ] \
  || fail "a subscriber registry appeared"
[ -f "$RDA_BUS_HOME/$R/.presence.jsonl" ] \
  || fail "presence is not an append-only log where the rest of the system can audit it"
pbefore="$(wc -l < "$RDA_BUS_HOME/$R/.presence.jsonl" | tr -d ' ')"
as architect sess-A hello --repo "$R" --card "$C" --doing "still here" >/dev/null 2>&1
pafter="$(wc -l < "$RDA_BUS_HOME/$R/.presence.jsonl" | tr -d ' ')"
[ "$pafter" -gt "$pbefore" ] \
  || fail "a second hello REWROTE the presence record: that is a lease being renewed, not an event being appended"
ok "presence is append-only: a second hello adds a record, it never refreshes one"

# 1d. FREE PROSE ON THE PRESENCE LOG PASSES THE SAME PRIVACY GATE AS A MESSAGE.
#     `--doing` and `--why` are prose kept forever in a store that lives outside
#     every git tree, so nothing else will ever scan them. `send` runs
#     leak-check on every body; presence was a second door into the same
#     permanent archive with a weaker policy — which is how a declared property
#     stops being true without anybody deciding to drop it.
cat > "$TMP/leak-stub.sh" <<'LEAKEOF'
#!/usr/bin/env bash
# Refuses anything containing the marker, the way the real one refuses a term.
grep -q "zzconfidentialzz" "$2" && exit 1
exit 0
LEAKEOF
chmod +x "$TMP/leak-stub.sh"
refused="$(env RDA_BUS_ROLE=architect RDA_BUS_SESSION=sess-leak RDA_BUS_REPO="$R" \
  RDA_BUS_HOME="$RDA_BUS_HOME" RDA_LEAKCHECK="$TMP/leak-stub.sh" \
  bash "$BUS" hello --repo "$R" --as architect --doing "zzconfidentialzz" 2>&1 || true)"
grep -qi "leak-check\|BLOCKED" <<<"$refused" \
  || fail "a presence note went into the permanent store without the privacy gate a message body gets: $refused"
grep -q "zzconfidentialzz" "$RDA_BUS_HOME/$R/.presence.jsonl" \
  && fail "the refused note was written anyway"
missing="$(env RDA_BUS_ROLE=architect RDA_BUS_HOME="$RDA_BUS_HOME" \
  RDA_LEAKCHECK="$TMP/nothing-here.sh" \
  bash "$BUS" hello --repo "$R" --as architect --doing "anything" 2>&1 || true)"
grep -qi "not executable\|leak-check" <<<"$missing" \
  || fail "a missing leak-check did not fail closed on the presence path: $missing"
ok "a presence note is scanned like a message body, and fails closed when the scanner is gone"

# ---------------------------------------------------------------------------
# 2. A QUESTION SURVIVES THE CURSOR.
#    THE failure this whole change exists for. A question used to be delivered
#    once and then vanish: the reader who meant to answer "after one more thing"
#    had no artifact to come back to, and the asker could not tell "read and
#    ignored" from "never arrived".
# ---------------------------------------------------------------------------
echo "cache: option A or option B?" \
  | as architect sess-A send --card "$C" --to implementer --kind question >/dev/null 2>&1 \
  || fail "a question could not be sent"

first="$(as implementer sess-B read --card "$C" 2>/dev/null)"
grep -q "option A or option B" <<<"$first" \
  || fail "the question was not delivered at all"
grep -qi "ASKS YOU FOR AN ANSWER" <<<"$first" \
  || fail "a question renders exactly like a note: nothing tells the reader an answer is expected of them"
grep -q '#1' <<<"$first" \
  || fail "the message carries no number, so there is nothing for a reply to cite"
ok "a question says it is a question, and carries the number a reply can cite"

again="$(as implementer sess-B read --card "$C" 2>/dev/null)"
grep -q "nothing new" <<<"$again" \
  || fail "the cursor did not advance — this suite would then prove nothing about surviving it"
owed="$(as implementer sess-B owed 2>/dev/null)"
grep -q "option A or option B" <<<"$owed" \
  || fail "THE CORE REGRESSION: once read, an unanswered question is invisible again"
ok "after the cursor has moved past it, the unanswered question is still listed"

# 2b. IT IS THE ADDRESSEE'S DEBT, NOT EVERYONE'S. A reminder delivered to people
#     who cannot discharge it is how a reminder becomes noise and then silence.
owed_other="$(as architect sess-A owed 2>/dev/null)"
grep -q "owes no answer" <<<"$owed_other" \
  || fail "the asker is told it owes an answer to its own question"
ok "only the role a question was addressed to is told it owes an answer"

# ---------------------------------------------------------------------------
# 3. ANSWERING MEANS CITING, AND ONLY CITING DISCHARGES IT.
#    A reply that does not cite leaves the asker unable to tell an answer from
#    silence — which is the state the whole store was in.
# ---------------------------------------------------------------------------
echo "B, writes dominate here" \
  | as implementer sess-B send --card "$C" --to architect --kind verdict >/dev/null 2>&1
still="$(as implementer sess-B owed 2>/dev/null)"
grep -q "cache: option A" <<<"$still" \
  || fail "an uncited message discharged the question: then --re means nothing"
ok "a reply that cites nothing does not discharge the question"

echo "B, writes dominate here" \
  | as implementer sess-B send --card "$C" --to architect --re 1 --kind verdict >/dev/null 2>&1 \
  || fail "a cited reply was refused"
cleared="$(as implementer sess-B owed 2>/dev/null)"
grep -q "owes no answer" <<<"$cleared" \
  || fail "citing the question with --re did not discharge it"
ok "citing the question with --re discharges it, and nothing else does"

# 3c. AND THE CITATION HAS TO REACH THE ASKER. Citing the record was enough on
#     its own until an adversarial review reproduced it: a message citing #N and
#     addressed to a THIRD role cleared the debt while the asker received
#     nothing, so the channel printed "no answer owed" next to somebody who had
#     been answered by nobody.
echo "third-party question" \
  | as architect sess-A send --card "$C" --to implementer --kind question >/dev/null 2>&1
owedout="$(as implementer sess-B owed 2>/dev/null)"
grep -q 'third-party' <<<"$owedout" || fail "the setup for the third-party check did not land"
# The record number is READ OUT OF THE LISTING, never assumed. Hard-coding it got
# this check wrong on the first run for exactly the reason the number exists: the
# position of a record depends on everything sent before it.
SEQ3="$(awk '/third-party/ {print prev} {prev=$0}' <<<"$owedout" | grep -oE '#[0-9]+' | tr -d '#' | tail -1)"
[ -n "$SEQ3" ] || fail "could not read the record number out of the owed listing"
echo "answering, but to somebody else" \
  | as implementer sess-B send --card "$C" --to qa-gate --re "$SEQ3" --kind verdict >/dev/null 2>&1
still3="$(as implementer sess-B owed 2>/dev/null | grep -c 'third-party' || true)"
[ "$still3" = "1" ] \
  || fail "a citation addressed to a THIRD role discharged the question: the asker got nothing and the channel called it answered"
echo "answering the asker" \
  | as implementer sess-B send --card "$C" --to architect --re "$SEQ3" --kind verdict >/dev/null 2>&1
gone3="$(as implementer sess-B owed 2>/dev/null | grep -c 'third-party' || true)"
[ "$gone3" = "0" ] \
  || fail "a citation addressed to the asker did not discharge the question"
ok "a citation only discharges a question when it is addressed to the one who asked"

# 3d. WHAT THE DOORBELL MAY PUSH INTO A MODEL'S CONTEXT CARRIES NO BODY.
#     `bus owed` renders the first line of each unanswered message. That output
#     was being injected automatically at PostToolUse, which rebuilds by hand the
#     exact harm the 2026-07 board cut context-inject delivery for: another
#     agent's prose arriving as context, without the UNVERIFIED stamp. Being the
#     addressee is not a reason: it says nothing about whether the words are safe.
SECRET="zzmarkerzz-body-that-must-not-be-pushed"
printf '%s\n' "$SECRET" \
  | as architect sess-A send --card "$C" --to implementer --kind question >/dev/null 2>&1
full="$(as implementer sess-B owed 2>/dev/null)"
grep -q "$SECRET" <<<"$full" \
  || fail "the explicit form stopped showing the body: then this check proves nothing"
brief="$(as implementer sess-B owed --brief 2>/dev/null)"
grep -q "$SECRET" <<<"$brief" \
  && fail "--brief rendered a body — this is what the doorbell pushes into the model's context"
grep -q "#" <<<"$brief" \
  || fail "--brief rendered nothing useful: it must still say who asked, where, and which record"
ok "--brief names the asker, the card and the record, and never a word of what was said"

# 3e. AND THE DOORBELL ACTUALLY USES IT. A flag nobody calls is not a boundary.
grep -q 'owed .*--brief' "$ROOT/hooks/bus-doorbell.sh" \
  || fail "hooks/bus-doorbell.sh does not ask for --brief, so a body can still reach the context"
ok "the doorbell asks for the body-free form"

# 3f. AND SO DOES THE SESSION-START CONTEXT, which is the other place output is
#     pushed at a model rather than asked for. It shows the roster now — the
#     first version only printed the COMMAND, which is the same failure one
#     level up: the mail was fixed and the list of who is here stayed behind a
#     command nobody types.
grep -q 'who .*--brief' "$ROOT/hooks/context-inject.sh" \
  || fail "hooks/context-inject.sh does not ask for the facts-only roster, so another agent's prose can reach the context at startup"
grep -q 'bus.sh" who --repo "\$_brepo" 2>/dev/null' "$ROOT/hooks/context-inject.sh" \
  && fail "hooks/context-inject.sh injects the full roster, prose included"
ok "the session-start roster is the facts-only form"

# 3g. THE DOORBELL DOES NOT RING FOR MAIL NOBODY CAN ACT ON.
#     Roberto, 2026-09-22, opening a session: twelve lines of unread counts for
#     four roles nobody was playing, on two cards already in done/ and one card
#     that does not exist. "vorrei che il sistema riuscisse a tenersi pulito e
#     evitare ste robe che non si capisce che cazzo sono."
#     The cost is not the twelve lines: a doorbell that rings for mail nobody can
#     act on teaches the reader to stop hearing it, and then the message that
#     mattered arrives inside noise already learned away.
NOISE="$TMP/noise"; mkdir -p "$NOISE"
NR=noise-repo
echo "broadcast nobody will ever read" \
  | env RDA_BUS_ROLE=architect RDA_BUS_SESSION=n1 RDA_BUS_HOME="$RDA_BUS_HOME" \
      bash "$BUS" send --repo "$NR" --card ghost --from architect --to all >/dev/null 2>&1
allroles="$(b count --repo "$NR" 2>/dev/null | grep -c . || true)"
[ "$allroles" -gt 1 ] \
  || fail "the plain count no longer fans out across roles: then this check proves nothing"
quiet="$(b count --repo "$NR" --present 2>/dev/null | grep -c . || true)"
[ "$quiet" = "0" ] \
  || fail "the doorbell still rings for roles nobody is playing ($quiet lines)"
env RDA_BUS_ROLE=qa-gate RDA_BUS_SESSION=n2 RDA_BUS_HOME="$RDA_BUS_HOME" \
  bash "$BUS" hello --repo "$NR" --as qa-gate --session n2 >/dev/null 2>&1
loud="$(b count --repo "$NR" --present 2>/dev/null | grep -c 'qa-gate' || true)"
[ "$loud" = "1" ] \
  || fail "once a role is actually present, its unread mail must ring — it did not"
ok "the doorbell rings for roles that are present, and is silent for the ones that are not"

# 3h. AND NOTHING IS HIDDEN BY THAT FILTER. The mail is not dropped: it waits,
#     and the role that arrives later is told about it. A filter that made a
#     message unreachable would be the one failure durable delivery cannot have.
arrived="$(env RDA_BUS_ROLE=sol-gate RDA_BUS_HOME="$RDA_BUS_HOME" \
             bash "$BUS" count --repo "$NR" --as sol-gate 2>/dev/null | grep -c 'sol-gate' || true)"
[ "$arrived" = "1" ] \
  || fail "a role that asks for its own count is not told about mail the doorbell chose not to ring for"
ok "mail the doorbell stays quiet about is still there, and still counted when that role asks"

# 3i. A THREAD WHOSE WORK IS FINISHED STOPS CALLING — and loses not one word.
#     This is the other half of the same complaint: the three noisy threads
#     belonged to cards in done/, and nothing ever closed them, so they would
#     have counted forever.
TIDYBOARD="$TMP/board"; mkdir -p "$TIDYBOARD/done" "$TIDYBOARD/doing" "$TIDYBOARD/todo"
printf -- '---\ntitle: finita\n---\n' > "$TIDYBOARD/done/ghost.md"
before="$(b log --repo "$NR" --card ghost 2>/dev/null | grep -c 'broadcast nobody' || true)"
[ "$before" = "1" ] || fail "the tidy fixture did not land"
env RDA_KANBAN="$TIDYBOARD" RDA_BUS_HOME="$RDA_BUS_HOME" RDA_BUS_ROLE=orchestrator \
  bash "$BUS" tidy --repo "$NR" --by orchestrator --yes >/dev/null 2>&1 \
  || fail "tidy failed on a card that is done"
after="$(b count --repo "$NR" 2>/dev/null | grep -c 'ghost' || true)"
[ "$after" = "0" ] \
  || fail "a thread whose card is done still counts: it will nag forever"
kept="$(b log --repo "$NR" --card ghost 2>/dev/null | grep -c 'broadcast nobody' || true)"
[ "$kept" = "1" ] \
  || fail "tidy LOST the thread — closing must keep every word, the reasoning is what the kanban does not store"
ok "a thread on finished work stops counting, and every word of it is still readable"

# 3j. AND TIDY NEVER TOUCHES WORK THAT IS STILL OPEN.
echo "live thread" \
  | env RDA_BUS_ROLE=architect RDA_BUS_HOME="$RDA_BUS_HOME" \
      bash "$BUS" send --repo "$NR" --card alive --from architect --to qa-gate >/dev/null 2>&1
printf -- '---\ntitle: in corso\n---\n' > "$TIDYBOARD/doing/alive.md"
env RDA_KANBAN="$TIDYBOARD" RDA_BUS_HOME="$RDA_BUS_HOME" RDA_BUS_ROLE=orchestrator \
  bash "$BUS" tidy --repo "$NR" --by orchestrator --yes >/dev/null 2>&1
stillalive="$(b count --repo "$NR" --as qa-gate 2>/dev/null | grep -c 'alive' || true)"
[ "$stillalive" = "1" ] \
  || fail "tidy closed a thread whose card is still being worked on"
ok "tidy leaves alone every thread whose card is still open"

# 3b. --re IS VALIDATED, NOT TRUSTED. A reply pointing at a record that does not
#     exist would discharge an obligation that was never met.
out="$(echo "x" | as implementer sess-B send --card "$C" --to architect --re 999 --kind verdict 2>&1 || true)"
grep -qi "only\|record" <<<"$out" || fail "--re pointing past the end of the thread was accepted: $out"
out="$(echo "x" | as implementer sess-B send --card "$C" --to architect --re "abc" --kind verdict 2>&1 || true)"
grep -qi "number" <<<"$out" || fail "--re accepted something that is not a record number: $out"
ok "--re is checked against the thread: it cannot cite a record that does not exist"

# ---------------------------------------------------------------------------
# 4. IDENTITY SURVIVES THE NEXT COMMAND.
#    On at least one host every shell command runs in a fresh process, so an
#    exported identity lasts exactly one call. An identity that has to be retyped
#    is an identity that gets forgotten — which is how `--as` was lost.
# ---------------------------------------------------------------------------
WORK="$TMP/work"; mkdir -p "$WORK/sub"
( cd "$WORK" && git init -q . 2>/dev/null ) || fail "could not make a test checkout"
( cd "$WORK" && env -u RDA_BUS_ROLE -u RDA_BUS_SESSION RDA_BUS_HOME="$RDA_BUS_HOME" \
    bash "$BUS" hello --repo "$R" --as qa-gate --session sess-C >/dev/null 2>&1 ) \
  || fail "hello failed inside a checkout"
[ -f "$WORK/.bus-role" ] || fail "hello left nothing behind: the next command has no way to know who it is"
solo="$(cd "$WORK/sub" && env -u RDA_BUS_ROLE -u RDA_BUS_SESSION -u RDA_BUS_REPO \
          RDA_BUS_HOME="$RDA_BUS_HOME" bash "$BUS" owed --repo "$R" 2>&1)"
grep -q "qa-gate" <<<"$solo" \
  || fail "a fresh process in a sub-directory could not work out who it is: $solo"
ok "identity survives into a later, unrelated command, from a sub-directory too"

# 4b. IT IS NOT A REGISTRY IN THE STORE. The file lives next to the work, like
#     .gbrain-source. Inside the store it would be the shape test 12 refuses.
[ ! -e "$RDA_BUS_HOME/$R/.bus-role" ] \
  || fail "the identity file was written into the bus store, where it becomes a registry"
ok "the identity file lives in the worktree, not in the bus store"

# 4c. THE SESSION NAME SURVIVES TOO, AND LEAVING OUT THIS CHECK BUILT A GHOST.
#     Found by @rex, reproduced live: the role had a file fallback and the session
#     did not, so `hello` in one process invented one name and `bye` in the next
#     process invented another. The goodbye landed on a session nobody had ever
#     announced and the first one stayed DECLARED forever — and that is the exact
#     sequence every agents/*.md teaches, hello in one command and bye in another.
#     It survived the first version of this suite because the helper above passes
#     the SAME session literal on every call, which is a usage nobody has.
GHOST="$TMP/ghost"; mkdir -p "$GHOST"
( cd "$GHOST" && env -u RDA_BUS_ROLE -u RDA_BUS_SESSION RDA_BUS_HOME="$RDA_BUS_HOME" \
    bash "$BUS" hello --repo "$R" --as reviewer --card "$C" --doing "two processes" >/dev/null 2>&1 ) \
  || fail "hello failed in the ghost check"
( cd "$GHOST" && env -u RDA_BUS_ROLE -u RDA_BUS_SESSION RDA_BUS_HOME="$RDA_BUS_HOME" \
    bash "$BUS" bye --repo "$R" >/dev/null 2>&1 ) \
  || fail "bye failed in the ghost check"
ghosts="$(b who --repo "$R" 2>/dev/null | grep -c "reviewer" || true)"
[ "$ghosts" = "0" ] \
  || fail "a session that said hello in one process and bye in the next is still DECLARED present: the goodbye went to a different session id"
ok "hello and bye in two separate processes name the SAME session, so nobody is left behind"

# 4d. AND A NEW SESSION MUST NOT INHERIT SOMEBODY ELSE'S NAME. The check above
#     created the hazard the moment it fixed the first one: a role is a job
#     description and inheriting it is right, but a session name is an INSTANCE.
#     A session that picks one up from a parent directory is two sessions
#     answering to one name, and its `bye` withdraws the other one's presence —
#     the stray session renewing a lease behind your back, which is what the
#     2026-07 board cut leases to prevent, walking back in through a file.
#     This suite caught it BY ACCIDENT, one directory deep. An accident is not a
#     net, so it is pinned here.
INNER="$GHOST/inner"; mkdir -p "$INNER"
( cd "$GHOST" && env -u RDA_BUS_ROLE -u RDA_BUS_SESSION RDA_BUS_HOME="$RDA_BUS_HOME" \
    bash "$BUS" hello --repo "$R" --as architect --session sess-outer --card "$C" >/dev/null 2>&1 )
( cd "$INNER" && env -u RDA_BUS_ROLE -u RDA_BUS_SESSION RDA_BUS_HOME="$RDA_BUS_HOME" \
    bash "$BUS" hello --repo "$R" --as qa-gate --card "$C" >/dev/null 2>&1 ) \
  || fail "hello failed in a sub-directory"
( cd "$INNER" && env -u RDA_BUS_ROLE -u RDA_BUS_SESSION RDA_BUS_HOME="$RDA_BUS_HOME" \
    bash "$BUS" bye --repo "$R" >/dev/null 2>&1 )
outer="$(b who --repo "$R" 2>/dev/null | grep -c "sess-outer" || true)"
[ "$outer" = "1" ] \
  || fail "a session announced in a sub-directory inherited the session name above it, and its goodbye withdrew that one's presence"
( cd "$GHOST" && env -u RDA_BUS_ROLE -u RDA_BUS_SESSION RDA_BUS_HOME="$RDA_BUS_HOME" \
    bash "$BUS" bye --repo "$R" --session sess-outer >/dev/null 2>&1 )
ok "announcing a session mints a fresh name: it never inherits the one above it"

# ---------------------------------------------------------------------------
# 5. THE REPO IS WORKED OUT FROM THE MAIN CHECKOUT, NEVER FROM THE WORKTREE.
#    THE SILENT ONE. `kb start` gives every card its own worktree and the canon
#    says to work there; `git rev-parse --show-toplevel` answers <card-id> there.
#    So two agents on two cards of the same project were writing to two different
#    repos on this bus and could never meet, and the doorbell was looking for
#    mail under a repo named after a card — it never rang where the work happens.
# ---------------------------------------------------------------------------
MAIN="$TMP/myproject"; mkdir -p "$MAIN"
( cd "$MAIN" && git init -q . && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init ) 2>/dev/null \
  || fail "could not make a test project"
( cd "$MAIN" && git worktree add -q "$TMP/wt-card" -b card/x ) 2>/dev/null \
  || fail "could not make a test worktree"
seen="$(cd "$TMP/wt-card" && env -u RDA_BUS_ROLE -u RDA_BUS_REPO RDA_BUS_HOME="$RDA_BUS_HOME" \
          bash "$BUS" who 2>&1 || true)"
grep -q "myproject" <<<"$seen" \
  || fail "inside a card worktree the bus thinks the repo is the card, so two agents on one project never meet: $seen"
grep -q "wt-card\|card/x" <<<"$seen" \
  && fail "the worktree's own name reached the bus as a repo name: $seen"
ok "inside a per-card worktree the repo resolves to the project, not to the card"

# ---------------------------------------------------------------------------
# 6. LEAVING IS SAID, AND LEAVING WITH UNANSWERED MAIL IS SAID OUT LOUD.
#    Nothing may BLOCK a session from ending — but a session that walks away from
#    a question is the failure this suite exists for, so it is never silent.
# ---------------------------------------------------------------------------
echo "and what about the index?" \
  | as architect sess-A send --card "$C" --to implementer --kind question >/dev/null 2>&1
byeout="$(as implementer sess-B bye --repo "$R" 2>&1)"
grep -qi "never answered\|were never" <<<"$byeout" \
  || fail "a session left with an unanswered question and nothing said so: $byeout"
ok "leaving with unanswered mail is reported, and never blocked"

who2="$(b who --repo "$R" 2>/dev/null)"
grep -q "sess-B" <<<"$who2" \
  && fail "a session that said bye is still shown as present"
grep -q "sess-A" <<<"$who2" \
  || fail "saying bye removed somebody else's presence too"
ok "bye ends that session's presence, and only that one"

# 6b. THE DEBT OUTLIVES THE SESSION. It belongs to the ROLE, because the question
#     was addressed to a role: whoever plays it next inherits the conversation.
inherited="$(as implementer sess-D owed 2>/dev/null)"
grep -q "and what about the index" <<<"$inherited" \
  || fail "the unanswered question died with the session that ignored it"
ok "an unanswered question is inherited by whoever plays that role next"

echo "PASS: test-bus-team.sh"
