from unittest import mock

from test_jev_support import Fixture, client, core, reply, sample
from jevlib.private import Area


class RecoveryTests(Fixture):
    def overrun(self):
        self.configure()
        with mock.patch.object(client, "transport", side_effect=lambda p, k: reply(p, k, 200000)):
            return self.live()

    def changed(self):
        data = sample("wanda")
        data["items"][0]["text"] += " Changed."
        return data

    def snapshot(self):
        return {p.name: p.read_bytes() for p in self.area.iterdir()}

    def test_latched_cache_hit_succeeds_without_key_or_transport(self):
        initial = self.overrun()
        before = self.snapshot()
        self.env.pop("TYPESAFE_API_KEY")
        with mock.patch.object(client, "credential", side_effect=AssertionError("credential read")):
            with mock.patch.object(client, "transport") as network:
                cached = self.live()
                network.assert_not_called()
        self.assertTrue(cached["from_cache"])
        self.assertEqual(cached["result"], initial["result"])
        self.assertTrue(cached["consumption"]["reservation_exceeded"])
        self.assertEqual(cached["warning"], "reservation_exceeded_next_network_call_blocked")
        self.assertEqual(before, self.snapshot())

    def test_latched_cache_miss_stops_before_key_or_transport(self):
        self.overrun()
        before = self.snapshot()
        with mock.patch.object(client, "credential", side_effect=AssertionError("credential read")):
            with mock.patch.object(client, "transport") as network:
                with self.assertRaisesRegex(core.JevError, "reservation_exceeded"):
                    self.live(data=self.changed())
                network.assert_not_called()
        self.assertEqual(before, self.snapshot())

    def test_acknowledgement_preserves_usage_uncertainty_cache_and_config(self):
        self.configure()
        with mock.patch.object(client, "transport", side_effect=reply):
            self.live()
        def malformed(payload, key):
            result = reply(payload, key, 200000)
            result["answers"] = {}
            return result
        with mock.patch.object(client, "transport", side_effect=malformed):
            with self.assertRaisesRegex(core.JevError, "malformed_response"):
                self.live(data=self.changed())
        before, files_before = self.state(), self.snapshot()
        self.assertEqual(before["uncertain_requests"], 1)
        reference = "operator-reviewed-local-overrun"
        self.env.pop("TYPESAFE_API_KEY")
        with mock.patch.object(client, "credential", side_effect=AssertionError("credential read")):
            with mock.patch.object(client, "transport") as network:
                code, output = self.invoke(["acknowledge-overrun", "--approval", reference])
                cached = self.live()
                network.assert_not_called()
        self.assertEqual((code, output["status"]), (0, "overrun_acknowledged"))
        self.assertTrue(cached["from_cache"])
        expected = dict(before, reservation_exceeded=False, overrun_acknowledgement={
            "approval_sha256": core.digest(reference), "at_request": before["requests"]})
        self.assertEqual(self.state(), expected)
        self.assertEqual(output["consumption"]["overrun_acknowledgement"],
                         expected["overrun_acknowledgement"])
        status = client.status(self.home)
        self.assertEqual(status["consumption"], output["consumption"])
        after = self.snapshot()
        self.assertEqual(after["config.json"], files_before["config.json"])
        self.assertEqual(after["lock"], files_before["lock"])
        self.assertNotIn(reference.encode(), after["state.json"])

    def test_acknowledgement_allows_next_request_without_resetting_counters(self):
        self.overrun()
        client.acknowledge_overrun("reviewed", self.home)
        with mock.patch.object(client, "transport", side_effect=reply) as network:
            output = self.live(data=self.changed())
            network.assert_called_once()
        self.assertFalse(output["from_cache"])
        self.assertEqual(self.state()["requests"], 2)
        self.assertEqual(self.state()["input_tokens"], 200100)
        self.assertEqual(self.state()["charged_nano_usd"], 200100 * 42)
        self.assertEqual(self.state()["overrun_acknowledgement"]["at_request"], 1)

    def test_acknowledgement_does_not_release_request_or_budget_limits(self):
        self.configure(max_requests=1, budget_usd=0.01)
        with mock.patch.object(client, "transport", side_effect=lambda p, k: reply(p, k, 200000)):
            self.live()
        client.acknowledge_overrun("reviewed", self.home)
        with mock.patch.object(client, "transport") as network:
            with self.assertRaisesRegex(core.JevError, "request_limit"):
                self.live(data=self.changed())
            self.configure(max_requests=10)
            with self.assertRaisesRegex(core.JevError, "budget_limit"):
                self.live(data=self.changed())
            network.assert_not_called()
        self.assertEqual(self.state()["requests"], 1)
        self.assertEqual(self.state()["charged_nano_usd"], 200000 * 42)

    def test_invalid_or_missing_reference_never_opens_or_mutates_private_state(self):
        self.overrun()
        before = self.snapshot()
        with mock.patch.object(client, "Area", side_effect=AssertionError("private access")):
            for reference in (None, True, 1, "", " \t\n", "x" * 1001, "\ud800"):
                with self.subTest(reference=reference):
                    with self.assertRaisesRegex(core.JevError, "invalid_approval_reference"):
                        client.acknowledge_overrun(reference, self.home)
            for args, reason in (([], "invalid_arguments"),
                                 (["--approval", ""], "invalid_approval_reference"),
                                 (["--approval", "  "], "invalid_approval_reference")):
                code, output = self.invoke(["acknowledge-overrun", *args])
                self.assertEqual((code, output["reason"]), (2, reason))
        self.assertEqual(before, self.snapshot())

    def test_no_overrun_and_repeat_acknowledgement_are_explicit_noops(self):
        self.configure()
        before = self.snapshot()
        code, output = self.invoke(["acknowledge-overrun", "--approval", "reviewed"])
        self.assertEqual((code, output), (2, core.not_evaluated("no_overrun_to_acknowledge")))
        self.assertEqual(before, self.snapshot())
        self.overrun()
        client.acknowledge_overrun("first-reference", self.home)
        before = self.snapshot()
        with self.assertRaisesRegex(core.JevError, "no_overrun_to_acknowledge"):
            client.acknowledge_overrun("different-reference", self.home)
        self.assertEqual(before, self.snapshot())

    def test_acknowledgement_uses_same_lock_and_atomic_write(self):
        self.overrun()
        before = self.snapshot()
        with Area(self.home, "jev") as area:
            with area.locked():
                with self.assertRaisesRegex(core.JevError, "busy"):
                    client.acknowledge_overrun("reviewed", self.home)
        self.assertEqual(before, self.snapshot())
        with mock.patch("jevlib.private.os.replace", side_effect=OSError("synthetic failure")):
            with self.assertRaises(OSError):
                client.acknowledge_overrun("reviewed", self.home)
        self.assertEqual(before, self.snapshot())

    def test_existing_version_one_ledger_retains_consumption_and_cache(self):
        self.overrun()
        legacy = self.state()
        legacy.pop("overrun_acknowledgement")
        self.write_private(self.area / "state.json", legacy)
        before = self.snapshot()
        self.assertIsNone(client.status(self.home)["consumption"]["overrun_acknowledgement"])
        self.assertEqual(before, self.snapshot())
        client.acknowledge_overrun("legacy-review", self.home)
        after = self.state()
        self.assertEqual({k: v for k, v in after.items() if k in legacy},
                         dict(legacy, reservation_exceeded=False))

    def test_acknowledgement_metadata_is_validated(self):
        self.overrun()
        state = self.state()
        for acknowledgement in ({"approval_sha256": "not-a-hash", "at_request": 1},
                                {"approval_sha256": "a" * 64, "at_request": 2},
                                {"approval_sha256": "a" * 64, "at_request": True},
                                {"approval_sha256": "a" * 64, "at_request": 1, "text": "raw"}):
            self.write_private(self.area / "state.json",
                               dict(state, overrun_acknowledgement=acknowledgement))
            with self.assertRaisesRegex(core.JevError, "invalid_consumption_state"):
                client.status(self.home)
