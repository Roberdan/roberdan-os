#!/usr/bin/env python3
"""Native callbacks -> real private SQLite -> count-only skill telemetry."""
from collections import Counter
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / "kanban"), str(ROOT / "bin")]
from audit_schema import native
from audit_skills import POLICY, public_skill_names
from audit_store import append, read_events, attempts
from telemetry_inventory import declaration, manifests
from telemetry_skills import build_report, CRITERIA

WHEN = "2026-09-24T06:00:00Z"
CANARY = "PRIVATE_nested_prompt_and_content"
NODE = """
import { readFileSync } from "node:fs";
const { createAuditObserver } = await import(process.env.RDA_OS + "/hooks/copilot/audit.mjs");
const handlers = new Map();
const observer = createAuditObserver({root: process.env.RDA_OS, sessionId: "copilot-general"});
observer.register({on: (kind, callback) => {handlers.set(kind, callback); return () => handlers.delete(kind);}});
if (!await observer.flush()) throw Error("registration failed");
for (const event of JSON.parse(readFileSync(0, "utf8"))) {
    handlers.get(event.type)(event);
    if (!await observer.flush()) throw Error("ingest failed");
}
if (!await observer.stop()) throw Error("shutdown failed");
"""
# hooks/copilot/audit.mjs's AUDIT_LIMITS.writeMs=1000 (and hooks/audit.sh's own 1.5s) are
# production budgets on a python3 subprocess spawn; under real CPU contention (@thor: 6x `yes`)
# that spawn can legitimately miss them, so the node/bash harness above reports ingest_timeout/
# flush_timeout and this file's own AssertionError/TimeoutExpired follows. That is not a bug in
# either timeout (frozen by design, not touched here) or in the 15s/5s outer subprocess.run caps
# below (a real hang must still fail). Same diagnosis and fix as test-audit-chain.sh (commit
# 8bb7176): collect every diagnostic line from every subprocess call in this run; if the whole
# run failed and EVERY line collected is one of these transient codes (never zero, never any
# other code), retry the whole file, up to RETRIES times, against fresh state. A persistent
# failure fails identically on every retry and stays red.
TRANSIENT = {"ingest_timeout", "flush_timeout", "test_subprocess_timeout"}
RETRIES = 1  # matches test-audit-chain.sh's precedent (commit 8bb7176); bounded, not "keep trying".
DIAGNOSTICS = []


def _run(cmd, **kwargs):
    # Every call's stderr is collected into DIAGNOSTICS unconditionally (success or failure —
    # hooks/audit.sh exits 0 even on its own timeout), and classified only at the end: the one
    # deliberately-triggered diagnostic this file expects on a still-exit-0 call
    # (invalid_timestamp) is excluded there, not by guessing per call which outcome was "expected".
    try:
        return subprocess.run(cmd, **kwargs)
    except subprocess.TimeoutExpired as timeout:
        DIAGNOSTICS.append((timeout.stderr or "") + "\n[roberdan-os audit] test_subprocess_timeout")
        raise


class NativeSkillAudit(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="rda-native-skills-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.installed = self.base / "installed"
        self.installed.mkdir()
        for name in ("film-director", "pdf", "rdos-film-director", "roberdan-twin"):
            folder = self.installed / name
            folder.mkdir()
            (folder / "SKILL.md").write_text(f"---\nname: {name}\n---\n")
        with (self.installed / "rdos-film-director/SKILL.md").open("a") as file:
            file.write("Canonical logic: read `skills/film-director/skill.md` in roberdan-os.\n"
                       "<!-- roberdan-os: namespaced install (skill-name collision) -->\n")
        # A syntactically valid installed declaration is NOT public audit consent.
        private = self.installed / "private"
        private.mkdir()
        (private / "SKILL.md").write_text(f"---\nname: {CANARY}\n---\n")
        self.env = patch.dict(os.environ, {
            "HOME": str(self.base / "home"), "RDA_HOME": str(self.base / "state"),
            "RDA_OS": str(ROOT), "RDA_AUDIT_HOME": str(self.base / "audit"),
            "RDA_TELEMETRY_SKILL_DIRS": str(self.installed),
            "RDA_SESSION_STORE": str(self.base / "absent.db"),
            "PYTHONDONTWRITEBYTECODE": "1",
        })
        self.env.start()
        self.addCleanup(self.env.stop)

    def copilot(self, events, ok=True):
        result = _run(["node", "--input-type=module", "-e", NODE],
                      input=json.dumps(events), text=True, capture_output=True, timeout=15)
        DIAGNOSTICS.append(result.stderr or "")
        self.assertEqual(result.returncode == 0, ok, result.stderr)
        self.assertNotIn(CANARY, result.stdout + result.stderr)
        return result

    def claude(self, event):
        result = _run(["bash", str(ROOT / "hooks/audit.sh")], text=True,
                      input=json.dumps({"session_id": "claude-general", **event}),
                      capture_output=True, timeout=5)
        # hooks/audit.sh exits 0 even on its own internal ingest_timeout (it reports and moves
        # on, same as invalid_timestamp), so this diagnostic is collected unconditionally too —
        # a dropped event can still fail a LATER count assertion with nothing else to explain it.
        DIAGNOSTICS.append(result.stderr or "")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertNotIn(CANARY, result.stderr)
        return result

    def tool(self, call, skill):
        return {"type": "tool.execution_start", "timestamp": WHEN,
                "data": {"toolCallId": call, "toolName": "skill", "arguments": {
                    "skill": skill, "args": {"nested": {"prompt": CANARY}},
                    "content": CANARY}}}

    def rows(self):
        rows, exists = read_events()
        self.assertTrue(exists)
        serialized = json.dumps(rows)
        self.assertNotIn(CANARY, serialized)
        self.assertNotIn(CANARY.encode(), (self.base / "audit/events.sqlite3").read_bytes())
        return rows

    def test_public_policy_matches_declarations_and_existing_provider_criteria(self):
        data = json.loads((ROOT / "kanban/audit_skill_names.json").read_text())
        declared = {item["name"] for base in (ROOT / "skills", ROOT / ".github/skills")
                    for path in manifests(base) if (item := declaration(path))}
        self.assertEqual(set(data["canonical"]), declared)
        self.assertEqual(set(data["providers"]), set(CRITERIA) - declared)
        self.assertEqual(data["compatibility"], ["roberto-twin"])
        expected = declared | {"rdos-" + name for name in declared} | set(data["providers"]) | {"roberto-twin"}
        self.assertEqual(public_skill_names(), expected)
        self.assertNotIn(CANARY, public_skill_names())
        events = [self.tool(f"policy-{index}", name) for index, name in enumerate(sorted(expected))]
        self.copilot(events)
        actual = {row["data"]["arguments"]["skill"] for row in self.rows()
                  if row["native_type"] == "tool.execution_start"}
        self.assertEqual(actual, expected, "JS and Python must share the exact same selector policy")

    def test_both_native_adapters_store_general_names_without_changing_twin_totals(self):
        names = ["film-director", "pdf", "rdos-film-director", "rdos-roberdan-twin"]
        events = [{"type": "session.skills_loaded", "timestamp": WHEN, "data": {
            "skills": [{"name": name, "content": CANARY} for name in names + [CANARY]]}}]
        for index, name in enumerate(names):
            start = self.tool(f"call-{index}", name)
            if index % 2:
                start["data"]["arguments"] = json.dumps(start["data"]["arguments"])
            events.extend([start, {"type": "tool.execution_complete", "timestamp": WHEN,
                                  "data": {"toolCallId": f"call-{index}", "success": index != 1}}])
        self.copilot(events)
        self.claude({"hook_event_name": "SessionStart", "timestamp": WHEN})
        for index, name in enumerate(names):
            common = {"tool_use_id": f"call-{index}", "tool_name": "Skill", "timestamp": WHEN,
                      "tool_input": {"skill": name, "args": {"nested": CANARY}},
                      "prompt": CANARY, "tool_response": {"content": CANARY}}
            self.claude({"hook_event_name": "PreToolUse", **common})
            self.claude({"hook_event_name": "PostToolUseFailure" if index == 1 else "PostToolUse", **common})
        rows = self.rows()
        starts = [row for row in rows if row["native_type"] in ("PreToolUse", "tool.execution_start")]
        for host in ("copilot", "claude"):
            self.assertEqual([row["data"]["arguments"]["skill"] for row in starts if row["host"] == host], names)
        self.assertTrue(all(row["data"]["skillNamePolicy"] == POLICY for row in starts))
        kinds = Counter(row["kind"] for row in rows)
        self.assertEqual(kinds["execution_started"], 6)
        self.assertEqual(kinds["execution_completed"], 4)
        self.assertEqual(kinds["execution_failed"], 2)
        self.assertEqual(kinds["skill_invocation_started"], 2)
        self.assertEqual(kinds["skill_invocation_succeeded"], 2)
        self.assertEqual(kinds["consultation_started"], 0)
        self.assertEqual(kinds["consultation_completed"], 0)
        states = Counter(attempt["status"] for attempt in attempts(rows))
        self.assertEqual(states, {"succeeded": 6, "failed": 2})
        discovery = next(row["data"] for row in rows if row["kind"] == "skill_discovery_snapshot")
        self.assertEqual(discovery["skills"], sorted(names))
        self.assertEqual(discovery["skillNameStatus"], "omitted")
        report = build_report(ROOT, 7, datetime(2026, 9, 24, 8, tzinfo=timezone.utc))
        measured = {row["name"]: row["observed_sessions"] for row in report["skills"]}
        self.assertEqual(measured["film-director"], 2)
        self.assertEqual(measured["pdf"], 2, "failed invocation is still an observed start, not a success")
        self.assertNotIn("rdos-film-director", measured)
        self.assertEqual(measured["roberdan-twin"], 2)

    def test_unknown_secretlike_paths_and_nested_names_never_enter_either_adapter_or_schema(self):
        names = [CANARY, "ghp_" + "S" * 32, "sk-" + "s" * 40, "/private/path",
                 "token=private", "document-skills:PRIVATE", "rdos-pdf", "", {"name": CANARY}]
        self.copilot([self.tool(f"invalid-{index}", name) for index, name in enumerate(names)])
        for index, name in enumerate(names):
            self.claude({"hook_event_name": "PreToolUse", "tool_use_id": f"invalid-{index}",
                         "tool_name": "Skill", "timestamp": WHEN, "tool_input": {"skill": name}})
            append(native("claude", {"type": "PreToolUse", "session_id": "schema-direct",
                                    "data": {"toolCallId": f"schema-{index}", "toolName": "Skill",
                                             "arguments": {"skill": name, "nested": CANARY}}}))
        append(native("copilot", {"type": "session.skills_loaded", "session_id": "schema-direct",
                                 "data": {"skills": ["film-director", "pdf", *names]}}))
        rows = self.rows()
        for row in rows:
            if row["native_type"] in ("PreToolUse", "tool.execution_start"):
                self.assertNotIn("skill", row["data"].get("arguments", {}))
                self.assertEqual(row["data"]["skillNameStatus"], "omitted")
        for secret in names[1:7]:
            self.assertNotIn(secret, json.dumps(rows))
            self.assertNotIn(secret.encode(), (self.base / "audit/events.sqlite3").read_bytes())
        self.assertEqual(rows[-1]["data"]["skills"], ["film-director", "pdf"])

    def test_discovery_only_undated_events_and_invalid_times_do_not_become_measured_use(self):
        event = self.tool("undated", "film-director")
        del event["timestamp"]
        self.copilot([{"type": "session.skills_loaded", "timestamp": WHEN,
                       "data": {"skills": [{"name": "film-director"}, {"name": "pdf"}]}}, event])
        self.claude({"hook_event_name": "PreToolUse", "tool_use_id": "undated",
                     "tool_name": "Skill", "tool_input": {"skill": "pdf"}})
        report = build_report(ROOT, 7, datetime(2026, 9, 24, 8, tzinfo=timezone.utc))
        measured = {row["name"]: row["observed_sessions"] for row in report["skills"]}
        self.assertIsNone(measured["film-director"])
        self.assertIsNone(measured["pdf"])
        self.assertGreaterEqual(report["sources"]["audit"]["undated_events"], 2)
        self.assertTrue(all(row["timestamp"] is None for row in self.rows()
                            if row["native_type"] in ("PreToolUse", "tool.execution_start")))
        bad = self.tool("bad-time", "pdf")
        bad["timestamp"] = "PRIVATE_invalid_time"
        result = self.copilot([bad], ok=False)
        self.assertIn("invalid_timestamp", result.stderr)
        for timestamp in ("PRIVATE_invalid_time", "2026-09-24T08:00:00", None, 42):
            result = self.claude({"hook_event_name": "PreToolUse", "tool_use_id": "bad",
                                 "tool_name": "Skill", "timestamp": timestamp, "tool_input": {"skill": "pdf"}})
            self.assertIn("invalid_timestamp", result.stderr)
        self.assertNotIn("PRIVATE_invalid_time", json.dumps(self.rows()))


if __name__ == "__main__":
    _result = unittest.main(verbosity=2, exit=False).result
    _attempt = int(os.environ.get("RDA_AUDIT_SKILLS_RETRY", "0"))
    if not _result.wasSuccessful() and _attempt < RETRIES:
        codes = set(re.findall(r"\[roberdan-os audit\] (\w+)", "\n".join(DIAGNOSTICS)))
        codes -= {"invalid_timestamp"}  # this file's own deliberately-triggered, still-exit-0 case
        if codes and codes <= TRANSIENT:
            print(f"  retry {_attempt + 1}/{RETRIES}: transient timeout under load "
                  f"({','.join(sorted(codes))})", file=sys.stderr)
            os.environ["RDA_AUDIT_SKILLS_RETRY"] = str(_attempt + 1)
            os.execv(sys.executable, [sys.executable, __file__])
    sys.exit(0 if _result.wasSuccessful() else 1)
