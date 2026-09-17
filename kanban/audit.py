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
NATIVE_TYPES = {
    "tool.execution_start", "tool.execution_complete", "subagent.started",
    "subagent.completed", "subagent.failed", "session.start", "session.end",
    "user.message", "session.skills_loaded",
}
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
        clean["skills"] = sorted(set(names) & {
            "roberdan-twin", "roberto-twin", "rdos-roberdan-twin",
        })
    kind = {
        "session.skills_loaded": "skill_discovery_snapshot",
        "session.start": "session_started", "session.end": "session_ended",
        "user.message": "user_message_observed",
        "tool.execution_complete": "tool_observation",
        "subagent.started": "subagent_started",
        "subagent.completed": "subagent_completed", "subagent.failed": "subagent_failed",
    }.get(event_type, "unsupported_observation")
    if event_type == "tool.execution_start":
        args = clean.get("arguments", {})
        kind = ("skill_invocation_started" if clean.get("toolName") == "skill" else
                "consultation_started" if args.get("agent_type") == "twin" else "execution_started")
    return {
        "kind": kind, "host": host, "session_id": session_id, "native_type": event_type,
        "source_event_id": identifier(raw["id"]) if raw.get("id") is not None else None,
        "timestamp": timestamp(raw.get("timestamp")), "data": clean,
        "agent_id": clean.get("agentId"), "agent_name": clean.get("agentName"),
        "model": clean.get("model"), "metrics": metrics({}), "evidence": [],
        "provenance": "adapter_reported",
    }


def call_key(event):
    native_type = event.get("native_type", "")
    data = event.get("data", {})
    field = "agentId" if native_type.startswith("subagent.") else "toolCallId"
    if native_type.startswith(("tool.execution_", "subagent.")) and data.get(field):
        return event["host"], event["session_id"], field, data[field]
    return None


def phase(event):
    native_type = event.get("native_type")
    if native_type in ("tool.execution_start", "subagent.started"):
        return "start"
    if native_type in ("tool.execution_complete", "subagent.completed", "subagent.failed"):
        return "terminal"
    return None


def validate_links(event, previous):
    by_id = {row["id"]: row for row in previous}
    for field in REFS:
        ref = event.get(field)
        if not ref:
            continue
        if ref == event["id"] and (field, event["kind"]) in (
                ("request_id", "request"), ("decision_id", "decision")):
            continue
        require(ref in by_id, "reference does not exist")
        target = by_id[ref]
        expected = {"request_id": ("request",), "decision_id": ("decision",),
                    "recommendation_id": ("recommendation",),
                    "consultation_id": ("consultation_requested", "consultation_started",
                                        "consultation_completed", "consultation_failed"),
                    "execution_id": ("execution_started", "execution_completed", "execution_failed")}
        require(field not in expected or target["kind"] in expected[field], "reference has wrong event kind")
        for scope in ("request_id", "decision_id"):
            require(not target.get(scope) or not event.get(scope) or target[scope] == event[scope],
                    "reference crosses a request or decision")
    key = call_key(event)
    if key:
        require(not any(call_key(row) == key and phase(row) == phase(event) for row in previous),
                "duplicate native call phase; another attempt requires a different call identifier")
    if not event.get("native_type"):
        for prefix in ("consultation", "execution"):
            if event["kind"] in (prefix + "_completed", prefix + "_failed"):
                ref = event.get(prefix + "_id")
                require(ref in by_id and by_id[ref]["kind"] in (
                    prefix + "_started", prefix + "_requested"), "terminal must reference its start or request")
                require(not any(not row.get("native_type") and row["kind"] in (
                    prefix + "_completed", prefix + "_failed") and row.get(prefix + "_id") == ref
                    for row in previous), "duplicate declared terminal; another attempt requires another start")
    if event["kind"] == "bind":
        binding = (event["host"], event["session_id"], "toolCallId", event["tool_call_id"])
        require(any(call_key(row) == binding for row in previous), "bind target was not observed")
        require(not any(row["kind"] == "bind" and
                        (row["host"], row["session_id"], row["tool_call_id"]) ==
                        (event["host"], event["session_id"], event["tool_call_id"]) for row in previous),
                "native call is already bound; the audit cannot reassign it")


def private_path(write):
    require(hasattr(os, "getuid") and hasattr(os, "O_NOFOLLOW"),
            "owner-only audit storage requires a supported POSIX platform")
    home = Path(os.environ.get("RDA_HOME", str(Path.home() / ".roberdan-os")))
    requested = Path(os.environ.get("RDA_AUDIT_HOME", str(home / "private" / "audit")))
    require(requested.is_absolute() and not requested.is_symlink(), "audit directory must be absolute and not a symlink")
    root = requested.resolve()
    # Git's worktree marker is a directory OR a file, including in linked worktrees.
    for parent in (root, *root.parents):
        require(not os.path.lexists(parent / ".git"), "audit data must stay outside every Git worktree")
    os.umask(0o077)
    if write:
        root.mkdir(mode=0o700, parents=True, exist_ok=True)
    if root.exists():
        info = root.lstat()
        require(stat.S_ISDIR(info.st_mode) and info.st_uid == os.getuid()
                and stat.S_IMODE(info.st_mode) == 0o700, "audit directory must be owned by you with mode 0700")
    path = root / "events.sqlite3"
    if write:
        try:
            fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
        except FileExistsError:
            pass
        else:
            os.close(fd)
    for candidate in (path, Path(str(path) + "-journal"), Path(str(path) + "-wal"), Path(str(path) + "-shm")):
        if os.path.lexists(candidate):
            info = candidate.lstat()
            require(stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid()
                    and info.st_nlink == 1 and stat.S_IMODE(info.st_mode) == 0o600,
                    "audit files must be regular, unlinked, owned by you and mode 0600")
    return path


def initialize(db):
    db.execute("""CREATE TABLE IF NOT EXISTS events (
        seq INTEGER PRIMARY KEY, id TEXT NOT NULL UNIQUE, source_key TEXT UNIQUE,
        input_hash TEXT NOT NULL, body TEXT NOT NULL, previous_hash TEXT NOT NULL,
        hash TEXT NOT NULL)""")
    for operation in ("UPDATE", "DELETE"):
        db.execute(f"""CREATE TRIGGER IF NOT EXISTS no_{operation.lower()}
            BEFORE {operation} ON events BEGIN SELECT RAISE(ABORT, 'append-only audit'); END""")
    db.execute("PRAGMA user_version = 1")


def load(db):
    require(db.execute("PRAGMA quick_check").fetchall() == [("ok",)], "audit database is damaged")
    require(db.execute("PRAGMA user_version").fetchone()[0] == 1, "unsupported or uninitialized audit schema")
    triggers = {row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type = 'trigger'")}
    require({"no_update", "no_delete"} <= triggers, "append-only audit guards are missing")
    result, previous_hash = [], ""
    for seq, event_id, source_key, input_hash, body, prev, stored_hash in db.execute("SELECT * FROM events ORDER BY seq"):
        require(seq == len(result) + 1 and prev == previous_hash, "audit sequence is damaged")
        require(digest([seq, event_id, source_key, input_hash, body, prev]) == stored_hash,
                "audit record integrity failure")
        try:
            event = json.loads(body)
        except (ValueError, TypeError) as exc:
            raise AuditError("audit record is damaged") from exc
        require(isinstance(event, dict) and event.get("id") == event_id
                and event.get("schema_version") == 1, "invalid audit record")
        validate_links(event, result)
        result.append(event)
        previous_hash = stored_hash
    return result, previous_hash


def source_key(event):
    if event.get("source_event_id"):
        return canonical(["native", event["host"], event["session_id"], event["source_event_id"]])
    if event["kind"] == "bind":
        return canonical(["bind", event["host"], event["session_id"], event["tool_call_id"]])
    if event.get("id"):
        return canonical(["manual", event["id"]])
    return None


def append(event):
    path = private_path(True)
    db = sqlite3.connect(path, timeout=2)
    try:
        db.execute("BEGIN IMMEDIATE")
        version = db.execute("PRAGMA user_version").fetchone()[0]
        if version == 0:
            require(not db.execute("SELECT name FROM sqlite_master").fetchall(), "refusing an unknown database")
            initialize(db)
        previous, previous_hash = load(db)
        key, fingerprint = source_key(event), digest(event)
        existing = db.execute("SELECT id, input_hash FROM events WHERE source_key = ?", (key,)).fetchone() if key else None
        if existing:
            require(existing[1] == fingerprint, "conflicting duplicate event")
            db.rollback()
            original = next(row for row in previous if row["id"] == existing[0])
            return receipt(original, True)
        event = dict(event)
        event.setdefault("id", str(uuid4()))
        event.update(schema_version=1, recorded_at=datetime.now(timezone.utc).isoformat())
        for field in REFS:
            event.setdefault(field, None)
        if event["kind"] == "request":
            require(event["request_id"] in (None, event["id"]), "request_id must match the request event id")
            event["request_id"] = event["id"]
        if event["kind"] == "decision":
            require(event["decision_id"] in (None, event["id"]), "decision_id must match the decision event id")
            event["decision_id"] = event["id"]
        elif event["decision_id"]:
            decision = next((row for row in previous if row["id"] == event["decision_id"]), {})
            if not event["request_id"]:
                event["request_id"] = decision.get("request_id")
        validate_links(event, previous)
        if event.get("native_type") == "tool.execution_complete":
            start = next((row for row in previous if call_key(event) and call_key(row) == call_key(event)
                          and phase(row) == "start"), None)
            if start:
                state = event["data"].get("success")
                suffix = (("succeeded" if start["kind"] == "skill_invocation_started" else "completed")
                          if state is True else "failed" if state is False else "terminal_unknown")
                event["kind"] = start["kind"].removesuffix("_started") + "_" + suffix
                event["parent_event_id"] = start["id"]
        seq, body = len(previous) + 1, canonical(event)
        record = [seq, event["id"], key, fingerprint, body, previous_hash]
        db.execute("INSERT INTO events VALUES (?, ?, ?, ?, ?, ?, ?)", (*record, digest(record)))
        db.commit()
        return receipt(event, False)
    finally:
        db.close()


def receipt(event, duplicate):
    return {"ok": True, "id": event["id"], "kind": event["kind"], "duplicate": duplicate,
            "provenance": event["provenance"], "permission_authority": False}


def read_events():
    path = private_path(False)
    if not path.exists():
        return [], False
    db = sqlite3.connect(path.as_uri() + "?mode=ro", uri=True, timeout=2)
    try:
        db.execute("BEGIN")
        rows, _ = load(db)
        return rows, True
    finally:
        db.close()


def bindings(rows):
    return {(row["host"], row["session_id"], "toolCallId", row["tool_call_id"]): row
            for row in rows if row["kind"] == "bind"}


def attempts(rows):
    bound = bindings(rows)
    groups = {}
    for row in rows:
        if phase(row):
            key = call_key(row) or ("unlinked", row["id"])
            groups.setdefault(key, {})[phase(row)] = row
        elif row["kind"] in ("consultation_started", "execution_started") and not row.get("native_type"):
            groups[("declared", row["id"])] = {"start": row}
    for row in rows:
        if not row.get("native_type") and row["kind"] in (
                "consultation_completed", "consultation_failed", "execution_completed", "execution_failed"):
            ref = row.get("consultation_id") or row.get("execution_id") or row.get("parent_event_id")
            if ref and ("declared", ref) in groups:
                groups[("declared", ref)]["terminal"] = row
            else:
                groups[("declared-terminal", row["id"])] = {"terminal": row}
    result = []
    for pair in groups.values():
        start, end = pair.get("start"), pair.get("terminal")
        origin = start or end
        data = origin.get("data", {})
        state = end.get("data", {}).get("success") if end else None
        if end and (end["kind"].endswith("_completed") or end["kind"].endswith("_failed")):
            state = end["kind"].endswith("_completed")
        status = ("terminal_not_observed" if not end else "start_not_observed" if not start
                  else "succeeded" if state is True else "failed" if state is False else "terminal_status_unknown")
        result.append({"kind": start["kind"] if start else "unlinked_terminal",
                       "start_event_id": start["id"] if start else None,
                       "terminal_event_id": end["id"] if end else None, "status": status,
                       "provenance": origin["provenance"], "host": origin.get("host"),
                       "session_id": origin.get("session_id"), "tool_call_id": data.get("toolCallId"),
                       "agent_id": data.get("agentId"), "tool_name": data.get("toolName"),
                       "skill": data.get("arguments", {}).get("skill"),
                       "binding_event_id": bound.get(call_key(origin), {}).get("id"),
                       "decision_id": origin.get("decision_id") or bound.get(call_key(origin), {}).get("decision_id")})
    return result


def coverage(rows, exists):
    observations = [row for row in rows if row["provenance"] == "adapter_reported"]
    unresolved = [attempt for attempt in attempts(rows) if attempt["status"] not in ("succeeded", "failed")]
    return {
        "store_exists": exists, "scope": "recorded events only",
        "supported_native_types": sorted(NATIVE_TYPES),
        "observed_host_sessions": sorted({(row["host"], row["session_id"]) for row in observations}),
        "native_events": len(observations),
        "unsupported_events": [row["id"] for row in observations if row["kind"] == "unsupported_observation"],
        "unlinked_native_events": [row["id"] for row in observations if phase(row) and not call_key(row)],
        "unresolved_attempts": unresolved,
        "pending_consultations": [row["id"] for row in rows if row["kind"] == "consultation_requested"
                                 and not any(other.get("consultation_id") == row["id"]
                                             or other.get("parent_event_id") == row["id"] for other in rows)],
        "declarations": [row for row in rows if row["kind"] == "coverage"],
        "limitations": LIMITS, "permission_authority": False,
    }


def report(command, rows, exists, event_id=None, limit=20, offset=0):
    observed = coverage(rows, exists)
    if command == "coverage":
        return observed
    if command == "check":
        return {"store_exists": exists, "integrity": "ok" if exists else "not_initialized",
                "events": len(rows), "permission_authority": False}
    if command == "stats":
        counts = {}
        for row in rows:
            counts[row["kind"]] = counts.get(row["kind"], 0) + 1
        responses = [row for row in rows if row["kind"] == "human_response"]
        answered = {row["recommendation_id"] for row in responses}
        return {
            "events": len(rows), "by_kind": counts, "attempts": attempts(rows),
            "unanswered_recommendations": [row["id"] for row in rows
                                           if row["kind"] == "recommendation" and row["id"] not in answered],
            "decisions_without_outcome": [row["id"] for row in rows if row["kind"] == "decision"
                                          and not any(other["kind"] == "outcome" and
                                                      other.get("decision_id") == row["id"] for other in rows)],
            "human_attributed_unverified": {answer: sum(row["response"] == answer for row in responses)
                                           for answer in ("yes", "no", "correction", "deferred")},
            "verified_human_responses": 0, "agreement_rate": None, "cost": None,
            "cost_note": "No authenticated, decision-attributed cost total is collected.",
            "coverage": observed,
        }
    if command == "show":
        event = next((row for row in rows if row["id"] == event_id), None)
        require(event is not None, "event does not exist")
        bound = bindings(rows)
        def decision_of(row):
            return row.get("decision_id") or bound.get(call_key(row), {}).get("decision_id")
        requested_decisions = {row["id"] for row in rows if row["kind"] == "decision"
                               and row.get("request_id") == event_id}
        related = [row for row in rows if row["id"] != event_id and (
            (decision_of(event) and decision_of(row) == decision_of(event))
            or (event["kind"] == "request" and
                (row.get("request_id") == event_id or decision_of(row) in requested_decisions))
            or (call_key(event) and call_key(row) == call_key(event)))]
        included = {event_id, *(row["id"] for row in related)}
        by_id = {row["id"]: row for row in rows}
        pending = [event, *related]
        while pending:
            current = pending.pop()
            for field in REFS:
                ref = current.get(field)
                if ref and ref not in included:
                    included.add(ref)
                    related.append(by_id[ref])
                    pending.append(by_id[ref])
        return {"event": event, "related": related, "attempts": attempts([event, *related])}
    return {"schema_version": 1, "total": len(rows),
            "events": rows if command == "export" else rows[offset:offset + limit],
            "coverage": observed}


def human_report(command, result):
    print("Audit: recorded claims and adapter observations; never permission.")
    if command == "check":
        print(f"Integrity: {result['integrity']}; events: {result['events']}")
        return
    if command == "coverage":
        print(f"Native events: {result['native_events']}; unresolved attempts: {len(result['unresolved_attempts'])}")
        print(f"Unsupported events: {len(result['unsupported_events'])}; unlinked events: {len(result['unlinked_native_events'])}")
        print(f"Consultations awaiting a recorded response: {len(result['pending_consultations'])}")
        for item in result["unresolved_attempts"]:
            print(f"  {item['start_event_id'] or item['terminal_event_id']} {item['status']}")
        print("Coverage excludes unobserved sessions and earlier events; adapter replay is not authenticated.")
        return
    if command == "stats":
        print(f"Events: {result['events']}; unanswered recommendations: {len(result['unanswered_recommendations'])}")
        print(f"Decisions without an outcome: {len(result['decisions_without_outcome'])}")
        print(f"Attributed, unverified human responses: {canonical(result['human_attributed_unverified'])}")
        print(f"Unresolved attempts: {len(result['coverage']['unresolved_attempts'])}; agreement: unknown; cost: unknown")
        for attempt in result["attempts"]:
            print(f"  {attempt['start_event_id'] or attempt['terminal_event_id']} {attempt['kind']} {attempt['status']}")
        return
    events = [result["event"], *result["related"]] if command == "show" else result["events"]
    if not events:
        print("No recorded events; usage outside coverage is unknown.")
    for row in events:
        print(f"{row['id']} {row['kind']} [{row['provenance']}] {row.get('summary') or ''}".rstrip())
    if command == "list":
        print(f"Showing {len(events)} of {result['total']}; use --json or export for structured detail.")


def parse_input(value):
    if value is None:
        require(not sys.stdin.isatty(), "provide --json or JSON on stdin")
        value = sys.stdin.buffer.read(MAX_INPUT + 1)
    require(len(value.encode() if isinstance(value, str) else value) <= MAX_INPUT, "JSON input exceeds 16384 bytes")

    def pairs(items):
        result = {}
        for key, item in items:
            require(key not in result, "duplicate JSON field")
            result[key] = item
        return result

    def invalid_constant(_value):
        raise AuditError("non-finite JSON number")

    try:
        result = json.loads(value, object_pairs_hook=pairs, parse_constant=invalid_constant)
    except (ValueError, UnicodeError, RecursionError) as exc:
        raise AuditError("invalid JSON input") from exc
    require(isinstance(result, dict), "JSON input must be an object")
    return result


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise AuditError("invalid command arguments; use --help")


def main():
    parser = Parser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    record = commands.add_parser("record", help="Append an explicitly declared semantic event")
    record.add_argument("kind", choices=sorted(KINDS))
    record.add_argument("--json", metavar="JSON")
    ingest = commands.add_parser("ingest", help="Append sanitized adapter observations, not authenticated evidence")
    ingest.add_argument("--host", required=True, choices=("copilot", "claude"))
    ingest.add_argument("--json", metavar="JSON")
    for name in ("list", "show", "stats", "coverage", "check", "export"):
        command = commands.add_parser(name)
        command.add_argument("--json", action="store_true", help="Print structured JSON")
        if name == "show":
            command.add_argument("id")
        if name == "list":
            command.add_argument("--limit", type=int, default=20)
            command.add_argument("--offset", type=int, default=0)
    try:
        args = parser.parse_args()
        if args.command in ("record", "ingest"):
            raw = parse_input(args.json)
            event = manual(args.kind, raw) if args.command == "record" else native(args.host, raw)
            print(canonical(append(event)))
            return 0
        require(1 <= getattr(args, "limit", 20) <= 1000 and getattr(args, "offset", 0) >= 0,
                "list requires limit 1..1000 and nonnegative offset")
        if args.command == "show":
            identifier(args.id)
        rows, exists = read_events()
        result = report(args.command, rows, exists, getattr(args, "id", None),
                        getattr(args, "limit", 20), getattr(args, "offset", 0))
        if args.json:
            print(canonical(result))
        else:
            human_report(args.command, result)
        return 0
    except AuditError as exc:
        print(f"audit: {exc}; operation not completed.", file=sys.stderr)
    except UnicodeError:
        print("audit: invalid Unicode input; operation not completed.", file=sys.stderr)
    except (OSError, sqlite3.Error) as exc:
        print(f"audit: storage unavailable or damaged ({type(exc).__name__}); operation not completed.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
