#!/usr/bin/env python3
"""Bounded 12-call real-model retest for the v1.2 candidate affordance."""

from __future__ import annotations

import argparse
import copy
import csv
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping, Sequence

from affordance_contract_v1_2 import (
    AffordanceContractError,
    CONTRACT_VERSION,
    candidate_tool_schema,
    validate_candidate_blueprint,
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
from atomic_output import atomic_deliver
from secret_scan import scan_repository
from semantic_contract import (
    CLARIFICATION_REQUEST_SCHEMA,
    REQUEST_CLARIFICATION_TOOL,
    SUBMIT_BLUEPRINT_TOOL,
)


APPROVED_CALLS = 12
FROZEN_MODEL_ID = "claude-sonnet-5"
RUN_PREFIX = "affordance-retest-v1-2"
CASE_ORDER = tuple(f"A{index:02d}" for index in range(1, APPROVED_CALLS + 1))
_MODEL_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}")


class AffordanceRetestError(RuntimeError):
    pass


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _sha256(path: Path) -> str:
    return _sha256_bytes(path.read_bytes())


def _canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise AffordanceRetestError(f"Cannot read required JSON: {path}") from exc


def _atomic_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    encoded = json.dumps(value, ensure_ascii=False, indent=2).encode("utf-8") + b"\n"
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(encoded)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def _load_configuration(semantic_root: Path) -> tuple[str, dict[str, Any], list[dict[str, Any]], dict[str, str]]:
    base_prompt_path = semantic_root / "prompts" / "semantic_compiler_system_prompt.md"
    addendum_path = semantic_root / "prompts" / "affordance_v1_2_candidate_addendum.md"
    cases_path = semantic_root / "cases" / "affordance_blind_12_candidate.json"
    freeze_path = semantic_root / "cases" / "affordance_v1_2_candidate_freeze.json"
    freeze = _read_json(freeze_path)
    if not isinstance(freeze, dict):
        raise AffordanceRetestError("Candidate freeze manifest must be an object.")
    for field in ("candidate_extension_schema", "candidate_blueprint_schema", "offline_validator", "blind_cases"):
        relative = freeze.get(field)
        expected = freeze.get(f"{field}_sha256")
        path = semantic_root.parent.parent / str(relative)
        if not path.is_file() or not isinstance(expected, str) or _sha256(path) != expected:
            raise AffordanceRetestError(f"Frozen candidate input changed: {field}")
    corpus = _read_json(cases_path)
    if not isinstance(corpus, dict) or corpus.get("case_order") != list(CASE_ORDER):
        raise AffordanceRetestError("Frozen 12-case order is invalid.")
    cases = corpus.get("cases")
    if not isinstance(cases, list) or len(cases) != APPROVED_CALLS:
        raise AffordanceRetestError("Frozen candidate corpus must contain exactly 12 cases.")
    for expected_id, case in zip(CASE_ORDER, cases):
        if not isinstance(case, dict) or set(case) != {"case_id", "prompt_zh", "identity", "review_parts"}:
            raise AffordanceRetestError("A frozen case has an invalid evidence envelope.")
        if case.get("case_id") != expected_id or not isinstance(case.get("prompt_zh"), str) or not case["prompt_zh"].strip():
            raise AffordanceRetestError("A frozen case ID or model-visible prompt is invalid.")
    base_prompt = base_prompt_path.read_text(encoding="utf-8")
    addendum = addendum_path.read_text(encoding="utf-8")
    if not base_prompt.strip() or not addendum.strip():
        raise AffordanceRetestError("Candidate system prompt is empty.")
    prompt = base_prompt.rstrip() + "\n\n" + addendum.strip() + "\n"
    schema = candidate_tool_schema()
    frozen_candidate = _read_json(semantic_root / "schema" / "forge_semantic_blueprint.v1_2_candidate.schema.json")
    if (
        not isinstance(frozen_candidate, dict)
        or frozen_candidate.get("required") != ["identity", "combat", "visual", "confidence", "affordance"]
        or set((frozen_candidate.get("properties") or {})) != {"identity", "combat", "visual", "confidence", "affordance"}
        or schema.get("required") != frozen_candidate.get("required")
        or set(schema.get("properties", {})) != set(frozen_candidate.get("properties", {}))
        or "$ref" in json.dumps(schema)
    ):
        raise AffordanceRetestError("Generated self-contained tool schema is not the frozen candidate composition.")
    hashes = {
        "base_prompt_sha256": _sha256(base_prompt_path),
        "candidate_addendum_sha256": _sha256(addendum_path),
        "combined_prompt_sha256": _sha256_bytes(prompt.encode("utf-8")),
        "candidate_schema_sha256": _sha256_bytes(_canonical_bytes(schema)),
        "clarification_schema_sha256": _sha256_bytes(_canonical_bytes(CLARIFICATION_REQUEST_SCHEMA)),
        "cases_sha256": _sha256(cases_path),
        "freeze_manifest_sha256": _sha256(freeze_path),
    }
    return prompt, schema, copy.deepcopy(cases), hashes


def _source_model(semantic_root: Path) -> str:
    path = semantic_root / "reports" / "limited_retest_3b" / "limited-retest-3b-20260803T040934865715Z-79738d1b" / "limited_retest_3b_summary.json"
    value = _read_json(path)
    if not isinstance(value, dict) or value.get("model_id") != FROZEN_MODEL_ID or value.get("provider") != "anthropic":
        raise AffordanceRetestError("Frozen source model provenance is invalid.")
    return FROZEN_MODEL_ID


def _reservation_path(semantic_root: Path) -> Path:
    return semantic_root / "reports" / "affordance_retest_v1_2_real_call_reservation.json"


def _report_root(semantic_root: Path) -> Path:
    return semantic_root / "reports" / "affordance_retest_v1_2"


def preflight(repository_root: Path, semantic_root: Path, *, require_unused: bool = True) -> dict[str, Any]:
    if semantic_root.parent.parent.resolve() != repository_root.resolve():
        raise AffordanceRetestError("Repository root does not own the semantic implementation.")
    if scan_repository(repository_root):
        raise AffordanceRetestError("Repository secret scan failed.")
    prompt, schema, cases, hashes = _load_configuration(semantic_root)
    model_id = _source_model(semantic_root)
    if require_unused:
        reservation = _reservation_path(semantic_root)
        reports = _report_root(semantic_root)
        if reservation.exists() or (reports.exists() and any(reports.iterdir())):
            raise AffordanceRetestError("The approved 12-call budget already has evidence; a second paid run is forbidden.")
    return {
        "status": "AFFORDANCE_RETEST_V1_2_PREFLIGHT_PASS",
        "model_id": model_id,
        "case_count": len(cases),
        "case_order": list(CASE_ORDER),
        "configuration_hashes": hashes,
        "prompt_bytes": len(prompt.encode("utf-8")),
        "schema_sha256": hashes["candidate_schema_sha256"],
        "ready": True,
    }


def _require_environment() -> None:
    key = os.environ.get("ANTHROPIC_API_KEY", "")
    model = os.environ.get("FORGE_SEMANTIC_MODEL", "")
    if not key.strip():
        raise AffordanceRetestError("ANTHROPIC_API_KEY is missing; use the interactive script.")
    if model != FROZEN_MODEL_ID or not _MODEL_PATTERN.fullmatch(model):
        raise AffordanceRetestError("FORGE_SEMANTIC_MODEL does not exactly match the frozen model ID.")
    if model == key or redact_sensitive_text(model) != model:
        raise AffordanceRetestError("Model ID resembles credential material.")


def _new_run_id() -> str:
    return f"{RUN_PREFIX}-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')}-{uuid.uuid4().hex[:8]}"


def _claim_reservation(path: Path, run_id: str, hashes: Mapping[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    value = {
        "run_id": run_id,
        "contract_version": CONTRACT_VERSION,
        "model_id": FROZEN_MODEL_ID,
        "endpoint": ANTHROPIC_MESSAGES_URL,
        "case_order": list(CASE_ORDER),
        "max_real_calls": APPROVED_CALLS,
        "attempts_reserved": 0,
        "actual_calls_observed": 0,
        "attempted_case_ids": [],
        "retry_count": 0,
        "configuration_hashes": dict(hashes),
        "status": "reserved",
        "created_at": _utc_now(),
        "updated_at": _utc_now(),
    }
    encoded = json.dumps(value, ensure_ascii=False, indent=2).encode("utf-8") + b"\n"
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError as exc:
        raise AffordanceRetestError("The 12-call reservation already exists.") from exc
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(encoded)
        stream.flush()
        os.fsync(stream.fileno())


def _update_reservation(path: Path, *, case_id: str | None = None, calls: int | None = None, status: str | None = None) -> None:
    value = _read_json(path)
    if not isinstance(value, dict):
        raise AffordanceRetestError("Call reservation is invalid.")
    if case_id is not None:
        expected = CASE_ORDER[int(value["attempts_reserved"])]
        if case_id != expected:
            raise AffordanceRetestError("Case attempt is duplicated or out of order.")
        value["attempts_reserved"] = int(value["attempts_reserved"]) + 1
        value["attempted_case_ids"] = list(CASE_ORDER[: int(value["attempts_reserved"])])
    if calls is not None:
        value["actual_calls_observed"] = calls
    if status is not None:
        value["status"] = status
    value["updated_at"] = _utc_now()
    _atomic_json(path, value)


def _request_hash(prompt: str, player_input: str, schema: Mapping[str, Any]) -> str:
    payload = build_anthropic_payload(prompt, player_input, FROZEN_MODEL_ID, schema, CLARIFICATION_REQUEST_SCHEMA)
    return _sha256_bytes(_canonical_bytes(payload))


def _record_result(parsed: Mapping[str, Any], base: dict[str, Any]) -> dict[str, Any]:
    tool_name = parsed.get("tool_name")
    tool_input = parsed.get("tool_input")
    record = copy.deepcopy(base)
    record.update({
        "api_status": 200,
        "request_id": parsed.get("request_id"),
        "response_model_id": parsed.get("model_id"),
        "tool_name": tool_name,
        "tool_input_received": copy.deepcopy(tool_input),
        "exactly_one_legal_tool_use": True,
        "sole_content_is_tool_use": True,
        "raw_response_redacted": redact_sensitive_text(parsed.get("raw_response_redacted", "")),
        "usage": copy.deepcopy(parsed.get("usage", {})),
        "stop_reason": parsed.get("stop_reason"),
    })
    if tool_name != SUBMIT_BLUEPRINT_TOOL:
        record.update({"status": "FAILED", "failure_reason": f"UNEXPECTED_TOOL:{tool_name}", "schema_valid": False, "cross_field_valid": False})
        return record
    if not isinstance(tool_input, dict):
        record.update({"status": "FAILED", "failure_reason": "INVALID_TOOL_INPUT", "schema_valid": False, "cross_field_valid": False})
        return record
    serialized_tool_input = json.dumps(tool_input, ensure_ascii=False, separators=(",", ":"))
    if redact_sensitive_text(serialized_tool_input) != serialized_tool_input:
        raise AffordanceRetestError("Tool input contained credential-shaped material.")
    snapshot = copy.deepcopy(tool_input)
    try:
        returned = validate_candidate_blueprint(tool_input)
        if returned is not tool_input or tool_input != snapshot:
            raise AffordanceRetestError("Candidate validator mutated or replaced tool input.")
        if tool_input["combat"]["behavior_family"] != "heavy_melee":
            raise AffordanceContractError("/combat/behavior_family: expected heavy_melee for this frozen corpus")
        record.update({"status": "VALID", "failure_reason": "", "schema_valid": True, "cross_field_valid": True, "validated_blueprint": copy.deepcopy(tool_input)})
    except (AffordanceContractError, AffordanceRetestError) as exc:
        if tool_input != snapshot:
            raise AffordanceRetestError("Rejected candidate input was mutated.")
        record.update({"status": "FAILED", "failure_reason": str(exc), "schema_valid": False, "cross_field_valid": False})
    return record


def _record_error(error: BaseException, base: dict[str, Any]) -> dict[str, Any]:
    code = error.code if isinstance(error, SemanticCompilerError) else "LOCAL_FAILURE"
    status = error.http_status if isinstance(error, SemanticCompilerError) else None
    raw = error.raw_response_redacted if isinstance(error, SemanticCompilerError) else ""
    record = copy.deepcopy(base)
    record.update({
        "status": "FAILED", "failure_reason": f"{code}: {redact_sensitive_text(str(error))[:1000]}",
        "api_status": status, "request_id": None, "response_model_id": None,
        "tool_name": None, "tool_input_received": None,
        "exactly_one_legal_tool_use": False, "sole_content_is_tool_use": False,
        "schema_valid": None, "cross_field_valid": None,
        "raw_response_redacted": redact_sensitive_text(raw), "usage": {}, "stop_reason": None,
    })
    return record


def _redacted_response_value(raw: Any) -> Any:
    if not isinstance(raw, str) or not raw:
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return raw


def _deliver_case(semantic_root: Path, run_directory: Path, case_id: str, record: Mapping[str, Any]) -> None:
    temporary = semantic_root / ".tmp" / "affordance_retest_v1_2" / run_directory.name / case_id
    final = run_directory / "cases" / case_id
    if temporary.exists() or final.exists():
        raise AffordanceRetestError("Case output path already exists.")
    temporary.mkdir(parents=True)
    _atomic_json(temporary / "result.json", record)
    atomic_deliver(temporary, final, lambda path: _read_json(path / "result.json").get("case_id") == case_id)


def _find_godot(repository_root: Path) -> Path:
    candidates = [
        repository_root / ".tools" / "Godot_v4.7.1-stable_win64_console.exe",
        repository_root.parent / "project forge" / ".tools" / "Godot_v4.7.1-stable_win64_console.exe",
    ]
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    for name in ("godot4.7.1", "godot4", "godot"):
        found = shutil.which(name)
        if found:
            return Path(found)
    raise AffordanceRetestError("Godot 4.7.1 console executable was not found for offline recipe export.")


def _export_recipes(repository_root: Path, run_directory: Path) -> None:
    safe_environment = dict(os.environ)
    safe_environment.pop("ANTHROPIC_API_KEY", None)
    safe_environment.pop("FORGE_SEMANTIC_MODEL", None)
    command = [
        str(_find_godot(repository_root)), "--headless", "--path", str(repository_root),
        "--script", "res://tools/semantic/scripts/export_affordance_retest_recipes.gd", "--",
        f"--run-directory={run_directory}",
    ]
    completed = subprocess.run(command, cwd=repository_root, env=safe_environment, capture_output=True, text=True, timeout=60, check=False)
    if completed.returncode != 0 or "AFFORDANCE_RETEST_RECIPE_EXPORT=PASS" not in completed.stdout:
        raise AffordanceRetestError("Offline MeleeMotionCompiler recipe export failed.")


def _write_reports(run_directory: Path, cases: list[dict[str, Any]], records: list[dict[str, Any]]) -> dict[str, Any]:
    compiled = _read_json(run_directory / "compiled_recipes.json")
    compiled_by_id = {item["case_id"]: item for item in compiled["records"]}
    valid = sum(record.get("status") == "VALID" for record in records)
    api_success = sum(record.get("api_status") == 200 for record in records)
    tool_success = sum(record.get("exactly_one_legal_tool_use") is True for record in records)
    compiled_count = sum(item.get("status") == "COMPILED" for item in compiled["records"])
    automatic_pass = valid == APPROVED_CALLS and api_success == APPROVED_CALLS and tool_success == APPROVED_CALLS and compiled_count == APPROVED_CALLS
    summary = {
        "run_id": run_directory.name,
        "status": "AUTOMATIC_CONTRACT_PASS_HUMAN_REVIEW_PENDING" if automatic_pass else "NEEDS_WORK",
        "contract_version": CONTRACT_VERSION,
        "provider": "anthropic",
        "endpoint": ANTHROPIC_MESSAGES_URL,
        "model_id": FROZEN_MODEL_ID,
        "call_count": APPROVED_CALLS,
        "retry_count": 0,
        "api_success_count": api_success,
        "exactly_one_tool_use_count": tool_success,
        "schema_and_cross_field_valid_count": valid,
        "offline_recipe_compile_count": compiled_count,
        "human_affordance_review_complete": False,
        "blind_comparison_executed": False,
        "flux_started": False,
        "birefnet_started": False,
        "comfyui_started": False,
    }
    _atomic_json(run_directory / "affordance_retest_v1_2_summary.json", summary)
    result_fields = ["case_id", "api_status", "tool_name", "status", "schema_valid", "cross_field_valid", "elapsed_ms", "failure_reason", "primitive_sequence", "recipe_signature"]
    with (run_directory / "affordance_retest_v1_2_results.csv").open("x", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=result_fields)
        writer.writeheader()
        for record in records:
            combo = compiled_by_id.get(record["case_id"], {})
            writer.writerow({**{field: record.get(field, "") for field in result_fields}, "primitive_sequence": " -> ".join(combo.get("primitive_sequence", [])), "recipe_signature": combo.get("recipe_signature", "")})
    review_fields = ["case_id", "frozen_identity", "frozen_review_parts", "model_canonical_identity", "model_evidence_parts", "affordance_semantically_correct", "at_least_two_identity_parts_supported", "review_notes"]
    with (run_directory / "human_affordance_review.csv").open("x", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=review_fields)
        writer.writeheader()
        for case, record in zip(cases, records):
            blueprint = record.get("validated_blueprint") or {}
            writer.writerow({
                "case_id": case["case_id"], "frozen_identity": case["identity"],
                "frozen_review_parts": " | ".join(case["review_parts"]),
                "model_canonical_identity": (blueprint.get("identity") or {}).get("canonical_name_en", ""),
                "model_evidence_parts": " | ".join((blueprint.get("affordance") or {}).get("evidence_parts", [])),
                "affordance_semantically_correct": "UNREVIEWED",
                "at_least_two_identity_parts_supported": "UNREVIEWED", "review_notes": "",
            })
    lines = [
        "# Forge Affordance v1.2 Limited Real Retest", "", f"Status: **{summary['status']}**", "",
        "This bounded run used the official Anthropic Messages API with the exact frozen model `claude-sonnet-5`. Each of the 12 frozen inputs was called once with zero retries. FLUX, BiRefNet, ComfyUI, and BlindComparison were not started.", "",
        "## Automatic envelope", "",
        f"- API success: {api_success}/12", f"- Exactly one legal tool use: {tool_success}/12",
        f"- Candidate Schema and cross-field valid: {valid}/12", f"- Existing MeleeMotionCompiler offline compile: {compiled_count}/12", "- Human affordance correctness: pending independent review", "",
        "## Frozen handoff table", "", "| Case | Frozen identity | Model affordance | Dominant mechanism axes | Compiled combo | State |", "|---|---|---|---|---|---|",
    ]
    for case, record in zip(cases, records):
        blueprint = record.get("validated_blueprint") or {}
        affordance = blueprint.get("affordance") or {}
        combo = compiled_by_id.get(case["case_id"], {})
        axes = ", ".join(f"{key}={affordance.get(key)}" for key in ("handle_length", "body_length", "grip_topology", "rigidity", "mass_distribution", "contact_surface", "secondary_contact_surface"))
        sequence = " → ".join(combo.get("primitive_sequence", [])) or "—"
        lines.append(f"| {case['case_id']} | {case['identity']} | `{json.dumps(affordance, ensure_ascii=False, separators=(',', ':'))}` | {axes or '—'} | {sequence} | {record.get('status')} |")
    lines += ["", "## Interpretation boundary", "", "The model produced semantic identity, combat, visual, and affordance data only. Recipe selection was performed afterward by the existing GDScript `MeleeMotionCompiler` with one neutral anchor/bounds basis for every case. No object name, expected answer, or review rubric was sent to the compiler.", "", "The automatic result does not certify semantic correctness or combat feel. Complete `human_affordance_review.csv` before authorizing a new BlindComparison.", ""]
    (run_directory / "AFFORDANCE_RETEST_V1_2_REPORT.md").write_text("\n".join(lines), encoding="utf-8", newline="\n")
    return summary


def _freeze_evidence(run_directory: Path, summary: Mapping[str, Any]) -> None:
    excluded = {"evidence_hashes.json", "COMPLETE.json"}
    files = {
        path.relative_to(run_directory).as_posix(): _sha256(path)
        for path in sorted(run_directory.rglob("*"))
        if path.is_file() and path.name not in excluded
    }
    evidence = {"algorithm": "SHA-256", "run_id": run_directory.name, "files": files}
    _atomic_json(run_directory / "evidence_hashes.json", evidence)
    _atomic_json(run_directory / "COMPLETE.json", {
        "run_id": run_directory.name, "status": summary["status"],
        "evidence_sha256": _sha256(run_directory / "evidence_hashes.json"), "completed_at": _utc_now(),
    })


def execute(repository_root: Path, semantic_root: Path) -> dict[str, Any]:
    require_safe_tls_environment()
    preflight(repository_root, semantic_root, require_unused=True)
    _require_environment()
    prompt, schema, cases, hashes = _load_configuration(semantic_root)
    run_id = _new_run_id()
    run_directory = _report_root(semantic_root) / run_id
    run_directory.mkdir(parents=True, exist_ok=False)
    _atomic_json(run_directory / "case_order.json", list(CASE_ORDER))
    reservation = _reservation_path(semantic_root)
    _claim_reservation(reservation, run_id, hashes)
    compiler = AnthropicSemanticCompiler(system_prompt=prompt, blueprint_schema=schema, clarification_schema=CLARIFICATION_REQUEST_SCHEMA, call_limiter=CallLimiter(APPROVED_CALLS))
    records: list[dict[str, Any]] = []
    print(f"AFFORDANCE_RETEST_V1_2_START run_id={run_id} calls={APPROVED_CALLS}", flush=True)
    for ordinal, case in enumerate(cases, 1):
        case_id = case["case_id"]
        player_input = case["prompt_zh"]
        local_request_id = str(uuid.uuid4())
        started_at = _utc_now()
        started = time.monotonic()
        calls_before = compiler.calls_made
        _update_reservation(reservation, case_id=case_id, status="in_progress")
        base = {
            "case_id": case_id, "ordinal": ordinal, "contract_version": CONTRACT_VERSION,
            "provider": "anthropic", "endpoint": ANTHROPIC_MESSAGES_URL, "model_id": FROZEN_MODEL_ID,
            "local_request_id": local_request_id, "input_sha256": _sha256_bytes(player_input.encode("utf-8")),
            "request_body_sha256": _request_hash(prompt, player_input, schema),
            "started_at": started_at, "retry_count": 0, "repair_applied": False,
            "unwrap_applied": False, "coercion_applied": False, "defaults_applied": False,
        }
        print(f"AFFORDANCE_RETEST_V1_2_CALL case={case_id} ordinal={ordinal}/12", flush=True)
        try:
            parsed = compiler.compile(player_input)
            if compiler.calls_made != calls_before + 1:
                raise AffordanceRetestError("Case did not consume exactly one call slot.")
            record = _record_result(parsed, base)
        except Exception as exc:
            if compiler.calls_made not in {calls_before, calls_before + 1}:
                raise AffordanceRetestError("Case consumed an invalid number of call slots.") from None
            record = _record_error(exc, base)
        record["completed_at"] = _utc_now()
        record["elapsed_ms"] = max(0, round((time.monotonic() - started) * 1000))
        raw_value = record.pop("raw_response_redacted", "")
        _deliver_case(semantic_root, run_directory, case_id, record)
        _atomic_json(run_directory / "raw_response_redacted" / f"{case_id}.json", {"case_id": case_id, "response": _redacted_response_value(raw_value)})
        _atomic_json(run_directory / "request_manifests" / f"{case_id}.json", {key: record[key] for key in ("case_id", "ordinal", "contract_version", "provider", "endpoint", "model_id", "local_request_id", "input_sha256", "request_body_sha256", "retry_count")})
        if record.get("status") == "VALID":
            blueprint = record["validated_blueprint"]
            _atomic_json(run_directory / "semantic_blueprints" / f"{case_id}.json", blueprint)
            _atomic_json(run_directory / "affordance_profiles" / f"{case_id}.json", blueprint["affordance"])
        records.append(record)
        _update_reservation(reservation, calls=compiler.calls_made)
        print(f"AFFORDANCE_RETEST_V1_2_RESULT case={case_id} status={record.get('status')} elapsed_ms={record['elapsed_ms']}", flush=True)
    _update_reservation(reservation, calls=compiler.calls_made, status="closed_pending_human_review")
    _export_recipes(repository_root, run_directory)
    summary = _write_reports(run_directory, cases, records)
    if scan_repository(repository_root):
        raise AffordanceRetestError("Post-run secret scan rejected generated evidence.")
    _freeze_evidence(run_directory, summary)
    print(json.dumps({"run_id": run_id, "status": summary["status"], "report_path": str(run_directory / "AFFORDANCE_RETEST_V1_2_REPORT.md")}, ensure_ascii=False), flush=True)
    return summary


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--preflight-only", action="store_true")
    args = parser.parse_args(argv)
    repository_root = args.repo_root.resolve()
    semantic_root = repository_root / "tools" / "semantic"
    try:
        if args.preflight_only:
            print(json.dumps(preflight(repository_root, semantic_root, require_unused=True), ensure_ascii=False))
        else:
            execute(repository_root, semantic_root)
        return 0
    except Exception as exc:
        print(f"AFFORDANCE_RETEST_V1_2_ERROR: {redact_sensitive_text(str(exc))[:1200]}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
