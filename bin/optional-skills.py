#!/usr/bin/env python3
"""Build or install one explicitly selected optional skill, without running sync."""

import argparse
import json
import re
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "skills" / "optional"


def catalog() -> dict:
    data = json.loads((CATALOG / "catalog.json").read_text(encoding="utf-8"))
    if data.get("schema_version") != 1 or not isinstance(data.get("skills"), dict):
        raise ValueError("Invalid optional catalog schema")
    for name, entry in data["skills"].items():
        if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", name):
            raise ValueError(f"Unsafe skill name: {name}")
        files = entry.get("files", [])
        if not files or "SKILL.md" not in files or len(set(files)) != len(files):
            raise ValueError(f"{name}: explicit unique file list must include SKILL.md")
        if not entry.get("description"):
            raise ValueError(f"{name}: description required")
        for filename in files:
            relative = Path(filename)
            path = CATALOG / name / relative
            if relative.is_absolute() or ".." in relative.parts or path.is_symlink():
                raise ValueError(f"{name}: unsafe file {filename}")
            if not path.is_file() or not path.resolve().is_relative_to(CATALOG / name):
                raise ValueError(f"{name}: missing or escaping file {filename}")
        text = (CATALOG / name / "SKILL.md").read_text(encoding="utf-8")
        if not text.startswith("---\n") or f"\nname: {name}\n" not in text:
            raise ValueError(f"{name}: SKILL.md needs matching frontmatter")
        if "\ndescription: " not in text.split("---", 2)[1]:
            raise ValueError(f"{name}: SKILL.md needs a description")
    return data["skills"]


def build(name: str, target: Path, entries: dict, installing: bool) -> Path:
    if name not in entries:
        raise ValueError(f"Unknown optional skill: {name}")
    target = target.expanduser().resolve()
    destination = target / name
    if destination.exists() or destination.is_symlink():
        raise ValueError(f"Refusing existing destination: {destination}")
    if installing and target.exists():
        for file in target.glob("*/SKILL.md"):
            text = file.read_text(encoding="utf-8")
            if re.search(rf"^name:\s*['\"]?{re.escape(name)}['\"]?\s*$", text, re.M):
                raise ValueError(f"Skill name already installed: {file}")
    target.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".optional-skill-", dir=target) as temp:
        package = Path(temp) / name
        package.mkdir()
        for filename in entries[name]["files"]:
            output = package / filename
            output.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(CATALOG / name / filename, output)
        # Reserve rather than replace an existing skill, even during concurrent installs.
        destination.mkdir()
        for child in package.iterdir():
            shutil.move(str(child), destination / child.name)
    return destination


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["list", "validate", "build", "install"])
    parser.add_argument("name", nargs="?")
    parser.add_argument(
        "--target", type=Path, help="Explicit build or host skills directory"
    )
    args = parser.parse_args()
    try:
        entries = catalog()
        if args.action in {"list", "validate"}:
            if args.name or args.target:
                parser.error("list/validate take no name or target")
            print(json.dumps({"optional": entries, "valid": True}, indent=2))
        else:
            if not args.name or not args.target:
                parser.error("build/install require a skill name and --target")
            print(build(args.name, args.target, entries, args.action == "install"))
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"optional-skills: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
