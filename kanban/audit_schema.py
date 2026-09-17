#!/usr/bin/env python3
"""Private decision receipts. Neither declarations nor adapter replays grant permission."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import sqlite3
import stat
import sys
from datetime import datetime, timezone
from uuid import uuid4

MAX_INPUT = 16384
MAX_SUMMARY = 512
ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.:/@+#-]{0,255}\Z")
SECRET = re.compile(
    r"(?:gh[pousr]_[A-Za-z0-9]{12,}|github_pat_[A-Za-z0-9_]+|"
    r"sk-[A-Za-z0-9_-]{16,}|AKIA[A-Z0-9]{16}|-----BEGIN .*PRIVATE KEY|"
    r"\b(?:password|passwd|secret|token|api[_-]?key)\s*[:=]\s*\S+|"
    r"\bBearer\s+\S+)", re.I
)
KINDS = {
    "request", "decision", "skill_load", "consultation_requested",
    "consultation_started", "consultation_completed", "consultation_failed",
    "recommendation", "human_response", "escalation", "execution_started",
    "execution_completed", "execution_failed", "outcome", "bind", "coverage",
}
NATIVE_KINDS = {
    "tool.execution_start": "execution_started", "tool.execution_complete": "tool_observation",
    "subagent.started": "subagent_started", "subagent.completed": "subagent_completed",
    "subagent.failed": "subagent_failed", "subagent.configured": "subagent_configured",
    "session.start": "session_started", "session.end": "session_ended",
    "session.shutdown": "session_ended", "session.skills_loaded": "skill_discovery_snapshot",
    "user.message": "user_message_observed",
    # Claude command hooks name their own events; PostToolUseFailure carries no error code.
    "SessionStart": "session_started", "SessionEnd": "session_ended",
    "PreToolUse": "execution_started", "PostToolUse": "tool_observation",
    "PostToolUseFailure": "tool_observation", "SubagentStart": "subagent_started",
    "SubagentStop": "subagent_stopped",
    # Observers report their own coverage: a missing observer_end is not a clean session.
    "observer.start": "observer_started", "observer.end": "observer_ended",
    "observer.gap": "observer_gap", "observer.unsupported": "observer_limitation",
}
NATIVE_TYPES = set(NATIVE_KINDS)
TOOL_START_TYPES = ("tool.execution_start", "PreToolUse")
TOOL_TERMINAL_TYPES = ("tool.execution_complete", "PostToolUse", "PostToolUseFailure")
AGENT_CALL_TYPES = ("subagent.started", "subagent.completed", "subagent.failed",
                    "SubagentStart", "SubagentStop")
START_TYPES = TOOL_START_TYPES + ("subagent.started", "SubagentStart")
TERMINAL_TYPES = TOOL_TERMINAL_TYPES + ("subagent.completed", "subagent.failed", "SubagentStop")
TWIN_SELECTORS = ("roberdan-twin", "roberto-twin", "rdos-roberdan-twin")
REFS = ("request_id", "decision_id", "parent_event_id", "consultation_id",
        "recommendation_id", "execution_id")
IDENTIFIERS = ("id", "session_id", "agent_id", "agent_name", "model", "option_id",
               "tool_call_id") + REFS
MANUAL_FIELDS = set(IDENTIFIERS) | {
    "host", "summary", "evidence", "timestamp", "response", "metrics", "coverage",
}
METRIC_FIELDS = ("cost", "cost_unit", "input_tokens", "output_tokens",
                 "duration_ms", "scope", "source")
NATIVE_IDS = ("toolCallId", "toolName", "model", "agentId", "agentName",
              "parentToolCallId", "requestId")
LIMITS = [
    "Adapter replay is not authenticated; this audit never grants permission.",
    "Discovery is not invocation, consultation, recommendation or human approval.",
    "Unobserved sessions and events before observer attachment are unknown.",
    "An observed gap marks lost events; their number and content stay unrecoverable.",
    "Missing terminal events are unresolved, not successful or necessarily failed.",
    "Summaries are declarations; secret-pattern checks cannot recognize every secret.",
    "Local integrity checks do not prevent rewriting by the same OS user.",
]


class AuditError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise AuditError(message)


def canonical(value):
    return json.dumps(value, ensure_ascii=True, sort_keys=True,
                      separators=(",", ":"), allow_nan=False)


def digest(value):
    return hashlib.sha256(canonical(value).encode()).hexdigest()


def identifier(value):
    require(isinstance(value, str) and ID.fullmatch(value) is not None
            and not SECRET.search(value), "invalid or sensitive identifier")
    return value


def text(value):
    require(isinstance(value, str) and 0 < len(value) <= MAX_SUMMARY
            and value.strip() and not any(ord(c) < 32 or ord(c) == 127
                                         or 0xD800 <= ord(c) <= 0xDFFF for c in value)
            and not SECRET.search(value), "invalid, oversized or sensitive summary")
    return value


def timestamp(value):
    if value is None:
        return None
    require(isinstance(value, str) and len(value) <= 40, "invalid timestamp")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise AuditError("invalid timestamp") from exc
    require(parsed.tzinfo is not None, "timestamp must include a timezone")
    return value


def evidence(values):
    require(isinstance(values, list) and len(values) <= 16, "invalid evidence list")
    for value in values:
        identifier(value)
        require(re.match(r"^(git|event|test|artifact|kb):.+", value) is not None,
                "evidence must be a typed reference, not raw output")
    return values


def metrics(value):
    require(isinstance(value, dict) and not value.keys() - set(METRIC_FIELDS),
            "invalid metrics")
    result = dict.fromkeys(METRIC_FIELDS)
    result.update(value)
    for key in ("cost", "input_tokens", "output_tokens", "duration_ms"):
        number = result[key]
        require(number is None or (type(number) in (int, float)
                and (type(number) is int or math.isfinite(number)) and number >= 0), "invalid metric value")
    for key in ("input_tokens", "output_tokens"):
        require(result[key] is None or type(result[key]) is int, "tokens must be integers")
    if any(result[key] is not None for key in ("cost", "input_tokens", "output_tokens", "duration_ms")):
        evidence([result["source"]])
        require(result["scope"] in ("event", "execution", "consultation", "session"),
                "measured metrics require an explicit scope")
    if result["cost"] is not None:
        identifier(result["cost_unit"])
    for key in ("cost_unit", "source", "scope"):
        if result[key] is not None:
            identifier(result[key])
    return result


def coverage_declaration(value):
    require(isinstance(value, dict)
            and set(value) <= {"status", "event_types", "reason"}, "invalid coverage declaration")
    require(value.get("status") in ("active", "partial", "unavailable", "ended"),
            "coverage requires a status")
    types = value.get("event_types", [])
    require(isinstance(types, list) and len(types) <= 32, "invalid coverage event types")
    return {"status": value["status"], "event_types": [identifier(t) for t in types],
            "reason": text(value["reason"]) if "reason" in value else None}


def manual(kind, raw):
    require(kind in KINDS, "unsupported semantic event kind")
    require(not raw.keys() - MANUAL_FIELDS, "unknown record field")
    out = {key: identifier(raw[key]) if raw.get(key) is not None else None
           for key in IDENTIFIERS if key != "id"}
    if "id" in raw:
        out["id"] = identifier(raw["id"])
    out.update(kind=kind, host=raw.get("host"), timestamp=timestamp(raw.get("timestamp")),
               summary=text(raw["summary"]) if "summary" in raw else None,
               evidence=evidence(raw.get("evidence", [])), metrics=metrics(raw.get("metrics", {})),
               provenance="human_attributed_unverified" if kind == "human_response" else "agent_declared")
    require(out["host"] in (None, "copilot", "claude", "codex", "manual"), "invalid host")
    if kind in ("request", "decision", "recommendation", "escalation", "outcome"):
        require(out["summary"] is not None, "this semantic event requires a summary")
    if kind not in ("request", "coverage", "skill_load"):
        require(out.get("decision_id") or kind == "decision", "semantic event requires decision_id")
    if kind == "skill_load":
        require(out.get("request_id") or out.get("decision_id"), "skill_load requires request_id or decision_id")
    if kind == "decision":
        require(out.get("request_id"), "decision requires request_id")
    if kind == "human_response":
        require(out.get("recommendation_id"), "human response requires recommendation_id")
        require(raw.get("response") in ("yes", "no", "correction", "deferred"),
                "human response requires yes, no, correction or deferred")
        out["response"] = raw["response"]
    else:
        require("response" not in raw, "response is only valid for human_response")
    if kind == "coverage":
        out["coverage"] = coverage_declaration(raw.get("coverage"))
    else:
        require("coverage" not in raw, "coverage is only valid for a coverage event")
    if kind == "bind":
        require(out["host"] in ("copilot", "claude") and out.get("session_id")
                and out.get("tool_call_id"), "bind requires exact host, session_id and tool_call_id")
    else:
        require("tool_call_id" not in raw, "tool_call_id is only valid for bind")
    for prefix in ("consultation", "execution"):
        if kind in (prefix + "_completed", prefix + "_failed"):
            require(out.get(prefix + "_id"), "terminal declaration requires its consultation_id or execution_id")
    return out


def native(host, raw):
    require(host in ("copilot", "claude"), "unsupported adapter host")
    event_type = identifier(raw.get("type"))
    session_id = identifier(raw.get("session_id"))
    data = raw.get("data", {})
    require(isinstance(data, dict), "native data must be an object")
    clean = {key: identifier(data[key]) for key in NATIVE_IDS if data.get(key) is not None}
    if "success" in data:
        require(type(data["success"]) is bool, "native success must be a boolean")
        clean["success"] = data["success"]
    if "error" in data:
        require(isinstance(data["error"], dict), "native error must contain only a code")
        if "code" in data["error"]:
            clean["error"] = {"code": identifier(data["error"]["code"])}
    if "arguments" in data:
        require(isinstance(data["arguments"], dict), "sanitized arguments must be an object")
        clean["arguments"] = {key: identifier(data["arguments"][key])
                              for key in ("skill", "agent_type", "name") if key in data["arguments"]}
    if "skills" in data:
        require(isinstance(data["skills"], list) and len(data["skills"]) <= 64,
                "skills must be a bounded list of names")
        names = [identifier(name) for name in data["skills"]]
        clean["skills"] = sorted(set(names) & set(TWIN_SELECTORS))
    kind = NATIVE_KINDS.get(event_type, "unsupported_observation")
    if event_type in TOOL_START_TYPES:
        kind = started_kind(clean)
    return {
        "kind": kind, "host": host, "session_id": session_id, "native_type": event_type,
        "source_event_id": identifier(raw["id"]) if raw.get("id") is not None else None,
        "timestamp": timestamp(raw.get("timestamp")), "data": clean,
        "agent_id": clean.get("agentId"), "agent_name": clean.get("agentName"),
        "model": clean.get("model"), "metrics": metrics({}), "evidence": [],
        "provenance": "adapter_reported",
    }


def started_kind(clean):
    """A generic skill or agent is ordinary execution; only the twin selectors are pertinent."""
    args = clean.get("arguments", {})
    if (clean.get("toolName") or "").lower() == "skill":
        return "skill_invocation_started" if args.get("skill") in TWIN_SELECTORS else "execution_started"
    return "consultation_started" if args.get("agent_type") == "twin" else "execution_started"


