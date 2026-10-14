#!/usr/bin/env bash
# Sourced by bus.sh. Observations and election share one append lock; no executor is started.

_team_snapshot() {
  local log="$1" epoch="$2" ttl="$3"
  jq -cs --argjson epoch "$epoch" --argjson ttl "$ttl" '
    (last.coordinator // "") as $leader
    | reduce .[] as $e ({}; .[$e.session] = $e)
    | [.[] | select(.event != "leave" and ($epoch - .seen) < $ttl)]
    | sort_by(.joined, .session) as $members
    | {members:$members,
       coordinator: (if any($members[]; .session == $leader) then $leader
                     else ($members[0].session // "") end)}
  ' "$log"
}

_team_roles() {
  local log="$BUS_HOME/$1/.team.jsonl"
  [ -s "$log" ] || return 0
  _assert_readable_log "$log"
  _team_snapshot "$log" "$(date +%s)" "${RDA_BUS_TEAM_TTL:-300}" | jq -r '.members[].role'
}

_team_observe() {
  local log="$1" repo="$2" session="$3" host="$4" event="$5" epoch="$6" ttl="$7"
  local prior state joined seen role coordinator record
  [ -e "$log" ] || : > "$log"
  _assert_readable_log "$log"
  prior="$(jq -cs --arg s "$session" 'map(select(.session == $s)) | last // {}' "$log")"
  joined="$(jq -r --argjson now "$epoch" '
    if .event == "leave" or .joined == null then $now else .joined end' <<<"$prior")"
  seen="$(jq -r '.seen // 0' <<<"$prior")"
  role="implementer--$session"
  _assert_role "$role"
  record="$(jq -cn --arg session "$session" --arg role "$role" --arg host "$host" \
    --arg event "$event" --argjson seen "$epoch" --argjson joined "$joined" \
    '{session:$session,role:$role,host:$host,event:$event,seen:$seen,joined:$joined}')"
  # Compute the election INCLUDING this observation, before appending its decision.
  state="$( { cat "$log"; printf '%s\n' "$record"; } | jq -cs \
    --argjson epoch "$epoch" --argjson ttl "$ttl" '
      (.[-2].coordinator // "") as $leader
      | reduce .[] as $e ({}; .[$e.session] = $e)
      | [.[] | select(.event != "leave" and ($epoch - .seen) < $ttl)]
      | sort_by(.joined, .session) as $members
      | {members:$members, coordinator:
          (if any($members[]; .session == $leader) then $leader
           else ($members[0].session // "") end)}
    ')"
  coordinator="$(jq -r '.coordinator' <<<"$state")"
  # Observations at most every 30s, but departures and changed elections are immediate.
  if [ "$event" = "leave" ] || [ $((epoch - seen)) -ge 30 ] \
      || [ "$(jq -r '.coordinator // ""' <<<"$prior")" != "$coordinator" ]; then
    jq -c --arg coordinator "$coordinator" --arg repo "$repo" \
      '. + {repo:$repo,coordinator:$coordinator}' <<<"$record" >> "$log"
  fi
  _team_result "$state" "$repo" "$session" "$role"
}

_team_result() {
  jq -c --arg repo "$2" --arg session "$3" --arg role "$4" '
    . + {repo:$repo,session:$session,role:$role,
         coordinator_role: (if .coordinator=="" then "" else "implementer--" + .coordinator end),
         mode: (if (.members|length) < 2 then "solo"
                elif .coordinator == $session then "coordinator" else "worker" end)}
  ' <<<"$1"
}

_cmd_team() {
  local repo="" session="" host="unknown" event="observe" json=0 status=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) _need $# "$1"; repo="$2"; shift 2;;
      --session) _need $# "$1"; session="$2"; shift 2;;
      --host) _need $# "$1"; host="$2"; shift 2;;
      --leave) event="leave"; shift;;
      --status) status=1; shift;;
      --json) json=1; shift;;
      *) die "team: unknown argument '$1'";;
    esac
  done
  repo="$(_slug "--repo" "$(_ident_repo "$repo")")"
  session="$(_slug "--session" "${session:-${RDA_BUS_SESSION:-}}")"
  case "$host" in claude|copilot|unknown) ;; *) die "team: --host must be claude|copilot|unknown";; esac
  local ttl="${RDA_BUS_TEAM_TTL:-300}" epoch log state
  [[ "$ttl" =~ ^[0-9]+$ ]] && [ "$ttl" -ge 60 ] && [ "$ttl" -le 86400 ] \
    || die "team: RDA_BUS_TEAM_TTL must be 60..86400 seconds"
  epoch="$(date +%s)"
  log="$BUS_HOME/$repo/.team.jsonl"
  if [ "$status" = "1" ]; then
    if [ -s "$log" ]; then
      _assert_readable_log "$log"
      state="$(_team_snapshot "$log" "$epoch" "$ttl")"
    else
      state='{"members":[],"coordinator":""}'
    fi
    state="$(_team_result "$state" "$repo" "$session" "implementer--$session")"
  else
    # Do not register factory/verifiers or inherited one-shot subagents as coordinators.
    [ "${RDA_HEADLESS:-0}" != "1" ] && [ "${RDA_IN_THOR_VERIFY:-0}" != "1" ] \
      || die "team: headless/verifier sessions do not participate"
    state="$(_with_lock "$log" _team_observe "$log" "$repo" "$session" "$host" "$event" "$epoch" "$ttl")"
  fi
  if [ "$json" = "1" ]; then
    printf '%s\n' "$state"
  else
    jq -r '"bus team: \(.repo) — \(.mode), coordinator @\(.coordinator_role)",
      (.members[] | "  @\(.role) [\(.host)] session \(.session), last observed \(.seen)")' <<<"$state"
  fi
}
