from __future__ import annotations

import csv
import hashlib
import io
import json
import os
import shutil
import tempfile
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any, Callable, Mapping


CSV_FIELDS = (
    "case_id",
    "api_status",
    "result_type",
    "schema_valid",
    "identity_correct",
    "behavior_correct",
    "preserved_features_quality",
    "clarification_correct",
    "fixed_weapon_substitution",
    "reviewer_reason",
    "input_tokens",
    "output_tokens",
    "elapsed_ms",
)

APPROVED_ENDPOINT = "https://api.anthropic.com/v1/messages"
CONTRACT_VERSION = "forge-semantic-v1.1"


def _atomic_write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, path)
    finally:
        if temporary_path.exists():
            temporary_path.unlink()


def _atomic_write_json(path: Path, payload: Any) -> None:
    _atomic_write_text(path, json.dumps(payload, ensure_ascii=False, indent=2) + "\n")


def _valid_price(value: str | None) -> Decimal | None:
    if value is None or not value.strip():
        return None
    try:
        parsed = Decimal(value)
    except InvalidOperation:
        return None
    if not parsed.is_finite() or parsed < 0:
        return None
    return parsed


def calculate_cost(
    input_tokens: int,
    output_tokens: int,
    environ: Mapping[str, str] | None = None,
) -> dict[str, Any]:
    environment = os.environ if environ is None else environ
    input_price = _valid_price(environment.get("FORGE_SEMANTIC_INPUT_PRICE_PER_M"))
    output_price = _valid_price(environment.get("FORGE_SEMANTIC_OUTPUT_PRICE_PER_M"))
    if input_price is None or output_price is None:
        return {
            "status": "COST_NOT_CALCULATED — TOKEN_USAGE_ONLY",
            "estimated_cost": None,
            "currency": None,
        }
    estimated = (Decimal(input_tokens) * input_price + Decimal(output_tokens) * output_price) / Decimal(
        1_000_000
    )
    return {
        "status": "CALCULATED_FROM_USER_SUPPLIED_RATES",
        "estimated_cost": format(estimated.quantize(Decimal("0.000001")), "f"),
        "currency": "USD",
    }


def _score_rows(
    results: list[dict[str, Any]],
    scores: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    score_by_case = {str(score["case_id"]): score for score in scores}
    rows: list[dict[str, Any]] = []
    for result in results:
        case_id = str(result.get("case_id", ""))
        score = score_by_case.get(case_id, {})
        rows.append(
            {
                "case_id": case_id,
                "api_status": result.get("api_status", ""),
                "result_type": result.get("result_type", "failed"),
                "schema_valid": bool(score.get("schema_valid", False)),
                "identity_correct": bool(score.get("identity_correct", False)),
                "behavior_correct": bool(score.get("behavior_correct", False)),
                "preserved_features_quality": int(score.get("preserved_features_quality", 0)),
                "clarification_correct": bool(score.get("clarification_correct", False)),
                "fixed_weapon_substitution": bool(score.get("fixed_weapon_substitution", False)),
                "reviewer_reason": str(score.get("reviewer_reason", result.get("failure_reason", ""))),
                "input_tokens": int(result.get("input_tokens", 0) or 0),
                "output_tokens": int(result.get("output_tokens", 0) or 0),
                "elapsed_ms": int(result.get("elapsed_ms", 0) or 0),
            }
        )
    return rows


def _successful_api_status(value: Any) -> bool:
    if isinstance(value, bool):
        return False
    if isinstance(value, int):
        return 200 <= value < 300
    if isinstance(value, str) and value.strip().isdigit():
        return 200 <= int(value.strip()) < 300
    return False


def _attested_anthropic_envelope(result: Mapping[str, Any], model_id: str) -> bool:
    usage = result.get("usage")
    if not isinstance(usage, Mapping):
        return False
    usage_valid = all(
        isinstance(usage.get(field), int)
        and not isinstance(usage.get(field), bool)
        and usage.get(field, -1) >= 0
        for field in ("input_tokens", "output_tokens")
    )
    return bool(
        result.get("provider") == "anthropic"
        and result.get("ai_interpretation_used") is True
        and result.get("contract_version") == CONTRACT_VERSION
        and result.get("model_id") == model_id
        and isinstance(result.get("request_id"), str)
        and bool(result.get("request_id", "").strip())
        and _successful_api_status(result.get("api_status"))
        and result.get("result_type") in {"compiled", "needs_clarification"}
        and usage_valid
    )


def _call_reservation_attested(
    semantic_root: Path,
    run_id: str,
    actual_call_count: int,
) -> bool:
    path = semantic_root / "reports" / "gate_a_real_call_reservation.json"
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    return bool(
        isinstance(value, dict)
        and value.get("contract_version") == CONTRACT_VERSION
        and value.get("run_id") == run_id
        and value.get("status") == "requests_complete"
        and value.get("max_real_calls") == 20
        and value.get("attempts_reserved") == 20
        and value.get("actual_calls_observed") == actual_call_count
        and isinstance(actual_call_count, int)
        and not isinstance(actual_call_count, bool)
        and 0 <= actual_call_count <= 20
    )


def _delivered_result_attestation_count(
    output_run_directory: Path,
    results: list[dict[str, Any]],
) -> int:
    matched = 0
    seen: set[str] = set()
    for result in results:
        case_id = str(result.get("case_id", ""))
        if (
            not case_id
            or case_id in seen
            or any(
                character
                not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
                for character in case_id
            )
        ):
            continue
        seen.add(case_id)
        path = output_run_directory / case_id / "result.json"
        try:
            delivered = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if delivered == result:
            matched += 1
    return matched


def _csv_text(rows: list[dict[str, Any]]) -> str:
    buffer = io.StringIO(newline="")
    writer = csv.DictWriter(buffer, fieldnames=CSV_FIELDS, extrasaction="ignore", lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return buffer.getvalue()


def _gate_summary(
    *,
    run_id: str,
    model_id: str,
    results: list[dict[str, Any]],
    rows: list[dict[str, Any]],
    secret_scan_passed: bool,
    actual_call_count: int,
    scope_unchanged: bool,
    call_reservation_attested: bool,
    delivered_result_attestation_count: int,
) -> dict[str, Any]:
    if not isinstance(actual_call_count, int) or isinstance(actual_call_count, bool):
        raise TypeError("actual_call_count must be an integer")
    if not 0 <= actual_call_count <= 20:
        raise ValueError("actual_call_count must be between 0 and 20")
    call_count = actual_call_count
    processable = sum(row["result_type"] in ("compiled", "needs_clarification") for row in rows)
    schema_valid = sum(bool(row["schema_valid"]) for row in rows)
    identity_correct = sum(bool(row["identity_correct"]) for row in rows)
    behavior_correct = sum(bool(row["behavior_correct"]) for row in rows)
    features_full = sum(int(row["preserved_features_quality"]) == 2 for row in rows)
    clarification_correct = sum(bool(row["clarification_correct"]) for row in rows)
    substitutions = sum(bool(row["fixed_weapon_substitution"]) for row in rows)
    retries = sum(int(result.get("retry_count", 0) or 0) for result in results)
    input_tokens = sum(int(row["input_tokens"]) for row in rows)
    output_tokens = sum(int(row["output_tokens"]) for row in rows)
    cache_creation = sum(int(result.get("cache_creation_input_tokens", 0) or 0) for result in results)
    cache_read = sum(int(result.get("cache_read_input_tokens", 0) or 0) for result in results)
    real_calls = bool(call_reservation_attested and call_count > 0)
    attested_envelopes = sum(
        _attested_anthropic_envelope(result, model_id) for result in results
    )
    response_ids = {
        str(result.get("request_id"))
        for result in results
        if _attested_anthropic_envelope(result, model_id)
    }
    gate_pass = all(
        (
            real_calls,
            call_count == 20,
            call_reservation_attested,
            delivered_result_attestation_count == 20,
            attested_envelopes == 20,
            len(response_ids) == 20,
            processable == 20,
            schema_valid == 20,
            identity_correct >= 18,
            behavior_correct >= 17,
            features_full >= 18,
            clarification_correct == 2,
            substitutions == 0,
            retries == 0,
            secret_scan_passed,
            scope_unchanged,
        )
    )
    return {
        "status": "GATE A PASS" if gate_pass else "NEEDS WORK",
        "provider": "anthropic",
        "endpoint": APPROVED_ENDPOINT,
        "model_id": model_id,
        "contract_version": CONTRACT_VERSION,
        "run_id": run_id,
        "real_ai_calls_performed": real_calls,
        "call_count": call_count,
        "attested_anthropic_envelope_count": attested_envelopes,
        "unique_provider_response_id_count": len(response_ids),
        "call_reservation_attested": call_reservation_attested,
        "delivered_result_attestation_count": delivered_result_attestation_count,
        "processable_results": processable,
        "schema_valid_count": schema_valid,
        "identity_correct_count": identity_correct,
        "behavior_correct_count": behavior_correct,
        "preserved_features_quality_2_count": features_full,
        "clarification_correct_count": clarification_correct,
        "fixed_weapon_substitution_count": substitutions,
        "automatic_retry_count": retries,
        "secret_scan_passed": secret_scan_passed,
        "scope_hash_verified": bool(scope_unchanged),
        "usage": {
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
            "cache_creation_input_tokens": cache_creation,
            "cache_read_input_tokens": cache_read,
        },
        "cost": calculate_cost(input_tokens, output_tokens),
        "gate_b_recommended": gate_pass,
        "gate_b_executed": False,
        "comfyui_started": False,
        "v2_started": False,
        "gameplay_or_rooms_modified": not bool(scope_unchanged),
    }


def _report_markdown(summary: dict[str, Any], rows: list[dict[str, Any]]) -> str:
    lines = [
        "# Forge Multilingual Semantic Compiler Spike 3 — Gate A",
        "",
        f"Status: **{summary['status']}**",
        "",
        "- Provider: Anthropic official Messages API at https://api.anthropic.com/v1/messages",
        f"- Exact model ID: {summary['model_id']}",
        f"- Real AI calls performed: {str(summary['real_ai_calls_performed']).lower()}",
        f"- Calls: {summary['call_count']} (automatic retries: {summary['automatic_retry_count']})",
        f"- Attested Anthropic envelopes: {summary['attested_anthropic_envelope_count']}/20",
        f"- Persistent call reservation attested: {str(summary['call_reservation_attested']).lower()}",
        f"- Delivered result files attested: {summary['delivered_result_attestation_count']}/20",
        f"- Unique provider response IDs: {summary['unique_provider_response_id_count']}/20",
        f"- Processable results: {summary['processable_results']}/20",
        f"- Structured Schema valid: {summary['schema_valid_count']}/20",
        f"- Identity correct: {summary['identity_correct_count']}/20",
        f"- Behavior correct: {summary['behavior_correct_count']}/20",
        f"- Preserved-features quality 2: {summary['preserved_features_quality_2_count']}/20",
        f"- Clarification correct: {summary['clarification_correct_count']}/2",
        f"- Fixed weapon substitutions: {summary['fixed_weapon_substitution_count']}",
        f"- Token usage: input {summary['usage']['input_tokens']}, output {summary['usage']['output_tokens']}, "
        f"cache creation {summary['usage']['cache_creation_input_tokens']}, cache read {summary['usage']['cache_read_input_tokens']}",
        f"- Cost: {summary['cost']['status']}"
        + (
            f" — estimated USD {summary['cost']['estimated_cost']}"
            if summary["cost"]["estimated_cost"] is not None
            else ""
        ),
        f"- Gate B recommended: {str(summary['gate_b_recommended']).lower()} "
        "(separate user approval is still required)",
        "",
        "## Per-case review",
        "",
        "| Case | API | Result | Schema | Identity | Behavior | Features | Clarification | Fixed substitution | Reason |",
        "|---|---:|---|---:|---:|---:|---:|---:|---:|---|",
    ]
    for row in rows:
        reason = str(row["reviewer_reason"]).replace("|", "/").replace("\n", " ").strip()
        display = dict(row)
        display["reason"] = reason
        lines.append(
            "| {case_id} | {api_status} | {result_type} | {schema_valid} | {identity_correct} | "
            "{behavior_correct} | {preserved_features_quality} | {clarification_correct} | "
            "{fixed_weapon_substitution} | {reason} |".format(**display)
        )
    failures: list[str] = []
    for row in rows:
        if row["result_type"] == "needs_clarification":
            case_passed = bool(row["schema_valid"] and row["clarification_correct"])
        else:
            case_passed = bool(
                row["result_type"] == "compiled"
                and row["schema_valid"]
                and row["identity_correct"]
                and row["behavior_correct"]
                and int(row["preserved_features_quality"]) == 2
                and not row["fixed_weapon_substitution"]
            )
        if not case_passed:
            safe_reason = (
                str(row["reviewer_reason"] or "UNKNOWN_FAILURE")
                .replace("\r", " ")
                .replace("\n", " ")
            )
            failures.append(f"- {row['case_id']}: {safe_reason}")
    lines.extend(
        [
            "",
            "## Failures",
            "",
            *(failures or ["- None."]),
            "",
            "## Boundary declaration",
            "",
            "- ComfyUI was not started.",
            "- Gate B was not executed.",
            "- V2 was not started.",
            (
                "- Protected gameplay, Web, ComfyUI, art, and room files match the pre-execution scope hash."
                if summary["scope_hash_verified"]
                else "- Protected-scope verification failed; no unchanged-scope claim is made."
            ),
            "- A passing Gate A still requires separate user approval before Gate B.",
            "",
        ]
    )
    return "\n".join(lines)


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _redacted_response_document(value: Any) -> Any:
    if not isinstance(value, str):
        return value
    try:
        decoded = json.loads(value)
    except json.JSONDecodeError:
        return {"redacted_text": value}
    return decoded


def write_gate_a_reports(
    *,
    semantic_root: Path,
    run_id: str,
    model_id: str,
    results: list[dict[str, Any]],
    scores: list[dict[str, Any]],
    output_run_directory: Path,
    secret_scan_passed: bool,
    actual_call_count: int,
    scope_unchanged: bool,
    pre_publish_validator: Callable[[Path], bool] | None = None,
) -> dict[str, Any]:
    reports = semantic_root / "reports"
    reservation_attested = _call_reservation_attested(
        semantic_root, run_id, actual_call_count
    )
    delivered_attestation_count = _delivered_result_attestation_count(
        output_run_directory, results
    )
    run_reports = reports / "runs" / run_id
    redacted_root = reports / "raw_response_redacted" / run_id
    compiled_root = reports / "compiled_blueprints" / run_id
    if run_reports.exists() or redacted_root.exists() or compiled_root.exists():
        raise FileExistsError("IMMUTABLE_GATE_A_RUN_REPORT_ALREADY_EXISTS")
    run_reports.mkdir(parents=True, exist_ok=False)
    pending = run_reports / ".pending"
    pending.mkdir()
    rows = _score_rows(results, scores)
    summary = _gate_summary(
        run_id=run_id,
        model_id=model_id,
        results=results,
        rows=rows,
        secret_scan_passed=secret_scan_passed,
        actual_call_count=actual_call_count,
        scope_unchanged=scope_unchanged,
        call_reservation_attested=reservation_attested,
        delivered_result_attestation_count=delivered_attestation_count,
    )
    csv_text = _csv_text(rows)
    markdown_text = _report_markdown(summary, rows)
    _atomic_write_text(pending / "gate_a_results.csv", csv_text)
    _atomic_write_json(pending / "gate_a_summary.json", summary)
    _atomic_write_text(pending / "GATE_A_REPORT.md", markdown_text)
    pending_redacted = pending / "raw_response_redacted"
    pending_compiled = pending / "compiled_blueprints"
    pending_redacted.mkdir()
    pending_compiled.mkdir()
    for result in results:
        case_id = str(result.get("case_id", ""))
        if not case_id or any(
            character not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
            for character in case_id
        ):
            raise ValueError("UNSAFE_CASE_ID_IN_REPORT")
        raw_path = pending_redacted / f"{case_id}.json"
        _atomic_write_json(
            raw_path,
            _redacted_response_document(result.get("raw_response_redacted", {})),
        )
        if result.get("result_type") == "compiled" and isinstance(result.get("result"), dict):
            compiled_path = pending_compiled / f"{case_id}.json"
            _atomic_write_json(compiled_path, result["result"])

    if pre_publish_validator is not None and pre_publish_validator(pending) is not True:
        # The pending tree may itself contain the detected credential. Remove
        # every staged raw/compiled/report artifact and retain only a key-free
        # marker outside that tree.
        if pending.name != ".pending" or pending.parent != run_reports:
            raise RuntimeError("UNSAFE_PENDING_REPORT_PATH")
        shutil.rmtree(pending)
        _atomic_write_json(
            run_reports / "PUBLISH_BLOCKED.json",
            {
                "run_id": run_id,
                "status": "NEEDS WORK",
                "reason": "PRE_PUBLISH_SECRET_SCAN_FAILED",
            },
        )
        raise PermissionError("PRE_PUBLISH_SECRET_SCAN_FAILED")

    for name in ("gate_a_results.csv", "gate_a_summary.json", "GATE_A_REPORT.md"):
        os.replace(pending / name, run_reports / name)
    redacted_root.parent.mkdir(parents=True, exist_ok=True)
    compiled_root.parent.mkdir(parents=True, exist_ok=True)
    os.replace(pending_redacted, redacted_root)
    os.replace(pending_compiled, compiled_root)
    pending.rmdir()

    evidence_paths: list[Path] = [
        run_reports / "gate_a_results.csv",
        run_reports / "gate_a_summary.json",
        run_reports / "GATE_A_REPORT.md",
    ]
    evidence_paths.extend(path for path in redacted_root.glob("*.json") if path.is_file())
    evidence_paths.extend(path for path in compiled_root.glob("*.json") if path.is_file())
    for result in results:
        delivered_result = output_run_directory / str(result.get("case_id", "")) / "result.json"
        if delivered_result.is_file():
            evidence_paths.append(delivered_result)

    reservation = reports / "gate_a_real_call_reservation.json"
    if reservation.is_file():
        evidence_paths.append(reservation)

    evidence = {
        "algorithm": "SHA-256",
        "run_id": run_id,
        "files": {
            path.relative_to(semantic_root).as_posix(): _sha256(path)
            for path in sorted(set(evidence_paths), key=str)
        },
    }
    _atomic_write_json(run_reports / "evidence_hashes.json", evidence)
    _atomic_write_json(
        run_reports / "COMPLETE.json",
        {
            "run_id": run_id,
            "status": "complete",
            "evidence_sha256": _sha256(run_reports / "evidence_hashes.json"),
        },
    )

    # These four top-level files are an atomic-per-file convenience view of the
    # latest authorized run. The immutable run-specific evidence above is never
    # replaced, including when a later run is explicitly authorized.
    _atomic_write_text(reports / "gate_a_results.csv", csv_text)
    _atomic_write_json(reports / "gate_a_summary.json", summary)
    _atomic_write_text(reports / "GATE_A_REPORT.md", markdown_text)
    _atomic_write_json(reports / "evidence_hashes.json", evidence)
    return summary
