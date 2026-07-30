#!/usr/bin/env bash
# test/test-directory-dump-check.sh — proves directory-dump-check.sh can go RED.
#
# This exists because of two mistakes made on 2026-07-29, one after the other, both in
# tests written to pin a new guard. The first grepped for a string the stale artefact also
# contained, so it passed against the very thing it was meant to reject. The second cloned
# the repository, which reads the COMMITTED state, so it never saw the working-tree change
# it was written to check. Both went green immediately, and green was the bug.
#
# So every case here builds a throwaway git repository, puts a specimen in it, and asserts
# the DIRECTION of the verdict — including the cases that must be accepted. A check that
# only ever says no is not a check, it is an outage.
#
# The specimens are invented. Using a real dump to test the anti-dump guard would commit
# the thing the guard exists to prevent, which is not irony, it is the same leak.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/directory-dump-check.sh"
pass=0; fail=0

lab() {
  local d; d="$(mktemp -d)"
  git -C "$d" init -q
  git -C "$d" config user.email a@example.com
  git -C "$d" config user.name t
  printf '%s' "$d"
}

# run_case <name> <expect: reject|accept> <filename> <content>
run_case() {
  local name="$1" expect="$2" fname="$3" content="$4"
  local d; d="$(lab)"
  mkdir -p "$d/$(dirname "$fname")" 2>/dev/null || true
  printf '%s\n' "$content" > "$d/$fname"
  git -C "$d" add -A >/dev/null 2>&1
  local out rc
  out="$(cd "$d" && bash "$CHECK" --staged 2>&1)"; rc=$?
  local verdict="accept"; [ "$rc" -ne 0 ] && verdict="reject"
  if [ "$verdict" = "$expect" ]; then
    echo "  PASS  $name (atteso $expect)"; pass=$((pass+1))
  else
    echo "  FAIL  $name — atteso $expect, ottenuto $verdict"; echo "$out" | sed 's/^/        /'
    fail=$((fail+1))
  fi
  # The failure message must not republish what it found. If the guard ever prints a
  # whole address, the leak has moved into CI logs instead of stopping.
  if [ "$verdict" = "reject" ] && printf '%s' "$out" | grep -qE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'; then
    echo "  FAIL  $name — il messaggio di errore contiene un indirizzo in chiaro"; fail=$((fail+1))
  fi
  rm -rf "$d"
}

echo "directory-dump-check:"

run_case "un solo contatto in un doc passa" accept "README.md" \
  "Scrivi a mario.rossi@contoso.com per accessi."

run_case "tre indirizzi reali in un file = roster" reject "tests/test_x.py" \
  "USERS = ['a.uno@contoso.com', 'b.due@contoso.com', 'c.tre@contoso.com']"

run_case "gli stessi tre su dominio example passano" accept "tests/test_x.py" \
  "USERS = ['a.uno@example.com', 'b.due@example.com', 'c.tre@example.com']"

run_case "un indirizzo + attributi di rubrica = scheda personale" reject "tests/fixture.json" \
  '{"displayName": "Tal Dei Tali", "jobTitle": "Principal PM", "upn": "tal@contoso.com"}'

run_case "un repo senza indirizzi passa" accept "src/app.py" \
  "def main(): return 42"

run_case "lo stesso indirizzo ripetuto non e' un roster" accept "docs/g.md" \
  "scrivi a x@contoso.com, ancora x@contoso.com, sempre x@contoso.com"

run_case "co-author trailer di git non conta" accept "docs/h.md" \
  "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"

# --- the ratchet -------------------------------------------------------------------
# The three cases that decide whether grandfathering is a control or a hole: what was
# already there is tolerated, one more is not, and a brand new file is judged on its own.
ratchet() {
  local d; d="$(lab)"
  mkdir -p "$d/tests"
  printf 'U = ["a@contoso.com","b@contoso.com","c@contoso.com","d@contoso.com"]\n' > "$d/tests/old.py"
  git -C "$d" add -A >/dev/null 2>&1
  ( cd "$d" && bash "$CHECK" --baseline >/dev/null 2>&1 )

  local out rc
  # 1. unchanged, grandfathered file
  git -C "$d" add -A >/dev/null 2>&1
  out="$(cd "$d" && bash "$CHECK" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then echo "  PASS  il baseline grazia il file preesistente"; pass=$((pass+1));
  else echo "  FAIL  il baseline non grazia il preesistente"; echo "$out" | sed 's/^/        /'; fail=$((fail+1)); fi

  # 2. one more address in the SAME file must fail
  printf 'MORE = "e@contoso.com"\n' >> "$d/tests/old.py"
  git -C "$d" add -A >/dev/null 2>&1
  out="$(cd "$d" && bash "$CHECK" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then echo "  PASS  un indirizzo IN PIU' sul file graziato fa scattare"; pass=$((pass+1));
  else echo "  FAIL  il cricchetto non scatta: si puo' aggiungere PII a un file graziato"; fail=$((fail+1)); fi

  # 3. a new file is judged on its own, baseline or not
  git -C "$d" checkout -- tests/old.py 2>/dev/null || printf 'U = ["a@contoso.com","b@contoso.com","c@contoso.com","d@contoso.com"]\n' > "$d/tests/old.py"
  printf 'NEW = ["x@contoso.com","y@contoso.com","z@contoso.com"]\n' > "$d/tests/new.py"
  git -C "$d" add -A >/dev/null 2>&1
  out="$(cd "$d" && bash "$CHECK" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then echo "  PASS  un file NUOVO non e' coperto dal baseline"; pass=$((pass+1));
  else echo "  FAIL  un file nuovo passa grazie al baseline di un altro"; fail=$((fail+1)); fi

  rm -rf "$d"
}
ratchet

echo "  ---- $pass passati, $fail falliti"
[ "$fail" -eq 0 ]