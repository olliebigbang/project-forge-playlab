from __future__ import annotations

import copy
import inspect
import json
import os
from pathlib import Path
import sys
import unittest

BRIDGE = Path(__file__).resolve().parents[1] / "bridge"
sys.path.insert(0, str(BRIDGE))

import affordance_retest_v1_2_runner as runner
from affordance_contract_v1_2 import candidate_tool_schema
from semantic_contract import SUBMIT_BLUEPRINT_TOOL
from test_affordance_contract_v1_2 import valid_blueprint


class AffordanceRetestV12Tests(unittest.TestCase):
    def setUp(self) -> None:
        self.repo = Path(__file__).resolve().parents[3]
        self.semantic = self.repo / "tools" / "semantic"

    def test_frozen_configuration_has_exactly_twelve_isolated_inputs(self) -> None:
        prompt, schema, cases, hashes = runner._load_configuration(self.semantic)
        self.assertEqual(tuple(case["case_id"] for case in cases), runner.CASE_ORDER)
        self.assertEqual(len(cases), 12)
        self.assertIn("affordance", schema["required"])
        self.assertNotIn("review_parts", prompt)
        self.assertEqual(len(hashes["cases_sha256"]), 64)

    def test_request_receives_only_player_prompt_not_frozen_answers(self) -> None:
        prompt, schema, cases, _ = runner._load_configuration(self.semantic)
        case = cases[0]
        digest = runner._request_hash(prompt, case["prompt_zh"], schema)
        self.assertEqual(len(digest), 64)
        from anthropic_semantic_compiler import build_anthropic_payload
        from semantic_contract import CLARIFICATION_REQUEST_SCHEMA
        payload = build_anthropic_payload(prompt, case["prompt_zh"], runner.FROZEN_MODEL_ID, schema, CLARIFICATION_REQUEST_SCHEMA)
        self.assertEqual(payload["messages"], [{"role": "user", "content": [{"type": "text", "text": case["prompt_zh"]}]}])
        non_user_payload = {key: value for key, value in payload.items() if key != "messages"}
        serialized = json.dumps(non_user_payload, ensure_ascii=False)
        self.assertNotIn(case["identity"], serialized)
        self.assertNotIn("review_parts", serialized)
        self.assertNotIn("evaluation_focus", serialized)
        self.assertNotIn("expected_identity", serialized)

    def test_valid_tool_input_is_preserved_exactly(self) -> None:
        blueprint = valid_blueprint()
        parsed = {"tool_name": SUBMIT_BLUEPRINT_TOOL, "tool_input": blueprint, "request_id": "msg_test", "model_id": runner.FROZEN_MODEL_ID, "usage": {}, "stop_reason": "tool_use", "raw_response_redacted": "{}"}
        frozen = copy.deepcopy(blueprint)
        record = runner._record_result(parsed, {"case_id": "A01"})
        self.assertEqual(record["status"], "VALID")
        self.assertEqual(record["validated_blueprint"], frozen)
        self.assertEqual(blueprint, frozen)

    def test_clarification_is_a_failure_for_clear_frozen_corpus(self) -> None:
        parsed = {"tool_name": "request_forge_clarification", "tool_input": {}, "request_id": "msg_test", "model_id": runner.FROZEN_MODEL_ID, "usage": {}, "stop_reason": "tool_use", "raw_response_redacted": "{}"}
        record = runner._record_result(parsed, {"case_id": "A01"})
        self.assertEqual(record["status"], "FAILED")
        self.assertIn("UNEXPECTED_TOOL", record["failure_reason"])

    def test_runner_has_fixed_call_limit_and_no_retry_loop(self) -> None:
        self.assertEqual(runner.APPROVED_CALLS, 12)
        source = inspect.getsource(runner.execute)
        self.assertIn("CallLimiter(APPROVED_CALLS)", source)
        self.assertEqual(source.count("compiler.compile(player_input)"), 1)
        self.assertNotIn("time.sleep", source)
        self.assertNotIn("while ", source)

    def test_frozen_model_and_candidate_schema_are_exact(self) -> None:
        self.assertEqual(runner._source_model(self.semantic), "claude-sonnet-5")
        schema = candidate_tool_schema()
        frozen = json.loads((self.semantic / "schema" / "forge_semantic_blueprint.v1_2_candidate.schema.json").read_text(encoding="utf-8"))
        self.assertEqual(schema["required"], frozen["required"])
        self.assertEqual(set(schema["properties"]), set(frozen["properties"]))
        self.assertNotIn("$ref", json.dumps(schema))

    def test_preflight_never_requires_or_reads_a_key(self) -> None:
        before = os.environ.get("ANTHROPIC_API_KEY")
        try:
            os.environ.pop("ANTHROPIC_API_KEY", None)
            result = runner.preflight(self.repo, self.semantic, require_unused=False)
            self.assertTrue(result["ready"])
            self.assertEqual(result["case_count"], 12)
        finally:
            if before is not None:
                os.environ["ANTHROPIC_API_KEY"] = before


if __name__ == "__main__":
    unittest.main()
