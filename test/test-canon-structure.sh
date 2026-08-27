#!/usr/bin/env bash
# test-canon-structure.sh — i cancelli umani sono numerati senza buchi e ogni puntatore ne dichiara il numero giusto
#
# Estratto da test/validate.sh il 2026-07-31. Da qui si lancia anche da solo:
#   bash test/test-canon-structure.sh
# che prima non si poteva: bisognava aspettare l'intera suite per leggere queste righe.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
section() { printf "\n=== %s ===\n" "$1"; }
err() { printf "  FAIL: %s\n" "$1"; FAIL=1; }
ok()  { printf "  ok: %s\n" "$1"; }

# --- 1e) canon structure — AGENTS.md § Human gates (mechanical invariant, @rex #4) -------
section "canon structure — root AGENTS.md § Human gates, and every pointer that counts them"
# The gate list grows. A hardcoded expected count here, and a hardcoded "7-item
# list" in the pointer, are two hand-written numbers that must agree with a third
# thing that moves — and hand-written numbers that must agree is the exact class
# this suite exists to refuse. It bit immediately: adding human gate #8 turned
# validate.sh red on a card that had not touched a gate.
# So nothing is hardcoded. The invariant is DERIVED: the gates are numbered
# 1..N with no gaps, and any pointer that states a count states THIS N.
if [ -s AGENTS.md ]; then
  gates_body="$(awk '/^## Human gates/{f=1;next} /^## /{if(f)exit} f' AGENTS.md)"
  gates_count=$(printf '%s\n' "$gates_body" | grep -cE '^[0-9]+\. ')
  gates_seq=$(printf '%s\n' "$gates_body" | grep -oE '^[0-9]+' | paste -sd, -)
  expected_seq=$(awk -v n="$gates_count" 'BEGIN{for(i=1;i<=n;i++){printf "%s%d", (i>1?",":""), i}}')
  if [ "$gates_count" -ge 1 ] && [ "$gates_seq" = "$expected_seq" ]; then
    ok "AGENTS.md § Human gates has $gates_count sequentially-numbered gates (1..$gates_count)"
  else
    err "AGENTS.md § Human gates is not a contiguous list: $gates_count gate(s), sequence ${gates_seq:-none}, expected ${expected_seq:-1..N} — a gap or a duplicate means one gate is unreachable by number"
  fi
  # Every pointer that promises "the full N-item list lives there" must promise
  # the right N, or it is a stale instruction to a reader who cannot see this file.
  for ptr in .github/copilot-instructions.md CLAUDE.md ~/.codex/AGENTS.md; do
    [ -f "$ptr" ] || continue
    claimed="$(grep -oE '[0-9]+-item list is `?AGENTS.md`? § Human gates' "$ptr" 2>/dev/null | grep -oE '^[0-9]+' | head -1)"
    [ -n "$claimed" ] || continue
    if [ "$claimed" = "$gates_count" ]; then
      ok "$ptr promises $claimed gates, and AGENTS.md has $gates_count"
    else
      err "$ptr promises a $claimed-item gate list but AGENTS.md § Human gates now has $gates_count — the pointer is lying to whoever only reads $ptr"
    fi
  done
else
  err "root AGENTS.md missing or empty — every pointer (.github/copilot-instructions.md, CLAUDE.md, ~/.codex/AGENTS.md) depends on it"
fi

# --- executive response format — one wording, carried by every surface --------------------
# The format lives, hand-maintained, in four places (no one generated from another):
# behavior/roberto-mode.md (source), AGENTS.md (the gate line), .github/copilot-instructions.md
# (the Copilot block), and the bin/sync.sh heredoc that generates the Copilot user file.
# @rex flagged the drift risk: reword one, the others go stale silently. Anchor phrases that
# define the format must appear in all four — reword the format and this goes red until every
# copy is updated together.
section "executive response format — all four surfaces carry the same anchor phrases"
for f in behavior/roberto-mode.md AGENTS.md .github/copilot-instructions.md bin/sync.sh; do
  if [ ! -f "$f" ]; then err "$f missing — it must carry the executive response format"; continue; fi
  # Flatten whitespace first: the anchor phrases wrap across lines in the prose copies.
  flat="$(tr -s '[:space:]' ' ' < "$f" | tr 'A-Z' 'a-z')"
  missing=""
  case "$flat" in *"verified / not verified"*) : ;; *) missing="${missing} 'verified / not verified'" ;; esac
  case "$flat" in *"unexplained jargon"*) : ;; *) missing="${missing} 'unexplained jargon'" ;; esac
  case "$flat" in *"executive"*) : ;; *) missing="${missing} 'executive'" ;; esac
  if [ -n "$missing" ]; then
    err "$f is missing executive-format anchor(s):${missing} — a reword drifted one copy"
  else
    ok "$f carries the executive-format anchors"
  fi
done

[ "$FAIL" -eq 0 ] && { echo; echo "test-canon-structure: PASS"; exit 0; }
echo; echo "test-canon-structure: FAIL"; exit 1
