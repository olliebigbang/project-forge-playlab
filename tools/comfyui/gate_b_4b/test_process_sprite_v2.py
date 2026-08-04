from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import cv2
import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))

import process_sprite_v2 as post  # noqa: E402


MAGENTA = (255, 0, 255)


def _canvas(size: int = 160) -> np.ndarray:
    image = np.empty((size, size, 3), dtype=np.uint8)
    image[:, :] = MAGENTA
    return image


def _central_subject() -> np.ndarray:
    image = _canvas()
    cv2.ellipse(image, (80, 80), (30, 27), 0, 0, 360, (24, 196, 224), -1, cv2.LINE_AA)
    cv2.rectangle(image, (61, 74), (99, 106), (32, 104, 220), -1, cv2.LINE_AA)
    cv2.circle(image, (71, 73), 6, (246, 210, 42), -1, cv2.LINE_AA)
    return image


class SegmentSpriteV2Tests(unittest.TestCase):
    def test_edge_ground_band_is_rejected(self) -> None:
        image = _central_subject()
        cv2.rectangle(image, (0, 142), (159, 159), (92, 66, 44), -1)

        result = post.segment_sprite(image)

        self.assertFalse(np.any(result.hard_mask[142:]))
        self.assertGreater(np.count_nonzero(result.debug["rejected_edge_pixels"][142:]), 1000)
        self.assertLess(result.metrics["object_bbox"][1] + result.metrics["object_bbox"][3], 130)

    def test_soft_background_colored_shadow_is_removed(self) -> None:
        image = _central_subject()
        # A black translucent blur over the key color remains on the same color
        # ray as the backdrop, which is what the generic shadow model detects.
        overlay = image.copy()
        cv2.ellipse(overlay, (82, 122), (35, 8), 0, 0, 360, (70, 0, 70), -1, cv2.LINE_AA)
        image = cv2.addWeighted(overlay, 0.55, image, 0.45, 0)

        result = post.segment_sprite(image)

        self.assertLess(int(result.alpha[116:130, 45:120].max(initial=0)), 12)
        self.assertLess(result.metrics["shadow_residual_score"], 0.08)
        self.assertGreater(float(np.max(result.debug["shadow_likelihood"][116:130, 45:120])), 0.6)

    def test_detached_hose_is_retained_as_a_near_small_component(self) -> None:
        image = _central_subject()
        points = np.array([[117, 70], [124, 72], [128, 80], [125, 88]], dtype=np.int32)
        cv2.polylines(image, [points], False, (30, 225, 92), 4, cv2.LINE_AA)

        result = post.segment_sprite(image)

        self.assertGreater(np.count_nonzero(result.hard_mask[68:91, 116:131]), 30)
        self.assertGreaterEqual(result.metrics["component_count"], 2)
        self.assertEqual(result.metrics["component_count"], result.metrics["kept_component_count"])
        self.assertGreater(result.metrics["smallest_kept_component_area"], 0)

    def test_remote_noise_is_removed_without_losing_subject(self) -> None:
        image = _central_subject()
        cv2.rectangle(image, (10, 10), (16, 16), (24, 196, 224), -1)

        result = post.segment_sprite(image)

        self.assertFalse(np.any(result.hard_mask[8:19, 8:19]))
        self.assertGreater(np.count_nonzero(result.debug["removed_components"][8:19, 8:19]), 20)
        self.assertGreaterEqual(result.metrics["removed_component_count"], 1)
        self.assertGreater(result.metrics["removed_area"], 20)
        self.assertTrue(result.hard_mask[80, 80])

    def test_thin_connected_stem_is_retained(self) -> None:
        image = _central_subject()
        cv2.line(image, (80, 54), (80, 30), (244, 214, 48), 2, cv2.LINE_AA)

        result = post.segment_sprite(image)

        self.assertGreater(np.count_nonzero(result.hard_mask[30:56, 78:83]), 25)
        self.assertLessEqual(result.metrics["object_bbox"][1], 31)

    def test_empty_and_low_confidence_inputs_are_rejected_with_debug(self) -> None:
        empty = _canvas()
        low_contrast = _canvas()
        cv2.circle(low_contrast, (80, 80), 28, (238, 0, 238), -1, cv2.LINE_AA)

        for image in (empty, low_contrast):
            with self.subTest(kind="empty" if image is empty else "low_contrast"):
                with self.assertRaises(post.SpritePostprocessError) as caught:
                    post.segment_sprite(image)
                self.assertIn(
                    caught.exception.code,
                    {"NO_CONFIDENT_FOREGROUND_SEED", "LOW_SEGMENTATION_CONFIDENCE"},
                )
                self.assertEqual(caught.exception.debug["chroma_distance"].shape, image.shape[:2])
                self.assertEqual(caught.exception.debug["final_failure_region"].shape, image.shape[:2])

    def test_coherent_dark_magenta_border_does_not_require_literal_key_brightness(self) -> None:
        image = np.empty((160, 160, 3), dtype=np.uint8)
        image[:, :] = (96, 0, 96)
        cv2.ellipse(image, (80, 80), (30, 28), 0, 0, 360, (24, 196, 224), -1, cv2.LINE_AA)

        result = post.segment_sprite(image)

        self.assertLess(result.metrics["background_expected_match"], 0.42)
        self.assertGreater(result.metrics["background_border_coherence"], 0.9)
        self.assertGreater(result.metrics["background_key_direction_similarity"], 0.98)
        self.assertGreater(result.metrics["segmentation_confidence"], 0.6)

    def test_debug_contract_exposes_all_required_intermediates(self) -> None:
        result = post.segment_sprite(_central_subject())
        required = {
            "border_estimate",
            "chroma_distance",
            "flood_bg",
            "largest_component",
            "candidate_fg",
            "rejected_edge_pixels",
            "final_failure_region",
            "kept_components",
            "removed_components",
        }
        self.assertTrue(required.issubset(result.debug))
        for name in required - {"border_estimate"}:
            self.assertEqual(result.debug[name].shape, (160, 160), name)
        self.assertEqual(result.debug["border_estimate"].shape, (160, 160, 3))
        expected_metrics = {
            "foreground_coverage",
            "edge_contact_ratio",
            "background_residual_ratio",
            "internal_hole_ratio",
            "component_count",
            "object_bbox",
            "soft_edge_pixel_ratio",
            "shadow_residual_score",
            "segmentation_confidence",
            "kept_component_count",
            "removed_component_count",
            "removed_area",
            "smallest_kept_component_area",
        }
        self.assertTrue(expected_metrics.issubset(result.metrics))


class ProcessSpriteV2DeliveryTests(unittest.TestCase):
    def _write_source(self, directory: Path, image: np.ndarray | None = None) -> Path:
        source = directory / "raw.png"
        Image.fromarray(_central_subject() if image is None else image, mode="RGB").save(source)
        return source

    def test_delivery_is_96_rgba_alpha_and_at_most_32_colors(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            source = self._write_source(temp)
            output = temp / "delivery"

            metrics = post.process_sprite(source, output, outline=True)

            sprite = Image.open(output / "processed_sprite.png").convert("RGBA")
            alpha = Image.open(output / "alpha_mask.png").convert("L")
            rgba = np.asarray(sprite, dtype=np.uint8)
            visible_colors = np.unique(rgba[:, :, :3][rgba[:, :, 3] > 0], axis=0)
            self.assertEqual(sprite.size, (96, 96))
            self.assertEqual(alpha.size, (96, 96))
            self.assertGreater(alpha.getextrema()[1], 0)
            self.assertLessEqual(len(visible_colors), 32)
            self.assertEqual(metrics["processed_dimensions"], [96, 96])
            self.assertGreater(metrics["soft_edge_pixel_ratio"], 0.0)
            self.assertEqual(
                json.loads((output / "metrics.json").read_text(encoding="utf-8")), metrics
            )
            self.assertTrue((output / "debug" / "01_border_estimate.png").is_file())
            self.assertTrue((output / "debug" / "09_removed_components.png").is_file())

    def test_atomic_delivery_never_overwrites_and_cleans_failed_stage(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            source = self._write_source(temp)
            output = temp / "immutable"
            output.mkdir()
            sentinel = output / "owner.txt"
            sentinel.write_text("original", encoding="utf-8")

            with self.assertRaisesRegex(post.SpritePostprocessError, "OUTPUT_DIRECTORY_EXISTS"):
                post.process_sprite(source, output)
            self.assertEqual(sentinel.read_text(encoding="utf-8"), "original")
            self.assertEqual(list(temp.glob(".immutable.tmp-*")), [])

            fresh_output = temp / "fresh"
            with mock.patch.object(post, "_write_delivery", side_effect=OSError("test write failure")):
                with self.assertRaisesRegex(OSError, "test write failure"):
                    post.process_sprite(source, fresh_output)
            self.assertFalse(fresh_output.exists())
            self.assertEqual(list(temp.glob(".fresh.tmp-*")), [])

    def test_rejected_source_atomically_publishes_evidence_but_no_sprite(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            source = self._write_source(temp, _canvas())
            output = temp / "rejected"

            with self.assertRaises(post.SpritePostprocessError) as caught:
                post.process_sprite(source, output)

            self.assertEqual(caught.exception.evidence_path, output)
            self.assertTrue(output.is_dir())
            metrics = json.loads((output / "metrics.json").read_text(encoding="utf-8"))
            self.assertEqual(metrics["status"], "rejected")
            self.assertEqual(metrics["failure_reason"], caught.exception.code)
            self.assertFalse((output / "processed_sprite.png").exists())
            self.assertFalse((output / "alpha_mask.png").exists())
            required_debug = {
                "01_border_estimate.png",
                "02_chroma_distance.png",
                "03_flood_bg.png",
                "04_largest_component.png",
                "05_candidate_fg.png",
                "06_rejected_edge_pixels.png",
                "07_final_failure_region.png",
            }
            self.assertTrue(required_debug.issubset({path.name for path in (output / "debug").iterdir()}))
            self.assertEqual(list(temp.glob(".rejected.tmp-*")), [])

    def test_validation_rejects_non_rgba_sprite(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            Image.new("RGB", (96, 96), (10, 20, 30)).save(stage / "processed_sprite.png")
            Image.new("L", (96, 96), 255).save(stage / "alpha_mask.png")
            with self.assertRaisesRegex(post.SpritePostprocessError, "OUTPUT_SPRITE_NOT_RGBA_PNG"):
                post._validate_delivery(stage, 96, 32)

    def test_validation_rejects_transparent_sprite_with_nonzero_mask(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            Image.new("RGBA", (96, 96), (10, 20, 30, 0)).save(stage / "processed_sprite.png")
            Image.new("L", (96, 96), 255).save(stage / "alpha_mask.png")
            with self.assertRaisesRegex(post.SpritePostprocessError, "OUTPUT_ALPHA_MISMATCH"):
                post._validate_delivery(stage, 96, 32)

    def test_validation_rejects_mismatched_alpha(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            sprite = Image.new("RGBA", (96, 96), (10, 20, 30, 0))
            sprite.putpixel((48, 48), (10, 20, 30, 255))
            sprite.save(stage / "processed_sprite.png")
            mask = Image.new("L", (96, 96), 0)
            mask.putpixel((47, 48), 255)
            mask.save(stage / "alpha_mask.png")
            with self.assertRaisesRegex(post.SpritePostprocessError, "OUTPUT_ALPHA_MISMATCH"):
                post._validate_delivery(stage, 96, 32)


if __name__ == "__main__":
    unittest.main()
