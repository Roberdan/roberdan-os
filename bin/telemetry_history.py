#!/usr/bin/env python3
"""Compare the latest bounded findings snapshot and append one already-observed report."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import sys

from telemetry_inventory import TelemetryError
from telemetry_snapshot import REASONS, SCHEMA, build_snapshot, observation

PREFIX = "<!-- rda-telemetry-snapshot:"
MARKER = PREFIX + "v1"
END = "-->"
LIMIT = 2 * 1024 * 1024
TOP = {"schema_version", "days", "semantics", "observed_at", "inventory_policy", "metrics"}
FIELDS = {"value", "source", "scope", "unit", "policy", "denominator"}
SOURCES = {"bus", "evolve", "claude-history", "copilot-sessions", "copilot-mentions",
           "documents", "audit", "copilot-files", "inventory", "cohort", "skill-audit"}
UNITS = {"count", "host_session", "message", "thread", "project", "role", "hello",
         "report", "line", "pair", "session", "turn", "flag", "document", "event"}


def count(value):
    return value is None or type(value) is int and 0 <= value <= 2**63 - 1


def valid(snapshot):
    if not isinstance(snapshot, dict) or set(snapshot) != TOP:
        return False
    if (type(snapshot["schema_version"]) is not int or type(snapshot["days"]) is not int
            or not 1 <= snapshot["days"] <= 999999
            or not isinstance(snapshot["semantics"], str) or len(snapshot["semantics"]) > 100
            or not isinstance(snapshot["observed_at"], str)
            or not re.fullmatch(r"[0-9T:.+Z-]{19,40}", snapshot["observed_at"])
            or not re.fullmatch(r"[a-f0-9]{64}", str(snapshot["inventory_policy"]))):
        return False
    if not isinstance(snapshot["metrics"], dict) or len(snapshot["metrics"]) > 10000:
        return False
    for key, metric in snapshot["metrics"].items():
        if not re.fullmatch(r"[A-Za-z0-9_.:-]{1,200}", key) or not isinstance(metric, dict) or set(metric) != FIELDS:
            return False
        if (not count(metric["value"]) or metric["source"] not in SOURCES
                or metric["unit"] not in UNITS
                or any(not re.fullmatch(r"[a-f0-9]{64}", str(metric[k])) for k in ("scope", "policy"))):
            return False
        denominator = metric["denominator"]
        if (not isinstance(denominator, dict) or set(denominator) != {"value", "status", "reason"}
                or not count(denominator["value"]) or denominator["reason"] not in REASONS
                or denominator["status"] not in ("misurabile", "non misurabile")):
            return False
        if denominator["status"] == "misurabile" and not denominator["value"]:
            return False
    return True


def unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate key")
        result[key] = value
    return result


def latest(stream):
    previous, reason, capture, size = None, "prima osservazione o referto legacy non strutturato", None, 0
    while True:
        line = stream.readline(LIMIT + 1)
        if not line:
            break
        if len(line) > LIMIT:
            previous, reason, capture = None, "snapshot/referto oltre il limite di lettura", None
            while line and not line.endswith(b"\n"):
                line = stream.readline(LIMIT + 1)
            continue
        if line.startswith(b"### ") and b"telemetria del valore (generata da bin/telemetry.sh)" in line:
            previous, reason, capture = None, "ultimo referto legacy non strutturato", None
        if line.startswith(PREFIX.encode()):
            previous, capture, size = None, [], 0
            reason = "snapshot malformato o incompleto"
            if line.rstrip() != MARKER.encode():
                capture, reason = None, "schema/marker legacy o diverso"
        elif capture is not None:
            if line.rstrip() == END.encode():
                try:
                    candidate = json.loads(b"".join(capture), object_pairs_hook=unique_pairs)
                    if valid(candidate):
                        previous, reason = candidate, None
                except (ValueError, TypeError, UnicodeError, RecursionError):
                    pass
                capture = None
            else:
                size += len(line)
                if size > LIMIT:
                    capture, reason = None, "snapshot oltre il limite di lettura"
                else:
                    capture.append(line)
    return previous, reason


def comparison(current, previous, reason):
    results = {}
    for key, metric in current["metrics"].items():
        why, delta = reason, None
        if previous is not None:
            old = previous["metrics"].get(key)
            if previous["schema_version"] != current["schema_version"]:
                why = "schema diverso"
            elif previous["semantics"] != current["semantics"]:
                why = "semantica della misura diversa"
            elif previous["days"] != current["days"]:
                why = "finestra diversa"
            elif old is None:
                why = "metrica assente nell'ultima osservazione"
            elif old["scope"] != metric["scope"] or old["source"] != metric["source"]:
                why = "fonte/perimetro diverso"
            elif (metric["source"] in ("skill-audit", "cohort", "inventory")
                  and previous["inventory_policy"] != current["inventory_policy"]):
                why = "inventario o politica di identita' diversi"
            elif old["policy"] != metric["policy"] or old["unit"] != metric["unit"]:
                why = "politica o unita' della misura diversa"
            elif metric["value"] is None or old["value"] is None:
                why = "dati mancanti in una delle osservazioni"
            else:
                delta, why = metric["value"] - old["value"], None
        results[key] = {"delta": delta, "reason": why}
    return results


def render(current, changes):
    lines = ["", "7. Confronto con l'ultima osservazione scritta e stato dei denominatori",
             "  Delta di CONTEGGI osservati, totali o su finestre mobili: non valore, bisogno o miglioramento causale.",
             "  Fonti identificate senza percorsi; conteggi non osservati restano null, mai zero inventato."]
    for key, metric in current["metrics"].items():
        change = changes[key]
        delta = f"{change['delta']:+d}" if change["delta"] is not None else "non confrontabile: " + change["reason"]
        denominator = metric["denominator"]
        status = denominator["status"]
        if status == "misurabile":
            status += f" ({denominator['value']})"
        lines.append(f"  {key}: delta {delta}; denominatore {status}: {REASONS[denominator['reason']]}")
    return "\n".join(lines)


def write_report(stream, payload):
    stream.seek(0, os.SEEK_END)
    original_size = stream.tell()
    try:
        if stream.write(payload) != len(payload):
            raise OSError("short write")
        stream.flush()
        os.fsync(stream.fileno())
    except OSError:
        try:
            stream.truncate(original_size)
            stream.flush()
            os.fsync(stream.fileno())
        except OSError as exc:
            raise TelemetryError("scrittura del referto fallita; ripristino non confermato") from exc
        raise


def execute(root, days, findings, write, text):
    if len(text) > LIMIT * 4:
        raise TelemetryError("osservazione oltre il limite")
    displayed, groups, skills = observation(text)
    current = build_snapshot(root, days, groups, skills)
    if not valid(current):
        raise TelemetryError("snapshot corrente non valido")
    encoded = json.dumps(current, ensure_ascii=True, separators=(",", ":"))
    if len(encoded) > LIMIT:
        raise TelemetryError("snapshot corrente oltre il limite")
    path = Path(findings) if findings else None
    if path is None:
        if write:
            raise TelemetryError("scrittura del referto fallita: destinazione non valida")
        previous, reason, stream = None, "nessuna destinazione delle osservazioni configurata", None
    else:
        stream = path.open("a+b" if write else "rb", buffering=0) if write or path.exists() else None
    try:
        if stream:
            fcntl.flock(stream, fcntl.LOCK_EX if write else fcntl.LOCK_SH)
            stream.seek(0)
            previous, reason = latest(stream)
        elif path:
            previous, reason = None, "prima osservazione o referto legacy non strutturato"
        report = displayed + "\n" + render(current, comparison(current, previous, reason))
        if write:
            plain = re.sub(r"\x1b\[[0-9;]*m", "", report)
            payload = (f"\n### {current['observed_at'][:10]} — telemetria del valore (generata da bin/telemetry.sh)\n\n"
                       f"```\n{plain}\n```\n{MARKER}\n{encoded}\n{END}\n").encode()
            write_report(stream, payload)
        print(report)
        if write:
            target = "a docs/findings.md" if path == root / "docs/findings.md" else "alla destinazione configurata"
            print("\nreferto aggiunto " + target)
    finally:
        if stream:
            stream.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--days", type=int, required=True)
    parser.add_argument("--findings", required=True)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    try:
        execute(args.root, args.days, args.findings, args.write, sys.stdin.read(LIMIT * 4 + 1))
        return 0
    except (TelemetryError, OSError, ValueError) as exc:
        reason = str(exc) if isinstance(exc, TelemetryError) else (
            "scrittura del referto fallita" if args.write else "storico dei referti non disponibile")
        print("telemetry: " + reason, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
