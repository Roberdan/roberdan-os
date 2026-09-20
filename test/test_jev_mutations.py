"""Put representative bugs back only in isolated copies of Jev-owned files."""

from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from test_jev_support import ROOT


class MutationTests(unittest.TestCase):
    def test_safety_and_consumer_mutants_are_killed(self):
        cases = [
            ("profiles.py", 'data["classification"] in ("public", "synthetic")', "True",
             "test_jev_profiles.ProfileTests.test_strict_input_schema_and_bounds"),
            ("profiles.py", 'if not linked:', 'if False:',
             "test_jev_profiles.ProfileTests.test_thor_missing_evidence_always_asks_even_for_signal_one"),
            ("profiles.py", 'not item["exact_match"],', 'item["exact_match"],',
             "test_jev_profiles.ProfileTests.test_retrieval_keeps_all_exact_matches_first_and_ties_stable"),
            ("responses.py", 'response["model"] == core.MODEL', "True",
             "test_jev_responses.ResponseTests.test_malformed_answer_shapes_and_numbers"),
            ("ledger.py", 'state["requests"] < settings["max_requests"]', "True",
             "test_jev_ledger.LedgerTests.test_budget_and_count_caps_before_network"),
            ("client.py", 'if not live:', 'if True:',
             "test_jev_profiles.ProfileTests.test_four_cli_live_consumers"),
            ("client.py", 'if not live:', 'if False:',
             "test_jev_security.SecurityTests.test_dry_run_never_opens_private_area_with_or_without_key"),
            ("client.py", 'profile in settings["enabled_profiles"]', 'True',
             "test_jev_security.SecurityTests.test_missing_and_disabled_config_make_zero_calls"),
            ("client.py", 'and approved_sha256 == prepared["sha256"]', 'and True',
             "test_jev_security.SecurityTests.test_hash_required_and_bound_to_exact_payload_before_credential_load"),
            ("ledger.py", 'state["charged_nano_usd"] += cost', 'state["charged_nano_usd"] += 0',
             "test_jev_ledger.LedgerTests.test_outage_retains_reservation_without_retry"),
            ("profiles.py", 'len(encoded) <= core.MAX_REQUEST_BYTES', 'True',
             "test_jev_profiles.ProfileTests.test_exact_payload_byte_boundary"),
            ("private.py", 'stat.S_IMODE(info.st_mode) == mode', 'True',
             "test_jev_security.SecurityTests.test_config_file_and_directory_permissions"),
            ("client.py", 'core.POLICY_VERSION', '"constant-policy"',
             "test_jev_ledger.LedgerTests.test_input_policy_rubric_model_and_config_invalidate_cache"),
            ("client.py", 'profiles.RUBRIC_VERSION', '"constant-rubric"',
             "test_jev_ledger.LedgerTests.test_input_policy_rubric_model_and_config_invalidate_cache"),
            ("client.py", '"config": settings', '"config": {}',
             "test_jev_ledger.LedgerTests.test_input_policy_rubric_model_and_config_invalidate_cache"),
        ]
        for filename, original, replacement, target in cases:
            with self.subTest(target=target), tempfile.TemporaryDirectory(prefix="jev-mutant-") as temp:
                root = Path(temp)
                shutil.copytree(ROOT / "bin/jevlib", root / "bin/jevlib",
                                ignore=shutil.ignore_patterns("__pycache__"))
                (root / "test").mkdir()
                for name in ("test_jev_support.py", target.split(".")[0] + ".py"):
                    shutil.copyfile(ROOT / "test" / name, root / "test" / name)
                path = root / "bin/jevlib" / filename
                source = path.read_text()
                self.assertIn(original, source)
                path.write_text(source.replace(original, replacement))
                result = subprocess.run(
                    [sys.executable, "-m", "unittest", target],
                    cwd=root / "test",
                    env={"HOME": str(root), "PYTHONDONTWRITEBYTECODE": "1"},
                    capture_output=True, text=True, timeout=20,
                )
                self.assertNotEqual(result.returncode, 0, "mutant survived: " + target)
                self.assertIn("FAILED (failures=", result.stderr, result.stderr)
