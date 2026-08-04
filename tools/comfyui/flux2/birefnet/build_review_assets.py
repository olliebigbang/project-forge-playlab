from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import shutil
import tempfile
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from PIL import Image, ImageDraw


class ReviewAssetError(RuntimeError):
    pass


EXPECTED_WORKFLOW_SHA256 = "56d74936b840de2ce2d5e823b6ad1704b9e65dd7ddd8b7a0edbfb5d4d4cf19df"
EXPECTED_SOURCE_FREEZE_SHA256 = "57b1de80841d4c5f3da4c07b5cb0dee606a3a3dbfffbbb1ba387d617f59f7af8"
EXPECTED_JOBS = (
    (1, "b01", "seed_4041001", "01_b01_seed_4041001"),
    (2, "b01", "seed_4041002", "02_b01_seed_4041002"),
    (3, "b02", "seed_4041001", "03_b02_seed_4041001"),
    (4, "b02", "seed_4041002", "04_b02_seed_4041002"),
    (5, "b03", "seed_4041001", "05_b03_seed_4041001"),
    (6, "b03", "seed_4041002", "06_b03_seed_4041002"),
    (7, "b04", "seed_4041001", "07_b04_seed_4041001"),
    (8, "b04", "seed_4041002", "08_b04_seed_4041002"),
)


def _json_object(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ReviewAssetError(f"JSON_OBJECT_REQUIRED:{path}")
    return value


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _file_record(path: Path, base: Path) -> dict[str, Any]:
    resolved = path.resolve(strict=True)
    try:
        relative = resolved.relative_to(base.resolve(strict=True)).as_posix()
    except ValueError as exc:
        raise ReviewAssetError(f"EVIDENCE_PATH_ESCAPES_BASE:{path}") from exc
    return {
        "path": relative,
        "bytes": resolved.stat().st_size,
        "sha256": _sha256(resolved),
    }


def _verify_run_evidence(run_root: Path) -> str:
    evidence_path = run_root / "evidence_hashes.json"
    evidence = _json_object(evidence_path)
    if evidence.get("algorithm") != "SHA-256" or not isinstance(evidence.get("files"), dict):
        raise ReviewAssetError("INVALID_RUN_EVIDENCE_MANIFEST")
    for relative, expected in evidence["files"].items():
        candidate = (run_root / str(relative)).resolve(strict=True)
        try:
            candidate.relative_to(run_root)
        except ValueError as exc:
            raise ReviewAssetError("RUN_EVIDENCE_PATH_ESCAPES_ROOT") from exc
        if _sha256(candidate) != expected:
            raise ReviewAssetError(f"RUN_EVIDENCE_HASH_MISMATCH:{relative}")
    return _sha256(evidence_path)


def _validate_delivery(
    sprite_path: Path, alpha_path: Path, metrics: dict[str, Any]
) -> tuple[Image.Image, dict[str, Any]]:
    with Image.open(sprite_path) as opened_sprite:
        if opened_sprite.format != "PNG" or opened_sprite.mode != "RGBA":
            raise ReviewAssetError("DELIVERY_SPRITE_NOT_RGBA_PNG")
        opened_sprite.load()
        sprite = opened_sprite.copy()
    with Image.open(alpha_path) as opened_alpha:
        if opened_alpha.format != "PNG" or opened_alpha.mode != "L":
            raise ReviewAssetError("DELIVERY_ALPHA_NOT_L_PNG")
        opened_alpha.load()
        delivered_alpha = opened_alpha.copy()
    if sprite.size != (96, 96) or delivered_alpha.size != (96, 96):
        raise ReviewAssetError("DELIVERY_NOT_96X96")
    rgba = np.asarray(sprite, dtype=np.uint8)
    alpha = np.asarray(delivered_alpha, dtype=np.uint8)
    if not np.array_equal(rgba[:, :, 3], alpha):
        raise ReviewAssetError("DELIVERY_ALPHA_MISMATCH")
    hard = alpha > 8
    if not np.any(hard) or np.all(hard):
        raise ReviewAssetError("DELIVERY_ALPHA_INVALID")
    if np.any(hard[0]) or np.any(hard[-1]) or np.any(hard[:, 0]) or np.any(hard[:, -1]):
        raise ReviewAssetError("DELIVERY_TOUCHES_OUTPUT_EDGE")
    visible_colors = np.unique(rgba[:, :, :3][rgba[:, :, 3] > 0], axis=0)
    recomputed = {
        "processed_dimensions": [96, 96],
        "alpha_coverage": round(float(np.mean(hard)), 6),
        "visible_color_count": int(len(visible_colors)),
    }
    for key, value in recomputed.items():
        if metrics.get(key) != value:
            raise ReviewAssetError(f"DELIVERY_METRIC_MISMATCH:{key}")
    if metrics.get("status") != "success" or metrics.get("alpha_valid") is not True:
        raise ReviewAssetError("DELIVERY_METRICS_NOT_SUCCESS")
    if metrics.get("largest_component_only") is not False:
        raise ReviewAssetError("LARGEST_COMPONENT_ONLY_FORBIDDEN")
    if metrics.get("case_specific_logic") is not False:
        raise ReviewAssetError("CASE_SPECIFIC_LOGIC_FORBIDDEN")
    return sprite, recomputed


def _checker(size: tuple[int, int], cell: int = 16) -> Image.Image:
    width, height = size
    yy, xx = np.indices((height, width))
    cells = ((xx // cell) + (yy // cell)) % 2
    rgb = np.where(cells[:, :, None] == 0, 222, 174).astype(np.uint8)
    return Image.fromarray(np.repeat(rgb, 3, axis=2), mode="RGB").convert("RGBA")


def _contain(image: Image.Image, size: tuple[int, int], *, nearest: bool = False) -> Image.Image:
    result = image.copy()
    result.thumbnail(size, Image.Resampling.NEAREST if nearest else Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", size, (28, 30, 38, 255))
    canvas.alpha_composite(result.convert("RGBA"), ((size[0] - result.width) // 2, (size[1] - result.height) // 2))
    return canvas


def _on_checker(image: Image.Image, size: tuple[int, int], *, nearest: bool = False) -> Image.Image:
    rgba = image.convert("RGBA")
    rgba.thumbnail(size, Image.Resampling.NEAREST if nearest else Image.Resampling.LANCZOS)
    checker = _checker(size)
    checker.alpha_composite(rgba, ((size[0] - rgba.width) // 2, (size[1] - rgba.height) // 2))
    return checker


def _label(draw: ImageDraw.ImageDraw, position: tuple[int, int], text: str) -> None:
    draw.rectangle((position[0] - 3, position[1] - 2, position[0] + len(text) * 7 + 4, position[1] + 14), fill=(0, 0, 0, 210))
    draw.text(position, text, fill=(255, 255, 255, 255))


def _panel_sheet(
    records: list[dict[str, Any]],
    columns: list[tuple[str, str]],
    *,
    panel_size: tuple[int, int] = (250, 250),
    jobs_per_row: int = 2,
) -> Image.Image:
    label_height = 26
    tile_width = panel_size[0] * len(columns)
    tile_height = panel_size[1] + label_height
    rows = (len(records) + jobs_per_row - 1) // jobs_per_row
    sheet = Image.new("RGBA", (tile_width * jobs_per_row, tile_height * rows), (18, 20, 26, 255))
    draw = ImageDraw.Draw(sheet)
    for index, record in enumerate(records):
        tile_x = (index % jobs_per_row) * tile_width
        tile_y = (index // jobs_per_row) * tile_height
        _label(draw, (tile_x + 7, tile_y + 6), record["label"])
        for column_index, (key, title) in enumerate(columns):
            image = record[key]
            x = tile_x + column_index * panel_size[0]
            y = tile_y + label_height
            if key in {"rgba", "old_sprite", "sprite"}:
                panel = _on_checker(image, panel_size, nearest=key in {"old_sprite", "sprite"})
            else:
                panel = _contain(image, panel_size)
            sheet.alpha_composite(panel, (x, y))
            _label(draw, (x + 6, y + 6), title)
    return sheet


def _mask_metrics(mask: Image.Image) -> dict[str, Any]:
    alpha = np.asarray(mask.convert("L"), dtype=np.uint8)
    hard = alpha > 8
    count, _, stats, _ = cv2.connectedComponentsWithStats(hard.astype(np.uint8), 8)
    border = np.concatenate((hard[0], hard[-1], hard[:, 0], hard[:, -1]))
    soft = (alpha > 0) & (alpha < 255)
    if np.any(hard):
        ys, xs = np.where(hard)
        bbox = [int(xs.min()), int(ys.min()), int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1)]
    else:
        bbox = None
    areas = [int(stats[index, cv2.CC_STAT_AREA]) for index in range(1, count)]
    return {
        "foreground_coverage": round(float(np.mean(hard)), 6),
        "edge_contact_ratio": round(float(np.mean(border)), 6),
        "soft_edge_pixel_ratio": round(float(np.mean(soft)), 6),
        "component_count": count - 1,
        "smallest_component_area": min(areas) if areas else 0,
        "object_bbox": bbox,
    }


def build(run_root: Path, flux2_root: Path, destination: Path) -> Path:
    run_root = run_root.resolve(strict=True)
    flux2_root = flux2_root.resolve(strict=True)
    destination = destination.resolve(strict=False)
    if destination.exists():
        raise ReviewAssetError("REVIEW_PACKET_ALREADY_EXISTS")
    run_evidence_sha256 = _verify_run_evidence(run_root)
    run_manifest = _json_object(run_root / "run_manifest.json")
    if run_manifest.get("contract") != "forge-birefnet-spike6-run-v1":
        raise ReviewAssetError("UNEXPECTED_RUN_CONTRACT")
    if run_manifest.get("run_id") != run_root.name:
        raise ReviewAssetError("RUN_ID_DIRECTORY_MISMATCH")
    if run_manifest.get("api_base") != "http://127.0.0.1:8190":
        raise ReviewAssetError("UNAPPROVED_API_BASE")
    if run_manifest.get("status") != "success":
        raise ReviewAssetError("RUN_NOT_SUCCESS")
    if run_manifest.get("planned_job_count") != 8 or run_manifest.get("completed_job_count") != 8:
        raise ReviewAssetError("RUN_NOT_EXACT_EIGHT")
    if run_manifest.get("retry_count") != 0 or run_manifest.get("serial_execution") is not True:
        raise ReviewAssetError("RUN_MANIFEST_NOT_EXACT_EIGHT_ZERO_RETRY")
    if run_manifest.get("workflow_sha256") != EXPECTED_WORKFLOW_SHA256:
        raise ReviewAssetError("UNAPPROVED_WORKFLOW_HASH")
    if run_manifest.get("source_freeze_sha256") != EXPECTED_SOURCE_FREEZE_SHA256:
        raise ReviewAssetError("UNAPPROVED_SOURCE_FREEZE_HASH")
    run_jobs = run_manifest.get("jobs")
    if not isinstance(run_jobs, list) or len(run_jobs) != len(EXPECTED_JOBS):
        raise ReviewAssetError("RUN_JOB_LIST_NOT_EXACT_EIGHT")
    expected_dir_names = {expected[3] for expected in EXPECTED_JOBS}
    actual_dir_names = {path.name for path in run_root.iterdir() if path.is_dir()}
    if actual_dir_names != expected_dir_names:
        raise ReviewAssetError("RUN_JOB_DIRECTORY_SET_MISMATCH")

    records: list[dict[str, Any]] = []
    metric_rows: list[dict[str, Any]] = []
    input_records: list[dict[str, Any]] = []
    for expected, run_job in zip(EXPECTED_JOBS, run_jobs, strict=True):
        expected_ordinal, expected_case, expected_seed, expected_directory = expected
        if (
            run_job.get("ordinal") != expected_ordinal
            or run_job.get("case_id") != expected_case
            or run_job.get("seed_id") != expected_seed
            or run_job.get("status") != "success"
            or run_job.get("retry_count") != 0
            or run_job.get("workflow_sha256") != EXPECTED_WORKFLOW_SHA256
        ):
            raise ReviewAssetError(f"RUN_JOB_BINDING_MISMATCH:{expected_directory}")
        job_dir = run_root / expected_directory
        job = _json_object(job_dir / "manifest.json")
        if job != run_job:
            raise ReviewAssetError(f"JOB_MANIFEST_DIFFERS_FROM_RUN:{expected_directory}")
        delivery_metrics = _json_object(job_dir / "delivery" / "metrics.json")
        raw_path = (flux2_root / str(job["source_raw_path"])).resolve(strict=True)
        try:
            raw_path.relative_to(flux2_root)
        except ValueError as exc:
            raise ReviewAssetError("SOURCE_RAW_ESCAPES_FLUX2_ROOT") from exc
        if _sha256(raw_path) != job.get("source_raw_sha256"):
            raise ReviewAssetError(f"SOURCE_RAW_HASH_MISMATCH:{expected_directory}")
        rgba_path = job_dir / "rgba.png"
        mask_path = job_dir / "mask.png"
        if _sha256(rgba_path) != job.get("rgba_sha256"):
            raise ReviewAssetError(f"RGBA_HASH_MISMATCH:{expected_directory}")
        if _sha256(mask_path) != job.get("mask_sha256"):
            raise ReviewAssetError(f"MASK_HASH_MISMATCH:{expected_directory}")
        old_manifest = _json_object(raw_path.parent / "manifest.json")
        old_sprite_path = raw_path.parent / "processed_sprite.png"
        with Image.open(raw_path) as opened:
            raw = opened.convert("RGB").copy()
        with Image.open(rgba_path) as opened:
            if opened.mode != "RGBA":
                raise ReviewAssetError("BIREFNET_RGBA_NOT_RGBA")
            rgba = opened.copy()
        with Image.open(mask_path) as opened:
            if opened.mode != "L":
                raise ReviewAssetError("BIREFNET_MASK_NOT_L")
            mask = opened.copy()
        sprite, _ = _validate_delivery(
            job_dir / "delivery" / "processed_sprite.png",
            job_dir / "delivery" / "alpha_mask.png",
            delivery_metrics,
        )
        if old_sprite_path.is_file():
            with Image.open(old_sprite_path) as opened:
                old_sprite = opened.convert("RGBA").copy()
            old_alpha_status = "success"
        else:
            old_sprite = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
            old_alpha_status = f"failed:{old_manifest.get('failure_reason', 'NO_SPRITE')}"
        label = f"{str(job['case_id']).upper()} / {str(job['seed_id']).replace('seed_', '')}"
        records.append(
            {
                "label": label,
                "raw": raw,
                "rgba": rgba,
                "mask": mask.convert("RGB"),
                "old_sprite": old_sprite,
                "sprite": sprite,
            }
        )
        mask_stats = _mask_metrics(mask)
        metric_rows.append(
            {
                "ordinal": job["ordinal"],
                "case_id": str(job["case_id"]).upper(),
                "seed": str(job["seed_id"]).replace("seed_", ""),
                "source_raw_sha256": job["source_raw_sha256"],
                "birefnet_rgba_sha256": job["rgba_sha256"],
                "birefnet_mask_sha256": job["mask_sha256"],
                "birefnet_status": job["status"],
                "old_alpha_status": old_alpha_status,
                **mask_stats,
                "segmentation_confidence": delivery_metrics["segmentation_confidence"],
                "postprocess_seconds": delivery_metrics["postprocess_seconds"],
                "processed_dimensions": "x".join(map(str, delivery_metrics["processed_dimensions"])),
                "processed_alpha_coverage": delivery_metrics["alpha_coverage"],
                "visible_color_count": delivery_metrics["visible_color_count"],
                "largest_component_only": delivery_metrics["largest_component_only"],
                "case_specific_logic": delivery_metrics["case_specific_logic"],
            }
        )
        for evidence_path in (
            raw_path,
            job_dir / "manifest.json",
            job_dir / "request_workflow.json",
            rgba_path,
            mask_path,
            job_dir / "delivery" / "processed_sprite.png",
            job_dir / "delivery" / "alpha_mask.png",
            job_dir / "delivery" / "metrics.json",
        ):
            input_records.append(_file_record(evidence_path, flux2_root))

    destination.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix=f".{destination.name}.tmp-", dir=str(destination.parent)))
    published = False
    try:
        _panel_sheet(records, [("raw", "Spike 5 raw"), ("rgba", "BiRefNet RGBA"), ("mask", "BiRefNet mask")]).save(
            stage / "birefnet_raw_rgba_comparison.png"
        )
        _panel_sheet(records, [("mask", "foreground mask")], panel_size=(300, 300), jobs_per_row=4).save(
            stage / "birefnet_masks.png"
        )
        _panel_sheet(records, [("raw", "raw"), ("old_sprite", "old chroma"), ("sprite", "BiRefNet 96")]).save(
            stage / "old_alpha_vs_birefnet.png"
        )
        _panel_sheet(records, [("sprite", "96x96")], panel_size=(300, 300), jobs_per_row=4).save(
            stage / "final_96_sprite_sheet.png"
        )
        fieldnames = list(metric_rows[0])
        with (stage / "alpha_metrics.csv").open("x", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(metric_rows)
        artifact_records = [
            _file_record(path, stage)
            for path in sorted(stage.iterdir())
            if path.is_file()
        ]
        packet_manifest = {
            "contract": "forge-birefnet-spike6-verified-review-packet-v1",
            "status": "PASS",
            "source_run_id": run_manifest["run_id"],
            "source_run_manifest_sha256": _sha256(run_root / "run_manifest.json"),
            "source_run_evidence_sha256": run_evidence_sha256,
            "source_freeze_sha256": run_manifest["source_freeze_sha256"],
            "workflow_sha256": run_manifest["workflow_sha256"],
            "job_count": len(records),
            "retry_count": run_manifest["retry_count"],
            "serial_execution": run_manifest["serial_execution"],
            "input_file_count": len(input_records),
            "input_files": input_records,
            "artifact_file_count": len(artifact_records),
            "artifacts": artifact_records,
        }
        (stage / "review_packet_manifest.json").write_text(
            json.dumps(packet_manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        if destination.exists():
            raise ReviewAssetError("REVIEW_PACKET_ALREADY_EXISTS")
        os.rename(stage, destination)
        published = True
    finally:
        if not published and stage.exists():
            shutil.rmtree(stage)
    return destination


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-root", type=Path, required=True)
    parser.add_argument("--flux2-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        output = build(args.run_root, args.flux2_root, args.output)
    except (ReviewAssetError, OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(json.dumps({"status": "failed", "failure_reason": str(exc)}))
        return 2
    print(json.dumps({"status": "success", "output": str(output)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
