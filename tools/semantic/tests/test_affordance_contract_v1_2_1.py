from __future__ import annotations

import copy
import hashlib
import json
import os
from pathlib import Path
import sys
import unittest

BRIDGE = Path(__file__).resolve().parents[1] / "bridge"
sys.path.insert(0, str(BRIDGE))

from affordance_contract_v1_2 import AffordanceContractError
from affordance_contract_v1_2_1 import (
    CONTRACT_VERSION,
    validate_candidate_blueprint_v1_2_1,
)
import affordance_targeted_retest_v1_2_1_runner as runner
from semantic_contract import ContractValidationError, validate_semantic_blueprint
from test_affordance_contract_v1_2 import valid_blueprint


SOURCE_RUN = "affordance-retest-v1-2-20260808T074610104680Z-70b603d7"


def lexical_probe(name_en: str, name_zh: str) -> dict:
    value = valid_blueprint()
    value["identity"].update(
        {
            "canonical_name_zh": name_zh,
            "canonical_name_en": name_en,
            "display_name_zh": name_zh,
            "display_name_en": name_en.title(),
            "category": "tool",
            "required_identity_parts": ["tool head", "handle"],
            "material_hints": ["metal", "wood"],
            "silhouette_hints": ["tool head mounted across a straight handle"],
            "optional_decorations": [],
        }
    )
    value["visual"].update(
        {
            "prompt_en": f"one isolated {name_en} with a complete tool head and handle, side view, complete object visible",
            "negative_prompt_en": "person, hand, text, unrelated object",
            "must_preserve": ["tool head", "handle"],
            "must_not_replace_with": ["gun"],
        }
    )
    return value


class AffordanceContractV121Tests(unittest.TestCase):
    def setUp(self) -> None:
        self.repo = Path(__file__).resolve().parents[3]
        self.semantic = self.repo / "tools" / "semantic"
        self.run = self.semantic / "reports" / "affordance_retest_v1_2" / SOURCE_RUN

    def test_version_is_additive_and_frozen_v11_still_rejects_fire_axe(self) -> None:
        self.assertEqual(CONTRACT_VERSION, "forge-semantic-v1.2.1-candidate")
        value = lexical_probe("fire axe", "消防斧")
        base = {key: value[key] for key in ("identity", "combat", "visual", "confidence")}
        with self.assertRaisesRegex(ContractValidationError, "modifiers: fire"):
            validate_semantic_blueprint(base)
        self.assertIs(validate_candidate_blueprint_v1_2_1(value), value)

    def test_fire_extinguisher_conventional_identity_is_valid(self) -> None:
        value = lexical_probe("fire extinguisher", "灭火器")
        value["identity"]["required_identity_parts"] = ["cylinder body", "top valve", "hose"]
        value["identity"]["silhouette_hints"] = ["upright cylinder with a hose at the top"]
        value["visual"]["must_preserve"] = ["cylinder body", "top valve", "hose"]
        value["visual"]["prompt_en"] = "one isolated fire extinguisher with a cylinder body, top valve, and hose, side view, complete object visible"
        self.assertIs(validate_candidate_blueprint_v1_2_1(value), value)

    def test_effect_polluted_non_conventional_identity_remains_rejected(self) -> None:
        with self.assertRaisesRegex(ContractValidationError, "modifiers: fire"):
            validate_candidate_blueprint_v1_2_1(lexical_probe("fire sword", "剑"))
        with self.assertRaisesRegex(ContractValidationError, "flaming"):
            validate_candidate_blueprint_v1_2_1(lexical_probe("flaming fire axe", "火焰斧"))

    def test_actual_a07_unknown_field_remains_rejected_without_mutation(self) -> None:
        result = json.loads((self.run / "cases" / "A07" / "result.json").read_text(encoding="utf-8"))
        value = result["tool_input_received"]
        frozen = copy.deepcopy(value)
        with self.assertRaisesRegex(AffordanceContractError, "has_broad_face_evidence"):
            validate_candidate_blueprint_v1_2_1(value)
        self.assertEqual(value, frozen)

    def test_actual_a09_contradictory_grip_remains_rejected_without_mutation(self) -> None:
        result = json.loads((self.run / "cases" / "A09" / "result.json").read_text(encoding="utf-8"))
        value = result["tool_input_received"]
        frozen = copy.deepcopy(value)
        with self.assertRaisesRegex(AffordanceContractError, "body_grip"):
            validate_candidate_blueprint_v1_2_1(value)
        self.assertEqual(value, frozen)

    def test_corrected_recorder_preserves_api_success_input_and_raw_on_local_rejection(self) -> None:
        source = json.loads((self.run / "cases" / "A07" / "result.json").read_text(encoding="utf-8"))
        parsed = {
            "tool_name": source["tool_name"], "tool_input": source["tool_input_received"],
            "request_id": source["request_id"], "model_id": source["response_model_id"],
            "usage": source["usage"], "stop_reason": source["stop_reason"],
            "raw_response_redacted": '{"id":"msg_redacted_test"}',
        }
        record, raw = runner.record_from_parsed(parsed, {"case_id": "A07"})
        self.assertTrue(record["api_success"])
        self.assertEqual(record["api_status"], 200)
        self.assertEqual(record["tool_input_received"], source["tool_input_received"])
        self.assertEqual(record["status"], "FAILED")
        self.assertIn("has_broad_face_evidence", record["failure_reason"])
        self.assertEqual(raw, parsed["raw_response_redacted"])

    def test_targeted_freeze_binds_all_four_source_results_and_missing_raw_is_explicit(self) -> None:
        manifest = json.loads((self.semantic / "cases" / "affordance_targeted_4_v1_2_1.json").read_text(encoding="utf-8"))
        self.assertEqual(tuple(item["case_id"] for item in manifest["cases"]), runner.CASE_ORDER)
        by_id = {item["case_id"]: item for item in manifest["cases"]}
        self.assertFalse(by_id["A03"]["exact_tool_input_available"])
        self.assertFalse(by_id["A08"]["exact_tool_input_available"])
        for case_id, entry in by_id.items():
            path = self.run / "cases" / case_id / "result.json"
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), entry["source_result_sha256"])

    def test_offline_preflight_is_four_calls_zero_retries_and_uses_no_key(self) -> None:
        before = os.environ.pop("ANTHROPIC_API_KEY", None)
        try:
            result = runner.preflight(self.repo, self.semantic, require_unused=False)
        finally:
            if before is not None:
                os.environ["ANTHROPIC_API_KEY"] = before
        self.assertEqual(result["case_order"], list(runner.CASE_ORDER))
        self.assertEqual(result["max_real_calls"], 4)
        self.assertEqual(result["retry_count"], 0)
        self.assertFalse(result["real_calls_authorized_by_preflight"])


if __name__ == "__main__":
    unittest.main()
