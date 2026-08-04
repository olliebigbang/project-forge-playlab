from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent
RUBRIC_PATH = ROOT / "human_review_rubric.json"
HUMAN_FIELDS = (
    "single_complete_subject",
    "no_person_hand_text",
    "canonical_identity_recognizable_raw",
    "required_parts_visible_count",
    "silhouette_matches",
    "forbidden_weapon_substitution",
    "recognizable_at_96x96",
    "facing_consistency",
)


def font(size: int, bold: bool = False) -> ImageFont.ImageFont:
    candidates = (
        "C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf",
        "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf",
    )
    for candidate in candidates:
        try:
            return ImageFont.truetype(candidate, size=size)
        except OSError:
            pass
    return ImageFont.load_default()


def contain_on(image: Image.Image, size: tuple[int, int], background=(34, 37, 44, 255)) -> Image.Image:
    rgba = image.convert("RGBA")
    rgba.thumbnail(size, Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", size, background)
    canvas.alpha_composite(rgba, ((size[0] - rgba.width) // 2, (size[1] - rgba.height) // 2))
    return canvas


def checkerboard(size: tuple[int, int], cell: int = 16) -> Image.Image:
    canvas = Image.new("RGBA", size, (220, 220, 220, 255))
    draw = ImageDraw.Draw(canvas)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if (x // cell + y // cell) % 2:
                draw.rectangle((x, y, x + cell - 1, y + cell - 1), fill=(174, 178, 186, 255))
    return canvas


def sprite_panel(path: Path | None, size: tuple[int, int]) -> Image.Image:
    board = checkerboard(size)
    if path is None or not path.is_file():
        draw = ImageDraw.Draw(board)
        draw.text((12, size[1] // 2 - 10), "NO VALID SPRITE", fill=(180, 20, 32), font=font(18, True))
        return board
    with Image.open(path) as opened:
        sprite = opened.convert("RGBA")
        sprite = sprite.resize((size[1], size[1]), Image.Resampling.NEAREST)
    board.alpha_composite(sprite, ((size[0] - sprite.width) // 2, 0))
    return board


def mask_panel(path: Path | None, size: tuple[int, int]) -> Image.Image:
    canvas = Image.new("RGB", size, (25, 27, 31))
    if path is None or not path.is_file():
        ImageDraw.Draw(canvas).text((12, size[1] // 2 - 10), "NO ALPHA", fill=(220, 80, 80), font=font(18, True))
        return canvas
    with Image.open(path) as opened:
        mask = opened.convert("L").resize((size[1], size[1]), Image.Resampling.NEAREST)
    canvas.paste(mask, ((size[0] - mask.width) // 2, 0))
    return canvas


def wrap(draw: ImageDraw.ImageDraw, text: str, width: int, selected_font: ImageFont.ImageFont) -> list[str]:
    words = text.split()
    lines: list[str] = []
    current = ""
    for word in words:
        candidate = word if not current else f"{current} {word}"
        if draw.textlength(candidate, font=selected_font) <= width:
            current = candidate
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def load_run(run_root: Path) -> tuple[dict, list[tuple[dict, Path, dict]]]:
    summary = json.loads((run_root / "generation_summary.json").read_text(encoding="utf-8"))
    rows: list[tuple[dict, Path, dict]] = []
    for item in summary["results"]:
        result_dir = ROOT.parent.parent.parent / item["output_directory"]
        manifest = json.loads((result_dir / "manifest.json").read_text(encoding="utf-8"))
        rows.append((item, result_dir, manifest))
    if len(rows) != 8:
        raise ValueError(f"expected eight result directories, got {len(rows)}")
    return summary, rows


def build_comparison(rows: list[tuple[dict, Path, dict]], target: Path) -> None:
    width, header_height, row_height = 1320, 74, 284
    canvas = Image.new("RGB", (width, header_height + row_height * len(rows)), (18, 20, 25))
    draw = ImageDraw.Draw(canvas)
    draw.text((24, 18), "Gate B 4A — Actual Raw / Transparent 96x96 / Alpha", fill="white", font=font(30, True))
    for index, (item, result_dir, manifest) in enumerate(rows):
        top = header_height + index * row_height
        draw.rectangle((0, top, width, top + row_height - 1), fill=(28, 31, 38) if index % 2 == 0 else (35, 38, 46))
        draw.text((20, top + 18), f"{item['case_id']}  seed {item['seed']}", fill=(255, 220, 120), font=font(23, True))
        draw.text((20, top + 55), f"status: {manifest['status']}", fill=(210, 215, 224), font=font(17))
        draw.text((20, top + 82), f"gen {manifest['generation_seconds']}s  post {manifest['postprocess_seconds']}s", fill=(170, 177, 190), font=font(15))
        raw_path = result_dir / "raw.png"
        if raw_path.is_file():
            with Image.open(raw_path) as opened:
                raw = contain_on(opened, (360, 240))
            canvas.paste(raw.convert("RGB"), (250, top + 22))
        else:
            draw.rectangle((250, top + 22, 609, top + 261), fill=(55, 32, 36))
            draw.text((330, top + 120), "NO RAW OUTPUT", fill=(240, 100, 110), font=font(20, True))
        canvas.paste(sprite_panel(result_dir / "processed_sprite.png", (320, 240)).convert("RGB"), (640, top + 22))
        canvas.paste(mask_panel(result_dir / "alpha_mask.png", (320, 240)), (990, top + 22))
    target.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(target, format="PNG", optimize=True)


def build_parts_review(rows: list[tuple[dict, Path, dict]], rubric: dict, target: Path) -> None:
    width, card_width, card_height = 1500, 750, 620
    canvas = Image.new("RGB", (width, card_height * 4), (20, 22, 27))
    draw = ImageDraw.Draw(canvas)
    body_font = font(18)
    for index, (item, result_dir, _manifest) in enumerate(rows):
        column = index % 2
        row = index // 2
        left, top = column * card_width, row * card_height
        draw.rectangle((left + 8, top + 8, left + card_width - 8, top + card_height - 8), fill=(31, 34, 41), outline=(85, 91, 105), width=2)
        case = rubric["cases"][item["case_id"]]
        draw.text((left + 26, top + 22), f"{item['case_id']} — seed {item['seed']}", fill=(255, 220, 120), font=font(24, True))
        draw.text((left + 26, top + 58), f"Identity: {case['canonical_identity']}", fill="white", font=font(20, True))
        raw_path = result_dir / "raw.png"
        if raw_path.is_file():
            with Image.open(raw_path) as opened:
                raw = contain_on(opened, (450, 390))
            canvas.paste(raw.convert("RGB"), (left + 24, top + 100))
        else:
            draw.rectangle((left + 24, top + 100, left + 473, top + 489), fill=(55, 32, 36))
            draw.text((left + 155, top + 280), "NO RAW", fill=(240, 100, 110), font=font(22, True))
        text_x = left + 500
        draw.text((text_x, top + 105), "Required parts", fill=(190, 205, 255), font=font(19, True))
        y = top + 145
        for part in case["required_part_concepts"]:
            lines = wrap(draw, part, 215, body_font)
            draw.rectangle((text_x, y + 3, text_x + 18, y + 21), outline=(220, 225, 235), width=2)
            for line_index, line in enumerate(lines):
                draw.text((text_x + 28, y + line_index * 22), line, fill=(225, 228, 235), font=body_font)
            y += max(42, len(lines) * 22 + 16)
        draw.text((text_x, top + 325), "Raw identity  [ ]", fill=(225, 228, 235), font=body_font)
        draw.text((text_x, top + 365), "96x96 identity [ ]", fill=(225, 228, 235), font=body_font)
        draw.text((text_x, top + 405), "Single complete [ ]", fill=(225, 228, 235), font=body_font)
        draw.text((text_x, top + 445), "No person/hand/text [ ]", fill=(225, 228, 235), font=body_font)
        draw.text((left + 26, top + 530), "Judge only what is visible in this actual image. Do not infer from its prompt.", fill=(165, 171, 184), font=font(16))
    target.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(target, format="PNG", optimize=True)


def write_review_csv(rows: list[tuple[dict, Path, dict]], path: Path) -> None:
    fieldnames = [
        "case_id",
        "seed",
        *HUMAN_FIELDS,
        "alpha_delivery_success",
        "generation_seconds",
        "postprocess_seconds",
        "reviewer",
        "notes",
    ]
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fieldnames)
        writer.writeheader()
        for item, _result_dir, manifest in rows:
            row = {field: "" for field in fieldnames}
            row.update(
                {
                    "case_id": item["case_id"],
                    "seed": item["seed"],
                    "alpha_delivery_success": str(bool(manifest["alpha_delivery_success"])).lower(),
                    "generation_seconds": manifest["generation_seconds"],
                    "postprocess_seconds": manifest["postprocess_seconds"],
                }
            )
            writer.writerow(row)


def main() -> int:
    parser = argparse.ArgumentParser(description="Build actual-image human-review assets for Gate B 4A.")
    parser.add_argument("--run-root", required=True, type=Path)
    args = parser.parse_args()
    run_root = args.run_root.resolve()
    _summary, rows = load_run(run_root)
    rubric = json.loads(RUBRIC_PATH.read_text(encoding="utf-8"))
    review_root = run_root / "human_review"
    build_comparison(rows, review_root / "raw_processed_comparison.png")
    build_parts_review(rows, rubric, review_root / "required_parts_review.png")
    write_review_csv(rows, review_root / "human_visual_review.csv")
    print(
        json.dumps(
            {
                "status": "HUMAN_REVIEW_PACKET_READY",
                "review_csv": str(review_root / "human_visual_review.csv"),
                "raw_processed_comparison": str(review_root / "raw_processed_comparison.png"),
                "required_parts_review": str(review_root / "required_parts_review.png"),
            }
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
