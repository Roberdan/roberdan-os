#!/usr/bin/env python3
"""Isolated audit acceptance tests; no real HOME, adapters, model calls or publication."""
import concurrent.futures
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "kanban" / "audit.py"


class AuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="rda-audit-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.env = {**os.environ, "HOME": str(self.root / "home"), "RDA_HOME": str(self.root / "rda"),
                    "RDA_AUDIT_HOME": str(self.root / "audit"),
                    "RDA_KANBAN": str(self.root / "never-board"), "PYTHONDONTWRITEBYTECODE": "1"}
        self.db = self.root / "audit" / "events.sqlite3"

    def run_cli(self, *args, stdin=None, ok=True, env=None, kb=False, machine=True):
        command = ["bash", str(ROOT / "kanban" / "kb.sh"), "audit"] if kb else [sys.executable, str(CLI)]
        result = subprocess.run([*command, *args], input=stdin, text=True, capture_output=True,
                                cwd=self.root, env=env or self.env, timeout=12)
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stderr, "")
            return json.loads(result.stdout) if machine else result.stdout
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "", "failure must not return partial or success-shaped output")
        self.assertIn("audit:", result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        return result.stderr

    def record(self, kind, payload, **kwargs):
        return self.run_cli("record", kind, "--json", json.dumps(payload), **kwargs)

    def ingest(self, event_type, data=None, *, sid="session-1", source=None, host="copilot", **kwargs):
        payload = {"type": event_type, "session_id": sid, "data": data or {}}
        if source:
            payload["id"] = source
        return self.run_cli("ingest", "--host", host, "--json", json.dumps(payload), **kwargs)

    def seed(self):
        self.record("request", {"id": "r1", "summary": "Choose a next step"})
        self.record("decision", {"id": "d1", "request_id": "r1", "summary": "Choose A or B"})

    def events(self):
        return self.run_cli("export", "--json")["events"]

    def test_read_only_empty_store_and_early_kb_dispatch(self):
        report = self.run_cli("list", "--json", kb=True)
        self.assertEqual(report["events"], [])
        self.assertFalse(report["coverage"]["store_exists"])
        self.assertFalse(self.db.parent.exists())
        self.assertFalse((self.root / "never-board").exists())
        self.assertEqual(self.run_cli("check", "--json")["integrity"], "not_initialized")
        ordinary = subprocess.run(["bash", str(ROOT / "kanban" / "kb.sh"), "view"],
                                  cwd=self.root, env=self.env, capture_output=True, text=True, timeout=12)
        self.assertEqual(ordinary.returncode, 0, ordinary.stderr)
        self.assertTrue((self.root / "never-board" / "todo").is_dir())
        self.assertFalse(self.db.exists(), "ordinary kb commands must not enter the audit path")

    def test_semantic_chain_and_no_human_authority(self):
        self.seed()
        self.record("consultation_started", {"id": "c1", "decision_id": "d1"})
        self.record("consultation_completed", {"id": "c2", "decision_id": "d1", "consultation_id": "c1"})
        self.record("recommendation", {"id": "rec1", "decision_id": "d1", "consultation_id": "c2",
                                     "summary": "Recommend option A", "option_id": "A", "evidence": ["test:comparison"]})
        stats = self.run_cli("stats", "--json")
        self.assertEqual(stats["unanswered_recommendations"], ["rec1"])
        response = self.record("human_response", {"decision_id": "d1", "recommendation_id": "rec1",
                                                "response": "yes"})
        self.assertEqual(response["provenance"], "human_attributed_unverified")
        self.assertFalse(response["permission_authority"])
        self.record("execution_started", {"id": "x1", "decision_id": "d1", "recommendation_id": "rec1"})
        self.record("execution_completed", {"id": "x2", "decision_id": "d1", "execution_id": "x1"})
        self.record("outcome", {"decision_id": "d1", "execution_id": "x2", "summary": "Artifact meets the check"})
        stats = self.run_cli("stats", "--json")
        self.assertEqual(stats["unanswered_recommendations"], [])
        self.assertEqual(stats["verified_human_responses"], 0)
        self.assertIsNone(stats["agreement_rate"])
        self.assertEqual(stats["human_attributed_unverified"]["yes"], 1)
        self.assertTrue(all(row.get("request_id") == "r1" for row in self.events()))
        self.assertEqual(len(self.run_cli("show", "r1", "--json")["related"]), len(self.events()) - 1)

    def test_live_discovery_failure_then_success_is_not_consultation(self):
        timeline = [
            ("session.skills_loaded", {"skills": ["roberdan-twin", "roberto-twin"]}),
            ("session.skills_loaded", {"skills": []}),
            ("tool.execution_start", {"toolCallId": "call-1", "toolName": "skill",
                                      "arguments": {"skill": "roberdan-twin"}}),
            ("tool.execution_complete", {"toolCallId": "call-1", "success": False,
                                         "error": {"code": "skill_not_found"}}),
            ("session.skills_loaded", {"skills": ["roberdan-twin"]}),
            ("tool.execution_start", {"toolCallId": "call-2", "toolName": "skill",
                                      "arguments": {"skill": "roberdan-twin"}}),
            ("tool.execution_complete", {"toolCallId": "call-2", "success": True}),
        ]
        for index, (kind, data) in enumerate(timeline):
            self.ingest(kind, data, source=f"native-{index}")
        rows = self.events()
        self.assertEqual([row["kind"] for row in rows], [
            "skill_discovery_snapshot", "skill_discovery_snapshot", "skill_invocation_started",
            "skill_invocation_failed", "skill_discovery_snapshot", "skill_invocation_started",
            "skill_invocation_succeeded"])
        stats = self.run_cli("stats", "--json")
        self.assertEqual([item["status"] for item in stats["attempts"]], ["failed", "succeeded"])
        self.assertNotIn("consultation_started", stats["by_kind"])
        self.assertNotIn("skill_load", stats["by_kind"])
        self.assertEqual(rows[3]["parent_event_id"], rows[2]["id"])
        self.assertTrue(all(row["decision_id"] is None for row in rows))

    def test_missing_and_unknown_terminal_not_success(self):
        self.ingest("tool.execution_start", {"toolCallId": "open", "toolName": "skill"})
        self.ingest("tool.execution_start", {"toolCallId": "unknown", "toolName": "task",
                                          "arguments": {"agent_type": "twin"}})
        self.ingest("tool.execution_complete", {"toolCallId": "unknown"})
        self.ingest("session.end")
        result = self.run_cli("coverage", "--json")
        self.assertEqual([item["status"] for item in result["unresolved_attempts"]],
                         ["terminal_not_observed", "terminal_status_unknown"])
        self.assertIn("terminal_not_observed", self.run_cli("stats", machine=False))

    def test_out_of_order_exact_pairing_and_missing_start(self):
        self.ingest("tool.execution_complete", {"toolCallId": "late", "success": True})
        self.assertEqual(self.run_cli("stats", "--json")["attempts"][0]["status"], "start_not_observed")
        self.ingest("tool.execution_start", {"toolCallId": "late", "toolName": "skill"})
        self.assertEqual(self.run_cli("stats", "--json")["attempts"][0]["status"], "succeeded")
        self.assertEqual(self.events()[0]["kind"], "tool_observation", "immutable original observation")

    def test_session_scoped_correlation_no_latest_decision_heuristic(self):
        self.seed()
        self.ingest("tool.execution_start", {"toolCallId": "same", "toolName": "bash", "requestId": "r1"}, sid="one")
        self.ingest("tool.execution_complete", {"toolCallId": "same", "success": True}, sid="two")
        self.assertEqual(len(self.run_cli("coverage", "--json")["unresolved_attempts"]), 2)
        self.assertIsNone(self.events()[2]["request_id"])
        self.assertIsNone(self.events()[2]["decision_id"])

    def test_bind_exact_known_call_and_refuse_reassignment(self):
        self.seed()
        binding = {"decision_id": "d1", "host": "copilot", "session_id": "session-1", "tool_call_id": "call"}
        self.record("bind", binding, ok=False)
        self.ingest("tool.execution_start", {"toolCallId": "call", "toolName": "bash"})
        first = self.record("bind", binding)
        self.assertEqual(self.record("bind", binding)["id"], first["id"])
        self.assertTrue(self.record("bind", binding)["duplicate"])
        shown = self.run_cli("show", "d1", "--json")
        self.assertTrue(any(row.get("native_type") == "tool.execution_start" for row in shown["related"]))
        self.assertEqual(shown["attempts"][0]["binding_event_id"], first["id"])
        self.assertEqual(shown["attempts"][0]["decision_id"], "d1")
        self.record("decision", {"id": "d2", "request_id": "r1", "summary": "Another choice"})
        self.record("bind", {**binding, "decision_id": "d2"}, ok=False)
        self.assertIsNone(self.events()[2]["decision_id"], "binding must not rewrite an observation")

    def test_duplicate_id_and_native_correlation_conflicts(self):
        self.seed()
        data = {"toolCallId": "c", "toolName": "skill"}
        first = self.ingest("tool.execution_start", data, source="source-1")
        again = self.ingest("tool.execution_start", data, source="source-1")
        self.assertTrue(again["duplicate"])
        self.assertEqual(first["id"], again["id"])
        self.ingest("tool.execution_start", {**data, "toolName": "bash"}, source="source-1", ok=False)
        self.ingest("tool.execution_start", data, source="different-source", ok=False)
        self.record("request", {"id": "r1", "summary": "Different content"}, ok=False)
        self.assertEqual(len(self.events()), 3)

    def test_no_source_id_does_not_collapse_discovery_snapshots(self):
        first = self.ingest("session.skills_loaded", {"skills": ["roberdan-twin"]})
        second = self.ingest("session.skills_loaded", {"skills": ["roberdan-twin"]})
        self.assertNotEqual(first["id"], second["id"])
        self.assertEqual(len(self.events()), 2)

    def test_strict_references_and_cross_decision_rejection(self):
        self.seed()
        self.record("recommendation", {"summary": "A", "decision_id": "missing"}, ok=False)
        self.record("human_response", {"decision_id": "d1", "recommendation_id": "r1", "response": "yes"}, ok=False)
        self.record("recommendation", {"id": "rec1", "decision_id": "d1", "summary": "A"})
        self.record("decision", {"id": "d2", "request_id": "r1", "summary": "Other choice"})
        self.record("human_response", {"decision_id": "d2", "recommendation_id": "rec1", "response": "yes"}, ok=False)
        self.record("request", {"id": "r2", "request_id": "r1", "summary": "Wrong self ref"}, ok=False)

    def test_native_consultation_and_execution_can_be_referenced_without_forging_a_decision(self):
        self.seed()
        start = self.ingest("tool.execution_start", {"toolCallId": "consult", "toolName": "task",
                                                   "arguments": {"agent_type": "twin"}})
        completed = self.ingest("tool.execution_complete", {"toolCallId": "consult", "success": True})
        self.assertEqual(completed["kind"], "consultation_completed")
        self.record("recommendation", {"decision_id": "d1", "consultation_id": completed["id"],
                                      "summary": "The adviser recommended A"})
        related_ids = {row["id"] for row in self.run_cli("show", "d1", "--json")["related"]}
        self.assertIn(completed["id"], related_ids)
        self.assertIn(start["id"], related_ids)
        self.assertIsNone(self.run_cli("show", start["id"], "--json")["event"]["decision_id"])
        self.ingest("tool.execution_start", {"toolCallId": "execute", "toolName": "bash"})
        executed = self.ingest("tool.execution_complete", {"toolCallId": "execute", "success": True})
        self.record("outcome", {"decision_id": "d1", "execution_id": executed["id"],
                               "summary": "Observed an artifact, not only a successful tool"})

    def test_pending_consultation_outcome_and_duplicate_manual_terminal(self):
        self.seed()
        self.record("skill_load", {"request_id": "r1", "summary": "Declared instruction load"})
        self.record("consultation_requested", {"id": "pending", "decision_id": "d1"})
        self.assertEqual(self.run_cli("coverage", "--json")["pending_consultations"], ["pending"])
        self.assertEqual(self.run_cli("stats", "--json")["decisions_without_outcome"], ["d1"])
        self.record("consultation_started", {"id": "cs", "decision_id": "d1", "consultation_id": "pending"})
        self.record("consultation_completed", {"decision_id": "d1", "consultation_id": "cs"})
        self.record("consultation_failed", {"decision_id": "d1", "consultation_id": "cs"}, ok=False)
        self.record("execution_completed", {"decision_id": "d1"}, ok=False)
        self.assertEqual(self.run_cli("coverage", "--json")["pending_consultations"], [])

    def test_privacy_unknown_native_fields_never_persist(self):
        sentinel = "PRIVATE_SENTINEL_not_for_storage"
        raw = {"type": "tool.execution_start", "session_id": "s", "prompt": sentinel,
               "data": {"toolCallId": "c", "toolName": "task", "arguments": {
                   "agent_type": "twin", "prompt": sentinel, "command": sentinel},
                        "raw_output": sentinel, "error": {"code": "example", "message": sentinel}}}
        self.run_cli("ingest", "--host", "copilot", "--json", json.dumps(raw))
        self.ingest("user.message", {"prompt": sentinel, "response": "yes", "content": sentinel})
        exported = self.run_cli("export", "--json")
        self.assertNotIn(sentinel, json.dumps(exported))
        self.assertNotIn(sentinel.encode(), self.db.read_bytes())
        self.assertNotIn("human_response", self.run_cli("stats", "--json")["by_kind"])
        self.assertEqual(exported["events"][0]["data"]["arguments"], {"agent_type": "twin"})

    def test_sensitive_semantics_and_invalid_json_fail_without_echo(self):
        secret = "ghp_" + "S" * 32
        err = self.record("request", {"summary": secret}, ok=False)
        self.assertNotIn(secret, err)
        self.record("request", {"summary": "Safe", "reasoning": secret}, ok=False)
        self.record("request", {"summary": "Safe", "evidence": ["raw tool output"]}, ok=False)
        self.run_cli("record", "request", "--json", '{"summary":"one","summary":"two"}', ok=False)
        self.run_cli("record", "request", "--json", '{"summary":', ok=False)
        self.run_cli("record", "request", "--json", "[]", ok=False)
        self.run_cli("record", "request", "--json", '{"summary":"Safe","cost":NaN}', ok=False)
        self.assertFalse(self.db.exists())

    def test_exact_input_and_summary_limits(self):
        self.record("request", {"summary": "x" * 512})
        self.record("request", {"summary": "x" * 513}, ok=False)
        self.run_cli("record", "request", "--json", '{"summary":"' + "x" * 16384 + '"}', ok=False)
        self.record("request", {"summary": "line\nbreak"}, ok=False)
        self.run_cli("record", "request", "--json", '{"summary":"\\ud800"}', ok=False)
        self.record("request", {"summary": " "}, ok=False)

    def test_unknown_metrics_not_zero_and_declared_metrics_require_evidence_scope(self):
        self.record("request", {"summary": "Unknown cost", "model": None, "agent_id": None})
        self.assertIsNone(self.events()[0]["metrics"]["cost"])
        self.record("request", {"summary": "Zero reported", "metrics": {
            "cost": 0, "cost_unit": "nano_aiu", "source": "artifact:usage-1", "scope": "session"}})
        self.assertEqual(self.events()[1]["metrics"]["cost"], 0)
        self.assertEqual(self.events()[1]["provenance"], "agent_declared")
        self.assertIsNone(self.run_cli("stats", "--json")["cost"])
        for value in (-1, True, float("inf")):
            self.record("request", {"summary": "Invalid", "metrics": {"cost": value}}, ok=False)
        self.record("request", {"summary": "No source", "metrics": {"input_tokens": 10}}, ok=False)
        self.record("request", {"summary": "Large integer does not crash validation", "metrics": {
            "input_tokens": 10 ** 400, "source": "artifact:declared-count", "scope": "session"}})

    def test_native_time_and_nullable_identifiers(self):
        payload = {"type": "session.start", "id": None, "session_id": "s", "data": {"model": None},
                   "timestamp": "2026-09-17T09:20:11+00:00"}
        self.run_cli("ingest", "--host", "copilot", "--json", json.dumps(payload))
        event = self.events()[0]
        self.assertEqual(event["timestamp"], payload["timestamp"])
        self.assertIsNone(event["model"])
        self.assertIsNotNone(event["recorded_at"])
        for time in ("2026-09-17T09:20:11", "not-a-time", 42):
            self.run_cli("ingest", "--host", "copilot", "--json", json.dumps({**payload, "timestamp": time}), ok=False)

    def test_coverage_declarations_and_unsupported_events(self):
        self.record("coverage", {"host": "claude", "session_id": "s", "coverage": {
            "status": "partial", "event_types": ["PreToolUse"], "reason": "No terminal observer"}})
        result = self.ingest("future.native_event", {"success": True}, host="claude")
        self.assertEqual(result["kind"], "unsupported_observation")
        coverage = self.run_cli("coverage", "--json")
        self.assertEqual(coverage["unsupported_events"], [result["id"]])
        self.assertEqual(coverage["declarations"][0]["provenance"], "agent_declared")
        self.assertFalse(coverage["permission_authority"])

    def test_native_validation_and_unlinked_subagent(self):
        self.run_cli("ingest", "--host", "copilot", "--json", '{"type":"session.start"}', ok=False)
        self.ingest("tool.execution_complete", {"success": "true"}, ok=False)
        self.ingest("tool.execution_start", {"arguments": "raw prompt"}, ok=False)
        self.ingest("subagent.started", {"agentId": "a", "agentName": "twin"})
        self.ingest("subagent.failed", {"agentId": "a", "error": {"code": "unavailable"}})
        self.ingest("tool.execution_start", {"toolName": "skill"})
        stats = self.run_cli("stats", "--json")
        self.assertEqual(stats["attempts"][0]["status"], "failed")
        self.assertEqual(len(stats["coverage"]["unlinked_native_events"]), 1)
        self.assertNotIn("consultation_started", stats["by_kind"], "child metadata must not double count consultations")

    def test_owner_only_permissions_and_unsafe_modes(self):
        self.seed()
        self.assertEqual(self.db.parent.stat().st_mode & 0o777, 0o700)
        self.assertEqual(self.db.stat().st_mode & 0o777, 0o600)
        self.db.chmod(0o644)
        self.run_cli("list", "--json", ok=False)
        self.db.chmod(0o600)
        self.db.parent.chmod(0o755)
        self.run_cli("check", "--json", ok=False)

    def test_symlink_and_hardlink_database_refused(self):
        self.seed()
        original = self.root / "original.sqlite3"
        self.db.rename(original)
        self.db.symlink_to(original)
        self.run_cli("list", "--json", ok=False)
        self.db.unlink()
        os.link(original, self.db)
        self.run_cli("list", "--json", ok=False)
        self.db.unlink()
        original.rename(self.db)
        alias = self.root / "alias"
        alias.symlink_to(self.db.parent, target_is_directory=True)
        self.run_cli("list", "--json", env={**self.env, "RDA_AUDIT_HOME": str(alias)}, ok=False)

    def test_git_checkout_linked_worktree_and_symlink_into_git_refused(self):
        repo = self.root / "repo"
        subprocess.run(["git", "init", "-q", str(repo)], check=True)
        for path in (repo / "ignored" / "audit", repo):
            self.record("request", {"summary": "Must not write"}, env={**self.env, "RDA_AUDIT_HOME": str(path)}, ok=False)
            self.assertFalse((path / "events.sqlite3").exists())
        linked = self.root / "linked"
        linked.mkdir()
        (linked / ".git").write_text("gitdir: /not-loaded-by-audit\n")
        self.record("request", {"summary": "No write"}, env={**self.env, "RDA_AUDIT_HOME": str(linked / "audit")}, ok=False)
        alias = self.root / "alias"
        alias.symlink_to(repo, target_is_directory=True)
        self.record("request", {"summary": "No write"}, env={**self.env, "RDA_AUDIT_HOME": str(alias / "audit")}, ok=False)

    def test_corruption_is_loud_whole_and_no_automatic_repair(self):
        self.seed()
        with sqlite3.connect(self.db) as db:
            db.execute("DROP TRIGGER no_update")
            db.execute("UPDATE events SET body = '{}' WHERE seq = 2")
        before = self.db.read_bytes()
        self.run_cli("export", "--json", ok=False)
        self.record("request", {"summary": "Cannot append over corruption"}, ok=False)
        self.assertEqual(self.db.read_bytes(), before)

    def test_append_only_triggers_and_database_corruption(self):
        self.seed()
        with sqlite3.connect(self.db) as db:
            for sql in ("DELETE FROM events", "UPDATE events SET body = '{}'"):
                with self.assertRaises(sqlite3.IntegrityError):
                    db.execute(sql)
        self.db.write_bytes(b"not a sqlite database")
        self.run_cli("stats", "--json", ok=False)

    def test_bounded_lock_failure_no_fallback(self):
        self.seed()
        db = sqlite3.connect(self.db)
        try:
            db.execute("BEGIN IMMEDIATE")
            self.record("request", {"summary": "Blocked writer"}, ok=False)
        finally:
            db.rollback()
            db.close()
        self.assertEqual(len(self.events()), 2)

    def test_concurrent_appends_and_duplicate_replays(self):
        def write(index):
            return self.record("request", {"id": f"r-{index}", "summary": f"Request {index}"})
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(write, range(16)))
        self.assertEqual(len({item["id"] for item in results}), 16)
        self.assertEqual(self.run_cli("check", "--json")["events"], 16)
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            replays = list(pool.map(lambda _: self.ingest("session.start", source="one-source"), range(6)))
        self.assertEqual(len({item["id"] for item in replays}), 1)
        self.assertEqual(sum(not item["duplicate"] for item in replays), 1)

    def test_stdin_json_queries_pagination_and_compact_human_output(self):
        self.run_cli("record", "request", stdin='{"id":"r1","summary":"From stdin"}', kb=True)
        self.run_cli("ingest", "--host", "claude", stdin='{"type":"session.start","session_id":"s","data":{}}')
        self.assertEqual(len(self.run_cli("list", "--limit", "1", "--offset", "1", "--json")["events"]), 1)
        self.run_cli("list", "--limit", "0", ok=False)
        self.run_cli("show", "missing", "--json", ok=False)
        self.assertIn("From stdin", self.run_cli("show", "r1", machine=False))
        self.assertIn("never permission", self.run_cli("export", machine=False))
        self.assertFalse((self.root / "never-board").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
