#!/usr/bin/env bash
# copilot-local.sh — run GitHub Copilot CLI against a LOCAL Ollama model (BYOK), opt-in.
#
# WHY opt-in: this is the *complement* to the default cloud model (Claude via Copilot),
# for confidential/offline code and cheap grunt work — NOT a replacement. It sets the
# BYOK env vars ONLY for this one invocation, so your normal `copilot` (GitHub-hosted
# Opus/Sonnet) is left completely untouched.
#
# Usage:
#   copilot-local                       # RDA_LOCAL_MODEL, else first PULLED model from PREFERRED
#   copilot-local --model qwen3.6:35b   # pick another pulled Ollama model
#   copilot-local -p "refactor this"    # any copilot args pass straight through
#
# Requirements (verified 2026-07-17 on Apple M5 Max):
#   - Ollama running on localhost:11434 with an OpenAI-compatible /v1 endpoint
#   - a model that supports TOOL CALLING + STREAMING (Copilot BYOK hard requirement);
#     qwen3-coder:30b passes both and exposes a 256k context window.
#     qwen3.6:35b verified 2026-08-05: streamed tool_calls OK on /v1/chat/completions.
# Docs: https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/use-byok-models
set -euo pipefail

OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"

# Preference order for the AUTO-PICK when nothing is specified. First one actually
# PULLED wins. Hardcoding a single default silently broke this script once: the default
# named a model that was never pulled on this machine, so the offline escape hatch was
# dead until someone ran it. Embedding-only models (bge-m3, nomic-embed-text) are never
# auto-picked — they cannot chat and are here for gbrain.
PREFERRED="qwen3-coder:30b qwen3.6:35b qwen3:30b qwen3:14b"

MODEL="${RDA_LOCAL_MODEL:-}"

# Allow `--model X` as the first pair without swallowing the rest of copilot's args.
if [ "${1:-}" = "--model" ] && [ -n "${2:-}" ]; then
  MODEL="$2"; shift 2
fi

# Preflight: Ollama reachable?
if ! curl -sf "${OLLAMA_HOST}/v1/models" >/dev/null 2>&1; then
  echo "copilot-local: Ollama non raggiungibile su ${OLLAMA_HOST}. Avvialo con 'ollama serve' (o l'app)." >&2
  exit 1
fi

# Resolve the model: explicit choice wins; otherwise auto-pick the first PREFERRED one
# that is actually pulled, so the hatch keeps working when models come and go.
PULLED="$(curl -sf "${OLLAMA_HOST}/v1/models" | grep -o '"id":"[^"]*"' | sed 's/"id":"//;s/"$//')"

if [ -z "${MODEL}" ]; then
  for candidate in ${PREFERRED}; do
    if printf '%s\n' "${PULLED}" | grep -qx "${candidate}"; then MODEL="${candidate}"; break; fi
  done
fi

if [ -z "${MODEL}" ]; then
  echo "copilot-local: nessun modello locale utilizzabile. Nessuno di questi e' scaricato:" >&2
  for c in ${PREFERRED}; do echo "  - ${c}" >&2; done
  echo "               Scaricane uno con 'ollama pull qwen3-coder:30b', oppure scegline uno" >&2
  echo "               a mano con --model / RDA_LOCAL_MODEL. Presenti ora in Ollama:" >&2
  printf '%s\n' "${PULLED}" | sed 's/^/  - /' >&2
  exit 1
fi

# Preflight: model actually pulled? (only bites on an explicit --model / RDA_LOCAL_MODEL)
if ! printf '%s\n' "${PULLED}" | grep -qx "${MODEL}"; then
  echo "copilot-local: modello '${MODEL}' non presente in Ollama. Scaricalo con 'ollama pull ${MODEL}'." >&2
  echo "               Disponibili:" >&2
  printf '%s\n' "${PULLED}" | sed 's/^/  - /' >&2
  exit 1
fi

echo "copilot-local: modello locale '${MODEL}' via ${OLLAMA_HOST}/v1 (le tue sessioni 'copilot' normali restano sul cloud)." >&2

# Scoped to THIS process only — nothing leaks into the parent shell.
export COPILOT_PROVIDER_BASE_URL="${OLLAMA_HOST}/v1"
export COPILOT_PROVIDER_TYPE="openai"
export COPILOT_MODEL="${MODEL}"

exec copilot "$@"
