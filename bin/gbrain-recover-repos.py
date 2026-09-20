#!/usr/bin/env python3
"""Resumable conservative recovery: snapshot first, scoped imports, local vectors."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
import urllib.request

HOME = Path.home()
GB = HOME / ".bun/bin/gbrain"
DB = "postgres:///gbrain_local"


def sql(text):
    result = subprocess.run(["psql", "--no-psqlrc", "-At", DB, "-c", text],
                            text=True, capture_output=True, timeout=60)
    if result.returncode:
        raise RuntimeError(result.stderr.strip())
    return json.loads(result.stdout)


def quote(value):
    return "'" + value.replace("'", "''") + "'"


def sources():
    return sql("SELECT coalesce(json_agg(row_to_json(s)), '[]') FROM "
               "(SELECT id,local_path,last_commit,last_sync_at FROM sources) s")


def active_pages(source):
    return set(sql("SELECT coalesce(json_agg(id), '[]') FROM pages WHERE source_id=" +
                   quote(source) + " AND deleted_at IS NULL"))


def make_id(identity):
    stem = re.sub("[^a-z0-9-]", "-", identity.split("/")[-1].lower()).strip("-")[:19]
    return "repo-" + stem + "-" + hashlib.sha256(identity.lower().encode()).hexdigest()[:6]


def plan(manifest):
    records = {}
    for item in manifest["remote"]:
        key = item["nameWithOwner"].lower()
        records[key] = {"key": key, "github": item["nameWithOwner"],
                        "archived": item["isArchived"], "local_path": None}
    for item in manifest["local"]:
        key = (item.get("github") or "local:" + item["path"]).lower()
        record = records.setdefault(key, {"key": key, "github": item.get("github"), "archived": False})
        if not record.get("local_path"):
            record.update(local_path=item["path"], bare=item.get("bare", False), pin=item.get("pin"))
    return sorted(records.values(), key=lambda row: (not bool(row.get("local_path")), row["key"]))


def eligible(record, root):
    if root is None:
        return True
    if not record.get("local_path"):
        return False
    path = Path(record["local_path"])
    return (path.name.casefold() not in {"warehouse", "parkinglot", "worktrees"}
            and not path.is_symlink() and path.is_dir()
            and path.resolve().parent == Path(root).resolve()
            and (path / ".git").exists())


def active_manifest(root, inspect_repo):
    root = Path(root)
    if not root.is_dir():
        raise RuntimeError("Active repository folder is unavailable.")
    local = [inspect_repo(path) for path in sorted(root.iterdir())
             if eligible({"local_path": str(path)}, root)]
    return {"local": [item for item in local if item], "remote": []}


class Recovery:
    def __init__(self, manifest, root, backup, blocked_sources=(), active_root=None):
        self.manifest = manifest
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.path = root / "state.json"
        self.state = json.loads(self.path.read_text()) if self.path.exists() else {"repos": {}, "commands": []}
        self.backup = backup
        self.blocked_sources = set(blocked_sources)
        self.active_root = active_root
        self.current_record = None
        self.env = dict(os.environ, GIT_TERMINAL_PROMPT="0", GH_PROMPT_DISABLED="1",
                        COPILOT_AUTO_UPDATE="false")
        for key in ("DATABASE_URL", "GBRAIN_DATABASE_URL", "GBRAIN_SOURCE"):
            self.env.pop(key, None)

    def save(self):
        temp = self.root / "state.tmp"
        temp.write_text(json.dumps(self.state, indent=2) + "\n")
        temp.replace(self.path)

    def check_scope(self):
        if self.current_record is not None and not eligible(self.current_record, self.active_root):
            raise RuntimeError("BLOCKED: repository was removed, archived or moved outside the active folder.")

    def command(self, argv, timeout=600):
        self.check_scope()
        argv = list(map(str, argv))
        index = len(self.state["commands"]) + 1
        log = self.root / f"command-{index:05d}.log"
        entry = {"argv": argv, "log": str(log), "started": time.time(), "exit": None}
        self.state["commands"].append(entry)
        self.save()
        with log.open("wb") as output:
            with subprocess.Popen(argv, cwd=HOME / ".gbrain", env=self.env,
                                  stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT,
                                  start_new_session=True) as proc:
                try:
                    code = proc.wait(timeout=timeout)
                except (subprocess.TimeoutExpired, KeyboardInterrupt):
                    os.killpg(proc.pid, signal.SIGTERM)
                    try:
                        proc.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        os.killpg(proc.pid, signal.SIGKILL)
                        proc.wait()
                    entry["exit"] = 124
                    self.save()
                    raise
        entry["exit"] = code
        self.save()
        text = log.read_text(errors="replace")
        if code:
            raise RuntimeError(f"Command exit {code}: {log}\n" + "\n".join(text.splitlines()[-8:]))
        return text.strip()

    def validate_backup(self):
        data = json.loads(self.backup.read_text())
        if data.get("status") != "verified":
            raise RuntimeError("A restore-tested backup is mandatory.")
        for name, expected in data["sha256"].items():
            with (self.backup.parent / name).open("rb") as stream:
                if hashlib.file_digest(stream, "sha256").hexdigest() != expected:
                    raise RuntimeError(f"Backup checksum mismatch: {name}")
        config = json.loads((HOME / ".gbrain/config.json").read_text())
        if config.get("embedding_model") != "ollama:bge-m3" or config.get("embedding_dimensions") != 1024:
            raise RuntimeError("Local bge-m3 / 1024 embedding configuration is required.")

    def checkout(self, record):
        local = record.get("local_path")
        identity = record.get("github")
        if identity and not re.fullmatch(r"[\w.-]+/[\w.-]+", identity):
            raise RuntimeError("No unambiguous GitHub identity for a managed checkout.")
        if not identity and not local:
            raise RuntimeError("No local checkout or GitHub identity.")
        path = HOME / ".gbrain/checkouts" / (identity or "local/" + make_id(record["key"]))
        marker = path / ".git/roberdan-recovery.json"
        if path.exists():
            if not marker.exists() or json.loads(marker.read_text()).get("key") != record["key"]:
                raise RuntimeError(f"Existing checkout is not owned by this recovery: {path}")
            if self.command(["git", "-C", path, "status", "--porcelain", "--untracked-files=all", "--ignored"]):
                raise RuntimeError(f"Managed snapshot was modified; refusing to overwrite: {path}")
            if local:
                revision = self.head(Path(local))
                if self.head(path) != revision:
                    git_dir = self.command(["git", "-C", local, "rev-parse", "--absolute-git-dir"])
                    self.command(["git", "-c", "core.hooksPath=/dev/null", "-C", path, "fetch",
                                  "--no-tags", "--no-recurse-submodules", git_dir, revision])
                    if self.head(Path(local)) != revision:
                        raise RuntimeError("Local HEAD changed while refreshing the managed snapshot.")
                    self.command(["git", "-c", "core.hooksPath=/dev/null", "-C", path,
                                  "merge", "--ff-only", "--no-edit", revision])
                    if self.head(path) != revision:
                        raise RuntimeError("Managed snapshot does not match current local HEAD.")
                    marker.write_text(json.dumps({"key": record["key"], "snapshot": revision}) + "\n")
            return path
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        if local:
            revision = self.head(Path(local))
            git_dir = self.command(["git", "-C", local, "rev-parse", "--absolute-git-dir"])
            self.command(["git", "-c", "core.hooksPath=/dev/null", "clone", "--no-hardlinks",
                          "--config", "core.hooksPath=/dev/null", git_dir, path], timeout=900)
            if self.head(path) != revision:
                raise RuntimeError("Local HEAD changed while creating the managed snapshot.")
        else:
            self.command(["gh", "repo", "clone", identity, path, "--", "--depth=1",
                          "--single-branch", "--filter=blob:none",
                          "--config", "core.hooksPath=/dev/null"], timeout=900)
        marker.write_text(json.dumps({"key": record["key"], "snapshot": self.head(path)}) + "\n")
        return path

    def head(self, path):
        return self.command(["git", "-C", path, "rev-parse", "HEAD"])

    def source_for(self, record, path):
        current = sources()
        candidates = [s for s in current if s["local_path"]
                      and s["local_path"] in (str(path), record.get("local_path"))]
        if not candidates:
            # Moved/missing roots are repairable only on an unambiguous repository name.
            name = record["key"].split("/")[-1].lower()
            matches = [s for s in current if s["id"].lower() == name
                       and s["local_path"] and not Path(s["local_path"]).exists()]
            identities = [r for r in plan(self.manifest) if r["key"].split("/")[-1].lower() == name]
            if len(matches) == 1 and len(identities) == 1:
                candidates = matches
        if len(candidates) > 1:
            raise RuntimeError("Multiple registered sources match; refuse to choose silently.")
        if candidates:
            source = candidates[0]
            if source["id"] in self.blocked_sources:
                raise RuntimeError(f"BLOCKED: source access not granted: {source['id']}")
            if source["local_path"] != str(path):
                self.command([GB, "sources", "set-path", source["id"], path])
            return source["id"], False
        source_id = make_id(record["key"])
        if any(s["id"] == source_id for s in current):
            raise RuntimeError(f"Source id collision: {source_id}")
        self.command([GB, "sources", "add", source_id, "--path", path, "--no-federated"])
        return source_id, True

    def refresh(self, source, path, new):
        before = active_pages(source)
        revision = self.head(path)
        base = [GB, "sync", "--source", source, "--repo", path, "--no-pull",
                "--strategy", "auto", "--no-embed", "--no-auto-embed"]
        preview = self.command([*base, "--dry-run"], timeout=300)
        if re.search(r"^\s*(Deleted|Removed|Renamed):|would delete", preview, re.MULTILINE | re.IGNORECASE):
            raise RuntimeError("BLOCKED: preview contains deletions/renames; originals preserved.")
        if before and re.search(r"full (sync|import)|reconcil", preview, re.IGNORECASE):
            raise RuntimeError("BLOCKED: existing source requires reconciliation; original pages preserved.")
        if before and not (re.search(r"Sync dry run: [0-9a-f]+\.\.[0-9a-f]+", preview)
                           or "Already up to date" in preview):
            raise RuntimeError("BLOCKED: existing source needs a full/reconcile sync; not authorized.")
        if new and before:
            raise RuntimeError("New source is unexpectedly nonempty.")
        if self.head(path) != revision:
            raise RuntimeError("BLOCKED: checkout HEAD changed after preview.")
        self.command(base, timeout=1800)
        after = active_pages(source)
        lost = before - after
        if lost:
            raise RuntimeError(f"RETENTION FAILURE: {len(lost)} prior pages no longer active; stop recovery.")
        if self.head(path) != revision:
            raise RuntimeError("BLOCKED: checkout HEAD changed during synchronization.")
        indexed = next((row for row in sources() if row["id"] == source), None)
        if not indexed or indexed["last_commit"] != revision:
            raise RuntimeError("BLOCKED: stored index revision does not match the managed checkout.")
        return {"pages_before": len(before), "pages_after": len(after), "snapshot": revision}

    def local_vectors(self, source):
        with urllib.request.urlopen("http://localhost:11434/api/version", timeout=5) as response:
            json.load(response)
        previous = None
        stalls = 0
        for _ in range(12):
            # dream's embed phase is global in 0.50 even when --source is given.
            self.command([GB, "embed", "--stale", "--source", source], timeout=1800)
            preview = self.command([GB, "embed", "--stale", "--source", source, "--dry-run"], timeout=180)
            match = re.search(r"Would embed (\d+) (?:stale )?chunks", preview)
            if not match:
                raise RuntimeError("Cannot verify the authoritative remaining stale-vector count.")
            missing = int(match[1])
            if missing == 0:
                return
            stalls = stalls + 1 if missing == previous else 0
            if stalls >= 2:
                raise RuntimeError(f"Embedding stalled: {missing} text chunks remain without vectors.")
            previous = missing
        raise RuntimeError("Embedding iteration ceiling reached; resume from saved state.")

    def run(self):
        with (self.root / "run.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.validate_backup()
            all_records = plan(self.manifest)
            records = [r for r in all_records if eligible(r, self.active_root)]
            registered = sources()
            self.state["total"] = len(records)
            self.state["excluded_from_scope"] = len(all_records) - len(records)
            self.state["active_root"] = str(self.active_root) if self.active_root else None
            for index, record in enumerate(records, 1):
                key = record["key"]
                row = {**record, "status": "running", "started": time.time()}
                self.current_record = record
                self.state["repos"][key] = row
                self.state["current"] = key
                self.save()
                print(f"[{index}/{len(records)}] {key}", flush=True)
                try:
                    self.check_scope()
                    matches = [s["id"] for s in registered if s["local_path"] == record.get("local_path")
                               and s["local_path"]]
                    if record.get("pin") in self.blocked_sources or self.blocked_sources.intersection(matches):
                        raise RuntimeError("BLOCKED: source access not granted; no content read.")
                    path = self.checkout(record)
                    row["checkout"] = str(path)
                    source, new = self.source_for(record, path)
                    row["source"] = source
                    row.update(self.refresh(source, path, new))
                    row["index_status"] = "verified"
                    self.save()
                    self.local_vectors(source)
                    if record.get("local_path") and self.head(Path(record["local_path"])) != row["snapshot"]:
                        raise RuntimeError("Local HEAD changed during recovery; a fresh pass is required.")
                    row["status"] = "verified"
                except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as exc:
                    row["status"] = "blocked"
                    row["error"] = str(exc)
                    print(f"  BLOCKED: {exc}", flush=True)
                    if "RETENTION FAILURE" in str(exc):
                        self.save()
                        return 1
                row["finished"] = time.time()
                self.save()
            self.state["current"] = None
            self.state["finished"] = time.time()
            self.save()
            return int(any(self.state["repos"][r["key"]]["status"] != "verified" for r in records))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--backup", type=Path, required=True)
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--active-root", type=Path, default=Path.home() / "GitHub",
                        help="Only existing direct-child repositories here; no archived or remote-only collections.")
    parser.add_argument("--blocked-source", action="append", default=[],
                        help="Do not access or modify an explicitly ungranted source.")
    args = parser.parse_args()
    os.umask(0o077)
    # The saved manifest is evidence, not authority to resurrect moved/deleted projects.
    import importlib.util
    spec = importlib.util.spec_from_file_location("repo_audit", Path(__file__).with_name("gbrain-repo-audit.py"))
    audit = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(audit)
    manifest = active_manifest(args.active_root, audit.inspect)
    if not args.apply:
        print(json.dumps([r for r in plan(manifest) if eligible(r, args.active_root)], indent=2))
        return 0
    return Recovery(manifest, args.state_dir, args.backup, args.blocked_source, args.active_root).run()


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
