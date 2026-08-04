from __future__ import annotations

import csv
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_ROOT = ROOT / "output"
CASES_PATH = ROOT / "test_cases" / "cases.json"
EVALUATIONS_PATH = ROOT / "test_cases" / "evaluations.json"
REPORT_DIRECTORY = Path(__file__).resolve().parent


def font(size: int) -> ImageFont.ImageFont:
    for path in (Path("C:/Windows/Fonts/arial.ttf"), Path("C:/Windows/Fonts/segoeui.ttf")):
        if path.is_file():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


def checkerboard(size: tuple[int, int], cell: int = 12) -> Image.Image:
    image = Image.new("RGB", size, (42, 48, 58))
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if (x // cell + y // cell) % 2 == 0:
                draw.rectangle((x, y, x + cell - 1, y + cell - 1), fill=(68, 76, 88))
    return image


def contain(image: Image.Image, size: tuple[int, int], nearest: bool = False) -> Image.Image:
    copy = image.copy()
    copy.thumbnail(size, Image.Resampling.NEAREST if nearest else Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    canvas.alpha_composite(copy.convert("RGBA"), ((size[0] - copy.width) // 2, (size[1] - copy.height) // 2))
    return canvas


def build_comparison() -> None:
    cases = json.loads(CASES_PATH.read_text(encoding="utf-8"))["cases"]
    cell_width, cell_height = 560, 310
    sheet = Image.new("RGB", (cell_width * 3, 58 + cell_height * 5), (17, 24, 39))
    draw = ImageDraw.Draw(sheet)
    draw.text((18, 15), "Forge Object Sprite Spike 0 - raw / processed comparison", font=font(26), fill=(235, 241, 249))
    for row, case in enumerate(cases):
        directories = sorted((OUTPUT_ROOT / case["case_id"]).glob("seed_*"))
        for column, directory in enumerate(directories):
            x, y = column * cell_width, 58 + row * cell_height
            manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
            draw.rectangle((x + 4, y + 4, x + cell_width - 5, y + cell_height - 5), outline=(55, 72, 94), width=2)
            title = f"{case['case_id'].upper()} / {directory.name} / {manifest['status'].upper()}"
            draw.text((x + 16, y + 12), title, font=font(17), fill=(121, 225, 181) if manifest["status"] == "success" else (251, 113, 133))
            raw = Image.open(directory / "raw.png").convert("RGB")
            raw.thumbnail((250, 230), Image.Resampling.LANCZOS)
            sheet.paste(raw, (x + 16 + (250 - raw.width) // 2, y + 48 + (230 - raw.height) // 2))
            processed_path = directory / "processed_sprite.png"
            preview = checkerboard((250, 230))
            if processed_path.is_file():
                processed = Image.open(processed_path).convert("RGBA")
                enlarged = contain(processed, (224, 204), nearest=True)
                preview.paste(enlarged, (13, 13), enlarged)
            else:
                preview_draw = ImageDraw.Draw(preview)
                reason = manifest.get("failure_reason", "failed")
                preview_draw.multiline_text((16, 80), f"REJECTED\n{reason}", font=font(18), fill=(251, 113, 133), spacing=8)
            sheet.paste(preview, (x + 294, y + 48))
            draw.text((x + 18, y + 283), "RAW 512x512", font=font(14), fill=(148, 163, 184))
            draw.text((x + 298, y + 283), "PROCESSED 96x96", font=font(14), fill=(148, 163, 184))
    sheet.save(REPORT_DIRECTORY / "raw_processed_comparison.png", optimize=True)


def build_anchor_debug() -> None:
    runs = []
    for case_directory in sorted(OUTPUT_ROOT.glob("case_*")):
        for directory in sorted(case_directory.glob("seed_*")):
            if (directory / "processed_sprite.png").is_file() and (directory / "anchors.json").is_file():
                runs.append(directory)
    cell_width, cell_height = 400, 350
    columns = 3
    rows = (len(runs) + columns - 1) // columns
    sheet = Image.new("RGB", (cell_width * columns, 54 + cell_height * rows), (17, 24, 39))
    draw = ImageDraw.Draw(sheet)
    draw.text((18, 14), "Alpha + Godot AnchorResolver debug", font=font(25), fill=(235, 241, 249))
    colors = {
        "GripPrimary": (45, 212, 191),
        "GripSecondary": (250, 204, 21),
        "Muzzle": (56, 189, 248),
        "Tip": (251, 113, 133),
        "SpinPivot": (192, 132, 252),
    }
    for index, directory in enumerate(runs):
        column, row = index % columns, index // columns
        x, y = column * cell_width, 54 + row * cell_height
        draw.rectangle((x + 4, y + 4, x + cell_width - 5, y + cell_height - 5), outline=(55, 72, 94), width=2)
        draw.text((x + 14, y + 10), f"{directory.parent.name}/{directory.name}", font=font(16), fill=(226, 232, 240))
        background = checkerboard((288, 288), 18)
        sprite = Image.open(directory / "processed_sprite.png").convert("RGBA").resize((288, 288), Image.Resampling.NEAREST)
        background.paste(sprite, (0, 0), sprite)
        anchors = json.loads((directory / "anchors.json").read_text(encoding="utf-8"))
        anchor_draw = ImageDraw.Draw(background)
        for name, color in colors.items():
            if name not in anchors:
                continue
            ax, ay = anchors[name]
            point = (int(ax * 3), int(ay * 3))
            anchor_draw.ellipse((point[0] - 6, point[1] - 6, point[0] + 6, point[1] + 6), fill=color, outline=(0, 0, 0), width=2)
            anchor_draw.text((point[0] + 8, point[1] - 8), name, font=font(12), fill=color, stroke_width=2, stroke_fill=(0, 0, 0))
        sheet.paste(background, (x + 55, y + 42))
    sheet.save(REPORT_DIRECTORY / "alpha_anchor_debug.png", optimize=True)


def build_scores_csv() -> None:
    if not EVALUATIONS_PATH.is_file():
        return
    evaluations = json.loads(EVALUATIONS_PATH.read_text(encoding="utf-8"))["runs"]
    fields = [
        "case_id", "run_id", "single_subject", "no_people_hands_text", "complete_uncropped",
        "facing_consistent", "identity_recognizable", "sketch_influence", "description_influence",
        "background_alpha_success", "recognizable_at_96", "holdable_region_exists", "grip_primary_reasonable",
        "effect_anchor_reasonable", "seed_variation_acceptable", "generation_seconds", "retry_count", "status", "notes",
    ]
    with (REPORT_DIRECTORY / "spike_scores.csv").open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(evaluations)


if __name__ == "__main__":
    REPORT_DIRECTORY.mkdir(parents=True, exist_ok=True)
    build_comparison()
    build_anchor_debug()
    build_scores_csv()
