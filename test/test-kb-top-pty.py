#!/usr/bin/env python3
"""Exercise the real dashboard loop through a resizable Unix terminal."""

import fcntl
import os
from pathlib import Path
import pty
import re
import select
import signal
import struct
import subprocess
import tempfile
import termios
import time
import unicodedata
import unittest


ROOT = Path(__file__).resolve().parents[1]
CSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")


def cells(text):
    return sum(
        0
        if unicodedata.combining(c)
        else 2
        if unicodedata.east_asian_width(c) in ("W", "F")
        else 1
        for c in text
    )


class DashboardTerminalTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="kb-top-pty-")
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        repo = self.home / "demo"
        repo.mkdir()
        env = dict(os.environ, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1")
        for args in (
            ["init", "-q", "-b", "main"],
            [
                "-c",
                "user.name=Test",
                "-c",
                "user.email=test@example.com",
                "-c",
                "core.hooksPath=/dev/null",
                "commit",
                "-q",
                "--allow-empty",
                "-m",
                "base",
            ],
        ):
            subprocess.run(["git", "-C", str(repo), *args], check=True, env=env)
        self.worktree = self.home / "terminal-resize-worktree-name"
        subprocess.run(
            [
                "git",
                "-C",
                str(repo),
                "worktree",
                "add",
                "-q",
                "-b",
                "terminal-resize-branch",
                str(self.worktree),
            ],
            check=True,
            env=env,
        )
        self.snap = self.home / "snapshot"
        self.write_snapshot("first observation")
        env.update(
            TERM="xterm-256color",
            RDA_HOME=str(self.home),
            RDA_TOP_SNAP=str(self.snap),
            RDA_TOP_REFRESH="3600",
            RDA_TOP_NO_COLOR="1",
        )
        for key in ("COLUMNS", "LINES", "RDA_TOP_WIDTH", "RDA_TOP_HEIGHT"):
            env.pop(key, None)
        self.master, slave = pty.openpty()
        self.addCleanup(os.close, self.master)
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 40, 0, 0))
        self.original_termios = termios.tcgetattr(slave)

        try:
            self.process = subprocess.Popen(
                ["/bin/bash", str(ROOT / "kanban/top.sh")],
                cwd=self.worktree,
                env=env,
                stdin=slave,
                stdout=slave,
                stderr=slave,
                start_new_session=True,
            )
        finally:
            os.close(slave)
        self.addCleanup(self.stop)
        self.buffer = b""
        self.transcript = b""

    def stop(self):
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.await_exit()
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.await_exit()

    def await_exit(self):
        deadline = time.monotonic() + 5
        while self.process.poll() is None and time.monotonic() < deadline:
            self.receive(0.05)
        if self.process.poll() is None:
            raise subprocess.TimeoutExpired(self.process.args, 5)
        return self.process.returncode

    def write_snapshot(self, marker):
        data = {
            "ts": int(time.time()),
            "dirty": 0,
            "card_doing": 1,
            "card_todo": 0,
            "card": f"C1|{marker}|{int(time.time())}",
            "agenti": 0,
            "unpushed": 0,
            "worktrees": 1,
            "bus": 0,
            "richieste_oggi": 0,
            "unita_oggi": "-",
            "ask": "corso|Check terminal rendering during resize",
        }
        self.snap.write_text(
            "".join(f"{key}\t{value}\n" for key, value in data.items())
        )

    def receive(self, timeout):
        if select.select([self.master], [], [], timeout)[0]:
            try:
                chunk = os.read(self.master, 65536)
            except OSError as error:
                if error.errno != 5:
                    raise
                return
            self.buffer += chunk
            self.transcript += chunk

    def frame(self, marker=None):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if b"\x1b[H" in self.buffer and b"\x1b[J" in self.buffer:
                _, rest = self.buffer.split(b"\x1b[H", 1)
                if b"\x1b[J" in rest:
                    raw, self.buffer = rest.split(b"\x1b[J", 1)
                    text = CSI.sub("", raw.decode()).replace("\r", "")
                    if marker is None or marker in text:
                        return text
            self.receive(0.2)
        self.fail(f"No complete dashboard frame: {self.transcript[-1000:]!r}")

    def assert_frame(self, frame, columns, rows):
        lines = frame.splitlines()
        self.assertLessEqual(len(lines), rows - 1, frame)
        self.assertLessEqual(max(map(cells, lines)), columns - 1, frame)
        self.assertIn("─" * (columns - 1), lines, frame)
        self.assertNotIn("unbound variable", frame)

    def resize(self, columns, rows, marker):
        fcntl.ioctl(
            self.master, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0)
        )
        os.kill(self.process.pid, signal.SIGWINCH)
        self.write_snapshot(marker)
        return self.frame(marker)

    def test_live_resize_redraw_and_exit(self):
        self.assert_frame(self.frame("first observation"), 40, 40)
        self.assert_frame(self.resize(24, 40, "narrow"), 24, 40)
        self.assert_frame(self.resize(60, 40, "expanded"), 60, 40)
        self.assert_frame(self.resize(40, 12, "short"), 40, 12)
        self.assert_frame(self.frame("short"), 40, 12)
        deadline = time.monotonic() + 3
        while termios.tcgetattr(self.master)[3] & termios.ICANON:
            self.assertLess(
                time.monotonic(), deadline, "dashboard never reads its keyboard"
            )
            time.sleep(0.01)
        os.write(self.master, b"q")
        self.assertEqual(self.await_exit(), 0)
        self.receive(0.2)
        self.assertIn(b"\x1b[?25h", self.transcript)
        self.assertEqual(self.transcript.count(b"\x1b[2J"), 1)
        self.assertEqual(termios.tcgetattr(self.master), self.original_termios)
        print(
            "PASS: live PTY 40 -> 24 -> 60 columns, 12 rows, repeated redraw, q, termios"
        )


if __name__ == "__main__":
    unittest.main()
