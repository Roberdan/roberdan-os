#!/usr/bin/env bash
# sora-azure.sh — Sora 2 on Azure OpenAI, keyless (Entra).
#
#   sora-azure.sh create  "<prompt>" [size] [seconds]   -> prints job id
#   sora-azure.sh status  <job_id>
#   sora-azure.sh wait    <job_id> [timeout_s]
#   sora-azure.sh get     <job_id> <out.mp4>
#   sora-azure.sh shot    "<prompt>" <out.mp4> [size] [seconds]   # create+wait+get
#   sora-azure.sh remix   <job_id> "<instruction>"                # one variable at a time
#
# Requires: AZURE_OPENAI_ENDPOINT (trailing slash), az login, jq, curl.
# Optional: SORA_DEPLOYMENT (default sora-2).
set -euo pipefail

ENDPOINT="${AZURE_OPENAI_ENDPOINT:?set AZURE_OPENAI_ENDPOINT, e.g. https://<res>.openai.azure.com/}"
ENDPOINT="${ENDPOINT%/}/"
MODEL="${SORA_DEPLOYMENT:-sora-2}"
API="api-version=preview"

token() { az account get-access-token --resource https://cognitiveservices.azure.com --query accessToken -o tsv; }
api() { # api <method> <path> [body]
  local method="$1" path="$2" body="${3:-}"
  if [[ -n "$body" ]]; then
    curl -sS -X "$method" "${ENDPOINT}openai/v1/${path}?${API}" \
      -H "Authorization: Bearer $(token)" -H 'Content-Type: application/json' -d "$body"
  else
    curl -sS -X "$method" "${ENDPOINT}openai/v1/${path}?${API}" -H "Authorization: Bearer $(token)"
  fi
}

cmd_create() {
  local prompt="$1" size="${2:-1280x720}" secs="${3:-4}"
  local body
  body=$(jq -nc --arg m "$MODEL" --arg p "$prompt" --arg s "$size" --arg d "$secs" \
    '{model:$m, prompt:$p, size:$s, seconds:$d}')
  local resp; resp=$(api POST videos "$body")
  local id; id=$(echo "$resp" | jq -r '.id // empty')
  [[ -n "$id" ]] || { echo "create failed: $resp" >&2; return 1; }
  echo "$id"
}

cmd_status() { api GET "videos/$1" | jq -r '{id, status, progress, error: (.error.message // null)}'; }

cmd_wait() {
  local id="$1" timeout="${2:-600}" waited=0 st
  while (( waited < timeout )); do
    st=$(api GET "videos/$id" | jq -r '.status')
    case "$st" in
      completed|succeeded) echo "completed"; return 0 ;;
      failed|cancelled)    api GET "videos/$id" | jq -r '.error.message // "failed"' >&2; return 1 ;;
    esac
    sleep 10; waited=$((waited + 10))
    printf '  %ss %s\n' "$waited" "$st" >&2
  done
  echo "timeout after ${timeout}s (still $st)" >&2; return 1
}

cmd_get() {
  local id="$1" out="$2"
  curl -sS -L "${ENDPOINT}openai/v1/videos/${id}/content?${API}" \
    -H "Authorization: Bearer $(token)" -o "$out"
  # a JSON error body is not a video
  if head -c 1 "$out" | grep -q '{'; then echo "download failed: $(cat "$out")" >&2; rm -f "$out"; return 1; fi
  ffprobe -v error -show_entries format=duration,size -of default=nw=1 "$out"
  echo "$out"
}

cmd_shot() {
  local prompt="$1" out="$2" size="${3:-1280x720}" secs="${4:-4}"
  local id; id=$(cmd_create "$prompt" "$size" "$secs")
  echo "job $id" >&2
  cmd_wait "$id" 900 >/dev/null
  cmd_get "$id" "$out"
}

cmd_remix() {
  local id="$1" instruction="$2"
  local body; body=$(jq -nc --arg m "$MODEL" --arg p "$instruction" --arg r "$id" \
    '{model:$m, prompt:$p, remix_video_id:$r}')
  api POST videos "$body" | jq -r '.id // .'
}

case "${1:-}" in
  create) shift; cmd_create "$@" ;;
  status) shift; cmd_status "$@" ;;
  wait)   shift; cmd_wait "$@" ;;
  get)    shift; cmd_get "$@" ;;
  shot)   shift; cmd_shot "$@" ;;
  remix)  shift; cmd_remix "$@" ;;
  *) sed -n '2,14p' "$0"; exit 2 ;;
esac
