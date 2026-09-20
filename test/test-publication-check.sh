#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHONDONTWRITEBYTECODE=1 python3 - "$ROOT" <<'PY'
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

script = Path(sys.argv[1]) / "bin/publication-check.sh"
bash, git = shutil.which("bash"), shutil.which("git")
with tempfile.TemporaryDirectory(prefix="publication-check-") as temp:
    root = Path(temp).resolve()
    repo, tools, absent = (root / name for name in ("repo", "tools", "absent"))
    for directory in (repo, tools, absent):
        directory.mkdir()
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(("GIT_", "GITLEAKS_"))}
    env.update(PATH=str(tools) + os.pathsep + env.get("PATH", ""),
               SCAN_LOG=str(root / "scan.log"), SCAN_RC="0")
    def g(*args):
        return subprocess.check_output([git, "-C", str(repo), *args], env=env, text=True).strip()
    g("init", "-q")
    g("config", "user.name", "Synthetic Test")
    g("config", "user.email", "test@example.invalid")
    g("config", "core.hooksPath", str(root / "no-hooks"))
    (repo / "file.txt").write_text("base\n")
    g("add", "file.txt")
    g("commit", "-qm", "base")
    base = g("rev-parse", "HEAD")
    (repo / "file.txt").write_text("change\n")
    g("commit", "-qam", "change")
    head = g("rev-parse", "HEAD")
    scanner = tools / "gitleaks"
    scanner.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$SCAN_LOG"\n'
                       'if [ "${CHANGE_HEAD:-0}" = 1 ]; then git commit --allow-empty -qm changed; fi\n'
                       'exit "$SCAN_RC"\n')
    scanner.chmod(0o700)
    def run(args, expected=2, environment=None, cwd=None):
        result = subprocess.run([bash, str(script), *args], cwd=cwd or repo,
                                env=environment or env, capture_output=True, text=True, timeout=15)
        assert result.returncode == expected, (result.returncode, result.stdout, result.stderr)
        return result
    run([])
    run([base], cwd=root)
    run(["--all"])
    run(["unknown-ref"])
    run([head])
    result = run([base], expected=0)
    assert "NOT disclosure or publication authorization" in result.stdout
    arguments = (root / "scan.log").read_text().splitlines()
    for item in ("git", "--redact", "--ignore-gitleaks-allow", "--timeout", "60",
                 f"--log-opts={base}..{head}", str(repo)):
        assert item in arguments, (item, arguments)
    for code in (1, 7):
        result = run([base], expected=code, environment={**env, "SCAN_RC": str(code)})
        assert "BLOCKED" in result.stderr and "do not publish" in result.stderr
    (absent / "git").symlink_to(git)
    result = run([base], environment={**env, "PATH": str(absent)})
    assert "gitleaks unavailable" in result.stderr
    (repo / "file.txt").write_text("uncommitted\n")
    result = run([base])
    assert "uncommitted" in result.stderr
    g("add", "file.txt")
    run([base])
    g("commit", "-qm", "reviewed")
    result = run([base], environment={**env, "CHANGE_HEAD": "1"})
    assert "HEAD changed" in result.stderr
    # Removing the executable scanner must refuse, not silently pass.
    scanner.unlink()
    run([base], environment={**env, "PATH": str(absent)})
print("test-publication-check: PASS (positive scan, missing scanner, failures, dirty state, changed HEAD)")
PY
