from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
MODULE_PATH = ROOT / "tools" / "semantic" / "bridge" / "generalization_v3_matrix.py"
MANIFEST_PATH = ROOT / "data" / "sunny_generalization_matrix_v3.json"
SPEC = importlib.util.spec_from_file_location("generalization_v3_matrix", MODULE_PATH)
assert SPEC and SPEC.loader
MATRIX = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MATRIX)


class GeneralizationV3MatrixTests(unittest.TestCase):
    def setUp(self) -> None:
        self.manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))

    def test_frozen_lcg_selection_covers_twelve_distinct_groups(self) -> None:
        samples = MATRIX.validate_manifest(self.manifest)
        self.assertEqual(len(samples), 12)
        self.assertEqual(len({sample["group"] for sample in samples}), 12)
        self.assertEqual(MATRIX.selected_indices(20260904, 12), [3, 2, 1, 0, 3, 2, 1, 0, 3, 2, 1, 0])

    def test_tampered_frozen_selection_is_rejected(self) -> None:
        changed = copy.deepcopy(self.manifest)
        changed["samples"][2]["candidate_index"] = 0
        with self.assertRaisesRegex(MATRIX.MatrixError, "MATRIX_FROZEN_SELECTION_MISMATCH"):
            MATRIX.validate_manifest(changed)

    def test_supported_record_requires_classification_and_group_axis_evidence(self) -> None:
        sample = MATRIX.validate_manifest(self.manifest)[2]
        result = {"status": "success", "response": {"classification": MATRIX.SUPPORTED, "declaration": {"handle_length": "long"}}}
        self.assertTrue(MATRIX.evaluate_record(sample, result)["passed"])
        result["response"]["declaration"]["handle_length"] = "short"
        checked = MATRIX.evaluate_record(sample, result)
        self.assertFalse(checked["passed"])
        self.assertEqual(checked["mismatches"][0]["path"], "declaration.handle_length")

    def test_sample_filter_is_bounded_and_rejects_unknown_ids(self) -> None:
        samples = MATRIX.validate_manifest(self.manifest)
        selected = MATRIX.select_samples(samples, "v3-05,v3-07")
        self.assertEqual([sample["id"] for sample in selected], ["v3-05", "v3-07"])
        with self.assertRaisesRegex(MATRIX.MatrixError, "MATRIX_SAMPLE_ID_UNKNOWN"):
            MATRIX.select_samples(samples, "v3-99")

    def test_boundary_requires_an_explicit_safe_route(self) -> None:
        sample = MATRIX.validate_manifest(self.manifest)[-1]
        routed = {"status": "success", "response": {"classification": "living_actor_required", "declaration": {}}}
        self.assertTrue(MATRIX.evaluate_record(sample, routed)["passed"])
        improvised = {"status": "success", "response": {"classification": MATRIX.SUPPORTED, "declaration": {"rigidity": "rigid"}}}
        self.assertFalse(MATRIX.evaluate_record(sample, improvised)["passed"])

    def test_summary_reports_axis_coverage_and_duplicate_directions(self) -> None:
        base = {"policy": "supported_object", "status": "success", "passed": True, "usage": {"input_tokens": 10}, "response": {"declaration": {"body_length": "long", "rigidity": "rigid"}}}
        records = [{**base, "id": "a", "axis_signature": "same"}, {**base, "id": "b", "axis_signature": "same"}]
        summary = MATRIX.summarize(records)
        self.assertEqual(summary["unique_axis_signatures"], 1)
        self.assertEqual(summary["duplicate_axis_signature_groups"], [["a", "b"]])
        self.assertEqual(summary["axis_value_coverage"]["body_length"], ["long"])
        self.assertEqual(summary["usage"]["input_tokens"], 20)

    def test_offline_cli_writes_a_zero_call_plan(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            completed = subprocess.run([sys.executable, "-B", str(MODULE_PATH), "--manifest", str(MANIFEST_PATH), "--output-dir", temporary], check=False, capture_output=True, text=True)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            report = json.loads((Path(temporary) / "report.json").read_text(encoding="utf-8"))
            self.assertEqual(report["mode"], "offline_plan")
            self.assertEqual(report["semantic_entry_attempts"], 0)
            self.assertEqual(report["online_visual_requests"], 0)
            self.assertEqual(report["summary"]["sample_count"], 12)

    def test_runner_contains_no_identity_specific_repairs(self) -> None:
        source = MODULE_PATH.read_text(encoding="utf-8")
        for identity in ("手电筒", "网球拍", "灭火器", "Excalibur", "虎斑猫"):
            self.assertNotIn(identity, source)
        self.assertNotIn("if identity ==", source)

    def test_offline_recheck_uses_later_roots_as_bounded_overlays(self) -> None:
        samples = MATRIX.validate_manifest(self.manifest)
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as overlay, tempfile.TemporaryDirectory() as output:
            for sample in samples:
                case = Path(first) / sample["id"]
                case.mkdir(parents=True)
                response = {"classification": MATRIX.SUPPORTED, "declaration": {}}
                if sample["expect"]["policy"] == "safe_route":
                    response["classification"] = "living_actor_required"
                for check in sample["expect"].get("checks", []):
                    response["declaration"][check["path"].split(".")[-1]] = check["in"][0]
                (case / "result.json").write_text(json.dumps({"status": "success", "response": response}), encoding="utf-8")
            replacement = Path(overlay) / "v3-01"
            replacement.mkdir(parents=True)
            (replacement / "result.json").write_text(json.dumps({"status": "failed", "failure_reason": "overlay"}), encoding="utf-8")
            exit_code = MATRIX.run_recheck(MANIFEST_PATH, Path(output), [Path(first), Path(overlay)])
            self.assertEqual(exit_code, 1)
            report = json.loads((Path(output) / "report.json").read_text(encoding="utf-8"))
            self.assertEqual(report["semantic_entry_attempts"], 0)
            self.assertEqual(report["records"][0]["failure_reason"], "overlay")


if __name__ == "__main__":
    unittest.main()
