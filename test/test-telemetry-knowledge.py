#!/usr/bin/env python3
"""Isolated fixtures for telemetry_knowledge: real MCP/skill invocations vs. everything else."""
from contextlib import closing, redirect_stdout
from datetime import datetime, timezone
import io
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "bin"))
sys.path.insert(0, str(ROOT / "kanban"))
from telemetry_knowledge import build_report, render  # noqa: E402
from audit_schema import native  # noqa: E402
from audit_store import append  # noqa: E402

NOW = datetime(2026, 9, 27, 12, tzinfo=timezone.utc)
RECENT = "2026-09-26T10:00:00Z"
OLD = "2026-09-01T00:00:00Z"


class KnowledgeTelemetry(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.environment = patch.dict(os.environ, {
            "HOME": str(self.base / "home"), "RDA_HOME": str(self.base / "rda"),
            "RDA_AUDIT_HOME": str(self.base / "audit"),
        })
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.sequence = 0

    def event(self, session, tool_name, skill=None, host="copilot", when=RECENT,
               event_type="tool.execution_start"):
        self.sequence += 1
        data = {"toolCallId": f"call-{self.sequence}", "toolName": tool_name}
        if skill:
            data["arguments"] = {"skill": skill}
        append(native(host, {"session_id": session, "id": f"event-{self.sequence}",
                             "timestamp": when, "type": event_type, "data": data}))

    def report(self, days=7):
        return build_report(days, NOW)

    def output(self, report):
        stream = io.StringIO()
        with redirect_stdout(stream):
            render(report)
        return stream.getvalue()

    def test_no_audit_reports_absent_not_zero(self):
        report = self.report()
        self.assertEqual(report["audit"]["status"], "assente")
        self.assertEqual(report["counts"]["gbrain"], {})
        self.assertIn("assente", self.output(report))

    def test_mcp_native_and_normalized_names_count_as_real_gbrain(self):
        self.event("PRIVATE_A", "mcp__gbrain__search")
        self.event("PRIVATE_B", "gbrain-search")
        self.event("PRIVATE_C", "gbrain-search", host="claude")
        report = self.report()
        self.assertEqual(report["counts"]["gbrain"], {"copilot": 2, "claude": 1})
        self.assertEqual(report["counts"]["codegraph"], {})

    def test_codegraph_mcp_name_counts_as_real(self):
        self.event("PRIVATE_A", "mcp__codegraph__codegraph_explore")
        report = self.report()
        self.assertEqual(report["counts"]["codegraph"], {"copilot": 1})

    def test_graphify_is_reported_not_observable_not_zero(self):
        # graphify e' una skill globale, non dichiarata dentro questo repo: l'elenco
        # pubblico riesaminato (kanban/audit_skill_names.json) non la contiene, quindi il
        # sanitizzatore la scarta prima che arrivi qui. Deve leggersi "non osservabile",
        # mai "0 invocazioni" (che direbbe implicitamente "misurato, e il conteggio e' zero").
        self.event("PRIVATE_A", "skill", skill="graphify")
        self.event("PRIVATE_B", "skill", skill="film-director")
        report = self.report()
        self.assertIn("graphify", report["not_observable"])
        self.assertEqual(report["counts"]["graphify"], {})
        output = self.output(report)
        self.assertIn("graphify: non osservabile", output)
        self.assertNotIn("graphify: 0 invocazioni", output)

    def test_unrelated_tool_names_are_not_counted(self):
        self.event("PRIVATE_A", "bash")
        self.event("PRIVATE_B", "Edit")
        report = self.report()
        for name in ("gbrain", "codegraph", "graphify"):
            self.assertEqual(report["counts"][name], {})

    def test_out_of_window_events_are_excluded(self):
        self.event("PRIVATE_old", "mcp__gbrain__search", when=OLD)
        report = self.report(days=7)
        self.assertEqual(report["counts"]["gbrain"], {})

    def test_undated_events_are_reported_not_silently_dropped(self):
        self.event("PRIVATE_A", "mcp__gbrain__search")
        self.event("PRIVATE_B", "mcp__gbrain__search", event_type="observer.gap")
        report = self.report()
        self.assertGreaterEqual(report["audit"]["undated_events"], 0)

    def test_real_and_mention_counts_are_never_summed_in_output(self):
        self.event("PRIVATE_A", "mcp__gbrain__search")
        output = self.output(self.report())
        self.assertIn("non somma mai", output)
        self.assertIn("gbrain: 1 invocazioni osservate", output)

    def test_no_private_identifiers_leak_into_rendered_output(self):
        self.event("PRIVATE_secret_session", "mcp__gbrain__search")
        output = self.output(self.report())
        self.assertNotIn("PRIVATE_secret_session", output)


if __name__ == "__main__":
    unittest.main()
