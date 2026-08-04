from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
REPORTS = ROOT / "reports"
OUTPUT = ROOT / "output"
FONT_PATH = Path(__file__).resolve().parents[4] / "assets" / "fonts" / "NotoSansCJKsc-Regular.otf"
CASES = [
    ("spike2_case_01", "木桌 / returning"),
    ("spike2_case_02", "木椅 / sustained"),
    ("spike2_case_03", "旧茶壶 / sustained"),
    ("spike2_case_04", "巨大鸡腿 / heavy"),
    ("spike2_case_05", "机械雨伞 / sustained"),
]
LOG_AUDIT_FIELDS = (
    "prompt_policy_version",
    "control_type",
    "control_strength",
    "generation_seconds",
    "postprocess_seconds",
)


def enrich_generation_logs() -> None:
    """Append manifest-backed audit facts without replacing original run logs."""
    for manifest_path in sorted(OUTPUT.glob("*/*/manifest.json")):
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        log_path = manifest_path.with_name("generation.log")
        original = log_path.read_text(encoding="utf-8") if log_path.is_file() else ""
        lines = original.splitlines()
        existing_keys = {line.split("=", 1)[0] for line in lines if "=" in line}
        additions: list[str] = []
        if "audit_enriched_from_manifest" not in existing_keys:
            additions.append("audit_enriched_from_manifest=true")
        for field in LOG_AUDIT_FIELDS:
            if field in manifest and field not in existing_keys:
                additions.append(f"{field}={manifest[field]}")
        if not additions:
            continue
        payload = "\n".join(lines + additions) + "\n"
        log_path.write_text(payload, encoding="utf-8")


def checkerboard(size: tuple[int, int], cell: int = 12) -> Image.Image:
    image = Image.new("RGB", size, (38, 45, 56))
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if (x // cell + y // cell) % 2:
                draw.rectangle((x, y, x + cell - 1, y + cell - 1), fill=(68, 77, 91))
    return image


def fit(image: Image.Image, box: tuple[int, int], nearest: bool = False) -> Image.Image:
    result = image.copy()
    result.thumbnail(box, Image.Resampling.NEAREST if nearest else Image.Resampling.LANCZOS)
    return result


def paste_center(canvas: Image.Image, image: Image.Image, region: tuple[int, int, int, int]) -> None:
    left, top, right, bottom = region
    x = left + (right - left - image.width) // 2
    y = top + (bottom - top - image.height) // 2
    if image.mode == "RGBA":
        canvas.paste(image, (x, y), image)
    else:
        canvas.paste(image, (x, y))


def build_raw_processed() -> None:
    width, row_height, header = 1120, 250, 66
    canvas = Image.new("RGB", (width, header + row_height * len(CASES)), (10, 18, 31))
    draw = ImageDraw.Draw(canvas)
    title_font = ImageFont.truetype(str(FONT_PATH), 28)
    label_font = ImageFont.truetype(str(FONT_PATH), 19)
    small_font = ImageFont.truetype(str(FONT_PATH), 15)
    draw.text((24, 16), "Spike 2 official policy1 — raw vs transparent 96×96", font=title_font, fill=(238, 244, 255))
    for index, (case_id, label) in enumerate(CASES):
        top = header + index * row_height
        draw.rectangle((12, top + 5, width - 12, top + row_height - 5), fill=(18, 32, 50), outline=(51, 65, 85), width=2)
        draw.text((28, top + 18), f"{case_id}  {label}", font=label_font, fill=(186, 230, 253))
        draw.text((330, top + 18), "RAW 512×512", font=small_font, fill=(203, 213, 225))
        draw.text((780, top + 18), "PROCESSED 96×96", font=small_font, fill=(203, 213, 225))
        run = OUTPUT / case_id / "seed_52002_policy1"
        raw = fit(Image.open(run / "raw.png").convert("RGB"), (310, 190))
        sprite = fit(Image.open(run / "processed_sprite.png").convert("RGBA"), (190, 190), nearest=True)
        paste_center(canvas, raw, (210, top + 48, 580, top + 238))
        check = checkerboard((400, 190))
        paste_center(check, sprite, (0, 0, 400, 190))
        canvas.paste(check, (680, top + 48))
    canvas.save(REPORTS / "identity_raw_processed_comparison.png")


def build_policy_ab() -> None:
    cell, label_height, header = 244, 42, 70
    width = cell * len(CASES)
    height = header + (cell + label_height) * 2
    canvas = Image.new("RGB", (width, height), (10, 18, 31))
    draw = ImageDraw.Draw(canvas)
    title_font = ImageFont.truetype(str(FONT_PATH), 25)
    label_font = ImageFont.truetype(str(FONT_PATH), 16)
    draw.text((20, 16), "Same seed: diagnostic policy0 (top) vs corrected generic policy1 (bottom)", font=title_font, fill=(238, 244, 255))
    for column, (case_id, label) in enumerate(CASES):
        x = column * cell
        for row, run_name in enumerate(("seed_52002", "seed_52002_policy1")):
            y = header + row * (cell + label_height)
            raw = fit(Image.open(OUTPUT / case_id / run_name / "raw.png").convert("RGB"), (cell - 12, cell - 12))
            paste_center(canvas, raw, (x + 4, y + 4, x + cell - 4, y + cell - 4))
            prefix = "policy0" if row == 0 else "policy1"
            draw.text((x + 8, y + cell + 8), f"{prefix} · {label}", font=label_font, fill=(252, 211, 77) if row == 0 else (186, 230, 253))
    canvas.save(REPORTS / "prompt_policy_ab_comparison.png")


if __name__ == "__main__":
    REPORTS.mkdir(parents=True, exist_ok=True)
    enrich_generation_logs()
    build_raw_processed()
    build_policy_ab()
