"""Real local rendering tests using generated media only."""

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

from PIL import Image, ImageChops, ImageDraw, ImageOps, ImageStat
from reel_preview_fixture import ROOT, SKILL, PreviewFixture, graphics, render, storage


class PreviewTests(PreviewFixture):

    def test_cover_dimensions_whitespace_text_source_and_revision(self):
        result = render.render(self.config)
        path = Path(self.output.name) / "preview.jpg"
        with Image.open(path) as image:
            self.assertEqual((image.size, image.mode), ((1080, 1920), "RGB"))
            for box in [(0, 0, 40, 1920), (1040, 0, 1080, 1920), (0, 0, 1080, 80)]:
                self.assertEqual(image.crop(box).getextrema(), ((255, 255),) * 3)
            pair = Image.new("RGB", (2160, 1920))
            pair.paste(image, (0, 0))
            pair.paste(image, (1080, 0))
            self.assertEqual(
                pair.crop((1040, 0, 1120, 1920)).getextrema(), ((255, 255),) * 3
            )
        self.assertEqual(result["cover_outer_margin"], graphics.MARGIN)
        self.assertEqual(result["sources"][0]["sha256"], self.video_hash)
        self.assertEqual(storage.sha256(self.video), self.video_hash)
        self.assertIn(
            "WATCH THE VIDEO", [r["text"] for r in result["cover_text_regions"]]
        )
        for region in result["cover_text_regions"]:
            a, b, c, d = region["bounds"]
            x, y, z, w = region["region"]
            self.assertTrue(x <= a <= c <= z and y <= b <= d <= w)
        before = path.read_bytes()
        with self.assertRaisesRegex(ValueError, "Output exists"):
            render.render(self.config)
        self.assertEqual(before, path.read_bytes())
        render.render(
            {**self.config, "subtitle": "An explicitly revised example."}, True
        )
        self.assertNotEqual(before, path.read_bytes())

    def test_exact_uncompressed_margins_and_gradient_border(self):
        config = {**render.DEFAULTS, **self.config}
        render.validate(config)
        image = graphics.cover(
            storage.read_image(self.photo),
            config,
            graphics.Typography(self.font, self.font),
        )
        difference = ImageChops.difference(image, Image.new("RGB", image.size, "white"))
        self.assertEqual(difference.getbbox(), (48, 85, 1032, 1834))
        self.assertNotEqual(image.getpixel((50, 90)), image.getpixel((1028, 1828)))
        pair = Image.new("RGB", (2160, 1920))
        pair.paste(image, (0, 0))
        pair.paste(image, (1080, 0))
        self.assertEqual(
            pair.crop((1032, 0, 1128, 1920)).getextrema(), ((255, 255),) * 3
        )

    def test_post_from_video_and_no_fake_text(self):
        result = render.render(
            {
                **self.config,
                "style": "instagram-post",
                "avatar": str(self.photo),
                "project_label": "Local demo",
            }
        )
        with Image.open(Path(self.output.name) / "preview.jpg") as image:
            self.assertEqual((image.size, image.mode), ((1080, 1920), "RGB"))
        text = [r["text"] for r in result["wrapper_text_regions"]]
        self.assertEqual(text, ["Sample", "Local demo"])
        self.assertIsNone(result["engagement_counts"])
        self.assertFalse(result["official_embed"])
        self.assertEqual(
            result["controls"], ["ellipsis", "heart", "comment", "share", "bookmark"]
        )
        self.assertEqual(result["cover_placement"]["fit"], "contain")
        self.assertLessEqual(result["cover_placement"]["bounds"][3], 1670)

    def test_existing_wide_cover_is_entirely_preserved(self):
        source = Path(self.output.name) / "wide.png"
        image = Image.new("RGB", (900, 400), (121, 140, 152))
        draw = ImageDraw.Draw(image)
        for box, color in [
            ((0, 0, 75, 75), "red"),
            ((824, 0, 899, 75), "green"),
            ((0, 324, 75, 399), "blue"),
            ((824, 324, 899, 399), "yellow"),
        ]:
            draw.rectangle(box, fill=color)
        image.save(source)
        before = source.read_bytes()
        result = render.render(
            dict(
                style="instagram-post",
                cover_input=str(source),
                display_name="Sample",
                font=self.font,
                output_dir=self.output.name,
                output_name="wrapped.jpg",
            )
        )
        bounds = result["cover_placement"]["bounds"]
        expected = ImageOps.contain(image, (984, 1480), Image.Resampling.LANCZOS)
        with Image.open(Path(self.output.name) / "wrapped.jpg") as output:
            actual = output.crop(bounds)
            self.assertEqual(actual.size, expected.size)
            self.assertLess(
                max(ImageStat.Stat(ImageChops.difference(actual, expected)).mean), 2
            )
        self.assertEqual(source.read_bytes(), before)

    def test_overflow_fails_without_output(self):
        for change in [
            {"title_lines": ["W" * 500]},
            {"subtitle": "W" * 500},
            {"display_name": "W" * 500},
            {"project_label": "W" * 500},
            {"cta": "W" * 500},
            {"reels_label": "W" * 500},
        ]:
            with self.subTest(change=next(iter(change))):
                with self.assertRaisesRegex(ValueError, "Text overflow"):
                    render.render({**self.config, **change})
                self.assertFalse((Path(self.output.name) / "preview.jpg").exists())

    def test_inputs_names_dependencies_and_locale_errors(self):
        for change, message in [
            ({"output_name": "../original.jpg"}, "safe basename"),
            ({"timestamp": float("nan")}, "timestamp"),
            ({"timestamp": 30}, "Cannot extract"),
            ({"focus_x": 2}, "focus_x"),
            ({"locale": "it"}, "translated"),
            ({"font": str(self.photo)}, "Cannot load"),
            ({"subtitle": "line\nbreak"}, "control"),
            ({"likes": 12}, "Unknown configuration"),
        ]:
            with self.subTest(change=change):
                with self.assertRaisesRegex(ValueError, message):
                    render.render({**self.config, **change})
        with patch.dict(os.environ, {"PATH": ""}):
            with self.assertRaisesRegex(ValueError, "ffmpeg missing"):
                storage.read_frame(self.video, 0.2)
        process = subprocess.run(
            [sys.executable, "-S", str(SKILL / "render.py"), "--help"],
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(process.returncode, 0)
        self.assertIn("Pillow missing", process.stderr)

    def test_refuses_original_tampered_generated_and_aliases(self):
        target = Path(self.output.name) / "preview.jpg"
        Image.new("RGB", (10, 10), "red").save(target)
        original = target.read_bytes()
        with self.assertRaisesRegex(ValueError, "both generated"):
            render.render(self.config, True)
        self.assertEqual(original, target.read_bytes())
        target.unlink()
        render.render(self.config)
        target.write_bytes(original)
        with self.assertRaisesRegex(ValueError, "unchanged generated"):
            render.render(self.config, True)
        target.unlink()
        target.symlink_to(self.photo)
        with self.assertRaisesRegex(ValueError, "symlink"):
            render.render(self.config, True)
        target.unlink()
        os.link(self.video, target)
        with self.assertRaisesRegex(ValueError, "hard link"):
            render.render(self.config, True)
        self.assertEqual(storage.sha256(self.video), self.video_hash)

    def test_source_change_is_detected_before_publication(self):
        source = Path(self.output.name) / "local.png"
        shutil.copyfile(self.photo, source)
        digest = storage.sha256(source)
        source.write_bytes(b"changed by another process")
        output = Path(self.output.name) / "new.jpg"
        with self.assertRaisesRegex(ValueError, "Input changed"):
            storage.publish(
                Image.new("RGB", (1080, 1920)),
                output,
                output.with_suffix(".jpg.json"),
                {},
                {source: digest},
                False,
            )
        self.assertFalse(output.exists())

    def test_installed_cli_with_config_relative_paths_and_translation(self):
        specification = importlib.util.spec_from_file_location(
            "optional_packager", ROOT / "bin/optional-skills.py"
        )
        packager = importlib.util.module_from_spec(specification)
        specification.loader.exec_module(packager)
        installed = packager.build(
            "instagram-reel-preview",
            Path(self.output.name) / "host",
            packager.catalog(),
            True,
        )
        config = Path(self.output.name) / "job.json"
        config.write_text(
            json.dumps(
                {
                    **self.config,
                    "video": "../synthetic.mp4",
                    "output_dir": ".",
                    "locale": "it",
                    "title_lines": ["UN CAMBIAMENTO.", "E POI?"],
                    "subtitle": "Un esempio sintetico.",
                    "cta": "GUARDA IL VIDEO",
                    "reels_label": "REEL",
                }
            )
        )
        process = subprocess.run(
            [
                sys.executable,
                str(installed / "render.py"),
                "--config",
                str(config),
                "--style",
                "instagram-post",
            ],
            cwd="/",
            capture_output=True,
            text=True,
        )
        self.assertEqual(process.returncode, 0, process.stderr)
        result = json.loads(process.stdout)
        self.assertEqual(result["style"], "instagram-post")
        self.assertIn(
            "GUARDA IL VIDEO", [r["text"] for r in result["cover_text_regions"]]
        )
        self.assertNotIn("WATCH THE VIDEO", process.stdout)


if __name__ == "__main__":
    unittest.main()
