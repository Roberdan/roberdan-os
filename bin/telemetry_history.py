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
             "  Estese solo le voci cambiate; +0 = invariato. Le parti sconosciute sono conteggiate separatamente; snapshot completo."]
    labels = {"observed": "osservate", "candidate_sessions": "candidate", "cohort_sessions": "coorte",
              "invoked_in_cohort": "usi in coorte", "uses_outside_cohort": "fuori coorte",
              "messages_total": "messaggi totali", "messages_recent": "messaggi recenti",
              "sessions": "sessioni", "turns": "turni", "pairs": "coppie", "projects": "progetti"}
    reasons = list(dict.fromkeys(change["reason"] for change in changes.values() if change["reason"]))
    groups = {}
    for key, metric in current["metrics"].items():
        group, field = key.rsplit(":" if key.startswith("skill:") else ".", 1)
        groups.setdefault(group, {})[field] = (metric, changes[key])
    for index, reason in enumerate(reasons, 1):
        affected = sum(any(change["reason"] == reason for _, change in fields.values()) for fields in groups.values())
        lines.append(f"  Non confrontabile [C{index}]: {reason} — {affected} {'voce' if affected == 1 else 'voci'}.")
    denominator_reasons = list(dict.fromkeys(metric["denominator"]["reason"]
                               for metric in current["metrics"].values()
                               if metric["denominator"]["status"] != "misurabile"))
    for index, reason in enumerate(denominator_reasons, 1):
        affected = sum(any(metric["denominator"]["reason"] == reason and
                           metric["denominator"]["status"] != "misurabile"
                           for metric, _ in fields.values()) for fields in groups.values())
        lines.append(f"  Denominatore non misurabile [D{index}]: {REASONS[reason]} — {affected} {'voce' if affected == 1 else 'voci'}.")
    unchanged = zeros = expanded = 0
    for group, fields in groups.items():
        if not any(change["delta"] not in (None, 0) for _, change in fields.values()):
            n = sum(change["delta"] == 0 for _, change in fields.values())
            unchanged += bool(n)
            zeros += n
            continue
        expanded += 1
        parts, unavailable, missing, denominators = [], {}, set(), {}
        for field, (metric, change) in fields.items():
            label = labels.get(field, field)
            if change["delta"] is not None:
                parts.append(f"{label} {change['delta']:+d}")
            else:
                unavailable.setdefault(change["reason"], []).append(label)
            denominator = metric["denominator"]
            if denominator["status"] == "misurabile":
                denominators[label] = denominator["value"]
            else:
                missing.add(denominator_reasons.index(denominator["reason"]) + 1)
        if not parts:
            refs = ",".join(f"C{reasons.index(reason) + 1}" for reason in unavailable)
            parts.append(f"delta non confrontabile [{refs}]")
        else:
            for reason, fields_unknown in unavailable.items():
                fields_text = ", ".join(fields_unknown)
                if group.startswith("skill:") and len(fields_unknown) > 1:
                    fields_text = "osservate e occasioni" if "osservate" in fields_unknown else "occasioni"
                parts.append(f"{fields_text} non confrontabile [C{reasons.index(reason) + 1}]")
        if group.startswith("skill:") and "invoked_in_cohort" in fields:
            numerator, numerator_change = fields["invoked_in_cohort"]
            cohort, cohort_change = fields["cohort_sessions"]
            if numerator["denominator"]["status"] == "misurabile":
                n, d = numerator["value"], cohort["value"]
                ratio = f"rapporto {n}/{d}"
                if numerator_change["delta"] is not None and cohort_change["delta"] is not None:
                    old_n, old_d = n - numerator_change["delta"], d - cohort_change["delta"]
                    if old_d > 0:
                        ratio += f" (delta {(n / d - old_n / old_d) * 100:+.1f} punti percentuali)"
                    else:
                        ratio += " (delta non confrontabile: precedente coorte vuota)"
                else:
                    ratio += " (delta non confrontabile)"
                parts.append(ratio)
                denominators.clear()
            else:
                parts.append("occasioni/rapporto non misurabile")
        if denominators:
            parts.append("denominatori misurabili: " + ", ".join(f"{key}={value}" for key, value in denominators.items()))
        if missing:
            parts.append("denominatori non misurabili [" + ",".join(f"D{index}" for index in sorted(missing)) + "]")
        lines.append(f"  {group}: " + "; ".join(parts))
    lines.append(f"  Invariate nelle misure confrontabili: {unchanged} voci, {zeros} conteggi con delta +0.")
    lines.append(f"  Voci con cambiamenti: {expanded}. Non confrontabile non significa invariato.")
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
