#!/usr/bin/env bash
# gbrain-search-probe.sh — fixed questions, known right answer: does search find it in the top 3?
# Each row: source <TAB> EXACT expected slug <TAB> question (paraphrased, never the title).
# Questions are in the language of the source (English for code/ADR repos, Italian for the vault):
# measured 2026-09-24, Italian questions against English docs found the file 4/10 times, same questions
# in the source's language 9/10 with exact-slug matching (see the log in the card). The canon rule 'query gbrain in the source's language' rests on this.
# Exit 0 only if at least MIN (default 9) of the rows hit. Read-only.
set -uo pipefail
MIN="${MIN:-9}"
cd "$HOME/.gbrain" || exit 2
unset DATABASE_URL
hits=0; total=0
while IFS=$'\t' read -r src want q; do
  [ -n "$src" ] || continue
  total=$((total + 1))
  top="$(timeout 120 gbrain query "$q" --source "$src" --limit 3 --expand false 2>/dev/null | grep -E '^\[[0-9.]+\]' | head -3)"
  slugs="$(printf '%s\n' "$top" | sed -E 's/^\[[0-9.]+\] ([^ ]+).*/\1/')"
  if printf '%s\n' "$slugs" | grep -qxF -- "$want"; then
    hits=$((hits + 1)); printf 'HIT   %-34s %s\n' "$src" "$want"
  else
    printf 'MISS  %-34s %s  <- got: %s\n' "$src" "$want" "$(printf '%s' "$slugs" | tr '\n' ' ')"
  fi
done <<'EOF'
gstack-code-roberdan-os-67e84638	hooks-bus-doorbell-sh	the doorbell hook that counts unread bus messages after a tool call
gstack-code-roberdan-os-67e84638	skills/model-selection-policy/skill	which model is the current one for each family in the reviewed list
gstack-code-roberdan-os-67e84638	kanban-worktree-sweep-sh	remove only worktrees that are merged and clean
mirrorbuddy	docs/adr/0153-redis-centralized-env-resolution	how we read Redis environment variables from a single place
mirrorbuddy	docs/adr/0078-vercel-runtime-constraints	limits we accept running on the Vercel serverless runtime
virtualbpm-fy27	docs/adr/0010-fde-update-claim-provenance	why every number in the FDE update states where it comes from
virtualbpm-fy27	docs/msx-ise-correlation	how a customer engagement request is tied to its sales opportunity and to the engineering work tracker
convergioedu2030	docs/adr/0007-accessibility-wcag-22-aa	accessibility as a first-class engineering concern from the margins
convergioedu2030	docs/adr/0014-identity-and-tier-split-multi-tenancy	separate project identity and tiers for multiple tenants
vault	agent-learnings/roberdan-os-adr-0001-self-improving	roberdan-os che migliora da solo con evolve, learn e ontologia
EOF
printf 'gbrain-search-probe: %d/%d nei primi 3 (soglia %d)\n' "$hits" "$total" "$MIN"
[ "$hits" -ge "$MIN" ]
