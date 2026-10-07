#!/usr/bin/env python3
"""Prove a known synthetic skill-use delta is observed exactly once per session."""

from __future__ import annotations

from datetime import datetime, timezone
import os
from pathlib import Path
import sqlite3
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "bin"))
sys.path.insert(0, str(ROOT / "kanban"))

from audit_schema import POLICY, native  # noqa: E402
from audit_store import append  # noqa: E402
from telemetry_skills import build_report  # noqa: E402

NOW = datetime(2026, 10, 7, 12, 0, tzinfo=timezone.utc)


def skill(report: dict[str, object], name: str) -> dict[str, object]:
    return next(item for item in report["skills"] if item["name"] == name)


with tempfile.TemporaryDirectory() as raw_tmp:
    tmp = Path(raw_tmp)
    audit = tmp / "audit"
    audit.mkdir(mode=0o700)
    store = tmp / "sessions.db"
    os.environ["RDA_AUDIT_HOME"] = str(audit)
    os.environ["RDA_SESSION_STORE"] = str(store)

    db = sqlite3.connect(store)
    db.execute(
        "CREATE TABLE session_files("
        "session_id TEXT, file_path TEXT, first_seen_at TEXT)"
    )
    db.executemany(
        "INSERT INTO session_files VALUES (?, ?, ?)",
        [
            ("session-a", "deliverables/launch-film.mp4", "2026-10-07T09:00:00Z"),
            ("session-c", "deliverables/other-film.mov", "2026-10-07T09:30:00Z"),
        ],
    )
    db.commit()
    db.close()

    baseline = skill(build_report(ROOT, 30, NOW), "film-director")
    assert baseline["observed_sessions"] is None
    assert baseline["opportunity"]["candidate_sessions"] == 2
    assert baseline["opportunity"]["status"] == "non misurabile"

    def record(event_id: str, session_id: str) -> None:
        append(
            native(
                "copilot",
                {
                    "id": event_id,
                    "type": "tool.execution_start",
                    "session_id": session_id,
                    "timestamp": "2026-10-07T10:00:00Z",
                    "data": {
                        "toolCallId": event_id,
                        "toolName": "Skill",
                        "arguments": {"skill": "film-director"},
                        "skillNamePolicy": POLICY,
                    },
                },
            )
        )

    record("event-a", "session-a")
    first = skill(build_report(ROOT, 30, NOW), "film-director")
    assert first["observed_sessions"] == 1
    assert first["opportunity"]["cohort_sessions"] == 1
    assert first["opportunity"]["invoked_in_cohort"] == 1
    assert first["opportunity"]["uses_outside_cohort"] == 0

    record("event-a-duplicate-session", "session-a")
    deduplicated = skill(build_report(ROOT, 30, NOW), "film-director")
    assert deduplicated["observed_sessions"] == 1
    assert deduplicated["opportunity"]["invoked_in_cohort"] == 1

    record("event-b", "session-b")
    second_session = skill(build_report(ROOT, 30, NOW), "film-director")
    assert second_session["observed_sessions"] == 2
    assert second_session["opportunity"]["cohort_sessions"] == 1
    assert second_session["opportunity"]["invoked_in_cohort"] == 1
    assert second_session["opportunity"]["uses_outside_cohort"] == 1

print("test-telemetry-positive-control: PASS")
