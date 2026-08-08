"""Offline candidate correction for lexicalized identities and affordances.

The frozen v1.1 and v1.2 validators remain unchanged.  This candidate filters
only a canonical-name pollution issue when the entire English canonical name is
a recognized conventional compound.  It never repairs or rewrites tool input.
"""

from __future__ import annotations

import copy
import re
import unicodedata
from typing import Any, Mapping

from affordance_contract_v1_2 import (
    AffordanceContractError,
    BLUEPRINT_FIELDS,
    candidate_tool_schema,
    validate_affordance_profile,
)
from semantic_contract import ContractValidationError, validate_semantic_blueprint


CONTRACT_VERSION = "forge-semantic-v1.2.1-candidate"

# Evaluator vocabulary only.  These conventional compounds do not select a
# recipe, primitive, gameplay class, or runtime path.
LEXICALIZED_CANONICAL_IDENTITIES_EN = frozenset(
    {
        "electric chair",
        "electric guitar",
        "fire alarm",
        "fire axe",
        "fire bell",
        "fire blanket",
        "fire extinguisher",
        "fire hose",
        "fire hydrant",
        "ice axe",
        "ice pick",
        "lightning rod",
        "steam iron",
    }
)


def _normalized_name(value: str) -> str:
    return " ".join(re.findall(r"[a-z0-9]+", unicodedata.normalize("NFKC", value).casefold()))


def _is_lexicalized_identity_issue(issue: Any, base: Mapping[str, Any]) -> bool:
    if getattr(issue, "path", "") != "$.identity.canonical_name_en":
        return False
    if not str(getattr(issue, "message", "")).startswith(
        "canonical identity contains combat/effect modifiers:"
    ):
        return False
    identity = base.get("identity")
    if not isinstance(identity, Mapping):
        return False
    value = identity.get("canonical_name_en")
    return isinstance(value, str) and _normalized_name(value) in LEXICALIZED_CANONICAL_IDENTITIES_EN


def validate_candidate_blueprint_v1_2_1(payload: Any) -> dict[str, Any]:
    """Validate without mutation, coercion, defaulting, or wrapper removal."""

    if not isinstance(payload, Mapping):
        raise AffordanceContractError("/: semantic blueprint must be an object")
    actual = frozenset(payload)
    if actual != BLUEPRINT_FIELDS:
        raise AffordanceContractError(
            f"/: blueprint fields mismatch missing={sorted(BLUEPRINT_FIELDS - actual)} "
            f"extra={sorted(actual - BLUEPRINT_FIELDS)}"
        )
    validate_affordance_profile(payload["affordance"])
    base = {key: payload[key] for key in ("identity", "combat", "visual", "confidence")}
    try:
        validate_semantic_blueprint(base)
    except ContractValidationError as exc:
        remaining = tuple(
            issue for issue in exc.issues if not _is_lexicalized_identity_issue(issue, base)
        )
        if remaining:
            raise ContractValidationError(remaining, stage=exc.stage) from None
    return payload  # type: ignore[return-value]


def candidate_tool_schema_v1_2_1() -> dict[str, Any]:
    return copy.deepcopy(candidate_tool_schema())


__all__ = [
    "CONTRACT_VERSION",
    "LEXICALIZED_CANONICAL_IDENTITIES_EN",
    "candidate_tool_schema_v1_2_1",
    "validate_candidate_blueprint_v1_2_1",
]
