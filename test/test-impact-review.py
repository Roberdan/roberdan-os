#!/usr/bin/env python3
"""Impact review: privacy of the store, evidence schema, three separate layers, Rex pilot."""
import fcntl
import io
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "bin"))
import impact_pilot  # noqa: E402
import impact_review  # noqa: E402
import impact_weekly  # noqa: E402
from impact_store import ImpactError, record  # noqa: E402

END = 1792022400.0  # 2026-10-12T00:00:00Z, fixed instant
CUR, PREV, OLD = "2026-10-10T10:00:00Z", "2026-10-02T10:00:00Z", "2026-09-01T10:00:00Z"
GIT = "git:0123abc"


def entry(**over):
    base = {"schema": 1, "kind": "agent", "name": "rex", "task_id": "kb:261012-000001",
            "run_id": "copilot:PRIVATE_session/c1", "observed_at": CUR, "acceptance": "accepted",
            "acceptance_source": "measured", "acceptance_ref": GIT, "adoption": "unassessed"}
    base.update(over)
    return {k: v for k, v in base.items() if v is not None}


class Base(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        self.private = self.tmp / "private"
        self.private.mkdir(mode=0o700)
        self.events = self.tmp / "events"
        env = patch.dict(os.environ, {"HOME": str(self.tmp / "home"), "RDA_PRIVATE_HOME": str(self.private),
                                      "RDA_COPILOT_EVENT_HOME": str(self.events),
                                      "RDA_TELEMETRY_SKILL_DIRS": str(self.tmp / "none")})
        env.start()
        self.addCleanup(env.stop)
        for key in ("RDA_IMPACT_HOME", "RDA_PILOT_CONFIRM_SPEND"):
            os.environ.pop(key, None)
        self.n = 0

    def event(self, kind, call, when, home=None, **data):
        self.n += 1
        path = (home or self.events) / "PRIVATE_session" / "events.jsonl"
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a") as stream:
            stream.write(json.dumps({"id": f"e{self.n}", "type": kind, "timestamp": when,
                                     "data": {"toolCallId": call, **data}}) + "\n")


class Store(Base):
    def test_destination_and_permissions(self):
        record([entry()])
        home = self.private / "impact-review"
        self.assertEqual(home.stat().st_mode & 0o777, 0o700)
        self.assertEqual((home / "evidence.jsonl").stat().st_mode & 0o777, 0o600)
        os.environ["RDA_IMPACT_HOME"] = str(self.tmp / "elsewhere")
        self.assertRaisesRegex(ImpactError, "sotto", record, [entry()])
        os.environ["RDA_IMPACT_HOME"] = str(ROOT / "eval/results")
        self.assertRaises(ImpactError, record, [entry()])
        del os.environ["RDA_IMPACT_HOME"]
        (self.tmp / ".git").mkdir()
        self.assertRaisesRegex(ImpactError, "git", record, [entry()])
        os.rmdir(self.tmp / ".git")
        os.chmod(self.private, 0o755)
        self.assertRaisesRegex(ImpactError, "permessi", record, [entry()])

    def test_schema_rejections_are_explicit_and_atomic(self):
        bad = [entry(name="private-custom-agent"), entry(kind="tool"), entry(extra="x"),
               entry(acceptance="useful"), entry(acceptance_ref="/Users/x/file"),
               entry(acceptance_ref="kb:261012-000001"), entry(adoption="adopted"),
               entry(acceptance="unassessed"), entry(acceptance_ref="private:missing.txt"),
               entry(observed_at="2026-10-10T10:00:00")]
        for value, unit in ((float("inf"), "minutes"), (-1, "minutes"), (True, "count"),
                            (float("nan"), "minutes"), (5, "usd")):
            measure = "work_items" if unit == "count" else "time"
            bad.append(entry(repair=[{"measure": measure, "value": value, "unit": unit,
                                      "source": "measured", "ref": GIT}]))
        for item in bad:
            with self.subTest(item=item):
                self.assertRaises(ImpactError, record, [entry(task_id="kb:261012-000009"), item])
        self.assertFalse((self.private / "impact-review/evidence.jsonl").exists())
        result = subprocess.run([sys.executable, "-B", str(ROOT / "bin/impact_review.py"), "evidence", "record"],
                                input=json.dumps(bad[-4]).replace("NaN", "Infinity"), text=True,
                                capture_output=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("errore", result.stderr)

    def test_conflicts_and_idempotence(self):
        self.assertEqual(record([entry()]), (1, 0))
        self.assertEqual(record([entry()]), (0, 1))
        self.assertRaisesRegex(ImpactError, "stesso run", record, [entry(acceptance="failed")])
        self.assertRaisesRegex(ImpactError, "task", record,
                               [entry(run_id="copilot:PRIVATE_session/c9", acceptance="failed")])
        (self.private / "proof.txt").write_text("x")
        self.assertEqual(record([entry(run_id="copilot:PRIVATE_session/c2")]), (1, 0))
        self.assertEqual(record([entry(task_id="t2", acceptance_ref="private:proof.txt")]), (1, 0))


class Weekly(Base):
    def build(self):
        return impact_weekly.build(ROOT, END, 7, impact_pilot.status("rex-2026-10"))

    def comp(self, report, kind, name):
        return next(c for c in report["components"] if c["kind"] == kind and c["name"] == name)

    def test_three_layers_stay_separate(self):
        self.event("subagent.started", "c1", CUR, agentName="rex")
        self.event("subagent.completed", "c1", CUR)
        self.event("subagent.started", "c0", PREV, agentName="rex")
        self.event("tool.execution_start", "s1", CUR, toolName="skill", arguments={"skill": "film-director"})
        self.event("tool.execution_complete", "s1", CUR, success=True)
        repair = [{"measure": "time", "value": 30, "unit": "seconds", "source": "measured", "ref": GIT}]
        record([entry(repair=repair), entry(run_id="copilot:PRIVATE_session/c1b", repair=repair),
                entry(task_id="stale", run_id="copilot:PRIVATE_session/gone"),
                entry(task_id="other-host", run_id="claude-run-7"),
                entry(task_id="old", observed_at=OLD)])
        report = self.build()
        rex, film = self.comp(report, "agent", "rex"), self.comp(report, "skill", "film-director")
        self.assertEqual(rex["execution"]["current"]["succeeded"], 1)
        self.assertEqual(rex["execution"]["previous"]["starts"], 1)
        self.assertEqual(rex["outcomes"]["tasks"], 3)  # same task across two runs counts once
        self.assertEqual(rex["outcomes"]["linkage"], {"tasks_linked_to_observed_run": 1, "tasks_unlinked": 1,
                                                      "tasks_linkage_not_verifiable": 1})
        self.assertEqual(rex["outcomes"]["repair"], {"time:minutes:measured": 0.5})
        self.assertEqual(rex["outcomes"]["acceptance"], {"accepted:measured": 3})
        # technical success is never promoted to usefulness
        self.assertEqual(film["execution"]["current"]["succeeded"], 1)
        self.assertEqual(film["outcomes"]["status"], "non misurato")
        self.assertEqual(rex["causal"]["status"], "non-preparato")
        self.assertEqual(self.comp(report, "agent", "coach")["execution"]["current"]["starts"], 0)
        text = impact_weekly.render(report)
        dump = impact_weekly.to_json(report) + text
        for secret in ("PRIVATE_session", str(self.tmp), "score"):
            self.assertNotIn(secret, dump)
        self.assertIn("non significa mai usato", text)
        self.assertNotIn("rimuovere", text.lower())

    def test_absent_source_is_not_zero_and_not_comparable(self):
        report = self.build()
        rex = self.comp(report, "agent", "rex")
        self.assertIsNone(rex["execution"]["current"])
        self.assertIsNone(rex["execution"]["previous"])
        self.assertIn("non confrontabile", report["sources"]["comparison"])
        self.event("subagent.started", "c1", CUR, agentName="rex")
        report = self.build()  # previous window has no session: still not comparable
        self.assertIsNone(self.comp(report, "agent", "rex")["execution"]["previous"])

    def test_periodic_idempotent_locked_and_schedule_dry_run(self):
        now = END + 3600
        self.assertEqual(impact_review.periodic(now)["weekly"], "scritto")
        self.assertEqual(impact_review.periodic(now)["weekly"], "gia-prodotto")
        home = self.private / "impact-review"
        self.assertEqual(len(list((home / "receipts").glob("periodic-*.json"))), 1)  # same stamp overwritten
        self.assertTrue((home / "reports/pilot-status-2026-10.json").exists())
        for path in home.rglob("*"):
            self.assertEqual(path.stat().st_mode & 0o077, 0, path.name)
        fd = os.open(home / ".periodic.lock", os.O_WRONLY)
        fcntl.flock(fd, fcntl.LOCK_EX)
        try:
            self.assertRaisesRegex(ImpactError, "in corso", impact_review.periodic, now + 60)
        finally:
            os.close(fd)
        text = impact_review.schedule(False)
        self.assertIn("NON eseguita", text)
        self.assertIn("un file presente non e' un job attivo", text)
        plist = plistlib.loads((ROOT / "scheduling/com.roberdan.rda-impact-review.plist").read_bytes())
        self.assertEqual(plist["Label"], impact_review.LABEL)
        command = plist["ProgramArguments"][-1]
        self.assertIn("$HOME/GitHub/roberdan-os/bin/impact_review.py\" periodic", command)
        self.assertNotIn("worktrees", command)


def model_id():
    lines = subprocess.run(["bash", str(ROOT / "bin/models.sh"), "list", "--status", "current"],
                           capture_output=True, text=True, check=True).stdout.splitlines()
    return lines[1].split()[0]


class Pilot(Base):
    def test_fixture_checks_discriminate(self):
        for case in impact_pilot.load_cases():
            for files, expected in ((case["files"], case["kind"] == "clean"), (case.get("fix"), True)):
                if files is None:
                    continue
                work = self.tmp / case["id"] / str(expected) / "ws"
                work.mkdir(parents=True)
                for name, text in files.items():
                    (work / name).write_text(text)
                self.assertEqual(impact_pilot.run_check(case["check"], work)[0], expected, case["id"])

    def run_slot(self, base, mapping, slot, case, activate=True, model=None):
        arm = base / "arms" / slot["slot"]
        condition = mapping[slot["slot"].split("/")[0]]
        if case["kind"] == "defect":
            for name, text in case["fix"].items():
                (arm / "workspace" / name).write_text(text)
        (arm / "workspace/VERDICT").write_text("changes-needed" if case["kind"] == "defect" else "approve")
        home = arm / "home/.copilot/session-state"
        self.event("tool.execution_start", "t1", CUR, home=home, toolName="bash")
        if condition == "with-rex" and activate:
            self.event("subagent.started", "r1", CUR, home=home, agentName="rex")
            self.event("subagent.completed", "r1", CUR, home=home)
        manifest = json.loads((base / "manifest.json").read_text())
        receipt = {"schema": 1, "pilot_id": "rex-2026-10", "slot": slot["slot"],
                   "model": model or manifest["model"], "timeout_s": 900,
                   "prompt_sha256": slot["prompt_sha256"], "started_at": "2099-01-01T00:00:00Z",
                   "ended_at": "2099-01-01T00:05:00Z", "timing_source": "measured",
                   "exit_code": 0, "timed_out": False}
        (arm / "receipt.json").write_text(json.dumps(receipt))
        return arm

    def test_lifecycle_blinding_guards_and_lost_arms(self):
        self.assertRaisesRegex(ImpactError, "registro", impact_pilot.prepare, "2026-10", "not-a-real-model")
        manifest = impact_pilot.prepare("2026-10", model_id())
        base = self.private / "impact-review/pilots/rex-2026-10"
        self.assertRaisesRegex(ImpactError, "gia' preparato", impact_pilot.prepare, "2026-10", model_id())
        self.assertEqual(len(manifest["slots"]), 20)
        mapping = json.loads((base / "sealed/mapping.json").read_text())
        self.assertEqual(sorted(mapping.values()), ["with-rex", "without-rex"])
        arms = base / "arms"
        names = " ".join(str(p.relative_to(arms)) for p in arms.rglob("*"))
        self.assertNotIn("with", names)
        for path in arms.rglob("*.py"):
            self.assertNotIn("assert", path.read_text())  # hidden checks stay sealed
        state = impact_pilot.status("rex-2026-10")
        self.assertEqual(state["state"], "preparato-non-eseguito")
        self.assertIn("NON eseguito", state["claim"])
        cases = {c["id"]: c for c in impact_pilot.load_cases()}
        slots = manifest["slots"]
        first = slots[0]["slot"]
        self.assertRaisesRegex(ImpactError, "RDA_PILOT_CONFIRM_SPEND", impact_pilot.claim, "rex-2026-10", first)
        os.environ["RDA_PILOT_CONFIRM_SPEND"] = "rex-2026-10"
        for slot in slots:
            impact_pilot.claim("rex-2026-10", slot["slot"])
        self.assertRaisesRegex(ImpactError, "consumato", impact_pilot.claim, "rex-2026-10", first)
        self.assertFalse(list(arms.rglob("handoff")))
        lost = next(s for s in slots if mapping[s["slot"].split("/")[0]] == "with-rex")
        for slot in slots:
            self.run_slot(base, mapping, slot, cases[slot["case"]], activate=slot is not lost)
        results = impact_pilot.ingest("rex-2026-10")
        self.assertEqual(results[lost["slot"]]["activation"], "rex-assente")
        state = impact_pilot.status("rex-2026-10")
        self.assertEqual(state["state"], "parziale")  # lost arm is unknown, never a tie
        self.assertEqual(state["coverage"]["matched_pairs"], 9)
        self.assertEqual(state["pairs"]["ties"], 9)
        self.assertEqual(state["arms"]["without-rex"]["false_positives_on_clean"], "0/4")
        self.assertEqual(state["operator_adoption"], "non misurato")
        arm = base / "arms" / lost["slot"]
        (arm / "receipt.json").write_text((arm / "receipt.json").read_text().replace("05:00", "06:00"))
        self.assertRaisesRegex(ImpactError, "cambiata", impact_pilot.ingest, "rex-2026-10")

    def test_receipt_mismatch_contamination_and_missing_log(self):
        manifest = impact_pilot.prepare("2026-10", model_id())
        base = self.private / "impact-review/pilots/rex-2026-10"
        mapping = json.loads((base / "sealed/mapping.json").read_text())
        cases = {c["id"]: c for c in impact_pilot.load_cases()}
        os.environ["RDA_PILOT_CONFIRM_SPEND"] = "rex-2026-10"
        without = [s for s in manifest["slots"] if mapping[s["slot"].split("/")[0]] == "without-rex"]
        unclaimed = without[0]
        self.run_slot(base, mapping, unclaimed, cases[unclaimed["case"]])
        self.assertRaisesRegex(ImpactError, "senza claim", impact_pilot.ingest, "rex-2026-10")
        impact_pilot.claim("rex-2026-10", unclaimed["slot"])
        self.run_slot(base, mapping, unclaimed, cases[unclaimed["case"]], model="other-model")
        self.assertRaisesRegex(ImpactError, "model", impact_pilot.ingest, "rex-2026-10")
        self.run_slot(base, mapping, unclaimed, cases[unclaimed["case"]])
        home = base / "arms" / unclaimed["slot"] / "home/.copilot/session-state"
        self.event("subagent.started", "rx", CUR, home=home, agentName="rex")
        self.assertEqual(impact_pilot.ingest("rex-2026-10")[unclaimed["slot"]]["activation"], "contaminata")
        other = without[1]
        impact_pilot.claim("rex-2026-10", other["slot"])
        arm = self.run_slot(base, mapping, other, cases[other["case"]])
        (arm / "home/.copilot/session-state/PRIVATE_session/events.jsonl").unlink()
        self.assertEqual(impact_pilot.ingest("rex-2026-10")[other["slot"]]["activation"], "sconosciuta")
        with redirect_stdout(io.StringIO()) as out:
            self.assertEqual(impact_review.main(["pilot", "status", "--pilot", "rex-2026-10"]), 0)
        self.assertEqual(json.loads(out.getvalue())["coverage"]["condition_not_met"], 2)


if __name__ == "__main__":
    unittest.main(verbosity=1)
