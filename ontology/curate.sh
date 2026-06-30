#!/usr/bin/env bash
# ontology/curate.sh — SINGLE-WRITER: promuove i candidati APPROVATI dalla quarantena
# a note tipate nel vault (type: agent-learning), con retry sul lock Tolaria AutoGit.
# Mai auto-promuove (richiede approved: true). Produce anche un report d'igiene.
# Vedi ontology/ontology-protocol.md. Lanciato da launchd. bash-3.2 + BSD-safe.
set -euo pipefail

quar="${RDA_QUARANTINE:-$HOME/.roberdan-os/learnings/quarantine}"
default_vault="$HOME/Obsidian/Roberdan's Vault"   # apostrofo ok in doppi apici semplici
vault="${RDA_VAULT:-$default_vault}"              # ...ma NON dentro ${:-} (rompe bash)
dest="$vault/agent-learnings"
state="${RDA_EVOLVE_STATE:-$HOME/.roberdan-os/evolve}"
report="$state/hygiene-$(date +%Y-%m-%d).md"
mkdir -p "$dest" "$state"

# Lock guard: un solo writer sul vault. Retry su .git/index.lock.
git_safe() {
  local tries=0
  while [ -f "$vault/.git/index.lock" ] && [ "$tries" -lt 10 ]; do sleep 3; tries=$((tries+1)); done
  git -C "$vault" "$@"
}

promoted=0
for c in "$quar"/*.md; do
  [ -e "$c" ] || continue
  grep -qE '^approved:[[:space:]]*true' "$c" || continue
  cls="$(grep -E '^class:' "$c" | head -1 | sed -E 's/^class:[[:space:]]*//;s/[[:space:]]*#.*//')"
  [ -n "$cls" ] && [ "$cls" != "TODO" ] || continue
  body="$(awk '/^## Segnale/{f=1;next} /^## /{f=0} f && NF' "$c")"
  [ -n "$body" ] || continue

  slug="agent-learning-$(date +%Y%m%d-%H%M%S)-$promoted"
  note="$dest/$slug.md"
  printf -- '---\n_organized: true\ntype: agent-learning\nclass: %s\nworkspace: agent-learnings\ncaptured: %s\n---\n\n# %s\n\n%s\n' \
    "$cls" "$(date +%Y-%m-%d)" "$slug" "$body" > "$note"
  promoted=$((promoted+1))
  mv "$c" "$c.promoted" 2>/dev/null || true
done

if [ "$promoted" -gt 0 ]; then
  git_safe add "agent-learnings" 2>/dev/null || true
  git_safe commit -m "chore(memory): promuovi $promoted agent-learning dalla quarantena" 2>/dev/null || true
fi

total="$(ls "$dest"/*.md 2>/dev/null | wc -l | tr -d ' ')"
pending="$(grep -LE '^approved:[[:space:]]*true' "$quar"/*.md 2>/dev/null | wc -l | tr -d ' ')"
printf -- '# igiene memoria — %s\n\n- promossi questo run: %s\n- note agent-learning totali: %s\n- candidati quarantena non approvati: %s\n\n## Proposte (gated, umano decide)\n- dedup semantico near-dup quando il provider embedding è attivo\n- tombstone retire: note RISOLTO/pre-v3 → agent-learnings/_archive/\n' \
  "$(date +%Y-%m-%d)" "$promoted" "$total" "$pending" > "$report"
echo "curate: $promoted promossi · report → $report" >&2
