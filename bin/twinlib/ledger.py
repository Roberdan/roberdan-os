"""Local-only JSONL ledger of decisions (docs/adr/0005-twin-decision-ledger.md).

One line per decision. The file lives under RDA_HOME/private/decisions and is refused
anywhere inside a git work tree: the privacy boundary is a check in code, not a convention.
"""

import contextlib
import datetime as _dt
import fcntl
import hashlib
import json
import os
import tempfile

CATEGORIES = ("tecnico", "priorita", "comunicazione", "soldi", "persone", "altro")
CHOICES = ("approve", "reject", "defer")
SOURCES = ("kb-pending", "draft-edit", "override")


class PrivacyError(RuntimeError):
    """The ledger path would land somewhere that can be committed."""


def now():
    # RDA_TWIN_NOW pins the clock in tests; real runs use UTC seconds (ISO sorts as text).
    fixed = os.environ.get("RDA_TWIN_NOW")
    if fixed:
        return fixed
    return _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def ledger_dir():
    explicit = os.environ.get("RDA_TWIN_LEDGER_DIR")
    if explicit:
        return os.path.abspath(explicit)
    home = os.environ.get("RDA_HOME") or os.path.join(os.path.expanduser("~"), ".roberdan-os")
    return os.path.join(os.path.abspath(home), "private", "decisions")


def inside_git_tree(path):
    """True when path (or its nearest existing ancestor) sits inside a git work tree."""
    cur = os.path.realpath(path)
    while True:
        if os.path.exists(os.path.join(cur, ".git")):
            return True
        parent = os.path.dirname(cur)
        if parent == cur:
            return False
        cur = parent


def ledger_path(create=False):
    d = ledger_dir()
    if inside_git_tree(d):
        raise PrivacyError(
            f"registro rifiutato: {d} sta dentro un repository git. "
            "Il registro delle decisioni vive solo in locale (RDA_HOME/private/decisions)."
        )
    if create:
        os.makedirs(d, mode=0o700, exist_ok=True)
        os.chmod(d, 0o700)
    return os.path.join(d, "ledger.jsonl")


def record_id(board, card):
    digest = hashlib.sha1(os.path.realpath(board).encode("utf-8")).hexdigest()[:8]
    return f"{card}@{digest}"


def load():
    path = ledger_path()
    if not os.path.exists(path):
        return []
    out = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                continue  # a torn line never blocks the rest of the ledger
    return out


@contextlib.contextmanager
def locked():
    """Exclusive lock + read; yields the list, writes it back atomically if changed."""
    path = ledger_path(create=True)
    with open(path + ".lock", "a", encoding="utf-8") as lk:
        os.chmod(path + ".lock", 0o600)
        fcntl.flock(lk, fcntl.LOCK_EX)
        records = load()
        before = json.dumps(records, sort_keys=True)
        yield records
        if json.dumps(records, sort_keys=True) != before:
            _write(path, records)


def _write(path, records):
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".ledger.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            for rec in records:
                fh.write(json.dumps(rec, ensure_ascii=False, sort_keys=True) + "\n")
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def find(records, rid):
    for rec in records:
        if rec.get("id") == rid:
            return rec
    return None


def new_record(board, card, situation, category="altro", source="kb-pending"):
    return {
        "id": record_id(board, card),
        "date": now()[:10],
        "created_at": now(),
        "board": os.path.realpath(board),
        "card": card,
        "category": category if category in CATEGORIES else "altro",
        "situation": situation[:200],
        "options": list(CHOICES),
        "twin_prediction": None,
        "jev_prediction": None,
        "roberto_choice": None,
        "reason": None,
        "source": source,
        "decided_at": None,
        "decided_by": None,
        "interactive": None,
        "attributed": False,
        "shown_at": None,
    }


def is_roberto(by, interactive):
    """Only a plain `--by roberto` from a terminal counts as Roberto's own choice.

    `--by` is honor-system (kanban/kb.sh), queue approvals are pre-authorizations of a list,
    and a non-interactive start may be an agent: all three are kept, none is counted."""
    return (by or "").strip().lower() == "roberto" and interactive == "yes"


def decide(rec, choice, by, interactive, source=None, reason=None):
    rec["roberto_choice"] = choice
    rec["decided_at"] = now()
    rec["decided_by"] = by
    rec["interactive"] = interactive
    rec["attributed"] = is_roberto(by, interactive)
    if source:
        rec["source"] = source
    if reason:
        rec["reason"] = reason[:200]
