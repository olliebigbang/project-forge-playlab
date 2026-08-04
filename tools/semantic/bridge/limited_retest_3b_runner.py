#!/usr/bin/env python3
"""Exactly-six, non-retried Anthropic runner for Contract v1.1 Retest 3B."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import re
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping, Protocol, Sequence

from anthropic_semantic_compiler import (
    ANTHROPIC_MESSAGES_URL,
    MAX_TOKENS,
    AnthropicSemanticCompiler,
    CallLimiter,
    SemanticCompilerError,
    build_anthropic_payload,
    redact_sensitive_text,
    require_safe_tls_environment,
)
from atomic_output import atomic_deliver
from gate_a_evaluator import isolated_model_input, load_gate_a_cases
from limited_retest_3b_evaluator import CASE_ORDER, evaluate_run
from limited_retest_3b_reporting import write_limited_retest_3b_reports
from scope_guard import ScopeGuardError, verify_scope_baseline
from secret_scan import scan_repository
from semantic_contract import (
    CLARIFICATION_REQUEST_SCHEMA,
    CONTRACT_VERSION,
    FORGE_SEMANTIC_BLUEPRINT_SCHEMA,
    REQUEST_CLARIFICATION_TOOL,
    SUBMIT_BLUEPRINT_TOOL,
    ContractValidationError,
    validate_tool_input,
)


APPROVED_CALLS = 6
SOURCE_RUN_ID = "gate-a-20260802T232039017356Z-fddde20a"
SOURCE_EVIDENCE_SHA256 = (
    "94a602bdf2d0571cf294287f3d188e830fe7fa968b148e8ca67af3387cd0b347"
)
APPROVED_CONFIG_MANIFEST_SHA256 = "ba32d21e0705cf3853376cfab99b1ad83c4b26102f72796f7726f335f332d10d"
RUN_PREFIX = "limited-retest-3b"
_RUN_ID_PATTERN = re.compile(
    r"limited-retest-3b-[0-9]{8}T[0-9]{12}Z-[0-9a-f]{8}"
)
_MODEL_ID_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}")
_APPROVAL_CONSTANT_PATTERN = re.compile(
    rb'APPROVED_CONFIG_MANIFEST_SHA256 = "[0-9a-f]{64}"'
)


class LimitedRetest3BError(RuntimeError):
    """Safe local failure that never contains credential material."""


class SemanticCompilerLike(Protocol):
    @property
    def calls_made(self) -> int: ...

    def compile(self, player_input: str) -> dict[str, Any]: ...


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace(
        "+00:00", "Z"
    )


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _sha256(path: Path) -> str:
    return _sha256_bytes(path.read_bytes())


def _read_json_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise LimitedRetest3BError(f"Cannot read required 3B JSON file: {path}") from exc
    if not isinstance(value, dict):
        raise LimitedRetest3BError(f"Required 3B JSON file is not an object: {path}")
    return value


def _safe_repo_path(repository_root: Path, relative: str) -> Path:
    raw_candidate = repository_root / Path(relative)
    if raw_candidate.is_symlink():
        raise LimitedRetest3BError("Protected history file is a symbolic link.")
    candidate = raw_candidate.resolve(strict=False)
    try:
        candidate.relative_to(repository_root)
    except ValueError as exc:
        raise LimitedRetest3BError("Protected history manifest contains an outside path.") from exc
    return candidate


def verify_protected_history(
    repository_root: Path, semantic_root: Path
) -> dict[str, Any]:
    """Verify every frozen report/fixture plus the source run evidence chain."""

    manifest_path = semantic_root / "cases" / "limited_retest_3b_protected_hashes.json"
    manifest = _read_json_object(manifest_path)
    if (
        manifest.get("algorithm") != "SHA-256"
        or manifest.get("source_run_id") != SOURCE_RUN_ID
        or manifest.get("source_evidence_sha256") != SOURCE_EVIDENCE_SHA256
        or not isinstance(manifest.get("files"), dict)
    ):
        raise LimitedRetest3BError("3B protected-history manifest is invalid.")
    for relative, expected in manifest["files"].items():
        if not isinstance(relative, str) or not re.fullmatch(r"[0-9A-Za-z_./-]+", relative):
            raise LimitedRetest3BError("3B protected-history path is invalid.")
        path = _safe_repo_path(repository_root, relative)
        if not path.is_file() or not isinstance(expected, str) or _sha256(path) != expected:
            raise LimitedRetest3BError(
                f"Frozen Gate A/3A evidence changed: {relative}"
            )

    run_reports = semantic_root / "reports" / "runs" / SOURCE_RUN_ID
    evidence_path = run_reports / "evidence_hashes.json"
    complete = _read_json_object(run_reports / "COMPLETE.json")
    if (
        complete.get("run_id") != SOURCE_RUN_ID
        or complete.get("status") != "complete"
        or complete.get("evidence_sha256") != SOURCE_EVIDENCE_SHA256
        or _sha256(evidence_path) != SOURCE_EVIDENCE_SHA256
    ):
        raise LimitedRetest3BError("Frozen Gate A completion attestation is invalid.")
    evidence = _read_json_object(evidence_path)
    if (
        evidence.get("algorithm") != "SHA-256"
        or evidence.get("run_id") != SOURCE_RUN_ID
        or not isinstance(evidence.get("files"), dict)
    ):
        raise LimitedRetest3BError("Frozen Gate A evidence manifest is invalid.")
    for relative, expected in evidence["files"].items():
        if not isinstance(relative, str) or not isinstance(expected, str):
            raise LimitedRetest3BError("Frozen Gate A evidence entry is invalid.")
        path = _safe_repo_path(semantic_root, relative)
        if not path.is_file() or _sha256(path) != expected:
            raise LimitedRetest3BError(
                f"Frozen Gate A evidence hash mismatch: {relative}"
            )

    summary = _read_json_object(run_reports / "gate_a_summary.json")
    if (
        summary.get("provider") != "anthropic"
        or summary.get("endpoint") != ANTHROPIC_MESSAGES_URL
        or summary.get("real_ai_calls_performed") is not True
        or summary.get("call_count") != 20
        or not isinstance(summary.get("model_id"), str)
        or not summary["model_id"].strip()
    ):
        raise LimitedRetest3BError("Frozen Gate A model provenance is invalid.")
    return {
        "source_run_id": SOURCE_RUN_ID,
        "source_evidence_sha256": SOURCE_EVIDENCE_SHA256,
        "model_id": summary["model_id"],
        "protected_file_count": len(manifest["files"]),
        "source_evidence_file_count": len(evidence["files"]),
    }


def _approved_file_sha256(path: Path, relative: str) -> str:
    data = path.read_bytes()
    if relative == "bridge/limited_retest_3b_runner.py":
        replacement = (
            b'APPROVED_CONFIG_MANIFEST_SHA256 = "'
            + b"0" * 64
            + b'"'
        )
        data, count = _APPROVAL_CONSTANT_PATTERN.subn(replacement, data)
        if count != 1:
            raise LimitedRetest3BError(
                "3B runner approval-constant normalization failed."
            )
    return _sha256_bytes(data)


def verify_approved_configuration(semantic_root: Path) -> dict[str, Any]:
    """Verify the exact approved prompt, schemas, evaluator, runner and scripts."""

    manifest_path = semantic_root / "cases" / "limited_retest_3b_approved_config.json"
    if not manifest_path.is_file() or manifest_path.is_symlink():
        raise LimitedRetest3BError("3B approved-configuration manifest is unavailable.")
    if _sha256(manifest_path) != APPROVED_CONFIG_MANIFEST_SHA256:
        raise LimitedRetest3BError("3B approved-configuration manifest digest changed.")
    manifest = _read_json_object(manifest_path)
    if (
        set(manifest) != {
            "contract_version",
            "algorithm",
            "runner_hash_normalization",
            "source_run_id",
            "files",
        }
        or manifest.get("contract_version") != CONTRACT_VERSION
        or manifest.get("algorithm") != "SHA-256"
        or manifest.get("source_run_id") != SOURCE_RUN_ID
        or manifest.get("runner_hash_normalization")
        != "APPROVED_CONFIG_MANIFEST_SHA256 value replaced by 64 zeroes"
        or not isinstance(manifest.get("files"), dict)
    ):
        raise LimitedRetest3BError("3B approved-configuration manifest is invalid.")
    root = semantic_root.resolve()
    for relative, expected in manifest["files"].items():
        if (
            not isinstance(relative, str)
            or not re.fullmatch(r"[0-9A-Za-z_./-]+", relative)
            or not isinstance(expected, str)
            or not re.fullmatch(r"[0-9a-f]{64}", expected)
        ):
            raise LimitedRetest3BError("3B approved-configuration entry is invalid.")
        raw_path = root / relative
        if raw_path.is_symlink():
            raise LimitedRetest3BError("3B approved configuration contains a symlink.")
        path = raw_path.resolve(strict=False)
        try:
            path.relative_to(root)
        except ValueError as exc:
            raise LimitedRetest3BError(
                "3B approved configuration contains an outside path."
            ) from exc
        if not path.is_file() or _approved_file_sha256(path, relative) != expected:
            raise LimitedRetest3BError(
                f"Approved 3B configuration changed: {relative}"
            )
    return {
        "approved_config_manifest_sha256": APPROVED_CONFIG_MANIFEST_SHA256,
        "approved_config_file_count": len(manifest["files"]),
    }


def _read_system_prompt(path: Path) -> str:
    try:
        value = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise LimitedRetest3BError("Cannot read the v1.1 system prompt.") from exc
    if not value.strip():
        raise LimitedRetest3BError("The v1.1 system prompt is empty.")
    return value


def _load_selected_cases(semantic_root: Path) -> list[dict[str, str]]:
    all_cases = load_gate_a_cases(semantic_root / "cases" / "gate_a_cases.json")
    by_id = {case["case_id"]: case for case in all_cases}
    try:
        selected = [by_id[case_id] for case_id in CASE_ORDER]
    except KeyError as exc:
        raise LimitedRetest3BError("An approved 3B source case is missing.") from exc
    if [case["case_id"] for case in selected] != list(CASE_ORDER):
        raise LimitedRetest3BError("3B case order differs from the approved order.")
    return selected


def _configuration(
    semantic_root: Path,
) -> tuple[str, dict[str, Any], dict[str, Any], list[dict[str, str]], dict[str, str]]:
    prompt_path = semantic_root / "prompts" / "semantic_compiler_system_prompt.md"
    blueprint_path = semantic_root / "schema" / "forge_semantic_blueprint.schema.json"
    clarification_path = semantic_root / "schema" / "clarification_request.schema.json"
    cases_path = semantic_root / "cases" / "gate_a_cases.json"
    expected_path = semantic_root / "cases" / "limited_retest_3b_expected.json"
    prompt = _read_system_prompt(prompt_path)
    blueprint = _read_json_object(blueprint_path)
    clarification = _read_json_object(clarification_path)
    if blueprint != FORGE_SEMANTIC_BLUEPRINT_SCHEMA:
        raise LimitedRetest3BError("Live v1.1 Blueprint Schema parity failed.")
    if clarification != CLARIFICATION_REQUEST_SCHEMA:
        raise LimitedRetest3BError("Live v1.1 clarification Schema parity failed.")
    known_action_type = (
        clarification.get("properties", {})
        .get("known_action_hints", {})
        .get("type")
    )
    if known_action_type != "array":
        raise LimitedRetest3BError(
            "Live v1.1 known_action_hints must be array-only before 3B."
        )
    cases = _load_selected_cases(semantic_root)
    selected_bytes = json.dumps(
        cases, ensure_ascii=False, separators=(",", ":")
    ).encode("utf-8")
    hashes = {
        "system_prompt_sha256": _sha256(prompt_path),
        "blueprint_schema_sha256": _sha256(blueprint_path),
        "clarification_schema_sha256": _sha256(clarification_path),
        "source_cases_file_sha256": _sha256(cases_path),
        "selected_cases_sha256": _sha256_bytes(selected_bytes),
        "evaluator_expected_sha256": _sha256(expected_path),
    }
    return prompt, blueprint, clarification, cases, hashes


def _reservation_path(semantic_root: Path) -> Path:
    return semantic_root / "reports" / "limited_retest_3b_real_call_reservation.json"


def _output_root(semantic_root: Path) -> Path:
    return semantic_root / "output" / "limited_retest_3b"


def _report_root(semantic_root: Path) -> Path:
    return semantic_root / "reports" / "limited_retest_3b"


def _ensure_no_prior_3b(semantic_root: Path) -> None:
    conflicts = [
        _reservation_path(semantic_root),
        semantic_root / "reports" / "LIMITED_RETEST_3B_REPORT.md",
        semantic_root / "reports" / "limited_retest_3b_results.csv",
        semantic_root / "reports" / "limited_retest_3b_summary.json",
    ]
    if any(path.exists() for path in conflicts):
        raise LimitedRetest3BError(
            "Limited Retest 3B already has evidence; refusing any second paid run."
        )
    for directory in (_output_root(semantic_root), _report_root(semantic_root)):
        if directory.exists() and any(directory.iterdir()):
            raise LimitedRetest3BError(
                "Limited Retest 3B output already exists; historical results are non-overwritable."
            )


def _preflight(
    repository_root: Path, semantic_root: Path, *, require_unused_budget: bool
) -> dict[str, Any]:
    if scan_repository(repository_root):
        raise LimitedRetest3BError("3B stopped because the repository secret scan failed.")
    try:
        protected_scope = verify_scope_baseline(
            repository_root,
            semantic_root / "reports" / "gate_a_scope_baseline.json",
        )
    except ScopeGuardError as exc:
        raise LimitedRetest3BError(str(exc)) from exc
    history = verify_protected_history(repository_root, semantic_root)
    approved = verify_approved_configuration(semantic_root)
    _, _, _, cases, hashes = _configuration(semantic_root)
    if require_unused_budget:
        _ensure_no_prior_3b(semantic_root)
    return {
        **history,
        **approved,
        "contract_version": CONTRACT_VERSION,
        "case_order": list(CASE_ORDER),
        "case_count": len(cases),
        "configuration_hashes": hashes,
        "protected_scope": protected_scope,
        "ready": True,
    }


def require_environment(expected_model_id: str) -> str:
    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    model_id = os.environ.get("FORGE_SEMANTIC_MODEL", "")
    if not api_key.strip():
        raise LimitedRetest3BError(
            "3B stopped: ANTHROPIC_API_KEY is missing. Use the interactive script."
        )
    if (
        not model_id
        or model_id != model_id.strip()
        or not _MODEL_ID_PATTERN.fullmatch(model_id)
        or model_id != expected_model_id
    ):
        raise LimitedRetest3BError(
            "3B stopped: FORGE_SEMANTIC_MODEL does not exactly match the frozen Gate A model."
        )
    if model_id == api_key or redact_sensitive_text(model_id) != model_id:
        raise LimitedRetest3BError("3B stopped: model ID resembles credential material.")
    return model_id


def _new_run_id(output_root: Path) -> str:
    for _ in range(16):
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        candidate = f"{RUN_PREFIX}-{timestamp}-{uuid.uuid4().hex[:8]}"
        if _RUN_ID_PATTERN.fullmatch(candidate) and not (output_root / candidate).exists():
            return candidate
    raise LimitedRetest3BError("Could not allocate a unique 3B run_id.")


def _atomic_write_json(path: Path, payload: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    encoded = (json.dumps(payload, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(encoded)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def _claim_budget(
    semantic_root: Path,
    *,
    run_id: str,
    model_id: str,
    hashes: Mapping[str, str],
) -> Path:
    path = _reservation_path(semantic_root)
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "run_id": run_id,
        "contract_version": CONTRACT_VERSION,
        "source_run_id": SOURCE_RUN_ID,
        "source_evidence_sha256": SOURCE_EVIDENCE_SHA256,
        "model_id": model_id,
        "endpoint": ANTHROPIC_MESSAGES_URL,
        "case_order": list(CASE_ORDER),
        "configuration_hashes": dict(hashes),
        "max_real_calls": APPROVED_CALLS,
        "attempts_reserved": 0,
        "actual_calls_observed": 0,
        "attempted_case_ids": [],
        "status": "reserved",
        "created_at": _utc_now(),
        "updated_at": _utc_now(),
    }
    encoded = (json.dumps(payload, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError as exc:
        raise LimitedRetest3BError(
            "The 3B six-call budget is already reserved; no reset or ForceNewRun is allowed."
        ) from exc
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(encoded)
            handle.flush()
            os.fsync(handle.fileno())
    except Exception:
        # Keep even a partial exclusive marker.  Removing it could permit a
        # second process to repeat a paid case after an ambiguous crash.
        raise
    return path


def _read_reservation(path: Path, run_id: str) -> dict[str, Any]:
    value = _read_json_object(path)
    if (
        value.get("run_id") != run_id
        or value.get("contract_version") != CONTRACT_VERSION
        or value.get("max_real_calls") != APPROVED_CALLS
        or value.get("case_order") != list(CASE_ORDER)
    ):
        raise LimitedRetest3BError("The persistent 3B call reservation is invalid.")
    attempts = value.get("attempts_reserved")
    actual = value.get("actual_calls_observed")
    attempted_ids = value.get("attempted_case_ids")
    if (
        isinstance(attempts, bool)
        or not isinstance(attempts, int)
        or not 0 <= attempts <= APPROVED_CALLS
        or isinstance(actual, bool)
        or not isinstance(actual, int)
        or not 0 <= actual <= APPROVED_CALLS
        or not isinstance(attempted_ids, list)
        or attempted_ids != list(CASE_ORDER[:attempts])
    ):
        raise LimitedRetest3BError("The persistent 3B call counters are invalid.")
    return value


def _reserve_case_attempt(path: Path, run_id: str, case_id: str) -> None:
    value = _read_reservation(path, run_id)
    attempts = int(value["attempts_reserved"])
    if attempts >= APPROVED_CALLS or case_id != CASE_ORDER[attempts]:
        raise LimitedRetest3BError("A 3B case would be duplicated or attempted out of order.")
    value["attempts_reserved"] = attempts + 1
    value["attempted_case_ids"] = list(CASE_ORDER[: attempts + 1])
    value["status"] = "in_progress"
    value["updated_at"] = _utc_now()
    _atomic_write_json(path, value)


def _record_observed_calls(
    path: Path, run_id: str, observed: int, *, status: str = "in_progress"
) -> None:
    value = _read_reservation(path, run_id)
    if isinstance(observed, bool) or not 0 <= observed <= APPROVED_CALLS:
        raise LimitedRetest3BError("Observed 3B call count is invalid.")
    if observed > int(value["attempts_reserved"]):
        raise LimitedRetest3BError("Observed calls exceed reserved 3B attempts.")
    value["actual_calls_observed"] = observed
    value["status"] = status
    value["updated_at"] = _utc_now()
    _atomic_write_json(path, value)


def _request_body_sha256(
    *,
    prompt: str,
    player_input: str,
    model_id: str,
    blueprint_schema: Mapping[str, Any],
    clarification_schema: Mapping[str, Any],
) -> str:
    payload = build_anthropic_payload(
        prompt,
        player_input,
        model_id,
        blueprint_schema,
        clarification_schema,
    )
    body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode(
        "utf-8"
    )
    return _sha256_bytes(body)


def _usage(value: Any) -> dict[str, int]:
    source = value if isinstance(value, Mapping) else {}
    result: dict[str, int] = {}
    for field in (
        "input_tokens",
        "output_tokens",
        "cache_creation_input_tokens",
        "cache_read_input_tokens",
    ):
        item = source.get(field, 0)
        result[field] = (
            item
            if isinstance(item, int) and not isinstance(item, bool) and item >= 0
            else 0
        )
    return result


def _base_record(
    *,
    case_id: str,
    player_input: str,
    local_request_id: str,
    model_id: str,
    request_body_sha256: str,
    hashes: Mapping[str, str],
    started_at: str,
    completed_at: str,
    elapsed_ms: int,
    actual_request_performed: bool,
) -> dict[str, Any]:
    return {
        "case_id": case_id,
        "input_text": player_input,
        "provider": "anthropic",
        "endpoint": ANTHROPIC_MESSAGES_URL,
        "model_id": model_id,
        "contract_version": CONTRACT_VERSION,
        "local_request_id": local_request_id,
        "request_body_sha256": request_body_sha256,
        "configuration_hashes": dict(hashes),
        "api_request_performed": actual_request_performed,
        "ai_interpretation_used": actual_request_performed,
        "started_at": started_at,
        "completed_at": completed_at,
        "elapsed_ms": elapsed_ms,
        "retry_count": 0,
        "repair_applied": False,
        "unwrap_applied": False,
        "coercion_applied": False,
        "defaults_applied": False,
    }


def _root_attestation(tool_name: str, tool_input: Mapping[str, Any]) -> dict[str, Any]:
    if tool_name == SUBMIT_BLUEPRINT_TOOL:
        expected = set(FORGE_SEMANTIC_BLUEPRINT_SCHEMA["properties"])
    elif tool_name == REQUEST_CLARIFICATION_TOOL:
        expected = set(CLARIFICATION_REQUEST_SCHEMA["properties"])
    else:
        expected = set()
    actual = {str(key) for key in tool_input}
    return {
        "input_root_keys": sorted(actual),
        "extra_root_keys": sorted(actual - expected),
        "missing_root_keys": sorted(expected - actual),
        "extra_root_wrapper": bool(actual - expected),
    }


def _record_from_parsed(
    *, parsed: Mapping[str, Any], base: Mapping[str, Any]
) -> dict[str, Any]:
    tool_name = str(parsed.get("tool_name", ""))
    source_input = parsed.get("tool_input")
    if not isinstance(source_input, Mapping):
        raise LimitedRetest3BError("Parsed tool input is not an object.")
    tool_input = copy.deepcopy(dict(source_input))
    serialized = json.dumps(tool_input, ensure_ascii=False, separators=(",", ":"))
    if redact_sensitive_text(serialized) != serialized:
        raise LimitedRetest3BError("Tool input contained credential-shaped material.")
    root = _root_attestation(tool_name, tool_input)
    validation: dict[str, Any]
    result: dict[str, Any] | None
    result_type: str
    failure_reason = ""
    snapshot = copy.deepcopy(tool_input)
    try:
        returned = validate_tool_input(tool_name, tool_input)
        if returned is not tool_input or tool_input != snapshot:
            raise LimitedRetest3BError("The live validator mutated or replaced tool input.")
        validation = {
            "stage": "complete",
            "schema_valid": True,
            "cross_field_valid": True,
            "issues": [],
            "repaired": False,
            "unwrapped": False,
            "coerced": False,
            "defaulted": False,
        }
        result = tool_input
        result_type = (
            "compiled"
            if tool_name == SUBMIT_BLUEPRINT_TOOL
            else "needs_clarification"
        )
    except ContractValidationError as exc:
        if tool_input != snapshot:
            raise LimitedRetest3BError("The live validator mutated rejected tool input.")
        validation = {
            "stage": exc.stage,
            "schema_valid": True if exc.stage == "cross_field" else False if exc.stage == "schema" else None,
            "cross_field_valid": False if exc.stage == "cross_field" else None,
            "issues": [
                {
                    "json_pointer": issue.json_pointer,
                    "path": issue.path,
                    "rule": issue.message,
                }
                for issue in exc.issues
            ],
            "repaired": False,
            "unwrapped": False,
            "coerced": False,
            "defaulted": False,
        }
        result = None
        result_type = "failed"
        failure_reason = f"CONTRACT_VALIDATION_FAILED[{exc.stage}]"

    usage = _usage(parsed.get("usage"))
    record = dict(base)
    record.update(
        {
            "api_status": 200,
            "response_model_id": parsed.get("model_id"),
            "request_id": parsed.get("request_id"),
            "tool_name": tool_name,
            "tool_input_received": tool_input,
            "tool_input_sha256": _sha256_bytes(serialized.encode("utf-8")),
            "result_type": result_type,
            "result": result,
            "validation": validation,
            "schema_valid": validation["schema_valid"],
            "response_attestation": {
                "exactly_one_legal_tool_use": True,
                "sole_content_is_tool_use": True,
                "stop_reason_is_tool_use": parsed.get("stop_reason") == "tool_use",
                **root,
            },
            "usage": usage,
            **usage,
            "stop_reason": parsed.get("stop_reason"),
            "raw_response_redacted": redact_sensitive_text(
                parsed.get("raw_response_redacted", "")
            ),
            "failure_reason": failure_reason,
        }
    )
    return record


def _record_from_error(
    *,
    error: BaseException,
    parsed: Mapping[str, Any] | None,
    base: Mapping[str, Any],
) -> dict[str, Any]:
    api_status: int | str = "unavailable"
    raw = ""
    code = "LOCAL_FAILURE"
    if isinstance(error, SemanticCompilerError):
        api_status = error.http_status if error.http_status is not None else "unavailable"
        raw = redact_sensitive_text(error.raw_response_redacted)
        code = error.code
    elif isinstance(error, LimitedRetest3BError):
        code = "LOCAL_EVIDENCE_REJECTION"
    if parsed is not None:
        raw = redact_sensitive_text(parsed.get("raw_response_redacted", raw))
    safe_reason = redact_sensitive_text(str(error))[:1000]
    usage = _usage(parsed.get("usage") if parsed else None)
    record = dict(base)
    record.update(
        {
            "api_status": api_status,
            "response_model_id": parsed.get("model_id") if parsed else None,
            "request_id": parsed.get("request_id") if parsed else None,
            "tool_name": parsed.get("tool_name") if parsed else None,
            "tool_input_received": None,
            "tool_input_sha256": None,
            "result_type": "failed",
            "result": None,
            "validation": {
                "stage": "transport_or_parser",
                "schema_valid": None,
                "cross_field_valid": None,
                "issues": [],
                "repaired": False,
                "unwrapped": False,
                "coerced": False,
                "defaulted": False,
            },
            "schema_valid": None,
            "response_attestation": {
                "exactly_one_legal_tool_use": False,
                "sole_content_is_tool_use": False,
                "stop_reason_is_tool_use": False,
                "input_root_keys": [],
                "extra_root_keys": [],
                "missing_root_keys": [],
                "extra_root_wrapper": False,
            },
            "usage": usage,
            **usage,
            "stop_reason": parsed.get("stop_reason") if parsed else None,
            "raw_response_redacted": raw,
            "error_code": code,
            "failure_reason": f"{code}: {safe_reason}",
        }
    )
    return record


def _write_staged_record(path: Path, record: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=False)
    encoded = json.dumps(record, ensure_ascii=False, indent=2) + "\n"
    if redact_sensitive_text(encoded) != encoded:
        raise LimitedRetest3BError("A staged 3B result contained credential-shaped material.")
    with path.open("x", encoding="utf-8", newline="\n") as handle:
        handle.write(encoded)
        handle.flush()
        os.fsync(handle.fileno())


def _validate_staged_record(
    directory: Path,
    *,
    case_id: str,
    local_request_id: str,
    model_id: str,
) -> bool:
    entries = list(directory.iterdir())
    if len(entries) != 1 or entries[0].name != "result.json":
        raise LimitedRetest3BError("A staged 3B case must contain exactly result.json.")
    value = _read_json_object(directory / "result.json")
    required = {
        "case_id": case_id,
        "local_request_id": local_request_id,
        "provider": "anthropic",
        "endpoint": ANTHROPIC_MESSAGES_URL,
        "model_id": model_id,
        "contract_version": CONTRACT_VERSION,
        "retry_count": 0,
        "repair_applied": False,
        "unwrap_applied": False,
        "coercion_applied": False,
        "defaults_applied": False,
    }
    if any(value.get(field) != expected for field, expected in required.items()):
        raise LimitedRetest3BError("Staged 3B result envelope mismatch.")
    if value.get("result_type") not in {"compiled", "needs_clarification", "failed"}:
        raise LimitedRetest3BError("Staged 3B result_type is invalid.")
    if value.get("result_type") != "failed":
        if value.get("result") != value.get("tool_input_received"):
            raise LimitedRetest3BError("Staged 3B result differs from exact tool input.")
        validate_tool_input(str(value.get("tool_name", "")), value.get("result"))
        validation = value.get("validation")
        if not isinstance(validation, Mapping) or (
            validation.get("schema_valid") is not True
            or validation.get("cross_field_valid") is not True
            or validation.get("repaired") is not False
            or validation.get("unwrapped") is not False
            or validation.get("coerced") is not False
            or validation.get("defaulted") is not False
        ):
            raise LimitedRetest3BError("Successful staged 3B result lacks validation attestation.")
    return True


def _deliver_case(
    *,
    semantic_root: Path,
    output_run_directory: Path,
    case_id: str,
    local_request_id: str,
    model_id: str,
    record: Mapping[str, Any],
) -> Path:
    temp_case = (
        semantic_root
        / ".tmp"
        / "limited_retest_3b"
        / output_run_directory.name
        / local_request_id
    )
    final_case = output_run_directory / case_id
    if temp_case.exists():
        raise LimitedRetest3BError("Temporary 3B request directory already exists.")
    _write_staged_record(temp_case / "result.json", record)
    return atomic_deliver(
        temp_case,
        final_case,
        lambda directory: _validate_staged_record(
            directory,
            case_id=case_id,
            local_request_id=local_request_id,
            model_id=model_id,
        ),
    )


def execute_limited_retest_3b(
    *,
    semantic_root: Path,
    repository_root: Path,
    compiler: SemanticCompilerLike | None = None,
) -> dict[str, Any]:
    """Run the approved cases once each; a reservation can never be reset here."""

    if compiler is not None:
        raise LimitedRetest3BError(
            "The production 3B entry point does not accept a substitute compiler."
        )
    semantic_root = semantic_root.resolve()
    repository_root = repository_root.resolve()
    if semantic_root.parent.parent != repository_root:
        raise LimitedRetest3BError("Repository root does not own this semantic implementation.")
    try:
        require_safe_tls_environment()
    except SemanticCompilerError as exc:
        raise LimitedRetest3BError(str(exc)) from None
    preflight = _preflight(repository_root, semantic_root, require_unused_budget=True)
    model_id = require_environment(str(preflight["model_id"]))
    prompt, blueprint, clarification, cases, hashes = _configuration(semantic_root)
    hashes = {
        **hashes,
        "approved_config_manifest_sha256": str(
            preflight["approved_config_manifest_sha256"]
        ),
    }

    run_id = _new_run_id(_output_root(semantic_root))
    output_run_directory = _output_root(semantic_root) / run_id
    reservation = _claim_budget(
        semantic_root,
        run_id=run_id,
        model_id=model_id,
        hashes=hashes,
    )
    limiter = CallLimiter(max_calls=APPROVED_CALLS)
    active_compiler = AnthropicSemanticCompiler(
        system_prompt=prompt,
        blueprint_schema=blueprint,
        clarification_schema=clarification,
        call_limiter=limiter,
    )
    results: list[dict[str, Any]] = []

    print(
        f"LIMITED_RETEST_3B_START run_id={run_id} calls={APPROVED_CALLS}",
        flush=True,
    )

    for ordinal, case in enumerate(cases, start=1):
        case_id = case["case_id"]
        player_input = isolated_model_input(case)
        local_request_id = str(uuid.uuid4())
        request_hash = _request_body_sha256(
            prompt=prompt,
            player_input=player_input,
            model_id=model_id,
            blueprint_schema=blueprint,
            clarification_schema=clarification,
        )
        started_at = _utc_now()
        started_clock = time.monotonic()
        calls_before = active_compiler.calls_made
        parsed: Mapping[str, Any] | None = None
        print(
            f"LIMITED_RETEST_3B_CALL case={case_id} ordinal={ordinal}/{APPROVED_CALLS}",
            flush=True,
        )
        _reserve_case_attempt(reservation, run_id, case_id)
        try:
            parsed = active_compiler.compile(player_input)
            calls_after = active_compiler.calls_made
            if calls_after != calls_before + 1:
                raise LimitedRetest3BError("A 3B case did not consume exactly one call slot.")
            completed_at = _utc_now()
            base = _base_record(
                case_id=case_id,
                player_input=player_input,
                local_request_id=local_request_id,
                model_id=model_id,
                request_body_sha256=request_hash,
                hashes=hashes,
                started_at=started_at,
                completed_at=completed_at,
                elapsed_ms=max(0, round((time.monotonic() - started_clock) * 1000)),
                actual_request_performed=True,
            )
            record = _record_from_parsed(parsed=parsed, base=base)
        except Exception as exc:
            calls_after = active_compiler.calls_made
            if calls_after not in {calls_before, calls_before + 1}:
                raise LimitedRetest3BError("A 3B case consumed an invalid call count.") from None
            completed_at = _utc_now()
            base = _base_record(
                case_id=case_id,
                player_input=player_input,
                local_request_id=local_request_id,
                model_id=model_id,
                request_body_sha256=request_hash,
                hashes=hashes,
                started_at=started_at,
                completed_at=completed_at,
                elapsed_ms=max(0, round((time.monotonic() - started_clock) * 1000)),
                actual_request_performed=calls_after == calls_before + 1,
            )
            record = _record_from_error(error=exc, parsed=parsed, base=base)

        _deliver_case(
            semantic_root=semantic_root,
            output_run_directory=output_run_directory,
            case_id=case_id,
            local_request_id=local_request_id,
            model_id=model_id,
            record=record,
        )
        results.append(record)
        _record_observed_calls(
            reservation,
            run_id,
            active_compiler.calls_made,
        )
        print(
            "LIMITED_RETEST_3B_RESULT "
            f"case={case_id} api_status={record.get('api_status')} "
            f"result_type={record.get('result_type')} elapsed_ms={record.get('elapsed_ms')}",
            flush=True,
        )

    actual_call_count = active_compiler.calls_made
    _record_observed_calls(
        reservation,
        run_id,
        actual_call_count,
        status="closed",
    )
    try:
        verify_scope_baseline(
            repository_root,
            semantic_root / "reports" / "gate_a_scope_baseline.json",
        )
    except ScopeGuardError as exc:
        raise LimitedRetest3BError(str(exc)) from exc
    verify_protected_history(repository_root, semantic_root)
    if scan_repository(repository_root):
        raise LimitedRetest3BError(
            "3B calls are preserved, but secret scanning blocked report publication."
        )

    # Evaluation labels are opened only after all six attempts and atomic case
    # deliveries.  They can never enter an Anthropic request.
    scores = evaluate_run(
        output_run_directory,
        semantic_root / "cases" / "limited_retest_3b_expected.json",
    )
    return write_limited_retest_3b_reports(
        semantic_root=semantic_root,
        repository_root=repository_root,
        run_id=run_id,
        model_id=model_id,
        results=results,
        scores=scores,
        output_run_directory=output_run_directory,
        reservation_path=reservation,
        actual_call_count=actual_call_count,
        configuration_hashes=hashes,
        preflight=preflight,
    )


def _parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--preflight-only", action="store_true")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv)
    repository_root = args.repo_root.resolve()
    semantic_root = Path(__file__).resolve().parents[1]
    try:
        if semantic_root.parent.parent != repository_root:
            raise LimitedRetest3BError(
                "--repo-root does not own this tools/semantic implementation."
            )
        if args.preflight_only:
            result = _preflight(
                repository_root, semantic_root, require_unused_budget=True
            )
            print(
                json.dumps(
                    {
                        "status": "LIMITED_RETEST_3B_PREFLIGHT_PASS",
                        "model_id": result["model_id"],
                        "case_order": result["case_order"],
                        "approved_calls": APPROVED_CALLS,
                    },
                    ensure_ascii=False,
                )
            )
            return 0
        summary = execute_limited_retest_3b(
            semantic_root=semantic_root,
            repository_root=repository_root,
        )
        print(
            json.dumps(
                {
                    "run_id": summary["run_id"],
                    "status": summary["status"],
                    "call_count": summary["call_count"],
                    "report_path": str(
                        semantic_root / "reports" / "LIMITED_RETEST_3B_REPORT.md"
                    ),
                },
                ensure_ascii=False,
            )
        )
        return 0 if summary["status"] == "LIMITED RETEST 3B PASS" else 2
    except LimitedRetest3BError as exc:
        print(str(exc), file=sys.stderr)
        return 3
    except Exception:
        print(
            "Limited Retest 3B stopped after an unexpected local failure; no secret was logged.",
            file=sys.stderr,
        )
        return 4
    finally:
        os.environ.pop("ANTHROPIC_API_KEY", None)
        os.environ.pop("FORGE_SEMANTIC_MODEL", None)


if __name__ == "__main__":
    raise SystemExit(main())
