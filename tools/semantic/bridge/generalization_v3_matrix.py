from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
from typing import Any, Mapping, Sequence


SCHEMA = "sunny-generalization-matrix-v3"
REPORT_SCHEMA = "sunny-generalization-v3-report-v1"
SUPPORTED = "improvised_object_supported"
ALLOWED_CHECK_PATHS = {
    "declaration.activation_mode",
    "declaration.body_length",
    "declaration.contact_surface",
    "declaration.flex_topology",
    "declaration.functional_output",
    "declaration.handle_length",
    "declaration.rigidity",
    "declaration.state_topology",
    "declaration.terminal_load",
    "declaration.tether_topology",
}


def select_samples(samples: Sequence[dict[str, Any]], sample_ids: str = "") -> list[dict[str, Any]]:
    requested = [item.strip() for item in sample_ids.split(",") if item.strip()]
    if not requested:
        return list(samples)
    if len(requested) != len(set(requested)):
        raise MatrixError("MATRIX_SAMPLE_IDS_DUPLICATE")
    known = {str(sample["id"]): sample for sample in samples}
    if any(sample_id not in known for sample_id in requested):
        raise MatrixError("MATRIX_SAMPLE_ID_UNKNOWN")
    requested_set = set(requested)
    return [sample for sample in samples if str(sample["id"]) in requested_set]


class MatrixError(RuntimeError):
    pass


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise MatrixError("MATRIX_JSON_INVALID") from exc
    if not isinstance(value, dict):
        raise MatrixError("MATRIX_ROOT_INVALID")
    return value


def atomic_write(path: Path, value: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(temporary, path)


def selected_indices(seed: int, count: int) -> list[int]:
    value = seed & 0xFFFFFFFF
    indices: list[int] = []
    for _ in range(count):
        value = (1664525 * value + 1013904223) & 0xFFFFFFFF
        indices.append(value % 4)
    return indices


def validate_manifest(value: Mapping[str, Any]) -> list[dict[str, Any]]:
    if value.get("schema") != SCHEMA:
        raise MatrixError("MATRIX_SCHEMA_INVALID")
    pools = value.get("pools")
    samples = value.get("samples")
    if not isinstance(pools, list) or not isinstance(samples, list) or len(pools) != 12 or len(samples) != 12:
        raise MatrixError("MATRIX_SAMPLE_COUNT_INVALID")
    if value.get("semantic_request_limit") != 12 or value.get("visual_promotion_limit") != 2:
        raise MatrixError("MATRIX_BUDGET_INVALID")
    indices = selected_indices(int(value.get("seed", -1)), len(pools))
    validated: list[dict[str, Any]] = []
    groups: set[str] = set()
    for ordinal, (pool, sample, expected_index) in enumerate(zip(pools, samples, indices), start=1):
        if not isinstance(pool, dict) or not isinstance(sample, dict):
            raise MatrixError("MATRIX_CASE_INVALID")
        group = str(pool.get("group", ""))
        candidates = pool.get("candidates")
        expectation = pool.get("expect")
        if not group or group in groups or not isinstance(candidates, list) or len(candidates) != 4:
            raise MatrixError("MATRIX_POOL_INVALID")
        if not isinstance(expectation, dict) or expectation.get("policy") not in {"supported_object", "safe_route"}:
            raise MatrixError("MATRIX_EXPECTATION_INVALID")
        groups.add(group)
        if sample.get("id") != f"v3-{ordinal:02d}" or sample.get("group") != group:
            raise MatrixError("MATRIX_SAMPLE_ORDER_INVALID")
        if sample.get("candidate_index") != expected_index or sample.get("identity") != candidates[expected_index]:
            raise MatrixError("MATRIX_FROZEN_SELECTION_MISMATCH")
        checks = expectation.get("checks", [])
        if not isinstance(checks, list):
            raise MatrixError("MATRIX_CHECKS_INVALID")
        for check in checks:
            if not isinstance(check, dict) or set(check) != {"path", "in"}:
                raise MatrixError("MATRIX_CHECK_INVALID")
            if check.get("path") not in ALLOWED_CHECK_PATHS or not isinstance(check.get("in"), list) or not check["in"]:
                raise MatrixError("MATRIX_CHECK_INVALID")
        validated.append({**sample, "expect": expectation})
    return validated


def dotted_get(value: Mapping[str, Any], path: str) -> Any:
    current: Any = value
    for part in path.split("."):
        if not isinstance(current, Mapping) or part not in current:
            return None
        current = current[part]
    return current


def evaluate_record(sample: Mapping[str, Any], result: Mapping[str, Any]) -> dict[str, Any]:
    expectation = sample["expect"]
    status = str(result.get("status", "failed"))
    response = result.get("response") if isinstance(result.get("response"), Mapping) else {}
    classification = str(response.get("classification", ""))
    mismatches: list[dict[str, Any]] = []
    if expectation["policy"] == "safe_route":
        allowed = expectation.get("classifications", [])
        passed = status == "success" and classification in allowed
        if not passed:
            mismatches.append({"path": "classification", "actual": classification, "expected": allowed})
    else:
        passed = status == "success" and classification == SUPPORTED
        if classification != SUPPORTED:
            mismatches.append({"path": "classification", "actual": classification, "expected": [SUPPORTED]})
        for check in expectation.get("checks", []):
            actual = dotted_get(response, str(check["path"]))
            if actual not in check["in"]:
                mismatches.append({"path": check["path"], "actual": actual, "expected": check["in"]})
        passed = passed and not mismatches
    declaration = response.get("declaration") if isinstance(response.get("declaration"), Mapping) else {}
    axis_signature = json.dumps(declaration, ensure_ascii=False, sort_keys=True, separators=(",", ":")) if declaration else ""
    return {
        "id": sample["id"],
        "group": sample["group"],
        "identity": sample["identity"],
        "policy": expectation["policy"],
        "status": status,
        "classification": classification,
        "passed": passed,
        "failure_reason": str(result.get("failure_reason", "")),
        "mismatches": mismatches,
        "axis_signature": axis_signature,
        "response": dict(response),
        "usage": dict(result.get("usage", {})) if isinstance(result.get("usage"), Mapping) else {},
    }


def summarize(records: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    generated = [record for record in records if record.get("policy") == "supported_object"]
    routed = [record for record in records if record.get("policy") == "safe_route"]
    signatures: dict[str, list[str]] = {}
    coverage: dict[str, set[str]] = {}
    total_usage: dict[str, int] = {}
    for record in generated:
        signature = str(record.get("axis_signature", ""))
        if signature:
            signatures.setdefault(signature, []).append(str(record.get("id", "")))
        response = record.get("response", {})
        declaration = response.get("declaration", {}) if isinstance(response, Mapping) else {}
        if isinstance(declaration, Mapping):
            for key, item in declaration.items():
                coverage.setdefault(str(key), set()).add(str(item).lower() if isinstance(item, bool) else str(item))
        usage = record.get("usage", {})
        if isinstance(usage, Mapping):
            for key, item in usage.items():
                if isinstance(item, int) and not isinstance(item, bool):
                    total_usage[str(key)] = total_usage.get(str(key), 0) + item
    duplicates = [ids for ids in signatures.values() if len(ids) > 1]
    return {
        "sample_count": len(records),
        "passed_count": sum(bool(record.get("passed")) for record in records),
        "supported_expected": len(generated),
        "supported_passed": sum(bool(record.get("passed")) for record in generated),
        "safe_route_expected": len(routed),
        "safe_route_passed": sum(bool(record.get("passed")) for record in routed),
        "semantic_success_count": sum(record.get("status") == "success" for record in records),
        "unique_axis_signatures": len(signatures),
        "duplicate_axis_signature_groups": duplicates,
        "axis_value_coverage": {key: sorted(values) for key, values in sorted(coverage.items())},
        "usage": total_usage,
    }


def run_live(manifest_path: Path, output_dir: Path, bridge_path: Path, sample_ids: str = "") -> int:
    if not os.environ.get("ANTHROPIC_API_KEY", "").strip():
        raise MatrixError("ANTHROPIC_API_KEY_MISSING")
    manifest = read_json(manifest_path)
    samples = select_samples(validate_manifest(manifest), sample_ids)
    output_dir.mkdir(parents=True, exist_ok=True)
    atomic_write(output_dir / "samples.json", manifest)
    budget = {"semantic_request_limit": len(samples), "visual_request_limit": 0, "selected_cases": [sample["id"] for sample in samples], "started_cases": []}
    atomic_write(output_dir / "budget.json", budget)
    records: list[dict[str, Any]] = []
    for sample in samples:
        case_dir = output_dir / str(sample["id"])
        case_dir.mkdir(parents=True, exist_ok=True)
        budget["started_cases"].append(sample["id"])
        atomic_write(output_dir / "budget.json", budget)
        request_path = case_dir / "request.json"
        atomic_write(request_path, {"schema": "forge-general-object-ai-request-v1", "identity": sample["identity"]})
        completed = subprocess.run(
            [sys.executable, "-E", "-S", "-B", str(bridge_path), "--request", str(request_path), "--output-dir", str(case_dir)],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=os.environ.copy(),
        )
        result_path = case_dir / "result.json"
        result = read_json(result_path) if result_path.is_file() else {"status": "failed", "failure_reason": "MATRIX_BRIDGE_RESULT_MISSING"}
        record = evaluate_record(sample, result)
        record["bridge_exit_code"] = completed.returncode
        records.append(record)
        atomic_write(case_dir / "record.json", record)
        report = {"schema": REPORT_SCHEMA, "mode": "live_semantic_only", "semantic_entry_attempts": len(records), "online_visual_requests": 0, "records": records, "summary": summarize(records)}
        atomic_write(output_dir / "report.json", report)
        reason = str(record.get("failure_reason", ""))
        if any(marker in reason for marker in ("AUTH", "KEY_MISSING", "BALANCE", "MISSING_MODEL_ID")):
            break
    final_summary = summarize(records)
    report = {"schema": REPORT_SCHEMA, "mode": "live_semantic_only", "semantic_entry_attempts": len(records), "online_visual_requests": 0, "records": records, "summary": final_summary}
    atomic_write(output_dir / "report.json", report)
    return 0 if len(records) == len(samples) and final_summary["passed_count"] == len(samples) else 1


def run_recheck(manifest_path: Path, output_dir: Path, result_roots: Sequence[Path]) -> int:
    manifest = read_json(manifest_path)
    samples = validate_manifest(manifest)
    roots = [root.resolve() for root in result_roots]
    if not roots:
        raise MatrixError("MATRIX_RESULTS_SOURCE_REQUIRED")
    records: list[dict[str, Any]] = []
    output_dir.mkdir(parents=True, exist_ok=True)
    atomic_write(output_dir / "samples.json", manifest)
    for sample in samples:
        result_path: Path | None = None
        for root in reversed(roots):
            candidate = root / str(sample["id"]) / "result.json"
            if candidate.is_file():
                result_path = candidate
                break
        result = read_json(result_path) if result_path is not None else {"status": "failed", "failure_reason": "MATRIX_SOURCE_RESULT_MISSING"}
        record = evaluate_record(sample, result)
        record["source_result"] = str(result_path) if result_path is not None else ""
        records.append(record)
    summary = summarize(records)
    report = {
        "schema": REPORT_SCHEMA,
        "mode": "offline_recheck",
        "semantic_entry_attempts": 0,
        "online_visual_requests": 0,
        "source_roots": [str(root) for root in roots],
        "records": records,
        "summary": summary,
    }
    atomic_write(output_dir / "report.json", report)
    return 0 if summary["passed_count"] == len(samples) else 1


def run_plan(manifest_path: Path, output_dir: Path) -> int:
    manifest = read_json(manifest_path)
    samples = validate_manifest(manifest)
    output_dir.mkdir(parents=True, exist_ok=True)
    atomic_write(output_dir / "samples.json", manifest)
    atomic_write(output_dir / "report.json", {"schema": REPORT_SCHEMA, "mode": "offline_plan", "semantic_entry_attempts": 0, "online_visual_requests": 0, "records": [{"id": sample["id"], "group": sample["group"], "identity": sample["identity"], "policy": sample["expect"]["policy"]} for sample in samples], "summary": {"sample_count": len(samples), "request_limit": manifest["semantic_request_limit"], "visual_promotion_limit": manifest["visual_promotion_limit"]}})
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--bridge", type=Path)
    parser.add_argument("--allow-live-semantic", action="store_true")
    parser.add_argument("--sample-ids", default="")
    parser.add_argument("--results-from", action="append", type=Path, default=[])
    args = parser.parse_args(argv)
    try:
        if args.allow_live_semantic and args.results_from:
            raise MatrixError("MATRIX_MODE_CONFLICT")
        if args.results_from:
            if args.sample_ids:
                raise MatrixError("MATRIX_RECHECK_SAMPLE_FILTER_UNSUPPORTED")
            return run_recheck(args.manifest.resolve(), args.output_dir.resolve(), args.results_from)
        if args.allow_live_semantic:
            if args.bridge is None:
                raise MatrixError("MATRIX_BRIDGE_REQUIRED")
            return run_live(args.manifest.resolve(), args.output_dir.resolve(), args.bridge.resolve(), args.sample_ids)
        return run_plan(args.manifest.resolve(), args.output_dir.resolve())
    except MatrixError as exc:
        atomic_write(args.output_dir.resolve() / "report.json", {"schema": REPORT_SCHEMA, "mode": "failed", "failure_reason": str(exc), "semantic_entry_attempts": 0, "online_visual_requests": 0})
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
