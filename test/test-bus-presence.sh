#!/usr/bin/env bash
# test-bus-presence.sh — who is here, who left, and who each session is.
#
# The shared fixture lives in test/lib-bus-team.sh: one store, one pair of
# helpers, and every call made through a CLEAN environment, because the identity
# features are the point and inheriting the caller's would make half of this pass
# for the wrong reason.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-bus-team.sh"

echo "== the bus: presence and identity =="


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

echo "PASS: test-bus-presence.sh"
