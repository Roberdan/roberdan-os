#!/usr/bin/env bash
# bus/bus.sh — agent-to-agent message bus.
#
# WHAT THIS IS: a durable place for one agent to leave a CLAIM or a REQUEST for
# another agent that is ALREADY RUNNING under its own authorized session.
#
# WHAT THIS IS NOT. Two of these are enforced by a BEHAVIOURAL test (run the
# command, watch what it executes); the third is an honest heuristic and is
# labelled as one, because pretending otherwise is worse than not filtering:
#
#   1. It NEVER starts, spawns or dispatches an agent, and NEVER writes kanban
#      state. Delivery is pull-only, by a session that already exists. The moment
#      a code path here starts a session on a pending message, this becomes
#      factory/dispatch-runner.sh - DORMANT by a reviewed @rex/@luca decision.
#      test/test-bus.sh runs every subcommand with a stub PATH and a canary and
#      fails if ANY external agent CLI, scheduler or `kb` is executed, and pins
#      the set of external commands this directory may call to an ALLOWLIST.
#      A denylist of bad names would not survive one indirection; an allowlist
#      turns "someone added a new external call" into a test failure that has to
#      be answered deliberately. That is the gate that has to hold in month 2.
#   2. It NEVER carries acceptance criteria - HEURISTIC, not a boundary. Scope
#      comes from the card and the diff. `send` refuses the obvious spellings,
#      and a rephrasing defeats it: this is a speed bump that makes the norm
#      visible, not a guarantee. The real guarantee is Roberto reading a random
#      unannounced sample, which no channel-side filter can replace.
#
# Liveness is an OBSERVATION, not a declaration: derived from the last append and
# the last read, so there are no leases to register, refresh, expire or GC.
#
# The log is append-only and PERMANENT: the kanban records WHAT was decided, this
# records WHY, and the why is what someone needs in month three.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
RDA_HOME="${RDA_HOME:-$HOME/.roberdan-os}"
BUS_HOME="${RDA_BUS_HOME:-$RDA_HOME/bus}"
ROLES_DIR="${RDA_BUS_ROLES:-$DIR/roles}"
LEAKCHECK="${RDA_LEAKCHECK:-$ROOT/test/leak-check.sh}"
KANBAN="${RDA_KANBAN:-$ROOT/kanban}"
REGISTRY="${RDA_KANBAN_REGISTRY:-$RDA_HOME/kanban-registry}"

die() { echo "bus: $*" >&2; exit 1; }
now() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

command -v jq >/dev/null 2>&1 || die "jq is required"

# --- argument hygiene ------------------------------------------------------
# Every name reaching the filesystem is a slug and nothing else. Unvalidated,
# `--repo ../../x` made the bus create directories and write files anywhere the
# user can write - found in review, and it is the kind of thing that is only
# ever found by someone trying.
_slug() {
  local what="$1" value="$2"
  [ -n "$value" ] || die "$what: empty"
  case "$value" in
    -*) die "$what: '$value' looks like a flag, not a value";;
  esac
  [[ "$value" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] \
    || die "$what: '$value' is not a plain name ([A-Za-z0-9._-], no slashes)"
  case "$value" in
    *..*) die "$what: '$value' contains '..'";;
  esac
  printf '%s' "$value"
}

# `--flag` with no value used to crash with `$2: unbound variable`.
_need() { [ "$1" -ge 2 ] || die "$2 requires a value"; }

# --- identity --------------------------------------------------------------
# WHO AM I ON THIS CHANNEL. Measured on the real store on 2026-09-22: 167
# messages over 31 threads, 13 of them with exactly ONE sender and 14 with no
# reader cursor at all. A large part of that is this: the role was a string the
# caller had to remember and type on every single call, and a sub-agent handed a
# task prompt had no way to know which one it was. So it sent nothing, or it
# sent as whatever name it invented, which has no manifest and is refused.
#
# `RDA_BUS_ROLE` and `RDA_BUS_SESSION` make identity a property of the session
# rather than an argument of the command, and they are INHERITED by every
# sub-process - which is the whole point, because a sub-agent inherits the
# environment of the session that spawned it.
#
# This is NOT authentication and it is not claimed to be: `--from` was
# self-declared before and it still is (see the UNVERIFIED stamp in _emit). What
# changes is that forgetting who you are is no longer the default.
_ident_role() {
  local given="$1" what="$2"
  if [ -z "$given" ]; then
    given="${RDA_BUS_ROLE:-}"
  fi
  if [ -z "$given" ]; then
    given="$(_role_from_file)"
  fi
  [ -n "$given" ] || die "$what: no role given, RDA_BUS_ROLE is not set and no .bus-role was found above $PWD. Either pass it, or announce yourself once for the whole session:
    bus hello --repo <REPO> --as <ROLE> --card <CARD>          (bus roles lists them)"
  printf '%s' "$given"
}

# THE ENVIRONMENT IS NOT ENOUGH, and finding out why cost a working design.
# On at least one host every shell command runs in a FRESH process: an `export`
# in one call is gone by the next one, so `eval "$(bus hello ...)"` gave the
# session an identity that lasted exactly one command. The environment still
# works where it is inherited (a sub-process started from the same shell, which
# is the sub-agent case), so it is tried first — and this file is what makes the
# identity survive between two unrelated commands of the same session.
#
# It lives in the WORKTREE, next to the work, exactly like `.gbrain-source`, and
# NOT in the bus store: a per-instance file inside the store is the registry test
# 12 refuses, and for its stated reason - liveness must not become something to
# keep up to date. This file is not liveness. Nothing expires it, nothing renews
# it, `who` never reads it, and delivery does not know it exists. It answers one
# question and only one: when nobody said who I am, who was I last time.
_id_from_file() {
  local name="$1" dir="$PWD"
  while :; do
    if [ -f "$dir/$name" ]; then
      tr -d '[:space:]' < "$dir/$name" 2>/dev/null || true
      return 0
    fi
    # The root is CHECKED and then ends the walk. Stopping at "$dir" != "/"
    # tested every directory except the one the loop was walking towards
    # (@rex, low severity, and true).
    [ -n "$dir" ] && [ "$dir" != "/" ] || return 0
    dir="${dir%/*}"
  done
}

_role_from_file() { _id_from_file .bus-role; }

# Written by `hello` at the top of the worktree, so every later command of that
# session - and every sub-agent that runs one - starts out knowing who it is.
_write_identity_files() {
  local role="$1" session="$2" dir top
  top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  dir="${top:-$PWD}"
  [ -d "$dir" ] && [ -w "$dir" ] || return 0
  printf '%s\n' "$role" > "$dir/.bus-role" 2>/dev/null || true
  # The session name is written for the same reason as the role and it is the
  # one that makes `bye` reach the session that said `hello`. Without it the
  # goodbye is addressed to a session id invented one microsecond earlier.
  printf '%s\n' "$session" > "$dir/.bus-session" 2>/dev/null || true
}

# The session id names an INSTANCE, never an addressee. Mail is addressed to
# roles only, and this constraint is the reason the board could cut leases in
# 2026-07 without cutting identity with them: nothing can be sent to a session,
# so a message can never be stranded on a session that has gone away.
_ident_session() {
  local given="$1"
  [ -n "$given" ] || given="${RDA_BUS_SESSION:-}"
  # THE SAME FILE FALLBACK AS THE ROLE, and leaving it out was a real ghost
  # factory. @rex reproduced it: `hello` in one process invents
  # `pid69092-...`, `bye` in the next process invents `pid69278-...`, the
  # goodbye lands on a session nobody ever announced, and the first one stays
  # DECLARED forever. That is precisely the sequence every agents/*.md teaches
  # — hello in one command, bye in another — so the failure was not exotic, it
  # was the documented path. The role had a file for this exact reason and the
  # session did not; the asymmetry was the bug.
  #
  # BUT `hello` MUST NOT READ IT, which is why this takes an argument. A role is
  # a job description and inheriting it is right; a session name is an INSTANCE,
  # and a new session that picks one up from a parent directory is two different
  # sessions answering to one name — so its `bye` withdraws somebody else's
  # presence. That is the stray session renewing a lease behind your back, the
  # thing the 2026-07 board cut leases to prevent, walking back in through a
  # file. Found by this suite one minute after the file was introduced: a
  # sub-directory check inherited the session of the directory above it and its
  # goodbye killed that one instead.
  if [ -z "$given" ] && [ "${2:-read}" = "read" ]; then
    given="$(_id_from_file .bus-session)"
  fi
  # Minted as a last resort, and ALWAYS minted for `hello`: a presence record
  # under a made-up name is worth more than no presence record at all, and a
  # fresh name is the only honest answer to "who is announcing themselves now".
  [ -n "$given" ] || given="pid$$-$(date -u '+%Y%m%d%H%M%S')"
  printf '%s' "$given"
}

# WHICH REPO, without being told. Typing `--repo` on every call is the same tax
# as typing `--as`, and it was paid in the same coin: it was not paid.
#
# It is the MAIN checkout's name, never the worktree's. `kb start` gives every
# card its own worktree (~/GitHub/worktrees/<repo>/<card-id>) and the canon says
# to work there, so `--show-toplevel` answers `<card-id>`: two agents on two
# cards of the SAME project would land in two different repos on this bus and
# could never meet. `--git-common-dir` points at the main `.git` from inside any
# worktree, so its parent is the project.
_ident_repo() {
  local given="$1"
  [ -n "$given" ] || given="${RDA_BUS_REPO:-}"
  if [ -z "$given" ]; then
    local common top=""
    common="$(git rev-parse --git-common-dir 2>/dev/null || true)"
    if [ -n "$common" ]; then
      case "$common" in /*) : ;; *) common="$PWD/$common";; esac
      top="$(cd "$common/.." 2>/dev/null && pwd || true)"
    fi
    [ -n "$top" ] || top="$PWD"
    given="${top##*/}"
  fi
  printf '%s' "$given"
}

# --- roles -----------------------------------------------------------------
# A role is addressable only if it has a manifest enumerating what it may do AND
# claiming no human-gated action. The safety property lives on the RECEIVER,
# where it is checkable by reading one file, rather than on the channel, where it
# would only be a promise. This regex is a denylist and therefore a heuristic
# too - but the manifests are human-authored and few, so a human reading one is
# the actual control. Human gates: AGENTS.md § Human gates.
HUMAN_GATED_RE='merge|force-push|force push|spend|invoice|email|publish|delete|deletion|kb (start|finish)|approve|approval|sign-?off|dispatch|spawn'

# A reserved addressee, not a role: `--to all` reaches every OTHER role on the
# thread. It exists because with three or more agents the alternative is sending
# the same message N times, and the copy you forget is the one that mattered.
# It is deliberately not a manifest: nothing can act "as all", only be addressed
# as all, so it can never accumulate capabilities.
BROADCAST="all"

# A manifest named after the broadcast addressee makes one word mean two things.
# Refuse it wherever roles are touched, not only when a broadcast happens to be
# sent: with the file present, `bus roles` used to advertise `@all: may read a
# thread` while every operation involving it failed.
_assert_no_broadcast_manifest() {
  [ ! -f "$ROLES_DIR/$BROADCAST.json" ] \
    || die "$ROLES_DIR/$BROADCAST.json shadows the reserved broadcast addressee — rename that role"
}

_assert_role() {
  local role="$1" file offenders
  _assert_no_broadcast_manifest
  [ "$role" != "$BROADCAST" ] \
    || die "'$BROADCAST' is a reserved addressee, not a role: you may send --to $BROADCAST, but nothing may act as it"
  role="$(_slug "role" "$role")"
  file="$ROLES_DIR/$role.json"
  [ -f "$file" ] || die "role '$role' has no manifest at $file — an unmanifested role is not addressable"
  jq -e '.role and (.may|type=="array") and (.may_not|type=="array")' "$file" >/dev/null 2>&1 \
    || die "role '$role': manifest must carry .role, .may[] and .may_not[]"
  [ "$(jq -r '.role' "$file")" = "$role" ] || die "role '$role': manifest .role disagrees with its filename"
  offenders="$(jq -r '.may[]' "$file" | grep -Ei "$HUMAN_GATED_RE" || true)"
  [ -z "$offenders" ] || die "role '$role' claims a human-gated capability: $(echo "$offenders" | tr '\n' ' ')"
}

# --- store -----------------------------------------------------------------
_log_path()    { printf '%s/%s/%s.jsonl' "$BUS_HOME" "$1" "$2"; }
# One directory level per card, rather than "<card>.<role>" in one flat name.
# A dot is legal in both a card id and a role name, so the flat form was
# ambiguous: role `sol.gate` on card `26.07` and role `gate` on card `26.07.sol`
# resolved to the same file, and the second one silently skipped a message it had
# never been shown. Silent loss is the one failure this design exists to avoid.
_cursor_path() { printf '%s/%s/.cursor/%s/%s' "$BUS_HOME" "$1" "$2" "$3"; }

# --- presence --------------------------------------------------------------
# DECLARED presence, and the distinction from a lease is the whole design.
#
# The board cut leases in 2026-07 for two stated reasons: a lease binds a role to
# N instances and splits the stream, and there is always a second stray session
# renewing it behind your back. Both are properties of a RENEWABLE RESERVATION.
# What is written here is neither renewable nor a reservation: it is an
# append-only log of two events, `hello` and `bye`, in the same shape and with
# the same permanence as every other record in this system. Nothing expires,
# nothing is refreshed, nothing is garbage-collected, and nothing about it
# changes delivery - mail is still addressed to a ROLE, still delivered by a
# per-role cursor, and a session that has said hello receives not one byte more
# than one that has not.
#
# Why it is needed at all: `who` used to answer "who is alive" by observing the
# last append or read. That answers "someone was here" and never "who is here,
# on what, and are they still on it" - so an agent had nobody to address, and
# addressed nobody. Observation cannot distinguish a session that finished
# cleanly from one that was killed, because neither leaves a trace; a declaration
# can, and when the declaration is wrong `who` says so by putting it next to the
# observation rather than believing it (see _cmd_who).
#
# It is a FILE, not a directory of per-instance registrations: test 12 forbids a
# `subscribers/` registry, and the reason it gives - liveness must not become a
# thing to maintain - applies to any per-instance file that has to be created,
# updated and removed. An append-only log has no such lifecycle.
_presence_path() { printf '%s/%s/.presence.jsonl' "$BUS_HOME" "$1"; }


# A durable log that interleaves two concurrent appends is not durable. Two 20KB
# sends in parallel corrupted it in review, permanently - there is no GC and no
# repair, so a corrupt thread is an unreadable thread forever.
_with_lock() {
  local log="$1"; shift
  local lock="$log.lock" waited=0 tries="${RDA_BUS_LOCK_TRIES:-100}"
  mkdir -p "$(dirname "$log")"
  until mkdir "$lock" 2>/dev/null; do
    waited=$((waited + 1))
    # A lock left behind by a killed send blocks this card forever, so say how
    # long it has been there and who left it: "remove it if stale" is useless
    # advice without the evidence needed to decide whether it is stale.
    [ "$waited" -lt "$tries" ] || die "could not acquire the log lock $lock after $((waited / 10))s — held since $(_lock_age "$lock") by $(cat "$lock/owner" 2>/dev/null || echo 'an unknown process'); if that process is gone, remove the directory"
    sleep 0.1
  done
  printf 'pid %s at %s\n' "$$" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$lock/owner" 2>/dev/null || true
  # Released with rm -f + rmdir rather than `rm -rf`: the log directory is
  # permanent by design and a recursive delete anywhere in this file is a
  # tripwire, so the lock is dismantled by name instead.
  trap '_release_lock "$lock"' EXIT
  "$@"
  _release_lock "$lock"
  trap - EXIT
}

# Read fails LOUD and WHOLE on a damaged log. It used to die mid-stream with a jq
# parse error, after printing part of the thread: a reader who does not check the
# exit code believes they have seen everything.
_assert_readable_log() {
  # An EMPTY file is not a damaged one. A send interrupted after the shell
  # created the file leaves zero bytes, and `jq -e .` on no input exits non-zero,
  # so every later read raised the scariest message in this file about a log that
  # had simply never been written to.
  [ -s "$1" ] || return 0
  jq -e . "$1" >/dev/null 2>&1 \
    || die "the log $1 is not valid JSONL — it is damaged. Nothing here deletes or rewrites it, so inspect it by hand rather than trusting a partial read."
}

# Copy AND count in one critical section. Two calls under two locks is the same
# TOCTOU one layer up: the log can grow between them, and then the count that is
# supposed to police the copy describes a different file.
_snapshot_log() {
  cp "$1" "$2"
  wc -l < "$1" | tr -d ' ' > "$3"
}

_release_lock() {
  rm -f "$1/owner" 2>/dev/null || true
  rmdir "$1" 2>/dev/null || true
}

_lock_age() {
  local since
  since="$(date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo 'an unknown time')"
  printf '%s' "$since"
}

# --- send ------------------------------------------------------------------
# Approval claims are not forbidden - they are made RESOLVABLE, so the reader
# checks an artifact instead of believing a sentence. Also a keyword denylist,
# also defeated by rephrasing: it raises the cost of a casual claim, and that is
# all it does.
APPROVAL_RE='approv|autorizz|sign-?off|roberto (ha |has )?(detto|said|ok|approv)|gate (passed|superato|cleared)'
SCOPE_RE='^[[:space:]]*[-*]?[[:space:]]*(acceptance([[:space:]]criteria)?|criteri[[:space:]]di[[:space:]]accettazione|dod|definition[[:space:]]of[[:space:]]done|done[[:space:]]when|ac)[[:space:]]*:'

_cmd_send() {
  local repo="" card="" from="" to="" kind="note" ref="" body_file="" re=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) _need $# "--repo"; repo="$2"; shift 2;;
      --card) _need $# "--card"; card="$2"; shift 2;;
      --from) _need $# "--from"; from="$2"; shift 2;;
      --to)   _need $# "--to";   to="$2";   shift 2;;
      --kind) _need $# "--kind"; kind="$2"; shift 2;;
      --ref)  _need $# "--ref";  ref="$2";  shift 2;;
      --re)   _need $# "--re";   re="$2";   shift 2;;
      --body-file) _need $# "--body-file"; body_file="$2"; shift 2;;
      *) die "send: unknown argument '$1'";;
    esac
  done
  repo="$(_ident_repo "$repo")"
  [ -n "$from" ] || from="$(_ident_role "$from" "send")"
  [ -n "$repo" ] && [ -n "$card" ] && [ -n "$to" ] \
    || die "send: --repo, --card and --to are required (--from too, unless RDA_BUS_ROLE is set)"
  repo="$(_slug "--repo" "$repo")"; card="$(_slug "--card" "$card")"
  case "$kind" in request|verdict|note|question) ;; *) die "send: --kind must be request|verdict|note|question";; esac
  _assert_role "$from"
  if [ "$to" = "$BROADCAST" ]; then
    _assert_no_broadcast_manifest
  else
    _assert_role "$to"
  fi

  # The body NEVER enters a shell variable. A 3MB verdict took it through command
  # substitution, two greps and a printf as one string, and the send hung for
  # minutes before ARG_MAX killed it at jq. It travels as a file from here to the
  # record, so its size is bounded by the disk and by nothing else - and a verdict
  # with a diff pasted into it is the normal case on this channel, not an abuse.
  local body; body="$(mktemp)"
  # Cleaned up on every exit path, including the die()s below - the body may be
  # the only copy of a verdict and it must not be left lying in /tmp either.
  trap 'rm -f "$body"' RETURN
  if [ -n "$body_file" ]; then
    [ -f "$body_file" ] || die "send: --body-file '$body_file' does not exist"
    cp "$body_file" "$body"
  else
    [ -t 0 ] && die "send: no --body-file and stdin is a terminal — pipe the body in"
    cat > "$body"
  fi
  [ -s "$body" ] && grep -q '[^[:space:]]' "$body" || die "send: empty body"

  # HEURISTIC (see the header): scope should not travel. A message that carries
  # acceptance criteria redefines "done" outside the card, which is Roberto's to
  # author. A rephrasing gets through; that is understood and declared.
  if grep -Eqi "$SCOPE_RE" "$body"; then
    die "send: body carries acceptance criteria. Scope comes from the card (kb show $card), never from the bus."
  fi

  if grep -Eqi "$APPROVAL_RE" "$body"; then
    [ -n "$ref" ] || die "send: body asserts a human approval but cites no durable artifact. Pass --ref kb:<card> or --ref git:<sha>, or remove the claim."
  fi

  # Same privacy tier as kanban cards, and FAIL-CLOSED: a leak-check that has
  # been renamed, moved or un-chmod-ed used to be skipped in silence, which is a
  # privacy tier that disappears exactly when something is wrong.
  [ -x "$LEAKCHECK" ] || die "send: leak-check is not executable at $LEAKCHECK — refusing to write an unscanned body"
  # Executed directly, not through `bash`: an allowlist that contains `bash` is
  # not an allowlist, since `bash -c` is every command at once.
  "$LEAKCHECK" --only "$body" >/dev/null 2>&1 \
    || die "send: BLOCKED — leak-check found a confidential term in the body"

  # The body must be valid UTF-8, and this refuses rather than repairs. `jq
  # --rawfile` silently substitutes U+FFFD for any byte it cannot decode, so a
  # verdict pasting a diff of a latin-1 file was rewritten mid-flight while send
  # reported success - and the thread is the permanent record, so the corruption
  # is the only version anyone ever reads afterwards. "The body survives
  # verbatim" is the promise; a promise that quietly degrades is worse than a
  # refusal, because the refusal is visible.
  iconv -f UTF-8 -t UTF-8 < "$body" > /dev/null 2>&1 \
    || die "send: the body is not valid UTF-8. This channel stores text and promises it survives verbatim, and jq would silently replace the undecodable bytes — convert it (iconv -f latin1 -t utf8) and send again."

  local log; log="$(_log_path "$repo" "$card")"
  [ ! -f "$log" ] || [ "$(_thread_state "$log")" != "closed" ] \
    || die "send: $repo/$card is closed. Reopen it deliberately with: bus open --repo $repo --card $card --by <role>"

  # `--re N` — THIS MESSAGE ANSWERS RECORD N OF THIS THREAD. A pointer, not a
  # claim: it says which question is being addressed, and says nothing about
  # whether the answer is any good. Validated against the thread rather than
  # trusted, because a reply pointing at a record that does not exist discharges
  # an obligation that was never met, which is worse than no linkage at all.
  if [ -n "$re" ]; then
    [[ "$re" =~ ^[0-9]+$ ]] && [ "$re" -ge 1 ] \
      || die "send: --re must be the number of a record in this thread (they are printed as '#N' by bus read and bus log), not '$re'"
    [ -f "$log" ] || die "send: --re $re, but there is no thread at $repo/$card yet"
    local depth; depth="$(wc -l < "$log" | tr -d ' ')"
    [ "$re" -le "$depth" ] \
      || die "send: --re $re, but $repo/$card holds only $depth record(s). Check the number with: bus log --repo $repo --card $card"
  fi

  _with_lock "$log" _append_record "$log" "$repo" "$card" "$from" "$to" "$kind" "$ref" "$body" "$re"
  echo "bus: appended $kind from $from to $to on $repo/$card${re:+ (answers #$re)} -> $log"
  # Say what is still owed AFTER a send, not only after a read. An agent that has
  # just written is the one agent guaranteed to be awake and looking at this
  # channel, and it is the cheapest possible moment to notice that something has
  # been waiting for it.
  #
  # THIS CARD ONLY, and the reason is measured. The first version scanned every
  # thread in the repo on every single send, which means reading the whole store
  # to print one reminder: with an 8MB thread present a send went from 0.023s to
  # 0.823s and a read from 0.021s to 0.739s — 35x, on the hot path, forever. It
  # was not found by reading the code: the mutation suite stopped FAILING and
  # started TIMING OUT, which is the shape a performance regression takes when it
  # is big enough. Repo-wide belongs where it is paid once — `hello`, `bye`, the
  # explicit `bus owed`, and the doorbell, which exists precisely to be the
  # periodic nudge and is throttled for it.
  local still; still="$(_owed_count "$repo" "$card" "$from")"
  [ "$still" = "0" ] \
    || echo "bus: @$from still owes an answer to $still message(s) on $repo/$card — bus owed --repo $repo --as $from" >&2
}

_append_record() {
  local log="$1" repo="$2" card="$3" from="$4" to="$5" kind="$6" ref="$7" body="$8" re="${9:-}"
  # $body is a PATH here, and --rawfile reads it directly: as `--arg` this hit
  # ARG_MAX at roughly a megabyte and died as a raw `jq: Argument list too long`
  # with no `bus:` message at all - an undocumented ceiling reported in a way
  # nobody could act on.
  #
  # `re` is an ADDITIVE field and is written as null when absent, so every record
  # ever written before it existed reads back exactly as it did: no selector in
  # this file asserts the key set, and `.re // null` is how every reader asks.
  jq -cn --arg ts "$(now)" --arg repo "$repo" --arg card "$card" --arg from "$from" \
        --arg to "$to" --arg kind "$kind" --arg ref "$ref" --arg re "$re" --rawfile body "$body" \
    '{ts:$ts,repo:$repo,card:$card,from:$from,to:$to,kind:$kind,ref:(if $ref=="" then null else $ref end),re:(if $re=="" then null else ($re|tonumber) end),body:$body}' \
    >> "$log" || die "send: could not encode the record — nothing was appended"
}

# --- ref resolution --------------------------------------------------------
# Turns "trust me" into a lookup - and says no more than the lookup proves. It
# used to print VERIFIED, which was the most effective laundering in the file:
# `kb start --by roberto` is honor-system by kb.sh's own admission, so promoting
# it to "verified" manufactures an independent confirmation that never happened.
_registry_repos() {
  [ -f "$REGISTRY" ] || return 0
  grep -vE '^[[:space:]]*(#|$)' "$REGISTRY" 2>/dev/null || true
}

_card_boards() {
  printf '%s\n' "$KANBAN"
  local r
  while IFS= read -r r; do
    [ -n "$r" ] && [ "$r/kanban" != "$KANBAN" ] && printf '%s/kanban\n' "$r"
  done < <(_registry_repos)
}

_resolve_ref() {
  local ref="$1"
  case "$ref" in
    "" ) echo "no citation";;
    kb:*)
      local id="${ref#kb:}" board col f found="" column=""
      case "$id" in *[!A-Za-z0-9._-]*) echo "UNRESOLVED (card id is not a plain name)"; return 0;; esac
      while IFS= read -r board; do
        for col in todo doing "done"; do
          f="$board/$col/$id.md"
          if [ -f "$f" ]; then found="$f"; column="$col"; break 2; fi
        done
      done < <(_card_boards)
      if [ -z "$found" ]; then
        echo "UNRESOLVED (no card $id in any registered board)"
      elif grep -qE '^(approved_by|verified_by|verified_at)' "$found"; then
        # NOT "verified": kb.sh says of --by, "any caller can pass --by roberto,
        # deliberately no blocking check". And kb writes its start audit line
        # BEFORE refusing an ungated start, so that line proves nothing at all.
        echo "RESOLVES to an honor-system approval line on $id (in $column/) — kb start is not a boundary, confirm with the human"
      else
        echo "UNRESOLVED (card $id is in $column/ and carries no approval line)"
      fi;;
    git:*)
      local sha="${ref#git:}" root
      # A citation must be durable. `HEAD`, `@` and `HEAD@{0}` all resolved here
      # and printed as commits: a moving pointer is not evidence.
      [[ "$sha" =~ ^[0-9a-f]{7,40}$ ]] || { echo "UNRESOLVED (not a commit sha — a moving ref like HEAD is not a durable citation)"; return 0; }
      if git rev-parse --git-dir >/dev/null 2>&1 && git cat-file -e "$sha^{commit}" 2>/dev/null; then
        echo "EXISTS as commit $sha in $(basename "$(git rev-parse --show-toplevel)") — existence only, proves no approval"; return 0
      fi
      while IFS= read -r root; do
        [ -d "$root/.git" ] || continue
        if git -C "$root" cat-file -e "$sha^{commit}" 2>/dev/null; then
          echo "EXISTS as commit $sha in $(basename "$root") — existence only, proves no approval"; return 0
        fi
      done < <(_registry_repos)
      echo "UNRESOLVED (no commit $sha here or in any registered repo)";;
    *) echo "UNRESOLVED (unknown citation form)";;
  esac
}

# --- read / peek -----------------------------------------------------------
# Output is labelled at the source. What arrives is a CLAIM BY ANOTHER AGENT and
# must never be readable as canon: a message that arrives looking like context
# gets believed like context. Note `--from` is self-declared and bound to
# nothing, so the stamp is the only thing standing between a thread and a review
# that never happened.
_emit() {
  local card="$1" me="${2:-}" line n=0
  while IFS= read -r line; do
    n=$((n+1))
    local ts from kind ref body seq re to
    ts="$(jq -r '.ts' <<<"$line")"; from="$(jq -r '.from' <<<"$line")"
    kind="$(jq -r '.kind' <<<"$line")"; ref="$(jq -r '.ref // ""' <<<"$line")"
    body="$(jq -r '.body' <<<"$line")"
    seq="$(jq -r '._seq // ""' <<<"$line")"
    re="$(jq -r '.re // ""' <<<"$line")"
    to="$(jq -r '.to' <<<"$line")"
    echo "--------------------------------------------------------------------"
    echo "CLAIM BY @$from ($kind, $ts) — UNVERIFIED, and @$from is self-declared."
    # The record number is what makes an answer addressable. Without it `--re`
    # would need a number the reader has no way to know, and a linkage nobody can
    # spell is a linkage nobody uses.
    [ -n "$seq" ] && echo "msg #$seq on $card, addressed to @$to${re:+ — answers #$re}"
    echo "Scope for this work comes from \`kb show $card\` and the diff, NOT from this message."
    [ -n "$ref" ] && echo "cites: $ref -> $(_resolve_ref "$ref")"
    # SAY WHAT IS EXPECTED OF THE READER. A question used to render in exactly the
    # same wrapper as a note, so "you owe an answer here" existed only in the
    # sender's head. This is the difference between a channel and a noticeboard.
    if [ -n "$me" ] && [ -n "$seq" ] && { [ "$kind" = "question" ] || [ "$kind" = "request" ]; }; then
      echo "THIS ASKS YOU FOR AN ANSWER. It stays listed in \`bus owed\` until you cite it:"
      echo "    bus send --card $card --to $from --re $seq --kind verdict"
    fi
    echo "--------------------------------------------------------------------"
    printf '%s\n' "$body"
    echo
  done
  [ "$n" -gt 0 ] || echo "bus: nothing new."
  # Report how many records were actually rendered, so the caller can check it
  # against how many it handed over. See the delivery audit in _cmd_read.
  printf '%s' "$n" > "${RDA_BUS_EMITTED:-/dev/null}"
}

_cmd_read() {
  local repo="" card="" as="" advance=1
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) _need $# "--repo"; repo="$2"; shift 2;;
      --card) _need $# "--card"; card="$2"; shift 2;;
      --as)   _need $# "--as";   as="$2";   shift 2;;
      --peek) advance=0; shift;;
      *) die "read: unknown argument '$1'";;
    esac
  done
  repo="$(_ident_repo "$repo")"
  [ -n "$as" ] || as="$(_ident_role "$as" "read")"
  [ -n "$repo" ] && [ -n "$card" ] && [ -n "$as" ] || die "read: --repo and --card are required (--as too, unless RDA_BUS_ROLE is set)"
  repo="$(_slug "--repo" "$repo")"; card="$(_slug "--card" "$card")"
  _assert_role "$as"
  local log cur seen total mine snap
  log="$(_log_path "$repo" "$card")"
  [ -f "$log" ] || { echo "bus: no traffic on $repo/$card."; return 0; }
  _assert_readable_log "$log"
  # A closed thread costs one line, forever. Nothing is deleted and nothing is
  # re-sent: the reasoning stays readable with `bus log`, it just stops arriving.
  if [ "$(_thread_state "$log")" = "closed" ]; then
    echo "bus: $repo/$card is closed ($(jq -r 'select(.kind=="closed")|"by @\(.from) at \(.ts)"' "$log" | tail -1)). $(wc -l < "$log" | tr -d ' ') record(s) kept — read them with: bus log --repo $repo --card $card"
    return 0
  fi
  cur="$(_cursor_path "$repo" "$card" "$as")"
  seen=0
  if [ -f "$cur" ]; then
    seen="$(tr -d '[:space:]' < "$cur")"
    [[ "$seen" =~ ^[0-9]+$ ]] || die "the cursor $cur is corrupt ('$seen') — delete it to re-read the thread from the start"
  fi
  # ONE snapshot, counted and emitted from the same bytes. Scanning the log twice
  # marked as read anything that arrived between the two scans: on a channel whose
  # only job is durable delivery between parallel sessions, that lost messages
  # silently, which is worse than failing.
  #
  # The cursor counts RAW records, not records addressed to me. This is a
  # robustness choice, not a bugfix, and the distinction matters: counting the
  # filtered stream is self-consistent and works fine as long as the delivery
  # rule never changes. It is the CHANGE that is dangerous - a cursor stored
  # under one rule and read under a wider one indexes into a different stream,
  # and the widened-in messages are skipped as though already read. A raw index
  # is decoupled from the rule, so the worst any stale cursor can do is
  # re-deliver, which is loud and harmless, instead of dropping, which is silent.
  # The snapshot is taken UNDER THE APPEND LOCK. Without it, validating the file
  # and then copying it is a TOCTOU: a large record being appended in between is
  # read torn, and the reader gets a raw `jq: parse error` on a log that is
  # perfectly valid a moment later. Observed in review: 9 of 12 snapshots taken
  # during a 900KB append were invalid.
  snap="$(mktemp)"
  local snapcount; snapcount="$(mktemp)"
  # The count is taken UNDER THE SAME LOCK as the copy, and checked against the
  # snapshot before anything reads it. That closes the last unaudited hop: the
  # delivery audit below spans snapshot -> rendered, so a loss at log -> snapshot
  # left every count downstream honestly agreeing. A `tail -n 500` added to bound
  # the memory a read may use dropped 100 records of a 600-record thread, exit 0,
  # trailer correct, cursor past all of them. The chain is now log -> snapshot ->
  # filter -> renderer -> cursor with no gap in it.
  _with_lock "$log" _snapshot_log "$log" "$snap" "$snapcount"
  # TEST-ONLY WINDOW. The regression this guards (the cursor computed from the
  # live log instead of the snapshot) is a race, and a race-based test passes most
  # of the time for reasons unrelated to the property: the mutant for it was
  # caught 1 run in 3. This widens the window on demand so the check is
  # deterministic. It can only ever sleep — it is validated as a number, it is
  # unset in every real invocation, and it is watched by the same run-wide canary
  # and allowlist as every other line here.
  if [[ "${RDA_BUS_TEST_PAUSE:-}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then sleep "$RDA_BUS_TEST_PAUSE"; fi
  # Validate THE BYTES WE WILL EMIT, not the file they came from. Validating the
  # file and streaming from a different read of it is the same TOCTOU one layer
  # down.
  _assert_readable_log "$snap"
  total="$(wc -l < "$snap" | tr -d ' ')"
  local expected; expected="$(tr -d '[:space:]' < "$snapcount")"; rm -f "$snapcount"
  if [ "$total" != "$expected" ]; then
    rm -f "$snap"
    die "the snapshot of $log is short: the log held $expected record(s) under the lock but the snapshot has $total. Nothing was delivered and the cursor has NOT advanced, so nothing is lost."
  fi
  # `.to == all` reaches everyone EXCEPT the sender: an agent that had to skip its
  # own broadcast by hand would eventually forget to.
  local deliverable; deliverable="$(mktemp)"
  # Filter to completion BEFORE emitting a single line. `tail | jq | _emit`
  # streamed, so a failure halfway printed a partial thread and then died - which
  # is exactly the "loud and whole" property this is supposed to provide.
  #
  # `_seq` is the record's ABSOLUTE position in the thread, computed here from
  # the index inside the snapshot rather than from a line count of the delivered
  # slice: the reader is shown numbers that `--re` can cite, and a number that
  # counted only what THIS role received would point at a different record for
  # every role on the thread.
  jq -c -s --arg me "$as" --arg all "$BROADCAST" --argjson skip "$seen" \
      'to_entries | .[$skip:] | map(.value + {_seq: (.key + 1)})
       | map(select(.to == $me or (.to == $all and .from != $me))) | .[]' "$snap" > "$deliverable" \
    || { rm -f "$snap" "$deliverable"; die "the snapshot of $log could not be filtered — nothing was delivered, so nothing is half-read"; }
  local emitted_f emitted want
  emitted_f="$(mktemp)"
  # `want` is derived from THE SNAPSHOT, not from $deliverable. Counting the same
  # file that feeds the renderer makes the audit downstream-only: anything the
  # filter itself drops (a dedupe, a narrowed select, an off-by-one in the tail)
  # is missing from both sides, both numbers agree, and both are wrong. Recomputed
  # independently, the audit spans the whole path from snapshot to rendered line.
  want="$(jq -s --arg me "$as" --arg all "$BROADCAST" --argjson skip "$seen" \
      '.[$skip:] | map(select(.to == $me or (.to == $all and .from != $me))) | length' "$snap")" \
    || { rm -f "$snap" "$deliverable" "$emitted_f"; die "the snapshot of $log could not be counted — nothing was delivered, so nothing is half-read"; }
  RDA_BUS_EMITTED="$emitted_f" _emit "$card" "$as" < "$deliverable"
  emitted="$(cat "$emitted_f" 2>/dev/null || echo 0)"; rm -f "$emitted_f"
  # THE DELIVERY AUDIT. The cursor advances past everything in the snapshot, and
  # the log is append-only, so a record that was deliverable but not rendered is
  # gone from `read` forever with nothing printed to say so. Nothing outside this
  # function can notice that: `send` returned 0, `read` returned 0, the trailer
  # even reports the right count. So the bus counts what it handed to the
  # renderer and what the renderer produced, and refuses to move the cursor if
  # they differ. A batch cap added to "save tokens" is the obvious way this
  # breaks, and it is the one failure durable delivery cannot survive.
  if [ "$emitted" != "$want" ]; then
    rm -f "$snap" "$deliverable"
    die "delivery is incomplete: $want record(s) were deliverable to @$as but $emitted were rendered. The cursor has NOT advanced, so nothing is lost — re-read after fixing the renderer."
  fi
  if [ "$advance" = "1" ]; then
    mkdir -p "$(dirname "$cur")"
    printf '%s\n' "$total" > "$cur"   # only after a successful emit
  fi
  mine="$(jq -c --arg me "$as" --arg all "$BROADCAST" \
            'select(.to == $me or (.to == $all and .from != $me))' "$snap" | wc -l | tr -d ' ')"
  rm -f "$snap" "$deliverable"
  echo "bus: $total record(s) on $repo/$card, $mine deliverable to @$as."
  # THE TRAILER THAT CLOSES THE LOOP. The cursor has just moved past everything
  # above, so without this line a question read at 10:02 and postponed at 10:03
  # is gone. Scoped to THIS CARD for the measured reason in `send` above — the
  # repo-wide scan cost 35x on every read — and the repo-wide view is one command
  # away, said here by name.
  local owed_n; owed_n="$(_owed_count "$repo" "$card" "$as")"
  if [ "$owed_n" != "0" ]; then
    echo "bus: @$as owes an answer to $owed_n message(s) on $repo/$card. They stay listed until you cite them with --re:"
    echo "     bus owed --repo $repo --as $as      (every card, not only this one)"
  fi
}

# --- count: HOW MANY, never WHAT -------------------------------------------
# The doorbell problem. Delivery is pull-only by design (property 1), so a
# message waits until somebody asks - and nobody asks, because nobody knows it
# is there. A COUNT is the only signal that can be pushed into a live session
# without becoming delivery: a number carries no claim, so it cannot be believed
# like context, which is the exact harm the board cut `context-inject` delivery
# for. Bodies still only ever arrive through `read`, stamped UNVERIFIED.
#
# Three properties, each pinned by a check in test/test-bus.sh:
#   - it NEVER renders a body: jq emits the literal `1` per match and never
#     touches `.body`. Counting with `jq -c 'select(...)' | wc -l` would work
#     just as well and would put every body on a pipe, which is the shape of the
#     bug, not of the fix.
#   - it NEVER advances a cursor. A doorbell that consumes the mail it announces
#     is worse than no doorbell: the message is then gone from `read` forever.
#   - it does NOT require --as. The hook that calls it has no role - it only
#     knows the repo. Role-agnostic counting also cannot launder a read: that
#     @sol-gate has two unread messages says nothing about what they say.
#
# ADVISORY BY DECLARATION: the count is taken WITHOUT the append lock. Taking it
# would let a doorbell that fires on every tool call block behind a 3MB send for
# up to 10s, and a slow doorbell gets removed. So a count taken mid-append may
# be short by one and the next one corrects it. Nothing can be LOST this way -
# the cursor never moves, and `read` is still the thing that is exact.
_count_unread() {
  local log="$1" role="$2" seen="$3"
  tail -n +$((seen + 1)) "$log" \
    | jq -r --arg me "$role" --arg all "$BROADCAST" \
        'select(.to == $me or (.to == $all and .from != $me)) | 1' 2>/dev/null \
    | wc -l | tr -d ' '
}

_cmd_count() {
  local repo="" card="" as="" present=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) _need $# "--repo"; repo="$2"; shift 2;;
      --card) _need $# "--card"; card="$2"; shift 2;;
      --as)   _need $# "--as";   as="$2";   shift 2;;
      # --present COUNTS ONLY FOR ROLES SOMEBODY IS ACTUALLY PLAYING, and it
      # exists because Roberto opened a session on 2026-09-22 and got twelve
      # lines of this:
      #
      #   260913-150759: 3 unread for @architect
      #   260913-150759: 3 unread for @qa-gate      ... and so on, four roles,
      #   260917-111539: 1 unread for @architect        three cards, forever
      #
      # Two of those cards were already in `done/` and the third had no card at
      # all. Nobody was playing any of those roles, and nobody was going to: the
      # mail was addressed to `all` months earlier, so every role that never read
      # it counted it as unread for the rest of time. A doorbell that rings for
      # mail NOBODY CAN ACT ON teaches exactly one thing — to stop hearing it —
      # and then it is worse than no doorbell, because the real message arrives
      # in the middle of noise somebody has already learned to skip.
      #
      # "Playing it" means: declared present with `hello` and not yet gone, or
      # this very session's role. Not "has a manifest" — a manifest says the role
      # is addressable, never that anyone is there.
      --present) present=1; shift;;
      *) die "count: unknown argument '$1'";;
    esac
  done
  [ -n "$repo" ] || die "count: --repo is required"
  repo="$(_slug "--repo" "$repo")"
  [ -z "$card" ] || card="$(_slug "--card" "$card")"
  # Roles are held in a space-separated string, not an array: role names are
  # slugs by construction, and `"${a[@]}"` on an empty array is an unbound
  # variable under `set -u` in bash 3.2, which is what macOS ships.
  local roles=""
  if [ -n "$as" ]; then
    _assert_role "$as"
    roles="$as"
  else
    [ -d "$ROLES_DIR" ] \
      || die "no roles directory at $ROLES_DIR — if you reached this through a symlink, point the wrapper at bus/bus.sh itself or set RDA_BUS_ROLES"
    _assert_no_broadcast_manifest
    local rf
    for rf in "$ROLES_DIR"/*.json; do
      [ -e "$rf" ] || break
      rf="${rf##*/}"
      roles="$roles ${rf%.json}"
    done
    if [ "$present" = "1" ]; then
      local here="" r
      # The reader's own role first: a session always counts as present to
      # itself, whether or not the hook that announces it ever ran.
      [ -z "${RDA_BUS_ROLE:-}" ] || here=" ${RDA_BUS_ROLE}"
      while IFS= read -r r; do
        [ -n "$r" ] || continue
        case " $here " in *" $r "*) ;; *) here="$here $r";; esac
      done < <(_declared_present "$(_presence_path "$repo")" 2>/dev/null | awk -F'\t' '{print $1}')
      roles="$here"
    fi
  fi
  # Nobody is here: there is nothing to ring about, and saying so would be the
  # noise this flag exists to remove.
  [ "$present" != "1" ] || [ -n "$(printf '%s' "$roles" | tr -d '[:space:]')" ] || return 0
  local dir="$BUS_HOME/$repo"
  # Silence, not an error: a repo with no traffic is the normal case, and this
  # runs on every tool call. Anything printed at zero is context spent for nothing.
  [ -d "$dir" ] || return 0
  local f
  for f in "$dir"/*.jsonl; do
    [ -e "$f" ] || continue
    [ -s "$f" ] || continue
    local cname; cname="${f##*/}"; cname="${cname%.jsonl}"
    [ -z "$card" ] || [ "$cname" = "$card" ] || continue
    # Same posture as `who`: one damaged thread must not take down the summary.
    # Delivery still fails loud and whole - this only decides whether to ring.
    if ! jq -e . "$f" >/dev/null 2>&1; then
      echo "bus: WARNING — $f is damaged and was skipped by count." >&2
      continue
    fi
    [ "$(_thread_state "$f")" != "closed" ] || continue
    local role cur seen n
    for role in $roles; do
      cur="$(_cursor_path "$repo" "$cname" "$role")"
      seen=0
      if [ -f "$cur" ]; then
        seen="$(tr -d '[:space:]' < "$cur")"
        # A corrupt cursor makes `read` die and say so. Here it must not: the
        # doorbell degrades towards RINGING (count from zero), never towards
        # silence, because the failure direction that loses a message is silence.
        if ! [[ "$seen" =~ ^[0-9]+$ ]]; then
          echo "bus: WARNING — the cursor $cur is corrupt; counting from the start." >&2
          seen=0
        fi
      fi
      n="$(_count_unread "$f" "$role" "$seen")"
      [ "$n" -gt 0 ] || continue
      printf '%s\t%s\t%s\n' "$cname" "$role" "$n"
    done
  done
}

# --- closing a thread ------------------------------------------------------
# The answer to "a finished message should stop costing anything" WITHOUT the
# answer being deletion. Reads already cost only what is new - each role has a
# durable cursor, so history is never re-sent - but a finished thread still
# showed up in `who` and still invited a read. Closing it makes it free and
# silent while keeping every word of it.
#
# The closure is itself a RECORD in the log, not a flag in a side file: who
# closed a thread and when is exactly the kind of fact this channel exists to
# keep, and a side file could go missing while the thread it described stayed.
_thread_state() {
  local log="$1"
  [ -s "$log" ] || { echo open; return 0; }
  jq -r 'select(.kind=="closed" or .kind=="opened") | .kind' "$log" 2>/dev/null \
    | tail -1 | grep -q closed && echo closed || echo open
}

_cmd_close() {
  local repo="" card="" by="" reopen="$1"; shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) _need $# "--repo"; repo="$2"; shift 2;;
      --card) _need $# "--card"; card="$2"; shift 2;;
      --by)   _need $# "--by";   by="$2";   shift 2;;
      *) die "${reopen:+open}${reopen:-close}: unknown argument '$1'";;
    esac
  done
  [ -n "$repo" ] && [ -n "$card" ] && [ -n "$by" ] \
    || die "close: --repo, --card and --by <role> are required"
  repo="$(_slug "--repo" "$repo")"; card="$(_slug "--card" "$card")"
  _assert_role "$by"
  local log; log="$(_log_path "$repo" "$card")"
  [ -f "$log" ] || die "close: there is no thread at $repo/$card"
  local want="closed" state
  [ -z "$reopen" ] || want="opened"
  state="$(_thread_state "$log")"
  [ "$want" != "closed" ] || [ "$state" != "closed" ] || die "close: $repo/$card is already closed"
  [ "$want" != "opened" ] || [ "$state" != "open" ]   || die "open: $repo/$card is already open"
  local bf; bf="$(mktemp)"
  printf 'thread %s by @%s\n' "$want" "$by" > "$bf"
  _with_lock "$log" _append_record "$log" "$repo" "$card" "$by" "$BROADCAST" "$want" "" "$bf"
  rm -f "$bf"
  echo "bus: $repo/$card is now $want — the thread is kept in full, 'bus log' still reads it."
}

# --- hello / bye -----------------------------------------------------------
# Announce yourself once, at the start of the session, and say when you leave.
# Both are ordinary appends to the presence log; neither delivers, consumes or
# blocks anything, and neither can start a session - they are written BY a
# session that already exists, about itself.
# THE SAME FAIL-CLOSED PRIVACY GATE AS A MESSAGE BODY. `--doing` and `--why` are
# free prose written by a human or an agent and kept forever in a store that
# lives outside every git tree, so nothing else will ever scan them. `send` runs
# leak-check on every body; presence was a second door into the same permanent
# archive with a weaker policy, which is how a declared property quietly stops
# being true (@baccio, adversarial review — a path, not a demonstrated leak).
_scan_note() {
  local what="$1" text="$2"
  [ -n "$text" ] || return 0
  [ -x "$LEAKCHECK" ] || die "$what: leak-check is not executable at $LEAKCHECK — refusing to write an unscanned note"
  local nf; nf="$(mktemp)"
  printf '%s\n' "$text" > "$nf"
  if ! "$LEAKCHECK" --only "$nf" >/dev/null 2>&1; then
    rm -f "$nf"
    die "$what: BLOCKED — leak-check found a confidential term in the note"
  fi
  rm -f "$nf"
}

_presence_append() {
  local pfile="$1" event="$2" repo="$3" session="$4" role="$5" card="$6" note="$7"
  jq -cn --arg ts "$(now)" --arg event "$event" --arg repo "$repo" --arg session "$session" \
        --arg role "$role" --arg card "$card" --arg note "$note" \
    '{ts:$ts,event:$event,repo:$repo,session:$session,role:$role,
      card:(if $card=="" then null else $card end),
      note:(if $note=="" then null else $note end)}' \
    >> "$pfile" || die "presence: could not encode the record — nothing was appended"
}

# The last event per session wins, and "last" is FILE ORDER, not timestamp order.
# `ts` has one-second resolution, so a hello and a bye inside the same second
# sort arbitrarily against each other and a session that had just left could come
# back from the dead. Append order is the only total order this log has.
_declared_present() {
  local pfile="$1"
  [ -s "$pfile" ] || return 0
  jq -e . "$pfile" >/dev/null 2>&1 || {
    echo "bus: WARNING — $pfile is damaged and was skipped by who." >&2
    return 0
  }
  jq -r -s 'group_by(.session) | map(last) | map(select(.event=="hello"))
            | sort_by(.ts) | .[] | [.role,.session,(.card // "-"),.ts,(.note // "")] | @tsv' "$pfile"
}

_cmd_hello() {
  local repo="" as="" session="" card="" doing=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo)    _need $# "--repo";    repo="$2";    shift 2;;
      --as)      _need $# "--as";      as="$2";      shift 2;;
      --session) _need $# "--session"; session="$2"; shift 2;;
      --card)    _need $# "--card";    card="$2";    shift 2;;
      --doing)   _need $# "--doing";   doing="$2";   shift 2;;
      *) die "hello: unknown argument '$1'";;
    esac
  done
  repo="$(_ident_repo "$repo")"
  [ -n "$repo" ] || die "hello: could not work out which repo this is — pass --repo"
  repo="$(_slug "--repo" "$repo")"
  as="$(_ident_role "$as" "hello")"
  _assert_role "$as"
  as="$(_slug "--as" "$as")"
  # `mint`: announcing yourself never inherits a name from the filesystem.
  session="$(_slug "--session" "$(_ident_session "$session" mint)")"
  [ -z "$card" ] || card="$(_slug "--card" "$card")"
  _scan_note "hello --doing" "$doing"
  local pfile; pfile="$(_presence_path "$repo")"
  mkdir -p "$(dirname "$pfile")"
  _with_lock "$pfile" _presence_append "$pfile" hello "$repo" "$session" "$as" "$card" "$doing"
  # Identity that survives the next command, and the one after that. See
  # _role_from_file: on a host where every command is a fresh process, the
  # environment alone gives an identity that lasts exactly one call.
  _write_identity_files "$as" "$session"
  # Printed as shell assignments ON STDOUT so the caller can `eval` it and have
  # the identity for the rest of the session, sub-agents included. Everything
  # human goes to stderr, so `eval "$(bus hello ...)"` cannot swallow a diagnostic
  # or execute one.
  {
    echo "bus: @$as is present on $repo${card:+ (card $card)} as session $session."
    echo "     others see you with: bus who --repo $repo"
    echo "     when you finish:     bus bye --repo $repo"
    local owed_n
    owed_n="$(_owed_count "$repo" "" "$as")"
    [ "$owed_n" = "0" ] || echo "     NOTE: $owed_n message(s) are waiting for YOUR answer — bus owed --repo $repo"
  } >&2
  printf 'export RDA_BUS_ROLE=%s RDA_BUS_SESSION=%s RDA_BUS_REPO=%s\n' "$as" "$session" "$repo"
}

_cmd_bye() {
  local repo="" as="" session="" why=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo)    _need $# "--repo";    repo="$2";    shift 2;;
      --as)      _need $# "--as";      as="$2";      shift 2;;
      --session) _need $# "--session"; session="$2"; shift 2;;
      --why)     _need $# "--why";     why="$2";     shift 2;;
      *) die "bye: unknown argument '$1'";;
    esac
  done
  repo="$(_ident_repo "$repo")"
  [ -n "$repo" ] || die "bye: could not work out which repo this is — pass --repo"
  repo="$(_slug "--repo" "$repo")"
  as="$(_ident_role "$as" "bye")"
  _assert_role "$as"
  as="$(_slug "--as" "$as")"
  session="$(_slug "--session" "$(_ident_session "$session")")"
  local pfile; pfile="$(_presence_path "$repo")"
  mkdir -p "$(dirname "$pfile")"
  # A bye WITHOUT a matching hello is recorded anyway rather than refused. The
  # alternative is a session that crashed, restarted and now cannot mark itself
  # gone — and the presence view reads the last event per session, so a bye that
  # answers nothing is simply the last word of a session nobody saw arrive.
  _scan_note "bye --why" "$why"
  _with_lock "$pfile" _presence_append "$pfile" bye "$repo" "$session" "$as" "" "$why"
  local owed_n; owed_n="$(_owed_count "$repo" "" "$as")"
  if [ "$owed_n" != "0" ]; then
    # Not a refusal: nothing here may block a session from ending. It is said
    # out loud because leaving with unanswered mail is the exact failure this
    # whole change exists to make visible.
    echo "bus: @$as left $repo — but $owed_n message(s) addressed to @$as were never answered." >&2
    echo "     they stay listed for whoever plays @$as next:  bus owed --repo $repo --as $as" >&2
  else
    local blind; blind="$(_unreadable_threads "$repo")"
    if [ "$blind" != "0" ]; then
      echo "bus: @$as left $repo (session $session). Nothing owed in the threads that could be READ — $blind could not be, so this is not a clean bill." >&2
    else
      echo "bus: @$as left $repo (session $session). Nothing was left unanswered." >&2
    fi
  fi
  printf 'unset RDA_BUS_ROLE RDA_BUS_SESSION RDA_BUS_REPO\n'
}

# --- owed: the questions nobody answered -----------------------------------
# THE FIX FOR "THEY LISTEN AND THEY DON'T TALK". A question used to be delivered
# exactly once and then become invisible: `read` renders it, the cursor moves
# past it, and from that moment nothing in the system knows it was ever asked.
# The reader who meant to answer after finishing one more thing had no artifact
# left to come back to, and the asker had no way to tell "read and ignored" from
# "never arrived". Measured on the real store: 13 of 31 threads had exactly one
# sender.
#
# So a `question` or a `request` addressed to a role stays listed until THAT
# role sends a message citing it with `--re`. This is deliberately not a state
# machine and writes no state at all: owed-ness is DERIVED from the append-only
# log every time it is asked, so there is nothing to keep in sync, nothing to
# migrate, and no way for the two to disagree.
#
# What it cannot do, stated rather than implied: it cannot make anyone answer,
# and `--re` proves only that a message was cited, never that it was addressed.
# An agent may reply "I disagree" and the question is discharged. The honest
# claim is that an unanswered question is now VISIBLE, not that it is resolved.
# A CITATION ONLY DISCHARGES A QUESTION IF IT REACHED THE PERSON WHO ASKED IT.
# It used to be enough to cite the record at all, so a message citing #3 and
# addressed to a THIRD role cleared the debt while the asker received nothing —
# "no answer owed" printed next to an asker who had been answered by nobody
# (@baccio, adversarial review, reproduced on the query itself). The addressee of
# the reply must be the asker, or the broadcast, which everyone including the
# asker receives.
# ONE jq PER THREAD, not three. It used to validate the file, then ask
# `_thread_state` (another jq) whether the thread was closed, then run the query.
# Three interpreter start-ups per thread is most of the cost of an answer that is
# printed after every message, so the closed check is folded in here and an
# unparsable file is detected by this same call failing.
_owed_jq='
  if ((map(select(.kind == "closed" or .kind == "opened")) | last | .kind?) == "closed")
  then empty
  else
  (map(select(.from == $me and ((.re // null) != null)) | {r: (.re | tonumber), to: .to})) as $cites
  | to_entries
  | map(select(.value.kind == "question" or .value.kind == "request"))
  | map(select(.value.to == $me or (.value.to == $all and .value.from != $me)))
  | map(select(
      (.key + 1) as $s | .value.from as $asker
      | ($cites | any(.r == $s and (.to == $asker or .to == $all))) | not))
  | .[]
  | [$card, (.key + 1), .value.from, .value.kind, .value.ts,
     ((.value.body | split("\n") | .[0])[0:90])]
  | @tsv
  end'

# Emits one TSV line per unanswered message: card, seq, from, kind, ts, first line.
_owed_records() {
  local repo="$1" only_card="$2" me="$3" f card
  local dir="$BUS_HOME/$repo"
  [ -d "$dir" ] || return 0
  for f in "$dir"/*.jsonl; do
    [ -e "$f" ] || continue
    [ -s "$f" ] || continue
    card="${f##*/}"; card="${card%.jsonl}"
    [ -z "$only_card" ] || [ "$card" = "$only_card" ] || continue
    # CHEAP FIRST PASS, and it can only ever be wrong in the safe direction.
    # Nothing can be owed on a thread that holds no question and no request at
    # all, and deciding that with a literal scan costs a fraction of slurping the
    # file into jq. A body that happens to contain the words only causes the real
    # query to run, which is the answer anyway; the reverse — missing a real
    # question — cannot happen, because every record here is written by `jq -c`
    # from one fixed object shape, so the key is always spelled this way.
    # Measured: this is what takes the reminder printed after every message from
    # 0.26s down to the cost of the send itself.
    grep -q '"kind":"question"\|"kind":"request"' "$f" 2>/dev/null || continue
    # A damaged thread must not take down the summary, for the same reason `who`
    # skips one: refusing to answer "what do I owe" because an unrelated card is
    # corrupt hides work from the only person who could do it. The query failing
    # IS the detection now — a file jq cannot parse makes this call non-zero.
    # A closed thread owes nothing (the query returns nothing for one): the work
    # is finished, and re-listing it forever is how a reminder becomes noise.
    jq -r -s --arg me "$me" --arg all "$BROADCAST" --arg card "$card" "$_owed_jq" "$f" 2>/dev/null \
      || echo "bus: WARNING — $f is damaged and was skipped by owed." >&2
  done
}

_owed_count() {
  local n
  n="$(_owed_records "$1" "$2" "$3" 2>/dev/null | grep -c . || true)"
  printf '%s' "${n:-0}"
}

# HOW MANY THREADS COULD NOT BE READ. `_owed_records` skips a damaged thread with
# a warning, and every caller of `_owed_count` swallowed that warning and then
# reported the number as if it were complete — `bye` announced "Nothing was left
# unanswered" about a repo whose threads it had failed to open (@baccio).
# A zero computed after ignoring unreadable data is not a zero, and the
# difference between "none" and "none that I could see" is the whole value of
# the answer.
_unreadable_threads() {
  local repo="$1" f n=0
  local dir="$BUS_HOME/$repo"
  [ -d "$dir" ] || { printf '0'; return 0; }
  for f in "$dir"/*.jsonl; do
    [ -e "$f" ] && [ -s "$f" ] || continue
    jq -e . "$f" >/dev/null 2>&1 || n=$((n + 1))
  done
  printf '%s' "$n"
}

_cmd_owed() {
  local repo="" card="" as="" brief=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) _need $# "--repo"; repo="$2"; shift 2;;
      --card) _need $# "--card"; card="$2"; shift 2;;
      --as)   _need $# "--as";   as="$2";   shift 2;;
      # --brief RENDERS NO BODY, and it exists because of a boundary this file
      # was breaking. `hooks/bus-doorbell.sh` pushes its output into the model's
      # context automatically, and the full form prints the first 90 characters
      # of somebody else's message — prose by another agent, arriving as context,
      # without the UNVERIFIED stamp that `_emit` puts on every delivered line.
      # That is exactly the harm the 2026-07 board cut context-inject delivery
      # for: a message that arrives looking like context gets believed like
      # context. Being ADDRESSED TO ME does not make another agent's words safe
      # (@baccio, adversarial review). So: who asked, on which card, which
      # record, what kind, when — facts about the store — and not one word of
      # what they said. The words are one explicit `bus read` away.
      --brief) brief=1; shift;;
      *) die "owed: unknown argument '$1'";;
    esac
  done
  repo="$(_ident_repo "$repo")"
  [ -n "$repo" ] || die "owed: could not work out which repo this is — pass --repo"
  repo="$(_slug "--repo" "$repo")"
  as="$(_ident_role "$as" "owed")"
  _assert_role "$as"
  as="$(_slug "--as" "$as")"
  [ -z "$card" ] || card="$(_slug "--card" "$card")"
  local out; out="$(mktemp)"
  _owed_records "$repo" "$card" "$as" > "$out"
  if [ ! -s "$out" ]; then
    rm -f "$out"
    local blind; blind="$(_unreadable_threads "$repo")"
    if [ "$blind" != "0" ]; then
      echo "bus: @$as owes no answer in the threads that could be READ on $repo${card:+/$card} — $blind thread(s) could not be parsed and were skipped. Inspect them by hand; nothing here deletes or repairs a log."
    else
      echo "bus: @$as owes no answer on $repo${card:+/$card}."
    fi
    return 0
  fi
  echo "bus: $(grep -c . < "$out") message(s) are waiting for an answer from @$as on $repo."
  echo "Each one was addressed to you and no message of yours cites it back to whoever asked."
  echo
  if [ "$brief" = "1" ]; then
    awk -F'\t' '{ printf "  %s #%s  from @%s (%s, %s)\n", $1, $2, $3, $4, $5 }' "$out"
    echo
    echo "What they actually say is NOT shown here. Read it, and it will arrive stamped"
    echo "UNVERIFIED like every claim on this channel:  bus read --repo $repo --card <CARD>"
  else
    awk -F'\t' -v repo="$repo" -v me="$as" '{
      printf "  %s #%s  from @%s (%s, %s)\n", $1, $2, $3, $4, $5
      printf "      %s\n", $6
      printf "      answer:  bus send --repo %s --card %s --from %s --to %s --re %s --kind verdict\n\n", repo, $1, me, $3, $2
    }' "$out"
    echo "Read the full text of any of them with: bus log --repo $repo --card <CARD>"
  fi
  rm -f "$out"
}

# --- tidy: i thread di un lavoro finito smettono di chiamare -----------------
# Roberto, 2026-09-22, aprendo una sessione: "vorrei che il sistema riuscisse a
# tenersi pulito e evitare ste robe che non si capisce che cazzo sono". Aveva
# davanti dodici righe di posta non letta su tre thread: due appartenevano a card
# gia' in `done/`, il terzo a una card che non esiste. Quei thread avrebbero
# continuato a chiamare per sempre, perche' niente li chiude quando il lavoro
# finisce.
#
# Due cose che questo comando NON fa, e sono il motivo per cui e' un comando e non
# un effetto collaterale:
#  - NON legge lo stato kanban per DECIDERE da solo. Lo legge per PROPORRE, e la
#    chiusura la scrive solo con `--yes`. Il bus non muove card e le card non
#    muovono il bus: qui le guarda, e basta.
#  - NON cancella niente. `close` e' un record in piu' in un registro che non
#    dimentica: il thread resta leggibile per intero con `bus log`, smette solo di
#    essere consegnato e di farsi contare. Il ragionamento e' la cosa che il
#    kanban non conserva, ed e' l'ultima che si butta.
_card_is_done() {
  local card="$1" board
  while IFS= read -r board; do
    [ -n "$board" ] || continue
    [ ! -f "$board/done/$card.md" ] || { printf 'done'; return 0; }
    for state in todo doing; do
      [ ! -f "$board/$state/$card.md" ] || { printf 'open'; return 0; }
    done
  done < <(_card_boards)
  printf 'missing'
}

_cmd_tidy() {
  local repo="" by="" yes=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) _need $# "--repo"; repo="$2"; shift 2;;
      --by|--as) _need $# "$1"; by="$2"; shift 2;;
      --yes)  yes=1; shift;;
      *) die "tidy: unknown argument '$1'";;
    esac
  done
  repo="$(_ident_repo "$repo")"
  [ -n "$repo" ] || die "tidy: could not work out which repo this is — pass --repo"
  repo="$(_slug "--repo" "$repo")"
  local dir="$BUS_HOME/$repo" f cname state n=0 closed=0
  [ -d "$dir" ] || { echo "bus: no traffic for $repo — nothing to tidy."; return 0; }
  if [ "$yes" = "1" ]; then
    by="$(_ident_role "$by" "tidy")"
    _assert_role "$by"
    by="$(_slug "--by" "$by")"
  fi
  for f in "$dir"/*.jsonl; do
    [ -e "$f" ] && [ -s "$f" ] || continue
    jq -e . "$f" >/dev/null 2>&1 || continue
    [ "$(_thread_state "$f")" != "closed" ] || continue
    cname="${f##*/}"; cname="${cname%.jsonl}"
    state="$(_card_is_done "$cname")"
    [ "$state" != "open" ] || continue
    n=$((n + 1))
    if [ "$yes" = "1" ]; then
      local bf; bf="$(mktemp)"
      printf 'thread closed by tidy: the card is %s
' "$state" > "$bf"
      _with_lock "$f" _append_record "$f" "$repo" "$cname" "$by" "$BROADCAST" closed "" "$bf" ""
      rm -f "$bf"
      closed=$((closed + 1))
      echo "  chiuso  $cname  (card $state)"
    else
      echo "  $cname  — card $state, il thread e ancora aperto e continua a farsi contare"
    fi
  done
  if [ "$n" = "0" ]; then
    echo "bus: $repo e a posto — nessun thread aperto su lavoro finito."
  elif [ "$yes" = "1" ]; then
    echo "bus: chiusi $closed thread su $repo. Niente e stato cancellato: bus log li legge ancora per intero."
  else
    echo "bus: $n thread aperti su card finite o inesistenti in $repo."
    echo "     Continuano a farsi contare dal campanello finche restano aperti."
    echo "     Chiudili (senza perdere una parola):  bus tidy --repo $repo --yes"
  fi
}

# --- who -------------------------------------------------------------------
# Liveness WITHOUT leases: a role that appended or read four minutes ago is
# alive. Presence is observed, not declared - and there is no lease for a stray
# second session to refresh behind your back. Reads count too: a review agent
# that has been reading for three minutes used to show as dead.
#
# Since 2026-09-22 it answers with BOTH halves, and never merges them into one
# number. DECLARED is what a session said about itself (`hello`/`bye`); OBSERVED
# is what the store shows it doing. Merging them would be the same laundering
# this file refuses everywhere else: a declaration is a claim, and a claim
# printed next to the evidence is useful, while a claim printed AS evidence is a
# lie with a timestamp on it. A session killed without `bye` therefore shows as
# declared-present with an old last-action, which is exactly what is true.
_cmd_who() {
  local repo="" brief=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) _need $# "--repo"; repo="$2"; shift 2;;
      # --brief DROPS THE `doing` PROSE and keeps everything the store knows as a
      # fact: role, session, card, timestamps, and whether that role has done
      # anything since. It exists for the one caller that pushes its output into
      # a model's context automatically (hooks/context-inject.sh), under the rule
      # an adversarial review made explicit on 2026-09-22:
      #
      #   automatic context carries STRUCTURED OBSERVATIONS with their provenance.
      #   Free text written by another agent arrives through an explicit read,
      #   stamped UNVERIFIED. Being the addressee does not make words safe.
      #
      # `doing` is a sentence another session wrote about itself — "review done,
      # only the handover left" redefines what the reader thinks is needed while
      # issuing no instruction at all. Which is precisely the laundering the 2026-07
      # board cut context-inject delivery to prevent.
      --brief) brief=1; shift;;
      *) die "who: unknown argument '$1'";;
    esac
  done
  repo="$(_ident_repo "$repo")"
  [ -n "$repo" ] || die "who: could not work out which repo this is — pass --repo"
  repo="$(_slug "--repo" "$repo")"
  local dir="$BUS_HOME/$repo" f
  [ -d "$dir" ] || { echo "bus: no traffic for $repo."; return 0; }
  # The whole report is assembled into a file and written out ONCE, at the end.
  # `who` is a display command and its reader is allowed to stop reading — a
  # `bus who | grep -q something` closes the pipe on its first match, and a
  # command that dies of SIGPIPE mid-report under `set -e` turns a successful
  # answer into a failed one. Found exactly that way: adding the declared block
  # after the table gave the table a reader that was already gone.
  local report acts; report="$(mktemp)"; acts="$(mktemp)"
  {
  {
    for f in "$dir"/*.jsonl; do
      [ -e "$f" ] || continue
      # An empty log is a thread nobody has written to yet, not a damaged one.
      [ -s "$f" ] || continue
      # A damaged thread must not take down the summary: `who` answers "is anyone
      # there", and refusing to answer because one card's log is corrupt would
      # hide the very people who could fix it. Delivery still fails loud.
      if ! jq -e . "$f" >/dev/null 2>&1; then
        echo "bus: WARNING — $f is damaged and was skipped by who." >&2
        continue
      fi
      # A closed thread does not make anyone look alive: `who` answers "who is
      # working", and finished work is not work.
      [ "$(_thread_state "$f")" != "closed" ] || continue
      jq -r '[.from,.ts,"append",.card]|@tsv' "$f"
    done
    # .cursor/<card>/<role>: split on the path, not on dots. Parsing "<card>.<role>"
    # attributed a read by `sol.gate` on card `26.07` to a role called `gate` on a
    # card called `26.07.sol`.
    for f in "$dir"/.cursor/*/*; do
      [ -e "$f" ] || continue
      local rolename cardname
      rolename="${f##*/}"
      cardname="${f%/*}"; cardname="${cardname##*/}"
      # Skipping closed threads on the append path only was half a rule: a role
      # that had merely READ a thread still showed up under it, so closing hid
      # the writers and left the readers. Which half won depended on which
      # timestamp sorted last - the flakiest possible kind of bug.
      local clog="$dir/$cardname.jsonl"
      if [ -s "$clog" ] && jq -e . "$clog" >/dev/null 2>&1; then
        [ "$(_thread_state "$clog")" != "closed" ] || continue
      fi
      printf '%s\t%s\tread\t%s\n' "$rolename" "$(date -u -r "$f" '+%Y-%m-%dT%H:%M:%SZ')" "$cardname"
    done
  } | sort -k1,1 -k2,2r \
    | awk -F'\t' '!seen[$1]++' > "$acts"
  {
    echo "OBSERVED — what the store shows (an append or a read is the evidence)"
    echo "role                 last seen (UTC)       how     card"
    awk -F'\t' '{printf "%-20s %-21s %-7s %s\n", $1, $2, $3, $4}' "$acts"
  }
  # DECLARED, printed second and kept separate. Second because the evidence
  # should be read before the claim, and separate because a session that was
  # killed cannot retract its hello: what is true is "it said it was here and
  # has done nothing since", and that is what this prints.
  local pfile declared
  pfile="$(_presence_path "$repo")"
  declared="$(_declared_present "$pfile" || true)"
  echo
  if [ -z "$declared" ]; then
    echo "DECLARED — nobody has announced a session on $repo."
    echo "  An agent announces itself once, and then everyone knows who is on what:"
    echo "    eval \"\$(bus hello --repo $repo --as <ROLE> --card <CARD> --doing '<one line>')\""
  else
    echo "DECLARED — sessions that said hello and have not said bye (a claim, not evidence)"
    if [ "$brief" = "1" ]; then
      printf '%-20s %-24s %-14s %-21s %s\n' "role" "session" "card" "since (UTC)" "state"
    else
      printf '%-20s %-24s %-14s %-21s %s\n' "role" "session" "card" "since (UTC)" "doing / state"
    fi
    # SILENT SINCE HELLO. A declaration cannot be retracted by a session that was
    # killed, so the list of "who is here" grows and nobody ever leaves it —
    # which is the failure this whole change started from, one level along.
    # There is no timeout here and deliberately so: a timeout needs date
    # arithmetic that differs by platform, and worse, it would DECIDE that
    # somebody is gone. This decides nothing. It states one fact the store
    # already holds — whether that role has appended or read anything since the
    # moment it announced itself — and leaves the reader to draw the conclusion.
    # ISO-8601 in UTC with a fixed width sorts lexicographically, so the
    # comparison needs no date parsing at all.
    printf '%s\n' "$declared" \
      | awk -F'\t' -v actsfile="$acts" -v brief="$brief" '
          BEGIN { while ((getline line < actsfile) > 0) {
                    n = split(line, f, "\t"); if (n >= 2) last[f[1]] = f[2] } }
          { state = (brief == "1") ? "" : $5
            seen = ($1 in last) ? last[$1] : ""
            # THE UNIT MEASURED IS THE ROLE, AND THE LABEL SAYS SO. Activity is
            # observed per role; presence is declared per session. If two
            # sessions share a role, a recent action by one says nothing about
            # the other, so a label reading "this session is idle" would be a
            # claim the store cannot support (@baccio, adversarial review).
            if (seen == "" || seen <= $4)
              state = state (state == "" ? "" : "  ") "[no @" $1 " activity since]"
            printf "%-20s %-24s %-14s %-21s %s\n", $1, $2, $3, $4, state }'
  fi
  } > "$report"
  # A reader that has stopped reading is not an error here — see above.
  cat "$report" 2>/dev/null || true
  rm -f "$report" "$acts"
}

_cmd_roles() {
  local f found=0
  # A missing directory is not an empty one. `$DIR` comes from BASH_SOURCE, which
  # bash does NOT resolve through a symlink: invoked as a symlinked `bus`, every
  # path here would point next to the symlink instead of next to the script, and
  # "no roles defined" would be a lie told about the wrong directory. Say which.
  [ -d "$ROLES_DIR" ] \
    || die "no roles directory at $ROLES_DIR — if you reached this through a symlink, point the wrapper at bus/bus.sh itself or set RDA_BUS_ROLES"
  _assert_no_broadcast_manifest
  for f in "$ROLES_DIR"/*.json; do
    [ -e "$f" ] || break
    found=1
    # The agent line is what makes this discovery instead of a glossary: an agent
    # reading `bus roles` has to find ITSELF in the list, and "architect" did not
    # tell @baccio that @baccio is the architect. Every role file carries the
    # mapping, and a role without one says so rather than guessing.
    jq -r '"@\(.role)  — played by: \(.agent // "nobody has claimed this role yet")\n   may \(.may|join(", "))\n   may NOT \(.may_not|join(", "))\n"' "$f"
  done
  [ "$found" = "1" ] || echo "bus: no roles defined."
}

_cmd_log() {
  local repo="" card=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) _need $# "--repo"; repo="$2"; shift 2;;
      --card) _need $# "--card"; card="$2"; shift 2;;
      *) die "log: unknown argument '$1'";;
    esac
  done
  repo="$(_ident_repo "$repo")"
  [ -n "$repo" ] && [ -n "$card" ] || die "log: --card is required"
  repo="$(_slug "--repo" "$repo")"; card="$(_slug "--card" "$card")"
  local log; log="$(_log_path "$repo" "$card")"
  [ -f "$log" ] || { echo "bus: no traffic on $repo/$card."; return 0; }
  _assert_readable_log "$log"
  # Numbered, because a thread you cannot cite is a thread you can only talk
  # past: `--re N` needs the same N the reader is looking at.
  jq -c -s 'to_entries | map(.value + {_seq: (.key + 1)}) | .[]' "$log" \
    | _emit "$card" "${RDA_BUS_ROLE:-}"
}

_usage() {
  cat <<'USAGE'
bus — durable agent-to-agent messages. Pull-only: it never starts an agent.

THE SHAPE OF A SESSION. Announce yourself, read, answer what you owe, say bye.
  eval "$(bus hello --repo R --as ROLE --card C --doing 'one line')"   # once, at the start
  bus who --repo R                                                     # who else is on this repo
  bus owed                                                             # what is waiting for ME
  bus bye --repo R                                                     # once, when you finish

  bus hello --repo R [--as ROLE] [--card C] [--session ID] [--doing "..."]
           announce this session. Prints shell assignments on stdout: eval them and
           --as/--from/--repo become optional for every later call, sub-agents included.
  bus bye  --repo R [--as ROLE] [--why "..."]        declare this session finished
  bus send --repo R --card C --to ROLE|all [--from ROLE] [--kind request|verdict|note|question]
           [--re N] [--ref kb:<card>|git:<sha>] [--body-file F]   (body on stdin if no --body-file)
           --re N answers record #N of this thread, and is what clears it from `owed`.
  bus read --repo R --card C [--as ROLE] [--peek]    unread for ROLE (--peek: don't advance)
  bus owed [--repo R] [--card C] [--as ROLE]         questions addressed to you that you never answered
  bus count --repo R [--card C] [--as ROLE]          HOW MANY are unread, never what they say
  bus who  --repo R                                  who is here: OBSERVED activity + DECLARED presence
  bus roles                                          addressable roles + their manifests
  bus close --repo R --card C --by ROLE              finished: stop delivering, keep every word
  bus open  --repo R --card C --by ROLE              deliberately reopen a closed thread
  bus log  --repo R --card C                         the whole permanent thread, numbered

Identity, and what it is NOT:
  RDA_BUS_ROLE / RDA_BUS_SESSION / RDA_BUS_REPO are read when a flag is absent, and
  they are INHERITED by sub-processes - which is how a sub-agent knows who it is.
  This is not authentication: `--from` is self-declared and always was, and every
  delivered line still says so. What changed is that forgetting is no longer the default.

Nobody is woken, so how does anyone know there is mail?
  `bus count` prints one `card<TAB>role<TAB>n` line per role with unread mail and
  NOTHING at all when there is none - so a hook can ring a doorbell inside a session
  that is already running. A count carries no claim; bodies still only arrive
  through `read`. It never advances a cursor, and it is taken without the append
  lock, so it can be short by one mid-append and is corrected by the next one.

Why `owed` exists:
  a question used to be delivered once and then vanish behind the cursor, so
  "read it and meant to answer" was indistinguishable from "never arrived".
  A question or request stays listed until the addressee sends something citing
  it with --re. It is DERIVED from the log, so there is no second state to
  disagree with the thread. It cannot make anyone answer, and --re proves only
  that a message was cited - never that the answer was any good.

Cost, since it is the usual worry:
  - `read` delivers only what is NEW to that role; history is never re-sent.
  - a CLOSED thread costs one line and appears in no summary. Nothing is deleted:
    deletion would remove the reasoning, which is the part the kanban does not keep.

With three or more agents:
  - `--to <role>` is addressed delivery; `--to all` reaches every role but the sender.
  - Nothing is consumed from a shared queue: each role has its own cursor, so a
    message addressed to two roles is delivered to both, in full.
  - The addressee is a ROLE, not a process. Two sessions claiming the same role
    share one cursor and will split the mail between them - give them two roles.
    `bus who` now shows both sessions, so the collision is visible instead of silent.
  - Delivery is targeted, but the record is public: `bus log` shows every message
    to everyone. There is no private channel, on purpose.

Enforced here, not asked of you:
  - nothing in bus/ executes an agent CLI, a scheduler or kb (behavioural test + allowlist)
  - a role is addressable only with a manifest that claims no human-gated action
  - a citation resolves to exactly what it proves, and never to the word "verified"
  - presence is an append-only log of hello/bye events: nothing expires, nothing is
    renewed, nothing is collected, and no session is ever an addressee.

Heuristic, and declared as one:
  - acceptance criteria are refused in the obvious spellings; a rephrasing gets through.
    Scope comes from the card. The real control is a human reading a random sample.
  - a DECLARED presence is a claim. A session killed without `bye` keeps claiming it
    is here; `who` prints the claim next to the last observed action, never instead of it.
USAGE
}

case "${1:-}" in
  send)  shift; _cmd_send "$@";;
  read)  shift; _cmd_read "$@";;
  peek)  shift; _cmd_read "$@" --peek;;
  count) shift; _cmd_count "$@";;
  who)   shift; _cmd_who "$@";;
  hello) shift; _cmd_hello "$@";;
  bye)   shift; _cmd_bye "$@";;
  owed)  shift; _cmd_owed "$@";;
  tidy)  shift; _cmd_tidy "$@";;
  close) shift; _cmd_close "" "$@";;
  open)  shift; _cmd_close "reopen" "$@";;
  roles) shift; _cmd_roles "$@";;
  log)   shift; _cmd_log "$@";;
  ""|-h|--help|help) _usage;;
  *) die "unknown command '${1}' (try: bus --help)";;
esac
