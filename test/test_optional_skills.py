"""Opt-in packaging tests: no live host state or optional runtime dependencies."""

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "optional_skills", ROOT / "bin/optional-skills.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
NAME = "instagram-reel-preview"


class OptionalSkillsTests(unittest.TestCase):
    def test_catalog_is_complete_and_not_general_sync_input(self):
        entries = MODULE.catalog()
        source = ROOT / "skills/optional" / NAME
        self.assertIn(NAME, entries)
        self.assertNotIn("skill.md", [p.name for p in source.iterdir()])
        self.assertNotIn(NAME, (ROOT / "AGENTS.md").read_text())
        self.assertIn(
            'list "$ROOT/skills" "skill.md" 3', (ROOT / "bin/sync.sh").read_text()
        )
        for filename in entries[NAME]["files"]:
            self.assertTrue((source / filename).is_file(), filename)

    def test_build_install_and_collision(self):
        entries = MODULE.catalog()
        with tempfile.TemporaryDirectory() as temp:
            target = Path(temp)
            package = MODULE.build(NAME, target / "bundle", entries, False)
            self.assertEqual(
                sorted(p.name for p in package.iterdir()),
                sorted(entries[NAME]["files"]),
            )
            installed = MODULE.build(NAME, target / "host", entries, True)
            self.assertFalse(installed.is_symlink())
            self.assertEqual(
                (installed / "render.py").read_bytes(),
                (package / "render.py").read_bytes(),
            )
            with self.assertRaisesRegex(ValueError, "existing destination"):
                MODULE.build(NAME, target / "host", entries, True)
            foreign = target / "collision" / "foreign"
            foreign.mkdir(parents=True)
            (foreign / "SKILL.md").write_text(f'---\nname: "{NAME}"\n---\n')
            with self.assertRaisesRegex(ValueError, "already installed"):
                MODULE.build(NAME, foreign.parent, entries, True)
            self.assertFalse((foreign.parent / NAME).exists())

    def test_cli_validate_and_unknown_name(self):
        process = subprocess.run(
            [sys.executable, str(ROOT / "bin/optional-skills.py"), "validate"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertTrue(json.loads(process.stdout)["valid"])
        with tempfile.TemporaryDirectory() as temp:
            process = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "bin/optional-skills.py"),
                    "build",
                    "missing",
                    "--target",
                    temp,
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(process.returncode, 2)
            self.assertIn("Unknown optional skill", process.stderr)


if __name__ == "__main__":
    unittest.main()
