from __future__ import annotations

import argparse
import csv
import json
import os
import shutil
import tempfile
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent
PROJECT_ROOT = ROOT.parent.parent.parent
FROZEN_PATH = ROOT / "frozen_4a_evidence.json"
POSTMORTEM_PATH = ROOT / "v1_postmortem" / "v1_postmortem_summary.json"
RUBRIC_PATH = ROOT / "human_structure_rubric.json"
PACKET_ROOT = ROOT / "review_packets"

REVIEW_FIELDS = (
    "case_id",
    "seed",
    "raw_identity_recognizable",
    "canonical_identity_recognizable_96x96",
    "no_person_or_hand",
    "no_extraneous_text_or_watermark",
    "intrinsic_identity_markings_present",
    "subject_severely_missing",
    "background_ground_or_shadow_residual",
    "part_1",
    "part_1_visible_raw",
    "part_1_preserved_v2",
    "part_2",
    "part_2_visible_raw",
    "part_2_preserved_v2",
    "part_3",
    "part_3_visible_raw",
    "part_3_preserved_v2",
    "required_parts_visible_raw_count",
    "required_parts_preserved_v2_count",
    "reviewer",
    "notes",
)


def _read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"JSON root must be an object: {path}")
    return value


def _font(size: int, bold: bool = False) -> ImageFont.ImageFont:
    candidates = (
        "C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf",
        "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf",
    )
    for candidate in candidates:
        try:
            return ImageFont.truetype(candidate, size=size)
        except OSError:
            continue
    return ImageFont.load_default()


def _contain(image: Image.Image, size: tuple[int, int], background=(28, 31, 38, 255)) -> Image.Image:
    item = image.convert("RGBA")
    item.thumbnail(size, Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", size, background)
    canvas.alpha_composite(item, ((size[0] - item.width) // 2, (size[1] - item.height) // 2))
    return canvas


def _checkerboard(size: tuple[int, int], cell: int = 14) -> Image.Image:
    canvas = Image.new("RGBA", size, (224, 224, 224, 255))
    draw = ImageDraw.Draw(canvas)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if (x // cell + y // cell) % 2:
                draw.rectangle((x, y, x + cell - 1, y + cell - 1), fill=(176, 181, 190, 255))
    return canvas


def _sprite_panel(path: Path | None, size: tuple[int, int], failure: str = "") -> Image.Image:
    board = _checkerboard(size)
    if path is None or not path.is_file():
        draw = ImageDraw.Draw(board)
        label = failure or "NO VALID SPRITE"
        draw.multiline_text((12, size[1] // 2 - 20), label, fill=(180, 25, 38), font=_font(15, True), spacing=4)
        return board
    with Image.open(path) as opened:
        sprite = opened.copy().convert("RGBA")
    scale = max(1, min(size) // max(sprite.size))
    scaled = sprite.resize((sprite.width * scale, sprite.height * scale), Image.Resampling.NEAREST)
    if scaled.width > size[0] or scaled.height > size[1]:
        scaled.thumbnail(size, Image.Resampling.NEAREST)
    board.alpha_composite(scaled, ((size[0] - scaled.width) // 2, (size[1] - scaled.height) // 2))
    return board


def _image_panel(path: Path | None, size: tuple[int, int], missing: str) -> Image.Image:
    if path is not None and path.is_file():
        with Image.open(path) as opened:
            return _contain(opened, size)
    canvas = Image.new("RGBA", size, (50, 32, 38, 255))
    ImageDraw.Draw(canvas).text((12, size[1] // 2 - 10), missing, fill=(245, 115, 125), font=_font(16, True))
    return canvas


def _resolve_source(path_value: str) -> Path:
    path = (PROJECT_ROOT / path_value).resolve()
    path.relative_to(PROJECT_ROOT.resolve())
    return path


def _load_rows(run_root: Path) -> tuple[dict[str, Any], list[dict[str, Any]], dict[str, Any]]:
    summary = _read_json(run_root / "run_summary.json")
    frozen = _read_json(FROZEN_PATH)
    rubric = _read_json(RUBRIC_PATH)
    frozen_by_key = {(item["case_id"], item["seed"]): item for item in frozen["case_matrix"]}
    rows: list[dict[str, Any]] = []
    for result in summary.get("results", []):
        key = (result["case_id"], result["seed"])
        frozen_item = frozen_by_key[key]
        result_dir = run_root / result["case_id"] / f"seed_{result['seed']}"
        rows.append(
            {
                "result": result,
                "frozen": frozen_item,
                "result_dir": result_dir,
                "raw": result_dir / "raw.png",
                "v2_sprite": result_dir / "processed_sprite.png",
                "v2_alpha": result_dir / "alpha_mask.png",
                "v2_kept": result_dir / "debug" / "08_kept_components.png",
                "v2_removed": result_dir / "debug" / "09_removed_components.png",
                "v2_candidate": result_dir / "debug" / "05_candidate_fg.png",
                "v2_failure": result_dir / "debug" / "07_final_failure_region.png",
                "v1_debug": ROOT / "v1_postmortem" / result["case_id"] / f"seed_{result['seed']}",
                "rubric": rubric["cases"][result["case_id"]],
            }
        )
    if len(rows) != 8:
        raise ValueError(f"Expected 8 run results, got {len(rows)}")
    return summary, rows, rubric


def _draw_title(canvas: Image.Image, title: str, subtitle: str) -> int:
    draw = ImageDraw.Draw(canvas)
    draw.text((24, 15), title, fill="white", font=_font(30, True))
    draw.text((24, 54), subtitle, fill=(180, 189, 205), font=_font(16))
    return 86


def _label(draw: ImageDraw.ImageDraw, x: int, y: int, text: str, color=(220, 224, 232)) -> None:
    draw.text((x, y), text, fill=color, font=_font(15, True))


def build_v1_v2_comparison(rows: list[dict[str, Any]], target: Path) -> None:
    width, row_height, header = 1680, 260, 86
    canvas = Image.new("RGB", (width, header + row_height * len(rows)), (18, 20, 25))
    _draw_title(
        canvas,
        "Gate B 4B - Frozen Raw / v1 / v2 / Alpha / Components",
        "Every v2 result uses the same sealed OpenCV Chroma + GrabCut processor. Confidence is technical, not identity scoring.",
    )
    draw = ImageDraw.Draw(canvas)
    columns = ((200, "RAW"), (460, "v1 RESULT / FAILURE"), (720, "v2 96x96"), (980, "ALPHA"), (1240, "KEPT / REMOVED"))
    for index, row in enumerate(rows):
        top = header + index * row_height
        draw.rectangle((0, top, width, top + row_height - 1), fill=(29, 32, 39) if index % 2 == 0 else (35, 38, 46))
        result = row["result"]
        metrics = result["v2"]["metrics"]
        draw.text((16, top + 16), f"{result['case_id']}\nseed {result['seed']}", fill=(255, 220, 120), font=_font(20, True), spacing=5)
        draw.text((16, top + 79), f"v1: {result['v1']['status']}", fill=(214, 219, 228), font=_font(14))
        if result["v1"].get("failure_reason"):
            draw.multiline_text((16, top + 103), result["v1"]["failure_reason"].replace("_", "\n"), fill=(242, 140, 146), font=_font(12, True), spacing=2)
        draw.text((16, top + 179), f"v2: {result['v2']['status']}\nconf {metrics['segmentation_confidence']:.3f}\npost {metrics['postprocess_seconds']:.3f}s", fill=(155, 232, 180), font=_font(13, True), spacing=3)
        for x, title in columns:
            _label(draw, x, top + 8, title)
        canvas.paste(_image_panel(row["raw"], (230, 210), "RAW MISSING").convert("RGB"), (190, top + 35))
        v1_record = row["frozen"].get("v1_processed_sprite")
        v1_path = _resolve_source(v1_record["path"]) if isinstance(v1_record, dict) else None
        v1_failure = result["v1"].get("failure_reason") or "NO VALID v1 SPRITE"
        canvas.paste(_sprite_panel(v1_path, (230, 210), v1_failure).convert("RGB"), (450, top + 35))
        v2_failure = result["v2"].get("failure_reason") or ""
        canvas.paste(_sprite_panel(row["v2_sprite"], (230, 210), v2_failure).convert("RGB"), (710, top + 35))
        canvas.paste(_image_panel(row["v2_alpha"], (230, 210), "NO ALPHA").convert("RGB"), (970, top + 35))
        kept = _image_panel(row["v2_kept"], (105, 210), "NO KEPT")
        removed = _image_panel(row["v2_removed"], (105, 210), "NO REMOVED")
        canvas.paste(kept.convert("RGB"), (1230, top + 35))
        canvas.paste(removed.convert("RGB"), (1340, top + 35))
        parts = ", ".join(row["rubric"]["parts"])
        draw.multiline_text((1460, top + 45), f"Parts to inspect:\n{parts}\n\nkept {metrics['kept_component_count']}\nremoved {metrics['removed_component_count']}\nremoved px {metrics['removed_area']}", fill=(215, 219, 228), font=_font(13), spacing=5)
    canvas.save(target, format="PNG", optimize=True)


def build_alpha_postmortem(rows: list[dict[str, Any]], target: Path) -> None:
    width, row_height, header = 1560, 220, 86
    canvas = Image.new("RGB", (width, header + row_height * len(rows)), (18, 20, 25))
    _draw_title(canvas, "Gate B 4B - v1 Alpha Failure Postmortem", "Exact v1 replay only; no Gate B 4A file was changed.")
    draw = ImageDraw.Draw(canvas)
    for index, row in enumerate(rows):
        top = header + index * row_height
        draw.rectangle((0, top, width, top + row_height - 1), fill=(29, 32, 39) if index % 2 == 0 else (35, 38, 46))
        result = row["result"]
        draw.text((14, top + 16), f"{result['case_id']}\n{result['seed']}", fill=(255, 220, 120), font=_font(18, True), spacing=4)
        names = (
            ("raw.png", row["raw"], "RAW"),
            ("border_background_estimate.png", row["v1_debug"] / "border_background_estimate.png", "BORDER ESTIMATE"),
            ("chroma_distance_map.png", row["v1_debug"] / "chroma_distance_map.png", "CHROMA DISTANCE"),
            ("flood_filled_background.png", row["v1_debug"] / "flood_filled_background.png", "FLOOD BG"),
            ("candidate_foreground.png", row["v1_debug"] / "candidate_foreground.png", "CANDIDATE FG"),
            ("final_failure_region.png", row["v1_debug"] / "final_failure_region.png", "FAILURE REGION"),
        )
        for panel_index, (_name, path, title) in enumerate(names):
            x = 125 + panel_index * 235
            _label(draw, x, top + 8, title)
            canvas.paste(_image_panel(path, (210, 180), "MISSING").convert("RGB"), (x, top + 34))
        reason = result["v1"].get("failure_reason") or "SUCCESS"
        draw.multiline_text((1530, top + 40), reason.replace("_", "\n"), anchor="ra", fill=(150, 230, 178) if reason == "SUCCESS" else (245, 140, 147), font=_font(12, True), spacing=2)
    canvas.save(target, format="PNG", optimize=True)


def build_alpha_masks(rows: list[dict[str, Any]], target: Path) -> None:
    width, card_w, card_h, header = 1280, 320, 390, 86
    canvas = Image.new("RGB", (width, header + card_h * 2), (18, 20, 25))
    _draw_title(canvas, "Gate B 4B - v2 Alpha Masks", "Sprite on checkerboard beside its exact delivered grayscale alpha mask.")
    draw = ImageDraw.Draw(canvas)
    for index, row in enumerate(rows):
        col, grid_row = index % 4, index // 4
        left, top = col * card_w, header + grid_row * card_h
        result = row["result"]
        metrics = result["v2"]["metrics"]
        draw.rectangle((left + 5, top + 5, left + card_w - 5, top + card_h - 5), fill=(31, 34, 42), outline=(80, 87, 104), width=2)
        draw.text((left + 15, top + 14), f"{result['case_id']}  seed {result['seed']}", fill=(255, 220, 120), font=_font(18, True))
        canvas.paste(_sprite_panel(row["v2_sprite"], (140, 260)).convert("RGB"), (left + 14, top + 52))
        canvas.paste(_image_panel(row["v2_alpha"], (140, 260), "NO ALPHA").convert("RGB"), (left + 166, top + 52))
        draw.text((left + 16, top + 326), f"confidence {metrics['segmentation_confidence']:.3f}   alpha coverage {metrics['output_alpha_coverage']:.3f}", fill=(202, 208, 220), font=_font(13))
        draw.text((left + 16, top + 350), f"soft edge {metrics['soft_edge_pixel_ratio']:.3f}   bbox {metrics['object_bbox']}", fill=(170, 178, 194), font=_font(12))
    canvas.save(target, format="PNG", optimize=True)


def build_component_debug(rows: list[dict[str, Any]], target: Path) -> None:
    width, row_height, header = 1420, 230, 86
    canvas = Image.new("RGB", (width, header + row_height * len(rows)), (18, 20, 25))
    _draw_title(canvas, "Gate B 4B - v2 Component Debug", "Candidate foreground, retained component set, removed components, final rejected region, and delivered sprite.")
    draw = ImageDraw.Draw(canvas)
    panels = (("CANDIDATE", "v2_candidate"), ("KEPT SET", "v2_kept"), ("REMOVED", "v2_removed"), ("FAILURE/REJECTED", "v2_failure"), ("DELIVERED", "v2_sprite"))
    for index, row in enumerate(rows):
        top = header + index * row_height
        draw.rectangle((0, top, width, top + row_height - 1), fill=(29, 32, 39) if index % 2 == 0 else (35, 38, 46))
        result = row["result"]
        metrics = result["v2"]["metrics"]
        draw.text((14, top + 16), f"{result['case_id']}\n{result['seed']}", fill=(255, 220, 120), font=_font(18, True), spacing=4)
        for panel_index, (title, key) in enumerate(panels):
            x = 120 + panel_index * 235
            _label(draw, x, top + 8, title)
            path = row[key]
            panel = _sprite_panel(path, (210, 185)) if key == "v2_sprite" else _image_panel(path, (210, 185), "MISSING")
            canvas.paste(panel.convert("RGB"), (x, top + 34))
        draw.multiline_text((1300, top + 35), f"kept: {metrics['kept_component_count']}\nremoved: {metrics['removed_component_count']}\nremoved area: {metrics['removed_area']}\nsmallest kept: {metrics['smallest_kept_component_area']}\nconfidence: {metrics['segmentation_confidence']:.3f}", fill=(210, 216, 228), font=_font(13), spacing=5)
    canvas.save(target, format="PNG", optimize=True)


def write_metrics(rows: list[dict[str, Any]], target: Path) -> None:
    fields = [
        "case_id", "seed", "v1_status", "v1_failure_reason", "v2_status", "v2_failure_reason",
        "foreground_coverage", "edge_contact_ratio", "background_residual_ratio", "internal_hole_ratio",
        "component_count", "kept_component_count", "removed_component_count", "removed_area",
        "smallest_kept_component_area", "object_bbox", "soft_edge_pixel_ratio", "shadow_residual_score",
        "segmentation_confidence", "processed_dimensions", "output_alpha_coverage", "visible_color_count",
        "postprocess_seconds", "processor_sha256",
    ]
    with target.open("x", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            result = row["result"]
            metrics = result["v2"]["metrics"]
            record = {field: metrics.get(field, "") for field in fields}
            record.update(
                {
                    "case_id": result["case_id"],
                    "seed": result["seed"],
                    "v1_status": result["v1"]["status"],
                    "v1_failure_reason": result["v1"].get("failure_reason", ""),
                    "v2_status": result["v2"]["status"],
                    "v2_failure_reason": result["v2"].get("failure_reason", ""),
                    "object_bbox": json.dumps(metrics.get("object_bbox", []), separators=(",", ":")),
                    "processor_sha256": result["v2"]["processor_sha256"],
                }
            )
            writer.writerow(record)


def write_review_template(rows: list[dict[str, Any]], target: Path) -> None:
    with target.open("x", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=REVIEW_FIELDS)
        writer.writeheader()
        for row in rows:
            result = row["result"]
            parts = row["rubric"]["parts"]
            record = {field: "" for field in REVIEW_FIELDS}
            record.update(
                {
                    "case_id": result["case_id"],
                    "seed": result["seed"],
                    "part_1": parts[0],
                    "part_2": parts[1],
                    "part_3": parts[2],
                }
            )
            writer.writerow(record)


def build_packet(run_root: Path, packet_root: Path) -> dict[str, str]:
    summary, rows, _rubric = _load_rows(run_root)
    packet_root.parent.mkdir(parents=True, exist_ok=True)
    if packet_root.exists():
        raise FileExistsError(packet_root)
    stage = Path(tempfile.mkdtemp(prefix=f".{packet_root.name}.tmp-", dir=str(packet_root.parent)))
    published = False
    try:
        build_alpha_postmortem(rows, stage / "alpha_postmortem_4b.png")
        build_v1_v2_comparison(rows, stage / "v1_v2_sprite_comparison.png")
        build_alpha_masks(rows, stage / "v2_alpha_masks.png")
        build_component_debug(rows, stage / "component_debug.png")
        write_metrics(rows, stage / "alpha_metrics.csv")
        write_review_template(rows, stage / "human_structure_review.template.csv")
        (stage / "packet_manifest.json").write_text(
            json.dumps(
                {
                    "gate": "Forge Gate B 4B - Offline Alpha Extraction Spike",
                    "run_id": summary["run_id"],
                    "status": "AWAITING_HUMAN_STRUCTURE_REVIEW",
                    "source_gate_4a_formal_status_preserved": "NEEDS WORK",
                    "result_count": len(rows),
                },
                indent=2,
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )
        os.rename(stage, packet_root)
        published = True
    finally:
        if not published and stage.exists():
            shutil.rmtree(stage)
    return {"status": "HUMAN_REVIEW_PACKET_READY", "packet_directory": str(packet_root)}


def main() -> int:
    parser = argparse.ArgumentParser(description="Build immutable Gate B 4B visual review assets.")
    parser.add_argument("--run-root", type=Path, required=True)
    parser.add_argument("--packet-root", type=Path)
    args = parser.parse_args()
    run_root = args.run_root.resolve()
    summary = _read_json(run_root / "run_summary.json")
    packet_root = (args.packet_root or (PACKET_ROOT / summary["run_id"])).resolve()
    print(json.dumps(build_packet(run_root, packet_root), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
