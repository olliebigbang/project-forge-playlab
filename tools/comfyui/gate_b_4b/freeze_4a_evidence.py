from __future__ import annotations

import hashlib
import json
import os
import sys
import uuid
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent
COMFY_ROOT = ROOT.parent
PROJECT_ROOT = COMFY_ROOT.parent.parent
GATE_4A_ROOT = COMFY_ROOT / "gate_b_4a"
RUN_ID = "gate-b-4a-20260803T094025408228Z-e25bf1f7"
RUN_ROOT = GATE_4A_ROOT / "output" / RUN_ID
TARGET = ROOT / "frozen_4a_evidence.json"
CASE_ORDER = ("B01", "B02", "B03", "B04")
SEEDS = (4041001, 4041002)


class FreezeError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def relative(path: Path) -> str:
    return path.resolve().relative_to(PROJECT_ROOT).as_posix()


def file_record(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise FreezeError(f"REQUIRED_4A_FILE_MISSING:{relative(path)}")
    return {"path": relative(path), "size": path.stat().st_size, "sha256": sha256_file(path)}


def build_manifest() -> dict[str, Any]:
    summary_path = RUN_ROOT / "generation_summary.json"
    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    if summary.get("run_id") != RUN_ID or summary.get("result_directory_count") != 8:
        raise FreezeError("GATE_4A_SUMMARY_MATRIX_INVALID")
    if summary.get("request_attempt_count") != 8 or summary.get("automatic_retry_count") != 0:
        raise FreezeError("GATE_4A_CALL_BOUNDARY_INVALID")
    cases: list[dict[str, Any]] = []
    raw_hashes: set[str] = set()
    v1_processed_count = 0
    v1_alpha_count = 0
    for ordinal, (case_id, seed) in enumerate(
        ((case_id, seed) for case_id in CASE_ORDER for seed in SEEDS), start=1
    ):
        result_root = RUN_ROOT / case_id / f"seed_{seed}"
        manifest_path = result_root / "manifest.json"
        workflow_path = result_root / "request_workflow.json"
        raw_path = result_root / "raw.png"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if manifest.get("case_id") != case_id or manifest.get("seed") != seed:
            raise FreezeError(f"GATE_4A_MANIFEST_IDENTITY_CHANGED:{case_id}:{seed}")
        if manifest.get("attempt_ordinal") != ordinal or manifest.get("retry_count") != 0:
            raise FreezeError(f"GATE_4A_MANIFEST_CALL_BOUNDARY_CHANGED:{case_id}:{seed}")
        raw_record = file_record(raw_path)
        raw_hashes.add(raw_record["sha256"])
        processed_path = result_root / "processed_sprite.png"
        alpha_path = result_root / "alpha_mask.png"
        processed_record = file_record(processed_path) if processed_path.is_file() else None
        alpha_record = file_record(alpha_path) if alpha_path.is_file() else None
        v1_processed_count += int(processed_record is not None)
        v1_alpha_count += int(alpha_record is not None)
        cases.append(
            {
                "ordinal": ordinal,
                "case_id": case_id,
                "seed": seed,
                "raw": raw_record,
                "manifest": file_record(manifest_path),
                "request_workflow": file_record(workflow_path),
                "effective_positive_prompt_sha256": manifest["effective_positive_prompt_sha256"],
                "effective_negative_prompt_sha256": manifest["effective_negative_prompt_sha256"],
                "request_workflow_sha256": manifest["request_workflow_sha256"],
                "workflow_sha256": manifest["workflow_sha256"],
                "checkpoint": manifest["checkpoint"],
                "checkpoint_sha256": manifest["checkpoint_sha256"],
                "v1_status": manifest["status"],
                "v1_failure_reason": manifest["failure_reason"],
                "v1_processed_sprite": processed_record,
                "v1_alpha_mask": alpha_record,
            }
        )
    if len(raw_hashes) != 8:
        raise FreezeError(f"GATE_4A_RAW_HASH_COUNT_NOT_EIGHT:{len(raw_hashes)}")
    if v1_processed_count != 1 or v1_alpha_count != 1:
        raise FreezeError(f"GATE_4A_V1_DELIVERY_COUNT_CHANGED:{v1_processed_count}:{v1_alpha_count}")

    # Freeze the complete 4A tree, not only selected evidence, so 4B can prove it
    # did not alter a config, prompt packet, score packet, log, image, or report.
    tree_files: dict[str, dict[str, Any]] = {}
    for path in sorted(item for item in GATE_4A_ROOT.rglob("*") if item.is_file()):
        record = file_record(path)
        tree_files[record["path"]] = {"size": record["size"], "sha256": record["sha256"]}
    external_inputs = [
        file_record(COMFY_ROOT / "postprocess" / "process_sprite.py"),
        file_record(COMFY_ROOT / "workflows" / "forge_object_sprite_v0.json"),
    ]
    human_review_path = RUN_ROOT / "human_review" / "human_visual_review.csv"
    report_root = GATE_4A_ROOT / "reports"
    return {
        "gate": "Forge Gate B 4B - Offline Alpha Extraction Spike",
        "source_gate": "GATE_B_4A",
        "source_run_id": RUN_ID,
        "source_gate_formal_status": "NEEDS WORK",
        "source_status_basis": [
            "4A technical Alpha delivery was 1/8, below its 6/8 threshold.",
            "The 4B authorization explicitly requires the 4A formal conclusion to remain NEEDS WORK.",
        ],
        "source_human_review_status": summary.get("human_visual_review_status", "unknown"),
        "source_raw_identity_count_frozen_by_4b_contract": {"passed": 6, "total": 8},
        "source_report_directory_present": report_root.is_dir(),
        "source_report_files": [relative(path) for path in report_root.rglob("*") if path.is_file()]
        if report_root.is_dir()
        else [],
        "source_human_review": file_record(human_review_path),
        "generation_summary": file_record(summary_path),
        "gate_4a_config": file_record(GATE_4A_ROOT / "forge_gate_b_4a_config.local.json"),
        "gate_4a_approved_run_manifest": file_record(GATE_4A_ROOT / "approved_run_manifest.json"),
        "gate_4a_frozen_handoff": file_record(GATE_4A_ROOT / "frozen" / "frozen_handoff.json"),
        "gate_4a_reservation": file_record(GATE_4A_ROOT / "GATE_B_4A_RUN.reservation.json"),
        "gate_4a_lifecycle": file_record(GATE_4A_ROOT / "runtime" / "lifecycle.json"),
        "external_inputs": external_inputs,
        "case_matrix": cases,
        "frozen_gate_4a_tree_file_count": len(tree_files),
        "frozen_gate_4a_tree": tree_files,
        "constraints": {
            "raw_images_may_be_modified": False,
            "gate_4a_files_may_be_overwritten": False,
            "comfyui_may_be_started": False,
            "anthropic_may_be_called": False,
            "network_may_be_used": False,
        },
    }


def main() -> int:
    try:
        if TARGET.exists():
            raise FreezeError(f"FREEZE_ALREADY_EXISTS:{TARGET}")
        manifest = build_manifest()
        temporary = ROOT / f".{TARGET.name}.{uuid.uuid4().hex}.tmp"
        temporary.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        descriptor = os.open(TARGET, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        try:
            with os.fdopen(descriptor, "wb") as stream:
                stream.write(temporary.read_bytes())
                stream.flush()
                os.fsync(stream.fileno())
        finally:
            temporary.unlink(missing_ok=True)
        print(
            json.dumps(
                {
                    "status": "GATE_B_4A_EVIDENCE_FROZEN",
                    "manifest": relative(TARGET),
                    "manifest_sha256": sha256_file(TARGET),
                    "raw_count": 8,
                    "v1_processed_count": 1,
                    "v1_alpha_count": 1,
                    "gate_4a_tree_file_count": manifest["frozen_gate_4a_tree_file_count"],
                }
            )
        )
        return 0
    except (FreezeError, OSError, ValueError, json.JSONDecodeError) as exc:
        print(json.dumps({"status": "NEEDS WORK", "failure_reason": str(exc)}), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
