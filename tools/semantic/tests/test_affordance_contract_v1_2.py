from __future__ import annotations

import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

BRIDGE_DIR = Path(__file__).resolve().parents[1] / "bridge"
sys.path.insert(0, str(BRIDGE_DIR))

from affordance_contract_v1_2 import (
    AffordanceContractError,
    CONTRACT_VERSION,
    candidate_tool_schema,
    publish_sidecar_atomic,
    validate_affordance_profile,
)


def valid_profile() -> dict:
    return {
        "handle_length": "none",
        "body_length": "medium",
        "grip_topology": "body_grip",
        "rigidity": "rigid",
        "mass_distribution": "balanced",
        "contact_surface": "whole_body",
        "secondary_contact_surface": "none",
        "has_point": False,
        "has_edge": False,
        "has_broad_face": False,
        "has_barrel": False,
        "has_stock": False,
        "confidence": 0.8,
        "evidence_parts": ["seat body", "four legs"],
    }


def valid_blueprint() -> dict:
    return {
        "identity": {
            "canonical_name_zh": "木椅",
            "canonical_name_en": "wooden chair",
            "display_name_zh": "重击木椅",
            "display_name_en": "Heavy Striking Wooden Chair",
            "category": "furniture",
            "required_identity_parts": ["seat", "four legs"],
            "material_hints": ["wood"],
            "silhouette_hints": ["upright back above a square seat"],
            "optional_decorations": [],
        },
        "combat": {
            "behavior_family": "heavy_melee",
            "delivery": "whole_object_strike",
            "impact_mode": "whole_body_collision",
            "effect_type": "normal",
            "drawback": "long_recovery",
            "cadence_hint": "slow_heavy",
        },
        "visual": {
            "prompt_en": "one isolated wooden chair game prop with a square seat and four visible legs",
            "negative_prompt_en": "person, hand, text, weapon replacement",
            "must_preserve": ["seat", "four legs"],
            "must_not_replace_with": ["gun", "sword"],
        },
        "confidence": 0.8,
        "affordance": valid_profile(),
    }


class AffordanceContractV12Tests(unittest.TestCase):
    def test_candidate_tool_schema_is_closed_self_contained_and_does_not_change_v11(self) -> None:
        schema = candidate_tool_schema()
        self.assertFalse(schema["additionalProperties"])
        self.assertEqual(schema["required"].count("affordance"), 1)
        self.assertNotIn("$ref", json.dumps(schema))
        base_path = Path(__file__).resolve().parents[1] / "schema" / "forge_semantic_blueprint.schema.json"
        self.assertNotIn("affordance", json.loads(base_path.read_text(encoding="utf-8"))["properties"])

    def test_handleless_body_grip_is_valid(self) -> None:
        value = valid_profile()
        self.assertIs(validate_affordance_profile(value), value)

    def test_handleless_handle_grip_is_rejected(self) -> None:
        value = valid_profile()
        value["grip_topology"] = "one_hand_handle"
        with self.assertRaisesRegex(AffordanceContractError, "handleless"):
            validate_affordance_profile(value)

    def test_unknown_fields_and_low_confidence_are_rejected(self) -> None:
        value = valid_profile()
        value["identity_name"] = "chair"
        with self.assertRaisesRegex(AffordanceContractError, "extra"):
            validate_affordance_profile(value)
        value = valid_profile()
        value["confidence"] = 0.64
        with self.assertRaisesRegex(AffordanceContractError, "0.65"):
            validate_affordance_profile(value)

    def test_primary_contact_requires_matching_evidence_flag(self) -> None:
        value = valid_profile()
        value["contact_surface"] = "edge"
        with self.assertRaisesRegex(AffordanceContractError, "has_edge"):
            validate_affordance_profile(value)

    def test_sidecar_is_atomic_and_never_overwritten(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "semantic_blueprint.json"
            source.write_text(json.dumps(valid_blueprint()), encoding="utf-8")
            output = root / "round"
            target = publish_sidecar_atomic(source, output)
            self.assertEqual(json.loads(target.read_text(encoding="utf-8")), valid_profile())
            self.assertEqual(list(output.glob("*.tmp")), [])
            with self.assertRaisesRegex(AffordanceContractError, "overwrite"):
                publish_sidecar_atomic(source, output)

    def test_validator_does_not_mutate_input(self) -> None:
        value = valid_profile()
        frozen = copy.deepcopy(value)
        validate_affordance_profile(value)
        self.assertEqual(value, frozen)


if __name__ == "__main__":
    unittest.main()
