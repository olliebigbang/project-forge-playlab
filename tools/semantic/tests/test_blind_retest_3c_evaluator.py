from __future__ import annotations

import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest


SEMANTIC_ROOT = Path(__file__).resolve().parents[1]
BRIDGE_ROOT = SEMANTIC_ROOT / "bridge"
if str(BRIDGE_ROOT) not in sys.path:
    sys.path.insert(0, str(BRIDGE_ROOT))

from anthropic_semantic_compiler import (  # noqa: E402
    ANTHROPIC_MESSAGES_URL,
    BLUEPRINT_TOOL_NAME,
)
from blind_retest_3c_evaluator import (  # noqa: E402
    CASE_ORDER,
    REVIEW_SUBMISSION_VERSION,
    BlindRetest3CEvaluationError,
    ManualStructureReviewError,
    aggregate,
    attach_manual_structure_review,
    evaluate_case,
    evaluate_run,
    load_cases,
    load_expected,
    load_review_rubric,
    validate_manual_structure_review_submission,
)
from semantic_contract import CONTRACT_VERSION  # noqa: E402


CASES_PATH = SEMANTIC_ROOT / "cases" / "blind_retest_3c_cases.json"
EXPECTED_PATH = SEMANTIC_ROOT / "cases" / "blind_retest_3c_expected.json"
RUBRIC_PATH = SEMANTIC_ROOT / "cases" / "blind_retest_3c_review_rubric.json"


DEFINITIONS = {
    "B01": {
        "zh": "吸尘器",
        "en": "vacuum cleaner",
        "display_zh": "灼热喷砂旧吸尘器",
        "display_en": "Old Scorching-Sand Vacuum Cleaner",
        "category": "household_object",
        "parts": ["vacuum body", "long flexible hose", "suction head"],
        "materials": ["aged plastic", "rubber hose"],
        "silhouette": ["canister body connected to a long hose and floor head"],
        "family": "sustained_ranged",
        "delivery": "continuous_emission",
        "impact": "continuous_stream",
        "effect": "fire",
        "drawback": "overheat",
        "cadence": "continuous",
    },
    "B02": {
        "zh": "双铃机械闹钟",
        "en": "twin-bell mechanical alarm clock",
        "display_zh": "回旋双铃机械闹钟",
        "display_en": "Returning Twin-Bell Mechanical Alarm Clock",
        "category": "household_object",
        "parts": ["round clock face", "twin bells", "clock hands"],
        "materials": ["painted metal", "glass face"],
        "silhouette": ["round clock body topped by two symmetric bells"],
        "family": "returning_thrown",
        "delivery": "whole_object_return",
        "impact": "whole_body_collision",
        "effect": "normal",
        "drawback": "weapon_absent_while_flying",
        "cadence": "single_commit",
    },
    "B03": {
        "zh": "巨大订书机",
        "en": "giant stapler",
        "display_zh": "夹击巨大订书机",
        "display_en": "Clamping Giant Stapler",
        "category": "tool",
        "parts": ["upper pressing arm", "stapler base", "rear hinge"],
        "materials": ["painted steel", "rubber base pad"],
        "silhouette": ["long upper arm hinged above a matching flat base"],
        "family": "heavy_melee",
        "delivery": "whole_object_strike",
        "impact": "whole_body_collision",
        "effect": "normal",
        "drawback": "long_recovery",
        "cadence": "slow_heavy",
    },
    "B04": {
        "zh": "高脚杯",
        "en": "goblet",
        "display_zh": "绿色酸液高脚杯",
        "display_en": "Green Acid-Spraying Wine Goblet",
        "category": "household_object",
        "parts": ["cup bowl", "narrow stem", "circular base"],
        "materials": ["green glass"],
        "silhouette": ["rounded bowl above a thin tall stem and broad foot"],
        "family": "sustained_ranged",
        "delivery": "continuous_emission",
        "impact": "continuous_stream",
        "effect": "poison",
        "drawback": "overheat",
        "cadence": "continuous",
    },
}


def _blueprint(case_id: str) -> dict:
    item = DEFINITIONS[case_id]
    parts = list(item["parts"])
    return {
        "identity": {
            "canonical_name_zh": item["zh"],
            "canonical_name_en": item["en"],
            "display_name_zh": item["display_zh"],
            "display_name_en": item["display_en"],
            "category": item["category"],
            "required_identity_parts": parts,
            "material_hints": list(item["materials"]),
            "silhouette_hints": list(item["silhouette"]),
            "optional_decorations": ["small forged reinforcement brackets"],
        },
        "combat": {
            "behavior_family": item["family"],
            "delivery": item["delivery"],
            "impact_mode": item["impact"],
            "effect_type": item["effect"],
            "drawback": item["drawback"],
            "cadence_hint": item["cadence"],
        },
        "visual": {
            "prompt_en": (
                f"One isolated {item['en']}, {parts[0]}, {parts[1]}, and {parts[2]}, "
                "side view, complete object fully visible on a plain background"
            ),
            "negative_prompt_en": "person, hand, text, scenery, generic replacement weapon",
            "must_preserve": parts,
            "must_not_replace_with": ["gun", "sword", "umbrella"],
        },
        "confidence": 0.9,
    }


def _record(case_id: str, payload: dict) -> dict:
    return {
        "case_id": case_id,
        "provider": "anthropic",
        "endpoint": ANTHROPIC_MESSAGES_URL,
        "model_id": "claude-sonnet-5",
        "response_model_id": "claude-sonnet-5",
        "request_id": f"msg_blind_{case_id}",
        "contract_version": CONTRACT_VERSION,
        "api_status": 200,
        "api_request_performed": True,
        "ai_interpretation_used": True,
        "tool_name": BLUEPRINT_TOOL_NAME,
        "tool_input_received": payload,
        "retry_count": 0,
        "repair_applied": False,
        "unwrap_applied": False,
        "coercion_applied": False,
        "defaults_applied": False,
        "response_attestation": {
            "exactly_one_legal_tool_use": True,
            "sole_content_is_tool_use": True,
            "stop_reason_is_tool_use": True,
        },
    }


def _submission(packet: dict, confirmed_count: int = 2) -> dict:
    reviews = []
    for index, concept in enumerate(packet["expected_concepts"]):
        confirmed = index < confirmed_count
        reviews.append(
            {
                "concept_id": concept["concept_id"],
                "required_identity_part_quotes": (
                    [packet["actual_required_identity_parts"][index]] if confirmed else []
                ),
                "must_preserve_quotes": (
                    []
                ),
                "same_structure_concept": confirmed,
                "structural_not_material_or_decoration": confirmed,
                "notes": "confirmed from exact model wording" if confirmed else "not confirmed",
            }
        )
    return {
        "review_submission_version": REVIEW_SUBMISSION_VERSION,
        "case_id": packet["case_id"],
        "tool_input_sha256": packet["tool_input_sha256"],
        "expected_concepts_sha256": packet["expected_concepts_sha256"],
        "concept_reviews": reviews,
        "all_required_parts_are_structural": True,
        "non_structural_required_identity_part_quotes": [],
        "reviewer_reason": "two or more identity structures confirmed",
    }


class BlindRetest3CFrozenInputTests(unittest.TestCase):
    def test_four_player_inputs_are_exact_and_ordered(self) -> None:
        cases = load_cases(CASES_PATH)
        self.assertEqual([item["case_id"] for item in cases], list(CASE_ORDER))
        self.assertEqual(
            [item["input_text"] for item in cases],
            [
                "一台带长软管的旧吸尘器，会持续喷射灼热沙子。",
                "一个双铃机械闹钟，扔出去转一圈后会飞回手中。",
                "一个巨大订书机，我要拿它在近距离夹击敌人。",
                "一个会从杯口持续喷出酸液的绿色高脚杯。",
            ],
        )

    def test_expected_and_rubric_freeze_twelve_unique_concepts(self) -> None:
        rubric = load_review_rubric(RUBRIC_PATH)
        expected = load_expected(EXPECTED_PATH, RUBRIC_PATH)
        concept_ids = []
        for case_id in CASE_ORDER:
            self.assertNotIn("effect_type", expected[case_id])
            ids = [
                item["concept_id"]
                for item in expected[case_id]["manual_structure_review"]["concepts"]
            ]
            self.assertEqual(ids, rubric["concept_ids_by_case"][case_id])
            concept_ids.extend(ids)
        self.assertEqual(len(concept_ids), 12)
        self.assertEqual(len(set(concept_ids)), 12)

    def test_concept_change_that_differs_from_rubric_is_rejected(self) -> None:
        document = json.loads(EXPECTED_PATH.read_text(encoding="utf-8"))
        document["cases"]["B01"]["manual_structure_review"]["concepts"][0][
            "concept_id"
        ] = "post_call_alias"
        with tempfile.TemporaryDirectory() as temp:
            changed = Path(temp) / "expected.json"
            changed.write_text(json.dumps(document, ensure_ascii=False), encoding="utf-8")
            with self.assertRaises(BlindRetest3CEvaluationError):
                load_expected(changed, RUBRIC_PATH)


class BlindRetest3CAutomaticEvaluationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.expected = load_expected(EXPECTED_PATH, RUBRIC_PATH)

    def _score(self, case_id: str, payload: dict) -> dict:
        expected = copy.deepcopy(self.expected[case_id])
        expected["case_id"] = case_id
        return evaluate_case(_record(case_id, payload), expected)

    def test_age_and_colour_may_be_omitted_from_canonical_identity(self) -> None:
        for case_id in ("B01", "B04"):
            with self.subTest(case_id=case_id):
                score = self._score(case_id, _blueprint(case_id))
                self.assertTrue(score["base_identity_correct"])
                self.assertTrue(score["automatic_case_pass"])

    def test_pre_frozen_safe_identity_synonyms_are_accepted(self) -> None:
        variants = {
            "B01": [
                ("旧式吸尘器", "antique vacuum cleaner"),
                ("老式吸尘器", "vintage vacuum cleaner"),
            ],
            "B03": [
                ("巨大订书器", "giant office stapler"),
                ("巨型订书器", "oversized office stapler"),
                ("大号订书器", "large stapler"),
            ],
            "B04": [
                ("葡萄酒杯", "wine glass"),
                ("绿色葡萄酒杯", "green wine glass"),
                ("高脚杯", "stemmed goblet"),
                ("绿色高脚杯", "green stemmed goblet"),
            ],
        }
        for case_id, pairs in variants.items():
            for name_zh, name_en in pairs:
                with self.subTest(case_id=case_id, name_zh=name_zh, name_en=name_en):
                    payload = _blueprint(case_id)
                    old_en = payload["identity"]["canonical_name_en"]
                    payload["identity"]["canonical_name_zh"] = name_zh
                    payload["identity"]["canonical_name_en"] = name_en
                    payload["visual"]["prompt_en"] = payload["visual"]["prompt_en"].replace(
                        old_en, name_en
                    )
                    self.assertTrue(self._score(case_id, payload)["base_identity_correct"])

    def test_canonical_requires_the_approved_base_identity_not_containment(self) -> None:
        payload = _blueprint("B01")
        payload["identity"]["canonical_name_en"] = "vacuum cleaner sand cannon"
        payload["visual"]["prompt_en"] = payload["visual"]["prompt_en"].replace(
            "vacuum cleaner", "vacuum cleaner sand cannon"
        )
        score = self._score("B01", payload)
        self.assertFalse(score["base_identity_correct"])

    def test_twin_bell_and_giant_identity_modifiers_are_required(self) -> None:
        mutations = (("B02", "闹钟", "alarm clock"), ("B03", "订书机", "stapler"))
        for case_id, name_zh, name_en in mutations:
            with self.subTest(case_id=case_id):
                payload = _blueprint(case_id)
                old_en = payload["identity"]["canonical_name_en"]
                payload["identity"]["canonical_name_zh"] = name_zh
                payload["identity"]["canonical_name_en"] = name_en
                payload["visual"]["prompt_en"] = payload["visual"]["prompt_en"].replace(
                    old_en, name_en
                )
                self.assertFalse(self._score(case_id, payload)["base_identity_correct"])

    def test_behavior_family_is_scored_but_effect_type_is_not(self) -> None:
        payload = _blueprint("B01")
        payload["combat"]["effect_type"] = "normal"
        score = self._score("B01", payload)
        self.assertTrue(score["behavior_correct"])
        self.assertTrue(score["automatic_case_pass"])
        self.assertEqual(score["observed_effect_type"], "normal")

        payload = _blueprint("B01")
        payload["combat"].update(
            {
                "behavior_family": "heavy_melee",
                "delivery": "whole_object_strike",
                "impact_mode": "whole_body_collision",
                "drawback": "long_recovery",
                "cadence_hint": "slow_heavy",
            }
        )
        score = self._score("B01", payload)
        self.assertFalse(score["behavior_correct"])
        self.assertFalse(score["automatic_case_pass"])

    def test_unknown_root_wrapper_fails_without_unwrap(self) -> None:
        wrapped = {"$FUNCTION_NAME2": _blueprint("B01")}
        score = self._score("B01", wrapped)
        self.assertFalse(score["schema_valid"])
        self.assertTrue(score["extra_root_wrapper"])
        self.assertEqual(wrapped, {"$FUNCTION_NAME2": _blueprint("B01")})

    def test_fixed_weapon_substitution_scans_only_positive_fields(self) -> None:
        ordinary = self._score("B01", _blueprint("B01"))
        self.assertFalse(ordinary["fixed_weapon_substitution"])

        payload = _blueprint("B01")
        payload["identity"]["optional_decorations"] = ["gatling gun barrel assembly"]
        score = self._score("B01", payload)
        self.assertTrue(score["fixed_weapon_substitution"])
        self.assertFalse(score["automatic_case_pass"])

    def test_invalid_tool_input_still_reports_fixed_weapon_substitution(self) -> None:
        payload = _blueprint("B01")
        payload["identity"]["optional_decorations"] = ["gatling gun barrel assembly"]
        payload["unexpected_root_field"] = True
        score = self._score("B01", payload)
        self.assertFalse(score["schema_valid"])
        self.assertTrue(score["fixed_weapon_substitution_attested"])
        self.assertTrue(score["fixed_weapon_substitution"])
        self.assertFalse(score["automatic_case_pass"])

    def test_exact_model_contract_and_no_local_transformation_are_required(self) -> None:
        payload = _blueprint("B01")
        record = _record("B01", payload)
        expected = copy.deepcopy(self.expected["B01"])
        expected["case_id"] = "B01"

        wrong_model = copy.deepcopy(record)
        wrong_model["model_id"] = "claude-sonnet-latest"
        wrong_model["response_model_id"] = "claude-sonnet-latest"
        score = evaluate_case(wrong_model, expected)
        self.assertFalse(score["envelope_valid"])
        self.assertFalse(score["automatic_case_pass"])

        repaired = copy.deepcopy(record)
        repaired["repair_applied"] = True
        score = evaluate_case(repaired, expected)
        self.assertFalse(score["local_transformation_free"])
        self.assertFalse(score["automatic_case_pass"])
        self.assertEqual(score["manual_structure_review_status"], "NOT_REVIEWABLE")

    def test_evaluate_run_preserves_case_order_and_builds_pending_packets(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            run_root = Path(temp) / "blind-run"
            for case_id in CASE_ORDER:
                case_root = run_root / case_id
                case_root.mkdir(parents=True)
                (case_root / "result.json").write_text(
                    json.dumps(_record(case_id, _blueprint(case_id)), ensure_ascii=False),
                    encoding="utf-8",
                )
            scores = evaluate_run(run_root, EXPECTED_PATH, RUBRIC_PATH)
        self.assertEqual([score["case_id"] for score in scores], list(CASE_ORDER))
        self.assertTrue(all(score["automatic_case_pass"] for score in scores))
        self.assertTrue(
            all(score["manual_structure_review_status"] == "PENDING" for score in scores)
        )


class BlindRetest3CManualReviewTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.expected = load_expected(EXPECTED_PATH, RUBRIC_PATH)

    def _packet(self, case_id: str) -> dict:
        expected = copy.deepcopy(self.expected[case_id])
        expected["case_id"] = case_id
        score = evaluate_case(_record(case_id, _blueprint(case_id)), expected)
        return score["manual_structure_review_packet"]

    def test_packets_expose_no_mutable_alias_list(self) -> None:
        packet = self._packet("B01")
        self.assertEqual(packet["status"], "PENDING")
        self.assertEqual(
            set(packet["expected_concepts"][0]), {"concept_id", "label_zh", "label_en"}
        )
        self.assertNotIn("aliases", json.dumps(packet, ensure_ascii=False).casefold())

    def test_each_case_can_confirm_at_least_two_distinct_exact_structures(self) -> None:
        for case_id in CASE_ORDER:
            with self.subTest(case_id=case_id):
                packet = self._packet(case_id)
                result = validate_manual_structure_review_submission(
                    packet, _submission(packet, confirmed_count=2)
                )
                self.assertEqual(result["status"], "COMPLETE")
                self.assertEqual(result["confirmed_concept_count"], 2)
                self.assertEqual(result["structure_quality"], 2)
                self.assertTrue(result["structure_correct"])
                self.assertTrue(
                    all(
                        not item["must_preserve_quotes"]
                        for item in _submission(packet, confirmed_count=2)["concept_reviews"]
                    )
                )

    def test_unknown_duplicate_and_missing_concepts_are_rejected(self) -> None:
        packet = self._packet("B01")
        base = _submission(packet)

        unknown = copy.deepcopy(base)
        unknown["concept_reviews"][2]["concept_id"] = "post_call_alias"
        with self.assertRaises(ManualStructureReviewError):
            validate_manual_structure_review_submission(packet, unknown)

        duplicate = copy.deepcopy(base)
        duplicate["concept_reviews"][2]["concept_id"] = duplicate["concept_reviews"][0][
            "concept_id"
        ]
        with self.assertRaises(ManualStructureReviewError):
            validate_manual_structure_review_submission(packet, duplicate)

        missing = copy.deepcopy(base)
        missing["concept_reviews"].pop()
        with self.assertRaises(ManualStructureReviewError):
            validate_manual_structure_review_submission(packet, missing)

    def test_review_quotes_must_be_exact_model_output(self) -> None:
        packet = self._packet("B01")
        submission = _submission(packet)
        submission["concept_reviews"][0]["required_identity_part_quotes"] = [
            "rewritten vacuum cleaner body"
        ]
        with self.assertRaises(ManualStructureReviewError):
            validate_manual_structure_review_submission(packet, submission)

    def test_tampered_expected_concept_is_rejected_by_packet_hash(self) -> None:
        packet = self._packet("B01")
        packet["expected_concepts"][0]["label_en"] = "post-call alias"
        with self.assertRaises(ManualStructureReviewError):
            validate_manual_structure_review_submission(packet, _submission(packet))

    def test_one_model_phrase_cannot_confirm_two_concepts(self) -> None:
        packet = self._packet("B01")
        submission = _submission(packet)
        submission["concept_reviews"][1]["required_identity_part_quotes"] = list(
            submission["concept_reviews"][0]["required_identity_part_quotes"]
        )
        submission["concept_reviews"][1]["must_preserve_quotes"] = list(
            submission["concept_reviews"][0]["must_preserve_quotes"]
        )
        with self.assertRaises(ManualStructureReviewError):
            validate_manual_structure_review_submission(packet, submission)

    def test_non_structural_required_part_prevents_quality_two(self) -> None:
        packet = self._packet("B01")
        submission = _submission(packet)
        submission["all_required_parts_are_structural"] = False
        submission["non_structural_required_identity_part_quotes"] = [
            packet["actual_required_identity_parts"][2]
        ]
        result = validate_manual_structure_review_submission(packet, submission)
        self.assertEqual(result["structure_quality"], 1)
        self.assertFalse(result["structure_correct"])

    def test_one_quote_cannot_be_both_structural_and_non_structural(self) -> None:
        packet = self._packet("B01")
        submission = _submission(packet)
        submission["all_required_parts_are_structural"] = False
        submission["non_structural_required_identity_part_quotes"] = [
            packet["actual_required_identity_parts"][0]
        ]
        with self.assertRaises(ManualStructureReviewError):
            validate_manual_structure_review_submission(packet, submission)

    def test_aggregate_keeps_automatic_and_human_gates_separate(self) -> None:
        scores = []
        for case_id in CASE_ORDER:
            expected = copy.deepcopy(self.expected[case_id])
            expected["case_id"] = case_id
            scores.append(evaluate_case(_record(case_id, _blueprint(case_id)), expected))

        pending = aggregate(scores)
        self.assertTrue(pending["automatic_thresholds_passed"])
        self.assertFalse(pending["overall_thresholds_passed"])
        self.assertEqual(pending["status"], "MANUAL REVIEW PENDING")
        self.assertFalse(pending["effect_type_is_scored"])

        reviewed = [
            attach_manual_structure_review(
                score, _submission(score["manual_structure_review_packet"])
            )
            for score in scores
        ]
        completed = aggregate(reviewed)
        self.assertTrue(completed["manual_structure_thresholds_passed"])
        self.assertTrue(completed["overall_thresholds_passed"])
        self.assertEqual(completed["status"], "PASS")


if __name__ == "__main__":
    unittest.main()
