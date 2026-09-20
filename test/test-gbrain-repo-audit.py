#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("audit", Path(__file__).resolve().parents[1] / "bin/gbrain-repo-audit.py")
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class AuditTests(unittest.TestCase):
    def test_origin_sanitizes_credentials(self):
        self.assertEqual(audit.identity("https://token@github.com/owner/repo.git"), "owner/repo")
        self.assertEqual(audit.identity("git@github.com:Owner/repo.git"), "Owner/repo")
        self.assertIsNone(audit.identity("https://other.example/owner/repo.git"))

    def test_warehouse_included_worktrees_and_dependencies_excluded(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for relative in ("active", "WareHouse/old", "node_modules/vendor", "worktrees/task"):
                path = root / relative
                path.mkdir(parents=True)
                subprocess.run(["git", "init", "-q", str(path)], check=True)
            self.assertEqual({Path(x["path"]).relative_to(root).as_posix() for x in audit.inventory(root)},
                             {"active", "WareHouse/old"})

    def test_bare_root_is_reported_not_reconfigured(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            subprocess.run(["git", "init", "--bare", "-q", str(root / ".git")], check=True)
            row = audit.inspect(root)
            self.assertTrue(row["bare"])
            self.assertEqual(subprocess.check_output(
                ["git", "--git-dir", str(root / ".git"), "config", "core.bare"], text=True).strip(), "true")


if __name__ == "__main__":
    unittest.main()
