import json
import subprocess
import sys

from test_jev_support import Fixture, ROOT, core


class EntrypointTests(Fixture):
    def run_cli(self, *args):
        return subprocess.run([sys.executable, str(ROOT / "bin/jev.py"), *args],
                              env=self.env, capture_output=True, text=True, timeout=10)

    def test_script_profiles_and_four_dry_runs(self):
        result = self.run_cli("profiles")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["profiles"], list(core.PROFILES))
        for profile in core.PROFILES:
            result = self.run_cli("evaluate", profile, "--input", str(self.input_file(profile)))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)["status"], "dry_run")
            self.assertEqual(result.stderr, "")
        self.assertFalse(self.area.exists())

    def test_missing_status_and_invalid_command_return_safe_nonzero_json(self):
        result = self.run_cli("status")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(json.loads(result.stdout), core.not_evaluated("missing_config"))
        result = self.run_cli("unknown-private-value")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stderr, "")
        self.assertNotIn("unknown-private-value", result.stdout)

    def test_input_file_required_and_input_io_failure_are_explicit(self):
        result = self.run_cli("evaluate", "twin")
        self.assertEqual(json.loads(result.stdout)["reason"], "invalid_arguments")
        result = self.run_cli("evaluate", "twin", "--input", str(self.home / "absent.json"))
        self.assertEqual(result.returncode, 2)
        self.assertEqual(json.loads(result.stdout)["reason"], "local_io_error")

    def test_help_exposes_explicit_local_recovery(self):
        result = self.run_cli("--help")
        self.assertEqual(result.returncode, 0)
        self.assertIn("acknowledge-overrun", result.stdout)
        result = self.run_cli("acknowledge-overrun", "--help")
        self.assertEqual(result.returncode, 0)
        self.assertIn("--approval REFERENCE", result.stdout)
        self.assertIn("No credentials or network", " ".join(result.stdout.split()))
        self.assertIn("1000", result.stdout)
        self.assertFalse(self.area.exists())
