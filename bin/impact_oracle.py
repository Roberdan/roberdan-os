"""Rex pilot oracle: evaluation-only material kept apart from what the agent may read.

The oracle (objective checks, reference fixes, condition mapping) is never part of the
agent-visible inputs. Two sources exist and they are never confused:
  - public-calibration: eval/rex-pilot/calibration-cases.json. Its answers are public in the
    repo and in git history, so it exercises the pipeline and never supports an effect claim;
  - private-holdout: an operator-supplied file under ~/.roberdan-os/private, outside git,
    sharing no case with the public calibration set. Only this can support a blinded claim.
Read scope is enforced mechanically with macOS sandbox-exec (deny reads of the private base
except the slot itself, and of the pilot fixtures in every known checkout). The profile is
probed at prepare time; where it cannot be verified the comparison is marked compromised.
Same-user limit: this is containment against reading the answers, not a security boundary.
"""
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from impact_store import ImpactError, digest, inside_git, private_base

ROOT = Path(__file__).resolve().parent.parent
CALIBRATION = ROOT / "eval/rex-pilot/calibration-cases.json"
CASE_KEYS = {"id", "kind", "intent", "files", "check", "fix"}
ORACLE_MARKERS = ("/sealed", "mapping.json", "calibration-cases", "rex-pilot", "holdout")


def run_check(code, workspace):
    """Run a predeclared check against a workspace. None = could not be decided."""
    with tempfile.TemporaryDirectory() as tmp:
        script = Path(tmp) / "check.py"
        script.write_text("import os, sys\nsys.path.insert(0, os.getcwd())\n" + code, encoding="utf-8")
        try:
            result = subprocess.run(["python3", "-B", "-E", "-s", str(script)], cwd=workspace,
                                    capture_output=True, timeout=30, check=False)
        except subprocess.TimeoutExpired:
            return None, None, None
        return result.returncode == 0, result.returncode, digest(result.stdout + result.stderr)


def _validate(cases):
    if not isinstance(cases, list) or len(cases) < 4 or len({c.get("id") for c in cases}) != len(cases):
        raise ImpactError("oracolo: servono almeno 4 casi con id distinti")
    for case in cases:
        if not isinstance(case, dict) or not {"id", "kind", "intent", "files", "check"} <= set(case) \
                or set(case) - CASE_KEYS:
            raise ImpactError("oracolo: caso con campi mancanti o sconosciuti")
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,47}", case["id"]) or case["kind"] not in ("defect", "clean"):
            raise ImpactError("oracolo: id o kind non validi")
        if not isinstance(case["files"], dict) or not case["files"] or not all(
                re.fullmatch(r"[a-z_][a-z0-9_]{0,31}\.py", n) and isinstance(t, str) for n, t in case["files"].items()):
            raise ImpactError("oracolo: file del caso non validi")
    if {c["kind"] for c in cases} != {"defect", "clean"}:
        raise ImpactError("oracolo: servono casi con difetto e casi senza difetto")
    return cases


def baseline(cases):
    """Each check must fail on a defect as submitted and pass on a clean case as submitted."""
    result = {}
    with tempfile.TemporaryDirectory() as tmp:
        for case in cases:
            work = Path(tmp) / case["id"]
            work.mkdir()
            for name, text in case["files"].items():
                (work / name).write_text(text, encoding="utf-8")
            passed = run_check(case["check"], work)[0]
            if passed is None or passed != (case["kind"] == "clean"):
                raise ImpactError(f"oracolo: il controllo di {case['id']} non discrimina il caso inviato")
            result[case["id"]] = passed
    return result


def outcome(kind, pre, post, changed):
    """Objective outcome from the sealed check before and after; never from the VERDICT."""
    if pre is None or post is None or pre != (kind == "clean"):
        return "ignoto"
    if kind == "defect":
        return "corretto" if post else "non-corretto"
    return "rotto" if not post else "modificato-ma-valido" if changed else "intatto"


def pre_check(case):
    with tempfile.TemporaryDirectory() as tmp:
        for name, text in case["files"].items():
            (Path(tmp) / name).write_text(text, encoding="utf-8")
        return run_check(case["check"], tmp)[0]


def summarize(rows):
    """Per-arm tallies: objective outcomes and the agent's self-declared verdict, never merged."""
    defect = [v for v in rows if v["kind"] == "defect"]
    clean = [v for v in rows if v["kind"] == "clean"]
    tally = lambda group, value: f"{sum(v['outcome'] == value for v in group)}/{len(group)}"  # noqa: E731
    declared = lambda group: f"{sum(v['verdict'] == 'changes-needed' for v in group)}/{len(group)}"  # noqa: E731
    times = sorted(v["seconds"] for v in rows)
    return {"outcomes": len(rows),
            "objective": {"defects_fixed": tally(defect, "corretto"), "defects_not_fixed": tally(defect, "non-corretto"),
                          "defects_unknown": tally(defect, "ignoto"), "clean_untouched": tally(clean, "intatto"),
                          "clean_modified_still_passing": tally(clean, "modificato-ma-valido"),
                          "clean_broken": tally(clean, "rotto"), "clean_unknown": tally(clean, "ignoto")},
            "self_declared": {"note": "VERDICT scritto dall'agente: dichiarazione, non prova",
                              "changes_needed_on_defect": declared(defect),
                              "changes_needed_on_clean": declared(clean),
                              "declared_but_not_fixed": sum(v["verdict"] == "changes-needed"
                                                            and v["outcome"] != "corretto" for v in defect),
                              "verdict_invalid": sum(v["verdict"] == "non valido" for v in rows)},
            "files_changed": sum(v["files_changed"] for v in rows),
            "agent_failures": sum(v["agent_exit"] != 0 or v["timed_out"] for v in rows),
            "median_seconds": times[len(times) // 2] if times else None,
            "timing_sources": sorted({v["timing_source"] for v in rows})}


def fingerprints(case):
    """A case is exposed if its id, its submitted files or its check already exist publicly."""
    return {case["id"], digest(json.dumps(case["files"], sort_keys=True)), digest(case["check"])}


def load(source=None):
    """Return (role, cases). No source -> public calibration; a source -> private holdout."""
    public = json.loads(CALIBRATION.read_text(encoding="utf-8"))
    if public.get("role") != "public-calibration":
        raise ImpactError("calibrazione: il registro pubblico deve dichiararsi public-calibration")
    if source is None:
        return "public-calibration", _validate(public["cases"])
    path = Path(source).expanduser().resolve()
    base = private_base().expanduser().resolve()
    if base not in path.parents or inside_git(path) or not path.is_file():
        raise ImpactError("oracolo privato: il file deve esistere sotto ~/.roberdan-os/private, fuori da git")
    if path.stat().st_mode & 0o077:
        raise ImpactError("oracolo privato: permessi aperti ad altri utenti (serve 0600)")
    try:
        cases = _validate(json.loads(path.read_text(encoding="utf-8")).get("cases"))
    except (ValueError, AttributeError) as exc:
        raise ImpactError("oracolo privato: JSON non interpretabile") from exc
    exposed = set().union(*(fingerprints(c) for c in public["cases"]))
    if any(fingerprints(c) & exposed for c in cases):
        raise ImpactError("oracolo privato: contiene casi pubblici; una risposta gia' esposta non e' holdout")
    return "private-holdout", cases


def checkouts():
    found = {ROOT, ROOT.parent.parent.parent / "roberdan-os", Path.home() / "GitHub/roberdan-os"}
    return sorted(str(p.resolve()) for p in found if p.exists())


def profile(slot_dir):
    """sandbox-exec profile: the agent reads its own slot, never the oracle or the fixtures."""
    q = lambda p: '"' + str(p).replace("\\", "\\\\").replace('"', '\\"') + '"'  # noqa: E731
    base = private_base().expanduser().resolve()
    lines = ["(version 1)", "(allow default)",
             f"(deny file-read* file-write* (subpath {q(base)}))"]
    lines += [f"(deny file-read* (subpath {q(Path(c) / 'eval/rex-pilot')}))" for c in checkouts()]
    lines.append(f"(allow file-read* file-write* (subpath {q(Path(slot_dir).resolve())}))")
    return "\n".join(lines) + "\n"


def probe(profile_path, readable, forbidden):
    """Mechanical proof that the profile blocks the oracle and lets the slot through."""
    if shutil.which("sandbox-exec") is None:
        return False
    ok = subprocess.run(["sandbox-exec", "-f", str(profile_path), "/bin/cat", str(readable)],
                        capture_output=True, check=False).returncode == 0
    blocked = subprocess.run(["sandbox-exec", "-f", str(profile_path), "/bin/cat", str(forbidden)],
                             capture_output=True, check=False).returncode != 0
    return ok and blocked


def oracle_references(events_dir):
    """Detector, not proof: count tool calls whose arguments name oracle locations."""
    hits = 0
    for path in sorted(Path(events_dir).glob("*/events.jsonl")) if Path(events_dir).is_dir() else []:
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            try:
                raw = json.loads(line)
            except ValueError:
                continue
            if isinstance(raw, dict) and raw.get("type") == "tool.execution_start":
                args = json.dumps((raw.get("data") or {}).get("arguments", ""))
                hits += any(marker in args for marker in ORACLE_MARKERS)
    return hits
