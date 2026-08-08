#!/usr/bin/env python3
"""Four-case targeted retest runner with corrected evidence separation.

No real call is made unless the explicit execution switch and process-only
credentials are both supplied. Preflight and tests are fully offline.
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
from typing import Any, Mapping, Sequence

from affordance_contract_v1_2 import AffordanceContractError
from affordance_contract_v1_2_1 import (
    CONTRACT_VERSION,
    candidate_tool_schema_v1_2_1,
    validate_candidate_blueprint_v1_2_1,
)
from anthropic_semantic_compiler import (
    ANTHROPIC_MESSAGES_URL,
    AnthropicSemanticCompiler,
    CallLimiter,
    SemanticCompilerError,
    build_anthropic_payload,
    redact_sensitive_text,
    require_safe_tls_environment,
)
from secret_scan import scan_repository
from semantic_contract import (
    CLARIFICATION_REQUEST_SCHEMA,
    ContractValidationError,
    SUBMIT_BLUEPRINT_TOOL,
)


APPROVED_CALLS = 4
CASE_ORDER = ("A03", "A07", "A08", "A09")
FROZEN_MODEL_ID = "claude-sonnet-5"
SOURCE_RUN_ID = "affordance-retest-v1-2-20260808T074610104680Z-70b603d7"
SOURCE_EVIDENCE_SHA256 = "fa76d8bc4f3c78ce4a9eb29c4a8baeade03e5297acefa4a0bf45fb8f1ff06324"
RUN_PREFIX = "affordance-targeted-v1-2-1"
_MODEL_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}")


class TargetedRetestError(RuntimeError):
    pass


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise TargetedRetestError(f"Cannot read required JSON: {path}") from exc


def _atomic_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    data = json.dumps(value, ensure_ascii=False, indent=2).encode("utf-8") + b"\n"
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def _source_run_directory(semantic_root: Path) -> Path:
    return semantic_root / "reports" / "affordance_retest_v1_2" / SOURCE_RUN_ID


def _verify_source_evidence(semantic_root: Path) -> dict[str, Any]:
    run = _source_run_directory(semantic_root)
    evidence_path = run / "evidence_hashes.json"
    complete_path = run / "COMPLETE.json"
    if _sha256(evidence_path) != SOURCE_EVIDENCE_SHA256:
        raise TargetedRetestError("Frozen v1.2 evidence manifest changed.")
    evidence = _read_json(evidence_path)
    complete = _read_json(complete_path)
    if (
        not isinstance(evidence, dict)
        or evidence.get("run_id") != SOURCE_RUN_ID
        or not isinstance(evidence.get("files"), dict)
        or not isinstance(complete, dict)
        or complete.get("evidence_sha256") != SOURCE_EVIDENCE_SHA256
    ):
        raise TargetedRetestError("Frozen v1.2 completion envelope is invalid.")
    for relative, expected in evidence["files"].items():
        path = run / relative
        if not path.is_file() or _sha256(path) != expected:
            raise TargetedRetestError(f"Frozen v1.2 evidence changed: {relative}")
    return {"source_run_id": SOURCE_RUN_ID, "source_evidence_sha256": SOURCE_EVIDENCE_SHA256, "source_file_count": len(evidence["files"])}


def _configuration(semantic_root: Path) -> tuple[str, dict[str, Any], list[dict[str, str]], dict[str, str]]:
    manifest_path = semantic_root / "cases" / "affordance_targeted_4_v1_2_1.json"
    manifest = _read_json(manifest_path)
    corpus_path = semantic_root / "cases" / "affordance_blind_12_candidate.json"
    corpus = _read_json(corpus_path)
    if not isinstance(manifest, dict) or manifest.get("case_order") != list(CASE_ORDER):
        raise TargetedRetestError("Targeted four-case freeze is invalid.")
    if manifest.get("source_run_id") != SOURCE_RUN_ID or manifest.get("source_evidence_sha256") != SOURCE_EVIDENCE_SHA256:
        raise TargetedRetestError("Targeted freeze does not bind the source run.")
    definitions = {item["case_id"]: item for item in corpus.get("cases", []) if isinstance(item, dict)}
    cases: list[dict[str, str]] = []
    source_run = _source_run_directory(semantic_root)
    for entry in manifest.get("cases", []):
        if not isinstance(entry, dict) or entry.get("case_id") not in CASE_ORDER:
            raise TargetedRetestError("Targeted case entry is invalid.")
        case_id = entry["case_id"]
        source_result = source_run / "cases" / case_id / "result.json"
        if _sha256(source_result) != entry.get("source_result_sha256"):
            raise TargetedRetestError(f"Frozen source result changed for {case_id}.")
        definition = definitions.get(case_id)
        if not isinstance(definition, dict):
            raise TargetedRetestError(f"Frozen model input is missing for {case_id}.")
        player_input = definition.get("prompt_zh")
        if not isinstance(player_input, str) or _sha256_bytes(player_input.encode("utf-8")) != entry.get("input_sha256"):
            raise TargetedRetestError(f"Frozen input digest changed for {case_id}.")
        cases.append({"case_id": case_id, "input_text": player_input})
    if [item["case_id"] for item in cases] != list(CASE_ORDER):
        raise TargetedRetestError("Targeted cases are out of order.")
    base_prompt_path = semantic_root / "prompts" / "semantic_compiler_system_prompt.md"
    affordance_prompt_path = semantic_root / "prompts" / "affordance_v1_2_candidate_addendum.md"
    correction_prompt_path = semantic_root / "prompts" / "affordance_v1_2_1_candidate_addendum.md"
    prompt = "\n\n".join(
        path.read_text(encoding="utf-8").strip()
        for path in (base_prompt_path, affordance_prompt_path, correction_prompt_path)
    ) + "\n"
    schema = candidate_tool_schema_v1_2_1()
    hashes = {
        "targeted_cases_sha256": _sha256(manifest_path),
        "source_cases_sha256": _sha256(corpus_path),
        "base_prompt_sha256": _sha256(base_prompt_path),
        "affordance_prompt_sha256": _sha256(affordance_prompt_path),
        "correction_prompt_sha256": _sha256(correction_prompt_path),
        "combined_prompt_sha256": _sha256_bytes(prompt.encode("utf-8")),
        "tool_schema_sha256": _sha256_bytes(json.dumps(schema, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")),
    }
    return prompt, schema, cases, hashes


def _reservation_path(semantic_root: Path) -> Path:
    return semantic_root / "reports" / "affordance_targeted_v1_2_1_real_call_reservation.json"


def _report_root(semantic_root: Path) -> Path:
    return semantic_root / "reports" / "affordance_targeted_v1_2_1"


def preflight(repository_root: Path, semantic_root: Path, *, require_unused: bool = True) -> dict[str, Any]:
    if repository_root.resolve() != semantic_root.parent.parent.resolve():
        raise TargetedRetestError("Repository root does not own the semantic implementation.")
    if scan_repository(repository_root):
        raise TargetedRetestError("Repository secret scan failed.")
    source = _verify_source_evidence(semantic_root)
    _, _, cases, hashes = _configuration(semantic_root)
    if require_unused:
        reports = _report_root(semantic_root)
        if _reservation_path(semantic_root).exists() or (reports.exists() and any(reports.iterdir())):
            raise TargetedRetestError("Targeted paid-call evidence already exists.")
    return {
        "status": "AFFORDANCE_TARGETED_V1_2_1_PREFLIGHT_PASS",
        "real_calls_authorized_by_preflight": False,
        "requires_explicit_execution_switch_and_user_approval": True,
        "model_id": FROZEN_MODEL_ID,
        "case_order": list(CASE_ORDER),
        "case_count": len(cases),
        "max_real_calls": APPROVED_CALLS,
        "retry_count": 0,
        "configuration_hashes": hashes,
        **source,
    }


def _base_record(case_id: str, local_request_id: str, request_hash: str) -> dict[str, Any]:
    return {
        "case_id": case_id,
        "contract_version": CONTRACT_VERSION,
        "provider": "anthropic",
        "endpoint": ANTHROPIC_MESSAGES_URL,
        "model_id": FROZEN_MODEL_ID,
        "local_request_id": local_request_id,
        "request_body_sha256": request_hash,
        "retry_count": 0,
        "repair_applied": False,
        "unwrap_applied": False,
        "coercion_applied": False,
        "defaults_applied": False,
    }


def record_from_parsed(parsed: Mapping[str, Any], base: Mapping[str, Any]) -> tuple[dict[str, Any], str]:
    """Record API success before candidate validation, including rejections."""

    record = copy.deepcopy(dict(base))
    tool_input = parsed.get("tool_input")
    raw = redact_sensitive_text(parsed.get("raw_response_redacted", ""))
    record.update(
        {
            "api_status": 200,
            "api_success": True,
            "request_id": parsed.get("request_id"),
            "response_model_id": parsed.get("model_id"),
            "tool_name": parsed.get("tool_name"),
            "tool_input_received": copy.deepcopy(tool_input),
            "exactly_one_legal_tool_use": True,
            "sole_content_is_tool_use": True,
            "usage": copy.deepcopy(parsed.get("usage", {})),
            "stop_reason": parsed.get("stop_reason"),
        }
    )
    if parsed.get("tool_name") != SUBMIT_BLUEPRINT_TOOL or not isinstance(tool_input, dict):
        record.update({"status": "FAILED", "validation_stage": "tool_dispatch", "failure_reason": "EXPECTED_BLUEPRINT_TOOL", "schema_valid": False, "cross_field_valid": False})
        return record, raw
    snapshot = copy.deepcopy(tool_input)
    try:
        returned = validate_candidate_blueprint_v1_2_1(tool_input)
        if returned is not tool_input or tool_input != snapshot:
            raise TargetedRetestError("Candidate validator mutated or replaced tool input.")
        record.update({"status": "VALID", "validation_stage": "complete", "failure_reason": "", "schema_valid": True, "cross_field_valid": True, "validated_blueprint": copy.deepcopy(tool_input)})
    except ContractValidationError as exc:
        record.update({
            "status": "FAILED", "validation_stage": exc.stage,
            "failure_reason": str(exc), "schema_valid": exc.stage != "schema",
            "cross_field_valid": False,
            "validation_issues": [{"json_pointer": issue.json_pointer, "path": issue.path, "rule": issue.message} for issue in exc.issues],
        })
    except AffordanceContractError as exc:
        record.update({"status": "FAILED", "validation_stage": "affordance", "failure_reason": str(exc), "schema_valid": False, "cross_field_valid": False})
    if tool_input != snapshot:
        raise TargetedRetestError("Candidate validation mutated rejected input.")
    return record, raw


def _record_transport_error(error: BaseException, base: Mapping[str, Any]) -> tuple[dict[str, Any], str]:
    record = copy.deepcopy(dict(base))
    code = error.code if isinstance(error, SemanticCompilerError) else "LOCAL_FAILURE"
    raw = redact_sensitive_text(error.raw_response_redacted) if isinstance(error, SemanticCompilerError) else ""
    record.update({
        "api_status": error.http_status if isinstance(error, SemanticCompilerError) else None,
        "api_success": False, "request_id": None, "response_model_id": None,
        "tool_name": None, "tool_input_received": None,
        "exactly_one_legal_tool_use": False, "sole_content_is_tool_use": False,
        "status": "FAILED", "validation_stage": "transport_or_parser",
        "failure_reason": f"{code}: {redact_sensitive_text(str(error))[:1000]}",
        "schema_valid": None, "cross_field_valid": None, "usage": {}, "stop_reason": None,
    })
    return record, raw


def _require_environment() -> None:
    key = os.environ.get("ANTHROPIC_API_KEY", "")
    model = os.environ.get("FORGE_SEMANTIC_MODEL", "")
    if not key.strip():
        raise TargetedRetestError("ANTHROPIC_API_KEY is missing from this process.")
    if model != FROZEN_MODEL_ID or not _MODEL_PATTERN.fullmatch(model):
        raise TargetedRetestError("FORGE_SEMANTIC_MODEL does not match the frozen model.")


def _request_hash(prompt: str, player_input: str, schema: Mapping[str, Any]) -> str:
    payload = build_anthropic_payload(prompt, player_input, FROZEN_MODEL_ID, schema, CLARIFICATION_REQUEST_SCHEMA)
    return _sha256_bytes(json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8"))


def execute_approved(repository_root: Path, semantic_root: Path) -> dict[str, Any]:
    require_safe_tls_environment()
    preflight(repository_root, semantic_root, require_unused=True)
    _require_environment()
    prompt, schema, cases, hashes = _configuration(semantic_root)
    run_id = f"{RUN_PREFIX}-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')}-{uuid.uuid4().hex[:8]}"
    run_directory = _report_root(semantic_root) / run_id
    run_directory.mkdir(parents=True, exist_ok=False)
    _atomic_json(run_directory / "case_order.json", list(CASE_ORDER))
    _atomic_json(run_directory / "configuration_snapshot.json", hashes)
    reservation = _reservation_path(semantic_root)
    _atomic_json(reservation, {
        "run_id": run_id, "contract_version": CONTRACT_VERSION, "model_id": FROZEN_MODEL_ID,
        "case_order": list(CASE_ORDER), "max_real_calls": APPROVED_CALLS,
        "attempts_reserved": 0, "actual_calls_observed": 0, "retry_count": 0,
        "status": "reserved", "configuration_hashes": hashes, "created_at": _utc_now(),
    })
    compiler = AnthropicSemanticCompiler(system_prompt=prompt, blueprint_schema=schema, clarification_schema=CLARIFICATION_REQUEST_SCHEMA, call_limiter=CallLimiter(APPROVED_CALLS))
    records: list[dict[str, Any]] = []
    for ordinal, case in enumerate(cases, 1):
        reservation_value = _read_json(reservation)
        reservation_value.update({"attempts_reserved": ordinal, "attempted_case_ids": list(CASE_ORDER[:ordinal]), "status": "in_progress", "updated_at": _utc_now()})
        _atomic_json(reservation, reservation_value)
        local_request_id = str(uuid.uuid4())
        base = _base_record(case["case_id"], local_request_id, _request_hash(prompt, case["input_text"], schema))
        started = time.monotonic()
        calls_before = compiler.calls_made
        try:
            parsed = compiler.compile(case["input_text"])
            record, raw = record_from_parsed(parsed, base)
        except Exception as exc:
            record, raw = _record_transport_error(exc, base)
        if compiler.calls_made not in {calls_before, calls_before + 1}:
            raise TargetedRetestError("A case consumed an invalid call count.")
        record["ordinal"] = ordinal
        record["elapsed_ms"] = max(0, round((time.monotonic() - started) * 1000))
        _atomic_json(run_directory / "cases" / case["case_id"] / "result.json", record)
        try:
            raw_value: Any = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            raw_value = raw
        _atomic_json(run_directory / "raw_response_redacted" / f"{case['case_id']}.json", {"case_id": case["case_id"], "response": raw_value})
        _atomic_json(
            run_directory / "request_manifests" / f"{case['case_id']}.json",
            {
                "case_id": case["case_id"], "ordinal": ordinal,
                "contract_version": CONTRACT_VERSION, "model_id": FROZEN_MODEL_ID,
                "request_body_sha256": base["request_body_sha256"], "retry_count": 0,
            },
        )
        records.append(record)
        reservation_value = _read_json(reservation)
        reservation_value.update({"actual_calls_observed": compiler.calls_made, "updated_at": _utc_now()})
        _atomic_json(reservation, reservation_value)
    reservation_value = _read_json(reservation)
    reservation_value.update({"status": "closed", "actual_calls_observed": compiler.calls_made, "updated_at": _utc_now()})
    _atomic_json(reservation, reservation_value)
    summary = {
        "run_id": run_id, "status": "PASS" if all(item["status"] == "VALID" for item in records) else "NEEDS_WORK",
        "contract_version": CONTRACT_VERSION, "model_id": FROZEN_MODEL_ID,
        "call_count": compiler.calls_made, "retry_count": 0,
        "api_success_count": sum(item.get("api_success") is True for item in records),
        "strict_valid_count": sum(item.get("status") == "VALID" for item in records),
        "blind_comparison_executed": False,
    }
    _atomic_json(run_directory / "affordance_targeted_v1_2_1_summary.json", summary)
    report_lines = [
        "# Affordance v1.2.1 Targeted Retest", "",
        f"Status: **{summary['status']}**", "",
        f"- API success: {summary['api_success_count']}/4",
        f"- Strict-valid candidate outputs: {summary['strict_valid_count']}/4",
        f"- Calls: {summary['call_count']}/4", "- Retries: 0",
        "- BlindComparison: not executed", "",
        "Local candidate validation is recorded separately from API transport success. "
        "Rejected tool input and redacted raw response remain preserved without repair.", "",
    ]
    (run_directory / "AFFORDANCE_TARGETED_V1_2_1_REPORT.md").write_text(
        "\n".join(report_lines), encoding="utf-8", newline="\n"
    )
    if scan_repository(repository_root):
        raise TargetedRetestError("Post-run secret scan rejected generated evidence.")
    evidence_files = {
        path.relative_to(run_directory).as_posix(): _sha256(path)
        for path in sorted(run_directory.rglob("*"))
        if path.is_file() and path.name not in {"evidence_hashes.json", "COMPLETE.json"}
    }
    _atomic_json(run_directory / "evidence_hashes.json", {"algorithm": "SHA-256", "run_id": run_id, "files": evidence_files})
    _atomic_json(
        run_directory / "COMPLETE.json",
        {
            "run_id": run_id, "status": summary["status"],
            "evidence_sha256": _sha256(run_directory / "evidence_hashes.json"),
            "completed_at": _utc_now(),
        },
    )
    return summary


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--preflight-only", action="store_true")
    parser.add_argument("--execute-approved-four-call-retest", action="store_true")
    args = parser.parse_args(argv)
    repository_root = args.repo_root.resolve()
    semantic_root = repository_root / "tools" / "semantic"
    try:
        if args.execute_approved_four_call_retest:
            print(json.dumps(execute_approved(repository_root, semantic_root), ensure_ascii=False))
        else:
            print(json.dumps(preflight(repository_root, semantic_root, require_unused=True), ensure_ascii=False))
        return 0
    except Exception as exc:
        print(f"AFFORDANCE_TARGETED_V1_2_1_ERROR: {redact_sensitive_text(str(exc))[:1200]}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
