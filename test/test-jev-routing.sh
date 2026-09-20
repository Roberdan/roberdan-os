#!/usr/bin/env bash
# Exercise canonical routing, actual CLI examples and isolated wrapper generation.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TMP="$(mktemp -d)"
trap 'python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1])" "$TMP"' EXIT
mkdir -p "$TMP/home"
HOME="$TMP/home" RDA_SYNC_OUT="$TMP/generated" \
  RDA_FORCE_CODEX=0 RDA_FORCE_OPENCODE=0 bash bin/sync.sh --emit-only >/dev/null
python3 - "$ROOT" "$TMP" <<'PY'
import json
import os
from pathlib import Path
import subprocess
import sys

root, tmp = map(Path, sys.argv[1:])
routes = {
    "AGENTS.md": "evaluate retrieval",
    "agents/twin.md": "evaluate twin",
    "agents/wanda.md": "evaluate wanda",
    "agents/thor.md": "evaluate thor",
    "skills/verify-done/skill.md": "jev",
    ".github/skills/roberdan-twin/SKILL.md": "Optional Jev observations",
}
for path, token in routes.items():
    assert token in (root / path).read_text(), (path, token)

wrapper = tmp / "generated/claude/skills/jev/SKILL.md"
assert wrapper.is_file(), "shared skill wrapper missing"
assert "skills/jev/skill.md" in wrapper.read_text()
for agent in ("twin", "wanda", "thor"):
    generated = tmp / f"generated/copilot/agents/{agent}.md"
    assert "jev" in generated.read_text(), agent

env = {k: v for k, v in os.environ.items() if not k.startswith("TYPESAFE_")}
env["HOME"] = str(tmp / "home")
env["PYTHONDONTWRITEBYTECODE"] = "1"
for profile in ("twin", "retrieval", "wanda", "thor"):
    fixture = root / "skills/jev/examples" / f"{profile}.json"
    result = subprocess.run(
        [sys.executable, str(root / "bin/jev.py"), "evaluate", profile,
         "--input", str(fixture)], env=env, capture_output=True, text=True,
        timeout=10, check=True,
    )
    assert json.loads(result.stdout)["status"] == "dry_run", result.stdout
assert not (tmp / "home/.roberdan-os/private").exists(), "dry-run wrote private state"
print("test-jev-routing: PASS (four real CLI examples and generated agent/skill routes)")
PY
