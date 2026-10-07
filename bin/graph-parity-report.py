#!/usr/bin/env python3
"""Compare source-scoped gbrain symbol lookup with immediately fresh rg."""

from __future__ import annotations

import argparse
import json
import os
import secrets
import subprocess
import sys
from pathlib import Path
from typing import Any

NEGATIVE = "__rda_gbrain_negative_control_9f4c0e__"


def command(
    argv: list[str], cwd: Path, env: dict[str, str]
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        cwd=cwd,
        env=env,
        check=False,
        capture_output=True,
        text=True,
        timeout=90,
    )


def gbrain_count(
    binary: str, source: str, symbol: str, cwd: Path, env: dict[str, str]
) -> tuple[int | None, str]:
    try:
        result = command(
            [binary, "code-def", "--source", source, symbol], cwd, env
        )
        if result.returncode != 0:
            return None, "command-failed"
        data = json.loads(result.stdout)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError):
        return None, "unusable-output"
    if (
        data.get("scope") != "single"
        or data.get("source_id") != source
        or not isinstance(data.get("count"), int)
    ):
        return None, "wrong-scope"
    return data["count"], "trusted"


def rg_has(binary: str, pattern: str, glob: str, cwd: Path, env: dict[str, str]) -> bool:
    try:
        result = command([binary, "-q", pattern, "--glob", glob, "."], cwd, env)
    except (OSError, subprocess.SubprocessError):
        return False
    return result.returncode == 0


def control(name: str, status: str, observation: str) -> dict[str, str]:
    return {"name": name, "status": status, "observation": observation}


def inspect(args: argparse.Namespace) -> dict[str, Any]:
    repo = args.repo.resolve()
    source = args.source or (repo / ".gbrain-source").read_text().strip()
    env = dict(os.environ)
    controls: list[dict[str, str]] = []

    positive, positive_trust = gbrain_count(
        args.gbrain, source, args.positive, repo, env
    )
    if positive is None:
        controls.append(control("positive-symbol", "inconclusive", positive_trust))
    elif positive > 0:
        controls.append(control("positive-symbol", "ok", "known-symbol-resolved"))
    else:
        controls.append(control("positive-symbol", "broken", "known-symbol-missing"))

    negative, negative_trust = gbrain_count(
        args.gbrain, source, NEGATIVE, repo, env
    )
    if negative is None:
        controls.append(control("negative-symbol", "inconclusive", negative_trust))
    elif negative == 0:
        controls.append(control("negative-symbol", "ok", "absent-symbol-absent"))
    else:
        controls.append(
            control("negative-symbol", "inconclusive", "absent-symbol-resolved")
        )

    bash_rg = rg_has(
        args.rg,
        rf"^[[:space:]]*{args.bash_symbol}[[:space:]]*\(\)",
        "*.sh",
        repo,
        env,
    )
    bash_count, bash_trust = gbrain_count(
        args.gbrain, source, args.bash_symbol, repo, env
    )
    if not bash_rg:
        controls.append(control("bash-fallback", "broken", "rg-definition-missing"))
    elif bash_count is None:
        controls.append(control("bash-fallback", "inconclusive", bash_trust))
    elif bash_count == 0:
        controls.append(
            control("bash-fallback", "ok", "known-gbrain-gap-rg-fallback-works")
        )
    else:
        controls.append(control("bash-fallback", "ok", "gbrain-now-resolves-bash"))

    fresh_symbol = f"RdaFreshParity{secrets.token_hex(8)}"
    fresh_file = repo / f"g1-fresh-{os.getpid()}.py"
    try:
        fresh_file.write_text(f"def {fresh_symbol}():\n    return True\n", encoding="utf-8")
        fresh_rg = rg_has(args.rg, rf"^def {fresh_symbol}\(", "*.py", repo, env)
        fresh_count, fresh_trust = gbrain_count(
            args.gbrain, source, fresh_symbol, repo, env
        )
    finally:
        fresh_file.unlink(missing_ok=True)
    if not fresh_rg:
        controls.append(control("freshness", "broken", "rg-missed-fresh-file"))
    elif fresh_count is None:
        controls.append(control("freshness", "inconclusive", fresh_trust))
    elif fresh_count == 0:
        controls.append(control("freshness", "ok", "rg-immediate-gbrain-stale"))
    else:
        controls.append(control("freshness", "ok", "both-immediate"))

    states = {item["status"] for item in controls}
    overall = "broken" if "broken" in states else "inconclusive" if "inconclusive" in states else "ok"
    return {"source": source, "overall": overall, "controls": controls}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument("--source")
    parser.add_argument("--positive", default="PrivacyError")
    parser.add_argument("--bash-symbol", default="run_preflight")
    parser.add_argument("--gbrain", default="gbrain")
    parser.add_argument("--rg", default="rg")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    try:
        report = inspect(args)
    except (OSError, ValueError) as error:
        print(f"graph-parity-report: {error}", file=sys.stderr)
        return 2
    if args.json:
        json.dump(report, sys.stdout, indent=2, sort_keys=True)
        print()
    else:
        for item in report["controls"]:
            print(f"{item['name']}\t{item['status']}\t{item['observation']}")
        print(f"overall\t{report['overall']}")
    return 1 if report["overall"] == "broken" else 0


if __name__ == "__main__":
    raise SystemExit(main())
