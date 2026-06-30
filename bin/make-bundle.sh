#!/usr/bin/env bash
# make-bundle.sh — concatena SOLO il canone committato in 1 doc incollabile per
# ChatGPT / Claude web (Custom Instructions / Project). ESCLUDE SEMPRE private/.
#
# Sicurezza (l'unico artefatto che lascia la macchina): scrive su tmp, esegue il
# leak-check ESPLICITO sul tmp, e promuove l'output solo se il check passa (exit 0).
# Un check fallito non lascia mai un file leaky su disco.
#
#   bin/make-bundle.sh            → platforms/chatgpt/bundle.md
#   bin/make-bundle.sh -          → stdout (sempre dopo leak-check)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT="${1:-$ROOT/platforms/chatgpt/bundle.md}"
TMP="$(mktemp "${TMPDIR:-/tmp}/rda-bundle.XXXXXX.md")"
trap 'rm -f "$TMP"' EXIT

# Le SOLE fonti ammesse nel bundle — tutte canone committato, mai private/.
SECTIONS=(
  "behavior/roberto-mode.md"
  "behavior/roberto-voice.md"
  "behavior/thinking-toolkit.md"
  "rules/constitution.md"
  "rules/best-practices.md"
)

{
  echo "# roberdan-os — bundle canonico (incollabile)"
  echo
  echo "> Generato da bin/make-bundle.sh dal canone committato. NON contiene il dossier"
  echo "> confidenziale (private/). Incolla in Custom Instructions / Project."
  echo
  for f in "${SECTIONS[@]}"; do
    [ -f "$f" ] || { echo "make-bundle: manca $f" >&2; exit 1; }
    echo "---"; echo
    cat "$f"; echo
  done
  # Indice agenti (solo name + description dal frontmatter — non l'intero file).
  echo "---"; echo
  echo "## Agents (indice)"; echo
  for a in $(find agents -maxdepth 1 -name '*.md' | LC_ALL=C sort); do
    n="$(grep -m1 -E '^name:' "$a" | sed -E 's/^name:[[:space:]]*//')"
    d="$(grep -m1 -E '^description:' "$a" | sed -E 's/^description:[[:space:]]*//')"
    echo "- **$n** — $d"
  done
} > "$TMP"

# GATE: leak-check ESPLICITO sul tmp (il bundle è fuori da git: il git-walk non lo vede).
if ! "$ROOT/test/leak-check.sh" "$TMP" >/dev/null 2>&1; then
  echo "make-bundle: LEAK nel bundle — output NON promosso. Esegui test/leak-check.sh \"$TMP\" per i dettagli." >&2
  exit 1
fi

if [ "$OUT" = "-" ]; then
  cat "$TMP"
else
  mkdir -p "$(dirname "$OUT")"
  mv "$TMP" "$OUT"
  trap - EXIT
  echo "make-bundle: bundle pulito in $OUT ($(wc -l < "$OUT") righe)."
fi
