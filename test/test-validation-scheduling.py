#!/usr/bin/env python3
"""Exercise the real shell scheduler with controlled, isolated suite processes."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / "test/lib-suites.sh"
WORKER = """import fcntl, json, sys, time
from pathlib import Path
p = Path("counts.json")
def change(delta):
    with open("counts.lock", "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        state = json.loads(p.read_text()) if p.exists() else {"active": 0, "peak": 0, "ended": 0}
        state["active"] += delta
        state["peak"] = max(state["peak"], state["active"])
        state["ended"] += delta < 0
        p.write_text(json.dumps(state))
change(1)
time.sleep(0.5)
change(-1)
sys.exit(int(sys.argv[1]))
"""


class Scheduling(unittest.TestCase):
    def run_fixture(self, jobs, body):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "test").mkdir()
            (root / "worker.py").write_text(WORKER)
            for number in range(8):
                (root / f"test/s{number}.sh").write_text("python3 worker.py 0\n")
            (root / "test/failing.sh").write_text("python3 worker.py 7\n")
            env = dict(os.environ, RDA_VALIDATE_JOBS=jobs, RDA_IN_THOR_VERIFY="0")
            if jobs is None:
                del env["RDA_VALIDATE_JOBS"]
            result = subprocess.run(
                ["bash", "-c", f'set -u; ROOT="$PWD"; source "{ENGINE}"\n{body}'],
                cwd=root, env=env, capture_output=True, text=True, timeout=30,
            )
            counts = json.loads((root / "counts.json").read_text()) if (root / "counts.json").exists() else None
            return result, counts

    def test_parallelism_is_bounded_but_not_serialized(self):
        result, counts = self.run_fixture("2", """
for i in 0 1 2 3 4 5 6 7; do _spawn "s$i"; done
for i in 0 1 2 3 4 5 6 7; do _suite "s$i" || exit $?; done
""")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(counts, {"active": 0, "peak": 2, "ended": 8})

    def test_serial_group_shares_slots_and_preserves_failure(self):
        result, counts = self.run_fixture("1", """
_spawn_serial_group s0 failing s1
_spawn s2
_suite s0 || exit $?
_suite failing; code=$?
[ "$code" -eq 7 ] || exit 90
_suite s1 || exit $?
_suite s2 || exit $?
for suite in s0 failing s1 s2; do [ -f "$_PARDIR/$suite.start" ] || exit 91; done
""")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(counts, {"active": 0, "peak": 1, "ended": 4})

    def test_default_limits_workers_to_four(self):
        result, counts = self.run_fixture(None, """
for i in 0 1 2 3 4 5 6 7; do _spawn "s$i"; done
for i in 0 1 2 3 4 5 6 7; do _suite "s$i" || exit $?; done
""")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(counts, {"active": 0, "peak": 4, "ended": 8})

    def test_stalled_launch_queue_has_a_finite_wait(self):
        result, counts = self.run_fixture("1", """
jobs() { printf '123\\n'; }
sleep() { SECONDS=$((SECONDS+901)); }
_wait_slot
""")
        self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
        self.assertIn("no scheduling progress within 15 minutes", result.stderr)
        self.assertIsNone(counts)

    def test_invalid_worker_limits_fail_before_any_suite(self):
        for jobs in ("0", "-1", "abc", "33", "2;echo nope", ""):
            with self.subTest(jobs=jobs):
                result, counts = self.run_fixture(jobs, '_spawn s0; _suite s0')
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertIsNone(counts)
                self.assertIn("RDA_VALIDATE_JOBS", result.stderr)


if __name__ == "__main__":
    unittest.main()
