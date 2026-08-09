"""Strict-provider candidate for stable orthogonal grip semantics.

The frozen v1.1, v1.2, and v1.2.1 contracts remain unchanged.  This additive
candidate exposes the same semantic fields and local validation rules while
making the legal ``handle_length``/``grip_topology`` pairs part of the schema
used by Anthropic strict tool use.
"""

from __future__ import annotations

import copy
from typing import Any, Mapping

from affordance_contract_v1_2 import AffordanceContractError
from affordance_contract_v1_2_1 import (
    candidate_tool_schema_v1_2_1,
    validate_candidate_blueprint_v1_2_1,
)


CONTRACT_VERSION = "forge-semantic-v1.2.2-candidate"

_UNSUPPORTED_STRICT_CONSTRAINTS = frozenset(
    {"minimum", "maximum", "minLength", "maxLength", "minItems", "maxItems"}
)


def _provider_compatible_schema(value: Any) -> Any:
    """Remove raw-API unsupported constraints without weakening local checks."""

    if isinstance(value, list):
        return [_provider_compatible_schema(item) for item in value]
    if not isinstance(value, Mapping):
        return copy.deepcopy(value)
    result: dict[str, Any] = {}
    constraints: list[str] = []
    for key, item in value.items():
        if key in _UNSUPPORTED_STRICT_CONSTRAINTS:
            constraints.append(f"{key}={item}")
            continue
        result[str(key)] = _provider_compatible_schema(item)
    if constraints:
        existing = str(result.get("description", "")).strip()
        suffix = "Local validation additionally requires " + ", ".join(constraints) + "."
        result["description"] = f"{existing} {suffix}".strip()
    return result


def candidate_tool_schema_v1_2_2() -> dict[str, Any]:
    """Return a raw-API strict-compatible schema with legal grip pairs only."""

    candidate = _provider_compatible_schema(candidate_tool_schema_v1_2_1())
    base_affordance = candidate["properties"]["affordance"]
    handleless = copy.deepcopy(base_affordance)
    handled = copy.deepcopy(base_affordance)
    handleless["properties"]["handle_length"] = {"type": "string", "enum": ["none"]}
    handleless["properties"]["grip_topology"] = {
        "type": "string",
        "enum": ["body_grip", "clamp_grip"],
    }
    handled["properties"]["handle_length"] = {
        "type": "string",
        "enum": ["short", "medium", "long"],
    }
    handled["properties"]["grip_topology"] = {
        "type": "string",
        "enum": ["one_hand_handle", "two_hand_handle", "clamp_grip"],
    }
    candidate["properties"]["affordance"] = {"anyOf": [handleless, handled]}
    return candidate


def validate_candidate_blueprint_v1_2_2(payload: Any) -> dict[str, Any]:
    """Preserve the v1.2.1 fail-closed validator without repair or coercion."""

    return validate_candidate_blueprint_v1_2_1(payload)


def strict_schema_accepts_grip_pair(handle_length: Any, grip_topology: Any) -> bool:
    """Mirror the two disjoint provider-schema branches for offline assertions."""

    if handle_length == "none":
        return grip_topology in {"body_grip", "clamp_grip"}
    if handle_length in {"short", "medium", "long"}:
        return grip_topology in {"one_hand_handle", "two_hand_handle", "clamp_grip"}
    return False


__all__ = [
    "AffordanceContractError",
    "CONTRACT_VERSION",
    "candidate_tool_schema_v1_2_2",
    "strict_schema_accepts_grip_pair",
    "validate_candidate_blueprint_v1_2_2",
]
