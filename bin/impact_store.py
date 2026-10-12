"""Private storage and review-evidence schema for the impact review.

Everything written here lives under ~/.roberdan-os/private/impact-review (or
RDA_IMPACT_HOME, which must itself sit under the private base). Directories are
0700, files 0600, and a destination inside any git worktree is refused: an
ignored file in a public checkout is not private. No silent fallback exists.
"""
from datetime import datetime
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent


class ImpactError(Exception):
    pass


IDENT = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}\Z")
REF = re.compile(r"(git:[0-9a-f]{7,40}|kb:[0-9]{6}-[0-9]{6}|"
                 r"(private|eval):[A-Za-z0-9][A-Za-z0-9._/-]{0,199})\Z")
STATUS = {"acceptance": ("accepted", "failed", "unassessed"),
          "adoption": ("adopted", "rejected", "unassessed")}
SOURCES = ("measured", "operator-declared")
UNITS = {"work_items": {"count": 1.0},
         "time": {"seconds": 1 / 60, "minutes": 1.0, "hours": 60.0},
         "resources": {"tokens": 1.0, "requests": 1.0, "premium-requests": 1.0}}
ENTRY_KEYS = {"schema", "kind", "name", "task_id", "run_id", "observed_at",
              "acceptance", "acceptance_source", "acceptance_ref",
              "adoption", "adoption_source", "adoption_ref", "repair"}
REPAIR_KEYS = {"measure", "value", "unit", "source", "ref"}


def private_base():
    return Path(os.environ.get("RDA_PRIVATE_HOME", str(Path.home() / ".roberdan-os/private")))


def inside_git(path):
    for parent in (path, *path.parents):
        if (parent / ".git").exists():
            return True
    return False


def secure_dir(path):
    missing, cursor = [], path
    while not cursor.exists() and not cursor.is_symlink():
        missing.append(cursor)
        cursor = cursor.parent
    for directory in reversed(missing):
        directory.mkdir(mode=0o700)
        os.chmod(directory, 0o700)
    if path.is_symlink() or not path.is_dir():
        raise ImpactError("destinazione privata non valida: non e' una directory")
    if path.stat().st_mode & 0o077:
        raise ImpactError("destinazione privata con permessi aperti ad altri utenti: correggere a 0700")
    return path


def impact_home():
    base = private_base().expanduser()
    home = Path(os.environ.get("RDA_IMPACT_HOME", str(base / "impact-review"))).expanduser()
    base_r, home_r = base.resolve(), home.resolve()
    if home_r != base_r and base_r not in home_r.parents:
        raise ImpactError("destinazione rifiutata: deve stare sotto ~/.roberdan-os/private")
    if inside_git(home_r) or home_r == ROOT or ROOT in home_r.parents:
        raise ImpactError("destinazione rifiutata: dentro una copia git, quindi non privata")
    secure_dir(base)
    return secure_dir(home)


def write_private(path, text):
    secure_dir(path.parent)
    tmp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        stream.write(text)
    os.replace(tmp, path)
    os.chmod(path, 0o600)


class Locked:
    def __init__(self, path):
        self.path = path

    def __enter__(self):
        secure_dir(self.path.parent)
        self.fd = os.open(self.path, os.O_WRONLY | os.O_CREAT, 0o600)
        fcntl.flock(self.fd, fcntl.LOCK_EX)
        return self

    def __exit__(self, *_):
        fcntl.flock(self.fd, fcntl.LOCK_UN)
        os.close(self.fd)


def parse_time(value, what="data"):
    if not isinstance(value, str):
        raise ImpactError(f"{what}: serve una data ISO con fuso orario")
    try:
        moment = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ImpactError(f"{what}: data non interpretabile") from exc
    if moment.tzinfo is None:
        raise ImpactError(f"{what}: manca il fuso orario")
    return moment.timestamp()


def roster(root=ROOT):
    """Public agents (canonical roster files) and public canonical skills."""
    agents = set()
    for path in sorted((root / "agents").glob("*.md")):
        for line in path.read_text(encoding="utf-8").splitlines()[1:12]:
            if line.startswith("name:"):
                agents.add(line.partition(":")[2].strip().strip("\"'"))
    policy = json.loads((root / "kanban/audit_skill_names.json").read_text(encoding="utf-8"))
    skills = set(policy["canonical"])
    return {"agent": sorted(agents), "skill": sorted(skills)}


def _ref(value, what):
    if not isinstance(value, str) or not REF.fullmatch(value) or "/../" in f"/{value}/" \
            or "//" in value:
        raise ImpactError(f"{what}: riferimento non valido (git:<sha>, kb:<id>, private:<rel>, eval:<rel>)")
    if value.startswith("private:") and not (private_base() / value[8:]).is_file():
        raise ImpactError(f"{what}: l'artefatto privato citato non esiste")
    return value


def validate(entry, names):
    if not isinstance(entry, dict) or set(entry) - ENTRY_KEYS:
        raise ImpactError("voce: campi sconosciuti o struttura non valida")
    if entry.get("schema") != 1:
        raise ImpactError("voce: schema deve essere 1")
    kind, name = entry.get("kind"), entry.get("name")
    if kind not in names:
        raise ImpactError("voce: kind deve essere agent o skill")
    if name not in names[kind]:
        raise ImpactError("voce: nome fuori dall'elenco pubblico")
    for key in ("task_id", "run_id"):
        if not isinstance(entry.get(key), str) or not IDENT.fullmatch(entry[key]):
            raise ImpactError(f"voce: {key} mancante o non valido")
    parse_time(entry.get("observed_at"), "observed_at")
    for field, allowed in STATUS.items():
        status = entry.get(field)
        if status not in allowed:
            raise ImpactError(f"voce: {field} deve essere uno di {', '.join(allowed)}")
        source, ref = entry.get(f"{field}_source"), entry.get(f"{field}_ref")
        if status == "unassessed":
            if source is not None or ref is not None:
                raise ImpactError(f"voce: {field} non valutato non puo' avere provenienza")
            continue
        if source not in SOURCES:
            raise ImpactError(f"voce: {field}_source deve essere measured o operator-declared")
        _ref(ref, f"{field}_ref")
        if source == "measured" and ref.startswith("kb:"):
            raise ImpactError(f"voce: {field} misurato richiede un artefatto, non solo una card")
    repairs = entry.get("repair", [])
    if not isinstance(repairs, list):
        raise ImpactError("voce: repair deve essere una lista")
    for item in repairs:
        if not isinstance(item, dict) or set(item) != REPAIR_KEYS:
            raise ImpactError("riparazione: servono measure, value, unit, source, ref")
        if item["measure"] not in UNITS or item["unit"] not in UNITS[item["measure"]]:
            raise ImpactError("riparazione: misura o unita' non ammessa (nessuna valuta)")
        value = item["value"]
        if type(value) not in (int, float) or not math.isfinite(value) or value < 0:
            raise ImpactError("riparazione: valore numerico finito e non negativo richiesto")
        if item["source"] not in SOURCES:
            raise ImpactError("riparazione: source deve essere measured o operator-declared")
        _ref(item["ref"], "riparazione")
    return entry


def evidence_path():
    return impact_home() / "evidence.jsonl"


def load_evidence():
    path = evidence_path()
    if not path.exists():
        return []
    rows = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        try:
            rows.append(json.loads(line))
        except ValueError as exc:
            raise ImpactError(f"evidenze: riga {number} non interpretabile") from exc
    return rows


def _key(entry):
    return entry["kind"], entry["name"], entry["task_id"], entry["run_id"]


def _outcome(entry):
    return tuple(entry.get(k) for k in ("acceptance", "acceptance_source", "acceptance_ref",
                                        "adoption", "adoption_source", "adoption_ref"))


def record(entries, root=ROOT):
    """Validate all, reject conflicts, append atomically; identical repeats are no-ops."""
    names = roster(root)
    entries = [validate(entry, names) for entry in entries]
    path = evidence_path()
    with Locked(path.with_name(".evidence.lock")):
        existing = load_evidence()
        by_key = {_key(row): row for row in existing}
        by_task = {}
        for row in existing:
            by_task[row["kind"], row["name"], row["task_id"]] = _outcome(row)
        added = []
        for entry in entries:
            known = by_key.get(_key(entry))
            if known is not None:
                if known != entry:
                    raise ImpactError("voce in conflitto con una gia' registrata per lo stesso run")
                continue
            task = entry["kind"], entry["name"], entry["task_id"]
            if task in by_task and by_task[task] != _outcome(entry):
                raise ImpactError("esito del task in conflitto fra invocazioni dello stesso componente")
            by_task[task] = _outcome(entry)
            by_key[_key(entry)] = entry
            added.append(entry)
        if added:
            text = "".join(json.dumps(row, sort_keys=True) + "\n" for row in existing + added)
            write_private(path, text)
    return len(added), len(entries) - len(added)


def digest(data):
    return hashlib.sha256(data if isinstance(data, bytes) else data.encode()).hexdigest()


TEMPLATE = {"schema": 1, "kind": "agent", "name": "rex", "task_id": "kb:261012-192844",
            "run_id": "copilot:<session>/<toolCallId>", "observed_at": "2026-10-12T10:00:00Z",
            "acceptance": "accepted", "acceptance_source": "measured",
            "acceptance_ref": "git:0123abc", "adoption": "unassessed",
            "repair": [{"measure": "time", "value": 12, "unit": "minutes",
                        "source": "operator-declared", "ref": "kb:261012-192844"}]}
