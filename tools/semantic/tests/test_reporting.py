from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path


SEMANTIC_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SEMANTIC_ROOT / "bridge"))

from gate_a_reporting import calculate_cost, write_gate_a_reports  # noqa: E402


def _fixture_results() -> tuple[list[dict], list[dict]]:
    results: list[dict] = []
    scores: list[dict] = []
    for index in range(1, 21):
        case_id = f"case_{index:02d}"
        clarification = index in (17, 18)
        result_type = "needs_clarification" if clarification else "compiled"
        results.append(
            {
                "case_id": case_id,
                "api_status": 200,
                "provider": "anthropic",
                "ai_interpretation_used": True,
                "contract_version": "forge-semantic-v1.1",
                "model_id": "exact-user-model",
                "request_id": f"msg-{index:02d}",
                "result_type": result_type,
                "result": {"question_zh": "请澄清"} if clarification else {"identity": {}},
                "input_tokens": 10,
                "output_tokens": 5,
                "elapsed_ms": 20,
                "retry_count": 0,
                "usage": {"input_tokens": 10, "output_tokens": 5},
                "raw_response_redacted": {"id": case_id},
            }
        )
        scores.append(
            {
                "case_id": case_id,
                "schema_valid": True,
                "identity_correct": not clarification,
                "behavior_correct": not clarification,
                "preserved_features_quality": 0 if clarification else 2,
                "clarification_correct": clarification,
                "fixed_weapon_substitution": False,
                "reviewer_reason": "fixture",
            }
        )
    return results, scores


def _write_reservation(semantic_root: Path, run_id: str = "run") -> None:
    reports = semantic_root / "reports"
    reports.mkdir(parents=True, exist_ok=True)
    (reports / "gate_a_real_call_reservation.json").write_text(
        json.dumps(
            {
                "contract_version": "forge-semantic-v1.1",
                "run_id": run_id,
                "status": "requests_complete",
                "max_real_calls": 20,
                "attempts_reserved": 20,
                "actual_calls_observed": 20,
            }
        ),
        encoding="utf-8",
    )


class GateAReportingTests(unittest.TestCase):
    def test_cost_requires_both_user_supplied_rates(self) -> None:
        self.assertEqual(
            calculate_cost(100, 50, {})["status"],
            "COST_NOT_CALCULATED — TOKEN_USAGE_ONLY",
        )
        calculated = calculate_cost(
            1_000_000,
            2_000_000,
            {
                "FORGE_SEMANTIC_INPUT_PRICE_PER_M": "1.25",
                "FORGE_SEMANTIC_OUTPUT_PRICE_PER_M": "2.50",
            },
        )
        self.assertEqual(calculated["estimated_cost"], "6.250000")

    def test_passing_fixture_writes_atomic_reports_and_hashes(self) -> None:
        results, scores = _fixture_results()
        with tempfile.TemporaryDirectory() as directory:
            semantic_root = Path(directory)
            _write_reservation(semantic_root)
            output_run = semantic_root / "output" / "gate_a" / "run"
            for result in results:
                case_directory = output_run / result["case_id"]
                case_directory.mkdir(parents=True)
                (case_directory / "result.json").write_text(
                    json.dumps(result, ensure_ascii=False),
                    encoding="utf-8",
                )
            summary = write_gate_a_reports(
                semantic_root=semantic_root,
                run_id="run",
                model_id="exact-user-model",
                results=results,
                scores=scores,
                output_run_directory=output_run,
                secret_scan_passed=True,
                actual_call_count=20,
                scope_unchanged=True,
            )
            self.assertEqual(summary["status"], "GATE A PASS")
            self.assertEqual(summary["call_count"], 20)
            self.assertEqual(summary["automatic_retry_count"], 0)
            evidence = json.loads(
                (semantic_root / "reports" / "evidence_hashes.json").read_text(encoding="utf-8")
            )
            self.assertGreaterEqual(len(evidence["files"]), 43)
            self.assertNotIn("api_key", json.dumps(summary).lower())
            complete = json.loads(
                (
                    semantic_root / "reports" / "runs" / "run" / "COMPLETE.json"
                ).read_text(encoding="utf-8")
            )
            self.assertEqual(complete["status"], "complete")
            with self.assertRaisesRegex(FileExistsError, "IMMUTABLE_GATE_A_RUN_REPORT"):
                write_gate_a_reports(
                    semantic_root=semantic_root,
                    run_id="run",
                    model_id="exact-user-model",
                    results=results,
                    scores=scores,
                    output_run_directory=output_run,
                    secret_scan_passed=True,
                    actual_call_count=20,
                    scope_unchanged=True,
                )

    def test_mock_attestation_cannot_pass_even_with_twenty_fixture_rows(self) -> None:
        results, scores = _fixture_results()
        with tempfile.TemporaryDirectory() as directory:
            semantic_root = Path(directory)
            output_run = semantic_root / "output" / "gate_a" / "run"
            for result in results:
                case_directory = output_run / result["case_id"]
                case_directory.mkdir(parents=True)
                (case_directory / "result.json").write_text(
                    json.dumps(result, ensure_ascii=False), encoding="utf-8"
                )
            summary = write_gate_a_reports(
                semantic_root=semantic_root,
                run_id="run",
                model_id="exact-user-model",
                results=results,
                scores=scores,
                output_run_directory=output_run,
                secret_scan_passed=True,
                actual_call_count=20,
                scope_unchanged=True,
            )
            self.assertEqual(summary["status"], "NEEDS WORK")
            self.assertFalse(summary["real_ai_calls_performed"])

    def test_boolean_attestation_cannot_hide_a_missing_provider_envelope(self) -> None:
        results, scores = _fixture_results()
        results[0].pop("provider")
        with tempfile.TemporaryDirectory() as directory:
            semantic_root = Path(directory)
            _write_reservation(semantic_root)
            output_run = semantic_root / "output" / "gate_a" / "run"
            for result in results:
                case_directory = output_run / result["case_id"]
                case_directory.mkdir(parents=True)
                (case_directory / "result.json").write_text(
                    json.dumps(result, ensure_ascii=False), encoding="utf-8"
                )
            summary = write_gate_a_reports(
                semantic_root=semantic_root,
                run_id="run",
                model_id="exact-user-model",
                results=results,
                scores=scores,
                output_run_directory=output_run,
                secret_scan_passed=True,
                actual_call_count=20,
                scope_unchanged=True,
            )
            self.assertEqual(summary["status"], "NEEDS WORK")
            self.assertEqual(summary["attested_anthropic_envelope_count"], 19)

    def test_failed_pre_publish_scan_never_publishes_a_pass_report(self) -> None:
        results, scores = _fixture_results()
        with tempfile.TemporaryDirectory() as directory:
            semantic_root = Path(directory)
            _write_reservation(semantic_root)
            output_run = semantic_root / "output" / "gate_a" / "run"
            for result in results:
                case_directory = output_run / result["case_id"]
                case_directory.mkdir(parents=True)
                (case_directory / "result.json").write_text(
                    json.dumps(result, ensure_ascii=False), encoding="utf-8"
                )
            with self.assertRaisesRegex(PermissionError, "PRE_PUBLISH_SECRET_SCAN"):
                write_gate_a_reports(
                    semantic_root=semantic_root,
                    run_id="run",
                    model_id="exact-user-model",
                    results=results,
                    scores=scores,
                    output_run_directory=output_run,
                    secret_scan_passed=True,
                    actual_call_count=20,
                    scope_unchanged=True,
                    pre_publish_validator=lambda _pending: False,
                )
            self.assertFalse((semantic_root / "reports" / "gate_a_summary.json").exists())
            run_reports = semantic_root / "reports" / "runs" / "run"
            self.assertFalse((run_reports / ".pending").exists())
            blocked = json.loads(
                (run_reports / "PUBLISH_BLOCKED.json").read_text(encoding="utf-8")
            )
            self.assertEqual(blocked["status"], "NEEDS WORK")
            self.assertEqual(blocked["reason"], "PRE_PUBLISH_SECRET_SCAN_FAILED")


if __name__ == "__main__":
    unittest.main()
