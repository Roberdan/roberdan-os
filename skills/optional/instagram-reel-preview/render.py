#!/usr/bin/env python3
"""Render one local 1080x1920 RGB JPEG with a source-hash provenance sidecar."""

import argparse
import json
import math
import subprocess
import sys
from pathlib import Path

try:
    from PIL import ImageFont
except ImportError:
    sys.exit(
        "Pillow missing. Install requirements.txt beside this script into your "
        "chosen Python environment; no dependencies are installed automatically."
    )

from graphics import MARGIN, Typography, cover, post
from storage import (
    check_destination,
    local_file,
    output_paths,
    publish,
    read_frame,
    read_image,
    sha256,
)

DEFAULTS = {
    "style": "reel-cover",
    "locale": "en",
    "photo_fit": "cover",
    "focus_x": 0.5,
    "focus_y": 0.5,
}
FIELDS = {
    "style",
    "video",
    "cover_input",
    "timestamp",
    "title_lines",
    "subtitle",
    "display_name",
    "project_label",
    "font",
    "sans_font",
    "avatar",
    "locale",
    "cta",
    "reels_label",
    "output_dir",
    "output_name",
    "photo_fit",
    "focus_x",
    "focus_y",
}


def parse_config() -> tuple[dict, bool, Path | None]:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="JSON; paths relative to this file")
    parser.add_argument(
        "--revise",
        action="store_true",
        help="Explicitly revise only an unchanged generated output",
    )
    for name in sorted(FIELDS - {"title_lines", "timestamp", "focus_x", "focus_y"}):
        parser.add_argument("--" + name.replace("_", "-"))
    parser.add_argument("--title-line", action="append", dest="title_lines")
    for name in ("timestamp", "focus_x", "focus_y"):
        parser.add_argument("--" + name.replace("_", "-"), type=float)
    args = vars(parser.parse_args())
    file = args.pop("config")
    revise = args.pop("revise")
    config = {}
    if file:
        file = file.expanduser().resolve(strict=True)
        config = json.loads(file.read_text(encoding="utf-8"))
        if not isinstance(config, dict) or set(config) - FIELDS:
            raise ValueError("Config must be an object with documented keys only")
        for key in (
            "video",
            "cover_input",
            "font",
            "sans_font",
            "avatar",
            "output_dir",
        ):
            if key in config and isinstance(config[key], str):
                path = Path(config[key]).expanduser()
                config[key] = str(path if path.is_absolute() else file.parent / path)
    config.update({key: value for key, value in args.items() if value is not None})
    return {**DEFAULTS, **config}, revise, file


def validate(config: dict) -> None:
    if set(config) - FIELDS:
        raise ValueError("Unknown configuration keys")
    if config.get("style") not in ("reel-cover", "instagram-post"):
        raise ValueError("style must be reel-cover or instagram-post")
    if config.get("photo_fit") not in ("cover", "contain"):
        raise ValueError("photo_fit must be cover or contain")
    if bool(config.get("video")) == bool(config.get("cover_input")):
        raise ValueError("Supply exactly one local video or cover_input")
    if config.get("cover_input") and config["style"] != "instagram-post":
        raise ValueError("cover_input is supported only by instagram-post")
    required = ["display_name", "font", "output_dir", "output_name", "locale"]
    if config.get("video"):
        required += ["subtitle"]
    for key in required:
        if not isinstance(config.get(key), str) or not config[key].strip():
            raise ValueError(f"{key} is required and must be a nonempty string")
    for key in (
        "video",
        "cover_input",
        "sans_font",
        "avatar",
        "project_label",
        "subtitle",
        "cta",
        "reels_label",
    ):
        if key in config and (
            not isinstance(config[key], str) or not config[key].strip()
        ):
            raise ValueError(f"{key} must be a nonempty string")
    if config.get("avatar") and config["style"] != "instagram-post":
        raise ValueError("avatar requires instagram-post")
    if config["locale"].lower().split("-")[0] != "en" and config.get("video"):
        if not config.get("cta") or not config.get("reels_label"):
            raise ValueError(
                "Non-English covers require translated cta and reels_label"
            )
    config.setdefault("cta", "WATCH THE VIDEO")
    config.setdefault("reels_label", "REELS")
    for key, value in config.items():
        if isinstance(value, str) and any(ord(char) < 32 for char in value):
            raise ValueError(
                f"{key} contains control characters; use separate title_lines"
            )
    for key in ("focus_x", "focus_y"):
        value = config.get(key)
        if (
            type(value) not in (float, int)
            or not math.isfinite(value)
            or not 0 <= value <= 1
        ):
            raise ValueError(f"{key} must be finite and between 0 and 1")
    if config.get("video"):
        time = config.get("timestamp")
        if type(time) not in (float, int) or not math.isfinite(time) or time < 0:
            raise ValueError("timestamp must be explicit, finite, nonnegative seconds")
        lines = config.get("title_lines")
        if not isinstance(lines, list) or not 1 <= len(lines) <= 3:
            raise ValueError("title_lines must contain 1-3 short editorial lines")
        if any(
            not isinstance(line, str)
            or not line.strip()
            or any(ord(char) < 32 for char in line)
            for line in lines
        ):
            raise ValueError("Each title line must be nonempty text without controls")
    elif any(key in config for key in ("title_lines", "subtitle", "timestamp")):
        raise ValueError(
            "Existing covers preserve their copy; omit title/subtitle/timestamp"
        )


def render(config: dict, revise: bool = False, config_file: Path | None = None) -> dict:
    config = {**DEFAULTS, **config}
    validate(config)
    paths = {}
    for key in ("video", "cover_input", "font", "sans_font", "avatar"):
        if config.get(key):
            paths[key] = local_file(config[key])
    if config_file:
        paths["config"] = local_file(str(config_file))
    for key in ("font", "sans_font"):
        if key in paths:
            try:
                ImageFont.truetype(str(paths[key]), 32)
            except OSError as error:
                raise ValueError(
                    f"Cannot load {key}: {paths[key]}; supply a TTF/OTF font"
                ) from error
    sources = {path: sha256(path) for path in paths.values()}
    output, manifest = output_paths(
        config["output_dir"], config["output_name"], list(sources)
    )
    check_destination(output, manifest, revise)
    typeface = Typography(
        str(paths["font"]), str(paths.get("sans_font", paths["font"]))
    )
    metadata = {
        "style": config["style"],
        "size": [1080, 1920],
        "mode": "RGB",
        "locale": config["locale"],
        "official_embed": False,
        "engagement_counts": None,
    }
    if "video" in paths:
        photo = read_frame(paths["video"], config["timestamp"])
        card = cover(photo, config, typeface)
        metadata.update(
            timestamp=config["timestamp"],
            photo_fit=config["photo_fit"],
            focus=[config["focus_x"], config["focus_y"]],
            cover_outer_margin=MARGIN,
            cover_text_transform={
                "scale_x": 984 / 1080,
                "scale_y": 1749 / 1920,
                "translate": [48, 85],
            },
        )
    else:
        card = read_image(paths["cover_input"])
    cover_regions = typeface.regions
    typeface.regions = []
    if config["style"] == "instagram-post":
        avatar = read_image(paths["avatar"]) if "avatar" in paths else None
        card, placement = post(card, config, typeface, avatar)
        metadata["cover_placement"] = placement
        metadata["controls"] = ["ellipsis", "heart", "comment", "share", "bookmark"]
    metadata["cover_text_regions"] = cover_regions
    metadata["wrapper_text_regions"] = typeface.regions
    return publish(card, output, manifest, metadata, sources, revise)


def main() -> int:
    try:
        config, revise, file = parse_config()
        print(json.dumps(render(config, revise, file), indent=2, ensure_ascii=False))
    except (OSError, ValueError, TypeError, subprocess.TimeoutExpired) as error:
        print(f"reel-preview: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
