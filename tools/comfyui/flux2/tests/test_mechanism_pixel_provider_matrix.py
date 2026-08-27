from __future__ import annotations

import base64
import io
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw


TEST_ROOT = Path(__file__).resolve().parent
BRIDGE_ROOT = TEST_ROOT.parent / "bridge"
sys.path.insert(0, str(BRIDGE_ROOT))

import run_mechanism_pixel_provider_matrix as matrix  # noqa: E402


class MechanismPixelProviderContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.scaffold = self.root / "scaffold.png"
        self.palette = self.root / "palette.png"
        image = Image.new("RGBA", matrix.CANVAS_SIZE, (0, 0, 0, 0))
        draw = ImageDraw.Draw(image)
        draw.line((8, 82, 83, 21), fill=(139, 84, 45, 255), width=7)
        draw.ellipse((78, 15, 92, 29), fill=(199, 154, 59, 255))
        image.save(self.scaffold)
        palette = Image.new("RGBA", (3, 1), (0, 0, 0, 0))
        palette.putdata([(21, 24, 32, 255), (139, 84, 45, 255), (199, 154, 59, 255)])
        palette.save(self.palette)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_retro_payload_uses_exact_canvas_init_palette_and_structure_strength(self) -> None:
        payload = matrix.build_retro_payload("mechanism", 41, self.scaffold, self.palette)
        self.assertEqual((payload["width"], payload["height"]), matrix.CANVAS_SIZE)
        self.assertEqual(payload["prompt_style"], "rd_plus__topdown_item")
        self.assertTrue(payload["remove_bg"])
        self.assertTrue(payload["bypass_prompt_expansion"])
        self.assertEqual(payload["upscale_output_factor"], 1)
        self.assertGreater(len(base64.b64decode(payload["input_image"])), 100)
        with Image.open(io.BytesIO(base64.b64decode(payload["input_palette"]))) as palette:
            self.assertEqual(palette.mode, "RGB")
            self.assertEqual(palette.size, (3, 1))
        self.assertNotIn("token", " ".join(payload.keys()).lower())

    def test_pixellab_pixflux_payload_uses_init_image_and_forced_palette(self) -> None:
        payload = matrix.build_pixellab_payload("mechanism", 42, self.scaffold, self.palette)
        self.assertEqual(payload["image_size"], {"width": 96, "height": 96})
        self.assertTrue(payload["no_background"])
        self.assertEqual(payload["detail"], "low detail")
        self.assertEqual(payload["shading"], "basic shading")
        self.assertEqual(payload["outline"], "single color outline")
        self.assertEqual(payload["view"], "side")
        self.assertEqual(payload["init_image_strength"], 800)
        self.assertEqual(base64.b64decode(payload["init_image"]["base64"]), self.scaffold.read_bytes())
        self.assertEqual(base64.b64decode(payload["color_image"]["base64"]), self.palette.read_bytes())

    def test_provider_response_extractors_accept_official_base64_shapes(self) -> None:
        png = self.scaffold.read_bytes()
        encoded = base64.b64encode(png).decode("ascii")
        self.assertEqual(matrix.extract_retro_image({"base64_images": [encoded]}, 1.0), png)
        self.assertEqual(
            matrix.extract_pixellab_image({"image": {"base64": f"data:image/png;base64,{encoded}"}}),
            png,
        )

    def test_exact_scaffold_passes_pixel_preflight_without_resizing(self) -> None:
        normalized, metrics = matrix.normalize_and_validate_png(self.scaffold.read_bytes(), self.scaffold)
        with Image.open(io.BytesIO(normalized)) as image:
            self.assertEqual(image.size, matrix.CANVAS_SIZE)
            self.assertEqual(image.mode, "RGBA")
        self.assertEqual(metrics["scaffold_alpha_iou"], 1.0)
        self.assertTrue(metrics["binary_alpha"])

    def test_opaque_background_is_rejected_instead_of_silently_removed(self) -> None:
        background = Image.new("RGB", matrix.CANVAS_SIZE, (255, 255, 255))
        encoded = io.BytesIO()
        background.save(encoded, format="PNG")
        with self.assertRaisesRegex(matrix.ProviderMatrixError, "BACKGROUND_NOT_TRANSPARENT"):
            matrix.normalize_and_validate_png(encoded.getvalue(), self.scaffold)

    def test_unrelated_transparent_sprite_is_rejected_as_scaffold_drift(self) -> None:
        unrelated = Image.new("RGBA", matrix.CANVAS_SIZE, (0, 0, 0, 0))
        ImageDraw.Draw(unrelated).rectangle((2, 2, 12, 12), fill=(255, 0, 0, 255))
        encoded = io.BytesIO()
        unrelated.save(encoded, format="PNG")
        with self.assertRaisesRegex(matrix.ProviderMatrixError, "SCAFFOLD_DRIFT"):
            matrix.normalize_and_validate_png(encoded.getvalue(), self.scaffold)

    def test_pipeline_contract_keeps_ai_authority_and_bounded_retries(self) -> None:
        source = (BRIDGE_ROOT / "run_mechanism_pixel_provider_matrix.py").read_text(encoding="utf-8")
        self.assertEqual(matrix.MAX_REDRAWS, 2)
        self.assertIn('"generator_authority": "style_and_color_only"', source)
        self.assertIn('"player_confirmation_required": False', source)
        self.assertIn('"playtest_performed": False', source)
        self.assertIn('"feel_tuning_performed": False', source)
        self.assertNotIn("input(\"", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
