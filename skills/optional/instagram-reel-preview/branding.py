"""Approved publisher identity; no network access or synthetic FTS replacement."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

FTS_PUBLISHER = "fightthestroke"
FTS_LOGO_URL = (
    "https://images.squarespace-cdn.com/content/v1/53f10f3ae4b0124ec1e3a087/"
    "2820f1f0-227f-4f45-9109-b00e56b9d0ba/logo-rgb-10years-fts.png?format=1500w"
)
FTS_LOGO_SHA256 = "c85db1c75d484e54acf1373c5750909fc8a27929135148c99faa65df07b8d40b"


def validate_publisher(config: dict) -> None:
    publisher = config.get("publisher")
    if not isinstance(publisher, str) or not publisher.strip():
        raise ValueError("publisher must be an explicit nonempty account name")
    if publisher.casefold() == FTS_PUBLISHER:
        config["publisher"] = FTS_PUBLISHER
        if config.get("avatar"):
            raise ValueError(
                "FTS uses only its approved publisher_logo, never an avatar"
            )
        if not config.get("publisher_logo"):
            raise ValueError(
                "FTS requires --publisher-logo pointing to the approved actual logo; "
                "see SKILL.md for the pinned URL/hash and safe local cache instructions. "
                "Another publisher requires an explicit --publisher."
            )


def read_logo(path: Path, publisher: str, digest: str) -> Image.Image:
    if publisher == FTS_PUBLISHER and digest != FTS_LOGO_SHA256:
        raise ValueError(
            "FTS logo SHA-256 does not match the approved original; do not substitute, "
            "redraw or convert it. Download the pinned source or request renewed approval."
        )
    with Image.open(path) as image:
        return ImageOps.exif_transpose(image).convert("RGBA")


def place_logo(image: Image.Image, logo: Image.Image, box: tuple) -> tuple:
    """Contain every logo pixel; composite original colors on a white backing."""
    left, top, right, bottom = box
    thumb = ImageOps.contain(
        logo, (right - left, bottom - top), Image.Resampling.LANCZOS
    )
    x = left + (right - left - thumb.width) // 2
    y = top + (bottom - top - thumb.height) // 2
    ImageDraw.Draw(image).rectangle(box, fill="white")
    image.paste(thumb, (x, y), thumb.getchannel("A"))
    return x, y, x + thumb.width, y + thumb.height
