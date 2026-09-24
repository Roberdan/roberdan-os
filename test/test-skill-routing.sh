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
def canonical_route(text, name, request):
    rows = [row.split("|") for row in text.splitlines()
            if row.startswith(f"| {request}")]
    return (len(rows) == 1
            and rows[0][2].strip() == f"`rdos-{name}`"
            and f"(skills/{name}/skill.md)" in rows[0][3])


for name, request in (("review", "Code review /"), ("ship", "Ship /")):
    assert canonical_route(canon, name, request), "Canonical route missing"
    assert not canonical_route(canon.replace(f"`rdos-{name}`", f"`{name}`"),
                               name, request), "Foreign name must not pass"
    assert not canonical_route(canon.replace(f"(skills/{name}/skill.md)", ""),
                               name, request), "Missing fallback must not pass"
    assert (root / "skills" / name / "skill.md").is_file()
assert "fresh session" in canon, "Installed changes must not claim a live-session refresh"
assert "including a text-only request" in canon, "Video planning must route before production"
assert "text-only concepts" in skill.read_text(), "Discovery must include concept-only work"
print("PASS: video and namespaced canonical routes, fallbacks and negative controls")
PY
