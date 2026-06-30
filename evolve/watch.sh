#!/usr/bin/env bash
# evolve/watch.sh — watcher settimanale: rileva novità nei changelog dei tool e
# PROPONE draft (mai applica). Stato durevole in seen (flat KEY=FP). Vedi evolve/evolve-protocol.md.
# Lanciato da launchd com.roberdan.rda-evolve. Idempotente, non-blocking.
set -euo pipefail

state_dir="${RDA_EVOLVE_STATE:-$HOME/.roberdan-os/evolve}"
repo_root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || echo "$HOME/GitHub/roberdan-os")"
proposals="$repo_root/proposals"
seen="$state_dir/seen"            # flat: una riga "nome=sha256" per fonte
mkdir -p "$state_dir" "$proposals"
touch "$seen"

# Fonti: nome → URL changelog (versionato). Espandibile.
sources_names=(claude-code copilot codex)
sources_urls=(
  "https://docs.anthropic.com/en/release-notes/claude-code"
  "https://github.blog/changelog/label/copilot/"
  "https://github.com/openai/codex/releases"
)

now="$(date +%Y-%m-%d)"
new_count=0

for i in "${!sources_names[@]}"; do
  name="${sources_names[$i]}"; url="${sources_urls[$i]}"
  body="$(curl -fsSL --max-time 20 "$url" 2>/dev/null || true)"
  [ -n "$body" ] || { echo "watch: $name unreachable, skip" >&2; continue; }

  # Fingerprint del contenuto: cambio = possibile novità. Il capability-diff lo fa
  # un agente sul draft; qui rileviamo solo il delta.
  fp="$(printf '%s' "$body" | shasum -a 256 | cut -d' ' -f1)"
  prev="$(awk -F= -v k="$name" '$1==k{print $2}' "$seen" 2>/dev/null || true)"
  [ "$fp" = "$prev" ] && continue

  new_count=$((new_count+1))
  draft="$proposals/${now}-${name}.md"
  {
    echo "# evolve proposal — $name ($now)"
    echo
    echo "**Fonte:** $url"
    echo "**Stato:** DRAFT — richiede review umana (mai auto-applicato al canone)."
    echo
    echo "## Novità rilevata"
    echo "Changelog cambiato dall'ultima scansione. Un agente deve:"
    echo "1. estrarre le novità concrete (con versione + data),"
    echo "2. valutarne l'impatto su roberdan-os (hook/skill/agent/scheduling/MCP/memoria),"
    echo "3. proporre la patch + **citare la fonte**. Niente citazione → niente proposta."
  } > "$draft"
  echo "watch: NUOVA proposta → $draft" >&2

  # Aggiorna seen atomico: rimuovi la vecchia riga, aggiungi la nuova.
  grep -v "^${name}=" "$seen" > "$seen.tmp" 2>/dev/null || true
  printf '%s=%s\n' "$name" "$fp" >> "$seen.tmp"
  mv "$seen.tmp" "$seen"
done

echo "watch: $new_count novità → $proposals" >&2
