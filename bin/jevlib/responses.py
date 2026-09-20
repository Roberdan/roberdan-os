"""Validate typed answers before any consumer or persistent cache sees them."""

import re

from . import core


def http_error_reason(status, raw):
    """Recognize explicit credit refusals, never echo or infer an account balance."""
    fallback = "provider_payment_required" if status == 402 else "upstream_error"
    if status not in (400, 402, 403, 429) or len(raw) > core.MAX_ERROR_BYTES:
        return fallback
    try:
        body = core.loads(raw)
    except core.JevError:
        try:
            body = raw.decode("utf-8")
        except UnicodeError:
            return fallback
    nodes = [body]
    if type(body) is dict:
        nodes.extend(body.get(key) for key in ("error", "detail"))
    codes = {"insufficient_credit", "insufficient_credits", "credit_exhausted",
             "credits_exhausted", "credit_balance_exhausted", "insufficient_balance"}
    for node in nodes:
        if type(node) is dict:
            for field in ("code", "type"):
                code = node.get(field)
                if type(code) is str and code.strip().lower() in codes:
                    return "provider_credit_exhausted"
            node = node.get("message")
        if type(node) is str and re.match(
            r"(?:insufficient (?:credits?|credit balance|balance)\b"
            r"|(?:your )?(?:credit balance|credits?)(?: is| are)? (?:exhausted|depleted)\b"
            r"|you (?:have )?run out of credits?\b)",
            node.strip(), flags=re.IGNORECASE | re.ASCII,
        ):
            return "provider_credit_exhausted"
    return fallback


def usage(value):
    core.exact(value, ("input_tokens", "output_tokens"), "malformed_response")
    return {key: core.integer(count, reason="malformed_response")
            for key, count in value.items()}


def answers(value, questions, cached=False):
    core.exact(value, questions, "malformed_response")
    clean = {}
    for ident, question in questions.items():
        answer = value[ident]
        kind = question["type"]
        if kind == "noul":
            core.exact(answer, ("noul",), "malformed_response")
            clean[ident] = {"noul": core.number(answer["noul"])}
            continue
        fields = [kind, "confidence", "probabilities"]
        if kind == "score" and not cached:
            fields.append("legend")
        core.exact(answer, fields, "malformed_response")
        criteria = question["criteria"]
        allowed = list(criteria) if kind == "choice" else [str(i) for i in range(len(criteria))]
        distribution = answer["probabilities"]
        core.exact(distribution, allowed, "malformed_response")
        probabilities = {key: core.number(distribution[key]) for key in allowed}
        core.require(abs(sum(probabilities.values()) - 1) <= 0.001, "malformed_response")
        confidence = core.number(answer["confidence"])
        if kind == "choice":
            selected = answer["choice"]
            core.require(type(selected) is str and selected in allowed, "malformed_response")
            core.require(abs(confidence - probabilities[selected]) <= 0.001,
                         "malformed_response")
            core.require(probabilities[selected] + 0.001 >= max(probabilities.values()),
                         "malformed_response")
        else:
            selected = core.number(answer["score"], maximum=len(criteria) - 1)
            if not cached:
                legend = {str(i): description for i, description in enumerate(criteria)}
                core.require(answer["legend"] == legend, "malformed_response")
        clean[ident] = {kind: selected, "confidence": confidence,
                        "probabilities": probabilities}
    return clean


def validate(response, questions):
    core.exact(response, ("model", "answers", "usage"), "malformed_response")
    core.require(response["model"] == core.MODEL, "model_mismatch")
    return answers(response["answers"], questions), usage(response["usage"])
