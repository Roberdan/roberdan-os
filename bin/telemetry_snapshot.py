"""Build count-only snapshots from the single observed report, never reread its sources."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
from datetime import datetime, timezone

from telemetry_inventory import NAME, TelemetryError

SCHEMA = 1
SEMANTICS = "observed-counts-v1"
REASONS = {
    "units": "unita'/coorti non allineate: nessun rapporto fra messaggi, sessioni e coppie",
    "need": "nessun metadato affidabile del bisogno; menzioni non sono invocazioni",
    "descriptive": "conteggio descrittivo, non misura di bisogno o utilizzo",
    "unmapped": "nessun criterio di occasione per questa skill",
    "missing": "dati o osservazione mancanti",
    "empty": "nessuna occasione nella coorte osservata",
    "documents": "copertura di documenti, non bisogno della funzionalita'",
    "cohort": "candidate Copilot intersecate con avvii audit: stessa finestra, host e sessioni",
}
GROUPS = {
    "bus": ("messages_total messages_recent threads projects roles hellos undated", "bus", "units"),
    "evolve": ("reports", "evolve", "need"),
    "claude": ("history_lines", "claude-history", "descriptive"),
    "overlap": ("pairs projects", "copilot-sessions", "units"),
}
MENTIONS = ("jev", "twin", "kb-checkup", "premortem", "focus-group", "bus")
UNITS = {"messages_total": "message", "messages_recent": "message", "undated": "message",
         "threads": "thread", "projects": "project", "roles": "role", "hellos": "hello",
         "reports": "report", "history_lines": "line", "pairs": "pair", "sessions": "session",
         "turns": "turn", "canon": "flag"}
for name in MENTIONS:
    GROUPS["mention." + name] = ("sessions turns", "copilot-mentions", "need")
for name in ("bus", "jev", "twin"):
    GROUPS["coverage." + name] = ("agents agents_total skills skills_total coordinators coordinators_total canon",
                                "documents", "documents")


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def paths(root):
    home = Path.home()
    rda = Path(os.environ.get("RDA_HOME", str(home / ".roberdan-os")))
    project = root
    if (root / ".git").exists():
        result = subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=root,
                                capture_output=True, text=True, check=False)
        if result.returncode:
            raise TelemetryError("identita' del progetto non disponibile")
        project = root / result.stdout.strip()
    sources = {
        "bus": Path(os.environ.get("RDA_BUS_HOME", str(rda / "bus"))),
        "evolve": rda / "evolve",
        "claude-history": Path(os.environ.get("RDA_CLAUDE_HISTORY", str(home / ".claude/history.jsonl"))),
        "copilot": Path(os.environ.get("RDA_SESSION_STORE", str(home / ".copilot/session-store.db"))),
        "audit": Path(os.environ.get("RDA_AUDIT_HOME", str(rda / "private/audit"))) / "events.sqlite3",
        "documents": project,
    }
    tokens = {key: digest([key, str(path.resolve())]) for key, path in sources.items()}
    override = os.environ.get("RDA_TELEMETRY_SKILL_DIRS")
    installed = ([Path(value) for value in override.split(os.pathsep) if value] if override is not None
                 else [home / f".{host}/skills" for host in ("claude", "copilot", "codex", "agents")])
    tokens["inventory"] = digest([tokens["documents"], sorted(str(p.resolve()) for p in installed)])
    return tokens


def observation(text):
    groups, skills, lines = {}, None, []
    for line in text.splitlines():
        if line.startswith("@@RDA_METRIC\t"):
            _, key, raw = line.split("\t", 2)
            if key not in GROUPS or key in groups:
                raise TelemetryError("misura interna duplicata o sconosciuta")
            fields = GROUPS[key][0].split()
            values = raw.split("|")
            if len(fields) != len(values) or any(not re.fullmatch(r"null|[0-9]+", v) for v in values):
                raise TelemetryError("misura interna non interpretabile")
            groups[key] = dict(zip(fields, (None if v == "null" else int(v) for v in values)))
        elif line.startswith("@@RDA_SKILLS\t"):
            if skills is not None:
                raise TelemetryError("osservazione skill duplicata")
            skills = json.loads(line.split("\t", 1)[1])
        else:
            lines.append(line)
    if set(groups) != set(GROUPS) or skills is None:
        raise TelemetryError("osservazione incompleta: nessun referto salvato")
    return "\n".join(lines), groups, skills


def build_snapshot(root, days, groups, skills):
    tokens, metrics = paths(root), {}
    catalog = [{key: skill[key] for key in ("name", "aliases", "scopes", "installed")} for skill in skills["skills"]]
    inventory_policy = digest(["declared-aliases-v1", catalog, skills["inventory"]["scopes"]])

    def add(key, value, source, unit="count", reason="descriptive", denominator=None, policy="v1"):
        scope = tokens.get(source)
        if source.startswith("copilot-"):
            scope = tokens["copilot"]
        elif source == "cohort":
            scope = digest([tokens["audit"], tokens["copilot"], tokens["inventory"]])
        elif source == "skill-audit":
            scope = digest([tokens["audit"], tokens["inventory"]])
        metrics[key] = {"value": value, "source": source, "scope": scope, "unit": unit,
                        "policy": digest([SEMANTICS, policy]), "denominator": {
                            "value": denominator, "status": "misurabile" if denominator else "non misurabile",
                            "reason": reason}}

    for group, values in groups.items():
        _, source, reason = GROUPS[group]
        for field, value in values.items():
            denominator = None
            if group.startswith("coverage.") and field + "_total" in values:
                denominator = values[field + "_total"]
            add(group + "." + field, value, source, unit=UNITS.get(field, "document"),
                reason=reason, denominator=denominator,
                policy=group + ("-rolling" if field == "messages_recent" or source.startswith("copilot-") else "-stored"))
    audit = skills["sources"]["audit"]
    for field in ("observed_sessions", "gap_sessions", "undated_events", "undated_gap_events",
                  "unrecognized_skill_sessions"):
        add("audit." + field, audit[field] if audit["status"] == "presente" else None, "audit",
            "event" if field.endswith("events") else "host_session")
    files = skills["sources"]["session_files"]
    add("files.undated", files.get("undated_files"), "copilot-files")
    add("inventory.unnamed", skills["inventory"]["unnamed_definitions"], "inventory")
    for scope in skills["inventory"]["scopes"]:
        add("inventory." + scope["scope"], scope["definitions"], "inventory")
    for skill in skills["skills"]:
        name = skill["name"]
        if not NAME.fullmatch(name):
            raise TelemetryError("nome skill non valido")
        opportunity = skill["opportunity"]
        add("skill:" + name + ":observed", skill["observed_sessions"], "skill-audit", "host_session", "need")
        for field in ("candidate_sessions", "cohort_sessions", "invoked_in_cohort", "uses_outside_cohort"):
            value = opportunity[field]
            denominator = opportunity["cohort_sessions"] if field == "invoked_in_cohort" else None
            reason = ("unmapped" if not opportunity["criteria"] else "missing" if value is None else
                      "empty" if field == "invoked_in_cohort" and not denominator else
                      "cohort" if field == "invoked_in_cohort" else "descriptive")
            add("skill:" + name + ":" + field, value, "cohort", "host_session", reason, denominator,
                policy=["first-seen-file/audit-start-intersection-v1", opportunity["criteria"]])
    return {"schema_version": SCHEMA, "days": days, "semantics": SEMANTICS,
            "observed_at": datetime.now(timezone.utc).isoformat(), "inventory_policy": inventory_policy,
            "metrics": metrics}
