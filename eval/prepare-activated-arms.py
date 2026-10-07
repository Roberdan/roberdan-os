#!/usr/bin/env python3
"""Build blind, isolated no-canon and activated-canon homes."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import secrets
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]


def arm_id(seed: str | None, condition: str) -> str:
    token = (
        hashlib.sha256(f"{seed}:{condition}".encode()).hexdigest()[:12]
        if seed
        else secrets.token_hex(6)
    )
    return f"arm-{token}"


def run(argv: list[str], env: dict[str, str]) -> None:
    result = subprocess.run(
        argv,
        cwd=ROOT,
        env=env,
        check=False,
        capture_output=True,
        text=True,
        timeout=180,
    )
    if result.returncode:
        raise RuntimeError(f"{Path(argv[1]).name} failed with exit {result.returncode}")


def prepare_base(home: Path) -> None:
    for path in (
        home / ".claude",
        home / ".copilot",
        home / ".codex",
        home / "GitHub",
    ):
        path.mkdir(parents=True, exist_ok=True)


def activate(home: Path) -> None:
    generated = home / "generated"
    env = dict(
        os.environ,
        HOME=str(home),
        RDA_SYNC_OUT=str(generated),
        RDA_CLAUDE_SKILLS_DIR=str(home / ".claude/skills"),
        RDA_COPILOT_SKILLS_DIR=str(home / ".copilot/skills"),
        RDA_COPILOT_AGENTS_DIR=str(home / ".copilot/agents"),
        RDA_COPILOT_EXT_DIR=str(home / ".copilot/extensions"),
        RDA_COPILOT_USER_INSTR=str(home / ".copilot/copilot-instructions.md"),
        RDA_COPILOT_MCP_CONFIG=str(home / ".copilot/mcp-config.json"),
        RDA_POINTER_HOME=str(home),
        RDA_FORCE_CODEX="1",
        RDA_FORCE_OPENCODE="0",
    )
    run(["bash", "bin/sync.sh", "--install"], env)
    shutil.copyfile(ROOT / "bin/claude-global-block.md", home / ".claude/CLAUDE.md")
    settings = home / ".claude/settings.json"
    env["RDA_CLAUDE_SETTINGS"] = str(settings)
    run(["bash", "bin/install-hooks.sh", "--apply"], env)


def count_files(path: Path, pattern: str) -> int:
    return len(list(path.glob(pattern))) if path.is_dir() else 0


def hook_count(settings: Path) -> int:
    if not settings.is_file():
        return 0
    data = json.loads(settings.read_text(encoding="utf-8"))
    return sum(
        len(group.get("hooks", []))
        for groups in data.get("hooks", {}).values()
        for group in groups
        if isinstance(group, dict)
    )


def structure(home: Path) -> dict[str, Any]:
    return {
        "claude_global": (home / ".claude/CLAUDE.md").is_file(),
        "claude_hooks": hook_count(home / ".claude/settings.json"),
        "claude_skills": count_files(home / ".claude/skills", "*/SKILL.md"),
        "copilot_agents": count_files(home / ".copilot/agents", "*.md"),
        "copilot_extension": (
            home / ".copilot/extensions/roberdan-os/extension.mjs"
        ).is_file(),
        "copilot_instructions": (
            home / ".copilot/copilot-instructions.md"
        ).is_file(),
        "copilot_skills": count_files(home / ".copilot/skills", "*/SKILL.md"),
        "codex_projection": (home / ".codex/AGENTS.md").is_file(),
        "github_projection": (home / "GitHub/AGENTS.md").is_file(),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--seed")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists():
        if not args.force:
            print("prepare-activated-arms: output already exists", file=sys.stderr)
            return 2
        shutil.rmtree(output)
    output.mkdir(parents=True)

    ids = {"no-canon": arm_id(args.seed, "no-canon"), "activated": arm_id(args.seed, "activated")}
    for identifier in ids.values():
        prepare_base(output / identifier / "home")
    activate(output / ids["activated"] / "home")

    manifests = {}
    for condition, identifier in ids.items():
        manifest = structure(output / identifier / "home")
        manifests[condition] = manifest
        (output / identifier / "structure.json").write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
    if manifests["no-canon"] == manifests["activated"]:
        print("prepare-activated-arms: collapse control failed", file=sys.stderr)
        return 1
    if not all(
        (
            manifests["activated"]["claude_global"],
            manifests["activated"]["claude_hooks"] > 0,
            manifests["activated"]["copilot_extension"],
            manifests["activated"]["codex_projection"],
        )
    ):
        print("prepare-activated-arms: activated arm is incomplete", file=sys.stderr)
        return 1
    (output / "arm-mapping.json").write_text(
        json.dumps(
            {
                "blind_ids": list(ids.values()),
                "mapping": {identifier: condition for condition, identifier in ids.items()},
                "claim": "structural activation only; not a behavioral value result",
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    print(json.dumps({"blind_ids": list(ids.values()), "status": "distinct"}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
