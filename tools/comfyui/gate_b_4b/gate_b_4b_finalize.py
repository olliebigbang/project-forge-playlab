from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parent
PROJECT_ROOT = ROOT.parent.parent.parent
REPORTS_ROOT = ROOT / "reports"
FROZEN_PATH = ROOT / "frozen_4a_evidence.json"
GAMEPLAY_PATH = ROOT / "frozen_gameplay_evidence.json"
RUBRIC_PATH = ROOT / "human_structure_rubric.json"
AUDIT_PATH = ROOT / "offline_segmentation_audit.json"
APPROVED_PATH = ROOT / "approved_run_manifest.json"
ALLOWED_POST_FREEZE_GODOT_SIDECAR_SUFFIXES = (".import", ".translation")
ASSET_NAMES = (
    "alpha_postmortem_4b.png",
    "v1_v2_sprite_comparison.png",
    "v2_alpha_masks.png",
    "component_debug.png",
    "alpha_metrics.csv",
)
PAIR_ORDER = (
    ("B01", 4041001),
    ("B01", 4041002),
    ("B02", 4041001),
    ("B02", 4041002),
    ("B03", 4041001),
    ("B03", 4041002),
    ("B04", 4041001),
    ("B04", 4041002),
)
BOOLEAN_FIELDS = (
    "raw_identity_recognizable",
    "canonical_identity_recognizable_96x96",
    "no_person_or_hand",
    "no_extraneous_text_or_watermark",
    "intrinsic_identity_markings_present",
    "subject_severely_missing",
    "background_ground_or_shadow_residual",
    "part_1_visible_raw",
    "part_1_preserved_v2",
    "part_2_visible_raw",
    "part_2_preserved_v2",
    "part_3_visible_raw",
    "part_3_preserved_v2",
)
KNOWN_LIMITATIONS = (
    "The border-coherence threshold is derived from the same border distribution and can accept a noisy magenta backdrop.",
    "The dense lower-row rejection is not constrained to a bottom-edge-connected run; it visibly removed valid lower structures in this run.",
    "Strong central color-difference pixels can be forced back after GrabCut, allowing some connected neutral shadows to survive.",
    "The secondary-component local-size rule lacks a mandatory bounding-box gap test and can retain an unrelated nearby component.",
    "A hard chroma edge can still produce a binary source matte; final resizing happened to provide soft pixels for these eight outputs.",
    "Semi-transparent RGB is quantized after a dark composite, which may produce dark fringes under Godot straight-alpha blending.",
    "A final delivery-validation failure is not currently published as a diagnostic rejection packet.",
)

sys.path.insert(0, str(ROOT))
import gate_b_4b_runner as runner  # noqa: E402


class FinalizeError(RuntimeError):
    pass


def _read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise FinalizeError(f"INVALID_JSON:{path}") from exc
    if not isinstance(value, dict):
        raise FinalizeError(f"JSON_ROOT_NOT_OBJECT:{path}")
    return value


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _sha256_file(path: Path) -> str:
    return runner.sha256_file(path)


def _resolve_frozen_path(project_root: Path, relative: str) -> Path:
    if not isinstance(relative, str) or not relative:
        raise FinalizeError("FROZEN_RECORD_PATH_INVALID")
    root = project_root.resolve()
    candidate = (root / relative).resolve()
    try:
        candidate.relative_to(root)
    except ValueError as exc:
        raise FinalizeError(f"FROZEN_RECORD_PATH_ESCAPES_PROJECT:{relative}") from exc
    return candidate


def _verify_frozen_record(project_root: Path, relative: str, record: Any) -> None:
    if not isinstance(record, dict):
        raise FinalizeError(f"FROZEN_RECORD_INVALID:{relative}")
    path = _resolve_frozen_path(project_root, relative)
    if not path.is_file():
        raise FinalizeError(f"FROZEN_RECORD_MISSING:{relative}")
    if path.stat().st_size != record.get("size"):
        raise FinalizeError(f"FROZEN_RECORD_SIZE_CHANGED:{relative}")
    actual_sha256 = _sha256_file(path)
    if actual_sha256 != record.get("sha256"):
        raise FinalizeError(f"FROZEN_RECORD_HASH_CHANGED:{relative}:{actual_sha256}")


def _audit_frozen_gameplay_for_closeout(
    *, project_root: Path, frozen_gameplay_path: Path
) -> dict[str, Any]:
    manifest_sha256 = _sha256_file(frozen_gameplay_path)
    if manifest_sha256 != runner.EXPECTED_FROZEN_GAMEPLAY_SHA256:
        raise FinalizeError(f"FROZEN_GAMEPLAY_MANIFEST_HASH_MISMATCH:{manifest_sha256}")
    frozen = _read_json(frozen_gameplay_path)
    records = frozen.get("files")
    if not isinstance(records, dict) or frozen.get("file_count") != len(records):
        raise FinalizeError("FROZEN_GAMEPLAY_FILE_MAP_INVALID")

    actual_paths = runner._current_gameplay_paths(project_root)  # noqa: SLF001
    expected_paths = set(records)
    missing = sorted(expected_paths - actual_paths)
    added = sorted(actual_paths - expected_paths)
    changed: list[dict[str, Any]] = []
    for relative in sorted(expected_paths & actual_paths):
        expected = records[relative]
        if not isinstance(expected, dict):
            raise FinalizeError(f"FROZEN_GAMEPLAY_RECORD_INVALID:{relative}")
        path = _resolve_frozen_path(project_root, relative)
        current_size = path.stat().st_size
        current_sha256 = _sha256_file(path)
        if current_size != expected.get("size") or current_sha256 != expected.get("sha256"):
            changed.append(
                {
                    "path": relative,
                    "expected_size": expected.get("size"),
                    "expected_sha256": expected.get("sha256"),
                    "current_size": current_size,
                    "current_sha256": current_sha256,
                }
            )
    added_records = [
        {
            "path": relative,
            "current_size": _resolve_frozen_path(project_root, relative).stat().st_size,
            "current_sha256": _sha256_file(_resolve_frozen_path(project_root, relative)),
        }
        for relative in added
    ]
    return {
        "status": "PASS" if not (missing or added or changed) else "RECORDED_PREEXISTING_DRIFT",
        "manifest_sha256": manifest_sha256,
        "frozen_file_count": len(records),
        "missing_count": len(missing),
        "added_count": len(added),
        "changed_count": len(changed),
        "missing": missing,
        "added": added_records,
        "changed": changed,
    }


def _verify_frozen_inputs_for_closeout(
    *,
    project_root: Path = PROJECT_ROOT,
    frozen_4a_path: Path = FROZEN_PATH,
    frozen_gameplay_path: Path = GAMEPLAY_PATH,
) -> tuple[dict[str, Any], dict[str, Any]]:
    """Verify frozen bytes and record later Godot metadata separately."""
    manifest_sha256 = _sha256_file(frozen_4a_path)
    if manifest_sha256 != runner.EXPECTED_FROZEN_4A_SHA256:
        raise FinalizeError(f"FROZEN_4A_MANIFEST_HASH_MISMATCH:{manifest_sha256}")
    frozen = _read_json(frozen_4a_path)
    tree = frozen.get("frozen_gate_4a_tree")
    if not isinstance(tree, dict) or frozen.get("frozen_gate_4a_tree_file_count") != len(tree):
        raise FinalizeError("FROZEN_4A_TREE_INVALID")

    project_root = project_root.resolve()
    gate_4a_root = project_root / "tools" / "comfyui" / "gate_b_4a"
    expected_paths = set(tree)
    actual_paths = {
        path.relative_to(project_root).as_posix()
        for path in gate_4a_root.rglob("*")
        if path.is_file()
    }
    missing = sorted(expected_paths - actual_paths)
    if missing:
        raise FinalizeError(f"FROZEN_4A_TREE_MISSING:{missing}")
    additions = sorted(actual_paths - expected_paths)
    disallowed = [
        relative
        for relative in additions
        if not relative.lower().endswith(ALLOWED_POST_FREEZE_GODOT_SIDECAR_SUFFIXES)
    ]
    if disallowed:
        raise FinalizeError(f"FROZEN_4A_UNEXPECTED_ADDITIONS:{disallowed}")

    for relative, record in tree.items():
        _verify_frozen_record(project_root, relative, record)
    for record in frozen.get("external_inputs", []):
        if not isinstance(record, dict):
            raise FinalizeError("FROZEN_EXTERNAL_INPUT_INVALID")
        _verify_frozen_record(project_root, record.get("path"), record)

    gameplay_audit = _audit_frozen_gameplay_for_closeout(
        project_root=project_root,
        frozen_gameplay_path=frozen_gameplay_path,
    )
    sidecars = [
        {
            "path": relative,
            "size": _resolve_frozen_path(project_root, relative).stat().st_size,
            "sha256": _sha256_file(_resolve_frozen_path(project_root, relative)),
        }
        for relative in additions
    ]
    return frozen, {
        "gate_4a": {
            "status": "PASS_FROZEN_BYTES_WITH_POST_FREEZE_GODOT_SIDECARS",
            "manifest_sha256": manifest_sha256,
            "frozen_tree_file_count": len(tree),
            "frozen_missing_count": 0,
            "frozen_changed_count": 0,
            "post_freeze_sidecar_count": len(sidecars),
            "post_freeze_sidecars": sidecars,
            "source_formal_status": "NEEDS WORK",
        },
        "gameplay": gameplay_audit,
    }


def _parse_bool(value: str, field: str, row_number: int) -> bool:
    normalized = value.strip().lower()
    if normalized == "true":
        return True
    if normalized == "false":
        return False
    raise FinalizeError(f"HUMAN_REVIEW_BOOLEAN_REQUIRED:row={row_number}:field={field}")


def _parse_count(value: str, field: str, row_number: int) -> int:
    try:
        parsed = int(value)
    except ValueError as exc:
        raise FinalizeError(f"HUMAN_REVIEW_INTEGER_REQUIRED:row={row_number}:field={field}") from exc
    if parsed < 0 or parsed > 3:
        raise FinalizeError(f"HUMAN_REVIEW_COUNT_OUT_OF_RANGE:row={row_number}:field={field}")
    return parsed


def validate_human_structure_review(
    review_bytes: bytes,
    rubric: dict[str, Any],
) -> list[dict[str, Any]]:
    try:
        text = review_bytes.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise FinalizeError("HUMAN_REVIEW_NOT_UTF8") from exc
    reader = csv.DictReader(io.StringIO(text))
    required_headers = {
        "case_id",
        "seed",
        *BOOLEAN_FIELDS,
        "part_1",
        "part_2",
        "part_3",
        "required_parts_visible_raw_count",
        "required_parts_preserved_v2_count",
        "reviewer",
        "notes",
    }
    if reader.fieldnames is None or not required_headers.issubset(set(reader.fieldnames)):
        missing = sorted(required_headers - set(reader.fieldnames or []))
        raise FinalizeError(f"HUMAN_REVIEW_HEADERS_MISSING:{missing}")
    parsed_rows: list[dict[str, Any]] = []
    for row_number, raw_row in enumerate(reader, start=2):
        case_id = (raw_row.get("case_id") or "").strip()
        try:
            seed = int((raw_row.get("seed") or "").strip())
        except ValueError as exc:
            raise FinalizeError(f"HUMAN_REVIEW_SEED_INVALID:row={row_number}") from exc
        if case_id not in rubric.get("cases", {}):
            raise FinalizeError(f"HUMAN_REVIEW_CASE_INVALID:row={row_number}:{case_id}")
        reviewer = (raw_row.get("reviewer") or "").strip()
        if not reviewer:
            raise FinalizeError(f"HUMAN_REVIEWER_REQUIRED:row={row_number}")
        if "not human" in reviewer.lower() or "codex" in reviewer.lower():
            raise FinalizeError(f"HUMAN_REVIEWER_NOT_HUMAN:row={row_number}")
        parsed: dict[str, Any] = {
            "case_id": case_id,
            "seed": seed,
            "reviewer": reviewer,
            "notes": (raw_row.get("notes") or "").strip(),
        }
        for field in BOOLEAN_FIELDS:
            parsed[field] = _parse_bool(raw_row.get(field) or "", field, row_number)
        expected_parts = rubric["cases"][case_id]["parts"]
        actual_parts = [(raw_row.get(f"part_{index}") or "").strip() for index in range(1, 4)]
        if actual_parts != expected_parts:
            raise FinalizeError(f"HUMAN_REVIEW_PART_LABEL_CHANGED:row={row_number}")
        parsed["parts"] = actual_parts
        visible_count = _parse_count(
            raw_row.get("required_parts_visible_raw_count") or "",
            "required_parts_visible_raw_count",
            row_number,
        )
        preserved_count = _parse_count(
            raw_row.get("required_parts_preserved_v2_count") or "",
            "required_parts_preserved_v2_count",
            row_number,
        )
        computed_visible = sum(parsed[f"part_{index}_visible_raw"] for index in range(1, 4))
        computed_preserved = sum(
            parsed[f"part_{index}_visible_raw"] and parsed[f"part_{index}_preserved_v2"]
            for index in range(1, 4)
        )
        if visible_count != computed_visible or preserved_count != computed_preserved:
            raise FinalizeError(f"HUMAN_REVIEW_PART_COUNT_MISMATCH:row={row_number}")
        for index in range(1, 4):
            if not parsed[f"part_{index}_visible_raw"] and parsed[f"part_{index}_preserved_v2"]:
                raise FinalizeError(f"HUMAN_REVIEW_PRESERVES_ABSENT_PART:row={row_number}:part={index}")
        parsed["required_parts_visible_raw_count"] = visible_count
        parsed["required_parts_preserved_v2_count"] = preserved_count
        parsed_rows.append(parsed)
    keys = [(row["case_id"], row["seed"]) for row in parsed_rows]
    if tuple(keys) != PAIR_ORDER:
        raise FinalizeError(f"HUMAN_REVIEW_MATRIX_CHANGED:{keys}")
    return parsed_rows


def _verify_sprite_delivery(result_dir: Path) -> tuple[bool, str]:
    try:
        with Image.open(result_dir / "processed_sprite.png") as opened_sprite:
            if opened_sprite.format != "PNG" or opened_sprite.mode != "RGBA":
                return False, "SPRITE_NOT_RGBA_PNG"
            opened_sprite.load()
            sprite = opened_sprite.copy()
        with Image.open(result_dir / "alpha_mask.png") as opened_alpha:
            if opened_alpha.format != "PNG" or opened_alpha.mode != "L":
                return False, "MASK_NOT_GRAYSCALE_PNG"
            opened_alpha.load()
            alpha = opened_alpha.copy()
    except OSError:
        return False, "PNG_UNREADABLE"
    if sprite.size != (96, 96) or alpha.size != (96, 96):
        return False, "DIMENSIONS_NOT_96"
    sprite_alpha = sprite.getchannel("A")
    if sprite_alpha.getbbox() is None:
        return False, "EMPTY_ALPHA"
    if sprite_alpha.tobytes() != alpha.tobytes():
        return False, "ALPHA_MISMATCH"
    return True, ""


def evaluate_thresholds(
    run_root: Path,
    run_summary: dict[str, Any],
    review_rows: list[dict[str, Any]],
    frozen: dict[str, Any],
) -> dict[str, Any]:
    review_by_key = {(row["case_id"], row["seed"]): row for row in review_rows}
    technical_success_count = 0
    fake_transparent_count = 0
    delivery_checks: dict[str, dict[str, Any]] = {}
    for result in run_summary["results"]:
        key = (result["case_id"], result["seed"])
        label = f"{key[0]}:{key[1]}"
        if result["v2"]["status"] == "success":
            technical_success_count += 1
            valid, failure = _verify_sprite_delivery(run_root / key[0] / f"seed_{key[1]}")
            if not valid:
                fake_transparent_count += 1
            delivery_checks[label] = {"valid": valid, "failure_reason": failure}
        else:
            delivery_checks[label] = {"valid": False, "failure_reason": result["v2"].get("failure_reason", "REJECTED")}
    serious_missing_count = sum(row["subject_severely_missing"] for row in review_rows)
    residual_count = sum(row["background_ground_or_shadow_residual"] for row in review_rows)
    usable_alpha_count = sum(
        delivery_checks[f"{row['case_id']}:{row['seed']}"]["valid"]
        and not row["subject_severely_missing"]
        and not row["background_ground_or_shadow_residual"]
        for row in review_rows
    )
    raw_identity_count = sum(row["raw_identity_recognizable"] for row in review_rows)
    preserved_identity_count = sum(
        row["raw_identity_recognizable"] and row["canonical_identity_recognizable_96x96"]
        for row in review_rows
    )
    b01_parts = all(
        review_by_key[("B01", seed)]["part_2_visible_raw"]
        and review_by_key[("B01", seed)]["part_2_preserved_v2"]
        and review_by_key[("B01", seed)]["part_3_visible_raw"]
        and review_by_key[("B01", seed)]["part_3_preserved_v2"]
        for seed in (4041001, 4041002)
    )
    b03_seed_one = (
        next(
            result["v2"]["status"]
            for result in run_summary["results"]
            if result["case_id"] == "B03" and result["seed"] == 4041001
        )
        == "success"
        and not review_by_key[("B03", 4041001)]["subject_severely_missing"]
    )
    b04_parts = all(
        review_by_key[("B04", seed)]["part_2_visible_raw"]
        and review_by_key[("B04", seed)]["part_2_preserved_v2"]
        and review_by_key[("B04", seed)]["part_3_visible_raw"]
        and review_by_key[("B04", seed)]["part_3_preserved_v2"]
        for seed in (4041001, 4041002)
    )
    raw_baseline = frozen["source_raw_identity_count_frozen_by_4b_contract"]["passed"]
    gates = {
        "usable_transparent_alpha_at_least_7_of_8": usable_alpha_count >= 7,
        "fake_transparent_zero": fake_transparent_count == 0,
        "serious_subject_missing_zero": serious_missing_count == 0,
        "raw_identity_baseline_is_6_of_8": raw_identity_count == raw_baseline == 6,
        "all_six_raw_identities_remain_recognizable_at_96": preserved_identity_count >= raw_baseline,
        "b01_hose_and_nozzle_preserved_both_seeds": b01_parts,
        "b03_seed_4041001_remains_usable": b03_seed_one,
        "b04_stem_and_base_preserved_both_seeds": b04_parts,
        "background_ground_shadow_residual_zero": residual_count == 0,
        "human_review_complete_8_of_8": len(review_rows) == 8,
    }
    return {
        "status": "PASS" if all(gates.values()) else "NEEDS WORK",
        "technical_alpha_success_count": technical_success_count,
        "usable_alpha_count": usable_alpha_count,
        "fake_transparent_count": fake_transparent_count,
        "serious_subject_missing_count": serious_missing_count,
        "background_ground_shadow_residual_count": residual_count,
        "raw_identity_recognizable_count": raw_identity_count,
        "raw_identity_preserved_at_96_count": preserved_identity_count,
        "no_person_or_hand_count": sum(row["no_person_or_hand"] for row in review_rows),
        "no_extraneous_text_or_watermark_count": sum(
            row["no_extraneous_text_or_watermark"] for row in review_rows
        ),
        "intrinsic_identity_markings_present_count": sum(
            row["intrinsic_identity_markings_present"] for row in review_rows
        ),
        "delivery_checks": delivery_checks,
        "gates": gates,
    }


def _report_markdown(
    run_summary: dict[str, Any],
    frozen: dict[str, Any],
    review_rows: list[dict[str, Any]],
    evaluation: dict[str, Any],
    audit: dict[str, Any],
    review_sha256: str,
    preflight: dict[str, Any],
) -> str:
    result_by_key = {(result["case_id"], result["seed"]): result for result in run_summary["results"]}
    lines = [
        "# Forge Gate B 4B — Offline Alpha Extraction Spike",
        "",
        f"Final status: **{evaluation['status']}**",
        "",
        "Gate B 4A remains **NEEDS WORK**. No Gate B 4A file, frozen raw image, prompt, seed, manifest, score, or conclusion was rewritten.",
        "",
        "## Outcome",
        "",
        f"- v1 technical Alpha delivery: 1/8.",
        f"- v2 technical Alpha delivery: {evaluation['technical_alpha_success_count']}/8.",
        f"- v2 usable Alpha after human structure review: {evaluation['usable_alpha_count']}/8.",
        f"- Serious subject loss: {evaluation['serious_subject_missing_count']}/8.",
        f"- Frozen raw identity baseline: {evaluation['raw_identity_recognizable_count']}/8; retained at 96×96: {evaluation['raw_identity_preserved_at_96_count']}/8.",
        f"- Fake-transparent deliveries: {evaluation['fake_transparent_count']}.",
        f"- Human review SHA-256: `{review_sha256}`.",
        f"- Frozen Gate B 4A bytes verified unchanged: {preflight['gate_4a']['frozen_tree_file_count']}/{preflight['gate_4a']['frozen_tree_file_count']}.",
        f"- Post-freeze Godot `.import`/`.translation` sidecars recorded separately: {preflight['gate_4a']['post_freeze_sidecar_count']}.",
        f"- Pre-existing gameplay drift recorded at closeout: changed={preflight['gameplay']['changed_count']}, added={preflight['gameplay']['added_count']}, missing={preflight['gameplay']['missing_count']}.",
        "",
        "The selected OpenCV Chroma + GrabCut method was the only locally executable candidate. It did not defeat an installed learned model in a head-to-head comparison: Candidate B was unavailable because its local node code had no installed weights.",
        "",
        "## Eight frozen results",
        "",
        "| Case | Seed | v1 | v2 technical | Confidence | 96px identity | Serious loss | Preserved parts |",
        "|---|---:|---|---|---:|---|---|---:|",
    ]
    for review in review_rows:
        key = (review["case_id"], review["seed"])
        result = result_by_key[key]
        v1 = result["v1"]["status"]
        if result["v1"].get("failure_reason"):
            v1 += f" ({result['v1']['failure_reason']})"
        lines.append(
            f"| {key[0]} | {key[1]} | {v1} | {result['v2']['status']} | "
            f"{result['v2']['metrics']['segmentation_confidence']:.3f} | "
            f"{'yes' if review['canonical_identity_recognizable_96x96'] else 'no'} | "
            f"{'yes' if review['subject_severely_missing'] else 'no'} | "
            f"{review['required_parts_preserved_v2_count']}/{review['required_parts_visible_raw_count']} |"
        )
    lines.extend(
        [
            "",
            "## Thresholds",
            "",
        ]
    )
    for name, passed in evaluation["gates"].items():
        lines.append(f"- {'PASS' if passed else 'FAIL'} — `{name}`")
    lines.extend(
        [
            "",
            "## v1 failure postmortem",
            "",
            "The exact v1 replay found six `OBJECT_TOUCHES_RAW_EDGE` failures, one `BACKGROUND_NOT_HIGH_CONTRAST_CHROMA` failure, and one success. Gradients, floor bands, shadows, and reflections joined the inverse-background candidate; largest-component-only selection could not distinguish those regions from the prop.",
            "",
            "## v2 interpretation",
            "",
            "v2 produced valid 96×96 RGBA/Alpha pairs for all eight inputs, but its confidence range of 0.945–0.976 failed to flag visible subject loss. The primary actual failure layer is the postprocess algorithm, especially the lower dense-row rejection. This is not evidence that all eight RealVisXL raw generations failed.",
            "",
            "B02 clock-face numbers and hands were reviewed as intrinsic identity markings, not extraneous text or a watermark.",
            "",
            "## Offline environment audit",
            "",
            f"- Learned Candidate B: `{audit['candidate_b']['status']}` and not executed.",
            "- Native BiRefNet and SAM3 node source exists locally, but the required model weights are absent.",
            "- Bria RMBG is an upload/API node and was not used.",
            "- No package, node, or model was downloaded or installed.",
            "",
            "## Known v2 limitations",
            "",
        ]
    )
    lines.extend(f"- {item}" for item in KNOWN_LIMITATIONS)
    lines.extend(
        [
            "",
            "## Recommendation",
            "",
            "RealVisXL may remain a temporary raw prop generator because the frozen raw identity baseline is still 6/8, but the current photographic studio backdrop plus classical chroma extraction is not reliable as a Sprite delivery chain. A future separately approved experiment should either use a genuinely flat no-floor generation workflow or an approved fully local learned segmentation model.",
            "",
            "Do **not** enter anchor calibration or the training-zone integration from this result. The Alpha/structure gate is not met.",
            "",
            "No Anthropic call, ComfyUI launch, image regeneration, network access, gameplay edit, anchor edit, or V2 work occurred in Gate B 4B.",
            "The closeout preflight and postflight snapshots are byte-identical. Any gameplay drift listed in the evidence ledger predates this closeout and was neither reverted nor modified.",
            "",
        ]
    )
    return "\n".join(lines)


def _evidence_record(path: Path) -> dict[str, Any]:
    return {"path": path.resolve().as_posix(), "size": path.stat().st_size, "sha256": _sha256_file(path)}


def finalize_gate_b_4b(
    *,
    run_root: Path,
    packet_root: Path,
    human_review_path: Path,
    reports_root: Path = REPORTS_ROOT,
) -> dict[str, Any]:
    run_root = run_root.resolve()
    packet_root = packet_root.resolve()
    human_review_path = human_review_path.resolve()
    run_summary = _read_json(run_root / "run_summary.json")
    run_id = run_summary.get("run_id")
    if not isinstance(run_id, str) or not re.fullmatch(r"gate-b-4b-[A-Za-z0-9-]+", run_id):
        raise FinalizeError("RUN_ID_INVALID")
    if run_root.name != run_id:
        raise FinalizeError("RUN_DIRECTORY_ID_MISMATCH")
    approved = _read_json(APPROVED_PATH)
    if _sha256_file(ROOT / "process_sprite_v2.py") != approved["processor_sha256"]:
        raise FinalizeError("PROCESSOR_CHANGED_AFTER_APPROVAL")
    if run_summary["processor"]["sha256"] != approved["processor_sha256"]:
        raise FinalizeError("RUN_PROCESSOR_NOT_APPROVED")
    frozen, preflight = _verify_frozen_inputs_for_closeout(
        project_root=PROJECT_ROOT,
        frozen_4a_path=FROZEN_PATH,
        frozen_gameplay_path=GAMEPLAY_PATH,
    )
    review_bytes = human_review_path.read_bytes()
    rubric = _read_json(RUBRIC_PATH)
    review_rows = validate_human_structure_review(review_bytes, rubric)
    evaluation = evaluate_thresholds(run_root, run_summary, review_rows, frozen)
    audit = _read_json(AUDIT_PATH)
    report_root = (reports_root.resolve() / run_id)
    if report_root.exists():
        raise FinalizeError("REPORT_DIRECTORY_EXISTS")
    reports_root.resolve().mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix=f".{run_id}.tmp-", dir=str(reports_root.resolve())))
    published = False
    try:
        for name in ASSET_NAMES:
            source = packet_root / name
            if not source.is_file():
                raise FinalizeError(f"REVIEW_ASSET_MISSING:{name}")
            shutil.copyfile(source, stage / name)
        (stage / "human_structure_review.csv").write_bytes(review_bytes)
        summary = {
            "gate": "Forge Gate B 4B - Offline Alpha Extraction Spike",
            "run_id": run_id,
            "status": evaluation["status"],
            "source_gate_4a_formal_status_preserved": "NEEDS WORK",
            "method_a": "opencv_chroma_grabcut",
            "method_b": audit["candidate_b"]["status"],
            "method_winner": "NO_HEAD_TO_HEAD_WINNER_METHOD_A_ONLY_EXECUTABLE",
            "processor_sha256": run_summary["processor"]["sha256"],
            "human_review_sha256": _sha256_bytes(review_bytes),
            "metrics": evaluation,
            "realvisxl_recommendation": "TEMPORARY_RAW_GENERATOR_ONLY_NOT_CURRENT_SPRITE_CHAIN",
            "ready_for_anchor_or_training_zone": False,
            "anthropic_called": False,
            "comfyui_started": False,
            "images_regenerated": False,
            "network_used": False,
            "gate_4a_modified": False,
            "gameplay_modified": False,
            "preexisting_gameplay_drift_count": (
                preflight["gameplay"]["changed_count"]
                + preflight["gameplay"]["added_count"]
                + preflight["gameplay"]["missing_count"]
            ),
            "automatic_retry_count": 0,
            "preflight": preflight,
        }
        (stage / "gate_b_4b_summary.json").write_text(
            json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        report = _report_markdown(
            run_summary,
            frozen,
            review_rows,
            evaluation,
            audit,
            _sha256_bytes(review_bytes),
            preflight,
        )
        (stage / "GATE_B_4B_REPORT.md").write_text(report, encoding="utf-8")
        _, postflight = _verify_frozen_inputs_for_closeout(
            project_root=PROJECT_ROOT,
            frozen_4a_path=FROZEN_PATH,
            frozen_gameplay_path=GAMEPLAY_PATH,
        )
        if postflight != preflight:
            raise FinalizeError("FROZEN_INPUTS_CHANGED_DURING_FINALIZATION")
        evidence_inputs = [
            FROZEN_PATH,
            GAMEPLAY_PATH,
            RUBRIC_PATH,
            AUDIT_PATH,
            APPROVED_PATH,
            ROOT / "process_sprite_v2.py",
            ROOT / "gate_b_4b_runner.py",
            ROOT / "gate_b_4b_assets.py",
            run_root / "run_summary.json",
            run_root / "RUN_COMPLETE.json",
            human_review_path,
        ]
        evidence_inputs.extend(
            _resolve_frozen_path(PROJECT_ROOT, record["path"])
            for record in preflight["gate_4a"]["post_freeze_sidecars"]
        )
        evidence_inputs.extend(
            _resolve_frozen_path(PROJECT_ROOT, record["path"])
            for key in ("changed", "added")
            for record in preflight["gameplay"][key]
        )
        for result in run_summary["results"]:
            result_dir = run_root / result["case_id"] / f"seed_{result['seed']}"
            evidence_inputs.extend(
                result_dir / name
                for name in ("raw.png", "processed_sprite.png", "alpha_mask.png", "metrics.json", "result.json")
            )
        delivery_records = {
            path.name: _evidence_record(path)
            for path in sorted(stage.iterdir())
            if path.is_file() and path.name != "evidence_hashes.json"
        }
        evidence = {
            "gate": "Forge Gate B 4B - Offline Alpha Extraction Spike",
            "run_id": run_id,
            "source_gate_4a_status": "NEEDS WORK",
            "preflight": preflight,
            "postflight": postflight,
            "inputs": [_evidence_record(path) for path in evidence_inputs],
            "deliverables_excluding_this_ledger": delivery_records,
            "ledger_self_hash_policy": "evidence_hashes.json cannot include its own SHA-256 without recursion.",
        }
        (stage / "evidence_hashes.json").write_text(
            json.dumps(evidence, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        if report_root.exists():
            raise FinalizeError("REPORT_DIRECTORY_EXISTS")
        os.rename(stage, report_root)
        published = True
    finally:
        if not published and stage.exists():
            shutil.rmtree(stage)
    return {
        "status": evaluation["status"],
        "run_id": run_id,
        "report_directory": report_root.as_posix(),
        "usable_alpha_count": evaluation["usable_alpha_count"],
        "technical_alpha_success_count": evaluation["technical_alpha_success_count"],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Finalize Gate B 4B from an explicit human visual review.")
    parser.add_argument("--run-root", type=Path, required=True)
    parser.add_argument("--packet-root", type=Path, required=True)
    parser.add_argument("--human-review", type=Path, required=True)
    parser.add_argument("--reports-root", type=Path, default=REPORTS_ROOT)
    args = parser.parse_args()
    try:
        result = finalize_gate_b_4b(
            run_root=args.run_root,
            packet_root=args.packet_root,
            human_review_path=args.human_review,
            reports_root=args.reports_root,
        )
    except (FinalizeError, runner.GateB4BRunnerError, OSError, KeyError, ValueError) as exc:
        print(json.dumps({"status": "NEEDS WORK", "failure_reason": str(exc)}, ensure_ascii=False))
        return 2
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
