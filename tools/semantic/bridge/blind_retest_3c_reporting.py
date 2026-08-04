#!/usr/bin/env python3
"""Two-stage, non-overwriting evidence publication for Blind Retest 3C."""

from __future__ import annotations

import argparse
import copy
import csv
import hashlib
import io
import json
import os
import re
import shutil
import sys
import uuid
from pathlib import Path
from typing import Any, Mapping, Sequence

from anthropic_semantic_compiler import ANTHROPIC_MESSAGES_URL, redact_sensitive_text
from atomic_output import atomic_deliver
from blind_retest_3c_evaluator import (
    CASE_ORDER,
    REVIEW_SUBMISSION_VERSION,
    aggregate,
    attach_manual_structure_review,
)
from secret_scan import scan_repository
from semantic_contract import CONTRACT_VERSION


PENDING_PACKAGE_VERSION = "forge-semantic-blind-retest-3c-pending-v1"
REVIEW_BATCH_VERSION = "forge-semantic-blind-retest-3c-review-batch-v1"
FROZEN_MODEL_ID = "claude-sonnet-5"
_RUN_ID_PATTERN = re.compile(
    r"blind-retest-3c-[0-9]{8}T[0-9]{12}Z-[0-9a-f]{8}"
)


class BlindRetest3CReportingError(RuntimeError):
    """Fail-closed report or evidence publication error."""


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _sha256(path: Path) -> str:
    return _sha256_bytes(path.read_bytes())


def _canonical_sha256(value: Any) -> str:
    return _sha256_bytes(
        json.dumps(
            value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
        ).encode("utf-8")
    )


def _read_json_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise BlindRetest3CReportingError(f"Cannot read JSON object: {path}") from exc
    if not isinstance(value, dict):
        raise BlindRetest3CReportingError(f"Expected JSON object: {path}")
    return value


def _json_object_from_bytes(raw: bytes, label: str) -> dict[str, Any]:
    try:
        value = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise BlindRetest3CReportingError(
            f"Cannot read JSON object: {label}"
        ) from exc
    if not isinstance(value, dict):
        raise BlindRetest3CReportingError(f"Expected JSON object: {label}")
    return value


def _read_json_array(path: Path) -> list[Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise BlindRetest3CReportingError(f"Cannot read JSON array: {path}") from exc
    if not isinstance(value, list):
        raise BlindRetest3CReportingError(f"Expected JSON array: {path}")
    return value


def _assert_safe_text_bytes(raw: bytes, label: str) -> None:
    try:
        text_value = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise BlindRetest3CReportingError(
            f"Refusing non-UTF-8 staged evidence: {label}"
        ) from exc
    if redact_sensitive_text(text_value) != text_value:
        raise BlindRetest3CReportingError(
            f"Sensitive content was rejected before staging: {label}"
        )


def _write_bytes(path: Path, raw: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        raise BlindRetest3CReportingError(f"Refusing to overwrite staged file: {path}")
    _assert_safe_text_bytes(raw, path.name)
    with path.open("xb") as handle:
        handle.write(raw)
        handle.flush()
        os.fsync(handle.fileno())


def _write_json(path: Path, value: Any) -> None:
    _write_bytes(
        path,
        (
            json.dumps(value, ensure_ascii=False, indent=2, sort_keys=False) + "\n"
        ).encode("utf-8"),
    )


def _write_text(path: Path, value: str) -> None:
    _write_bytes(path, value.encode("utf-8"))


def _require_safe_run_id(run_id: str) -> None:
    if not isinstance(run_id, str) or not _RUN_ID_PATTERN.fullmatch(run_id):
        raise BlindRetest3CReportingError("Blind Retest 3C run_id is invalid.")


def _discard_owned_stage(stage: Path, semantic_root: Path) -> None:
    """Remove only a freshly allocated 3C stage after a secret-scan rejection."""

    resolved = stage.resolve(strict=False)
    owned_root = (semantic_root.resolve() / ".tmp").resolve(strict=False)
    try:
        resolved.relative_to(owned_root)
    except ValueError as exc:
        raise BlindRetest3CReportingError(
            "Refusing to discard a stage outside tools/semantic/.tmp."
        ) from exc
    if resolved.exists():
        shutil.rmtree(resolved)


def _semantic_relative(semantic_root: Path, path: Path) -> str:
    resolved = path.resolve(strict=False)
    try:
        relative = resolved.relative_to(semantic_root.resolve())
    except ValueError as exc:
        raise BlindRetest3CReportingError(
            "Evidence path escapes tools/semantic."
        ) from exc
    return relative.as_posix()


def _raw_object(record: Mapping[str, Any]) -> dict[str, Any]:
    raw = record.get("raw_response_redacted")
    if not isinstance(raw, str) or not raw.strip():
        return {
            "status": "redacted_response_unavailable",
            "case_id": record.get("case_id"),
            "api_status": record.get("api_status"),
            "failure_reason": record.get("failure_reason"),
        }
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise BlindRetest3CReportingError(
            "A saved raw_response_redacted value is not JSON."
        ) from exc
    if not isinstance(value, dict):
        raise BlindRetest3CReportingError(
            "A saved raw_response_redacted value is not an object."
        )
    return value


def _request_manifest(record: Mapping[str, Any]) -> dict[str, Any]:
    fields = (
        "case_id",
        "local_request_id",
        "provider",
        "endpoint",
        "model_id",
        "response_model_id",
        "request_id",
        "contract_version",
        "api_status",
        "api_request_performed",
        "request_body_sha256",
        "tool_input_sha256",
        "retry_count",
        "started_at",
        "completed_at",
        "elapsed_ms",
        "input_tokens",
        "output_tokens",
        "cache_creation_input_tokens",
        "cache_read_input_tokens",
        "result_type",
        "response_attestation",
        "failure_reason",
    )
    return {field: copy.deepcopy(record.get(field)) for field in fields}


def _pending_paths(semantic_root: Path, run_id: str) -> tuple[Path, Path]:
    _require_safe_run_id(run_id)
    final = semantic_root / "reports" / "blind_retest_3c_pending" / run_id
    stage = (
        semantic_root
        / ".tmp"
        / "blind_retest_3c_pending"
        / f"{run_id}-{uuid.uuid4().hex}"
    )
    return stage, final


def _final_paths(semantic_root: Path, run_id: str) -> tuple[Path, Path]:
    _require_safe_run_id(run_id)
    final = semantic_root / "reports" / "blind_retest_3c" / run_id
    stage = (
        semantic_root
        / ".tmp"
        / "blind_retest_3c_final"
        / f"{run_id}-{uuid.uuid4().hex}"
    )
    return stage, final


def _validate_pending_stage(stage: Path) -> None:
    for name in (
        "pending_summary.json",
        "review_packet.json",
        "human_review_submission_template.json",
        "pending_evidence_hashes.json",
        "PENDING_COMPLETE.json",
    ):
        _read_json_object(stage / name)
    scores = _read_json_array(stage / "automatic_scores.json")
    if [
        str(item.get("case_id")) if isinstance(item, Mapping) else ""
        for item in scores
    ] != list(CASE_ORDER):
        raise BlindRetest3CReportingError(
            "Pending automatic scores are missing or reordered."
        )
    if len(list((stage / "raw_response_redacted").glob("*.json"))) != 4:
        raise BlindRetest3CReportingError("Pending archive requires four raw responses.")
    if len(list((stage / "request_manifests").glob("*.json"))) != 4:
        raise BlindRetest3CReportingError("Pending archive requires four request manifests.")


def _validate_final_stage(stage: Path) -> None:
    for name in (
        "blind_retest_3c_summary.json",
        "evidence_hashes.json",
        "COMPLETE.json",
        "review_submission.json",
    ):
        _read_json_object(stage / name)
    for name in (
        "BLIND_RETEST_3C_REPORT.md",
        "blind_retest_3c_results.csv",
        "human_structure_review.csv",
    ):
        if not (stage / name).is_file():
            raise BlindRetest3CReportingError(f"Final report file is missing: {name}")
    if len(list((stage / "raw_response_redacted").glob("*.json"))) != 4:
        raise BlindRetest3CReportingError("Final archive requires four raw responses.")


def _pending_template(scores: Sequence[Mapping[str, Any]], run_id: str) -> dict[str, Any]:
    cases: dict[str, Any] = {}
    for score in scores:
        case_id = str(score.get("case_id"))
        packet = score.get("manual_structure_review_packet")
        if not isinstance(packet, Mapping) or packet.get("status") != "PENDING":
            cases[case_id] = None
            continue
        concepts = packet.get("expected_concepts")
        if not isinstance(concepts, list):
            raise BlindRetest3CReportingError("A review packet has no frozen concepts.")
        cases[case_id] = {
            "review_submission_version": REVIEW_SUBMISSION_VERSION,
            "case_id": case_id,
            "tool_input_sha256": packet.get("tool_input_sha256"),
            "expected_concepts_sha256": packet.get("expected_concepts_sha256"),
            "concept_reviews": [
                {
                    "concept_id": concept.get("concept_id"),
                    "required_identity_part_quotes": [],
                    "must_preserve_quotes": [],
                    "same_structure_concept": None,
                    "structural_not_material_or_decoration": None,
                    "notes": "",
                }
                for concept in concepts
                if isinstance(concept, Mapping)
            ],
            "all_required_parts_are_structural": None,
            "non_structural_required_identity_part_quotes": [],
            "reviewer_reason": "",
        }
    return {
        "review_batch_version": REVIEW_BATCH_VERSION,
        "run_id": run_id,
        "pending_evidence_sha256": "REPLACE_FROM_PENDING_COMPLETE",
        "expected_sha256": "REPLACE_FROM_REVIEW_PACKET",
        "review_rubric_sha256": "REPLACE_FROM_REVIEW_PACKET",
        "reviewer": "REPLACE_WITH_HUMAN_REVIEWER",
        "cases": cases,
    }


def _stage_hash_map(
    *,
    semantic_root: Path,
    stage: Path,
    final_relative_root: str,
    extra_paths: Sequence[Path],
) -> dict[str, str]:
    files: dict[str, str] = {}
    for path in sorted(stage.rglob("*")):
        if path.is_file():
            relative = path.relative_to(stage).as_posix()
            if relative in {"pending_evidence_hashes.json", "PENDING_COMPLETE.json", "evidence_hashes.json", "COMPLETE.json"}:
                continue
            files[f"{final_relative_root}/{relative}"] = _sha256(path)
    for path in extra_paths:
        if not path.is_file() or path.is_symlink():
            raise BlindRetest3CReportingError(f"Required evidence is missing: {path}")
        files[_semantic_relative(semantic_root, path)] = _sha256(path)
    return dict(sorted(files.items()))


def write_pending_blind_retest_3c_review(
    *,
    semantic_root: Path,
    repository_root: Path,
    run_id: str,
    model_id: str,
    results: Sequence[Mapping[str, Any]],
    scores: Sequence[Mapping[str, Any]],
    output_run_directory: Path,
    reservation_path: Path,
    actual_call_count: int,
    configuration_hashes: Mapping[str, Any],
    configuration_snapshot: Mapping[str, Any],
    preflight: Mapping[str, Any],
) -> dict[str, Any]:
    """Publish an immutable paid-run packet, then stop for human review."""

    semantic_root = semantic_root.resolve()
    repository_root = repository_root.resolve()
    _require_safe_run_id(run_id)
    if [str(item.get("case_id")) for item in results] != list(CASE_ORDER):
        raise BlindRetest3CReportingError("3C results are missing or reordered.")
    if [str(item.get("case_id")) for item in scores] != list(CASE_ORDER):
        raise BlindRetest3CReportingError("3C scores are missing or reordered.")
    if (
        model_id != FROZEN_MODEL_ID
        or isinstance(actual_call_count, bool)
        or not isinstance(actual_call_count, int)
        or not 0 <= actual_call_count <= 4
    ):
        raise BlindRetest3CReportingError("3C model or call count differs from approval.")
    reservation = _read_json_object(reservation_path)
    if (
        reservation.get("run_id") != run_id
        or reservation.get("status") != "closed_pending_human_review"
        or reservation.get("attempts_reserved") != 4
        or reservation.get("actual_calls_observed") != actual_call_count
        or reservation.get("attempted_case_ids") != list(CASE_ORDER)
        or reservation.get("model_id") != FROZEN_MODEL_ID
    ):
        raise BlindRetest3CReportingError("3C reservation is not closed for review.")
    stage, final = _pending_paths(semantic_root, run_id)
    if final.exists() or stage.exists():
        raise BlindRetest3CReportingError("3C pending evidence already exists.")
    stage.mkdir(parents=True)

    for result in results:
        case_id = str(result["case_id"])
        _write_json(stage / "raw_response_redacted" / f"{case_id}.json", _raw_object(result))
        _write_json(stage / "request_manifests" / f"{case_id}.json", _request_manifest(result))
    _write_json(stage / "automatic_scores.json", list(scores))
    packets = {
        str(score["case_id"]): copy.deepcopy(score.get("manual_structure_review_packet"))
        for score in scores
    }
    review_packet = {
        "pending_package_version": PENDING_PACKAGE_VERSION,
        "run_id": run_id,
        "case_order": list(CASE_ORDER),
        "expected_sha256": configuration_hashes.get("blind_expected_sha256"),
        "review_rubric_sha256": configuration_hashes.get("blind_review_rubric_sha256"),
        "blind_definition_sha256": configuration_hashes.get("blind_definition_sha256"),
        "cases": packets,
    }
    _write_json(stage / "review_packet.json", review_packet)
    metrics = aggregate(scores)
    pending_summary = {
        "status": "PENDING_HUMAN_REVIEW",
        "run_id": run_id,
        "provider": "anthropic",
        "endpoint": ANTHROPIC_MESSAGES_URL,
        "model_id": model_id,
        "contract_version": CONTRACT_VERSION,
        "case_order": list(CASE_ORDER),
        "call_limit": 4,
        "call_count": actual_call_count,
        "automatic_metrics": metrics,
        "configuration_hashes": dict(configuration_hashes),
        "configuration_snapshot_sha256": configuration_snapshot.get("snapshot_sha256"),
        "approved_config_manifest_sha256": preflight.get("approved_config_manifest_sha256"),
        "source_3b_evidence_sha256": preflight.get("source_3b_evidence_sha256"),
        "next_step": "OFFLINE_HUMAN_STRUCTURE_REVIEW_ONLY",
    }
    _write_json(stage / "pending_summary.json", pending_summary)
    _write_json(
        stage / "configuration_snapshot.json", dict(configuration_snapshot)
    )
    template = _pending_template(scores, run_id)
    template["expected_sha256"] = review_packet["expected_sha256"]
    template["review_rubric_sha256"] = review_packet["review_rubric_sha256"]
    _write_json(stage / "human_review_submission_template.json", template)

    extra_paths = [reservation_path]
    for case_id in CASE_ORDER:
        extra_paths.append(output_run_directory / case_id / "result.json")
    snapshot_files = configuration_snapshot.get("files")
    if not isinstance(snapshot_files, Mapping):
        raise BlindRetest3CReportingError("3C configuration snapshot has no files map.")
    for relative in snapshot_files:
        if not isinstance(relative, str):
            raise BlindRetest3CReportingError("3C configuration path is invalid.")
        extra_paths.append(semantic_root / Path(relative))
    pending_relative = f"reports/blind_retest_3c_pending/{run_id}"
    evidence = {
        "algorithm": "SHA-256",
        "run_id": run_id,
        "status": "PENDING_HUMAN_REVIEW",
        "model_id": model_id,
        "case_order": list(CASE_ORDER),
        "blind_definition_sha256": configuration_hashes.get("blind_definition_sha256"),
        "files": _stage_hash_map(
            semantic_root=semantic_root,
            stage=stage,
            final_relative_root=pending_relative,
            extra_paths=extra_paths,
        ),
    }
    _write_json(stage / "pending_evidence_hashes.json", evidence)
    evidence_sha = _sha256(stage / "pending_evidence_hashes.json")
    _write_json(
        stage / "PENDING_COMPLETE.json",
        {
            "run_id": run_id,
            "status": "PENDING_HUMAN_REVIEW",
            "pending_evidence_sha256": evidence_sha,
            "gate_b_executed": False,
        },
    )
    if scan_repository(repository_root):
        _discard_owned_stage(stage, semantic_root)
        raise BlindRetest3CReportingError(
            "Secret scan blocked 3C pending evidence publication."
        )
    delivered = atomic_deliver(stage, final, _validate_pending_stage)
    return {
        "status": "PENDING_HUMAN_REVIEW",
        "run_id": run_id,
        "call_count": actual_call_count,
        "pending_path": str(delivered),
        "review_packet_path": str(delivered / "review_packet.json"),
        "review_template_path": str(
            delivered / "human_review_submission_template.json"
        ),
        "pending_evidence_sha256": evidence_sha,
    }


def _verify_evidence_map(
    semantic_root: Path, manifest: Mapping[str, Any]
) -> dict[str, bytes]:
    files = manifest.get("files")
    if not isinstance(files, Mapping) or not files:
        raise BlindRetest3CReportingError("Evidence manifest has no files.")
    root = semantic_root.resolve()
    verified: dict[str, bytes] = {}
    for relative, expected in files.items():
        if not isinstance(relative, str) or not isinstance(expected, str):
            raise BlindRetest3CReportingError("Evidence manifest entry is invalid.")
        path = (root / Path(relative)).resolve(strict=False)
        try:
            path.relative_to(root)
        except ValueError as exc:
            raise BlindRetest3CReportingError("Evidence path escapes semantic root.") from exc
        if path.is_symlink() or not path.is_file():
            raise BlindRetest3CReportingError(f"Evidence hash mismatch: {relative}")
        raw = path.read_bytes()
        if _sha256_bytes(raw) != expected:
            raise BlindRetest3CReportingError(f"Evidence hash mismatch: {relative}")
        verified[relative] = raw
    return verified


def _verified_bytes(verified: Mapping[str, bytes], relative: str) -> bytes:
    raw = verified.get(relative)
    if not isinstance(raw, bytes):
        raise BlindRetest3CReportingError(
            f"Pending evidence does not bind required file: {relative}"
        )
    return raw


def _attach_reviews(
    scores: Sequence[Mapping[str, Any]], submission: Mapping[str, Any]
) -> list[dict[str, Any]]:
    cases = submission.get("cases")
    if not isinstance(cases, Mapping) or tuple(cases) != CASE_ORDER:
        raise BlindRetest3CReportingError("Human review cases are missing or reordered.")
    attached: list[dict[str, Any]] = []
    for score in scores:
        case_id = str(score.get("case_id"))
        packet = score.get("manual_structure_review_packet")
        case_submission = cases.get(case_id)
        if isinstance(packet, Mapping) and packet.get("status") == "PENDING":
            if not isinstance(case_submission, Mapping):
                raise BlindRetest3CReportingError(
                    f"Human review submission is missing for {case_id}."
                )
            try:
                attached.append(attach_manual_structure_review(score, case_submission))
            except Exception as exc:
                raise BlindRetest3CReportingError(
                    f"Human structure review was rejected for {case_id}: {exc}"
                ) from exc
        else:
            if case_submission is not None:
                raise BlindRetest3CReportingError(
                    f"Non-reviewable case {case_id} must use null review submission."
                )
            copied = copy.deepcopy(dict(score))
            copied["manual_structure_review_status"] = "COMPLETE"
            copied["manual_structure_review_result"] = {
                "status": "COMPLETE",
                "case_id": case_id,
                "structure_quality": 0,
                "structure_correct": False,
                "confirmed_concept_count": 0,
                "confirmed_concept_ids": [],
                "unconfirmed_concept_ids": [
                    concept.get("concept_id")
                    for concept in (packet or {}).get("expected_concepts", [])
                    if isinstance(concept, Mapping)
                ],
                "all_required_parts_are_structural": False,
                "reviewer_reason": "Validated structural arrays were unavailable.",
            }
            attached.append(copied)
    return attached


def _automatic_csv(scores: Sequence[Mapping[str, Any]]) -> str:
    fields = (
        "case_id",
        "api_success",
        "exactly_one_legal_tool_use",
        "schema_valid",
        "cross_field_valid",
        "base_identity_correct",
        "behavior_correct",
        "observed_effect_type",
        "fixed_weapon_substitution",
        "fixed_weapon_substitution_attested",
        "automatic_retry_count",
        "retry_attested",
        "extra_root_wrapper",
        "repair_applied",
        "unwrap_applied",
        "coercion_applied",
        "defaults_applied",
        "manual_structure_quality",
        "manual_confirmed_concept_count",
        "manual_structure_correct",
        "reviewer_reason",
    )
    output = io.StringIO(newline="")
    writer = csv.DictWriter(output, fieldnames=fields, lineterminator="\n")
    writer.writeheader()
    for score in scores:
        manual = score.get("manual_structure_review_result")
        manual = manual if isinstance(manual, Mapping) else {}
        writer.writerow(
            {
                **{field: score.get(field) for field in fields},
                "manual_structure_quality": manual.get("structure_quality"),
                "manual_confirmed_concept_count": manual.get(
                    "confirmed_concept_count"
                ),
                "manual_structure_correct": manual.get("structure_correct"),
            }
        )
    return output.getvalue()


def _human_csv(
    scores: Sequence[Mapping[str, Any]], submission: Mapping[str, Any]
) -> str:
    fields = (
        "case_id",
        "concept_id",
        "expected_label_zh",
        "expected_label_en",
        "actual_required_identity_part_quotes",
        "actual_must_preserve_quotes",
        "same_structure_concept",
        "structural_not_material_or_decoration",
        "confirmed",
        "notes",
        "case_structure_quality",
        "case_structure_correct",
    )
    output = io.StringIO(newline="")
    writer = csv.DictWriter(output, fieldnames=fields, lineterminator="\n")
    writer.writeheader()
    submitted_cases = submission.get("cases", {})
    for score in scores:
        case_id = str(score.get("case_id"))
        packet = score.get("manual_structure_review_packet")
        concepts = packet.get("expected_concepts", []) if isinstance(packet, Mapping) else []
        case_submission = submitted_cases.get(case_id)
        review_by_id = {}
        if isinstance(case_submission, Mapping):
            review_by_id = {
                item.get("concept_id"): item
                for item in case_submission.get("concept_reviews", [])
                if isinstance(item, Mapping)
            }
        manual = score.get("manual_structure_review_result")
        manual = manual if isinstance(manual, Mapping) else {}
        confirmed_ids = set(manual.get("confirmed_concept_ids", []))
        for concept in concepts:
            if not isinstance(concept, Mapping):
                continue
            concept_id = concept.get("concept_id")
            review = review_by_id.get(concept_id, {})
            writer.writerow(
                {
                    "case_id": case_id,
                    "concept_id": concept_id,
                    "expected_label_zh": concept.get("label_zh"),
                    "expected_label_en": concept.get("label_en"),
                    "actual_required_identity_part_quotes": " | ".join(
                        review.get("required_identity_part_quotes", [])
                    ),
                    "actual_must_preserve_quotes": " | ".join(
                        review.get("must_preserve_quotes", [])
                    ),
                    "same_structure_concept": review.get("same_structure_concept", False),
                    "structural_not_material_or_decoration": review.get(
                        "structural_not_material_or_decoration", False
                    ),
                    "confirmed": concept_id in confirmed_ids,
                    "notes": review.get("notes", "NOT_REVIEWABLE"),
                    "case_structure_quality": manual.get("structure_quality"),
                    "case_structure_correct": manual.get("structure_correct"),
                }
            )
    return output.getvalue()


def _report_markdown(summary: Mapping[str, Any], scores: Sequence[Mapping[str, Any]]) -> str:
    metrics = summary["metrics"]
    thresholds = summary["thresholds"]
    rows = []
    for score in scores:
        manual = score.get("manual_structure_review_result")
        manual = manual if isinstance(manual, Mapping) else {}
        rows.append(
            "| {case} | {api} | {tool} | {schema} | {identity} | {behavior} | {parts} | {fixed} |".format(
                case=score.get("case_id"),
                api="PASS" if score.get("api_success") else "FAIL",
                tool="PASS" if score.get("exactly_one_legal_tool_use") else "FAIL",
                schema="PASS" if score.get("schema_valid") and score.get("cross_field_valid") else "FAIL",
                identity="PASS" if score.get("base_identity_correct") else "FAIL",
                behavior="PASS" if score.get("behavior_correct") else "FAIL",
                parts=manual.get("confirmed_concept_count", 0),
                fixed=(
                    "N/A"
                    if score.get("fixed_weapon_substitution_attested") is not True
                    else "FAIL"
                    if score.get("fixed_weapon_substitution")
                    else "PASS"
                ),
            )
        )
    gate_rows = []
    for name, target in thresholds.items():
        actual = metrics.get(name)
        gate_rows.append(
            f"| `{name}` | {actual} | {target} | {'PASS' if actual == target else 'FAIL'} |"
        )
    return "\n".join(
        [
            "# Forge Semantic Contract v1.1 Blind Retest 3C",
            "",
            f"**结论：{summary['status']}**",
            "",
            "本次为四案例全新盲测；冻结的运行合同使用 Anthropic 官方 Messages API、精确模型 `claude-sonnet-5`、原 v1.1 Schema 与系统 Prompt，并禁止修复、拆包、强制转换、默认处理和自动重试。",
            "",
            "## 调用与冻结边界",
            "",
            f"- Run ID：`{summary['run_id']}`",
            f"- 已观察真实调用：{summary['call_count']}/4；预留案例尝试：{summary['attempts_reserved']}/4；观察到的自动重试：{metrics.get('automatic_retry_count')}。",
            f"- 观察到的本地变换：repair={metrics.get('repair_count')}，unwrap={metrics.get('unwrap_count')}，coercion={metrics.get('coercion_count')}，default={metrics.get('default_count')}。",
            f"- Blind definition SHA-256：`{summary['blind_definition_sha256']}`",
            f"- 人工审阅 submission SHA-256：`{summary['review_submission_sha256']}`",
            "- effect_type 仅记录，不参与 3C 通过判定。",
            "",
            "## 通过门槛",
            "",
            "| 门槛 | 实际 | 要求 | 结果 |",
            "|---|---:|---:|---|",
            *gate_rows,
            "",
            "## 逐案例结果",
            "",
            "| Case | API | Tool | Schema/Cross | 基础身份 | 行为 | 人工确认结构数 | 固定替换 |",
            "|---|---|---|---|---|---|---:|---|",
            *rows,
            "",
            "## 停止条件",
            "",
            "Gate B、ComfyUI 与 V2 均未执行；本次完成后停止，等待用户批准。",
            "",
        ]
    )


def _publish_independent_copy(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        if (
            destination.is_symlink()
            or not destination.is_file()
            or _sha256(destination) != _sha256(source)
        ):
            raise BlindRetest3CReportingError(
                f"Refusing to overwrite mismatched convenience output: {destination}"
            )
        return
    temp = destination.parent / f".{destination.name}.{uuid.uuid4().hex}.tmp"
    try:
        with temp.open("xb") as handle:
            handle.write(source.read_bytes())
            handle.flush()
            os.fsync(handle.fileno())
        os.link(temp, destination)
    finally:
        if temp.exists():
            temp.unlink()


def _convenience_sources(archive: Path) -> dict[str, Path]:
    return {
        "BLIND_RETEST_3C_REPORT.md": archive / "BLIND_RETEST_3C_REPORT.md",
        "blind_retest_3c_results.csv": archive / "blind_retest_3c_results.csv",
        "blind_retest_3c_summary.json": archive / "blind_retest_3c_summary.json",
        "human_structure_review.csv": archive / "human_structure_review.csv",
    }


def _publish_convenience_outputs(semantic_root: Path, archive: Path) -> None:
    for name, source in _convenience_sources(archive).items():
        destination = semantic_root / "reports" / name
        _publish_independent_copy(source, destination)
        if _sha256(destination) != _sha256(source):
            raise BlindRetest3CReportingError("Convenience output hash mismatch.")


def _validate_existing_final_archive(
    *,
    semantic_root: Path,
    archive: Path,
    run_id: str,
    review_sha256: str,
) -> dict[str, Any]:
    _validate_final_stage(archive)
    complete = _read_json_object(archive / "COMPLETE.json")
    evidence_path = archive / "evidence_hashes.json"
    evidence = _read_json_object(evidence_path)
    summary = _read_json_object(archive / "blind_retest_3c_summary.json")
    if (
        complete.get("run_id") != run_id
        or complete.get("status") != "complete"
        or complete.get("evidence_sha256") != _sha256(evidence_path)
        or evidence.get("run_id") != run_id
        or evidence.get("review_submission_sha256") != review_sha256
        or summary.get("run_id") != run_id
        or summary.get("review_submission_sha256") != review_sha256
        or _sha256(archive / "review_submission.json") != review_sha256
    ):
        raise BlindRetest3CReportingError(
            "Existing final 3C archive does not match this review submission."
        )
    _verify_evidence_map(semantic_root, evidence)
    expected = evidence.get("convenience_files_expected_sha256")
    if not isinstance(expected, Mapping):
        raise BlindRetest3CReportingError(
            "Existing final archive lacks convenience-output hashes."
        )
    for name, source in _convenience_sources(archive).items():
        relative = f"reports/{name}"
        if expected.get(relative) != _sha256(source):
            raise BlindRetest3CReportingError(
                "Existing final archive convenience hashes are invalid."
            )
    return summary


def finalize_blind_retest_3c_review(
    *, semantic_root: Path, repository_root: Path, run_id: str, review_path: Path
) -> dict[str, Any]:
    """Validate independent human decisions and publish final 3C artifacts once."""

    semantic_root = semantic_root.resolve()
    repository_root = repository_root.resolve()
    _require_safe_run_id(run_id)
    pending = semantic_root / "reports" / "blind_retest_3c_pending" / run_id
    output_run = semantic_root / "output" / "blind_retest_3c" / run_id
    reservation_path = semantic_root / "reports" / "blind_retest_3c_real_call_reservation.json"
    pending_complete_path = pending / "PENDING_COMPLETE.json"
    pending_evidence_path = pending / "pending_evidence_hashes.json"
    try:
        pending_complete_bytes = pending_complete_path.read_bytes()
        pending_evidence_bytes = pending_evidence_path.read_bytes()
    except OSError as exc:
        raise BlindRetest3CReportingError(
            "Pending 3C evidence chain is unavailable."
        ) from exc
    pending_complete = _json_object_from_bytes(
        pending_complete_bytes, "PENDING_COMPLETE.json"
    )
    pending_evidence = _json_object_from_bytes(
        pending_evidence_bytes, "pending_evidence_hashes.json"
    )
    if (
        pending_complete.get("run_id") != run_id
        or pending_complete.get("status") != "PENDING_HUMAN_REVIEW"
        or pending_complete.get("pending_evidence_sha256")
        != _sha256_bytes(pending_evidence_bytes)
        or pending_evidence.get("run_id") != run_id
    ):
        raise BlindRetest3CReportingError("Pending 3C evidence chain is invalid.")
    verified = _verify_evidence_map(semantic_root, pending_evidence)
    reservation_relative = _semantic_relative(semantic_root, reservation_path)
    reservation = _json_object_from_bytes(
        _verified_bytes(verified, reservation_relative), reservation_relative
    )
    actual_calls = reservation.get("actual_calls_observed")
    if (
        reservation.get("run_id") != run_id
        or reservation.get("status") != "closed_pending_human_review"
        or reservation.get("attempts_reserved") != 4
        or isinstance(actual_calls, bool)
        or not isinstance(actual_calls, int)
        or not 0 <= actual_calls <= 4
    ):
        raise BlindRetest3CReportingError("3C reservation is not finalizable.")
    pending_relative = f"reports/blind_retest_3c_pending/{run_id}"
    try:
        scores_value = json.loads(
            _verified_bytes(
                verified, f"{pending_relative}/automatic_scores.json"
            ).decode("utf-8")
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise BlindRetest3CReportingError(
            "Pending automatic scores are invalid."
        ) from exc
    if not isinstance(scores_value, list) or [
        item.get("case_id") if isinstance(item, Mapping) else None
        for item in scores_value
    ] != list(CASE_ORDER):
        raise BlindRetest3CReportingError("Pending automatic scores are invalid.")
    review_packet_relative = f"{pending_relative}/review_packet.json"
    review_packet_bytes = _verified_bytes(verified, review_packet_relative)
    review_packet = _json_object_from_bytes(
        review_packet_bytes, review_packet_relative
    )
    if review_path.is_symlink():
        raise BlindRetest3CReportingError(
            "Human review submission cannot be a symbolic link."
        )
    try:
        resolved_review_path = review_path.resolve(strict=True)
        review_bytes = resolved_review_path.read_bytes()
    except OSError as exc:
        raise BlindRetest3CReportingError(
            "Human review submission is unavailable."
        ) from exc
    _assert_safe_text_bytes(review_bytes, "human review submission")
    submission = _json_object_from_bytes(review_bytes, "human review submission")
    required_submission_keys = {
        "review_batch_version",
        "run_id",
        "pending_evidence_sha256",
        "expected_sha256",
        "review_rubric_sha256",
        "reviewer",
        "cases",
    }
    if (
        set(submission) != required_submission_keys
        or submission.get("review_batch_version") != REVIEW_BATCH_VERSION
        or submission.get("run_id") != run_id
        or submission.get("pending_evidence_sha256")
        != pending_complete.get("pending_evidence_sha256")
        or submission.get("expected_sha256") != review_packet.get("expected_sha256")
        or submission.get("review_rubric_sha256")
        != review_packet.get("review_rubric_sha256")
        or not isinstance(submission.get("reviewer"), str)
        or not submission["reviewer"].strip()
    ):
        raise BlindRetest3CReportingError("Human review batch is not bound to this run.")
    attached = _attach_reviews(scores_value, submission)
    results = [
        _json_object_from_bytes(
            _verified_bytes(
                verified,
                f"output/blind_retest_3c/{run_id}/{case_id}/result.json",
            ),
            f"output/blind_retest_3c/{run_id}/{case_id}/result.json",
        )
        for case_id in CASE_ORDER
    ]
    unique_response_count = len(
        {
            record.get("request_id")
            for record in results
            if isinstance(record.get("request_id"), str)
            and record.get("request_id")
        }
    )
    metrics_raw = aggregate(attached)
    thresholds = dict(metrics_raw["automatic_thresholds"])
    thresholds.update(
        {
            "manual_structure_review_complete_count": 4,
            "manual_structure_quality_2_count": 4,
            "manual_structure_correct_count": 4,
            "actual_call_count": 4,
            "reserved_attempt_count": 4,
            "unique_provider_response_id_count": 4,
            "key_leak_count": 0,
        }
    )
    metrics = {
        key: metrics_raw.get(key)
        for key in thresholds
        if key != "key_leak_count"
    }
    metrics["actual_call_count"] = actual_calls
    metrics["reserved_attempt_count"] = reservation.get("attempts_reserved")
    metrics["unique_provider_response_id_count"] = unique_response_count
    metrics["key_leak_count"] = 0
    status = "PASS" if all(metrics.get(key) == value for key, value in thresholds.items()) else "NEEDS WORK"
    usage_fields = (
        "input_tokens",
        "output_tokens",
        "cache_creation_input_tokens",
        "cache_read_input_tokens",
    )
    usage = {
        field: sum(
            int(record.get(field, 0))
            for record in results
            if isinstance(record.get(field, 0), int)
        )
        for field in usage_fields
    }
    pending_summary_relative = f"{pending_relative}/pending_summary.json"
    pending_summary = _json_object_from_bytes(
        _verified_bytes(verified, pending_summary_relative),
        pending_summary_relative,
    )
    configuration_hashes = pending_summary.get("configuration_hashes")
    if not isinstance(configuration_hashes, Mapping):
        raise BlindRetest3CReportingError("Pending configuration hashes are missing.")
    summary = {
        "status": status,
        "run_id": run_id,
        "provider": "anthropic",
        "endpoint": ANTHROPIC_MESSAGES_URL,
        "model_id": FROZEN_MODEL_ID,
        "contract_version": CONTRACT_VERSION,
        "case_order": list(CASE_ORDER),
        "call_limit": 4,
        "call_count": actual_calls,
        "attempts_reserved": reservation.get("attempts_reserved"),
        "unique_provider_response_id_count": unique_response_count,
        "blind_definition_sha256": configuration_hashes.get("blind_definition_sha256"),
        "blind_cases_sha256": configuration_hashes.get("blind_cases_sha256"),
        "blind_expected_sha256": configuration_hashes.get("blind_expected_sha256"),
        "blind_review_rubric_sha256": configuration_hashes.get("blind_review_rubric_sha256"),
        "pending_evidence_sha256": pending_complete.get("pending_evidence_sha256"),
        "review_submission_sha256": _sha256_bytes(review_bytes),
        "reviewer": submission["reviewer"],
        "metrics": metrics,
        "thresholds": thresholds,
        "automatic_metrics": metrics_raw,
        "effect_type_is_scored": False,
        "secret_scan_passed": True,
        "usage": usage,
        "gate_b_executed": False,
        "comfyui_started": False,
        "v2_started": False,
        "gameplay_rooms_anchors_or_art_modified": False,
        "next_step": "STOP_AND_WAIT_FOR_USER_APPROVAL",
    }
    automatic_csv = _automatic_csv(attached)
    human_csv = _human_csv(attached, submission)
    report = _report_markdown(summary, attached)

    stage, final = _final_paths(semantic_root, run_id)
    if stage.exists():
        raise BlindRetest3CReportingError("A staged final 3C archive already exists.")
    if final.exists():
        existing_summary = _validate_existing_final_archive(
            semantic_root=semantic_root,
            archive=final,
            run_id=run_id,
            review_sha256=_sha256_bytes(review_bytes),
        )
        _publish_convenience_outputs(semantic_root, final)
        return existing_summary
    for destination in (
        semantic_root / "reports" / "BLIND_RETEST_3C_REPORT.md",
        semantic_root / "reports" / "blind_retest_3c_results.csv",
        semantic_root / "reports" / "blind_retest_3c_summary.json",
        semantic_root / "reports" / "human_structure_review.csv",
    ):
        if destination.exists():
            raise BlindRetest3CReportingError("A final 3C convenience output already exists.")
    stage.mkdir(parents=True)
    _write_text(stage / "BLIND_RETEST_3C_REPORT.md", report)
    _write_text(stage / "blind_retest_3c_results.csv", automatic_csv)
    _write_json(stage / "blind_retest_3c_summary.json", summary)
    _write_text(stage / "human_structure_review.csv", human_csv)
    _write_json(stage / "automatic_scores.json", attached)
    _write_bytes(stage / "review_packet.json", review_packet_bytes)
    _write_bytes(stage / "review_submission.json", review_bytes)
    for case_id in CASE_ORDER:
        raw_relative = f"{pending_relative}/raw_response_redacted/{case_id}.json"
        request_relative = f"{pending_relative}/request_manifests/{case_id}.json"
        _write_bytes(
            stage / "raw_response_redacted" / f"{case_id}.json",
            _verified_bytes(verified, raw_relative),
        )
        _write_bytes(
            stage / "request_manifests" / f"{case_id}.json",
            _verified_bytes(verified, request_relative),
        )
        result = results[list(CASE_ORDER).index(case_id)]
        if result.get("result_type") == "compiled" and isinstance(result.get("result"), Mapping):
            _write_json(stage / "compiled_results" / f"{case_id}.json", result["result"])

    final_relative = f"reports/blind_retest_3c/{run_id}"
    extra_paths = [reservation_path, pending / "PENDING_COMPLETE.json", pending_evidence_path]
    for case_id in CASE_ORDER:
        extra_paths.append(output_run / case_id / "result.json")
    evidence = {
        "algorithm": "SHA-256",
        "run_id": run_id,
        "status": status,
        "model_id": FROZEN_MODEL_ID,
        "case_order": list(CASE_ORDER),
        "pending_evidence_sha256": pending_complete.get("pending_evidence_sha256"),
        "review_submission_sha256": summary["review_submission_sha256"],
        "convenience_files_expected_sha256": {
            "reports/BLIND_RETEST_3C_REPORT.md": _sha256(stage / "BLIND_RETEST_3C_REPORT.md"),
            "reports/blind_retest_3c_results.csv": _sha256(stage / "blind_retest_3c_results.csv"),
            "reports/blind_retest_3c_summary.json": _sha256(stage / "blind_retest_3c_summary.json"),
            "reports/human_structure_review.csv": _sha256(stage / "human_structure_review.csv"),
        },
        "files": _stage_hash_map(
            semantic_root=semantic_root,
            stage=stage,
            final_relative_root=final_relative,
            extra_paths=extra_paths,
        ),
    }
    _write_json(stage / "evidence_hashes.json", evidence)
    evidence_sha = _sha256(stage / "evidence_hashes.json")
    _write_json(
        stage / "COMPLETE.json",
        {
            "run_id": run_id,
            "status": "complete",
            "result": status,
            "evidence_sha256": evidence_sha,
            "gate_b_executed": False,
        },
    )
    try:
        if (
            pending_complete_path.read_bytes() != pending_complete_bytes
            or pending_evidence_path.read_bytes() != pending_evidence_bytes
        ):
            raise BlindRetest3CReportingError(
                "Pending 3C evidence changed during finalization."
            )
    except OSError as exc:
        raise BlindRetest3CReportingError(
            "Pending 3C evidence became unavailable during finalization."
        ) from exc
    _verify_evidence_map(semantic_root, pending_evidence)
    if scan_repository(repository_root):
        _discard_owned_stage(stage, semantic_root)
        raise BlindRetest3CReportingError("Secret scan blocked final 3C publication.")
    delivered = atomic_deliver(stage, final, _validate_final_stage)
    _publish_convenience_outputs(semantic_root, delivered)
    return summary


def _parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--review-json", type=Path, required=True)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv)
    os.environ.pop("ANTHROPIC_API_KEY", None)
    os.environ.pop("FORGE_SEMANTIC_MODEL", None)
    semantic_root = Path(__file__).resolve().parents[1]
    repository_root = args.repo_root.resolve()
    try:
        if semantic_root.parent.parent != repository_root:
            raise BlindRetest3CReportingError(
                "--repo-root does not own this tools/semantic implementation."
            )
        summary = finalize_blind_retest_3c_review(
            semantic_root=semantic_root,
            repository_root=repository_root,
            run_id=args.run_id,
            review_path=args.review_json,
        )
        print(json.dumps(summary, ensure_ascii=False))
        return 0
    except BlindRetest3CReportingError as exc:
        print(str(exc), file=sys.stderr)
        return 3
    except Exception:
        print(
            "Blind Retest 3C finalization stopped after an unexpected local failure.",
            file=sys.stderr,
        )
        return 4
    finally:
        os.environ.pop("ANTHROPIC_API_KEY", None)
        os.environ.pop("FORGE_SEMANTIC_MODEL", None)


if __name__ == "__main__":
    raise SystemExit(main())


__all__ = [
    "BlindRetest3CReportingError",
    "PENDING_PACKAGE_VERSION",
    "REVIEW_BATCH_VERSION",
    "finalize_blind_retest_3c_review",
    "write_pending_blind_retest_3c_review",
]
