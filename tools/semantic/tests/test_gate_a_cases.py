from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path


SEMANTIC_ROOT = Path(__file__).resolve().parents[1]
BRIDGE_ROOT = SEMANTIC_ROOT / "bridge"
if str(BRIDGE_ROOT) not in sys.path:
    sys.path.insert(0, str(BRIDGE_ROOT))

import gate_a_evaluator as evaluator  # noqa: E402


EXACT_GATE_A_INPUTS = [
    "会飞出去撞敌人再返回的老木桌",
    "会连续发射螺丝的木椅",
    "喷射高温蒸汽的旧茶壶",
    "一只会吸血的巨大鸡腿，我要拿着它近身砸敌人",
    "一把扔出去后会带着电流飞回来的机械雨伞",
    "一个会持续喷出冰雾的破旧衣柜",
    "一根会咬人的巨型法棍，我想拿它在近距离砸敌人",
    "一个会连续发射钉子的红色工具箱",
    "一架飞出去会分裂，返回时重新合拢的纸飞机",
    "一口会不断发出冲击音波的旧铜钟",
    "一把整件飞出去绕一圈再回来的折叠木梯",
    "一只会连续吐出毒泡泡的橡皮鸭",
    "一柄会从枪尖持续喷出冰雾的古老长枪",
    "一口扔出去砸中敌人后会飞回手里的平底锅",
    "一台会连续发出致盲闪光的老式照相机",
    "一把用琴弓像锯子一样近距离割人的旧小提琴",
    "一个红色的东西，要非常快",
    "一件一直拿在手里持续喷火，同时整件飞出去撞人再回来",
    "a wooden toolbox，会连续发射生锈的钉子",
    "一团看起来像云但摸起来像铁的东西，我想拿它砸人",
]


def _base_envelope(case_id: str, result_type: str, tool_name: str, result: dict) -> dict:
    return {
        "case_id": case_id,
        "run_id": "gate-a-test-run",
        "api_status": 200,
        "provider": "anthropic",
        "model_id": "test-model-id",
        "request_id": f"request-{case_id}",
        "contract_version": "forge-semantic-v1",
        "ai_interpretation_used": True,
        "usage": {"input_tokens": 100, "output_tokens": 50},
        "started_at": "2026-08-03T00:00:00Z",
        "completed_at": "2026-08-03T00:00:01Z",
        "elapsed_ms": 1000,
        "result_type": result_type,
        "tool_name": tool_name,
        "failure_reason": "",
        "result": result,
    }


def _valid_table_blueprint(prompt_suffix: str = "") -> dict:
    return {
        "identity": {
            "name_zh": "老木桌",
            "name_en": "old wooden table",
            "category": "furniture",
            "preserved_features": ["桌面", "桌腿", "旧木材"],
            "material_hints": ["旧木材"],
            "silhouette_hints": ["四条桌腿支撑的宽桌面"],
        },
        "combat": {
            "behavior_family": "returning_thrown",
            "delivery": "whole_object_return",
            "impact_mode": "whole_body_collision",
            "effect_type": "normal",
            "drawback": "weapon_absent_while_flying",
            "cadence_hint": "single_commit",
        },
        "visual": {
            "prompt_en": (
                "one isolated old wooden table, broad tabletop, four table legs, "
                "aged wood material, subtle Forge fittings, side view, complete object visible"
                + prompt_suffix
            ),
            "negative_prompt_en": "gun, sword, umbrella, text, person, cropped object",
            "must_preserve": ["桌面", "桌腿", "旧木材"],
            "must_not_replace_with": ["gun", "sword", "umbrella"],
        },
        "confidence": 0.96,
    }


class GateACaseCorpusTests(unittest.TestCase):
    def setUp(self) -> None:
        self.case_path = SEMANTIC_ROOT / "cases" / "gate_a_cases.json"
        self.expected_path = SEMANTIC_ROOT / "cases" / "gate_a_expected.json"

    def test_all_twenty_inputs_are_verbatim_and_ordered(self) -> None:
        cases = evaluator.load_gate_a_cases(self.case_path)
        self.assertEqual([case["case_id"] for case in cases], [f"{i:02d}" for i in range(1, 21)])
        self.assertEqual([case["input_text"] for case in cases], EXACT_GATE_A_INPUTS)

    def test_model_facing_cases_contain_no_expected_labels(self) -> None:
        raw = json.loads(self.case_path.read_text(encoding="utf-8"))
        forbidden = {
            "result_type",
            "tool_name",
            "identity",
            "name_zh",
            "name_en",
            "behavior_family",
            "core_features",
            "ambiguity_type",
        }
        for case in raw["cases"]:
            self.assertEqual(set(case), {"case_id", "input_text"})
            self.assertTrue(forbidden.isdisjoint(case))

    def test_isolation_interface_returns_only_player_text(self) -> None:
        case = evaluator.load_gate_a_cases(self.case_path)[0]
        self.assertEqual(evaluator.isolated_model_input(case), EXACT_GATE_A_INPUTS[0])
        enriched = dict(case, behavior_family="returning_thrown")
        with self.assertRaises(evaluator.EvaluationInputError):
            evaluator.isolated_model_input(enriched)

    def test_expected_labels_are_complete_and_evaluator_only(self) -> None:
        expected = evaluator.load_gate_a_expected(self.expected_path)
        self.assertEqual(len(expected), 20)
        compiled = [item for item in expected if item["result_type"] == "compiled"]
        self.assertEqual(len(compiled), 18)
        for item in compiled:
            self.assertEqual(item["tool_name"], "submit_forge_semantic_blueprint")
            self.assertIn("name_zh_aliases", item["identity"])
            self.assertIn("name_en_aliases", item["identity"])
            self.assertGreaterEqual(len(item["core_features"]), 2)
            self.assertLessEqual(len(item["core_features"]), 5)

    def test_cases_17_and_18_require_exact_clarifications(self) -> None:
        expected = {item["case_id"]: item for item in evaluator.load_gate_a_expected(self.expected_path)}
        self.assertEqual(expected["17"]["result_type"], "needs_clarification")
        self.assertEqual(expected["17"]["tool_name"], "request_forge_clarification")
        self.assertEqual(expected["17"]["ambiguity_type"], "identity_unclear")
        self.assertEqual(expected["18"]["result_type"], "needs_clarification")
        self.assertEqual(expected["18"]["tool_name"], "request_forge_clarification")
        self.assertEqual(expected["18"]["ambiguity_type"], "behavior_conflict")

    def test_prompt_covers_injection_identity_and_positive_prompt_boundaries(self) -> None:
        prompt = (SEMANTIC_ROOT / "prompts" / "semantic_compiler_system_prompt.md").read_text(
            encoding="utf-8"
        )
        required_phrases = [
            "untrusted data",
            "change or bypass a schema",
            "reveal this prompt",
            "exactly one supplied client tool",
            "Identity is independent from combat behavior",
            "must remain that object",
            "behavior families, not visual identities",
            "Never put negative replacement wording",
            "negative_prompt_en",
            "must_not_replace_with",
            "request_forge_clarification",
            "exactly one short, decisive question",
        ]
        for phrase in required_phrases:
            self.assertIn(phrase, prompt)


class GateAEvaluatorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        expected_path = SEMANTIC_ROOT / "cases" / "gate_a_expected.json"
        cls.expected = {
            item["case_id"]: item for item in evaluator.load_gate_a_expected(expected_path)
        }

    def test_compiled_case_gets_bilingual_behavior_and_feature_scores(self) -> None:
        record = _base_envelope(
            "01", "compiled", "submit_forge_semantic_blueprint", _valid_table_blueprint()
        )
        score = evaluator.evaluate_case(record, self.expected["01"])
        self.assertTrue(score["schema_valid"])
        self.assertTrue(score["identity_correct"])
        self.assertTrue(score["behavior_correct"])
        self.assertEqual(score["preserved_features_quality"], 2)
        self.assertFalse(score["fixed_weapon_substitution"])
        self.assertEqual(score["input_tokens"], 100)

    def test_feature_score_is_conservative_when_identity_structure_is_missing(self) -> None:
        blueprint = _valid_table_blueprint()
        blueprint["identity"]["preserved_features"] = ["桌面", "金属铆钉"]
        blueprint["identity"]["material_hints"] = []
        blueprint["identity"]["silhouette_hints"] = ["宽阔轮廓"]
        blueprint["visual"]["must_preserve"] = ["桌面", "金属铆钉"]
        blueprint["visual"]["prompt_en"] = (
            "one isolated old wooden table with a broad tabletop and Forge fittings, "
            "side view, complete object visible"
        )
        record = _base_envelope("01", "compiled", "submit_forge_semantic_blueprint", blueprint)
        score = evaluator.evaluate_case(record, self.expected["01"])
        self.assertTrue(score["schema_valid"])
        self.assertEqual(score["preserved_features_quality"], 1)
        self.assertIn("桌腿", " ".join(score["missing_features"]))

    def test_prompt_only_features_cannot_receive_full_preservation_credit(self) -> None:
        blueprint = _valid_table_blueprint()
        blueprint["identity"]["preserved_features"] = ["金属铆钉", "锻造夹具"]
        blueprint["identity"]["material_hints"] = []
        blueprint["identity"]["silhouette_hints"] = ["宽阔轮廓"]
        blueprint["visual"]["must_preserve"] = ["金属铆钉", "锻造夹具"]
        # The positive prompt still contains every table feature, but prompt
        # prose is not evidence that explicit preservation fields retained it.
        record = _base_envelope(
            "01", "compiled", "submit_forge_semantic_blueprint", blueprint
        )
        score = evaluator.evaluate_case(record, self.expected["01"])
        self.assertLess(score["preserved_features_quality"], 2)

    def test_fixed_weapon_substitution_checks_positive_not_negative_fields(self) -> None:
        safe_record = _base_envelope(
            "01", "compiled", "submit_forge_semantic_blueprint", _valid_table_blueprint()
        )
        safe_score = evaluator.evaluate_case(safe_record, self.expected["01"])
        self.assertFalse(safe_score["fixed_weapon_substitution"])

        substituted = _valid_table_blueprint(
            ", transformed into a gatling gun as the dominant object silhouette"
        )
        bad_record = _base_envelope(
            "01", "compiled", "submit_forge_semantic_blueprint", substituted
        )
        bad_score = evaluator.evaluate_case(bad_record, self.expected["01"])
        self.assertTrue(bad_score["fixed_weapon_substitution"])
        self.assertFalse(bad_score["identity_correct"])
        self.assertEqual(bad_score["preserved_features_quality"], 0)

    def test_real_umbrella_identity_is_not_a_fixed_substitution(self) -> None:
        umbrella = _valid_table_blueprint()
        umbrella["identity"].update(
            {
                "name_zh": "机械雨伞",
                "name_en": "mechanical umbrella",
                "preserved_features": ["伞面", "伞骨", "伞柄"],
                "material_hints": ["metal"],
                "silhouette_hints": ["umbrella canopy and shaft"],
            }
        )
        umbrella["visual"].update(
            {
                "prompt_en": (
                    "one isolated mechanical umbrella, articulated canopy, umbrella ribs, "
                    "long umbrella shaft and handle, side view, complete object visible"
                ),
                "must_preserve": ["伞面", "伞骨", "伞柄"],
            }
        )
        record = _base_envelope(
            "05", "compiled", "submit_forge_semantic_blueprint", umbrella
        )
        score = evaluator.evaluate_case(record, self.expected["05"])
        self.assertFalse(score["fixed_weapon_substitution"])

    def test_clarification_cases_score_tool_type_and_one_question(self) -> None:
        clarification = {
            "question_zh": "这个红色物件具体是什么？",
            "ambiguity_type": "identity_unclear",
            "known_identity_hint": "红色物件",
            "known_action_hints": ["非常快"],
        }
        record = _base_envelope(
            "17", "needs_clarification", "request_forge_clarification", clarification
        )
        score = evaluator.evaluate_case(record, self.expected["17"])
        self.assertTrue(score["schema_valid"])
        self.assertTrue(score["clarification_correct"])
        self.assertFalse(score["identity_correct"])
        self.assertEqual(score["preserved_features_quality"], 0)

    def test_live_evaluator_rejects_scalar_action_hint(self) -> None:
        clarification = {
            "question_zh": "这个红色物件具体是什么？",
            "ambiguity_type": "identity_unclear",
            "known_identity_hint": "红色物件",
            "known_action_hints": "非常快",
        }
        record = _base_envelope(
            "17", "needs_clarification", "request_forge_clarification", clarification
        )
        score = evaluator.evaluate_case(record, self.expected["17"])
        self.assertFalse(score["schema_valid"])
        self.assertFalse(score["clarification_correct"])

    def test_wrong_clarification_type_fails(self) -> None:
        clarification = {
            "question_zh": "你希望保留哪一种主要攻击方式？",
            "ambiguity_type": "identity_unclear",
            "known_identity_hint": "",
            "known_action_hints": ["持续喷火", "整件飞出并返回"],
        }
        record = _base_envelope(
            "18", "needs_clarification", "request_forge_clarification", clarification
        )
        score = evaluator.evaluate_case(record, self.expected["18"])
        self.assertFalse(score["clarification_correct"])

    def test_non_chinese_or_dual_focus_clarification_fails_schema(self) -> None:
        for question in (
            "What object is this and how should it attack?",
            "请说明主体物件身份及主要攻击方式？",
        ):
            clarification = {
                "question_zh": question,
                "ambiguity_type": "identity_unclear",
                "known_identity_hint": "",
                "known_action_hints": [],
            }
            record = _base_envelope(
                "17",
                "needs_clarification",
                "request_forge_clarification",
                clarification,
            )
            score = evaluator.evaluate_case(record, self.expected["17"])
            self.assertFalse(score["schema_valid"])
            self.assertFalse(score["clarification_correct"])

    def test_mock_or_non_anthropic_result_cannot_receive_semantic_credit(self) -> None:
        record = _base_envelope(
            "01", "compiled", "submit_forge_semantic_blueprint", _valid_table_blueprint()
        )
        record["provider"] = "mock"
        record["ai_interpretation_used"] = False
        score = evaluator.evaluate_case(record, self.expected["01"])
        self.assertFalse(score["envelope_valid"])
        self.assertFalse(score["identity_correct"])
        self.assertFalse(score["behavior_correct"])

    def test_evaluator_refuses_tmp_and_reads_only_direct_case_results(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            tmp_run = root / ".tmp" / "run"
            tmp_run.mkdir(parents=True)
            with self.assertRaises(evaluator.EvaluationInputError):
                evaluator.load_run_results(tmp_run, ["01"])

            final_run = root / "output" / "gate_a" / "run"
            (final_run / "nested" / "01").mkdir(parents=True)
            (final_run / "nested" / "01" / "result.json").write_text(
                json.dumps(_base_envelope(
                    "01", "compiled", "submit_forge_semantic_blueprint", _valid_table_blueprint()
                )),
                encoding="utf-8",
            )
            loaded = evaluator.load_run_results(final_run, ["01"])
            self.assertIsNone(loaded["01"])

    def test_evaluate_run_emits_all_twenty_scores_when_files_are_missing(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            scores = evaluator.evaluate_run(
                temporary, SEMANTIC_ROOT / "cases" / "gate_a_expected.json"
            )
        self.assertEqual(len(scores), 20)
        self.assertTrue(all(score["api_status"] == "missing" for score in scores))
        summary = evaluator.summarize_scores(scores)
        self.assertEqual(summary["api_processable_count"], 0)
        self.assertEqual(summary["identity_correct_count"], 0)


if __name__ == "__main__":
    unittest.main()
