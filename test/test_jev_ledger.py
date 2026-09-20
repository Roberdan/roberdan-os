import multiprocessing
from unittest import mock

from test_jev_support import Fixture, client, core, ledger, profiles, reply, sample


def concurrent_call(home, data, approval, env, entered, release, results):
    def waiting(payload, key):
        entered.set()
        if not release.wait(10):
            raise TimeoutError("synthetic wait")
        return reply(payload, key)
    with mock.patch.object(client, "transport", side_effect=waiting):
        result = client.evaluate("wanda", data, live=True, approved_sha256=approval,
                                 home=home, environ=env)
    results.put(result["status"])


class LedgerTests(Fixture):
    def test_reservation_is_independent_of_payload_byte_count(self):
        questions = profiles.prepare("wanda", sample("wanda"))["payload"]["questions"]
        self.assertEqual(ledger.reservation(questions), 65536 + 2048)
        self.assertGreater(ledger.reservation(questions), core.MAX_REQUEST_BYTES)

    def test_budget_and_count_caps_before_network(self):
        self.configure(budget_usd=0.0000001)
        with mock.patch.object(client, "transport", side_effect=reply) as network:
            with self.assertRaisesRegex(core.JevError, "budget_limit"):
                self.live()
            network.assert_not_called()
            self.configure(budget_usd=1, max_requests=1)
            self.live()
            changed = sample("wanda")
            changed["items"][0]["text"] += " Changed."
            with self.assertRaisesRegex(core.JevError, "request_limit"):
                self.live(data=changed)
            self.assertEqual(network.call_count, 1)

    def test_usage_settles_reservation_with_documented_price(self):
        self.configure()
        with mock.patch.object(client, "transport", side_effect=reply):
            output = self.live()
        state = self.state()
        self.assertEqual(state["requests"], 1)
        self.assertEqual(state["charged_nano_usd"], 100 * 42)
        self.assertEqual(state["input_tokens"], 100)
        self.assertEqual(state["output_tokens"], 20)
        self.assertEqual(state["uncertain_requests"], 0)
        self.assertFalse(output["consumption"]["billing_guarantee"])

    def test_outage_retains_reservation_without_retry(self):
        self.configure()
        with mock.patch.object(client, "transport", side_effect=core.JevError("transport_error")) as network:
            with self.assertRaisesRegex(core.JevError, "transport_error"):
                self.live()
        self.assertEqual(network.call_count, 1)
        state = self.state()
        self.assertEqual(state["requests"], 1)
        self.assertEqual(state["uncertain_requests"], 1)
        self.assertEqual(state["charged_nano_usd"], (65536 + 2048) * 42)

    def test_overrun_latches_visible_stop_even_after_config_change(self):
        self.configure()
        with mock.patch.object(client, "transport", side_effect=lambda p, k: reply(p, k, 200000)) as net:
            output = self.live()
            self.assertEqual(output["warning"], "reservation_exceeded_next_call_blocked")
            self.assertEqual(self.state()["charged_nano_usd"], 200000 * 42)
            self.configure(budget_usd=10, max_requests=100)
            with self.assertRaisesRegex(core.JevError, "reservation_exceeded"):
                self.live()
            self.assertEqual(net.call_count, 1)
        self.assertTrue(client.status(self.home)["consumption"]["reservation_exceeded"])

    def test_malformed_answers_cannot_hide_usage_overrun(self):
        self.configure()
        def malformed(payload, key):
            value = reply(payload, key, 200000)
            value["answers"] = {}
            return value
        with mock.patch.object(client, "transport", side_effect=malformed):
            with self.assertRaisesRegex(core.JevError, "malformed_response"):
                self.live()
        self.assertTrue(self.state()["reservation_exceeded"])
        self.assertEqual(self.state()["charged_nano_usd"], 200000 * 42)

    def test_malformed_usage_also_blocks_after_reported_overrun(self):
        self.configure()
        def malformed(payload, key):
            value = reply(payload, key, core.MAX_USAGE + 1)
            value["usage"]["output_tokens"] = -1
            return value
        with mock.patch.object(client, "transport", side_effect=malformed):
            with self.assertRaisesRegex(core.JevError, "malformed_response"):
                self.live()
        self.assertTrue(self.state()["reservation_exceeded"])
        self.assertEqual(self.state()["uncertain_requests"], 1)

    def test_cache_hit_is_explicit_and_does_not_load_key_or_spend(self):
        self.configure(max_requests=1)
        with mock.patch.object(client, "transport", side_effect=reply) as network:
            initial = self.live()
            with mock.patch.object(client, "credential", side_effect=AssertionError("read")):
                cached = self.live()
            self.assertEqual(network.call_count, 1)
        self.assertFalse(initial["from_cache"])
        self.assertTrue(cached["from_cache"])
        self.assertEqual(initial["result"], cached["result"])
        self.assertEqual(cached["consumption"]["requests"], 1)

    def test_input_policy_rubric_model_and_config_invalidate_cache(self):
        self.configure()
        with mock.patch.object(client, "transport", side_effect=reply) as network:
            self.live()
            changed = sample("wanda")
            changed["items"][0]["text"] += " Changed."
            self.assertFalse(self.live(data=changed)["from_cache"])
            self.live()
            with mock.patch.object(core, "POLICY_VERSION", "test-policy"):
                self.assertFalse(self.live()["from_cache"])
            self.live()
            with mock.patch.object(profiles, "RUBRIC_VERSION", "test-rubric"):
                self.assertFalse(self.live()["from_cache"])
            self.live()
            with mock.patch.object(core, "MODEL", "test-model"):
                self.assertFalse(self.live()["from_cache"])
            self.live()
            self.configure(approval="a different explicit approval")
            self.assertFalse(self.live()["from_cache"])
            self.assertEqual(network.call_count, 10)
            self.assertEqual(self.state()["requests"], 10)
        self.assertEqual(self.state()["input_tokens"], 1000)

    def test_config_changes_never_reset_request_or_spending_totals(self):
        self.configure(max_requests=1)
        with mock.patch.object(client, "transport", side_effect=reply) as network:
            self.live()
            self.configure(approval="new approval", budget_usd=10)
            with self.assertRaisesRegex(core.JevError, "request_limit"):
                self.live()
            self.assertEqual(network.call_count, 1)
        self.assertEqual(self.state()["requests"], 1)
        self.assertEqual(self.state()["charged_nano_usd"], 4200)

    def test_disabled_profile_cannot_use_existing_cache(self):
        self.configure()
        with mock.patch.object(client, "transport", side_effect=reply):
            self.live()
            self.configure(enabled_profiles=[])
            with self.assertRaisesRegex(core.JevError, "profile_disabled"):
                self.live()

    def test_missing_or_corrupt_ledger_never_resets_consumption(self):
        self.configure()
        with mock.patch.object(client, "transport", side_effect=reply):
            self.live()
        state_path = self.area / "state.json"
        state_path.unlink()
        with self.assertRaisesRegex(core.JevError, "missing_consumption_state"):
            self.live()
        with self.assertRaisesRegex(core.JevError, "missing_consumption_state"):
            client.status(self.home)
        self.write_private(state_path, "{invalid")
        with self.assertRaisesRegex(core.JevError, "invalid_consumption_state"):
            self.live()

    def test_invalid_cached_answer_never_reaches_consumer(self):
        self.configure()
        with mock.patch.object(client, "transport", side_effect=reply) as network:
            self.live()
            state = self.state()
            state["cache"]["answers"]["q0"]["choice"] = "arbitrary"
            self.write_private(self.area / "state.json", state)
            with self.assertRaisesRegex(core.JevError, "malformed_response"):
                self.live()
            self.assertEqual(network.call_count, 1)

    def test_atomic_write_failure_does_not_send_or_lose_existing_state(self):
        self.configure()
        with mock.patch.object(client, "transport", side_effect=reply):
            self.live()
        before = (self.area / "state.json").read_bytes()
        data = sample("wanda")
        data["items"][0]["text"] += " Changed."
        with mock.patch.object(client, "transport") as network:
            with mock.patch("jevlib.private.os.replace", side_effect=OSError("simulated disk error")):
                with self.assertRaises(OSError):
                    self.live(data=data)
            network.assert_not_called()
        self.assertEqual((self.area / "state.json").read_bytes(), before)
        self.assertEqual(list(self.area.glob(".jev-*.tmp")), [])

    def test_concurrent_requests_cannot_overspend(self):
        self.configure(max_requests=1)
        context = multiprocessing.get_context("spawn")
        entered, release, results = context.Event(), context.Event(), context.Queue()
        data = sample("wanda")
        process = context.Process(target=concurrent_call, args=(
            self.home, data, profiles.prepare("wanda", data)["sha256"], self.env,
            entered, release, results))
        process.start()
        try:
            self.assertTrue(entered.wait(10), "first request did not reach fake transport")
            self.assertEqual(self.state()["requests"], 1)
            with mock.patch.object(client, "transport") as network:
                with self.assertRaisesRegex(core.JevError, "busy"):
                    self.live()
                network.assert_not_called()
            release.set()
            process.join(10)
            self.assertEqual(process.exitcode, 0)
            self.assertEqual(results.get(timeout=2), "evaluated")
            self.assertEqual(self.state()["requests"], 1)
        finally:
            release.set()
            process.join(10)
            if process.is_alive():
                process.terminate()
                process.join()
            results.close()
            results.join_thread()

    def test_lock_and_state_permissions_rechecked(self):
        self.configure()
        with mock.patch.object(client, "transport", side_effect=reply):
            self.live()
        for name in ("lock", "state.json"):
            path = self.area / name
            path.chmod(0o644)
            with self.assertRaisesRegex(core.JevError, "unsafe_private_permissions"):
                self.live()
            path.chmod(0o600)
