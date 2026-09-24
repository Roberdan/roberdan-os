#!/usr/bin/env python3
"""Bounded snapshot parsing, comparable counts, privacy, and append-only publication fixtures."""
from contextlib import redirect_stdout
from copy import deepcopy
import io
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "bin"))
from telemetry_history import END, LIMIT, MARKER, comparison, execute, latest, render, valid, write_report
from telemetry_snapshot import GROUPS, build_snapshot, observation
from telemetry_inventory import TelemetryError


class History(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.findings = self.root / "findings.md"
        self.env = patch.dict(os.environ, {
            "HOME": str(self.root / "PRIVATE_HOME"), "RDA_HOME": str(self.root / "PRIVATE_RDA"),
            "RDA_BUS_HOME": str(self.root / "PRIVATE_BUS"), "RDA_SESSION_STORE": str(self.root / "PRIVATE_DB"),
            "RDA_AUDIT_HOME": str(self.root / "PRIVATE_AUDIT"),
            "RDA_CLAUDE_HISTORY": str(self.root / "PRIVATE_HISTORY"),
            "RDA_TELEMETRY_SKILL_DIRS": str(self.root / "PRIVATE_SKILLS"),
            "RDA_TELEMETRY_FINDINGS": str(self.findings)})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.groups = {key: {field: 2 for field in spec[0].split()} for key, spec in GROUPS.items()}
        self.skills = {
            "inventory": {"unnamed_definitions": 0, "scopes": [
                {"scope": "installate-test", "status": "presente", "definitions": 1}]},
            "sources": {"audit": {"status": "presente", "observed_sessions": 4, "gap_sessions": 1,
                                 "undated_events": 0, "undated_gap_events": 0, "unrecognized_skill_sessions": 0},
                        "session_files": {"status": "presente", "undated_files": 0}},
            "skills": [{"name": "film-director", "aliases": ["director"], "installed": True,
                        "scopes": ["canoniche", "installate-test"], "observed_sessions": 3,
                        "opportunity": {"criteria": [".mp4", ".mov", "remotion"], "candidate_sessions": 4,
                                        "cohort_sessions": 3, "invoked_in_cohort": 2,
                                        "uses_outside_cohort": 1}}]}

    def snapshot(self):
        return build_snapshot(self.root, 7, self.groups, self.skills)

    def block(self, snapshot):
        return f"{MARKER}\n{json.dumps(snapshot)}\n{END}\n".encode()

    def observed_text(self):
        lines = ["TELEMETRIA: conteggi sintetici"]
        for key, values in self.groups.items():
            lines.append("@@RDA_METRIC\t" + key + "\t" +
                         "|".join("null" if value is None else str(value) for value in values.values()))
        lines.append("@@RDA_SKILLS\t" + json.dumps(self.skills))
        return "\n".join(lines)

    def run_report(self, write=False):
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            execute(self.root, 7, str(self.findings), write, self.observed_text())
        return stdout.getvalue()

    def test_first_legacy_and_latest_written_observation(self):
        self.assertIn("prima osservazione", self.run_report())
        self.assertFalse(self.findings.exists())
        self.findings.write_text("# PRIVATE_note\nlegacy report\n")
        self.assertIn("legacy", self.run_report())
        self.run_report(True)
        self.assertIn("conteggi con delta +0", self.run_report())
        with self.findings.open("a") as file:
            file.write("### 2026-09-23 — telemetria del valore (generata da bin/telemetry.sh)\nlegacy\n")
        self.assertIn("ultimo referto legacy", self.run_report())
        self.assertIn("0 conteggi con delta +0", self.run_report())

    def test_positive_negative_zero_counts_without_claiming_value(self):
        self.run_report(True)
        self.groups["bus"]["messages_total"] += 3
        self.groups["mention.jev"]["sessions"] -= 1
        output = self.run_report()
        self.assertIn("bus: messaggi totali +3", output)
        self.assertIn("mention.jev: sessioni -1", output)
        self.assertIn("conteggi con delta +0", output)
        self.assertIn("non valore, bisogno o miglioramento causale", output)
        self.assertIn("nessun metadato affidabile del bisogno", output)

    def test_schema_window_source_policy_and_inventory_mismatch(self):
        current = self.snapshot()
        for key, value, reason in (("schema_version", 0, "schema diverso"), ("days", 30, "finestra diversa"),
                                   ("semantics", "old", "semantica della misura diversa")):
            old = deepcopy(current)
            old[key] = value
            self.assertEqual(comparison(current, old, None)["bus.messages_total"]["reason"], reason)
        with patch.dict(os.environ, {"RDA_BUS_HOME": str(self.root / "OTHER_PRIVATE_BUS")}):
            changed = self.snapshot()
        changes = comparison(changed, current, None)
        self.assertEqual(changes["bus.messages_total"]["reason"], "fonte/perimetro diverso")
        self.assertEqual(changes["mention.jev.sessions"]["delta"], 0)
        old = deepcopy(current)
        old["inventory_policy"] = "0" * 64
        self.assertIn("inventario", comparison(current, old, None)["skill:film-director:observed"]["reason"])
        old = deepcopy(current)
        old["metrics"]["bus.messages_total"]["policy"] = "0" * 64
        self.assertIn("politica", comparison(current, old, None)["bus.messages_total"]["reason"])

    def test_missing_sources_remain_null_and_not_comparable(self):
        previous = self.snapshot()
        self.groups["bus"] = dict.fromkeys(self.groups["bus"])
        self.skills["skills"][0]["observed_sessions"] = None
        current = self.snapshot()
        self.assertIsNone(current["metrics"]["bus.messages_total"]["value"])
        for key in ("bus.messages_total", "skill:film-director:observed"):
            self.assertEqual(comparison(current, previous, None)[key]["reason"],
                             "dati mancanti in una delle osservazioni")

    def test_every_metric_has_denominator_status_and_ratios_keep_cohort(self):
        metrics = self.snapshot()["metrics"]
        self.assertTrue(all("status" in metric["denominator"] for metric in metrics.values()))
        for key in ("bus.messages_total", "mention.jev.sessions", "mention.twin.sessions"):
            self.assertEqual(metrics[key]["denominator"]["status"], "non misurabile")
            self.assertIsNone(metrics[key]["denominator"]["value"])
        numerator = metrics["skill:film-director:invoked_in_cohort"]
        self.assertEqual((numerator["value"], numerator["denominator"]["value"]), (2, 3))
        self.assertEqual(metrics["skill:film-director:observed"]["denominator"]["status"], "non misurabile")
        self.assertEqual(metrics["coverage.bus.agents"]["denominator"]["reason"], "documents")

    def test_latest_bad_marker_never_falls_back_to_older_snapshot(self):
        good = self.block(self.snapshot())
        for tail in (f"{MARKER}\n{{broken\n-->\n", f"{MARKER}\n",
                     "<!-- rda-telemetry-snapshot:v0\n{}\n-->\n",
                     f"{MARKER}\n{{\"schema_version\":1,\"schema_version\":1}}\n-->\n"):
            old, reason = latest(io.BytesIO(good + tail.encode()))
            self.assertIsNone(old)
            self.assertTrue(reason)
        old, reason = latest(io.BytesIO(good + f"{MARKER}\n".encode() + b"x" * (LIMIT + 1) + b"\n-->\n"))
        self.assertIsNone(old)
        self.assertIn("limite", reason)

    def test_ordinary_markdown_and_hostile_prior_text_are_never_rendered(self):
        current = self.snapshot()
        hostile = b"PRIVATE_SECRET <script>alert(1)</script> \x1b[2J $(touch nope)\n"
        self.findings.write_bytes(hostile + self.block(current) + b"# ordinary later note\n" + hostile)
        output = self.run_report()
        self.assertIn("conteggi con delta +0", output)
        for sentinel in ("PRIVATE_", "<script>", "\x1b[2J", "$(touch", str(self.root)):
            self.assertNotIn(sentinel, output)
        broken = deepcopy(current)
        broken["metrics"]["bus.messages_total"]["value"] = "PRIVATE_SECRET\x1b[2J"
        self.findings.write_bytes(self.block(current) + self.block(broken))
        output = self.run_report()
        self.assertIn("snapshot malformato", output)
        self.assertNotIn("PRIVATE_", output)

    def test_write_appends_same_report_and_structured_measurement_once(self):
        prefix = b"PRIVATE_ORIGINAL retained\n"
        self.findings.write_bytes(prefix)
        output = self.run_report(True)
        saved = self.findings.read_bytes()
        self.assertTrue(saved.startswith(prefix))
        report = output.removesuffix("\nreferto aggiunto alla destinazione configurata\n").rstrip("\n")
        self.assertEqual(saved.decode().split("```\n")[1].rstrip("\n"), report)
        previous, reason = latest(io.BytesIO(saved))
        self.assertIsNone(reason)
        self.assertEqual(previous["metrics"], self.snapshot()["metrics"])
        self.assertEqual(saved.count(MARKER.encode()), 1)
        snapshot_text = json.dumps(previous)
        self.assertNotIn("PRIVATE_", snapshot_text)
        self.assertNotIn(str(self.root), snapshot_text)
        self.assertTrue(valid(previous))

    def test_source_tokens_do_not_depend_on_count_updates(self):
        before = self.snapshot()
        self.groups["bus"]["messages_total"] += 1
        self.skills["skills"][0]["observed_sessions"] += 1
        after = self.snapshot()
        self.assertEqual(before["inventory_policy"], after["inventory_policy"])
        for key in before["metrics"]:
            self.assertEqual(before["metrics"][key]["scope"], after["metrics"][key]["scope"])
        self.assertEqual(comparison(after, before, None)["skill:film-director:observed"]["delta"], 1)

    def test_append_failure_rolls_back_and_does_not_print_success(self):
        self.findings.write_text("ORIGINAL\n")
        with self.findings.open("r+b") as file:
            with patch("telemetry_history.os.fsync", side_effect=[OSError("full"), None]):
                with self.assertRaises(OSError):
                    write_report(file, b"partial_snapshot")
        self.assertEqual(self.findings.read_text(), "ORIGINAL\n")
        with patch("telemetry_history.write_report", side_effect=OSError("PRIVATE_failure")):
            stdout = io.StringIO()
            with redirect_stdout(stdout), self.assertRaises(OSError):
                execute(self.root, 7, str(self.findings), True, self.observed_text())
            self.assertEqual(stdout.getvalue(), "")

    def test_observation_requires_complete_single_measurement(self):
        text, groups, skills = observation(self.observed_text())
        self.assertEqual(text, "TELEMETRIA: conteggi sintetici")
        self.assertEqual(groups, self.groups)
        self.assertEqual(skills, self.skills)
        with self.assertRaises(TelemetryError):
            observation(self.observed_text() + "\n@@RDA_METRIC\tevolve\t1")
        with self.assertRaises(TelemetryError):
            observation("report without measurements")

    def test_real_shell_second_write_and_source_mismatch(self):
        for directory in ("agents", "skills"):
            shutil.copytree(ROOT / directory, self.root / directory)
        shutil.copyfile(ROOT / "AGENTS.md", self.root / "AGENTS.md")
        (self.root / "bin").mkdir()
        (self.root / "kanban").mkdir()
        for file in (ROOT / "bin").glob("telemetry*"):
            shutil.copyfile(file, self.root / "bin" / file.name)
        for name in ("audit_schema.py", "audit_store.py", "audit_skills.py", "audit_skill_names.json"):
            shutil.copyfile(ROOT / "kanban" / name, self.root / "kanban" / name)
        bus = Path(os.environ["RDA_BUS_HOME"]) / "PRIVATE_PROJECT"
        bus.mkdir(parents=True)
        (bus / "messages.jsonl").write_text('{"from":"test","body":"PRIVATE_BODY"}\n')
        with sqlite3.connect(os.environ["RDA_SESSION_STORE"]) as db:
            db.execute("CREATE TABLE sessions(id TEXT, repository TEXT, created_at TEXT, updated_at TEXT)")
            db.execute("CREATE TABLE turns(session_id TEXT, timestamp TEXT, user_message TEXT, assistant_response TEXT)")
            db.execute("INSERT INTO turns VALUES('PRIVATE_SESSION',datetime('now'),'jev.py PRIVATE_BODY','')")
        db.close()
        command = ["bash", str(self.root / "bin/telemetry.sh"), "--days", "7", "--write"]
        first = subprocess.run(command, capture_output=True, text=True, timeout=15)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertIn("prima osservazione", first.stdout)
        prefix = self.findings.read_bytes()
        (bus / "messages.jsonl").write_text('{"from":"test"}\n' * 3)
        with sqlite3.connect(os.environ["RDA_SESSION_STORE"]) as db:
            db.execute("DELETE FROM turns")
        db.close()
        second = subprocess.run(command, capture_output=True, text=True, timeout=15)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertIn("bus: messaggi totali +2", second.stdout)
        self.assertIn("mention.jev: sessioni -1", second.stdout)
        self.assertIn("conteggi con delta +0", second.stdout)
        appended = self.findings.read_bytes()[len(prefix):].decode()
        rendered = second.stdout.removesuffix("\nreferto aggiunto alla destinazione configurata\n").rstrip()
        rendered = re.sub(r"\x1b\[[0-9;]*m", "", rendered)
        self.assertEqual(appended.split("```\n")[1].rstrip(), rendered)
        self.assertNotIn("PRIVATE_", appended)
        self.assertNotIn(str(self.root), appended)
        with patch.dict(os.environ, {"RDA_BUS_HOME": str(self.root / "OTHER_BUS")}):
            third = subprocess.run(command[:-1], capture_output=True, text=True, timeout=15)
        self.assertEqual(third.returncode, 0, third.stderr)
        self.assertIn("Non confrontabile", third.stdout)
        self.assertIn("fonte/perimetro diverso", third.stdout)
        self.assertEqual(self.findings.read_bytes()[:len(prefix)], prefix)

    def test_compact_skill_rows_keep_all_deltas_and_group_unknowns(self):
        current = self.snapshot()
        old = deepcopy(current)
        expected = {"observed": 2, "candidate_sessions": -1, "cohort_sessions": 0,
                    "invoked_in_cohort": 1, "uses_outside_cohort": -1}
        for field, delta in expected.items():
            old["metrics"]["skill:film-director:" + field]["value"] -= delta
        output = render(current, comparison(current, old, None))
        rows = [line for line in output.splitlines() if line.startswith("  skill:")]
        self.assertEqual(len(rows), 1)
        for expected_text in ("osservate +2", "candidate -1", "coorte +0",
                              "usi in coorte +1", "fuori coorte -1", "rapporto 2/3",
                              "delta +33.3 punti percentuali"):
            self.assertIn(expected_text, rows[0])
        for field in expected:
            if field != "observed":
                current["metrics"]["skill:film-director:" + field]["value"] = None
                current["metrics"]["skill:film-director:" + field]["denominator"] = {
                    "value": None, "status": "non misurabile", "reason": "unmapped"}
        unchanged = deepcopy(current)
        output = render(current, comparison(current, unchanged, None))
        rows = [line for line in output.splitlines() if line.startswith("  skill:")]
        self.assertEqual(len(rows), 0)
        self.assertIn("Invariate nelle misure confrontabili: 17 voci, 53 conteggi con delta +0.", output)
        self.assertIn("dati mancanti in una delle osservazioni — 1 voce", output)
        self.assertEqual(output.count("nessun criterio di occasione per questa skill"), 1)
        legacy = render(current, comparison(current, None, "prima osservazione legacy"))
        self.assertEqual(legacy.count("prima osservazione legacy"), 1)
        self.assertNotIn("  skill:", legacy)
        self.assertIn("prima osservazione legacy — 17 voci", legacy)
        self.assertEqual(current, unchanged)
        current["metrics"]["skill:film-director:observed"]["value"] = None
        current["metrics"]["skill:film-director:candidate_sessions"]["value"] = 4
        unchanged["metrics"]["skill:film-director:candidate_sessions"]["value"] = 3
        output = render(current, comparison(current, unchanged, None))
        self.assertIn("candidate +1", output)
        self.assertIn("osservate e occasioni non confrontabile", output)


if __name__ == "__main__":
    unittest.main(verbosity=2)
