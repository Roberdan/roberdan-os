#!/usr/bin/env python3
"""Native invocation cohorts, terminal correlation, source separation and privacy."""
from contextlib import closing, redirect_stdout
from copy import deepcopy
from datetime import datetime, timezone
import io
import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "bin"))
from telemetry_native import observations, render
from telemetry_skills import build_report
from telemetry_inventory import TelemetryError
from telemetry_snapshot import GROUPS, build_snapshot
from telemetry_history import comparison, valid
from audit_schema import native
from audit_store import append

NOW = datetime(2026, 10, 12, 8, 0, tzinfo=timezone.utc)
RECENT = "2026-10-11T10:00:00Z"
ALIASES = {"film-director": "film-director", "rdos-film-director": "film-director"}
PUBLIC = set(ALIASES)


class NativeTelemetry(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / "events"
        self.env = patch.dict(os.environ, {
            "HOME": str(self.root / "home"), "RDA_HOME": str(self.root / "rda"),
            "RDA_COPILOT_EVENT_HOME": str(self.home),
            "RDA_AUDIT_HOME": str(self.root / "audit"),
            "RDA_SESSION_STORE": str(self.root / "sessions.db"),
        })
        self.env.start()
        self.addCleanup(self.env.stop)
        os.environ.pop("RDA_TELEMETRY_SKILL_DIRS", None)
        self.counter = 0

    def event(self, kind, call="call", when=RECENT, session="PRIVATE_session", **data):
        self.counter += 1
        raw = {"id": f"event-{self.counter}", "type": kind, "timestamp": when,
               "data": {"toolCallId": call, **data}}
        self.write(raw, session)
        return raw

    def write(self, raw, session="PRIVATE_session"):
        path = self.home / session / "events.jsonl"
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a") as stream:
            stream.write(json.dumps(raw) + "\n")

    def read(self):
        return observations(
            datetime(2026, 10, 5, tzinfo=timezone.utc).timestamp(),
            NOW.timestamp(), ALIASES, PUBLIC)

    def test_starts_terminal_cohort_cancellation_and_missing_success(self):
        self.event("tool.execution_start", toolName="skill",
                   arguments={"skill": "film-director", "prompt": "PRIVATE_prompt"})
        self.event("tool.execution_complete", success=True, result="PRIVATE_result")
        self.event("tool.execution_start", "failure", toolName="functions.skill",
                   arguments={"skill": "rdos-film-director"})
        self.event("tool.execution_complete", "failure", success=False)
        self.event("tool.execution_start", "unknown", toolName="skill",
                   arguments={"skill": "film-director"})
        self.event("tool.execution_complete", "unknown")
        self.event("tool.execution_start", "pending", toolName="skill",
                   arguments={"skill": "film-director"})
        self.event("subagent.started", "agent", agentName="thor")
        self.event("subagent.completed", "agent", cancelled=True)
        self.event("subagent.completed", "orphan")
        uses, report = self.read()
        self.assertEqual(uses["film-director"], {("copilot", "PRIVATE_session")})
        self.assertEqual(report["skills"]["film-director"],
                         {"starts": 4, "succeeded": 1, "failed": 1, "unknown": 1, "pending": 1})
        self.assertEqual(report["agents"]["thor"]["failed"], 1)
        self.assertEqual(report["metadata"]["orphan_terminals"], 1)
        self.assertEqual(report["totals"]["agents"]["starts"], 1)
        output = io.StringIO()
        with redirect_stdout(output):
            render(report)
        for forbidden in ("PRIVATE_", str(self.root), "prompt", "result"):
            self.assertNotIn(forbidden, json.dumps(report) + output.getvalue())
        self.assertIn("non misurabili da questi eventi", output.getvalue())

    def test_window_offsets_undated_and_cross_session_call_ids(self):
        for session in ("PRIVATE_a", "PRIVATE_b"):
            self.event("subagent.started", session=session, agentName="twin")
            self.event("subagent.completed", session=session)
        for when in (None, "2026-10-04T23:59:59Z", "2026-10-12T08:00:01Z"):
            self.event("subagent.started", str(when), when, agentName="twin")
        self.event("subagent.started", "boundary", "2026-10-04T23:00:00-01:00", agentName="twin")
        self.event("subagent.started", "end", "2026-10-12T10:00:00+02:00", agentName="twin")
        _, report = self.read()
        self.assertEqual(report["agents"]["twin"]["starts"], 4)
        self.assertEqual(report["agents"]["twin"]["succeeded"], 2)
        self.assertEqual(report["metadata"]["undated_events"], 1)

    def test_repeated_runtime_terminals_do_not_overwrite_success_with_cancellation(self):
        self.event("subagent.started", agentName="thor")
        self.event("subagent.completed")
        self.event("subagent.completed", cancelled=True, when="2026-10-11T11:00:00Z")
        _, report = self.read()
        self.assertEqual(report["totals"]["agents"]["starts"], 1)
        self.assertEqual(report["agents"]["thor"]["unknown"], 1)
        self.assertEqual(report["metadata"]["repeated_terminals"], 1)
        self.assertEqual(report["metadata"]["conflicting_terminals"], 1)
        self.assertEqual(report["metadata"]["duplicate_events"], 0)
        self.event("subagent.started", when="2026-10-11T10:30:00Z", agentName="thor")
        self.assertEqual(self.read()[1]["agents"]["thor"]["unknown"], 2)
        self.assertEqual(self.read()[1]["metadata"]["ambiguous_starts"], 2)

    def test_unapproved_names_discovery_and_non_skill_calls_are_not_named_uses(self):
        self.event("tool.execution_start", toolName="skill", arguments={"skill": "PRIVATE_skill"})
        self.event("subagent.started", "private", agentName="PRIVATE_agent")
        self.event("tool.execution_start", "bash", toolName="bash", arguments={"skill": "film-director"})
        self.event("session.skills_loaded", "discovery", skills=[{"name": "film-director"}])
        uses, report = self.read()
        self.assertEqual(uses, {})
        self.assertEqual(report["totals"]["skills"]["starts"], 1)
        self.assertEqual(report["metadata"]["omitted_skills"], 1)
        self.assertEqual(report["metadata"]["omitted_agents"], 1)
        self.assertEqual(report["skills"], {})
        self.assertNotIn("PRIVATE_", json.dumps(report))

    def test_duplicates_conflicts_missing_ids_and_inverted_terminals(self):
        raw = self.event("subagent.started", agentName="rex")
        self.write(raw)
        self.assertEqual(self.read()[1]["agents"]["rex"]["starts"], 1)
        self.assertEqual(self.read()[1]["metadata"]["duplicate_events"], 1)
        conflict = deepcopy(raw)
        conflict["data"]["agentName"] = "thor"
        self.write(conflict)
        with self.assertRaisesRegex(TelemetryError, "duplicato in conflitto"):
            self.read()
        (self.home / "PRIVATE_session/events.jsonl").write_text("")
        self.write({"type": "subagent.started", "timestamp": RECENT, "data": {}})
        with self.assertRaisesRegex(TelemetryError, "senza identificativo"):
            self.read()
        (self.home / "PRIVATE_session/events.jsonl").write_text("")
        self.event("subagent.started", agentName="rex")
        self.event("subagent.completed", when="2026-10-10T10:00:00Z")
        with self.assertRaisesRegex(TelemetryError, "precedente"):
            self.read()
        (self.home / "PRIVATE_session/events.jsonl").write_text("")
        fallback = {"type": "subagent.started", "timestamp": RECENT,
                    "data": {"toolCallId": "fallback", "agentName": "rex"}}
        self.write(fallback)
        self.write(fallback)
        self.assertEqual(self.read()[1]["agents"]["rex"]["starts"], 1)
        self.assertEqual(self.read()[1]["metadata"]["duplicate_events"], 1)

    def test_absent_corrupt_partial_and_timezone_less_sources(self):
        self.assertEqual(self.read()[1]["metadata"]["status"], "assente")
        self.assertFalse(self.home.exists())
        self.event("subagent.started", agentName="rex")
        path = self.home / "PRIVATE_session/events.jsonl"
        with path.open("a") as stream:
            stream.write('{"type":')
        self.assertEqual(self.read()[1]["metadata"]["partial_lines"], 1)
        with path.open("a") as stream:
            stream.write("\n")
        with self.assertRaisesRegex(TelemetryError, "registro non interpretabile"):
            self.read()
        path.write_text("")
        self.event("subagent.started", when="2026-10-11T10:00:00", agentName="rex")
        with self.assertRaisesRegex(TelemetryError, "data non interpretabile"):
            self.read()
        path.write_text("")
        self.write({"type": ["PRIVATE_type"]})
        with self.assertRaisesRegex(TelemetryError, "tipo non interpretabile"):
            self.read()

    def test_audit_native_union_and_snapshot_source_policy(self):
        installed = self.root / "home/.copilot/skills/film-director"
        installed.mkdir(parents=True)
        (installed / "SKILL.md").write_text("---\nname: film-director\n---\n")
        db_path = self.root / "sessions.db"
        with closing(sqlite3.connect(db_path)) as db, db:
            db.execute("CREATE TABLE session_files(session_id TEXT, file_path TEXT, first_seen_at TEXT)")
            db.execute("INSERT INTO session_files VALUES ('PRIVATE_session','PRIVATE_film.mp4',?)", (RECENT,))
        self.event("tool.execution_start", toolName="skill", arguments={"skill": "film-director"})
        self.event("tool.execution_complete", success=True)
        append(native("copilot", {"session_id": "PRIVATE_session", "id": "audit-start",
                                 "type": "tool.execution_start", "timestamp": RECENT,
                                 "data": {"toolCallId": "call", "toolName": "skill",
                                          "arguments": {"skill": "film-director"}}}))
        report = build_report(self.root, 7, NOW)
        row = next(item for item in report["skills"] if item["name"] == "film-director")
        self.assertEqual(row["observed_sessions"], 1)
        self.assertEqual(row["native_calls"]["starts"], 1)
        self.assertEqual(row["opportunity"]["invoked_in_cohort"], 1)
        before = db_path.read_bytes()
        groups = {name: dict.fromkeys(spec[0].split(), 0) for name, spec in GROUPS.items()}
        snapshot = build_snapshot(self.root, 7, groups, report)
        self.assertTrue(valid(snapshot))
        metric = snapshot["metrics"]["native-skills:film-director:succeeded"]
        self.assertEqual(metric["denominator"]["value"], 1)
        self.assertEqual(metric["source"], "copilot-events")
        self.assertEqual(report["value"]["status"], "non misurabile")
        with patch.dict(os.environ, {"RDA_COPILOT_EVENT_HOME": str(self.root / "other")}):
            changed = build_snapshot(self.root, 7, groups, report)
        for key in ("native-skills:film-director:succeeded", "skill:film-director:observed"):
            self.assertEqual(comparison(changed, snapshot, None)[key]["reason"], "fonte/perimetro diverso")
        self.assertNotIn("PRIVATE_", json.dumps(report) + json.dumps(snapshot))
        self.assertEqual(db_path.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
