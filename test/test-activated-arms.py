#!/usr/bin/env python3
"""The activated A/B fixture uses real install paths and cannot collapse."""

from __future__ import annotations

import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PREPARE = ROOT / "eval/prepare-activated-arms.py"

with tempfile.TemporaryDirectory() as raw_tmp:
    output = Path(raw_tmp) / "arms"
    result = subprocess.run(
        [str(PREPARE), "--output", str(output), "--seed", "fixture-seed"],
        check=True,
        capture_output=True,
        text=True,
    )
    public = json.loads(result.stdout)
    mapping = json.loads((output / "arm-mapping.json").read_text(encoding="utf-8"))
    assert public["status"] == "distinct"
    assert len(set(public["blind_ids"])) == 2
    assert set(mapping["mapping"].values()) == {"no-canon", "activated"}
    assert "behavioral value" in mapping["claim"]

    structures = {
        condition: json.loads(
            (output / identifier / "structure.json").read_text(encoding="utf-8")
        )
        for identifier, condition in mapping["mapping"].items()
    }
    assert structures["no-canon"] != structures["activated"]
    assert not any(structures["no-canon"].values())
    active = structures["activated"]
    assert active["claude_global"]
    assert active["claude_hooks"] > 0
    assert active["claude_skills"] > 0
    assert active["copilot_agents"] > 0
    assert active["copilot_extension"]
    assert active["copilot_instructions"]
    assert active["copilot_skills"] > 0
    assert active["codex_projection"]
    assert active["github_projection"]

    rerun = subprocess.run(
        [str(PREPARE), "--output", str(output), "--seed", "fixture-seed"],
        check=False,
        capture_output=True,
        text=True,
    )
    assert rerun.returncode == 2 and "already exists" in rerun.stderr

print("test-activated-arms: PASS")
