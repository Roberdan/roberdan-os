"""Read-only public metadata from Copilot's existing, dated session event streams."""
from datetime import datetime
import json
import os
from pathlib import Path

from telemetry_inventory import TelemetryError

EVENTS = {
    "tool.execution_start", "tool.execution_complete",
    "subagent.started", "subagent.completed", "subagent.failed",
}
AGENTS = {
    "execution-subagent", "general-purpose", "explore", "research", "rubber-duck",
    "code-review", "security-review", "baccio", "board", "coach", "luca", "rex",
    "socrates", "studio-lead", "thor", "twin", "wanda",
    "impeccable-asset-producer", "impeccable-documenter", "impeccable-finish-reviewer",
    "impeccable-manual-edit-applier",
}
MAX_LINE = 16 * 1024 * 1024
FIELDS = ("starts", "succeeded", "failed", "unknown", "pending")


def event_home():
    return Path(os.environ.get(
        "RDA_COPILOT_EVENT_HOME", str(Path.home() / ".copilot/session-state")))


def dated(value):
    if value is None:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            raise ValueError()
        return parsed.timestamp()
    except (AttributeError, ValueError, OverflowError) as exc:
        raise TelemetryError("eventi Copilot: data non interpretabile") from exc


def project(raw, session, aliases, public):
    """Discard all content and unapproved names before retaining a record."""
    if not isinstance(raw, dict):
        raise TelemetryError("eventi Copilot: struttura non interpretabile")
    kind = raw.get("type")
    if not isinstance(kind, str):
        raise TelemetryError("eventi Copilot: tipo non interpretabile")
    if kind not in EVENTS:
        return None
    data = raw.get("data", {})
    if not isinstance(data, dict):
        raise TelemetryError("eventi Copilot: metadati non interpretabili")
    call = data.get("toolCallId")
    event_id = raw.get("id")
    if any(value is not None and (not isinstance(value, str) or not value)
           for value in (call, event_id)):
        raise TelemetryError("eventi Copilot: identificativo non interpretabile")
    name, skill = None, False
    if kind == "tool.execution_start":
        tool = data.get("toolName")
        skill = isinstance(tool, str) and tool.lower() in ("skill", "functions.skill")
        args = data.get("arguments", {})
        if skill and isinstance(args, dict):
            selector = args.get("skill")
            if isinstance(selector, str) and selector in public and selector in aliases:
                name = aliases[selector]
    elif kind == "subagent.started":
        selector = data.get("agentName")
        name = selector if isinstance(selector, str) and selector in AGENTS else None
    success = data.get("success")
    if success is not None and type(success) is not bool:
        raise TelemetryError("eventi Copilot: esito non interpretabile")
    if kind == "subagent.completed":
        cancelled = data.get("cancelled", False)
        if type(cancelled) is not bool:
            raise TelemetryError("eventi Copilot: annullamento non interpretabile")
        success = False if cancelled else True if success is None else success
    elif kind == "subagent.failed":
        success = False
    return {"session": session, "kind": kind, "time": dated(raw.get("timestamp")),
            "id": event_id, "call": call, "name": name, "skill": skill,
            "success": success}


def read_records(start, end, aliases, public, home=None):
    home = event_home() if home is None else Path(home)
    metadata = {"status": "assente", "sessions": 0, "files": 0, "undated_events": 0,
                "duplicate_events": 0, "partial_lines": 0, "orphan_terminals": 0}
    if not home.exists():
        return [], metadata
    if not home.is_dir():
        raise TelemetryError("eventi Copilot: archivio non leggibile")
    metadata["status"] = "presente"
    rows, seen, sessions = [], {}, set()
    for path in sorted(home.glob("*/events.jsonl")):
        metadata["files"] += 1
        with path.open("rb") as stream:
            while line := stream.readline(MAX_LINE + 1):
                if len(line) > MAX_LINE:
                    raise TelemetryError("eventi Copilot: evento oltre il limite di lettura")
                try:
                    raw = json.loads(line)
                except (ValueError, UnicodeError, RecursionError) as exc:
                    if not line.endswith(b"\n"):
                        metadata["partial_lines"] += 1
                        continue
                    raise TelemetryError("eventi Copilot: registro non interpretabile") from exc
                row = project(raw, path.parent.name, aliases, public)
                if row is None:
                    continue
                if row["time"] is None:
                    metadata["undated_events"] += 1
                    continue
                if not start <= row["time"] <= end:
                    continue
                if row["id"] is None and row["call"] is None:
                    raise TelemetryError("eventi Copilot: evento senza identificativo")
                identity = (row["session"], "event", row["id"]) if row["id"] else (
                    row["session"], row["kind"], row["call"])
                if identity in seen:
                    if seen[identity] != row:
                        raise TelemetryError("eventi Copilot: duplicato in conflitto")
                    metadata["duplicate_events"] += 1
                    continue
                seen[identity] = row
                sessions.add(row["session"])
                rows.append(row)
    metadata["sessions"] = len(sessions)
    return rows, metadata


def observations(start, end, aliases, public):
    rows, metadata = read_records(start, end, aliases, public)
    uses, agents, skills, starts, terminals, start_counts = {}, {}, {}, [], {}, {}
    omitted = {"agents": 0, "skills": 0}
    for row in rows:
        kind = row["kind"]
        family = "agent" if kind.startswith("subagent.") else "skill"
        key = (row["session"], family, row["call"]) if row["call"] else None
        is_start = kind in ("subagent.started", "tool.execution_start")
        if not is_start:
            if key:
                terminals.setdefault(key, []).append(row)
            continue
        if family == "skill" and not row["skill"]:
            continue
        starts.append((row, key))
        if key:
            start_counts[key] = start_counts.get(key, 0) + 1
        if row["name"] is None:
            omitted[family + "s"] += 1
            continue
        group = agents if family == "agent" else skills
        group.setdefault(row["name"], {field: 0 for field in FIELDS})
        if family == "skill":
            uses.setdefault(row["name"], set()).add(("copilot", row["session"]))
    linked = set()
    totals = {family: {field: 0 for field in FIELDS} for family in ("agents", "skills")}
    for row, key in starts:
        family = "agents" if row["kind"] == "subagent.started" else "skills"
        terminal = terminals.get(key, [])
        if terminal and start_counts[key] == 1 and min(item["time"] for item in terminal) < row["time"]:
            raise TelemetryError("eventi Copilot: esito precedente all'avvio")
        if terminal:
            linked.add(key)
        outcomes = {item["success"] for item in terminal}
        state = ("pending" if not terminal else "unknown" if start_counts[key] != 1 else
                 "succeeded" if outcomes == {True} else
                 "failed" if outcomes == {False} else "unknown")
        totals[family]["starts"] += 1
        totals[family][state] += 1
        group = agents if family == "agents" else skills
        if row["name"] is not None:
            group[row["name"]]["starts"] += 1
            group[row["name"]][state] += 1
    # Generic tool completions do not identify a skill without a linked named start.
    metadata["orphan_terminals"] = sum(
        key not in linked for key in terminals if key[1] == "agent")
    metadata["repeated_terminals"] = sum(len(items) - 1 for items in terminals.values())
    metadata["conflicting_terminals"] = sum(
        len({item["success"] for item in items}) > 1 for items in terminals.values())
    metadata["ambiguous_starts"] = sum(count for count in start_counts.values() if count > 1)
    metadata.update(omitted_agents=omitted["agents"], omitted_skills=omitted["skills"])
    return uses, {"source": "copilot-native", "coverage": "parziale",
                  "metadata": metadata, "totals": totals, "agents": agents, "skills": skills}


def render(report):
    meta, totals = report["metadata"], report["totals"]
    if meta["status"] != "presente":
        print(f"  Eventi Copilot nativi: {meta['status']}; agenti e caricamenti skill non misurabili.")
        return
    print(f"  Eventi Copilot nativi: {meta['status']}; {meta['files']} registri; "
          f"{meta['sessions']} sessioni datate nella finestra.")
    print(f"  Eventi pertinenti senza data: {meta['undated_events']}; "
          f"duplicati esclusi: {meta['duplicate_events']}; righe incomplete: {meta['partial_lines']}.")
    for label, family in (("Agenti", "agents"), ("Caricamenti skill", "skills")):
        counts = totals[family]
        print(f"  {label}: {counts['starts']} avvii; {counts['succeeded']} esiti tecnici riusciti; "
              f"{counts['failed']} falliti/annullati; {counts['unknown']} esiti sconosciuti; "
              f"{counts['pending']} senza esito osservato.")
        for name, values in sorted(report[family].items(), key=lambda item: (-item[1]["starts"], item[0])):
            print(f"    {name}: " + "; ".join(f"{field}={values[field]}" for field in FIELDS))
    print(f"  Nomi omessi: {meta['omitted_agents']} avvii agenti, "
          f"{meta['omitted_skills']} avvii skill; inclusi nei totali, non attribuiti.")
    print(f"  Esiti agenti senza avvio nella finestra: {meta['orphan_terminals']}; esclusi dalla resa degli avvii.")
    print(f"  Esiti ripetuti: {meta['repeated_terminals']}; chiamate con esiti discordanti: "
          f"{meta['conflicting_terminals']}; avvii con collegamento ambiguo: {meta['ambiguous_starts']}.")
    print("  Fonte: registri nativi esistenti, letti senza scrivere; non sommati all'audit.")
    print("  Esito tecnico != risultato verificato != valore: caricamento o fine agente non provano utilita'.")
    print("  Risultati accettati, tempo risparmiato e valore reale: non misurabili da questi eventi.")
