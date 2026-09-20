"""Fixed HTTPS transport and explicit live path. Never retries or logs payloads."""

import http.client
import os
from pathlib import Path
import urllib.error
import urllib.request

from . import core, ledger, profiles, responses
from .private import Area, credential


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise core.JevError("redirect_refused")

    def http_error_302(self, req, fp, code, msg, headers):
        fp.close()
        raise core.JevError("redirect_refused")

    http_error_301 = http_error_303 = http_error_307 = http_error_308 = http_error_302


def transport(payload, key):
    request = urllib.request.Request(
        core.ENDPOINT, data=core.canonical(payload), method="POST",
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json",
                 "Accept": "application/json"},
    )
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    try:
        with opener.open(request, timeout=30) as response:
            core.require(response.status == 200, "upstream_error")
            raw = response.read(core.MAX_RESPONSE_BYTES + 1)
    except urllib.error.HTTPError as error:
        try:
            raw = error.read(core.MAX_ERROR_BYTES + 1)
        except (OSError, http.client.HTTPException):
            raise core.JevError("upstream_error_body_unreadable") from None
        finally:
            error.close()
        raise core.JevError(responses.http_error_reason(error.code, raw)) from None
    except (urllib.error.URLError, OSError, http.client.HTTPException):
        raise core.JevError("transport_error") from None
    core.require(len(raw) <= core.MAX_RESPONSE_BYTES, "response_too_large")
    return core.loads(raw, "malformed_response")


def cache_key(prepared, settings):
    return core.digest({"request": prepared["sha256"], "input": prepared["input"],
                        "profile": prepared["profile"], "config": settings,
                        "rubric": profiles.RUBRIC_VERSION, "policy": core.POLICY_VERSION})


def evaluate(profile, data, *, live=False, approved_sha256=None, home=None, environ=None):
    prepared = profiles.prepare(profile, data)
    if not live:
        core.require(approved_sha256 is None, "approval_requires_live")
        return {"status": "dry_run", "profile": profile, "sha256": prepared["sha256"],
                "payload": prepared["payload"], "payload_bytes": len(core.canonical(prepared["payload"])),
                "notice": profiles.NOTICE, "rubric_version": profiles.RUBRIC_VERSION,
                "preserve_original_behavior": True}
    core.require(type(approved_sha256) is str and core.HASH.fullmatch(approved_sha256)
                 and approved_sha256 == prepared["sha256"], "payload_not_approved")
    home = Path.home() if home is None else Path(home)
    environ = os.environ if environ is None else environ
    try:
        with Area(home, "jev") as area:
            # Read settings again under the same lock as the lifetime ledger.
            settings = ledger.config(area)
            core.require(profile in settings["enabled_profiles"], "profile_disabled")
            with area.locked() as lock:
                settings = ledger.config(area)
                core.require(profile in settings["enabled_profiles"], "profile_disabled")
                key = cache_key(prepared, settings)
                state = ledger.read(area, lock)
                hit = state["cache"] is not None and state["cache"]["key"] == key
                if hit:
                    answers = responses.answers(state["cache"]["answers"],
                                                prepared["payload"]["questions"], cached=True)
                    usage = responses.usage(state["cache"]["usage"])
                else:
                    core.require(not state["reservation_exceeded"], "reservation_exceeded")
                    questions = prepared["payload"]["questions"]
                    core.require(bool(questions), "no_eligible_questions")
                    secret = credential(home, environ)
                    tokens = ledger.reservation(questions)
                    ledger.reserve(area, state, settings, tokens)
                    response = transport(prepared["payload"], secret)
                    core.require(type(response) is dict, "malformed_response")
                    reported = response.get("usage")
                    if type(reported) is dict and type(reported.get("input_tokens")) is int:
                        if reported["input_tokens"] > tokens:
                            # Even an otherwise malformed response must not hide an overrun.
                            state["reservation_exceeded"] = True
                            area.write("state.json", state)
                    usage = responses.usage(response.get("usage"))
                    try:
                        answers, usage = responses.validate(response, questions)
                    except core.JevError:
                        ledger.rejected(area, state, tokens, usage)
                        raise
                    ledger.settle(area, state, tokens, usage,
                                  {"key": key, "answers": answers, "usage": usage})
                result = {"status": "evaluated", "profile": profile, "sha256": prepared["sha256"],
                          "from_cache": hit, "model": core.MODEL, "usage": usage,
                          "consumption": ledger.metadata(state, settings),
                          "result": profiles.consume(prepared, answers)}
                if state["reservation_exceeded"]:
                    result["warning"] = "reservation_exceeded_next_network_call_blocked"
                return result
    except FileNotFoundError:
        raise core.JevError("missing_config") from None


def acknowledge_overrun(approval, home=None):
    core.require(type(approval) is str and 0 < len(approval) <= core.MAX_APPROVAL_CHARS
                 and bool(approval.strip()), "invalid_approval_reference")
    try:
        approval_hash = core.digest(approval.strip())
    except UnicodeError:
        raise core.JevError("invalid_approval_reference") from None
    try:
        with Area(Path.home() if home is None else home, "jev") as area:
            settings = ledger.config(area)
            state = ledger.read(area)
            core.require(state["reservation_exceeded"], "no_overrun_to_acknowledge")
            with area.locked():
                settings = ledger.config(area)
                state = ledger.read(area)
                ledger.acknowledge_overrun(area, state, approval_hash)
                return {"status": "overrun_acknowledged",
                        "consumption": ledger.metadata(state, settings)}
    except FileNotFoundError:
        raise core.JevError("missing_config") from None


def status(home=None):
    try:
        with Area(Path.home() if home is None else home, "jev") as area:
            settings = ledger.config(area)
            state = ledger.read(area)
            return {"status": "configured", "profiles": list(core.PROFILES),
                    "enabled_profiles": settings["enabled_profiles"],
                    "consumption": ledger.metadata(state, settings)}
    except FileNotFoundError:
        raise core.JevError("missing_config") from None
