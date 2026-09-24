#!/usr/bin/env bash
set -eu
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import fcntl
import json
import os
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import time
import unittest

HOOK = Path(sys.argv.pop()) / "hooks" / "audit.sh"


class ClaudeAuditHooks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="rda-audit-claude-")
        self.root = Path(self.temp.name)
        (self.root / "kanban").mkdir()
        for filename in ("audit_skills.py", "audit_skill_names.json"):
            shutil.copyfile(HOOK.parents[1] / "kanban" / filename, self.root / "kanban" / filename)
        self.log = self.root / "events.jsonl"
        self.core = self.root / "kanban" / "audit.py"
        self.env = dict(os.environ, RDA_OS=str(self.root), RDA_HOME=str(self.root / "home"))
        self.healthy()

    def tearDown(self):
        self.temp.cleanup()

    def healthy(self):
        self.core.write_text(
            "import json,sys\n"
            "assert sys.argv[1:] == ['ingest', '--host', 'claude']\n"
            f"with open({str(self.log)!r}, 'a') as output:\n"
            "    output.write(json.dumps(json.load(sys.stdin)) + '\\n')\n")

    def invoke(self, event, **extra):
        if isinstance(event, dict):
            event = json.dumps(dict(session_id="claude-session", **event, **extra)).encode()
        result = subprocess.run(["bash", str(HOOK)], input=event, env=self.env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"", "observer must never emit permission output")
        self.assertNotIn(b"PRIVATE", result.stderr)
        return result

    def events(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_native_tool_fields_only_and_error_not_forged_into_code(self):
        for kind in ["PreToolUse", "PostToolUseFailure", "PostToolUse"]:
            self.invoke(dict(hook_event_name=kind, tool_use_id="toolu_01", tool_name="Skill",
                             tool_input={"skill": "roberdan-twin", "args": "PRIVATE_ARGUMENTS"},
                             error="PRIVATE_ERROR", tool_response={"content": "PRIVATE_RESULT"},
                             transcript_path="/PRIVATE_TRANSCRIPT", model="unverified-model",
                             prompt="PRIVATE_PROMPT", permission_mode="bypassPermissions"))
        events = self.events()
        self.assertEqual([e["data"].get("success") for e in events], [None, False, True])
        self.assertEqual(events[0]["data"]["arguments"], {"skill": "roberdan-twin"})
        self.assertEqual(events[1]["data"]["toolCallId"], "toolu_01")
        self.assertNotIn("error", events[1]["data"])
        self.assertNotIn("model", events[0]["data"])
        self.assertNotIn("PRIVATE", json.dumps(events))

    def test_child_identity_never_invents_parent_call_or_success(self):
        self.invoke(dict(hook_event_name="PreToolUse", tool_use_id="spawn-1", tool_name="Agent",
                         tool_input={"subagent_type": "twin", "prompt": "PRIVATE"}))
        for kind in ["SubagentStart", "SubagentStop"]:
            self.invoke(dict(hook_event_name=kind, agent_id="child-1", agent_type="twin",
                             tool_use_id="not-in-native-subagent-schema",
                             last_assistant_message="PRIVATE", agent_transcript_path="/PRIVATE"))
        events = self.events()
        self.assertEqual(events[0]["data"]["arguments"], {"agent_type": "twin"})
        for event in events[1:]:
            self.assertEqual(event["data"], {"agentId": "child-1", "agentName": "twin"})
        self.assertNotIn("PRIVATE", json.dumps(events))

    def test_coverage_lifecycle_and_unsupported_not_human_consent(self):
        self.invoke(dict(hook_event_name="SessionStart", model="claude-test-model"))
        self.invoke(dict(hook_event_name="UserPromptSubmit", prompt="yes PRIVATE"))
        self.invoke(dict(hook_event_name="SessionEnd", reason="PRIVATE"))
        events = self.events()
        self.assertEqual([e["type"] for e in events],
                         ["SessionStart", "observer.unsupported", "observer.unsupported", "observer.gap", "SessionEnd"])
        self.assertEqual(events[0]["data"]["model"], "claude-test-model")
        self.assertEqual(events[-1]["data"], {})
        self.assertNotIn("PRIVATE", json.dumps(events))

    def test_invalid_oversized_and_missing_ids_never_persist_and_next_success_records_gap(self):
        bad = [
            b'{"secret":"PRIVATE", broken',
            b"PRIVATE" * 10000,
            {"hook_event_name": "PreToolUse", "tool_name": "Skill", "tool_input": {"skill": "roberdan-twin"}},
            {"hook_event_name": "SubagentStart", "agent_type": "twin"},
            {"hook_event_name": ["PRIVATE"]},
            {"hook_event_name": "SessionStart", "model": "PRIVATE invalid identifier"},
        ]
        for payload in bad:
            self.assertTrue(self.invoke(payload).stderr)
        self.assertEqual(self.events(), [])
        self.invoke(dict(hook_event_name="PostToolUse", tool_use_id="terminal-1", tool_name="Read"))
        self.assertEqual([e["type"] for e in self.events()], ["observer.gap", "PostToolUse"])
        self.assertNotIn("PRIVATE", self.log.read_text())
        self.assertFalse((self.root / "home/audit-observer/claude.pending").exists())
        self.assertFalse((self.root / "home/audit-observer/claude.recovering").exists())

    def test_failed_logger_empty_permission_output_and_persistent_next_success_gap(self):
        self.core.write_text("import sys\nprint('PRIVATE', file=sys.stderr)\nprint('PRIVATE')\nsys.exit(7)\n")
        self.assertIn(b"ingest_failed", self.invoke(dict(hook_event_name="SessionEnd")).stderr)
        self.assertEqual(self.events(), [])
        self.assertEqual((self.root / "home/audit-observer/claude.pending").read_bytes(), b"1")
        self.healthy()
        self.invoke(dict(hook_event_name="SessionStart"))
        self.assertEqual([e["type"] for e in self.events()],
                         ["observer.gap", "SessionStart", "observer.unsupported", "observer.unsupported"])

    def test_single_ingest_at_a_time_and_busy_observer_leaves_bounded_gap(self):
        state = self.root / "home/audit-observer"
        state.mkdir(parents=True)
        with (state / "claude.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            for _ in range(3):
                self.assertIn(b"observer_busy", self.invoke(dict(hook_event_name="SessionEnd")).stderr)
        self.assertEqual((state / "claude.pending").read_bytes(), b"1")
        self.assertEqual(len(list(state.iterdir())), 2)
        self.invoke(dict(hook_event_name="SessionEnd"))
        self.assertEqual([e["type"] for e in self.events()], ["observer.gap", "SessionEnd"])

    def test_stuck_logger_is_killed_within_bound(self):
        self.core.write_text("import time\ntime.sleep(30)\n")
        before = time.monotonic()
        self.assertIn(b"ingest_timeout", self.invoke(dict(hook_event_name="SessionEnd")).stderr)
        self.assertLess(time.monotonic() - before, 2)


result = unittest.main(verbosity=2, exit=False)
raise SystemExit(0 if result.result.wasSuccessful() and subprocess.call(
    ["node", "--test", str(HOOK.parents[1] / "test" / "test-copilot-audit.mjs")]) == 0 and subprocess.call(
    ["bash", str(HOOK.parents[1] / "test" / "test-audit-chain.sh")]) == 0 else 1)
PY
PYTHONDONTWRITEBYTECODE=1 python3 "$ROOT/test/test-audit-skills.py"
