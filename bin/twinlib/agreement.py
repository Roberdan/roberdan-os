"""How often the twin (and Jev) predicted Roberto's actual choice. Plain Italian output."""

import datetime as _dt

from .ledger import CATEGORIES, now

MIN_N = 5


def _since(days):
    ref = _dt.datetime.strptime(now(), "%Y-%m-%dT%H:%M:%SZ")
    return (ref - _dt.timedelta(days=days)).strftime("%Y-%m-%dT%H:%M:%SZ")


def seen_first(rec):
    """Roberto saw the twin's pick (via `batch`) before deciding: anchored, not independent."""
    shown, decided = rec.get("shown_at"), rec.get("decided_at")
    return bool(shown) and bool(decided) and shown <= decided


def classify(records, days=None):
    """Split decided records into counted ones and the reasons the rest are left out."""
    since = _since(days) if days else ""
    counted, skipped = [], {"senza_previsione": 0, "non_attribuite": 0, "viste_prima": 0}
    for rec in records:
        if not rec.get("roberto_choice") or (rec.get("decided_at") or "") < since:
            continue
        if not rec.get("attributed"):
            skipped["non_attribuite"] += 1
        elif not rec.get("twin_prediction"):
            skipped["senza_previsione"] += 1
        elif seen_first(rec):
            skipped["viste_prima"] += 1
        else:
            counted.append(rec)
    return counted, skipped


def _rate(pairs):
    n = len(pairs)
    hit = sum(1 for p, r in pairs if p == r)
    return n, hit


def _line(label, n, hit):
    if n < MIN_N:
        return f"  {label:<14} N={n:<3} dati insufficienti (servono almeno {MIN_N} decisioni)"
    return f"  {label:<14} N={n:<3} accordo {round(100 * hit / n)}% ({hit} su {n})"


def stats(records, days=None):
    counted, skipped = classify(records, days)
    per_cat = {}
    for cat in CATEGORIES:
        pairs = [(r["twin_prediction"]["choice"], r["roberto_choice"])
                 for r in counted if r.get("category") == cat]
        if pairs:
            per_cat[cat] = _rate(pairs)
    overall = _rate([(r["twin_prediction"]["choice"], r["roberto_choice"]) for r in counted])
    # Jev is never scored here: its twin profile gives separate signals, not a prediction of
    # Roberto (ADR-0003), so the ledger keeps a `jev_observation`, not a choice.
    return {"per_cat": per_cat, "overall": overall, "skipped": skipped}


def category_rate(records, cat):
    """Historical (all-time) twin agreement for one category, as a short label."""
    st = stats(records)
    n, hit = st["per_cat"].get(cat, (0, 0))
    if n < MIN_N:
        return f"storico {cat}: dati insufficienti (N={n})"
    return f"storico {cat}: {round(100 * hit / n)}% su {n}"


def render(records, days=7):
    head = f"ultimi {days} giorni" if days else "da sempre"
    st = stats(records, days)
    out = [f"Twin — accordo con Roberto ({head})"]
    n, hit = st["overall"]
    if n == 0:
        out.append("  nessuna decisione confrontabile: dati insufficienti")
    if n < MIN_N:
        out.append("  passo successivo: accendi le previsioni automatiche con "
                   "touch ~/.roberdan-os/private/decisions/auto-predict (max 5 card per giro, "
                   "tetto $0.05 a card), oppure lancia bin/twin-shadow.sh predict")
    else:
        for cat, (cn, chit) in st["per_cat"].items():
            out.append(_line(cat, cn, chit))
        out.append(_line("totale", n, hit))
    sk = st["skipped"]
    if any(sk.values()):
        out.append(
            "  non contate: "
            f"{sk['senza_previsione']} senza previsione del twin, "
            f"{sk['non_attribuite']} non attribuibili a Roberto (coda, agente, o card sparita), "
            f"{sk['viste_prima']} decise dopo aver visto il consiglio del twin"
        )
    return "\n".join(out)
