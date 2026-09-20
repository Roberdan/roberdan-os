import copy
import io
import json
from email.message import Message
import urllib.error
import urllib.request
import urllib.response
from unittest import mock

from test_jev_support import FAKE_KEY, Fixture, client, core, profiles, reply, sample
from jevlib import responses


class ResponseTests(Fixture):
    def test_malformed_answer_shapes_and_numbers(self):
        payload = profiles.prepare("retrieval", sample("retrieval"))["payload"]
        valid = reply(payload)
        mutations = [
            lambda r: r.update(model="untrusted-model"),
            lambda r: r.update(extra="untrusted"),
            lambda r: r["answers"].pop("q0"),
            lambda r: r["answers"].update(unexpected=r["answers"]["q0"]),
            lambda r: r["answers"]["q0"].update(extra="arbitrary text"),
            lambda r: r["answers"]["q0"].update(score=-1),
            lambda r: r["answers"]["q0"].update(score=4),
            lambda r: r["answers"]["q0"].update(score=True),
            lambda r: r["answers"]["q0"].update(score=float("nan")),
            lambda r: r["answers"]["q0"].update(confidence=float("inf")),
            lambda r: r["answers"]["q0"].update(confidence=-0.1),
            lambda r: r["answers"]["q0"].update(confidence="0.5"),
            lambda r: r["answers"]["q0"].update(probabilities={"0": 1}),
            lambda r: r["answers"]["q0"]["probabilities"].update({"3": float("nan")}),
            lambda r: r["answers"]["q0"]["probabilities"].update({"3": -0.1}),
            lambda r: r["answers"]["q0"]["probabilities"].update({"3": 1}),
            lambda r: r["answers"]["q0"]["legend"].update({"0": "arbitrary echoed text"}),
            lambda r: r["usage"].update(input_tokens=-1),
            lambda r: r["usage"].update(input_tokens=True),
            lambda r: r["usage"].update(input_tokens=1.5),
            lambda r: r["usage"].update(input_tokens=1000001),
            lambda r: r["usage"].update(output_tokens=float("nan")),
            lambda r: r["usage"].update(extra=1),
        ]
        for mutate in mutations:
            value = copy.deepcopy(valid)
            mutate(value)
            with self.subTest(value=value), self.assertRaises(core.JevError):
                responses.validate(value, payload["questions"])

    def test_choice_values_distribution_and_confidence(self):
        payload = profiles.prepare("wanda", sample("wanda"))["payload"]
        for change in ({"choice": "delete"}, {"choice": []}, {"confidence": 0.5},
                       {"probabilities": {"decision_needed": 1}},
                       {"probabilities": {"progress": 0.8, "blocked": 0,
                                          "decision_needed": 0.2, "unknown": 0},
                        "confidence": 0.2}):
            value = reply(payload)
            value["answers"]["q0"].update(change)
            with self.assertRaises(core.JevError):
                responses.validate(value, payload["questions"])

    def test_noul_is_bounded_and_cannot_generate_text(self):
        payload = profiles.prepare("thor", sample("thor"))["payload"]
        for answer in ({"noul": -1}, {"noul": 1.1}, {"noul": True}, {"noul": float("nan")},
                       {"noul": 1, "explanation": "invented"}, {"noul": "yes"}):
            value = reply(payload)
            value["answers"]["q0"] = answer
            with self.assertRaises(core.JevError):
                responses.validate(value, payload["questions"])

    def test_malformed_response_retains_reservation_and_is_not_cached(self):
        self.configure()
        def malformed(payload, key):
            value = reply(payload, key)
            value["answers"].pop("q0")
            return value
        with mock.patch.object(client, "transport", side_effect=malformed) as network:
            with self.assertRaisesRegex(core.JevError, "malformed_response"):
                self.live()
        self.assertEqual(network.call_count, 1)
        self.assertEqual(self.state()["requests"], 1)
        self.assertEqual(self.state()["uncertain_requests"], 1)
        self.assertIsNone(self.state()["cache"])
        self.assertGreater(self.state()["charged_nano_usd"], 100 * 42)

    def test_transport_fixed_endpoint_bearer_no_proxy_and_size_bound(self):
        payload = profiles.prepare("wanda", sample("wanda"))["payload"]
        response = mock.MagicMock()
        response.status = 200
        response.read.return_value = core.canonical(reply(payload))
        response.__enter__.return_value = response
        opener = mock.Mock()
        opener.open.return_value = response
        with mock.patch("jevlib.client.urllib.request.build_opener", return_value=opener) as build:
            value = client.transport(payload, FAKE_KEY)
        request = opener.open.call_args.args[0]
        self.assertEqual(request.full_url, "https://api.typesafe.ai/v1/systemone")
        self.assertEqual(request.get_header("Authorization"), "Bearer " + FAKE_KEY)
        self.assertEqual(request.get_method(), "POST")
        self.assertEqual(json.loads(request.data), payload)
        self.assertEqual(build.call_args.args[0].proxies, {})
        self.assertIsInstance(build.call_args.args[1], client.NoRedirect)
        self.assertEqual(value, reply(payload))
        self.assertEqual(response.read.call_args.args, (core.MAX_RESPONSE_BYTES + 1,))
        opener.open.assert_called_once()

    def test_every_redirect_is_refused_without_followup_request(self):
        handler = client.NoRedirect()
        for code in (301, 302, 303, 307, 308):
            body = io.BytesIO(b"upstream secret body")
            with self.subTest(code=code), self.assertRaisesRegex(core.JevError, "redirect_refused"):
                getattr(handler, f"http_error_{code}")(
                    mock.Mock(), body, code, "redirect", {"Location": "https://other.invalid"})
            self.assertTrue(body.closed)
        with self.assertRaisesRegex(core.JevError, "redirect_refused"):
            handler.redirect_request(mock.Mock(), None, 302, "", {}, "https://other.invalid")

    def test_redirect_through_real_opener_never_forwards_credentials(self):
        seen = []
        class SyntheticHTTPS(urllib.request.HTTPSHandler):
            def https_open(self, request):
                seen.append(request)
                if len(seen) > 1:
                    raise AssertionError("a redirect forwarded the request")
                headers = Message()
                headers["Location"] = "https://other.invalid/"
                response = urllib.response.addinfourl(
                    io.BytesIO(b"not inspected"), headers, request.full_url, 302)
                response.msg = "Found"
                return response
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}),
                                            SyntheticHTTPS(), client.NoRedirect())
        payload = profiles.prepare("wanda", sample("wanda"))["payload"]
        with mock.patch("jevlib.client.urllib.request.build_opener", return_value=opener):
            with self.assertRaisesRegex(core.JevError, "redirect_refused"):
                client.transport(payload, FAKE_KEY)
        self.assertEqual(len(seen), 1)
        self.assertEqual(seen[0].full_url, core.ENDPOINT)

    def test_transport_errors_and_bodies_are_not_exposed_or_retried(self):
        payload = profiles.prepare("wanda", sample("wanda"))["payload"]
        errors = [urllib.error.URLError("secret body"), TimeoutError("secret body"),
                  urllib.error.HTTPError(core.ENDPOINT, 403, "secret body", {},
                                         io.BytesIO(b"secret body"))]
        for error in errors:
            opener = mock.Mock()
            opener.open.side_effect = error
            with mock.patch("jevlib.client.urllib.request.build_opener", return_value=opener):
                with self.assertRaises(core.JevError) as raised:
                    client.transport(payload, FAKE_KEY)
            self.assertNotIn("secret", str(raised.exception))
            opener.open.assert_called_once()

    def test_transport_rejects_invalid_json_nan_and_oversized_body(self):
        payload = profiles.prepare("wanda", sample("wanda"))["payload"]
        for raw in (b"{broken", b'{"usage":NaN}', b"x" * (core.MAX_RESPONSE_BYTES + 1)):
            response = mock.MagicMock()
            response.status = 200
            response.__enter__.return_value = response
            response.read.return_value = raw
            opener = mock.Mock()
            opener.open.return_value = response
            with mock.patch("jevlib.client.urllib.request.build_opener", return_value=opener):
                with self.assertRaises(core.JevError):
                    client.transport(payload, FAKE_KEY)
