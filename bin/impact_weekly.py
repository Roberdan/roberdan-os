"""Weekly impact review: execution observed, evidence-backed outcomes, causal status.

Three layers that are never merged into one number:
  1. execution  - dated starts and technical terminals from native Copilot events;
  2. outcomes   - private, schema-validated review evidence with explicit provenance;
  3. causal     - only a controlled with/without pilot can speak to contribution.
Low use is never a removal signal, and a missing layer is "non misurato", not zero.
"""
from datetime import datetime, timezone
import json
import sys

from impact_store import ImpactError, UNITS, load_evidence, parse_time, roster

sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent.parent / "kanban"))
from audit_schema import TWIN_SELECTORS  # noqa: E402
from audit_skills import public_skill_names  # noqa: E402
from telemetry_inventory import inventory  # noqa: E402
from telemetry_native import FIELDS, observations, read_records  # noqa: E402

POLICY = "impact-weekly-v1:copilot-native+public-roster+private-evidence"
NOT_MEASURED = "non misurato"


def iso(ts):
    return datetime.fromtimestamp(ts, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _native(start, end, catalog, public):
    _, report = observations(start, end - 1e-3, catalog["aliases"], public)
    return report


def _runs(start, end, catalog, public):
    rows, _ = read_records(start, end - 1e-3, catalog["aliases"], public)
    runs = {}
    for row in rows:
        if row["name"] is None or not row["call"]:
            continue
        if row["kind"] == "subagent.started":
            family = "agent"
        elif row["kind"] == "tool.execution_start" and row["skill"]:
            family = "skill"
        else:
            continue
        runs.setdefault((family, row["name"]), set()).add(f"copilot:{row['session']}/{row['call']}")
    return runs


def _execution(report, family, name):
    if report["metadata"]["status"] != "presente":
        return None
    counts = report[family + "s"].get(name)
    return counts or {field: 0 for field in FIELDS}


def _outcomes(entries, runs):
    if not entries:
        return {"status": NOT_MEASURED, "reason": "nessuna evidenza di revisione nella finestra"}
    tasks = {}
    for entry in entries:
        tasks.setdefault(entry["task_id"], []).append(entry)
    result = {"status": "misurato su campione", "tasks": len(tasks), "entries": len(entries)}
    for field in ("acceptance", "adoption"):
        tally = {}
        for rows in tasks.values():
            first = rows[0]
            label = first[field] if first[field] == "unassessed" else \
                f"{first[field]}:{first[field + '_source']}"
            tally[label] = tally.get(label, 0) + 1
        result[field] = dict(sorted(tally.items()))
    linked = unverifiable = 0
    for rows in tasks.values():
        ids = {row["run_id"] for row in rows}
        if ids & runs:
            linked += 1
        elif not any(run.startswith("copilot:") for run in ids):
            unverifiable += 1
    result["linkage"] = {"tasks_linked_to_observed_run": linked,
                         "tasks_unlinked": len(tasks) - linked - unverifiable,
                         "tasks_linkage_not_verifiable": unverifiable}
    repairs, seen = {}, set()
    for entry in entries:
        for item in entry.get("repair", []):
            key = (entry["task_id"], item["measure"], item["unit"], item["source"], item["ref"])
            if key in seen:
                continue
            seen.add(key)
            unit = "minutes" if item["measure"] == "time" else item["unit"]
            value = item["value"] * UNITS[item["measure"]][item["unit"]] if \
                item["measure"] == "time" else item["value"]
            label = f"{item['measure']}:{unit}:{item['source']}"
            repairs[label] = round(repairs.get(label, 0) + value, 4)
    result["repair"] = dict(sorted(repairs.items())) or NOT_MEASURED
    return result


def build(root, end, days=7, pilot=None):
    if not 1 <= days <= 366:
        raise ImpactError("finestra non valida (1..366 giorni)")
    names = roster(root)
    catalog = inventory(root, (TWIN_SELECTORS,))
    public = public_skill_names()
    start, prev_start = end - days * 86400, end - 2 * days * 86400
    current, previous = _native(start, end, catalog, public), _native(prev_start, start, catalog, public)
    runs = _runs(start, end, catalog, public) if current["metadata"]["status"] == "presente" else {}
    window_entries = [e for e in load_evidence() if start <= parse_time(e["observed_at"]) < end]
    meta_c, meta_p = current["metadata"], previous["metadata"]
    comparable = (meta_c["status"] == meta_p["status"] == "presente"
                  and meta_c["sessions"] > 0 and meta_p["sessions"] > 0)
    components = []
    for family in ("agent", "skill"):
        for name in names[family]:
            entries = [e for e in window_entries if e["kind"] == family and e["name"] == name]
            causal = {"status": NOT_MEASURED,
                      "reason": "nessun confronto controllato con/senza per questo componente"}
            if family == "agent" and name == "rex" and pilot is not None:
                causal = {"status": pilot["state"], "claim": pilot["claim"],
                          "claim_scope": pilot.get("claim_scope"),
                          "pilot_id": pilot.get("pilot_id")}
            components.append({
                "kind": family, "name": name,
                "execution": {"current": _execution(current, family, name),
                              "previous": _execution(previous, family, name) if comparable else None},
                "outcomes": _outcomes(entries, runs.get((family, name), set())),
                "causal": causal})
    return {"schema": 1, "policy": POLICY, "kind": "weekly",
            "window": {"start": iso(start), "end": iso(end), "days": days,
                       "previous_start": iso(prev_start), "end_exclusive": True},
            "sources": {"copilot_native_current": meta_c, "copilot_native_previous": meta_p,
                        "comparison": "stessa fonte e stessa politica" if comparable else
                        "non confrontabile: fonte assente o nessuna sessione in una delle finestre",
                        "evidence_entries_in_window": len(window_entries),
                        "evidence_tasks_in_window": len({e["task_id"] for e in window_entries})},
            "totals": {"current": current["totals"], "previous": previous["totals"] if comparable else None,
                       "omitted_unapproved_names": {"agents": meta_c.get("omitted_agents"),
                                                    "skills": meta_c.get("omitted_skills")}},
            "components": components,
            "limits": ["esito tecnico != risultato accettato != utilita' != contributo causale",
                       "zero avvii osservati con copertura parziale non significa mai usato",
                       "uso basso non e' un segnale di rimozione",
                       "esiti per componente non sono sommabili: un task puo' coinvolgerne piu' d'uno",
                       "nessun tempo o denaro stimato: solo unita' dichiarate con provenienza"]}


def _counts(counts):
    if counts is None:
        return "non osservabile"
    if counts["starts"] == 0:
        return "nessun avvio osservato (copertura parziale: non significa mai usato)"
    return (f"avvii {counts['starts']} · riusciti {counts['succeeded']} · falliti {counts['failed']}"
            f" · sconosciuti {counts['unknown']} · senza esito {counts['pending']}")


def render(report):
    window, sources = report["window"], report["sources"]
    lines = [f"REVISIONE D'IMPATTO SETTIMANALE — {window['start']} → {window['end']} (fine esclusa)",
             f"Politica: {report['policy']}",
             f"Confronto con la settimana precedente: {sources['comparison']}",
             f"Evidenze di revisione nella finestra: {sources['evidence_entries_in_window']} voci, "
             f"{sources['evidence_tasks_in_window']} task distinti (campione, non popolazione)", ""]
    for family, title in (("agent", "AGENTI"), ("skill", "SKILL")):
        lines.append(title)
        for item in (c for c in report["components"] if c["kind"] == family):
            execution, outcome = item["execution"], item["outcomes"]
            lines.append(f"  {item['name']}")
            lines.append(f"    esecuzione (tecnica): {_counts(execution['current'])}")
            if execution["previous"] is not None:
                lines.append(f"    settimana precedente:  {_counts(execution['previous'])}")
            if outcome["status"] == NOT_MEASURED:
                lines.append(f"    esiti/utilita': {NOT_MEASURED} ({outcome['reason']})")
            else:
                link = outcome["linkage"]
                lines.append(f"    esiti: {outcome['tasks']} task · accettazione {outcome['acceptance']}"
                             f" · adozione {outcome['adoption']}")
                lines.append(f"    collegati a un avvio osservato: {link['tasks_linked_to_observed_run']};"
                             f" non collegati: {link['tasks_unlinked']};"
                             f" non verificabili: {link['tasks_linkage_not_verifiable']}")
                lines.append(f"    riparazioni: {outcome['repair']}")
            causal = item["causal"]
            lines.append(f"    contributo causale: {causal['status']}"
                         + (f" — {causal['claim']}" if causal.get("claim") else ""))
        lines.append("")
    lines.append("Limiti: " + "; ".join(report["limits"]) + ".")
    return "\n".join(lines) + "\n"


def to_json(report):
    return json.dumps(report, indent=1, sort_keys=True) + "\n"
