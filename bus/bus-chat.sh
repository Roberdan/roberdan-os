# shellcheck shell=bash
# bus/bus-chat.sh — `bus chat`: the thread as a chat log, one line per message,
# with the trust mark bus-trust.sh computed already printed inline instead of
# hidden behind the long CLAIM-BY banner _emit prints for `read`/`log`.
#
# Split out for the same reason as every other bus-*.sh file: test/file-size-
# baseline.txt freezes bus.sh's length. Sourced by bus.sh, so BUS_HOME, `die`,
# `_log_path`, `_ident_repo`, `_slug`, `_thread_state`, `_trust_mark` and
# `_assert_readable_log` already exist by call time.
#
# NEVER a second delivery path: this reads the whole permanent log (like `bus
# log`), it does not touch a cursor, and it renders nothing `bus log` could not
# already show — only the layout differs. Card 260924-142220, item G.
_cmd_chat() {
  local repo="" card="" follow=0 interval="${RDA_BUS_WAIT_INTERVAL:-5}"
  while [ $# -gt 0 ]; do case "$1" in
    --repo)   _need $# "--repo";  repo="$2"; shift 2;;
    --card)   _need $# "--card";  card="$2"; shift 2;;
    --follow) follow=1; shift;;
    *) die "chat: unknown argument '$1'";; esac done
  repo="$(_ident_repo "$repo")"
  [ -n "$repo" ] && [ -n "$card" ] || die "chat: --repo and --card are required"
  repo="$(_slug "--repo" "$repo")"; card="$(_slug "--card" "$card")"
  local log; log="$(_log_path "$repo" "$card")"
  [ -f "$log" ] || { echo "bus: no traffic on $repo/$card."; return 0; }
  _assert_readable_log "$log"

  _chat_render() {
    local from_line="${1:-1}"
    jq -c -s "if length >= $from_line then .[$((from_line - 1)):][] else empty end" "$log" 2>/dev/null \
      | while IFS= read -r rec; do
          local m; m="$(_trust_mark "$repo" "$rec")"
          local ts from to kind re body first
          ts="$(jq -r '.ts' <<<"$rec")"; from="$(jq -r '.from' <<<"$rec")"
          to="$(jq -r '.to' <<<"$rec")"; kind="$(jq -r '.kind' <<<"$rec")"
          re="$(jq -r '.re // empty' <<<"$rec")"
          body="$(jq -r '.body' <<<"$rec")"
          first="${body%%$'\n'*}"
          [ "${#first}" -le 120 ] || first="${first:0:117}..."
          printf '[%s] @%-12s -> %-6s (%s%s) %s\n    %s\n' \
            "$ts" "$from" "$to" "$kind" "${re:+ re#$re}" "$m" "$first"
        done
  }

  _chat_render 1
  [ "$follow" = "1" ] || return 0
  local seen; seen="$(wc -l < "$log" | tr -d ' ')"
  while :; do
    sleep "$interval"
    [ "$(_thread_state "$log")" != "closed" ] || { echo "bus: $repo/$card closed — chat --follow stopping."; return 0; }
    local total; total="$(wc -l < "$log" 2>/dev/null | tr -d ' ')"
    [ "${total:-0}" -gt "${seen:-0}" ] || continue
    _chat_render $((seen + 1))
    seen="$total"
  done
}
