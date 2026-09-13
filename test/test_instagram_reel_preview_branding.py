"""Publisher policy and uncropped logo geometry, using only synthetic fixtures."""

import importlib
import unittest
from pathlib import Path

from PIL import Image, ImageChops

from reel_preview_fixture import PreviewFixture, graphics, render, storage

branding = importlib.import_module("branding")


class PublisherTests(PreviewFixture):
    def test_default_is_fts_and_missing_logo_has_no_synthetic_fallback(self):
        self.assertEqual(render.DEFAULTS["publisher"], "fightthestroke")
        config = {k: v for k, v in self.config.items() if k != "publisher"}
        with self.assertRaisesRegex(ValueError, "FTS requires --publisher-logo"):
            render.render(config)
        self.assertFalse((Path(self.output.name) / "preview.jpg").exists())

    def test_wrong_logo_and_avatar_cannot_replace_approved_fts_asset(self):
        for change, message in [
            ({"publisher_logo": str(self.photo)}, "does not match the approved"),
            ({"avatar": str(self.photo), "style": "instagram-post"}, "never an avatar"),
        ]:
            with self.subTest(change=change):
                with self.assertRaisesRegex(ValueError, message):
                    render.render(
                        {**self.config, "publisher": "fightthestroke", **change}
                    )
        self.assertEqual(
            branding.FTS_LOGO_SHA256,
            "c85db1c75d484e54acf1373c5750909fc8a27929135148c99faa65df07b8d40b",
        )
        self.assertTrue(
            branding.FTS_LOGO_URL.endswith("/logo-rgb-10years-fts.png?format=1500w")
        )

    def test_explicit_publisher_is_not_subject_and_logo_is_hashed(self):
        result = render.render(
            {
                **self.config,
                "style": "instagram-post",
                "publisher_logo": str(self.photo),
            }
        )
        self.assertEqual(result["publisher"], "Example publisher")
        self.assertEqual(result["subject"], "Sample")
        self.assertEqual(result["publisher_logo_sha256"], storage.sha256(self.photo))
        self.assertIsNone(result["publisher_logo_url"])
        self.assertEqual(
            [r["text"] for r in result["wrapper_text_regions"]],
            ["Example publisher", "Sample"],
        )

    def test_full_logo_survives_without_crop_mask_recolor_or_stretch(self):
        logo = Image.new("RGBA", (96, 32), (10, 80, 140, 255))
        for point, color in [
            ((0, 0), "red"),
            ((95, 0), "green"),
            ((0, 31), "blue"),
            ((95, 31), "yellow"),
        ]:
            logo.putpixel(point, Image.new("RGBA", (1, 1), color).getpixel((0, 0)))
        output = Image.new("RGB", (96, 96), "black")
        bounds = branding.place_logo(output, logo, (0, 0, 96, 96))
        self.assertEqual(bounds, (0, 32, 96, 64))
        self.assertIsNone(
            ImageChops.difference(output.crop(bounds), logo.convert("RGB")).getbbox()
        )
        self.assertEqual(output.getpixel((0, 0)), (255, 255, 255))

    def test_fts_publisher_text_and_subject_are_separate_in_layout(self):
        # Layout only; a synthetic image is never passed through FTS identity validation.
        config = {**self.config, "publisher": "fightthestroke"}
        typeface = graphics.Typography(self.font, self.font)
        graphics.post(
            Image.new("RGB", (1080, 1920)),
            config,
            typeface,
            None,
            Image.new("RGBA", (96, 32), "white"),
        )
        self.assertEqual(
            [r["text"] for r in typeface.regions], ["fightthestroke", "Sample"]
        )


if __name__ == "__main__":
    unittest.main()
