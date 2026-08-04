from __future__ import annotations

import copy
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import unittest
from unittest import mock


SEMANTIC_ROOT = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = SEMANTIC_ROOT.parent.parent
BRIDGE_ROOT = SEMANTIC_ROOT / "bridge"
if str(BRIDGE_ROOT) not in sys.path:
    sys.path.insert(0, str(BRIDGE_ROOT))

import blind_retest_3c_reporting as reporting  # noqa: E402
import blind_retest_3c_runner as runner  # noqa: E402
from anthropic_semantic_compiler import (  # noqa: E402
    ANTHROPIC_MESSAGES_URL,
    BLUEPRINT_TOOL_NAME,
    build_anthropic_payload,
)
from blind_retest_3c_evaluator import (  # noqa: E402
    CASE_ORDER,
    REVIEW_SUBMISSION_VERSION,
    evaluate_case,
    load_cases,
    load_expected,
)
from semantic_contract import (  # noqa: E402
    CLARIFICATION_REQUEST_SCHEMA,
    CONTRACT_VERSION,
    FORGE_SEMANTIC_BLUEPRINT_SCHEMA,
)


CASES_PATH = SEMANTIC_ROOT / "cases" / "blind_retest_3c_cases.json"
EXPECTED_PATH = SEMANTIC_ROOT / "cases" / "blind_retest_3c_expected.json"
RUBRIC_PATH = SEMANTIC_ROOT / "cases" / "blind_retest_3c_review_rubric.json"
APPROVED_PATH = SEMANTIC_ROOT / "cases" / "blind_retest_3c_approved_config.json"

FROZEN_INPUTS = {
    "B01": "一台带长软管的旧吸尘器，会持续喷射灼热沙子。",
    "B02": "一个双铃机械闹钟，扔出去转一圈后会飞回手中。",
    "B03": "一个巨大订书机，我要拿它在近距离夹击敌人。",
    "B04": "一个会从杯口持续喷出酸液的绿色高脚杯。",
}

SHARED_HASHES = {
    "prompts/semantic_compiler_system_prompt.md": (
        "a2d42b808175988267cf51193f2a4e43b2cc258bc1647887fe5c238d006bed12"
    ),
    "schema/forge_semantic_blueprint.schema.json": (
        "9f404c7894b32a46c8f319ed1a95724fc3e623fa2fec384ce00375d0facb631d"
    ),
    "schema/clarification_request.schema.json": (
        "17d1cda61f298db0ec2f7cc8b2f3fe901c7e63bea37c13ce7825cb6a0871f1ee"
    ),
    "bridge/semantic_contract.py": (
        "38d571d86c7360ffe4a861eeaabc34a5563ecc3db30e3de38651501311ace756"
    ),
    "bridge/anthropic_semantic_compiler.py": (
        "1e4fd20fc3de8ff1815636038887ca37009450c842d294356c5e0a90a3eca1b8"
    ),
}


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


_BLUEPRINT_DATA = {
    "B01": (
        "旧吸尘器",
        "old vacuum cleaner",
        "sustained_ranged",
        "continuous_emission",
        "continuous_stream",
        "fire",
        "overheat",
        "continuous",
        ["vacuum body", "long flexible hose", "suction head"],
    ),
    "B02": (
        "双铃机械闹钟",
        "twin-bell mechanical alarm clock",
        "returning_thrown",
        "whole_object_return",
        "whole_body_collision",
        "normal",
        "weapon_absent_while_flying",
        "single_commit",
        ["clock face", "twin bells", "clock hands"],
    ),
    "B03": (
        "巨大订书机",
        "giant stapler",
        "heavy_melee",
        "whole_object_strike",
        "whole_body_collision",
        "normal",
        "long_recovery",
        "slow_heavy",
        ["upper pressing arm", "base", "rear hinge"],
    ),
    "B04": (
        "绿色高脚杯",
        "green wine goblet",
        "sustained_ranged",
        "continuous_emission",
        "continuous_stream",
        "poison",
        "overheat",
        "continuous",
        ["cup bowl", "narrow stem", "base"],
    ),
}


def _blueprint(case_id: str) -> dict:
    (
        canonical_zh,
        canonical_en,
        family,
        delivery,
        impact,
        effect,
        drawback,
        cadence,
        parts,
    ) = _BLUEPRINT_DATA[case_id]
    return {
        "identity": {
            "canonical_name_zh": canonical_zh,
            "canonical_name_en": canonical_en,
            "display_name_zh": canonical_zh,
            "display_name_en": canonical_en,
            "category": "household_object" if case_id != "B03" else "tool",
            "required_identity_parts": list(parts),
            "material_hints": ["forged material"],
            "silhouette_hints": ["recognizable complete object silhouette"],
            "optional_decorations": ["small forge brackets"],
        },
        "combat": {
            "behavior_family": family,
            "delivery": delivery,
            "impact_mode": impact,
            "effect_type": effect,
            "drawback": drawback,
            "cadence_hint": cadence,
        },
        "visual": {
            "prompt_en": (
                f"One isolated {canonical_en}, {parts[0]}, {parts[1]}, {parts[2]}, "
                "complete object fully visible"
            ),
            "negative_prompt_en": "person, hand, text, scenery, replacement weapon",
            "must_preserve": list(parts),
            "must_not_replace_with": ["gun", "umbrella", "greatsword"],
        },
        "confidence": 0.9,
    }


def _result_record(case_id: str) -> dict:
    payload = _blueprint(case_id)
    raw = {
        "id": f"msg_blind_{case_id}",
        "model": runner.FROZEN_MODEL_ID,
        "stop_reason": "tool_use",
        "content": [
            {"type": "tool_use", "name": BLUEPRINT_TOOL_NAME, "input": payload}
        ],
    }
    return {
        "case_id": case_id,
        "input_text": FROZEN_INPUTS[case_id],
        "local_request_id": f"local-{case_id}",
        "provider": "anthropic",
        "endpoint": ANTHROPIC_MESSAGES_URL,
        "model_id": runner.FROZEN_MODEL_ID,
        "response_model_id": runner.FROZEN_MODEL_ID,
        "request_id": f"msg_blind_{case_id}",
        "contract_version": CONTRACT_VERSION,
        "api_status": 200,
        "api_request_performed": True,
        "ai_interpretation_used": True,
        "request_body_sha256": "1" * 64,
        "tool_name": BLUEPRINT_TOOL_NAME,
        "tool_input_received": copy.deepcopy(payload),
        "tool_input_sha256": hashlib.sha256(
            json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode(
                "utf-8"
            )
        ).hexdigest(),
        "result_type": "compiled",
        "result": copy.deepcopy(payload),
        "validation": {
            "stage": "complete",
            "schema_valid": True,
            "cross_field_valid": True,
            "issues": [],
            "repaired": False,
            "unwrapped": False,
            "coerced": False,
            "defaulted": False,
        },
        "schema_valid": True,
        "response_attestation": {
            "exactly_one_legal_tool_use": True,
            "sole_content_is_tool_use": True,
            "stop_reason_is_tool_use": True,
            "input_root_keys": sorted(payload),
            "extra_root_keys": [],
            "missing_root_keys": [],
            "extra_root_wrapper": False,
        },
        "retry_count": 0,
        "repair_applied": False,
        "unwrap_applied": False,
        "coercion_applied": False,
        "defaults_applied": False,
        "started_at": "2026-08-03T00:00:00.000Z",
        "completed_at": "2026-08-03T00:00:01.000Z",
        "elapsed_ms": 1000,
        "input_tokens": 10,
        "output_tokens": 20,
        "cache_creation_input_tokens": 0,
        "cache_read_input_tokens": 0,
        "result": payload,
        "raw_response_redacted": json.dumps(raw, ensure_ascii=False),
        "failure_reason": "",
    }


def _score(case_id: str, expected_by_id: dict) -> dict:
    expected = copy.deepcopy(expected_by_id[case_id])
    expected["case_id"] = case_id
    return evaluate_case(_result_record(case_id), expected)


def _case_review(packet: dict) -> dict:
    reviews = []
    for index, concept in enumerate(packet["expected_concepts"]):
        confirmed = index < 2
        reviews.append(
            {
                "concept_id": concept["concept_id"],
                "required_identity_part_quotes": (
                    [packet["actual_required_identity_parts"][index]] if confirmed else []
                ),
                "must_preserve_quotes": [],
                "same_structure_concept": confirmed,
                "structural_not_material_or_decoration": confirmed,
                "notes": "exact model phrase" if confirmed else "not confirmed",
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
        "reviewer_reason": "two frozen structures confirmed from exact output",
    }


class BlindRetest3CFrozenBoundaryTests(unittest.TestCase):
    def test_frozen_inputs_model_and_shared_contract_hashes(self) -> None:
        cases = load_cases(CASES_PATH)
        self.assertEqual([item["case_id"] for item in cases], list(CASE_ORDER))
        self.assertEqual(
            {item["case_id"]: item["input_text"] for item in cases}, FROZEN_INPUTS
        )
        self.assertEqual(runner.APPROVED_CALLS, 4)
        self.assertEqual(runner.FROZEN_MODEL_ID, "claude-sonnet-5")
        self.assertEqual(CONTRACT_VERSION, "forge-semantic-v1.1")
        for relative, expected in SHARED_HASHES.items():
            with self.subTest(relative=relative):
                self.assertEqual(_sha256(SEMANTIC_ROOT / relative), expected)

    def test_expected_structures_never_enter_provider_payload(self) -> None:
        system_prompt = (
            SEMANTIC_ROOT / "prompts" / "semantic_compiler_system_prompt.md"
        ).read_text(encoding="utf-8")
        payload = build_anthropic_payload(
            system_prompt,
            FROZEN_INPUTS["B03"],
            runner.FROZEN_MODEL_ID,
            FORGE_SEMANTIC_BLUEPRINT_SCHEMA,
            CLARIFICATION_REQUEST_SCHEMA,
        )
        encoded = json.dumps(payload, ensure_ascii=False)
        self.assertIn(FROZEN_INPUTS["B03"], encoded)
        self.assertNotIn("upper pressing arm", encoded)
        self.assertNotIn("rear hinge", encoded)
        self.assertNotIn("blind_retest_3c_expected", encoded)

    def test_approved_manifest_verifies_or_fails_closed_before_sealing(self) -> None:
        if APPROVED_PATH.is_file():
            verified = runner.verify_approved_configuration(SEMANTIC_ROOT)
            self.assertEqual(
                verified["approved_config_manifest_sha256"],
                runner.APPROVED_CONFIG_MANIFEST_SHA256,
            )
            self.assertEqual(
                verified["approved_config_file_count"],
                len(runner.APPROVED_FILE_RELATIVE_PATHS),
            )
            self.assertNotEqual(runner.APPROVED_CONFIG_MANIFEST_SHA256, "0" * 64)
        else:
            self.assertEqual(runner.APPROVED_CONFIG_MANIFEST_SHA256, "0" * 64)
            with self.assertRaises(runner.BlindRetest3CError):
                runner.verify_approved_configuration(SEMANTIC_ROOT)

    def test_protected_gate_a_and_3b_hash_chains_are_read_only_valid(self) -> None:
        protected = runner.verify_3c_protected_history_manifest(
            REPOSITORY_ROOT, SEMANTIC_ROOT
        )
        source = runner.verify_source_3b(SEMANTIC_ROOT)
        self.assertEqual(protected["protected_history_anchor_count"], 8)
        self.assertEqual(source["source_3b_run_id"], runner.SOURCE_3B_RUN_ID)
        self.assertEqual(source["source_3b_evidence_file_count"], 51)
        self.assertEqual(source["source_prior_protected_file_count"], 14)


class BlindRetest3CStrictRunnerTests(unittest.TestCase):
    def test_reservation_allows_four_ordered_attempts_and_never_a_fifth(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            semantic_root = Path(temp) / "tools" / "semantic"
            semantic_root.mkdir(parents=True)
            reservation = runner._claim_budget(
                semantic_root,
                run_id="blind-retest-3c-20260803T000000000000Z-1234abcd",
                model_id=runner.FROZEN_MODEL_ID,
                hashes={"blind_expected_sha256": "a" * 64},
                configuration_snapshot={"files": {}},
            )
            run_id = "blind-retest-3c-20260803T000000000000Z-1234abcd"
            for observed, case_id in enumerate(CASE_ORDER, start=1):
                runner._reserve_case_attempt(reservation, run_id, case_id)
                runner._record_observed_calls(reservation, run_id, observed)
            value = json.loads(reservation.read_text(encoding="utf-8"))
            self.assertEqual(value["attempts_reserved"], 4)
            self.assertEqual(value["actual_calls_observed"], 4)
            self.assertEqual(value["attempted_case_ids"], list(CASE_ORDER))
            with self.assertRaises(runner.BlindRetest3CError):
                runner._reserve_case_attempt(reservation, run_id, "B04")
            with self.assertRaises(runner.BlindRetest3CError):
                runner._claim_budget(
                    semantic_root,
                    run_id=run_id,
                    model_id=runner.FROZEN_MODEL_ID,
                    hashes={"blind_expected_sha256": "a" * 64},
                    configuration_snapshot={"files": {}},
                )

    def test_strict_parser_keeps_exact_tool_input_and_rejects_root_wrapper(self) -> None:
        base = runner._base_record(
            case_id="B01",
            player_input=FROZEN_INPUTS["B01"],
            local_request_id="local-B01",
            model_id=runner.FROZEN_MODEL_ID,
            request_body_sha256="1" * 64,
            hashes={},
            started_at="2026-08-03T00:00:00.000Z",
            completed_at="2026-08-03T00:00:01.000Z",
            elapsed_ms=1000,
            actual_request_performed=True,
        )
        payload = _blueprint("B01")
        parsed = {
            "tool_name": BLUEPRINT_TOOL_NAME,
            "tool_input": payload,
            "model_id": runner.FROZEN_MODEL_ID,
            "request_id": "msg-B01",
            "stop_reason": "tool_use",
            "usage": {},
            "raw_response_redacted": "{}",
        }
        record = runner._record_from_parsed(parsed=parsed, base=base)
        self.assertEqual(record["result"], payload)
        self.assertEqual(record["tool_input_received"], payload)
        self.assertIsNot(record["result"], payload)
        self.assertFalse(record["repair_applied"])
        self.assertFalse(record["unwrap_applied"])
        self.assertFalse(record["coercion_applied"])
        self.assertFalse(record["defaults_applied"])

        wrapped = copy.deepcopy(parsed)
        wrapped["tool_input"] = {"$FUNCTION_NAME2": payload}
        rejected = runner._record_from_parsed(parsed=wrapped, base=base)
        self.assertEqual(rejected["result_type"], "failed")
        self.assertTrue(rejected["response_attestation"]["extra_root_wrapper"])
        self.assertEqual(rejected["tool_input_received"], wrapped["tool_input"])
        self.assertFalse(rejected["validation"]["unwrapped"])

    def test_four_case_loop_does_not_retry_after_one_simulated_failure(self) -> None:
        real_cases = load_cases(CASES_PATH)
        calls: list[str] = []
        delivered: list[str] = []
        captured: dict = {}

        class FakeCompiler:
            def __init__(self, **_kwargs: object) -> None:
                self._calls = 0

            @property
            def calls_made(self) -> int:
                return self._calls

            def compile(self, player_input: str) -> dict:
                self._calls += 1
                calls.append(player_input)
                if player_input == FROZEN_INPUTS["B02"]:
                    raise RuntimeError("simulated single-attempt failure")
                case_id = next(
                    item["case_id"] for item in real_cases if item["input_text"] == player_input
                )
                return {
                    "tool_name": BLUEPRINT_TOOL_NAME,
                    "tool_input": _blueprint(case_id),
                    "model_id": runner.FROZEN_MODEL_ID,
                    "request_id": f"msg-{case_id}",
                    "stop_reason": "tool_use",
                    "usage": {},
                    "raw_response_redacted": "{}",
                }

        def fake_deliver(**kwargs: object) -> Path:
            delivered.append(str(kwargs["case_id"]))
            return Path(kwargs["output_run_directory"]) / str(kwargs["case_id"])

        def fake_writer(**kwargs: object) -> dict:
            captured.update(kwargs)
            return {"status": "PENDING_HUMAN_REVIEW", "run_id": kwargs["run_id"]}

        with tempfile.TemporaryDirectory() as temp:
            repository_root = Path(temp) / "repo"
            semantic_root = repository_root / "tools" / "semantic"
            semantic_root.mkdir(parents=True)
            hashes = {
                "blind_expected_sha256": _sha256(EXPECTED_PATH),
                "blind_review_rubric_sha256": _sha256(RUBRIC_PATH),
            }
            snapshot = {"snapshot_sha256": "frozen", "files": {}}
            preflight = {
                "model_id": runner.FROZEN_MODEL_ID,
                "configuration_snapshot": snapshot,
            }
            with (
                mock.patch.object(runner, "require_safe_tls_environment"),
                mock.patch.object(runner, "_preflight", return_value=preflight),
                mock.patch.object(
                    runner, "require_environment", return_value=runner.FROZEN_MODEL_ID
                ),
                mock.patch.object(
                    runner,
                    "_configuration",
                    return_value=(
                        "frozen prompt",
                        FORGE_SEMANTIC_BLUEPRINT_SCHEMA,
                        CLARIFICATION_REQUEST_SCHEMA,
                        real_cases,
                        hashes,
                    ),
                ),
                mock.patch.object(
                    runner, "verify_configuration_snapshot", return_value=snapshot
                ),
                mock.patch.object(runner, "AnthropicSemanticCompiler", FakeCompiler),
                mock.patch.object(
                    runner,
                    "_new_run_id",
                    return_value="blind-retest-3c-20260803T000000000000Z-deadbeef",
                ),
                mock.patch.object(runner, "_deliver_case", side_effect=fake_deliver),
                mock.patch.object(runner, "verify_scope_baseline", return_value={}),
                mock.patch.object(
                    runner, "verify_3c_protected_history_manifest", return_value={}
                ),
                mock.patch.object(runner, "verify_source_3b", return_value={}),
                mock.patch.object(
                    runner, "verify_approved_configuration", return_value={}
                ),
                mock.patch.object(runner, "scan_repository", return_value=[]),
                mock.patch.object(
                    runner,
                    "evaluate_run",
                    return_value=[{"case_id": case_id} for case_id in CASE_ORDER],
                ),
                mock.patch.object(
                    runner, "write_pending_blind_retest_3c_review", side_effect=fake_writer
                ),
                mock.patch.object(
                    runner,
                    "_sha256",
                    side_effect=lambda path: (
                        hashes["blind_expected_sha256"]
                        if Path(path).name == EXPECTED_PATH.name
                        else hashes["blind_review_rubric_sha256"]
                    ),
                ),
            ):
                result = runner.execute_blind_retest_3c(
                    semantic_root=semantic_root, repository_root=repository_root
                )

            self.assertEqual(result["status"], "PENDING_HUMAN_REVIEW")
            self.assertEqual(calls, [FROZEN_INPUTS[item] for item in CASE_ORDER])
            self.assertEqual(delivered, list(CASE_ORDER))
            self.assertEqual(captured["actual_call_count"], 4)
            self.assertEqual(len(captured["results"]), 4)
            failed = next(
                item for item in captured["results"] if item["case_id"] == "B02"
            )
            self.assertEqual(failed["result_type"], "failed")
            reservation = json.loads(
                (
                    semantic_root
                    / "reports"
                    / "blind_retest_3c_real_call_reservation.json"
                ).read_text(encoding="utf-8")
            )
            self.assertEqual(reservation["attempted_case_ids"], list(CASE_ORDER))
            self.assertEqual(reservation["attempts_reserved"], 4)
            self.assertEqual(reservation["actual_calls_observed"], 4)
            self.assertEqual(reservation["status"], "closed_pending_human_review")


class BlindRetest3CReportingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.expected = load_expected(EXPECTED_PATH, RUBRIC_PATH)

    def _publish_pending(
        self,
        temp: str,
        *,
        actual_calls: int = 4,
        duplicate_provider_ids: bool = False,
    ) -> tuple[Path, Path, str, list[dict], dict]:
        repository_root = Path(temp) / "repo"
        semantic_root = repository_root / "tools" / "semantic"
        run_id = "blind-retest-3c-20260803T000000000000Z-feedface"
        output_run = semantic_root / "output" / "blind_retest_3c" / run_id
        results = [_result_record(case_id) for case_id in CASE_ORDER]
        if duplicate_provider_ids:
            for result in results:
                result["request_id"] = "msg-duplicate"
        scores = [_score(case_id, self.expected) for case_id in CASE_ORDER]
        for result in results:
            case_root = output_run / result["case_id"]
            case_root.mkdir(parents=True)
            (case_root / "result.json").write_text(
                json.dumps(result, ensure_ascii=False) + "\n", encoding="utf-8"
            )
        reservation = (
            semantic_root / "reports" / "blind_retest_3c_real_call_reservation.json"
        )
        reservation.parent.mkdir(parents=True)
        reservation.write_text(
            json.dumps(
                {
                    "run_id": run_id,
                    "status": "closed_pending_human_review",
                    "attempts_reserved": 4,
                    "actual_calls_observed": actual_calls,
                    "attempted_case_ids": list(CASE_ORDER),
                    "model_id": runner.FROZEN_MODEL_ID,
                }
            )
            + "\n",
            encoding="utf-8",
        )
        hashes = {
            "blind_definition_sha256": "a" * 64,
            "blind_cases_sha256": "b" * 64,
            "blind_expected_sha256": _sha256(EXPECTED_PATH),
            "blind_review_rubric_sha256": _sha256(RUBRIC_PATH),
        }
        with mock.patch.object(reporting, "scan_repository", return_value=[]):
            pending_result = reporting.write_pending_blind_retest_3c_review(
                semantic_root=semantic_root,
                repository_root=repository_root,
                run_id=run_id,
                model_id=runner.FROZEN_MODEL_ID,
                results=results,
                scores=scores,
                output_run_directory=output_run,
                reservation_path=reservation,
                actual_call_count=actual_calls,
                configuration_hashes=hashes,
                configuration_snapshot={"snapshot_sha256": "c" * 64, "files": {}},
                preflight={
                    "approved_config_manifest_sha256": "d" * 64,
                    "source_3b_evidence_sha256": runner.SOURCE_3B_EVIDENCE_SHA256,
                },
            )
        self.assertEqual(pending_result["status"], "PENDING_HUMAN_REVIEW")
        return semantic_root, repository_root, run_id, scores, hashes

    def _submission(
        self, semantic_root: Path, run_id: str, scores: list[dict], hashes: dict
    ) -> dict:
        pending = semantic_root / "reports" / "blind_retest_3c_pending" / run_id
        complete = json.loads(
            (pending / "PENDING_COMPLETE.json").read_text(encoding="utf-8")
        )
        return {
            "review_batch_version": reporting.REVIEW_BATCH_VERSION,
            "run_id": run_id,
            "pending_evidence_sha256": complete["pending_evidence_sha256"],
            "expected_sha256": hashes["blind_expected_sha256"],
            "review_rubric_sha256": hashes["blind_review_rubric_sha256"],
            "reviewer": "offline human reviewer",
            "cases": {
                score["case_id"]: _case_review(
                    score["manual_structure_review_packet"]
                )
                for score in scores
            },
        }

    def test_two_stage_publication_is_bound_atomic_and_non_overwriting(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            semantic_root, repository_root, run_id, scores, hashes = (
                self._publish_pending(temp)
            )
            pending = semantic_root / "reports" / "blind_retest_3c_pending" / run_id
            self.assertTrue((pending / "PENDING_COMPLETE.json").is_file())
            template = json.loads(
                (pending / "human_review_submission_template.json").read_text(
                    encoding="utf-8"
                )
            )
            self.assertEqual(
                template["pending_evidence_sha256"], "REPLACE_FROM_PENDING_COMPLETE"
            )
            self.assertFalse(
                (semantic_root / "reports" / "blind_retest_3c" / run_id).exists()
            )
            self.assertFalse(
                (semantic_root / "reports" / "BLIND_RETEST_3C_REPORT.md").exists()
            )

            bad_path = Path(temp) / "bad-review.json"
            bad_submission = self._submission(semantic_root, run_id, scores, hashes)
            bad_submission["pending_evidence_sha256"] = "0" * 64
            bad_path.write_text(json.dumps(bad_submission), encoding="utf-8")
            with self.assertRaises(reporting.BlindRetest3CReportingError):
                reporting.finalize_blind_retest_3c_review(
                    semantic_root=semantic_root,
                    repository_root=repository_root,
                    run_id=run_id,
                    review_path=bad_path,
                )
            self.assertFalse(
                (semantic_root / "reports" / "blind_retest_3c" / run_id).exists()
            )

            review_path = Path(temp) / "human-review.json"
            review_path.write_text(
                json.dumps(
                    self._submission(semantic_root, run_id, scores, hashes),
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )
            with mock.patch.object(reporting, "scan_repository", return_value=[]):
                summary = reporting.finalize_blind_retest_3c_review(
                    semantic_root=semantic_root,
                    repository_root=repository_root,
                    run_id=run_id,
                    review_path=review_path,
                )
            self.assertEqual(summary["status"], "PASS")
            self.assertEqual(summary["call_count"], 4)
            self.assertEqual(summary["metrics"]["key_leak_count"], 0)
            self.assertEqual(summary["review_submission_sha256"], _sha256(review_path))
            final = semantic_root / "reports" / "blind_retest_3c" / run_id
            self.assertTrue((final / "COMPLETE.json").is_file())
            self.assertEqual(
                (final / "review_submission.json").read_bytes(), review_path.read_bytes()
            )
            human_rows = (
                (final / "human_structure_review.csv")
                .read_text(encoding="utf-8")
                .splitlines()
            )
            self.assertEqual(len(human_rows), 13)  # header plus 12 frozen concepts
            for name in (
                "BLIND_RETEST_3C_REPORT.md",
                "blind_retest_3c_results.csv",
                "blind_retest_3c_summary.json",
                "human_structure_review.csv",
            ):
                archive_file = final / name
                convenience = semantic_root / "reports" / name
                self.assertEqual(archive_file.read_bytes(), convenience.read_bytes())
                self.assertNotEqual(os.stat(archive_file).st_ino, os.stat(convenience).st_ino)

            convenience_mtimes = {
                name: (semantic_root / "reports" / name).stat().st_mtime_ns
                for name in (
                    "BLIND_RETEST_3C_REPORT.md",
                    "blind_retest_3c_results.csv",
                    "blind_retest_3c_summary.json",
                    "human_structure_review.csv",
                )
            }
            with mock.patch.object(reporting, "scan_repository", return_value=[]):
                repeated = reporting.finalize_blind_retest_3c_review(
                    semantic_root=semantic_root,
                    repository_root=repository_root,
                    run_id=run_id,
                    review_path=review_path,
                )
            self.assertEqual(repeated, summary)
            self.assertEqual(
                convenience_mtimes,
                {
                    name: (semantic_root / "reports" / name).stat().st_mtime_ns
                    for name in convenience_mtimes
                },
            )

    def test_pending_archive_is_not_overwritten(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            semantic_root, repository_root, run_id, scores, hashes = (
                self._publish_pending(temp)
            )
            output_run = semantic_root / "output" / "blind_retest_3c" / run_id
            reservation = (
                semantic_root
                / "reports"
                / "blind_retest_3c_real_call_reservation.json"
            )
            results = [
                json.loads(
                    (output_run / case_id / "result.json").read_text(encoding="utf-8")
                )
                for case_id in CASE_ORDER
            ]
            with mock.patch.object(reporting, "scan_repository", return_value=[]):
                with self.assertRaises(reporting.BlindRetest3CReportingError):
                    reporting.write_pending_blind_retest_3c_review(
                        semantic_root=semantic_root,
                        repository_root=repository_root,
                        run_id=run_id,
                        model_id=runner.FROZEN_MODEL_ID,
                        results=results,
                        scores=scores,
                        output_run_directory=output_run,
                        reservation_path=reservation,
                        actual_call_count=4,
                        configuration_hashes=hashes,
                        configuration_snapshot={
                            "snapshot_sha256": "c" * 64,
                            "files": {},
                        },
                        preflight={
                            "approved_config_manifest_sha256": "d" * 64,
                            "source_3b_evidence_sha256": runner.SOURCE_3B_EVIDENCE_SHA256,
                        },
                    )

    def test_final_pass_requires_four_observed_calls_and_unique_responses(self) -> None:
        for options in (
            {"actual_calls": 3},
            {"duplicate_provider_ids": True},
        ):
            with self.subTest(options=options), tempfile.TemporaryDirectory() as temp:
                semantic_root, repository_root, run_id, scores, hashes = (
                    self._publish_pending(temp, **options)
                )
                review_path = Path(temp) / "human-review.json"
                review_path.write_text(
                    json.dumps(
                        self._submission(semantic_root, run_id, scores, hashes),
                        ensure_ascii=False,
                    ),
                    encoding="utf-8",
                )
                with mock.patch.object(reporting, "scan_repository", return_value=[]):
                    try:
                        result = reporting.finalize_blind_retest_3c_review(
                            semantic_root=semantic_root,
                            repository_root=repository_root,
                            run_id=run_id,
                            review_path=review_path,
                        )
                    except reporting.BlindRetest3CReportingError:
                        continue
                self.assertNotEqual(result["status"], "PASS")

    def test_human_review_is_read_hashed_and_archived_from_one_byte_snapshot(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            semantic_root, repository_root, run_id, scores, hashes = (
                self._publish_pending(temp)
            )
            review_path = Path(temp) / "human-review.json"
            review_path.write_text(
                json.dumps(
                    self._submission(semantic_root, run_id, scores, hashes),
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )
            original_sha256 = reporting._sha256

            def reject_separate_review_hash(path: Path) -> str:
                if Path(path).resolve() == review_path.resolve():
                    raise AssertionError("review path was re-read for hashing")
                return original_sha256(path)

            with (
                mock.patch.object(reporting, "scan_repository", return_value=[]),
                mock.patch.object(
                    reporting, "_sha256", side_effect=reject_separate_review_hash
                ),
            ):
                summary = reporting.finalize_blind_retest_3c_review(
                    semantic_root=semantic_root,
                    repository_root=repository_root,
                    run_id=run_id,
                    review_path=review_path,
                )
            self.assertEqual(summary["status"], "PASS")
            archived = (
                semantic_root
                / "reports"
                / "blind_retest_3c"
                / run_id
                / "review_submission.json"
            )
            self.assertEqual(archived.read_bytes(), review_path.read_bytes())

    def test_convenience_failure_recovers_only_from_verified_archive(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            semantic_root, repository_root, run_id, scores, hashes = (
                self._publish_pending(temp)
            )
            review_path = Path(temp) / "human-review.json"
            review_path.write_text(
                json.dumps(
                    self._submission(semantic_root, run_id, scores, hashes),
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )
            original_publish = reporting._publish_independent_copy
            publish_count = 0

            def fail_second(source: Path, destination: Path) -> None:
                nonlocal publish_count
                publish_count += 1
                if publish_count == 2:
                    raise reporting.BlindRetest3CReportingError(
                        "simulated convenience publication failure"
                    )
                original_publish(source, destination)

            with (
                mock.patch.object(reporting, "scan_repository", return_value=[]),
                mock.patch.object(
                    reporting, "_publish_independent_copy", side_effect=fail_second
                ),
            ):
                with self.assertRaises(reporting.BlindRetest3CReportingError):
                    reporting.finalize_blind_retest_3c_review(
                        semantic_root=semantic_root,
                        repository_root=repository_root,
                        run_id=run_id,
                        review_path=review_path,
                    )
            final = semantic_root / "reports" / "blind_retest_3c" / run_id
            self.assertTrue((final / "COMPLETE.json").is_file())
            report_path = semantic_root / "reports" / "BLIND_RETEST_3C_REPORT.md"
            self.assertTrue(report_path.is_file())
            report_bytes = report_path.read_bytes()
            report_mtime = report_path.stat().st_mtime_ns

            with mock.patch.object(reporting, "scan_repository", return_value=[]):
                recovered = reporting.finalize_blind_retest_3c_review(
                    semantic_root=semantic_root,
                    repository_root=repository_root,
                    run_id=run_id,
                    review_path=review_path,
                )
            self.assertEqual(recovered["status"], "PASS")
            for name in (
                "BLIND_RETEST_3C_REPORT.md",
                "blind_retest_3c_results.csv",
                "blind_retest_3c_summary.json",
                "human_structure_review.csv",
            ):
                convenience = semantic_root / "reports" / name
                archive_file = final / name
                self.assertTrue(convenience.is_file())
                self.assertEqual(convenience.read_bytes(), archive_file.read_bytes())
            self.assertEqual(report_path.read_bytes(), report_bytes)
            self.assertEqual(report_path.stat().st_mtime_ns, report_mtime)

            # Recovery must never overwrite an existing convenience file whose
            # bytes do not match the already verified archive source of truth.
            summary_path = semantic_root / "reports" / "blind_retest_3c_summary.json"
            summary_path.write_text('{"tampered":true}\n', encoding="utf-8")
            with mock.patch.object(reporting, "scan_repository", return_value=[]):
                with self.assertRaises(reporting.BlindRetest3CReportingError):
                    reporting.finalize_blind_retest_3c_review(
                        semantic_root=semantic_root,
                        repository_root=repository_root,
                        run_id=run_id,
                        review_path=review_path,
                    )
            self.assertEqual(summary_path.read_text(encoding="utf-8"), '{"tampered":true}\n')


class BlindRetest3CScriptSecurityTests(unittest.TestCase):
    def test_scripts_keep_credentials_out_of_tests_preflight_and_finalizer(self) -> None:
        scripts = SEMANTIC_ROOT / "scripts"
        interactive = (scripts / "run_blind_retest_3c_interactive.ps1").read_text(
            encoding="utf-8"
        )
        noninteractive = (scripts / "run_blind_retest_3c.ps1").read_text(
            encoding="utf-8"
        )
        finalize = (scripts / "finalize_blind_retest_3c_review.ps1").read_text(
            encoding="utf-8"
        )
        invoke = (scripts / "invoke_blind_retest_3c_core.ps1").read_text(
            encoding="utf-8"
        )

        self.assertLess(interactive.index("--preflight-only"), interactive.index("Read-Host"))
        self.assertIn("-AsSecureString", interactive)
        self.assertIn("SecureStringToBSTR", interactive)
        self.assertIn("ZeroFreeBSTR", interactive)
        self.assertIn("Remove-Item Env:ANTHROPIC_API_KEY", interactive)

        remove_index = noninteractive.index("Remove-Item Env:ANTHROPIC_API_KEY")
        test_index = noninteractive.index("test_semantic.ps1")
        restore_index = noninteractive.index("$env:ANTHROPIC_API_KEY = $processApiKey")
        core_index = noninteractive.index("invoke_blind_retest_3c_core.ps1")
        self.assertLess(remove_index, test_index)
        self.assertLess(test_index, restore_index)
        self.assertLess(restore_index, core_index)
        self.assertIn("finally", noninteractive)
        self.assertIn("Remove-Item Env:ANTHROPIC_API_KEY", finalize)
        self.assertIn("ANTHROPIC_API_KEY is missing", invoke)

    def test_no_force_new_run_dotenv_or_forbidden_launches(self) -> None:
        paths = [
            SEMANTIC_ROOT / "bridge" / "blind_retest_3c_runner.py",
            SEMANTIC_ROOT / "bridge" / "blind_retest_3c_reporting.py",
            *(SEMANTIC_ROOT / "scripts").glob("*blind_retest_3c*.ps1"),
        ]
        combined = "\n".join(path.read_text(encoding="utf-8") for path in paths)
        lowered = combined.casefold()
        self.assertNotIn("forcenewrun", lowered)
        # ``os.environ`` and PowerShell's ``Env:`` are process-local storage,
        # not a dotenv file.  Reject an actual quoted ``.env`` path/name.
        self.assertIsNone(re.search(r'''["']\.env(?:["'/\\]|$)''', lowered))
        self.assertFalse(
            any(path.name.casefold() == ".env" for path in SEMANTIC_ROOT.rglob("*") if path.is_file())
        )
        # Report provenance must mention these systems, but no launcher command
        # may target them and every persisted execution attestation stays false.
        self.assertIsNone(
            re.search(r"(?:start-process|python(?:\.exe)?)[^\n]*comfyui", lowered)
        )
        self.assertNotIn('"gate_b_executed": true', lowered)
        self.assertNotIn('"comfyui_started": true', lowered)
        self.assertNotIn('"v2_started": true', lowered)


if __name__ == "__main__":
    unittest.main(verbosity=2)
