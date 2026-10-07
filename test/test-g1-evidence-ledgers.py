#!/usr/bin/env python3
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read_tsv(relative: str, expected: list[str]) -> list[dict[str, str]]:
    path = ROOT / relative
    with path.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    assert rows, f"{relative}: no rows"
    assert list(rows[0]) == expected, f"{relative}: schema drift"
    for number, row in enumerate(rows, 2):
        empty = [key for key, value in row.items() if not value.strip()]
        assert not empty, f"{relative}:{number}: empty fields {empty}"
        assert all(token not in row.values() for token in ("TBD", "TODO", "unknown")), (
            f"{relative}:{number}: unsupported placeholder"
        )
    return rows


def existing_paths(cell: str, relative: str, row_number: int) -> None:
    for item in cell.split(";"):
        path = ROOT / item
        assert path.exists(), f"{relative}:{row_number}: missing evidence {item}"


capability = read_tsv(
    "docs/evidence/capability-ledger.tsv",
    [
        "component",
        "capability",
        "trigger",
        "data",
        "owner",
        "failure_mode",
        "consumer",
        "proof",
        "fallback",
        "metric",
        "rollback",
    ],
)
assert len({row["component"] for row in capability}) == len(capability), "duplicate component"
for index, row in enumerate(capability, 2):
    existing_paths(row["proof"], "capability-ledger.tsv", index)
assert any(row["component"] == "codex-cli" and "unproven" in row["failure_mode"].lower()
           for row in capability), "Codex execution limit disappeared"

hooks = read_tsv(
    "docs/evidence/hook-parity.tsv",
    [
        "capability",
        "claude_event",
        "copilot_event",
        "codex_event",
        "blocking",
        "implementation",
        "behavioral_test",
        "gap",
    ],
)
for index, row in enumerate(hooks, 2):
    existing_paths(row["implementation"], "hook-parity.tsv", index)
    existing_paths(row["behavioral_test"], "hook-parity.tsv", index)
    assert row["blocking"] in {"no", "yes", "ask-or-deny", "bounded-block"}
assert any(row["capability"] == "goal-gate" and row["blocking"] == "yes" for row in hooks)
assert all(row["codex_event"] in {"none", "AGENTS discovery"} for row in hooks)

recovery = read_tsv(
    "docs/evidence/recovery-matrix.tsv",
    ["failure_mode", "claude_code", "copilot_cli", "codex", "evidence", "limit"],
)
for index, row in enumerate(recovery, 2):
    existing_paths(row["evidence"], "recovery-matrix.tsv", index)
assert all("proven" not in row["codex"].lower() for row in recovery)
assert any(
    row["failure_mode"] == "session-crash"
    and "no callback" in row["claude_code"].lower()
    and "no callback" in row["copilot_cli"].lower()
    for row in recovery
)

jobs = read_tsv(
    "docs/evidence/job-slo.tsv",
    [
        "label",
        "owner",
        "domain",
        "plist",
        "receipt_glob",
        "max_age_seconds",
        "correctness_probe",
    ],
)
assert len(jobs) >= 10, "job SLO manifest is not an explicit system population"
assert len({row["label"] for row in jobs}) == len(jobs), "duplicate job label"
for row in jobs:
    assert row["domain"] in {"user", "system"}
    assert row["plist"] == "auto" or row["plist"].endswith(".plist")
    assert row["max_age_seconds"].isdigit()
    if row["receipt_glob"] == "-":
        assert row["max_age_seconds"] == "0"
    if row["correctness_probe"] != "-":
        assert (ROOT / row["correctness_probe"]).exists(), (
            f"missing correctness probe {row['correctness_probe']}"
        )

telemetry = read_tsv(
    "docs/evidence/telemetry-coverage.tsv",
    [
        "area",
        "source",
        "unit",
        "quality",
        "current_coverage",
        "honest_limit",
        "proof",
    ],
)
assert len({row["area"] for row in telemetry}) == len(telemetry), "duplicate telemetry area"
assert any(row["quality"] == "unproven" for row in telemetry)
for index, row in enumerate(telemetry, 2):
    existing_paths(row["proof"], "telemetry-coverage.tsv", index)

print("test-g1-evidence-ledgers: PASS")
