#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROOT" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])


def route(text):
    rows = [row for row in text.splitlines() if row.startswith("| Video,")]
    return (
        len(rows) == 1
        and "before planning or production" in rows[0]
        and "`film-director`" in rows[0]
        and "(skills/film-director/skill.md)" in rows[0]
    )


canon = (root / "AGENTS.md").read_text()
assert route(canon), "Video work has no contextual film-director route"
without = "\n".join(row for row in canon.splitlines() if not row.startswith("| Video,"))
assert not route(without), "Removing the route must fail its contract"
skill = root / "skills/film-director/skill.md"
assert skill.is_file(), "Fallback skill is missing"
assert re.search(r"(?m)^name:\s*film-director\s*$", skill.read_text()), (
    "Route and declared skill name disagree"
)
print("PASS: contextual video route, declared fallback and negative control")
PY
