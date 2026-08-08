#!/usr/bin/env python3
"""Measure whether anonymous affordance axes reach the existing combat runtime."""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import os
import shutil
import subprocess
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping, Sequence


RAW_SCHEMA = "forge-affordance-runtime-realization-raw-v1"
MECHANISM_EXPECTATION = "runtime_effect"
INVARIANT_EXPECTATION = "invariant"
EPSILON = 1.0e-6


class RuntimeRealizationAuditError(RuntimeError):
    pass


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _stable_hash(value: Any) -> str:
    payload = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _json_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, indent=2).encode("utf-8") + b"\n"


def _write_new(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(_json_bytes(value))
        stream.flush()
        os.fsync(stream.fileno())


def _write_text_new(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(value.encode("utf-8"))
        stream.flush()
        os.fsync(stream.fileno())


def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RuntimeRealizationAuditError(f"Cannot read JSON: {path}") from exc


def _find_godot(repo_root: Path) -> Path:
    candidates = [
        repo_root / ".tools" / "Godot_v4.7.1-stable_win64_console.exe",
        repo_root.parent / "project forge" / ".tools" / "Godot_v4.7.1-stable_win64_console.exe",
    ]
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    for name in ("godot4.7.1", "godot4", "godot"):
        found = shutil.which(name)
        if found:
            return Path(found)
    raise RuntimeRealizationAuditError("Godot 4.7.1 console executable was not found.")


def _profile_runtime_payload(profile: Mapping[str, Any]) -> dict[str, Any]:
    value = json.loads(json.dumps(profile, ensure_ascii=False))
    value.pop("mechanism_axes", None)
    value.pop("primitive_scores", None)
    value.pop("compile_trace", None)
    recipe = value.get("combo_recipe")
    if isinstance(recipe, dict):
        for field in ("recipe_signature", "compile_reason", "mechanism_axes", "primitive_scores"):
            recipe.pop(field, None)
    return value


def _metric(runtime: Mapping[str, Any], path: str) -> Any:
    value: Any = runtime
    for segment in path.split("/"):
        if not segment:
            continue
        if isinstance(value, Mapping) and segment in value:
            value = value[segment]
            continue
        if isinstance(value, list) and segment.isdigit() and int(segment) < len(value):
            value = value[int(segment)]
            continue
        else:
            raise RuntimeRealizationAuditError(f"Runtime metric does not exist: {path}")
    return value


def _contract(metric: str, operator: str, reference: str = "baseline") -> dict[str, str]:
    return {"metric": metric, "operator": operator, "reference": reference}


CONTRACTS: dict[str, list[dict[str, str]]] = {
    "handle_short": [
        _contract("combo/root_motion_total", "lt"),
        _contract("combo/forward_extent", "lt"),
        _contract("combo/collision_area", "lt"),
    ],
    "handle_long": [
        _contract("combo/root_motion_total", "gt"),
        _contract("combo/forward_extent", "gt"),
        _contract("combo/collision_area", "gt"),
    ],
    "body_short": [
        _contract("combo/root_motion_total", "lt"),
        _contract("combo/forward_extent", "lt"),
        _contract("combo/collision_area", "lt"),
    ],
    "body_long": [
        _contract("combo/root_motion_total", "gt"),
        _contract("combo/forward_extent", "gt"),
        _contract("combo/collision_area", "gt"),
    ],
    "grip_two_hand": [_contract("two_hand_support_drawn", "true")],
    "grip_clamp": [
        _contract("combo/startup_total", "lt"),
        _contract("combo/recovery_total", "lt"),
        _contract("combo/movement_allowed_average", "lt"),
    ],
    "grip_handleless_body": [
        _contract("grip_mode", "eq_value:center"),
        _contract("combo/root_motion_total", "lt"),
        _contract("combo/forward_extent", "lt"),
    ],
    "rigidity_semi": [_contract("combo/collision_area", "gt")],
    "rigidity_flexible": [_contract("combo/collision_area", "gt", "rigidity_semi")],
    "mass_rear": [
        _contract("combo/startup_total", "lt"),
        _contract("combo/knockback_total", "lt"),
    ],
    "mass_front": [
        _contract("combo/startup_total", "gt"),
        _contract("combo/recovery_total", "gt"),
        _contract("combo/knockback_total", "gt"),
        _contract("combo/hitstop_total", "gt"),
    ],
    "primary_point": [
        _contract("combo/collision_area", "lt"),
        _contract("combo/vertical_span", "lt"),
    ],
    "primary_edge": [
        _contract("combo/collision_area", "gt", "primary_point"),
        _contract("combo/vertical_span", "gt", "primary_point"),
    ],
    "primary_whole_body": [
        _contract("combo/collision_area", "gt"),
        _contract("combo/movement_allowed_average", "gt"),
    ],
    "secondary_point": [_contract("combo/knockback_total", "gt")],
    "secondary_edge": [_contract("combo/knockback_total", "gt", "secondary_point")],
    "secondary_broad": [_contract("combo/knockback_total", "gt", "secondary_edge")],
    "secondary_whole_body": [_contract("combo/knockback_total", "gt", "secondary_broad")],
    "feature_point": [_contract("hits/1/forward_extent", "gt")],
    "feature_edge": [_contract("combo/collision_area", "gt")],
    "feature_broad_face": [_contract("combo/collision_area", "gt")],
    "feature_barrel": [
        _contract("combo/root_motion_total", "gt"),
        _contract("combo/forward_extent", "gt"),
    ],
    "feature_stock": [_contract("", "runtime_diff")],
}


def _evaluate_contract(
    contract: Mapping[str, str],
    runtime: Mapping[str, Any],
    reference_runtime: Mapping[str, Any],
) -> dict[str, Any]:
    metric_path = contract["metric"]
    operator = contract["operator"]
    if operator == "runtime_diff":
        actual = _stable_hash(runtime)
        expected = _stable_hash(reference_runtime)
        passed = actual != expected
    else:
        actual = _metric(runtime, metric_path)
        if operator == "true":
            expected = True
            passed = actual is True
        elif operator.startswith("eq_value:"):
            expected = operator.split(":", 1)[1]
            passed = actual == expected
        else:
            expected = _metric(reference_runtime, metric_path)
            if not isinstance(actual, (int, float)) or not isinstance(expected, (int, float)):
                raise RuntimeRealizationAuditError(f"Non-numeric monotonic contract: {metric_path}")
            if operator == "gt":
                passed = float(actual) > float(expected) + EPSILON
            elif operator == "lt":
                passed = float(actual) < float(expected) - EPSILON
            else:
                raise RuntimeRealizationAuditError(f"Unknown contract operator: {operator}")
    return {
        "metric": metric_path or "complete_runtime",
        "operator": operator,
        "reference": contract.get("reference", "baseline"),
        "actual": actual,
        "expected_reference": expected,
        "passed": passed,
    }


def analyze_raw(raw: Mapping[str, Any]) -> dict[str, Any]:
    if raw.get("schema") != RAW_SCHEMA or raw.get("identity_inputs_used") is not False:
        raise RuntimeRealizationAuditError("Raw runtime-realization boundary is invalid.")
    if raw.get("runtime_weights_modified") is not False:
        raise RuntimeRealizationAuditError("Runtime-realization audit must not modify Grammar weights.")
    scenarios = raw.get("scenarios")
    frozen_cases = raw.get("frozen_cases")
    baseline_record = raw.get("baseline")
    if not isinstance(scenarios, list) or len(scenarios) != 25:
        raise RuntimeRealizationAuditError("Expected exactly 25 anonymous scenarios.")
    if not isinstance(frozen_cases, list) or len(frozen_cases) != 12:
        raise RuntimeRealizationAuditError("Expected exactly 12 frozen coverage profiles.")
    if not isinstance(baseline_record, Mapping) or baseline_record.get("ok") is not True:
        raise RuntimeRealizationAuditError("Anonymous baseline did not compile and execute.")
    baseline_runtime = baseline_record.get("runtime")
    baseline_profile = baseline_record.get("profile")
    if not isinstance(baseline_runtime, Mapping) or not isinstance(baseline_profile, Mapping):
        raise RuntimeRealizationAuditError("Anonymous baseline lacks runtime evidence.")
    records_by_id = {str(record.get("id")): record for record in scenarios if isinstance(record, Mapping)}
    if len(records_by_id) != 25:
        raise RuntimeRealizationAuditError("Scenario IDs are missing or duplicated.")
    rows: list[dict[str, Any]] = []
    for record in scenarios:
        scenario_id = str(record["id"])
        expectation = str(record.get("expected"))
        runtime = record.get("runtime")
        profile = record.get("profile")
        if record.get("ok") is not True or not isinstance(runtime, Mapping) or not isinstance(profile, Mapping):
            raise RuntimeRealizationAuditError(f"Scenario did not execute: {scenario_id}")
        runtime_changed = _stable_hash(runtime) != _stable_hash(baseline_runtime)
        profile_changed = _stable_hash(_profile_runtime_payload(profile)) != _stable_hash(_profile_runtime_payload(baseline_profile))
        if expectation == INVARIANT_EXPECTATION:
            contract_results = [
                {
                    "metric": "complete_runtime",
                    "operator": "invariant",
                    "reference": "baseline",
                    "actual": _stable_hash(runtime),
                    "expected_reference": _stable_hash(baseline_runtime),
                    "passed": not runtime_changed,
                }
            ]
            passed = not runtime_changed
            classification = "INVARIANT_PASS" if passed else "INVARIANT_VIOLATION"
        elif expectation == MECHANISM_EXPECTATION:
            definitions = CONTRACTS.get(scenario_id)
            if not definitions:
                raise RuntimeRealizationAuditError(f"No monotonic property contract for {scenario_id}")
            contract_results = []
            for definition in definitions:
                reference_id = definition.get("reference", "baseline")
                if reference_id == "baseline":
                    reference_runtime = baseline_runtime
                else:
                    reference_record = records_by_id.get(reference_id)
                    if not isinstance(reference_record, Mapping) or not isinstance(reference_record.get("runtime"), Mapping):
                        raise RuntimeRealizationAuditError(f"Missing contract reference: {reference_id}")
                    reference_runtime = reference_record["runtime"]
                contract_results.append(_evaluate_contract(definition, runtime, reference_runtime))
            passed = all(bool(result["passed"]) for result in contract_results)
            if passed:
                classification = "RUNTIME_PROPERTY_PASS"
            elif profile_changed and not runtime_changed:
                classification = "PROFILE_ONLY_NOT_REALIZED"
            elif runtime_changed:
                classification = "RUNTIME_WRONG_DIRECTION_OR_INCOMPLETE"
            else:
                classification = "RUNTIME_SILENT"
        else:
            raise RuntimeRealizationAuditError(f"Unknown expectation for {scenario_id}")
        combo = runtime["combo"]
        baseline_combo = baseline_runtime["combo"]
        rows.append(
            {
                "id": scenario_id,
                "axis": str(record["axis"]),
                "changes": json.dumps(record.get("changes", {}), ensure_ascii=False, sort_keys=True, separators=(",", ":")),
                "expected": expectation,
                "passed": passed,
                "classification": classification,
                "profile_changed": profile_changed,
                "runtime_changed": runtime_changed,
                "sequence": " -> ".join(str(item) for item in runtime["primitive_sequence"]),
                "collision_area_delta": float(combo["collision_area"]) - float(baseline_combo["collision_area"]),
                "forward_extent_delta": float(combo["forward_extent"]) - float(baseline_combo["forward_extent"]),
                "root_motion_delta": float(combo["root_motion_total"]) - float(baseline_combo["root_motion_total"]),
                "knockback_delta": float(combo["knockback_total"]) - float(baseline_combo["knockback_total"]),
                "failed_contracts": [result["metric"] for result in contract_results if not result["passed"]],
                "contracts": contract_results,
            }
        )
    mechanism_rows = [row for row in rows if row["expected"] == MECHANISM_EXPECTATION]
    invariant_rows = [row for row in rows if row["expected"] == INVARIANT_EXPECTATION]
    failed_rows = [row for row in mechanism_rows if not row["passed"]]
    failed_invariants = [row for row in invariant_rows if not row["passed"]]
    frozen_summary: list[dict[str, Any]] = []
    for record in frozen_cases:
        runtime = record["runtime"]
        combo = runtime["combo"]
        frozen_summary.append(
            {
                "case_id": str(record["case_id"]),
                "sequence": " -> ".join(str(item) for item in runtime["primitive_sequence"]),
                "collision_area": combo["collision_area"],
                "formation_hit_count": combo["formation_hit_count"],
                "forward_extent": combo["forward_extent"],
                "root_motion_total": combo["root_motion_total"],
                "startup_total": combo["startup_total"],
                "recovery_total": combo["recovery_total"],
                "knockback_total": combo["knockback_total"],
            }
        )
    status = "PASS" if not failed_rows and not failed_invariants else "NEEDS_WORK"
    return {
        "status": status,
        "scenario_count": len(rows),
        "mechanism_probe_count": len(mechanism_rows),
        "mechanism_pass_count": sum(bool(row["passed"]) for row in mechanism_rows),
        "invariant_probe_count": len(invariant_rows),
        "invariant_pass_count": sum(bool(row["passed"]) for row in invariant_rows),
        "failed_probe_ids": [row["id"] for row in failed_rows],
        "failed_invariant_ids": [row["id"] for row in failed_invariants],
        "profile_only_not_realized_ids": [row["id"] for row in failed_rows if row["classification"] == "PROFILE_ONLY_NOT_REALIZED"],
        "wrong_direction_or_incomplete_ids": [row["id"] for row in failed_rows if row["classification"] == "RUNTIME_WRONG_DIRECTION_OR_INCOMPLETE"],
        "baseline_runtime": baseline_runtime,
        "frozen_case_count": len(frozen_summary),
        "frozen_cases": frozen_summary,
        "rows": rows,
    }


def _matrix_csv(rows: Sequence[Mapping[str, Any]]) -> str:
    columns = (
        "id",
        "axis",
        "changes",
        "expected",
        "passed",
        "classification",
        "profile_changed",
        "runtime_changed",
        "sequence",
        "collision_area_delta",
        "forward_extent_delta",
        "root_motion_delta",
        "knockback_delta",
        "failed_contracts",
    )
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=columns, extrasaction="ignore", lineterminator="\n")
    writer.writeheader()
    for row in rows:
        value = dict(row)
        value["failed_contracts"] = "|".join(row["failed_contracts"])
        writer.writerow(value)
    return stream.getvalue()


def _frozen_csv(rows: Sequence[Mapping[str, Any]]) -> str:
    columns = (
        "case_id",
        "sequence",
        "collision_area",
        "formation_hit_count",
        "forward_extent",
        "root_motion_total",
        "startup_total",
        "recovery_total",
        "knockback_total",
    )
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=columns, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return stream.getvalue()


def _report_text(summary: Mapping[str, Any]) -> str:
    lines = [
        "# Anonymous Affordance Runtime Realization Audit",
        "",
        f"Status: **{summary['status']}**",
        "",
        "This offline diagnostic keeps the current orthogonal Grammar weights frozen. It changes anonymous structural axes and measures the existing combat consumers directly: `CombatFeelSlice0._attack_contains`, `CombatMotionProfile.timing_for`, `ImpactFeedbackProfile.for_attack`, root motion, and the current character pose.",
        "",
        "The twelve frozen affordance profiles are coverage witnesses only. They are not pass samples and were not used to tune any rule or weight. The prior three-asset blind comparison also remains historical evidence rather than a tuning target.",
        "",
        "## Result",
        "",
        f"- Monotonic mechanism contracts passed: {summary['mechanism_pass_count']}/{summary['mechanism_probe_count']}",
        f"- Non-mechanical invariants passed: {summary['invariant_pass_count']}/{summary['invariant_probe_count']}",
        f"- Frozen profiles executed through the neutral harness: {summary['frozen_case_count']}/12",
        f"- Profile changes that did not reach measured combat behavior: {', '.join(summary['profile_only_not_realized_ids']) or '-'}",
        f"- Runtime changes with a wrong or incomplete monotonic direction: {', '.join(summary['wrong_direction_or_incomplete_ids']) or '-'}",
        "",
        "## Anonymous one-axis matrix",
        "",
        "| Probe | Axis | Result | Classification | Sequence | Failed runtime properties |",
        "|---|---|---|---|---|---|",
    ]
    for row in summary["rows"]:
        lines.append(
            f"| {row['id']} | {row['axis']} | {'PASS' if row['passed'] else 'FAIL'} | {row['classification']} | `{row['sequence']}` | {', '.join(row['failed_contracts']) or '-'} |"
        )
    lines.extend(
        [
            "",
            "## Frozen coverage profiles",
            "",
            "These rows show diversity under the same neutral runtime geometry. They do not certify feel and do not authorize per-case fixes.",
            "",
            "| Case | Primitive sequence | Collision area | Formation hits | Forward extent | Root motion | Knockback total |",
            "|---|---|---:|---:|---:|---:|---:|",
        ]
    )
    for row in summary["frozen_cases"]:
        lines.append(
            f"| {row['case_id']} | `{row['sequence']}` | {float(row['collision_area']):.0f} | {int(row['formation_hit_count'])} | {float(row['forward_extent']):.0f} | {float(row['root_motion_total']):.2f} | {float(row['knockback_total']):.2f} |"
        )
    lines.extend(["", "## Diagnosis", ""])
    if summary["status"] == "PASS":
        lines.append("All declared anonymous monotonic properties reach the current combat runtime. This is a technical result only; the next human feel validation must use new unseen real assets.")
    else:
        lines.extend(
            [
                "The orthogonal compiler is not yet fully realized by combat. A Compiler/Profile difference is not accepted when collision, timing, root movement, feedback, support-hand participation, or pose remains unchanged.",
                "",
                "The next correction should be limited to the failed generic consumer paths. Do not tune named assets, restore exact legacy recipes, or conduct another three-sample feel pass until this same anonymous matrix passes.",
            ]
        )
    return "\n".join(lines) + "\n"


def _frozen_input_directory(repo_root: Path) -> Path:
    root = repo_root / "tools" / "semantic" / "reports" / "affordance_combined_handoff_v1_2_1"
    candidates = sorted(path for path in root.glob("affordance-combined-v1-2-1-*") if path.is_dir())
    if not candidates:
        raise RuntimeRealizationAuditError("Frozen v1.2.1 affordance handoff was not found.")
    completed = [path for path in candidates if (path / "COMPLETE.json").is_file()]
    if not completed:
        raise RuntimeRealizationAuditError("No completed frozen v1.2.1 affordance handoff was found.")
    return completed[-1]


def run_audit(repo_root: Path, output_directory: Path) -> dict[str, Any]:
    repo_root = repo_root.resolve()
    output_directory = output_directory.resolve()
    if output_directory.exists():
        raise RuntimeRealizationAuditError(f"Output already exists: {output_directory}")
    frozen_root = _frozen_input_directory(repo_root)
    profiles_directory = frozen_root / "affordance_profiles"
    case_order = frozen_root / "case_order.json"
    stage = output_directory.with_name(f".{output_directory.name}.{uuid.uuid4().hex}.tmp")
    stage.mkdir(parents=True)
    try:
        input_files = [case_order, *sorted(profiles_directory.glob("A*.json"))]
        if len(input_files) != 13:
            raise RuntimeRealizationAuditError("Frozen input set must contain case_order plus twelve profiles.")
        input_manifest = {
            "source_directory": str(frozen_root),
            "role": "coverage_evidence_not_tuning_targets",
            "files": {str(path.relative_to(frozen_root)).replace("\\", "/"): _sha256(path) for path in input_files},
        }
        _write_new(stage / "frozen_input_hashes.json", input_manifest)
        raw_path = stage / "runtime_probe_output.json"
        safe_environment = dict(os.environ)
        safe_environment.pop("ANTHROPIC_API_KEY", None)
        safe_environment.pop("FORGE_SEMANTIC_MODEL", None)
        command = [
            str(_find_godot(repo_root)),
            "--headless",
            "--path",
            str(repo_root),
            "--script",
            "res://tools/semantic/scripts/export_affordance_runtime_realization.gd",
            "--",
            f"--output={raw_path}",
            f"--profiles-dir={profiles_directory}",
            f"--case-order={case_order}",
        ]
        completed = subprocess.run(command, cwd=repo_root, env=safe_environment, capture_output=True, text=True, timeout=120, check=False)
        if completed.returncode != 0 or "AFFORDANCE_RUNTIME_REALIZATION_EXPORT=PASS" not in completed.stdout or not raw_path.is_file():
            raise RuntimeRealizationAuditError(f"Godot runtime-realization export failed: {completed.stderr.strip()}")
        raw = _read_json(raw_path)
        summary = analyze_raw(raw)
        summary_without_rows = {key: value for key, value in summary.items() if key != "rows"}
        _write_new(stage / "runtime_realization_summary.json", summary_without_rows)
        _write_text_new(stage / "runtime_realization_matrix.csv", _matrix_csv(summary["rows"]))
        _write_text_new(stage / "frozen_profile_runtime_matrix.csv", _frozen_csv(summary["frozen_cases"]))
        _write_text_new(stage / "AFFORDANCE_RUNTIME_REALIZATION_REPORT.md", _report_text(summary))
        files = {
            path.relative_to(stage).as_posix(): _sha256(path)
            for path in sorted(stage.rglob("*"))
            if path.is_file() and path.name not in {"evidence_hashes.json", "COMPLETE.json"}
        }
        _write_new(stage / "evidence_hashes.json", {"algorithm": "SHA-256", "run_id": output_directory.name, "files": files})
        _write_new(
            stage / "COMPLETE.json",
            {
                "run_id": output_directory.name,
                "status": summary["status"],
                "evidence_sha256": _sha256(stage / "evidence_hashes.json"),
                "completed_at": _utc_now(),
                "network_calls": 0,
                "grammar_weights_modified": False,
            },
        )
        output_directory.parent.mkdir(parents=True, exist_ok=True)
        os.replace(stage, output_directory)
        return summary
    finally:
        if stage.exists():
            shutil.rmtree(stage)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--output-directory", required=True)
    parser.add_argument("--execute-offline-audit", action="store_true")
    args = parser.parse_args(argv)
    if not args.execute_offline_audit:
        print(json.dumps({"status": "PREFLIGHT_PASS", "network_calls": 0, "identity_inputs": 0, "scenario_count": 25, "frozen_case_count": 12}))
        return 0
    repo_root = Path(args.repo_root).resolve()
    output_directory = Path(args.output_directory)
    if not output_directory.is_absolute():
        output_directory = repo_root / output_directory
    summary = run_audit(repo_root, output_directory)
    print(
        json.dumps(
            {
                "status": summary["status"],
                "mechanism_pass_count": summary["mechanism_pass_count"],
                "mechanism_probe_count": summary["mechanism_probe_count"],
                "failed_probe_ids": summary["failed_probe_ids"],
                "output_directory": str(output_directory),
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


__all__ = ["RuntimeRealizationAuditError", "analyze_raw", "run_audit"]
