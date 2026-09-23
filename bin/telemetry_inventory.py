"""Declared skill identities; file presence is not runtime discovery or invocation."""
import os
from pathlib import Path
import re


class TelemetryError(Exception):
    pass


NAME = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_.:-]{0,127}\Z")


def scalar(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        value = value[1:-1]
    if not NAME.fullmatch(value):
        raise TelemetryError("inventario: nome o alias non interpretabile")
    return value


def declaration(path):
    text = path.read_text(encoding="utf-8-sig")
    lines = text.splitlines()
    if not lines or lines[0] != "---":
        return None
    try:
        end = lines.index("---", 1)
    except ValueError as exc:
        raise TelemetryError("inventario: intestazione incompleta") from exc
    name, aliases, collecting = None, [], False
    for line in lines[1:end]:
        if line.startswith("name:"):
            if name is not None:
                raise TelemetryError("inventario: nome dichiarato piu' volte")
            name = scalar(line.partition(":")[2])
        elif line.startswith("aliases:"):
            value = line.partition(":")[2].strip()
            collecting = not value
            if value:
                if not (value.startswith("[") and value.endswith("]")):
                    raise TelemetryError("inventario: aliases deve essere una lista")
                aliases.extend(scalar(item) for item in value[1:-1].split(",") if item.strip())
        elif collecting and re.match(r"\s+-\s+", line):
            aliases.append(scalar(line.strip()[1:]))
        elif line and not line[0].isspace():
            collecting = False
    if name is None:
        return None
    reference = None
    if "<!-- roberdan-os: namespaced install (skill-name collision) -->" in text:
        match = re.search(r"Canonical logic: read `(skills/[^`]+/skill\.md)` in roberdan-os", text)
        if match:
            reference = match[1]
    return {"name": name, "aliases": aliases, "reference": reference}


def manifests(base):
    def unreadable(_error):
        raise TelemetryError("inventario: directory non leggibile")

    seen = set()
    for directory, children, files in os.walk(base, followlinks=True, onerror=unreadable):
        resolved = Path(directory).resolve()
        if resolved in seen:
            children[:] = []
            continue
        seen.add(resolved)
        children[:] = sorted(child for child in children if child not in
                             (".git", "node_modules", "__pycache__"))
        for filename in sorted(files):
            if filename.lower() == "skill.md":
                yield Path(directory) / filename


def inventory(root, alias_groups=()):
    scopes = [("canoniche", root / "skills", False),
              ("pacchetto-progetto", root / ".github/skills", False)]
    override = os.environ.get("RDA_TELEMETRY_SKILL_DIRS")
    if override is not None:
        scopes += [(f"installate-{i + 1}", Path(path), True)
                   for i, path in enumerate(override.split(os.pathsep)) if path]
    else:
        for host in ("claude", "copilot", "codex", "agents"):
            scopes.append((f"installate-{host}", Path.home() / f".{host}/skills", True))
            scopes.append((f"progetto-{host}", root / f".{host}/skills", True))
    definitions, observations, references = [], [], {}
    unnamed = 0
    for scope, base, installed in scopes:
        if not base.exists() and not base.is_symlink():
            observations.append({"scope": scope, "status": "assente", "definitions": None})
            continue
        if not base.is_dir():
            raise TelemetryError("inventario: sorgente non leggibile")
        count = 0
        for path in manifests(base):
            item = declaration(path)
            if item is None:
                unnamed += 1
                continue
            item.update(scope=scope, installed=installed)
            definitions.append(item)
            if scope == "canoniche":
                references[path.relative_to(root).with_name("skill.md").as_posix()] = item["name"]
            count += 1
        observations.append({"scope": scope, "status": "presente", "definitions": count})

    parent = {}

    def find(name):
        parent.setdefault(name, name)
        if parent[name] != name:
            parent[name] = find(parent[name])
        return parent[name]

    def merge(name, alias):
        parent[find(alias)] = find(name)

    for item in definitions:
        find(item["name"])
        for alias in item["aliases"]:
            merge(item["name"], alias)
    for item in definitions:
        if item["reference"] in references:
            merge(references[item["reference"]], item["name"])
    for group in alias_groups:
        if group[0] in parent:
            for alias in group[1:]:
                merge(group[0], alias)
    skills = {}
    for item in definitions:
        name = find(item["name"])
        entry = skills.setdefault(name, {"name": name, "scopes": set(), "installed": False})
        entry["scopes"].add(item["scope"])
        entry["installed"] |= item["installed"]
    aliases = {name: find(name) for name in parent}
    for name, item in skills.items():
        item["scopes"] = sorted(item["scopes"])
        item["aliases"] = sorted(alias for alias, canonical in aliases.items()
                                 if canonical == name and alias != name)
    return {"skills": [skills[name] for name in sorted(skills)],
            "aliases": aliases, "scopes": observations, "unnamed_definitions": unnamed}
