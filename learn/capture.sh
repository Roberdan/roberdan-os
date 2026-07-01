#!/usr/bin/env bash
# learn/capture.sh — appende UN segnale di apprendimento alla staging inbox.
# Economico, no-lock, no-giudizio. Chiamabile da qualsiasi platform (hook Stop,
# fine-task, o a mano). Il giudizio (classifica/dedup/promozione) avviene dopo,
# in distill.sh + curate.sh. Vedi learn/learn-protocol.md.
set -euo pipefail

inbox="${RDA_INBOX:-$HOME/.roberdan-os/learnings/inbox}"
mkdir -p "$inbox"

# Segnale da $1 (testo) o stdin.
signal="${1:-$(cat)}"
[ -n "${signal// /}" ] || { echo "capture: segnale vuoto, skip" >&2; exit 0; }

# Privacy hard-gate (come CODICE, non discrezione):
# 1) mai catturare riferimenti al path del dossier
case "$signal" in
  *"/.roberdan-os/private/"*) echo "capture: blocco privacy (path dossier), skip" >&2; exit 0 ;;
esac
# 2) mai catturare contenuto che matcha la deny-list reale (nomi/entità confidenziali).
#    Deny-list runtime: ~/.roberdan-os/private/.denylist, fallback al repo.
denylist=""
for d in "$HOME/.roberdan-os/private/.denylist" "$(dirname "$0")/../private/.denylist"; do
  [ -f "$d" ] && { denylist="$d"; break; }
done
# NB: filtra righe vuote/commento della deny-list (un pattern vuoto in grep -f matcha tutto).
if [ -n "$denylist" ] && printf '%s' "$signal" | grep -iEf <(grep -vE '^[[:space:]]*($|#)' "$denylist") >/dev/null 2>&1; then
  echo "capture: blocco privacy (deny-list match), skip" >&2; exit 0
fi

day="$(date +%Y-%m-%d)"
sess="${RDA_SESSION:-${CLAUDE_SESSION_ID:-local}}"
ts="$(date +%Y-%m-%dT%H:%M:%S%z)"
file="$inbox/${day}-${sess}.md"

# 1 record/segnale, append-only.
printf -- '- [%s] %s\n' "$ts" "$signal" >> "$file"
echo "capture: +1 segnale → $file" >&2
