#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import Mock

spec = importlib.util.spec_from_file_location(
    "refresh", Path(__file__).resolve().parents[1] / "bin/gbrain-refresh-active.py")
refresh = importlib.util.module_from_spec(spec)
spec.loader.exec_module(refresh)


class RefreshTests(unittest.TestCase):
    def test_only_explicit_source_and_authoritative_zero_completes(self):
        job = Mock()
        job.command.side_effect = ["Would embed 2 stale chunks", "ok", "Would embed 0 chunks"]
        refresh.embed_until_done(job, "permitted", {}, "/gbrain")
        for call in job.command.call_args_list:
            self.assertIn("--source", call.args[1])
            self.assertIn("permitted", call.args[1])
            self.assertNotIn("dream", call.args[1])
        self.assertEqual(job.command.call_count, 3)

    def test_zero_does_not_launch_embedding(self):
        job = Mock()
        job.command.return_value = "Would embed 0 chunks"
        refresh.embed_until_done(job, "source", {}, "/gbrain")
        self.assertEqual(job.command.call_count, 1)
        self.assertIn("--dry-run", job.command.call_args.args[1])

    def test_failure_is_not_swallowed(self):
        for responses in ([None], ["unknown"], ["Would embed 1 chunks", None]):
            job = Mock()
            job.command.side_effect = responses
            with self.assertRaises(RuntimeError):
                refresh.embed_until_done(job, "source", {}, "/gbrain")

    def test_stall_and_ceiling_are_failures(self):
        job = Mock()
        job.command.side_effect = ["Would embed 1 chunks", "ok"] * 3
        with self.assertRaisesRegex(RuntimeError, "nessun progresso"):
            refresh.embed_until_done(job, "source", {}, "/gbrain")
        job.command.side_effect = ["Would embed 3 chunks", "ok", "Would embed 2 chunks"]
        with self.assertRaisesRegex(RuntimeError, "limite"):
            refresh.embed_until_done(job, "source", {}, "/gbrain", passes=1)

    def test_source_is_required_and_never_interpolated_into_sql(self):
        for source in ("", "x'; DROP TABLE pages;--", "--all"):
            job = Mock()
            with self.assertRaises(RuntimeError):
                refresh.embed_until_done(job, source, {}, "/gbrain")
            job.command.assert_not_called()

    def test_denied_pins_and_registered_paths_are_excluded(self):
        manifest = {"remote": [{"nameWithOwner": "remote/only"}], "local": [
            {"path": "/root/one", "pin": "denied"},
            {"path": "/root/two"},
            {"path": "/root/three"}]}
        selected, excluded = refresh.scoped_manifest(
            manifest, [{"id": "denied", "local_path": "/root/two"}], {"denied"})
        self.assertEqual(selected, {"remote": [], "local": [{"path": "/root/three"}]})
        self.assertEqual(excluded, ["/root/one", "/root/two"])


if __name__ == "__main__":
    unittest.main()
