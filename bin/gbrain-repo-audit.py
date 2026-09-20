#!/usr/bin/env python3
"""Read-only repository/source coverage audit; private output stays outside Git."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import urlparse

PRUNE = {".git", "node_modules", ".venv", "venv", ".next", ".turbo", "target",
         ".build", "Pods", ".gradle", "DerivedData", "graphify-out", ".codegraph",
         "worktrees", "copilot-worktrees"}


def run(argv, cwd=None, allowed=(0,)):
    result = subprocess.run(argv, cwd=cwd, text=True, capture_output=True, timeout=120)
    if result.returncode not in allowed:
        raise RuntimeError(f"{argv[0]} failed ({result.returncode}): {result.stderr.strip()}")
    return result.stdout.strip()


def identity(url):
    if url.startswith("git@github.com:"):
        path = url.removeprefix("git@github.com:")
    else:
        parsed = urlparse(url)
        if parsed.hostname != "github.com":
            return None
        path = parsed.path.lstrip("/")
    path = path.removesuffix(".git").rstrip("/")
    return path if re.fullmatch(r"[\w.-]+/[\w.-]+", path) else None


def inspect(path):
    marker = path / ".git"
    if not marker.exists():
        return None
    git = ["git", "--git-dir", str(marker)] if marker.is_dir() else ["git", "-C", str(path)]
    common = run([*git, "rev-parse", "--git-common-dir"], allowed=(0, 128))
    if not common:
        return {"path": str(path), "error": "Invalid Git metadata"}
    origin = run([*git, "config", "--get", "remote.origin.url"], allowed=(0, 1))
    bare = run([*git, "rev-parse", "--is-bare-repository"]) == "true"
    branch = run([*git, "symbolic-ref", "--quiet", "--short", "HEAD"], allowed=(0, 1))
    head = run([*git, "rev-parse", "--verify", "HEAD"], allowed=(0, 128))
    pin = path / ".gbrain-source"
    return {"path": str(path), "github": identity(origin), "bare": bare,
            "linked_worktree": marker.is_file(), "branch": branch, "head": head,
            "pin": pin.read_text().strip() if pin.exists() else None}


def inventory(root, extra=()):
    found = []
    for base, dirs, _ in os.walk(root):
        path = Path(base)
        if (path / ".git").is_dir():
            found.append(inspect(path))
        elif (path / ".git").is_file():
            # Linked worktrees are not distinct projects.
            dirs[:] = []
            continue
        dirs[:] = [d for d in dirs if d not in PRUNE and not d.startswith(".")]
    for path in extra:
        if path.exists() and (path / ".git").exists():
            found.append(inspect(path))
    return sorted({row["path"]: row for row in found if row}.values(), key=lambda r: r["path"])


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.home() / "GitHub")
    parser.add_argument("--owner", action="append", default=[])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    os.umask(0o077)
    home = Path.home()
    local = inventory(args.root, [home / ".claude", home / "gbrain",
                                 home / "Obsidian/Roberdan's Vault"])
    remote = []
    for owner in args.owner or ["Roberdan", "FightTheStroke"]:
        rows = json.loads(run(["gh", "repo", "list", owner, "--limit", "1000", "--json",
                              "nameWithOwner,isArchived,isFork,defaultBranchRef,diskUsage"]))
        if len(rows) == 1000:
            raise RuntimeError(f"Repository listing for {owner} may be truncated.")
        remote.extend(rows)
    sources = json.loads(run(["psql", "--no-psqlrc", "-At", "postgres:///gbrain_local", "-c",
                              "SELECT coalesce(json_agg(row_to_json(s)), '[]') "
                              "FROM (SELECT id,local_path,last_sync_at,last_commit FROM sources) s;"]))
    by_path = {str(Path(s["local_path"]).resolve()): s for s in sources if s["local_path"]}
    by_identity = {}
    for repo in local:
        if repo.get("github"):
            by_identity.setdefault(repo["github"].lower(), []).append(repo)
        source = by_path.get(str(Path(repo["path"]).resolve()))
        repo["source"] = source["id"] if source else None
        repo["coverage"] = "registered" if source else "unregistered"
    for repo in remote:
        repo["local_paths"] = [r["path"] for r in by_identity.get(repo["nameWithOwner"].lower(), [])]
        repo["coverage"] = "local" if repo["local_paths"] else "remote-only"
    data = {"local": local, "remote": remote, "sources": sources,
            "counts": {"local": len(local), "remote": len(remote),
                       "remote_only": sum(not r["local_paths"] for r in remote),
                       "unregistered_local": sum(r["source"] is None for r in local)}}
    args.output.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    args.output.write_text(json.dumps(data, indent=2) + "\n")
    print(json.dumps(data["counts"]))
    print(args.output)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.TimeoutExpired, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
