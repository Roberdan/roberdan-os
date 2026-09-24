#!/usr/bin/env python3
"""Twin shadow mode: predict Roberto's kb-pending decisions, then measure agreement.

    twin_shadow.py predict [--max N] [--if-enabled]   hidden prediction per todo card
    twin_shadow.py outcome --board B --card C --choice X --by BY --interactive yes|no
    twin_shadow.py reconcile              catch approvals/vanished cards the hook missed
    twin_shadow.py decide --card C --choice X [--reason R] [--category K] [--source S]
    twin_shadow.py batch                  pending list sorted by the twin's advice (approves nothing)
    twin_shadow.py agreement [--days N | --all]

Ledger: local only (twinlib/ledger.py). The twin never approves: kb start --by roberto does.
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from twinlib import agreement, board, host, ledger  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _open_record(records, bd, card, text):
    rid = ledger.record_id(bd, card)
    rec = ledger.find(records, rid)
    if rec is None:
        cat = board.field(text, "category") or "altro"
        rec = ledger.new_record(bd, card, board.field(text, "title") or card, cat)
        records.append(rec)
    return rec


def cmd_predict(args):
    if args.if_enabled and not os.path.exists(os.path.join(ledger.ledger_dir(), "auto-predict")):
        return 0  # the scheduled digest predicts only after Roberto opted in: predictions spend
    todo = [(bd, c) for bd in board.boards(ROOT) for c in board.todo_cards(bd)]
    asked = done = missing = 0
    reason = ""
    for bd, card in todo:
        _col, text = board.read_card(bd, card)
        with ledger.locked() as records:
            rec = _open_record(records, bd, card, text)
            if rec["twin_prediction"] or rec["roberto_choice"]:
                continue
        if asked >= args.max:
            missing += 1
            continue
        asked += 1
        prompt = host.build_prompt(ROOT, board.field(text, "repo"), board.summary(text, card))
        pred, why = host.ask(ROOT, prompt)
        with ledger.locked() as records:
            rec = ledger.find(records, ledger.record_id(bd, card))
            if rec is None or rec["roberto_choice"]:
                continue  # decided while we were asking: a late prediction is not a prediction
            if pred is None:
                rec["prediction_note"] = why
                missing += 1
                reason = why
                continue
            pred["at"] = ledger.now()
            rec["twin_prediction"] = pred
            rec.pop("prediction_note", None)
            if not board.field(text, "category"):
                rec["category"] = pred["category"]
            done += 1
    # Shadow mode: the count only, never the prediction itself.
    msg = f"twin-shadow: {done} previsioni registrate, {missing} senza previsione"
    print(msg + (f" ({reason})" if reason else "") + f", {len(todo)} card in attesa")
    return 0


def cmd_outcome(args):
    # Update-only and silent: called from `kb start`, it must never create a ledger for a
    # card it did not shadow (tests with temp boards, other people's boards).
    rid = ledger.record_id(args.board, args.card)
    if not any(r.get("id") == rid and not r.get("roberto_choice") for r in ledger.load()):
        return 0
    with ledger.locked() as records:
        rec = ledger.find(records, rid)
        if rec and not rec["roberto_choice"]:
            ledger.decide(rec, args.choice, args.by, args.interactive, "kb-pending")
    return 0


def cmd_reconcile(_args):
    known = set(board.boards(ROOT))
    changed = 0
    with ledger.locked() as records:
        for rec in records:
            if rec.get("roberto_choice") or rec.get("board") not in known:
                continue
            col, text = board.read_card(rec["board"], rec["card"])
            if col in ("doing", "done"):
                by, inter = board.last_start_audit(text)
                ledger.decide(rec, "approve", board.field(text, "approved_by") or by, inter)
                changed += 1
            elif col is None:
                ledger.decide(rec, "reject", "card sparita", "no")
                changed += 1
    print(f"twin-shadow: {changed} decisioni riconciliate")
    return 0


def cmd_decide(args):
    interactive = "yes" if sys.stdin.isatty() else "no"
    with ledger.locked() as records:
        rec = next((r for r in records if r.get("card") == args.card
                    and not r.get("roberto_choice")), None)
        if rec is None:
            bd = args.board or (board.boards(ROOT) or [os.getcwd()])[0]
            rec = ledger.new_record(bd, args.card, args.situation or args.card)
            records.append(rec)
        if args.category:
            rec["category"] = args.category
        ledger.decide(rec, args.choice, "roberto", interactive, args.source, args.reason)
    print(f"twin-shadow: registrata la scelta '{args.choice}' su {args.card}")
    return 0


RANK = {"approve": 0, "defer": 1, "reject": 2}


def cmd_batch(_args):
    rows = []
    with ledger.locked() as records:
        for bd in board.boards(ROOT):
            for card in board.todo_cards(bd):
                _col, text = board.read_card(bd, card)
                rec = ledger.find(records, ledger.record_id(bd, card))
                pred = rec.get("twin_prediction") if rec else None
                if rec and pred and not rec.get("shown_at"):
                    rec["shown_at"] = ledger.now()  # from now on this decision is anchored
                cat = (rec or {}).get("category") or board.field(text, "category") or "altro"
                rows.append((RANK.get(pred["choice"], 3) if pred else 3,
                             -(pred["confidence"] if pred else 0), card,
                             board.field(text, "repo") or "?", board.field(text, "title") or card,
                             pred, cat))
        history = list(records)
    rows.sort()
    print("## In attesa, ordinate dal consiglio del twin — NON approva nulla")
    if not rows:
        print("  (nessuna card in attesa)")
    for _r, _c, card, repo, title, pred, cat in rows:
        advice = (f"{pred['choice']} {round(pred['confidence'] * 100)}%" if pred
                  else "nessuna previsione")
        print(f"  • {card} ({repo}) — {title}\n      twin: {advice} · "
              f"{agreement.category_rate(history, cat)}")
    print("Per approvare resta il tuo comando: kb start <id> --by roberto")
    print("Le voci mostrate qui non contano piu' nell'accordo: le hai viste prima di decidere.")
    return 0


def cmd_agreement(args):
    print(agreement.render(ledger.load(), None if args.all else args.days))
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(prog="twin-shadow")
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("predict")
    s.add_argument("--max", type=int, default=int(os.environ.get("RDA_TWIN_MAX", "5")))
    s.add_argument("--if-enabled", action="store_true")
    s = sub.add_parser("outcome")
    s.add_argument("--board", required=True)
    s.add_argument("--card", required=True)
    s.add_argument("--choice", choices=ledger.CHOICES, required=True)
    s.add_argument("--by", default="")
    s.add_argument("--interactive", choices=("yes", "no"), default="no")
    sub.add_parser("reconcile")
    s = sub.add_parser("decide")
    s.add_argument("--card", required=True)
    s.add_argument("--choice", choices=ledger.CHOICES, required=True)
    s.add_argument("--board")
    s.add_argument("--situation")
    s.add_argument("--reason")
    s.add_argument("--category", choices=ledger.CATEGORIES)
    s.add_argument("--source", choices=ledger.SOURCES, default="override")
    sub.add_parser("batch")
    s = sub.add_parser("agreement")
    s.add_argument("--days", type=int, default=7)
    s.add_argument("--all", action="store_true")
    args = p.parse_args(argv)
    try:
        return globals()["cmd_" + args.cmd](args)
    except ledger.PrivacyError as exc:
        print(f"twin-shadow: {exc}", file=sys.stderr)
        return 3


if __name__ == "__main__":
    raise SystemExit(main())
