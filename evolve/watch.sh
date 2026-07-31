#!/usr/bin/env bash
# evolve/watch.sh — weekly watcher: detects novelties in tool changelogs and, per novelty,
# DROPS A KANBAN CARD any agent (Claude, Copilot, …) can pick up and execute on its next run.
# It does NOT analyze itself and NEVER launches a headless agent — the card IS the handoff
# (Roberto's choice: no `claude -p`, use the kanban dispatch pattern). Never applies to the
# canon. Durable state in seen (flat KEY=FP). See evolve/evolve-protocol.md.
# Launched by launchd com.roberdan.rda-evolve. Idempotent, non-blocking.
set -euo pipefail

RDA_HOME="${RDA_HOME:-$HOME/.roberdan-os}"
state_dir="${RDA_EVOLVE_STATE:-$RDA_HOME/evolve}"
repo_root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || echo "$HOME/GitHub/roberdan-os")"
# Cards land in the kanban todo column (gitignored, local-only). Overridable for tests so a
# run never dirties the real board.
kb_todo="${RDA_KANBAN_TODO:-$repo_root/kanban/todo}"
# A card already being worked on suppresses a new one just as much as an untouched
# one does: the agent holding it will read the refreshed body.
kb_doing="${RDA_KANBAN_DOING:-$repo_root/kanban/doing}"
seen="$state_dir/seen"            # flat: one line "name=sha256" per source
mkdir -p "$state_dir" "$kb_todo"
touch "$seen"

# --- BACKPRESSURE (2026-07-28) ------------------------------------------------
# This watcher is a generator with no guaranteed consumer, and on 2026-07-28 that
# showed: proposals/ stopped at 07-19, the five cards from 07-25 were never worked,
# and the next Saturday run would have added five more. A board that grows by five
# a week regardless of what gets closed is unusable within a month.
#
# The fix is COALESCING, not expiry. An unresolved card for a source already IS the
# open request "assess $name"; a second one carries no more information, it just
# splits attention. So a later changelog change REFRESHES that card instead of
# adding a sibling, and the card states how many changes it now covers.
#
# It deliberately does NOT close or expire anything. Moving a card out of todo/ is a
# human gate (kb start needs Roberto, kb finish needs @thor); a watcher that retired
# its own cards on a timer would be exactly the automated gate-crossing the rest of
# this system refuses. Staleness is ANNOTATED here and decided by a human.
_open_card_for() {
  local name="$1" f
  for f in "$kb_todo"/*-"$name".md "$kb_doing"/*-"$name".md; do
    [ -e "$f" ] && { printf '%s\n' "$f"; return 0; }
  done
  return 1
}

# Sources: name → changelog URL (versioned). Expandable.
# codex and hermes-agent dropped 2026-07-31 (Roberto: tools no longer in use). A watcher
# that files cards about a tool nobody runs spends his gate on nothing.
# L'URL sorvegliato deve essere anche quello LEGGIBILE da chi raccoglie la card. Il watcher
# rileva il delta — e quella parte reggeva — e apre una card che dice a un agente "vai a
# leggere questa fonte": se la pagina si costruisce nel browser, quell'agente riceve menu e
# script. E' il modo silenzioso di rompersi, ed e' quello che test/test-evolve-sources.sh ora
# impedisce. Misurato il 2026-07-31, marcatori di rilascio distinti trovati via curl:
#   claude-code  docs.anthropic.com/en/release-notes/... =   0  ->  raw CHANGELOG.md = 101
#   warp         /getting-started/changelog             =   2  ->  /changelog/2026.md =  70
#   copilot      /changelog/label/copilot/              =  17  (gia' leggibile, invariato)
# Due sorgenti su tre erano cieche, non una.
sources_names=(claude-code copilot warp)
sources_urls=(
  "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md"
  "https://github.blog/changelog/label/copilot/"
  "https://docs.warp.dev/changelog/2026.md"
)

now="$(date +%Y-%m-%d)"
new_count=0        # changelog deltas detected
created=0          # cards actually added to the board
coalesced=0        # deltas folded into a card that was already open

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

  # COALESCE: an unresolved card for this source already carries the request.
  # Refresh it and move on — never add a sibling. `seen` is still advanced, so the
  # same change is not re-detected forever.
  if existing="$(_open_card_for "$name")"; then
    # `grep -c` prints 0 AND exits 1 when there is no match, so a `|| echo 0`
    # fallback appends a SECOND zero and the arithmetic dies on "0\n0". Let the
    # count stand and only neutralise the exit status.
    covered=$(( $(grep -c '^- changelog changed on ' "$existing" 2>/dev/null || true) + 2 ))
    {
      echo
      echo "- changelog changed on $now (still unresolved; this card now covers $covered changes)"
    } >> "$existing"
    coalesced=$((coalesced+1))
    echo "watch: COALESCED into $existing ($name changed again, no new card)" >&2
    grep -v "^${name}=" "$seen" > "$seen.tmp" 2>/dev/null || true
    printf '%s=%s\n' "$name" "$fp" >> "$seen.tmp"
    mv "$seen.tmp" "$seen"
    continue
  fi

  created=$((created+1))
  # One card per novel source. Id is timestamped AND suffixed with the source name so two
  # changelogs changing in the same second don't collide on the id. Frontmatter matches the
  # kb schema (title, repo, dod, acceptance, status, created) that test/validate.sh lints.
  card_id="$(date +%y%m%d-%H%M%S)-${name}"
  card="$kb_todo/${card_id}.md"
  {
    echo '---'
    echo "title: \"evolve: analyze $name updates and propose optimizations for roberdan-os\""
    echo "repo: roberdan-os"
    echo "dod: \"Concrete $name novelties extracted (version + date) from the changelog; impact on roberdan-os assessed (hook/skill/agent/scheduling/MCP/memory/factory/loop); proposal written to proposals/${now}-${name}.md with source citation. Draft-only: no change to behavior/rules/agents/AGENTS.md.\""
    echo "acceptance: \"proposals/${now}-${name}.md exists with novelties + impact + suggested patch and the source URL/version/date cited; the canon is untouched.\""
    echo 'status: todo'
    echo "created: $now"
    echo '---'
    echo
    echo "**Auto-generated by the evolve watcher** ($now) — \`$name\`'s changelog changed since the last scan."
    echo
    echo "Source: $url"
    echo
    # Rejected-proposal buffer: what was already assessed and declined for THIS source, so the
    # agent doesn't re-derive it a fourth week running (see evolve/declined.sh for the measured
    # case this exists for). Informational — it never suppresses a genuine novelty.
    if declined_block="$("$(dirname "$0")/declined.sh" render "$name" 2>/dev/null)" && [ -n "$declined_block" ]; then
      echo "**Already assessed and DECLINED for \`$name\`** — do not re-propose these unless the"
      echo "source shows something materially new about them; say explicitly that you skipped them:"
      echo
      printf '%s\n' "$declined_block"
      echo
    fi
    echo "Task for whichever agent picks this card up (any CLI — Claude, Copilot):"
    echo "1. Open the source; identify the concrete novelties since the last known version (with version + date)."
    echo "2. For each, assess whether it touches something roberdan-os uses (hook, skill, agent, scheduling, MCP, memory, factory, loop)."
    echo "3. Write the proposal to \`proposals/${now}-${name}.md\`: what changes, why, the suggested patch — **with source citation (URL + version + date)**. No citation → no proposal."
    echo "4. Do NOT apply to the canon: draft-only, human gate (see evolve/evolve-protocol.md)."
    echo "5. For every novelty you assess and decide needs NO patch, record it so next week's card"
    echo "   carries it forward: \`evolve/declined.sh add $name \"<one-line summary>\"\`."
  } > "$card"
  echo "watch: NEW card → $card" >&2

  # Atomically update seen: remove the old line, add the new one.
  grep -v "^${name}=" "$seen" > "$seen.tmp" 2>/dev/null || true
  printf '%s=%s\n' "$name" "$fp" >> "$seen.tmp"
  mv "$seen.tmp" "$seen"
done

echo "watch: $new_count novelt(ies) → $created new card(s), $coalesced folded into cards already open, in $kb_todo (run \`kb\` to see them)" >&2
