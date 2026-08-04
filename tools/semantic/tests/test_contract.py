from __future__ import annotations

import copy
import math
from pathlib import Path
import sys
import unittest


BRIDGE_DIR = Path(__file__).resolve().parents[1] / "bridge"
if str(BRIDGE_DIR) not in sys.path:
    sys.path.insert(0, str(BRIDGE_DIR))

from semantic_contract import (  # noqa: E402
    ALLOWED_TOOL_NAMES,
    CLARIFICATION_REQUEST_SCHEMA,
    ContractValidationError,
    FORGE_SEMANTIC_BLUEPRINT_SCHEMA,
    REQUEST_CLARIFICATION_TOOL,
    SUBMIT_BLUEPRINT_TOOL,
    schema_for_tool,
    validate_clarification_request,
    validate_schema_instance,
    validate_semantic_blueprint,
    validate_tool_input,
)


def valid_blueprint(family: str = "returning_thrown") -> dict:
    combat = {
        "sustained_ranged": {
            "behavior_family": "sustained_ranged",
            "delivery": "continuous_emission",
            "impact_mode": "continuous_stream",
            "effect_type": "steam",
            "drawback": "overheat",
            "cadence_hint": "continuous",
        },
        "returning_thrown": {
            "behavior_family": "returning_thrown",
            "delivery": "whole_object_return",
            "impact_mode": "whole_body_collision",
            "effect_type": "normal",
            "drawback": "weapon_absent_while_flying",
            "cadence_hint": "single_commit",
        },
        "heavy_melee": {
            "behavior_family": "heavy_melee",
            "delivery": "whole_object_strike",
            "impact_mode": "strike_edge",
            "effect_type": "normal",
            "drawback": "long_recovery",
            "cadence_hint": "slow_heavy",
        },
    }[family]
    return {
        "identity": {
            "canonical_name_zh": "老木桌",
            "canonical_name_en": "old wooden table",
            "display_name_zh": "回旋锻造老木桌",
            "display_name_en": "Returning Forge Old Wooden Table",
            "category": "furniture",
            "required_identity_parts": ["broad tabletop", "four table legs"],
            "material_hints": ["aged wood"],
            "silhouette_hints": ["wide rectangular top above four legs"],
            "optional_decorations": ["small forge corner brackets"],
        },
        "combat": combat,
        "visual": {
            "prompt_en": (
                "One isolated old wooden table, broad tabletop, four sturdy legs, "
                "aged wood grain, handcrafted fantasy forge fittings, side view, "
                "complete object visible on a flat background."
            ),
            "negative_prompt_en": "gun, sword, umbrella, person, hand, text, scenery",
            "must_preserve": ["broad tabletop", "four sturdy table legs"],
            "must_not_replace_with": ["gun", "sword", "umbrella"],
        },
        "confidence": 0.92,
    }


def valid_clarification() -> dict:
    return {
        "question_zh": "这个红色物件具体是什么？",
        "ambiguity_type": "identity_unclear",
        "known_identity_hint": "红色物件",
        "known_action_hints": ["速度很快"],
    }


class CheckedInSchemaTests(unittest.TestCase):
    def test_schema_shapes_are_exactly_closed(self) -> None:
        self.assertEqual(FORGE_SEMANTIC_BLUEPRINT_SCHEMA["type"], "object")
        self.assertIs(FORGE_SEMANTIC_BLUEPRINT_SCHEMA["additionalProperties"], False)
        self.assertEqual(
            FORGE_SEMANTIC_BLUEPRINT_SCHEMA["required"],
            ["identity", "combat", "visual", "confidence"],
        )
        self.assertEqual(
            FORGE_SEMANTIC_BLUEPRINT_SCHEMA["properties"]["confidence"],
            {"type": "number", "minimum": 0, "maximum": 1},
        )
        self.assertEqual(
            FORGE_SEMANTIC_BLUEPRINT_SCHEMA["properties"]["identity"]["required"],
            [
                "canonical_name_zh",
                "canonical_name_en",
                "display_name_zh",
                "display_name_en",
                "category",
                "required_identity_parts",
                "material_hints",
                "silhouette_hints",
                "optional_decorations",
            ],
        )
        self.assertIs(CLARIFICATION_REQUEST_SCHEMA["additionalProperties"], False)
        self.assertEqual(
            CLARIFICATION_REQUEST_SCHEMA["required"],
            ["question_zh", "ambiguity_type", "known_identity_hint", "known_action_hints"],
        )
        self.assertEqual(
            CLARIFICATION_REQUEST_SCHEMA["properties"]["known_action_hints"]["type"],
            "array",
        )

    def test_tool_schema_lookup_is_closed(self) -> None:
        self.assertEqual(ALLOWED_TOOL_NAMES, {SUBMIT_BLUEPRINT_TOOL, REQUEST_CLARIFICATION_TOOL})
        self.assertIs(schema_for_tool(SUBMIT_BLUEPRINT_TOOL), FORGE_SEMANTIC_BLUEPRINT_SCHEMA)
        with self.assertRaisesRegex(ContractValidationError, "unknown tool"):
            schema_for_tool("invented_tool")


class RecursiveSchemaTests(unittest.TestCase):
    def test_valid_blueprint_is_not_mutated(self) -> None:
        payload = valid_blueprint()
        snapshot = copy.deepcopy(payload)
        self.assertIs(validate_semantic_blueprint(payload), payload)
        self.assertEqual(payload, snapshot)

    def test_unknown_properties_are_rejected_at_every_depth(self) -> None:
        mutations = (
            lambda data: data.__setitem__("debug", True),
            lambda data: data["identity"].__setitem__("weapon_name", "table"),
            lambda data: data["combat"].__setitem__("metadata", {}),
        )
        for mutate in mutations:
            with self.subTest(mutate=repr(mutate)):
                payload = valid_blueprint()
                mutate(payload)
                with self.assertRaisesRegex(ContractValidationError, "additional property"):
                    validate_semantic_blueprint(payload)

    def test_missing_required_and_illegal_enum_are_rejected(self) -> None:
        payload = valid_blueprint()
        del payload["identity"]["canonical_name_zh"]
        with self.assertRaisesRegex(ContractValidationError, "required property is missing"):
            validate_semantic_blueprint(payload)
        payload = valid_blueprint()
        payload["combat"]["effect_type"] = "cosmic"
        with self.assertRaisesRegex(ContractValidationError, "is not in enum"):
            validate_semantic_blueprint(payload)

    def test_wrong_types_are_not_coerced(self) -> None:
        mutations = (
            lambda data: data.__setitem__("confidence", "0.9"),
            lambda data: data.__setitem__("confidence", True),
            lambda data: data["identity"].__setitem__("required_identity_parts", "tabletop"),
            lambda data: data["visual"]["must_preserve"].__setitem__(0, 42),
        )
        for mutate in mutations:
            payload = valid_blueprint()
            mutate(payload)
            with self.assertRaisesRegex(ContractValidationError, "expected"):
                validate_semantic_blueprint(payload)

    def test_string_and_array_bounds_are_recursive(self) -> None:
        payload = valid_blueprint()
        payload["identity"]["canonical_name_en"] = ""
        with self.assertRaisesRegex(ContractValidationError, "below minimum"):
            validate_semantic_blueprint(payload)
        payload = valid_blueprint()
        payload["identity"]["canonical_name_zh"] = "桌" * 81
        with self.assertRaisesRegex(ContractValidationError, "exceeds maximum"):
            validate_semantic_blueprint(payload)
        payload = valid_blueprint()
        payload["identity"]["required_identity_parts"] = ["tabletop"]
        with self.assertRaisesRegex(ContractValidationError, "minimum is 2"):
            validate_semantic_blueprint(payload)
        payload = valid_blueprint()
        payload["identity"]["material_hints"] = ["a", "b", "c", "d", "e"]
        with self.assertRaisesRegex(ContractValidationError, "maximum is 4"):
            validate_semantic_blueprint(payload)

    def test_number_bounds_and_non_json_numbers_are_rejected(self) -> None:
        for invalid in (-0.01, 1.01, 10**1000, math.nan, math.inf):
            payload = valid_blueprint()
            payload["confidence"] = invalid
            with self.assertRaises(ContractValidationError):
                validate_semantic_blueprint(payload)

    def test_generic_validator_recurses_for_objects_arrays_and_numbers(self) -> None:
        schema = {
            "type": "object", "additionalProperties": False, "required": ["rows"],
            "properties": {"rows": {"type": "array", "minItems": 1, "maxItems": 2,
                "items": {"type": "object", "additionalProperties": False,
                    "required": ["score"], "properties": {
                        "score": {"type": "number", "minimum": 0, "maximum": 1}
                    }}}},
        }
        value = {"rows": [{"score": 0.5}]}
        self.assertIs(validate_schema_instance(value, schema), value)
        with self.assertRaisesRegex(ContractValidationError, "additional property"):
            validate_schema_instance({"rows": [{"score": 0.5, "extra": 1}]}, schema)


class CrossFieldTests(unittest.TestCase):
    def test_all_consistent_behavior_families_pass(self) -> None:
        for family in ("sustained_ranged", "returning_thrown", "heavy_melee"):
            validate_semantic_blueprint(valid_blueprint(family))

    def test_sustained_delivery_and_cadence_are_linked(self) -> None:
        payload = valid_blueprint("sustained_ranged")
        payload["combat"]["delivery"] = "whole_object_return"
        payload["combat"]["cadence_hint"] = "single_commit"
        with self.assertRaises(ContractValidationError) as caught:
            validate_semantic_blueprint(payload)
        self.assertIn("continuous_emission or projectile_stream", str(caught.exception))
        self.assertIn("continuous cadence_hint", str(caught.exception))

    def test_returning_requires_four_linked_values(self) -> None:
        for field, invalid in {
            "delivery": "projectile_stream", "impact_mode": "strike_point",
            "cadence_hint": "continuous", "drawback": "overheat",
        }.items():
            payload = valid_blueprint("returning_thrown")
            payload["combat"][field] = invalid
            with self.assertRaisesRegex(ContractValidationError, "returning_thrown requires"):
                validate_semantic_blueprint(payload)

    def test_heavy_requires_linked_delivery_impact_and_cadence(self) -> None:
        for field, invalid in {
            "delivery": "continuous_emission", "impact_mode": "continuous_stream",
            "cadence_hint": "continuous",
        }.items():
            payload = valid_blueprint("heavy_melee")
            payload["combat"][field] = invalid
            with self.assertRaisesRegex(ContractValidationError, "heavy_melee requires"):
                validate_semantic_blueprint(payload)

    def test_positive_prompt_must_contain_name_en(self) -> None:
        payload = valid_blueprint()
        payload["visual"]["prompt_en"] = (
            "One isolated wooden furnishing with a broad top and four sturdy legs, "
            "side view, complete object visible on a flat background."
        )
        with self.assertRaisesRegex(ContractValidationError, "must contain identity.canonical_name_en"):
            validate_semantic_blueprint(payload)

    def test_name_match_tolerates_case_and_punctuation_only(self) -> None:
        payload = valid_blueprint()
        payload["identity"]["canonical_name_en"] = "OLD wooden-table"
        validate_semantic_blueprint(payload)

    def test_positive_prompt_rejects_negative_replacement_language(self) -> None:
        for insert in (
            "Do not replace with a cannon.", "It is not a gun.",
            "Use furniture rather than a sword.", "Avoid generic weapons.", "不得替换成枪。",
        ):
            payload = valid_blueprint()
            payload["visual"]["prompt_en"] += " " + insert
            with self.assertRaisesRegex(ContractValidationError, "forbidden negative replacement phrase"):
                validate_semantic_blueprint(payload)

    def test_must_not_items_cannot_enter_positive_prompt(self) -> None:
        payload = valid_blueprint()
        payload["visual"]["prompt_en"] += " Ornamental gun mechanism."
        with self.assertRaisesRegex(ContractValidationError, "forbidden replacement item 'gun'"):
            validate_semantic_blueprint(payload)

    def test_must_preserve_requires_substantive_intersection(self) -> None:
        payload = valid_blueprint()
        payload["visual"]["must_preserve"] = ["glowing crystal", "spiral horns"]
        with self.assertRaisesRegex(ContractValidationError, "lacks required identity parts"):
            validate_semantic_blueprint(payload)
        payload = valid_blueprint()
        payload["visual"]["must_preserve"] = ["rectangular broad tabletop", "sturdy legs"]
        validate_semantic_blueprint(payload)

    def test_forbidden_fields_are_found_recursively(self) -> None:
        for key in (
            "damage", "base_damage", "attackSpeed", "fire_rate", "range_meters",
            "cooldown_seconds", "code_payload", "runtimeCode", "GDScript",
            "伤害数值", "攻击速度", "射程米数", "冷却时间", "运行代码",
        ):
            payload = valid_blueprint()
            payload["visual"]["unexpected"] = [{"nested": {key: 10}}]
            with self.assertRaisesRegex(ContractValidationError, "may not define"):
                validate_semantic_blueprint(payload)


class ClarificationAndDispatchTests(unittest.TestCase):
    def test_valid_clarification_is_not_mutated(self) -> None:
        payload = valid_clarification()
        snapshot = copy.deepcopy(payload)
        self.assertIs(validate_clarification_request(payload), payload)
        self.assertEqual(payload, snapshot)

    def test_production_clarification_rejects_scalar_action_hint(self) -> None:
        payload = valid_clarification()
        payload["known_action_hints"] = "速度很快"
        snapshot = copy.deepcopy(payload)
        with self.assertRaises(ContractValidationError) as caught:
            validate_clarification_request(payload)
        self.assertEqual(caught.exception.stage, "schema")
        self.assertEqual(
            [issue.json_pointer for issue in caught.exception.issues],
            ["/known_action_hints"],
        )
        self.assertEqual(payload, snapshot)

    def test_clarification_rejects_unknown_enum_and_multiple_questions(self) -> None:
        payload = valid_clarification()
        payload["blueprint"] = valid_blueprint()
        with self.assertRaisesRegex(ContractValidationError, "additional property"):
            validate_clarification_request(payload)
        payload = valid_clarification()
        payload["ambiguity_type"] = "pick_a_weapon"
        with self.assertRaisesRegex(ContractValidationError, "is not in enum"):
            validate_clarification_request(payload)
        payload = valid_clarification()
        payload["question_zh"] = "它是什么？你希望它怎么攻击？"
        with self.assertRaisesRegex(ContractValidationError, "one answer focus"):
            validate_clarification_request(payload)
        payload = valid_clarification()
        payload["question_zh"] = "这个东西是什么，以及你希望它怎样攻击？"
        with self.assertRaisesRegex(ContractValidationError, "interrogative focus"):
            validate_clarification_request(payload)
        payload = valid_clarification()
        payload["question_zh"] = "What object is this and how should it attack?"
        with self.assertRaisesRegex(ContractValidationError, "written in Chinese"):
            validate_clarification_request(payload)
        payload = valid_clarification()
        payload["question_zh"] = "请说明主体物件身份及主要攻击方式？"
        with self.assertRaisesRegex(ContractValidationError, "single focus"):
            validate_clarification_request(payload)

    def test_tool_dispatch_accepts_only_two_names(self) -> None:
        blueprint, clarification = valid_blueprint(), valid_clarification()
        self.assertIs(validate_tool_input(SUBMIT_BLUEPRINT_TOOL, blueprint), blueprint)
        self.assertIs(validate_tool_input(REQUEST_CLARIFICATION_TOOL, clarification), clarification)
        with self.assertRaisesRegex(ContractValidationError, "unknown tool"):
            validate_tool_input("submit_weapon_code", {})


if __name__ == "__main__":
    unittest.main()
