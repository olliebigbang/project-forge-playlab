#!/usr/bin/env python3
"""Build and finalize the versioned twelve-profile affordance handoff.

The handoff combines the eight strict-valid v1.2 profiles with the four
strict-valid v1.2.1 targeted profiles. It never contacts a provider and never
passes identity text to the Godot motion compiler.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import os
import shutil
import uuid
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping, Sequence

from affordance_contract_v1_2 import validate_affordance_profile
from affordance_contract_v1_2_1 import validate_candidate_blueprint_v1_2_1


SOURCE_RUN_ID = "affordance-retest-v1-2-20260808T074610104680Z-70b603d7"
SOURCE_EVIDENCE_SHA256 = "fa76d8bc4f3c78ce4a9eb29c4a8baeade03e5297acefa4a0bf45fb8f1ff06324"
TARGET_RUN_ID = "affordance-targeted-v1-2-1-20260808T130139638529Z-a318dc88"
TARGET_EVIDENCE_SHA256 = "6ffd56aebc23140104ebb511186c6f4c8e5cd395f43c083cc0a0f723facf01a7"
CASE_ORDER = tuple(f"A{index:02d}" for index in range(1, 13))
TARGET_CASES = frozenset({"A03", "A07", "A08", "A09"})
PRIMITIVES = frozenset({"bash", "sweep", "thrust", "slam", "spin"})
RECIPE_STAGES = ("hit_1", "hit_2", "hit_3", "charge_attack", "dodge_attack")


class CombinedHandoffError(RuntimeError):
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
        raise CombinedHandoffError(f"Cannot read required JSON: {path}") from exc


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


def _source_run(semantic_root: Path) -> Path:
    return semantic_root / "reports" / "affordance_retest_v1_2" / SOURCE_RUN_ID


def _target_run(semantic_root: Path) -> Path:
    return semantic_root / "reports" / "affordance_targeted_v1_2_1" / TARGET_RUN_ID


def verify_frozen_run(run: Path, run_id: str, expected_evidence_sha256: str) -> dict[str, Any]:
    evidence_path = run / "evidence_hashes.json"
    complete_path = run / "COMPLETE.json"
    if not evidence_path.is_file() or _sha256(evidence_path) != expected_evidence_sha256:
        raise CombinedHandoffError(f"Frozen evidence manifest changed: {run_id}")
    evidence = _read_json(evidence_path)
    complete = _read_json(complete_path)
    if (
        not isinstance(evidence, dict)
        or evidence.get("run_id") != run_id
        or not isinstance(evidence.get("files"), dict)
        or not isinstance(complete, dict)
        or complete.get("run_id") != run_id
        or complete.get("evidence_sha256") != expected_evidence_sha256
    ):
        raise CombinedHandoffError(f"Frozen completion envelope is invalid: {run_id}")
    for relative, expected in evidence["files"].items():
        path = run / relative
        if not path.is_file() or _sha256(path) != expected:
            raise CombinedHandoffError(f"Frozen evidence changed: {run_id}/{relative}")
    return {
        "run_id": run_id,
        "evidence_sha256": expected_evidence_sha256,
        "file_count": len(evidence["files"]),
    }


def _frozen_profiles(repo_root: Path) -> tuple[dict[str, dict[str, Any]], list[dict[str, Any]], dict[str, Any]]:
    semantic_root = repo_root / "tools" / "semantic"
    source_run = _source_run(semantic_root)
    target_run = _target_run(semantic_root)
    source_evidence = verify_frozen_run(source_run, SOURCE_RUN_ID, SOURCE_EVIDENCE_SHA256)
    target_evidence = verify_frozen_run(target_run, TARGET_RUN_ID, TARGET_EVIDENCE_SHA256)

    corpus = _read_json(semantic_root / "cases" / "affordance_blind_12_candidate.json")
    if not isinstance(corpus, dict) or tuple(corpus.get("case_order", ())) != CASE_ORDER:
        raise CombinedHandoffError("Frozen twelve-case corpus changed.")

    profiles: dict[str, dict[str, Any]] = {}
    sources: list[dict[str, Any]] = []
    for case_id in CASE_ORDER:
        if case_id in TARGET_CASES:
            result_path = target_run / "cases" / case_id / "result.json"
            result = _read_json(result_path)
            if (
                not isinstance(result, dict)
                or result.get("case_id") != case_id
                or result.get("status") != "VALID"
                or result.get("api_success") is not True
                or result.get("schema_valid") is not True
                or result.get("cross_field_valid") is not True
            ):
                raise CombinedHandoffError(f"Targeted profile is not strict-valid: {case_id}")
            validated = validate_candidate_blueprint_v1_2_1(result.get("tool_input_received"))
            profile = validate_affordance_profile(validated["affordance"])
            contract = "forge-semantic-v1.2.1-candidate"
            run_id = TARGET_RUN_ID
        else:
            result_path = source_run / "cases" / case_id / "result.json"
            result = _read_json(result_path)
            profile_path = source_run / "affordance_profiles" / f"{case_id}.json"
            if not isinstance(result, dict) or result.get("status") != "VALID" or not profile_path.is_file():
                raise CombinedHandoffError(f"Source profile is not strict-valid: {case_id}")
            profile = validate_affordance_profile(_read_json(profile_path))
            contract = "forge-semantic-v1.2-candidate"
            run_id = SOURCE_RUN_ID
        profiles[case_id] = profile
        sources.append(
            {
                "case_id": case_id,
                "contract_version": contract,
                "source_run_id": run_id,
                "source_result_sha256": _sha256(result_path),
                "profile_sha256": _sha256_bytes(_json_bytes(profile)),
            }
        )
    return profiles, sources, {"source": source_evidence, "targeted": target_evidence}


def prepare_handoff(repo_root: Path, output_directory: Path) -> dict[str, Any]:
    repo_root = repo_root.resolve()
    output_directory = output_directory.resolve()
    if output_directory.exists():
        raise CombinedHandoffError(f"Output already exists: {output_directory}")
    profiles, sources, evidence = _frozen_profiles(repo_root)
    stage = output_directory.with_name(f".{output_directory.name}.{uuid.uuid4().hex}.tmp")
    if stage.exists():
        raise CombinedHandoffError(f"Unexpected staging collision: {stage}")
    try:
        (stage / "affordance_profiles").mkdir(parents=True)
        _write_new(stage / "case_order.json", list(CASE_ORDER))
        for case_id in CASE_ORDER:
            _write_new(stage / "affordance_profiles" / f"{case_id}.json", profiles[case_id])
        manifest = {
            "schema": "forge-affordance-combined-handoff-v1",
            "status": "PREPARED_FOR_OFFLINE_GODOT_COMPILATION",
            "created_at": _utc_now(),
            "case_order": list(CASE_ORDER),
            "profile_count": len(profiles),
            "identity_inputs_in_compiler_bundle": False,
            "version_boundary": {
                "v1_2_case_count": len(CASE_ORDER) - len(TARGET_CASES),
                "v1_2_1_targeted_case_count": len(TARGET_CASES),
                "homogeneous_twelve_call_run": False,
            },
            "frozen_evidence": evidence,
            "case_sources": sources,
        }
        _write_new(stage / "combined_source_manifest.json", manifest)
        _write_new(
            stage / "PREPARED.json",
            {
                "status": "PREPARED",
                "profile_count": 12,
                "source_manifest_sha256": _sha256(stage / "combined_source_manifest.json"),
                "created_at": _utc_now(),
            },
        )
        output_directory.parent.mkdir(parents=True, exist_ok=True)
        os.replace(stage, output_directory)
        return manifest
    finally:
        if stage.exists():
            shutil.rmtree(stage)


def _axis_summary(profile: Mapping[str, Any]) -> str:
    flags = [name.removeprefix("has_") for name in ("has_point", "has_edge", "has_broad_face", "has_barrel", "has_stock") if profile.get(name) is True]
    flag_text = "+".join(flags) if flags else "no-shape-flag"
    return "/".join(
        [
            str(profile["handle_length"]),
            str(profile["body_length"]),
            str(profile["grip_topology"]),
            str(profile["rigidity"]),
            str(profile["mass_distribution"]),
            f"{profile['contact_surface']}+{profile['secondary_contact_surface']}",
            flag_text,
        ]
    )


def _mechanical_signature(recipe: Mapping[str, Any]) -> str:
    payload = {stage: recipe[stage] for stage in RECIPE_STAGES}
    return _sha256_bytes(json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8"))


def analyze_compiled(compiled: Mapping[str, Any], case_labels: Mapping[str, str], case_sources: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    records = compiled.get("records")
    if compiled.get("identity_inputs_used") is not False or not isinstance(records, list) or len(records) != 12:
        raise CombinedHandoffError("Compiled handoff is incomplete or identity-contaminated.")
    if tuple(record.get("case_id") for record in records) != CASE_ORDER:
        raise CombinedHandoffError("Compiled record order differs from the frozen corpus.")
    source_by_case = {str(item["case_id"]): item for item in case_sources}
    rows: list[dict[str, Any]] = []
    primitive_counts: Counter[str] = Counter()
    sequence_counts: Counter[str] = Counter()
    mechanical_signatures: set[str] = set()
    for record in records:
        case_id = str(record["case_id"])
        if record.get("status") != "COMPILED":
            raise CombinedHandoffError(f"Profile did not compile: {case_id}")
        profile = record.get("mechanism_axes")
        sequence = record.get("primitive_sequence")
        recipe = record.get("recipe")
        scores = record.get("primitive_scores")
        if not isinstance(profile, dict) or not isinstance(sequence, list) or len(sequence) != 3 or not isinstance(recipe, dict) or not isinstance(scores, dict):
            raise CombinedHandoffError(f"Compiled record is malformed: {case_id}")
        if any(item not in PRIMITIVES for item in sequence):
            raise CombinedHandoffError(f"Unknown primitive in compiled sequence: {case_id}")
        sequence_key = " -> ".join(sequence)
        primitive_counts.update(sequence)
        sequence_counts[sequence_key] += 1
        mechanical_signature = _mechanical_signature(recipe)
        mechanical_signatures.add(mechanical_signature)
        top_scores = sorted(((name, float(value)) for name, value in scores.items()), key=lambda item: (-item[1], item[0]))[:3]
        rows.append(
            {
                "case_id": case_id,
                "identity": case_labels[case_id],
                "contract_version": source_by_case[case_id]["contract_version"],
                "affordance_axes": _axis_summary(profile),
                "dominant_mechanisms": "; ".join(f"{name}={value:.3f}" for name, value in top_scores),
                "primitive_sequence": sequence_key,
                "recipe_signature": str(record["recipe_signature"]),
                "mechanical_signature": mechanical_signature,
            }
        )
    most_common_sequence, most_common_count = sequence_counts.most_common(1)[0]
    all_five_used = set(primitive_counts) == PRIMITIVES
    summary = {
        "status": "PASS" if all_five_used and len(sequence_counts) > 1 else "NEEDS_WORK",
        "case_count": len(rows),
        "compiled_count": len(rows),
        "identity_inputs_used": False,
        "all_five_primitives_used_in_normal_combo_hits": all_five_used,
        "primitive_counts": dict(sorted(primitive_counts.items())),
        "unique_primitive_sequences": len(sequence_counts),
        "sequence_counts": dict(sorted(sequence_counts.items())),
        "unique_mechanical_recipes": len(mechanical_signatures),
        "most_common_sequence": most_common_sequence,
        "most_common_sequence_count": most_common_count,
        "most_common_sequence_ratio": most_common_count / len(rows),
        "single_sequence_degradation": len(sequence_counts) == 1,
        "dominant_sequence_warning": most_common_count / len(rows) >= 0.5,
        "rows": rows,
    }
    return summary


def _csv_text(rows: Sequence[Mapping[str, Any]]) -> str:
    columns = (
        "case_id",
        "identity",
        "contract_version",
        "affordance_axes",
        "dominant_mechanisms",
        "primitive_sequence",
        "recipe_signature",
        "mechanical_signature",
    )
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=columns, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return stream.getvalue()


def _report_text(summary: Mapping[str, Any]) -> str:
    lines = [
        "# Orthogonal Affordance Coverage Matrix — 12 frozen inputs",
        "",
        f"Status: **{summary['status']}**",
        "",
        "This is an offline compiler-coverage audit. It does not call Claude, FLUX, BiRefNet, ComfyUI, or a second model scorer. The compiler bundle contains only affordance profiles, case IDs, neutral anchors, and neutral alpha bounds. Identity labels are joined after compilation for this human-readable table.",
        "",
        "## Version boundary",
        "",
        "- A01, A02, A04, A05, A06, A10, A11, and A12 come from the frozen strict-valid v1.2 run.",
        "- A03, A07, A08, and A09 come from the frozen strict-valid targeted v1.2.1 run.",
        "- This is not represented as one homogeneous 12/12 model run.",
        "",
        "## Coverage result",
        "",
        f"- Compiled profiles: {summary['compiled_count']}/12",
        f"- Unique normal-combo sequences: {summary['unique_primitive_sequences']}",
        f"- Unique mechanical Recipes: {summary['unique_mechanical_recipes']}",
        f"- All five primitives used in normal combo hits: {str(summary['all_five_primitives_used_in_normal_combo_hits']).lower()}",
        f"- Most common sequence: `{summary['most_common_sequence']}` ({summary['most_common_sequence_count']}/12)",
        f"- Single-sequence degradation: {str(summary['single_sequence_degradation']).lower()}",
        f"- Dominant-sequence warning (>= 50%): {str(summary['dominant_sequence_warning']).lower()}",
        "",
        "## Affordance to mechanism to combo matrix",
        "",
        "| Case | Identity label (report only) | Contract source | Affordance axes | Dominant mechanism scores | Hit 1 -> Hit 2 -> Hit 3 |",
        "|---|---|---|---|---|---|",
    ]
    for row in summary["rows"]:
        lines.append(
            "| {case_id} | {identity} | {contract_version} | `{affordance_axes}` | `{dominant_mechanisms}` | `{primitive_sequence}` |".format(**row)
        )
    lines.extend(
        [
            "",
            "## Interpretation boundary",
            "",
            "A PASS means the frozen profiles compile without identity input, use the full five-primitive vocabulary across the corpus, and do not collapse to one normal-combo sequence. It does not mean the resulting differences are already perceptually strong or fun. The separately frozen orthogonal BlindComparison remains **TECHNICAL PASS / FEEL NEEDS WORK (3/5)**.",
            "",
            "No object-name matcher, asset-ID matcher, runtime keyword map, or case-specific Recipe was added by this audit.",
            "",
        ]
    )
    return "\n".join(lines)


def finalize_handoff(repo_root: Path, output_directory: Path) -> dict[str, Any]:
    repo_root = repo_root.resolve()
    output_directory = output_directory.resolve()
    manifest = _read_json(output_directory / "combined_source_manifest.json")
    compiled = _read_json(output_directory / "compiled_recipes.json")
    corpus = _read_json(repo_root / "tools" / "semantic" / "cases" / "affordance_blind_12_candidate.json")
    labels = {str(item["case_id"]): str(item["identity"]) for item in corpus["cases"]}
    summary = analyze_compiled(compiled, labels, manifest["case_sources"])
    for name in ("coverage_matrix.csv", "coverage_summary.json", "AFFORDANCE_ORTHOGONAL_COVERAGE_REPORT.md", "evidence_hashes.json", "COMPLETE.json"):
        if (output_directory / name).exists():
            raise CombinedHandoffError(f"Finalize output already exists: {name}")
    _write_text_new(output_directory / "coverage_matrix.csv", _csv_text(summary["rows"]))
    _write_new(output_directory / "coverage_summary.json", {key: value for key, value in summary.items() if key != "rows"})
    _write_text_new(output_directory / "AFFORDANCE_ORTHOGONAL_COVERAGE_REPORT.md", _report_text(summary))
    excluded = {"evidence_hashes.json", "COMPLETE.json"}
    files = {
        path.relative_to(output_directory).as_posix(): _sha256(path)
        for path in sorted(output_directory.rglob("*"))
        if path.is_file() and path.name not in excluded
    }
    _write_new(
        output_directory / "evidence_hashes.json",
        {
            "algorithm": "SHA-256",
            "run_id": output_directory.name,
            "files": files,
        },
    )
    _write_new(
        output_directory / "COMPLETE.json",
        {
            "run_id": output_directory.name,
            "status": summary["status"],
            "evidence_sha256": _sha256(output_directory / "evidence_hashes.json"),
            "completed_at": _utc_now(),
        },
    )
    return summary


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--output-directory", required=True)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--preflight-only", action="store_true")
    action.add_argument("--prepare", action="store_true")
    action.add_argument("--finalize", action="store_true")
    args = parser.parse_args(argv)
    repo_root = Path(args.repo_root).resolve()
    output_directory = Path(args.output_directory)
    if not output_directory.is_absolute():
        output_directory = repo_root / output_directory
    if args.preflight_only:
        profiles, sources, evidence = _frozen_profiles(repo_root)
        print(json.dumps({"status": "PASS", "profile_count": len(profiles), "case_source_count": len(sources), "frozen_evidence": evidence, "network_calls": 0}, ensure_ascii=False))
        return 0
    if args.prepare:
        manifest = prepare_handoff(repo_root, output_directory)
        print(json.dumps({"status": "PREPARED", "output_directory": str(output_directory), "profile_count": manifest["profile_count"]}, ensure_ascii=False))
        return 0
    summary = finalize_handoff(repo_root, output_directory)
    print(json.dumps({"status": summary["status"], "compiled_count": summary["compiled_count"], "unique_sequences": summary["unique_primitive_sequences"], "output_directory": str(output_directory)}, ensure_ascii=False))
    return 0 if summary["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())


__all__ = [
    "CASE_ORDER",
    "CombinedHandoffError",
    "SOURCE_EVIDENCE_SHA256",
    "TARGET_CASES",
    "TARGET_EVIDENCE_SHA256",
    "analyze_compiled",
    "finalize_handoff",
    "prepare_handoff",
    "verify_frozen_run",
]
