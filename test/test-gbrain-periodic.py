#!/usr/bin/env python3
"""Offline regression tests; no production database, embeddings or worker startup."""
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import Mock, patch


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).resolve().parents[1] / "bin" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


recovery = load("recovery", "gbrain-recover-repos.py")
periodic = load("periodic", "gbrain-refresh-active.py")


class RefreshTests(unittest.TestCase):
    def refresh(self, old="abc", new="abc", preview="Already up to date",
                before=None, after=None):
        runner = object.__new__(recovery.Recovery)
        runner.head = Mock(return_value=new)
        runner.command = Mock(side_effect=[preview, "sync complete"])
        runner.rename_proof = None
        runner.full_sync_proofs = None
        self.runner = runner
        with patch.object(recovery, "active_pages",
                          side_effect=[{1} if before is None else before,
                                       {1} if after is None else after]), \
                patch.object(recovery, "sources", side_effect=[
                    [{"id": "test", "last_commit": old}],
                    [{"id": "test", "last_commit": new}]]):
            return runner.refresh("test", Path("/unused"), False)

    def test_revision_proof_comes_from_a_verified_receipt_bound_to_that_revision(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            receipt = home / ".roberdan-os/gbrain-upgrade/last-install.json"
            receipt.parent.mkdir(parents=True)
            self.assertFalse(periodic.revision_is_proven("f" * 40, home))
            for status, revision, proven in (("verified", "f" * 40, True), ("unverified", "f" * 40, False),
                                             ("verified", "e" * 40, False)):
                receipt.write_text(json.dumps({"status": status, "revision": revision}))
                self.assertIs(periodic.revision_is_proven("f" * 40, home), proven, (status, revision))
            receipt.write_text("not json")
            self.assertFalse(periodic.revision_is_proven("f" * 40, home))
        self.assertTrue(periodic.revision_is_proven("31f257a0a7b218b40e03d302bc6913c99f26f0ec", home))

    def test_noop_records_live_revisions(self):
        row = self.refresh()
        self.assertEqual(row["indexed_before"], "abc")
        self.assertEqual(row["indexed_after"], "abc")
        self.assertFalse(row["sync_changed"])
        self.assertEqual(periodic.verified_refresh_result(row)[0], "INVARIATO")

    def test_real_revision_change(self):
        row = self.refresh(old="abc", new="def", preview="Sync dry run: abc..def")
        self.assertTrue(row["sync_changed"])
        state, detail = periodic.verified_refresh_result(row)
        self.assertEqual(state, "ESEGUITO")
        self.assertIn("abc -> def", detail)

    def test_added_pages_measured_even_without_revision_change(self):
        self.assertTrue(self.refresh(after={1, 2})["sync_changed"])

    def test_vector_only_change(self):
        row = self.refresh()
        row["embedded_chunks"] = 3
        self.assertEqual(periodic.verified_refresh_result(row)[0], "ESEGUITO")

    def test_deletions_and_renames_remain_blocked(self):
        for preview in ("Deleted: old.py", "Removed: old.py", "Renamed: a.py -> b.py"):
            with self.subTest(preview=preview), self.assertRaisesRegex(RuntimeError, "BLOCKED"):
                self.refresh(preview=preview)
            self.assertEqual(self.runner.command.call_count, 1)

    def test_reconciliation_remains_blocked(self):
        with self.assertRaisesRegex(RuntimeError, "requires reconciliation"):
            self.refresh(preview="Full-sync dry run: chunker_version gate")
        self.assertEqual(self.runner.command.call_count, 1)

    def test_retention_failure_is_not_success(self):
        with self.assertRaisesRegex(RuntimeError, "RETENTION FAILURE"):
            self.refresh(after=set())

    def test_missing_revision_evidence_is_not_noop(self):
        state, detail = periodic.verified_refresh_result({"status": "verified"})
        self.assertEqual(state, "RINVIATO")
        self.assertIn("senza misure prima/dopo", detail)

    def test_partial_revision_evidence_is_not_noop(self):
        row = self.refresh()
        for field in ("sync_changed", "indexed_before", "indexed_after"):
            with self.subTest(field=field):
                partial = {key: value for key, value in row.items() if key != field}
                self.assertEqual(periodic.verified_refresh_result(partial)[0], "RINVIATO")

    def test_current_run_receipt_can_report_noop(self):
        row = dict(self.refresh(), started=200)
        self.assertEqual(periodic.verified_refresh_result(row, run_started=199)[0], "INVARIATO")

    def test_partial_failure_preserves_error_and_reports_remaining_old_receipts(self):
        manifest = {"remote": [], "local": [
            {"path": "/a-failed"}, {"path": "/b-legacy"}, {"path": "/c-prior-run"}]}
        error = "RETENTION FAILURE: 1 prior pages no longer active; stop recovery."
        with tempfile.TemporaryDirectory() as tmp:
            runner = recovery.Recovery(manifest, Path(tmp), Path(tmp) / "unused-backup")
            runner.state["repos"] = {
                "local:/b-legacy": {"status": "verified", "snapshot": "abc"},
                "local:/c-prior-run": {"status": "verified", "started": 1,
                                       "sync_changed": False, "indexed_before": "abc",
                                       "indexed_after": "abc"}}
            runner.save()
            with patch.object(runner, "validate_backup"), \
                    patch.object(recovery, "sources", return_value=[]), \
                    patch.object(runner, "checkout", return_value=Path("/unused")), \
                    patch.object(runner, "source_for", return_value=("test", False)), \
                    patch.object(runner, "refresh", side_effect=RuntimeError(error)):
                self.assertEqual(runner.run(), 1)
            job = Mock()
            periodic.report_recovery_results(job, recovery.plan(manifest), runner.state)
        calls = [call.args for call in job.row.call_args_list]
        self.assertEqual(len(calls), 3)
        self.assertEqual(calls[0], ("ERRORE", "a-failed", error))
        self.assertEqual(calls[1][:2], ("RINVIATO", "b-legacy"))
        self.assertIn("senza misure prima/dopo", calls[1][2])
        self.assertEqual(calls[2][:2], ("RINVIATO", "c-prior-run"))
        self.assertIn("non verificata in questo giro", calls[2][2])


class EmbeddingTests(unittest.TestCase):
    @staticmethod
    def scripted_job(*steps):
        job = Mock()
        job.commands = []
        sequence = iter(steps)

        def command(*_args, **_kwargs):
            output, exit_code = next(sequence)
            job.commands.append({"exit": exit_code})
            return output

        job.command.side_effect = command
        return job

    def test_zero_chunks_does_not_run_embed(self):
        job = Mock()
        job.command.return_value = "Would embed 0 stale chunks"
        self.assertEqual(periodic.embed_until_done(job, "test", {}, "/gbrain"), 0)
        self.assertEqual(job.command.call_count, 1)
        self.assertIn("--dry-run", job.command.call_args.args[1])

    def test_reports_measured_vector_change(self):
        job = self.scripted_job(
            ("Would embed 3 stale chunks", 0),
            ("embedded", 0),
            ("Would embed 0 stale chunks", 0),
        )
        self.assertEqual(periodic.embed_until_done(job, "test", {}, "/gbrain"), 3)
        for call in job.command.call_args_list:
            argv = call.args[1]
            self.assertEqual(argv[argv.index("--source") + 1], "test")

    def test_transient_ollama_disconnect_is_retried(self):
        disconnect = (
            "Error embedding one: [embed(ollama:bge-m3)] "
            "Cannot connect to API: Unable to connect"
        )
        job = self.scripted_job(
            ("Would embed 3 stale chunks", 0),
            (disconnect, 1),
            ("embedded", 0),
            ("Would embed 0 stale chunks", 0),
        )
        with patch.object(periodic.time, "sleep") as sleep:
            self.assertEqual(periodic.embed_until_done(job, "test", {}, "/gbrain"), 3)
        sleep.assert_called_once_with(5)
        self.assertEqual(job.command.call_count, 4)
        self.assertIn("ok", job.command.call_args_list[1].kwargs)
        self.assertNotIn("change", job.command.call_args_list[1].kwargs)
        job.row.assert_called_once()

    def test_retry_exhaustion_is_error(self):
        disconnect = ("Error embedding one: [embed(ollama:bge-m3)] "
                      "Cannot connect to API: Unable to connect")
        job = self.scripted_job(
            ("Would embed 3 stale chunks", 0),
            *((disconnect, 1) for _ in range(4)),
        )
        with patch.object(periodic.time, "sleep") as sleep, \
                self.assertRaisesRegex(RuntimeError, "Indicizzazione locale fallita"):
            periodic.embed_until_done(job, "test", {}, "/gbrain")
        self.assertEqual([call.args[0] for call in sleep.call_args_list], [5, 10, 15])
        job.row.assert_called_once()
        self.assertEqual(job.row.call_args.args[0], "ERRORE")

    def test_non_connectivity_failure_is_not_retried(self):
        job = self.scripted_job(
            ("Would embed 3 stale chunks", 0),
            ("Error embedding one: invalid embedding dimensions", 1),
        )
        with patch.object(periodic.time, "sleep") as sleep, \
                self.assertRaisesRegex(RuntimeError, "Indicizzazione locale fallita"):
            periodic.embed_until_done(job, "test", {}, "/gbrain")
        sleep.assert_not_called()
        job.row.assert_called_once()
        self.assertIn("invalid embedding dimensions", job.row.call_args.args[2])

    def test_exit_one_without_chunk_error_is_not_success(self):
        job = self.scripted_job(
            ("Would embed 3 stale chunks", 0),
            ("Projection recovery requires a working embedding provider.", 1),
        )
        with patch.object(periodic.time, "sleep") as sleep, \
                self.assertRaisesRegex(RuntimeError, "Indicizzazione locale fallita"):
            periodic.embed_until_done(job, "test", {}, "/gbrain")
        sleep.assert_not_called()
        job.row.assert_called_once_with(
            "ERRORE", "Indicizzazione locale test",
            "Projection recovery requires a working embedding provider.")

    def test_stalls_are_errors(self):
        job = self.scripted_job(
            ("Would embed 3 stale chunks", 0),
            ("embedded", 0),
            ("Would embed 3 stale chunks", 0),
            ("embedded", 0),
            ("Would embed 3 stale chunks", 0),
        )
        with self.assertRaisesRegex(RuntimeError, "nessun progresso"):
            periodic.embed_until_done(job, "test", {}, "/gbrain")

    def test_bad_measurement_is_error(self):
        job = Mock()
        job.command.return_value = "unknown output"
        with self.assertRaisesRegex(RuntimeError, "non riconoscibile"):
            periodic.embed_until_done(job, "test", {}, "/gbrain")


class ScheduleTests(unittest.TestCase):
    def test_installed_schedule_and_safety_flags(self):
        home = Path.home()
        plist = home / "Library/LaunchAgents/com.roberdan.gbrain-refresh-code.plist"
        if not plist.exists():
            self.skipTest("launchd job not installed on this machine (e.g. CI)")
        with plist.open("rb") as f:
            config = plistlib.load(f)
        self.assertEqual(config["StartInterval"], 3 * 60 * 60)
        self.assertNotIn("StartCalendarInterval", config)
        self.assertFalse(config["RunAtLoad"])
        # Background jobs run only on AC power (2026-10-07). The gate sits in
        # front of the real command, as the on-ac wrapper or as the inline
        # /bin/sh -c pmset form; either is required, then skipped here.
        args = list(config["ProgramArguments"])
        gated = False
        if args and args[0].endswith("/on-ac"):
            args, gated = args[1:], True
        elif args[:2] == ["/bin/sh", "-c"] and len(args) > 2 and "AC Power" in args[2]:
            args, gated = args[3:], True
        self.assertTrue(gated, "the refresh must start only on AC power")
        launcher_path = next(
            Path(arg)
            for arg in args
            if Path(arg).name == "gbrain-refresh-code"
        )
        launcher = launcher_path.read_text()
        for flag in ("--require-ac", "--blocked-source vault",
                     "--blocked-source gstack-code-roberdan-os-67e84638"):
            self.assertIn(flag, launcher)
        self.assertIn("gbrain-upgrade/last-install.json", launcher)
        self.assertIn('with_name("state.json")', launcher)
        self.assertIn('GBRAIN_MAX_CHUNK_TOKENS="${GBRAIN_MAX_CHUNK_TOKENS:-1500}"', launcher)
        self.assertNotIn("260920-active-validation", launcher)

    def test_exclusions_preserved(self):
        manifest = {"local": [{"path": "/a", "pin": "denied"}, {"path": "/b"}]}
        scoped, excluded = periodic.scoped_manifest(manifest, [], {"denied"})
        self.assertEqual(scoped["local"], [{"path": "/b"}])
        self.assertEqual(excluded, ["/a"])


if __name__ == "__main__":
    unittest.main()
