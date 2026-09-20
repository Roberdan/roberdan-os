#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import tempfile
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("recovery", Path(__file__).resolve().parents[1] /
                                             "bin/gbrain-recover-repos.py")
recovery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recovery)


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.runner = recovery.Recovery({"local": [], "remote": []}, self.root, self.root / "backup.json")
        self.head_patch = patch.object(self.runner, "head", return_value="abc")
        self.head_mock = self.head_patch.start()
        self.sources_patch = patch.object(recovery, "sources",
                                          return_value=[{"id": "source", "local_path": "/repo",
                                                         "last_commit": "abc"}])
        self.sources_mock = self.sources_patch.start()

    def tearDown(self):
        self.head_patch.stop()
        self.sources_patch.stop()
        self.tmp.cleanup()

    def test_deduplicates_identity_without_dropping_remote_only(self):
        manifest = {"remote": [{"nameWithOwner": "Owner/Repo", "isArchived": False},
                               {"nameWithOwner": "Owner/Remote", "isArchived": True}],
                    "local": [{"github": "owner/repo", "path": "/tmp/repo", "bare": False}]}
        rows = recovery.plan(manifest)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["local_path"], "/tmp/repo")
        self.assertTrue(rows[1]["archived"])

    def test_source_ids_are_stable_bounded_and_owner_specific(self):
        a = recovery.make_id("Owner/" + "long" * 30)
        self.assertLessEqual(len(a), 32)
        self.assertRegex(a, r"^[a-z0-9-]+$")
        self.assertNotEqual(recovery.make_id("owner/repo"), recovery.make_id("other/repo"))
        self.assertEqual(recovery.make_id("Owner/Repo"), recovery.make_id("owner/repo"))

    def test_active_scope_excludes_archives_remote_deleted_and_symlinks(self):
        root = self.root / "GitHub"
        for name in ("active", "WareHouse/old", "ParkingLot/parked", "worktrees/copy"):
            (root / name / ".git").mkdir(parents=True)
        (root / "alias").symlink_to(root / "WareHouse/old", target_is_directory=True)
        self.assertTrue(recovery.eligible({"local_path": str(root / "active")}, root))
        for name in ("WareHouse/old", "ParkingLot/parked", "worktrees/copy", "alias", "deleted"):
            self.assertFalse(recovery.eligible({"local_path": str(root / name)}, root))
        self.assertFalse(recovery.eligible({"local_path": None}, root))

    def test_moved_repository_stops_before_next_command(self):
        active = self.root / "GitHub/active"
        (active / ".git").mkdir(parents=True)
        self.runner.active_root = active.parent
        self.runner.current_record = {"local_path": str(active)}
        self.runner.check_scope()
        active.rename(active.parent / "removed")
        with patch.object(recovery.subprocess, "Popen", side_effect=AssertionError("must not run")):
            with self.assertRaisesRegex(RuntimeError, "outside the active folder"):
                self.runner.command(["git", "status"])

    def test_denied_pin_is_blocked_before_checkout_even_if_registered_path_changed(self):
        self.runner.manifest = {"remote": [], "local": [
            {"path": "/repo", "github": "owner/repo", "pin": "denied"}]}
        self.runner.blocked_sources = {"denied"}
        with patch.object(self.runner, "validate_backup"), \
             patch.object(self.runner, "checkout", side_effect=AssertionError("must not read content")):
            self.assertEqual(self.runner.run(), 1)

    def test_no_repair_before_verified_backup(self):
        (self.root / "backup.json").write_text('{"status":"running"}')
        with self.assertRaisesRegex(RuntimeError, "restore-tested"):
            self.runner.validate_backup()

    def test_deletions_are_preview_only(self):
        with patch.object(recovery, "active_pages", return_value={1, 2}), \
             patch.object(self.runner, "command", return_value="Sync dry run: abc..def\n  Deleted: file.md") as cmd:
            with self.assertRaisesRegex(RuntimeError, "deletions"):
                self.runner.refresh("source", Path("/repo"), False)
            self.assertEqual(cmd.call_count, 1)
            self.assertIn("--dry-run", cmd.call_args.args[0])

    def test_existing_full_sync_is_blocked(self):
        with patch.object(recovery, "active_pages", return_value={1}), \
             patch.object(self.runner, "command", return_value="Full sync would import all files") as cmd:
            with self.assertRaisesRegex(RuntimeError, "reconciliation"):
                self.runner.refresh("source", Path("/repo"), False)
            self.assertEqual(cmd.call_count, 1)

    def test_unsyncable_hard_delete_preview_is_blocked(self):
        with patch.object(recovery, "active_pages", return_value={1}), \
             patch.object(self.runner, "command",
                          return_value="Sync dry run: abc..def\n [dry-run] would delete un-syncable page: old") as cmd:
            with self.assertRaisesRegex(RuntimeError, "deletions"):
                self.runner.refresh("source", Path("/repo"), False)
            self.assertEqual(cmd.call_count, 1)

    def test_head_change_prevents_actual_sync(self):
        self.head_mock.side_effect = ["abc", "def"]
        with patch.object(recovery, "active_pages", return_value={1}), \
             patch.object(self.runner, "command", return_value="Sync dry run: abc..def\nAdded: one") as cmd:
            with self.assertRaisesRegex(RuntimeError, "HEAD changed"):
                self.runner.refresh("source", Path("/repo"), False)
            self.assertEqual(cmd.call_count, 1)

    def test_success_exit_without_matching_index_revision_is_not_verified(self):
        self.sources_mock.return_value = [{"id": "source", "last_commit": "old", "local_path": "/repo"}]
        with patch.object(recovery, "active_pages", return_value={1}), \
             patch.object(self.runner, "command", side_effect=["Sync dry run: abc..def\nAdded: one", "ok"]):
            with self.assertRaisesRegex(RuntimeError, "stored index revision"):
                self.runner.refresh("source", Path("/repo"), False)

    def test_ungranted_source_never_reads_repository_content(self):
        self.runner.manifest = {"remote": [], "local": [{"path": "/repo", "github": "owner/repo"}]}
        self.runner.blocked_sources = {"source"}
        with patch.object(self.runner, "validate_backup"), \
             patch.object(self.runner, "checkout", side_effect=AssertionError("must not access denied content")):
            self.assertEqual(self.runner.run(), 1)
        self.assertIn("access not granted", self.runner.state["repos"]["owner/repo"]["error"])

    def test_embed_command_really_is_scoped_without_dream(self):
        with patch.object(recovery.urllib.request, "urlopen") as response, \
             patch.object(self.runner, "command", side_effect=["ok", "[dry-run] Would embed 0 chunks"]) as cmd:
            response.return_value.__enter__.return_value.read.return_value = '{"version":"test"}'
            self.runner.local_vectors("target")
            self.assertEqual(cmd.call_args_list[0].args[0],
                             [recovery.GB, "embed", "--stale", "--source", "target"])
            self.assertFalse(any("dream" in call.args[0] for call in cmd.call_args_list))

    def test_managed_snapshot_does_not_follow_later_user_commits(self):
        self.head_patch.stop()
        home = self.root / "home"
        (home / ".gbrain").mkdir(parents=True)
        original = self.root / "original"
        def git(*args):
            return subprocess.run(["git", "-c", "core.hooksPath=/dev/null",
                                   "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                                   *map(str, args)], capture_output=True, text=True, check=True).stdout.strip()
        git("init", "--initial-branch=main", original)
        (original / "readme.md").write_text("one")
        git("-C", original, "add", "readme.md")
        git("-C", original, "commit", "-m", "one")
        with patch.object(recovery, "HOME", home):
            path = self.runner.checkout({"key": "owner/repo", "github": "owner/repo",
                                         "local_path": str(original), "bare": False})
            first = self.runner.head(path)
            (original / "readme.md").write_text("two")
            git("-C", original, "commit", "-am", "two")
            self.assertEqual(self.runner.head(path), first)
            self.assertNotEqual(git("-C", original, "rev-parse", "HEAD"), first)
            self.assertEqual((path / "readme.md").read_text(), "one")

    def test_incremental_refresh_checks_retained_page_identity(self):
        with patch.object(recovery, "active_pages", side_effect=[{1, 2}, {2, 3}]), \
             patch.object(self.runner, "command", side_effect=["Sync dry run: abc..def\nModified: one.md", "ok"]):
            with self.assertRaisesRegex(RuntimeError, "RETENTION FAILURE"):
                self.runner.refresh("source", Path("/repo"), False)

    def test_incremental_refresh_never_pulls_or_embeds(self):
        with patch.object(recovery, "active_pages", side_effect=[{1}, {1, 2}]), \
             patch.object(self.runner, "command", side_effect=["Sync dry run: abc..def\nAdded: one.md", "ok"]) as cmd:
            self.assertEqual(self.runner.refresh("source", Path("/repo"), False)["pages_after"], 2)
            actual = cmd.call_args.args[0]
            for flag in ("--no-pull", "--no-embed", "--no-auto-embed"):
                self.assertIn(flag, actual)
            self.assertNotIn("--force", actual)

    def test_null_path_does_not_match_every_remote_repo(self):
        data = [{"id": "default", "local_path": None}]
        with patch.object(recovery, "sources", return_value=data), \
             patch.object(self.runner, "command") as cmd:
            source, new = self.runner.source_for({"key": "owner/repo", "local_path": None}, Path("/repo"))
            self.assertTrue(new)
            self.assertNotEqual(source, "default")
            self.assertIn("--no-federated", cmd.call_args.args[0])


if __name__ == "__main__":
    unittest.main()
