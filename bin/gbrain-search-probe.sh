#!/usr/bin/env bash
# gbrain-search-probe.sh — fixed questions, known right answer: does search find it in the top 3?
#
# The 10 rows are NEVER committed: they name private-repo slugs and internal project vocabulary
# (scar 2026-09-24 — an earlier version shipped them inline in this file, which is public). They
# live in a PRIVATE file instead, default $HOME/.roberdan-os/private/gbrain-probe.tsv (chmod 600),
# overridable via GBRAIN_PROBE_FILE. See bin/gbrain-search-probe.example.tsv for the row format —
# two public rows against roberdan-os itself, safe to commit and to run as-is.
#
# Each row: source <TAB> EXACT expected slug <TAB> question (paraphrased, never the title).
# Questions are in the language of the source (English for code/ADR repos, Italian for the vault):
# measured 2026-09-24, Italian questions against English docs found the file 4/10 times, same
# questions in the source's language 9/10 with exact-slug matching.
#
# Exit 0 only if at least MIN (default 9) of the rows hit. Exit 2 if the file is missing or empty
# — "not configured", never a failed probe: a caller (bin/system-health.sh) must tell the two
# apart, since the second needs a proposal and the first needs a shrug.
set -uo pipefail
MIN="${MIN:-9}"
FILE="${GBRAIN_PROBE_FILE:-$HOME/.roberdan-os/private/gbrain-probe.tsv}"

if [ ! -s "$FILE" ]; then
  echo "gbrain-search-probe: non configurata (nessuna domanda in $FILE — vedi bin/gbrain-search-probe.example.tsv)"
  exit 2
fi

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
done < "$FILE"
printf 'gbrain-search-probe: %d/%d nei primi 3 (soglia %d)\n' "$hits" "$total" "$MIN"
[ "$hits" -ge "$MIN" ]
