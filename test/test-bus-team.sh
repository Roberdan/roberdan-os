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
