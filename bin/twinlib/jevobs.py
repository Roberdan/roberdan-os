"""Jev observation for a pending card (ADR-0003 boundary). Dry-run only, never a prediction.

A card reaches Jev only if it DECLARES `jev: public` or `jev: synthetic`; cards are private by
default and are recorded as "non inviato: privato". Even then this runs `bin/jev.py evaluate`
in its default dry-run: no credentials, no network, no spend. Going live needs the operator to
review the payload and approve its sha256 (ADR-0003); the twin never approves it. Jev's twin
profile returns separate signals, not a choice, so it is never scored as a prediction of Roberto.
"""

import json
import os
import subprocess
import tempfile

from . import board
from .ledger import now

OPTIONS = [("approve", "Start this card now."), ("defer", "Keep it waiting for later."),
           ("reject", "Drop this card.")]


def observe(root, text):
    classification = board.field(text, "jev").lower()
    if classification not in ("public", "synthetic"):
        return {"status": "non inviato: privato", "at": now()}
    payload = {"classification": classification, "situation": board.field(text, "title")[:300],
               "options": [{"id": i, "text": t, "eligible": True} for i, t in OPTIONS]}
    fd, path = tempfile.mkstemp(suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(payload, fh)
        res = subprocess.run(["python3", os.path.join(root, "bin", "jev.py"), "evaluate", "twin",
                              "--input", path], capture_output=True, text=True, timeout=30)
        out = json.loads(res.stdout) if res.returncode == 0 else {}
    except (OSError, subprocess.SubprocessError, ValueError):
        out = {}
    finally:
        os.unlink(path)
    if out.get("status") != "dry_run":
        return {"status": "jev non disponibile", "at": now()}
    return {"status": "dry-run", "profile": "twin", "sha256": out.get("sha256"), "at": now()}
