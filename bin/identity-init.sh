#!/usr/bin/env bash
# identity-init.sh — set up YOUR identity in a fork of roberdan-os. Replaces the
# removed fork-identity.sh (v1.3.0): that script's git mv + sed rename model is
# exactly what manufactured perpetual merge conflicts with upstream. This one
# **renames NO engine file** — it only scaffolds the forker-owned identity/ surface:
#
#   - rewrites identity/identity.conf with your slug/name/home,
#   - marks each identity/*.md prose file with a FORK TODO banner (the reference
#     content is kept for you to overwrite — it is still Roberto's until you do),
#   - prints the manual checklist (RDA_HOME, denylist, voice rewrite).
#
# Everything a fork must change lives in identity/ (see identity/README.md); engine
# files stay upstream-owned, so `git merge upstream/main` stays conflict-free on them.
#
# Dry-run by default — prints the plan, writes nothing. Pass --apply to execute.
#
#   bin/identity-init.sh --slug jane [--name "Jane Doe"] [--apply] [--force]
#
# --force is required to --apply against the Roberdan/roberdan-os origin itself
# (a safety rail so this can't be run by accident against the real repo).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SLUG=""
NAME=""
APPLY=""
FORCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --slug) SLUG="${2:-}"; shift 2 ;;
    --name) NAME="${2:-}"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    --force) FORCE=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$SLUG" ]; then
  echo "usage: bin/identity-init.sh --slug <lowercase-slug> [--name \"Full Name\"] [--apply] [--force]" >&2
  exit 1
fi
case "$SLUG" in
  *[!a-z0-9-]*|"") echo "error: --slug must be lowercase letters/digits/hyphens (got: $SLUG)" >&2; exit 1 ;;
esac

# Safety rail: refuse to mutate the real roberdan-os repo unless explicitly forced.
origin_url="$(git remote get-url origin 2>/dev/null || true)"
if [ -n "$APPLY" ] && printf '%s' "$origin_url" | grep -qi "Roberdan/roberdan-os" && [ -z "$FORCE" ]; then
  echo "refusing --apply: origin is Roberdan/roberdan-os itself. Pass --force if you really mean it" \
       "(you almost certainly don't — this is meant to run on YOUR fork)." >&2
  exit 1
fi

DISPLAY_NAME="${NAME:-[Your Name]}"
NEW_HOME="\$HOME/.${SLUG}-os"

echo "== identity-init: $([ -n "$APPLY" ] && echo APPLY || echo DRY-RUN) — slug='$SLUG' name='${NAME:-<not given>}' =="
echo "Scope: identity/ ONLY. No engine file is renamed or edited — that is the point."
echo ""

# --- 1) identity.conf from template -----------------------------------------------------
echo "write: identity/identity.conf (slug=$SLUG, full_name=$DISPLAY_NAME, rda_home=$NEW_HOME)"
if [ -n "$APPLY" ]; then
  cat > identity/identity.conf <<EOF
# identity.conf — machine-readable identity (bash-sourceable KEY=value, no spaces).
# Consumed by scripts (\`source\`) and by bin/sync.sh at generation time.
# Scaffolded by bin/identity-init.sh — review every value.
slug=$SLUG
full_name="$DISPLAY_NAME"
primary_language=en
twin_handle=twin
rda_home="$NEW_HOME"
EOF
fi

# --- 2) FORK TODO banner on each identity prose file ------------------------------------
# The reference content (Roberto's) is kept for you to overwrite — the banner marks it
# loudly until you do. Idempotent: a file already bannered is skipped.
banner_file() {
  local f="$1" tmp
  [ -f "$f" ] || { echo "skip: $f not found"; return 0; }
  if grep -q "FORK TODO" "$f"; then
    echo "skip: $f already has a FORK TODO banner"
    return 0
  fi
  echo "banner: $f (content kept as reference — rewrite it as your own)"
  if [ -n "$APPLY" ]; then
    tmp="$(mktemp "${TMPDIR:-/tmp}/identity-init.XXXXXX")"
    {
      echo "<!-- FORK TODO: this file still describes the upstream operator (Roberto D'Angelo),"
      echo "     kept as a reference. Rewrite it as YOUR identity before relying on it —"
      echo "     see docs/QUICKSTART-for-forkers.md. -->"
      echo ""
      cat "$f"
    } > "$tmp" && mv "$tmp" "$f"
  fi
}
banner_file identity/voice.md
banner_file identity/operator.md
banner_file identity/twin-persona.md
banner_file identity/profile-pointer.md

echo ""
echo "== Checklist (manual, not scriptable) =="
echo ""
echo "1) Runtime home: add to your shell profile (a VALUE, not a file edit):"
echo "     export RDA_HOME=~/.${SLUG}-os"
echo "   (default stays ~/.roberdan-os if unset; the RDA_ prefix is the engine's fixed"
echo "    namespace — intentionally NOT yours to rename, see identity/README.md)"
echo ""
echo "2) Rewrite the identity/ prose in your own words (the banners mark what's still"
echo "   the upstream operator's): voice.md, operator.md, twin-persona.md,"
echo "   profile-pointer.md. identity/ is the ONLY directory you should ever edit."
echo ""
echo "3) Privacy: write your own denylist + dossier —"
echo "     private/.denylist                     (gitignored, local-only)"
echo "     ~/.${SLUG}-os/private/<your-profile>.md  (read by @twin at runtime)"
echo "   then run bin/update-denylist-hashes.sh and commit test/denylist.sha256 so CI"
echo "   can leak-check without holding your terms in plaintext."
echo ""
echo "4) Verify: bash test/validate.sh  →  must be ALL GREEN."
echo ""
echo "5) Stay merged with upstream: git remote add upstream <roberdan-os-url>;"
echo "   'git merge upstream/main' stays clean on engine files because you only ever"
echo "   edited identity/ (see test/test-fork-merge.sh for the proof)."
echo ""
[ -z "$APPLY" ] && echo "This was a DRY RUN — nothing was written. Re-run with --apply to execute."
exit 0
