from __future__ import annotations

import argparse
import json
import math
import os
import shutil
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

import cv2
import numpy as np
from PIL import Image, ImageFilter


SPRITE_SIZE = 96
MAX_COLORS = 32
MARGIN_RATIO = 0.10
MIN_SEGMENTATION_CONFIDENCE = 0.72


class BiRefNetPostprocessError(RuntimeError):
    """A stable rejection from the offline BiRefNet pixel contract."""

    def __init__(self, code: str, *, metrics: dict[str, Any] | None = None) -> None:
        super().__init__(code)
        self.code = code
        self.metrics = metrics or {}


@dataclass(frozen=True)
class CleanedAlpha:
    """Validated BiRefNet alpha after conservative pixel-only cleanup."""

    alpha: np.ndarray
    metrics: dict[str, Any]


def _component_data(mask: np.ndarray) -> tuple[np.ndarray, list[dict[str, int]]]:
    count, labels, stats, _ = cv2.connectedComponentsWithStats(
        np.asarray(mask, dtype=np.uint8), connectivity=8
    )
    components: list[dict[str, int]] = []
    for label in range(1, count):
        components.append(
            {
                "label": label,
                "area": int(stats[label, cv2.CC_STAT_AREA]),
                "x": int(stats[label, cv2.CC_STAT_LEFT]),
                "y": int(stats[label, cv2.CC_STAT_TOP]),
                "width": int(stats[label, cv2.CC_STAT_WIDTH]),
                "height": int(stats[label, cv2.CC_STAT_HEIGHT]),
            }
        )
    return labels, components


def _remove_only_tiny_isolated_noise(alpha: np.ndarray) -> tuple[np.ndarray, dict[str, int]]:
    """Remove dust-sized components without selecting a dominant component.

    Every non-tiny component is retained regardless of position, distance from
    another component, or object class. Long/thin components are explicitly
    protected so a detached hose, handle, cable, stem, or ornament is not lost.
    """

    cleaned = alpha.copy()
    hard = cleaned > 8
    labels, components = _component_data(hard)
    image_area = int(hard.size)
    tiny_area_limit = max(2, min(8, int(round(image_area / 65536.0))))
    removed_count = 0
    removed_area = 0
    for component in components:
        extent = max(component["width"], component["height"])
        elongated = extent >= 5 or (
            min(component["width"], component["height"]) > 0
            and extent / min(component["width"], component["height"]) >= 3.0
        )
        is_tiny_dust = component["area"] <= tiny_area_limit and extent <= 3
        if is_tiny_dust and not elongated:
            selected = labels == component["label"]
            removed_count += 1
            removed_area += int(np.count_nonzero(selected))
            cleaned[selected] = 0
    return cleaned, {
        "input_component_count": len(components),
        "removed_tiny_component_count": removed_count,
        "removed_tiny_area": removed_area,
        "tiny_noise_area_limit": tiny_area_limit,
    }


def _repair_only_small_internal_holes(alpha: np.ndarray) -> tuple[np.ndarray, dict[str, int]]:
    cleaned = alpha.copy()
    foreground = cleaned > 8
    inverse = ~foreground
    labels, components = _component_data(inverse)
    height, width = foreground.shape
    image_area = int(foreground.size)
    hole_area_limit = max(2, min(16, int(round(image_area / 16384.0))))
    repaired_count = 0
    repaired_area = 0
    kernel = np.ones((3, 3), dtype=np.uint8)
    for component in components:
        touches_edge = (
            component["x"] == 0
            or component["y"] == 0
            or component["x"] + component["width"] >= width
            or component["y"] + component["height"] >= height
        )
        if touches_edge or component["area"] > hole_area_limit:
            continue
        hole = labels == component["label"]
        ring = cv2.dilate(hole.astype(np.uint8), kernel, iterations=1).astype(bool) & ~hole
        neighbors = cleaned[ring & (cleaned > 8)]
        if neighbors.size == 0:
            continue
        fill_value = int(max(64, round(float(np.median(neighbors)))))
        cleaned[hole] = fill_value
        repaired_count += 1
        repaired_area += component["area"]
    return cleaned, {
        "repaired_small_hole_count": repaired_count,
        "repaired_small_hole_area": repaired_area,
        "small_hole_area_limit": hole_area_limit,
    }


def _light_edge_smoothing(alpha: np.ndarray) -> np.ndarray:
    """Blend a small Gaussian only around the boundary; never erode the core."""

    source = alpha.astype(np.uint8, copy=True)
    foreground = source > 8
    kernel = np.ones((3, 3), dtype=np.uint8)
    dilated = cv2.dilate(foreground.astype(np.uint8), kernel, iterations=1).astype(bool)
    eroded = cv2.erode(foreground.astype(np.uint8), kernel, iterations=1).astype(bool)
    boundary = dilated & ~eroded
    blurred = cv2.GaussianBlur(source, (3, 3), sigmaX=0.55, sigmaY=0.55)
    result = source.astype(np.float32)
    result[boundary] = source[boundary].astype(np.float32) * 0.82 + blurred[
        boundary
    ].astype(np.float32) * 0.18
    result[~dilated] = 0.0
    # Protect all original confident pixels, including one-pixel-wide structures.
    protect = source >= 16
    result[protect] = np.maximum(result[protect], source[protect].astype(np.float32) * 0.94)
    return np.clip(np.rint(result), 0, 255).astype(np.uint8)


def clean_birefnet_alpha(rgba_alpha: np.ndarray, model_mask: np.ndarray) -> CleanedAlpha:
    """Validate and conservatively clean an official BiRefNet RGBA+mask pair."""

    rgba_alpha = np.asarray(rgba_alpha)
    model_mask = np.asarray(model_mask)
    if (
        rgba_alpha.ndim != 2
        or model_mask.ndim != 2
        or rgba_alpha.shape != model_mask.shape
        or rgba_alpha.dtype != np.uint8
        or model_mask.dtype != np.uint8
    ):
        raise BiRefNetPostprocessError("INVALID_BIREFNET_ALPHA_ARRAYS")
    height, width = rgba_alpha.shape
    if height < 32 or width < 32:
        raise BiRefNetPostprocessError("BIREFNET_OUTPUT_TOO_SMALL")

    difference = np.abs(rgba_alpha.astype(np.int16) - model_mask.astype(np.int16))
    mean_difference = float(np.mean(difference) / 255.0)
    alpha_binary = rgba_alpha > 8
    mask_binary = model_mask > 8
    union = int(np.count_nonzero(alpha_binary | mask_binary))
    intersection = int(np.count_nonzero(alpha_binary & mask_binary))
    binary_iou = 1.0 if union == 0 else intersection / float(union)
    agreement = max(0.0, 1.0 - mean_difference)
    if mean_difference > 0.08 or binary_iou < 0.90:
        raise BiRefNetPostprocessError(
            "BIREFNET_RGBA_MASK_MISMATCH",
            metrics={
                "rgba_mask_mean_abs_difference": round(mean_difference, 6),
                "rgba_mask_binary_iou": round(binary_iou, 6),
            },
        )

    combined = np.rint(
        (rgba_alpha.astype(np.float32) + model_mask.astype(np.float32)) * 0.5
    ).astype(np.uint8)
    foreground = combined > 8
    foreground_pixels = int(np.count_nonzero(foreground))
    if foreground_pixels == 0:
        raise BiRefNetPostprocessError("EMPTY_BIREFNET_ALPHA")
    coverage = foreground_pixels / float(combined.size)
    if coverage < 0.002 or coverage > 0.94:
        raise BiRefNetPostprocessError(
            "LOW_SEGMENTATION_CONFIDENCE",
            metrics={"foreground_coverage": round(coverage, 6)},
        )

    foreground_probabilities = combined[foreground].astype(np.float32) / 255.0
    foreground_certainty = float(
        np.mean(np.abs(foreground_probabilities - 0.5) * 2.0)
    )
    core_ratio = float(np.mean(combined[foreground] >= 160))
    segmentation_confidence = (
        agreement * 0.35 + foreground_certainty * 0.35 + core_ratio * 0.30
    )
    validation_metrics: dict[str, Any] = {
        "rgba_mask_mean_abs_difference": round(mean_difference, 6),
        "rgba_mask_binary_iou": round(binary_iou, 6),
        "foreground_coverage": round(coverage, 6),
        "foreground_certainty": round(foreground_certainty, 6),
        "confident_foreground_ratio": round(core_ratio, 6),
        "segmentation_confidence": round(segmentation_confidence, 6),
        "minimum_segmentation_confidence": MIN_SEGMENTATION_CONFIDENCE,
    }
    if segmentation_confidence < MIN_SEGMENTATION_CONFIDENCE:
        raise BiRefNetPostprocessError(
            "LOW_SEGMENTATION_CONFIDENCE", metrics=validation_metrics
        )

    cleaned, noise_metrics = _remove_only_tiny_isolated_noise(combined)
    cleaned, hole_metrics = _repair_only_small_internal_holes(cleaned)
    cleaned = _light_edge_smoothing(cleaned)
    output_hard = cleaned > 8
    _, kept_components = _component_data(output_hard)
    if not kept_components:
        raise BiRefNetPostprocessError("EMPTY_ALPHA_AFTER_CLEANUP")
    validation_metrics.update(noise_metrics)
    validation_metrics.update(hole_metrics)
    validation_metrics.update(
        {
            "kept_component_count": len(kept_components),
            "smallest_kept_component_area": min(
                component["area"] for component in kept_components
            ),
            "cleanup_policy": "retain_all_non_tiny_components",
            "largest_component_only": False,
        }
    )
    return CleanedAlpha(alpha=cleaned, metrics=validation_metrics)


def _quantize_rgba(image: Image.Image, max_colors: int) -> Image.Image:
    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A")
    quantized = rgba.convert("RGB").quantize(
        colors=max_colors, method=Image.Quantize.MEDIANCUT
    ).convert("RGB")
    quantized.putalpha(alpha)
    return quantized


def _add_generic_outline(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    alpha = np.asarray(rgba.getchannel("A"), dtype=np.uint8)
    expanded = np.asarray(
        rgba.getchannel("A").filter(ImageFilter.MaxFilter(3)), dtype=np.uint8
    )
    outline_alpha = np.maximum(
        expanded.astype(np.int16) - alpha.astype(np.int16), 0
    ).astype(np.uint8)
    outline = Image.new("RGBA", rgba.size, (18, 22, 30, 0))
    outline.putalpha(Image.fromarray(outline_alpha, mode="L"))
    return Image.alpha_composite(outline, rgba)


def _fit_sprite(
    rgba: np.ndarray,
    alpha: np.ndarray,
    *,
    sprite_size: int,
    margin_ratio: float,
    max_colors: int,
    outline: bool,
) -> Image.Image:
    visible = alpha > 4
    if not np.any(visible):
        raise BiRefNetPostprocessError("EMPTY_ALPHA_AFTER_CLEANUP")
    ys, xs = np.where(visible)
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    source = rgba.copy()
    source[:, :, 3] = alpha
    source[alpha == 0, :3] = 0
    cropped = Image.fromarray(source[y0:y1, x0:x1], mode="RGBA")
    span = max(cropped.width, cropped.height)
    padding = max(2, int(math.ceil(span * margin_ratio)))
    padded = Image.new(
        "RGBA",
        (cropped.width + padding * 2, cropped.height + padding * 2),
        (0, 0, 0, 0),
    )
    padded.alpha_composite(cropped, (padding, padding))
    scale = min(sprite_size / padded.width, sprite_size / padded.height)
    resized_size = (
        max(1, int(round(padded.width * scale))),
        max(1, int(round(padded.height * scale))),
    )
    resized = padded.resize(resized_size, Image.Resampling.LANCZOS)
    sprite = Image.new("RGBA", (sprite_size, sprite_size), (0, 0, 0, 0))
    offset = (
        (sprite_size - resized.width) // 2,
        (sprite_size - resized.height) // 2,
    )
    sprite.alpha_composite(resized, offset)
    if outline:
        sprite = _add_generic_outline(sprite)
    return _quantize_rgba(sprite, max_colors)


def _validate_delivery(stage: Path, max_colors: int) -> dict[str, Any]:
    try:
        with Image.open(stage / "processed_sprite.png") as opened_sprite:
            if opened_sprite.format != "PNG" or opened_sprite.mode != "RGBA":
                raise BiRefNetPostprocessError("OUTPUT_SPRITE_NOT_RGBA_PNG")
            opened_sprite.load()
            sprite = opened_sprite.copy()
        with Image.open(stage / "alpha_mask.png") as opened_mask:
            if opened_mask.format != "PNG" or opened_mask.mode != "L":
                raise BiRefNetPostprocessError("OUTPUT_ALPHA_NOT_L_PNG")
            opened_mask.load()
            mask = opened_mask.copy()
    except (OSError, ValueError) as exc:
        raise BiRefNetPostprocessError("OUTPUT_VALIDATION_FAILED") from exc
    if sprite.size != (SPRITE_SIZE, SPRITE_SIZE) or mask.size != sprite.size:
        raise BiRefNetPostprocessError("OUTPUT_MUST_BE_96X96")
    rgba = np.asarray(sprite, dtype=np.uint8)
    alpha = np.asarray(mask, dtype=np.uint8)
    if not np.array_equal(rgba[:, :, 3], alpha):
        raise BiRefNetPostprocessError("OUTPUT_ALPHA_MISMATCH")
    hard = alpha > 8
    if not np.any(hard):
        raise BiRefNetPostprocessError("EMPTY_OUTPUT_ALPHA")
    if np.all(hard):
        raise BiRefNetPostprocessError("OUTPUT_HAS_NO_TRANSPARENCY")
    if np.any(hard[0]) or np.any(hard[-1]) or np.any(hard[:, 0]) or np.any(hard[:, -1]):
        raise BiRefNetPostprocessError("SPRITE_TOUCHES_OUTPUT_EDGE")
    visible_colors = np.unique(rgba[:, :, :3][rgba[:, :, 3] > 0], axis=0)
    if len(visible_colors) > max_colors:
        raise BiRefNetPostprocessError("PALETTE_LIMIT_EXCEEDED")
    ys, xs = np.where(hard)
    return {
        "processed_dimensions": [SPRITE_SIZE, SPRITE_SIZE],
        "alpha_coverage": round(float(np.mean(hard)), 6),
        "opaque_bounds": [
            int(xs.min()),
            int(ys.min()),
            int(xs.max() - xs.min() + 1),
            int(ys.max() - ys.min() + 1),
        ],
        "visible_color_count": int(len(visible_colors)),
        "alpha_valid": True,
    }


def _write_delivery(stage: Path, sprite: Image.Image, metrics: dict[str, Any]) -> None:
    sprite.save(stage / "processed_sprite.png", format="PNG", optimize=True)
    sprite.getchannel("A").save(stage / "alpha_mask.png", format="PNG", optimize=True)
    metrics.update(_validate_delivery(stage, int(metrics["palette_limit"])))
    (stage / "metrics.json").write_text(
        json.dumps(metrics, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def _atomic_publish(destination: Path, writer: Callable[[Path], None]) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        raise BiRefNetPostprocessError("OUTPUT_DIRECTORY_EXISTS")
    stage = Path(
        tempfile.mkdtemp(
            prefix=f".{destination.name}.tmp-", dir=str(destination.parent)
        )
    )
    published = False
    try:
        writer(stage)
        if destination.exists():
            raise BiRefNetPostprocessError("OUTPUT_DIRECTORY_EXISTS")
        os.rename(stage, destination)
        published = True
    finally:
        if not published and stage.exists():
            shutil.rmtree(stage)


def _load_official_pair(
    rgba_path: Path, mask_path: Path
) -> tuple[np.ndarray, np.ndarray]:
    try:
        with Image.open(rgba_path) as opened_rgba:
            if opened_rgba.format != "PNG" or opened_rgba.mode != "RGBA":
                raise BiRefNetPostprocessError("BIREFNET_RGBA_MUST_BE_RGBA_PNG")
            opened_rgba.load()
            rgba = np.asarray(opened_rgba, dtype=np.uint8).copy()
        with Image.open(mask_path) as opened_mask:
            if opened_mask.format != "PNG" or opened_mask.mode != "L":
                raise BiRefNetPostprocessError("BIREFNET_MASK_MUST_BE_L_PNG")
            opened_mask.load()
            mask = np.asarray(opened_mask, dtype=np.uint8).copy()
    except BiRefNetPostprocessError:
        raise
    except (OSError, ValueError) as exc:
        raise BiRefNetPostprocessError("INVALID_BIREFNET_PNG") from exc
    if rgba.shape[:2] != mask.shape:
        raise BiRefNetPostprocessError("BIREFNET_RGBA_MASK_SIZE_MISMATCH")
    return rgba, mask


def process_birefnet_sprite(
    rgba_path: str | Path,
    mask_path: str | Path,
    output_directory: str | Path,
    *,
    sprite_size: int = SPRITE_SIZE,
    max_colors: int = MAX_COLORS,
    margin_ratio: float = MARGIN_RATIO,
    outline: bool = True,
) -> dict[str, Any]:
    """Create one immutable sprite delivery from an existing BiRefNet result."""

    started = time.perf_counter()
    if sprite_size != SPRITE_SIZE:
        raise BiRefNetPostprocessError("SPRITE_SIZE_MUST_BE_96")
    if not 2 <= max_colors <= MAX_COLORS:
        raise BiRefNetPostprocessError("PALETTE_LIMIT_MUST_BE_AT_MOST_32")
    if not 0.08 <= margin_ratio <= 0.12:
        raise BiRefNetPostprocessError("MARGIN_RATIO_MUST_BE_8_TO_12_PERCENT")
    destination = Path(output_directory)
    if destination.exists():
        raise BiRefNetPostprocessError("OUTPUT_DIRECTORY_EXISTS")
    rgba, model_mask = _load_official_pair(Path(rgba_path), Path(mask_path))
    cleaned = clean_birefnet_alpha(rgba[:, :, 3], model_mask)
    sprite = _fit_sprite(
        rgba,
        cleaned.alpha,
        sprite_size=sprite_size,
        margin_ratio=margin_ratio,
        max_colors=max_colors,
        outline=outline,
    )
    metrics: dict[str, Any] = {
        "contract": "forge-birefnet-pixel-postprocess-v1",
        "status": "success",
        "segmentation_source": "official_birefnet_rgba_plus_mask",
        "pixel_cleanup_only": True,
        "case_specific_logic": False,
        "raw_dimensions": [int(rgba.shape[1]), int(rgba.shape[0])],
        "sprite_size": sprite_size,
        "palette_limit": max_colors,
        "margin_ratio": margin_ratio,
        "outline": bool(outline),
        **cleaned.metrics,
    }

    def writer(stage: Path) -> None:
        metrics["postprocess_seconds"] = round(time.perf_counter() - started, 3)
        _write_delivery(stage, sprite, metrics)

    _atomic_publish(destination, writer)
    return metrics


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Validate an existing official BiRefNet RGBA+mask pair and atomically "
            "publish a 96px sprite without running a model or service."
        )
    )
    parser.add_argument("birefnet_rgba_png", type=Path)
    parser.add_argument("birefnet_mask_png", type=Path)
    parser.add_argument("output_directory", type=Path)
    parser.add_argument("--colors", type=int, default=MAX_COLORS)
    parser.add_argument("--margin-ratio", type=float, default=MARGIN_RATIO)
    parser.add_argument("--no-outline", action="store_true")
    args = parser.parse_args()
    try:
        metrics = process_birefnet_sprite(
            args.birefnet_rgba_png,
            args.birefnet_mask_png,
            args.output_directory,
            max_colors=args.colors,
            margin_ratio=args.margin_ratio,
            outline=not args.no_outline,
        )
    except BiRefNetPostprocessError as exc:
        print(
            json.dumps(
                {
                    "status": "failed",
                    "failure_reason": exc.code,
                    "metrics": exc.metrics,
                },
                ensure_ascii=False,
            )
        )
        return 2
    print(json.dumps(metrics, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
