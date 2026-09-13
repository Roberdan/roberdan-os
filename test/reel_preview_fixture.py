"""Generated local footage shared by optional renderer tests."""

import importlib
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / "skills/optional/instagram-reel-preview"
sys.path.insert(0, str(SKILL))
graphics = importlib.import_module("graphics")
render = importlib.import_module("render")
storage = importlib.import_module("storage")


class PreviewFixture(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("ffmpeg"):
            raise RuntimeError("Tests require ffmpeg on PATH (no downloads performed)")
        candidates = [
            os.environ.get("REEL_PREVIEW_TEST_FONT", ""),
            "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        ]
        cls.font = next((p for p in candidates if p and Path(p).is_file()), None)
        if not cls.font:
            raise RuntimeError("Set REEL_PREVIEW_TEST_FONT to a local TTF/OTF font")
        cls.workspace = tempfile.TemporaryDirectory()
        cls.root = Path(cls.workspace.name)
        cls.photo = cls.root / "synthetic.png"
        image = Image.new("RGB", (360, 640), (45, 93, 111))
        draw = ImageDraw.Draw(image)
        draw.ellipse((90, 95, 270, 305), fill=(231, 182, 137))
        draw.ellipse((130, 175, 144, 189), fill="black")
        draw.ellipse((216, 175, 230, 189), fill="black")
        draw.arc((140, 208, 220, 263), 0, 180, fill="black", width=4)
        draw.rectangle((80, 320, 280, 639), fill=(131, 54, 101))
        image.save(cls.photo)
        cls.video = cls.root / "synthetic.mp4"
        subprocess.run(
            [
                "ffmpeg",
                "-hide_banner",
                "-loglevel",
                "error",
                "-nostdin",
                "-loop",
                "1",
                "-i",
                str(cls.photo),
                "-t",
                "1",
                "-r",
                "5",
                "-pix_fmt",
                "yuv420p",
                str(cls.video),
            ],
            check=True,
        )
        cls.video_hash = storage.sha256(cls.video)

    @classmethod
    def tearDownClass(cls):
        cls.workspace.cleanup()

    def setUp(self):
        self.output = tempfile.TemporaryDirectory(dir=self.root)
        self.addCleanup(self.output.cleanup)
        self.config = dict(
            video=str(self.video),
            timestamp=0.2,
            title_lines=["A SMALL CHANGE.", "WHAT NEXT?"],
            subtitle="A synthetic rendering example.",
            display_name="Sample",
            font=self.font,
            output_dir=self.output.name,
            output_name="preview.jpg",
        )
