#!/usr/bin/env bash
# leak-check.sh — privacy gate. Fails if a confidential term shows up in ANY committable
# canon file or in a generated bundle. Run by validate.sh and by hand before every commit/bundle.
#   usage: test/leak-check.sh [extra-file ...]
#
# Three-tier fallback, most to least capable:
#   (a) private/.denylist exists (Roberto's real machine only, gitignored, never in CI):
#       authoritative — plain grep -niE of each pattern against every target file. Can print
#       the actual confidential text in its own error output (it's local-only, never seen by CI).
#   (b) else test/denylist.sha256 exists (committed, see bin/update-denylist-hashes.sh): CI
#       can check WITHOUT ever holding or printing the confidential terms. Scans every tracked
#       text file, normalizes it the same way the hash file's entries were normalized, hashes
#       every word n-gram (up to the header's max-words) with the file's stored salt, and fails
#       on any match against the stored hash set. Reports the file + line + n-gram word-offset
#       of a hit — NEVER the matched text itself, since we don't have it: only its hash. Single
#       Python pass over the whole corpus (not a per-word shell loop) — the repo is small
#       (~1MB text) so this finishes in a couple of seconds.
#       Honest tradeoff (see bin/update-denylist-hashes.sh and AGENTS.md § Privacy): a
#       committed salt stops casual reading of the denylist and keeps CI logs clean, but does
#       NOT stop a dictionary attack against guessed names — anyone can hash a guess with the
#       same salt and compare. This upgrades CI from "cannot check at all" to "checks without
#       revealing the list", not to cryptographic secrecy of the names themselves.
#   (c) else: today's no-op warning — no way to check without either file present.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Overridable for tests (see test/test-leak-check.sh) — unset in normal use.
DENYLIST="${RDA_DENYLIST_SRC:-$ROOT/private/.denylist}"
HASHFILE="${RDA_DENYLIST_HASHFILE:-$ROOT/test/denylist.sha256}"

# Targets: every tracked file (excludes private/, .git, binaries) + any extras (e.g. bundle).
# Portable to bash 3.2 (macOS): no mapfile. Shared by tiers (a) and (b).
targets=()
while IFS= read -r f; do
  [[ -n "$f" ]] && targets+=("$f")
done < <(cd "$ROOT" && git ls-files --cached --others --exclude-standard -- . ':!:private/**' 2>/dev/null)
# Adds extra files passed on the CLI (absolute paths or relative to cwd).
for f in "$@"; do targets+=("$f"); done

# --- Tier (a): private/.denylist present — authoritative, local-only -------------------
if [[ -f "$DENYLIST" ]]; then
  patterns="$(grep -vE '^\s*(#|$)' "$DENYLIST")"
  [[ -z "$patterns" ]] && { echo "leak-check: empty denylist, nothing to check."; exit 0; }
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
    echo "leak-check: FAIL — $hits confidential leaks (tier a, denylist). Do NOT commit/bundle." >&2
    exit 1
  fi
  echo "leak-check: OK — 0 confidential terms in the canon (tier a, denylist)."
  exit 0
fi

# --- Tier (b): test/denylist.sha256 present — salted-hash check, CI-safe ---------------
if [[ -f "$HASHFILE" ]]; then
  if ! command -v python3 >/dev/null 2>&1; then
    echo "leak-check: WARN test/denylist.sha256 present but python3 missing — cannot run tier (b), skipping." >&2
    exit 0
  fi
  [[ ${#targets[@]} -eq 0 ]] && { echo "leak-check: no tracked files to check."; exit 0; }
  python3 - "$ROOT" "$HASHFILE" "${targets[@]}" <<'PYEOF'
import hashlib
import os
import re
import sys

root, hashfile, *rel_targets = sys.argv[1:]

salt = None
max_words = 1
hashes = set()
with open(hashfile, "r", encoding="utf-8", errors="replace") as fh:
    for line in fh:
        line = line.rstrip("\n")
        if line.startswith("#"):
            m = re.match(r"#\s*salt:\s*(\S+)", line)
            if m:
                salt = m.group(1)
            m = re.match(r"#\s*max-words:\s*(\d+)", line)
            if m:
                max_words = int(m.group(1))
            continue
        line = line.strip()
        if re.fullmatch(r"[0-9a-f]{64}", line):
            hashes.add(line)

if not salt or not hashes:
    print("leak-check: WARN test/denylist.sha256 present but unparseable (missing salt/hashes) — skipping tier (b).", file=sys.stderr)
    sys.exit(0)

WS_RE = re.compile(r"\s+")


def normalize(s: str) -> str:
    # Must match bin/update-denylist-hashes.sh's normalize() exactly: lowercase, collapse
    # all whitespace to a single space, trim ends.
    return WS_RE.sub(" ", s.lower()).strip()


def ngram_hash(ngram: str) -> str:
    return hashlib.sha256((salt + "\n" + ngram).encode("utf-8")).hexdigest()


hits = 0
for rel in rel_targets:
    full = rel if not root or rel.startswith("/") else root + "/" + rel
    if not os.path.isfile(full):
        full = rel
        if not os.path.isfile(full):
            continue
    try:
        with open(full, "r", encoding="utf-8", errors="strict") as fh:
            text = fh.read()
    except (UnicodeDecodeError, OSError):
        continue  # binary or unreadable — same exclusion tier (a) gets from git ls-files/grep

    for lineno, raw_line in enumerate(text.splitlines(), start=1):
        norm = normalize(raw_line)
        if not norm:
            continue
        words = norm.split(" ")
        w = len(words)
        for start in range(w):
            for n in range(1, max_words + 1):
                end = start + n
                if end > w:
                    break
                ngram = " ".join(words[start:end])
                if ngram_hash(ngram) in hashes:
                    print(f"LEAK: hash match in {rel}:{lineno} (word-offset {start}, {n}-gram) "
                          "— position only, the matched text is intentionally not printed "
                          "(this environment has no private/.denylist, only its salted hash)",
                          file=sys.stderr)
                    hits += 1

if hits:
    print(f"leak-check: FAIL — {hits} confidential leak(s) (tier b, salted hash). Do NOT commit/bundle.", file=sys.stderr)
    sys.exit(1)
print("leak-check: OK — 0 confidential terms in the canon (tier b, salted hash).")
PYEOF
  exit $?
fi

# --- Tier (c): neither present — no way to check ----------------------------------------
echo "leak-check: WARN denylist absent ($DENYLIST) and no test/denylist.sha256 — skipping (environment without a dossier or committed hash file)." >&2
exit 0
