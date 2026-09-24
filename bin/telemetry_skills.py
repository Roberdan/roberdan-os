#!/usr/bin/env python3
"""Read-only, count-only skill observations and explicit file-metadata proxies."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path, PurePosixPath
import sqlite3
import sys

from telemetry_inventory import TelemetryError, inventory

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "kanban"))
from audit_schema import AuditError, TOOL_START_TYPES, TWIN_SELECTORS
from audit_skills import POLICY, public_skill_names
from audit_store import read_events

CRITERIA = {
    "film-director": (".mp4", ".mov", "remotion"),
    "pptx": (".pptx",), "docx": (".docx",), "xlsx": (".xlsx",),
    "pdf": (".pdf",), "make-pdf": (".pdf",), "source-command-pdf": (".pdf",),
}


def moment(value):
    if not isinstance(value, str):
        raise TelemetryError("dati temporali non interpretabili")
    try:
        date = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return date.replace(tzinfo=date.tzinfo or timezone.utc).timestamp()
    except (ValueError, OverflowError) as exc:
        raise TelemetryError("dati temporali non interpretabili") from exc


def audit_observations(start, end, aliases):
    try:
        rows, exists = read_events()
    except AuditError as exc:
        raise TelemetryError("audit non disponibile: archivio non valido o non leggibile") from exc
    uses, observed, gaps, unknown, unrecognized = {}, set(), set(), 0, set()
    named_coverage, legacy = set(), set()
    undated_gaps = 0
    for row in rows:
        if row.get("provenance") != "adapter_reported":
            continue
        if row.get("timestamp") is None:
            unknown += 1
            undated_gaps += row.get("native_type") == "observer.gap"
            continue
        if not start <= moment(row["timestamp"]) <= end:
            continue
        key = (row.get("host"), row.get("session_id"))
        if key[0] not in ("copilot", "claude") or not isinstance(key[1], str) or not key[1]:
            raise TelemetryError("audit non disponibile: identita' di sessione incompleta")
        if row.get("native_type") == "observer.gap":
            gaps.add(key)
        if row.get("native_type") not in TOOL_START_TYPES:
            continue
        observed.add(key)
        data = row.get("data")
        if not isinstance(data, dict):
            raise TelemetryError("audit non disponibile: evento incompleto")
        tool, arguments = data.get("toolName", ""), data.get("arguments", {})
        if not isinstance(tool, str) or not isinstance(arguments, dict):
            raise TelemetryError("audit non disponibile: struttura dell'avvio non valida")
        if data.get("skillNamePolicy") == POLICY:
            named_coverage.add(key)
        else:
            legacy.add(key)
        if tool.lower() != "skill":
            continue
        name = arguments.get("skill")
        if not isinstance(name, str):
            unrecognized.add(key)
        elif name not in aliases:
            unrecognized.add(key)
        else:
            uses.setdefault(aliases[name], set()).add(key)
    return uses, named_coverage - legacy, {"status": "presente" if exists else "assente",
                           "coverage": "parziale" if observed else "non osservata",
                           "observed_sessions": len(observed), "gap_sessions": len(gaps),
                           "public_name_sessions": len(named_coverage),
                           "legacy_or_unmarked_sessions": len(legacy),
                           "undated_events": unknown, "undated_gap_events": undated_gaps,
                           "unrecognized_skill_sessions": len(unrecognized)}


def file_candidates(start, end):
    path = Path(os.environ.get("RDA_SESSION_STORE") or Path.home() / ".copilot/session-store.db")
    candidates = {name: set() for name in CRITERIA}
    if not path.exists():
        return candidates, {"status": "non misurabile", "reason": "storico Copilot assente"}
    db = sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True, timeout=2)
    try:
        db.execute("BEGIN")
        if not db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='session_files'").fetchone():
            return candidates, {"status": "non misurabile", "reason": "metadati session_files assenti"}
        unknown = 0
        for session, filename, timestamp in db.execute(
                "SELECT session_id, file_path, first_seen_at FROM session_files"):
            if not isinstance(session, str) or not session or not isinstance(filename, str):
                raise TelemetryError("metadati dei file non interpretabili")
            if timestamp is None:
                unknown += 1
                continue
            if not start <= moment(timestamp) <= end:
                continue
            file = PurePosixPath(filename.replace("\\", "/").lower())
            remotion = "remotion" in file.parts or file.name.startswith("remotion.config.")
            for name, patterns in CRITERIA.items():
                if file.suffix in patterns or ("remotion" in patterns and remotion):
                    candidates[name].add(("copilot", session))
        return candidates, {"status": "presente", "undated_files": unknown}
    finally:
        db.close()


def build_report(root, days, now=None):
    now = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
    end = now.timestamp()
    start = now.replace(hour=0, minute=0, second=0, microsecond=0).timestamp() - days * 86400
    catalog = inventory(root, (TWIN_SELECTORS,))
    uses, observed, audit = audit_observations(start, end, catalog["aliases"])
    try:
        public_names = public_skill_names()
    except (OSError, ValueError) as exc:
        raise TelemetryError("elenco pubblico dei nomi osservabili non disponibile") from exc
    candidates, files = file_candidates(start, end)
    results = []
    for skill in catalog["skills"]:
        name = skill["name"]
        invocations = uses.get(name, set())
        public = bool({name, *skill["aliases"]} & public_names)
        matching = {key for key in observed
                    if any(scope in skill["scopes"] for scope in
                           (f"installate-{key[0]}", f"progetto-{key[0]}"))}
        measured = bool(invocations) or (bool(matching) and public)
        usage_reason = (None if measured else "installazione non osservata" if not skill["installed"]
                        else "nome fuori dall'elenco pubblico osservabile" if not public
                        else "copertura dei nomi pubblici non osservata per l'host di installazione")
        selectors = [selector for selector in (name, *skill["aliases"]) if selector in CRITERIA]
        criterion = tuple(dict.fromkeys(pattern for selector in selectors for pattern in CRITERIA[selector]))
        opportunity = {"criteria": list(criterion) if criterion else None,
                       "candidate_sessions": None, "cohort_sessions": None,
                       "invoked_in_cohort": None, "uses_outside_cohort": None}
        reason = "nessun criterio di occasione definito per questa skill"
        if criterion:
            reason = files.get("reason")
            if files["status"] == "presente":
                candidate = set().union(*(candidates[selector] for selector in selectors))
                cohort = candidate & (matching | invocations)
                opportunity["candidate_sessions"] = len(candidate)
                if measured:
                    opportunity.update(cohort_sessions=len(cohort),
                                       invoked_in_cohort=len(invocations & cohort),
                                       uses_outside_cohort=len(invocations - cohort))
                reason = (usage_reason if not measured else
                          "nessuna occasione candidata nella coorte osservata" if not cohort else None)
        opportunity.update(status="misurabile" if reason is None else "non misurabile", reason=reason)
        results.append({**skill, "observed_sessions": len(invocations) if measured else None,
                        "usage_reason": usage_reason, "opportunity": opportunity})
    return {"schema_version": 1, "unit": "host_session",
            "cohort_definition": "Copilot session_files first_seen_at intersect installed-host public-name-policy starts or named skill invocations",
            "window": {"days": days, "start_epoch": start, "end_epoch": end},
            "inventory": {"scopes": catalog["scopes"], "unnamed_definitions": catalog["unnamed_definitions"]},
            "sources": {"audit": audit, "session_files": files}, "skills": results}


def render(report):
    scopes = report["inventory"]["scopes"]
    print("  Inventario per nomi/alias dichiarati; presenza su disco, non caricamento nella sessione.")
    print("  Perimetro: " + "; ".join(f"{s['scope']}={s['status']}" for s in scopes))
    print(f"  Definizioni senza nome dichiarato: {report['inventory']['unnamed_definitions']} (non attribuibili).")
    audit, files = report["sources"]["audit"], report["sources"]["session_files"]
    if audit["status"] != "presente":
        print(f"  Audit: {audit['status']}; conteggi e copertura dei nomi pubblici non misurabili.")
    else:
        print(f"  Audit: {audit['status']}; sessioni con avvii osservati: {audit['observed_sessions']}; "
              f"sessioni con lacune dichiarate: {audit['gap_sessions']}; eventi senza data: {audit['undated_events']}.")
        print(f"  Avvisi di lacuna senza data: {audit['undated_gap_events']}, non attribuibili alla finestra.")
        print(f"  Sessioni con invocazioni skill non riconciliate: {audit['unrecognized_skill_sessions']}.")
        print(f"  Nomi pubblici: {audit['public_name_sessions']} sessioni con filtro dichiarato; "
              f"{audit['legacy_or_unmarked_sessions']} precedenti/senza dichiarazione: assenze non misurabili.")
    print(f"  Metadati file: {files['status']}; " + (files.get("reason") or
          f"prime osservazioni senza data: {files['undated_files']}"))
    print("  Occasioni CANDIDATE: estensioni/percorso Remotion in session_files Copilot, prima osservazione nella finestra.")
    print("  Rapporto: invocazioni / candidate con filtro pubblico dichiarato o invocazione nominativa, stessa finestra e host.")
    print("  Invocazione osservata = avvio nominativo riportato dall'adattatore, non prova di completamento.")
    print("  Copertura parziale: un avvio non prova osservazione completa; zero osservato NON significa mai usata.")
    print("  Solo nomi pubblici approvati; nomi privati/sconosciuti omessi. I vecchi adattatori mascheravano le skill generali.")
    print("  File pertinenti non provano un bisogno; mancano attivita' senza file, altri host e dati prima dell'osservatore.")
    for skill in report["skills"]:
        usage = (f"{skill['observed_sessions']} sessioni con invocazione osservata"
                 if skill["observed_sessions"] is not None else f"non misurabile ({skill['usage_reason']})")
        opportunity = skill["opportunity"]
        ratio = (f"{opportunity['invoked_in_cohort']}/{opportunity['cohort_sessions']}"
                 if opportunity["status"] == "misurabile" else f"non misurabile ({opportunity['reason']})")
        detail = ""
        if opportunity["candidate_sessions"] is not None:
            detail += f"; candidate Copilot: {opportunity['candidate_sessions']}"
        if opportunity["uses_outside_cohort"] is not None:
            detail += f"; usi fuori coorte: {opportunity['uses_outside_cohort']}"
        if opportunity["criteria"]:
            detail += "; criterio: " + ", ".join(opportunity["criteria"])
        print(f"  {skill['name']}: {usage}; rapporto: {ratio}{detail}")


class Parser(argparse.ArgumentParser):
    def error(self, _message):
        raise TelemetryError("argomenti non validi; usare --help")


def main():
    parser = Parser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--days", type=int, default=30)
    parser.add_argument("--json", action="store_true", help="Count-only structured metrics")
    parser.add_argument("--observation", action="store_true", help=argparse.SUPPRESS)
    try:
        args = parser.parse_args()
        if not 1 <= args.days <= 999999:
            raise TelemetryError("giorni non validi")
        report = build_report(args.root, args.days)
        print(json.dumps(report, ensure_ascii=True)) if args.json else render(report)
        if args.observation:
            print("@@RDA_SKILLS\t" + json.dumps(report, ensure_ascii=True))
        return 0
    except (TelemetryError, OSError, UnicodeError, sqlite3.Error) as exc:
        reason = str(exc) if isinstance(exc, TelemetryError) else "sorgente non disponibile o danneggiata"
        print(f"telemetry: skill non misurabili: {reason}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
