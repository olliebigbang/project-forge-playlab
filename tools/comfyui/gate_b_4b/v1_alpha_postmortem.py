from __future__ import annotations

import json
import math
import os
import shutil
import uuid
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from PIL import Image, ImageDraw


class V1PostmortemError(RuntimeError):
    pass


def _border_pixels(rgb: np.ndarray) -> np.ndarray:
    return np.concatenate((rgb[0], rgb[-1], rgb[1:-1, 0], rgb[1:-1, -1]), axis=0)


def _largest_component(mask: np.ndarray) -> tuple[np.ndarray, int, int]:
    count, labels, stats, _ = cv2.connectedComponentsWithStats(mask.astype(np.uint8), 8)
    if count <= 1:
        return np.zeros_like(mask, dtype=bool), 0, 0
    candidates = [(int(stats[index, cv2.CC_STAT_AREA]), index) for index in range(1, count)]
    area, index = max(candidates)
    return labels == index, area, count - 1


def _mask_image(mask: np.ndarray) -> Image.Image:
    return Image.fromarray(np.where(mask, 255, 0).astype(np.uint8), mode="L")


def _heatmap(values: np.ndarray, ceiling: float) -> Image.Image:
    normalized = np.clip(values / max(ceiling, 1e-6), 0.0, 1.0)
    colored = cv2.applyColorMap(np.rint(normalized * 255.0).astype(np.uint8), cv2.COLORMAP_TURBO)
    return Image.fromarray(cv2.cvtColor(colored, cv2.COLOR_BGR2RGB), mode="RGB")


def _overlay(rgb: np.ndarray, masks: list[tuple[np.ndarray, tuple[int, int, int], float]]) -> Image.Image:
    result = rgb.astype(np.float32)
    for mask, color, opacity in masks:
        if not np.any(mask):
            continue
        color_array = np.array(color, dtype=np.float32)
        result[mask] = result[mask] * (1.0 - opacity) + color_array * opacity
    return Image.fromarray(np.rint(np.clip(result, 0, 255)).astype(np.uint8), mode="RGB")


def analyze_v1(
    raw_path: Path,
    manifest_path: Path,
    output_directory: Path,
    *,
    expected_background: tuple[int, int, int] = (255, 0, 255),
) -> dict[str, Any]:
    if output_directory.exists():
        raise V1PostmortemError(f"OUTPUT_ALREADY_EXISTS:{output_directory}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    try:
        with Image.open(raw_path) as opened:
            source = opened.convert("RGB")
            source.load()
    except (OSError, ValueError) as exc:
        raise V1PostmortemError("INVALID_SOURCE_PNG") from exc
    rgb = np.asarray(source, dtype=np.uint8)
    height, width = rgb.shape[:2]
    border = _border_pixels(rgb).astype(np.float32)
    expected = np.array(expected_background, dtype=np.float32)
    expected_distance = np.linalg.norm(border - expected, axis=1)
    expected_ratio = float(np.mean(expected_distance < 180.0))
    border_median = np.median(border, axis=0)
    distance = np.linalg.norm(rgb.astype(np.float32) - border_median, axis=2)
    permissive = (distance < 82.0).astype(np.uint8)
    flood_source = permissive.copy()
    flood_mask = np.zeros((height + 2, width + 2), dtype=np.uint8)
    for x in range(width):
        if flood_source[0, x]:
            cv2.floodFill(flood_source, flood_mask, (x, 0), 2)
        if flood_source[-1, x]:
            cv2.floodFill(flood_source, flood_mask, (x, height - 1), 2)
    for y in range(height):
        if flood_source[y, 0]:
            cv2.floodFill(flood_source, flood_mask, (0, y), 2)
        if flood_source[y, -1]:
            cv2.floodFill(flood_source, flood_mask, (width - 1, y), 2)
    flood_background = flood_source == 2
    candidate_foreground = ~flood_background
    first_largest, first_area, initial_component_count = _largest_component(candidate_foreground)
    closed = cv2.morphologyEx(first_largest.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8)) > 0
    final_largest, final_area, closed_component_count = _largest_component(closed)
    edge_band = np.zeros((height, width), dtype=bool)
    edge_band[:2] = True
    edge_band[-2:] = True
    edge_band[:, :2] = True
    edge_band[:, -2:] = True
    rejected_edge_pixels = final_largest & edge_band
    low_chroma_border = np.zeros((height, width), dtype=bool)
    border_bad = expected_distance >= 180.0
    cursor = 0
    low_chroma_border[0] = border_bad[cursor : cursor + width]
    cursor += width
    low_chroma_border[-1] = border_bad[cursor : cursor + width]
    cursor += width
    if height > 2:
        low_chroma_border[1:-1, 0] = border_bad[cursor : cursor + height - 2]
        cursor += height - 2
        low_chroma_border[1:-1, -1] = border_bad[cursor : cursor + height - 2]

    bounds: list[int] = []
    if np.any(final_largest):
        ys, xs = np.where(final_largest)
        bounds = [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1]
    exact_failure = str(manifest.get("failure_reason", ""))
    failure_region = np.zeros((height, width), dtype=bool)
    if exact_failure == "BACKGROUND_NOT_HIGH_CONTRAST_CHROMA":
        failure_region = cv2.dilate(low_chroma_border.astype(np.uint8), np.ones((13, 13), np.uint8)) > 0
    elif exact_failure == "OBJECT_TOUCHES_RAW_EDGE":
        failure_region = cv2.dilate(rejected_edge_pixels.astype(np.uint8), np.ones((17, 17), np.uint8)) > 0
    elif exact_failure in {"NO_FOREGROUND_COMPONENT", "FOREGROUND_TOO_SMALL"}:
        failure_region = candidate_foreground
    elif exact_failure == "UNRELIABLE_FOREGROUND_COVERAGE":
        failure_region = final_largest
    else:
        failure_region = rejected_edge_pixels | low_chroma_border

    stage = output_directory.parent / f".{output_directory.name}.{uuid.uuid4().hex}.tmp"
    stage.mkdir(parents=True, exist_ok=False)
    try:
        # Border estimate: yellow marks the samples, and the swatch stores the
        # exact robust median color used by v1.
        border_debug = source.copy()
        border_draw = ImageDraw.Draw(border_debug)
        border_draw.rectangle((0, 0, width - 1, height - 1), outline=(255, 220, 0), width=4)
        swatch = tuple(int(round(value)) for value in border_median)
        border_draw.rectangle((12, 12, 116, 70), fill=swatch, outline=(255, 255, 255), width=2)
        border_draw.text((20, 82), f"median {swatch}", fill=(255, 255, 255))
        border_debug.save(stage / "border_background_estimate.png", format="PNG", optimize=True)
        _heatmap(distance, max(120.0, float(np.percentile(distance, 99)))).save(
            stage / "chroma_distance_map.png", format="PNG", optimize=True
        )
        _mask_image(flood_background).save(stage / "flood_filled_background.png", format="PNG", optimize=True)
        _mask_image(candidate_foreground).save(stage / "candidate_foreground.png", format="PNG", optimize=True)
        _mask_image(final_largest).save(stage / "largest_component.png", format="PNG", optimize=True)
        _overlay(rgb, [(rejected_edge_pixels, (255, 35, 20), 0.9)]).save(
            stage / "rejected_edge_pixels.png", format="PNG", optimize=True
        )
        _overlay(
            rgb,
            [
                (failure_region, (255, 20, 20), 0.72),
                (final_largest & ~failure_region, (40, 210, 255), 0.28),
            ],
        ).save(stage / "final_failure_region.png", format="PNG", optimize=True)
        result = {
            "method": "v1_exact_chroma_flood_replay",
            "source_raw": str(raw_path),
            "source_manifest": str(manifest_path),
            "recorded_v1_status": manifest.get("status"),
            "recorded_v1_failure_reason": exact_failure,
            "border_background_rgb": [round(float(value), 3) for value in border_median],
            "expected_background_match_ratio": round(expected_ratio, 6),
            "distance_threshold": 82.0,
            "candidate_foreground_coverage": round(float(np.mean(candidate_foreground)), 6),
            "largest_component_coverage": round(float(np.mean(final_largest)), 6),
            "initial_component_count": initial_component_count,
            "closed_component_count": closed_component_count,
            "first_largest_component_area": first_area,
            "final_largest_component_area": final_area,
            "largest_component_bounds_xyxy": bounds,
            "rejected_edge_pixel_count": int(np.count_nonzero(rejected_edge_pixels)),
            "failed_expected_chroma_border_pixel_count": int(np.count_nonzero(low_chroma_border)),
            "debug_files": [
                "border_background_estimate.png",
                "chroma_distance_map.png",
                "flood_filled_background.png",
                "candidate_foreground.png",
                "largest_component.png",
                "rejected_edge_pixels.png",
                "final_failure_region.png",
            ],
        }
        (stage / "v1_postmortem.json").write_text(
            json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        output_directory.parent.mkdir(parents=True, exist_ok=True)
        os.replace(stage, output_directory)
        return result
    finally:
        if stage.exists():
            shutil.rmtree(stage)

