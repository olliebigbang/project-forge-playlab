from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from flux2_profile_bridge import Flux2BridgeError, generate, resolve_profile


REPO_ROOT = Path(__file__).resolve().parents[4]
FLUX_ROOT = Path(__file__).resolve().parents[1]
COMFY_ROOT = FLUX_ROOT.parent
REPORTS = FLUX_ROOT / "reports"
FROZEN_BLUEPRINTS = REPORTS / "frozen_semantic_blueprints.json"
HANDOFF = COMFY_ROOT / "gate_b_4a" / "frozen" / "frozen_handoff.json"
EXPECTED_HANDOFF_SHA256 = "cb084add3587889f1bcb00651b2f25458c03c5ef73bc5f44e436264f65c52083"
CASE_ORDER = ("B01", "B02", "B03", "B04")
SEEDS = (4041001, 4041002)
SMOKE_SEED = 5050001
EDIT_SMOKE_SEED = 5050002
SMOKE_PROMPT = (
    "one isolated old wooden table, flat rectangular tabletop, four wooden legs, "
    "aged wood, side view, complete object visible, plain background"
)
IDENTITY_FIELDS = (
    "canonical_name_en",
    "required_identity_parts",
    "material_hints",
    "silhouette_hints",
    "optional_decorations",
)
VISUAL_FIELDS = ("prompt_en", "negative_prompt_en", "must_preserve", "must_not_replace_with")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def _canonical_sha(value: Any) -> str:
    encoded = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _atomic_json(path: Path, payload: Any, *, exclusive: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = (json.dumps(payload, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    if exclusive:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL)
        try:
            os.write(descriptor, data)
        finally:
            os.close(descriptor)
        return
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    try:
        temporary.write_bytes(data)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def _ascii_projection(value: Any, pointer: str = "") -> None:
    if isinstance(value, str):
        if any(ord(character) > 127 for character in value):
            raise Flux2BridgeError(f"NON_ASCII_FROZEN_FIELD:{pointer or '/'}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _ascii_projection(child, f"{pointer}/{index}")
    elif isinstance(value, dict):
        for key, child in value.items():
            _ascii_projection(child, f"{pointer}/{key}")


def freeze_blueprints() -> dict[str, Any]:
    if _sha256(HANDOFF) != EXPECTED_HANDOFF_SHA256:
        raise Flux2BridgeError("FROZEN_4A_HANDOFF_HASH_MISMATCH")
    handoff = json.loads(HANDOFF.read_text(encoding="utf-8"))
    frozen_cases: dict[str, Any] = {}
    for case_id in CASE_ORDER:
        handoff_case = handoff["cases"][case_id]
        source = REPO_ROOT / handoff_case["source_file"]
        if _sha256(source) != handoff_case["source_result_sha256"]:
            raise Flux2BridgeError(f"FROZEN_3C_SOURCE_HASH_MISMATCH:{case_id}")
        source_payload = json.loads(source.read_text(encoding="utf-8"))
        result = source_payload.get("result")
        if not isinstance(result, dict):
            raise Flux2BridgeError(f"FROZEN_3C_COMPILED_RESULT_MISSING:{case_id}")
        projection = {
            "identity": {field: result["identity"][field] for field in IDENTITY_FIELDS},
            "visual": {field: result["visual"][field] for field in VISUAL_FIELDS},
        }
        seven_field_projection = {
            "identity": {field: projection["identity"][field] for field in IDENTITY_FIELDS},
            "visual": {field: projection["visual"][field] for field in VISUAL_FIELDS[:2]},
        }
        if seven_field_projection != handoff_case["handoff"]:
            raise Flux2BridgeError(f"FROZEN_4A_AND_3C_PROJECTION_DIVERGED:{case_id}")
        _ascii_projection(projection)
        frozen_cases[case_id] = {
            "source_file": handoff_case["source_file"],
            "source_result_sha256": handoff_case["source_result_sha256"],
            "source_tool_input_sha256": handoff_case["source_tool_input_sha256"],
            "projection_sha256": _canonical_sha(projection),
            "blueprint": projection,
        }
    payload = {
        "contract": "forge-flux2-frozen-semantic-blueprints-v1",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "source_handoff": HANDOFF.relative_to(REPO_ROOT).as_posix(),
        "source_handoff_sha256": EXPECTED_HANDOFF_SHA256,
        "case_order": list(CASE_ORDER),
        "seeds": list(SEEDS),
        "planned_generation_count": 8,
        "source_language_sent_to_flux": "English only",
        "semantic_reinterpretation_performed": False,
        "cases": frozen_cases,
    }
    if FROZEN_BLUEPRINTS.exists():
        existing = json.loads(FROZEN_BLUEPRINTS.read_text(encoding="utf-8"))
        comparable = dict(existing)
        comparable.pop("created_at", None)
        expected = dict(payload)
        expected.pop("created_at", None)
        if comparable != expected:
            raise Flux2BridgeError("FROZEN_BLUEPRINT_FILE_ALREADY_EXISTS_WITH_DIFFERENT_CONTENT")
        return existing
    _atomic_json(FROZEN_BLUEPRINTS, payload, exclusive=True)
    return payload


def _smoke_blueprint() -> dict[str, Any]:
    return {
        "identity": {
            "canonical_name_en": "old wooden table",
            "required_identity_parts": ["flat rectangular tabletop", "four wooden legs"],
            "material_hints": ["aged wood"],
            "silhouette_hints": ["rectangular tabletop supported by four legs"],
            "optional_decorations": [],
        },
        "visual": {
            "prompt_en": SMOKE_PROMPT,
            "negative_prompt_en": "human, person, hand, text, watermark, multiple objects, cropped object",
            "must_preserve": ["flat rectangular tabletop", "four wooden legs"],
            "must_not_replace_with": ["gun", "sword", "umbrella"],
        },
    }


def run_smoke(profile_name: str, mode: str = "normal") -> Path:
    if mode not in {"normal", "low_memory"}:
        raise Flux2BridgeError("SMOKE_MODE_INVALID")
    profile = resolve_profile(profile_name)
    return generate(
        profile,
        case_id="smoke_t2i",
        run_id=f"seed_{SMOKE_SEED}_{mode}",
        output_group="smoke",
        blueprint=_smoke_blueprint(),
        seed=SMOKE_SEED,
        raw_only=True,
        exact_positive_prompt=SMOKE_PROMPT,
    )


def run_edit_smoke(profile_name: str, reference: Path | None) -> Path:
    profile = resolve_profile(profile_name)
    if reference is None:
        normal = Path(profile["output_root"]) / "smoke" / "smoke_t2i" / f"seed_{SMOKE_SEED}_normal" / "raw.png"
        low_memory = Path(profile["output_root"]) / "smoke" / "smoke_t2i" / f"seed_{SMOKE_SEED}_low_memory" / "raw.png"
        reference = normal if normal.is_file() else low_memory
    return generate(
        profile,
        case_id="smoke_edit",
        run_id=f"seed_{EDIT_SMOKE_SEED}",
        output_group="smoke",
        blueprint=_smoke_blueprint(),
        seed=EDIT_SMOKE_SEED,
        mode="edit",
        reference_image=reference,
        raw_only=True,
    )


def _reserve_matrix(output_root: Path, run_id: str, freeze_sha: str) -> Path:
    reservation = output_root / ".reservations" / "formal_matrix_v1.json"
    _atomic_json(
        reservation,
        {
            "contract": "forge-flux2-formal-matrix-reservation-v1",
            "run_id": run_id,
            "frozen_blueprints_sha256": freeze_sha,
            "planned_generation_count": 8,
            "retry_policy": "zero automatic retries",
            "reserved_at": datetime.now(timezone.utc).isoformat(),
        },
        exclusive=True,
    )
    return reservation


def run_matrix(profile_name: str) -> Path:
    frozen = freeze_blueprints()
    profile = resolve_profile(profile_name)
    output_root = Path(profile["output_root"])
    run_id = datetime.now(timezone.utc).strftime("flux2-matrix-%Y%m%dT%H%M%S%fZ")
    output_group = run_id.replace("-", "_").lower()
    reservation = _reserve_matrix(output_root, run_id, _sha256(FROZEN_BLUEPRINTS))
    records: list[dict[str, Any]] = []
    ordinal = 0
    for case_id in CASE_ORDER:
        blueprint = frozen["cases"][case_id]["blueprint"]
        for seed in SEEDS:
            ordinal += 1
            item: dict[str, Any] = {
                "ordinal": ordinal,
                "case_id": case_id,
                "seed": seed,
                "retry_count": 0,
                "status": "failed",
                "output_directory": "",
                "failure_reason": "",
            }
            final = output_root / output_group / case_id.lower() / f"seed_{seed}"
            try:
                delivered = generate(
                    profile,
                    case_id=case_id,
                    run_id=f"seed_{seed}",
                    output_group=output_group,
                    blueprint=blueprint,
                    seed=seed,
                )
                item["output_directory"] = str(delivered)
            except Flux2BridgeError as exc:
                item["failure_reason"] = str(exc)
                item["output_directory"] = str(final)
            manifest = final / "manifest.json"
            if manifest.is_file():
                item["manifest"] = json.loads(manifest.read_text(encoding="utf-8"))
                item["status"] = item["manifest"].get("status", "failed")
                item["failure_reason"] = item["manifest"].get("failure_reason", item["failure_reason"])
            records.append(item)
    summary = {
        "contract": "forge-flux2-formal-matrix-summary-v1",
        "run_id": run_id,
        "output_group": output_group,
        "frozen_blueprints_file": str(FROZEN_BLUEPRINTS),
        "frozen_blueprints_sha256": _sha256(FROZEN_BLUEPRINTS),
        "reservation_file": str(reservation),
        "planned_generation_count": 8,
        "attempted_generation_count": len(records),
        "automatic_retry_count": sum(int(item["retry_count"]) for item in records),
        "records": records,
        "completed_at": datetime.now(timezone.utc).isoformat(),
    }
    destination = output_root / output_group / "generation_summary.json"
    _atomic_json(destination, summary, exclusive=True)
    return destination


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the approved, no-retry FLUX.2 Spike 5 sequence.")
    parser.add_argument("--profile", default="flux2_klein_4b")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("freeze")
    smoke = sub.add_parser("smoke")
    smoke.add_argument("--mode", choices=("normal", "low_memory"), default="normal")
    edit = sub.add_parser("edit-smoke")
    edit.add_argument("--reference", type=Path)
    sub.add_parser("matrix")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.command == "freeze":
            result: Any = freeze_blueprints()
            result = {"status": "PASS", "path": str(FROZEN_BLUEPRINTS), "sha256": _sha256(FROZEN_BLUEPRINTS)}
        elif args.command == "smoke":
            result = {"status": "success", "output_directory": str(run_smoke(args.profile, args.mode))}
        elif args.command == "edit-smoke":
            result = {"status": "success", "output_directory": str(run_edit_smoke(args.profile, args.reference))}
        else:
            result = {"status": "COMPLETE", "summary": str(run_matrix(args.profile))}
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (Flux2BridgeError, OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(json.dumps({"status": "FAIL", "failure_reason": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
