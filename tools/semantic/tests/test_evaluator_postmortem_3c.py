#!/usr/bin/env python3
"""Offline regression checks for the immutable Evaluator Postmortem 3C."""

from __future__ import annotations

import csv
import hashlib
import json
import unittest
from pathlib import Path
from typing import Any


SEMANTIC_ROOT = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = SEMANTIC_ROOT.parents[1]
SOURCE_RUN_ID = "blind-retest-3c-20260803T060715018997Z-4ddf8f31"
POSTMORTEM_ID = "evaluator-postmortem-3c-20260803T0710367230688Z"
POSTMORTEM_ROOT = (
    SEMANTIC_ROOT / "reports" / "evaluator_postmortem_3c" / POSTMORTEM_ID
)
PENDING_ROOT = (
    SEMANTIC_ROOT / "reports" / "blind_retest_3c_pending" / SOURCE_RUN_ID
)
OUTPUT_ROOT = SEMANTIC_ROOT / "output" / "blind_retest_3c" / SOURCE_RUN_ID


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _object(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise AssertionError(f"expected JSON object: {path}")
    return value


class EvaluatorPostmortem3CSourceEvidenceTests(unittest.TestCase):
    def test_frozen_source_hashes_and_recursive_pending_chain_are_unchanged(self) -> None:
        source = _object(POSTMORTEM_ROOT / "source_evidence_hashes.json")
        self.assertEqual(source["algorithm"], "SHA-256")
        self.assertEqual(source["source_run_id"], SOURCE_RUN_ID)
        self.assertEqual(
            source["source_pending_evidence_sha256"],
            "650c0de04ebe417c822a19d542528908170897047daacefd5e79e589efe74f29",
        )
        for relative, expected in source["files"].items():
            path = REPOSITORY_ROOT / relative
            self.assertTrue(path.is_file(), relative)
            self.assertFalse(path.is_symlink(), relative)
            self.assertEqual(_sha256(path), expected, relative)

        pending_complete = _object(PENDING_ROOT / "PENDING_COMPLETE.json")
        pending_manifest_path = PENDING_ROOT / "pending_evidence_hashes.json"
        pending_manifest = _object(pending_manifest_path)
        self.assertEqual(
            pending_complete["pending_evidence_sha256"], _sha256(pending_manifest_path)
        )
        self.assertEqual(len(pending_manifest["files"]), 43)
        for relative, expected in pending_manifest["files"].items():
            path = SEMANTIC_ROOT / relative
            self.assertTrue(path.is_file(), relative)
            self.assertFalse(path.is_symlink(), relative)
            self.assertEqual(_sha256(path), expected, relative)

    def test_official_automatic_verdict_is_snapshotted_not_recalculated(self) -> None:
        official = _object(POSTMORTEM_ROOT / "official_automatic_verdict.json")
        pending = _object(PENDING_ROOT / "pending_summary.json")
        automatic = pending["automatic_metrics"]
        self.assertEqual(official["source_automatic_status"], "NEEDS WORK")
        self.assertTrue(official["official_verdict_unchanged"])
        self.assertFalse(official["superseded"])
        self.assertFalse(official["recalculated"])
        self.assertEqual(automatic["base_identity_correct_count"], 3)
        self.assertEqual(automatic["behavior_correct_count"], 4)
        self.assertFalse(automatic["automatic_thresholds_passed"])
        self.assertEqual(official["metrics"]["base_identity_correct_count"], 3)
        self.assertEqual(official["metrics"]["behavior_correct_count"], 4)
        self.assertFalse(official["cases"]["B03"]["base_identity_correct"])


class EvaluatorPostmortem3CIndependentReviewTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.review = _object(POSTMORTEM_ROOT / "independent_semantic_review.json")
        cls.packet = _object(PENDING_ROOT / "review_packet.json")

    def test_independent_metrics_meet_the_user_directed_contract(self) -> None:
        metrics = self.review["independent_metrics"]
        self.assertEqual(metrics["identity_correct_count"], 4)
        self.assertEqual(metrics["behavior_correct_count"], 4)
        self.assertEqual(metrics["cases_with_at_least_two_confirmed_structures"], 4)
        self.assertEqual(metrics["structure_quality_2_count"], 4)
        self.assertEqual(metrics["confirmed_structure_concept_count"], 11)
        self.assertEqual(metrics["reviewed_structure_concept_count"], 12)
        self.assertEqual(
            [self.review["cases"][case]["confirmed_structure_count"] for case in ("B01", "B02", "B03", "B04")],
            [3, 3, 2, 3],
        )

    def test_review_quotes_and_concept_ids_are_bound_to_frozen_packet(self) -> None:
        for case_id, case_review in self.review["cases"].items():
            packet = self.packet["cases"][case_id]
            expected_ids = [item["concept_id"] for item in packet["expected_concepts"]]
            reviewed_ids = [item["concept_id"] for item in case_review["structure_reviews"]]
            self.assertEqual(reviewed_ids, expected_ids)
            actual_parts = set(packet["actual_required_identity_parts"])
            for item in case_review["structure_reviews"]:
                quote = item["actual_required_identity_part_quote"]
                if item["same_structure_concept"]:
                    self.assertIsInstance(quote, str)
                    self.assertIn(quote, actual_parts)
                    self.assertTrue(item["structural_not_material_or_decoration"])
                else:
                    self.assertIsNone(quote)
            self.assertGreaterEqual(case_review["confirmed_structure_count"], 2)
            self.assertTrue(case_review["all_required_identity_parts_are_structural"])
            self.assertEqual(case_review["structure_quality"], 2)

    def test_b03_official_false_and_independent_true_coexist(self) -> None:
        official = _object(POSTMORTEM_ROOT / "official_automatic_verdict.json")
        independent = self.review["cases"]["B03"]
        result = _object(OUTPUT_ROOT / "B03" / "result.json")["tool_input_received"]
        self.assertFalse(official["cases"]["B03"]["base_identity_correct"])
        self.assertTrue(independent["identity_correct"])
        self.assertEqual(result["identity"]["canonical_name_zh"], "订书机")
        self.assertEqual(result["identity"]["canonical_name_en"], "stapler")
        self.assertIn("巨型", result["identity"]["display_name_zh"])
        self.assertIn("Giant", result["identity"]["display_name_en"])
        self.assertIn("giant oversized stapler", result["visual"]["prompt_en"])
        cause = independent["identity_failure_root_cause"]
        self.assertEqual(cause["owner"], "frozen_evaluator_expected_identity_policy")
        self.assertFalse(cause["model_semantic_error"])
        self.assertFalse(cause["schema_error"])
        self.assertFalse(cause["parser_error"])

    def test_b04_stem_is_a_structure_and_slender_is_silhouette(self) -> None:
        independent = self.review["cases"]["B04"]
        stem = next(
            item
            for item in independent["structure_reviews"]
            if item["concept_id"] == "goblet_narrow_stem"
        )
        result = _object(OUTPUT_ROOT / "B04" / "result.json")["tool_input_received"]
        self.assertEqual(stem["actual_required_identity_part_quote"], "stem")
        self.assertTrue(stem["same_structure_concept"])
        self.assertIn("stem", result["identity"]["required_identity_parts"])
        self.assertTrue(
            any("slender stem" in value for value in result["identity"]["silhouette_hints"])
        )
        self.assertIn("slender stem", result["visual"]["prompt_en"])

    def test_csv_records_exactly_twelve_user_directed_decisions(self) -> None:
        with (POSTMORTEM_ROOT / "human_structure_review.csv").open(
            encoding="utf-8", newline=""
        ) as handle:
            rows = list(csv.DictReader(handle))
        self.assertEqual(len(rows), 12)
        self.assertEqual(sum(row["confirmed"] == "true" for row in rows), 11)
        rejected = [row for row in rows if row["confirmed"] == "false"]
        self.assertEqual(len(rejected), 1)
        self.assertEqual(rejected[0]["case_id"], "B03")
        self.assertEqual(rejected[0]["concept_id"], "stapler_rear_hinge")

    def test_review_is_data_only_and_gate_b_is_only_recommended(self) -> None:
        self.assertFalse(self.review["runtime_object_mapping_added"])
        self.assertFalse(self.review["second_model_scoring_used"])
        self.assertTrue(self.review["official_automatic_verdict_unchanged"])
        self.assertFalse(self.review["official_automatic_verdict_superseded"])
        recommendation = self.review["gate_b_recommendation"]
        self.assertTrue(recommendation["criteria_confirmed"])
        self.assertTrue(recommendation["recommend_semantic_layer_enter_gate_b"])
        self.assertFalse(recommendation["gate_b_executed"])
        self.assertTrue(recommendation["requires_separate_user_approval"])
        self.assertEqual(self.review["scope"]["external_api_calls_performed"], 0)
        self.assertFalse(self.review["scope"]["comfyui_started"])


class EvaluatorPostmortem3CEvidenceTests(unittest.TestCase):
    def test_new_postmortem_evidence_and_complete_chain_verify(self) -> None:
        evidence_path = POSTMORTEM_ROOT / "evidence_hashes.json"
        evidence = _object(evidence_path)
        complete = _object(POSTMORTEM_ROOT / "COMPLETE.json")
        self.assertEqual(complete["postmortem_id"], POSTMORTEM_ID)
        self.assertEqual(complete["status"], "complete")
        self.assertEqual(complete["evidence_sha256"], _sha256(evidence_path))
        self.assertFalse(complete["gate_b_executed"])
        for relative, expected in evidence["files"].items():
            path = REPOSITORY_ROOT / relative
            self.assertTrue(path.is_file(), relative)
            self.assertFalse(path.is_symlink(), relative)
            self.assertEqual(_sha256(path), expected, relative)


if __name__ == "__main__":
    unittest.main()
