"""Roberto approves the twin's "approve" block in one command (plan 2026-09-24 item 4.6).

The twin still approves nothing. This only saves Roberto typing: it refuses unless a person is
at a terminal, shows the block, asks ONE confirmation, then runs the normal
`kb start <id> --by roberto` per card, so every kb gate (fields filled, one card in progress
per repo, precheck, audit line) still decides card by card.
"""

import os
import subprocess
import sys

from . import board, ledger

AGENT_ENV = ("CLAUDECODE", "RDA_FACTORY", "RDA_GOAL_GATE_RUN")


def refuse_reason():
    # Same test kb start uses for its audit line (`[ -t 0 ]`), plus stdout: a person reads the list.
    if not (sys.stdin.isatty() and sys.stdout.isatty()):
        return ("serve un terminale con Roberto davanti: questo comando non parte da un agente, "
                "da uno scheduler o da una pipe")
    hit = [v for v in AGENT_ENV if os.environ.get(v)]
    if hit:
        return f"sessione agente rilevata ({', '.join(hit)}): lancialo tu dal tuo terminale"
    return ""


def block(root, except_ids):
    """(board, card, title, prediction) for todo cards the twin advises to approve."""
    out = []
    records = ledger.load()
    for bd in board.boards(root):
        for card in board.todo_cards(bd):
            if card in except_ids:
                continue
            rec = ledger.find(records, ledger.record_id(bd, card)) or {}
            pred = rec.get("twin_prediction")
            if pred and pred.get("choice") == "approve" and not rec.get("roberto_choice"):
                _col, text = board.read_card(bd, card)
                out.append((bd, card, board.field(text, "title") or card, pred))
    out.sort(key=lambda r: -r[3].get("confidence", 0))
    return out


def run(root, except_ids):
    why = refuse_reason()
    if why:
        print(f"twin-shadow approve: RIFIUTATO — {why}.", file=sys.stderr)
        return 2
    rows = block(root, except_ids)
    print("## Blocco da approvare — il twin consiglia 'approve' (decidi tu)")
    if not rows:
        print("  (nessuna card: il twin non consiglia di approvare nulla, o non ha previsioni)")
        return 0
    for _bd, card, title, pred in rows:
        print(f"  • {card} — {title} · twin: approve {round(pred.get('confidence', 0) * 100)}%")
    if except_ids:
        print(f"  escluse da te: {', '.join(sorted(except_ids))}")
    with ledger.locked() as records:  # from here these decisions are anchored: not in agreement
        for bd, card, _t, _p in rows:
            rec = ledger.find(records, ledger.record_id(bd, card))
            if rec is not None and not rec.get("shown_at"):
                rec["shown_at"] = ledger.now()
    sys.stdout.write(f"Avvio queste {len(rows)} card con kb start --by roberto? Scrivi 'si' per confermare: ")
    sys.stdout.flush()
    if sys.stdin.readline().strip().lower() not in ("si", "sì"):
        print("Nessuna card avviata.")
        return 0
    kb = os.environ.get("RDA_KB") or os.path.join(root, "kanban", "kb.sh")
    started = 0
    for bd, card, _t, _p in rows:
        env = dict(os.environ, RDA_KANBAN=bd)  # the card's own board, as kb resolves it
        res = subprocess.run(["bash", kb, "start", card, "--by", "roberto"], env=env)
        if res.returncode == 0:
            started += 1
            with ledger.locked() as records:
                rec = ledger.find(records, ledger.record_id(bd, card))
                if rec is not None:
                    rec["batch"] = True
        else:
            print(f"  {card}: kb start ha rifiutato (motivo sopra) — resta in attesa")
    print(f"Avviate {started} di {len(rows)}. Le approvazioni in blocco non contano nell'accordo.")
    return 0 if started == len(rows) else 1
