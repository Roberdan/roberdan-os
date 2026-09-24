"""Similar past decisions from the local ledger (plan 4.5). Lexical + category, no network.

Only decisions attributed to Roberto are precedents: a queue approval or an agent's start is
not evidence of how he decides.
"""

import re

STOP = {"che", "con", "del", "della", "dei", "delle", "per", "una", "uno", "the", "and", "for",
        "nel", "nella", "sul", "sulla", "gli", "le", "da", "di", "in", "un", "il", "lo", "la"}


def tokens(text):
    return {w for w in re.findall(r"[a-zà-ù0-9]+", (text or "").lower()) if len(w) > 2 and w not in STOP}


def similar(records, category, text, k=3, exclude_id=None):
    """Top-k attributed decisions sharing at least one meaningful word; same category ranks higher."""
    want = tokens(text)
    scored = []
    for rec in records:
        if not rec.get("roberto_choice") or not rec.get("attributed") or rec.get("id") == exclude_id:
            continue
        have = tokens(rec.get("situation"))
        shared = want & have
        if not shared:
            continue
        score = len(shared) / len(want | have) + (0.5 if rec.get("category") == category else 0)
        scored.append((-score, rec.get("decided_at") or "", rec))
    scored.sort(key=lambda t: (t[0], t[1]))
    return [rec for _s, _d, rec in scored[:k]]


def render(recs):
    lines = []
    for rec in recs:
        line = (f"- {rec.get('situation')} · categoria {rec.get('category')} · "
                f"scelta di Roberto: {rec.get('roberto_choice')}")
        if rec.get("reason"):
            line += f" · motivo: {rec['reason']}"
        lines.append(line)
    return "\n".join(lines) or "(nessun caso simile nel registro)"
