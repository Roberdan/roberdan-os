#!/usr/bin/env bash
# test-install-hooks.sh — bin/install-hooks.sh merges the generated hook snippet into
# a settings.json additively, idempotently, non-destructively, and never leaves broken JSON.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$ROOT/bin/install-hooks.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
S="$TMP/settings.json"
fail() { echo "FAIL: $*" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 absent"; exit 0; }

# 1. Empty settings → dry-run adds nothing on disk; --apply wires the five events.
echo '{}' > "$S"
RDA_CLAUDE_SETTINGS="$S" bash "$SH" >/dev/null              # dry-run
python3 -c "import json;h=json.load(open('$S')).get('hooks',{});assert not h, 'dry-run wrote to disk'" \
  || fail "dry-run must not modify the file"
RDA_CLAUDE_SETTINGS="$S" bash "$SH" --apply >/dev/null
for ev in SessionStart PreToolUse PostToolUse PreCompact Stop; do
  python3 -c "import json;assert '$ev' in json.load(open('$S'))['hooks'], '$ev missing'" \
    || fail "$ev not wired after --apply"
done
jq -e . "$S" >/dev/null || fail "result not valid JSON"

# 2. Idempotent: a second --apply adds nothing (byte-identical hooks).
before="$(jq -S .hooks "$S")"
RDA_CLAUDE_SETTINGS="$S" bash "$SH" --apply >/dev/null
[ "$before" = "$(jq -S .hooks "$S")" ] || fail "second run changed the hooks (not idempotent)"

# 3. Non-destructive: a foreign hook survives the merge.
python3 -c "
import json
d=json.load(open('$S'))
d['hooks'].setdefault('Stop',[]).append({'hooks':[{'type':'command','command':'foreign-orca.sh'}]})
json.dump(d,open('$S','w'))
"
RDA_CLAUDE_SETTINGS="$S" bash "$SH" --apply >/dev/null
python3 -c "import json;assert 'foreign-orca.sh' in json.dumps(json.load(open('$S'))), 'foreign hook dropped'" \
  || fail "merge removed a foreign hook"

# 4. A backup file was produced on a real write.
ls "$S".bak-* >/dev/null 2>&1 || fail "no backup created on --apply"

echo "PASS: install-hooks (wires 5 events, dry-run safe, idempotent, non-destructive, backup, valid JSON)"
