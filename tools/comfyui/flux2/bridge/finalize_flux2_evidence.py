#!/usr/bin/env python3
"""Build deterministic, offline evidence artifacts for Forge FLUX.2 Spike 5.

This finalizer is deliberately read-only with respect to both generation runs.  It
never imports the generation bridge, opens a socket, or starts ComfyUI.  Human
visual judgements are accepted only through a separate CSV.  When no completed
review is present, every visual field remains the literal value ``PENDING``.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import os
import statistics
import sys
import tempfile
from pathlib import Path
from typing import Any, Iterable

from PIL import Image, ImageDraw, ImageFont


REPO_ROOT = Path(__file__).resolve().parents[4]
FLUX_ROOT = REPO_ROOT / "tools" / "comfyui" / "flux2"
DEFAULT_MATRIX = (
    FLUX_ROOT / "output" / "flux2_matrix_20260803t130451548924z"
)
DEFAULT_REALVIS = (
    REPO_ROOT
    / "tools"
    / "comfyui"
    / "gate_b_4a"
    / "output"
    / "gate-b-4a-20260803T094025408228Z-e25bf1f7"
)
DEFAULT_REPORTS = FLUX_ROOT / "reports"
FROZEN_4A = REPO_ROOT / "tools" / "comfyui" / "gate_b_4b" / "frozen_4a_evidence.json"

CASES = ("B01", "B02", "B03", "B04")
SEEDS = (4041001, 4041002)
EXPECTED_KEYS = tuple((case, seed) for case in CASES for seed in SEEDS)

REVIEW_FIELDS = (
    "correct_raw_identity",
    "required_parts_visible",
    "required_parts_visible_names",
    "required_parts_missing_names",
    "single_complete_object",
    "no_person_or_hand",
    "no_extraneous_text_or_watermark",
    "side_or_three_quarter_view",
    "complete_not_cropped",
    "fixed_weapon_substitution",
    "unwanted_scene_or_pedestal",
    "intrinsic_identity_markings_present",
    "identity_recognizable_96",
    "required_parts_preserved_96",
    "required_parts_preserved_names_96",
    "outline_readable",
    "background_residual",
    "shadow_residual",
    "serious_structure_loss_96",
    "reviewer",
    "notes",
)

BOOL_REVIEW_FIELDS = (
    "correct_raw_identity",
    "single_complete_object",
    "no_person_or_hand",
    "no_extraneous_text_or_watermark",
    "side_or_three_quarter_view",
    "complete_not_cropped",
    "fixed_weapon_substitution",
    "unwanted_scene_or_pedestal",
    "intrinsic_identity_markings_present",
    "identity_recognizable_96",
    "outline_readable",
    "background_residual",
    "shadow_residual",
    "serious_structure_loss_96",
)

RESULT_FIELDS = (
    "case_id",
    "seed",
    "generation_status",
    "failure_reason",
    "raw_delivered",
    "raw_width",
    "raw_height",
    "sprite_delivered",
    "sprite_width",
    "sprite_height",
    "alpha_valid",
    "alpha_coverage",
    "correct_raw_identity",
    "required_parts_visible",
    "required_parts_visible_names",
    "required_parts_missing_names",
    "single_complete_object",
    "no_person_or_hand",
    "no_extraneous_text_or_watermark",
    "side_or_three_quarter_view",
    "complete_not_cropped",
    "fixed_weapon_substitution",
    "unwanted_scene_or_pedestal",
    "intrinsic_identity_markings_present",
    "identity_recognizable_96",
    "required_parts_preserved_96",
    "required_parts_preserved_names_96",
    "outline_readable",
    "background_residual",
    "shadow_residual",
    "serious_structure_loss_96",
    "generation_seconds",
    "total_wall_seconds",
    "postprocess_seconds",
    "peak_vram_mb",
    "peak_ram_mb",
    "retry_count",
    "workflow_sha256",
    "positive_prompt_sha256",
    "negative_prompt_sha256",
    "reviewer",
    "notes",
)

PERFORMANCE_FIELDS = (
    "case_id",
    "seed",
    "generation_status",
    "generation_seconds",
    "total_wall_seconds",
    "postprocess_seconds",
    "peak_vram_mb",
    "peak_ram_mb",
    "raw_bytes",
    "processed_sprite_bytes",
    "retry_count",
)

GATE_PARTS = {
    "B01": ("vacuum body", "long flexible hose", "nozzle or suction head"),
    "B02": ("clock face", "twin bells", "clock body or hands"),
    "B03": ("upper pressing arm", "base", "rear hinge"),
    "B04": ("cup bowl", "stem", "base"),
}


class EvidenceError(RuntimeError):
    """Fail-closed evidence validation error."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def file_record(path: Path) -> dict[str, Any]:
    return {
        "path": path.relative_to(REPO_ROOT).as_posix(),
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise EvidenceError(f"INVALID_JSON:{path}:{exc}") from exc
    if not isinstance(value, dict):
        raise EvidenceError(f"JSON_ROOT_NOT_OBJECT:{path}")
    return value


def atomic_bytes(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_name, path)
    finally:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass


def atomic_text(path: Path, text: str) -> None:
    atomic_bytes(path, text.encode("utf-8"))


def atomic_json(path: Path, value: Any) -> None:
    atomic_text(path, json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n")


def csv_bytes(fieldnames: Iterable[str], rows: Iterable[dict[str, Any]]) -> bytes:
    buffer = io.StringIO(newline="")
    writer = csv.DictWriter(buffer, fieldnames=list(fieldnames), extrasaction="ignore", lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return buffer.getvalue().encode("utf-8")


def parse_bool(value: str) -> bool | None:
    normalized = value.strip().lower()
    if normalized in ("pending", "", "n/a"):
        return None
    if normalized == "true":
        return True
    if normalized == "false":
        return False
    raise EvidenceError(f"INVALID_REVIEW_BOOLEAN:{value!r}")


def bool_text(value: bool) -> str:
    return "true" if value else "false"


def verify_4a_freeze() -> dict[str, Any]:
    frozen = read_json(FROZEN_4A)
    tree = frozen.get("frozen_gate_4a_tree")
    if not isinstance(tree, dict) or not tree:
        raise EvidenceError("FROZEN_4A_TREE_MISSING")
    verified = 0
    for relative, expected in tree.items():
        path = REPO_ROOT / relative
        if not path.is_file():
            raise EvidenceError(f"FROZEN_4A_FILE_MISSING:{relative}")
        actual_size = path.stat().st_size
        actual_hash = sha256_file(path)
        if actual_size != int(expected["size"]):
            raise EvidenceError(f"FROZEN_4A_SIZE_CHANGED:{relative}")
        if actual_hash != expected["sha256"]:
            raise EvidenceError(f"FROZEN_4A_HASH_CHANGED:{relative}")
        verified += 1
    return {
        "manifest": file_record(FROZEN_4A),
        "source_run_id": frozen.get("source_run_id"),
        "source_gate_formal_status": frozen.get("source_gate_formal_status"),
        "verified_file_count": verified,
        "all_hashes_match": True,
        "frozen_raw_identity_baseline": frozen.get("source_raw_identity_count_frozen_by_4b_contract"),
    }


def validate_png(path: Path, expected_size: tuple[int, int] | None = None) -> dict[str, Any]:
    if not path.is_file():
        raise EvidenceError(f"PNG_MISSING:{path}")
    try:
        with Image.open(path) as image:
            image.load()
            if image.format != "PNG":
                raise EvidenceError(f"NOT_PNG:{path}")
            dimensions = image.size
            mode = image.mode
            if expected_size is not None and dimensions != expected_size:
                raise EvidenceError(f"PNG_DIMENSIONS:{path}:{dimensions}")
            alpha_valid = False
            alpha_coverage: float | None = None
            if "A" in image.getbands():
                alpha = image.getchannel("A")
                extrema = alpha.getextrema()
                alpha_valid = extrema[0] < 255 and extrema[1] > 0
                histogram = alpha.histogram()
                visible = sum(histogram[1:])
                alpha_coverage = round(visible / (dimensions[0] * dimensions[1]), 6)
    except (OSError, ValueError) as exc:
        raise EvidenceError(f"PNG_UNREADABLE:{path}:{exc}") from exc
    return {
        "width": dimensions[0],
        "height": dimensions[1],
        "mode": mode,
        "alpha_valid": alpha_valid,
        "alpha_coverage_observed": alpha_coverage,
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def load_matrix(matrix: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    summary_path = matrix / "generation_summary.json"
    summary = read_json(summary_path)
    if int(summary.get("planned_generation_count", -1)) != 8:
        raise EvidenceError("MATRIX_PLANNED_COUNT_NOT_8")
    if int(summary.get("attempted_generation_count", -1)) != 8:
        raise EvidenceError("MATRIX_ATTEMPTED_COUNT_NOT_8")
    if int(summary.get("automatic_retry_count", -1)) != 0:
        raise EvidenceError("MATRIX_RETRY_COUNT_NOT_ZERO")

    records: list[dict[str, Any]] = []
    found: list[tuple[str, int]] = []
    for case, seed in EXPECTED_KEYS:
        directory = matrix / case.lower() / f"seed_{seed}"
        manifest_path = directory / "manifest.json"
        manifest = read_json(manifest_path)
        manifest_case = str(manifest.get("case_id", "")).upper()
        manifest_seed = int(manifest.get("seed", -1))
        if (manifest_case, manifest_seed) != (case, seed):
            raise EvidenceError(f"MATRIX_KEY_MISMATCH:{manifest_path}")
        if int(manifest.get("retry_count", -1)) != 0:
            raise EvidenceError(f"MATRIX_RECORD_RETRIED:{case}:{seed}")

        raw_path = directory / "raw.png"
        raw = validate_png(raw_path, (512, 512))
        sprite_path = directory / "processed_sprite.png"
        alpha_path = directory / "alpha_mask.png"
        sprite: dict[str, Any] | None = None
        if sprite_path.is_file():
            sprite = validate_png(sprite_path, (96, 96))
            if not alpha_path.is_file():
                raise EvidenceError(f"ALPHA_MASK_MISSING:{case}:{seed}")
            validate_png(alpha_path, (96, 96))
            if not sprite["alpha_valid"]:
                raise EvidenceError(f"DELIVERED_SPRITE_ALPHA_INVALID:{case}:{seed}")
        elif alpha_path.exists():
            raise EvidenceError(f"ORPHAN_ALPHA_MASK:{case}:{seed}")

        manifest_alpha = bool(manifest.get("alpha_valid", False))
        if manifest_alpha != bool(sprite and sprite["alpha_valid"]):
            raise EvidenceError(f"MANIFEST_ALPHA_DISAGREEMENT:{case}:{seed}")

        found.append((case, seed))
        records.append(
            {
                "case_id": case,
                "seed": seed,
                "directory": directory,
                "manifest_path": manifest_path,
                "manifest": manifest,
                "raw_path": raw_path,
                "raw": raw,
                "sprite_path": sprite_path if sprite else None,
                "alpha_path": alpha_path if sprite else None,
                "sprite": sprite,
            }
        )
    if tuple(found) != EXPECTED_KEYS:
        raise EvidenceError("MATRIX_CASE_ORDER_MISMATCH")
    return summary, records


def review_template_rows() -> list[dict[str, str]]:
    rows = []
    for case, seed in EXPECTED_KEYS:
        row: dict[str, str] = {
            "case_id": case,
            "seed": str(seed),
            "gate_identity_parts": "; ".join(GATE_PARTS[case]),
        }
        row.update({field: "PENDING" for field in REVIEW_FIELDS})
        row["reviewer"] = ""
        row["notes"] = ""
        rows.append(row)
    return rows


def load_or_create_review(path: Path) -> tuple[list[dict[str, str]], str]:
    review_fields = ("case_id", "seed", "gate_identity_parts", *REVIEW_FIELDS)
    if not path.exists():
        rows = review_template_rows()
        atomic_bytes(path, csv_bytes(review_fields, rows))
        return rows, "PENDING"
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        missing = [field for field in review_fields if field not in (reader.fieldnames or [])]
        if missing:
            raise EvidenceError(f"REVIEW_COLUMNS_MISSING:{','.join(missing)}")
        rows = [dict(row) for row in reader]
    keys = tuple((row["case_id"].upper(), int(row["seed"])) for row in rows)
    if keys != EXPECTED_KEYS:
        raise EvidenceError("REVIEW_CASE_ORDER_MISMATCH")
    pending = False
    for row in rows:
        case = row["case_id"].upper()
        row["case_id"] = case
        if row["gate_identity_parts"] != "; ".join(GATE_PARTS[case]):
            raise EvidenceError(f"REVIEW_GATE_PARTS_CHANGED:{case}:{row['seed']}")
        for field in BOOL_REVIEW_FIELDS:
            normalized = row[field].strip().lower()
            parse_bool(row[field])
            if normalized in ("pending", ""):
                pending = True
        for field in ("required_parts_visible", "required_parts_preserved_96"):
            value = row[field].strip()
            if value.lower() in ("pending", ""):
                pending = True
            else:
                try:
                    number = int(value)
                except ValueError as exc:
                    raise EvidenceError(f"INVALID_REVIEW_COUNT:{field}:{value!r}") from exc
                if not 0 <= number <= 3:
                    raise EvidenceError(f"REVIEW_COUNT_OUT_OF_RANGE:{field}:{number}")
    return rows, "PENDING" if pending else "COMPLETE"


def make_result_rows(records: list[dict[str, Any]], review: list[dict[str, str]]) -> list[dict[str, Any]]:
    review_by_key = {(row["case_id"], int(row["seed"])): row for row in review}
    rows: list[dict[str, Any]] = []
    for record in records:
        manifest = record["manifest"]
        sprite = record["sprite"]
        row: dict[str, Any] = {
            "case_id": record["case_id"],
            "seed": record["seed"],
            "generation_status": manifest.get("status", ""),
            "failure_reason": manifest.get("failure_reason", ""),
            "raw_delivered": "true",
            "raw_width": record["raw"]["width"],
            "raw_height": record["raw"]["height"],
            "sprite_delivered": bool_text(sprite is not None),
            "sprite_width": sprite["width"] if sprite else "",
            "sprite_height": sprite["height"] if sprite else "",
            "alpha_valid": bool_text(bool(sprite and sprite["alpha_valid"])),
            "alpha_coverage": manifest.get("alpha_coverage", ""),
            "generation_seconds": manifest.get("generation_seconds", ""),
            "total_wall_seconds": manifest.get("total_wall_seconds", ""),
            "postprocess_seconds": manifest.get("postprocess_seconds", ""),
            "peak_vram_mb": manifest.get("peak_vram_mb", ""),
            "peak_ram_mb": manifest.get("peak_ram_mb", ""),
            "retry_count": manifest.get("retry_count", ""),
            "workflow_sha256": manifest.get("workflow_sha256", ""),
            "positive_prompt_sha256": manifest.get("positive_prompt_sha256", ""),
            "negative_prompt_sha256": manifest.get("negative_prompt_sha256", ""),
        }
        human = review_by_key[(record["case_id"], record["seed"])]
        row.update({field: human[field] for field in REVIEW_FIELDS})
        rows.append(row)
    return rows


def make_performance_rows(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows = []
    for record in records:
        manifest = record["manifest"]
        rows.append(
            {
                "case_id": record["case_id"],
                "seed": record["seed"],
                "generation_status": manifest.get("status", ""),
                "generation_seconds": manifest.get("generation_seconds", ""),
                "total_wall_seconds": manifest.get("total_wall_seconds", ""),
                "postprocess_seconds": manifest.get("postprocess_seconds", ""),
                "peak_vram_mb": manifest.get("peak_vram_mb", ""),
                "peak_ram_mb": manifest.get("peak_ram_mb", ""),
                "raw_bytes": record["raw"]["bytes"],
                "processed_sprite_bytes": record["sprite"]["bytes"] if record["sprite"] else 0,
                "retry_count": manifest.get("retry_count", ""),
            }
        )
    return rows


def get_font(size: int, bold: bool = False) -> ImageFont.ImageFont:
    filename = "arialbd.ttf" if bold else "arial.ttf"
    font_path = Path("C:/Windows/Fonts") / filename
    try:
        return ImageFont.truetype(str(font_path), size=size)
    except OSError:
        return ImageFont.load_default()


def fit_image(source: Image.Image, size: tuple[int, int], resample: Image.Resampling) -> Image.Image:
    image = source.copy()
    image.thumbnail(size, resample=resample)
    canvas = Image.new("RGB", size, "#10151d")
    if image.mode == "RGBA":
        checker = checkerboard(size)
        offset = ((size[0] - image.width) // 2, (size[1] - image.height) // 2)
        checker.paste(image, offset, image)
        return checker
    rgb = image.convert("RGB")
    canvas.paste(rgb, ((size[0] - rgb.width) // 2, (size[1] - rgb.height) // 2))
    return canvas


def checkerboard(size: tuple[int, int], unit: int = 16) -> Image.Image:
    canvas = Image.new("RGB", size, "#d8d8d8")
    draw = ImageDraw.Draw(canvas)
    for y in range(0, size[1], unit):
        for x in range(0, size[0], unit):
            if (x // unit + y // unit) % 2:
                draw.rectangle((x, y, min(x + unit - 1, size[0] - 1), min(y + unit - 1, size[1] - 1)), fill="#f4f4f4")
    return canvas


def paste_label(draw: ImageDraw.ImageDraw, xy: tuple[int, int], label: str, size: int = 18) -> None:
    draw.text(xy, label, fill="#f4f7fb", font=get_font(size, bold=True))


def save_png_atomic(image: Image.Image, path: Path) -> None:
    payload = io.BytesIO()
    image.save(payload, format="PNG", optimize=False)
    atomic_bytes(path, payload.getvalue())


def make_raw_contact_sheet(records: list[dict[str, Any]], output: Path) -> None:
    cell_w, cell_h = 300, 326
    canvas = Image.new("RGB", (cell_w * 4, cell_h * 2), "#090d13")
    draw = ImageDraw.Draw(canvas)
    for index, record in enumerate(records):
        column, row = index % 4, index // 4
        x, y = column * cell_w, row * cell_h
        paste_label(draw, (x + 10, y + 8), f"{record['case_id']} / seed {record['seed']}", 17)
        with Image.open(record["raw_path"]) as raw:
            tile = fit_image(raw, (280, 280), Image.Resampling.LANCZOS)
        canvas.paste(tile, (x + 10, y + 36))
    save_png_atomic(canvas, output)


def make_raw_sprite_sheet(records: list[dict[str, Any]], output: Path) -> None:
    cell_w, cell_h = 500, 270
    canvas = Image.new("RGB", (cell_w * 2, cell_h * 4), "#090d13")
    draw = ImageDraw.Draw(canvas)
    for index, record in enumerate(records):
        column, row = index % 2, index // 2
        x, y = column * cell_w, row * cell_h
        status = record["manifest"].get("status", "")
        paste_label(draw, (x + 10, y + 8), f"{record['case_id']} / {record['seed']} / {status}", 16)
        draw.text((x + 80, y + 40), "RAW 512", fill="#b9c5d3", font=get_font(14))
        draw.text((x + 330, y + 40), "SPRITE 96", fill="#b9c5d3", font=get_font(14))
        with Image.open(record["raw_path"]) as raw:
            raw_tile = fit_image(raw, (220, 210), Image.Resampling.LANCZOS)
        canvas.paste(raw_tile, (x + 10, y + 58))
        if record["sprite_path"]:
            with Image.open(record["sprite_path"]) as sprite:
                sprite_tile = fit_image(sprite.convert("RGBA"), (220, 210), Image.Resampling.NEAREST)
            canvas.paste(sprite_tile, (x + 260, y + 58))
        else:
            fail = checkerboard((220, 210))
            fail_draw = ImageDraw.Draw(fail)
            fail_draw.rectangle((8, 65, 211, 145), fill="#521f2a", outline="#ff637c", width=2)
            reason = record["manifest"].get("failure_reason") or "NOT DELIVERED"
            fail_draw.text((18, 82), "NO SPRITE", fill="#ffffff", font=get_font(20, bold=True))
            fail_draw.text((18, 116), reason, fill="#ffd6dc", font=get_font(11))
            canvas.paste(fail, (x + 260, y + 58))
    save_png_atomic(canvas, output)


def make_model_comparison(records: list[dict[str, Any]], realvis: Path, output: Path) -> None:
    cell_w, cell_h = 500, 270
    canvas = Image.new("RGB", (cell_w * 2, cell_h * 4), "#090d13")
    draw = ImageDraw.Draw(canvas)
    for index, record in enumerate(records):
        column, row = index % 2, index // 2
        x, y = column * cell_w, row * cell_h
        paste_label(draw, (x + 10, y + 8), f"{record['case_id']} / seed {record['seed']}", 16)
        draw.text((x + 68, y + 40), "RealVisXL 4A (frozen)", fill="#b9c5d3", font=get_font(13))
        draw.text((x + 330, y + 40), "FLUX.2 Klein 4B", fill="#b9c5d3", font=get_font(13))
        realvis_raw = realvis / record["case_id"] / f"seed_{record['seed']}" / "raw.png"
        validate_png(realvis_raw, (512, 512))
        with Image.open(realvis_raw) as old_image, Image.open(record["raw_path"]) as flux_image:
            old_tile = fit_image(old_image, (220, 210), Image.Resampling.LANCZOS)
            flux_tile = fit_image(flux_image, (220, 210), Image.Resampling.LANCZOS)
        canvas.paste(old_tile, (x + 10, y + 58))
        canvas.paste(flux_tile, (x + 260, y + 58))
    save_png_atomic(canvas, output)


def count_review_true(rows: list[dict[str, str]], field: str) -> int:
    return sum(parse_bool(row[field]) is True for row in rows)


def count_review_false(rows: list[dict[str, str]], field: str) -> int:
    return sum(parse_bool(row[field]) is False for row in rows)


def build_summary(
    generation: dict[str, Any],
    records: list[dict[str, Any]],
    review: list[dict[str, str]],
    review_status: str,
    freeze: dict[str, Any],
) -> dict[str, Any]:
    generation_seconds = [float(item["manifest"]["generation_seconds"]) for item in records]
    wall_seconds = [float(item["manifest"]["total_wall_seconds"]) for item in records]
    post_seconds = [float(item["manifest"]["postprocess_seconds"]) for item in records]
    vram = [float(item["manifest"]["peak_vram_mb"]) for item in records]
    ram = [float(item["manifest"]["peak_ram_mb"]) for item in records]
    alpha_delivered = sum(item["sprite"] is not None for item in records)
    alpha_failures: dict[str, int] = {}
    for item in records:
        reason = item["manifest"].get("failure_reason", "")
        if reason:
            alpha_failures[reason] = alpha_failures.get(reason, 0) + 1

    gates: dict[str, dict[str, Any]] = {
        "generation_completed": {"actual": len(records), "required": 8, "passed": len(records) == 8},
        "formal_matrix_retry_count": {
            "actual": int(generation["automatic_retry_count"]),
            "maximum": 0,
            "passed": int(generation["automatic_retry_count"]) == 0,
        },
        "sprite_delivered": {"actual": alpha_delivered, "required": 8, "passed": alpha_delivered == 8},
    }
    model_status = "PENDING HUMAN REVIEW"
    alpha_status = "PENDING HUMAN REVIEW"
    if review_status == "COMPLETE":
        required_parts = sum(int(row["required_parts_visible"]) for row in review)
        gates.update(
            {
                "correct_raw_identity": {
                    "actual": count_review_true(review, "correct_raw_identity"),
                    "required": 7,
                },
                "required_parts_visible": {"actual": required_parts, "required": 21, "total": 24},
                "single_complete_object": {
                    "actual": count_review_true(review, "single_complete_object"),
                    "required": 8,
                },
                "no_person_or_hand": {
                    "actual": count_review_true(review, "no_person_or_hand"),
                    "required": 8,
                },
                "fixed_weapon_substitution": {
                    "actual": count_review_true(review, "fixed_weapon_substitution"),
                    "maximum": 0,
                },
                "complete_not_cropped": {
                    "actual": count_review_true(review, "complete_not_cropped"),
                    "required": 7,
                },
                "identity_recognizable_96": {
                    "actual": count_review_true(review, "identity_recognizable_96"),
                    "required": 6,
                },
                "serious_structure_loss_96": {
                    "actual": count_review_true(review, "serious_structure_loss_96"),
                    "maximum": 0,
                },
                "background_residual": {
                    "actual": count_review_true(review, "background_residual"),
                    "maximum": 0,
                },
                "shadow_residual": {
                    "actual": count_review_true(review, "shadow_residual"),
                    "maximum": 0,
                },
            }
        )
        for gate in gates.values():
            if "required" in gate:
                gate["passed"] = gate["actual"] >= gate["required"]
            elif "maximum" in gate:
                gate["passed"] = gate["actual"] <= gate["maximum"]
        model_keys = (
            "generation_completed",
            "formal_matrix_retry_count",
            "correct_raw_identity",
            "required_parts_visible",
            "single_complete_object",
            "no_person_or_hand",
            "fixed_weapon_substitution",
            "complete_not_cropped",
        )
        model_status = "PASS" if all(gates[key]["passed"] for key in model_keys) else "NEEDS WORK"
        alpha_keys = (
            "sprite_delivered",
            "identity_recognizable_96",
            "serious_structure_loss_96",
            "background_residual",
            "shadow_residual",
        )
        alpha_status = (
            "PASS"
            if all(gates[key]["passed"] for key in alpha_keys)
            and all(bool(item["sprite"]["alpha_valid"]) for item in records if item["sprite"])
            else "NEEDS WORK"
        )

    return {
        "contract": "forge-flux2-spike-5-evidence-summary-v1",
        "matrix_run_id": generation.get("run_id"),
        "matrix_output_group": generation.get("output_group"),
        "source_completed_at": generation.get("completed_at"),
        "frozen_blueprints_sha256": generation.get("frozen_blueprints_sha256"),
        "review_status": review_status,
        "technical_results": {
            "planned_generation_count": generation.get("planned_generation_count"),
            "attempted_generation_count": generation.get("attempted_generation_count"),
            "raw_delivered_count": len(records),
            "sprite_delivered_count": alpha_delivered,
            "alpha_failed_count": len(records) - alpha_delivered,
            "alpha_failure_reasons": alpha_failures,
            "automatic_retry_count": generation.get("automatic_retry_count"),
        },
        "performance": {
            "generation_seconds_mean": round(statistics.mean(generation_seconds), 3),
            "generation_seconds_median": round(statistics.median(generation_seconds), 3),
            "generation_seconds_min": round(min(generation_seconds), 3),
            "generation_seconds_max": round(max(generation_seconds), 3),
            "total_wall_seconds_mean": round(statistics.mean(wall_seconds), 3),
            "total_wall_seconds_total": round(sum(wall_seconds), 3),
            "postprocess_seconds_mean": round(statistics.mean(post_seconds), 3),
            "peak_vram_mb_max": round(max(vram), 1),
            "peak_ram_mb_max": round(max(ram), 1),
        },
        "formal_gates": gates,
        "model_identity_status": model_status,
        "alpha_status": alpha_status,
        "formal_classification": (
            "PENDING HUMAN REVIEW"
            if review_status != "COMPLETE"
            else (
                "MODEL PASS / ALPHA NEEDS WORK"
                if model_status == "PASS" and alpha_status != "PASS"
                else f"MODEL {model_status} / ALPHA {alpha_status}"
            )
        ),
        "realvisxl_4a_frozen_baseline": {
            "formal_status": freeze["source_gate_formal_status"],
            "raw_identity": freeze["frozen_raw_identity_baseline"],
            "v1_alpha_delivery": {"passed": 1, "total": 8},
            "evidence_hashes_unchanged": freeze["all_hashes_match"],
        },
        "review_warning": (
            "Actual images have not yet been human-scored; no prompt or JSON value was used as a visual verdict."
            if review_status != "COMPLETE"
            else "Human fields were loaded from the independent review CSV and were not inferred from prompts."
        ),
    }


def build_mechanical_markdown(summary: dict[str, Any], records: list[dict[str, Any]]) -> str:
    technical = summary["technical_results"]
    perf = summary["performance"]
    lines = [
        "# FLUX.2 Spike 5 Evidence Summary",
        "",
        "> This is a mechanically generated evidence summary. It is not the final integration report.",
        "",
        f"- Matrix run: `{summary['matrix_run_id']}`",
        f"- Human review: **{summary['review_status']}**",
        f"- Formal classification: **{summary['formal_classification']}**",
        f"- Raw generation: {technical['raw_delivered_count']}/8",
        f"- Current v1 Alpha delivery: {technical['sprite_delivered_count']}/8",
        f"- Automatic retries: {technical['automatic_retry_count']}",
        f"- Frozen RealVisXL 4A evidence unchanged: {str(summary['realvisxl_4a_frozen_baseline']['evidence_hashes_unchanged']).lower()}",
        "",
        "## Per-image technical evidence",
        "",
        "| Case | Seed | Generation | Alpha | Failure | Gen s | Post s | Peak VRAM MB |",
        "|---|---:|---|---|---|---:|---:|---:|",
    ]
    for record in records:
        manifest = record["manifest"]
        lines.append(
            f"| {record['case_id']} | {record['seed']} | raw delivered | "
            f"{'delivered' if record['sprite'] else 'rejected'} | "
            f"{manifest.get('failure_reason') or '-'} | {manifest.get('generation_seconds')} | "
            f"{manifest.get('postprocess_seconds')} | {manifest.get('peak_vram_mb')} |"
        )
    lines.extend(
        [
            "",
            "## Performance",
            "",
            f"- Mean generation: {perf['generation_seconds_mean']} s",
            f"- Maximum generation: {perf['generation_seconds_max']} s",
            f"- Total matrix wall time: {perf['total_wall_seconds_total']} s",
            f"- Maximum observed VRAM: {perf['peak_vram_mb_max']} MB",
            f"- Maximum observed RAM: {perf['peak_ram_mb_max']} MB",
            "",
            "## Review boundary",
            "",
            summary["review_warning"],
            "The final report must keep raw model identity and Alpha delivery as separate conclusions.",
            "",
        ]
    )
    return "\n".join(lines)


def collect_tree_records(root: Path, *, skip: set[Path] | None = None) -> dict[str, dict[str, Any]]:
    skip = {path.resolve() for path in (skip or set())}
    records: dict[str, dict[str, Any]] = {}
    for path in sorted((item for item in root.rglob("*") if item.is_file()), key=lambda item: item.as_posix().lower()):
        resolved = path.resolve()
        if resolved in skip:
            continue
        relative_parts = path.relative_to(FLUX_ROOT).parts if path.is_relative_to(FLUX_ROOT) else ()
        if "__pycache__" in relative_parts or "logs" in relative_parts:
            continue
        if path.name.endswith(".runtime.local.json") or path.suffix in (
            ".pyc",
            ".partial",
            ".safetensors",
            ".import",
            ".translation",
        ):
            continue
        record = file_record(path)
        records[record["path"]] = {"bytes": record["bytes"], "sha256": record["sha256"]}
    return records


def build_evidence_hashes(
    matrix: Path,
    realvis: Path,
    reports: Path,
    freeze: dict[str, Any],
    evidence_path: Path,
) -> dict[str, Any]:
    matrix_files = collect_tree_records(matrix)
    realvis_files: dict[str, dict[str, Any]] = {}
    for case, seed in EXPECTED_KEYS:
        for name in ("raw.png", "manifest.json"):
            path = realvis / case / f"seed_{seed}" / name
            record = file_record(path)
            realvis_files[record["path"]] = {"bytes": record["bytes"], "sha256": record["sha256"]}
    integration_paths = (
        REPO_ROOT / ".gitignore",
        REPO_ROOT / "tools" / "comfyui" / "config" / "profiles" / "flux2_klein_4b.json",
        REPO_ROOT / "tools" / "comfyui" / "config" / "profiles" / "realvisxl.json",
        REPO_ROOT / "tools" / "comfyui" / "bridge" / "forge_comfy_bridge.py",
        REPO_ROOT / "tools" / "comfyui" / "postprocess" / "process_sprite.py",
        REPO_ROOT / "scripts" / "open_identity_spike.gd",
        REPO_ROOT / "scripts" / "services" / "local_comfy_forge_visual_provider.gd",
    )
    integration_files: dict[str, dict[str, Any]] = {}
    for path in integration_paths:
        if not path.is_file():
            raise EvidenceError(f"INTEGRATION_EVIDENCE_MISSING:{path}")
        record = file_record(path)
        integration_files[record["path"]] = {"bytes": record["bytes"], "sha256": record["sha256"]}
    delivery_files = collect_tree_records(FLUX_ROOT, skip={evidence_path})
    return {
        "contract": "forge-flux2-spike-5-evidence-hashes-v1",
        "matrix_run_directory": matrix.relative_to(REPO_ROOT).as_posix(),
        "realvisxl_frozen_run_directory": realvis.relative_to(REPO_ROOT).as_posix(),
        "frozen_gate_4a_verification": freeze,
        "matrix_file_count": len(matrix_files),
        "matrix_files": matrix_files,
        "realvisxl_comparison_file_count": len(realvis_files),
        "realvisxl_comparison_files": realvis_files,
        "integration_file_count": len(integration_files),
        "integration_files": integration_files,
        "spike_5_delivery_file_count": len(delivery_files),
        "spike_5_delivery_files": delivery_files,
        "excluded_from_hash_set": [
            evidence_path.relative_to(REPO_ROOT).as_posix(),
            "tools/comfyui/flux2/logs/**",
            "**/__pycache__/**",
            "**/*.runtime.local.json",
            "**/*.safetensors",
            "**/*.partial",
        ],
        "reports_directory": reports.relative_to(REPO_ROOT).as_posix(),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--matrix", type=Path, default=DEFAULT_MATRIX)
    parser.add_argument("--realvis", type=Path, default=DEFAULT_REALVIS)
    parser.add_argument("--reports", type=Path, default=DEFAULT_REPORTS)
    parser.add_argument("--review-file", type=Path)
    args = parser.parse_args(argv)

    matrix = args.matrix.resolve()
    realvis = args.realvis.resolve()
    reports = args.reports.resolve()
    review_file = (args.review_file or reports / "human_visual_review.csv").resolve()
    if matrix != DEFAULT_MATRIX.resolve():
        raise EvidenceError("UNAPPROVED_MATRIX_RUN")
    if realvis != DEFAULT_REALVIS.resolve():
        raise EvidenceError("UNAPPROVED_REALVIS_BASELINE")

    reports.mkdir(parents=True, exist_ok=True)
    freeze = verify_4a_freeze()
    generation, records = load_matrix(matrix)
    review, review_status = load_or_create_review(review_file)
    result_rows = make_result_rows(records, review)
    performance_rows = make_performance_rows(records)

    results_path = reports / "flux2_matrix_results.csv"
    performance_path = reports / "performance_metrics.csv"
    summary_path = reports / "flux2_matrix_summary.json"
    report_data_path = reports / "FLUX2_INTEGRATION_REPORT_DATA.md"
    raw_contact_path = reports / "flux2_raw_contact_sheet.png"
    raw_sprite_path = reports / "flux2_raw_sprite_comparison.png"
    model_comparison_path = reports / "realvisxl_flux2_raw_comparison.png"
    evidence_path = reports / "evidence_hashes.json"

    atomic_bytes(results_path, csv_bytes(RESULT_FIELDS, result_rows))
    atomic_bytes(performance_path, csv_bytes(PERFORMANCE_FIELDS, performance_rows))
    make_raw_contact_sheet(records, raw_contact_path)
    make_raw_sprite_sheet(records, raw_sprite_path)
    make_model_comparison(records, realvis, model_comparison_path)

    summary = build_summary(generation, records, review, review_status, freeze)
    atomic_json(summary_path, summary)
    atomic_text(report_data_path, build_mechanical_markdown(summary, records))

    evidence = build_evidence_hashes(matrix, realvis, reports, freeze, evidence_path)
    atomic_json(evidence_path, evidence)
    print(
        json.dumps(
            {
                "status": "PASS",
                "review_status": review_status,
                "matrix_run_id": generation.get("run_id"),
                "raw_delivered": 8,
                "sprite_delivered": summary["technical_results"]["sprite_delivered_count"],
                "automatic_retries": generation.get("automatic_retry_count"),
                "reports": reports.as_posix(),
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except EvidenceError as exc:
        print(json.dumps({"status": "FAIL", "failure_reason": str(exc)}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(2)
