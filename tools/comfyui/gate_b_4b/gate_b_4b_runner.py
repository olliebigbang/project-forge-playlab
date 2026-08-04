from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

from PIL import Image


ROOT = Path(__file__).resolve().parent
PROJECT_ROOT = ROOT.parent.parent.parent
FROZEN_4A_PATH = ROOT / "frozen_4a_evidence.json"
FROZEN_GAMEPLAY_PATH = ROOT / "frozen_gameplay_evidence.json"
PROCESSOR_PATH = ROOT / "process_sprite_v2.py"
OUTPUT_ROOT = ROOT / "output"
RESERVATION_ROOT = ROOT / "reservations"

EXPECTED_FROZEN_4A_SHA256 = "95b4e4141e241e723bffa9c8a0dc22cbd19b1780c7ef1f02e39c80ac0574709d"
EXPECTED_FROZEN_GAMEPLAY_SHA256 = "27b1f9d643862adbd004a6c04326a680d386229ee064a2a46f1eb2a178fa2245"
EXPECTED_PAIRS = (
    ("B01", 4041001),
    ("B01", 4041002),
    ("B02", 4041001),
    ("B02", 4041002),
    ("B03", 4041001),
    ("B03", 4041002),
    ("B04", 4041001),
    ("B04", 4041002),
)
GAMEPLAY_ROOT_FILES = ("project.godot", "export_presets.cfg")
GAMEPLAY_DIRECTORIES = ("scenes", "scripts", "tests")
REQUIRED_ALPHA_METRICS = (
    "foreground_coverage",
    "edge_contact_ratio",
    "background_residual_ratio",
    "internal_hole_ratio",
    "component_count",
    "kept_component_count",
    "removed_component_count",
    "removed_area",
    "smallest_kept_component_area",
    "object_bbox",
    "soft_edge_pixel_ratio",
    "shadow_residual_score",
    "segmentation_confidence",
)

sys.path.insert(0, str(ROOT))
from process_sprite_v2 import SpritePostprocessError, process_sprite  # noqa: E402


class GateB4BRunnerError(RuntimeError):
    pass


Processor = Callable[..., dict[str, Any]]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise GateB4BRunnerError(f"INVALID_JSON:{path}") from exc
    if not isinstance(value, dict):
        raise GateB4BRunnerError(f"JSON_ROOT_NOT_OBJECT:{path}")
    return value


def _write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True).encode("utf-8") + b"\n")


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _display_path(path: Path, project_root: Path) -> str:
    try:
        return path.resolve().relative_to(project_root.resolve()).as_posix()
    except ValueError:
        return path.resolve().as_posix()


def _resolve_project_path(project_root: Path, relative: str) -> Path:
    if not isinstance(relative, str) or not relative or Path(relative).is_absolute():
        raise GateB4BRunnerError(f"INVALID_FROZEN_PATH:{relative!r}")
    root = project_root.resolve()
    candidate = (root / Path(relative)).resolve()
    try:
        candidate.relative_to(root)
    except ValueError as exc:
        raise GateB4BRunnerError(f"FROZEN_PATH_ESCAPES_PROJECT:{relative}") from exc
    return candidate


def _verify_record(path: Path, record: dict[str, Any], label: str) -> None:
    if not path.is_file():
        raise GateB4BRunnerError(f"FROZEN_FILE_MISSING:{label}")
    expected_size = record.get("size")
    expected_hash = record.get("sha256")
    if not isinstance(expected_size, int) or not isinstance(expected_hash, str):
        raise GateB4BRunnerError(f"INVALID_FROZEN_RECORD:{label}")
    actual_size = path.stat().st_size
    if actual_size != expected_size:
        raise GateB4BRunnerError(f"FROZEN_SIZE_MISMATCH:{label}:{actual_size}")
    actual_hash = sha256_file(path)
    if actual_hash != expected_hash:
        raise GateB4BRunnerError(f"FROZEN_HASH_MISMATCH:{label}:{actual_hash}")


def _load_and_verify_frozen_4a(
    *,
    project_root: Path = PROJECT_ROOT,
    frozen_path: Path = FROZEN_4A_PATH,
) -> tuple[dict[str, Any], dict[str, Any]]:
    manifest_hash = sha256_file(frozen_path)
    if manifest_hash != EXPECTED_FROZEN_4A_SHA256:
        raise GateB4BRunnerError(f"FROZEN_4A_MANIFEST_HASH_MISMATCH:{manifest_hash}")
    frozen = _read_json(frozen_path)
    if frozen.get("source_gate_formal_status") != "NEEDS WORK":
        raise GateB4BRunnerError("FROZEN_4A_STATUS_CHANGED")
    matrix = frozen.get("case_matrix")
    if not isinstance(matrix, list) or len(matrix) != len(EXPECTED_PAIRS):
        raise GateB4BRunnerError("FROZEN_RAW_COUNT_NOT_EIGHT")
    pairs: list[tuple[str, int]] = []
    raw_paths: set[Path] = set()
    for expected_ordinal, item in enumerate(matrix, start=1):
        if not isinstance(item, dict) or item.get("ordinal") != expected_ordinal:
            raise GateB4BRunnerError(f"FROZEN_CASE_ORDINAL_INVALID:{expected_ordinal}")
        case_id = item.get("case_id")
        seed = item.get("seed")
        if not isinstance(case_id, str) or not isinstance(seed, int):
            raise GateB4BRunnerError(f"FROZEN_CASE_KEY_INVALID:{expected_ordinal}")
        pairs.append((case_id, seed))
        raw_record = item.get("raw")
        if not isinstance(raw_record, dict):
            raise GateB4BRunnerError(f"FROZEN_RAW_RECORD_INVALID:{case_id}:{seed}")
        raw_path = _resolve_project_path(project_root, raw_record.get("path"))
        _verify_record(raw_path, raw_record, f"raw:{case_id}:{seed}")
        if raw_path in raw_paths:
            raise GateB4BRunnerError(f"DUPLICATE_FROZEN_RAW_PATH:{case_id}:{seed}")
        raw_paths.add(raw_path)
        for name in ("manifest", "request_workflow"):
            record = item.get(name)
            if not isinstance(record, dict):
                raise GateB4BRunnerError(f"FROZEN_{name.upper()}_INVALID:{case_id}:{seed}")
            _verify_record(
                _resolve_project_path(project_root, record.get("path")),
                record,
                f"{name}:{case_id}:{seed}",
            )
        for name in ("v1_processed_sprite", "v1_alpha_mask"):
            record = item.get(name)
            if record is not None:
                if not isinstance(record, dict):
                    raise GateB4BRunnerError(f"FROZEN_{name.upper()}_INVALID:{case_id}:{seed}")
                _verify_record(
                    _resolve_project_path(project_root, record.get("path")),
                    record,
                    f"{name}:{case_id}:{seed}",
                )
    if tuple(pairs) != EXPECTED_PAIRS:
        raise GateB4BRunnerError(f"FROZEN_CASE_MATRIX_CHANGED:{pairs}")

    tree = frozen.get("frozen_gate_4a_tree")
    if not isinstance(tree, dict) or frozen.get("frozen_gate_4a_tree_file_count") != len(tree):
        raise GateB4BRunnerError("FROZEN_4A_TREE_INVALID")
    gate_4a_root = project_root / "tools" / "comfyui" / "gate_b_4a"
    actual_tree = {
        path.relative_to(project_root).as_posix()
        for path in gate_4a_root.rglob("*")
        if path.is_file()
    }
    expected_tree = set(tree)
    if actual_tree != expected_tree:
        missing = sorted(expected_tree - actual_tree)
        added = sorted(actual_tree - expected_tree)
        raise GateB4BRunnerError(f"FROZEN_4A_TREE_CHANGED:missing={missing}:added={added}")
    for relative, record in tree.items():
        if not isinstance(record, dict):
            raise GateB4BRunnerError(f"INVALID_FROZEN_TREE_RECORD:{relative}")
        _verify_record(_resolve_project_path(project_root, relative), record, f"tree:{relative}")
    for entry in frozen.get("external_inputs", []):
        if not isinstance(entry, dict):
            raise GateB4BRunnerError("INVALID_EXTERNAL_INPUT_RECORD")
        _verify_record(
            _resolve_project_path(project_root, entry.get("path")), entry, f"external:{entry.get('path')}"
        )
    return frozen, {
        "status": "PASS",
        "manifest_sha256": manifest_hash,
        "frozen_tree_file_count": len(tree),
        "frozen_raw_count": len(raw_paths),
        "source_formal_status": "NEEDS WORK",
    }


def _current_gameplay_paths(project_root: Path) -> set[str]:
    paths = [project_root / name for name in GAMEPLAY_ROOT_FILES]
    for directory in GAMEPLAY_DIRECTORIES:
        paths.extend(path for path in (project_root / directory).rglob("*") if path.is_file())
    return {path.relative_to(project_root).as_posix() for path in paths if path.is_file()}


def _verify_gameplay_payload(payload: dict[str, Any], project_root: Path) -> dict[str, Any]:
    records = payload.get("files")
    if not isinstance(records, dict) or payload.get("file_count") != len(records):
        raise GateB4BRunnerError("FROZEN_GAMEPLAY_FILE_MAP_INVALID")
    actual_paths = _current_gameplay_paths(project_root)
    if actual_paths != set(records):
        missing = sorted(set(records) - actual_paths)
        added = sorted(actual_paths - set(records))
        raise GateB4BRunnerError(f"GAMEPLAY_TREE_CHANGED:missing={missing}:added={added}")
    for relative, record in records.items():
        if not isinstance(record, dict):
            raise GateB4BRunnerError(f"INVALID_GAMEPLAY_RECORD:{relative}")
        _verify_record(_resolve_project_path(project_root, relative), record, f"gameplay:{relative}")
    return {"status": "PASS", "file_count": len(records)}


def _load_and_verify_gameplay(
    *,
    project_root: Path = PROJECT_ROOT,
    frozen_path: Path = FROZEN_GAMEPLAY_PATH,
) -> tuple[dict[str, Any], dict[str, Any]]:
    manifest_hash = sha256_file(frozen_path)
    if manifest_hash != EXPECTED_FROZEN_GAMEPLAY_SHA256:
        raise GateB4BRunnerError(f"FROZEN_GAMEPLAY_MANIFEST_HASH_MISMATCH:{manifest_hash}")
    frozen = _read_json(frozen_path)
    audit = _verify_gameplay_payload(frozen, project_root)
    audit["manifest_sha256"] = manifest_hash
    return frozen, audit


def verify_frozen_inputs(
    *,
    project_root: Path = PROJECT_ROOT,
    frozen_4a_path: Path = FROZEN_4A_PATH,
    frozen_gameplay_path: Path = FROZEN_GAMEPLAY_PATH,
) -> tuple[dict[str, Any], dict[str, Any]]:
    frozen_4a, audit_4a = _load_and_verify_frozen_4a(
        project_root=project_root, frozen_path=frozen_4a_path
    )
    _, gameplay_audit = _load_and_verify_gameplay(
        project_root=project_root, frozen_path=frozen_gameplay_path
    )
    return frozen_4a, {"gate_4a": audit_4a, "gameplay": gameplay_audit}


def _reserve_unique_run(reservation_root: Path, output_root: Path) -> tuple[str, Path, dict[str, Any]]:
    reservation_root.mkdir(parents=True, exist_ok=True)
    output_root.mkdir(parents=True, exist_ok=True)
    for _ in range(16):
        run_id = f"gate-b-4b-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')}-{uuid.uuid4().hex[:8]}"
        final = output_root / run_id
        reservation = reservation_root / f"{run_id}.json"
        if final.exists():
            continue
        payload = {"run_id": run_id, "reserved_at": _utc_now(), "output_directory": str(final.resolve())}
        try:
            descriptor = os.open(reservation, os.O_WRONLY | os.O_CREAT | os.O_EXCL)
        except FileExistsError:
            continue
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(json.dumps(payload, ensure_ascii=False, indent=2).encode("utf-8") + b"\n")
            stream.flush()
            os.fsync(stream.fileno())
        return run_id, reservation, payload
    raise GateB4BRunnerError("UNABLE_TO_RESERVE_UNIQUE_RUN")


def _validate_metric_contract(metrics: dict[str, Any], label: str) -> None:
    missing = [name for name in REQUIRED_ALPHA_METRICS if name not in metrics]
    if missing:
        raise GateB4BRunnerError(f"V2_METRICS_MISSING:{label}:{missing}")
    if metrics.get("status") not in {"success", "rejected"}:
        raise GateB4BRunnerError(f"V2_METRICS_STATUS_INVALID:{label}")


def _validate_success_delivery(directory: Path, metrics: dict[str, Any], label: str) -> None:
    if metrics.get("status") != "success":
        raise GateB4BRunnerError(f"V2_SUCCESS_STATUS_INVALID:{label}")
    try:
        with Image.open(directory / "processed_sprite.png") as opened_sprite:
            if opened_sprite.format != "PNG" or opened_sprite.mode != "RGBA":
                raise GateB4BRunnerError(f"V2_SUCCESS_SPRITE_NOT_RGBA_PNG:{label}")
            opened_sprite.load()
            sprite = opened_sprite.copy()
        with Image.open(directory / "alpha_mask.png") as opened_alpha:
            if opened_alpha.format != "PNG" or opened_alpha.mode != "L":
                raise GateB4BRunnerError(f"V2_SUCCESS_MASK_NOT_GRAYSCALE_PNG:{label}")
            opened_alpha.load()
            alpha = opened_alpha.copy()
    except (OSError, ValueError) as exc:
        raise GateB4BRunnerError(f"V2_SUCCESS_ARTIFACT_INVALID:{label}") from exc
    if sprite.size != (96, 96) or alpha.size != (96, 96):
        raise GateB4BRunnerError(f"V2_SUCCESS_DIMENSIONS_INVALID:{label}")
    if alpha.getbbox() is None or sprite.getchannel("A").getbbox() is None:
        raise GateB4BRunnerError(f"V2_SUCCESS_ALPHA_EMPTY:{label}")
    if sprite.getchannel("A").tobytes() != alpha.tobytes():
        raise GateB4BRunnerError(f"V2_SUCCESS_ALPHA_MISMATCH:{label}")


def _validate_rejection_delivery(directory: Path, metrics: dict[str, Any], label: str) -> None:
    if metrics.get("status") != "rejected" or not metrics.get("failure_reason"):
        raise GateB4BRunnerError(f"V2_REJECTION_STATUS_INVALID:{label}")
    if (directory / "processed_sprite.png").exists() or (directory / "alpha_mask.png").exists():
        raise GateB4BRunnerError(f"V2_REJECTION_HAS_FAKE_SPRITE:{label}")
    debug_dir = directory / "debug"
    if not debug_dir.is_dir() or not any(debug_dir.glob("*.png")):
        raise GateB4BRunnerError(f"V2_REJECTION_DEBUG_MISSING:{label}")


def _artifact_hashes(directory: Path, run_root: Path) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for path in sorted(item for item in directory.rglob("*") if item.is_file()):
        if path.name == "result.json":
            continue
        result[path.relative_to(run_root).as_posix()] = {
            "size": path.stat().st_size,
            "sha256": sha256_file(path),
        }
    return result


def _run_one(
    item: dict[str, Any],
    *,
    project_root: Path,
    stage_root: Path,
    processor: Processor,
    processor_hash: str,
) -> dict[str, Any]:
    case_id = item["case_id"]
    seed = item["seed"]
    label = f"{case_id}:{seed}"
    source_record = item["raw"]
    source = _resolve_project_path(project_root, source_record["path"])
    destination = stage_root / case_id / f"seed_{seed}"
    invocation_started = time.perf_counter()
    failure_reason = ""
    try:
        metrics = processor(source, destination, debug=True)
        status = "success"
    except SpritePostprocessError as exc:
        status = "rejected"
        failure_reason = exc.code
        metrics = exc.metrics
        if exc.evidence_path is None or Path(exc.evidence_path).resolve() != destination.resolve():
            raise GateB4BRunnerError(f"V2_REJECTION_EVIDENCE_PATH_INVALID:{label}") from exc
    elapsed = round(time.perf_counter() - invocation_started, 3)
    if not destination.is_dir():
        raise GateB4BRunnerError(f"V2_DELIVERY_MISSING:{label}")
    metrics_path = destination / "metrics.json"
    written_metrics = _read_json(metrics_path)
    if metrics != written_metrics:
        raise GateB4BRunnerError(f"V2_RETURNED_METRICS_DIVERGE:{label}")
    _validate_metric_contract(written_metrics, label)
    if status == "success":
        _validate_success_delivery(destination, written_metrics, label)
    else:
        if written_metrics.get("failure_reason") != failure_reason:
            raise GateB4BRunnerError(f"V2_FAILURE_REASON_DIVERGES:{label}")
        _validate_rejection_delivery(destination, written_metrics, label)

    copied_raw = destination / "raw.png"
    shutil.copyfile(source, copied_raw)
    if sha256_file(copied_raw) != source_record["sha256"]:
        raise GateB4BRunnerError(f"RAW_COPY_HASH_MISMATCH:{label}")
    record: dict[str, Any] = {
        "ordinal": item["ordinal"],
        "case_id": case_id,
        "seed": seed,
        "source_raw": source_record,
        "copied_raw": {
            "path": copied_raw.relative_to(stage_root).as_posix(),
            "size": copied_raw.stat().st_size,
            "sha256": sha256_file(copied_raw),
        },
        "v1": {
            "status": item.get("v1_status"),
            "failure_reason": item.get("v1_failure_reason", ""),
            "processed_sprite": item.get("v1_processed_sprite"),
            "alpha_mask": item.get("v1_alpha_mask"),
        },
        "v2": {
            "method": "opencv_chroma_grabcut",
            "status": status,
            "failure_reason": failure_reason,
            "metrics": written_metrics,
            "processor_invocation_count": 1,
            "processor_sha256": processor_hash,
            "runner_observed_seconds": elapsed,
        },
    }
    record["artifact_hashes"] = _artifact_hashes(destination, stage_root)
    _write_json(destination / "result.json", record)
    record["result_sha256"] = sha256_file(destination / "result.json")
    return record


def _safe_remove_stage(stage: Path, temporary_root: Path) -> None:
    if not stage.exists():
        return
    resolved_stage = stage.resolve()
    resolved_temporary = temporary_root.resolve()
    try:
        resolved_stage.relative_to(resolved_temporary)
    except ValueError as exc:
        raise GateB4BRunnerError(f"REFUSING_STAGE_CLEANUP:{resolved_stage}") from exc
    shutil.rmtree(resolved_stage)


def run_gate_b_4b(
    *,
    project_root: Path = PROJECT_ROOT,
    frozen_4a_path: Path = FROZEN_4A_PATH,
    frozen_gameplay_path: Path = FROZEN_GAMEPLAY_PATH,
    processor_path: Path = PROCESSOR_PATH,
    output_root: Path = OUTPUT_ROOT,
    reservation_root: Path = RESERVATION_ROOT,
    processor: Processor = process_sprite,
) -> dict[str, Any]:
    frozen, preflight = verify_frozen_inputs(
        project_root=project_root,
        frozen_4a_path=frozen_4a_path,
        frozen_gameplay_path=frozen_gameplay_path,
    )
    processor_hash = sha256_file(processor_path)
    run_id, reservation_path, reservation = _reserve_unique_run(reservation_root, output_root)
    final_root = output_root / run_id
    temporary_root = output_root / ".tmp"
    temporary_root.mkdir(parents=True, exist_ok=True)
    stage = temporary_root / f"{run_id}-{uuid.uuid4().hex}"
    stage.mkdir()
    started_at = _utc_now()
    started = time.perf_counter()
    published = False
    try:
        results = [
            _run_one(
                item,
                project_root=project_root,
                stage_root=stage,
                processor=processor,
                processor_hash=processor_hash,
            )
            for item in frozen["case_matrix"]
        ]
        if len(results) != 8 or sum(item["v2"]["processor_invocation_count"] for item in results) != 8:
            raise GateB4BRunnerError("V2_INVOCATION_COUNT_NOT_EIGHT")
        if sha256_file(processor_path) != processor_hash:
            raise GateB4BRunnerError("PROCESSOR_CHANGED_DURING_RUN")
        _, postflight = verify_frozen_inputs(
            project_root=project_root,
            frozen_4a_path=frozen_4a_path,
            frozen_gameplay_path=frozen_gameplay_path,
        )
        success_count = sum(item["v2"]["status"] == "success" for item in results)
        summary = {
            "gate": "Forge Gate B 4B - Offline Alpha Extraction Spike",
            "run_id": run_id,
            "status": "TECHNICAL_OUTPUT_READY_FOR_HUMAN_REVIEW",
            "started_at": started_at,
            "completed_at": _utc_now(),
            "runner_seconds": round(time.perf_counter() - started, 3),
            "source_gate_4a_formal_status_preserved": "NEEDS WORK",
            "method_a": "opencv_chroma_grabcut",
            "method_b": "not_invoked_by_runner",
            "processor": {
                "path": _display_path(processor_path, project_root),
                "sha256": processor_hash,
            },
            "reservation": {**reservation, "path": _display_path(reservation_path, project_root)},
            "preflight": preflight,
            "postflight": postflight,
            "raw_count": 8,
            "processor_invocation_count": 8,
            "v2_success_count": success_count,
            "v2_rejected_count": 8 - success_count,
            "automatic_retry_count": 0,
            "results": results,
        }
        _write_json(stage / "run_summary.json", summary)
        _write_json(stage / "RUN_COMPLETE.json", {"run_id": run_id, "result_directory_count": 8})
        if final_root.exists():
            raise GateB4BRunnerError("FINAL_RUN_DIRECTORY_ALREADY_EXISTS")
        os.rename(stage, final_root)
        published = True
        summary["run_directory"] = _display_path(final_root, project_root)
        summary["run_summary_sha256"] = sha256_file(final_root / "run_summary.json")
        return summary
    finally:
        if not published:
            _safe_remove_stage(stage, temporary_root)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the eight-image Gate B 4B offline Alpha extraction matrix.")
    parser.add_argument("--output-root", type=Path, default=OUTPUT_ROOT)
    parser.add_argument("--reservation-root", type=Path, default=RESERVATION_ROOT)
    args = parser.parse_args()
    try:
        summary = run_gate_b_4b(output_root=args.output_root, reservation_root=args.reservation_root)
    except (GateB4BRunnerError, SpritePostprocessError, OSError) as exc:
        print(json.dumps({"status": "NEEDS WORK", "failure_reason": str(exc)}, ensure_ascii=False))
        return 2
    print(
        json.dumps(
            {
                "status": summary["status"],
                "run_id": summary["run_id"],
                "run_directory": summary["run_directory"],
                "v2_success_count": summary["v2_success_count"],
                "v2_rejected_count": summary["v2_rejected_count"],
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
