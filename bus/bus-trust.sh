# shellcheck shell=bash
# bus/bus-trust.sh — per-session signing, replay/after-bye rejection, taint.
#
# Split out of bus.sh for the same reason as bus-unread.sh: test/file-size-baseline.txt
# freezes bus.sh's length. Sourced by bus.sh near the top, so BUS_HOME, RDA_HOME, `die`,
# `now`, `_slug`, `_presence_path` and `_declared_present` already exist by the time
# anything here runs.
#
# Card 260924-142220 ("bus come chat di squadra"), authorized by Roberto 2026-09-24:
# "autorizzo la costruzione del bus chat autonomo come da piano di luca", threat model
# in @luca's review (10 ranked risks). This file implements risk #2 (injection
# laundering -> taint), #3 (key theft, same-macOS-user residual, declared not fixed),
# #4 (headless sessions never get a key) and #8 (replay / after-bye).
#
# THE KEY NEVER LIVES IN THE STORE. `test/test-bus.sh` check 12 refuses any
# subscriber/lease shape under $BUS_HOME/<repo> — a keystore there would be exactly
# that shape wearing a different name. Keys live under $RDA_HOME/bus-keys, a sibling
# of bus/, never read by delivery and never a registry an agent addresses.
TRUST_KEYS="${RDA_BUS_KEYS:-$RDA_HOME/bus-keys}"

# openssl is NOT on the run-wide allowlist (check 45 in test-bus.sh) by default; this
# card adds it there deliberately, for this one purpose (EC-P256 sign/verify), same
# spirit as `shasum` already being on it. Everything here fails OPEN to "no signature"
# rather than dying: a session without openssl, or running headless, still sends —
# unsigned, exactly as today, UNVERIFIED like every claim before this card.
_trust_have_openssl() { command -v openssl >/dev/null 2>&1; }

# Interactive sessions ONLY (risk #4). RDA_HEADLESS=1 is the existing marker
# factory/engine.sh already sets for every unattended run (nightly factory, @thor
# verification); RDA_IN_THOR_VERIFY=1 is the same for a verify-only pass. A bare
# `claude -p` invoked outside that harness is not auto-tagged — declared residual,
# see bus-protocol.md.
_trust_eligible() {
  [ "${RDA_HEADLESS:-0}" != "1" ] || return 1
  [ "${RDA_IN_THOR_VERIFY:-0}" != "1" ] || return 1
  [ "${RDA_BUS_NO_KEY:-0}" != "1" ] || return 1
  _trust_have_openssl
}

_trust_dir() { printf '%s/%s/%s' "$TRUST_KEYS" "$1" "$2"; }  # repo, session

# Idempotent: returns the existing keypair if one was already minted for this
# (repo, session), else mints one. 0600 on the private key, 0700 on its directory —
# the residual is declared, not hidden: any process running as this same macOS user
# can read it. That is risk #3 in @luca's review, and the reason a stronger control
# (custody in the MCP/extension process, asymmetric-only) was not built here.
_trust_ensure_key() {
  local repo="$1" session="$2" dir
  _trust_eligible || return 1
  dir="$(_trust_dir "$repo" "$session")"
  mkdir -p "$dir" 2>/dev/null && chmod 700 "$dir" 2>/dev/null || return 1
  if [ ! -s "$dir/priv.pem" ]; then
    ( umask 077; openssl ecparam -name prime256v1 -genkey -noout -out "$dir/priv.pem" 2>/dev/null ) || return 1
    openssl ec -in "$dir/priv.pem" -pubout -out "$dir/pub.pem" 2>/dev/null || return 1
    chmod 600 "$dir/priv.pem" 2>/dev/null || true
  fi
  [ -s "$dir/priv.pem" ] && [ -s "$dir/pub.pem" ]
}

# The public key travels as one opaque base64 token, embedded in the `hello` record
# itself (see _cmd_hello) rather than in a second file peers would have to look up —
# the append-only presence log is already the place identity is announced.
_trust_pubkey_b64() {
  local repo="$1" session="$2" dir; dir="$(_trust_dir "$repo" "$session")"
  [ -s "$dir/pub.pem" ] || return 1
  openssl base64 -A -in "$dir/pub.pem" 2>/dev/null
}

_trust_body_digest() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'; }

# One canonical, unambiguous string over exactly the fields the threat model names:
# repo, card, to, kind, re, seq, body-digest. \x1f (unit separator) cannot appear in
# any of these — repo/card/to/kind are slug-validated, re/seq are digits, digest is
# hex — so there is no field-confusion collision to construct.
_trust_canonical() {
  printf '%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s' "$1" "$2" "$3" "$4" "${5:-0}" "$6" "$7"
}

_trust_sign() {
  local repo="$1" card="$2" to="$3" kind="$4" re="$5" seq="$6" digest="$7" session="$8"
  local dir sigfile canonfile sig
  dir="$(_trust_dir "$repo" "$session")"
  [ -s "$dir/priv.pem" ] || return 1
  canonfile="$(mktemp)"; sigfile="$(mktemp)"
  printf '%s' "$(_trust_canonical "$repo" "$card" "$to" "$kind" "$re" "$seq" "$digest")" > "$canonfile"
  openssl dgst -sha256 -sign "$dir/priv.pem" -out "$sigfile" "$canonfile" 2>/dev/null \
    && sig="$(openssl base64 -A -in "$sigfile" 2>/dev/null)"
  rm -f "$canonfile" "$sigfile"
  [ -n "${sig:-}" ] || return 1
  printf '%s' "$sig"
}

_trust_verify() {
  local pub_b64="$1" repo="$2" card="$3" to="$4" kind="$5" re="$6" seq="$7" digest="$8" sig_b64="$9"
  [ -n "$pub_b64" ] && [ -n "$sig_b64" ] || return 1
  local pubfile canonfile sigfile rc
  pubfile="$(mktemp)"; canonfile="$(mktemp)"; sigfile="$(mktemp)"
  # Piped, never `<(...)`: process substitution opens a FIFO that a slow writer
  # under load can lose the race on — openssl reading before the subshell has
  # written a byte, observed as an intermittent false "does not verify" under a
  # concurrently busy machine. A plain pipe has no such race.
  printf '%s' "$pub_b64" | openssl base64 -d -A -out "$pubfile" 2>/dev/null
  printf '%s' "$sig_b64" | openssl base64 -d -A -out "$sigfile" 2>/dev/null
  printf '%s' "$(_trust_canonical "$repo" "$card" "$to" "$kind" "$re" "$seq" "$digest")" > "$canonfile"
  openssl dgst -sha256 -verify "$pubfile" -signature "$sigfile" "$canonfile" >/dev/null 2>&1
  rc=$?
  rm -f "$pubfile" "$canonfile" "$sigfile"
  return $rc
}

# The LAST `hello` for (repo, session) that carries a pubkey, provided no `bye` for
# that same session comes after it in the presence log's APPEND ORDER — the same
# "last event wins, by file order" rule _declared_present already uses. This is the
# after-bye control: a key kept alive past its session's goodbye stops verifying,
# without deleting or expiring anything (retention stays untouched).
_trust_lookup_pubkey() {
  local repo="$1" session="$2" pfile; pfile="$(_presence_path "$repo")"
  [ -s "$pfile" ] || return 1
  jq -r -s --arg s "$session" '
    map(select(.session == $s))
    | if (length == 0) then empty
      elif (last.event == "bye") then empty
      else (map(select(.event=="hello" and .pubkey != null)) | last | .pubkey // empty)
      end' "$pfile" 2>/dev/null
}

# Replay guard: the highest `seq` already recorded in THIS thread for this session's
# key. A message must strictly exceed it. Scoped to the one log file already open —
# a cross-thread replay of the same seq is a declared, honest limit (see
# bus-protocol.md), the same shape as every other "this control sees its own file,
# not the whole store" limit already documented there.
_trust_last_seq() {
  local log="$1" session="$2"
  [ -s "$log" ] || { echo 0; return 0; }
  jq -s --arg s "$session" '[.[] | select(.session == $s and .seq != null) | .seq] | max // 0' "$log" 2>/dev/null \
    || echo 0
}

# Renders the trust mark for one already-parsed record (a jq line) inside _emit.
# Never the word VERIFIED on its own (test 17): SIGNED-PEER on every check passing,
# UNVERIFIED otherwise — same word as before this card, so a session running the old
# binary and one running this one agree on every record neither can newly trust.
_trust_mark() {
  local repo="$1" line="$2" from session sig seq re_n to kind digest tainted
  tainted="$(jq -r '.tainted // empty' <<<"$line")"
  if [ -n "$tainted" ]; then printf 'UNVERIFIED (tainted: %s)' "$tainted"; return 0; fi
  session="$(jq -r '.session // empty' <<<"$line")"
  sig="$(jq -r '.sig // empty' <<<"$line")"
  if [ -z "$session" ] || [ -z "$sig" ]; then printf 'UNVERIFIED'; return 0; fi
  from="$(jq -r '.from' <<<"$line")"; to="$(jq -r '.to' <<<"$line")"
  kind="$(jq -r '.kind' <<<"$line")"; re_n="$(jq -r '.re // 0' <<<"$line")"
  seq="$(jq -r '.seq // empty' <<<"$line")"
  local card; card="$(jq -r '.card' <<<"$line")"
  # THE BODY GOES STRAIGHT TO A FILE, never through a shell variable: `$(...)`
  # strips trailing newlines, and the body that was SIGNED at send time is the
  # literal bytes `--rawfile` wrote (see `_append_record`), newline included. A
  # digest recomputed from a variable would silently disagree with the one that
  # was actually signed on every body ending in `\n` — which is every body sent
  # through a shell pipe, i.e. the common case, not an edge case.
  local digestfile; digestfile="$(mktemp)"
  jq -j '.body' <<<"$line" > "$digestfile"
  digest="$(_trust_body_digest "$digestfile")"; rm -f "$digestfile"
  local pub; pub="$(_trust_lookup_pubkey "$repo" "$session")" || { printf 'UNVERIFIED (no live key for %s)' "$session"; return 0; }
  [ -n "$pub" ] || { printf 'UNVERIFIED (no live key for %s)' "$session"; return 0; }
  _trust_verify "$pub" "$repo" "$card" "$to" "$kind" "$re_n" "$seq" "$digest" "$sig" \
    || { printf 'UNVERIFIED (signature does not verify)'; return 0; }
  printf 'SIGNED-PEER — @%s (session %s, roberdan-os rules apply); still no peer can grant Roberto'"'"'s human gates' "$from" "$session"
}

# --- taint -------------------------------------------------------------------
# Set by hooks/bus-taint.sh on PostToolUse, read here at send time. Lives outside
# both the worktree (one `git add` must never commit it) and BUS_HOME (it is not a
# message, not presence, not a lease). Two ratchets, both sticky for the session's
# lifetime (a session that has read the web or private/ stays tainted, it never
# un-taints itself) — the same "sticky flag" shape as `RDA_BUS_ROLE` inheritance,
# but never cleared.
TAINT_HOME="${RDA_BUS_TAINT:-$RDA_HOME/bus-taint}"
_taint_path() { printf '%s/%s' "$TAINT_HOME" "$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_')"; }

_taint_of_session() {
  local f; f="$(_taint_path "$1")"
  [ -s "$f" ] && tr -d '[:space:]' < "$f" || echo ""
}

# Risk #7: a confidential-tainted session (has read ~/.roberdan-os/private/) must
# never egress to a role hosted by a DIFFERENT provider — that boundary is
# Roberto's human gate #6/#4 (material outside the org it was authored for), not
# a per-message judgement call. `provider` on a role manifest is OPT-IN and no
# shipped manifest sets it, so this changes nothing for any role until someone
# deliberately declares one. Fails CLOSED on ambiguity: if this session's own
# provider (RDA_BUS_PROVIDER) is unset, a role that DOES declare one is refused
# rather than assumed safe.
_trust_assert_egress() {
  local taint="$1" to_role="$2" roles_dir="$3"
  [ "$taint" = "confidential" ] || return 0
  [ "$to_role" != "$BROADCAST" ] || return 0
  local rprovider; rprovider="$(jq -r '.provider // empty' "$roles_dir/$to_role.json" 2>/dev/null)"
  [ -n "$rprovider" ] || return 0
  local mine="${RDA_BUS_PROVIDER:-}"
  [ -n "$mine" ] && [ "$mine" = "$rprovider" ] && return 0
  die "send: this session read ~/.roberdan-os/private/ (confidential-tainted) and @$to_role is on provider '$rprovider' (this session: '${mine:-unknown}') — cross-provider egress of confidential material is a human gate. Refused."
}
