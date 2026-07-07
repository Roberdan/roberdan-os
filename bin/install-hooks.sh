#!/usr/bin/env bash
# install-hooks.sh — merge the GENERATED Claude Code hook snippet into the real
# ~/.claude/settings.json, idempotently and non-destructively. Closes the last
# "manual step" gap: after this, `clone + bootstrap + sync --install + install-hooks`
# is a complete, zero-hand-edit setup on a fresh machine.
#
#   bin/install-hooks.sh          # DRY-RUN: print the merge that WOULD happen
#   bin/install-hooks.sh --apply  # write it (timestamped backup first)
#
# Non-destructive by construction:
#   - additive: only ADDS roberdan-os hook entries that aren't already present
#     (dedup by the hook command string) — never removes or reorders the user's
#     own hooks (orca, gstack, etc.).
#   - backup: writes ~/.claude/settings.json.bak-<ts> before any change.
#   - idempotent: a second run is a no-op ("already wired").
# Override the target for testing: RDA_CLAUDE_SETTINGS (default ~/.claude/settings.json).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

command -v jq >/dev/null 2>&1 || { echo "install-hooks: jq required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "install-hooks: python3 required" >&2; exit 1; }

SETTINGS="${RDA_CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"

# 1) Generate the snippet fresh from the canon (deterministic; absolute paths already
#    expanded by sync.sh at generation time — no $RDA_OS left to break on merge).
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
RDA_SYNC_OUT="$TMP/platforms" bash bin/sync.sh --emit-only >/dev/null
SNIPPET="$TMP/platforms/claude/settings-hooks.json"
[ -f "$SNIPPET" ] || { echo "install-hooks: generated snippet missing" >&2; exit 1; }

# 2) Merge in python3 (readable, precise dedup) — prints a summary of what changes.
python3 - "$SETTINGS" "$SNIPPET" "$APPLY" <<'PY'
import json, sys, os, time

settings_path, snippet_path, apply = sys.argv[1], sys.argv[2], sys.argv[3] == "1"

snippet = json.load(open(snippet_path))["hooks"]
settings = {}
if os.path.exists(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)
hooks = settings.setdefault("hooks", {})

def cmds(entry):
    return {h.get("command", "") for h in entry.get("hooks", [])}

added = []
for event, entries in snippet.items():
    existing = hooks.setdefault(event, [])
    existing_cmds = set()
    for e in existing:
        existing_cmds |= cmds(e)
    for entry in entries:
        new_cmds = cmds(entry) - existing_cmds
        if not new_cmds:
            continue  # every command in this entry already wired somewhere
        # add only the not-yet-present commands (keep the entry's matcher if any)
        keep = {k: v for k, v in entry.items() if k != "hooks"}
        keep["hooks"] = [h for h in entry["hooks"] if h.get("command") in new_cmds]
        existing.append(keep)
        added.extend(sorted(new_cmds))

if not added:
    print("install-hooks: ✅ already wired — nothing to add (idempotent no-op).")
    sys.exit(0)

print("install-hooks: would add %d hook command(s):" % len(added))
for c in added:
    # show a short tail of the command for readability
    tail = c.split("roberdan-os/")[-1] if "roberdan-os/" in c else c
    print("  +", tail)

if not apply:
    print("\n(dry-run) re-run with --apply to write it.")
    sys.exit(0)

bak = settings_path + ".bak-" + time.strftime("%Y%m%dT%H%M%S")
if os.path.exists(settings_path):
    import shutil
    shutil.copy(settings_path, bak)
    print("\nbackup:", bak)
os.makedirs(os.path.dirname(settings_path), exist_ok=True)
with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write("\n")
print("install-hooks: ✅ merged into", settings_path)
PY

# 3) Validate the result is still parseable JSON (never leave a broken settings file).
if [ "$APPLY" = "1" ] && [ -f "$SETTINGS" ]; then
  jq . "$SETTINGS" >/dev/null || { echo "install-hooks: ✗ result is not valid JSON — restore from the .bak" >&2; exit 1; }
fi
