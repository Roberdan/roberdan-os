"""Owner-only files, descriptor-relative access and durable atomic replacement."""

import contextlib
import fcntl
import os
from pathlib import Path
import re
import stat
import uuid

from . import core

KEY = re.compile(r"[A-Za-z0-9._~+/=-]{8,512}\Z", re.ASCII)


def check_stat(info, directory=False, mode=None):
    correct_type = stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode)
    core.require(correct_type and info.st_uid == os.getuid(), "unsafe_private_path")
    if mode is not None:
        core.require(stat.S_IMODE(info.st_mode) == mode, "unsafe_private_permissions")
    else:
        core.require(not info.st_mode & 0o022, "unsafe_private_permissions")
    if not directory:
        core.require(info.st_nlink == 1, "unsafe_private_path")


class Area:
    def __init__(self, home, leaf):
        self.home = Path(home).absolute()
        core.require(".." not in self.home.parts, "unsafe_private_path")
        self.path = self.home / ".roberdan-os" / "private" / leaf
        self.fd = None

    def __enter__(self):
        # Inspect ancestors without reading their contents or invoking Git.
        for path in (self.path, *self.path.parents):
            core.require(not path.is_symlink(), "unsafe_private_path")
            core.require(not os.path.lexists(path / ".git"), "private_path_in_git")
            core.require(not ((path / "HEAD").exists() and (path / "objects").is_dir()
                              and (path / "refs").is_dir()), "private_path_in_git")
        check_stat(self.home.stat(), directory=True)
        descriptor = os.open(self.home, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            check_stat(os.fstat(descriptor), directory=True)
            for name, mode in ((".roberdan-os", None), ("private", 0o700),
                               (self.path.name, 0o700)):
                child = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                                dir_fd=descriptor)
                os.close(descriptor)
                descriptor = child
                check_stat(os.fstat(descriptor), directory=True, mode=mode)
            self.fd = descriptor
        except (OSError, core.JevError):
            os.close(descriptor)
            raise
        return self

    def __exit__(self, *_):
        os.close(self.fd)
        self.fd = None

    def open(self, name, flags=os.O_RDONLY, create=False):
        descriptor = os.open(name, flags | os.O_NOFOLLOW | os.O_NONBLOCK |
                             (os.O_CREAT if create else 0), 0o600, dir_fd=self.fd)
        try:
            check_stat(os.fstat(descriptor), mode=0o600)
        except core.JevError:
            os.close(descriptor)
            raise
        return descriptor

    def read(self, name, limit=core.MAX_RESPONSE_BYTES):
        descriptor = self.open(name)
        with os.fdopen(descriptor, "rb") as stream:
            raw = stream.read(limit + 1)
        core.require(len(raw) <= limit, "private_file_too_large")
        return raw

    def write(self, name, value):
        temporary = f".jev-{uuid.uuid4().hex}.tmp"
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL |
                             os.O_NOFOLLOW, 0o600, dir_fd=self.fd)
        try:
            with os.fdopen(descriptor, "wb") as stream:
                stream.write(core.canonical(value))
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, name, src_dir_fd=self.fd, dst_dir_fd=self.fd)
            os.fsync(self.fd)
        finally:
            try:
                os.unlink(temporary, dir_fd=self.fd)
            except FileNotFoundError:
                pass

    @contextlib.contextmanager
    def locked(self):
        descriptor = self.open("lock", os.O_RDWR, create=True)
        try:
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise core.JevError("busy") from None
            yield descriptor
        finally:
            os.close(descriptor)


def credential(home, environ):
    value = environ.get("TYPESAFE_API_KEY")
    if value is None:
        try:
            with Area(home, "credentials") as area:
                raw = area.read("typesafe.env", 4096).decode("utf-8")
        except FileNotFoundError:
            raise core.JevError("missing_credential") from None
        except UnicodeError:
            raise core.JevError("invalid_credential_file") from None
        lines = [line.strip() for line in raw.splitlines()
                 if line.strip() and not line.lstrip().startswith("#")]
        core.require(len(lines) == 1 and lines[0].startswith("TYPESAFE_API_KEY="),
                     "invalid_credential_file")
        value = lines[0].split("=", 1)[1]
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
    core.require(type(value) is str and KEY.fullmatch(value), "invalid_credential")
    return value
