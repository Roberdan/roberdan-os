#!/usr/bin/env python3
"""Stub every trust branch of the gbrain/rg parity report."""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "bin/graph-parity-report.py"


def run(repo: Path, tools: Path, mode: str) -> tuple[int, dict[str, object]]:
    env = dict(os.environ, GBRAIN_STUB_MODE=mode)
    result = subprocess.run(
        [
            str(REPORT),
            "--repo",
            str(repo),
            "--gbrain",
            str(tools / "gbrain"),
            "--rg",
            "rg",
            "--json",
        ],
        env=env,
        check=False,
        capture_output=True,
        text=True,
    )
    return result.returncode, json.loads(result.stdout)


with tempfile.TemporaryDirectory() as raw_tmp:
    tmp = Path(raw_tmp)
    repo = tmp / "repo"
    tools = tmp / "tools"
    repo.mkdir()
    tools.mkdir()
    (repo / ".gbrain-source").write_text("fixture-source\n", encoding="utf-8")
    (repo / "fixture.py").write_text(
        "class PrivacyError(Exception):\n    pass\n", encoding="utf-8"
    )
    (repo / "fixture.sh").write_text(
        "run_preflight() {\n  return 0\n}\n", encoding="utf-8"
    )
    stub = tools / "gbrain"
    stub.write_text(
        """#!/usr/bin/env python3
import json, os, sys
source = sys.argv[sys.argv.index("--source") + 1]
symbol = sys.argv[-1]
mode = os.environ.get("GBRAIN_STUB_MODE", "healthy")
if mode == "malformed":
    print("not-json")
    raise SystemExit
if mode == "widened":
    print(json.dumps({"source_id": None, "scope": "all", "count": 9}))
    raise SystemExit
counts = {"PrivacyError": 1}
if mode == "missing-positive":
    counts["PrivacyError"] = 0
if mode == "bash-supported":
    counts["run_preflight"] = 1
if mode == "bad-negative":
    counts["__rda_gbrain_negative_control_9f4c0e__"] = 1
print(json.dumps({"source_id": source, "scope": "single", "count": counts.get(symbol, 0)}))
""",
        encoding="utf-8",
    )
    stub.chmod(0o755)

    rc, healthy = run(repo, tools, "healthy")
    assert rc == 0 and healthy["overall"] == "ok"
    observations = {row["name"]: row["observation"] for row in healthy["controls"]}
    assert observations["bash-fallback"] == "known-gbrain-gap-rg-fallback-works"
    assert observations["freshness"] == "rg-immediate-gbrain-stale"

    rc, supported = run(repo, tools, "bash-supported")
    assert rc == 0 and supported["overall"] == "ok"
    assert next(
        row["observation"]
        for row in supported["controls"]
        if row["name"] == "bash-fallback"
    ) == "gbrain-now-resolves-bash"

    rc, missing = run(repo, tools, "missing-positive")
    assert rc == 1 and missing["overall"] == "broken"

    for mode in ("widened", "malformed", "bad-negative"):
        rc, report = run(repo, tools, mode)
        assert rc == 0 and report["overall"] == "inconclusive"

print("test-graph-parity-report: PASS")
