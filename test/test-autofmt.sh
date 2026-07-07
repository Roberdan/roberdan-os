#!/usr/bin/env bash
# test-autofmt.sh — regression test for hooks/autofmt.sh's input contract.
# The hook once read CLAUDE_FILE_PATH (an env var the modern hook API never sets)
# and shipped as a silent no-op. This proves the stdin-JSON contract actually
# reaches a formatter, and that degenerate inputs exit 0 without hanging.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/hooks/autofmt.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# 1. stdin JSON with a real .py file → the formatter on PATH gets called with that file.
#    Fake ruff/black record their argv; PATH is prepended so no real formatter runs.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/ruff" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$TMP/calls.log"
EOF
cp "$TMP/bin/ruff" "$TMP/bin/black"
chmod +x "$TMP/bin/ruff" "$TMP/bin/black"
printf 'x=1\n' > "$TMP/target.py"

printf '{"tool_input":{"file_path":"%s"}}' "$TMP/target.py" \
  | PATH="$TMP/bin:$PATH" bash "$HOOK"
grep -q "target.py" "$TMP/calls.log" 2>/dev/null \
  || fail "formatter never received the file from stdin JSON (silent no-op regression)"

# 2. Nonexistent file → exit 0, no formatter call.
: > "$TMP/calls.log"
printf '{"tool_input":{"file_path":"%s/ghost.py"}}' "$TMP" \
  | PATH="$TMP/bin:$PATH" bash "$HOOK" || fail "nonexistent file must exit 0"
[ -s "$TMP/calls.log" ] && fail "formatter called for a nonexistent file"

# 3. Empty/garbage stdin → exit 0 (never blocks the turn).
printf '' | bash "$HOOK" || fail "empty stdin must exit 0"
printf 'not-json' | bash "$HOOK" || fail "garbage stdin must exit 0"

# 4. Legacy fallback: no stdin JSON path but CLAUDE_FILE_PATH set → still formats.
: > "$TMP/calls.log"
printf '{}' | CLAUDE_FILE_PATH="$TMP/target.py" PATH="$TMP/bin:$PATH" bash "$HOOK"
grep -q "target.py" "$TMP/calls.log" 2>/dev/null \
  || fail "legacy CLAUDE_FILE_PATH fallback broken"

echo "PASS: autofmt input contract (stdin JSON + degenerate inputs + legacy fallback)"
