from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import shutil
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parent
COMFY_ROOT = ROOT.parent
PROJECT_ROOT = COMFY_ROOT.parent.parent
BRIDGE_ROOT = COMFY_ROOT / "bridge"
POSTPROCESS_ROOT = COMFY_ROOT / "postprocess"
sys.path.insert(0, str(BRIDGE_ROOT))
sys.path.insert(0, str(POSTPROCESS_ROOT))

from forge_comfy_bridge import (  # noqa: E402
    BridgeError,
    SYSTEM_NEGATIVE,
    SYSTEM_POSITIVE,
    _output_path,
    _prepare_input,
    _submit_and_wait,
    health_check,
    inject_workflow,
    validate_api_base,
)
from process_sprite import SpritePostprocessError, process_sprite  # noqa: E402


CASE_ORDER = ("B01", "B02", "B03", "B04")
SEEDS = (4041001, 4041002)
RUN_COUNT = 8
SOURCE_RUN = (
    PROJECT_ROOT
    / "tools"
    / "semantic"
    / "output"
    / "blind_retest_3c"
    / "blind-retest-3c-20260803T060715018997Z-4ddf8f31"
)
SOURCE_RESULT_HASHES = {
    "B01": "5eb529c9f817b5ef8d2061f3068af3fda61c57fa1485174afc60e244bc48a918",
    "B02": "8255ec89850c145ecc707bacac2dafd97d502ce7e021b0593e42ac5cb2cb0ed6",
    "B03": "116f6bae56d34927d088ad544ec40fad7ed17b2a6d3dda20cf4c874e9ce6b4aa",
    "B04": "bcc65d2408980f32cf1c9eab037c67af6e562402c4ea39a3159ebb195cb48983",
}
SOURCE_TOOL_INPUT_HASHES = {
    "B01": "d7fdfc05e968a69711e1d8588703e3157156ef69f352fd4bee278be1cec5031e",
    "B02": "ee9d4308c471681f164934e81f9f2336d3310ee7f4e5edaf3a8cc840bd04006b",
    "B03": "9678c5cf7b33e6d7e60ac4ca1aa219608a0edbd6047110c06d6b4e72f766af0e",
    "B04": "6914315979b4e94f21dfe381e2d2c2b6deb2af597ec852515775bff99124efaf",
}
HANDOFF_HASHES = {
    "B01": "625b600f54ce062e522cff2811265b6c40d7fc1aabb0d4557a1530f8f5d7bfba",
    "B02": "63933f45b3bc9cf817e8594f20ba163d929cc175354ea76ca74ef4cddcbca3f1",
    "B03": "1cf2baaaad26308d99cc5e886703095901dc5e5163beb314c30515f6ce1aa446",
    "B04": "33df2fff63abbd414357b54c22cd518b5b7e0c475d62176bb15fb6325beff96d",
}
WORKFLOW_SHA256 = "507095e0e1cbe0556d1bcac7cff8d28e93af65d843f69cc54de836ff267398a5"
POSTPROCESS_SHA256 = "f748c8e61dfd022d351d84c57c2d68b50b3dc39685403c7af20cc0402eebc0e9"
CHECKPOINT_SHA256 = "6a35a7855770ae9820a3c931d4964c3817b6d9e3c6f9c4dabb5b3a94e5643b80"
SPIKE2_REPORT_HASHES = {
    "tools/comfyui/open_identity/reports/evidence_hashes.json": "0d92d689ea57150f5c793c258c08d98bb25b9d4bce0e8cafa87ec8c80f8393f1",
    "tools/comfyui/open_identity/reports/SPIKE2_REPORT.md": "039ee41cbb5ab83233a1b7f051123858e7bcedeade207dbc0d0f81d2694a065d",
    "tools/comfyui/open_identity/reports/evaluation.json": "eaf467b3bbe63197fe817dca6c84b6f29e03df27e821c05f415bb12eb9e495df",
    "tools/comfyui/open_identity/reports/generation_summary.json": "3fbd4fd344c1cbc32939a9e11a7ad2e67d541b42e21d5c7d106cb27fd42b4e8e",
    "tools/comfyui/open_identity/reports/identity_raw_processed_comparison.png": "82e402458614d1fede448658948f58fc8a56ab2586ad522360fa5d54f59066ef",
    "tools/comfyui/open_identity/reports/prompt_policy_ab_comparison.png": "9b4f071d03eee549c982665333ccf55a8deccb947d8575390c6880bb7291c4e0",
}
FROZEN_DIRECTORY = ROOT / "frozen"
FROZEN_HANDOFF_PATH = FROZEN_DIRECTORY / "frozen_handoff.json"
PROTECTED_HISTORY_PATH = FROZEN_DIRECTORY / "protected_history.json"
APPROVED_MANIFEST_PATH = ROOT / "approved_run_manifest.json"
APPROVED_MANIFEST_SHA256 = "02d33878f82a63e264e41a15818978f1bbe4b436a50326f0640afb74cc5fedb3"
RESERVATION_PATH = ROOT / "GATE_B_4A_RUN.reservation.json"
OUTPUT_ROOT = ROOT / "output"


class GateBError(RuntimeError):
    pass


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def atomic_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    temporary.write_bytes(json.dumps(value, ensure_ascii=False, indent=2).encode("utf-8") + b"\n")
    os.replace(temporary, path)


def _is_english_only(value: Any) -> bool:
    if isinstance(value, str):
        return value.isascii()
    if isinstance(value, list):
        return all(_is_english_only(item) for item in value)
    if isinstance(value, dict):
        return all(_is_english_only(key) and _is_english_only(item) for key, item in value.items())
    return True


def _require_string_list(value: Any, pointer: str) -> list[str]:
    if not isinstance(value, list) or not value or any(not isinstance(item, str) or not item.strip() for item in value):
        raise GateBError(f"INVALID_STRING_LIST:{pointer}")
    return list(value)


def _extract_handoff(result: dict[str, Any]) -> dict[str, Any]:
    identity = result.get("identity")
    visual = result.get("visual")
    if not isinstance(identity, dict) or not isinstance(visual, dict):
        raise GateBError("SOURCE_IDENTITY_OR_VISUAL_MISSING")
    canonical = identity.get("canonical_name_en")
    prompt = visual.get("prompt_en")
    negative = visual.get("negative_prompt_en")
    if any(not isinstance(item, str) or not item.strip() for item in (canonical, prompt, negative)):
        raise GateBError("SOURCE_ENGLISH_FIELD_INVALID")
    handoff = {
        "identity": {
            "canonical_name_en": canonical,
            "required_identity_parts": _require_string_list(
                identity.get("required_identity_parts"), "/identity/required_identity_parts"
            ),
            "material_hints": _require_string_list(identity.get("material_hints"), "/identity/material_hints"),
            "silhouette_hints": _require_string_list(
                identity.get("silhouette_hints"), "/identity/silhouette_hints"
            ),
            "optional_decorations": _require_string_list(
                identity.get("optional_decorations"), "/identity/optional_decorations"
            ),
        },
        "visual": {"prompt_en": prompt, "negative_prompt_en": negative},
    }
    if not _is_english_only(handoff):
        raise GateBError("HANDOFF_MUST_BE_ASCII_ENGLISH_ONLY")
    return handoff


def compose_positive(handoff: dict[str, Any]) -> str:
    identity = handoff["identity"]
    visual = handoff["visual"]
    segments = (
        f"canonical object identity: {identity['canonical_name_en']}",
        "required identity parts: " + "; ".join(identity["required_identity_parts"]),
        "material hints: " + "; ".join(identity["material_hints"]),
        "silhouette hints: " + "; ".join(identity["silhouette_hints"]),
        "optional decorations: " + "; ".join(identity["optional_decorations"]),
        "frozen visual description: " + visual["prompt_en"],
        SYSTEM_POSITIVE,
    )
    return ". ".join(segment.rstrip(". ") for segment in segments) + "."


def compose_negative(handoff: dict[str, Any]) -> str:
    return ". ".join(
        segment.rstrip(". ") for segment in (handoff["visual"]["negative_prompt_en"], SYSTEM_NEGATIVE)
    ) + "."


def load_source_case(case_id: str) -> dict[str, Any]:
    path = SOURCE_RUN / case_id / "result.json"
    raw = path.read_bytes()
    actual_hash = sha256_bytes(raw)
    if actual_hash != SOURCE_RESULT_HASHES[case_id]:
        raise GateBError(f"SOURCE_RESULT_HASH_MISMATCH:{case_id}:{actual_hash}")
    payload = json.loads(raw.decode("utf-8"))
    if payload.get("case_id") != case_id or payload.get("result_type") != "compiled":
        raise GateBError(f"SOURCE_NOT_COMPILED:{case_id}")
    if payload.get("schema_valid") is not True:
        raise GateBError(f"SOURCE_SCHEMA_INVALID:{case_id}")
    validation = payload.get("validation", {})
    if validation.get("schema_valid") is not True or validation.get("cross_field_valid") is not True:
        raise GateBError(f"SOURCE_VALIDATION_INVALID:{case_id}")
    for field in ("repair_applied", "unwrap_applied", "coercion_applied", "defaults_applied"):
        if payload.get(field) is not False:
            raise GateBError(f"SOURCE_WAS_TRANSFORMED:{case_id}:{field}")
    if payload.get("retry_count") != 0:
        raise GateBError(f"SOURCE_RETRIED:{case_id}")
    result = payload.get("result")
    if not isinstance(result, dict) or result != payload.get("tool_input_received"):
        raise GateBError(f"SOURCE_RESULT_DIVERGES_FROM_TOOL_INPUT:{case_id}")
    if payload.get("tool_input_sha256") != SOURCE_TOOL_INPUT_HASHES[case_id]:
        raise GateBError(f"SOURCE_TOOL_INPUT_HASH_MISMATCH:{case_id}")
    handoff = _extract_handoff(result)
    handoff_hash = sha256_bytes(canonical_bytes(handoff))
    if handoff_hash != HANDOFF_HASHES[case_id]:
        raise GateBError(f"HANDOFF_HASH_MISMATCH:{case_id}:{handoff_hash}")
    return {
        "source_file": path.relative_to(PROJECT_ROOT).as_posix(),
        "source_result_sha256": actual_hash,
        "source_tool_input_sha256": SOURCE_TOOL_INPUT_HASHES[case_id],
        "handoff_sha256": handoff_hash,
        "handoff": handoff,
        "effective_positive_prompt": compose_positive(handoff),
        "effective_negative_prompt": compose_negative(handoff),
    }


def build_frozen_handoff() -> dict[str, Any]:
    cases: dict[str, Any] = {}
    for case_id in CASE_ORDER:
        case = load_source_case(case_id)
        case["effective_positive_prompt_sha256"] = sha256_bytes(
            case["effective_positive_prompt"].encode("utf-8")
        )
        case["effective_negative_prompt_sha256"] = sha256_bytes(
            case["effective_negative_prompt"].encode("utf-8")
        )
        cases[case_id] = case
    plan = [
        {"ordinal": ordinal, "case_id": case_id, "seed": seed, "run_label": f"seed_{seed}"}
        for ordinal, (case_id, seed) in enumerate(
            ((case_id, seed) for case_id in CASE_ORDER for seed in SEEDS), start=1
        )
    ]
    return {
        "gate": "Forge Visual Identity Gate B - Semantic Prompt Handoff 4A",
        "contract": "frozen-3c-seven-field-handoff",
        "source_run": SOURCE_RUN.relative_to(PROJECT_ROOT).as_posix(),
        "case_order": list(CASE_ORDER),
        "seeds": list(SEEDS),
        "planned_submission_count": RUN_COUNT,
        "allowed_source_fields": [
            "/identity/canonical_name_en",
            "/identity/required_identity_parts",
            "/identity/material_hints",
            "/identity/silhouette_hints",
            "/identity/optional_decorations",
            "/visual/prompt_en",
            "/visual/negative_prompt_en",
        ],
        "generic_positive_prompt": SYSTEM_POSITIVE,
        "generic_negative_prompt": SYSTEM_NEGATIVE,
        "generic_positive_prompt_sha256": sha256_bytes(SYSTEM_POSITIVE.encode("utf-8")),
        "generic_negative_prompt_sha256": sha256_bytes(SYSTEM_NEGATIVE.encode("utf-8")),
        "workflow_sha256": WORKFLOW_SHA256,
        "postprocess_sha256": POSTPROCESS_SHA256,
        "checkpoint_sha256": CHECKPOINT_SHA256,
        "cases": cases,
        "ordered_plan": plan,
    }


def _verify_spike2_history() -> dict[str, Any]:
    verified: dict[str, str] = {}
    for relative, expected in SPIKE2_REPORT_HASHES.items():
        path = PROJECT_ROOT / relative
        actual = sha256_file(path)
        if actual != expected:
            raise GateBError(f"SPIKE2_HISTORY_CHANGED:{relative}:{actual}")
        verified[relative] = actual
    evidence_path = PROJECT_ROOT / "tools/comfyui/open_identity/reports/evidence_hashes.json"
    evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    image_evidence: dict[str, str] = {}
    for relative, expected in evidence.get("files", {}).items():
        actual = sha256_file(PROJECT_ROOT / relative)
        if actual != expected:
            raise GateBError(f"SPIKE2_IMAGE_EVIDENCE_CHANGED:{relative}:{actual}")
        image_evidence[relative] = actual
    if len(image_evidence) != 15:
        raise GateBError(f"SPIKE2_EVIDENCE_COUNT_INVALID:{len(image_evidence)}")
    return {
        "comparison_kind": "non-paired historical baseline",
        "warning": "The five Spike 2 cases differ from the four Gate B cases; this is not a controlled causal A/B test.",
        "official_policy": "forge-open-identity-v1",
        "official_run": "seed_52002_policy1",
        "baseline": {
            "raw_identity_recognizable": {"passed": 2, "total": 5},
            "recognizable_at_96x96": {"passed": 2, "total": 5},
            "person_or_hands_generated": {"failed": 1, "total": 5},
            "alpha_delivery_success": {"passed": 5, "total": 5},
            "retry_count": 0,
        },
        "report_hashes": verified,
        "image_evidence_hashes": image_evidence,
    }


def freeze() -> None:
    if FROZEN_DIRECTORY.exists():
        raise GateBError(f"FROZEN_DIRECTORY_ALREADY_EXISTS:{FROZEN_DIRECTORY}")
    stage = ROOT / f".frozen-{uuid.uuid4().hex}.tmp"
    stage.mkdir(parents=False, exist_ok=False)
    try:
        handoff = build_frozen_handoff()
        history = _verify_spike2_history()
        (stage / "frozen_handoff.json").write_bytes(
            json.dumps(handoff, ensure_ascii=False, indent=2).encode("utf-8") + b"\n"
        )
        (stage / "protected_history.json").write_bytes(
            json.dumps(history, ensure_ascii=False, indent=2).encode("utf-8") + b"\n"
        )
        os.replace(stage, FROZEN_DIRECTORY)
    finally:
        if stage.exists():
            shutil.rmtree(stage)
    print(
        json.dumps(
            {
                "status": "GATE_B_4A_FREEZE_PASS",
                "frozen_handoff_sha256": sha256_file(FROZEN_HANDOFF_PATH),
                "protected_history_sha256": sha256_file(PROTECTED_HISTORY_PATH),
                "planned_submission_count": RUN_COUNT,
            }
        )
    )


def _resolve_path(config_path: Path, value: str) -> Path:
    expanded = os.path.expandvars(value)
    candidate = Path(expanded)
    return candidate.resolve() if candidate.is_absolute() else (config_path.parent / candidate).resolve()


def load_config(config_path: Path) -> dict[str, Any]:
    path = config_path.resolve()
    data = json.loads(path.read_text(encoding="utf-8"))
    data["api_base"] = validate_api_base(str(data.get("api_base", "")))
    for key in (
        "comfyui_install",
        "python_executable",
        "workflow_file",
        "postprocess_script",
        "input_directory",
        "comfy_output_directory",
        "runtime_temp_directory",
        "output_root",
    ):
        value = str(data.get(key, ""))
        if not value or value.startswith("${"):
            raise GateBError(f"CONFIG_PATH_UNRESOLVED:{key}")
        data[key] = str(_resolve_path(path, value))
    if data["api_base"] != "http://127.0.0.1:8188":
        raise GateBError("GATE_B_4A_REQUIRES_127_0_0_1_8188")
    return data


def _load_and_verify_frozen() -> tuple[dict[str, Any], str]:
    if not FROZEN_HANDOFF_PATH.is_file() or not PROTECTED_HISTORY_PATH.is_file():
        raise GateBError("FROZEN_EVIDENCE_MISSING")
    frozen_hash = sha256_file(FROZEN_HANDOFF_PATH)
    frozen = json.loads(FROZEN_HANDOFF_PATH.read_text(encoding="utf-8"))
    rebuilt = build_frozen_handoff()
    if canonical_bytes(frozen) != canonical_bytes(rebuilt):
        raise GateBError("FROZEN_HANDOFF_DIVERGED_FROM_3C_SOURCE")
    protected = json.loads(PROTECTED_HISTORY_PATH.read_text(encoding="utf-8"))
    if canonical_bytes(protected) != canonical_bytes(_verify_spike2_history()):
        raise GateBError("PROTECTED_SPIKE2_HISTORY_DIVERGED")
    return frozen, frozen_hash


def _verify_approved_manifest(config_path: Path) -> dict[str, Any]:
    if sha256_file(APPROVED_MANIFEST_PATH) != APPROVED_MANIFEST_SHA256:
        raise GateBError("APPROVED_RUN_MANIFEST_HASH_MISMATCH")
    approved = json.loads(APPROVED_MANIFEST_PATH.read_text(encoding="utf-8"))
    hashes = approved.get("hashes", {})
    checks = {
        "frozen_handoff_sha256": sha256_file(FROZEN_HANDOFF_PATH),
        "protected_history_sha256": sha256_file(PROTECTED_HISTORY_PATH),
        "local_config_sha256": sha256_file(config_path.resolve()),
        "workflow_sha256": sha256_file(COMFY_ROOT / "workflows" / "forge_object_sprite_v0.json"),
        "postprocess_sha256": sha256_file(COMFY_ROOT / "postprocess" / "process_sprite.py"),
    }
    for name, actual in checks.items():
        if hashes.get(name) != actual:
            raise GateBError(f"APPROVED_INPUT_HASH_MISMATCH:{name}:{actual}")
    if approved.get("case_order") != list(CASE_ORDER) or approved.get("seeds") != list(SEEDS):
        raise GateBError("APPROVED_CASE_OR_SEED_MATRIX_CHANGED")
    if approved.get("planned_submission_count") != RUN_COUNT:
        raise GateBError("APPROVED_SUBMISSION_COUNT_CHANGED")
    if approved.get("automatic_retry_allowed") is not False or approved.get("third_seed_allowed") is not False:
        raise GateBError("APPROVED_RETRY_OR_THIRD_SEED_BOUNDARY_CHANGED")
    if approved.get("anthropic_api_allowed") is not False:
        raise GateBError("APPROVED_ANTHROPIC_BOUNDARY_CHANGED")
    return approved


def _verify_runtime_configuration(config: dict[str, Any], *, hash_checkpoint: bool) -> dict[str, Any]:
    workflow_path = Path(config["workflow_file"])
    postprocess_path = Path(config["postprocess_script"])
    checkpoint_path = Path(config["comfyui_install"]) / "models" / "checkpoints" / str(config["checkpoint"])
    if sha256_file(workflow_path) != WORKFLOW_SHA256:
        raise GateBError("WORKFLOW_HASH_MISMATCH")
    if sha256_file(postprocess_path) != POSTPROCESS_SHA256:
        raise GateBError("POSTPROCESS_HASH_MISMATCH")
    if not Path(config["python_executable"]).is_file():
        raise GateBError("PYTHON_EXECUTABLE_MISSING")
    if not (Path(config["comfyui_install"]) / "main.py").is_file():
        raise GateBError("COMFYUI_MAIN_MISSING")
    if not checkpoint_path.is_file():
        raise GateBError("CHECKPOINT_MISSING")
    checkpoint_hash = CHECKPOINT_SHA256
    if hash_checkpoint:
        checkpoint_hash = sha256_file(checkpoint_path)
        if checkpoint_hash != CHECKPOINT_SHA256:
            raise GateBError(f"CHECKPOINT_HASH_MISMATCH:{checkpoint_hash}")
    workflow = json.loads(workflow_path.read_text(encoding="utf-8"))
    sampler = workflow.get("6", {}).get("inputs", {})
    expected_sampler = {
        "steps": 26,
        "cfg": 6.5,
        "sampler_name": "dpmpp_2m",
        "scheduler": "karras",
        "denoise": 1.0,
    }
    actual_sampler = {key: sampler.get(key) for key in expected_sampler}
    if actual_sampler != expected_sampler:
        raise GateBError(f"SAMPLER_CONFIGURATION_CHANGED:{actual_sampler}")
    if config.get("checkpoint") != "RealVisXL_V5.0_fp16.safetensors":
        raise GateBError("CHECKPOINT_NAME_CHANGED")
    if int(config.get("generation_width", 0)) != 512 or int(config.get("generation_height", 0)) != 512:
        raise GateBError("GENERATION_SIZE_CHANGED")
    if int(config.get("sprite_size", 0)) != 96:
        raise GateBError("SPRITE_SIZE_CHANGED")
    return {
        "workflow_sha256": WORKFLOW_SHA256,
        "postprocess_sha256": POSTPROCESS_SHA256,
        "checkpoint_sha256": checkpoint_hash,
        "checkpoint_file": checkpoint_path.name,
        "sampler": actual_sampler,
        "generation_dimensions": [512, 512],
        "processed_dimensions": [96, 96],
    }


def preflight(config_path: Path, *, hash_checkpoint: bool = True) -> dict[str, Any]:
    frozen, frozen_hash = _load_and_verify_frozen()
    _verify_approved_manifest(config_path)
    config = load_config(config_path)
    runtime = _verify_runtime_configuration(config, hash_checkpoint=hash_checkpoint)
    if len(frozen.get("ordered_plan", [])) != RUN_COUNT:
        raise GateBError("FROZEN_PLAN_COUNT_CHANGED")
    pairs = [(item["case_id"], item["seed"]) for item in frozen["ordered_plan"]]
    expected_pairs = [(case_id, seed) for case_id in CASE_ORDER for seed in SEEDS]
    if pairs != expected_pairs:
        raise GateBError("FROZEN_PLAN_ORDER_CHANGED")
    if RESERVATION_PATH.exists():
        raise GateBError(f"RUN_ALREADY_RESERVED:{RESERVATION_PATH}")
    if OUTPUT_ROOT.exists() and any(OUTPUT_ROOT.iterdir()):
        raise GateBError(f"OUTPUT_ROOT_NOT_EMPTY:{OUTPUT_ROOT}")
    return {
        "status": "GATE_B_4A_OFFLINE_PREFLIGHT_PASS",
        "network_used": False,
        "comfyui_started": False,
        "anthropic_api_called": False,
        "frozen_handoff_sha256": frozen_hash,
        "protected_history_sha256": sha256_file(PROTECTED_HISTORY_PATH),
        "approved_run_manifest_sha256": APPROVED_MANIFEST_SHA256,
        "planned_submission_count": RUN_COUNT,
        "case_order": list(CASE_ORDER),
        "seeds": list(SEEDS),
        **runtime,
    }


def _reserve_run(frozen_hash: str, config_path: Path) -> tuple[str, dict[str, Any]]:
    run_id = f"gate-b-4a-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')}-{uuid.uuid4().hex[:8]}"
    reservation = {
        "gate": "GATE_B_4A",
        "run_id": run_id,
        "created_at": utc_now(),
        "frozen_handoff_sha256": frozen_hash,
        "config_sha256": sha256_file(config_path.resolve()),
        "runner_sha256": sha256_file(Path(__file__).resolve()),
        "maximum_submissions": RUN_COUNT,
        "automatic_retry_allowed": False,
        "third_seed_allowed": False,
    }
    descriptor = os.open(RESERVATION_PATH, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(json.dumps(reservation, ensure_ascii=False, indent=2).encode("utf-8") + b"\n")
            stream.flush()
            os.fsync(stream.fileno())
    except Exception:
        try:
            os.close(descriptor)
        except OSError:
            pass
        raise
    return run_id, reservation


def _run_one(
    *,
    config: dict[str, Any],
    runtime: dict[str, Any],
    frozen_hash: str,
    run_id: str,
    item: dict[str, Any],
    case: dict[str, Any],
    workflow: dict[str, Any],
) -> dict[str, Any]:
    case_id = str(item["case_id"])
    seed = int(item["seed"])
    ordinal = int(item["ordinal"])
    final_directory = Path(config["output_root"]) / run_id / case_id / f"seed_{seed}"
    if final_directory.exists():
        raise GateBError(f"RESULT_DIRECTORY_ALREADY_EXISTS:{final_directory}")
    stage = Path(config["output_root"]) / ".tmp" / run_id / f"{ordinal:02d}-{uuid.uuid4().hex}"
    stage.mkdir(parents=True, exist_ok=False)
    started = time.perf_counter()
    generation_started: float | None = None
    postprocess_started: float | None = None
    prompt_id = ""
    status = "failed"
    failure_reason = "UNFINISHED"
    raw_dimensions: list[int] = []
    postprocess_result: dict[str, Any] = {
        "postprocess_seconds": 0.0,
        "processed_dimensions": [],
        "alpha_coverage": 0.0,
        "opaque_bounds": [],
    }
    input_relative = Path("GateB4A") / run_id / case_id / f"seed_{seed}.png"
    input_path = Path(config["input_directory"]) / input_relative
    positive = str(case["effective_positive_prompt"])
    negative = str(case["effective_negative_prompt"])
    output_prefix = f"ForgeGateB4A/{run_id}/{case_id}/seed_{seed}/raw"
    graph = inject_workflow(
        workflow,
        checkpoint=str(config["checkpoint"]),
        positive_prompt=positive,
        negative_prompt=negative,
        input_image=input_relative.as_posix(),
        seed=seed,
        denoise=1.0,
        output_prefix=output_prefix,
    )
    request_graph_hash = sha256_bytes(canonical_bytes(graph))
    manifest: dict[str, Any] = {
        "gate": "GATE_B_4A",
        "run_id": run_id,
        "case_id": case_id,
        "attempt_ordinal": ordinal,
        "seed": seed,
        "request_attempted": False,
        "retry_count": 0,
        "automatic_retry": False,
        "prompt_id": "",
        "status": status,
        "failure_reason": failure_reason,
        "source_3c_result_sha256": case["source_result_sha256"],
        "source_3c_tool_input_sha256": case["source_tool_input_sha256"],
        "source_handoff_sha256": case["handoff_sha256"],
        "frozen_handoff_sha256": frozen_hash,
        "semantic_fields_modified": False,
        "english_only_handoff": True,
        "anthropic_api_called": False,
        "effective_positive_prompt": positive,
        "effective_positive_prompt_sha256": case["effective_positive_prompt_sha256"],
        "effective_negative_prompt": negative,
        "effective_negative_prompt_sha256": case["effective_negative_prompt_sha256"],
        "request_workflow_sha256": request_graph_hash,
        "workflow_file": Path(config["workflow_file"]).name,
        "workflow_sha256": runtime["workflow_sha256"],
        "checkpoint": config["checkpoint"],
        "checkpoint_sha256": runtime["checkpoint_sha256"],
        "sampler": runtime["sampler"],
        "generation_dimensions": runtime["generation_dimensions"],
        "raw_dimensions": raw_dimensions,
        "processed_dimensions": [],
        "alpha_delivery_success": False,
        "alpha_coverage": 0.0,
        "opaque_bounds": [],
        "generation_seconds": 0.0,
        "postprocess_seconds": 0.0,
        "selected_comfyui_install": config.get("selected_install_label", "unknown"),
        "api_base": config["api_base"],
        "control_type": "none",
        "control_strength": 0.0,
    }
    log_lines = [
        f"gate=GATE_B_4A",
        f"run_id={run_id}",
        f"case_id={case_id}",
        f"attempt_ordinal={ordinal}",
        f"seed={seed}",
        "retry_count=0",
        "semantic_fields_modified=false",
        "anthropic_api_called=false",
    ]
    try:
        _prepare_input(
            None,
            input_path,
            (int(config["generation_width"]), int(config["generation_height"])),
            tuple(int(value) for value in config["background_rgb"]),
        )
        shutil.copy2(input_path, stage / "input_sketch.png")
        (stage / "request_workflow.json").write_bytes(
            json.dumps(graph, ensure_ascii=False, indent=2).encode("utf-8") + b"\n"
        )
        manifest["request_attempted"] = True
        generation_started = time.perf_counter()
        prompt_id, entry = _submit_and_wait(config, graph, float(config.get("timeout_seconds", 120)))
        manifest["prompt_id"] = prompt_id
        manifest["generation_seconds"] = round(time.perf_counter() - generation_started, 3)
        raw_source = _output_path(config, entry)
        raw_target = stage / "raw.png"
        shutil.copy2(raw_source, raw_target)
        with Image.open(raw_target) as opened:
            opened.load()
            raw_dimensions = [opened.width, opened.height]
        manifest["raw_dimensions"] = raw_dimensions
        postprocess_started = time.perf_counter()
        postprocess_result = process_sprite(
            raw_target,
            stage / "processed_sprite.png",
            stage / "alpha_mask.png",
            expected_background=tuple(int(value) for value in config["background_rgb"]),
            sprite_size=int(config["sprite_size"]),
            max_colors=int(config["max_colors"]),
            outline=bool(config["outline"]),
        )
        manifest.update(postprocess_result)
        manifest["alpha_delivery_success"] = True
        status = "success"
        failure_reason = ""
    except (BridgeError, SpritePostprocessError, OSError, ValueError, json.JSONDecodeError) as exc:
        if generation_started is not None and not manifest["generation_seconds"]:
            manifest["generation_seconds"] = round(time.perf_counter() - generation_started, 3)
        if postprocess_started is not None and not manifest["postprocess_seconds"]:
            manifest["postprocess_seconds"] = round(time.perf_counter() - postprocess_started, 3)
        status = "failed"
        failure_reason = str(exc)
    finally:
        manifest["status"] = status
        manifest["failure_reason"] = failure_reason
        manifest["prompt_id"] = prompt_id
        manifest["total_seconds"] = round(time.perf_counter() - started, 3)
        log_lines.extend(
            (
                f"request_attempted={str(manifest['request_attempted']).lower()}",
                f"prompt_id={prompt_id}",
                f"status={status}",
                f"failure_reason={failure_reason}",
                f"generation_seconds={manifest['generation_seconds']}",
                f"postprocess_seconds={manifest['postprocess_seconds']}",
            )
        )
        (stage / "manifest.json").write_bytes(
            json.dumps(manifest, ensure_ascii=False, indent=2).encode("utf-8") + b"\n"
        )
        (stage / "generation.log").write_text("\n".join(log_lines) + "\n", encoding="utf-8")
        final_directory.parent.mkdir(parents=True, exist_ok=True)
        os.replace(stage, final_directory)
    return {
        "ordinal": ordinal,
        "case_id": case_id,
        "seed": seed,
        "status": status,
        "failure_reason": failure_reason,
        "request_attempted": manifest["request_attempted"],
        "prompt_id": prompt_id,
        "output_directory": final_directory.relative_to(PROJECT_ROOT).as_posix(),
        "generation_seconds": manifest["generation_seconds"],
        "postprocess_seconds": manifest["postprocess_seconds"],
        "alpha_delivery_success": manifest["alpha_delivery_success"],
    }


def run(config_path: Path) -> int:
    frozen, frozen_hash = _load_and_verify_frozen()
    _verify_approved_manifest(config_path)
    config = load_config(config_path)
    runtime = _verify_runtime_configuration(config, hash_checkpoint=True)
    health = health_check(config)
    if not health.get("ok") or not health.get("listen_is_loopback"):
        raise GateBError("COMFYUI_HEALTH_OR_LOOPBACK_CHECK_FAILED")
    config["output_root"] = str(OUTPUT_ROOT.resolve())
    run_id, reservation = _reserve_run(frozen_hash, config_path)
    workflow = json.loads(Path(config["workflow_file"]).read_text(encoding="utf-8"))
    results: list[dict[str, Any]] = []
    submit_count = 0
    started = time.perf_counter()
    for item in frozen["ordered_plan"]:
        case_id = item["case_id"]
        print(
            f"GATE_B_4A_ATTEMPT ordinal={item['ordinal']}/8 case={case_id} seed={item['seed']} retry=0",
            flush=True,
        )
        result = _run_one(
            config=config,
            runtime=runtime,
            frozen_hash=frozen_hash,
            run_id=run_id,
            item=item,
            case=frozen["cases"][case_id],
            workflow=workflow,
        )
        submit_count += int(bool(result["request_attempted"]))
        results.append(result)
        print(
            f"GATE_B_4A_RESULT ordinal={item['ordinal']}/8 case={case_id} status={result['status']} "
            f"prompt_id={result['prompt_id'] or '-'}",
            flush=True,
        )
    summary = {
        "gate": "GATE_B_4A",
        "run_id": run_id,
        "status": "GENERATION_COMPLETE" if len(results) == RUN_COUNT else "GENERATION_INCOMPLETE",
        "started_from_reservation": reservation,
        "completed_at": utc_now(),
        "planned_submission_count": RUN_COUNT,
        "request_attempt_count": submit_count,
        "result_directory_count": len(results),
        "automatic_retry_count": 0,
        "third_seed_used": False,
        "anthropic_api_called": False,
        "semantic_contract_modified": False,
        "workflow_sha256": runtime["workflow_sha256"],
        "checkpoint": runtime["checkpoint_file"],
        "checkpoint_sha256": runtime["checkpoint_sha256"],
        "sampler": runtime["sampler"],
        "frozen_handoff_sha256": frozen_hash,
        "protected_history_sha256": sha256_file(PROTECTED_HISTORY_PATH),
        "approved_run_manifest_sha256": APPROVED_MANIFEST_SHA256,
        "elapsed_seconds": round(time.perf_counter() - started, 3),
        "technical_alpha_success_count": sum(int(item["alpha_delivery_success"]) for item in results),
        "results": results,
        "human_visual_review_status": "PENDING",
    }
    run_root = OUTPUT_ROOT / run_id
    atomic_json(run_root / "generation_summary.json", summary)
    atomic_json(run_root / "RUN_COMPLETE.json", {"run_id": run_id, "result_directory_count": len(results)})
    print(json.dumps(summary, ensure_ascii=False), flush=True)
    return 0 if len(results) == RUN_COUNT and submit_count == RUN_COUNT else 2


def main() -> int:
    parser = argparse.ArgumentParser(description="Frozen 3C -> RealVisXL Gate B 4A runner; exactly eight submissions.")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("freeze")
    preflight_parser = subparsers.add_parser("preflight")
    preflight_parser.add_argument("--config", required=True, type=Path)
    preflight_parser.add_argument("--skip-checkpoint-hash", action="store_true", help=argparse.SUPPRESS)
    run_parser = subparsers.add_parser("run")
    run_parser.add_argument("--config", required=True, type=Path)
    args = parser.parse_args()
    try:
        if args.command == "freeze":
            freeze()
            return 0
        if args.command == "preflight":
            print(
                json.dumps(
                    preflight(args.config, hash_checkpoint=not args.skip_checkpoint_hash),
                    ensure_ascii=False,
                )
            )
            return 0
        return run(args.config)
    except (GateBError, BridgeError, OSError, ValueError, json.JSONDecodeError) as exc:
        print(json.dumps({"status": "NEEDS_WORK", "failure_reason": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
