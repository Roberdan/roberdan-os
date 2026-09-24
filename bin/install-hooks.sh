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
#     own hooks (orca, gstack, etc.). The one exception is our OWN commands: if the
#     canon snippet narrows a command's matcher across a release (e.g. bus-doorbell.sh
#     moving off "*"), a stale roberdan-os entry is MOVED to the new matcher, not left
#     behind and not duplicated. This never touches a command outside the snippet.
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
import json, re, sys, os, time

settings_path, snippet_path, apply = sys.argv[1], sys.argv[2], sys.argv[3] == "1"

HOME = os.path.expanduser("~")

def norm(cmd):
    """Due scritture dello STESSO comando devono confrontarsi uguali.

    Rilievo 24, 2026-08-02: il dedup confrontava la stringa grezza, e la configurazione viva di
    Roberto usa forme equivalenti ma diverse da quelle che il generatore produce oggi —
    `bash $HOME/...` contro `bash /Users/Roberdan/...`, `bash ~/...` contro il percorso assoluto,
    `bash X` contro `X`. Risultato: il dry-run annunciava "would add 11 hook command(s)" quando
    dieci di quelli erano GIA' installati, e `--apply` avrebbe fatto girare ogni controllo DUE
    VOLTE a ogni evento — due checkpoint, due gate di pre-completamento, due formattatori. Il
    file dichiara di essere "non-destructive by construction" e "idempotent: a second run is a
    no-op": su questa macchina non lo era, e chi lo lancia lo fa proprio credendo a quella riga.

    Normalizza SOLO cio' che e' davvero la stessa cosa. NON tocca redirezioni, `|| true`,
    argomenti o ordine: `X` e `X 2>/dev/null || true` restano due comandi diversi, perche' lo
    sono — hanno due comportamenti diversi davanti a un errore. Un dedup troppo generoso
    saprebbe di idempotenza e sarebbe invece un controllo che sparisce senza dirlo.
    """
    c = cmd.strip()
    c = c.replace("${HOME}", HOME).replace("$HOME", HOME)
    c = re.sub(r'(?<![\w/~])~/', HOME + "/", c)      # `~/x` solo a inizio percorso, non dentro
    c = re.sub(r'^(?:bash|sh|/bin/sh|/bin/bash)\s+', '', c)
    c = re.sub(r'\s+', ' ', c)
    return c

snippet = json.load(open(snippet_path))["hooks"]
settings = {}
if os.path.exists(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)
hooks = settings.setdefault("hooks", {})

def cmds(entry):
    return {norm(h.get("command", "")) for h in entry.get("hooks", [])}

# Matcher the CANON snippet wants for each (event, command) pair — the source of
# truth for "which tools this hook should run after". A command can move to a
# narrower matcher across a release (e.g. bus-doorbell.sh from unmatched/"*" to
# "Bash|Edit|Write"); an existing settings.json written under the old matcher
# must be UPGRADED to the new one, not left stale and not duplicated.
desired_matcher = {}
for event, entries in snippet.items():
    for entry in entries:
        for h in entry.get("hooks", []):
            nc = norm(h.get("command", ""))
            if nc:
                desired_matcher[(event, nc)] = entry.get("matcher")

def matcher_key(m):
    """None, "" and "*" all mean 'match every tool' to Claude Code — compare them as
    equal so a command already on any 'match-all' spelling is never moved just because
    the canon snippet happens to write that same meaning differently."""
    return "*" if m in (None, "") else m

upgraded = []
touched_ids = set()
for event, entries in hooks.items():
    if event not in snippet:
        continue  # not ours to touch — a foreign event stays exactly as found
    for e in entries:
        keep_hooks = []
        for h in e.get("hooks", []):
            nc = norm(h.get("command", ""))
            want = desired_matcher.get((event, nc))
            if (event, nc) in desired_matcher and matcher_key(e.get("matcher")) != matcher_key(want):
                # This command is ours (it's in the canon snippet) and is sitting
                # under a stale matcher. Drop it here — the add-pass below re-adds
                # it under the entry with the canon matcher, so it moves instead
                # of duplicating.
                upgraded.append(nc)
                touched_ids.add(id(e))
                continue
            keep_hooks.append(h)
        e["hooks"] = keep_hooks
    # Drop only entries THIS pass emptied — a pre-existing entry we never touched
    # (however it got that way) is the user's own business, not ours to remove.
    hooks[event] = [e for e in entries if e.get("hooks") or id(e) not in touched_ids]

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
        keep["hooks"] = [h for h in entry["hooks"] if norm(h.get("command", "")) in new_cmds]
        existing.append(keep)
        added.extend(sorted(new_cmds))

if not added and not upgraded:
    print("install-hooks: ✅ already wired — nothing to add (idempotent no-op).")
    sys.exit(0)

if upgraded:
    print("install-hooks: would move %d hook command(s) to their canon matcher:" % len(upgraded))
    for c in sorted(set(upgraded)):
        tail = c.split("roberdan-os/")[-1] if "roberdan-os/" in c else c
        print("  ~", tail)

if added:
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
