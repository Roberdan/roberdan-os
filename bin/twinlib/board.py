"""Read-only view of the kanban boards the twin shadows. Never moves or edits a card."""

import os
import re

COLUMNS = ("todo", "doing", "done")


def boards(root):
    """Board dirs in the same order kb resolves them: RDA_TWIN_BOARDS pins them (tests)."""
    pinned = os.environ.get("RDA_TWIN_BOARDS")
    if pinned is not None:
        return [os.path.realpath(b) for b in pinned.split(":") if b]
    found = []
    env_kb = os.environ.get("RDA_KANBAN")
    if env_kb:
        found.append(env_kb)
    found.append(os.path.join(root, "kanban"))
    home = os.environ.get("RDA_HOME") or os.path.join(os.path.expanduser("~"), ".roberdan-os")
    registry = os.environ.get("RDA_KANBAN_REGISTRY") or os.path.join(home, "kanban-registry")
    if os.path.exists(registry):
        with open(registry, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if line and not line.startswith("#"):
                    found.append(os.path.join(line, "kanban"))
    out = []
    for b in found:
        b = os.path.realpath(b)
        if b not in out and os.path.isdir(os.path.join(b, "todo")):
            out.append(b)
    return out


def field(text, key):
    """First `key:` line anywhere in the card — the same rule as kb.sh `_field`."""
    m = re.search(rf"^{re.escape(key)}:[ \t]*(.*)$", text, re.MULTILINE)
    if not m:
        return ""
    return m.group(1).strip().strip('"')


def todo_cards(board):
    col = os.path.join(board, "todo")
    if not os.path.isdir(col):
        return []
    out = []
    for name in sorted(os.listdir(col)):
        if name.endswith(".md") and not name.startswith("_"):
            out.append(name[:-3])
    return out


def read_card(board, card):
    for col in COLUMNS:
        path = os.path.join(board, col, card + ".md")
        if os.path.exists(path):
            with open(path, encoding="utf-8", errors="replace") as fh:
                return col, fh.read()
    return None, ""


def last_start_audit(text):
    """(by, interactive) from the last `kb_start_audit` line kb start appends to the card."""
    hits = re.findall(r'^kb_start_audit: "at=\S+ by=(.*?) interactive=(yes|no)"$', text, re.MULTILINE)
    return hits[-1] if hits else ("", "no")


def summary(text, card):
    title = field(text, "title") or card
    parts = [title]
    for key in ("dod", "acceptance"):
        val = field(text, key)
        if val:
            parts.append(f"{key}: {val}")
    return " | ".join(parts)
