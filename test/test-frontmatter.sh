#!/usr/bin/env bash
# test-frontmatter.sh — il frontmatter e' il contratto fra un file e chi lo carica. Un agente
# senza `model:`, una skill senza `description:`, una card senza `acceptance:` non falliscono
# rumorosamente: vengono caricati lo stesso e si comportano in modo diverso da come sono scritti.
#
# Quattro famiglie, una per blocco:
#   agenti  — otto chiavi obbligatorie, e `model:` deve essere fra virgolette
#   skill   — nome, descrizione, provider
#   card    — solo todo/ e doing/: done/ e' l'archivio append-only e non si riscrive
#   schema federato — grammatica di runner: e corrispondenza human_gates: <-> human-only
#
# Estratto da test/validate.sh il 2026-07-31 (era la sezione 1). Da qui si lancia anche da solo.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
section() { printf "\n=== %s ===\n" "$1"; }
err() { printf "  FAIL: %s\n" "$1"; FAIL=1; }
ok()  { printf "  ok: %s\n" "$1"; }

section "frontmatter — agents (name, description, model, effort, tools, constraints, version, maturity)"
for a in $(find agents -maxdepth 1 -name '*.md' | LC_ALL=C sort); do
  miss=""
  for k in name description model effort tools constraints version maturity; do
    grep -qE "^$k:" "$a" || miss="$miss $k"
  done
  # model deve essere fra virgolette
  if grep -qE '^model:' "$a" && ! grep -qE '^model:[[:space:]]*"' "$a"; then
    miss="$miss model-not-quoted"
  fi
  [ -n "$miss" ] && err "$a missing:$miss" || ok "$(basename "$a")"
done

section "frontmatter — skills (name, description, providers)"
for s in $(find skills -maxdepth 2 -name 'skill.md' | LC_ALL=C sort); do
  miss=""
  for k in name description providers; do
    grep -qE "^$k:" "$s" || miss="$miss $k"
  done
  [ -n "$miss" ] && err "$s missing:$miss" || ok "$s"
done

section "frontmatter — kanban cards, todo/doing only (title, repo, dod, acceptance, status, created)"
# done/ e' l'archivio di controllo append-only — non si lintano (kanban/README.md): riempire
# `repo:` a posteriori sulle card storiche non serve, il cancello vale sulle card attive.
found=0
for k in kanban/todo kanban/doing; do
  for c in "$k"/*.md; do
    [ -e "$c" ] || continue
    case "$(basename "$c")" in _*) continue ;; esac
    found=1
    miss=""
    for field in title repo dod acceptance status created; do
      grep -qE "^$field:" "$c" || miss="$miss $field"
    done
    [ -n "$miss" ] && err "$c missing:$miss" || ok "$c"
  done
done
[ "$found" -eq 0 ] && printf "  skip: no active todo/doing cards to lint\n"

# lint additivo dello schema federato (grammatica runner: + human_gates: <-> human-only)
section "frontmatter — federated card schema (runner:, human_gates:↔human-only)"
if bash kanban/lint-cards.sh kanban >/dev/null 2>&1; then ok "runner/human_gates schema clean"; else err "runner/human_gates lint — see bash kanban/lint-cards.sh kanban"; fi

[ "$FAIL" -eq 0 ] && { echo; echo "test-frontmatter: PASS"; exit 0; }
echo; echo "test-frontmatter: FAIL"; exit 1
