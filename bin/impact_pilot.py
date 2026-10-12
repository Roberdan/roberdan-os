"""Monthly Rex pilot: fixed synthetic cases, blind arms, rigorous result ingestion.

This module never calls a model. `prepare` fixes cases, seed, repetitions, model and
limits before any result exists; `claim` is the one-shot consume guard that hands the
operator the exact command for one slot; `ingest` validates operator receipts against
the manifest, re-runs the predeclared objective check itself and reads Rex activation
from the slot's own native event log; `status` aggregates without inventing scores.
"""
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import random
import re
import subprocess
import tempfile

from impact_store import ImpactError, digest, impact_home, load_evidence, parse_time, write_private, secure_dir
from telemetry_native import read_records

ROOT = Path(__file__).resolve().parent.parent
CONDITIONS = ("with-rex", "without-rex")
REVIEW = ("Before writing VERDICT, obtain a code review of the change from the `rex` agent "
          "(start it as a subagent) and decide on each of its findings.\n")
PROMPT = """You are working in an isolated synthetic repository (the current directory).
A teammate submitted the change in {files} for merge.
Intent: {intent}
Task: decide whether the change implements the intent. If it does not, fix the code in place;
if it does, leave it unchanged. Write a file named VERDICT containing exactly one word:
approve (the submitted change was already correct) or changes-needed (it was not).
Gates, identical in every condition: stay inside this directory; no network; no git push;
before finishing, verify your claim with an executed check and state the evidence
(verify-done discipline, the @thor gate).
{review}"""
RECEIPT_KEYS = {"schema", "pilot_id", "slot", "model", "timeout_s", "prompt_sha256", "started_at",
                "ended_at", "timing_source", "exit_code", "timed_out"}


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_cases(root=ROOT):
    data = json.loads((root / "eval/rex-pilot/cases.json").read_text(encoding="utf-8"))
    cases = data["cases"]
    if len(cases) != 10 or len({c["id"] for c in cases}) != 10:
        raise ImpactError("casi del pilota: servono 10 casi con id distinti")
    if not {c["kind"] for c in cases} == {"defect", "clean"}:
        raise ImpactError("casi del pilota: servono casi con difetto e casi senza difetto")
    return cases


def run_check(code, workspace):
    with tempfile.TemporaryDirectory() as tmp:
        sealed = Path(tmp) / "check.py"
        sealed.write_text("import os, sys\nsys.path.insert(0, os.getcwd())\n" + code, encoding="utf-8")
        try:
            result = subprocess.run(["python3", "-B", "-E", "-s", str(sealed)], cwd=workspace,
                                    capture_output=True, timeout=30, check=False)
        except subprocess.TimeoutExpired:
            return False, None, None
        return result.returncode == 0, result.returncode, digest(result.stdout + result.stderr)


def pilot_dir(pilot_id):
    if not re.fullmatch(r"rex-\d{4}-\d{2}", pilot_id):
        raise ImpactError("pilota: identificativo atteso rex-AAAA-MM")
    return impact_home() / "pilots" / pilot_id


def prepare(month, model, repetitions=1, seed=None, timeout_s=900, root=ROOT):
    if not re.fullmatch(r"\d{4}-(0[1-9]|1[0-2])", month or ""):
        raise ImpactError("pilota: mese atteso AAAA-MM")
    if not 1 <= repetitions <= 5 or not 60 <= timeout_s <= 7200:
        raise ImpactError("pilota: ripetizioni 1..5 e limite 60..7200 secondi")
    check = subprocess.run(["bash", str(root / "bin/models.sh"), "validate", "--model", model],
                           capture_output=True, text=True, check=False)
    if check.returncode:
        raise ImpactError("pilota: modello assente dal registro rivisto (bin/models.sh validate)")
    pilot_id = f"rex-{month}"
    base = pilot_dir(pilot_id)
    if base.exists():
        raise ImpactError("pilota gia' preparato: manifest, seme e selezione non si riscrivono")
    seed = seed or pilot_id
    cases = load_cases(root)
    rng = random.Random(seed)
    blind = {c: f"arm-{digest(f'{seed}:{c}')[:10]}" for c in CONDITIONS}
    secure_dir(base / "sealed" / "checks")
    slots = []
    for case in cases:
        write_private(base / "sealed/checks" / f"{case['id']}.py", case["check"])
        for condition in CONDITIONS:
            prompt = PROMPT.format(files=", ".join(sorted(case["files"])), intent=case["intent"],
                                   review=REVIEW if condition == "with-rex" else "")
            for rep in range(1, repetitions + 1):
                slot = f"{blind[condition]}/{case['id']}-r{rep}"
                for name, text in case["files"].items():
                    write_private(base / "arms" / slot / "workspace" / name, text)
                write_private(base / "arms" / slot / "prompt.md", prompt)
                slots.append({"slot": slot, "case": case["id"], "kind": case["kind"],
                              "repetition": rep, "prompt_sha256": digest(prompt)})
    rng.shuffle(slots)
    write_private(base / "sealed/mapping.json", json.dumps(
        {v: k for k, v in blind.items()}, indent=1, sort_keys=True) + "\n")
    manifest = {"schema": 1, "pilot_id": pilot_id, "month": month, "seed": seed,
                "repetitions": repetitions, "model": model, "limits": {"timeout_s": timeout_s},
                "selection": "tutti i 10 casi registrati, fissati prima di ogni risultato",
                "case_registry_sha256": digest((root / "eval/rex-pilot/cases.json").read_bytes()),
                "conditions": {"identical": ["casi, prompt base, modello, limiti, gate di sicurezza e @thor"],
                               "varies": "passo di revisione Rex attivato vs agente Rex assente"},
                "slots": slots, "prepared_at": now_iso(), "state": "preparato-non-eseguito"}
    write_private(base / "manifest.json", json.dumps(manifest, indent=1, sort_keys=True) + "\n")
    return manifest


def _manifest(pilot_id):
    path = pilot_dir(pilot_id) / "manifest.json"
    if not path.is_file():
        raise ImpactError("pilota non preparato")
    return json.loads(path.read_text(encoding="utf-8"))


def _slot(manifest, slot):
    for item in manifest["slots"]:
        if item["slot"] == slot:
            return item
    raise ImpactError("slot sconosciuto per questo pilota")


def claim(pilot_id, slot):
    if os.environ.get("RDA_PILOT_CONFIRM_SPEND") != pilot_id:
        raise ImpactError(f"rifiutato: serve RDA_PILOT_CONFIRM_SPEND={pilot_id} (autorizzazione di spesa)")
    manifest, base = _manifest(pilot_id), pilot_dir(pilot_id)
    _slot(manifest, slot)
    arm = base / "arms" / slot
    try:
        os.mkdir(arm / ".claimed", 0o700)
    except FileExistsError as exc:
        raise ImpactError("rifiutato: slot gia' consumato") from exc
    write_private(arm / ".claimed/at", now_iso() + "\n")
    condition = json.loads((base / "sealed/mapping.json").read_text())[slot.split("/")[0]]
    setup = ("copy RDA_PILOT_HOME_TEMPLATE into home/ and confirm a rex agent file is installed"
             if condition == "with-rex" else
             "copy RDA_PILOT_HOME_TEMPLATE into home/ and remove every agents/rex* file from that copy")
    text = (f"slot: {slot}\n1. cd \"{arm}\"; {setup}\n"
            f"2. cd workspace && HOME=\"{arm}/home\" RDA_PILOT_MODEL={manifest['model']} "
            f"timeout {manifest['limits']['timeout_s']} $RDA_EVAL_AGENT_CMD < ../prompt.md\n"
            "3. write receipt.json next to prompt.md with keys: " + ", ".join(sorted(RECEIPT_KEYS)) + "\n")
    write_private(base / "sealed/handoff" / (slot.replace("/", "__") + ".txt"), text)
    return text


def _activation(home, condition):
    events = home / ".copilot/session-state"
    rows, meta = read_records(0, 4e9, {}, frozenset(), home=events)
    if meta["status"] != "presente" or meta["files"] == 0:
        return "sconosciuta", False
    starts = {r["call"] for r in rows if r["kind"] == "subagent.started" and r["name"] == "rex"}
    done = {r["call"] for r in rows if r["kind"] == "subagent.completed" and r["success"] is True}
    if condition == "without-rex":
        return ("assenza-verificata", True) if not starts else ("contaminata", False)
    if starts & done:
        return "rex-attivato-e-completato", True
    return ("rex-avviato-senza-esito" if starts else "rex-assente"), False


def _receipt(arm, manifest, item):
    receipt = json.loads((arm / "receipt.json").read_text(encoding="utf-8"))
    if not isinstance(receipt, dict) or set(receipt) != RECEIPT_KEYS or receipt["schema"] != 1:
        raise ImpactError(f"{item['slot']}: ricevuta con campi diversi da quelli attesi")
    expected = {"pilot_id": manifest["pilot_id"], "slot": item["slot"], "model": manifest["model"],
                "timeout_s": manifest["limits"]["timeout_s"], "prompt_sha256": item["prompt_sha256"]}
    for key, value in expected.items():
        if receipt[key] != value:
            raise ImpactError(f"{item['slot']}: ricevuta non corrisponde al manifest ({key})")
    if digest((arm / "prompt.md").read_bytes()) != item["prompt_sha256"]:
        raise ImpactError(f"{item['slot']}: prompt modificato dopo la preparazione")
    started, ended = parse_time(receipt["started_at"]), parse_time(receipt["ended_at"])
    claimed = parse_time((arm / ".claimed/at").read_text().strip())
    if not claimed <= started <= ended or ended - started > receipt["timeout_s"] + 60:
        raise ImpactError(f"{item['slot']}: tempi incoerenti con claim e limite")
    if receipt["timing_source"] not in ("measured", "operator-declared") \
            or type(receipt["exit_code"]) is not int or type(receipt["timed_out"]) is not bool:
        raise ImpactError(f"{item['slot']}: esito o provenienza dei tempi non validi")
    return receipt, ended - started


def ingest(pilot_id, root=ROOT):
    manifest, base = _manifest(pilot_id), pilot_dir(pilot_id)
    mapping = json.loads((base / "sealed/mapping.json").read_text())
    cases = {c["id"]: c for c in load_cases(root)}
    results_path = base / "results.json"
    results = json.loads(results_path.read_text()) if results_path.exists() else {}
    for item in manifest["slots"]:
        arm = base / "arms" / item["slot"]
        if not (arm / "receipt.json").exists():
            continue
        if not (arm / ".claimed").is_dir():
            raise ImpactError(f"{item['slot']}: ricevuta senza claim (consumo non registrato)")
        raw = (arm / "receipt.json").read_bytes()
        receipt, seconds = _receipt(arm, manifest, item)
        old = results.get(item["slot"])
        if old and old["receipt_sha256"] != digest(raw):
            raise ImpactError(f"{item['slot']}: ricevuta cambiata dopo l'acquisizione")
        condition = mapping[item["slot"].split("/")[0]]
        activation, met = _activation(arm / "home", condition)
        workspace, case = arm / "workspace", cases[item["case"]]
        passed, code, output = run_check((base / "sealed/checks" / f"{case['id']}.py").read_text(), workspace)
        verdict_file = workspace / "VERDICT"
        verdict = verdict_file.read_text().strip().lower() if verdict_file.is_file() else "assente"
        changed = sum((workspace / n).read_text() != t if (workspace / n).is_file() else True
                      for n, t in case["files"].items())
        extra = sum(1 for p in workspace.rglob("*") if p.is_file() and p.name != "VERDICT"
                    and "__pycache__" not in p.parts and p.name not in case["files"])
        results[item["slot"]] = {
            "case": item["case"], "kind": item["kind"], "repetition": item["repetition"],
            "condition": condition, "activation": activation, "condition_met": met,
            "check_pass": passed, "check_exit": code, "check_output_sha256": output,
            "verdict": verdict if verdict in ("approve", "changes-needed") else "non valido",
            "files_changed": changed + extra, "agent_exit": receipt["exit_code"],
            "timed_out": receipt["timed_out"], "seconds": round(seconds, 3),
            "timing_source": receipt["timing_source"], "receipt_sha256": digest(raw)}
    write_private(results_path, json.dumps(results, indent=1, sort_keys=True) + "\n")
    return results


def status(pilot_id):
    base = pilot_dir(pilot_id)
    if not (base / "manifest.json").exists():
        return {"pilot_id": pilot_id, "state": "non-preparato",
                "claim": "pilota non preparato: nessuna evidenza controllata su Rex"}
    manifest = _manifest(pilot_id)
    results = json.loads((base / "results.json").read_text()) if (base / "results.json").exists() else {}
    slots = manifest["slots"]
    claimed = sum((base / "arms" / s["slot"] / ".claimed").is_dir() for s in slots)
    receipts = sum((base / "arms" / s["slot"] / "receipt.json").exists() for s in slots)
    valid = {k: v for k, v in results.items() if v["condition_met"]}
    arms = {}
    for condition in CONDITIONS:
        rows = [v for v in valid.values() if v["condition"] == condition]
        defect = [v for v in rows if v["kind"] == "defect"]
        clean = [v for v in rows if v["kind"] == "clean"]
        times = sorted(v["seconds"] for v in rows)
        arms[condition] = {
            "outcomes": len(rows), "check_pass": sum(v["check_pass"] for v in rows),
            "defects_detected": f"{sum(v['verdict'] == 'changes-needed' for v in defect)}/{len(defect)}",
            "false_positives_on_clean": f"{sum(v['verdict'] == 'changes-needed' for v in clean)}/{len(clean)}",
            "regressions_on_clean": f"{sum(not v['check_pass'] for v in clean)}/{len(clean)}",
            "files_changed": sum(v["files_changed"] for v in rows),
            "agent_failures": sum(v["agent_exit"] != 0 or v["timed_out"] for v in rows),
            "median_seconds": times[len(times) // 2] if times else None,
            "timing_sources": sorted({v["timing_source"] for v in rows})}
    pairs = {}
    for v in valid.values():
        pairs.setdefault((v["case"], v["repetition"]), {})[v["condition"]] = v["check_pass"]
    complete = [p for p in pairs.values() if len(p) == 2]
    expected = len(slots) // 2
    adoption = {}
    for entry in load_evidence():
        if entry["task_id"].startswith(f"eval:{pilot_id}/") and entry["adoption"] != "unassessed":
            adoption[entry["adoption"]] = adoption.get(entry["adoption"], 0) + 1
    state = ("preparato-non-eseguito" if not complete else
             "parziale" if len(complete) < expected else "completo")
    claim_text = {"preparato-non-eseguito":
                  "pilota NON eseguito: nessuna coppia valida; le 10 fixture non sono evidenza",
                  "parziale": f"parziale: {len(complete)}/{expected} coppie valide; le mancanti sono ignote, non pareggi",
                  "completo": "contributo di Rex SOLO in queste condizioni (modello, limiti, casi sintetici); "
                              "non superiorita' generale"}[state]
    return {"pilot_id": pilot_id, "state": state, "claim": claim_text,
            "coverage": {"selected_slots": len(slots), "claimed": claimed, "receipts": receipts,
                         "ingested": len(results), "condition_met": len(valid),
                         "condition_not_met": len(results) - len(valid),
                         "receipts_not_ingested": receipts - len(results),
                         "matched_pairs": len(complete), "expected_pairs": expected},
            "arms": arms,
            "pairs": {"with_better": sum(p["with-rex"] and not p["without-rex"] for p in complete),
                      "without_better": sum(p["without-rex"] and not p["with-rex"] for p in complete),
                      "ties": sum(p["with-rex"] == p["without-rex"] for p in complete)},
            "operator_adoption": adoption or "non misurato",
            "resources": "non misurato: le ricevute non portano consumi verificati"}

