#!/usr/bin/env bash
# test-bus-trust.sh — per-session signing (card 260924-142220, item A).
#
# Red-then-green note: every property below was run against the pre-signing
# bus.sh first and failed exactly as expected (no `sig`/`session`/`seq` fields,
# every record UNVERIFIED, `openssl` absent from ALLOWED in test-bus.sh) — see
# the card's report for the interactive transcript. This file is the green,
# repeatable form of that same walk-through.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUS="$ROOT/bus/bus.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export RDA_HOME="$HOME/.roberdan-os"
export RDA_BUS_HOME="$RDA_HOME/bus"
mkdir -p "$HOME" "$TMP/cwd"
REPO=trust-repo; CARD=c1
LOG="$RDA_BUS_HOME/$REPO/$CARD.jsonl"

# RUN FROM A SCRATCH DIRECTORY, NOT FROM THE CHECKOUT — same reason as
# test-bus.sh's canary_run: `hello` leaves `.bus-role`/`.bus-session` at the top
# of the git worktree it runs in, and this suite's cwd would otherwise be the
# actual card worktree, so every run would pollute real work.
runbus() ( cd "$TMP/cwd" && bash "$BUS" "$@" )

# 1. An interactive `hello` mints a key and publishes it on the presence record.
runbus hello --repo "$REPO" --as implementer --session s1 --card "$CARD" --doing x >/dev/null 2>&1
pub="$(jq -r 'select(.session=="s1") | .pubkey' "$RDA_BUS_HOME/$REPO/.presence.jsonl" 2>/dev/null | tail -1)"
[ -n "$pub" ] && [ "$pub" != "null" ] || fail "hello did not publish a pubkey for an interactive session"
ok "interactive hello publishes a signing key on the presence log"

# 2. A signed send round-trips as SIGNED-PEER on read, never the bare word VERIFIED.
echo "trust test body" | RDA_BUS_SESSION=s1 runbus send --repo "$REPO" --card "$CARD" --from implementer --to reviewer --kind note >/dev/null 2>&1
out="$(runbus log --repo "$REPO" --card "$CARD")"
echo "$out" | grep -q "SIGNED-PEER" || fail "a genuinely signed message did not render SIGNED-PEER: $out"
echo "$out" | grep -qE '\bVERIFIED\b' && fail "the bare word VERIFIED leaked into output"
ok "a real signature renders SIGNED-PEER, never bare VERIFIED"

# 3. Tamper: flip one base64 char of the stored signature -> back to UNVERIFIED.
sig="$(jq -r '.sig' "$LOG")"
bad="$(printf '%s' "$sig" | sed 's/^./X/')"
sed -i.bak "s#\"sig\":\"$sig\"#\"sig\":\"$bad\"#" "$LOG"
runbus log --repo "$REPO" --card "$CARD" > "$TMP/tamper.out" 2>&1
grep -q "signature does not verify" "$TMP/tamper.out" \
  || fail "a tampered signature was not caught"
ok "a tampered signature is rejected, not silently trusted"
mv "$LOG.bak" "$LOG"

# 4. After-bye rejection: bye, then a NEW send from the same session (key file
# still on disk) must render UNVERIFIED — the presence log says the session left.
runbus bye --repo "$REPO" --as implementer --session s1 >/dev/null 2>&1
echo "post-bye body" | RDA_BUS_SESSION=s1 runbus send --repo "$REPO" --card "$CARD" --from implementer --to reviewer --kind note >/dev/null 2>&1
runbus log --repo "$REPO" --card "$CARD" | tail -6 | grep -q "no live key for s1" \
  || fail "a message signed after bye still rendered as trusted"
ok "after-bye: a session's key stops verifying the moment it says bye"

# 5. Headless (RDA_HEADLESS=1, the marker factory/engine.sh already sets for
# every unattended claude -p run) never mints a key: risk #4.
RDA_HEADLESS=1 runbus hello --repo "$REPO" --as implementer --session hless --card "$CARD" --doing x >/dev/null 2>&1
hpub="$(jq -r 'select(.session=="hless") | .pubkey' "$RDA_BUS_HOME/$REPO/.presence.jsonl" | tail -1)"
[ "$hpub" = "null" ] || [ -z "$hpub" ] || fail "a headless (RDA_HEADLESS=1) hello minted a signing key"
echo "headless body" | RDA_BUS_SESSION=hless runbus send --repo "$REPO" --card "$CARD" --from implementer --to reviewer --kind note >/dev/null 2>&1
runbus log --repo "$REPO" --card "$CARD" | tail -6 | grep -q "UNVERIFIED" \
  || fail "a headless (claude -p shape) send did not render UNVERIFIED"
ok "headless (RDA_HEADLESS=1, the claude -p / factory shape) sends UNVERIFIED — never a key"

echo "test-bus-trust: PASS"
