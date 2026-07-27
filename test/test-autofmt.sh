#!/usr/bin/env bash
# test-autofmt.sh — regression test for hooks/autofmt.sh's input contract and
# its opt-in policy.
#
# Two regressions are pinned here. The hook once read CLAUDE_FILE_PATH (an env
# var the modern hook API never sets) and shipped as a silent no-op, so cases
# 1-4 prove the stdin-JSON contract actually reaches a formatter and that
# degenerate inputs exit 0 without hanging. Then it ran black and ruff in EVERY
# repository, including ones that never declared either: black would have
# rewritten 63 of 87 Python files in one of them, and `ruff --fix` deletes
# unused imports, which is a code change riding inside a commit about something
# else. Cases 5-7 prove formatting is now declared, not imposed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/hooks/autofmt.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# Fake ruff/black record their argv; PATH is prepended so no real formatter runs.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/ruff" <<EOF
#!/usr/bin/env bash
echo "ruff \$@" >> "$TMP/calls.log"
EOF
cat > "$TMP/bin/black" <<EOF
#!/usr/bin/env bash
echo "black \$@" >> "$TMP/calls.log"
EOF
chmod +x "$TMP/bin/ruff" "$TMP/bin/black"

run_hook() {  # $1 = file path
  printf '{"tool_input":{"file_path":"%s"}}' "$1" \
    | PATH="$TMP/bin:$PATH" bash "$HOOK"
}

# A repo that DECLARES both formatters, which is where they are meant to run.
declaring="$TMP/declaring"
mkdir -p "$declaring"
git -C "$declaring" init -q
printf '[tool.black]\nline-length = 88\n\n[tool.ruff]\n' > "$declaring/pyproject.toml"
printf 'x=1\n' > "$declaring/target.py"

# 1. stdin JSON with a real .py file in a declaring repo → formatters called.
run_hook "$declaring/target.py"
grep -q "target.py" "$TMP/calls.log" 2>/dev/null \
  || fail "formatter never received the file from stdin JSON (silent no-op regression)"

# 2. Nonexistent file → exit 0, no formatter call.
: > "$TMP/calls.log"
printf '{"tool_input":{"file_path":"%s/ghost.py"}}' "$declaring" \
  | PATH="$TMP/bin:$PATH" bash "$HOOK" || fail "nonexistent file must exit 0"
[ -s "$TMP/calls.log" ] && fail "formatter called for a nonexistent file"

# 3. Empty/garbage stdin → exit 0 (never blocks the turn).
printf '' | bash "$HOOK" || fail "empty stdin must exit 0"
printf 'not-json' | bash "$HOOK" || fail "garbage stdin must exit 0"

# 4. Legacy fallback: no stdin JSON path but CLAUDE_FILE_PATH set → still formats.
: > "$TMP/calls.log"
printf '{}' | CLAUDE_FILE_PATH="$declaring/target.py" PATH="$TMP/bin:$PATH" bash "$HOOK"
grep -q "target.py" "$TMP/calls.log" 2>/dev/null \
  || fail "legacy CLAUDE_FILE_PATH fallback broken"

# 5. A repo that declared NOTHING is left alone, and the file comes back
#    byte-identical. This is the whole point: an agent editing one line must not
#    receive a reformatted file, or a deleted import, as a side effect.
silent="$TMP/silent"
mkdir -p "$silent"
git -C "$silent" init -q
printf 'import os\nx   =    1\n' > "$silent/target.py"
before="$(shasum "$silent/target.py" | cut -d' ' -f1)"
: > "$TMP/calls.log"
run_hook "$silent/target.py"
[ -s "$TMP/calls.log" ] \
  && fail "a repo that declared no formatter was formatted anyway: $(cat "$TMP/calls.log")"
[ "$(shasum "$silent/target.py" | cut -d' ' -f1)" = "$before" ] \
  || fail "the file was modified in a repo that declared no formatter"

# 6. Declaring one tool does not enrol the other.
ruff_only="$TMP/ruff-only"
mkdir -p "$ruff_only"
git -C "$ruff_only" init -q
: > "$ruff_only/ruff.toml"
printf 'x=1\n' > "$ruff_only/target.py"
: > "$TMP/calls.log"
run_hook "$ruff_only/target.py"
grep -q "^ruff " "$TMP/calls.log" || fail "ruff.toml did not enable ruff"
grep -q "^black " "$TMP/calls.log" && fail "a ruff-only repo must not be black-formatted"

# 7. A pyproject.toml ABOVE the repo root must not opt the repo in behind its
#    back - the walk stops at the repo boundary.
printf '[tool.black]\n[tool.ruff]\n' > "$TMP/pyproject.toml"
: > "$TMP/calls.log"
run_hook "$silent/target.py"
[ -s "$TMP/calls.log" ] \
  && fail "a config outside the repo opted it in: $(cat "$TMP/calls.log")"

echo "PASS: autofmt input contract (stdin JSON + degenerate inputs + legacy fallback + opt-in policy)"
