#!/usr/bin/env python3
"""Sequential, fail-closed runner for Forge Semantic Compiler Gate A.

The only production entry point in this module uses the checked-in prompt,
schemas, and 20-case corpus, then performs at most one Anthropic request per
case. Expected labels are deliberately loaded only after the request loop.
"""

from __future__ import annotations

import argparse
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
    MAX_REAL_CALLS,
    AnthropicSemanticCompiler,
    SemanticCompilerError,
    redact_sensitive_text,
    require_safe_tls_environment,
)
from atomic_output import atomic_deliver
from gate_a_evaluator import (
    evaluate_run,
    isolated_model_input,
    load_gate_a_cases,
    load_gate_a_expected,
)
from gate_a_reporting import write_gate_a_reports
from secret_scan import scan_repository
from scope_guard import ScopeGuardError, verify_scope_baseline
from semantic_contract import (
    CLARIFICATION_REQUEST_SCHEMA,
    CONTRACT_VERSION,
    FORGE_SEMANTIC_BLUEPRINT_SCHEMA,
    REQUEST_CLARIFICATION_TOOL,
    SUBMIT_BLUEPRINT_TOOL,
    ContractValidationError,
    validate_tool_input,
)


_RUN_ID_PATTERN = re.compile(r"gate-a-[0-9]{8}T[0-9]{12}Z-[0-9a-f]{8}")
_MODEL_ID_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}")


class GateARunnerError(RuntimeError):
    """Safe, user-facing local Gate A failure."""


class SemanticCompilerLike(Protocol):
    @property
    def calls_made(self) -> int: ...

    def compile(self, player_input: str) -> dict[str, Any]: ...


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace(
        "+00:00", "Z"
    )


def _read_json_object(path: Path) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as handle:
            value = json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        raise GateARunnerError(f"Cannot read required Gate A JSON file: {path}") from exc
    if not isinstance(value, dict):
        raise GateARunnerError(f"Required Gate A JSON file is not an object: {path}")
    return value


def _read_system_prompt(path: Path) -> str:
    try:
        value = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise GateARunnerError(f"Cannot read the Gate A system prompt: {path}") from exc
    if not value.strip():
        raise GateARunnerError("The Gate A system prompt is empty.")
    return value


def require_environment(environ: Mapping[str, str] | None = None) -> str:
    """Check presence without logging, persisting, or guessing either value."""

    environment = os.environ if environ is None else environ
    if not environment.get("ANTHROPIC_API_KEY", "").strip():
        raise GateARunnerError(
            "Gate A stopped: ANTHROPIC_API_KEY is missing from this process. "
            "Use tools/semantic/scripts/run_gate_a_interactive.ps1."
        )
    model_id = environment.get("FORGE_SEMANTIC_MODEL", "")
    if not model_id.strip():
        raise GateARunnerError(
            "Gate A stopped: FORGE_SEMANTIC_MODEL is missing; no model was guessed."
        )
    if model_id != model_id.strip() or not _MODEL_ID_PATTERN.fullmatch(model_id):
        raise GateARunnerError(
            "Gate A stopped: FORGE_SEMANTIC_MODEL is not a safe exact model ID."
        )
    if (
        model_id == environment.get("ANTHROPIC_API_KEY")
        or redact_sensitive_text(model_id) != model_id
    ):
        raise GateARunnerError(
            "Gate A stopped: FORGE_SEMANTIC_MODEL resembles credential material."
        )
    return model_id


def _new_run_id(output_root: Path) -> str:
    for _ in range(16):
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        candidate = f"gate-a-{timestamp}-{uuid.uuid4().hex[:8]}"
        if _RUN_ID_PATTERN.fullmatch(candidate) and not (output_root / candidate).exists():
            return candidate
    raise GateARunnerError("Could not allocate a unique Gate A run_id.")


def _prepare_run(semantic_root: Path, force_new_run: bool) -> tuple[str, Path]:
    output_root = semantic_root / "output" / "gate_a"
    existing = output_root.exists() and any(output_root.iterdir())
    if existing and not force_new_run:
        raise GateARunnerError(
            "Gate A output already exists. Refusing another paid run without -ForceNewRun."
        )
    run_id = _new_run_id(output_root)
    return run_id, output_root / run_id


def _reservation_path(semantic_root: Path) -> Path:
    return semantic_root / "reports" / "gate_a_real_call_reservation.json"


def _atomic_write_reservation(path: Path, payload: Mapping[str, Any]) -> None:
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


def _claim_real_call_budget(semantic_root: Path, run_id: str) -> Path:
    """Atomically reserve the Spike's sole real 20-case run across processes."""

    path = _reservation_path(semantic_root)
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "contract_version": CONTRACT_VERSION,
        "run_id": run_id,
        "status": "reserved",
        "max_real_calls": MAX_REAL_CALLS,
        "attempts_reserved": 0,
        "actual_calls_observed": 0,
        "created_at": _utc_now(),
        "updated_at": _utc_now(),
    }
    encoded = (json.dumps(payload, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError as exc:
        raise GateARunnerError(
            "The real Gate A call budget is already reserved; refusing another paid run."
        ) from exc
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(encoded)
            handle.flush()
            os.fsync(handle.fileno())
    except Exception:
        # Keep even an incomplete exclusive marker: automatic recovery could
        # permit a second process to exceed the approved lifetime call budget.
        raise
    return path


def _read_reservation(path: Path, run_id: str) -> dict[str, Any]:
    value = _read_json_object(path)
    if value.get("run_id") != run_id or value.get("max_real_calls") != MAX_REAL_CALLS:
        raise GateARunnerError("The persistent Gate A call reservation is invalid.")
    attempts = value.get("attempts_reserved")
    actual = value.get("actual_calls_observed")
    if (
        isinstance(attempts, bool)
        or not isinstance(attempts, int)
        or not 0 <= attempts <= MAX_REAL_CALLS
        or isinstance(actual, bool)
        or not isinstance(actual, int)
        or not 0 <= actual <= MAX_REAL_CALLS
    ):
        raise GateARunnerError("The persistent Gate A call counters are invalid.")
    return value


def _reserve_case_attempt(path: Path, run_id: str) -> None:
    value = _read_reservation(path, run_id)
    attempts = int(value["attempts_reserved"])
    if attempts >= MAX_REAL_CALLS:
        raise GateARunnerError("The persistent Gate A call budget is exhausted.")
    value["attempts_reserved"] = attempts + 1
    value["status"] = "in_progress"
    value["updated_at"] = _utc_now()
    _atomic_write_reservation(path, value)


def _record_observed_calls(
    path: Path,
    run_id: str,
    observed: int,
    *,
    status: str = "in_progress",
) -> None:
    value = _read_reservation(path, run_id)
    if isinstance(observed, bool) or not 0 <= observed <= MAX_REAL_CALLS:
        raise GateARunnerError("Observed Gate A call count is invalid.")
    value["actual_calls_observed"] = observed
    value["status"] = status
    value["updated_at"] = _utc_now()
    _atomic_write_reservation(path, value)


def _write_staged_record(path: Path, record: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=False)
    encoded = json.dumps(record, ensure_ascii=False, indent=2) + "\n"
    # A credential-shaped value in a result envelope is rejected, not repaired.
    if redact_sensitive_text(encoded) != encoded:
        raise GateARunnerError("A staged result contained credential-shaped material.")
    with path.open("x", encoding="utf-8", newline="\n") as handle:
        handle.write(encoded)
        handle.flush()
        os.fsync(handle.fileno())


def _validate_staged_record(
    directory: Path,
    *,
    case_id: str,
    local_request_id: str,
) -> bool:
    entries = list(directory.iterdir())
    if [entry.name for entry in entries] != ["result.json"]:
        raise GateARunnerError("A staged case must contain exactly result.json.")
    value = _read_json_object(directory / "result.json")
    if value.get("case_id") != case_id:
        raise GateARunnerError("Staged result case_id mismatch.")
    if value.get("local_request_id") != local_request_id:
        raise GateARunnerError("Staged result request correlation mismatch.")
    if value.get("result_type") not in {
        "compiled",
        "needs_clarification",
        "failed",
    }:
        raise GateARunnerError("Staged result_type is invalid.")
    if value.get("result_type") != "failed":
        validate_tool_input(str(value.get("tool_name", "")), value.get("result"))
        if value.get("schema_valid") is not True:
            raise GateARunnerError("A successful staged result is not schema-valid.")
    return True


def _usage_fields(usage: Mapping[str, Any] | None) -> dict[str, int]:
    source = usage if isinstance(usage, Mapping) else {}
    fields: dict[str, int] = {}
    for name in (
        "input_tokens",
        "output_tokens",
        "cache_creation_input_tokens",
        "cache_read_input_tokens",
    ):
        value = source.get(name, 0)
        fields[name] = (
            value
            if isinstance(value, int) and not isinstance(value, bool) and value >= 0
            else 0
        )
    return fields


def _base_record(
    *,
    case_id: str,
    input_text: str,
    local_request_id: str,
    expected_model_id: str,
    started_at: str,
    completed_at: str,
    elapsed_ms: int,
    real_transport: bool,
    ai_interpretation_used: bool,
) -> dict[str, Any]:
    return {
        "case_id": case_id,
        "input_text": input_text,
        "provider": "anthropic" if real_transport else "test-double",
        "model_id": expected_model_id,
        "request_id": local_request_id,
        "local_request_id": local_request_id,
        "contract_version": CONTRACT_VERSION,
        "ai_interpretation_used": bool(
            real_transport and ai_interpretation_used
        ),
        "started_at": started_at,
        "completed_at": completed_at,
        "elapsed_ms": elapsed_ms,
        "retry_count": 0,
    }


def _success_record(
    *,
    parsed: Mapping[str, Any],
    base: dict[str, Any],
) -> dict[str, Any]:
    tool_name = str(parsed["tool_name"])
    result = parsed["tool_input"]
    serialized_result = json.dumps(result, ensure_ascii=False, separators=(",", ":"))
    if redact_sensitive_text(serialized_result) != serialized_result:
        raise ContractValidationError("tool input contains credential-shaped material")
    validate_tool_input(tool_name, result)
    result_type = (
        "compiled"
        if tool_name == SUBMIT_BLUEPRINT_TOOL
        else "needs_clarification"
        if tool_name == REQUEST_CLARIFICATION_TOOL
        else "failed"
    )
    usage = _usage_fields(parsed.get("usage"))
    record = dict(base)
    record.update(
        {
            "api_status": 200,
            "model_id": parsed["model_id"],
            "request_id": parsed["request_id"],
            "result_type": result_type,
            "tool_name": tool_name,
            "result": result,
            "schema_valid": True,
            "validation": {
                "schema_valid": True,
                "cross_field_valid": True,
                "repaired": False,
            },
            "usage": usage,
            **usage,
            "stop_reason": parsed.get("stop_reason"),
            "raw_response_redacted": redact_sensitive_text(
                parsed.get("raw_response_redacted", "")
            ),
            "failure_reason": "",
        }
    )
    return record


def _failure_record(
    *,
    base: dict[str, Any],
    error: BaseException,
    parsed: Mapping[str, Any] | None,
) -> dict[str, Any]:
    usage_source: Mapping[str, Any] | None = (
        parsed.get("usage") if parsed else None
    )
    api_status: int | str = "unavailable"
    error_code = "LOCAL_VALIDATION_FAILURE"
    validation_stage = "transport_or_parser"
    schema_valid: bool | None = False
    cross_field_valid: bool | None = None
    validation_issues: list[dict[str, str]] = []
    raw_redacted = redact_sensitive_text(
        parsed.get("raw_response_redacted", "") if parsed else ""
    )
    if isinstance(error, SemanticCompilerError):
        failure = error.to_failure_record()
        api_status = failure.get("http_status") or "unavailable"
        error_code = str(failure.get("error_code", "SEMANTIC_COMPILER_FAILURE"))
        raw_redacted = redact_sensitive_text(
            failure.get("raw_response_redacted", "")
        )
        if usage_source is None and raw_redacted:
            try:
                raw_document = json.loads(raw_redacted)
            except json.JSONDecodeError:
                raw_document = None
            if isinstance(raw_document, Mapping) and isinstance(
                raw_document.get("usage"), Mapping
            ):
                usage_source = raw_document["usage"]
    elif isinstance(error, ContractValidationError):
        api_status = 200 if parsed is not None else "unavailable"
        error_code = "CONTRACT_VALIDATION_FAILED"
        validation_stage = error.stage
        schema_valid = error.stage == "cross_field"
        cross_field_valid = False if error.stage == "cross_field" else None
        validation_issues = [
            {
                "path": issue.path,
                "json_pointer": issue.json_pointer,
                "message": issue.message,
            }
            for issue in error.issues
        ]

    safe_reason = redact_sensitive_text(str(error))[:2000]
    usage = _usage_fields(usage_source)
    record = dict(base)
    if parsed is not None:
        parsed_model = str(parsed.get("model_id", record["model_id"]))
        parsed_request = str(parsed.get("request_id", record["request_id"]))
        if redact_sensitive_text(parsed_model) == parsed_model:
            record["model_id"] = parsed_model
        if redact_sensitive_text(parsed_request) == parsed_request:
            record["request_id"] = parsed_request
    record.update(
        {
            "api_status": api_status,
            "result_type": "failed",
            "tool_name": parsed.get("tool_name") if parsed else None,
            "result": None,
            "schema_valid": schema_valid,
            "validation": {
                "stage": validation_stage,
                "schema_valid": schema_valid,
                "cross_field_valid": cross_field_valid,
                "issues": validation_issues,
                "repaired": False,
            },
            "usage": usage,
            **usage,
            "raw_response_redacted": raw_redacted,
            "error_code": error_code,
            "failure_reason": f"{error_code}: {safe_reason}",
        }
    )
    return record


def _deliver_case(
    *,
    semantic_root: Path,
    output_run_directory: Path,
    case_id: str,
    local_request_id: str,
    record: Mapping[str, Any],
) -> Path:
    temp_case = semantic_root / ".tmp" / local_request_id
    final_case = output_run_directory / case_id
    if temp_case.exists():
        raise GateARunnerError("Temporary request directory already exists.")
    _write_staged_record(temp_case / "result.json", record)
    return atomic_deliver(
        temp_case,
        final_case,
        lambda directory: _validate_staged_record(
            directory,
            case_id=case_id,
            local_request_id=local_request_id,
        ),
    )


def execute_gate_a(
    *,
    semantic_root: Path,
    repository_root: Path,
    force_new_run: bool = False,
    compiler: SemanticCompilerLike | None = None,
    environ: Mapping[str, str] | None = None,
) -> dict[str, Any]:
    """Execute one isolated run; injected compilers are never attested as real AI."""

    real_transport = compiler is None
    if real_transport and environ is not None:
        raise GateARunnerError(
            "A real Gate A transport must use the current process environment directly."
        )
    semantic_root = semantic_root.resolve()
    repository_root = repository_root.resolve()
    model_id = require_environment(environ)
    if real_transport:
        try:
            require_safe_tls_environment()
        except SemanticCompilerError as exc:
            raise GateARunnerError(str(exc)) from None
    if scan_repository(repository_root):
        raise GateARunnerError(
            "Gate A stopped before any real call because the secret scan failed."
        )
    scope_baseline = semantic_root / "reports" / "gate_a_scope_baseline.json"
    if real_transport:
        try:
            verify_scope_baseline(repository_root, scope_baseline)
        except ScopeGuardError as exc:
            raise GateARunnerError(str(exc)) from exc
    cases = load_gate_a_cases(semantic_root / "cases" / "gate_a_cases.json")
    if len(cases) != MAX_REAL_CALLS:
        raise GateARunnerError("Gate A corpus must contain exactly 20 ordered cases.")

    prompt = _read_system_prompt(
        semantic_root / "prompts" / "semantic_compiler_system_prompt.md"
    )
    # Read the checked-in files independently, then require exact parity with
    # the validator-owned copies used after every response.
    blueprint_schema = _read_json_object(
        semantic_root / "schema" / "forge_semantic_blueprint.schema.json"
    )
    clarification_schema = _read_json_object(
        semantic_root / "schema" / "clarification_request.schema.json"
    )
    if blueprint_schema != FORGE_SEMANTIC_BLUEPRINT_SCHEMA:
        raise GateARunnerError("Blueprint Schema differs from the local validator contract.")
    if clarification_schema != CLARIFICATION_REQUEST_SCHEMA:
        raise GateARunnerError(
            "Clarification Schema differs from the local validator contract."
        )

    active_compiler: SemanticCompilerLike = compiler or AnthropicSemanticCompiler(
        system_prompt=prompt,
        blueprint_schema=blueprint_schema,
        clarification_schema=clarification_schema,
    )
    calls_before = int(getattr(active_compiler, "calls_made", 0))
    if real_transport and calls_before != 0:
        raise GateARunnerError(
            "Gate A process already consumed a real-call slot; refusing a partial paid run."
        )

    run_id, output_run_directory = _prepare_run(semantic_root, force_new_run)
    reservation_path = (
        _claim_real_call_budget(semantic_root, run_id) if real_transport else None
    )
    results: list[dict[str, Any]] = []
    for case in cases:
        case_id = case["case_id"]
        player_input = isolated_model_input(case)
        local_request_id = str(uuid.uuid4())
        started_at = _utc_now()
        started_clock = time.monotonic()
        case_calls_before = int(getattr(active_compiler, "calls_made", 0))
        parsed: Mapping[str, Any] | None = None
        try:
            if real_transport and int(active_compiler.calls_made) >= MAX_REAL_CALLS:
                raise GateARunnerError("Gate A call limit was reached before the next case.")
            if reservation_path is not None:
                _reserve_case_attempt(reservation_path, run_id)
            parsed = active_compiler.compile(player_input)
            case_calls_after = int(getattr(active_compiler, "calls_made", case_calls_before))
            case_real_call = real_transport and case_calls_after == case_calls_before + 1
            completed_at = _utc_now()
            elapsed_ms = max(0, round((time.monotonic() - started_clock) * 1000))
            base = _base_record(
                case_id=case_id,
                input_text=player_input,
                local_request_id=local_request_id,
                expected_model_id=model_id,
                started_at=started_at,
                completed_at=completed_at,
                elapsed_ms=elapsed_ms,
                real_transport=real_transport,
                ai_interpretation_used=case_real_call,
            )
            record = _success_record(parsed=parsed, base=base)
        except Exception as exc:
            case_calls_after = int(getattr(active_compiler, "calls_made", case_calls_before))
            case_real_call = real_transport and case_calls_after == case_calls_before + 1
            completed_at = _utc_now()
            elapsed_ms = max(0, round((time.monotonic() - started_clock) * 1000))
            base = _base_record(
                case_id=case_id,
                input_text=player_input,
                local_request_id=local_request_id,
                expected_model_id=model_id,
                started_at=started_at,
                completed_at=completed_at,
                elapsed_ms=elapsed_ms,
                real_transport=real_transport,
                ai_interpretation_used=case_real_call,
            )
            record = _failure_record(base=base, error=exc, parsed=parsed)

        _deliver_case(
            semantic_root=semantic_root,
            output_run_directory=output_run_directory,
            case_id=case_id,
            local_request_id=local_request_id,
            record=record,
        )
        results.append(record)
        if reservation_path is not None:
            _record_observed_calls(
                reservation_path,
                run_id,
                int(active_compiler.calls_made) - calls_before,
            )

    calls_after = int(getattr(active_compiler, "calls_made", calls_before))
    actual_call_count = calls_after - calls_before if real_transport else 0
    if not 0 <= actual_call_count <= MAX_REAL_CALLS:
        raise GateARunnerError("Gate A transport reported an invalid real-call count.")
    if reservation_path is not None:
        _record_observed_calls(
            reservation_path,
            run_id,
            actual_call_count,
            status="requests_complete",
        )
    if real_transport:
        try:
            verify_scope_baseline(repository_root, scope_baseline)
        except ScopeGuardError as exc:
            raise GateARunnerError(str(exc)) from exc

    # Isolation boundary: expected labels are first opened after all request
    # attempts and all final case directories have been atomically delivered.
    load_gate_a_expected(semantic_root / "cases" / "gate_a_expected.json")
    scores = evaluate_run(
        output_run_directory,
        semantic_root / "cases" / "gate_a_expected.json",
    )

    pre_report_findings = scan_repository(repository_root)
    if pre_report_findings:
        raise GateARunnerError(
            "Gate A case results were preserved, but the pre-report secret scan failed."
        )
    summary = write_gate_a_reports(
        semantic_root=semantic_root,
        run_id=run_id,
        model_id=model_id,
        results=results,
        scores=scores,
        output_run_directory=output_run_directory,
        secret_scan_passed=True,
        actual_call_count=actual_call_count,
        scope_unchanged=True,
        pre_publish_validator=lambda _pending: not scan_repository(repository_root),
    )
    return summary


def _parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--force-new-run", action="store_true")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv)
    repository_root = args.repo_root.resolve()
    semantic_root = Path(__file__).resolve().parents[1]
    model_id: str | None = None
    try:
        if semantic_root.parent.parent.resolve() != repository_root:
            raise GateARunnerError(
                "--repo-root does not own this tools/semantic implementation."
            )
        model_id = require_environment()
        summary = execute_gate_a(
            semantic_root=semantic_root,
            repository_root=repository_root,
            force_new_run=args.force_new_run,
        )
        public_summary = {
            "run_id": summary["run_id"],
            "call_count": summary["call_count"],
            "processable_results": summary["processable_results"],
            "schema_valid_count": summary["schema_valid_count"],
            "status": summary["status"],
            "report_path": str(semantic_root / "reports" / "GATE_A_REPORT.md"),
        }
        print(json.dumps(public_summary, ensure_ascii=False))
        return 0 if summary["status"] == "GATE A PASS" else 2
    except GateARunnerError as exc:
        print(str(exc), file=sys.stderr)
        return 3
    except Exception:
        # Do not echo an unexpected exception: transport exceptions are handled
        # per-case and an arbitrary message could contain credential material.
        print("Gate A stopped after an unexpected local failure; no secret was logged.", file=sys.stderr)
        return 4
    finally:
        # This Python process owns only inherited copies of these environment
        # variables. Removing them cannot alter the parent PowerShell process.
        os.environ.pop("ANTHROPIC_API_KEY", None)
        os.environ.pop("FORGE_SEMANTIC_MODEL", None)
        model_id = None


if __name__ == "__main__":
    raise SystemExit(main())
