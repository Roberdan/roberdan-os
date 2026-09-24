"""Values and conflict rules PROPOSED from the ledger (plan 4.4). Never applied.

Written to the local ledger folder as a proposal. identity/ is not touched: turning a proposal
into canon is material in Roberto's name (human gate #6), so only he does it.
"""

import collections

MIN_N = 10       # attributed decisions before any proposal is worth reading
MIN_SUPPORT = 2  # decisions behind a value or a rule


def _attributed(records):
    return [r for r in records if r.get("roberto_choice") and r.get("attributed")]


def proposal(records, when):
    recs = _attributed(records)
    if len(recs) < MIN_N:
        return None, (f"dati insufficienti: {len(recs)} decisioni attribuite a Roberto, ne servono "
                      f"almeno {MIN_N}. Nessuna proposta scritta.")
    by_reason = collections.defaultdict(list)
    for r in recs:
        if r.get("reason"):
            by_reason[r["reason"].strip().lower()].append(r)
    values = sorted(((len(v), sum(x["roberto_choice"] == "approve" for x in v), k, v)
                     for k, v in by_reason.items() if len(v) >= MIN_SUPPORT), key=lambda t: (-t[0], -t[1], t[2]))
    out = [f"# Valori e regole di conflitto — PROPOSTA ({when})", "",
           "Ricavata dal registro locale delle decisioni. NON applicata: identity/ non e' stato toccato.",
           "Diventa canone solo se Roberto la approva e la scrive lui (gate #6).", "",
           f"Base: {len(recs)} decisioni attribuite a Roberto.", "", "## Valori, in ordine di sostegno", ""]
    if not values:
        out.append(f"(nessun motivo ricorre almeno {MIN_SUPPORT} volte: scrivi il motivo quando decidi)")
    for i, (n, appr, reason, v) in enumerate(values, 1):
        cats = ", ".join(sorted({x.get("category", "altro") for x in v}))
        out.append(f"{i}. {reason} — {n} decisioni ({appr} approvate), categorie: {cats}")
    out += ["", "## Conflitti — dove Roberto ha scelto diversamente dal twin", ""]
    overrides = collections.defaultdict(list)
    for r in recs:
        pred = (r.get("twin_prediction") or {}).get("choice")
        if pred and pred != r["roberto_choice"]:
            overrides[(r.get("category", "altro"), pred)].append(r)
    rules = sorted(overrides.items(), key=lambda kv: -len(kv[1]))
    shown = 0
    for (cat, pred), v in rules:
        if len(v) < MIN_SUPPORT:
            continue
        shown += 1
        top = collections.Counter(x["roberto_choice"] for x in v).most_common(1)[0][0]
        why = "; ".join(sorted({x["reason"] for x in v if x.get("reason")})) or "nessun motivo scritto"
        out.append(f"- Se tocca **{cat}**: il twin diceva {pred}, Roberto ha scelto {top} "
                   f"({len(v)} decisioni; motivi: {why}). Regola proposta: in {cat} non '{pred}' "
                   f"per default, proponi '{top}' e lascia decidere lui.")
    if not shown:
        out.append(f"(nessun disaccordo ricorre almeno {MIN_SUPPORT} volte nella stessa categoria)")
    out += ["", "## Per categoria", ""]
    for cat, v in sorted(collections.Counter(r.get("category", "altro") for r in recs).items()):
        appr = sum(1 for r in recs if r.get("category", "altro") == cat and r["roberto_choice"] == "approve")
        out.append(f"- {cat}: {v} decisioni, {appr} approvate")
    return "\n".join(out) + "\n", ""
