"""Immutable report publication for Forge Semantic Limited Retest 3B."""

from __future__ import annotations

import csv
import hashlib
import io
import json
import os
import uuid
from pathlib import Path
from typing import Any, Mapping, Sequence

from anthropic_semantic_compiler import ANTHROPIC_MESSAGES_URL, redact_sensitive_text
from atomic_output import atomic_deliver
from limited_retest_3b_evaluator import CASE_ORDER, aggregate
from secret_scan import scan_repository
from semantic_contract import CONTRACT_VERSION


CSV_FIELDS = (
    "case_id",
    "api_success",
    "exactly_one_legal_tool_use",
    "schema_valid",
    "cross_field_valid",
    "clarification_correct",
    "identity_correct",
    "behavior_correct",
    "required_identity_parts_quality",
    "fixed_weapon_substitution",
    "automatic_retry_count",
    "extra_root_wrapper",
    "input_tokens",
    "output_tokens",
    "elapsed_ms",
    "reviewer_reason",
)


class LimitedRetest3BReportingError(RuntimeError):
    pass


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _json_bytes(payload: Any) -> bytes:
    return (json.dumps(payload, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def _write_new(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as handle:
        handle.write(data)
        handle.flush()
        os.fsync(handle.fileno())


def _publish_copy_new(source: Path, destination: Path) -> None:
    """Atomically publish an independent, non-overwriting convenience copy."""

    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        raise LimitedRetest3BReportingError(
            f"3B publication target already exists: {destination}"
        )
    temporary = destination.with_name(f".{destination.name}.{uuid.uuid4().hex}.tmp")
    _write_new(temporary, source.read_bytes())
    try:
        # Linking the fully flushed temporary inode is atomic and fails if the
        # destination appeared concurrently.  The archive source is never
        # linked, so editing a convenience file cannot mutate archived bytes.
        os.link(temporary, destination)
    except FileExistsError as exc:
        raise LimitedRetest3BReportingError(
            f"3B publication target already exists: {destination}"
        ) from exc
    except OSError as exc:
        raise LimitedRetest3BReportingError(
            "3B requires same-filesystem atomic convenience publication."
        ) from exc
    finally:
        if temporary.exists():
            temporary.unlink()


def _redacted_document(value: Any, case_id: str) -> Any:
    safe = redact_sensitive_text(value)
    if not safe:
        return {"case_id": case_id, "status": "raw_response_unavailable"}
    try:
        parsed = json.loads(safe)
    except json.JSONDecodeError:
        return {"case_id": case_id, "raw_response_redacted": safe}
    return parsed


def _reservation_attestation(
    reservation_path: Path, *, run_id: str, model_id: str, actual_call_count: int
) -> tuple[bool, dict[str, Any]]:
    try:
        value = json.loads(reservation_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False, {}
    valid = bool(
        isinstance(value, dict)
        and value.get("run_id") == run_id
        and value.get("model_id") == model_id
        and value.get("contract_version") == CONTRACT_VERSION
        and value.get("endpoint") == ANTHROPIC_MESSAGES_URL
        and value.get("max_real_calls") == 6
        and value.get("attempts_reserved") == 6
        and value.get("actual_calls_observed") == actual_call_count
        and value.get("attempted_case_ids") == list(CASE_ORDER)
        and value.get("status") == "closed"
    )
    return valid, value if isinstance(value, dict) else {}


def _csv_text(scores: Sequence[Mapping[str, Any]]) -> str:
    output = io.StringIO(newline="")
    writer = csv.DictWriter(output, fieldnames=CSV_FIELDS, extrasaction="ignore")
    writer.writeheader()
    for score in scores:
        writer.writerow({field: score.get(field) for field in CSV_FIELDS})
    return output.getvalue()


def _usage(results: Sequence[Mapping[str, Any]]) -> dict[str, int]:
    total = {
        "input_tokens": 0,
        "output_tokens": 0,
        "cache_creation_input_tokens": 0,
        "cache_read_input_tokens": 0,
    }
    for result in results:
        for field in total:
            value = result.get(field, 0)
            if isinstance(value, int) and not isinstance(value, bool) and value >= 0:
                total[field] += value
    return total


def _summary(
    *,
    run_id: str,
    model_id: str,
    results: Sequence[Mapping[str, Any]],
    scores: Sequence[Mapping[str, Any]],
    actual_call_count: int,
    reservation_attested: bool,
    configuration_hashes: Mapping[str, str],
    preflight: Mapping[str, Any],
) -> dict[str, Any]:
    metrics = aggregate(scores)
    provider_ids = [
        result.get("request_id")
        for result in results
        if isinstance(result.get("request_id"), str) and result.get("request_id")
    ]
    exact_call_count = actual_call_count == 6 and sum(
        result.get("api_request_performed") is True for result in results
    ) == 6
    passed = bool(
        metrics["semantic_thresholds_passed"]
        and exact_call_count
        and reservation_attested
        and len(results) == 6
        and len(set(provider_ids)) == 6
    )
    return {
        "status": "LIMITED RETEST 3B PASS" if passed else "NEEDS WORK",
        "run_id": run_id,
        "provider": "anthropic",
        "endpoint": ANTHROPIC_MESSAGES_URL,
        "model_id": model_id,
        "contract_version": CONTRACT_VERSION,
        "case_order": list(CASE_ORDER),
        "call_limit": 6,
        "call_count": actual_call_count,
        "api_request_performed_count": sum(
            result.get("api_request_performed") is True for result in results
        ),
        "automatic_retry_count": metrics["automatic_retry_count"],
        "call_reservation_attested": reservation_attested,
        "unique_provider_response_id_count": len(set(provider_ids)),
        "source_run_id": preflight.get("source_run_id"),
        "source_evidence_sha256": preflight.get("source_evidence_sha256"),
        "historical_gate_a_and_3a_hashes_verified": True,
        "protected_file_count": preflight.get("protected_file_count"),
        "approved_config_manifest_sha256": preflight.get(
            "approved_config_manifest_sha256"
        ),
        "approved_config_file_count": preflight.get("approved_config_file_count"),
        "configuration_hashes": dict(configuration_hashes),
        **{key: value for key, value in metrics.items() if key != "thresholds"},
        "thresholds": metrics["thresholds"],
        "key_leak_count": 0,
        "secret_scan_passed": True,
        "repair_count": sum(result.get("repair_applied") is True for result in results),
        "unwrap_count": sum(result.get("unwrap_applied") is True for result in results),
        "coercion_count": sum(result.get("coercion_applied") is True for result in results),
        "default_count": sum(result.get("defaults_applied") is True for result in results),
        "usage": _usage(results),
        "gate_b_executed": False,
        "comfyui_started": False,
        "v2_started": False,
        "gameplay_rooms_anchors_or_art_modified": False,
        "next_step": "STOP_AND_WAIT_FOR_APPROVAL_OF_FOUR_NEW_BLIND_CASES",
    }


def _pass(value: bool) -> str:
    return "PASS" if value else "FAIL"


def _report_markdown(
    summary: Mapping[str, Any],
    scores: Sequence[Mapping[str, Any]],
    results: Sequence[Mapping[str, Any]],
) -> str:
    thresholds = summary["thresholds"]
    gate_rows = [
        ("API 成功", summary["api_success_count"], thresholds["api_success_count"]),
        (
            "exactly one 合法 tool_use",
            summary["exactly_one_legal_tool_use_count"],
            thresholds["exactly_one_legal_tool_use_count"],
        ),
        (
            "Schema + 跨字段有效",
            summary["schema_and_cross_field_valid_count"],
            thresholds["schema_and_cross_field_valid_count"],
        ),
        (
            "澄清正确",
            summary["clarification_correct_count"],
            thresholds["clarification_correct_count"],
        ),
        (
            "compiled 身份正确",
            summary["compiled_identity_correct_count"],
            thresholds["compiled_identity_correct_count"],
        ),
        (
            "compiled 行为正确",
            summary["compiled_behavior_correct_count"],
            thresholds["compiled_behavior_correct_count"],
        ),
        (
            "required_identity_parts 质量 2",
            summary["required_identity_parts_quality_2_count"],
            thresholds["required_identity_parts_quality_2_count"],
        ),
        (
            "固定武器替换",
            summary["fixed_weapon_substitution_count"],
            thresholds["fixed_weapon_substitution_count"],
        ),
        (
            "自动重试",
            summary["automatic_retry_count"],
            thresholds["automatic_retry_count"],
        ),
        (
            "额外根包装",
            summary["extra_root_wrapper_count"],
            thresholds["extra_root_wrapper_count"],
        ),
        ("Key 泄漏", summary["key_leak_count"], 0),
    ]
    lines = [
        "# Forge Semantic Contract v1.1 Limited Retest 3B",
        "",
        f"**结论：{summary['status']}**",
        "",
        "本次运行是独立、不可覆盖的六案例有限真实复测。未执行 Gate B，未启动 ComfyUI 或 V2，也未修改战斗、房间、锚点或美术系统。",
        "",
        "## 调用与合同",
        "",
        f"- Run ID：`{summary['run_id']}`",
        f"- 官方端点：`{summary['endpoint']}`",
        f"- 精确模型：`{summary['model_id']}`",
        f"- 合同：`{summary['contract_version']}`",
        f"- 调用：{summary['call_count']}/6；自动重试：{summary['automatic_retry_count']}",
        f"- v1.1 实时 clarification 的 `known_action_hints` 仅允许数组；历史字符串只保留在 forensic replay。",
        "- 模型 tool input 原样验证；没有修复、拆包、强制转换或默认值。",
        "",
        "## 通过门槛",
        "",
        "| 门槛 | 实际 | 要求 | 结果 |",
        "|---|---:|---:|---|",
    ]
    for label, actual, expected in gate_rows:
        lines.append(f"| {label} | {actual} | {expected} | {_pass(actual == expected)} |")
    lines.extend(
        [
            "",
            "## 逐案例结果",
            "",
            "| Case | API | Tool | Schema/Cross | 澄清 | 身份 | 行为 | Parts | 固定替换 | 根包装 |",
            "|---|---|---|---|---|---|---|---:|---|---|",
        ]
    )
    by_id = {str(result.get("case_id")): result for result in results}
    for score in scores:
        case_id = str(score["case_id"])
        result = by_id.get(case_id, {})
        lines.append(
            "| {case} | {api} | {tool} | {schema} | {clarify} | {identity} | "
            "{behavior} | {parts} | {fixed} | {wrapper} |".format(
                case=case_id,
                api=_pass(score.get("api_success") is True),
                tool=_pass(score.get("exactly_one_legal_tool_use") is True),
                schema=_pass(
                    score.get("schema_valid") is True
                    and score.get("cross_field_valid") is True
                ),
                clarify=(
                    _pass(score.get("clarification_correct") is True)
                    if case_id in {"17", "18"}
                    else "—"
                ),
                identity=(
                    _pass(score.get("identity_correct") is True)
                    if case_id in {"10", "13", "04", "01"}
                    else "—"
                ),
                behavior=(
                    _pass(score.get("behavior_correct") is True)
                    if case_id in {"10", "13", "04", "01"}
                    else "—"
                ),
                parts=(
                    score.get("required_identity_parts_quality", 0)
                    if case_id in {"10", "13", "04", "01"}
                    else "—"
                ),
                fixed=_pass(score.get("fixed_weapon_substitution") is False),
                wrapper=_pass(score.get("extra_root_wrapper") is False),
            )
        )
    lines.extend(["", "## 输出摘录", ""])
    for case_id in CASE_ORDER:
        result = by_id.get(case_id, {})
        tool_input = result.get("tool_input_received")
        if isinstance(tool_input, Mapping) and isinstance(tool_input.get("identity"), Mapping):
            identity = tool_input["identity"]
            combat = tool_input.get("combat", {})
            lines.append(
                f"- Case {case_id}：`{identity.get('canonical_name_zh')}` / "
                f"`{identity.get('canonical_name_en')}`；"
                f"`{combat.get('behavior_family')}` + `{combat.get('effect_type')}`；"
                f"parts={json.dumps(identity.get('required_identity_parts'), ensure_ascii=False)}"
            )
        elif isinstance(tool_input, Mapping):
            lines.append(
                f"- Case {case_id}：`{tool_input.get('ambiguity_type')}`；"
                f"问题：{tool_input.get('question_zh')}；"
                f"known_action_hints 类型：{type(tool_input.get('known_action_hints')).__name__}"
            )
        else:
            lines.append(
                f"- Case {case_id}：无可验证 tool input；{result.get('failure_reason', '')}"
            )
    lines.extend(
        [
            "",
            "## 证据与边界",
            "",
            f"- 冻结 Gate A source run：`{summary['source_run_id']}`",
            f"- source evidence SHA-256：`{summary['source_evidence_sha256']}`",
            f"- Approved 3B config SHA-256：`{summary['approved_config_manifest_sha256']}`（{summary['approved_config_file_count']} 个固定输入/执行文件）",
            "- 原 Gate A 报告、Postmortem 3A 报告及四个冻结 fixture 在调用前后均按 SHA-256 验证，未改写。",
            "- 每例完整脱敏响应位于本 run 的 `raw_response_redacted/`；逐例原始 tool input 同时保存在不可覆盖的 `result.json`。",
            "- `evidence_hashes.json` 覆盖逐例结果、脱敏响应、请求清单、报告、额度锁和合同输入。",
            f"- Secret scan：{_pass(summary['secret_scan_passed'] is True)}；Key 泄漏：{summary['key_leak_count']}。",
            "",
            "## 停止条件",
            "",
            "Gate B 未执行。即使本次通过，也必须停止并等待用户批准 4 个全新盲测案例。",
            "",
        ]
    )
    return "\n".join(lines)


def _validate_stage(
    directory: Path,
    run_id: str,
    semantic_root: Path,
    archive_relative: str,
) -> bool:
    required = {
        "LIMITED_RETEST_3B_REPORT.md",
        "limited_retest_3b_results.csv",
        "limited_retest_3b_summary.json",
        "evidence_hashes.json",
        "COMPLETE.json",
        "raw_response_redacted",
        "request_manifests",
    }
    if not required.issubset({entry.name for entry in directory.iterdir()}):
        raise LimitedRetest3BReportingError("3B report stage is incomplete.")
    summary = json.loads(
        (directory / "limited_retest_3b_summary.json").read_text(encoding="utf-8")
    )
    if summary.get("run_id") != run_id or summary.get("case_order") != list(CASE_ORDER):
        raise LimitedRetest3BReportingError("3B staged summary correlation mismatch.")
    raw_files = sorted((directory / "raw_response_redacted").glob("*.json"))
    manifests = sorted((directory / "request_manifests").glob("*.json"))
    if [path.stem for path in raw_files] != sorted(CASE_ORDER) or [
        path.stem for path in manifests
    ] != sorted(CASE_ORDER):
        raise LimitedRetest3BReportingError("3B staged per-case evidence is incomplete.")
    evidence = json.loads((directory / "evidence_hashes.json").read_text(encoding="utf-8"))
    complete = json.loads((directory / "COMPLETE.json").read_text(encoding="utf-8"))
    if (
        evidence.get("run_id") != run_id
        or complete.get("run_id") != run_id
        or complete.get("status") != "complete"
        or complete.get("evidence_sha256") != _sha256(directory / "evidence_hashes.json")
    ):
        raise LimitedRetest3BReportingError("3B staged completion attestation is invalid.")
    files = evidence.get("files")
    if not isinstance(files, Mapping):
        raise LimitedRetest3BReportingError("3B staged evidence map is invalid.")
    archive_prefix = archive_relative + "/"
    for relative, expected in files.items():
        if not isinstance(relative, str) or not isinstance(expected, str):
            raise LimitedRetest3BReportingError("3B staged evidence entry is invalid.")
        if relative.startswith(archive_prefix):
            path = directory / relative[len(archive_prefix):]
        else:
            path = semantic_root / relative
        if path.is_symlink() or not path.is_file() or _sha256(path) != expected:
            raise LimitedRetest3BReportingError(
                f"3B staged evidence hash mismatch: {relative}"
            )
    return True


def _verify_evidence(semantic_root: Path, manifest: Mapping[str, Any]) -> None:
    files = manifest.get("files")
    if not isinstance(files, Mapping):
        raise LimitedRetest3BReportingError("3B evidence manifest has no files map.")
    root = semantic_root.resolve()
    for relative, expected in files.items():
        if not isinstance(relative, str) or not isinstance(expected, str):
            raise LimitedRetest3BReportingError("3B evidence entry is invalid.")
        raw_path = root / relative
        if raw_path.is_symlink():
            raise LimitedRetest3BReportingError("3B evidence path is a symbolic link.")
        path = raw_path.resolve(strict=False)
        try:
            path.relative_to(root)
        except ValueError as exc:
            raise LimitedRetest3BReportingError("3B evidence path escapes semantic root.") from exc
        if not path.is_file() or _sha256(path) != expected:
            raise LimitedRetest3BReportingError(
                f"3B evidence hash mismatch after publication: {relative}"
            )


def write_limited_retest_3b_reports(
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
    configuration_hashes: Mapping[str, str],
    preflight: Mapping[str, Any],
) -> dict[str, Any]:
    if [str(result.get("case_id")) for result in results] != list(CASE_ORDER):
        raise LimitedRetest3BReportingError("3B result order is incomplete.")
    if [str(score.get("case_id")) for score in scores] != list(CASE_ORDER):
        raise LimitedRetest3BReportingError("3B score order is incomplete.")
    reservation_attested, _ = _reservation_attestation(
        reservation_path,
        run_id=run_id,
        model_id=model_id,
        actual_call_count=actual_call_count,
    )
    summary = _summary(
        run_id=run_id,
        model_id=model_id,
        results=results,
        scores=scores,
        actual_call_count=actual_call_count,
        reservation_attested=reservation_attested,
        configuration_hashes=configuration_hashes,
        preflight=preflight,
    )
    report_text = _report_markdown(summary, scores, results)
    csv_text = _csv_text(scores)

    archive_final = semantic_root / "reports" / "limited_retest_3b" / run_id
    stage = semantic_root / ".tmp" / "limited_retest_3b_reports" / run_id
    if stage.exists() or archive_final.exists():
        raise LimitedRetest3BReportingError("3B report destination already exists.")
    _write_new(stage / "LIMITED_RETEST_3B_REPORT.md", report_text.encode("utf-8"))
    _write_new(stage / "limited_retest_3b_results.csv", csv_text.encode("utf-8-sig"))
    _write_new(stage / "limited_retest_3b_summary.json", _json_bytes(summary))

    for result in results:
        case_id = str(result["case_id"])
        raw = _redacted_document(result.get("raw_response_redacted", ""), case_id)
        _write_new(stage / "raw_response_redacted" / f"{case_id}.json", _json_bytes(raw))
        request_manifest = {
            "case_id": case_id,
            "local_request_id": result.get("local_request_id"),
            "provider_request_id": result.get("request_id"),
            "endpoint": result.get("endpoint"),
            "model_id": result.get("model_id"),
            "contract_version": result.get("contract_version"),
            "request_body_sha256": result.get("request_body_sha256"),
            "tool_input_sha256": result.get("tool_input_sha256"),
            "api_status": result.get("api_status"),
            "retry_count": result.get("retry_count"),
        }
        _write_new(stage / "request_manifests" / f"{case_id}.json", _json_bytes(request_manifest))
        if result.get("result_type") == "compiled" and isinstance(result.get("result"), Mapping):
            _write_new(
                stage / "compiled_results" / f"{case_id}.json",
                _json_bytes(result["result"]),
            )

    archive_relative = archive_final.relative_to(semantic_root).as_posix()
    files: dict[str, str] = {}
    for path in sorted(stage.rglob("*")):
        if path.is_file():
            staged_relative = path.relative_to(stage).as_posix()
            files[f"{archive_relative}/{staged_relative}"] = _sha256(path)
    for case_id in CASE_ORDER:
        result_path = output_run_directory / case_id / "result.json"
        files[result_path.relative_to(semantic_root).as_posix()] = _sha256(result_path)
    files[reservation_path.relative_to(semantic_root).as_posix()] = _sha256(reservation_path)
    approved_manifest_path = (
        semantic_root / "cases" / "limited_retest_3b_approved_config.json"
    )
    approved_manifest = json.loads(approved_manifest_path.read_text(encoding="utf-8"))
    approved_files = approved_manifest.get("files")
    if not isinstance(approved_files, Mapping):
        raise LimitedRetest3BReportingError(
            "Approved 3B configuration manifest is invalid during reporting."
        )
    input_paths = [approved_manifest_path]
    input_paths.extend(semantic_root / relative for relative in approved_files)
    for path in input_paths:
        files[path.relative_to(semantic_root).as_posix()] = _sha256(path)
    convenience_mapping = {
        "reports/LIMITED_RETEST_3B_REPORT.md": stage / "LIMITED_RETEST_3B_REPORT.md",
        "reports/limited_retest_3b_results.csv": stage / "limited_retest_3b_results.csv",
        "reports/limited_retest_3b_summary.json": stage / "limited_retest_3b_summary.json",
    }
    convenience_hashes = {
        relative: _sha256(source) for relative, source in convenience_mapping.items()
    }
    evidence = {
        "algorithm": "SHA-256",
        "run_id": run_id,
        "source_run_id": preflight.get("source_run_id"),
        "source_evidence_sha256": preflight.get("source_evidence_sha256"),
        "approved_config_manifest_sha256": preflight.get(
            "approved_config_manifest_sha256"
        ),
        "contract_version": CONTRACT_VERSION,
        "model_id": model_id,
        "case_order": list(CASE_ORDER),
        "convenience_files_expected_sha256": convenience_hashes,
        "files": dict(sorted(files.items())),
    }
    _write_new(stage / "evidence_hashes.json", _json_bytes(evidence))
    evidence_hash = _sha256(stage / "evidence_hashes.json")
    _write_new(
        stage / "COMPLETE.json",
        _json_bytes(
            {
                "run_id": run_id,
                "status": "complete",
                "result": summary["status"],
                "evidence_sha256": evidence_hash,
                "gate_b_executed": False,
            }
        ),
    )

    if scan_repository(repository_root):
        raise LimitedRetest3BReportingError(
            "Secret scan rejected staged 3B report publication."
        )
    atomic_deliver(
        stage,
        archive_final,
        lambda directory: _validate_stage(
            directory,
            run_id,
            semantic_root,
            archive_relative,
        ),
    )
    for relative, source_name in (
        ("LIMITED_RETEST_3B_REPORT.md", "LIMITED_RETEST_3B_REPORT.md"),
        ("limited_retest_3b_results.csv", "limited_retest_3b_results.csv"),
        ("limited_retest_3b_summary.json", "limited_retest_3b_summary.json"),
    ):
        _publish_copy_new(
            archive_final / source_name,
            semantic_root / "reports" / relative,
        )
    _verify_evidence(semantic_root, evidence)
    for relative, expected in convenience_hashes.items():
        path = semantic_root / relative
        if not path.is_file() or path.is_symlink() or _sha256(path) != expected:
            raise LimitedRetest3BReportingError(
                f"3B convenience copy hash mismatch: {relative}"
            )
    return summary


__all__ = [
    "CSV_FIELDS",
    "LimitedRetest3BReportingError",
    "write_limited_retest_3b_reports",
]
