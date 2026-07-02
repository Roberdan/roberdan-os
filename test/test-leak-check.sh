#!/usr/bin/env bash
# test/test-leak-check.sh — proves tier (b) of test/leak-check.sh (the salted-hash check)
# actually catches a planted leak, fully isolated via RDA_DENYLIST_SRC/RDA_DENYLIST_OUT/
# RDA_DENYLIST_HASHFILE (see bin/update-denylist-hashes.sh and test/leak-check.sh). Does not
# touch a real private/ — builds a temp fake denylist, hashes it with the real generator
# script, then scans temp scratch files with the real leak-check.sh.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
section() { printf "\n=== %s ===\n" "$1"; }
ok()      { printf "  ok: %s\n" "$1"; }
err()     { printf "  FAIL: %s\n" "$1"; FAIL=1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/private" "$TMP/scratch"
DENY="$TMP/private/.denylist"
HASHFILE="$TMP/denylist.sha256"

# A distinctive, never-realistically-collides phrase — planted only in temp scratch files.
# Built from separate parts at runtime (never written contiguously in THIS script's own
# source) so leak-check.sh's real-corpus scan (it scans every tracked file under the repo,
# including this test file) never flags test-leak-check.sh itself as the planted leak.
p1="ZzzPlantedLeakTestPhrase123"; p2="Foobar"; p3="Quux"; p4="Corp"
phrase="$p1 $p2 $p3 $p4"
printf '# test-only denylist\n%s\n' "$phrase" > "$DENY"

section "bin/update-denylist-hashes.sh: refuses to run without private/.denylist"
if RDA_DENYLIST_SRC="$TMP/does-not-exist/.denylist" RDA_DENYLIST_OUT="$TMP/should-not-appear.sha256" \
  bash bin/update-denylist-hashes.sh >/dev/null 2>&1; then
  err "update-denylist-hashes.sh ran without a private/.denylist (should refuse)"
else
  ok "update-denylist-hashes.sh refused to run without private/.denylist"
fi
[ -e "$TMP/should-not-appear.sha256" ] \
  && err "update-denylist-hashes.sh wrote an output file despite refusing" \
  || ok "no output file written on refusal"

section "bin/update-denylist-hashes.sh: generates a salted hash file from a fake denylist"
if RDA_DENYLIST_SRC="$DENY" RDA_DENYLIST_OUT="$HASHFILE" bash bin/update-denylist-hashes.sh >/dev/null 2>&1 \
  && [ -f "$HASHFILE" ] && grep -q '^# salt:' "$HASHFILE" && grep -q '^# max-words:' "$HASHFILE"; then
  ok "hash file generated with a salt + max-words header"
else
  err "bin/update-denylist-hashes.sh did not produce a well-formed hash file"
fi
if grep -q "$p1" "$HASHFILE" 2>/dev/null; then
  err "the plaintext denylist phrase leaked into the committable hash file"
else
  ok "the plaintext denylist phrase does not appear in the hash file (only its hash does)"
fi

section "test/leak-check.sh tier (b): catches a planted leak via the salted hash, no private/"
printf 'This line mentions %s by accident.\n' "$phrase" > "$TMP/scratch/leaky.md"
out="$(RDA_DENYLIST_SRC="$TMP/nonexistent/.denylist" RDA_DENYLIST_HASHFILE="$HASHFILE" \
  bash test/leak-check.sh "$TMP/scratch/leaky.md" 2>&1)"
rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'tier b, salted hash'; then
  ok "planted leak caught by tier (b) (exit $rc)"
else
  err "tier (b) did not catch the planted leak (rc=$rc): $out"
fi
if printf '%s' "$out" | grep -q "$p1"; then
  err "tier (b) printed the actual leaked text — it must report position only, never the match"
else
  ok "tier (b)'s report never prints the matched text, only file/line/word-offset"
fi

section "test/leak-check.sh tier (b): a clean file with no planted phrase passes"
cat > "$TMP/scratch/clean.md" <<'EOF'
Nothing sensitive here, just ordinary unrelated words in a row.
EOF
if RDA_DENYLIST_SRC="$TMP/nonexistent/.denylist" RDA_DENYLIST_HASHFILE="$HASHFILE" \
  bash test/leak-check.sh "$TMP/scratch/clean.md" >/dev/null 2>&1; then
  ok "a clean scratch file with no planted phrase passes tier (b)"
else
  err "tier (b) false-positived on a clean scratch file"
fi

section "test/leak-check.sh: falls back to tier (c) no-op when neither file is present"
if out3="$(RDA_DENYLIST_SRC="$TMP/nonexistent/.denylist" RDA_DENYLIST_HASHFILE="$TMP/nonexistent.sha256" \
  bash test/leak-check.sh "$TMP/scratch/leaky.md" 2>&1)"; then
  printf '%s' "$out3" | grep -qi 'WARN' \
    && ok "no denylist and no hash file -> tier (c) no-op warning, exit 0" \
    || err "tier (c) exited 0 but without the expected WARN message"
else
  err "tier (c) (neither file present) should degrade to a no-op, not fail"
fi

# ---------------------------------------------------------------------------
printf "\n"
if [ "$FAIL" -eq 0 ]; then echo "test-leak-check: ✅ ALL GREEN"; exit 0; else echo "test-leak-check: ❌ FAIL (see above)"; exit 1; fi
