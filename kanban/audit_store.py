#!/usr/bin/env python3
"""Append-only audit storage and coverage calculations."""
import json
import os
from datetime import datetime, timezone
from pathlib import Path
import sqlite3
import stat
from uuid import uuid4

from audit_schema import (
    AGENT_CALL_TYPES, AuditError, LIMITS, NATIVE_TYPES, REFS, START_TYPES, TERMINAL_TYPES, TOOL_TERMINAL_TYPES,
    canonical, digest, identifier, metrics,
    require,
)

def call_key(event):
    native_type = event.get("native_type", "")
    data = event.get("data", {})
    if native_type not in START_TYPES + TERMINAL_TYPES:
        return None
    field = "agentId" if native_type in AGENT_CALL_TYPES else "toolCallId"
    if data.get(field):
        return event["host"], event["session_id"], field, data[field]
    return None


def phase(event):
    native_type = event.get("native_type")
    if native_type in START_TYPES:
        return "start"
    if native_type in TERMINAL_TYPES:
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
        if event.get("native_type") in TERMINAL_TYPES and call_key(event):
            start = next((row for row in previous if call_key(row) == call_key(event)
                          and phase(row) == "start"), None)
            if start:
                event["parent_event_id"] = start["id"]
                state = event["data"].get("success")
                if event["native_type"] in TOOL_TERMINAL_TYPES:
                    suffix = (("succeeded" if start["kind"] == "skill_invocation_started" else "completed")
                              if state is True else "failed" if state is False else "terminal_unknown")
                    event["kind"] = start["kind"].removesuffix("_started") + "_" + suffix
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
        if end:
            if end.get("native_type"):
                if state is None and end["kind"].endswith("_failed"):
                    state = False
            elif end["kind"].endswith("_completed") or end["kind"].endswith("_failed"):
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
        "observer_gaps": [row["id"] for row in observations if row["kind"] == "observer_gap"],
        "observer_limitations": [{"id": row["id"], "host": row["host"], "session_id": row["session_id"],
                                  "code": row.get("data", {}).get("error", {}).get("code")}
                                 for row in observations if row["kind"] == "observer_limitation"],
        "unlinked_native_events": [row["id"] for row in observations if phase(row) and not call_key(row)],
        "unresolved_attempts": unresolved,
        "pending_consultations": [row["id"] for row in rows if row["kind"] == "consultation_requested"
                                 and not any(other.get("consultation_id") == row["id"]
                                             or other.get("parent_event_id") == row["id"] for other in rows)],
        "declarations": [row for row in rows if row["kind"] == "coverage"],
        "limitations": LIMITS, "permission_authority": False,
    }
