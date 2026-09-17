#!/usr/bin/env python3
"""CLI for the private decision audit."""
import argparse
import json
import sqlite3
import sys

from audit_schema import AuditError, KINDS, canonical, identifier, manual, native, require
from audit_report import human_report, report
from audit_store import append, read_events

MAX_INPUT = 16384

def parse_input(value):
    if value is None:
        require(not sys.stdin.isatty(), "provide --json or JSON on stdin")
        value = sys.stdin.buffer.read(MAX_INPUT + 1)
    require(len(value.encode() if isinstance(value, str) else value) <= MAX_INPUT,
            "JSON input exceeds 16384 bytes")

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
