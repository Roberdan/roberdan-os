"""Public JSON CLI. Disabled and all errors exit 2; dry-run/evaluated exit 0."""

import argparse
import json
from pathlib import Path

from . import client, core, profiles


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise core.JevError("invalid_arguments")


def main(argv=None):
    parser = Parser(description="Optional Jev judgments; dry-run by default.")
    commands = parser.add_subparsers(dest="command", required=True, parser_class=Parser)
    commands.add_parser("profiles")
    commands.add_parser("status")
    evaluate = commands.add_parser("evaluate")
    evaluate.add_argument("profile", choices=core.PROFILES)
    evaluate.add_argument("--input", type=Path, required=True)
    evaluate.add_argument("--live", action="store_true")
    evaluate.add_argument("--approved-sha256")
    try:
        args = parser.parse_args(argv)
        if args.command == "profiles":
            result = {"profiles": list(core.PROFILES), "model": core.MODEL,
                      "rubric_version": profiles.RUBRIC_VERSION, "default": "disabled",
                      "max_payload_utf8_bytes": core.MAX_REQUEST_BYTES,
                      "notice": profiles.NOTICE}
        elif args.command == "status":
            result = client.status()
        else:
            with args.input.open("rb") as stream:
                raw = stream.read(core.MAX_INPUT_BYTES + 1)
            core.require(len(raw) <= core.MAX_INPUT_BYTES, "input_too_large")
            result = client.evaluate(args.profile, core.loads(raw), live=args.live,
                                     approved_sha256=args.approved_sha256)
    except core.JevError as error:
        result = core.not_evaluated(str(error))
    except OSError:
        result = core.not_evaluated("local_io_error")
    print(json.dumps(result, ensure_ascii=True, allow_nan=False, sort_keys=True))
    return 2 if result.get("status") == "not_evaluated" else 0
