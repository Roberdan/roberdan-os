#!/usr/bin/env bash
# test-bus-owed.sh — a question that was read is not a question that was answered.
#
# The shared fixture lives in test/lib-bus-team.sh: one store, one pair of
# helpers, and every call made through a CLEAN environment, because the identity
# features are the point and inheriting the caller's would make half of this pass
# for the wrong reason.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-bus-team.sh"

echo "== the bus: what is owed, and the noise that buried it =="

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
# Checked by BEHAVIOUR, not by grepping for a command name: the briefing was four
# calls and became one (`hello --arrival`) to stop paying 1.4s at every session
# start, and a check that pins the spelling would have failed on a change that
# preserved the property perfectly. What must hold is that another agent's prose
# never lands in the context automatically.
PROSE="zzprosezz-another-agents-sentence"
env RDA_BUS_ROLE=architect RDA_BUS_HOME="$RDA_BUS_HOME" \
  bash "$BUS" hello --repo "$R" --as architect --session prose-sess --doing "$PROSE" >/dev/null 2>&1
briefing="$(env RDA_BUS_ROLE=qa-gate RDA_BUS_HOME="$RDA_BUS_HOME" \
  bash "$BUS" hello --repo "$R" --as qa-gate --session reader-sess --arrival 2>/dev/null)"
[ -n "$briefing" ] || fail "the arrival briefing printed nothing"
grep -q "prose-sess" <<<"$briefing" \
  || fail "the arrival briefing does not name the other session at all: then nobody learns who is here"
grep -q "$PROSE" <<<"$briefing" \
  && fail "the arrival briefing carries another agent's own sentence into the context automatically"
# Two greps, not one: the call is split across lines with a continuation, and a
# single-line pattern would report the hook as broken while it works.
grep -q 'bus.sh" hello' "$ROOT/hooks/context-inject.sh" \
  && grep -q -- '--arrival' "$ROOT/hooks/context-inject.sh" \
  || fail "hooks/context-inject.sh does not use the facts-only arrival briefing"
ok "the session-start briefing names who is here and carries none of their prose"

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
# 4. "DA LEGGERE": A NOTE (or a verdict, or anything else) IS NOT A QUESTION, so
#    it never appeared in the section above — and an agent that checks only
#    `bus owed` reads it late. Card 260924-120127, real: an agent checked only
#    `bus owed` and read an important note late; three threads of already-closed
#    cards were still open because nothing ever closed them (that half is
#    test-kb-done-gate.sh — "kb finish closes the card's bus thread").
NOTE_TXT="zzda-leggerezz-a-note-nobody-asked-for"
printf '%s\n' "$NOTE_TXT" \
  | as architect sess-A send --card note-thread --to implementer --kind note >/dev/null 2>&1 \
  || fail "could not send the note fixture"

owed_before_read="$(as implementer sess-B owed --card note-thread 2>/dev/null)"
grep -q "owes no answer" <<<"$owed_before_read" \
  || fail "a NOTE is being treated as something owed an answer — it is not a question"
grep -q "DA LEGGERE" <<<"$owed_before_read" \
  || fail "THE CORE REGRESSION (card 260924-120127): an unread note never appears in bus owed"
grep -q '#1' <<<"$owed_before_read" \
  || fail "the da-leggere entry carries no record number"
ok "an unread note appears in bus owed, under 'da leggere', even though it owes no answer"

# The row names card/seq/sender/kind — never the body, in EITHER form. A note can
# say anything; `bus owed`'s own discipline (see 3d above) is that a body only
# ever arrives through an explicit `bus read`, stamped UNVERIFIED.
grep -q "$NOTE_TXT" <<<"$owed_before_read" \
  && fail "the da-leggere section rendered the note's BODY — this is what the doorbell reuses verbatim"
ok "da leggere never shows a body, even in the non-brief form"

# A READ clears it — same cursor `bus read` already advances, nothing new to keep
# in sync. Answering does NOT clear it (a note has nothing to answer); only
# reading does.
as implementer sess-B read --card note-thread >/dev/null 2>&1 \
  || fail "could not read the note fixture"
owed_after_read="$(as implementer sess-B owed --card note-thread 2>/dev/null)"
grep -q "has nothing unread" <<<"$owed_after_read" \
  || fail "reading the note did not clear it from da leggere: $owed_after_read"
ok "a bus read clears the note from da leggere"

# MAIL YOU SENT YOURSELF MUST NOT APPEAR — neither a direct self-address nor a
# broadcast the sender itself receives back.
echo "note to myself" \
  | as architect sess-A send --card self-thread --to architect --kind note >/dev/null 2>&1
echo "broadcast from myself" \
  | as architect sess-A send --card self-thread --to all --kind note >/dev/null 2>&1
selfowed="$(as architect sess-A owed --card self-thread 2>/dev/null)"
grep -q "has nothing unread" <<<"$selfowed" \
  || fail "mail the reader sent to itself (direct or broadcast) counted as something to read: $selfowed"
ok "mail sent to yourself, direct or broadcast, never appears in da leggere"

# A QUESTION lives in BOTH sections until it is both read and answered — "da
# rispondere" and "da leggere" are independent, and one never substitutes the
# other. This is the same third-party-question fixture as 3c, re-read here.
both="$(as implementer sess-B owed --card "$C" 2>/dev/null)"
grep -q "waiting for an answer" <<<"$both" \
  || fail "the still-unanswered questions on $C vanished from da rispondere"
grep -q "DA LEGGERE" <<<"$both" \
  || fail "an UNREAD (never-\`bus read\`) question does not also show as unread — da leggere must cover any kind"
ok "an unread question appears in both sections until it is read and answered"

# ---------------------------------------------------------------------------
echo "PASS: test-bus-owed.sh"
