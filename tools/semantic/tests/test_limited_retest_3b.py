from __future__ import annotations

import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock


SEMANTIC_ROOT = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = SEMANTIC_ROOT.parent.parent
BRIDGE_ROOT = SEMANTIC_ROOT / "bridge"
if str(BRIDGE_ROOT) not in sys.path:
    sys.path.insert(0, str(BRIDGE_ROOT))

from anthropic_semantic_compiler import (  # noqa: E402
    ANTHROPIC_MESSAGES_URL,
    BLUEPRINT_TOOL_NAME,
    CLARIFICATION_TOOL_NAME,
    build_anthropic_payload,
)
from limited_retest_3b_evaluator import (  # noqa: E402
    CASE_ORDER,
    aggregate,
    evaluate_case,
    load_expected,
)
from limited_retest_3b_reporting import (  # noqa: E402
    LimitedRetest3BReportingError,
    write_limited_retest_3b_reports,
)
import limited_retest_3b_runner as runner  # noqa: E402
from semantic_contract import (  # noqa: E402
    CLARIFICATION_REQUEST_SCHEMA,
    CONTRACT_VERSION,
    FORGE_SEMANTIC_BLUEPRINT_SCHEMA,
    ContractValidationError,
    validate_tool_input,
)


def _blueprint(case_id: str) -> dict:
    definitions = {
        "10": {
            "zh": "旧铜钟",
            "en": "old bronze bell",
            "display_zh": "冲击音波旧铜钟",
            "display_en": "Shockwave Old Bronze Bell",
            "category": "instrument",
            "parts": ["bell body", "bell opening"],
            "material": ["aged bronze"],
            "silhouette": ["heavy flared body with an open lower rim"],
            "family": "sustained_ranged",
            "delivery": "continuous_emission",
            "impact": "continuous_stream",
            "effect": "sound",
            "drawback": "overheat",
            "cadence": "continuous",
        },
        "13": {
            "zh": "古老长枪",
            "en": "ancient spear",
            "display_zh": "冰雾古老长枪",
            "display_en": "Frost-Mist Ancient Spear",
            "category": "traditional_weapon",
            "parts": ["long shaft", "spearhead"],
            "material": ["aged wood", "dark metal"],
            "silhouette": ["very long narrow pole ending in a pointed head"],
            "family": "sustained_ranged",
            "delivery": "continuous_emission",
            "impact": "continuous_stream",
            "effect": "ice",
            "drawback": "slow_movement",
            "cadence": "continuous",
        },
        "04": {
            "zh": "巨大鸡腿",
            "en": "giant chicken leg",
            "display_zh": "吸血锻造巨大鸡腿",
            "display_en": "Lifesteal Forge Giant Chicken Leg",
            "category": "food",
            "parts": ["thick meaty body", "protruding bone handle"],
            "material": ["roasted chicken meat", "exposed bone"],
            "silhouette": ["bulbous meat end tapering to a narrow bone end"],
            "family": "heavy_melee",
            "delivery": "whole_object_strike",
            "impact": "strike_point",
            "effect": "lifesteal",
            "drawback": "long_recovery",
            "cadence": "slow_heavy",
        },
        "01": {
            "zh": "老木桌",
            "en": "old wooden table",
            "display_zh": "回旋锻造老木桌",
            "display_en": "Returning Forge Old Wooden Table",
            "category": "furniture",
            "parts": ["broad tabletop", "four sturdy wooden legs"],
            "material": ["aged wood"],
            "silhouette": ["wide rectangular top supported by four legs"],
            "family": "returning_thrown",
            "delivery": "whole_object_return",
            "impact": "whole_body_collision",
            "effect": "normal",
            "drawback": "weapon_absent_while_flying",
            "cadence": "single_commit",
        },
    }
    item = definitions[case_id]
    parts = list(item["parts"])
    return {
        "identity": {
            "canonical_name_zh": item["zh"],
            "canonical_name_en": item["en"],
            "display_name_zh": item["display_zh"],
            "display_name_en": item["display_en"],
            "category": item["category"],
            "required_identity_parts": parts,
            "material_hints": list(item["material"]),
            "silhouette_hints": list(item["silhouette"]),
            "optional_decorations": ["small iron corner brackets"],
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
                f"One isolated {item['en']}, {parts[0]} and {parts[1]}, side view, "
                "complete object visible on a flat high contrast background"
            ),
            "negative_prompt_en": "person, hand, text, scenery, generic replacement weapon",
            "must_preserve": parts,
            "must_not_replace_with": ["gun", "sword", "umbrella"],
        },
        "confidence": 0.92,
    }


def _clarification(case_id: str) -> dict:
    if case_id == "17":
        return {
            "question_zh": "这个红色的东西具体是什么物件？",
            "ambiguity_type": "identity_unclear",
            "known_identity_hint": "",
            "known_action_hints": ["非常快"],
        }
    return {
        "question_zh": "你希望主要是一直拿在手里持续喷火，还是让整件飞出去撞人再回来？",
        "ambiguity_type": "behavior_conflict",
        "known_identity_hint": "",
        "known_action_hints": ["一直拿在手里持续喷火", "整件飞出去撞人再回来"],
    }


def _record(case_id: str, tool_name: str, tool_input: dict) -> dict:
    return {
        "case_id": case_id,
        "provider": "anthropic",
        "endpoint": ANTHROPIC_MESSAGES_URL,
        "model_id": "claude-sonnet-5",
        "response_model_id": "claude-sonnet-5",
        "request_id": f"msg_test_{case_id}",
        "contract_version": CONTRACT_VERSION,
        "api_status": 200,
        "api_request_performed": True,
        "ai_interpretation_used": True,
        "tool_name": tool_name,
        "tool_input_received": tool_input,
        "retry_count": 0,
        "response_attestation": {
            "exactly_one_legal_tool_use": True,
            "sole_content_is_tool_use": True,
            "stop_reason_is_tool_use": True,
        },
        "input_tokens": 10,
        "output_tokens": 20,
        "elapsed_ms": 50,
    }


class LimitedRetest3BContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.expected = load_expected(
            SEMANTIC_ROOT / "cases" / "limited_retest_3b_expected.json"
        )

    def _score(self, case_id: str, tool_name: str, payload: dict) -> dict:
        expected = dict(self.expected[case_id])
        expected["case_id"] = case_id
        return evaluate_case(_record(case_id, tool_name, payload), expected)

    def test_case_order_and_live_schema_are_exact(self) -> None:
        self.assertEqual(CASE_ORDER, ("10", "13", "17", "18", "04", "01"))
        action = CLARIFICATION_REQUEST_SCHEMA["properties"]["known_action_hints"]
        self.assertEqual(action["type"], "array")
        self.assertNotIsInstance(action["type"], list)

    def test_four_compiled_examples_pass_strict_offline_scoring(self) -> None:
        for case_id in ("10", "13", "04", "01"):
            with self.subTest(case_id=case_id):
                payload = _blueprint(case_id)
                self.assertIs(validate_tool_input(BLUEPRINT_TOOL_NAME, payload), payload)
                score = self._score(case_id, BLUEPRINT_TOOL_NAME, payload)
                self.assertTrue(score["schema_valid"])
                self.assertTrue(score["cross_field_valid"])
                self.assertTrue(score["identity_correct"])
                self.assertTrue(score["behavior_correct"])
                self.assertEqual(score["required_identity_parts_quality"], 2)
                self.assertFalse(score["fixed_weapon_substitution"])

    def test_two_clarifications_pass_focus_and_array_scoring(self) -> None:
        for case_id in ("17", "18"):
            with self.subTest(case_id=case_id):
                payload = _clarification(case_id)
                self.assertIs(
                    validate_tool_input(CLARIFICATION_TOOL_NAME, payload), payload
                )
                score = self._score(case_id, CLARIFICATION_TOOL_NAME, payload)
                self.assertTrue(score["schema_valid"])
                self.assertTrue(score["cross_field_valid"])
                self.assertTrue(score["clarification_correct"])

    def test_valid_six_case_matrix_meets_every_semantic_threshold(self) -> None:
        scores = []
        for case_id in CASE_ORDER:
            if case_id in {"17", "18"}:
                scores.append(
                    self._score(case_id, CLARIFICATION_TOOL_NAME, _clarification(case_id))
                )
            else:
                scores.append(self._score(case_id, BLUEPRINT_TOOL_NAME, _blueprint(case_id)))
        metrics = aggregate(scores)
        self.assertTrue(metrics["semantic_thresholds_passed"])
        self.assertEqual(metrics["compiled_identity_correct_count"], 4)
        self.assertEqual(metrics["clarification_correct_count"], 2)

    def test_canonical_effect_pollution_is_not_accepted_or_repaired(self) -> None:
        payload = _blueprint("04")
        snapshot = copy.deepcopy(payload)
        payload["identity"]["canonical_name_en"] = "lifesteal giant chicken leg"
        payload["visual"]["prompt_en"] = payload["visual"]["prompt_en"].replace(
            "giant chicken leg", "lifesteal giant chicken leg"
        )
        with self.assertRaises(ContractValidationError):
            validate_tool_input(BLUEPRINT_TOOL_NAME, payload)
        self.assertEqual(payload["combat"], snapshot["combat"])

    def test_material_or_category_phrase_cannot_replace_table_legs(self) -> None:
        payload = _blueprint("01")
        payload["identity"]["required_identity_parts"] = [
            "broad tabletop",
            "wooden furniture",
        ]
        payload["visual"]["must_preserve"] = ["broad tabletop", "wooden furniture"]
        score = self._score("01", BLUEPRINT_TOOL_NAME, payload)
        self.assertEqual(score["required_identity_parts_quality"], 1)
        self.assertIn("table_legs", score["missing_features"])

    def test_fixed_weapon_in_positive_decoration_is_detected(self) -> None:
        payload = _blueprint("10")
        payload["identity"]["optional_decorations"] = ["small gatling gun ornament"]
        score = self._score("10", BLUEPRINT_TOOL_NAME, payload)
        self.assertTrue(score["fixed_weapon_substitution"])
        self.assertFalse(score["identity_correct"])

    def test_fixed_mapping_synonyms_cannot_escape_substitution_scan(self) -> None:
        for replacement in (
            "minigun",
            "machinegun",
            "rifle",
            "pistol",
            "cannon",
            "autocannon",
            "chainsaw",
            "chain saw",
            "claymore",
            "brolly",
        ):
            with self.subTest(replacement=replacement):
                payload = _blueprint("10")
                payload["identity"]["optional_decorations"] = [
                    f"large {replacement} barrel assembly"
                ]
                score = self._score("10", BLUEPRINT_TOOL_NAME, payload)
                self.assertTrue(score["fixed_weapon_substitution"])

    def test_unapproved_decoration_cannot_hide_in_required_parts(self) -> None:
        payload = _blueprint("10")
        payload["identity"]["required_identity_parts"].append(
            "decorative crystal ornament"
        )
        payload["visual"]["must_preserve"].append("decorative crystal ornament")
        score = self._score("10", BLUEPRINT_TOOL_NAME, payload)
        self.assertNotEqual(score["required_identity_parts_quality"], 2)
        self.assertTrue(
            any(
                item.startswith("invalid_required_part:")
                for item in score["missing_features"]
            )
        )

    def test_approved_extra_identity_structure_does_not_reduce_quality(self) -> None:
        payload = _blueprint("10")
        payload["identity"]["required_identity_parts"].append("bell clapper")
        payload["visual"]["must_preserve"].append("bell clapper")
        score = self._score("10", BLUEPRINT_TOOL_NAME, payload)
        self.assertEqual(score["required_identity_parts_quality"], 2)

    def test_negative_replacement_lists_do_not_trigger_substitution(self) -> None:
        score = self._score("10", BLUEPRINT_TOOL_NAME, _blueprint("10"))
        self.assertFalse(score["fixed_weapon_substitution"])

    def test_wrong_identity_category_cannot_receive_identity_or_parts_credit(self) -> None:
        wrong_categories = {
            "10": "food",
            "13": "toy",
            "04": "furniture",
            "01": "traditional_weapon",
        }
        for case_id, category in wrong_categories.items():
            with self.subTest(case_id=case_id):
                payload = _blueprint(case_id)
                payload["identity"]["category"] = category
                score = self._score(case_id, BLUEPRINT_TOOL_NAME, payload)
                self.assertFalse(score["identity_correct"])
                self.assertEqual(score["required_identity_parts_quality"], 0)

    def test_extra_root_wrapper_is_rejected_without_unwrap(self) -> None:
        wrapped = {"$FUNCTION_NAME2": _blueprint("10")}
        score = self._score("10", BLUEPRINT_TOOL_NAME, wrapped)
        self.assertFalse(score["schema_valid"])
        self.assertTrue(score["extra_root_wrapper"])
        self.assertEqual(wrapped, {"$FUNCTION_NAME2": _blueprint("10")})

    def test_case_17_behavior_question_does_not_pass_identity_focus(self) -> None:
        payload = _clarification("17")
        payload["question_zh"] = "你希望它怎么攻击？"
        score = self._score("17", CLARIFICATION_TOOL_NAME, payload)
        self.assertFalse(score["clarification_correct"])

    def test_case_18_identity_question_does_not_pass_behavior_focus(self) -> None:
        payload = _clarification("18")
        payload["question_zh"] = "这个物件到底是什么？"
        score = self._score("18", CLARIFICATION_TOOL_NAME, payload)
        self.assertFalse(score["clarification_correct"])

    def test_mixed_focus_clarifications_are_rejected_by_live_contract_and_evaluator(self) -> None:
        variants = {
            "17": (
                "这个红色东西是什么物件，速度应该多快？",
                "这个红色东西是什么物件，要快速近战吗？",
            ),
            "18": (
                "主要是持续喷火还是整件飞出去再返回，颜色要红色吗？",
                "主要是持续喷火还是整件飞出去再返回，哪个伤害更高？",
            ),
        }
        for case_id, questions in variants.items():
            for question in questions:
                with self.subTest(case_id=case_id, question=question):
                    payload = _clarification(case_id)
                    payload["question_zh"] = question
                    with self.assertRaises(ContractValidationError):
                        validate_tool_input(CLARIFICATION_TOOL_NAME, payload)
                    score = self._score(case_id, CLARIFICATION_TOOL_NAME, payload)
                    self.assertFalse(score["clarification_correct"])

    def test_source_faithful_case_17_identity_hint_is_accepted(self) -> None:
        payload = _clarification("17")
        payload["known_identity_hint"] = "红色的东西"
        score = self._score("17", CLARIFICATION_TOOL_NAME, payload)
        self.assertTrue(score["clarification_correct"])

    def test_valid_clarification_paraphrases_remain_accepted(self) -> None:
        identity = _clarification("17")
        identity["question_zh"] = "这个红色东西具体是哪一类？"
        identity["known_identity_hint"] = "红色物体"
        self.assertTrue(
            self._score("17", CLARIFICATION_TOOL_NAME, identity)[
                "clarification_correct"
            ]
        )
        behavior = _clarification("18")
        behavior["question_zh"] = (
            "主要是保持在手中不断喷射火焰，还是把整件投出去再飞回？"
        )
        self.assertTrue(
            self._score("18", CLARIFICATION_TOOL_NAME, behavior)[
                "clarification_correct"
            ]
        )

    def test_fabricated_extra_action_hints_fail_clarification_scoring(self) -> None:
        identity = _clarification("17")
        identity["known_action_hints"].append("heavy melee")
        self.assertFalse(
            self._score("17", CLARIFICATION_TOOL_NAME, identity)[
                "clarification_correct"
            ]
        )
        behavior = _clarification("18")
        behavior["known_action_hints"].append("红色外观")
        self.assertFalse(
            self._score("18", CLARIFICATION_TOOL_NAME, behavior)[
                "clarification_correct"
            ]
        )

    def test_live_request_payload_has_v11_schemas_and_no_root_wrapper(self) -> None:
        payload = build_anthropic_payload(
            "strict semantic compiler",
            "一口会不断发出冲击音波的旧铜钟",
            "claude-sonnet-5",
            FORGE_SEMANTIC_BLUEPRINT_SCHEMA,
            CLARIFICATION_REQUEST_SCHEMA,
        )
        self.assertEqual(payload["model"], "claude-sonnet-5")
        self.assertEqual(payload["tool_choice"]["disable_parallel_tool_use"], True)
        self.assertEqual(len(payload["tools"]), 2)
        self.assertNotIn("$FUNCTION_NAME2", json.dumps(payload, ensure_ascii=False))
        clarification = next(
            tool for tool in payload["tools"] if tool["name"] == CLARIFICATION_TOOL_NAME
        )
        self.assertEqual(
            clarification["input_schema"]["properties"]["known_action_hints"]["type"],
            "array",
        )


class LimitedRetest3BGuardTests(unittest.TestCase):
    def test_approved_configuration_manifest_pins_live_inputs(self) -> None:
        value = runner.verify_approved_configuration(SEMANTIC_ROOT)
        self.assertEqual(
            value["approved_config_manifest_sha256"],
            runner.APPROVED_CONFIG_MANIFEST_SHA256,
        )
        self.assertGreaterEqual(value["approved_config_file_count"], 20)

    def test_frozen_history_and_exact_model_provenance_verify(self) -> None:
        value = runner.verify_protected_history(REPOSITORY_ROOT, SEMANTIC_ROOT)
        self.assertEqual(value["source_run_id"], runner.SOURCE_RUN_ID)
        self.assertEqual(value["model_id"], "claude-sonnet-5")
        self.assertEqual(value["source_evidence_sha256"], runner.SOURCE_EVIDENCE_SHA256)

    def test_configuration_selects_only_six_approved_cases(self) -> None:
        prompt, blueprint, clarification, cases, hashes = runner._configuration(
            SEMANTIC_ROOT
        )
        self.assertTrue(prompt.strip())
        self.assertEqual(blueprint, FORGE_SEMANTIC_BLUEPRINT_SCHEMA)
        self.assertEqual(clarification, CLARIFICATION_REQUEST_SCHEMA)
        self.assertEqual([case["case_id"] for case in cases], list(CASE_ORDER))
        self.assertEqual(set(hashes), {
            "system_prompt_sha256",
            "blueprint_schema_sha256",
            "clarification_schema_sha256",
            "source_cases_file_sha256",
            "selected_cases_sha256",
            "evaluator_expected_sha256",
        })

    def test_separate_persistent_budget_allows_each_case_once_only(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            semantic = Path(temp)
            path = runner._claim_budget(
                semantic,
                run_id="limited-retest-3b-20260803T000000000000Z-1234abcd",
                model_id="claude-sonnet-5",
                hashes={"selected_cases_sha256": "0" * 64},
            )
            run_id = "limited-retest-3b-20260803T000000000000Z-1234abcd"
            for index, case_id in enumerate(CASE_ORDER, start=1):
                runner._reserve_case_attempt(path, run_id, case_id)
                runner._record_observed_calls(path, run_id, index)
            value = runner._read_reservation(path, run_id)
            self.assertEqual(value["attempts_reserved"], 6)
            self.assertEqual(value["actual_calls_observed"], 6)
            with self.assertRaises(runner.LimitedRetest3BError):
                runner._reserve_case_attempt(path, run_id, "10")
            with self.assertRaises(runner.LimitedRetest3BError):
                runner._claim_budget(
                    semantic,
                    run_id=run_id,
                    model_id="claude-sonnet-5",
                    hashes={},
                )

    def test_exact_frozen_model_is_required_without_echoing_key(self) -> None:
        key = "not-a-real-value"
        original_key = runner.os.environ.get("ANTHROPIC_API_KEY")
        original_model = runner.os.environ.get("FORGE_SEMANTIC_MODEL")
        try:
            runner.os.environ["ANTHROPIC_API_KEY"] = key
            runner.os.environ["FORGE_SEMANTIC_MODEL"] = "claude-sonnet-5"
            self.assertEqual(
                runner.require_environment("claude-sonnet-5"), "claude-sonnet-5"
            )
            runner.os.environ["FORGE_SEMANTIC_MODEL"] = "claude-sonnet-5-latest"
            with self.assertRaisesRegex(
                runner.LimitedRetest3BError, "exactly match"
            ):
                runner.require_environment("claude-sonnet-5")
        finally:
            if original_key is None:
                runner.os.environ.pop("ANTHROPIC_API_KEY", None)
            else:
                runner.os.environ["ANTHROPIC_API_KEY"] = original_key
            if original_model is None:
                runner.os.environ.pop("FORGE_SEMANTIC_MODEL", None)
            else:
                runner.os.environ["FORGE_SEMANTIC_MODEL"] = original_model

    def test_no_force_new_run_surface_exists(self) -> None:
        for name in (
            "run_limited_retest_3b_interactive.ps1",
            "run_limited_retest_3b.ps1",
            "invoke_limited_retest_3b_core.ps1",
        ):
            text = (SEMANTIC_ROOT / "scripts" / name).read_text(encoding="utf-8")
            self.assertNotIn("ForceNewRun", text)
        help_text = runner._parse_args(["--repo-root", str(REPOSITORY_ROOT)])
        self.assertFalse(hasattr(help_text, "force_new_run"))

    def test_interactive_key_boundary_is_process_local_and_scrubbed(self) -> None:
        interactive = (
            SEMANTIC_ROOT / "scripts" / "run_limited_retest_3b_interactive.ps1"
        ).read_text(encoding="utf-8")
        core = (
            SEMANTIC_ROOT / "scripts" / "invoke_limited_retest_3b_core.ps1"
        ).read_text(encoding="utf-8")
        self.assertIn("-AsSecureString", interactive)
        self.assertIn("SecureStringToBSTR", interactive)
        self.assertIn("ZeroFreeBSTR", interactive)
        self.assertIn("Remove-Item Env:ANTHROPIC_API_KEY", interactive)
        self.assertIn("Remove-Item Env:FORGE_SEMANTIC_MODEL", interactive)
        self.assertIn("-E -S -B", core)
        self.assertNotIn("setx", interactive.casefold())
        self.assertNotIn("Invoke-WebRequest", interactive)

    def test_runner_attempts_six_cases_once_in_order_without_network(self) -> None:
        class FakeCompiler:
            instances: list["FakeCompiler"] = []

            def __init__(self, **kwargs: object) -> None:
                self._limiter = kwargs["call_limiter"]
                self.inputs: list[str] = []
                FakeCompiler.instances.append(self)

            @property
            def calls_made(self) -> int:
                return self._limiter.calls_made

            def compile(self, player_input: str) -> dict:
                self._limiter.reserve()
                self.inputs.append(player_input)
                case_id = dict(zip([case["input_text"] for case in selected], CASE_ORDER))[
                    player_input
                ]
                if case_id in {"17", "18"}:
                    tool_name = CLARIFICATION_TOOL_NAME
                    tool_input = _clarification(case_id)
                else:
                    tool_name = BLUEPRINT_TOOL_NAME
                    tool_input = _blueprint(case_id)
                return {
                    "tool_name": tool_name,
                    "tool_input": tool_input,
                    "request_id": f"msg_fake_{case_id}",
                    "model_id": "claude-sonnet-5",
                    "usage": {
                        "input_tokens": 1,
                        "output_tokens": 1,
                        "cache_creation_input_tokens": 0,
                        "cache_read_input_tokens": 0,
                    },
                    "stop_reason": "tool_use",
                    "raw_response_redacted": json.dumps(
                        {"id": f"msg_fake_{case_id}", "model": "claude-sonnet-5"}
                    ),
                }

        selected = [
            {"case_id": case_id, "input_text": f"offline input {case_id}"}
            for case_id in CASE_ORDER
        ]
        valid_scores = []
        expected = load_expected(
            SEMANTIC_ROOT / "cases" / "limited_retest_3b_expected.json"
        )
        for case_id in CASE_ORDER:
            tool_name = (
                CLARIFICATION_TOOL_NAME
                if case_id in {"17", "18"}
                else BLUEPRINT_TOOL_NAME
            )
            payload = (
                _clarification(case_id)
                if case_id in {"17", "18"}
                else _blueprint(case_id)
            )
            label = dict(expected[case_id])
            label["case_id"] = case_id
            valid_scores.append(evaluate_case(_record(case_id, tool_name, payload), label))

        with tempfile.TemporaryDirectory() as temp:
            repository = Path(temp)
            semantic = repository / "tools" / "semantic"
            semantic.mkdir(parents=True)
            fake_summary = {
                "run_id": "fake-run",
                "status": "LIMITED RETEST 3B PASS",
                "call_count": 6,
            }
            patches = (
                mock.patch.object(runner, "AnthropicSemanticCompiler", FakeCompiler),
                mock.patch.object(
                    runner,
                    "_preflight",
                    return_value={
                        "model_id": "claude-sonnet-5",
                        "source_run_id": runner.SOURCE_RUN_ID,
                        "source_evidence_sha256": runner.SOURCE_EVIDENCE_SHA256,
                        "approved_config_manifest_sha256": "0" * 64,
                        "approved_config_file_count": 1,
                    },
                ),
                mock.patch.object(
                    runner,
                    "_configuration",
                    return_value=(
                        "offline strict prompt",
                        FORGE_SEMANTIC_BLUEPRINT_SCHEMA,
                        CLARIFICATION_REQUEST_SCHEMA,
                        selected,
                        {"selected_cases_sha256": "0" * 64},
                    ),
                ),
                mock.patch.object(runner, "verify_scope_baseline", return_value={}),
                mock.patch.object(runner, "verify_protected_history", return_value={}),
                mock.patch.object(runner, "scan_repository", return_value=[]),
                mock.patch.object(runner, "evaluate_run", return_value=valid_scores),
                mock.patch.object(
                    runner,
                    "write_limited_retest_3b_reports",
                    return_value=fake_summary,
                ),
            )
            with mock.patch.dict(
                runner.os.environ,
                {
                    "ANTHROPIC_API_KEY": "process-local-test-value",
                    "FORGE_SEMANTIC_MODEL": "claude-sonnet-5",
                },
                clear=False,
            ):
                with patches[0], patches[1], patches[2], patches[3], patches[4], patches[5], patches[6], patches[7]:
                    summary = runner.execute_limited_retest_3b(
                        semantic_root=semantic,
                        repository_root=repository,
                    )
            self.assertEqual(summary, fake_summary)
            self.assertEqual(len(FakeCompiler.instances), 1)
            self.assertEqual(
                FakeCompiler.instances[0].inputs,
                [case["input_text"] for case in selected],
            )
            self.assertEqual(FakeCompiler.instances[0].calls_made, 6)
            reservation = json.loads(
                (semantic / "reports" / "limited_retest_3b_real_call_reservation.json").read_text(
                    encoding="utf-8"
                )
            )
            self.assertEqual(reservation["attempted_case_ids"], list(CASE_ORDER))
            self.assertEqual(reservation["status"], "closed")
            for case_id in CASE_ORDER:
                self.assertTrue(
                    (
                        semantic
                        / "output"
                        / "limited_retest_3b"
                        / reservation["run_id"]
                        / case_id
                        / "result.json"
                    ).is_file()
                )


class LimitedRetest3BReportingTests(unittest.TestCase):
    def test_report_tree_is_new_atomic_hashed_and_non_overwritable(self) -> None:
        expected = load_expected(
            SEMANTIC_ROOT / "cases" / "limited_retest_3b_expected.json"
        )
        results: list[dict] = []
        scores: list[dict] = []
        for case_id in CASE_ORDER:
            if case_id in {"17", "18"}:
                tool_name = CLARIFICATION_TOOL_NAME
                tool_input = _clarification(case_id)
                result_type = "needs_clarification"
            else:
                tool_name = BLUEPRINT_TOOL_NAME
                tool_input = _blueprint(case_id)
                result_type = "compiled"
            record = _record(case_id, tool_name, tool_input)
            record.update(
                {
                    "local_request_id": f"local-{case_id}",
                    "request_body_sha256": case_id * 32,
                    "tool_input_sha256": ("a" + case_id) * 21 + "a",
                    "result_type": result_type,
                    "result": tool_input,
                    "raw_response_redacted": json.dumps(
                        {
                            "id": f"msg_test_{case_id}",
                            "type": "message",
                            "model": "claude-sonnet-5",
                        }
                    ),
                    "repair_applied": False,
                    "unwrap_applied": False,
                    "coercion_applied": False,
                    "defaults_applied": False,
                }
            )
            results.append(record)
            label = dict(expected[case_id])
            label["case_id"] = case_id
            scores.append(evaluate_case(record, label))

        with tempfile.TemporaryDirectory() as temp:
            repository = Path(temp)
            semantic = repository / "tools" / "semantic"
            run_id = "limited-retest-3b-20260803T000000000000Z-1234abcd"
            output_run = semantic / "output" / "limited_retest_3b" / run_id
            for record in results:
                path = output_run / record["case_id"] / "result.json"
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(
                    json.dumps(record, ensure_ascii=False, indent=2) + "\n",
                    encoding="utf-8",
                )
            for relative, content in (
                ("prompts/semantic_compiler_system_prompt.md", "safe prompt"),
                ("schema/forge_semantic_blueprint.schema.json", "{}"),
                ("schema/clarification_request.schema.json", "{}"),
                ("cases/gate_a_cases.json", "{}"),
                ("cases/limited_retest_3b_expected.json", "{}"),
                ("cases/limited_retest_3b_protected_hashes.json", "{}"),
            ):
                path = semantic / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content, encoding="utf-8")
            approved_relatives = [
                "prompts/semantic_compiler_system_prompt.md",
                "schema/forge_semantic_blueprint.schema.json",
                "schema/clarification_request.schema.json",
                "cases/gate_a_cases.json",
                "cases/limited_retest_3b_expected.json",
                "cases/limited_retest_3b_protected_hashes.json",
            ]
            (semantic / "cases" / "limited_retest_3b_approved_config.json").write_text(
                json.dumps({"files": {relative: "0" * 64 for relative in approved_relatives}}),
                encoding="utf-8",
            )
            reservation = semantic / "reports" / "limited_retest_3b_real_call_reservation.json"
            reservation.parent.mkdir(parents=True, exist_ok=True)
            reservation.write_text(
                json.dumps(
                    {
                        "run_id": run_id,
                        "model_id": "claude-sonnet-5",
                        "contract_version": CONTRACT_VERSION,
                        "endpoint": ANTHROPIC_MESSAGES_URL,
                        "max_real_calls": 6,
                        "attempts_reserved": 6,
                        "actual_calls_observed": 6,
                        "attempted_case_ids": list(CASE_ORDER),
                        "status": "closed",
                    }
                ),
                encoding="utf-8",
            )
            summary = write_limited_retest_3b_reports(
                semantic_root=semantic,
                repository_root=repository,
                run_id=run_id,
                model_id="claude-sonnet-5",
                results=results,
                scores=scores,
                output_run_directory=output_run,
                reservation_path=reservation,
                actual_call_count=6,
                configuration_hashes={"test": "0" * 64},
                preflight={
                    "source_run_id": runner.SOURCE_RUN_ID,
                    "source_evidence_sha256": runner.SOURCE_EVIDENCE_SHA256,
                    "protected_file_count": 14,
                    "approved_config_manifest_sha256": "0" * 64,
                    "approved_config_file_count": len(approved_relatives),
                },
            )
            self.assertEqual(summary["status"], "LIMITED RETEST 3B PASS")
            archive = semantic / "reports" / "limited_retest_3b" / run_id
            self.assertTrue((archive / "COMPLETE.json").is_file())
            self.assertTrue((archive / "evidence_hashes.json").is_file())
            self.assertEqual(
                len(list((archive / "raw_response_redacted").glob("*.json"))), 6
            )
            top_report = semantic / "reports" / "LIMITED_RETEST_3B_REPORT.md"
            archive_report = archive / "LIMITED_RETEST_3B_REPORT.md"
            self.assertTrue(top_report.is_file())
            archived_bytes = archive_report.read_bytes()
            top_report.write_text("independent convenience edit", encoding="utf-8")
            self.assertEqual(archive_report.read_bytes(), archived_bytes)
            with self.assertRaises(LimitedRetest3BReportingError):
                write_limited_retest_3b_reports(
                    semantic_root=semantic,
                    repository_root=repository,
                    run_id=run_id,
                    model_id="claude-sonnet-5",
                    results=results,
                    scores=scores,
                    output_run_directory=output_run,
                    reservation_path=reservation,
                    actual_call_count=6,
                    configuration_hashes={},
                    preflight={},
                )


if __name__ == "__main__":
    unittest.main()
