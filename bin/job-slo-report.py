#!/usr/bin/env python3
"""Report scheduled-job liveness without reading logs or receipt contents."""

from __future__ import annotations

import argparse
import csv
import glob
import json
import os
import plistlib
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "docs/evidence/job-slo.tsv"
REQUIRED = {
    "label",
    "owner",
    "domain",
    "plist",
    "receipt_glob",
    "max_age_seconds",
    "correctness_probe",
}


def expand(value: str, home: Path) -> str:
    return value.replace("$HOME", str(home)).replace("~", str(home), 1)


def load_manifest(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if set(reader.fieldnames or []) != REQUIRED:
            raise ValueError(f"invalid manifest schema: {reader.fieldnames}")
        rows = list(reader)
    labels = [row["label"] for row in rows]
    if not rows or len(labels) != len(set(labels)):
        raise ValueError("manifest must contain unique jobs")
    return rows


def plist_path(row: dict[str, str], launchagents: Path, home: Path) -> Path:
    if row["plist"] == "auto":
        preferred = launchagents / f"{row['label']}.plist"
        if preferred.is_file():
            return preferred
        for candidate in launchagents.glob("*.plist"):
            try:
                with candidate.open("rb") as handle:
                    if plistlib.load(handle).get("Label") == row["label"]:
                        return candidate
            except (OSError, plistlib.InvalidFileException):
                continue
        return preferred
    return Path(expand(row["plist"], home))


def plist_metadata(path: Path) -> tuple[str, str]:
    if not path.is_file():
        return "missing", "unknown"
    try:
        with path.open("rb") as handle:
            data = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException):
        return "invalid", "unknown"
    if "StartInterval" in data:
        schedule = "interval"
    elif "StartCalendarInterval" in data:
        schedule = "calendar"
    elif data.get("KeepAlive"):
        schedule = "keepalive"
    elif data.get("RunAtLoad"):
        schedule = "run-at-load"
    else:
        schedule = "unscheduled"
    return "present", schedule


def launchctl_text(label: str, domain: str, fixture_dir: Path | None) -> str | None:
    if fixture_dir:
        path = fixture_dir / f"{label}.txt"
        return path.read_text(encoding="utf-8") if path.is_file() else None
    target = f"gui/{os.getuid()}/{label}" if domain == "user" else f"system/{label}"
    result = subprocess.run(
        ["launchctl", "print", target],
        check=False,
        capture_output=True,
        text=True,
        timeout=10,
    )
    return result.stdout if result.returncode == 0 else None


def launchctl_state(text: str | None) -> tuple[str, int | None]:
    if text is None:
        return "not-loaded", None
    state_match = re.search(r"^\s*state = (.+?)\s*$", text, re.MULTILINE)
    exit_match = re.search(r"^\s*last exit code = (-?\d+)", text, re.MULTILINE)
    exit_code = int(exit_match.group(1)) if exit_match else None
    if exit_code not in (None, 0):
        return "loaded-failing", exit_code
    state = state_match.group(1).lower() if state_match else "unknown"
    normalized = {
        "not running": "idle",
        "waiting": "idle",
        "running": "running",
    }.get(state, re.sub(r"[^a-z0-9]+", "-", state).strip("-"))
    return f"loaded-{normalized}", exit_code


def receipt_state(pattern: str, max_age: int, home: Path, now: float) -> tuple[str, int | None]:
    if pattern == "-":
        return "not-configured", None
    paths = [Path(path) for path in glob.glob(expand(pattern, home))]
    files = [path for path in paths if path.is_file()]
    if not files:
        return "missing", None
    newest = max(files, key=lambda path: path.stat().st_mtime)
    age = max(0, int(now - newest.stat().st_mtime))
    return ("fresh" if age <= max_age else "stale"), age


def probe_state(value: str) -> str:
    if value == "-":
        return "unproven"
    return "available-not-run" if (ROOT / value).is_file() else "missing"


def inspect(
    row: dict[str, str],
    launchagents: Path,
    fixture_dir: Path | None,
    home: Path,
    now: float,
) -> dict[str, Any]:
    plist, schedule = plist_metadata(plist_path(row, launchagents, home))
    loaded, exit_code = launchctl_state(
        launchctl_text(row["label"], row["domain"], fixture_dir)
    )
    receipt, age = receipt_state(
        row["receipt_glob"], int(row["max_age_seconds"]), home, now
    )
    return {
        "label": row["label"],
        "owner": row["owner"],
        "plist": plist,
        "schedule": schedule,
        "liveness": loaded,
        "last_exit": exit_code,
        "receipt": receipt,
        "receipt_age_seconds": age,
        "correctness": probe_state(row["correctness_probe"]),
    }


def print_table(results: list[dict[str, Any]]) -> None:
    print("label\towner\tplist\tschedule\tliveness\treceipt\tcorrectness")
    for item in results:
        print(
            "\t".join(
                str(item[key])
                for key in (
                    "label",
                    "owner",
                    "plist",
                    "schedule",
                    "liveness",
                    "receipt",
                    "correctness",
                )
            )
        )
    print(
        "\nLiveness reports wiring and the last launchd exit only; "
        "correctness probes are listed but not executed."
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument(
        "--launchagents-dir",
        type=Path,
        default=Path.home() / "Library/LaunchAgents",
    )
    parser.add_argument("--launchctl-fixture-dir", type=Path)
    parser.add_argument("--home", type=Path, default=Path.home())
    parser.add_argument("--now", type=float, default=time.time())
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    try:
        rows = load_manifest(args.manifest)
        results = [
            inspect(
                row,
                args.launchagents_dir,
                args.launchctl_fixture_dir,
                args.home,
                args.now,
            )
            for row in rows
        ]
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"job-slo-report: {error}", file=sys.stderr)
        return 2
    if args.json:
        json.dump({"jobs": results}, sys.stdout, indent=2, sort_keys=True)
        print()
    else:
        print_table(results)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
