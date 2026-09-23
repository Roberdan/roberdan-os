#!/usr/bin/env python3
"""Isolated identity, observation, cohort, availability, and confidentiality fixtures."""
from contextlib import closing, redirect_stdout
from datetime import datetime, timezone
import io
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "bin"))
from telemetry_skills import build_report, render
from telemetry_inventory import inventory
from audit_schema import native, manual
from audit_store import append

NOW = datetime(2026, 9, 23, 12, tzinfo=timezone.utc)
RECENT = "2026-09-22T10:00:00Z"


class SkillTelemetry(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root, self.installed = self.base / "repo", self.base / "installed"
        self.db = self.base / "session.db"
        self.environment = patch.dict(os.environ, {
            "HOME": str(self.base / "home"), "RDA_HOME": str(self.base / "rda"),
            "RDA_AUDIT_HOME": str(self.base / "audit"), "RDA_SESSION_STORE": str(self.db),
            "RDA_TELEMETRY_SKILL_DIRS": str(self.installed),
            "RDA_TELEMETRY_FINDINGS": str(self.base / "findings.md"),
        })
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.sequence = 0
        self.manifest(self.root / "skills/film-director", "film-director", ["director"])
        self.manifest(self.root / "skills/not-installed", "not-installed")
        self.manifest(self.root / ".github/skills/twin", "roberdan-twin")
        for name in ("film-director", "director", "pptx", "docx", "xlsx", "pdf", "qa"):
            self.manifest(self.installed / name, name)
        with closing(sqlite3.connect(self.db)) as db, db:
            db.execute("CREATE TABLE session_files(session_id TEXT, file_path TEXT, first_seen_at TEXT)")
            db.execute("CREATE TABLE turns(session_id TEXT, user_message TEXT, timestamp TEXT)")
            db.execute("INSERT INTO turns VALUES ('PRIVATE_session', 'PRIVATE_prompt film-director', ?)", (RECENT,))

    def manifest(self, directory, name, aliases=()):
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "SKILL.md").write_text(
            f"---\nname: {name}\naliases: {json.dumps(list(aliases))}\n---\n", encoding="utf-8")

    def event(self, session, skill=None, host="copilot", when=RECENT, event_type="tool.execution_start"):
        self.sequence += 1
        data = {"toolCallId": f"call-{self.sequence}", "toolName": "skill" if skill else "bash"}
        if skill:
            data["arguments"] = {"skill": skill}
        append(native(host, {"session_id": session, "id": f"event-{self.sequence}",
                             "timestamp": when, "type": event_type, "data": data}))

    def file(self, session, filename, when=RECENT):
        with closing(sqlite3.connect(self.db)) as db, db:
            db.execute("INSERT INTO session_files VALUES (?,?,?)", (session, filename, when))

    def report(self):
        return build_report(self.root, 7, NOW)

    def row(self, name, report=None):
        return next(row for row in (report or self.report())["skills"] if row["name"] == name)

    def output(self, report):
        output = io.StringIO()
        with redirect_stdout(output):
            render(report)
        return output.getvalue()

    def assert_private(self, output):
        for forbidden in ("PRIVATE_", str(self.base), "session_id", "user_message"):
            self.assertNotIn(forbidden, output)

    def cli(self):
        return subprocess.run([sys.executable, "-B", str(ROOT / "bin/telemetry_skills.py"),
                               "--root", str(self.root), "--days", "9999", "--json"],
                              capture_output=True, text=True, timeout=15)

    def test_inventory_deduplicates_names_aliases_packages_and_symlinks(self):
        (self.installed / "same").symlink_to(self.installed / "film-director", target_is_directory=True)
        (self.installed / "cycle").symlink_to(self.installed, target_is_directory=True)
        self.manifest(self.root / "skills/optional/nested", "nested")
        self.manifest(self.installed / "namespace", "rdos-nested")
        with (self.installed / "namespace/SKILL.md").open("a") as file:
            file.write("Canonical logic: read `skills/optional/nested/skill.md` in roberdan-os.\n"
                       "<!-- roberdan-os: namespaced install (skill-name collision) -->\n")
        catalog = inventory(self.root)
        names = [row["name"] for row in catalog["skills"]]
        self.assertEqual(names.count("film-director"), 1)
        self.assertNotIn("director", names)
        self.assertIn("roberdan-twin", names)
        self.assertEqual(catalog["aliases"]["rdos-nested"], "nested")
        film = next(row for row in catalog["skills"] if row["name"] == "film-director")
        self.assertEqual(film["scopes"], ["canoniche", "installate-1"])
        self.assert_private(json.dumps(catalog))

    def test_named_starts_and_ratio_share_host_time_and_opportunity_cohort(self):
        self.event("PRIVATE_A", "director")
        self.event("PRIVATE_A", "film-director")
        self.event("PRIVATE_B")
        self.event("PRIVATE_C", "film-director")
        self.event("PRIVATE_A", "film-director", host="claude", event_type="PreToolUse")
        self.event("PRIVATE_old", "film-director", when="2026-09-01T00:00:00Z")
        self.event("PRIVATE_future", "film-director", when="2026-09-24T00:00:00Z")
        self.event("PRIVATE_discovery", "film-director", event_type="session.skills_loaded")
        self.event("PRIVATE_B", event_type="observer.gap")
        self.file("PRIVATE_A", "/PRIVATE_dir/film.MP4")
        self.file("PRIVATE_A", "/PRIVATE_dir/another.mov")
        self.file("PRIVATE_B", "/PRIVATE_dir/remotion/scene.tsx")
        self.file("PRIVATE_discovery", "/PRIVATE_dir/unused.mp4")
        self.file("PRIVATE_C", "/PRIVATE_dir/old.mp4", "2026-09-01T00:00:00Z")
        report = self.report()
        film = self.row("film-director", report)
        self.assertEqual(film["observed_sessions"], 3)
        self.assertEqual(film["opportunity"], {
            "criteria": [".mp4", ".mov", "remotion"], "candidate_sessions": 3,
            "cohort_sessions": 2, "invoked_in_cohort": 1, "uses_outside_cohort": 2,
            "status": "misurabile", "reason": None})
        self.assertEqual(report["sources"]["audit"]["gap_sessions"], 1)
        self.assert_private(json.dumps(report) + self.output(report))

    def test_file_predicates_and_utc_window_do_not_classify_prompt_text(self):
        self.event("PRIVATE_files")
        for extension in ("pptx", "docx", "xlsx", "pdf"):
            self.file("PRIVATE_files", "/PRIVATE_dir/file." + extension.upper(),
                      "2026-09-15T23:30:00-02:00")
            row = self.row(extension)
            self.assertEqual(row["opportunity"]["candidate_sessions"], 1)
            self.assertEqual(row["opportunity"]["invoked_in_cohort"], 0)
            self.assertEqual(row["opportunity"]["cohort_sessions"], 1)
        self.file("PRIVATE_files", "/PRIVATE_dir/remotion.config.ts")
        self.assertEqual(self.row("film-director")["opportunity"]["candidate_sessions"], 1)
        self.assertEqual(self.row("film-director")["observed_sessions"], 0)
        self.assertIn("zero osservato NON significa mai usata", self.output(self.report()))

    def test_unmapped_missing_install_and_missing_observer_are_not_zero_use(self):
        report = self.report()
        self.assertIsNone(self.row("film-director", report)["observed_sessions"])
        self.assertEqual(report["sources"]["audit"]["status"], "assente")
        self.event("PRIVATE_other")
        report = self.report()
        self.assertEqual(self.row("qa", report)["opportunity"]["status"], "non misurabile")
        self.assertIsNone(self.row("not-installed", report)["observed_sessions"])
        self.assertIn("installazione non osservata", self.output(report))
        self.assertNotIn("0/0", self.output(report))

    def test_discovery_manual_load_and_undated_events_are_not_invocations(self):
        request = append(manual("request", {"id": "request", "summary": "Synthetic request"}))
        append(manual("skill_load", {"request_id": request["id"], "summary": "film-director"}))
        self.event("PRIVATE_discovery", "film-director", event_type="session.skills_loaded")
        self.event("PRIVATE_undated", "film-director", when=None)
        self.event("PRIVATE_gap", event_type="observer.gap", when=None)
        report = self.report()
        self.assertIsNone(self.row("film-director", report)["observed_sessions"])
        self.assertEqual(report["sources"]["audit"]["undated_events"], 2)
        self.assertEqual(report["sources"]["audit"]["undated_gap_events"], 1)
        self.assertIn("non attribuibili alla finestra", self.output(report))

    def test_missing_metadata_is_unmeasurable_not_a_zero_denominator(self):
        self.event("PRIVATE_use", "film-director")
        with closing(sqlite3.connect(self.db)) as db, db:
            db.execute("DROP TABLE session_files")
        row = self.row("film-director")
        self.assertEqual(row["observed_sessions"], 1)
        self.assertIsNone(row["opportunity"]["candidate_sessions"])
        self.assertIn("session_files assenti", row["opportunity"]["reason"])
        self.db.unlink()
        self.assertIn("storico Copilot assente", self.row("film-director")["opportunity"]["reason"])
        self.assertFalse(self.db.exists())

    def test_unobserved_candidate_is_not_added_to_observed_denominator(self):
        self.event("PRIVATE_outside", "film-director")
        self.file("PRIVATE_unobserved", "/PRIVATE_file.mp4")
        row = self.row("film-director")["opportunity"]
        self.assertEqual((row["candidate_sessions"], row["cohort_sessions"], row["uses_outside_cohort"]), (1, 0, 1))
        self.assertEqual(row["status"], "non misurabile")
        self.assertNotIn("1/0", self.output(self.report()))

    def test_twin_declared_aliases_only_affect_identity_not_decision_rates(self):
        self.event("PRIVATE_twin", "roberto-twin")
        row = self.row("roberdan-twin")
        self.assertEqual(row["observed_sessions"], 1)
        self.assertEqual(row["opportunity"]["status"], "non misurabile")
        self.assertIn("rdos-roberdan-twin", row["aliases"])

    def test_corrupt_present_sources_fail_explicitly_without_content_or_paths(self):
        self.db.write_bytes(b"PRIVATE_not_sqlite")
        result = self.cli()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("non misurabili", result.stderr)
        self.assert_private(result.stdout + result.stderr)
        self.assertEqual(result.stdout, "")

    def test_bad_schema_dates_and_audit_are_not_silent_empty_data(self):
        with closing(sqlite3.connect(self.db)) as db, db:
            db.execute("DROP TABLE session_files")
            db.execute("CREATE TABLE session_files(wrong TEXT)")
        self.assertNotEqual(self.cli().returncode, 0)
        with closing(sqlite3.connect(self.db)) as db, db:
            db.execute("DROP TABLE session_files")
            db.execute("CREATE TABLE session_files(session_id TEXT, file_path TEXT, first_seen_at TEXT)")
        self.file("PRIVATE_invalid", "/PRIVATE_file.mp4", "PRIVATE_bad_date")
        result = self.cli()
        self.assertNotEqual(result.returncode, 0)
        self.assert_private(result.stderr)
        self.event("PRIVATE_audit")
        audit = self.base / "audit/events.sqlite3"
        audit.write_bytes(b"PRIVATE_broken_audit")
        result = self.cli()
        self.assertNotEqual(result.returncode, 0)
        self.assert_private(result.stderr)

    def test_default_host_scope_missing_is_not_reported_as_zero_definitions(self):
        os.environ.pop("RDA_TELEMETRY_SKILL_DIRS")
        catalog = inventory(self.root)
        missing = [scope for scope in catalog["scopes"] if scope["scope"].startswith("installate-")]
        self.assertEqual(len(missing), 4)
        self.assertTrue(all(scope["status"] == "assente" and scope["definitions"] is None for scope in missing))
        self.assertFalse((self.base / "home").exists())

    def test_cli_is_count_only_and_read_only(self):
        self.event("PRIVATE_A", "film-director")
        self.file("PRIVATE_A", "/PRIVATE_film.mp4")
        before = {path: path.read_bytes() for path in (self.db, self.base / "audit/events.sqlite3")}
        result = self.cli()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["schema_version"], 1)
        self.assert_private(result.stdout + result.stderr)
        self.assertTrue(all(path.read_bytes() == data for path, data in before.items()))
        self.assertFalse((self.base / "findings.md").exists())

    def test_missing_manifest_names_and_invalid_inventory_are_not_silent(self):
        unknown = self.installed / "PRIVATE_unknown"
        unknown.mkdir()
        (unknown / "SKILL.md").write_text("No declared name\n")
        report = self.report()
        self.assertEqual(report["inventory"]["unnamed_definitions"], 1)
        self.assert_private(json.dumps(report) + self.output(report))
        (unknown / "SKILL.md").write_text("---\nname: /PRIVATE_invalid/name\n---\n")
        result = self.cli()
        self.assertNotEqual(result.returncode, 0)
        self.assert_private(result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
