"""Ask the local host for the twin's prediction. Optional, bounded, never blocking.

No host, an unreviewed model, a timeout or unparseable output all return None: the caller
records "no prediction" and moves on. The twin predicts; it never approves anything.
"""

import json
import os
import re
import shlex
import shutil
import subprocess
import tempfile

from .ledger import CATEGORIES, CHOICES

PROMPT = """Sei il twin di Roberto. Una card aspetta la SUA approvazione (todo -> doing).
Prevedi cosa fara' LUI, non cosa sarebbe giusto in astratto. Non approvi nulla: la tua
risposta viene solo registrata e confrontata dopo con la sua scelta.

Come decide Roberto:
{lens}

Casi simili gia' decisi da Roberto (registro locale, i piu' vicini per primi):
{precedents}

Card (progetto {repo}):
{card}

Rispondi SOLO con una riga JSON, senza altro testo:
{{"choice": "approve|reject|defer", "confidence": 0.0-1.0,
 "category": "tecnico|priorita|comunicazione|soldi|persone|altro", "why": "una riga"}}
"""


def decision_lens(root):
    """Section 3 of identity/voice.md ("How he decides") — the canon, not a paraphrase."""
    path = os.path.join(root, "identity", "voice.md")
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return "(identity/voice.md non trovato: decidi solo dal contenuto della card)"
    m = re.search(r"^## 3\..*?$(.*?)^## ", text, re.MULTILINE | re.DOTALL)
    return (m.group(1).strip() if m else text[:1500])[:2000]


def build_prompt(root, repo, card_text, precedents="(nessun caso simile nel registro)"):
    return PROMPT.format(lens=decision_lens(root), repo=repo or "?", card=card_text[:2500],
                         precedents=precedents[:1500])


def _claude_argv(root):
    claude = shutil.which("claude")
    if not claude:
        return None
    models = os.path.join(root, "bin", "models.sh")
    try:
        model = subprocess.run(
            ["bash", models, "resolve", "sonnet", "--host", "claude"],
            capture_output=True, text=True, timeout=20, check=True,
        ).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return None  # a model the registry does not resolve is never typed from memory
    if not model:
        return None
    budget = os.environ.get("RDA_TWIN_BUDGET_USD", "0.05")
    # No tools, MCP, skills, settings or saved session, and a hard per-call spend cap. The short
    # system prompt matters: the default one plus CLAUDE.md is ~16k tokens (~$0.05 a card,
    # measured 2026-09-24); with it replaced one prediction measured $0.0026.
    return [claude, "-p", "--model", model, "--tools", "", "--strict-mcp-config",
            "--disable-slash-commands", "--no-session-persistence", "--setting-sources", "",
            "--system-prompt", "Sei il twin di Roberto. Rispondi solo con una riga JSON.",
            "--max-budget-usd", budget]


def host_argv(root):
    custom = os.environ.get("RDA_TWIN_HOST_CMD")
    if custom is not None:
        return shlex.split(custom) or None
    if os.environ.get("RDA_TWIN_HOST", "claude") == "none":
        return None
    return _claude_argv(root)


def parse(raw):
    m = re.search(r"\{.*?\}", raw or "", re.DOTALL)
    if not m:
        return None
    try:
        data = json.loads(m.group(0))
    except json.JSONDecodeError:
        return None
    choice = str(data.get("choice", "")).strip().lower()
    if choice not in CHOICES:
        return None
    try:
        conf = max(0.0, min(1.0, float(data.get("confidence", 0.5))))
    except (TypeError, ValueError):
        conf = 0.5
    cat = str(data.get("category", "altro")).strip().lower()
    return {"choice": choice, "confidence": round(conf, 2),
            "category": cat if cat in CATEGORIES else "altro",
            "why": str(data.get("why", ""))[:200]}


def ask(root, prompt):
    """(prediction or None, why-not). Prompt goes on stdin; cwd is a neutral temp dir."""
    argv = host_argv(root)
    if not argv:
        return None, "nessun host disponibile"
    timeout = int(os.environ.get("RDA_TWIN_TIMEOUT_S", "90"))
    try:
        res = subprocess.run(argv, input=prompt, capture_output=True, text=True,
                             timeout=timeout, cwd=tempfile.gettempdir())
    except (OSError, subprocess.SubprocessError) as exc:
        return None, f"host fallito: {type(exc).__name__}"
    if res.returncode != 0:
        return None, f"host uscito con {res.returncode}"
    pred = parse(res.stdout)
    if not pred:
        return None, "risposta non leggibile"
    pred["model"] = os.path.basename(argv[0]) + (
        f":{argv[argv.index('--model') + 1]}" if "--model" in argv else "")
    return pred, ""
