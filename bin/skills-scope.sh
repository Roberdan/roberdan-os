#!/usr/bin/env bash
# skills-scope.sh — keep the per-session skill preamble small.
#
# WHY: every installed skill costs its `description:` line in the system prompt of EVERY
# session, in every tool. 75 skills ~= 13k characters (~3k tokens) burned before the first
# question is read. This script parks the ones telemetry says were never invoked, and moves
# repo-specific ones INTO their repo — where both Claude Code and Copilot CLI read
# `<repo>/.claude/skills/`, so one location serves both clients.
#
# Reversible by construction: nothing is deleted, only moved to `<skills-dir>/../skills-off/`.
# Idempotent: safe to re-run after `gstack-upgrade` reinstalls the parked skills.
#
#   bin/skills-scope.sh          apply
#   bin/skills-scope.sh --dry    show what would move
#   bin/skills-scope.sh --restore  put everything back under the global skill dirs
set -euo pipefail

HOME_DIR="${HOME}"
SKILL_ROOTS=("${HOME_DIR}/.claude/skills" "${HOME_DIR}/.copilot/skills")

# Never invoked in any recorded session, and not repo-specific: park them.
PARK=(
  gstack-autoplan gstack-benchmark gstack-benchmark-models gstack-canary
  gstack-codex gstack-devex-review gstack-diagram gstack-document-release
  gstack-landing-report gstack-open-gstack-browser gstack-pair-agent
  gstack-plan-ceo-review gstack-plan-design-review gstack-plan-devex-review
  gstack-plan-tune gstack-qa-only gstack-retro gstack-setup-browser-cookies
  gstack-setup-deploy gstack-skillify gstack-connect-chrome resource-export
)

# Repo-specific: they only make sense inside these repos, so that is where they live.
# Format: "<skill-name>:<repo1>,<repo2>"
SCOPED=(
  "gstack-ios-clean:MirrorBuddy,MirrorScopio"
  "gstack-ios-design-review:MirrorBuddy,MirrorScopio"
  "gstack-ios-fix:MirrorBuddy,MirrorScopio"
  "gstack-ios-qa:MirrorBuddy,MirrorScopio"
  "gstack-ios-sync:MirrorBuddy,MirrorScopio"
)

MODE="apply"
case "${1:-}" in
  --dry|--dry-run) MODE="dry" ;;
  --restore) MODE="restore" ;;
  "") ;;
  *) echo "usage: $0 [--dry|--restore]" >&2; exit 64 ;;
esac

say() { printf '%s\n' "$*"; }
moved=0

if [[ "$MODE" == "restore" ]]; then
  for root in "${SKILL_ROOTS[@]}"; do
    off="$(dirname "$root")/skills-off"
    [[ -d "$off" ]] || continue
    for d in "$off"/*/; do
      [[ -d "$d" ]] || continue
      name="$(basename "$d")"
      [[ -e "$root/$name" ]] && { say "skip (already present): $root/$name"; continue; }
      mv "$d" "$root/$name"; say "restored: $root/$name"; moved=$((moved+1))
    done
  done
  say "restored $moved skill(s)."
  exit 0
fi

# 1. Park the never-used ones.
for root in "${SKILL_ROOTS[@]}"; do
  [[ -d "$root" ]] || continue
  off="$(dirname "$root")/skills-off"
  for name in "${PARK[@]}"; do
    src="$root/$name"
    [[ -d "$src" ]] || continue
    if [[ "$MODE" == "dry" ]]; then say "would park: $src -> $off/$name"; moved=$((moved+1)); continue; fi
    mkdir -p "$off"
    # A previous park left a copy: the global one is the stale duplicate, drop it.
    if [[ -e "$off/$name" ]]; then rm -rf "$src"; else mv "$src" "$off/$name"; fi
    say "parked: $name"; moved=$((moved+1))
  done
done

# 2. Move repo-specific skills into each repo's .claude/skills (read by Claude AND Copilot).
for entry in "${SCOPED[@]}"; do
  name="${entry%%:*}"; repos="${entry#*:}"
  for root in "${SKILL_ROOTS[@]}"; do
    src="$root/$name"
    [[ -d "$src" ]] || continue
    IFS=',' read -r -a repo_list <<< "$repos"
    placed=0
    for repo in "${repo_list[@]}"; do
      dest_dir="${HOME_DIR}/GitHub/${repo}/.claude/skills"
      [[ -d "${HOME_DIR}/GitHub/${repo}" ]] || continue
      if [[ "$MODE" == "dry" ]]; then say "would scope: $name -> $dest_dir/$name"; placed=1; continue; fi
      mkdir -p "$dest_dir"
      [[ -e "$dest_dir/$name" ]] || cp -R "$src" "$dest_dir/$name"
      say "scoped: $name -> $repo"
      placed=1
    done
    # Only drop the global copy once it actually lives somewhere else.
    if [[ "$placed" == 1 && "$MODE" != "dry" ]]; then rm -rf "$src"; fi
    [[ "$placed" == 1 ]] && moved=$((moved+1))
  done
done

if [[ "$MODE" == "dry" ]]; then
  say "-- dry run: $moved skill(s) would move. Nothing changed."
else
  for root in "${SKILL_ROOTS[@]}"; do
    # Count entries, not `-type d`: some skills are installed as symlinks.
    [[ -d "$root" ]] && say "$root now has $(ls -1 "$root" | wc -l | tr -d ' ') skills"
  done
  say "-- done: $moved skill(s) moved. Undo with: $0 --restore"
fi
