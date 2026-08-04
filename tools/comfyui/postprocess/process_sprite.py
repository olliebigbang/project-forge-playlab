from __future__ import annotations

import argparse
import json
import math
import time
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageFilter


class SpritePostprocessError(RuntimeError):
    pass


def _largest_component(mask: np.ndarray) -> np.ndarray:
    count, labels, stats, _ = cv2.connectedComponentsWithStats(mask.astype(np.uint8), 8)
    if count <= 1:
        raise SpritePostprocessError("NO_FOREGROUND_COMPONENT")
    candidates = [(int(stats[index, cv2.CC_STAT_AREA]), index) for index in range(1, count)]
    area, index = max(candidates)
    if area < 64:
        raise SpritePostprocessError("FOREGROUND_TOO_SMALL")
    return labels == index


def _border_pixels(rgb: np.ndarray) -> np.ndarray:
    return np.concatenate((rgb[0], rgb[-1], rgb[1:-1, 0], rgb[1:-1, -1]), axis=0)


def _background_mask(rgb: np.ndarray, expected_rgb: tuple[int, int, int]) -> tuple[np.ndarray, np.ndarray, float]:
    border = _border_pixels(rgb).astype(np.float32)
    expected = np.array(expected_rgb, dtype=np.float32)
    expected_distance = np.linalg.norm(border - expected, axis=1)
    # Diffusion models preserve the requested chroma hue more reliably than the
    # exact RGB value. Accept a broad magenta family, then rely on border flood
    # fill and largest-component validation before producing alpha.
    expected_ratio = float(np.mean(expected_distance < 180.0))
    border_median = np.median(border, axis=0)
    if expected_ratio < 0.18:
        raise SpritePostprocessError("BACKGROUND_NOT_HIGH_CONTRAST_CHROMA")
    distance = np.linalg.norm(rgb.astype(np.float32) - border_median, axis=2)
    permissive = (distance < 82.0).astype(np.uint8)
    flood_source = permissive.copy()
    flood_mask = np.zeros((rgb.shape[0] + 2, rgb.shape[1] + 2), dtype=np.uint8)
    for x in range(rgb.shape[1]):
        if flood_source[0, x]:
            cv2.floodFill(flood_source, flood_mask, (x, 0), 2)
        if flood_source[-1, x]:
            cv2.floodFill(flood_source, flood_mask, (x, rgb.shape[0] - 1), 2)
    for y in range(rgb.shape[0]):
        if flood_source[y, 0]:
            cv2.floodFill(flood_source, flood_mask, (0, y), 2)
        if flood_source[y, -1]:
            cv2.floodFill(flood_source, flood_mask, (rgb.shape[1] - 1, y), 2)
    return flood_source == 2, border_median, expected_ratio


def _quantize_rgba(image: Image.Image, colors: int) -> Image.Image:
    rgba = np.array(image.convert("RGBA"), dtype=np.uint8)
    alpha = Image.fromarray(rgba[:, :, 3], mode="L")
    composite = Image.new("RGB", image.size, (32, 32, 40))
    composite.paste(image.convert("RGB"), mask=alpha)
    quantized = composite.quantize(colors=max(2, colors - 1), method=Image.Quantize.MEDIANCUT).convert("RGB")
    quantized.putalpha(alpha)
    return quantized


def _add_outline(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A")
    expanded = alpha.filter(ImageFilter.MaxFilter(3))
    outline_alpha = np.maximum(np.array(expanded, dtype=np.int16) - np.array(alpha, dtype=np.int16), 0).astype(np.uint8)
    outline = Image.new("RGBA", rgba.size, (20, 24, 32, 0))
    outline.putalpha(Image.fromarray(outline_alpha, mode="L"))
    return Image.alpha_composite(outline, rgba)


def process_sprite(
    raw_path: Path,
    sprite_path: Path,
    mask_path: Path,
    *,
    expected_background: tuple[int, int, int] = (255, 0, 255),
    sprite_size: int = 96,
    max_colors: int = 32,
    margin_ratio: float = 0.10,
    outline: bool = True,
) -> dict:
    started = time.perf_counter()
    try:
        source = Image.open(raw_path).convert("RGB")
        source.load()
    except (OSError, ValueError) as exc:
        raise SpritePostprocessError("INVALID_SOURCE_PNG") from exc
    rgb = np.array(source, dtype=np.uint8)
    if rgb.shape[0] < 64 or rgb.shape[1] < 64:
        raise SpritePostprocessError("RAW_IMAGE_TOO_SMALL")
    background, border_color, border_match = _background_mask(rgb, expected_background)
    foreground = _largest_component(~background)
    foreground = cv2.morphologyEx(foreground.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8)) > 0
    foreground = _largest_component(foreground)
    coverage = float(np.mean(foreground))
    if coverage < 0.015 or coverage > 0.82:
        raise SpritePostprocessError("UNRELIABLE_FOREGROUND_COVERAGE")
    ys, xs = np.where(foreground)
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    if x0 <= 1 or y0 <= 1 or x1 >= rgb.shape[1] - 1 or y1 >= rgb.shape[0] - 1:
        raise SpritePostprocessError("OBJECT_TOUCHES_RAW_EDGE")
    distance = np.linalg.norm(rgb.astype(np.float32) - border_color.astype(np.float32), axis=2)
    soft_alpha = np.clip((distance - 22.0) / 54.0, 0.0, 1.0)
    keep = cv2.dilate(foreground.astype(np.uint8), np.ones((5, 5), np.uint8), iterations=1) > 0
    alpha = np.where(keep, soft_alpha, 0.0)
    alpha = np.maximum(alpha, foreground.astype(np.float32) * 0.88)
    rgba = np.dstack((rgb, np.rint(alpha * 255.0).astype(np.uint8)))
    cropped = Image.fromarray(rgba[y0:y1, x0:x1], mode="RGBA")
    span = max(cropped.width, cropped.height)
    padding = max(2, int(math.ceil(span * margin_ratio)))
    padded = Image.new("RGBA", (cropped.width + padding * 2, cropped.height + padding * 2), (0, 0, 0, 0))
    padded.alpha_composite(cropped, (padding, padding))
    scale = min(sprite_size / padded.width, sprite_size / padded.height)
    resized_size = (max(1, int(round(padded.width * scale))), max(1, int(round(padded.height * scale))))
    resized = padded.resize(resized_size, Image.Resampling.LANCZOS)
    sprite = Image.new("RGBA", (sprite_size, sprite_size), (0, 0, 0, 0))
    offset = ((sprite_size - resized.width) // 2, (sprite_size - resized.height) // 2)
    sprite.alpha_composite(resized, offset)
    sprite = _quantize_rgba(sprite, max_colors)
    if outline:
        sprite = _add_outline(sprite)
    output_alpha = np.array(sprite.getchannel("A"), dtype=np.uint8)
    if output_alpha.max(initial=0) == 0:
        raise SpritePostprocessError("NO_SUBJECT_ALPHA")
    output_mask = output_alpha > 8
    if np.any(output_mask[0]) or np.any(output_mask[-1]) or np.any(output_mask[:, 0]) or np.any(output_mask[:, -1]):
        raise SpritePostprocessError("SPRITE_TOUCHES_OUTPUT_EDGE")
    out_y, out_x = np.where(output_mask)
    opaque_bounds = [int(out_x.min()), int(out_y.min()), int(out_x.max() - out_x.min() + 1), int(out_y.max() - out_y.min() + 1)]
    sprite_path.parent.mkdir(parents=True, exist_ok=True)
    sprite.save(sprite_path, format="PNG", optimize=True)
    Image.fromarray(output_alpha, mode="L").save(mask_path, format="PNG", optimize=True)
    verification = Image.open(sprite_path).convert("RGBA")
    verification.load()
    if verification.size != (sprite_size, sprite_size) or verification.getchannel("A").getextrema()[1] == 0:
        raise SpritePostprocessError("OUTPUT_VALIDATION_FAILED")
    return {
        "postprocess_seconds": round(time.perf_counter() - started, 3),
        "raw_dimensions": [source.width, source.height],
        "processed_dimensions": [verification.width, verification.height],
        "alpha_coverage": round(float(np.mean(output_alpha > 8)), 4),
        "opaque_bounds": opaque_bounds,
        "background_border_rgb": [round(float(value), 1) for value in border_color],
        "background_expected_match": round(border_match, 4),
        "palette_limit": max_colors,
        "outline": outline,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Convert a flat-background ComfyUI object PNG into a validated transparent sprite.")
    parser.add_argument("raw_png", type=Path)
    parser.add_argument("processed_png", type=Path)
    parser.add_argument("alpha_mask_png", type=Path)
    parser.add_argument("--background", default="255,0,255")
    parser.add_argument("--size", type=int, default=96)
    parser.add_argument("--colors", type=int, default=32)
    parser.add_argument("--no-outline", action="store_true")
    args = parser.parse_args()
    background = tuple(int(part) for part in args.background.split(","))
    if len(background) != 3:
        raise SystemExit("--background must be R,G,B")
    try:
        result = process_sprite(
            args.raw_png,
            args.processed_png,
            args.alpha_mask_png,
            expected_background=background,
            sprite_size=args.size,
            max_colors=args.colors,
            outline=not args.no_outline,
        )
    except SpritePostprocessError as exc:
        print(json.dumps({"status": "failed", "failure_reason": str(exc)}))
        return 2
    print(json.dumps({"status": "success", **result}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
