"""Offline candidate contract adding real-world object mass to the affordance profile.

The frozen v1.1, v1.2, v1.2.1 and v1.3 validators are untouched: this is a new candidate
alongside them, so existing profiles and their evidence stay valid under the version they
were authored against. Same shape as v1.3 (decision P05), one axis further along.

Why a number and not another bucket: `mass_distribution` is an ordinal with three values,
and it does not measure mass at all -- it says where the mass sits, not how much there is.
The two are independent, and the compiler currently has no access to the second: all four
shipped objects classify `heavy`, and a chicken leg would classify heavier than a
sledgehammer because it is front-weighted. That is the same failure `real_length_cm` was
added to fix, in the mass dimension.

Why the model has to supply it at all: a generated image cannot. T60 retired measuring
mass off the drawing because ink area saturates -- 280x30 and 280x60 both measure 1.000.
That is an indictment of inferring mass from pixels, not of mass. Real kilograms are
precisely what geometry cannot see, which is the case T73/T74 reserve for asking the
model -- the same argument that justified `real_length_cm` in P05.

What consumers may do with it is constrained by decision P08: a real quantity may decide
*which* weapon something is, never *whether it is worth using*. Mass spans a thousandfold
here while the damage band spans 1.55x by deliberate design, so anything that multiplies
damage by this field is a bug, not a tuning choice.
"""

from __future__ import annotations

import copy
import json
import math
from pathlib import Path
from typing import Any, Mapping

from affordance_contract_v1_2 import AffordanceContractError, BLUEPRINT_FIELDS
from affordance_contract_v1_3 import (
    FIELDS as FIELDS_V1_3,
    validate_affordance_profile_v1_3,
)
from semantic_contract import validate_semantic_blueprint


CONTRACT_VERSION = "forge-semantic-v1.4-candidate"
SIDECAR_NAME = "object_affordance_profile.json"
REAL_MASS_FIELD = "real_mass_kg"
FIELDS = FIELDS_V1_3 | {REAL_MASS_FIELD}

# Bounds describe the world, not the tuning band the compiler happens to use today. Below
# 50g an object cannot deliver a melee blow at all; above 50kg it is not something a
# human-scale character carries in one hand or two. A legal mass the compiler finds
# extreme is the compiler's problem to compress (P08 layer 3), not the contract's to
# forbid -- the same reasoning that gave real_length_cm a 5..400cm range in P05.
MIN_REAL_MASS_KG = 0.05
MAX_REAL_MASS_KG = 50.0

SCHEMA_ROOT = Path(__file__).resolve().parents[1] / "schema"


def candidate_tool_schema_v1_4() -> dict[str, Any]:
    """Return one self-contained provider schema without mutating frozen versions."""
    base = json.loads((SCHEMA_ROOT / "forge_semantic_blueprint.schema.json").read_text(encoding="utf-8"))
    affordance = json.loads(
        (SCHEMA_ROOT / "object_affordance_profile.v1_4_candidate.schema.json").read_text(encoding="utf-8")
    )
    for metadata in ("$schema", "$id", "title"):
        affordance.pop(metadata, None)
    candidate = copy.deepcopy(base)
    candidate["properties"]["affordance"] = affordance
    candidate["required"] = [*candidate["required"], "affordance"]
    return candidate


def validate_real_mass_kg(value: Any) -> float:
    if type(value) not in (int, float) or isinstance(value, bool) or not math.isfinite(value):
        raise AffordanceContractError(f"/{REAL_MASS_FIELD}: expected finite number")
    if not MIN_REAL_MASS_KG <= float(value) <= MAX_REAL_MASS_KG:
        raise AffordanceContractError(
            f"/{REAL_MASS_FIELD}: expected {MIN_REAL_MASS_KG}..{MAX_REAL_MASS_KG}"
        )
    return float(value)


def validate_affordance_profile_v1_4(payload: Any) -> dict[str, Any]:
    """Validate a v1.4 profile without mutation, coercion, or defaulting."""
    if not isinstance(payload, dict):
        raise AffordanceContractError("/: expected object")
    actual = frozenset(payload)
    if actual != FIELDS:
        raise AffordanceContractError(
            f"/: fields mismatch missing={sorted(FIELDS - actual)} extra={sorted(actual - FIELDS)}"
        )
    validate_real_mass_kg(payload[REAL_MASS_FIELD])
    # Reuse v1.3 for everything else so the shared cross-field rules stay in one place.
    validate_affordance_profile_v1_3({key: value for key, value in payload.items() if key != REAL_MASS_FIELD})
    return payload


def validate_candidate_blueprint_v1_4(semantic_blueprint: Any) -> dict[str, Any]:
    if not isinstance(semantic_blueprint, Mapping):
        raise AffordanceContractError("/: semantic blueprint must be an object")
    actual = frozenset(semantic_blueprint)
    if actual != BLUEPRINT_FIELDS:
        raise AffordanceContractError(
            f"/: blueprint fields mismatch missing={sorted(BLUEPRINT_FIELDS - actual)} "
            f"extra={sorted(actual - BLUEPRINT_FIELDS)}"
        )
    validate_semantic_blueprint({key: semantic_blueprint[key] for key in ("identity", "combat", "visual", "confidence")})
    validate_affordance_profile_v1_4(semantic_blueprint["affordance"])
    return semantic_blueprint  # type: ignore[return-value]


def upgrade_profile_to_v1_4(profile: Mapping[str, Any], real_mass_kg: float) -> dict[str, Any]:
    """Return a v1.4 profile from a valid v1.3 one plus an estimated mass.

    Used to carry already-frozen objects forward without editing them in place: their
    sidecars under data/ are SHA-256 pinned and stay as they are.
    """
    validate_affordance_profile_v1_3(dict(profile))
    upgraded = {**dict(profile), REAL_MASS_FIELD: float(real_mass_kg)}
    return validate_affordance_profile_v1_4(upgraded)


def read_real_mass_kg(profile_path: Path) -> float:
    """Read and validate the mass from a profile file on disk."""
    payload = json.loads(Path(profile_path).read_text(encoding="utf-8"))
    if not isinstance(payload, dict) or REAL_MASS_FIELD not in payload:
        raise AffordanceContractError(f"/{REAL_MASS_FIELD}: absent from {profile_path}")
    return validate_real_mass_kg(payload[REAL_MASS_FIELD])


__all__ = [
    "CONTRACT_VERSION",
    "FIELDS",
    "MAX_REAL_MASS_KG",
    "MIN_REAL_MASS_KG",
    "REAL_MASS_FIELD",
    "candidate_tool_schema_v1_4",
    "read_real_mass_kg",
    "upgrade_profile_to_v1_4",
    "validate_affordance_profile_v1_4",
    "validate_candidate_blueprint_v1_4",
    "validate_real_mass_kg",
]
