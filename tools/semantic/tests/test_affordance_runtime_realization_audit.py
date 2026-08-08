from __future__ import annotations

import hashlib
import inspect
import json
from pathlib import Path
import sys
import tempfile
import unittest

BRIDGE = Path(__file__).resolve().parents[1] / "bridge"
sys.path.insert(0, str(BRIDGE))

import affordance_runtime_realization_audit as audit


class AffordanceRuntimeRealizationAuditTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.repo = Path(__file__).resolve().parents[3]
        cls.temporary = tempfile.TemporaryDirectory()
        cls.output = Path(cls.temporary.name) / "runtime-realization"
        cls.summary = audit.run_audit(cls.repo, cls.output)
        cls.raw = json.loads((cls.output / "runtime_probe_output.json").read_text(encoding="utf-8"))

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def test_anonymous_probe_executes_existing_runtime_consumers(self) -> None:
        self.assertFalse(self.raw["identity_inputs_used"])
        self.assertFalse(self.raw["runtime_weights_modified"])
        self.assertEqual(self.raw["collision_consumer"], "CombatFeelSlice0._attack_contains")
        self.assertEqual(self.raw["feedback_consumer"], "ImpactFeedbackProfile.for_attack")
        self.assertEqual(len(self.raw["scenarios"]), 25)
        serialized = json.dumps(self.raw["baseline"], ensure_ascii=False).lower()
        for forbidden in ("frying_pan", "old_mop", "shotgun_melee", "display_name", "canonical_name", "prompt_zh"):
            self.assertNotIn(forbidden, serialized)

    def test_every_mechanical_probe_has_an_explicit_runtime_property_contract(self) -> None:
        mechanism_ids = {
            str(record["id"])
            for record in self.raw["scenarios"]
            if record["expected"] == audit.MECHANISM_EXPECTATION
        }
        self.assertEqual(mechanism_ids, set(audit.CONTRACTS))
        self.assertEqual(self.summary["mechanism_probe_count"], 23)

    def test_invariants_are_mechanically_inert(self) -> None:
        self.assertEqual(self.summary["invariant_probe_count"], 2)
        self.assertEqual(self.summary["invariant_pass_count"], 2)
        self.assertEqual(self.summary["failed_invariant_ids"], [])

    def test_generic_correction_closes_all_declared_runtime_properties(self) -> None:
        self.assertEqual(self.summary["status"], "PASS")
        self.assertEqual(self.summary["mechanism_pass_count"], 23)
        self.assertEqual(self.summary["failed_probe_ids"], [])
        self.assertEqual(self.summary["profile_only_not_realized_ids"], [])
        self.assertEqual(self.summary["wrong_direction_or_incomplete_ids"], [])
        self.assertFalse(self.raw["runtime_weights_modified"])

    def test_twelve_frozen_profiles_are_executed_as_coverage_only(self) -> None:
        self.assertEqual(self.summary["frozen_case_count"], 12)
        self.assertEqual([row["case_id"] for row in self.summary["frozen_cases"]], [f"A{index:02d}" for index in range(1, 13)])
        manifest = json.loads((self.output / "frozen_input_hashes.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["role"], "coverage_evidence_not_tuning_targets")
        self.assertEqual(len(manifest["files"]), 13)

    def test_collision_timing_feedback_and_pose_are_present_per_hit(self) -> None:
        runtime = self.raw["baseline"]["runtime"]
        self.assertEqual(len(runtime["hits"]), 3)
        for hit in runtime["hits"]:
            self.assertGreater(hit["collision_cell_count"], 0)
            self.assertIn("startup", hit["timing"])
            self.assertIn("hitstop_seconds", hit["feedback"])
            self.assertIn("torso_rotation", hit["pose"])

    def test_output_is_atomic_and_self_verifying(self) -> None:
        evidence = json.loads((self.output / "evidence_hashes.json").read_text(encoding="utf-8"))
        for relative, expected in evidence["files"].items():
            self.assertEqual(hashlib.sha256((self.output / relative).read_bytes()).hexdigest(), expected)
        complete = json.loads((self.output / "COMPLETE.json").read_text(encoding="utf-8"))
        self.assertEqual(complete["evidence_sha256"], hashlib.sha256((self.output / "evidence_hashes.json").read_bytes()).hexdigest())
        self.assertEqual(complete["network_calls"], 0)
        self.assertFalse(complete["grammar_weights_modified"])

    def test_runner_contains_no_provider_or_network_client(self) -> None:
        source = inspect.getsource(audit)
        self.assertNotIn("AnthropicSemanticCompiler", source)
        self.assertNotIn("requests", source)
        self.assertNotIn("urllib", source)
        self.assertNotIn("http://", source)
        self.assertNotIn("https://", source)


if __name__ == "__main__":
    unittest.main()
