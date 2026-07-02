#!/usr/bin/env bash
# leak-check.sh — privacy gate. Fails if a confidential term (private/.denylist)
# shows up in ANY committable canon file or in a generated bundle.
# Run by validate.sh and by hand before every commit/bundle.
#   usage: test/leak-check.sh [extra-file ...]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DENYLIST="$ROOT/private/.denylist"

if [[ ! -f "$DENYLIST" ]]; then
  echo "leak-check: WARN denylist absent ($DENYLIST) — skipping (environment without a dossier)." >&2
  exit 0
fi

# Active patterns (no comments, no blank lines).
patterns="$(grep -vE '^\s*(#|$)' "$DENYLIST")"
[[ -z "$patterns" ]] && { echo "leak-check: empty denylist, nothing to check."; exit 0; }

# Targets: every tracked file (excludes private/, .git, binaries) + any extras (e.g. bundle).
# Portable to bash 3.2 (macOS): no mapfile.
targets=()
while IFS= read -r f; do
  [[ -n "$f" ]] && targets+=("$f")
done < <(cd "$ROOT" && git ls-files --cached --others --exclude-standard -- . ':!:private/**' 2>/dev/null)
# Adds extra files passed on the CLI (absolute paths or relative to cwd).
for f in "$@"; do targets+=("$f"); done
[[ ${#targets[@]} -eq 0 ]] && { echo "leak-check: no tracked files to check."; exit 0; }

hits=0
while IFS= read -r pat; do
  [[ -z "$pat" ]] && continue
  for f in "${targets[@]}"; do
    full="$f"; [[ -f "$ROOT/$f" ]] && full="$ROOT/$f"
    [[ -f "$full" ]] || continue
    if grep -niE "$pat" "$full" 2>/dev/null | grep -qv '^[0-9]*:.*denylist'; then
      echo "LEAK: pattern /$pat/ found in $f" >&2
      grep -niE "$pat" "$full" 2>/dev/null | head -3 | sed 's/^/   /' >&2
      hits=$((hits + 1))
    fi
  done
done <<< "$patterns"

if [[ "$hits" -gt 0 ]]; then
  echo "leak-check: FAIL — $hits confidential leaks. Do NOT commit/bundle." >&2
  exit 1
fi
echo "leak-check: OK — 0 confidential terms in the canon."
