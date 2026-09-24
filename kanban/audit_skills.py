"""Public selectors only; installed/private declarations never expand this policy.

Canonical entries are checked against telemetry_inventory.declaration by the audit
fixtures. Provider entries are the document selectors already used by telemetry's
public opportunity criteria. Namespaced aliases follow lib-skills-install.sh.
"""
from functools import lru_cache
import json
from pathlib import Path
import re

POLICY = "public_allowlist_v1"
NAME = re.compile(r"[a-z][a-z0-9-]{0,63}\Z")


@lru_cache(maxsize=1)
def public_skill_names():
    payload = Path(__file__).with_name("audit_skill_names.json").read_bytes()
    if len(payload) > 16384:
        raise ValueError("skill_policy_unavailable")
    data = json.loads(payload)
    if not isinstance(data, dict) or set(data) != {"canonical", "compatibility", "providers"}:
        raise ValueError("skill_policy_unavailable")
    for values in data.values():
        if (not isinstance(values, list) or len(values) > 64
                or any(not isinstance(name, str) or not NAME.fullmatch(name) for name in values)):
            raise ValueError("skill_policy_unavailable")
    return frozenset(data["canonical"] + ["rdos-" + name for name in data["canonical"]]
                     + data["compatibility"] + data["providers"])
