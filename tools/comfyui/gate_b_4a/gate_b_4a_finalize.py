from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import shutil
import sys
import uuid
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent
COMFY_ROOT = ROOT.parent
PROJECT_ROOT = COMFY_ROOT.parent.parent
sys.path.insert(0, str(ROOT))

import gate_b_4a_runner as runner  # noqa: E402


BOOLEAN_FIELDS = (
    "single_complete_subject",
    "no_person_hand_text",
    "canonical_identity_recognizable_raw",
    "silhouette_matches",
    "forbidden_weapon_substitution",
    "recognizable_at_96x96",
    "facing_consistency",
)
EXPECTED_KEYS = {
    "case_id",
    "seed",
    *BOOLEAN_FIELDS,
    "required_parts_visible_count",
    "alpha_delivery_success",
    "generation_seconds",
    "postprocess_seconds",
    "reviewer",
    "notes",
}


class FinalizeError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_bool(value: str, pointer: str) -> bool:
    normalized = value.strip().lower()
    if normalized == "true":
        return True
    if normalized == "false":
        return False
    raise FinalizeError(f"HUMAN_REVIEW_BOOLEAN_REQUIRED:{pointer}")


def load_human_review(path: Path) -> tuple[list[dict[str, Any]], str]:
    review_bytes = path.read_bytes()
    review_hash = hashlib.sha256(review_bytes).hexdigest()
    text = review_bytes.decode("utf-8-sig")
    reader = csv.DictReader(text.splitlines())
    if set(reader.fieldnames or []) != EXPECTED_KEYS:
        raise FinalizeError("HUMAN_REVIEW_COLUMNS_CHANGED")
    rows: list[dict[str, Any]] = []
    for index, raw in enumerate(reader, start=2):
        row: dict[str, Any] = dict(raw)
        for field in BOOLEAN_FIELDS:
            row[field] = parse_bool(str(raw[field]), f"row={index}/{field}")
        try:
            count = int(str(raw["required_parts_visible_count"]).strip())
        except ValueError as exc:
            raise FinalizeError(f"HUMAN_REVIEW_PART_COUNT_REQUIRED:row={index}") from exc
        if count < 0 or count > 3:
            raise FinalizeError(f"HUMAN_REVIEW_PART_COUNT_OUT_OF_RANGE:row={index}:{count}")
        row["required_parts_visible_count"] = count
        row["alpha_delivery_success"] = parse_bool(str(raw["alpha_delivery_success"]), f"row={index}/alpha")
        if not str(raw["reviewer"]).strip():
            raise FinalizeError(f"HUMAN_REVIEWER_REQUIRED:row={index}")
        rows.append(row)
    if len(rows) != 8:
        raise FinalizeError(f"HUMAN_REVIEW_ROW_COUNT:{len(rows)}")
    return rows, review_hash


def load_generation(run_root: Path) -> tuple[dict[str, Any], dict[tuple[str, int], dict[str, Any]], list[Path]]:
    summary = json.loads((run_root / "generation_summary.json").read_text(encoding="utf-8"))
    if summary.get("result_directory_count") != 8 or len(summary.get("results", [])) != 8:
        raise FinalizeError("GENERATION_RESULT_COUNT_NOT_EIGHT")
    if summary.get("request_attempt_count") != 8 or summary.get("automatic_retry_count") != 0:
        raise FinalizeError("GENERATION_CALL_OR_RETRY_COUNT_INVALID")
    manifests: dict[tuple[str, int], dict[str, Any]] = {}
    evidence_paths: list[Path] = [run_root / "generation_summary.json", run_root / "RUN_COMPLETE.json"]
    prompt_ids: set[str] = set()
    for item in summary["results"]:
        result_dir = PROJECT_ROOT / item["output_directory"]
        manifest_path = result_dir / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        key = (str(item["case_id"]), int(item["seed"]))
        if key in manifests:
            raise FinalizeError(f"DUPLICATE_GENERATION_RESULT:{key}")
        manifests[key] = manifest
        if not manifest.get("request_attempted") or manifest.get("retry_count") != 0:
            raise FinalizeError(f"MANIFEST_CALL_BOUNDARY_INVALID:{key}")
        prompt_id = str(manifest.get("prompt_id", ""))
        if prompt_id:
            if prompt_id in prompt_ids:
                raise FinalizeError(f"PROMPT_ID_DUPLICATE:{key}")
            prompt_ids.add(prompt_id)
        if manifest.get("semantic_fields_modified") is not False or manifest.get("anthropic_api_called") is not False:
            raise FinalizeError(f"SEMANTIC_OR_ANTHROPIC_BOUNDARY_BROKEN:{key}")
        for path in sorted(result_dir.iterdir()):
            if path.is_file():
                evidence_paths.append(path)
    if set(manifests) != {(case_id, seed) for case_id in runner.CASE_ORDER for seed in runner.SEEDS}:
        raise FinalizeError("GENERATION_CASE_SEED_MATRIX_CHANGED")
    return summary, manifests, evidence_paths


def scan_for_secrets(paths: list[Path]) -> list[str]:
    patterns = (
        re.compile(rb"sk-ant-[A-Za-z0-9_-]{12,}"),
        re.compile(rb"(?:api[_-]?key|authorization)\s*[:=]\s*[A-Za-z0-9_-]{16,}", re.IGNORECASE),
    )
    findings: list[str] = []
    for path in paths:
        if path.suffix.lower() in {".png", ".pyc"}:
            continue
        data = path.read_bytes()
        if any(pattern.search(data) for pattern in patterns):
            findings.append(path.relative_to(PROJECT_ROOT).as_posix())
    return findings


def count_true(rows: list[dict[str, Any]], field: str) -> int:
    return sum(int(bool(row[field])) for row in rows)


def build_metrics(
    rows: list[dict[str, Any]], manifests: dict[tuple[str, int], dict[str, Any]], secret_findings: list[str]
) -> tuple[dict[str, Any], list[str]]:
    single = count_true(rows, "single_complete_subject")
    clean = count_true(rows, "no_person_hand_text")
    raw_identity = count_true(rows, "canonical_identity_recognizable_raw")
    at_96 = count_true(rows, "recognizable_at_96x96")
    substitutions = count_true(rows, "forbidden_weapon_substitution")
    alpha = sum(int(bool(manifest["alpha_delivery_success"])) for manifest in manifests.values())
    silhouette = count_true(rows, "silhouette_matches")
    facing = count_true(rows, "facing_consistency")
    per_case_parts = {
        case_id: max(
            int(row["required_parts_visible_count"]) for row in rows if row["case_id"] == case_id
        )
        for case_id in runner.CASE_ORDER
    }
    checks = {
        "single_complete_subject": {"actual": single, "required": 7, "passed": single >= 7},
        "no_person_hand_text": {"actual": clean, "required": 8, "passed": clean == 8},
        "canonical_identity_recognizable_raw": {"actual": raw_identity, "required": 7, "passed": raw_identity >= 7},
        "recognizable_at_96x96": {"actual": at_96, "required": 6, "passed": at_96 >= 6},
        "each_case_one_seed_two_parts": {
            "actual": per_case_parts,
            "required": 2,
            "passed": all(value >= 2 for value in per_case_parts.values()),
        },
        "forbidden_weapon_substitution": {"actual": substitutions, "required": 0, "passed": substitutions == 0},
        "alpha_delivery_success": {"actual": alpha, "required": 6, "passed": alpha >= 6},
        "automatic_retry_count": {"actual": 0, "required": 0, "passed": True},
        "semantic_contract_modification_count": {"actual": 0, "required": 0, "passed": True},
        "key_leak_count": {"actual": len(secret_findings), "required": 0, "passed": not secret_findings},
    }
    failures = [name for name, value in checks.items() if not value["passed"]]
    metrics = {
        "checks": checks,
        "supplemental": {
            "silhouette_matches": {"actual": silhouette, "total": 8},
            "facing_consistency": {"actual": facing, "total": 8},
        },
        "human_reviewed_images": 8,
        "secret_scan_findings": secret_findings,
    }
    return metrics, failures


def percentage(value: int, total: int) -> float:
    return round(value * 100.0 / total, 1)


def build_report(
    run_id: str,
    summary: dict[str, Any],
    metrics: dict[str, Any],
    failures: list[str],
    rows: list[dict[str, Any]],
    review_hash: str,
    shutdown: dict[str, Any],
) -> str:
    checks = metrics["checks"]
    current_raw = int(checks["canonical_identity_recognizable_raw"]["actual"])
    current_96 = int(checks["recognizable_at_96x96"]["actual"])
    current_clean = int(checks["no_person_hand_text"]["actual"])
    current_alpha = int(checks["alpha_delivery_success"]["actual"])
    raw_delta = percentage(current_raw, 8) - 40.0
    at96_delta = percentage(current_96, 8) - 40.0
    directional_improvement = raw_delta >= 25.0 and at96_delta >= 25.0
    status = "PASS" if not failures else "NEEDS WORK"
    recommendation = (
        "Recommend a separately approved, training-zone-only integration step. Do not enter combat rooms."
        if status == "PASS"
        else "Do not integrate into the training zone yet; the failed visual layer needs a separate bounded correction."
    )
    lines = [
        "# Forge Visual Identity Gate B — Semantic Prompt Handoff 4A",
        "",
        f"**Status:** {status}",
        "",
        f"Run: `{run_id}`. Human visual review SHA-256: `{review_hash}`.",
        "",
        "## Execution attestation",
        "",
        f"- ComfyUI checkpoint: `{summary['checkpoint']}` (`{summary['checkpoint_sha256']}`).",
        "- Workflow: `forge_object_sprite_v0.json`, 512×512, 26 steps, CFG 6.5, `dpmpp_2m` + `karras`, denoise 1.0.",
        f"- Exactly 8 local ComfyUI submissions were attempted; {sum(1 for item in summary['results'] if item.get('prompt_id'))} prompt IDs were returned, with 0 automatic retries.",
        "- The effective prompt used only the seven approved English fields from each frozen 3C `result`, plus the unchanged generic Spike prompt constraints.",
        "- Chinese input, expected answers, review rubric, combat, display name, confidence, `must_preserve`, and `must_not_replace_with` were not injected.",
        "- No semantic field, semantic contract, system prompt, or Claude model was modified. Anthropic was not called.",
        f"- ComfyUI was stopped by its recorded Gate B PID; port 8188 closed verification: `{str(bool(shutdown.get('port_8188_closed'))).lower()}`.",
        "",
        "## Gate results",
        "",
        "| Criterion | Actual | Required | Verdict |",
        "|---|---:|---:|---|",
    ]
    for name, check in checks.items():
        actual = json.dumps(check["actual"], ensure_ascii=False) if isinstance(check["actual"], dict) else str(check["actual"])
        lines.append(f"| {name} | {actual} | {check['required']} | {'PASS' if check['passed'] else 'FAIL'} |")
    lines.extend(
        [
            "",
            "## Per-image human review",
            "",
            "| Case | Seed | Single | Clean | Raw identity | Parts | Silhouette | Fixed weapon | 96×96 | Facing | Alpha |",
            "|---|---:|---|---|---|---:|---|---|---|---|---|",
        ]
    )
    for row in rows:
        marker = lambda value: "yes" if value else "no"
        lines.append(
            f"| {row['case_id']} | {row['seed']} | {marker(row['single_complete_subject'])} | "
            f"{marker(row['no_person_hand_text'])} | {marker(row['canonical_identity_recognizable_raw'])} | "
            f"{row['required_parts_visible_count']} | {marker(row['silhouette_matches'])} | "
            f"{marker(row['forbidden_weapon_substitution'])} | {marker(row['recognizable_at_96x96'])} | "
            f"{marker(row['facing_consistency'])} | {marker(row['alpha_delivery_success'])} |"
        )
    lines.extend(
        [
            "",
            "## Historical comparison",
            "",
            "Spike 2 is retained unchanged as a non-paired historical baseline: five different Chinese-direct cases with one seed each. Gate B uses four new 3C cases with two seeds each, so the comparison is directional and not a controlled causal A/B test.",
            "",
            "| Metric | Spike 2 Chinese-direct | Gate B structured English | Change |",
            "|---|---:|---:|---:|",
            f"| Raw identity recognizable | 2/5 (40.0%) | {current_raw}/8 ({percentage(current_raw, 8)}%) | {raw_delta:+.1f} pp |",
            f"| Recognizable at 96×96 | 2/5 (40.0%) | {current_96}/8 ({percentage(current_96, 8)}%) | {at96_delta:+.1f} pp |",
            f"| Person/hand error rate | 1/5 (20.0%) | {8-current_clean}/8 ({percentage(8-current_clean, 8)}%) | {percentage(8-current_clean, 8)-20.0:+.1f} pp |",
            f"| Alpha success | 5/5 (100.0%) | {current_alpha}/8 ({percentage(current_alpha, 8)}%) | {percentage(current_alpha, 8)-100.0:+.1f} pp |",
            "",
            f"Directional visual identity improvement under the predeclared 25-point descriptive rule: **{'yes' if directional_improvement else 'no'}**. This is not a statistical-significance claim.",
            "",
            "## Decision",
            "",
            recommendation,
        ]
    )
    if failures:
        lines.extend(("", "Failed gates: " + ", ".join(f"`{item}`" for item in failures) + "."))
    lines.extend(("", "Gate B 4A stops here. It does not start Gate B follow-up work, V2, or any battle-room integration.", ""))
    return "\n".join(lines)


def normalized_csv(rows: list[dict[str, Any]], path: Path) -> None:
    fieldnames = [
        "case_id",
        "seed",
        *BOOLEAN_FIELDS,
        "required_parts_visible_count",
        "alpha_delivery_success",
        "generation_seconds",
        "postprocess_seconds",
        "reviewer",
        "notes",
    ]
    with path.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({key: str(row[key]).lower() if isinstance(row[key], bool) else row[key] for key in fieldnames})


def finalize(run_root: Path) -> Path:
    run_root = run_root.resolve()
    if run_root.parent != runner.OUTPUT_ROOT.resolve():
        raise FinalizeError("RUN_ROOT_OUTSIDE_GATE_B_OUTPUT")
    run_id = run_root.name
    frozen, frozen_hash = runner._load_and_verify_frozen()
    del frozen
    summary, manifests, evidence_paths = load_generation(run_root)
    if summary.get("frozen_handoff_sha256") != frozen_hash:
        raise FinalizeError("RUN_FROZEN_HASH_MISMATCH")
    review_root = run_root / "human_review"
    review_path = review_root / "human_visual_review.csv"
    rows, review_hash = load_human_review(review_path)
    for row in rows:
        key = (str(row["case_id"]), int(row["seed"]))
        if key not in manifests:
            raise FinalizeError(f"HUMAN_REVIEW_UNKNOWN_RESULT:{key}")
        manifest = manifests[key]
        if row["alpha_delivery_success"] is not bool(manifest["alpha_delivery_success"]):
            raise FinalizeError(f"HUMAN_REVIEW_ALPHA_FIELD_CHANGED:{key}")
    shutdown_path = ROOT / "runtime" / "lifecycle.json"
    shutdown = json.loads(shutdown_path.read_text(encoding="utf-8"))
    if shutdown.get("action") != "stopped" or shutdown.get("port_8188_closed") is not True:
        raise FinalizeError("COMFYUI_SHUTDOWN_EVIDENCE_MISSING")
    evidence_paths.extend(
        [
            runner.FROZEN_HANDOFF_PATH,
            runner.PROTECTED_HISTORY_PATH,
            ROOT / "human_review_rubric.json",
            ROOT / "gate_b_4a_runner.py",
            ROOT / "gate_b_4a_lifecycle.ps1",
            ROOT / "gate_b_4a_assets.py",
            ROOT / "gate_b_4a_finalize.py",
            review_path,
            review_root / "raw_processed_comparison.png",
            review_root / "required_parts_review.png",
            shutdown_path,
        ]
    )
    secret_findings = scan_for_secrets(evidence_paths)
    metrics, failures = build_metrics(rows, manifests, secret_findings)
    report_root = ROOT / "reports" / run_id
    if report_root.exists():
        raise FinalizeError(f"REPORT_ALREADY_EXISTS:{report_root}")
    stage = ROOT / f".report-{uuid.uuid4().hex}.tmp"
    stage.mkdir(parents=False, exist_ok=False)
    try:
        normalized_csv(rows, stage / "gate_b_4a_results.csv")
        summary_payload = {
            "gate": "GATE_B_4A",
            "run_id": run_id,
            "status": "PASS" if not failures else "NEEDS WORK",
            "failures": failures,
            "metrics": metrics,
            "generation_summary_sha256": sha256_file(run_root / "generation_summary.json"),
            "human_review_sha256": review_hash,
            "frozen_handoff_sha256": frozen_hash,
            "checkpoint": summary["checkpoint"],
            "checkpoint_sha256": summary["checkpoint_sha256"],
            "request_attempt_count": summary["request_attempt_count"],
            "automatic_retry_count": summary["automatic_retry_count"],
            "semantic_contract_modified": summary["semantic_contract_modified"],
            "anthropic_api_called": summary["anthropic_api_called"],
            "comfyui_port_8188_closed": True,
        }
        (stage / "gate_b_4a_summary.json").write_text(
            json.dumps(summary_payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        (stage / "GATE_B_4A_REPORT.md").write_text(
            build_report(run_id, summary, metrics, failures, rows, review_hash, shutdown), encoding="utf-8"
        )
        shutil.copy2(review_root / "raw_processed_comparison.png", stage / "raw_processed_comparison.png")
        shutil.copy2(review_root / "required_parts_review.png", stage / "required_parts_review.png")
        evidence_hashes: dict[str, str] = {}
        for path in evidence_paths:
            evidence_hashes[path.resolve().relative_to(PROJECT_ROOT).as_posix()] = sha256_file(path)
        for name in (
            "GATE_B_4A_REPORT.md",
            "gate_b_4a_results.csv",
            "gate_b_4a_summary.json",
            "raw_processed_comparison.png",
            "required_parts_review.png",
        ):
            final_relative = (report_root / name).relative_to(PROJECT_ROOT).as_posix()
            evidence_hashes[final_relative] = sha256_file(stage / name)
        (stage / "evidence_hashes.json").write_text(
            json.dumps(
                {
                    "algorithm": "SHA-256",
                    "run_id": run_id,
                    "frozen_spike2_history_sha256": sha256_file(runner.PROTECTED_HISTORY_PATH),
                    "files": dict(sorted(evidence_hashes.items())),
                },
                ensure_ascii=False,
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
        report_root.parent.mkdir(parents=True, exist_ok=True)
        os.replace(stage, report_root)
    finally:
        if stage.exists():
            shutil.rmtree(stage)
    return report_root


def main() -> int:
    parser = argparse.ArgumentParser(description="Finalize Gate B 4A after explicit human image review.")
    parser.add_argument("--run-root", required=True, type=Path)
    args = parser.parse_args()
    try:
        output = finalize(args.run_root)
    except (FinalizeError, runner.GateBError, OSError, ValueError, json.JSONDecodeError) as exc:
        print(json.dumps({"status": "NEEDS_WORK", "failure_reason": str(exc)}), file=sys.stderr)
        return 2
    print(json.dumps({"status": "FINALIZED", "report_root": str(output)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
