"""Synthetic provider refusals only; never read real account state or consume credit."""

import io
import json
import urllib.error
from unittest import mock

from test_jev_support import FAKE_KEY, Fixture, client, core, ledger, profiles, sample


class CreditTests(Fixture):
    def transport_failure(self, status, body):
        stream = io.BytesIO(body if isinstance(body, bytes) else core.canonical(body))
        error = urllib.error.HTTPError(core.ENDPOINT, status, "DO_NOT_ECHO", {}, stream)
        opener = mock.Mock()
        opener.open.side_effect = error
        with mock.patch("jevlib.client.urllib.request.build_opener", return_value=opener):
            with self.assertRaises(core.JevError) as caught:
                client.transport(profiles.prepare("wanda", sample("wanda"))["payload"], FAKE_KEY)
        self.assertTrue(stream.closed)
        opener.open.assert_called_once()
        self.assertNotIn("DO_NOT_ECHO", str(caught.exception))
        return str(caught.exception)

    def test_explicit_credit_errors_have_distinct_reason(self):
        bodies = [
            {"error": {"code": "insufficient_credits", "message": "DO_NOT_ECHO"}},
            {"code": "credits_exhausted"},
            {"detail": {"type": "insufficient_balance"}},
            {"message": "Insufficient credits. DO_NOT_ECHO"},
            {"detail": "Your credit balance is exhausted. Please add credits."},
            {"error": "You have run out of credits."},
            "Insufficient credits",
            b"Credits exhausted. DO_NOT_ECHO",
        ]
        for status in (400, 402, 403, 429):
            for body in bodies:
                with self.subTest(status=status, body=body):
                    self.assertEqual(self.transport_failure(status, body),
                                     "provider_credit_exhausted")

    def test_payment_required_without_credit_evidence_is_not_asserted_exhaustion(self):
        for body in (b"", b"{broken", {"detail": "Payment required"},
                     {"message": "DO_NOT_ECHO"}):
            with self.subTest(body=body):
                self.assertEqual(self.transport_failure(402, body), "provider_payment_required")

    def test_auth_rate_limits_and_echoed_input_are_not_credit_exhaustion(self):
        for status, body in (
            (401, {"error": {"code": "insufficient_credits"}}),
            (422, {"message": "Insufficient credits"}),
            (500, {"message": "Insufficient credits"}),
            (403, {"detail": "Forbidden DO_NOT_ECHO"}),
            (429, {"code": "rate_limit_exceeded", "message": "Too many requests"}),
            (429, {"code": "insufficient_quota"}),
            (400, {"input": "Insufficient credits"}),
            (400, {"message": "The input mentions insufficient credits."}),
            (403, b"\xff"),
            (403, b'{"code":"insufficient_credits","code":"other"}'),
            (403, {"detail": [{"msg": "Insufficient credits"}]}),
        ):
            with self.subTest(status=status, body=body):
                self.assertEqual(self.transport_failure(status, body), "upstream_error")

    def test_oversized_credit_body_is_bounded_and_not_classified(self):
        stream = mock.Mock(wraps=io.BytesIO(b"Insufficient credits. " + b"x" * 5000))
        error = urllib.error.HTTPError(core.ENDPOINT, 403, "DO_NOT_ECHO", {}, stream)
        opener = mock.Mock()
        opener.open.side_effect = error
        with mock.patch("jevlib.client.urllib.request.build_opener", return_value=opener):
            with self.assertRaisesRegex(core.JevError, "^upstream_error$"):
                client.transport({}, FAKE_KEY)
        stream.read.assert_called_once_with(4097)
        stream.close.assert_called_once()

    def test_error_body_read_failure_is_explicit_and_does_not_leak(self):
        stream = mock.Mock()
        stream.read.side_effect = OSError("DO_NOT_ECHO")
        error = urllib.error.HTTPError(core.ENDPOINT, 403, "DO_NOT_ECHO", {}, stream)
        opener = mock.Mock()
        opener.open.side_effect = error
        with mock.patch("jevlib.client.urllib.request.build_opener", return_value=opener):
            with self.assertRaisesRegex(core.JevError, "^upstream_error_body_unreadable$"):
                client.transport({}, FAKE_KEY)
        stream.close.assert_called_once()

    def test_cli_alert_is_clear_private_nonretrying_and_retains_reservation(self):
        self.configure()
        payload = profiles.prepare("wanda", sample("wanda"))
        path = self.input_file("wanda")
        body = {"error": {"code": "insufficient_credits",
                          "message": "DO_NOT_ECHO " + FAKE_KEY}}
        stream = io.BytesIO(core.canonical(body))
        error = urllib.error.HTTPError(core.ENDPOINT, 402, "DO_NOT_ECHO", {}, stream)
        opener = mock.Mock()
        opener.open.side_effect = error
        with mock.patch("jevlib.client.urllib.request.build_opener", return_value=opener):
            code, result = self.invoke(["evaluate", "wanda", "--input", str(path),
                                        "--live", "--approved-sha256", payload["sha256"]])
        self.assertEqual(code, 2)
        self.assertEqual(result["reason"], "provider_credit_exhausted")
        self.assertIn("Credito TypeSafe esaurito o insufficiente", result["message"])
        self.assertTrue(result["operator_action_required"])
        self.assertTrue(result["preserve_original_behavior"])
        self.assertNotIn("DO_NOT_ECHO", json.dumps(result))
        self.assertNotIn(FAKE_KEY, json.dumps(result))
        opener.open.assert_called_once()
        self.assertEqual(self.state()["requests"], 1)
        self.assertEqual(self.state()["uncertain_requests"], 1)
        self.assertEqual(self.state()["charged_nano_usd"],
                         ledger.reservation(payload["payload"]["questions"]) * 42)
        self.assertIsNone(self.state()["cache"])
        self.assertNotIn("DO_NOT_ECHO", (self.area / "state.json").read_text())

    def test_local_caps_have_distinct_alerts_without_claiming_provider_exhaustion(self):
        for reason in ("budget_limit", "request_limit"):
            with self.subTest(reason=reason):
                result = core.not_evaluated(reason)
                self.assertIn("locale", result["message"])
                self.assertIn("non indica", result["message"])
                self.assertTrue(result["operator_action_required"])
