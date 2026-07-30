#!/usr/bin/env bash
# test/directory-dump-check.sh — refuses a commit that carries a corporate directory dump.
#
# WHY THIS EXISTS, and why leak-check.sh could not have caught it.
#
# On 2026-07-30 a branch of an internal project was found published on GitHub carrying
# `tests/test_crews.py`: 39 corporate addresses and 4 real colleagues' names, harvested by
# an agent that had just run a live org-hierarchy walk and pasted the result in as test
# fixtures. Nobody decided to leak anything. The data was simply the most convenient
# fixture within reach, and a fixture is exactly the kind of file nobody reviews closely.
#
# leak-check.sh could not see it. That check is a DENYLIST: it knows the confidential
# terms someone thought to write down. A colleague's name is not on any list — the whole
# point is that you do not know the names in advance. A denylist answers "is this the
# secret I already named?", and the answer here was correctly no.
#
# So this check asks a different question, about SHAPE rather than vocabulary: does this
# file look like a directory extract? Real people arrive in bulk and they arrive with
# their attributes. One address in a document is a contact. Several distinct addresses in
# one file, or an address sitting next to a job title, is a personnel record — and a
# personnel record in a PUBLIC repository is a different category of mistake.
#
# It reports COUNTS and REDACTED fragments, never the addresses themselves. A guard whose
# failure message pastes the leaked data into CI logs has moved the leak, not stopped it.
#
# Every grep runs under `|| true`. `set -e` plus `pipefail` turns "grep found nothing"
# (exit 1) into an abort, so on a clean repository the unguarded version of this script
# would die instead of passing — a failure mode that reads as green because it never ran.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# How many distinct real-looking addresses in ONE file stop being a contact and start
# being a roster. Three, because a document legitimately naming two people is ordinary and
# a third is already a list. The dump that prompted this carried thirty-nine.
MAX_ADDRESSES="${DIRECTORY_DUMP_MAX_ADDRESSES:-3}"

# Domains that exist in order to be written down. An address here is documentation.
FAKE_DOMAINS='example\.com|example\.org|example\.net|test\.local|localhost|invalid|noreply\.github\.com|users\.noreply\.github\.com|acme\.test'

# THE RATCHET, and why this check would otherwise have been bypassed within a day.
#
# Pointed at the repository that actually leaked, this check flagged six files on its
# first run — synthetic fixtures written long before it existed, plus a configuration file
# that legitimately names three org-hierarchy roots the application walks. A guard that is
# red on arrival blocks honest commits, and a guard that blocks honest commits gets
# disabled; that is not a prediction, it is what happened here on 2026-07-29 when a check
# fired on every clean clone.
#
# So the limit applies to what is NEW. `--baseline` records what each file carries today;
# after that a file may hold what it held and no more, and anything unlisted faces the
# limit. Counts can fall and never rise. Grandfathering is written down in a file someone
# can read and shrink, rather than granted silently by a threshold tuned until it passed.
BASELINE_FILE="${DIRECTORY_DUMP_BASELINE:-.directory-dump-baseline}"

allowed_for() {
  # Echoes the count grandfathered for a path, or empty when it is not listed.
  [ -f "$BASELINE_FILE" ] || return 0
  awk -v p="$1" '$0 !~ /^[[:space:]]*#/ && $2 == p { print $1; exit }' "$BASELINE_FILE" 2>/dev/null || true
}

# Paths this check does not read: its own test, which contains deliberate specimens, and
# private/, whose job is to hold the words nobody may publish.
is_exempt() {
  case "$1" in
    test/test-directory-dump-check.sh|test/directory-dump-check.sh) return 0 ;;
    private/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Show that something matched without republishing it.
redact() { sed -E 's/[A-Za-z0-9._%+-]/*/g; s/\*+/[redatto]/g'; }

if [ "${1:-}" = "--baseline" ]; then
  MODE="baseline"
  FILES=()
  while IFS= read -r line; do FILES+=("$line"); done < <(git ls-files 2>/dev/null || true)
  WHERE="tracked in the repository"
elif [ "${1:-}" = "--staged" ]; then
  MODE="check"
  FILES=()
  while IFS= read -r line; do FILES+=("$line"); done < <(git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)
  WHERE="staged for commit"
else
  MODE="check"
  FILES=()
  while IFS= read -r line; do FILES+=("$line"); done < <(git ls-files 2>/dev/null || true)
  WHERE="tracked in the repository"
fi

failed=0
baseline_rows=""

for f in "${FILES[@]:-}"; do
  [ -n "$f" ] || continue
  [ -f "$f" ] || continue
  is_exempt "$f" && continue
  # Binary files are not read: an image whose bytes happen to spell an address is not a
  # directory dump.
  grep -Iq . "$f" 2>/dev/null || continue

  addresses="$(grep -ohiE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$f" 2>/dev/null \
                | tr '[:upper:]' '[:lower:]' \
                | { grep -vE "@($FAKE_DOMAINS)" 2>/dev/null || true; } \
                | sort -u || true)"
  count="$(printf '%s' "$addresses" | { grep -c . 2>/dev/null || true; })"
  count="${count:-0}"

  # Signal B: an address in a file that also names directory attributes. One personnel
  # record is already a record, so this fires below the bulk threshold.
  attributes="$(grep -ohiE '(jobTitle|job_title|displayName|display_name|officeLocation|employeeId|managerUpn)' "$f" 2>/dev/null | tr '[:upper:]' '[:lower:]' | sort -u || true)"
  attr_count="$(printf '%s' "$attributes" | { grep -c . 2>/dev/null || true; })"
  attr_count="${attr_count:-0}"

  reason=""
  if [ "$count" -ge "$MAX_ADDRESSES" ] 2>/dev/null; then
    reason="$count distinct real-looking addresses (limit $MAX_ADDRESSES)"
  elif [ "$count" -ge 1 ] 2>/dev/null && [ "$attr_count" -ge 2 ] 2>/dev/null; then
    reason="$count address(es) beside $attr_count directory attributes — personnel record shape"
  fi

  [ -n "$reason" ] || continue

  if [ "$MODE" = "baseline" ]; then
    baseline_rows="${baseline_rows}${count} ${f}"$'\n'
    continue
  fi

  # Grandfathered: this file may carry what it already carried, never more.
  allowed="$(allowed_for "$f")"
  if [ -n "$allowed" ] && [ "$count" -le "$allowed" ] 2>/dev/null; then
    continue
  fi
  if [ -n "$allowed" ]; then
    reason="$reason; il baseline ne concedeva $allowed"
  fi

  failed=1
  echo "directory-dump-check: $f — $reason" >&2
  printf '%s\n' "$addresses" | head -3 | redact | sed 's/^/    /' >&2
done

if [ "$MODE" = "baseline" ]; then
  {
    echo "# .directory-dump-baseline — what test/directory-dump-check.sh grandfathers."
    echo "# Written by: directory-dump-check.sh --baseline. Format: <count> <path>."
    echo "# These files already carried addresses when the check arrived. They may keep"
    echo "# that many and no more. Shrinking a number here is always allowed; raising one"
    echo "# is the edit a reviewer should stop, because it means new personal data landed."
    printf '%s' "$baseline_rows" | sort -k2
  } > "$BASELINE_FILE"
  rows="$(printf '%s' "$baseline_rows" | grep -c . 2>/dev/null || true)"
  echo "directory-dump-check: baseline scritto in $BASELINE_FILE (${rows:-0} file congelati)"
  exit 0
fi

if [ "$failed" -ne 0 ]; then
  cat >&2 <<'MSG'

directory-dump-check: BLOCKED — this looks like corporate directory data.

Real people's addresses, names and job titles do not belong in a git history: it is
copied, cloned and mirrored, and it outlives the branch. Test fixtures must be invented,
not harvested — a name you made up proves exactly as much about the code as a name you
took from the org chart.

If a file genuinely needs several addresses and none of them are real, use an example
domain (example.com) — those are ignored here, and they also tell the next reader the
data is fabricated, which this check cannot do on their behalf.
MSG
  exit 1
fi

echo "directory-dump-check: OK (${#FILES[@]} files $WHERE)"
