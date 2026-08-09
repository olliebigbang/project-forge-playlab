from __future__ import annotations

import copy
import json
from pathlib import Path
import sys
import unittest


BRIDGE = Path(__file__).resolve().parents[1] / "bridge"
sys.path.insert(0, str(BRIDGE))

from affordance_contract_v1_2 import AffordanceContractError  # noqa: E402
from affordance_contract_v1_2_2 import (  # noqa: E402
    CONTRACT_VERSION,
    candidate_tool_schema_v1_2_2,
    strict_schema_accepts_grip_pair,
    validate_candidate_blueprint_v1_2_2,
)
from test_affordance_contract_v1_2 import valid_blueprint  # noqa: E402


UNSUPPORTED = {"minimum", "maximum", "minLength", "maxLength", "minItems", "maxItems"}


def all_keys(value):
    if isinstance(value, dict):
        for key, item in value.items():
            yield key
            yield from all_keys(item)
    elif isinstance(value, list):
        for item in value:
            yield from all_keys(item)


class AffordanceContractV122Tests(unittest.TestCase):
    def test_version_is_additive_and_local_validator_does_not_repair(self) -> None:
        self.assertEqual(CONTRACT_VERSION, "forge-semantic-v1.2.2-candidate")
        value = valid_blueprint()
        value["affordance"]["handle_length"] = "short"
        value["affordance"]["grip_topology"] = "body_grip"
        frozen = copy.deepcopy(value)
        with self.assertRaisesRegex(AffordanceContractError, "body_grip"):
            validate_candidate_blueprint_v1_2_2(value)
        self.assertEqual(value, frozen)

    def test_strict_schema_has_two_disjoint_legal_grip_pair_branches(self) -> None:
        schema = candidate_tool_schema_v1_2_2()
        affordance = schema["properties"]["affordance"]
        self.assertEqual(len(affordance["anyOf"]), 2)
        self.assertTrue(all(branch["additionalProperties"] is False for branch in affordance["anyOf"]))
        self.assertTrue(strict_schema_accepts_grip_pair("none", "body_grip"))
        self.assertTrue(strict_schema_accepts_grip_pair("none", "clamp_grip"))
        self.assertTrue(strict_schema_accepts_grip_pair("short", "one_hand_handle"))
        self.assertTrue(strict_schema_accepts_grip_pair("long", "two_hand_handle"))
        self.assertFalse(strict_schema_accepts_grip_pair("short", "body_grip"))
        self.assertFalse(strict_schema_accepts_grip_pair("none", "one_hand_handle"))

    def test_provider_schema_removes_only_unsupported_constraints(self) -> None:
        schema = candidate_tool_schema_v1_2_2()
        self.assertFalse(UNSUPPORTED.intersection(all_keys(schema)))
        self.assertFalse(schema["additionalProperties"])
        self.assertIn("affordance", schema["required"])
        self.assertEqual(
            set(schema["properties"]),
            {"identity", "combat", "visual", "confidence", "affordance"},
        )

    def test_prompt_is_identity_agnostic_and_makes_combat_grip_invariant(self) -> None:
        prompt = (
            Path(__file__).resolve().parents[1]
            / "prompts"
            / "affordance_v1_2_2_candidate_addendum.md"
        ).read_text(encoding="utf-8")
        self.assertIn("Combat verbs", prompt)
        self.assertIn("must not change", prompt)
        for forbidden in ("chicken", "pan", "broom", "shotgun", "鸡腿"):
            self.assertNotIn(forbidden, prompt.casefold())

    def test_valid_v1_2_1_candidate_remains_valid_without_mutation(self) -> None:
        value = valid_blueprint()
        frozen = json.dumps(value, ensure_ascii=False, sort_keys=True)
        self.assertIs(validate_candidate_blueprint_v1_2_2(value), value)
        self.assertEqual(json.dumps(value, ensure_ascii=False, sort_keys=True), frozen)


if __name__ == "__main__":
    unittest.main()
