"""Shared bounds and strict JSON primitives. Error codes never contain input."""

import hashlib
import json
import math
import re

MODEL = "jev-1.13.0"
ENDPOINT = "https://api.typesafe.ai/v1/systemone"
POLICY_VERSION = "jev-policy-1"
MAX_INPUT_BYTES = 48000
MAX_REQUEST_BYTES = 12000
MAX_RESPONSE_BYTES = 262144
MAX_ERROR_BYTES = 4096
MAX_ITEMS = 8
MAX_TEXT_CHARS = 1200
MAX_CONTEXT_CHARS = 2400
MAX_ID_CHARS = 24
MAX_APPROVAL_CHARS = 1000
MAX_USAGE = 1000000
PRICE_NANO_PER_INPUT_TOKEN = 42  # $0.042/M; output free, documented 2026-09-20.
PROFILES = ("twin", "retrieval", "wanda", "thor")
ID = re.compile(rf"[a-z][a-z0-9_-]{{0,{MAX_ID_CHARS - 1}}}\Z", re.ASCII)
HASH = re.compile(r"[0-9a-f]{64}\Z", re.ASCII)
SECRET = re.compile(
    r"(?i)(?:\b(?:sk|ghp|github_pat|xox[baprs])[-_][a-z0-9_-]{8,}"
    r"|\bAKIA[A-Z0-9]{16}\b|-----BEGIN [A-Z ]*PRIVATE KEY-----"
    r"|\bBearer\s+[a-z0-9._~+/=-]{8,}"
    r"|\b(?:api[_ -]?key|password|passwd|secret|access[_ -]?token|"
    r"authorization|credential)\s*[=:]\s*\S+)"
)


class JevError(Exception):
    """A fixed public reason code, never an upstream exception message."""


def require(condition, reason):
    if not condition:
        raise JevError(reason)


def exact(value, keys, reason="invalid_input"):
    require(type(value) is dict and set(value) == set(keys), reason)


def integer(value, minimum=0, maximum=MAX_USAGE, reason="invalid_input"):
    require(type(value) is int and minimum <= value <= maximum, reason)
    return value


def number(value, minimum=0, maximum=1, reason="malformed_response"):
    require(type(value) in (float, int), reason)
    require(minimum <= value <= maximum and math.isfinite(value), reason)
    return value


def text(value, limit=MAX_TEXT_CHARS):
    require(type(value) is str and 0 < len(value) <= limit, "invalid_input")
    require(bool(value.strip()) and not SECRET.search(value), "unsafe_input")
    require(not any(ord(c) < 32 and c not in "\n\t" for c in value), "unsafe_input")
    try:
        value.encode("utf-8")
    except UnicodeError:
        raise JevError("invalid_input") from None
    return value


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=False, allow_nan=False).encode("utf-8")


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def loads(raw, reason="invalid_json"):
    def pairs(entries):
        result = {}
        for key, value in entries:
            require(key not in result, reason)
            result[key] = value
        return result

    def constant(_):
        raise JevError(reason)

    try:
        return json.loads(raw, object_pairs_hook=pairs, parse_constant=constant)
    except (ValueError, UnicodeError, RecursionError):
        raise JevError(reason) from None


def not_evaluated(reason):
    result = {"status": "not_evaluated", "reason": reason,
              "preserve_original_behavior": True}
    messages = {
        "provider_credit_exhausted": (
            "Credito TypeSafe esaurito o insufficiente. Valutazione non disponibile: "
            "verifica il saldo o ricarica l'account. Nessun nuovo tentativo automatico."),
        "provider_payment_required": (
            "TypeSafe richiede un pagamento (HTTP 402). Verifica credito e fatturazione: "
            "la risposta non conferma che il saldo sia esaurito."),
        "budget_limit": (
            "Raggiunto il limite di spesa locale autorizzato per Jev. "
            "Questo non indica che il credito TypeSafe sia esaurito."),
        "request_limit": (
            "Raggiunto il limite locale di chiamate autorizzate per Jev. "
            "Questo non indica che il credito TypeSafe sia esaurito."),
    }
    if reason in messages:
        result.update(message=messages[reason], operator_action_required=True)
    return result
