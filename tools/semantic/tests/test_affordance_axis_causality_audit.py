from __future__ import annotations

import inspect
import json
from pathlib import Path
import sys
import tempfile
import unittest

BRIDGE = Path(__file__).resolve().parents[1] / "bridge"
sys.path.insert(0, str(BRIDGE))

import affordance_axis_causality_audit as audit


class AffordanceAxisCausalityAuditTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.repo = Path(__file__).resolve().parents[3]
        cls.temporary = tempfile.TemporaryDirectory()
        cls.output = Path(cls.temporary.name) / "axis-audit"
        cls.summary = audit.run_audit(cls.repo, cls.output)
        cls.raw = json.loads((cls.output / "axis_probe_output.json").read_text(encoding="utf-8"))

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def test_export_uses_one_anonymous_baseline_and_twenty_five_probes(self) -> None:
        self.assertFalse(self.raw["identity_inputs_used"])
        self.assertEqual(len(self.raw["scenarios"]), 25)
        serialized = json.dumps(self.raw, ensure_ascii=False).lower()
        for forbidden in ("frying_pan", "old_mop", "shotgun_melee", "display_name", "canonical_name", "prompt_zh"):
            self.assertNotIn(forbidden, serialized)

    def test_non_mechanical_controls_are_invariant(self) -> None:
        self.assertEqual(self.summary["invariant_probe_count"], 2)
        self.assertEqual(self.summary["invariant_pass_count"], 2)
        self.assertEqual(self.summary["failed_invariant_probe_ids"], [])

    def test_every_mechanism_probe_changes_runtime_without_score_only_credit(self) -> None:
        self.assertEqual(self.summary["status"], "PASS")
        self.assertEqual(self.summary["mechanism_runtime_effect_count"], 23)
        self.assertEqual(self.summary["mechanism_score_only_masked_count"], 0)
        self.assertEqual(self.summary["mechanism_silent_count"], 0)
        self.assertEqual(self.summary["failed_mechanism_probe_ids"], [])

    def test_previously_masked_axes_now_change_consumed_runtime_parameters(self) -> None:
        rows = {row["id"]: row for row in self.summary["rows"]}
        for probe_id in (
            "grip_clamp",
            "rigidity_semi",
            "secondary_edge",
            "secondary_broad",
            "secondary_whole_body",
            "feature_point",
            "feature_edge",
            "feature_broad_face",
        ):
            self.assertTrue(rows[probe_id]["runtime_effect"], probe_id)
            self.assertEqual(rows[probe_id]["classification"], "PARAMETER_EFFECT", probe_id)

    def test_runtime_effects_include_parameter_only_changes(self) -> None:
        rows = {row["id"]: row for row in self.summary["rows"]}
        self.assertTrue(rows["handle_long"]["runtime_effect"])
        self.assertFalse(rows["handle_long"]["sequence_effect"])
        self.assertEqual(rows["handle_long"]["classification"], "PARAMETER_EFFECT")
        self.assertTrue(rows["primary_point"]["sequence_effect"])
        self.assertEqual(rows["primary_point"]["classification"], "SEQUENCE_EFFECT")

    def test_audit_evidence_self_verifies(self) -> None:
        evidence = json.loads((self.output / "evidence_hashes.json").read_text(encoding="utf-8"))
        import hashlib

        for relative, expected in evidence["files"].items():
            self.assertEqual(hashlib.sha256((self.output / relative).read_bytes()).hexdigest(), expected)
        complete = json.loads((self.output / "COMPLETE.json").read_text(encoding="utf-8"))
        self.assertEqual(complete["evidence_sha256"], hashlib.sha256((self.output / "evidence_hashes.json").read_bytes()).hexdigest())

    def test_runner_contains_no_provider_or_network_client(self) -> None:
        source = inspect.getsource(audit)
        self.assertNotIn("AnthropicSemanticCompiler", source)
        self.assertNotIn("requests", source)
        self.assertNotIn("urllib", source)
        self.assertNotIn("http://", source)
        self.assertNotIn("https://", source)


if __name__ == "__main__":
    unittest.main()
