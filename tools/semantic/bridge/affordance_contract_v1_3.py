"""Offline candidate contract adding real-world object length to the affordance profile.

The frozen v1.1, v1.2 and v1.2.1 validators are untouched: this is a new candidate
alongside them, so existing profiles and their evidence stay valid under the version
they were authored against.

Why a number and not another bucket: `body_length` is an ordinal with three values,
and it already collides. `old_mop` and `giant_wooden_spoon` are both "long" while
measuring 150cm and 60cm -- a 2.5x difference the contract could not express. Adding a
fourth bucket set would repeat the failure T51 and T76 retired. Reach is continuous, so
the field that drives it is continuous.

Why the model has to supply it at all: a generated image cannot. Generators fill the
canvas whatever the subject, so length in pixels describes the framing, not the object.
This is exactly the split T73/T74 asked for -- measure what geometry can see, ask the
model only for what it cannot.
"""

from __future__ import annotations

import copy
import json
import math
from pathlib import Path
from typing import Any, Mapping

from affordance_contract_v1_2 import (
    AffordanceContractError,
    BLUEPRINT_FIELDS,
    FIELDS as FIELDS_V1_2,
    validate_affordance_profile,
)
from semantic_contract import validate_semantic_blueprint


CONTRACT_VERSION = "forge-semantic-v1.3-candidate"
SIDECAR_NAME = "object_affordance_profile.json"
REAL_LENGTH_FIELD = "real_length_cm"
FIELDS = FIELDS_V1_2 | {REAL_LENGTH_FIELD}

# Bounds describe the world, not the sprite frame. A pipeline that cannot represent a
# legal length must fail there and say so, rather than have the contract quietly
# pretend long objects do not exist. See docs/DECISIONS.md P05.
MIN_REAL_LENGTH_CM = 5.0
MAX_REAL_LENGTH_CM = 400.0

SCHEMA_ROOT = Path(__file__).resolve().parents[1] / "schema"


def candidate_tool_schema_v1_3() -> dict[str, Any]:
    """Return one self-contained provider schema without mutating frozen versions."""
    base = json.loads((SCHEMA_ROOT / "forge_semantic_blueprint.schema.json").read_text(encoding="utf-8"))
    affordance = json.loads(
        (SCHEMA_ROOT / "object_affordance_profile.v1_3_candidate.schema.json").read_text(encoding="utf-8")
    )
    for metadata in ("$schema", "$id", "title"):
        affordance.pop(metadata, None)
    candidate = copy.deepcopy(base)
    candidate["properties"]["affordance"] = affordance
    candidate["required"] = [*candidate["required"], "affordance"]
    return candidate


def validate_real_length_cm(value: Any) -> float:
    if type(value) not in (int, float) or isinstance(value, bool) or not math.isfinite(value):
        raise AffordanceContractError(f"/{REAL_LENGTH_FIELD}: expected finite number")
    if not MIN_REAL_LENGTH_CM <= float(value) <= MAX_REAL_LENGTH_CM:
        raise AffordanceContractError(
            f"/{REAL_LENGTH_FIELD}: expected {MIN_REAL_LENGTH_CM}..{MAX_REAL_LENGTH_CM}"
        )
    return float(value)


def validate_affordance_profile_v1_3(payload: Any) -> dict[str, Any]:
    """Validate a v1.3 profile without mutation, coercion, or defaulting."""
    if not isinstance(payload, dict):
        raise AffordanceContractError("/: expected object")
    actual = frozenset(payload)
    if actual != FIELDS:
        raise AffordanceContractError(
            f"/: fields mismatch missing={sorted(FIELDS - actual)} extra={sorted(actual - FIELDS)}"
        )
    validate_real_length_cm(payload[REAL_LENGTH_FIELD])
    # Reuse v1.2 for everything else so the shared cross-field rules stay in one place.
    validate_affordance_profile({key: value for key, value in payload.items() if key != REAL_LENGTH_FIELD})
    return payload


def validate_candidate_blueprint_v1_3(semantic_blueprint: Any) -> dict[str, Any]:
    if not isinstance(semantic_blueprint, Mapping):
        raise AffordanceContractError("/: semantic blueprint must be an object")
    actual = frozenset(semantic_blueprint)
    if actual != BLUEPRINT_FIELDS:
        raise AffordanceContractError(
            f"/: blueprint fields mismatch missing={sorted(BLUEPRINT_FIELDS - actual)} "
            f"extra={sorted(actual - BLUEPRINT_FIELDS)}"
        )
    validate_semantic_blueprint({key: semantic_blueprint[key] for key in ("identity", "combat", "visual", "confidence")})
    validate_affordance_profile_v1_3(semantic_blueprint["affordance"])
    return semantic_blueprint  # type: ignore[return-value]


def upgrade_profile_to_v1_3(profile: Mapping[str, Any], real_length_cm: float) -> dict[str, Any]:
    """Return a v1.3 profile from a valid v1.2 one plus a measured length.

    Used to carry the four already-frozen objects forward without editing them in
    place: their sidecars under data/ are SHA-256 pinned and stay as they are.
    """
    validate_affordance_profile(dict(profile))
    upgraded = {**dict(profile), REAL_LENGTH_FIELD: float(real_length_cm)}
    return validate_affordance_profile_v1_3(upgraded)


def read_real_length_cm(profile_path: Path) -> float:
    """Read and validate the length from a profile file on disk."""
    payload = json.loads(Path(profile_path).read_text(encoding="utf-8"))
    if not isinstance(payload, dict) or REAL_LENGTH_FIELD not in payload:
        raise AffordanceContractError(f"/{REAL_LENGTH_FIELD}: absent from {profile_path}")
    return validate_real_length_cm(payload[REAL_LENGTH_FIELD])


__all__ = [
    "CONTRACT_VERSION",
    "FIELDS",
    "MAX_REAL_LENGTH_CM",
    "MIN_REAL_LENGTH_CM",
    "REAL_LENGTH_FIELD",
    "candidate_tool_schema_v1_3",
    "read_real_length_cm",
    "upgrade_profile_to_v1_3",
    "validate_affordance_profile_v1_3",
    "validate_candidate_blueprint_v1_3",
    "validate_real_length_cm",
]
