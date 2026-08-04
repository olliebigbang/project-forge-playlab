from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import cv2
import numpy as np
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))

import process_birefnet_sprite as post  # noqa: E402


def _rgba_mask_pair(size: int = 192) -> tuple[Image.Image, Image.Image]:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((48, 55, 124, 126), radius=16, fill=242)
    draw.ellipse((62, 66, 84, 88), fill=255)
    rgba = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    color = Image.new("RGBA", (size, size), (42, 164, 198, 255))
    rgba.paste(color, mask=mask)
    rgba.putalpha(mask)
    return rgba, mask


def _write_pair(directory: Path, rgba: Image.Image, mask: Image.Image) -> tuple[Path, Path]:
    rgba_path = directory / "birefnet_rgba.png"
    mask_path = directory / "birefnet_mask.png"
    rgba.save(rgba_path, format="PNG")
    mask.save(mask_path, format="PNG")
    return rgba_path, mask_path


class BiRefNetAlphaContractTests(unittest.TestCase):
    def test_empty_and_low_confidence_alpha_are_rejected(self) -> None:
        empty = np.zeros((128, 128), dtype=np.uint8)
        with self.assertRaisesRegex(
            post.BiRefNetPostprocessError, "EMPTY_BIREFNET_ALPHA"
        ):
            post.clean_birefnet_alpha(empty, empty)

        low = np.zeros((128, 128), dtype=np.uint8)
        cv2.circle(low, (64, 64), 28, 118, -1, cv2.LINE_AA)
        with self.assertRaises(post.BiRefNetPostprocessError) as caught:
            post.clean_birefnet_alpha(low, low)
        self.assertEqual(caught.exception.code, "LOW_SEGMENTATION_CONFIDENCE")
        self.assertLess(
            caught.exception.metrics["segmentation_confidence"],
            post.MIN_SEGMENTATION_CONFIDENCE,
        )

    def test_thin_connected_stem_is_not_eroded(self) -> None:
        alpha = np.zeros((192, 192), dtype=np.uint8)
        cv2.ellipse(alpha, (96, 60), (28, 22), 0, 0, 360, 242, -1, cv2.LINE_AA)
        cv2.line(alpha, (96, 80), (96, 142), 242, 2, cv2.LINE_AA)
        cv2.ellipse(alpha, (96, 145), (25, 5), 0, 0, 360, 242, -1, cv2.LINE_AA)

        result = post.clean_birefnet_alpha(alpha, alpha)

        self.assertGreater(np.count_nonzero(result.alpha[81:142, 94:99] > 8), 90)
        self.assertEqual(result.metrics["kept_component_count"], 1)
        self.assertFalse(result.metrics["largest_component_only"])

    def test_detached_hose_is_retained_instead_of_largest_component_only(self) -> None:
        alpha = np.zeros((192, 192), dtype=np.uint8)
        cv2.rectangle(alpha, (42, 58), (108, 132), 245, -1)
        hose = np.array(
            [[122, 72], [136, 70], [149, 80], [154, 98], [147, 117]],
            dtype=np.int32,
        )
        cv2.polylines(alpha, [hose], False, 238, 3, cv2.LINE_AA)

        result = post.clean_birefnet_alpha(alpha, alpha)

        self.assertGreater(np.count_nonzero(result.alpha[66:122, 118:158] > 8), 100)
        self.assertEqual(result.metrics["input_component_count"], 2)
        self.assertEqual(result.metrics["kept_component_count"], 2)
        self.assertEqual(result.metrics["removed_tiny_component_count"], 0)

    def test_only_tiny_dust_is_removed_and_small_internal_hole_is_repaired(self) -> None:
        alpha = np.zeros((128, 128), dtype=np.uint8)
        cv2.rectangle(alpha, (32, 30), (96, 100), 244, -1)
        alpha[64, 64] = 0
        alpha[8, 8] = 255

        result = post.clean_birefnet_alpha(alpha, alpha)

        self.assertGreater(result.alpha[64, 64], 8)
        self.assertEqual(result.alpha[8, 8], 0)
        self.assertEqual(result.metrics["repaired_small_hole_count"], 1)
        self.assertEqual(result.metrics["removed_tiny_component_count"], 1)

    def test_rgba_mask_disagreement_is_rejected(self) -> None:
        first = np.zeros((128, 128), dtype=np.uint8)
        second = np.zeros_like(first)
        cv2.circle(first, (44, 64), 25, 240, -1)
        cv2.circle(second, (84, 64), 25, 240, -1)

        with self.assertRaises(post.BiRefNetPostprocessError) as caught:
            post.clean_birefnet_alpha(first, second)

        self.assertEqual(caught.exception.code, "BIREFNET_RGBA_MASK_MISMATCH")


class BiRefNetAtomicDeliveryTests(unittest.TestCase):
    def test_delivery_is_exact_rgba_alpha_palette_and_metrics_contract(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            rgba, mask = _rgba_mask_pair()
            rgba_path, mask_path = _write_pair(temp, rgba, mask)
            output = temp / "delivery"

            metrics = post.process_birefnet_sprite(rgba_path, mask_path, output)

            self.assertEqual(
                {path.name for path in output.iterdir()},
                {"processed_sprite.png", "alpha_mask.png", "metrics.json"},
            )
            with Image.open(output / "processed_sprite.png") as sprite:
                self.assertEqual(sprite.mode, "RGBA")
                self.assertEqual(sprite.size, (96, 96))
                sprite_array = np.asarray(sprite, dtype=np.uint8)
            with Image.open(output / "alpha_mask.png") as alpha:
                self.assertEqual(alpha.mode, "L")
                self.assertEqual(alpha.size, (96, 96))
                alpha_array = np.asarray(alpha, dtype=np.uint8)
            self.assertTrue(np.array_equal(sprite_array[:, :, 3], alpha_array))
            self.assertGreater(int(alpha_array.max(initial=0)), 0)
            visible_colors = np.unique(
                sprite_array[:, :, :3][sprite_array[:, :, 3] > 0], axis=0
            )
            self.assertLessEqual(len(visible_colors), 32)
            self.assertEqual(metrics["processed_dimensions"], [96, 96])
            self.assertTrue(metrics["alpha_valid"])
            self.assertFalse(metrics["largest_component_only"])
            self.assertEqual(
                json.loads((output / "metrics.json").read_text(encoding="utf-8")),
                metrics,
            )

    def test_detached_hose_survives_full_96px_delivery(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            alpha = np.zeros((192, 192), dtype=np.uint8)
            cv2.rectangle(alpha, (36, 58), (100, 132), 244, -1)
            points = np.array(
                [[116, 69], [135, 66], [153, 78], [160, 99], [151, 122]],
                dtype=np.int32,
            )
            cv2.polylines(alpha, [points], False, 240, 4, cv2.LINE_AA)
            mask = Image.fromarray(alpha, mode="L")
            rgba = Image.new("RGBA", (192, 192), (0, 0, 0, 0))
            rgba.paste(Image.new("RGBA", (192, 192), (62, 190, 148, 255)), mask=mask)
            rgba.putalpha(mask)
            rgba_path, mask_path = _write_pair(temp, rgba, mask)

            post.process_birefnet_sprite(rgba_path, mask_path, temp / "delivery")

            output_alpha = np.asarray(
                Image.open(temp / "delivery" / "alpha_mask.png"), dtype=np.uint8
            )
            count, _ = cv2.connectedComponents((output_alpha > 8).astype(np.uint8), 8)
            self.assertGreaterEqual(count - 1, 2)

    def test_existing_output_is_never_overwritten(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            rgba_path, mask_path = _write_pair(temp, *_rgba_mask_pair())
            output = temp / "owned"
            output.mkdir()
            sentinel = output / "owner.txt"
            sentinel.write_text("original", encoding="utf-8")

            with self.assertRaisesRegex(
                post.BiRefNetPostprocessError, "OUTPUT_DIRECTORY_EXISTS"
            ):
                post.process_birefnet_sprite(rgba_path, mask_path, output)

            self.assertEqual(sentinel.read_text(encoding="utf-8"), "original")
            self.assertEqual(list(temp.glob(".owned.tmp-*")), [])

    def test_failed_stage_leaves_no_partial_output(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            rgba_path, mask_path = _write_pair(temp, *_rgba_mask_pair())
            output = temp / "new_delivery"

            with mock.patch.object(
                post, "_write_delivery", side_effect=OSError("simulated write failure")
            ):
                with self.assertRaisesRegex(OSError, "simulated write failure"):
                    post.process_birefnet_sprite(rgba_path, mask_path, output)

            self.assertFalse(output.exists())
            self.assertEqual(list(temp.glob(".new_delivery.tmp-*")), [])

    def test_rejected_input_publishes_nothing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            empty = Image.new("L", (128, 128), 0)
            rgba = Image.new("RGBA", (128, 128), (20, 30, 40, 0))
            rgba_path, mask_path = _write_pair(temp, rgba, empty)
            output = temp / "rejected"

            with self.assertRaisesRegex(
                post.BiRefNetPostprocessError, "EMPTY_BIREFNET_ALPHA"
            ):
                post.process_birefnet_sprite(rgba_path, mask_path, output)

            self.assertFalse(output.exists())
            self.assertEqual(list(temp.glob(".rejected.tmp-*")), [])


if __name__ == "__main__":
    unittest.main()
