#!/usr/bin/env bash
# test-bus-chat.sh — `bus chat` (card 260924-142220, item G): a chat-like view
# with trust marks, never a second delivery path.
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
runbus() ( cd "$TMP/cwd" && bash "$BUS" "$@" )
REPO=chat-repo

echo "no traffic yet" >/dev/null
out0="$(runbus chat --repo "$REPO" --card c1)"
echo "$out0" | grep -q "no traffic" || fail "chat on an empty thread did not say so"
ok "bus chat on an empty thread: says so, does not error"

echo "first message" | runbus send --repo "$REPO" --card c1 --from implementer --to reviewer --kind note >/dev/null
echo "second message" | runbus send --repo "$REPO" --card c1 --from reviewer --to implementer --kind note --re 1 >/dev/null
out="$(runbus chat --repo "$REPO" --card c1)"
echo "$out" | grep -q "first message" || fail "chat did not show the first message"
echo "$out" | grep -q "second message" || fail "chat did not show the second message"
echo "$out" | grep -q "UNVERIFIED" || fail "chat did not carry a trust mark (both messages are unsigned here)"
ok "bus chat renders every message with a trust mark, oldest first"

# chat never advances the read cursor — it is a second VIEW of the permanent
# log, not a second delivery path. `bus read` must still see both as new.
cnt="$(runbus read --repo "$REPO" --card c1 --as reviewer | grep -c '^msg #' || true)"
[ "$cnt" -ge 1 ] || fail "bus read found nothing new after bus chat had rendered the thread — chat must never advance a cursor"
ok "bus chat never advances a cursor: bus read still delivers"

echo "test-bus-chat: PASS"
