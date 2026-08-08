"""Offline-only candidate contract for orthogonal melee affordances.

This module does not alter the frozen forge-semantic-v1.1 tool contract.  It is
the fail-closed boundary that a future approved v1.2 real-model retest must pass
before an affordance sidecar can enter Combat Feel.
"""

from __future__ import annotations

import json
import math
import os
from pathlib import Path
import tempfile
from typing import Any, Mapping
import copy

from semantic_contract import validate_semantic_blueprint


CONTRACT_VERSION = "forge-semantic-v1.2-candidate"
SIDECAR_NAME = "object_affordance_profile.json"
FIELDS = frozenset({
    "handle_length", "body_length", "grip_topology", "rigidity",
    "mass_distribution", "contact_surface", "secondary_contact_surface",
    "has_point", "has_edge", "has_broad_face", "has_barrel", "has_stock",
    "confidence", "evidence_parts",
})
BLUEPRINT_FIELDS = frozenset({"identity", "combat", "visual", "confidence", "affordance"})
ENUMS = {
    "handle_length": frozenset({"none", "short", "medium", "long"}),
    "body_length": frozenset({"short", "medium", "long"}),
    "grip_topology": frozenset({"one_hand_handle", "two_hand_handle", "body_grip", "clamp_grip"}),
    "rigidity": frozenset({"rigid", "semi_rigid", "flexible"}),
    "mass_distribution": frozenset({"rear", "balanced", "front"}),
    "contact_surface": frozenset({"point", "edge", "broad", "whole_body"}),
    "secondary_contact_surface": frozenset({"none", "point", "edge", "broad", "whole_body"}),
}
BOOLEAN_FIELDS = ("has_point", "has_edge", "has_broad_face", "has_barrel", "has_stock")
SCHEMA_ROOT = Path(__file__).resolve().parents[1] / "schema"


class AffordanceContractError(ValueError):
    pass


def candidate_tool_schema() -> dict[str, Any]:
    """Return one self-contained provider schema without mutating frozen v1.1."""
    base = json.loads((SCHEMA_ROOT / "forge_semantic_blueprint.schema.json").read_text(encoding="utf-8"))
    affordance = json.loads((SCHEMA_ROOT / "object_affordance_profile.v1_2_candidate.schema.json").read_text(encoding="utf-8"))
    for metadata in ("$schema", "$id", "title"):
        affordance.pop(metadata, None)
    candidate = copy.deepcopy(base)
    candidate["properties"]["affordance"] = affordance
    candidate["required"] = [*candidate["required"], "affordance"]
    return candidate


def validate_affordance_profile(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise AffordanceContractError("/: expected object")
    actual = frozenset(payload)
    if actual != FIELDS:
        missing = sorted(FIELDS - actual)
        extra = sorted(actual - FIELDS)
        raise AffordanceContractError(f"/: fields mismatch missing={missing} extra={extra}")
    for field, allowed in ENUMS.items():
        value = payload[field]
        if type(value) is not str or value not in allowed:
            raise AffordanceContractError(f"/{field}: value {value!r} not in {sorted(allowed)}")
    for field in BOOLEAN_FIELDS:
        if type(payload[field]) is not bool:
            raise AffordanceContractError(f"/{field}: expected boolean")
    confidence = payload["confidence"]
    if type(confidence) not in (int, float) or isinstance(confidence, bool) or not math.isfinite(confidence):
        raise AffordanceContractError("/confidence: expected finite number")
    if not 0.65 <= float(confidence) <= 1.0:
        raise AffordanceContractError("/confidence: expected 0.65..1.0")
    evidence = payload["evidence_parts"]
    if not isinstance(evidence, list) or not 1 <= len(evidence) <= 5:
        raise AffordanceContractError("/evidence_parts: expected 1..5 strings")
    if any(type(value) is not str or not value.strip() or len(value) > 100 for value in evidence):
        raise AffordanceContractError("/evidence_parts: invalid evidence string")
    if payload["handle_length"] == "none" and payload["grip_topology"] not in {"body_grip", "clamp_grip"}:
        raise AffordanceContractError("/grip_topology: handleless object requires body_grip or clamp_grip")
    if payload["handle_length"] != "none" and payload["grip_topology"] == "body_grip":
        raise AffordanceContractError("/grip_topology: body_grip requires handle_length none")
    required_flag = {"point": "has_point", "edge": "has_edge", "broad": "has_broad_face"}.get(payload["contact_surface"])
    if required_flag and not payload[required_flag]:
        raise AffordanceContractError(f"/{required_flag}: must support primary contact_surface")
    if payload["has_stock"] and payload["secondary_contact_surface"] == "none":
        raise AffordanceContractError("/secondary_contact_surface: stock requires a rear contact surface")
    return payload


def validate_candidate_blueprint(semantic_blueprint: Any) -> dict[str, Any]:
	if not isinstance(semantic_blueprint, Mapping):
		raise AffordanceContractError("/: semantic blueprint must be an object")
	actual = frozenset(semantic_blueprint)
	if actual != BLUEPRINT_FIELDS:
		raise AffordanceContractError(
			f"/: blueprint fields mismatch missing={sorted(BLUEPRINT_FIELDS - actual)} "
			f"extra={sorted(actual - BLUEPRINT_FIELDS)}"
		)
	base = {key: semantic_blueprint[key] for key in ("identity", "combat", "visual", "confidence")}
	validate_semantic_blueprint(base)
	validate_affordance_profile(semantic_blueprint["affordance"])
	return semantic_blueprint  # type: ignore[return-value]


def extract_candidate_affordance(semantic_blueprint: Any) -> dict[str, Any]:
	validated = validate_candidate_blueprint(semantic_blueprint)
	return validated["affordance"]


def publish_sidecar_atomic(semantic_blueprint_path: Path, round_directory: Path) -> Path:
    blueprint = json.loads(semantic_blueprint_path.read_text(encoding="utf-8"))
    affordance = extract_candidate_affordance(blueprint)
    target = round_directory / SIDECAR_NAME
    if target.exists():
        raise AffordanceContractError(f"refusing to overwrite {target}")
    round_directory.mkdir(parents=True, exist_ok=True)
    handle, temporary_name = tempfile.mkstemp(prefix=f".{SIDECAR_NAME}.", suffix=".tmp", dir=round_directory)
    try:
        with os.fdopen(handle, "w", encoding="utf-8", newline="\n") as stream:
            json.dump(affordance, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_name, target)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise
    return target


__all__ = [
	"AffordanceContractError", "CONTRACT_VERSION", "candidate_tool_schema", "extract_candidate_affordance",
	"publish_sidecar_atomic", "validate_affordance_profile", "validate_candidate_blueprint",
]
