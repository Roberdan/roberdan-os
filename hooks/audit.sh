#!/usr/bin/env bash
# Claude command hook only: never prints a permission decision or conversation content.
# Input contract: https://code.claude.com/docs/en/hooks (reviewed 2026-09-17).
ROOT="${RDA_OS:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
python3 - "$ROOT" 3<&0 <<'PY'
import fcntl
from datetime import datetime
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys

LIMIT = 65536
IDENTIFIER = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.:/-]{0,127}\Z")
EVENTS = {"SessionStart", "SessionEnd", "PreToolUse", "PostToolUse",
          "PostToolUseFailure", "SubagentStart", "SubagentStop"}
root = Path(sys.argv[1])
sys.path.insert(0, str(root / "kanban"))
state = Path(os.environ.get("RDA_HOME", str(Path.home() / ".roberdan-os"))) / "audit-observer"
pending = state / "claude.pending"
recovering = state / "claude.recovering"


def diagnostic(code):
    print("[roberdan-os audit] " + code, file=sys.stderr)


def mark_gap():
    try:
        state.mkdir(mode=0o700, parents=True, exist_ok=True)
        fd = os.open(pending, os.O_CREAT | os.O_WRONLY | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
        os.write(fd, b"1")
        os.close(fd)
    except OSError:
        diagnostic("gap_marker_failed")


def identifier(value):
    return isinstance(value, str) and IDENTIFIER.fullmatch(value) is not None


def normalize(raw):
    if not isinstance(raw, dict) or not identifier(raw.get("session_id")):
        raise ValueError("invalid_session_id")
    kind = raw.get("hook_event_name")
    if kind not in EVENTS:
        raise ValueError("unsupported_event")
    data = {}
    try:
        from audit_skills import POLICY, public_skill_names
        names = public_skill_names()
    except (ImportError, OSError, ValueError) as exc:
        raise ValueError("skill_policy_unavailable") from exc

    def put(key, value):
        if value is not None:
            if not identifier(value):
                raise ValueError("invalid_metadata")
            data[key] = value

    put("agentId", raw.get("agent_id"))
    put("agentName", raw.get("agent_type"))
    if kind == "SessionStart":
        put("model", raw.get("model"))
    if kind in {"PreToolUse", "PostToolUse", "PostToolUseFailure"}:
        if kind == "PreToolUse":
            data["skillNamePolicy"] = POLICY
        if not identifier(raw.get("tool_use_id")):
            raise ValueError("missing_tool_call_id")
        if not identifier(raw.get("tool_name")):
            raise ValueError("invalid_tool_name")
        put("toolCallId", raw["tool_use_id"])
        put("toolName", raw["tool_name"])
        args = raw.get("tool_input")
        if isinstance(args, dict):
            if raw["tool_name"] == "Skill" and isinstance(args.get("skill"), str) and args["skill"] in names:
                data["arguments"] = {"skill": args["skill"]}
            if raw["tool_name"] in {"Agent", "Task"} and args.get("subagent_type") is not None:
                if not identifier(args["subagent_type"]):
                    raise ValueError("invalid_metadata")
                data["arguments"] = {"agent_type": args["subagent_type"]}
        if raw["tool_name"] == "Skill" and "arguments" not in data:
            data["skillNameStatus"] = "omitted"
        if kind != "PreToolUse":
            data["success"] = kind == "PostToolUse"
        # Claude's error field is free text, not a machine-readable error code.
    if kind in {"SubagentStart", "SubagentStop"} and not identifier(raw.get("agent_id")):
        raise ValueError("missing_agent_id")
    envelope = {"type": kind, "session_id": raw["session_id"], "data": data}
    if "timestamp" in raw:
        value = raw["timestamp"]
        try:
            if (not isinstance(value, str) or len(value) > 40
                    or datetime.fromisoformat(value.replace("Z", "+00:00")).tzinfo is None):
                raise ValueError()
        except ValueError as exc:
            raise ValueError("invalid_timestamp") from exc
        envelope["timestamp"] = value
    return envelope


def send(envelope):
    try:
        result = subprocess.run(
            ["python3", str(root / "kanban" / "audit.py"), "ingest", "--host", "claude"],
            input=json.dumps(envelope).encode(), stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, timeout=1.5, check=False)
    except subprocess.TimeoutExpired:
        diagnostic("ingest_timeout")
        return False
    except OSError:
        diagnostic("ingest_unavailable")
        return False
    if result.returncode != 0:
        diagnostic("ingest_failed")
        return False
    return True


def input_timeout(signum, frame):
    raise TimeoutError()


def main():
    signal.signal(signal.SIGALRM, input_timeout)
    signal.setitimer(signal.ITIMER_REAL, 1)
    try:
        with os.fdopen(3, "rb") as source:
            payload = source.read(LIMIT + 1)
    except (OSError, TimeoutError):
        diagnostic("input_unavailable")
        mark_gap()
        return
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
    if len(payload) > LIMIT:
        diagnostic("oversized_input")
        mark_gap()
        return
    try:
        raw = json.loads(payload)
    except (ValueError, UnicodeError, RecursionError):
        diagnostic("invalid_json")
        mark_gap()
        return
    try:
        envelope = normalize(raw)
    except (ValueError, TypeError) as error:
        codes = {"invalid_session_id", "unsupported_event", "invalid_metadata",
                 "missing_tool_call_id", "invalid_tool_name", "missing_agent_id",
                 "skill_policy_unavailable", "invalid_timestamp"}
        diagnostic(str(error) if isinstance(error, ValueError) and str(error) in codes else "invalid_input")
        mark_gap()
        return
    try:
        state.mkdir(mode=0o700, parents=True, exist_ok=True)
        fd = os.open(state / "claude.lock", os.O_CREAT | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "wb") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                diagnostic("observer_busy")
                mark_gap()
                return
            # Two fixed one-byte markers retain concurrent failures without storing payloads.
            if pending.exists():
                pending.replace(recovering)
            if recovering.exists():
                gap = {"type": "observer.gap", "session_id": envelope["session_id"],
                       "data": {"error": {"code": "claude_host_previous_write_failed"}}}
                if not send(gap):
                    mark_gap()
                    return
                recovering.unlink()
            if not send(envelope):
                mark_gap()
                return
            if envelope["type"] == "SessionStart":
                unsupported = {"type": "observer.unsupported", "session_id": envelope["session_id"],
                               "data": {"error": {"code": "claude_hooks_no_permission_or_semantic_consent"}}}
                if not send(unsupported):
                    mark_gap()
                unsupported["data"]["error"]["code"] = "public_skill_names_only"
                if not send(unsupported):
                    mark_gap()
    except OSError:
        diagnostic("observer_state_failed")
        mark_gap()


main()
PY
status=$?
if [ "$status" -ne 0 ]; then
  printf '%s\n' '[roberdan-os audit] adapter_failed' >&2
fi
exit 0
