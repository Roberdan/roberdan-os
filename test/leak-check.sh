#!/usr/bin/env bash
# leak-check.sh — privacy gate. Fallisce se un termine confidenziale (private/.denylist)
# compare in QUALSIASI file del canone committabile o in un bundle generato.
# Eseguito da validate.sh e a mano prima di ogni commit/bundle.
#   uso: test/leak-check.sh [extra-file ...]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DENYLIST="$ROOT/private/.denylist"

if [[ ! -f "$DENYLIST" ]]; then
  echo "leak-check: WARN denylist assente ($DENYLIST) — salto (ambiente senza dossier)." >&2
  exit 0
fi

# Pattern attivi (no commenti, no righe vuote).
patterns="$(grep -vE '^\s*(#|$)' "$DENYLIST")"
[[ -z "$patterns" ]] && { echo "leak-check: denylist vuota, nulla da controllare."; exit 0; }

# Target: ogni file tracciabile (esclude private/, .git, binari) + eventuali extra (es. bundle).
# Portabile a bash 3.2 (macOS): niente mapfile.
targets=()
while IFS= read -r f; do
  [[ -n "$f" ]] && targets+=("$f")
done < <(cd "$ROOT" && git ls-files --cached --others --exclude-standard -- . ':!:private/**' 2>/dev/null)
# Aggiunge file extra passati da CLI (path assoluti o relativi alla cwd).
for f in "$@"; do targets+=("$f"); done
[[ ${#targets[@]} -eq 0 ]] && { echo "leak-check: nessun file tracciato da controllare."; exit 0; }

hits=0
while IFS= read -r pat; do
  [[ -z "$pat" ]] && continue
  for f in "${targets[@]}"; do
    full="$f"; [[ -f "$ROOT/$f" ]] && full="$ROOT/$f"
    [[ -f "$full" ]] || continue
    if grep -niE "$pat" "$full" 2>/dev/null | grep -qv '^[0-9]*:.*denylist'; then
      echo "LEAK: pattern /$pat/ trovato in $f" >&2
      grep -niE "$pat" "$full" 2>/dev/null | head -3 | sed 's/^/   /' >&2
      hits=$((hits + 1))
    fi
  done
done <<< "$patterns"

if [[ "$hits" -gt 0 ]]; then
  echo "leak-check: FAIL — $hits leak confidenziali. NON committare/bundle." >&2
  exit 1
fi
echo "leak-check: OK — 0 termini confidenziali nel canone."
