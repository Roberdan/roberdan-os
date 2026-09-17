#!/usr/bin/env python3
"""Human and structured audit reports."""
from audit_schema import REFS, canonical, require
from audit_store import attempts, bindings, call_key, coverage, phase

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

