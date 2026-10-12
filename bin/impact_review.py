#!/usr/bin/env python3
"""Impact review: weekly agent/skill report + monthly Rex with/without pilot status.

  bin/impact_review.py weekly [--end ISO] [--days 7] [--write] [--json]
  bin/impact_review.py evidence template | record < entry.json | import --file F
  bin/impact_review.py pilot prepare --month AAAA-MM --model ID [--repetitions N] [--seed S]
                               [--oracle PRIVATE_FILE]   # holdout privato; senza = solo calibrazione
  bin/impact_review.py pilot claim --pilot rex-AAAA-MM --slot ARM/CASE-rK
  bin/impact_review.py pilot ingest|status --pilot rex-AAAA-MM [--write]
  bin/impact_review.py periodic [--now ISO]        # launchd entry point, idempotent
  bin/impact_review.py schedule [--check-loaded]    # dry-run: prints, never installs

Reads existing native events; writes only under ~/.roberdan-os/private/impact-review
(0700/0600). Never calls a model and never writes public findings.
"""
import argparse
from datetime import datetime, timedelta, timezone
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys

from impact_store import TEMPLATE, ImpactError, impact_home, parse_time, record, write_private
import impact_pilot
import impact_weekly
from telemetry_inventory import TelemetryError

ROOT = Path(__file__).resolve().parent.parent
LABEL = "com.roberdan.rda-impact-review"


def weekly(end, days, write):
    month = datetime.fromtimestamp(end, timezone.utc).strftime("%Y-%m")
    report = impact_weekly.build(ROOT, end, days, impact_pilot.status(f"rex-{month}"))
    text = impact_weekly.render(report)
    path = None
    if write:
        window = report["window"]
        stem = f"weekly-{window['start'][:10]}_{window['end'].replace(':', '')}"
        path = impact_home() / "reports" / f"{stem}.json"
        write_private(path, impact_weekly.to_json(report))
        write_private(path.with_suffix(".txt"), text)
    return report, text, path


def week_end(now):
    moment = datetime.fromtimestamp(now, timezone.utc)
    monday = (moment - timedelta(days=moment.weekday())).replace(hour=0, minute=0, second=0, microsecond=0)
    return monday.timestamp()


def periodic(now):
    home = impact_home()
    lock = home / ".periodic.lock"
    stamp = datetime.fromtimestamp(now, timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    outcome = {"started_at": stamp, "weekly": None, "pilot": None, "error": None}
    fd = os.open(lock, os.O_WRONLY | os.O_CREAT, 0o600)
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise ImpactError("esecuzione periodica gia' in corso: nessun doppione") from exc
        try:
            end = week_end(now)
            start = datetime.fromtimestamp(end - 7 * 86400, timezone.utc).strftime("%Y-%m-%d")
            stem = f"weekly-{start}_{datetime.fromtimestamp(end, timezone.utc).strftime('%Y-%m-%dT%H%M%SZ')}"
            if (home / "reports" / f"{stem}.json").exists():
                outcome["weekly"] = "gia-prodotto"
            else:
                weekly(end, 7, True)
                outcome["weekly"] = "scritto"
            month = datetime.fromtimestamp(now, timezone.utc).strftime("%Y-%m")
            state = impact_pilot.status(f"rex-{month}")
            write_private(home / "reports" / f"pilot-status-{month}.json",
                          json.dumps(state, indent=1, sort_keys=True) + "\n")
            outcome["pilot"] = state["state"]
        except (ImpactError, TelemetryError, OSError, ValueError) as exc:
            outcome["error"] = str(exc) if isinstance(exc, (ImpactError, TelemetryError)) \
                else type(exc).__name__
            raise
        finally:
            write_private(home / "receipts" / f"periodic-{stamp}.json",
                          json.dumps(outcome, indent=1, sort_keys=True) + "\n")
    finally:
        os.close(fd)
    return outcome


def schedule(check_loaded):
    target = Path.home() / "GitHub/roberdan-os"
    plist = ROOT / "scheduling" / f"{LABEL}.plist"
    lines = [f"plist versionato: {plist.relative_to(ROOT)} ({'presente' if plist.is_file() else 'ASSENTE'})",
             f"checkout persistente atteso: {target}"]
    persistent = (target / ".git").is_dir() and (target / "bin/impact_review.py").is_file()
    lines.append("checkout persistente con impact_review: " + ("si" if persistent else
                 "NO — integrare su main prima di attivare (una copia per card non e' un bersaglio)"))
    lines += ["attivazione (NON eseguita da questo comando):",
              f"  cp \"{target}/scheduling/{LABEL}.plist\" ~/Library/LaunchAgents/",
              f"  launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/{LABEL}.plist"]
    if check_loaded:
        result = subprocess.run(["launchctl", "print", f"gui/{os.getuid()}/{LABEL}"],
                                capture_output=True, text=True, check=False)
        lines.append("caricato in launchd: " + ("si" if result.returncode == 0 else "no"))
    else:
        lines.append("caricato in launchd: non verificato (usa --check-loaded); un file presente non e' un job attivo")
    return "\n".join(lines) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    w = sub.add_parser("weekly")
    w.add_argument("--end"), w.add_argument("--days", type=int, default=7)
    w.add_argument("--write", action="store_true"), w.add_argument("--json", action="store_true")
    e = sub.add_parser("evidence")
    e.add_argument("action", choices=("template", "record", "import")), e.add_argument("--file", type=Path)
    p = sub.add_parser("pilot")
    p.add_argument("action", choices=("prepare", "claim", "ingest", "status"))
    for flag in ("--month", "--model", "--seed", "--pilot", "--slot", "--oracle"):
        p.add_argument(flag)
    p.add_argument("--repetitions", type=int, default=1), p.add_argument("--timeout-s", type=int, default=900)
    p.add_argument("--write", action="store_true")
    r = sub.add_parser("periodic")
    r.add_argument("--now")
    s = sub.add_parser("schedule")
    s.add_argument("--check-loaded", action="store_true")
    args = parser.parse_args(argv)
    try:
        if args.command == "weekly":
            end = parse_time(args.end, "--end") if args.end else datetime.now(timezone.utc).timestamp()
            report, text, path = weekly(end, args.days, args.write)
            print(impact_weekly.to_json(report) if args.json else text, end="")
            if path:
                print(f"scritto in privato: ~/{path.relative_to(Path.home())}" if Path.home() in path.parents
                      else "scritto nella destinazione privata configurata")
        elif args.command == "evidence":
            if args.action == "template":
                print(json.dumps(TEMPLATE, indent=1))
                return 0
            if args.action == "import" and args.file is None:
                raise ImpactError("import richiede --file")
            raw = args.file.read_text(encoding="utf-8") if args.action == "import" else sys.stdin.read()
            try:
                data = json.loads(raw)
            except ValueError as exc:
                raise ImpactError("evidenza: JSON non interpretabile") from exc
            added, repeated = record(data if isinstance(data, list) else [data])
            print(f"evidenze registrate: {added} nuove, {repeated} gia' presenti (identiche)")
        elif args.command == "pilot":
            if args.action == "prepare":
                if not args.model:
                    raise ImpactError("prepare richiede --model scelto dal registro (nessun id predefinito)")
                manifest = impact_pilot.prepare(args.month, args.model, args.repetitions, args.seed,
                                                args.timeout_s, args.oracle)
                print(f"{manifest['pilot_id']}: {len(manifest['slots'])} slot preparati; stato {manifest['state']}; "
                      f"oracolo {manifest['oracle']['role']}; perimetro di lettura {manifest['read_scope']}")
            elif args.action == "claim":
                print(impact_pilot.claim(args.pilot, args.slot), end="")
            elif args.action == "ingest":
                results = impact_pilot.ingest(args.pilot)
                print(f"{args.pilot}: {len(results)} ricevute acquisite")
            else:
                pilot_id = args.pilot or f"rex-{args.month or datetime.now(timezone.utc).strftime('%Y-%m')}"
                state = impact_pilot.status(pilot_id)
                if args.write:
                    write_private(impact_home() / "reports" / f"pilot-status-{pilot_id[4:]}.json",
                                  json.dumps(state, indent=1, sort_keys=True) + "\n")
                print(json.dumps(state, indent=1, sort_keys=True))
        elif args.command == "periodic":
            now = parse_time(args.now, "--now") if args.now else datetime.now(timezone.utc).timestamp()
            outcome = periodic(now)
            print(f"impact-review: settimanale={outcome['weekly']} pilota={outcome['pilot']}")
        else:
            print(schedule(args.check_loaded), end="")
        return 0
    except (ImpactError, TelemetryError, OSError, KeyError, ValueError) as exc:
        reason = str(exc) if isinstance(exc, (ImpactError, TelemetryError)) else \
            f"{type(exc).__name__} (dettaglio omesso: puo' contenere percorsi privati)"
        print(f"impact-review: errore: {reason}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
