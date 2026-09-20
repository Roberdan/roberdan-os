"""One lifetime ledger; config changes never reset consumption.

Reservation is a conservative application policy, not a tokenizer or a provider
billing guarantee: 65,536 input tokens plus 2,048 per question. Validated actual
usage replaces the reservation; ambiguous outcomes retain it. Any overrun latches
a network stop until explicitly acknowledged locally, without resetting usage.
Prices are the documented 2026-09-20 values, not live account pricing.
"""

from decimal import Decimal
import os

from . import core, responses

CONFIG_KEYS = ("enabled_profiles", "max_requests", "budget_usd", "approval")
STATE_KEYS = ("version", "requests", "charged_nano_usd", "input_tokens", "output_tokens",
              "uncertain_requests", "reservation_exceeded", "cache", "overrun_acknowledgement")
TOTAL_MAX = 10**18


def config(area):
    try:
        value = core.loads(area.read("config.json", 8192), "invalid_config")
    except FileNotFoundError:
        raise core.JevError("missing_config") from None
    core.exact(value, CONFIG_KEYS, "invalid_config")
    enabled = value["enabled_profiles"]
    core.require(type(enabled) is list and len(enabled) <= len(core.PROFILES),
                 "invalid_config")
    core.require(all(type(p) is str and p in core.PROFILES for p in enabled),
                 "invalid_config")
    core.require(len(set(enabled)) == len(enabled), "invalid_config")
    core.integer(value["max_requests"], 1, reason="invalid_config")
    budget = core.number(value["budget_usd"], maximum=1000000, reason="invalid_config")
    core.require(budget > 0, "invalid_config")
    core.require(type(value["approval"]) is str
                 and 0 < len(value["approval"]) <= core.MAX_APPROVAL_CHARS
                 and bool(value["approval"].strip()), "invalid_config")
    try:
        value["approval"].encode("utf-8")
    except UnicodeError:
        raise core.JevError("invalid_config") from None
    core.require(budget_nano(value) > 0, "invalid_config")
    return value


def budget_nano(settings):
    return int(Decimal(str(settings["budget_usd"])) * Decimal(10**9))


def empty():
    return {"version": 1, "requests": 0, "charged_nano_usd": 0, "input_tokens": 0,
            "output_tokens": 0, "uncertain_requests": 0, "reservation_exceeded": False,
            "cache": None, "overrun_acknowledgement": None}


def read(area, lock=None):
    try:
        raw = area.read("state.json")
    except FileNotFoundError:
        # A durable sentinel prevents a deleted ledger from silently resetting caps.
        if lock is None:
            try:
                marker = area.read("lock", 32)
            except FileNotFoundError:
                marker = b""
            core.require(not marker, "missing_consumption_state")
            return empty()
        core.require(os.fstat(lock).st_size == 0, "missing_consumption_state")
        os.write(lock, b"initialized\n")
        os.fsync(lock)
        value = empty()
        area.write("state.json", value)
        return value
    value = core.loads(raw, "invalid_consumption_state")
    # Existing version-1 ledgers predate local overrun acknowledgements.
    if type(value) is dict and "overrun_acknowledgement" not in value:
        value["overrun_acknowledgement"] = None
    core.exact(value, STATE_KEYS, "invalid_consumption_state")
    core.require(type(value["version"]) is int and value["version"] == 1,
                 "invalid_consumption_state")
    for field in ("requests", "charged_nano_usd", "input_tokens",
                  "output_tokens", "uncertain_requests"):
        core.integer(value[field], maximum=TOTAL_MAX, reason="invalid_consumption_state")
    core.require(value["uncertain_requests"] <= value["requests"], "invalid_consumption_state")
    core.require(type(value["reservation_exceeded"]) is bool, "invalid_consumption_state")
    acknowledgement = value["overrun_acknowledgement"]
    if acknowledgement is not None:
        core.exact(acknowledgement, ("approval_sha256", "at_request"), "invalid_consumption_state")
        approval_hash = acknowledgement["approval_sha256"]
        core.require(type(approval_hash) is str and core.HASH.fullmatch(approval_hash),
                     "invalid_consumption_state")
        core.integer(acknowledgement["at_request"], maximum=value["requests"],
                     reason="invalid_consumption_state")
    cache = value["cache"]
    if cache is not None:
        core.exact(cache, ("key", "answers", "usage"), "invalid_consumption_state")
        core.require(type(cache["key"]) is str and core.HASH.fullmatch(cache["key"]),
                     "invalid_consumption_state")
        core.require(type(cache["answers"]) is dict and len(cache["answers"]) <= 32,
                     "invalid_consumption_state")
        responses.usage(cache["usage"])
    return value


def reservation(questions):
    return 65536 + 2048 * len(questions)


def reserve(area, state, settings, tokens):
    core.require(not state["reservation_exceeded"], "reservation_exceeded")
    core.require(state["requests"] < settings["max_requests"], "request_limit")
    cost = tokens * core.PRICE_NANO_PER_INPUT_TOKEN
    core.require(state["charged_nano_usd"] + cost <= budget_nano(settings), "budget_limit")
    state["requests"] += 1
    state["uncertain_requests"] += 1
    state["charged_nano_usd"] += cost
    area.write("state.json", state)


def settle(area, state, tokens, usage, cache):
    actual = usage["input_tokens"]
    state["charged_nano_usd"] += (actual - tokens) * core.PRICE_NANO_PER_INPUT_TOKEN
    state["input_tokens"] += actual
    state["output_tokens"] += usage["output_tokens"]
    state["uncertain_requests"] -= 1
    state["reservation_exceeded"] = actual > tokens
    state["cache"] = cache
    area.write("state.json", state)


def rejected(area, state, tokens, usage):
    """Known usage can increase an ambiguous reservation, never refund it."""
    state["charged_nano_usd"] += max(0, usage["input_tokens"] - tokens) * core.PRICE_NANO_PER_INPUT_TOKEN
    state["input_tokens"] += usage["input_tokens"]
    state["output_tokens"] += usage["output_tokens"]
    state["reservation_exceeded"] = usage["input_tokens"] > tokens
    area.write("state.json", state)


def acknowledge_overrun(area, state, approval_hash):
    core.require(state["reservation_exceeded"], "no_overrun_to_acknowledge")
    state["reservation_exceeded"] = False
    state["overrun_acknowledgement"] = {
        "approval_sha256": approval_hash, "at_request": state["requests"]}
    area.write("state.json", state)


def metadata(state, settings):
    return {"requests": state["requests"], "max_requests": settings["max_requests"],
            "charged_usd": state["charged_nano_usd"] / 10**9,
            "budget_usd": settings["budget_usd"],
            "input_tokens": state["input_tokens"], "output_tokens": state["output_tokens"],
            "uncertain_requests": state["uncertain_requests"],
            "reservation_exceeded": state["reservation_exceeded"],
            "overrun_acknowledgement": state["overrun_acknowledgement"],
            "billing_guarantee": False}
