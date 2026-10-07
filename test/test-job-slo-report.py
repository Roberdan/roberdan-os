#!/usr/bin/env python3
"""Behavioral fixtures for the metadata-only job SLO report."""

from __future__ import annotations

import json
import os
import plistlib
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "bin/job-slo-report.py"
NOW = 1_800_000_000


def write_plist(path: Path, label: str, schedule: str) -> None:
    data: dict[str, object] = {"Label": label, "ProgramArguments": ["/bin/true"]}
    if schedule == "interval":
        data["StartInterval"] = 60
    elif schedule == "calendar":
        data["StartCalendarInterval"] = {"Hour": 1}
    with path.open("wb") as handle:
        plistlib.dump(data, handle)


with tempfile.TemporaryDirectory() as raw_tmp:
    tmp = Path(raw_tmp)
    home = tmp / "home"
    agents = home / "Library/LaunchAgents"
    launchctl = tmp / "launchctl"
    probes = ROOT / "test"
    agents.mkdir(parents=True)
    launchctl.mkdir()

    manifest = tmp / "jobs.tsv"
    manifest.write_text(
        "label\towner\tdomain\tplist\treceipt_glob\tmax_age_seconds\tcorrectness_probe\n"
        "fixture.healthy\towner-a\tuser\tauto\t$HOME/receipt.bin\t300\t"
        "test/test-job-slo-report.py\n"
        "fixture.failing\towner-b\tuser\tauto\t$HOME/stale.bin\t60\t"
        "test/test-job-slo-report.py\n"
        "fixture.unproven\towner-c\tuser\tauto\t-\t0\t-\n",
        encoding="utf-8",
    )
    write_plist(agents / "fixture.healthy.plist", "fixture.healthy", "interval")
    write_plist(agents / "fixture.failing.plist", "fixture.failing", "calendar")
    (launchctl / "fixture.healthy.txt").write_text(
        "state = waiting\nlast exit code = 0\n", encoding="utf-8"
    )
    (launchctl / "fixture.failing.txt").write_text(
        "state = waiting\nlast exit code = 3\n", encoding="utf-8"
    )

    receipt = home / "receipt.bin"
    receipt.write_text("PRIVATE_RECEIPT_SENTINEL", encoding="utf-8")
    stale = home / "stale.bin"
    stale.write_text("PRIVATE_STALE_SENTINEL", encoding="utf-8")
    os.utime(receipt, (NOW - 30, NOW - 30))
    os.utime(stale, (NOW - 600, NOW - 600))
    receipt.chmod(0)
    stale.chmod(0)

    command = [
        str(REPORT),
        "--manifest",
        str(manifest),
        "--launchagents-dir",
        str(agents),
        "--launchctl-fixture-dir",
        str(launchctl),
        "--home",
        str(home),
        "--now",
        str(NOW),
        "--json",
    ]
    result = subprocess.run(command, check=True, capture_output=True, text=True)
    assert "PRIVATE_" not in result.stdout
    jobs = {item["label"]: item for item in json.loads(result.stdout)["jobs"]}
    assert jobs["fixture.healthy"] == {
        "correctness": "available-not-run",
        "label": "fixture.healthy",
        "last_exit": 0,
        "liveness": "loaded-idle",
        "owner": "owner-a",
        "plist": "present",
        "receipt": "fresh",
        "receipt_age_seconds": 30,
        "schedule": "interval",
    }
    assert jobs["fixture.failing"]["liveness"] == "loaded-failing"
    assert jobs["fixture.failing"]["last_exit"] == 3
    assert jobs["fixture.failing"]["receipt"] == "stale"
    assert jobs["fixture.unproven"]["liveness"] == "not-loaded"
    assert jobs["fixture.unproven"]["correctness"] == "unproven"
    assert jobs["fixture.unproven"]["receipt"] == "not-configured"
    assert probes.is_dir()

print("test-job-slo-report: PASS")
