#!/usr/bin/env python3
"""Freeze and verify the canonical Spike 5 inputs used by Spike 6.

This module is deliberately read-only with respect to Spike 5.  It writes one
new, non-overwriting SHA-256 manifest and never copies or edits source evidence.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import uuid
from pathlib import Path
from typing import Any, Mapping


FREEZE_CONTRACT = "forge-birefnet-spike6-source-freeze-v1"
CASE_ORDER = ("b01", "b02", "b03", "b04")


class Spike5FreezeError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def _json_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise Spike5FreezeError(f"JSON_READ_FAILED:{path}") from exc
    if not isinstance(value, dict):
        raise Spike5FreezeError(f"JSON_OBJECT_REQUIRED:{path}")
    return value


def _relative(root: Path, path: Path) -> str:
    resolved = path.resolve(strict=True)
    try:
        return resolved.relative_to(root.resolve(strict=True)).as_posix()
    except ValueError as exc:
        raise Spike5FreezeError(f"SOURCE_OUTSIDE_FLUX2_ROOT:{path}") from exc


def _file_entry(root: Path, path: Path) -> dict[str, Any]:
    if path.is_symlink() or not path.is_file():
        raise Spike5FreezeError(f"SOURCE_FILE_INVALID:{path}")
    return {
        "path": _relative(root, path),
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def _canonical_run(flux2_root: Path) -> tuple[Path, dict[str, Any], dict[str, Any]]:
    reports = flux2_root / "reports"
    summary = _json_object(reports / "flux2_matrix_summary.json")
    evidence = _json_object(reports / "evidence_hashes.json")
    group = summary.get("matrix_output_group")
    if not isinstance(group, str) or not group.startswith("flux2_matrix_"):
        raise Spike5FreezeError("SPIKE5_SUMMARY_OUTPUT_GROUP_INVALID")
    run = (flux2_root / "output" / group).resolve(strict=False)
    if run.parent != (flux2_root / "output").resolve() or not run.is_dir():
        raise Spike5FreezeError("SPIKE5_CANONICAL_RUN_MISSING")
    evidence_run = str(evidence.get("matrix_run_directory", "")).replace("\\", "/")
    if not evidence_run.endswith(f"tools/comfyui/flux2/output/{group}"):
        raise Spike5FreezeError("SPIKE5_EVIDENCE_RUN_MISMATCH")
    if summary.get("technical_results", {}).get("raw_delivered_count") != 8:
        raise Spike5FreezeError("SPIKE5_RAW_COUNT_NOT_EIGHT")
    return run, summary, evidence


def build_freeze(flux2_root: Path) -> dict[str, Any]:
    """Build an in-memory freeze from the canonical report-selected run."""

    flux2_root = flux2_root.resolve(strict=True)
    run, summary, evidence = _canonical_run(flux2_root)
    matrix_files = evidence.get("matrix_files")
    if not isinstance(matrix_files, Mapping):
        raise Spike5FreezeError("SPIKE5_MATRIX_HASHES_MISSING")

    jobs: list[dict[str, Any]] = []
    source_files: dict[str, dict[str, Any]] = {}
    workflow_hashes: set[str] = set()
    workflow_files: set[str] = set()
    model_hashes: dict[str, str] | None = None
    processed_count = 0
    mask_count = 0
    for case_id in CASE_ORDER:
        case_root = run / case_id
        seed_dirs = sorted(path for path in case_root.glob("seed_*") if path.is_dir())
        if len(seed_dirs) != 2:
            raise Spike5FreezeError(f"SPIKE5_EXPECTED_TWO_SEEDS:{case_id}")
        for seed_dir in seed_dirs:
            required = {
                "raw": seed_dir / "raw.png",
                "manifest": seed_dir / "manifest.json",
                "blueprint_projection": seed_dir / "blueprint_projection.json",
                "request_workflow": seed_dir / "request_workflow.json",
            }
            entries = {name: _file_entry(flux2_root, path) for name, path in required.items()}
            for entry in entries.values():
                evidence_key = f"tools/comfyui/flux2/{entry['path']}"
                frozen = matrix_files.get(evidence_key)
                if not isinstance(frozen, Mapping) or frozen.get("sha256") != entry["sha256"]:
                    raise Spike5FreezeError(f"SPIKE5_EXISTING_EVIDENCE_MISMATCH:{entry['path']}")
                source_files[entry["path"]] = entry

            manifest = _json_object(required["manifest"])
            if manifest.get("case_id") != case_id or manifest.get("run_id") != seed_dir.name:
                raise Spike5FreezeError(f"SPIKE5_MANIFEST_ID_MISMATCH:{case_id}/{seed_dir.name}")
            if manifest.get("retry_count") != 0 or not str(manifest.get("status", "")).startswith(("success", "raw_success")):
                raise Spike5FreezeError(f"SPIKE5_MANIFEST_NOT_SUCCESSFUL:{case_id}/{seed_dir.name}")
            workflow_hash = manifest.get("workflow_sha256")
            workflow_file = manifest.get("workflow_file")
            models = manifest.get("model_sha256")
            if not isinstance(workflow_hash, str) or len(workflow_hash) != 64:
                raise Spike5FreezeError("SPIKE5_WORKFLOW_HASH_INVALID")
            if not isinstance(workflow_file, str) or Path(workflow_file).name != workflow_file:
                raise Spike5FreezeError("SPIKE5_WORKFLOW_FILE_INVALID")
            if not isinstance(models, dict) or not models or any(
                not isinstance(value, str) or len(value) != 64 for value in models.values()
            ):
                raise Spike5FreezeError("SPIKE5_MODEL_HASHES_INVALID")
            workflow_hashes.add(workflow_hash)
            workflow_files.add(workflow_file)
            if model_hashes is None:
                model_hashes = dict(models)
            elif model_hashes != models:
                raise Spike5FreezeError("SPIKE5_MODEL_HASHES_CHANGED_WITHIN_RUN")

            optional: dict[str, Any] = {}
            processed = seed_dir / "processed_sprite.png"
            mask = seed_dir / "alpha_mask.png"
            if processed.exists() != mask.exists():
                raise Spike5FreezeError(f"SPIKE5_PARTIAL_ALPHA_PAIR:{case_id}/{seed_dir.name}")
            if processed.is_file():
                optional["processed_sprite"] = _file_entry(flux2_root, processed)
                optional["alpha_mask"] = _file_entry(flux2_root, mask)
                processed_count += 1
                mask_count += 1
                for entry in optional.values():
                    evidence_key = f"tools/comfyui/flux2/{entry['path']}"
                    frozen = matrix_files.get(evidence_key)
                    if not isinstance(frozen, Mapping) or frozen.get("sha256") != entry["sha256"]:
                        raise Spike5FreezeError(f"SPIKE5_EXISTING_EVIDENCE_MISMATCH:{entry['path']}")
                    source_files[entry["path"]] = entry

            jobs.append(
                {
                    "ordinal": len(jobs) + 1,
                    "case_id": case_id,
                    "seed_id": seed_dir.name,
                    "raw": entries["raw"],
                    "manifest": entries["manifest"],
                    "blueprint_projection": entries["blueprint_projection"],
                    "request_workflow": entries["request_workflow"],
                    "current_alpha_outputs": optional,
                }
            )

    if len(jobs) != 8 or processed_count != mask_count:
        raise Spike5FreezeError("SPIKE5_JOB_SET_INVALID")

    report_names = (
        "flux2_matrix_summary.json",
        "flux2_matrix_results.csv",
        "human_visual_review.csv",
        "human_visual_review_rubric.json",
        "frozen_semantic_blueprints.json",
        "workflow_sources.json",
        "model_download_manifest.json",
        "runtime_install_manifest.json",
        "evidence_hashes.json",
    )
    report_files = {
        name: _file_entry(flux2_root, flux2_root / "reports" / name)
        for name in report_names
    }
    source_files.update({entry["path"]: entry for entry in report_files.values()})
    if len(workflow_files) != 1 or len(workflow_hashes) != 1:
        raise Spike5FreezeError("SPIKE5_WORKFLOW_IDENTITY_CHANGED_WITHIN_RUN")
    workflow_file = flux2_root / "workflows" / next(iter(workflow_files))
    workflow_entry = _file_entry(flux2_root, workflow_file)
    if workflow_entry["sha256"] != next(iter(workflow_hashes)):
        raise Spike5FreezeError("SPIKE5_WORKFLOW_FILE_HASH_MISMATCH")
    source_files[workflow_entry["path"]] = workflow_entry

    download_manifest = _json_object(flux2_root / "reports" / "model_download_manifest.json")
    downloaded = download_manifest.get("files")
    if not isinstance(downloaded, list):
        raise Spike5FreezeError("SPIKE5_MODEL_DOWNLOAD_LIST_MISSING")
    downloaded_by_name = {
        item.get("filename"): item.get("sha256")
        for item in downloaded
        if isinstance(item, dict)
    }
    first_manifest_path = flux2_root / jobs[0]["manifest"]["path"]
    manifest_model_names = _json_object(first_manifest_path).get("models")
    if not isinstance(manifest_model_names, dict) or set(manifest_model_names) != set(model_hashes or {}):
        raise Spike5FreezeError("SPIKE5_MODEL_NAME_EVIDENCE_INVALID")
    for role, expected_hash in (model_hashes or {}).items():
        if downloaded_by_name.get(manifest_model_names[role]) != expected_hash:
            raise Spike5FreezeError(f"SPIKE5_MODEL_DOWNLOAD_HASH_MISMATCH:{role}")
    blueprint_sha = report_files["frozen_semantic_blueprints.json"]["sha256"]
    if summary.get("frozen_blueprints_sha256") != blueprint_sha:
        raise Spike5FreezeError("SPIKE5_BLUEPRINT_HASH_MISMATCH")

    return {
        "contract": FREEZE_CONTRACT,
        "algorithm": "SHA-256",
        "source_matrix_run_id": summary.get("matrix_run_id"),
        "source_output_group": summary.get("matrix_output_group"),
        "case_order": list(CASE_ORDER),
        "job_count": len(jobs),
        "raw_png_count": len(jobs),
        "manifest_count": len(jobs),
        "current_processed_sprite_count": processed_count,
        "current_alpha_mask_count": mask_count,
        "semantic_blueprints_sha256": blueprint_sha,
        "generation_workflow_sha256": sorted(workflow_hashes),
        "generation_workflow_file": workflow_entry,
        "generation_model_sha256": model_hashes or {},
        "source_evidence_manifest_sha256": report_files["evidence_hashes.json"]["sha256"],
        "jobs": jobs,
        "report_files": report_files,
        "files": dict(sorted(source_files.items())),
    }


def verify_freeze(flux2_root: Path, freeze: Mapping[str, Any] | Path) -> dict[str, Any]:
    """Verify every frozen source byte and the exact eight-job contract."""

    if isinstance(freeze, Path):
        document = _json_object(freeze)
    else:
        document = dict(freeze)
    if document.get("contract") != FREEZE_CONTRACT:
        raise Spike5FreezeError("FREEZE_CONTRACT_INVALID")
    if document.get("job_count") != 8 or document.get("raw_png_count") != 8 or document.get("manifest_count") != 8:
        raise Spike5FreezeError("FREEZE_COUNT_INVALID")
    if document.get("case_order") != list(CASE_ORDER):
        raise Spike5FreezeError("FREEZE_CASE_ORDER_INVALID")
    jobs = document.get("jobs")
    if not isinstance(jobs, list) or len(jobs) != 8 or [job.get("ordinal") for job in jobs if isinstance(job, dict)] != list(range(1, 9)):
        raise Spike5FreezeError("FREEZE_JOBS_INVALID")
    expected_cases = [case_id for case_id in CASE_ORDER for _ in range(2)]
    if [job.get("case_id") for job in jobs] != expected_cases:
        raise Spike5FreezeError("FREEZE_JOB_CASES_INVALID")
    raw_paths = [job.get("raw", {}).get("path") for job in jobs]
    manifest_paths = [job.get("manifest", {}).get("path") for job in jobs]
    if len(set(raw_paths)) != 8 or len(set(manifest_paths)) != 8:
        raise Spike5FreezeError("FREEZE_JOB_SOURCE_DUPLICATE")
    files = document.get("files")
    if not isinstance(files, dict) or not files:
        raise Spike5FreezeError("FREEZE_FILES_MISSING")
    for job in jobs:
        for field in ("raw", "manifest", "blueprint_projection", "request_workflow"):
            entry = job.get(field)
            if not isinstance(entry, dict) or files.get(entry.get("path")) != entry:
                raise Spike5FreezeError(f"FREEZE_JOB_ENTRY_UNBOUND:{field}")
        optional = job.get("current_alpha_outputs")
        if not isinstance(optional, dict) or set(optional) not in (set(), {"processed_sprite", "alpha_mask"}):
            raise Spike5FreezeError("FREEZE_ALPHA_PAIR_INVALID")
        if any(files.get(entry.get("path")) != entry for entry in optional.values() if isinstance(entry, dict)):
            raise Spike5FreezeError("FREEZE_ALPHA_ENTRY_UNBOUND")
    root = flux2_root.resolve(strict=True)
    for relative, entry in files.items():
        if not isinstance(relative, str) or not isinstance(entry, dict) or entry.get("path") != relative:
            raise Spike5FreezeError("FREEZE_FILE_ENTRY_INVALID")
        candidate = (root / Path(relative)).resolve(strict=False)
        try:
            candidate.relative_to(root)
        except ValueError as exc:
            raise Spike5FreezeError(f"FREEZE_PATH_ESCAPE:{relative}") from exc
        if candidate.is_symlink() or not candidate.is_file():
            raise Spike5FreezeError(f"FROZEN_SOURCE_MISSING:{relative}")
        if candidate.stat().st_size != entry.get("bytes") or sha256_file(candidate) != entry.get("sha256"):
            raise Spike5FreezeError(f"FROZEN_SOURCE_CHANGED:{relative}")
    return document


def _atomic_write_new(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if os.path.lexists(path):
        raise Spike5FreezeError(f"FREEZE_ALREADY_EXISTS:{path}")
    temp = path.parent / f".{path.name}.{uuid.uuid4().hex}.tmp"
    try:
        with temp.open("xb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.link(temp, path)
    except FileExistsError as exc:
        raise Spike5FreezeError(f"FREEZE_ALREADY_EXISTS:{path}") from exc
    finally:
        if temp.exists():
            temp.unlink()


def freeze_to_file(flux2_root: Path, destination: Path) -> dict[str, Any]:
    before = build_freeze(flux2_root)
    verify_freeze(flux2_root, before)
    payload = (json.dumps(before, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    _atomic_write_new(destination, payload)
    published = verify_freeze(flux2_root, destination)
    if published != before:
        raise Spike5FreezeError("PUBLISHED_FREEZE_CHANGED")
    return published


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flux2-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    try:
        result = verify_freeze(args.flux2_root, args.output) if args.verify_only else freeze_to_file(args.flux2_root, args.output)
        print(json.dumps({"status": "PASS", "job_count": result["job_count"], "output": str(args.output.resolve())}))
        return 0
    except Spike5FreezeError as exc:
        print(json.dumps({"status": "NEEDS WORK", "failure_reason": str(exc)}))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
