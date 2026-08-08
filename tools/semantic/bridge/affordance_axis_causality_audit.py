#!/usr/bin/env python3
"""Run and report an offline anonymous affordance-axis causality audit."""

from __future__ import annotations

import argparse
import copy
import csv
import hashlib
import io
import json
import os
import shutil
import subprocess
import uuid
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping, Sequence


RAW_SCHEMA = "forge-affordance-axis-causality-raw-v1"
MECHANISM_EXPECTATION = "runtime_effect"
INVARIANT_EXPECTATION = "invariant"
RECIPE_STAGES = ("hit_1", "hit_2", "hit_3", "charge_attack", "dodge_attack")


class AxisCausalityAuditError(RuntimeError):
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
        raise AxisCausalityAuditError(f"Cannot read audit JSON: {path}") from exc


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
    raise AxisCausalityAuditError("Godot 4.7.1 console executable was not found.")


def _runtime_payload(profile: Mapping[str, Any]) -> dict[str, Any]:
    value = copy.deepcopy(dict(profile))
    value.pop("mechanism_axes", None)
    value.pop("primitive_scores", None)
    value.pop("compile_trace", None)
    recipe = value.get("combo_recipe")
    if not isinstance(recipe, dict):
        raise AxisCausalityAuditError("Compiled profile is missing ComboRecipe data.")
    for field in ("recipe_signature", "compile_reason", "mechanism_axes", "primitive_scores"):
        recipe.pop(field, None)
    return value


def _sequence(profile: Mapping[str, Any]) -> list[str]:
    recipe = profile["combo_recipe"]
    return [str(recipe[f"hit_{index}"]["motion_family"]) for index in (1, 2, 3)]


def _metrics(profile: Mapping[str, Any]) -> dict[str, Any]:
    recipe = profile["combo_recipe"]
    hits = [recipe[f"hit_{index}"] for index in (1, 2, 3)]
    return {
        "sequence": " -> ".join(_sequence(profile)),
        "contact_anchors": " -> ".join(str(hit["contact_anchor"]) for hit in hits),
        "root_motion_total": sum(float(hit["root_motion_distance"]) for hit in hits),
        "hitbox_width_average": sum(float(hit["hitbox_width_multiplier"]) for hit in hits) / 3.0,
        "hitstop_total": sum(float(hit["hitstop_multiplier"]) for hit in hits),
        "startup_total": sum(float(profile["startup"]) * float(hit["startup_multiplier"]) for hit in hits),
        "recovery_total": sum(float(profile["recovery"]) * float(hit["recovery_multiplier"]) for hit in hits),
        "reach_pixels": float(profile["reach_pixels"]),
        "swing_arc_degrees": float(profile["swing_arc_degrees"]),
        "hitbox_thickness": float(profile["hitbox_thickness"]),
        "control_strength": float(profile["control_strength"]),
        "impact_sharpness": float(profile["impact_sharpness"]),
        "tempo": str(profile["tempo"]),
        "weight_class": str(profile["weight_class"]),
        "grip_mode": str(profile["grip_mode"]),
    }


def _flatten(value: Any, prefix: str = "") -> dict[str, Any]:
    flattened: dict[str, Any] = {}
    if isinstance(value, dict):
        for key in sorted(value):
            path = f"{prefix}/{key}" if prefix else f"/{key}"
            flattened.update(_flatten(value[key], path))
    elif isinstance(value, list):
        for index, item in enumerate(value):
            flattened.update(_flatten(item, f"{prefix}/{index}"))
    else:
        flattened[prefix] = value
    return flattened


def analyze_raw(raw: Mapping[str, Any]) -> dict[str, Any]:
    if raw.get("schema") != RAW_SCHEMA or raw.get("identity_inputs_used") is not False:
        raise AxisCausalityAuditError("Raw audit boundary is invalid.")
    baseline_record = raw.get("baseline")
    scenarios = raw.get("scenarios")
    if not isinstance(baseline_record, dict) or not isinstance(scenarios, list) or len(scenarios) != 25:
        raise AxisCausalityAuditError("Raw audit must contain one baseline and 25 scenarios.")
    baseline_profile = baseline_record.get("profile")
    if baseline_record.get("ok") is not True or not isinstance(baseline_profile, dict):
        raise AxisCausalityAuditError("Anonymous baseline did not compile.")
    baseline_runtime = _runtime_payload(baseline_profile)
    baseline_runtime_hash = _stable_hash(baseline_runtime)
    baseline_scores = baseline_profile.get("primitive_scores")
    if not isinstance(baseline_scores, dict):
        raise AxisCausalityAuditError("Anonymous baseline has no primitive scores.")
    baseline_flat = _flatten(baseline_runtime)
    baseline_metrics = _metrics(baseline_profile)
    rows: list[dict[str, Any]] = []
    by_axis: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for record in scenarios:
        profile = record.get("profile")
        if record.get("ok") is not True or not isinstance(profile, dict):
            raise AxisCausalityAuditError(f"Scenario did not compile: {record.get('id')}")
        expectation = str(record.get("expected"))
        if expectation not in {MECHANISM_EXPECTATION, INVARIANT_EXPECTATION}:
            raise AxisCausalityAuditError(f"Unknown scenario expectation: {record.get('id')}")
        runtime = _runtime_payload(profile)
        runtime_effect = _stable_hash(runtime) != baseline_runtime_hash
        score_effect = profile.get("primitive_scores") != baseline_scores
        scenario_metrics = _metrics(profile)
        sequence_effect = scenario_metrics["sequence"] != baseline_metrics["sequence"]
        contact_anchor_effect = scenario_metrics["contact_anchors"] != baseline_metrics["contact_anchors"]
        current_flat = _flatten(runtime)
        changed_paths = sorted(path for path in set(baseline_flat) | set(current_flat) if baseline_flat.get(path) != current_flat.get(path))
        if expectation == INVARIANT_EXPECTATION:
            passed = not runtime_effect and not score_effect
            classification = "INVARIANT_PASS" if passed else "INVARIANT_VIOLATION"
        elif runtime_effect:
            passed = True
            classification = "SEQUENCE_EFFECT" if sequence_effect else "PARAMETER_EFFECT"
        elif score_effect:
            passed = False
            classification = "SCORE_ONLY_MASKED"
        else:
            passed = False
            classification = "SILENT"
        row = {
            "id": str(record["id"]),
            "axis": str(record["axis"]),
            "changes": json.dumps(record.get("changes", {}), ensure_ascii=False, sort_keys=True, separators=(",", ":")),
            "expected": expectation,
            "passed": passed,
            "classification": classification,
            "score_effect": score_effect,
            "runtime_effect": runtime_effect,
            "sequence_effect": sequence_effect,
            "contact_anchor_effect": contact_anchor_effect,
            "baseline_sequence": baseline_metrics["sequence"],
            "scenario_sequence": scenario_metrics["sequence"],
            "changed_runtime_path_count": len(changed_paths),
            "changed_runtime_paths": changed_paths,
            "metric_deltas": {
                key: scenario_metrics[key] - baseline_metrics[key]
                for key in (
                    "root_motion_total",
                    "hitbox_width_average",
                    "hitstop_total",
                    "startup_total",
                    "recovery_total",
                    "reach_pixels",
                    "swing_arc_degrees",
                    "hitbox_thickness",
                    "control_strength",
                    "impact_sharpness",
                )
            },
        }
        rows.append(row)
        by_axis[row["axis"]].append(row)
    axis_results: list[dict[str, Any]] = []
    for axis in sorted(by_axis):
        probes = by_axis[axis]
        mechanism_probes = [row for row in probes if row["expected"] == MECHANISM_EXPECTATION]
        invariant_probes = [row for row in probes if row["expected"] == INVARIANT_EXPECTATION]
        if invariant_probes:
            state = "INVARIANT_PASS" if all(row["passed"] for row in invariant_probes) else "INVARIANT_VIOLATION"
        elif all(row["runtime_effect"] for row in mechanism_probes):
            state = "ACTIVE"
        elif any(row["runtime_effect"] for row in mechanism_probes):
            state = "PARTIAL_THRESHOLD_MASKING"
        elif any(row["score_effect"] for row in mechanism_probes):
            state = "SCORE_ONLY_MASKED"
        else:
            state = "SILENT"
        axis_results.append(
            {
                "axis": axis,
                "state": state,
                "probe_count": len(probes),
                "runtime_effect_count": sum(bool(row["runtime_effect"]) for row in probes),
                "score_only_count": sum(row["classification"] == "SCORE_ONLY_MASKED" for row in probes),
                "failed_probe_ids": [row["id"] for row in probes if not row["passed"]],
            }
        )
    mechanism_rows = [row for row in rows if row["expected"] == MECHANISM_EXPECTATION]
    invariant_rows = [row for row in rows if row["expected"] == INVARIANT_EXPECTATION]
    failed_mechanism = [row["id"] for row in mechanism_rows if not row["passed"]]
    failed_invariants = [row["id"] for row in invariant_rows if not row["passed"]]
    status = "PASS" if not failed_mechanism and not failed_invariants else "NEEDS_WORK"
    return {
        "status": status,
        "baseline_metrics": baseline_metrics,
        "scenario_count": len(rows),
        "mechanism_probe_count": len(mechanism_rows),
        "mechanism_runtime_effect_count": sum(bool(row["runtime_effect"]) for row in mechanism_rows),
        "mechanism_score_only_masked_count": sum(row["classification"] == "SCORE_ONLY_MASKED" for row in mechanism_rows),
        "mechanism_silent_count": sum(row["classification"] == "SILENT" for row in mechanism_rows),
        "invariant_probe_count": len(invariant_rows),
        "invariant_pass_count": sum(bool(row["passed"]) for row in invariant_rows),
        "failed_mechanism_probe_ids": failed_mechanism,
        "failed_invariant_probe_ids": failed_invariants,
        "axis_results": axis_results,
        "rows": rows,
    }


def _csv_text(rows: Sequence[Mapping[str, Any]]) -> str:
    columns = (
        "id",
        "axis",
        "changes",
        "expected",
        "passed",
        "classification",
        "score_effect",
        "runtime_effect",
        "sequence_effect",
        "contact_anchor_effect",
        "baseline_sequence",
        "scenario_sequence",
        "changed_runtime_path_count",
    )
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=columns, extrasaction="ignore", lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return stream.getvalue()


def _report_text(summary: Mapping[str, Any]) -> str:
    lines = [
        "# Anonymous Affordance Axis Causality Audit",
        "",
        f"Status: **{summary['status']}**",
        "",
        "This offline audit changes one legal anonymous structural axis at a time against a neutral baseline. It evaluates the actual CombatMotionProfile and five MotionPrimitive specs after removing trace text, confidence, evidence wording, and reporting metadata. A primitive score change alone is not accepted as a runtime effect.",
        "",
        "No identity, object name, asset ID, run ID, player prompt, Claude call, image generation, or human feel retest is involved.",
        "",
        "## Summary",
        "",
        f"- Mechanism probes: {summary['mechanism_probe_count']}",
        f"- Probes with an actual runtime effect: {summary['mechanism_runtime_effect_count']}",
        f"- Score-only masked probes: {summary['mechanism_score_only_masked_count']}",
        f"- Fully silent probes: {summary['mechanism_silent_count']}",
        f"- Non-mechanical invariant controls passed: {summary['invariant_pass_count']}/{summary['invariant_probe_count']}",
        "",
        "## Axis states",
        "",
        "| Axis | State | Probes | Runtime effects | Score-only | Failed probes |",
        "|---|---|---:|---:|---:|---|",
    ]
    for axis in summary["axis_results"]:
        lines.append(
            f"| {axis['axis']} | {axis['state']} | {axis['probe_count']} | {axis['runtime_effect_count']} | {axis['score_only_count']} | {', '.join(axis['failed_probe_ids']) or '-'} |"
        )
    lines.extend(
        [
            "",
            "## Probe matrix",
            "",
            "| Probe | Axis | Change | Classification | Sequence | Runtime paths changed |",
            "|---|---|---|---|---|---:|",
        ]
    )
    for row in summary["rows"]:
        lines.append(
            f"| {row['id']} | {row['axis']} | `{row['changes']}` | {row['classification']} | `{row['scenario_sequence']}` | {row['changed_runtime_path_count']} |"
        )
    lines.extend(
        [
            "",
            "## Interpretation",
            "",
            "`SCORE_ONLY_MASKED` means the input axis changed internal primitive scores but produced no change in the runtime profile or MotionPrimitive specs for this neutral structure. This is threshold masking, not proof that the field is globally unused. It is nevertheless a failed local causal probe because a player would receive the same mechanics for that one-axis change.",
            "",
            "This audit does not authorize sample-specific tuning. Any future correction must make generic axes influence continuous runtime parameters or selection in anonymous profiles, then rerun this same matrix before another human test.",
            "",
        ]
    )
    return "\n".join(lines)


def run_audit(repo_root: Path, output_directory: Path) -> dict[str, Any]:
    repo_root = repo_root.resolve()
    output_directory = output_directory.resolve()
    if output_directory.exists():
        raise AxisCausalityAuditError(f"Output already exists: {output_directory}")
    stage = output_directory.with_name(f".{output_directory.name}.{uuid.uuid4().hex}.tmp")
    stage.mkdir(parents=True)
    try:
        raw_path = stage / "axis_probe_output.json"
        safe_environment = dict(os.environ)
        safe_environment.pop("ANTHROPIC_API_KEY", None)
        safe_environment.pop("FORGE_SEMANTIC_MODEL", None)
        command = [
            str(_find_godot(repo_root)),
            "--headless",
            "--path",
            str(repo_root),
            "--script",
            "res://tools/semantic/scripts/export_affordance_axis_causality.gd",
            "--",
            f"--output={raw_path}",
        ]
        completed = subprocess.run(command, cwd=repo_root, env=safe_environment, capture_output=True, text=True, timeout=60, check=False)
        if completed.returncode != 0 or "AFFORDANCE_AXIS_CAUSALITY_EXPORT=PASS" not in completed.stdout or not raw_path.is_file():
            raise AxisCausalityAuditError("Godot affordance-axis export failed.")
        raw = _read_json(raw_path)
        summary = analyze_raw(raw)
        _write_new(stage / "axis_causality_summary.json", {key: value for key, value in summary.items() if key != "rows"})
        _write_text_new(stage / "axis_causality_matrix.csv", _csv_text(summary["rows"]))
        _write_text_new(stage / "AFFORDANCE_AXIS_CAUSALITY_REPORT.md", _report_text(summary))
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
        print(json.dumps({"status": "PREFLIGHT_PASS", "network_calls": 0, "identity_inputs": 0, "scenario_count": 25}))
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
                "mechanism_runtime_effect_count": summary["mechanism_runtime_effect_count"],
                "mechanism_probe_count": summary["mechanism_probe_count"],
                "score_only_masked_count": summary["mechanism_score_only_masked_count"],
                "output_directory": str(output_directory),
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


__all__ = [
    "AxisCausalityAuditError",
    "analyze_raw",
    "run_audit",
]
