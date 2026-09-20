import copy
import json
from unittest import mock

from test_jev_support import Fixture, client, core, profiles, reply, sample


class ProfileTests(Fixture):
    def test_four_cli_dry_runs_are_offline_and_nonpersistent(self):
        with mock.patch.object(client, "transport") as network:
            with mock.patch.object(client, "credential", side_effect=AssertionError("credential read")):
                for profile in core.PROFILES:
                    with self.subTest(profile=profile):
                        path = self.input_file(profile)
                        code, result = self.invoke(["evaluate", profile, "--input", str(path)])
                        self.assertEqual(code, 0)
                        self.assertEqual(result["status"], "dry_run")
                        self.assertEqual(result["sha256"], core.digest(result["payload"]))
                        self.assertEqual(set(result["payload"]), {"model", "state", "questions"})
                        self.assertLessEqual(result["payload_bytes"], 12000)
                        self.assertIn("synthetic", result["payload"]["state"])
                        self.assertTrue(result["preserve_original_behavior"])
            network.assert_not_called()
        self.assertFalse((self.home / ".roberdan-os").exists())

    def test_four_cli_live_consumers(self):
        self.configure()
        with mock.patch.object(client, "transport", side_effect=reply) as network:
            for profile in core.PROFILES:
                path = self.input_file(profile)
                sha = profiles.prepare(profile, sample(profile))["sha256"]
                code, result = self.invoke(["evaluate", profile, "--input", str(path),
                                           "--live", "--approved-sha256", sha])
                self.assertEqual((code, result["status"]), (0, "evaluated"))
                self.assertFalse(result["from_cache"])
                self.assertNotIn("payload", result)
                for field in ("options", "candidates", "items", "requirements", "evidence"):
                    for item in sample(profile).get(field, []):
                        self.assertNotIn(item["text"], json.dumps(result, ensure_ascii=False))
            self.assertEqual(network.call_count, 4)

    def test_twin_only_observes_eligible_options(self):
        self.configure()
        with mock.patch.object(client, "transport", side_effect=reply) as network:
            result = self.live("twin")["result"]
        self.assertTrue(result["observation_only"])
        self.assertTrue(result["rubric_review_required"])
        self.assertEqual(result["excluded_ids"], ["due"])
        self.assertEqual(set(result["observations"]), {"uno"})
        self.assertEqual(set(result["observations"]["uno"]), set(profiles.DIMENSIONS))
        self.assertNotIn("EXCLUDED_LOCAL_TEXT", json.dumps(network.call_args.args[0]))
        self.assertNotIn("recommendation", result)
        self.assertNotIn("combined_score", result)

    def test_all_ineligible_stays_offline(self):
        self.configure()
        data = sample("twin")
        data["options"][0]["eligible"] = False
        with mock.patch.object(client, "transport") as network:
            with self.assertRaisesRegex(core.JevError, "no_eligible_questions"):
                self.live("twin", data)
            network.assert_not_called()

    def test_retrieval_keeps_all_exact_matches_first_and_ties_stable(self):
        self.configure()
        with mock.patch.object(client, "transport", side_effect=reply):
            result = self.live("retrieval")["result"]
        self.assertEqual(result["original_order"], ["uno", "due", "tre", "quattro"])
        self.assertEqual(result["ordered_ids"], ["due", "tre", "uno", "quattro"])
        self.assertEqual(set(result["relevance"]), set(result["original_order"]))

    def test_retrieval_orders_nonexact_by_score_without_deleting(self):
        def ranked(payload, key):
            value = reply(payload, key)
            value["answers"]["q3"]["score"] = 3
            return value
        self.configure()
        with mock.patch.object(client, "transport", side_effect=ranked):
            result = self.live("retrieval")["result"]
        self.assertEqual(result["ordered_ids"], ["due", "tre", "quattro", "uno"])

    def test_wanda_only_suggestions(self):
        self.configure()
        with mock.patch.object(client, "transport", side_effect=reply):
            result = self.live()["result"]
        self.assertTrue(result["suggestions_only"])
        self.assertEqual(result["suggestions"]["uno"]["choice"], "decision_needed")

    def test_thor_missing_evidence_always_asks_even_for_signal_one(self):
        self.configure()
        with mock.patch.object(client, "transport", side_effect=reply):
            result = self.live("thor")["result"]
        self.assertTrue(result["non_exhaustive"])
        self.assertEqual(result["requirement_ids"], ["uno", "due"])
        self.assertEqual(result["evidence_ids"], ["prova"])
        self.assertEqual(result["signals"][0]["evidence_ids"], ["prova"])
        missing = result["signals"][1]
        self.assertTrue(missing["missing_evidence"])
        self.assertEqual(missing["evidence_ids"], [])
        self.assertTrue(missing["follow_up_questions"])
        for forbidden in ("confidence", "pass", "fail", "done"):
            self.assertNotIn(forbidden, result)

    def test_thor_pre_enumeration_and_reference_validation(self):
        for mutate in (lambda d: d.update(criteria_recorded=False),
                       lambda d: d.update(criteria_recorded=1),
                       lambda d: d.update(requirements=[]),
                       lambda d: d["evidence"][0].update(requirement_ids=["unknown"])):
            data = sample("thor")
            mutate(data)
            with mock.patch.object(client, "transport") as network:
                with self.assertRaises(core.JevError):
                    client.evaluate("thor", data)
                network.assert_not_called()

    def test_strict_input_schema_and_bounds(self):
        mutations = [
            lambda d: d.update(extra="x"),
            lambda d: d.update(classification="private"),
            lambda d: d.update(classification={}),
            lambda d: d["items"][0].update(password="x"),
            lambda d: d["items"][0].update(text="x" * 1201),
            lambda d: d["items"][0].update(text=" "),
            lambda d: d["items"][0].update(text="\ud800"),
            lambda d: d["items"][0].update(id="../escape"),
            lambda d: d["items"][0].update(id="ghp_abcdefghijk"),
            lambda d: d.update(items=d["items"] * 2),
            lambda d: d.update(items=[]),
            lambda d: d.update(items=[{"id": f"i{i}", "text": "x"} for i in range(9)]),
        ]
        for mutate in mutations:
            data = sample("wanda")
            mutate(data)
            with self.subTest(data=data), self.assertRaises(core.JevError):
                profiles.prepare("wanda", data)
        for field, profile in (("eligible", "twin"), ("exact_match", "retrieval")):
            data = sample(profile)
            collection = "options" if profile == "twin" else "candidates"
            data[collection][0][field] = 1
            with self.assertRaises(core.JevError):
                profiles.prepare(profile, data)

    def test_secret_scanner_rejects_recognizable_keys(self):
        for secret in ("api_key=should-not-leak", "Bearer fakecredential",
                       "ghp_" + "a" * 30, "-----BEGIN PRIVATE KEY-----",
                       "AKIA" + "A" * 16):
            data = sample("wanda")
            data["items"][0]["text"] = secret
            with self.assertRaisesRegex(core.JevError, "unsafe_input"):
                profiles.prepare("wanda", data)

    def test_utf8_request_byte_limit_is_not_character_or_token_limit(self):
        data = sample("wanda")
        data["items"] = [{"id": f"i{i}", "text": "\u00e8" * 1200} for i in range(8)]
        with self.assertRaisesRegex(core.JevError, "payload_too_large"):
            profiles.prepare("wanda", data)

    def test_exact_payload_byte_boundary(self):
        data = sample("wanda")
        data["items"] = [{"id": f"i{i}", "text": "x"} for i in range(8)]
        payload = profiles.prepare("wanda", data)["payload"]
        remaining = core.MAX_REQUEST_BYTES - len(core.canonical(payload))
        for item in data["items"]:
            pairs = min(1199, remaining // 2)
            item["text"] += "\u00e8" * pairs
            remaining -= pairs * 2
            if remaining == 1 and len(item["text"]) < 1200:
                item["text"] += "x"
                remaining -= 1
        self.assertEqual(remaining, 0)
        payload = profiles.prepare("wanda", data)["payload"]
        self.assertEqual(len(core.canonical(payload)), 12000)
        data["items"][-1]["text"] += "x"
        with self.assertRaisesRegex(core.JevError, "payload_too_large"):
            profiles.prepare("wanda", data)

    def test_canonical_hash_and_input_rubric_model_changes(self):
        data = sample("twin")
        original = profiles.prepare("twin", data)["sha256"]
        reordered = dict(reversed(list(data.items())))
        self.assertEqual(original, profiles.prepare("twin", reordered)["sha256"])
        changed = copy.deepcopy(data)
        changed["situation"] += " Cambiata."
        self.assertNotEqual(original, profiles.prepare("twin", changed)["sha256"])
        with mock.patch.object(core, "MODEL", "test-model"):
            self.assertNotEqual(original, profiles.prepare("twin", data)["sha256"])
        with mock.patch.dict(profiles.DIMENSIONS, {"focus": ["a", "b", "c", "d"]}):
            self.assertNotEqual(original, profiles.prepare("twin", data)["sha256"])
