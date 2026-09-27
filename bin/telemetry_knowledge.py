#!/usr/bin/env python3
"""Read-only, count-only REAL invocation counter for the knowledge tools (gbrain,
codegraph, graphify) — Fase T, T4 del piano 2026-09-24.

Il resto di telemetry.sh (sezione 2) misura MENZIONI testuali: nomina uno strumento senza
provare che sia stato invocato. Questo modulo legge invece l'audit degli AVVII di tool
riportati dagli adattatori host (kanban/audit_store.py, provenance=adapter_reported) e
conta un'invocazione solo quando il nome del tool corrisponde esattamente a uno di questi
tre. Le due cifre non si sommano mai: sono qualita' di prova diverse, come il resto di
questo file gia' fa per bus/jev/twin.

LIMITE DICHIARATO: gli eventi di avvio per i tool bash/Bash non portano il testo del
comando (kanban/audit_schema.py filtra "arguments" a pochi campi non sensibili), quindi
`gbrain search ...`/`codegraph explore ...`/`graphify ...` lanciati da riga di comando
NON sono visibili qui — solo le chiamate MCP native e l'invocazione della skill graphify
lo sono. Zero osservato non prova mai zero uso.
"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import sqlite3
import sys

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "kanban"))
from audit_schema import AuditError, TOOL_START_TYPES  # noqa: E402
from audit_skills import public_skill_names  # noqa: E402
from audit_store import read_events  # noqa: E402
from telemetry_inventory import TelemetryError  # noqa: E402

# Prefissi del nome-tool nativo per chiamata MCP diretta, piu' i nomi che gli host
# normalizzano (osservato su Copilot 2026-09-27: "gbrain-search", non "mcp__gbrain__search").
MCP_TOOLS = {
    "gbrain": ("mcp__gbrain__", "gbrain-", "gbrain_"),
    "codegraph": ("mcp__codegraph__", "codegraph-", "codegraph_"),
}
# graphify e' una skill GLOBALE (~/.claude/skills/graphify), non dichiarata dentro questo
# repo: kanban/audit_skill_names.json (canonical) e' verificato contro le skill DEL REPO
# (test-audit-skills.py), quindi non puo' includerla senza dichiarare una skill locale
# fittizia. Finche' resta fuori dall'elenco pubblico riesaminato, il sanitizzatore
# (audit_schema.native) sostituisce il suo nome con skillNameStatus="omitted" PRIMA che
# arrivi qui: qui sotto lo trattiamo come "non osservabile per policy", mai come "zero uso".
SKILL_TOOLS = ("graphify",)
KNOWN = tuple(MCP_TOOLS) + SKILL_TOOLS
try:
    _OBSERVABLE_SKILLS = frozenset(name for name in SKILL_TOOLS if name in public_skill_names())
except (OSError, ValueError):
    _OBSERVABLE_SKILLS = frozenset()


def moment(value):
    if not isinstance(value, str):
        raise TelemetryError("dati temporali non interpretabili")
    try:
        date = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return date.replace(tzinfo=date.tzinfo or timezone.utc).timestamp()
    except (ValueError, OverflowError) as exc:
        raise TelemetryError("dati temporali non interpretabili") from exc


def _match(tool_name, arguments):
    low = (tool_name or "").lower()
    for name, prefixes in MCP_TOOLS.items():
        if any(low == p.rstrip("-_") or low.startswith(p) for p in prefixes):
            return name
    if low == "skill":
        skill = (arguments or {}).get("skill")
        if skill in SKILL_TOOLS:
            return skill
    return None


def build_report(days, now=None):
    now = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
    end = now.timestamp()
    start = end - days * 86400
    try:
        rows, exists = read_events()
    except (AuditError, OSError, sqlite3.Error) as exc:
        raise TelemetryError("audit non disponibile: archivio non valido o non leggibile") from exc
    counts = {name: {} for name in KNOWN}
    undated = 0
    hosts = set()
    if exists:
        for row in rows:
            if row.get("provenance") != "adapter_reported":
                continue
            if row.get("native_type") not in TOOL_START_TYPES:
                continue
            ts = row.get("timestamp")
            if ts is None:
                undated += 1
                continue
            when = moment(ts)
            if not start <= when <= end:
                continue
            host = row.get("host")
            if host not in ("copilot", "claude"):
                continue
            data = row.get("data")
            if not isinstance(data, dict):
                raise TelemetryError("audit non disponibile: evento incompleto")
            matched = _match(data.get("toolName"), data.get("arguments"))
            if matched is None:
                continue
            hosts.add(host)
            counts[matched][host] = counts[matched].get(host, 0) + 1
    return {
        "window": {"days": days, "start_epoch": start, "end_epoch": end},
        "audit": {"status": "presente" if exists else "assente", "undated_events": undated,
                  "hosts_observed": sorted(hosts)},
        "counts": counts,
        "not_observable": sorted(set(SKILL_TOOLS) - _OBSERVABLE_SKILLS),
    }


def render(report):
    print("  Fonte: audit degli avvii di tool riportati dagli host (esatto, non campionato).")
    print("  Conta un'invocazione SOLO se il nome del tool e' esattamente gbrain/codegraph/graphify;")
    print("  non somma mai queste cifre con le menzioni testuali della sezione 2 qui sopra.")
    audit = report["audit"]
    if audit["status"] != "presente":
        print("  Audit: assente; nessuna invocazione reale misurabile in questa finestra.")
    else:
        not_observable = set(report.get("not_observable", ()))
        for name in KNOWN:
            if name in not_observable:
                print(f"  {name}: non osservabile — nome fuori dall'elenco pubblico riesaminato "
                      "(policy, non zero uso).")
                continue
            per_host = report["counts"][name]
            total = sum(per_host.values())
            if total == 0:
                print(f"  {name}: 0 invocazioni osservate — zero osservato non prova zero uso.")
            else:
                detail = ", ".join(f"{host}: {n}" for host, n in sorted(per_host.items()))
                print(f"  {name}: {total} invocazioni osservate ({detail})")
        if audit["undated_events"]:
            print(f"  (limite) {audit['undated_events']} eventi di avvio senza data: esclusi dalla finestra, non dal totale storico.")
    print("  (limite) comandi bash che lanciano questi strumenti da riga di comando non sono visibili qui:")
    print("           l'audit non porta il testo del comando per i tool bash/Bash.")


class Parser(argparse.ArgumentParser):
    def error(self, _message):
        raise TelemetryError("argomenti non validi; usare --help")


def main():
    parser = Parser(description=__doc__)
    parser.add_argument("--days", type=int, default=30)
    parser.add_argument("--json", action="store_true")
    try:
        args = parser.parse_args()
        if not 1 <= args.days <= 999999:
            raise TelemetryError("giorni non validi")
        report = build_report(args.days)
        print(json.dumps(report, ensure_ascii=True)) if args.json else render(report)
        return 0
    except TelemetryError as exc:
        print(f"telemetry: uso reale conoscenza non misurabile: {exc}", file=sys.stderr)
        return 1
    except (OSError, UnicodeError, sqlite3.Error) as exc:
        print(f"telemetry: uso reale conoscenza non misurabile: sorgente non disponibile o danneggiata ({exc})",
              file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
