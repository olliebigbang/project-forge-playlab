from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))

import gate_b_4b_finalize as finalize  # noqa: E402
import gate_b_4b_runner as runner  # noqa: E402


RUN_ID = "gate-b-4b-20260803T113856150162Z-602df44f"
RUN_ROOT = ROOT / "output" / RUN_ID
PACKET_ROOT = ROOT / "review_packets" / RUN_ID
PROPOSED_REVIEW = PACKET_ROOT / "independent_visual_observation.proposed.csv"


def confirmed_review_bytes() -> bytes:
    return PROPOSED_REVIEW.read_bytes().replace(
        b"Codex independent visual observation - NOT HUMAN REVIEW",
        b"Eddie L",
    )


class GateB4BFinalizeTests(unittest.TestCase):
    def test_non_human_observation_cannot_be_finalized_as_human_review(self) -> None:
        rubric = json.loads(finalize.RUBRIC_PATH.read_text(encoding="utf-8"))
        with self.assertRaisesRegex(finalize.FinalizeError, "HUMAN_REVIEWER_NOT_HUMAN"):
            finalize.validate_human_structure_review(PROPOSED_REVIEW.read_bytes(), rubric)

    def test_confirmed_review_evaluates_strict_actual_thresholds(self) -> None:
        rubric = json.loads(finalize.RUBRIC_PATH.read_text(encoding="utf-8"))
        rows = finalize.validate_human_structure_review(confirmed_review_bytes(), rubric)
        summary = json.loads((RUN_ROOT / "run_summary.json").read_text(encoding="utf-8"))
        frozen = json.loads(finalize.FROZEN_PATH.read_text(encoding="utf-8"))
        result = finalize.evaluate_thresholds(RUN_ROOT, summary, rows, frozen)
        self.assertEqual(result["status"], "NEEDS WORK")
        self.assertEqual(result["technical_alpha_success_count"], 8)
        self.assertEqual(result["usable_alpha_count"], 4)
        self.assertEqual(result["fake_transparent_count"], 0)
        self.assertEqual(result["serious_subject_missing_count"], 4)
        self.assertEqual(result["raw_identity_recognizable_count"], 6)
        self.assertEqual(result["raw_identity_preserved_at_96_count"], 5)
        self.assertFalse(result["gates"]["b01_hose_and_nozzle_preserved_both_seeds"])
        self.assertTrue(result["gates"]["b03_seed_4041001_remains_usable"])
        self.assertFalse(result["gates"]["b04_stem_and_base_preserved_both_seeds"])

    def test_full_report_packet_is_atomic_and_does_not_modify_frozen_4a(self) -> None:
        before = runner.sha256_file(finalize.FROZEN_PATH)
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            review = temp / "confirmed.csv"
            review.write_bytes(confirmed_review_bytes())
            reports = temp / "reports"
            result = finalize.finalize_gate_b_4b(
                run_root=RUN_ROOT,
                packet_root=PACKET_ROOT,
                human_review_path=review,
                reports_root=reports,
            )
            report_root = reports / RUN_ID
            self.assertEqual(result["status"], "NEEDS WORK")
            self.assertTrue(report_root.is_dir())
            expected = {
                *finalize.ASSET_NAMES,
                "human_structure_review.csv",
                "GATE_B_4B_REPORT.md",
                "gate_b_4b_summary.json",
                "evidence_hashes.json",
            }
            self.assertEqual({path.name for path in report_root.iterdir() if path.is_file()}, expected)
            ledger = json.loads((report_root / "evidence_hashes.json").read_text(encoding="utf-8"))
            self.assertEqual(ledger["source_gate_4a_status"], "NEEDS WORK")
            self.assertEqual(ledger["preflight"]["gate_4a"]["frozen_changed_count"], 0)
            self.assertEqual(ledger["preflight"]["gate_4a"]["frozen_missing_count"], 0)
            self.assertGreater(ledger["preflight"]["gate_4a"]["post_freeze_sidecar_count"], 0)
            self.assertTrue(
                all(
                    item["path"].endswith(finalize.ALLOWED_POST_FREEZE_GODOT_SIDECAR_SUFFIXES)
                    for item in ledger["preflight"]["gate_4a"]["post_freeze_sidecars"]
                )
            )
            self.assertEqual(ledger["preflight"]["gameplay"]["missing_count"], 0)
            self.assertEqual(ledger["preflight"], ledger["postflight"])
            with self.assertRaisesRegex(finalize.FinalizeError, "REPORT_DIRECTORY_EXISTS"):
                finalize.finalize_gate_b_4b(
                    run_root=RUN_ROOT,
                    packet_root=PACKET_ROOT,
                    human_review_path=review,
                    reports_root=reports,
                )
            self.assertEqual(list(reports.glob(f".{RUN_ID}.tmp-*")), [])
        self.assertEqual(runner.sha256_file(finalize.FROZEN_PATH), before)

    def test_finalizer_has_no_external_service_or_process_launch_capability(self) -> None:
        source = Path(finalize.__file__).read_text(encoding="utf-8").lower()
        forbidden = (
            "import requests",
            "import urllib",
            "import socket",
            "import subprocess",
            "http://",
            "https://",
            "anthropic.messages",
            "popen(",
        )
        self.assertFalse([token for token in forbidden if token in source])


if __name__ == "__main__":
    unittest.main()
