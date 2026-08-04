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


class SpritePostprocessError(RuntimeError):
    """A stable postprocess failure with optional in-memory diagnostics."""

    def __init__(
        self,
        code: str,
        *,
        metrics: dict[str, Any] | None = None,
        debug: dict[str, np.ndarray] | None = None,
        evidence_path: Path | None = None,
    ) -> None:
        super().__init__(code)
        self.code = code
        self.metrics = metrics or {}
        self.debug = debug or {}
        self.evidence_path = evidence_path


@dataclass(frozen=True)
class SegmentationResult:
    """The source-resolution matte and diagnostics, before sprite fitting."""

    alpha: np.ndarray
    hard_mask: np.ndarray
    metrics: dict[str, Any]
    debug: dict[str, np.ndarray]


_DEBUG_ORDER = (
    "border_estimate",
    "chroma_distance",
    "flood_bg",
    "largest_component",
    "candidate_fg",
    "rejected_edge_pixels",
    "final_failure_region",
    "kept_components",
    "removed_components",
    "sure_bg",
    "sure_fg",
    "grabcut_foreground",
    "shadow_likelihood",
    "soft_alpha",
)


def _as_bool(mask: np.ndarray) -> np.ndarray:
    return np.asarray(mask, dtype=bool)


def _border_ring(shape: tuple[int, int], thickness: int) -> np.ndarray:
    height, width = shape
    ring = np.zeros((height, width), dtype=bool)
    ring[:thickness, :] = True
    ring[-thickness:, :] = True
    ring[:, :thickness] = True
    ring[:, -thickness:] = True
    return ring


def _edge_connected(mask: np.ndarray) -> np.ndarray:
    """Return all true components that intersect the image perimeter."""

    source = _as_bool(mask)
    count, labels = cv2.connectedComponents(source.astype(np.uint8), connectivity=8)
    if count <= 1:
        return np.zeros_like(source)
    edge_labels = np.unique(
        np.concatenate((labels[0], labels[-1], labels[1:-1, 0], labels[1:-1, -1]))
    )
    edge_labels = edge_labels[edge_labels != 0]
    if edge_labels.size == 0:
        return np.zeros_like(source)
    return source & np.isin(labels, edge_labels)


def _component_data(mask: np.ndarray) -> tuple[np.ndarray, list[dict[str, Any]]]:
    count, labels, stats, centroids = cv2.connectedComponentsWithStats(
        _as_bool(mask).astype(np.uint8), connectivity=8
    )
    components: list[dict[str, Any]] = []
    for label in range(1, count):
        x = int(stats[label, cv2.CC_STAT_LEFT])
        y = int(stats[label, cv2.CC_STAT_TOP])
        width = int(stats[label, cv2.CC_STAT_WIDTH])
        height = int(stats[label, cv2.CC_STAT_HEIGHT])
        components.append(
            {
                "label": label,
                "area": int(stats[label, cv2.CC_STAT_AREA]),
                "bbox": (x, y, width, height),
                "centroid": (float(centroids[label, 0]), float(centroids[label, 1])),
            }
        )
    return labels, components


def _bbox_gap(first: tuple[int, int, int, int], second: tuple[int, int, int, int]) -> float:
    ax, ay, aw, ah = first
    bx, by, bw, bh = second
    dx = max(bx - (ax + aw), ax - (bx + bw), 0)
    dy = max(by - (ay + ah), ay - (by + bh), 0)
    return math.hypot(dx, dy)


def _bbox_union(boxes: list[tuple[int, int, int, int]]) -> tuple[int, int, int, int]:
    left = min(box[0] for box in boxes)
    top = min(box[1] for box in boxes)
    right = max(box[0] + box[2] for box in boxes)
    bottom = max(box[1] + box[3] for box in boxes)
    return left, top, right - left, bottom - top


def _shadow_likelihood(rgb: np.ndarray, background: np.ndarray) -> np.ndarray:
    """Score pixels that are predominantly a darker multiple of the key color."""

    pixels = rgb.astype(np.float32)
    key = np.asarray(background, dtype=np.float32)
    denominator = max(float(np.dot(key, key)), 1.0)
    scale = np.sum(pixels * key[None, None, :], axis=2) / denominator
    projected = scale[:, :, None] * key[None, None, :]
    residual = np.linalg.norm(pixels - projected, axis=2)
    chroma_similarity = np.exp(-np.square(residual / 30.0))
    darker = np.clip((0.98 - scale) / 0.30, 0.0, 1.0)
    valid_scale = (scale >= 0.18) & (scale < 0.97)
    return (chroma_similarity * darker * valid_scale).astype(np.float32)


def _find_edge_artifacts(mask: np.ndarray, edge_guard: int) -> np.ndarray:
    """Find generic edge-connected strips/specks without assuming an object class."""

    source = _as_bool(mask)
    height, width = source.shape
    rejected = np.zeros_like(source)

    # A broad run adjacent to an edge is usually floor/backdrop spill. Detect the
    # run independently from connected components so a narrow contact with the
    # central candidate cannot pull the whole candidate into the rejection set.
    row_coverage = np.mean(source, axis=1)
    bottom_start = height - edge_guard - 1
    dense_rows: list[int] = []
    misses = 0
    for y in range(bottom_start, max(-1, int(height * 0.62)), -1):
        if row_coverage[y] >= 0.24:
            dense_rows.append(y)
            misses = 0
        elif dense_rows:
            misses += 1
            if misses > 1:
                break
    if dense_rows:
        cutoff = min(dense_rows)
        rejected[cutoff:, :] |= source[cutoff:, :]

    labels, components = _component_data(source & ~rejected)
    near = edge_guard + 1
    image_area = float(height * width)
    for component in components:
        x, y, box_width, box_height = component["bbox"]
        area = component["area"]
        near_left = x <= near
        near_top = y <= near
        near_right = x + box_width >= width - near
        near_bottom = y + box_height >= height - near
        if not (near_left or near_top or near_right or near_bottom):
            continue
        horizontal_strip = box_width >= width * 0.28 and box_height <= height * 0.28
        vertical_strip = box_height >= height * 0.28 and box_width <= width * 0.28
        edge_speck = area <= max(12, int(image_area * 0.0015))
        if horizontal_strip or vertical_strip or edge_speck:
            rejected |= labels == component["label"]
    return rejected


def _select_component_set(
    mask: np.ndarray,
    central_region: np.ndarray,
    edge_guard: int,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, int]:
    """Keep a coherent set of nearby components rather than largest-only."""

    labels, components = _component_data(mask)
    empty = np.zeros_like(mask, dtype=bool)
    if not components:
        return empty, empty, empty, 0

    height, width = mask.shape
    central_candidates: list[tuple[float, dict[str, Any]]] = []
    for component in components:
        component_mask = labels == component["label"]
        central_fraction = float(np.mean(central_region[component_mask]))
        # Area stays dominant; the central prior only breaks implausible edge/noise
        # choices when components have comparable size.
        score = component["area"] * (0.72 + 0.56 * central_fraction)
        central_candidates.append((score, component))
    primary = max(central_candidates, key=lambda item: item[0])[1]
    largest = labels == max(components, key=lambda item: item["area"])["label"]

    main_area = int(primary["area"])
    if main_area < max(24, int(height * width * 0.0018)):
        return empty, mask.copy(), largest, 0

    kept_labels = {int(primary["label"])}
    primary_bbox = primary["bbox"]
    primary_span = max(primary_bbox[2], primary_bbox[3])
    image_diagonal = math.hypot(width, height)
    minimum_part_area = max(3, int(round(main_area * 0.0015)))
    proximity = max(5.0, min(22.0, primary_span * 0.12))

    # Components are assessed against the primary object's bounding box. This
    # preserves nearby small/long parts while preventing chains of dust specks
    # from walking the accepted set across the canvas.
    for component in sorted(components, key=lambda item: item["area"], reverse=True):
        label = int(component["label"])
        if label in kept_labels:
            continue
        x, y, box_width, box_height = component["bbox"]
        near_edge = (
            x <= edge_guard
            or y <= edge_guard
            or x + box_width >= width - edge_guard
            or y + box_height >= height - edge_guard
        )
        if near_edge:
            continue
        gap = _bbox_gap(primary_bbox, component["bbox"])
        cx, cy = component["centroid"]
        px, py = primary["centroid"]
        centroid_distance = math.hypot(cx - px, cy - py)
        area_ratio = component["area"] / float(main_area)
        extent = max(box_width, box_height)
        substantive_small_part = component["area"] >= minimum_part_area and extent >= 2
        near_primary = gap <= proximity + min(5.0, math.sqrt(component["area"]) * 0.35)
        sizeable_and_local = area_ratio >= 0.025 and centroid_distance <= image_diagonal * 0.30
        if (substantive_small_part and near_primary) or sizeable_and_local:
            kept_labels.add(label)

    kept = np.isin(labels, np.fromiter(kept_labels, dtype=np.int32))
    removed = _as_bool(mask) & ~kept
    return kept, removed, largest, len(kept_labels)


def _internal_holes(mask: np.ndarray) -> np.ndarray:
    inverse = ~_as_bool(mask)
    exterior = _edge_connected(inverse)
    return inverse & ~exterior


def _failure(
    code: str,
    *,
    debug: dict[str, np.ndarray],
    metrics: dict[str, Any] | None = None,
    failure_region: np.ndarray | None = None,
) -> SpritePostprocessError:
    if failure_region is not None:
        debug["final_failure_region"] = _as_bool(failure_region)
    return SpritePostprocessError(code, metrics=metrics, debug=debug)


def segment_sprite(
    rgb: np.ndarray,
    *,
    expected_background: tuple[int, int, int] = (255, 0, 255),
    grabcut_iterations: int = 5,
) -> SegmentationResult:
    """Segment one chroma-key image without reading or writing the filesystem."""

    image = np.asarray(rgb)
    if image.ndim != 3 or image.shape[2] != 3 or image.dtype != np.uint8:
        raise SpritePostprocessError("INVALID_RGB_ARRAY")
    height, width = image.shape[:2]
    if height < 64 or width < 64:
        raise SpritePostprocessError("RAW_IMAGE_TOO_SMALL")
    if grabcut_iterations < 1 or grabcut_iterations > 12:
        raise SpritePostprocessError("INVALID_GRABCUT_ITERATIONS")

    expected = np.asarray(expected_background, dtype=np.float32)
    if expected.shape != (3,) or np.any(expected < 0) or np.any(expected > 255):
        raise SpritePostprocessError("INVALID_EXPECTED_BACKGROUND")

    edge_guard = max(2, min(height, width) // 80)
    ring = _border_ring((height, width), edge_guard)
    border_pixels = image[ring].astype(np.float32)
    expected_distance_at_border = np.linalg.norm(border_pixels - expected, axis=1)
    expected_family = expected_distance_at_border <= 92.0
    expected_match = float(np.mean(expected_family))
    # Absolute brightness is intentionally not part of acceptance. A diffusion
    # backdrop can be a coherent dark exposure of the requested key color. The
    # robust perimeter median and its chromatic direction are more dependable
    # than distance to literal (255, 0, 255).
    border_color = np.median(border_pixels, axis=0)

    border_estimate = np.broadcast_to(
        np.rint(border_color).astype(np.uint8), (height, width, 3)
    ).copy()
    distance_to_border = np.linalg.norm(image.astype(np.float32) - border_color, axis=2)
    distance_to_expected = np.linalg.norm(image.astype(np.float32) - expected, axis=2)
    chroma_distance = np.minimum(distance_to_border, distance_to_expected).astype(np.float32)
    border_noise = distance_to_border[ring]
    border_core_radius = float(np.clip(np.median(border_noise) + 28.0, 28.0, 72.0))
    border_coherence = float(np.mean(border_noise <= border_core_radius))
    key_norm = float(np.linalg.norm(expected))
    border_norm = float(np.linalg.norm(border_color))
    if key_norm <= 1.0 or border_norm <= 1.0:
        key_direction_similarity = 1.0 if abs(key_norm - border_norm) <= 12.0 else 0.0
    else:
        key_direction_similarity = float(
            np.clip(np.dot(border_color, expected) / (border_norm * key_norm), 0.0, 1.0)
        )
    sure_bg_threshold = float(np.clip(np.percentile(border_noise, 90) + 12.0, 18.0, 48.0))
    flood_threshold = min(78.0, sure_bg_threshold + 30.0)

    debug: dict[str, np.ndarray] = {
        "border_estimate": border_estimate,
        "chroma_distance": chroma_distance,
        "flood_bg": np.zeros((height, width), dtype=bool),
        "largest_component": np.zeros((height, width), dtype=bool),
        "candidate_fg": np.zeros((height, width), dtype=bool),
        "rejected_edge_pixels": np.zeros((height, width), dtype=bool),
        "final_failure_region": np.zeros((height, width), dtype=bool),
        "kept_components": np.zeros((height, width), dtype=bool),
        "removed_components": np.zeros((height, width), dtype=bool),
    }
    if border_coherence < 0.50 or key_direction_similarity < 0.78:
        raise _failure(
            "BACKGROUND_NOT_HIGH_CONTRAST_CHROMA",
            debug=debug,
            failure_region=ring,
            metrics={
                "background_expected_match": round(expected_match, 6),
                "background_border_coherence": round(border_coherence, 6),
                "background_key_direction_similarity": round(key_direction_similarity, 6),
            },
        )

    loose_chroma = chroma_distance <= flood_threshold
    flood_bg = _edge_connected(loose_chroma | ring)
    sure_chroma = (distance_to_expected <= sure_bg_threshold) | (
        distance_to_border <= sure_bg_threshold
    )
    sure_bg = ring | sure_chroma | flood_bg
    debug["flood_bg"] = flood_bg
    debug["sure_bg"] = sure_bg

    yy, xx = np.ogrid[:height, :width]
    normalized_x = (xx - (width - 1) / 2.0) / max(width * 0.43, 1.0)
    normalized_y = (yy - (height - 1) / 2.0) / max(height * 0.43, 1.0)
    central_region = normalized_x * normalized_x + normalized_y * normalized_y <= 1.0
    shadow_score = _shadow_likelihood(image, border_color)
    debug["shadow_likelihood"] = shadow_score

    candidate_threshold = max(sure_bg_threshold + 6.0, 31.0)
    strong_threshold = max(flood_threshold + 15.0, 72.0)
    candidate_fg = (
        ~sure_bg
        & (chroma_distance >= candidate_threshold)
        & (shadow_score < 0.82)
    )
    strong_non_background = (
        candidate_fg
        & (chroma_distance >= strong_threshold)
        & (shadow_score < 0.45)
    )
    debug["candidate_fg"] = candidate_fg

    strong_labels, strong_components = _component_data(strong_non_background)
    sure_fg = np.zeros((height, width), dtype=bool)
    for component in strong_components:
        component_mask = strong_labels == component["label"]
        central_pixels = component_mask & central_region
        if component["area"] >= max(8, int(height * width * 0.0005)) and np.any(central_pixels):
            sure_fg |= central_pixels
    if np.count_nonzero(sure_fg) < max(8, int(height * width * 0.0005)):
        failure_region = candidate_fg | strong_non_background
        debug["sure_fg"] = sure_fg
        raise _failure(
            "NO_CONFIDENT_FOREGROUND_SEED",
            debug=debug,
            failure_region=failure_region,
            metrics={
                "background_expected_match": round(expected_match, 6),
                "background_border_coherence": round(border_coherence, 6),
                "background_key_direction_similarity": round(key_direction_similarity, 6),
            },
        )

    # Eroding only the sure seed gives GrabCut unambiguous interiors while all
    # thin/detached candidates remain probable foreground and can survive.
    eroded_seed = cv2.erode(sure_fg.astype(np.uint8), np.ones((3, 3), np.uint8), iterations=1) > 0
    if np.count_nonzero(eroded_seed) >= 8:
        sure_fg = eroded_seed
    debug["sure_fg"] = sure_fg

    grab_mask = np.full((height, width), cv2.GC_PR_BGD, dtype=np.uint8)
    grab_mask[candidate_fg] = cv2.GC_PR_FGD
    grab_mask[sure_bg] = cv2.GC_BGD
    grab_mask[sure_fg] = cv2.GC_FGD
    background_model = np.zeros((1, 65), dtype=np.float64)
    foreground_model = np.zeros((1, 65), dtype=np.float64)
    try:
        cv2.grabCut(
            cv2.cvtColor(image, cv2.COLOR_RGB2BGR),
            grab_mask,
            None,
            background_model,
            foreground_model,
            grabcut_iterations,
            cv2.GC_INIT_WITH_MASK,
        )
    except cv2.error as exc:
        raise _failure(
            "GRABCUT_FAILED",
            debug=debug,
            failure_region=candidate_fg,
        ) from exc

    grab_foreground = (grab_mask == cv2.GC_FGD) | (grab_mask == cv2.GC_PR_FGD)
    # Strong chroma evidence protects narrow structures that GrabCut's GMM can
    # otherwise classify as background solely because they have few pixels.
    grab_foreground |= strong_non_background
    grab_foreground &= ~sure_bg
    debug["grabcut_foreground"] = grab_foreground

    rejected_edge = _find_edge_artifacts(grab_foreground, edge_guard)
    shadow_candidate = (
        ~sure_bg & (chroma_distance >= candidate_threshold) & (shadow_score >= 0.52)
    )
    shadow_rejection = (grab_foreground | shadow_candidate) & (shadow_score >= 0.52) & ~sure_fg
    cleaned = grab_foreground & ~rejected_edge & ~shadow_rejection
    debug["rejected_edge_pixels"] = rejected_edge

    kept, removed, largest, _ = _select_component_set(
        cleaned, central_region, edge_guard
    )
    removed |= shadow_rejection
    debug["largest_component"] = largest
    debug["kept_components"] = kept
    debug["removed_components"] = removed
    failure_region = rejected_edge | removed
    debug["final_failure_region"] = failure_region

    foreground_pixels = int(np.count_nonzero(kept))
    if foreground_pixels == 0:
        raise _failure(
            "NO_FOREGROUND_COMPONENT",
            debug=debug,
            failure_region=candidate_fg | failure_region,
        )

    ys, xs = np.where(kept)
    object_bbox = [
        int(xs.min()),
        int(ys.min()),
        int(xs.max() - xs.min() + 1),
        int(ys.max() - ys.min() + 1),
    ]
    coverage = foreground_pixels / float(height * width)
    edge_contact_pixels = np.count_nonzero(kept & _border_ring((height, width), edge_guard + 1))
    edge_contact_ratio = edge_contact_pixels / float(foreground_pixels)
    background_residual = kept & (chroma_distance < candidate_threshold + 4.0)
    background_residual_ratio = np.count_nonzero(background_residual) / float(foreground_pixels)
    holes = _internal_holes(kept)
    enclosed_area = foreground_pixels + int(np.count_nonzero(holes))
    internal_hole_ratio = int(np.count_nonzero(holes)) / float(max(enclosed_area, 1))
    shadow_residual_score = float(np.mean(shadow_score[kept]))
    separation = float(np.median(chroma_distance[kept]))
    _, kept_component_data = _component_data(kept)
    _, removed_component_data = _component_data(failure_region)
    kept_component_count = len(kept_component_data)
    removed_component_count = len(removed_component_data)
    removed_area = int(np.count_nonzero(failure_region))
    smallest_kept_component_area = min(
        (component["area"] for component in kept_component_data), default=0
    )

    coverage_score = min(1.0, coverage / 0.018) * min(1.0, (0.76 - coverage) / 0.12)
    coverage_score = float(np.clip(coverage_score, 0.0, 1.0))
    border_score = float(
        np.clip(border_coherence * 0.65 + key_direction_similarity * 0.35, 0.0, 1.0)
    )
    separation_score = float(np.clip((separation - 42.0) / 90.0, 0.0, 1.0))
    edge_score = float(np.clip(1.0 - edge_contact_ratio * 12.0, 0.0, 1.0))
    residual_score = float(np.clip(1.0 - background_residual_ratio * 4.0, 0.0, 1.0))
    shadow_clean_score = float(np.clip(1.0 - shadow_residual_score * 2.5, 0.0, 1.0))
    segmentation_confidence = (
        border_score * 0.17
        + coverage_score * 0.16
        + separation_score * 0.25
        + edge_score * 0.15
        + residual_score * 0.15
        + shadow_clean_score * 0.12
    )

    # Build a color-aware soft matte only in a narrow neighborhood of accepted
    # components. Rejected floors, shadows, and remote components cannot leak
    # back through the Gaussian edge support.
    hard_u8 = kept.astype(np.uint8)
    interior_distance = cv2.distanceTransform(hard_u8, cv2.DIST_L2, 5)
    blurred = cv2.GaussianBlur(hard_u8.astype(np.float32), (0, 0), sigmaX=0.85, sigmaY=0.85)
    support = cv2.dilate(hard_u8, np.ones((3, 3), np.uint8), iterations=1) > 0
    support &= ~sure_bg & ~failure_region
    color_matte = np.clip(
        (chroma_distance - sure_bg_threshold * 0.65) / max(strong_threshold - sure_bg_threshold, 1.0),
        0.0,
        1.0,
    )
    alpha_float = blurred * np.maximum(color_matte, 0.18) * support
    interior = kept & (interior_distance >= 1.8)
    alpha_float[interior] = np.maximum(alpha_float[interior], 0.97)
    alpha_float[kept] = np.maximum(alpha_float[kept], np.minimum(color_matte[kept] + 0.18, 1.0))
    alpha_float[failure_region | sure_bg] = 0.0
    alpha = np.rint(np.clip(alpha_float, 0.0, 1.0) * 255.0).astype(np.uint8)
    debug["soft_alpha"] = alpha
    soft_edge_pixel_ratio = float(
        np.count_nonzero((alpha > 0) & (alpha < 255)) / max(np.count_nonzero(alpha > 0), 1)
    )

    metrics: dict[str, Any] = {
        "foreground_coverage": round(coverage, 6),
        "edge_contact_ratio": round(edge_contact_ratio, 6),
        "background_residual_ratio": round(background_residual_ratio, 6),
        "internal_hole_ratio": round(internal_hole_ratio, 6),
        "component_count": kept_component_count,
        "kept_component_count": kept_component_count,
        "removed_component_count": removed_component_count,
        "removed_area": removed_area,
        "smallest_kept_component_area": int(smallest_kept_component_area),
        "object_bbox": object_bbox,
        "soft_edge_pixel_ratio": round(soft_edge_pixel_ratio, 6),
        "shadow_residual_score": round(shadow_residual_score, 6),
        "segmentation_confidence": round(float(segmentation_confidence), 6),
        "background_border_rgb": [round(float(channel), 2) for channel in border_color],
        "background_expected_match": round(expected_match, 6),
        "background_border_coherence": round(border_coherence, 6),
        "background_key_direction_similarity": round(key_direction_similarity, 6),
    }

    if coverage < 0.008 or coverage > 0.72:
        raise _failure(
            "UNRELIABLE_FOREGROUND_COVERAGE",
            debug=debug,
            metrics=metrics,
            failure_region=kept | failure_region,
        )
    if edge_contact_ratio > 0.025:
        raise _failure(
            "FOREGROUND_TOUCHES_RAW_EDGE",
            debug=debug,
            metrics=metrics,
            failure_region=kept & _border_ring((height, width), edge_guard + 1),
        )
    if background_residual_ratio > 0.18 or shadow_residual_score > 0.20:
        raise _failure(
            "BACKGROUND_OR_SHADOW_RESIDUAL",
            debug=debug,
            metrics=metrics,
            failure_region=background_residual | (kept & (shadow_score >= 0.35)),
        )
    if segmentation_confidence < 0.60:
        raise _failure(
            "LOW_SEGMENTATION_CONFIDENCE",
            debug=debug,
            metrics=metrics,
            failure_region=kept | failure_region,
        )
    if alpha.max(initial=0) == 0:
        raise _failure("NO_SUBJECT_ALPHA", debug=debug, metrics=metrics, failure_region=kept)

    return SegmentationResult(alpha=alpha, hard_mask=kept, metrics=metrics, debug=debug)


def _add_outline(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A")
    expanded = alpha.filter(ImageFilter.MaxFilter(3))
    outline_alpha = np.maximum(
        np.asarray(expanded, dtype=np.int16) - np.asarray(alpha, dtype=np.int16), 0
    ).astype(np.uint8)
    outline = Image.new("RGBA", rgba.size, (20, 24, 32, 0))
    outline.putalpha(Image.fromarray(outline_alpha, mode="L"))
    return Image.alpha_composite(outline, rgba)


def _quantize_rgba(image: Image.Image, max_colors: int) -> Image.Image:
    rgba = np.asarray(image.convert("RGBA"), dtype=np.uint8)
    alpha = Image.fromarray(rgba[:, :, 3], mode="L")
    # Quantizing a fixed RGB composite prevents fully transparent RGB values from
    # consuming palette capacity while retaining the independently soft alpha.
    composite = Image.new("RGB", image.size, (20, 24, 32))
    composite.paste(image.convert("RGB"), mask=alpha)
    quantized = composite.quantize(
        colors=max_colors,
        method=Image.Quantize.MEDIANCUT,
        dither=Image.Dither.NONE,
    ).convert("RGB")
    quantized.putalpha(alpha)
    return quantized


def _fit_sprite(
    rgb: np.ndarray,
    alpha: np.ndarray,
    hard_mask: np.ndarray,
    *,
    sprite_size: int,
    margin_ratio: float,
    max_colors: int,
    outline: bool,
) -> Image.Image:
    ys, xs = np.where(hard_mask)
    if xs.size == 0:
        raise SpritePostprocessError("NO_FOREGROUND_COMPONENT")
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    rgba = np.dstack((rgb, alpha))
    crop = Image.fromarray(rgba[y0:y1, x0:x1], mode="RGBA")
    span = max(crop.width, crop.height)
    padding = max(3, int(math.ceil(span * margin_ratio)))
    padded = Image.new(
        "RGBA",
        (crop.width + padding * 2, crop.height + padding * 2),
        (0, 0, 0, 0),
    )
    padded.alpha_composite(crop, (padding, padding))
    scale = min(sprite_size / padded.width, sprite_size / padded.height)
    resized_size = (
        max(1, int(round(padded.width * scale))),
        max(1, int(round(padded.height * scale))),
    )
    resized = padded.resize(resized_size, Image.Resampling.LANCZOS)
    sprite = Image.new("RGBA", (sprite_size, sprite_size), (0, 0, 0, 0))
    offset = ((sprite_size - resized.width) // 2, (sprite_size - resized.height) // 2)
    sprite.alpha_composite(resized, offset)
    if outline:
        sprite = _add_outline(sprite)
    return _quantize_rgba(sprite, max_colors)


def _debug_image(name: str, array: np.ndarray) -> Image.Image:
    data = np.asarray(array)
    if data.ndim == 3 and data.shape[2] == 3:
        return Image.fromarray(data.astype(np.uint8), mode="RGB")
    if name == "chroma_distance":
        normalized = np.rint(np.clip(data.astype(np.float32) / math.sqrt(3 * 255 * 255), 0, 1) * 255)
        return Image.fromarray(normalized.astype(np.uint8), mode="L")
    if name == "shadow_likelihood":
        normalized = np.rint(np.clip(data.astype(np.float32), 0, 1) * 255)
        return Image.fromarray(normalized.astype(np.uint8), mode="L")
    if data.dtype == bool:
        data = data.astype(np.uint8) * 255
    return Image.fromarray(np.clip(data, 0, 255).astype(np.uint8), mode="L")


def _write_delivery(
    stage: Path,
    sprite: Image.Image,
    result: SegmentationResult,
    metrics: dict[str, Any],
    *,
    write_debug: bool,
) -> None:
    sprite_path = stage / "processed_sprite.png"
    alpha_path = stage / "alpha_mask.png"
    sprite.save(sprite_path, format="PNG", optimize=True)
    sprite.getchannel("A").save(alpha_path, format="PNG", optimize=True)
    (stage / "metrics.json").write_text(
        json.dumps(metrics, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    if write_debug:
        _write_debug_images(stage / "debug", result.debug)


def _write_debug_images(debug_dir: Path, arrays: dict[str, np.ndarray]) -> None:
    debug_dir.mkdir()
    names = [name for name in _DEBUG_ORDER if name in arrays]
    names.extend(sorted(name for name in arrays if name not in _DEBUG_ORDER))
    for index, name in enumerate(names, start=1):
        _debug_image(name, arrays[name]).save(
            debug_dir / f"{index:02d}_{name}.png", format="PNG", optimize=True
        )


def _rejection_metrics(
    error: SpritePostprocessError,
    *,
    source_size: tuple[int, int],
    sprite_size: int,
    max_colors: int,
    outline: bool,
    elapsed_seconds: float,
) -> dict[str, Any]:
    defaults: dict[str, Any] = {
        "foreground_coverage": 0.0,
        "edge_contact_ratio": 0.0,
        "background_residual_ratio": 0.0,
        "internal_hole_ratio": 0.0,
        "component_count": 0,
        "kept_component_count": 0,
        "removed_component_count": 0,
        "removed_area": 0,
        "smallest_kept_component_area": 0,
        "object_bbox": [0, 0, 0, 0],
        "soft_edge_pixel_ratio": 0.0,
        "shadow_residual_score": 0.0,
        "segmentation_confidence": 0.0,
    }
    defaults.update(error.metrics)
    return {
        "status": "rejected",
        "failure_reason": error.code,
        **defaults,
        "raw_dimensions": [int(source_size[0]), int(source_size[1])],
        "sprite_size": sprite_size,
        "palette_limit": max_colors,
        "outline": bool(outline),
        "postprocess_seconds": round(elapsed_seconds, 3),
    }


def _write_rejection_delivery(
    stage: Path,
    error: SpritePostprocessError,
    metrics: dict[str, Any],
) -> None:
    (stage / "metrics.json").write_text(
        json.dumps(metrics, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    if error.debug:
        _write_debug_images(stage / "debug", error.debug)


def _publish_directory(destination: Path, writer: Callable[[Path], None]) -> None:
    """Populate a private sibling directory, then publish it exactly once."""

    destination.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(
        tempfile.mkdtemp(prefix=f".{destination.name}.tmp-", dir=str(destination.parent))
    )
    published = False
    try:
        writer(stage)
        if destination.exists():
            raise FileExistsError(str(destination))
        os.rename(stage, destination)
        published = True
    except FileExistsError as exc:
        raise SpritePostprocessError("OUTPUT_DIRECTORY_EXISTS") from exc
    finally:
        if not published and stage.exists():
            shutil.rmtree(stage)


def _validate_delivery(stage: Path, sprite_size: int, max_colors: int) -> dict[str, Any]:
    try:
        with Image.open(stage / "processed_sprite.png") as opened_sprite:
            if opened_sprite.format != "PNG" or opened_sprite.mode != "RGBA":
                raise SpritePostprocessError("OUTPUT_SPRITE_NOT_RGBA_PNG")
            opened_sprite.load()
            sprite = opened_sprite.copy()
        with Image.open(stage / "alpha_mask.png") as opened_alpha:
            if opened_alpha.format != "PNG" or opened_alpha.mode != "L":
                raise SpritePostprocessError("OUTPUT_ALPHA_NOT_GRAYSCALE_PNG")
            opened_alpha.load()
            alpha = opened_alpha.copy()
    except (OSError, ValueError) as exc:
        raise SpritePostprocessError("OUTPUT_VALIDATION_FAILED") from exc
    if sprite.size != (sprite_size, sprite_size) or alpha.size != sprite.size:
        raise SpritePostprocessError("OUTPUT_DIMENSIONS_INVALID")
    alpha_array = np.asarray(alpha, dtype=np.uint8)
    rgba = np.asarray(sprite, dtype=np.uint8)
    sprite_alpha = rgba[:, :, 3]
    if not np.array_equal(sprite_alpha, alpha_array):
        raise SpritePostprocessError("OUTPUT_ALPHA_MISMATCH")
    if sprite_alpha.max(initial=0) == 0:
        raise SpritePostprocessError("NO_SUBJECT_ALPHA")
    output_mask = sprite_alpha > 8
    if (
        np.any(output_mask[0])
        or np.any(output_mask[-1])
        or np.any(output_mask[:, 0])
        or np.any(output_mask[:, -1])
    ):
        raise SpritePostprocessError("SPRITE_TOUCHES_OUTPUT_EDGE")
    visible_colors = np.unique(rgba[:, :, :3][rgba[:, :, 3] > 0], axis=0)
    if len(visible_colors) > max_colors:
        raise SpritePostprocessError("PALETTE_LIMIT_EXCEEDED")
    return {
        "processed_dimensions": [sprite.width, sprite.height],
        "output_alpha_coverage": round(float(np.mean(output_mask)), 6),
        "visible_color_count": int(len(visible_colors)),
    }


def process_sprite(
    raw_path: str | Path,
    output_dir: str | Path,
    *,
    expected_background: tuple[int, int, int] = (255, 0, 255),
    sprite_size: int = 96,
    max_colors: int = 32,
    margin_ratio: float = 0.10,
    outline: bool = True,
    debug: bool = True,
) -> dict[str, Any]:
    """Create one immutable, atomically-published sprite output directory."""

    started = time.perf_counter()
    source_path = Path(raw_path)
    destination = Path(output_dir)
    if destination.exists():
        raise SpritePostprocessError("OUTPUT_DIRECTORY_EXISTS")
    if sprite_size != 96:
        raise SpritePostprocessError("SPRITE_SIZE_MUST_BE_96")
    if not 2 <= max_colors <= 32:
        raise SpritePostprocessError("INVALID_PALETTE_LIMIT")
    if not 0.06 <= margin_ratio <= 0.24:
        raise SpritePostprocessError("INVALID_MARGIN_RATIO")
    try:
        source = Image.open(source_path).convert("RGB")
        source.load()
    except (OSError, ValueError) as exc:
        raise SpritePostprocessError("INVALID_SOURCE_PNG") from exc
    rgb = np.asarray(source, dtype=np.uint8)
    try:
        result = segment_sprite(rgb, expected_background=expected_background)
    except SpritePostprocessError as exc:
        rejected_metrics = _rejection_metrics(
            exc,
            source_size=source.size,
            sprite_size=sprite_size,
            max_colors=max_colors,
            outline=outline,
            elapsed_seconds=time.perf_counter() - started,
        )
        _publish_directory(
            destination,
            lambda stage: _write_rejection_delivery(stage, exc, rejected_metrics),
        )
        raise SpritePostprocessError(
            exc.code,
            metrics=rejected_metrics,
            debug=exc.debug,
            evidence_path=destination,
        ) from exc
    sprite = _fit_sprite(
        rgb,
        result.alpha,
        result.hard_mask,
        sprite_size=sprite_size,
        margin_ratio=margin_ratio,
        max_colors=max_colors,
        outline=outline,
    )
    output_alpha = np.asarray(sprite.getchannel("A"), dtype=np.uint8)
    output_soft_ratio = float(
        np.count_nonzero((output_alpha > 0) & (output_alpha < 255))
        / max(np.count_nonzero(output_alpha > 0), 1)
    )
    metrics = {
        "status": "success",
        **result.metrics,
        "raw_dimensions": [source.width, source.height],
        "sprite_size": sprite_size,
        "palette_limit": max_colors,
        "outline": bool(outline),
        "soft_edge_pixel_ratio": round(output_soft_ratio, 6),
    }

    def write_success(stage: Path) -> None:
        _write_delivery(stage, sprite, result, metrics, write_debug=debug)
        metrics.update(_validate_delivery(stage, sprite_size, max_colors))
        metrics["postprocess_seconds"] = round(time.perf_counter() - started, 3)
        (stage / "metrics.json").write_text(
            json.dumps(metrics, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

    _publish_directory(destination, write_success)
    return metrics


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Segment a chroma-key object with GrabCut and atomically publish a 96px sprite."
    )
    parser.add_argument("raw_png", type=Path)
    parser.add_argument("output_directory", type=Path)
    parser.add_argument("--background", default="255,0,255")
    parser.add_argument("--colors", type=int, default=32)
    parser.add_argument("--no-outline", action="store_true")
    parser.add_argument("--no-debug", action="store_true")
    args = parser.parse_args()
    try:
        parts = tuple(int(part) for part in args.background.split(","))
    except ValueError:
        parts = ()
    if len(parts) != 3:
        print(json.dumps({"status": "failed", "failure_reason": "INVALID_BACKGROUND_ARGUMENT"}))
        return 2
    try:
        metrics = process_sprite(
            args.raw_png,
            args.output_directory,
            expected_background=parts,
            max_colors=args.colors,
            outline=not args.no_outline,
            debug=not args.no_debug,
        )
    except SpritePostprocessError as exc:
        payload: dict[str, Any] = {
            "status": "rejected" if exc.evidence_path is not None else "failed",
            "failure_reason": exc.code,
            "metrics": exc.metrics,
        }
        if exc.evidence_path is not None:
            payload["evidence_directory"] = str(exc.evidence_path)
        print(
            json.dumps(payload, ensure_ascii=False)
        )
        return 2
    print(json.dumps(metrics, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
