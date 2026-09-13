"""Local drawing primitives; every text region has a hard bounding box."""

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

SIZE = (1080, 1920)
INK = (17, 22, 24)
WHITE = (250, 249, 241)
ACCENT = (218, 255, 98)
MARGIN = {"left": 48, "right": 48, "top": 85, "bottom": 86}


def gradient(size: tuple[int, int]) -> Image.Image:
    colors = [
        (255, 214, 107),
        (255, 135, 53),
        (241, 48, 114),
        (196, 39, 161),
        (112, 56, 213),
        (73, 87, 223),
    ]
    small = Image.new("RGB", (64, 96))
    for y in range(96):
        for x in range(64):
            t = (0.65 * (1 - y / 95) + 0.35 * x / 63) * (len(colors) - 1)
            index = min(int(t), len(colors) - 2)
            small.putpixel(
                (x, y),
                tuple(
                    round(a + (b - a) * (t - index))
                    for a, b in zip(colors[index], colors[index + 1])
                ),
            )
    return small.resize(size, Image.Resampling.BICUBIC)


class Typography:
    def __init__(self, font: str, sans: str):
        self.font = font
        self.sans = sans
        self.regions: list[dict] = []

    def text(
        self,
        image: Image.Image,
        label: str,
        box: tuple,
        size: int,
        minimum: int,
        fill=WHITE,
        body: bool = False,
    ) -> tuple:
        draw = ImageDraw.Draw(image)
        for point_size in range(size, minimum - 1, -1):
            font = ImageFont.truetype(self.sans if body else self.font, point_size)
            bounds = draw.textbbox(box[:2], label, font=font, anchor="lt")
            if (
                bounds[0] >= box[0]
                and bounds[1] >= box[1]
                and bounds[2] <= box[2]
                and bounds[3] <= box[3]
            ):
                draw.text(box[:2], label, font=font, anchor="lt", fill=fill)
                self.regions.append(
                    {
                        "text": label,
                        "bounds": list(bounds),
                        "region": list(box),
                        "font_size": point_size,
                    }
                )
                return bounds
        raise ValueError(
            f"Text overflow: {label!r}; shorten it or supply a narrower font"
        )


def reels_icon(draw: ImageDraw.ImageDraw, x: int, y: int) -> None:
    draw.rounded_rectangle((x, y, x + 63, y + 63), radius=13, outline="white", width=5)
    draw.line((x + 3, y + 20, x + 60, y + 20), fill="white", width=5)
    for offset in (17, 39):
        draw.line((x + offset, y + 1, x + offset + 12, y + 19), fill="white", width=5)
    draw.polygon([(x + 25, y + 31), (x + 25, y + 52), (x + 43, y + 41)], fill="white")


def cover(photo: Image.Image, config: dict, typeface: Typography) -> Image.Image:
    focus = (config["focus_x"], config["focus_y"])
    image = ImageOps.fit(photo, SIZE, centering=focus).filter(
        ImageFilter.GaussianBlur(40)
    )
    if config["photo_fit"] == "contain":
        # Preserve the entire selected frame above the copy, without distortion.
        foreground = ImageOps.contain(photo, (1008, 760), Image.Resampling.LANCZOS)
        image.paste(
            foreground,
            ((1080 - foreground.width) // 2, 240 + (760 - foreground.height) // 2),
        )
    else:
        image = ImageOps.fit(photo, SIZE, Image.Resampling.LANCZOS, centering=focus)
    overlay = Image.new("RGBA", SIZE)
    draw = ImageDraw.Draw(overlay)
    for y in range(1920):
        lower = max(0, min(1, (y - 850) / 600))
        upper = max(0, 1 - y / 500) * 0.75
        draw.line((0, y, 1080, y), fill=(*INK, round(255 * max(lower * 0.985, upper))))
    image = Image.alpha_composite(image.convert("RGBA"), overlay).convert("RGB")
    if config.get("project_label"):
        typeface.text(
            image, config["project_label"], (80, 130, 700, 220), 36, 24, body=True
        )
    badge = gradient((270, 116))
    image.paste(badge, (734, 120))
    reels_icon(ImageDraw.Draw(image), 752, 145)
    typeface.text(image, config["reels_label"], (830, 159, 992, 202), 30, 20, body=True)
    name = config["display_name"]
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((78, 1010, 1002, 1080), radius=12, fill=ACCENT)
    typeface.text(image, name, (100, 1027, 980, 1068), 31, 24, INK, True)
    lines = config["title_lines"]
    line_height = 145 if len(lines) <= 2 else 108
    for index, line in enumerate(lines):
        y = 1120 + index * line_height
        typeface.text(
            image,
            line,
            (78, y, 1002, y + line_height - 12),
            132 if len(lines) <= 2 else 96,
            48,
            WHITE if index == 0 else ACCENT,
        )
    typeface.text(image, config["subtitle"], (80, 1485, 1000, 1545), 34, 24, body=True)
    draw = ImageDraw.Draw(image)
    draw.line((80, 1588, 1000, 1588), fill=(80, 88, 77), width=2)
    draw.ellipse((80, 1630, 145, 1695), fill=ACCENT)
    draw.polygon([(106, 1648), (106, 1677), (128, 1663)], fill=INK)
    typeface.text(image, config["cta"], (166, 1645, 1000, 1700), 32, 24, body=True)
    mask = Image.new("L", SIZE, 0)
    ImageDraw.Draw(mask).rounded_rectangle((36, 36, 1043, 1883), radius=66, fill=255)
    image = Image.composite(image, gradient(SIZE), mask)
    card = image.resize((984, 1749), Image.Resampling.LANCZOS)
    output = Image.new("RGB", SIZE, "white")
    output.paste(card, (48, 85))
    return output


def actions(draw: ImageDraw.ImageDraw) -> None:
    # Outline-only controls: no fabricated engagement or verification signals.
    draw.line(
        [
            (79, 1767),
            (53, 1742),
            (48, 1728),
            (53, 1716),
            (66, 1712),
            (79, 1722),
            (92, 1712),
            (105, 1716),
            (110, 1728),
            (105, 1742),
            (79, 1767),
        ],
        fill=INK,
        width=5,
        joint="curve",
    )
    draw.rounded_rectangle((147, 1713, 205, 1758), radius=16, outline=INK, width=5)
    draw.line([(163, 1757), (150, 1770), (150, 1748)], fill=INK, width=5)
    draw.line(
        [
            (241, 1715),
            (305, 1715),
            (276, 1770),
            (268, 1745),
            (241, 1715),
            (305, 1715),
            (268, 1745),
        ],
        fill=INK,
        width=5,
    )
    draw.line(
        [
            (982, 1713),
            (1026, 1713),
            (1026, 1770),
            (1004, 1753),
            (982, 1770),
            (982, 1713),
        ],
        fill=INK,
        width=5,
    )


def post(
    card: Image.Image, config: dict, typeface: Typography, avatar: Image.Image | None
) -> tuple[Image.Image, dict]:
    output = Image.new("RGB", SIZE, "white")
    draw = ImageDraw.Draw(output)
    if avatar is None:
        draw.ellipse((48, 61, 124, 137), outline=INK, width=3)
        draw.ellipse((75, 76, 97, 98), outline=INK, width=3)
        draw.arc((60, 99, 112, 143), 185, 355, fill=INK, width=3)
    else:
        thumb = ImageOps.fit(avatar, (76, 76), Image.Resampling.LANCZOS)
        mask = Image.new("L", (76, 76), 0)
        ImageDraw.Draw(mask).ellipse((0, 0, 75, 75), fill=255)
        output.paste(thumb, (48, 61), mask)
    typeface.text(
        output, config["display_name"], (148, 65, 945, 110), 34, 24, INK, True
    )
    if config.get("project_label"):
        typeface.text(
            output, config["project_label"], (148, 117, 945, 154), 26, 20, INK, True
        )
    draw = ImageDraw.Draw(output)
    for x in (986, 1005, 1024):
        draw.ellipse((x, 89, x + 7, 96), fill=INK)
    # Contain, never fit: the WHOLE cover including its text and border survives.
    resized = ImageOps.contain(card, (984, 1480), Image.Resampling.LANCZOS)
    x, y = (1080 - resized.width) // 2, 190 + (1480 - resized.height) // 2
    output.paste(resized, (x, y))
    actions(ImageDraw.Draw(output))
    return output, {
        "bounds": [x, y, x + resized.width, y + resized.height],
        "source_size": list(card.size),
        "scaled_size": list(resized.size),
        "fit": "contain",
    }
