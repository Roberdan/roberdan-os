#!/usr/bin/env bash
# fork-identity.sh — rewrite Roberto-specific identity markers for your own fork.
#
# Renames the identity-bound files/tokens (roberdan-twin agent, roberto-voice.md,
# RDA_ env prefix, ~/.roberdan-os home dir) to your own name across the LIVE canon
# (behavior/, rules/, agents/, skills/, hooks/, bin/, factory/, learn/, evolve/,
# ontology/, kanban/, memory/, loop/, test/, eval/*.sh, AGENTS.md, README.md,
# START-HERE.md, docs/USAGE.md, docs/adr/, .github/).
#
# Deliberately OUT of automated scope (mechanical rename would corrupt them):
#   - docs/archive/, docs/plan*.md, docs/report-*.md, docs/roberdan-os-paper-en.md(.pdf)
#     — dated historical record / the paper's own narrative, not live config.
#   - eval/tasks/*.md, eval/README.md prose — fixture content, renaming mid-fixture
#     changes what's being measured, not just cosmetics.
#   - claude-ai-skill/roberto-mode/ — a packaged, named artifact (dir name + zip);
#     review and rename by hand if you want to ship your own version.
# These are printed as a manual-review checklist at the end, never touched.
#
# Dry-run by default — prints the plan, writes nothing. Pass --apply to execute.
#
#   bin/fork-identity.sh --slug jane [--name "Jane Doe"] [--apply] [--force]
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
  echo "usage: bin/fork-identity.sh --slug <lowercase-slug> [--name \"Full Name\"] [--apply] [--force]" >&2
  exit 1
fi
case "$SLUG" in
  *[!a-z0-9-]*|"") echo "error: --slug must be lowercase letters/digits/hyphens (got: $SLUG)" >&2; exit 1 ;;
esac
SLUG_UPPER="$(printf '%s' "$SLUG" | tr '[:lower:]-' '[:upper:]_')"

# Safety rail: refuse to mutate the real roberdan-os repo unless explicitly forced.
origin_url="$(git remote get-url origin 2>/dev/null || true)"
if [ -n "$APPLY" ] && printf '%s' "$origin_url" | grep -qi "Roberdan/roberdan-os" && [ -z "$FORCE" ]; then
  echo "refusing --apply: origin is Roberdan/roberdan-os itself. Pass --force if you really mean it" \
       "(you almost certainly don't — this is meant to run on YOUR fork)." >&2
  exit 1
fi

# Explicit include scope — live canon only, see header comment for what's excluded and why.
SCOPE=(
  agents behavior rules skills hooks bin factory learn evolve ontology kanban memory loop test
  AGENTS.md README.md START-HERE.md CHANGELOG.md docs/USAGE.md docs/adr .github
)
# eval/*.sh (functional scripts) yes, eval/tasks/*.md and eval/README.md (fixture prose) no.
EVAL_SCRIPTS=(eval/run-eval.sh eval/judge.sh eval/report.sh eval/test-eval-pipeline.sh eval/lib.sh)

collect_files() {
  local f
  for f in "${SCOPE[@]}"; do
    [ -e "$f" ] || continue
    if [ -d "$f" ]; then
      git ls-files -- "$f"
    else
      printf '%s\n' "$f"
    fi
  done
  for f in "${EVAL_SCRIPTS[@]}"; do
    [ -f "$f" ] && printf '%s\n' "$f"
  done
}

mapfile_files=()
while IFS= read -r f; do
  [ -n "$f" ] && mapfile_files+=("$f")
done < <(collect_files | sort -u)

echo "== fork-identity: $([ -n "$APPLY" ] && echo APPLY || echo DRY-RUN) — slug='$SLUG' name='${NAME:-<not given>}' =="
echo "Scope: ${#mapfile_files[@]} files across ${SCOPE[*]}"
echo ""

# --- Rename 1: agents/roberdan-twin.md -> agents/<slug>-twin.md ------------------------
NEW_TWIN="agents/${SLUG}-twin.md"
if [ -f agents/roberdan-twin.md ]; then
  echo "rename: agents/roberdan-twin.md -> $NEW_TWIN"
  if [ -n "$APPLY" ]; then git mv agents/roberdan-twin.md "$NEW_TWIN"; fi
else
  echo "skip (already renamed?): agents/roberdan-twin.md not found"
fi

# --- Rename 2: behavior/roberto-voice.md -> behavior/<slug>-voice.md -------------------
NEW_VOICE="behavior/${SLUG}-voice.md"
ORIG_VOICE_NAME="roberto-voice.md"  # captured before renaming/replacing, for the banner below
if [ -f behavior/roberto-voice.md ]; then
  echo "rename: behavior/roberto-voice.md -> $NEW_VOICE (content kept as-is + a banner — rewrite the actual voice yourself)"
  if [ -n "$APPLY" ]; then git mv behavior/roberto-voice.md "$NEW_VOICE"; fi
else
  echo "skip (already renamed?): behavior/roberto-voice.md not found"
fi
echo ""

# --- Text substitutions across scope (word-boundary safe, portable sed — no -i) --------
replace_in_file() {
  local f="$1" tmp
  [ -f "$f" ] || return 0
  tmp="$(mktemp "${TMPDIR:-/tmp}/fork-identity.XXXXXX")"
  sed -e "s/roberdan-twin/${SLUG}-twin/g" \
      -e "s/roberto-voice/${SLUG}-voice/g" \
      -e "s/RDA_/${SLUG_UPPER}_/g" \
      -e "s/\.roberdan-os/.${SLUG}-os/g" \
      "$f" > "$tmp"
  if ! cmp -s "$tmp" "$f"; then
    if [ -n "$APPLY" ]; then mv "$tmp" "$f"; else rm -f "$tmp"; fi
    return 0
  fi
  rm -f "$tmp"
  return 1
}

changed=0
for f in "${mapfile_files[@]}"; do
  # Skip the two files we just renamed under their NEW path (already git mv'd above).
  case "$f" in agents/roberdan-twin.md|behavior/roberto-voice.md) continue ;; esac
  if replace_in_file "$f"; then
    changed=$((changed + 1))
    [ -n "$APPLY" ] && echo "  updated: $f" || echo "  would update: $f"
  fi
done
[ -f "$NEW_TWIN" ] && { replace_in_file "$NEW_TWIN" && { changed=$((changed+1)); [ -n "$APPLY" ] && echo "  updated: $NEW_TWIN"; } || true; }
[ -f "$NEW_VOICE" ] && { replace_in_file "$NEW_VOICE" && { changed=$((changed+1)); [ -n "$APPLY" ] && echo "  updated: $NEW_VOICE"; } || true; }

# Banner added LAST, after all sed passes, so its own reference to the original filename
# (which the substitutions above would otherwise rewrite too) survives intact.
if [ -n "$APPLY" ] && [ -f "$NEW_VOICE" ]; then
  tmp="$(mktemp "${TMPDIR:-/tmp}/fork-identity.XXXXXX")"
  {
    echo "<!-- FORK TODO: this file still has Roberto's voice, copied verbatim from ${ORIG_VOICE_NAME}."
    echo "     Rewrite it in your own voice before relying on it — see docs/QUICKSTART-for-forkers.md. -->"
    echo ""
    cat "$NEW_VOICE"
  } > "$tmp" && mv "$tmp" "$NEW_VOICE"
fi

echo ""
echo "$changed file(s) $([ -n "$APPLY" ] && echo "updated" || echo "would be updated")."
echo ""

# --- Manual-review report: things this script deliberately does NOT touch -------------
echo "== Manual review still needed (not automated — needs your judgment, not sed) =="
echo ""
echo "1) Narrative mentions of \"Roberto\" in prose (rewrite the sentence, not just the name):"
git grep -ciw "Roberto" -- "${SCOPE[@]}" 2>/dev/null | awk -F: '$2>0' | sed 's/^/   /'
echo ""
echo "2) Out-of-scope directories/files this script never touches — review by hand:"
echo "   - docs/archive/, docs/plan*.md, docs/report-*.md, docs/roberdan-os-paper-en.md(.pdf)"
echo "     (dated historical record — most forks just delete these rather than rename)"
echo "   - eval/tasks/*.md, eval/README.md (fixture prose, not identity)"
echo "   - claude-ai-skill/roberto-mode/ (packaged skill dir name + its .zip build artifact)"
echo ""
echo "3) Still to do yourself, not scriptable:"
echo "   - Rename the GitHub repo itself and your local clone directory."
echo "   - Rewrite $NEW_VOICE in your own voice (banner marks it if you just --apply'd)."
echo "   - Write your own private/.denylist and ~/.${SLUG}-os/private/profile.md — Roberto's"
echo "     denylist is meaningless to you and yours doesn't exist yet (see README.md § Privacy)."
echo ""
[ -z "$APPLY" ] && echo "This was a DRY RUN — nothing was written. Re-run with --apply to execute."
