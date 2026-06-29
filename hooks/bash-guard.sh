#!/usr/bin/env bash
# PreToolUse Bash guard — solo la metà git/gh universale (sicurezza, non token-saving).
# Le regole npm/test-runner sono per-repo e NON vivono qui (vedi hook repo-local).
# Richiede `jq`.
set -euo pipefail

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"

deny() { jq -cn --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'; exit 0; }
ask()  { jq -cn --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'; exit 0; }

# Tronca il corpo heredoc (dati, non comandi) per evitare falsi positivi sui messaggi di commit.
cmd_head="${cmd%%<<*}"
norm="$(printf '%s' "$cmd_head" | tr -s ' \t\n' ' ' | sed 's/^ //;s/ $//')"

# 1) Push pericolosi: --force / -f / --no-verify → sempre vietati (azione irreversibile).
if printf '%s' "$norm" | grep -qE 'git[[:space:]]+push.*(--no-verify|(^|[[:space:]])-f([[:space:]]|$)|--force)'; then
  deny "--no-verify / --force su git push vietati. Risolvi la causa (hook fallito, conflitto), non bypassare. Gate umano #2 per il force-push su main."
fi

# 2) gh pr merge → richiede approvazione umana esplicita (gate umano #1).
if printf '%s' "$norm" | grep -qE '^gh[[:space:]]+pr[[:space:]]+merge'; then
  ask "Prima di mergiare: 'gh pr checks <n>', incolla output, conferma tutti SUCCESS, e ottieni 'sì' esplicito dell'utente. Vedi skills/ship."
fi

# 3) Reset/clean distruttivi su history o working tree → conferma.
if printf '%s' "$norm" | grep -qE 'git[[:space:]]+(reset[[:space:]]+--hard|clean[[:space:]]+-[a-z]*f)'; then
  ask "git reset --hard / clean -f distrugge modifiche non committate. Conferma esplicita prima di procedere."
fi

exit 0
