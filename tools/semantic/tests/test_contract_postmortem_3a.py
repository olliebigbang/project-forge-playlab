from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import sys
import unittest


SEMANTIC_ROOT = Path(__file__).resolve().parents[1]
BRIDGE_ROOT = SEMANTIC_ROOT / "bridge"
FIXTURE_ROOT = Path(__file__).resolve().parent / "fixtures" / "postmortem_3a"
RUN_ID = "gate-a-20260802T232039017356Z-fddde20a"
if str(BRIDGE_ROOT) not in sys.path:
    sys.path.insert(0, str(BRIDGE_ROOT))

import gate_a_evaluator as evaluator  # noqa: E402
import gate_a_runner as runner  # noqa: E402
from semantic_contract import (  # noqa: E402
    ContractValidationError,
    REQUEST_CLARIFICATION_TOOL,
    SUBMIT_BLUEPRINT_TOOL,
    validate_clarification_request,
    validate_forensic_clarification_request,
    validate_legacy_semantic_blueprint_v1,
    validate_semantic_blueprint,
    validate_tool_input,
)


def _read_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise AssertionError(f"expected JSON object: {path}")
    return value


def _fixture(case_id: str) -> dict:
    return _read_json(FIXTURE_ROOT / f"case_{case_id}_tool_input.json")


def _v1_1_blueprint(
    *,
    canonical_zh: str = "老木桌",
    canonical_en: str = "old wooden table",
    display_zh: str = "回旋锻造老木桌",
    display_en: str = "Returning Forge Old Wooden Table",
    category: str = "furniture",
    required_parts: list[str] | None = None,
) -> dict:
    parts = required_parts or ["broad tabletop", "four table legs"]
    return {
        "identity": {
            "canonical_name_zh": canonical_zh,
            "canonical_name_en": canonical_en,
            "display_name_zh": display_zh,
            "display_name_en": display_en,
            "category": category,
            "required_identity_parts": parts,
            "material_hints": ["aged wood"],
            "silhouette_hints": ["wide rectangular top above four legs"],
            "optional_decorations": ["small forge corner brackets"],
        },
        "combat": {
            "behavior_family": "sustained_ranged",
            "delivery": "continuous_emission",
            "impact_mode": "continuous_stream",
            "effect_type": "sound",
            "drawback": "overheat",
            "cadence_hint": "continuous",
        },
        "visual": {
            "prompt_en": (
                f"One isolated {canonical_en}, broad tabletop, four sturdy wooden legs, "
                "aged wood, side view, complete object visible, subtle Forge fixture"
            ),
            "negative_prompt_en": "gun, sword, umbrella, person, text, scenery",
            "must_preserve": list(parts),
            "must_not_replace_with": ["gun", "sword", "umbrella"],
        },
        "confidence": 0.9,
    }


class FrozenEvidenceFixtureTests(unittest.TestCase):
    def test_four_fixtures_equal_saved_redacted_tool_inputs(self) -> None:
        manifest = _read_json(FIXTURE_ROOT / "manifest.json")
        for case_id, item in manifest["cases"].items():
            with self.subTest(case_id=case_id):
                raw_path = SEMANTIC_ROOT / item["source"]
                raw = _read_json(raw_path)
                tool_uses = [
                    block
                    for block in raw.get("content", [])
                    if isinstance(block, dict) and block.get("type") == "tool_use"
                ]
                self.assertEqual(len(tool_uses), 1)
                self.assertEqual(tool_uses[0]["name"], item["tool_name"])
                self.assertEqual(tool_uses[0]["id"], item["tool_use_id"])
                self.assertEqual(
                    _read_json(FIXTURE_ROOT / item["fixture"]),
                    tool_uses[0]["input"],
                )

    def test_case_10_is_precisely_rejected_without_unwrap_or_repair(self) -> None:
        payload = _fixture("10")
        snapshot = copy.deepcopy(payload)
        with self.assertRaises(ContractValidationError) as caught:
            validate_legacy_semantic_blueprint_v1(payload)
        self.assertEqual(caught.exception.stage, "schema")
        self.assertEqual(
            {issue.json_pointer for issue in caught.exception.issues},
            {"/identity", "/combat", "/visual", "/confidence", "/$FUNCTION_NAME2"},
        )
        self.assertEqual(payload, snapshot)
        self.assertEqual(
            payload["$FUNCTION_NAME2"]["combat"]["behavior_family"],
            "sustained_ranged",
        )

    def test_case_13_passes_frozen_v1_replay_with_bilingual_structure_match(self) -> None:
        payload = _fixture("13")
        snapshot = copy.deepcopy(payload)
        self.assertIs(validate_legacy_semantic_blueprint_v1(payload), payload)
        self.assertEqual(payload, snapshot)
        self.assertEqual(payload["combat"]["behavior_family"], "sustained_ranged")

    def test_case_17_scalar_hint_is_accepted_only_by_forensic_replay(self) -> None:
        payload = _fixture("17")
        snapshot = copy.deepcopy(payload)
        with self.assertRaises(ContractValidationError) as caught:
            validate_clarification_request(payload)
        self.assertEqual(caught.exception.stage, "schema")
        self.assertEqual(
            [issue.json_pointer for issue in caught.exception.issues],
            ["/known_action_hints"],
        )
        with self.assertRaises(ContractValidationError):
            validate_tool_input(REQUEST_CLARIFICATION_TOOL, payload)
        self.assertIs(validate_forensic_clarification_request(payload), payload)
        self.assertEqual(payload, snapshot)
        self.assertIsInstance(payload["known_action_hints"], str)

    def test_case_18_array_hints_are_accepted_by_production_without_rewrite(self) -> None:
        payload = _fixture("18")
        snapshot = copy.deepcopy(payload)
        self.assertIs(validate_clarification_request(payload), payload)
        self.assertEqual(payload, snapshot)
        self.assertIsInstance(payload["known_action_hints"], list)

    def test_saved_evidence_and_original_report_are_byte_unchanged(self) -> None:
        hashes_path = SEMANTIC_ROOT / "reports" / "runs" / RUN_ID / "evidence_hashes.json"
        hashes = _read_json(hashes_path)
        self.assertEqual(hashes["algorithm"], "SHA-256")
        self.assertEqual(hashes["run_id"], RUN_ID)
        for relative, expected in hashes["files"].items():
            with self.subTest(relative=relative):
                actual = hashlib.sha256((SEMANTIC_ROOT / relative).read_bytes()).hexdigest()
                self.assertEqual(actual, expected)

    def test_missing_request_and_validator_files_are_not_invented(self) -> None:
        run_root = SEMANTIC_ROOT / "output" / "gate_a" / RUN_ID
        for case_id in ("10", "13", "17", "18"):
            with self.subTest(case_id=case_id):
                self.assertEqual(
                    {path.name for path in (run_root / case_id).iterdir()},
                    {"result.json"},
                )

    def test_future_failure_manifest_keeps_schema_and_cross_field_stages_distinct(self) -> None:
        payload = _fixture("10")
        with self.assertRaises(ContractValidationError) as caught:
            validate_legacy_semantic_blueprint_v1(payload)
        base = {
            "case_id": "10",
            "model_id": "offline-fixture-model",
            "request_id": "offline-request",
        }
        record = runner._failure_record(
            base=base,
            error=caught.exception,
            parsed={
                "tool_name": SUBMIT_BLUEPRINT_TOOL,
                "model_id": "offline-fixture-model",
                "request_id": "offline-request",
                "usage": {"input_tokens": 0, "output_tokens": 0},
                "raw_response_redacted": "{}",
            },
        )
        self.assertEqual(record["validation"]["stage"], "schema")
        self.assertIs(record["validation"]["schema_valid"], False)
        self.assertIsNone(record["validation"]["cross_field_valid"])
        self.assertEqual(
            {issue["json_pointer"] for issue in record["validation"]["issues"]},
            {"/identity", "/combat", "/visual", "/confidence", "/$FUNCTION_NAME2"},
        )


class ContractV11Tests(unittest.TestCase):
    def test_canonical_identity_rejects_effect_pollution(self) -> None:
        for field, value in (
            ("canonical_name_en", "electric returning wooden table"),
            ("canonical_name_zh", "吸血木桌"),
        ):
            payload = _v1_1_blueprint()
            payload["identity"][field] = value
            if field.endswith("_en"):
                payload["visual"]["prompt_en"] = (
                    f"One isolated {value}, broad tabletop, four table legs, side view, "
                    "complete object visible with subtle Forge fixture"
                )
            with self.assertRaisesRegex(
                ContractValidationError, "canonical identity contains combat/effect"
            ):
                validate_semantic_blueprint(payload)

    def test_display_name_allows_fantasy_and_effect_words(self) -> None:
        payload = _v1_1_blueprint(
            display_zh="吸血闪电回旋老木桌",
            display_en="Electric Lifesteal Returning Forge Table",
        )
        self.assertIs(validate_semantic_blueprint(payload), payload)

    def test_required_identity_parts_reject_material_only_entries(self) -> None:
        payload = _v1_1_blueprint(required_parts=["wood", "bronze"])
        payload["visual"]["must_preserve"] = ["wood", "bronze"]
        with self.assertRaisesRegex(ContractValidationError, "material-only"):
            validate_semantic_blueprint(payload)

    def test_unknown_fields_still_fail_closed(self) -> None:
        payload = _v1_1_blueprint()
        payload["identity"]["legacy_weapon_name"] = "table"
        with self.assertRaisesRegex(ContractValidationError, "additional property"):
            validate_semantic_blueprint(payload)

    def test_true_multi_focus_clarification_is_still_rejected(self) -> None:
        payload = {
            "question_zh": "它是什么？你希望它怎么攻击？",
            "ambiguity_type": "insufficient_information",
            "known_identity_hint": "",
            "known_action_hints": [],
        }
        with self.assertRaisesRegex(ContractValidationError, "one answer focus"):
            validate_tool_input(REQUEST_CLARIFICATION_TOOL, payload)

    def test_empty_string_is_the_only_unknown_identity_sentinel(self) -> None:
        payload = {
            "question_zh": "这个物件是什么？",
            "ambiguity_type": "identity_unclear",
            "known_identity_hint": "",
            "known_action_hints": [],
        }
        self.assertIs(validate_clarification_request(payload), payload)
        payload["known_identity_hint"] = None
        with self.assertRaisesRegex(ContractValidationError, "expected string, got null"):
            validate_clarification_request(payload)

    def test_object_category_does_not_override_continuous_action(self) -> None:
        bell = _v1_1_blueprint(
            canonical_zh="旧铜钟",
            canonical_en="old bronze bell",
            display_zh="冲击音波旧铜钟",
            display_en="Shockwave Old Bronze Bell",
            category="instrument",
            required_parts=["bell body", "bell opening"],
        )
        bell["visual"]["prompt_en"] = (
            "One isolated old bronze bell, bell body and bell opening, side view, "
            "complete object visible with a subtle sound-emission Forge fixture"
        )
        spear = _v1_1_blueprint(
            canonical_zh="古老长枪",
            canonical_en="ancient spear",
            display_zh="冰雾古老长枪",
            display_en="Frost-Mist Ancient Spear",
            category="traditional_weapon",
            required_parts=["long shaft", "spearhead"],
        )
        spear["visual"]["prompt_en"] = (
            "One isolated ancient spear, long straight shaft and pointed spearhead, "
            "side view, complete object visible with a subtle Forge fixture"
        )
        for payload in (bell, spear):
            with self.subTest(category=payload["identity"]["category"]):
                self.assertIs(validate_tool_input(SUBMIT_BLUEPRINT_TOOL, payload), payload)
                self.assertEqual(payload["combat"]["behavior_family"], "sustained_ranged")


class EvaluatorSynonymTests(unittest.TestCase):
    def test_structure_synonyms_are_conservative(self) -> None:
        aliases = ["table legs", "table leg"]
        for candidate in (
            "table legs", "four legs", "wooden legs", "four sturdy wooden legs"
        ):
            with self.subTest(candidate=candidate):
                self.assertTrue(evaluator._feature_matches(candidate, aliases))
        self.assertFalse(evaluator._feature_matches("wooden furniture", aliases))

    def test_plural_and_curated_structure_paraphrases_match(self) -> None:
        self.assertTrue(evaluator._feature_matches("folded paper wing structure", ["wings"]))
        self.assertTrue(evaluator._feature_matches("round flat pan head", ["pan body"]))
        self.assertTrue(evaluator._feature_matches("两侧梯腿", ["side rails"]))

    def test_material_and_decorations_cannot_replace_required_structure(self) -> None:
        result = _v1_1_blueprint()
        result["identity"]["required_identity_parts"] = ["broad tabletop", "carved apron"]
        result["identity"]["material_hints"] = ["wooden furniture", "four-leg motif"]
        result["identity"]["optional_decorations"] = ["decorative metal legs"]
        expected = {
            "core_features": [
                {"label": "桌腿 / table legs", "aliases": ["桌腿", "table legs"]}
            ]
        }
        quality, matched, missing = evaluator._feature_quality(result, expected, False)
        self.assertEqual((quality, matched, missing), (0, [], ["桌腿 / table legs"]))


if __name__ == "__main__":
    unittest.main()
