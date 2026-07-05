#!/usr/bin/env bash
# evolve/watch.sh — weekly watcher: detects novelties in tool changelogs and
# PROPOSES a draft (never applies). Durable state in seen (flat KEY=FP). See evolve/evolve-protocol.md.
# Launched by launchd com.roberdan.rda-evolve. Idempotent, non-blocking.
set -euo pipefail

RDA_HOME="${RDA_HOME:-$HOME/.roberdan-os}"
state_dir="${RDA_EVOLVE_STATE:-$RDA_HOME/evolve}"
repo_root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || echo "$HOME/GitHub/roberdan-os")"
proposals="$repo_root/proposals"
seen="$state_dir/seen"            # flat: one line "name=sha256" per source
mkdir -p "$state_dir" "$proposals"
touch "$seen"

# Sources: name → changelog URL (versioned). Expandable.
sources_names=(claude-code copilot codex hermes-agent warp)
sources_urls=(
  "https://docs.anthropic.com/en/release-notes/claude-code"
  "https://github.blog/changelog/label/copilot/"
  "https://github.com/openai/codex/releases"
  "https://github.com/NousResearch/hermes-agent/releases"
  "https://docs.warp.dev/getting-started/changelog"
)

now="$(date +%Y-%m-%d)"
new_count=0

for i in "${!sources_names[@]}"; do
  name="${sources_names[$i]}"; url="${sources_urls[$i]}"
  body="$(curl -fsSL --max-time 20 "$url" 2>/dev/null || true)"
  [ -n "$body" ] || { echo "watch: $name unreachable, skip" >&2; continue; }

  # Content fingerprint: a change = possible novelty. The capability-diff is done
  # by an agent on the draft; here we only detect the delta.
  fp="$(printf '%s' "$body" | shasum -a 256 | cut -d' ' -f1)"
  prev="$(awk -F= -v k="$name" '$1==k{print $2}' "$seen" 2>/dev/null || true)"
  [ "$fp" = "$prev" ] && continue

  new_count=$((new_count+1))
  draft="$proposals/${now}-${name}.md"
  {
    echo "# evolve proposal — $name ($now)"
    echo
    echo "**Source:** $url"
    echo "**Status:** DRAFT — requires human review (never auto-applied to the canon)."
    echo
    echo "## Novelty detected"
    echo "Changelog changed since the last scan. An agent must:"
    echo "1. extract the concrete novelties (with version + date),"
    echo "2. assess their impact on roberdan-os (hook/skill/agent/scheduling/MCP/memory),"
    echo "3. propose the patch + **cite the source**. No citation → no proposal."
  } > "$draft"
  echo "watch: NEW proposal → $draft" >&2

  # Atomically update seen: remove the old line, add the new one.
  grep -v "^${name}=" "$seen" > "$seen.tmp" 2>/dev/null || true
  printf '%s=%s\n' "$name" "$fp" >> "$seen.tmp"
  mv "$seen.tmp" "$seen"
done

echo "watch: $new_count novelties → $proposals" >&2
