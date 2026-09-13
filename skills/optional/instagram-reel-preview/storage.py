"""Read-only local sources and provenance-checked output publication."""

import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageOps

GENERATOR = "instagram-reel-preview/v1"


def local_file(value: str) -> Path:
    path = Path(value).expanduser().resolve(strict=True)
    if not path.is_file():
        raise ValueError(f"Not a local regular file: {value}")
    return path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_image(path: Path) -> Image.Image:
    with Image.open(path) as image:
        return ImageOps.exif_transpose(image).convert("RGB")


def read_frame(path: Path, timestamp: float) -> Image.Image:
    executable = shutil.which("ffmpeg")
    if not executable:
        raise ValueError("ffmpeg missing: install ffmpeg locally and put it on PATH")
    # Local file/pipe only, including nested protocols; never resolve remote playlists.
    result = subprocess.run(
        [
            executable,
            "-hide_banner",
            "-loglevel",
            "error",
            "-nostdin",
            "-protocol_whitelist",
            "file,pipe",
            "-ss",
            str(timestamp),
            "-i",
            str(path),
            "-frames:v",
            "1",
            "-f",
            "image2pipe",
            "-vcodec",
            "png",
            "pipe:1",
        ],
        capture_output=True,
        timeout=120,
        check=False,
    )
    if result.returncode or not result.stdout:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise ValueError(
            f"Cannot extract frame at {timestamp}s (past end or bad video): "
            f"{detail or 'no video frame returned'}"
        )
    with Image.open(io.BytesIO(result.stdout)) as image:
        return image.convert("RGB")


def output_paths(directory: str, name: str, sources: list[Path]) -> tuple[Path, Path]:
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*\.jpg", name):
        raise ValueError("output_name must be a safe basename ending in .jpg")
    parent = Path(directory).expanduser().resolve()
    output, manifest = parent / name, parent / f"{name}.json"
    for path in (output, manifest):
        if path.is_symlink() or path.resolve() in sources:
            raise ValueError(f"Output must not alias an input or symlink: {path}")
        if path.exists() and any(os.path.samefile(path, source) for source in sources):
            raise ValueError(f"Output is a hard link to an input: {path}")
    return output, manifest


def check_destination(output: Path, manifest: Path, revise: bool) -> None:
    if not output.exists() and not manifest.exists():
        return
    if not revise:
        raise ValueError(
            f"Output exists: {output}; use a new name or explicit --revise"
        )
    if not output.is_file() or not manifest.is_file():
        raise ValueError("Refusing revision without both generated image and manifest")
    old = json.loads(manifest.read_text(encoding="utf-8"))
    if (
        not isinstance(old, dict)
        or old.get("generator") != GENERATOR
        or old.get("output_name") != output.name
        or old.get("output_sha256") != sha256(output)
    ):
        raise ValueError("Refusing revision: output is not an unchanged generated file")


def publish(
    image: Image.Image,
    output: Path,
    manifest: Path,
    metadata: dict,
    sources: dict[Path, str],
    revise: bool,
) -> dict:
    for path, expected in sources.items():
        if sha256(path) != expected:
            raise ValueError(f"Input changed during rendering: {path}")
    check_destination(output, manifest, revise)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix=".reel-preview-", dir=output.parent
    ) as temp:
        staged = Path(temp) / output.name
        image.convert("RGB").save(
            staged, "JPEG", quality=96, subsampling=0, dpi=(72, 72)
        )
        with Image.open(staged) as check:
            check.load()
            if check.size != (1080, 1920) or check.mode != "RGB":
                raise ValueError("Generated JPEG failed dimension/RGB validation")
        metadata.update(
            generator=GENERATOR,
            output_name=output.name,
            output_sha256=sha256(staged),
            sources=[{"path": str(p), "sha256": h} for p, h in sources.items()],
        )
        staged_manifest = Path(temp) / manifest.name
        staged_manifest.write_text(
            json.dumps(metadata, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
        # Reserve a per-output lock, never take over another render's lock.
        lock = output.parent / f".{output.name}.lock"
        descriptor = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        try:
            os.close(descriptor)
            output_paths(str(output.parent), output.name, list(sources))
            check_destination(output, manifest, revise)
            if revise and output.exists():
                os.replace(staged, output)
                os.replace(staged_manifest, manifest)
            else:
                os.link(staged, output)
                os.link(staged_manifest, manifest)
        finally:
            lock.unlink()
    return metadata
