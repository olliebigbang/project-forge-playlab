#!/usr/bin/env python3
"""Exactly-four, non-retried Anthropic runner for Blind Retest 3C.

The paid phase ends by publishing an immutable ``PENDING_HUMAN_REVIEW``
archive.  Final semantic results are published only by the separate offline
review finalizer in :mod:`blind_retest_3c_reporting`.
"""

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
    AnthropicSemanticCompiler,
    CallLimiter,
    SemanticCompilerError,
    build_anthropic_payload,
    redact_sensitive_text,
    require_safe_tls_environment,
)
from atomic_output import atomic_deliver
from blind_retest_3c_evaluator import CASE_ORDER, evaluate_run, load_cases
from blind_retest_3c_reporting import write_pending_blind_retest_3c_review
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


APPROVED_CALLS = 4
FROZEN_MODEL_ID = "claude-sonnet-5"
APPROVED_CONFIG_MANIFEST_SHA256 = "276c32b5663dfffb11f740b1deb8b8bc3ed4e481e15957e29842dc92fafc01a0"
_APPROVAL_CONSTANT_PATTERN = re.compile(
    rb'APPROVED_CONFIG_MANIFEST_SHA256 = "[0-9a-f]{64}"'
)
SOURCE_3B_RUN_ID = "limited-retest-3b-20260803T040934865715Z-79738d1b"
SOURCE_3B_COMPLETE_SHA256 = (
    "5ee00d32fa75e688176c6daed8e8e00289a565d12ed06ac001c8810c68eb67b1"
)
SOURCE_3B_EVIDENCE_SHA256 = (
    "5b1900083853005b3ac8c1059f22a865d05c382bd5489c0621769ad6aff8fa28"
)
SOURCE_3B_RESERVATION_SHA256 = (
    "9ae93429e0e323b67b11bbe87aa90a237362e6033495096f263d970a9578ab37"
)
SOURCE_3B_CONVENIENCE_HASHES = {
    "reports/LIMITED_RETEST_3B_REPORT.md": (
        "a91d19528976f1d59b58b8e0354b39d263323dafdaf3a015e2a798783a15367d"
    ),
    "reports/limited_retest_3b_results.csv": (
        "bd3b114321c04eda403020983670f6f85c28b193ca308950e0ef9179ecac238b"
    ),
    "reports/limited_retest_3b_summary.json": (
        "78492cdf32ed850fe7bebe2bd89b0a88269b5e48e309ca939da5510f241c9553"
    ),
}
RUN_PREFIX = "blind-retest-3c"
_RUN_ID_PATTERN = re.compile(
    r"blind-retest-3c-[0-9]{8}T[0-9]{12}Z-[0-9a-f]{8}"
)
_MODEL_ID_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}")
_SAFE_RELATIVE_PATTERN = re.compile(r"[0-9A-Za-z_./-]+")

# Every byte that can affect a request, local validation, evidence publication,
# or review packet is frozen into the reservation before the first call.  The
# expected file is hashed but is never included in an Anthropic payload.
CONFIGURATION_RELATIVE_PATHS = (
    "bridge/anthropic_semantic_compiler.py",
    "bridge/atomic_output.py",
    "bridge/blind_retest_3c_evaluator.py",
    "bridge/blind_retest_3c_reporting.py",
    "bridge/blind_retest_3c_runner.py",
    "bridge/scope_guard.py",
    "bridge/secret_scan.py",
    "bridge/semantic_contract.py",
    "cases/blind_retest_3c_approved_config.json",
    "cases/blind_retest_3c_cases.json",
    "cases/blind_retest_3c_expected.json",
    "cases/blind_retest_3c_protected_hashes.json",
    "cases/blind_retest_3c_review_rubric.json",
    "prompts/semantic_compiler_system_prompt.md",
    "schema/clarification_request.schema.json",
    "schema/forge_semantic_blueprint.schema.json",
    "scripts/finalize_blind_retest_3c_review.ps1",
    "scripts/invoke_blind_retest_3c_core.ps1",
    "scripts/run_blind_retest_3c.ps1",
    "scripts/run_blind_retest_3c_interactive.ps1",
    "scripts/test_semantic.ps1",
    "scripts/verify_no_secrets.ps1",
    "tests/run_offline_tests.py",
    "tests/test_blind_retest_3c_evaluator.py",
    "tests/test_blind_retest_3c_runner.py",
)
APPROVED_CONFIG_RELATIVE_PATH = "cases/blind_retest_3c_approved_config.json"
APPROVED_FILE_RELATIVE_PATHS = tuple(
    relative
    for relative in CONFIGURATION_RELATIVE_PATHS
    if relative != APPROVED_CONFIG_RELATIVE_PATH
)


class BlindRetest3CError(RuntimeError):
    """Safe local failure that never intentionally contains credentials."""


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


def _canonical_sha256(value: Any) -> str:
    encoded = json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    return _sha256_bytes(encoded.encode("utf-8"))


def _read_json_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise BlindRetest3CError(f"Cannot read required 3C JSON file: {path}") from exc
    if not isinstance(value, dict):
        raise BlindRetest3CError(f"Required 3C JSON file is not an object: {path}")
    return value


def _safe_semantic_path(semantic_root: Path, relative: str) -> Path:
    if not _SAFE_RELATIVE_PATTERN.fullmatch(relative):
        raise BlindRetest3CError("3C manifest contains an invalid relative path.")
    root = semantic_root.resolve()
    raw = root / Path(relative)
    if raw.is_symlink():
        raise BlindRetest3CError("3C evidence/configuration path is a symbolic link.")
    resolved = raw.resolve(strict=False)
    try:
        resolved.relative_to(root)
    except ValueError as exc:
        raise BlindRetest3CError("3C manifest path escapes tools/semantic.") from exc
    return resolved


def _verify_hash_map(semantic_root: Path, files: Mapping[str, Any], label: str) -> None:
    if not files:
        raise BlindRetest3CError(f"{label} has an empty files map.")
    for relative, expected in files.items():
        if (
            not isinstance(relative, str)
            or not isinstance(expected, str)
            or not re.fullmatch(r"[0-9a-f]{64}", expected)
        ):
            raise BlindRetest3CError(f"{label} contains an invalid hash entry.")
        path = _safe_semantic_path(semantic_root, relative)
        if not path.is_file() or _sha256(path) != expected:
            raise BlindRetest3CError(f"{label} hash mismatch: {relative}")


def _approved_file_sha256(path: Path, relative: str) -> str:
    data = path.read_bytes()
    if relative == "bridge/blind_retest_3c_runner.py":
        replacement = (
            b'APPROVED_CONFIG_MANIFEST_SHA256 = "' + b"0" * 64 + b'"'
        )
        data, count = _APPROVAL_CONSTANT_PATTERN.subn(replacement, data)
        if count != 1:
            raise BlindRetest3CError(
                "3C runner approval-constant normalization failed."
            )
    return _sha256_bytes(data)


def verify_approved_configuration(semantic_root: Path) -> dict[str, Any]:
    """Verify the exact pre-approved 3C request, evaluation and evidence code."""

    manifest_path = _safe_semantic_path(
        semantic_root, APPROVED_CONFIG_RELATIVE_PATH
    )
    if not manifest_path.is_file() or manifest_path.is_symlink():
        raise BlindRetest3CError("3C approved-configuration manifest is unavailable.")
    if _sha256(manifest_path) != APPROVED_CONFIG_MANIFEST_SHA256:
        raise BlindRetest3CError(
            "3C approved-configuration manifest digest changed."
        )
    manifest = _read_json_object(manifest_path)
    if (
        set(manifest)
        != {
            "contract_version",
            "algorithm",
            "model_id",
            "case_order",
            "runner_hash_normalization",
            "source_3b_run_id",
            "files",
        }
        or manifest.get("contract_version") != CONTRACT_VERSION
        or manifest.get("algorithm") != "SHA-256"
        or manifest.get("model_id") != FROZEN_MODEL_ID
        or manifest.get("case_order") != list(CASE_ORDER)
        or manifest.get("source_3b_run_id") != SOURCE_3B_RUN_ID
        or manifest.get("runner_hash_normalization")
        != "APPROVED_CONFIG_MANIFEST_SHA256 value replaced by 64 zeroes"
        or not isinstance(manifest.get("files"), Mapping)
        or set(manifest["files"]) != set(APPROVED_FILE_RELATIVE_PATHS)
    ):
        raise BlindRetest3CError("3C approved-configuration manifest is invalid.")
    for relative, expected in manifest["files"].items():
        if (
            not isinstance(relative, str)
            or not isinstance(expected, str)
            or not re.fullmatch(r"[0-9a-f]{64}", expected)
        ):
            raise BlindRetest3CError(
                "3C approved-configuration manifest contains an invalid entry."
            )
        path = _safe_semantic_path(semantic_root, relative)
        if not path.is_file() or _approved_file_sha256(path, relative) != expected:
            raise BlindRetest3CError(
                f"Approved 3C configuration changed: {relative}"
            )
    return {
        "approved_config_manifest_sha256": APPROVED_CONFIG_MANIFEST_SHA256,
        "approved_config_file_count": len(manifest["files"]),
    }


def verify_3c_protected_history_manifest(
    repository_root: Path, semantic_root: Path
) -> dict[str, Any]:
    """Verify the 3C anchor manifest before recursively checking old evidence."""

    manifest_path = semantic_root / "cases" / "blind_retest_3c_protected_hashes.json"
    manifest = _read_json_object(manifest_path)
    if (
        set(manifest)
        != {
            "algorithm",
            "gate_a_source_run_id",
            "gate_a_source_evidence_sha256",
            "limited_retest_3b_run_id",
            "limited_retest_3b_evidence_sha256",
            "files",
        }
        or manifest.get("algorithm") != "SHA-256"
        or manifest.get("gate_a_source_run_id")
        != "gate-a-20260802T232039017356Z-fddde20a"
        or manifest.get("gate_a_source_evidence_sha256")
        != "94a602bdf2d0571cf294287f3d188e830fe7fa968b148e8ca67af3387cd0b347"
        or manifest.get("limited_retest_3b_run_id") != SOURCE_3B_RUN_ID
        or manifest.get("limited_retest_3b_evidence_sha256")
        != SOURCE_3B_EVIDENCE_SHA256
        or not isinstance(manifest.get("files"), Mapping)
        or len(manifest["files"]) != 8
    ):
        raise BlindRetest3CError("3C protected-history manifest is invalid.")
    root = repository_root.resolve()
    for relative, expected in manifest["files"].items():
        if (
            not isinstance(relative, str)
            or not _SAFE_RELATIVE_PATTERN.fullmatch(relative)
            or not isinstance(expected, str)
            or not re.fullmatch(r"[0-9a-f]{64}", expected)
        ):
            raise BlindRetest3CError("3C protected-history entry is invalid.")
        raw = root / Path(relative)
        if raw.is_symlink():
            raise BlindRetest3CError("3C protected-history path is a symbolic link.")
        resolved = raw.resolve(strict=False)
        try:
            resolved.relative_to(root)
        except ValueError as exc:
            raise BlindRetest3CError(
                "3C protected-history path escapes repository."
            ) from exc
        if not resolved.is_file() or _sha256(resolved) != expected:
            raise BlindRetest3CError(
                f"Protected history changed before 3C: {relative}"
            )
    return {
        "protected_history_manifest_sha256": _sha256(manifest_path),
        "protected_history_anchor_count": len(manifest["files"]),
    }


def verify_source_3b(semantic_root: Path) -> dict[str, Any]:
    """Recursively verify the frozen 3B run and its prior 14-file chain."""

    archive = semantic_root / "reports" / "limited_retest_3b" / SOURCE_3B_RUN_ID
    complete_path = archive / "COMPLETE.json"
    evidence_path = archive / "evidence_hashes.json"
    reservation_path = semantic_root / "reports" / "limited_retest_3b_real_call_reservation.json"
    if _sha256(complete_path) != SOURCE_3B_COMPLETE_SHA256:
        raise BlindRetest3CError("Frozen 3B COMPLETE.json changed.")
    if _sha256(evidence_path) != SOURCE_3B_EVIDENCE_SHA256:
        raise BlindRetest3CError("Frozen 3B evidence manifest changed.")
    if _sha256(reservation_path) != SOURCE_3B_RESERVATION_SHA256:
        raise BlindRetest3CError("Frozen 3B reservation changed.")

    complete = _read_json_object(complete_path)
    evidence = _read_json_object(evidence_path)
    reservation = _read_json_object(reservation_path)
    if (
        complete.get("run_id") != SOURCE_3B_RUN_ID
        or complete.get("status") != "complete"
        or complete.get("evidence_sha256") != SOURCE_3B_EVIDENCE_SHA256
        or evidence.get("algorithm") != "SHA-256"
        or evidence.get("run_id") != SOURCE_3B_RUN_ID
        or reservation.get("run_id") != SOURCE_3B_RUN_ID
        or reservation.get("status") != "closed"
        or reservation.get("attempts_reserved") != 6
        or reservation.get("actual_calls_observed") != 6
        or reservation.get("model_id") != FROZEN_MODEL_ID
    ):
        raise BlindRetest3CError("Frozen 3B provenance envelope is invalid.")
    files = evidence.get("files")
    if not isinstance(files, Mapping) or len(files) != 51:
        raise BlindRetest3CError("Frozen 3B evidence must contain exactly 51 entries.")
    _verify_hash_map(semantic_root, files, "Frozen 3B evidence")

    for relative, expected in SOURCE_3B_CONVENIENCE_HASHES.items():
        path = _safe_semantic_path(semantic_root, relative)
        if not path.is_file() or _sha256(path) != expected:
            raise BlindRetest3CError(f"Frozen 3B convenience evidence changed: {relative}")

    protected_path = semantic_root / "cases" / "limited_retest_3b_protected_hashes.json"
    protected = _read_json_object(protected_path)
    protected_files = protected.get("files")
    if not isinstance(protected_files, Mapping) or len(protected_files) != 14:
        raise BlindRetest3CError("Frozen 3B prior-history manifest must contain 14 entries.")
    repository_root = semantic_root.parent.parent
    for relative, expected in protected_files.items():
        if (
            not isinstance(relative, str)
            or not _SAFE_RELATIVE_PATTERN.fullmatch(relative)
            or not isinstance(expected, str)
            or not re.fullmatch(r"[0-9a-f]{64}", expected)
        ):
            raise BlindRetest3CError("Frozen prior-history hash entry is invalid.")
        raw = repository_root / Path(relative)
        if raw.is_symlink():
            raise BlindRetest3CError("Frozen prior-history path is a symbolic link.")
        resolved = raw.resolve(strict=False)
        try:
            resolved.relative_to(repository_root)
        except ValueError as exc:
            raise BlindRetest3CError("Frozen prior-history path escapes repository.") from exc
        if not resolved.is_file() or _sha256(resolved) != expected:
            raise BlindRetest3CError(f"Frozen prior-history evidence changed: {relative}")

    summary = _read_json_object(archive / "limited_retest_3b_summary.json")
    if (
        summary.get("provider") != "anthropic"
        or summary.get("endpoint") != ANTHROPIC_MESSAGES_URL
        or summary.get("model_id") != FROZEN_MODEL_ID
        or summary.get("call_count") != 6
        or summary.get("gate_b_executed") is not False
    ):
        raise BlindRetest3CError("Frozen 3B summary provenance is invalid.")
    return {
        "source_3b_run_id": SOURCE_3B_RUN_ID,
        "source_3b_evidence_sha256": SOURCE_3B_EVIDENCE_SHA256,
        "source_3b_complete_sha256": SOURCE_3B_COMPLETE_SHA256,
        "source_3b_reservation_sha256": SOURCE_3B_RESERVATION_SHA256,
        "source_3b_evidence_file_count": len(files),
        "source_prior_protected_file_count": len(protected_files),
        "model_id": FROZEN_MODEL_ID,
    }


def build_configuration_snapshot(semantic_root: Path) -> dict[str, Any]:
    files: dict[str, str] = {}
    for relative in CONFIGURATION_RELATIVE_PATHS:
        path = _safe_semantic_path(semantic_root, relative)
        if not path.is_file():
            raise BlindRetest3CError(f"Required 3C configuration file is missing: {relative}")
        files[relative] = _sha256(path)
    snapshot = {
        "algorithm": "SHA-256",
        "contract_version": CONTRACT_VERSION,
        "model_id": FROZEN_MODEL_ID,
        "case_order": list(CASE_ORDER),
        "files": dict(sorted(files.items())),
    }
    snapshot["snapshot_sha256"] = _canonical_sha256(snapshot)
    return snapshot


def verify_configuration_snapshot(
    semantic_root: Path, snapshot: Mapping[str, Any]
) -> dict[str, Any]:
    if (
        snapshot.get("algorithm") != "SHA-256"
        or snapshot.get("contract_version") != CONTRACT_VERSION
        or snapshot.get("model_id") != FROZEN_MODEL_ID
        or snapshot.get("case_order") != list(CASE_ORDER)
        or not isinstance(snapshot.get("files"), Mapping)
    ):
        raise BlindRetest3CError("3C frozen configuration snapshot is invalid.")
    payload = {key: value for key, value in snapshot.items() if key != "snapshot_sha256"}
    if snapshot.get("snapshot_sha256") != _canonical_sha256(payload):
        raise BlindRetest3CError("3C configuration snapshot digest is invalid.")
    files = snapshot["files"]
    if set(files) != set(CONFIGURATION_RELATIVE_PATHS):
        raise BlindRetest3CError("3C configuration snapshot file set changed.")
    _verify_hash_map(semantic_root, files, "Frozen 3C configuration")
    return dict(snapshot)


def _read_system_prompt(path: Path) -> str:
    try:
        value = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise BlindRetest3CError("Cannot read the v1.1 system prompt.") from exc
    if not value.strip():
        raise BlindRetest3CError("The v1.1 system prompt is empty.")
    return value


def _configuration(
    semantic_root: Path,
) -> tuple[str, dict[str, Any], dict[str, Any], list[dict[str, str]], dict[str, str]]:
    prompt_path = semantic_root / "prompts" / "semantic_compiler_system_prompt.md"
    blueprint_path = semantic_root / "schema" / "forge_semantic_blueprint.schema.json"
    clarification_path = semantic_root / "schema" / "clarification_request.schema.json"
    cases_path = semantic_root / "cases" / "blind_retest_3c_cases.json"
    expected_path = semantic_root / "cases" / "blind_retest_3c_expected.json"
    rubric_path = semantic_root / "cases" / "blind_retest_3c_review_rubric.json"
    protected_path = semantic_root / "cases" / "blind_retest_3c_protected_hashes.json"
    prompt = _read_system_prompt(prompt_path)
    blueprint = _read_json_object(blueprint_path)
    clarification = _read_json_object(clarification_path)
    if blueprint != FORGE_SEMANTIC_BLUEPRINT_SCHEMA:
        raise BlindRetest3CError("Live v1.1 Blueprint Schema parity failed.")
    if clarification != CLARIFICATION_REQUEST_SCHEMA:
        raise BlindRetest3CError("Live v1.1 clarification Schema parity failed.")
    cases = load_cases(cases_path)
    if [case.get("case_id") for case in cases] != list(CASE_ORDER):
        raise BlindRetest3CError("3C cases differ from the frozen four-case order.")
    for case in cases:
        if set(case) != {"case_id", "input_text"}:
            raise BlindRetest3CError("A 3C model-visible case contains an extra field.")
        if not isinstance(case.get("input_text"), str) or not case["input_text"].strip():
            raise BlindRetest3CError("A 3C model-visible case has no input_text.")
    if len({case["input_text"] for case in cases}) != APPROVED_CALLS:
        raise BlindRetest3CError("3C blind inputs must be four distinct strings.")
    prior_cases = _read_json_object(
        semantic_root / "cases" / "gate_a_cases.json"
    ).get("cases")
    if not isinstance(prior_cases, list):
        raise BlindRetest3CError("Frozen Gate A case corpus is unavailable.")
    prior_inputs = {
        item.get("input_text")
        for item in prior_cases
        if isinstance(item, Mapping) and isinstance(item.get("input_text"), str)
    }
    if any(case["input_text"] in prior_inputs for case in cases):
        raise BlindRetest3CError("A 3C input is not blind; it appeared in Gate A.")
    hashes = {
        "system_prompt_sha256": _sha256(prompt_path),
        "blueprint_schema_sha256": _sha256(blueprint_path),
        "clarification_schema_sha256": _sha256(clarification_path),
        "blind_cases_sha256": _sha256(cases_path),
        # Hash only. Expected labels are parsed after all four atomic deliveries.
        "blind_expected_sha256": _sha256(expected_path),
        # Hash only. The rubric is parsed only during post-call evaluation/review.
        "blind_review_rubric_sha256": _sha256(rubric_path),
        "protected_history_manifest_sha256": _sha256(protected_path),
    }
    hashes["blind_definition_sha256"] = _canonical_sha256(
        {
            "cases": hashes["blind_cases_sha256"],
            "expected": hashes["blind_expected_sha256"],
            "review_rubric": hashes["blind_review_rubric_sha256"],
        }
    )
    return prompt, blueprint, clarification, cases, hashes


def _reservation_path(semantic_root: Path) -> Path:
    return semantic_root / "reports" / "blind_retest_3c_real_call_reservation.json"


def _output_root(semantic_root: Path) -> Path:
    return semantic_root / "output" / "blind_retest_3c"


def _pending_root(semantic_root: Path) -> Path:
    return semantic_root / "reports" / "blind_retest_3c_pending"


def _final_root(semantic_root: Path) -> Path:
    return semantic_root / "reports" / "blind_retest_3c"


def _ensure_no_prior_3c(semantic_root: Path) -> None:
    conflicts = [_reservation_path(semantic_root)]
    if any(path.exists() for path in conflicts):
        raise BlindRetest3CError(
            "Blind Retest 3C already has a call reservation; it cannot be reset."
        )
    for directory in (_output_root(semantic_root), _pending_root(semantic_root), _final_root(semantic_root)):
        if directory.exists() and any(directory.iterdir()):
            raise BlindRetest3CError(
                "Blind Retest 3C evidence already exists; no second paid run is allowed."
            )


def _preflight(
    repository_root: Path, semantic_root: Path, *, require_unused_budget: bool
) -> dict[str, Any]:
    if scan_repository(repository_root):
        raise BlindRetest3CError("3C stopped because the repository secret scan failed.")
    try:
        protected_scope = verify_scope_baseline(
            repository_root,
            semantic_root / "reports" / "gate_a_scope_baseline.json",
        )
    except ScopeGuardError as exc:
        raise BlindRetest3CError(str(exc)) from exc
    protected_history = verify_3c_protected_history_manifest(
        repository_root, semantic_root
    )
    source = verify_source_3b(semantic_root)
    approved = verify_approved_configuration(semantic_root)
    _, _, _, cases, hashes = _configuration(semantic_root)
    snapshot = build_configuration_snapshot(semantic_root)
    if snapshot["files"]["cases/blind_retest_3c_expected.json"] != hashes[
        "blind_expected_sha256"
    ]:
        raise BlindRetest3CError("3C expected hash differs inside the pre-call snapshot.")
    if snapshot["files"]["cases/blind_retest_3c_review_rubric.json"] != hashes[
        "blind_review_rubric_sha256"
    ]:
        raise BlindRetest3CError("3C review rubric differs inside the pre-call snapshot.")
    if snapshot["files"]["cases/blind_retest_3c_protected_hashes.json"] != hashes[
        "protected_history_manifest_sha256"
    ]:
        raise BlindRetest3CError("3C protected history differs inside the snapshot.")
    if snapshot["files"][APPROVED_CONFIG_RELATIVE_PATH] != approved[
        "approved_config_manifest_sha256"
    ]:
        raise BlindRetest3CError("3C approved manifest differs inside the snapshot.")
    if require_unused_budget:
        _ensure_no_prior_3c(semantic_root)
    return {
        **source,
        **protected_history,
        **approved,
        "contract_version": CONTRACT_VERSION,
        "case_order": list(CASE_ORDER),
        "case_count": len(cases),
        "configuration_hashes": hashes,
        "configuration_snapshot": snapshot,
        "protected_scope": protected_scope,
        "ready": True,
    }


def require_environment(expected_model_id: str) -> str:
    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    model_id = os.environ.get("FORGE_SEMANTIC_MODEL", "")
    if not api_key.strip():
        raise BlindRetest3CError(
            "3C stopped: ANTHROPIC_API_KEY is missing. Use the interactive script."
        )
    if (
        not model_id
        or model_id != model_id.strip()
        or not _MODEL_ID_PATTERN.fullmatch(model_id)
        or model_id != expected_model_id
        or model_id != FROZEN_MODEL_ID
    ):
        raise BlindRetest3CError(
            "3C stopped: FORGE_SEMANTIC_MODEL does not exactly match the frozen 3B model."
        )
    if model_id == api_key or redact_sensitive_text(model_id) != model_id:
        raise BlindRetest3CError("3C stopped: model ID resembles credential material.")
    return model_id


def _new_run_id(output_root: Path) -> str:
    for _ in range(16):
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        candidate = f"{RUN_PREFIX}-{timestamp}-{uuid.uuid4().hex[:8]}"
        if _RUN_ID_PATTERN.fullmatch(candidate) and not (output_root / candidate).exists():
            return candidate
    raise BlindRetest3CError("Could not allocate a unique 3C run_id.")


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
    configuration_snapshot: Mapping[str, Any],
) -> Path:
    path = _reservation_path(semantic_root)
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "run_id": run_id,
        "contract_version": CONTRACT_VERSION,
        "source_3b_run_id": SOURCE_3B_RUN_ID,
        "source_3b_evidence_sha256": SOURCE_3B_EVIDENCE_SHA256,
        "model_id": model_id,
        "endpoint": ANTHROPIC_MESSAGES_URL,
        "case_order": list(CASE_ORDER),
        "configuration_hashes": dict(hashes),
        "configuration_snapshot": copy.deepcopy(dict(configuration_snapshot)),
        "expected_sha256": hashes.get("blind_expected_sha256"),
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
        raise BlindRetest3CError(
            "The 3C four-call budget is already reserved; no reset is allowed."
        ) from exc
    with os.fdopen(descriptor, "wb") as handle:
        handle.write(encoded)
        handle.flush()
        os.fsync(handle.fileno())
    return path


def _read_reservation(path: Path, run_id: str) -> dict[str, Any]:
    value = _read_json_object(path)
    attempts = value.get("attempts_reserved")
    actual = value.get("actual_calls_observed")
    attempted_ids = value.get("attempted_case_ids")
    if (
        value.get("run_id") != run_id
        or value.get("contract_version") != CONTRACT_VERSION
        or value.get("source_3b_run_id") != SOURCE_3B_RUN_ID
        or value.get("source_3b_evidence_sha256") != SOURCE_3B_EVIDENCE_SHA256
        or value.get("model_id") != FROZEN_MODEL_ID
        or value.get("endpoint") != ANTHROPIC_MESSAGES_URL
        or value.get("max_real_calls") != APPROVED_CALLS
        or value.get("case_order") != list(CASE_ORDER)
        or isinstance(attempts, bool)
        or not isinstance(attempts, int)
        or not 0 <= attempts <= APPROVED_CALLS
        or isinstance(actual, bool)
        or not isinstance(actual, int)
        or not 0 <= actual <= APPROVED_CALLS
        or not isinstance(attempted_ids, list)
        or attempted_ids != list(CASE_ORDER[:attempts])
        or not isinstance(value.get("configuration_snapshot"), Mapping)
        or value.get("expected_sha256")
        != value.get("configuration_hashes", {}).get("blind_expected_sha256")
    ):
        raise BlindRetest3CError("The persistent 3C call reservation is invalid.")
    return value


def _reserve_case_attempt(path: Path, run_id: str, case_id: str) -> None:
    value = _read_reservation(path, run_id)
    attempts = int(value["attempts_reserved"])
    if attempts >= APPROVED_CALLS or case_id != CASE_ORDER[attempts]:
        raise BlindRetest3CError("A 3C case would be duplicated or attempted out of order.")
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
        raise BlindRetest3CError("Observed 3C call count is invalid.")
    if observed > int(value["attempts_reserved"]):
        raise BlindRetest3CError("Observed calls exceed reserved 3C attempts.")
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
    body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
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
        result[field] = item if isinstance(item, int) and not isinstance(item, bool) and item >= 0 else 0
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
        raise BlindRetest3CError("Parsed tool input is not an object.")
    tool_input = copy.deepcopy(dict(source_input))
    serialized = json.dumps(tool_input, ensure_ascii=False, separators=(",", ":"))
    if redact_sensitive_text(serialized) != serialized:
        raise BlindRetest3CError("Tool input contained credential-shaped material.")
    root = _root_attestation(tool_name, tool_input)
    snapshot = copy.deepcopy(tool_input)
    try:
        returned = validate_tool_input(tool_name, tool_input)
        if returned is not tool_input or tool_input != snapshot:
            raise BlindRetest3CError("The live validator mutated or replaced tool input.")
        validation: dict[str, Any] = {
            "stage": "complete",
            "schema_valid": True,
            "cross_field_valid": True,
            "issues": [],
            "repaired": False,
            "unwrapped": False,
            "coerced": False,
            "defaulted": False,
        }
        result: dict[str, Any] | None = tool_input
        result_type = "compiled" if tool_name == SUBMIT_BLUEPRINT_TOOL else "needs_clarification"
        failure_reason = ""
    except ContractValidationError as exc:
        if tool_input != snapshot:
            raise BlindRetest3CError("The live validator mutated rejected tool input.")
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
    *, error: BaseException, parsed: Mapping[str, Any] | None, base: Mapping[str, Any]
) -> dict[str, Any]:
    api_status: int | str = "unavailable"
    raw = ""
    code = "LOCAL_FAILURE"
    if isinstance(error, SemanticCompilerError):
        api_status = error.http_status if error.http_status is not None else "unavailable"
        raw = redact_sensitive_text(error.raw_response_redacted)
        code = error.code
    elif isinstance(error, BlindRetest3CError):
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
        raise BlindRetest3CError("A staged 3C result contained credential-shaped material.")
    with path.open("x", encoding="utf-8", newline="\n") as handle:
        handle.write(encoded)
        handle.flush()
        os.fsync(handle.fileno())


def _validate_staged_record(
    directory: Path, *, case_id: str, local_request_id: str, model_id: str
) -> bool:
    entries = list(directory.iterdir())
    if len(entries) != 1 or entries[0].name != "result.json":
        raise BlindRetest3CError("A staged 3C case must contain exactly result.json.")
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
        raise BlindRetest3CError("Staged 3C result envelope mismatch.")
    if value.get("result_type") not in {"compiled", "needs_clarification", "failed"}:
        raise BlindRetest3CError("Staged 3C result_type is invalid.")
    if value.get("result_type") != "failed":
        if value.get("result") != value.get("tool_input_received"):
            raise BlindRetest3CError("Staged 3C result differs from exact tool input.")
        validate_tool_input(str(value.get("tool_name", "")), value.get("result"))
        validation = value.get("validation")
        if not isinstance(validation, Mapping) or any(
            (
                validation.get("schema_valid") is not True,
                validation.get("cross_field_valid") is not True,
                validation.get("repaired") is not False,
                validation.get("unwrapped") is not False,
                validation.get("coerced") is not False,
                validation.get("defaulted") is not False,
            )
        ):
            raise BlindRetest3CError("Successful staged 3C result lacks strict validation attestation.")
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
        semantic_root / ".tmp" / "blind_retest_3c" / output_run_directory.name / local_request_id
    )
    final_case = output_run_directory / case_id
    if temp_case.exists():
        raise BlindRetest3CError("Temporary 3C request directory already exists.")
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


def execute_blind_retest_3c(
    *, semantic_root: Path, repository_root: Path, compiler: SemanticCompilerLike | None = None
) -> dict[str, Any]:
    """Attempt the four frozen blind cases exactly once and stop for review."""

    if compiler is not None:
        raise BlindRetest3CError(
            "The production 3C entry point does not accept a substitute compiler."
        )
    semantic_root = semantic_root.resolve()
    repository_root = repository_root.resolve()
    if semantic_root.parent.parent != repository_root:
        raise BlindRetest3CError("Repository root does not own this semantic implementation.")
    try:
        require_safe_tls_environment()
    except SemanticCompilerError as exc:
        raise BlindRetest3CError(str(exc)) from None
    preflight = _preflight(repository_root, semantic_root, require_unused_budget=True)
    model_id = require_environment(str(preflight["model_id"]))
    prompt, blueprint, clarification, cases, hashes = _configuration(semantic_root)
    snapshot = verify_configuration_snapshot(
        semantic_root, preflight["configuration_snapshot"]
    )
    hashes = {**hashes, "configuration_snapshot_sha256": str(snapshot["snapshot_sha256"])}

    run_id = _new_run_id(_output_root(semantic_root))
    output_run_directory = _output_root(semantic_root) / run_id
    reservation = _claim_budget(
        semantic_root,
        run_id=run_id,
        model_id=model_id,
        hashes=hashes,
        configuration_snapshot=snapshot,
    )
    limiter = CallLimiter(max_calls=APPROVED_CALLS)
    active_compiler = AnthropicSemanticCompiler(
        system_prompt=prompt,
        blueprint_schema=blueprint,
        clarification_schema=clarification,
        call_limiter=limiter,
    )
    results: list[dict[str, Any]] = []
    print(f"BLIND_RETEST_3C_START run_id={run_id} calls={APPROVED_CALLS}", flush=True)

    for ordinal, case in enumerate(cases, start=1):
        case_id = str(case["case_id"])
        player_input = str(case["input_text"])
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
            f"BLIND_RETEST_3C_CALL case={case_id} ordinal={ordinal}/{APPROVED_CALLS}",
            flush=True,
        )
        _reserve_case_attempt(reservation, run_id, case_id)
        try:
            parsed = active_compiler.compile(player_input)
            calls_after = active_compiler.calls_made
            if calls_after != calls_before + 1:
                raise BlindRetest3CError("A 3C case did not consume exactly one call slot.")
            base = _base_record(
                case_id=case_id,
                player_input=player_input,
                local_request_id=local_request_id,
                model_id=model_id,
                request_body_sha256=request_hash,
                hashes=hashes,
                started_at=started_at,
                completed_at=_utc_now(),
                elapsed_ms=max(0, round((time.monotonic() - started_clock) * 1000)),
                actual_request_performed=True,
            )
            record = _record_from_parsed(parsed=parsed, base=base)
        except Exception as exc:
            calls_after = active_compiler.calls_made
            if calls_after not in {calls_before, calls_before + 1}:
                raise BlindRetest3CError("A 3C case consumed an invalid call count.") from None
            base = _base_record(
                case_id=case_id,
                player_input=player_input,
                local_request_id=local_request_id,
                model_id=model_id,
                request_body_sha256=request_hash,
                hashes=hashes,
                started_at=started_at,
                completed_at=_utc_now(),
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
        _record_observed_calls(reservation, run_id, active_compiler.calls_made)
        print(
            "BLIND_RETEST_3C_RESULT "
            f"case={case_id} api_status={record.get('api_status')} "
            f"result_type={record.get('result_type')} elapsed_ms={record.get('elapsed_ms')}",
            flush=True,
        )

    actual_call_count = active_compiler.calls_made
    _record_observed_calls(
        reservation,
        run_id,
        actual_call_count,
        status="closed_pending_human_review",
    )
    try:
        verify_scope_baseline(
            repository_root,
            semantic_root / "reports" / "gate_a_scope_baseline.json",
        )
    except ScopeGuardError as exc:
        raise BlindRetest3CError(str(exc)) from exc
    verify_3c_protected_history_manifest(repository_root, semantic_root)
    verify_source_3b(semantic_root)
    verify_approved_configuration(semantic_root)
    verify_configuration_snapshot(semantic_root, snapshot)
    if _sha256(semantic_root / "cases" / "blind_retest_3c_expected.json") != hashes[
        "blind_expected_sha256"
    ]:
        raise BlindRetest3CError("3C expected labels changed after the calls.")
    if _sha256(
        semantic_root / "cases" / "blind_retest_3c_review_rubric.json"
    ) != hashes["blind_review_rubric_sha256"]:
        raise BlindRetest3CError("3C review rubric changed after the calls.")
    if scan_repository(repository_root):
        raise BlindRetest3CError(
            "3C calls are preserved, but secret scanning blocked pending publication."
        )

    # Expected labels are first parsed only after every attempt has an atomic
    # result directory. They are never passed to build_anthropic_payload.
    scores = evaluate_run(
        output_run_directory,
        semantic_root / "cases" / "blind_retest_3c_expected.json",
    )
    return write_pending_blind_retest_3c_review(
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
        configuration_snapshot=snapshot,
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
            raise BlindRetest3CError(
                "--repo-root does not own this tools/semantic implementation."
            )
        if args.preflight_only:
            result = _preflight(
                repository_root, semantic_root, require_unused_budget=True
            )
            print(
                json.dumps(
                    {
                        "status": "BLIND_RETEST_3C_PREFLIGHT_PASS",
                        "model_id": result["model_id"],
                        "case_order": result["case_order"],
                        "approved_calls": APPROVED_CALLS,
                        "approved_config_manifest_sha256": result[
                            "approved_config_manifest_sha256"
                        ],
                        "blind_definition_sha256": result[
                            "configuration_hashes"
                        ]["blind_definition_sha256"],
                        "configuration_snapshot_sha256": result[
                            "configuration_snapshot"
                        ]["snapshot_sha256"],
                    },
                    ensure_ascii=False,
                )
            )
            return 0
        summary = execute_blind_retest_3c(
            semantic_root=semantic_root,
            repository_root=repository_root,
        )
        print(json.dumps(summary, ensure_ascii=False))
        return 0 if summary.get("status") == "PENDING_HUMAN_REVIEW" else 2
    except BlindRetest3CError as exc:
        print(str(exc), file=sys.stderr)
        return 3
    except Exception:
        print(
            "Blind Retest 3C stopped after an unexpected local failure; no secret was logged.",
            file=sys.stderr,
        )
        return 4
    finally:
        os.environ.pop("ANTHROPIC_API_KEY", None)
        os.environ.pop("FORGE_SEMANTIC_MODEL", None)


if __name__ == "__main__":
    raise SystemExit(main())
