#!/usr/bin/env bash
# Scan the complete outgoing Git history; a clean result is not publication consent.
set -euo pipefail
die() { printf 'publication-check: BLOCKED - %s\n' "$*" >&2; exit 2; }
[ "$#" -eq 1 ] || die "pass the reviewed base commit/ref as the only argument"
root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not in a Git working tree"
cd "$root"
base="$(git rev-parse --verify --end-of-options "$1^{commit}" 2>/dev/null)" \
  || die "base does not resolve to a commit"
head="$(git rev-parse HEAD)"
git merge-base --is-ancestor "$base" "$head" || die "base is not an ancestor of HEAD"
[ "$base" != "$head" ] || die "empty outgoing range; choose the actual publication base"
if ! git diff --quiet || ! git diff --cached --quiet; then
  die "tracked changes are uncommitted; commit the reviewed publication first"
fi
command -v gitleaks >/dev/null 2>&1 || die "gitleaks unavailable; secrets were NOT checked"
rc=0
gitleaks git --no-banner --redact --ignore-gitleaks-allow --timeout 60 \
  --log-opts="$base..$head" "$root" || rc=$?
if [ "$rc" -ne 0 ]; then
  printf 'publication-check: BLOCKED - gitleaks returned %s; inspect its redacted diagnostic, do not publish.\n' "$rc" >&2
  exit "$rc"
fi
[ "$(git rev-parse HEAD)" = "$head" ] || die "HEAD changed during scanning"
if ! git diff --quiet || ! git diff --cached --quiet; then
  die "tracked files changed during scanning"
fi
printf 'publication-check: scanned %s..%s; no detected secrets. This is NOT disclosure or publication authorization.\n' "$base" "$head"
