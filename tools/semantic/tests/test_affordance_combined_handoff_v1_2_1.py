from __future__ import annotations

import inspect
import json
from pathlib import Path
import sys
import tempfile
import unittest

BRIDGE = Path(__file__).resolve().parents[1] / "bridge"
sys.path.insert(0, str(BRIDGE))

import affordance_combined_handoff_v1_2_1 as handoff


class CombinedAffordanceHandoffTests(unittest.TestCase):
    def setUp(self) -> None:
        self.repo = Path(__file__).resolve().parents[3]

    def test_frozen_runs_self_verify_before_merge(self) -> None:
        semantic = self.repo / "tools" / "semantic"
        source = handoff.verify_frozen_run(
            semantic / "reports" / "affordance_retest_v1_2" / handoff.SOURCE_RUN_ID,
            handoff.SOURCE_RUN_ID,
            handoff.SOURCE_EVIDENCE_SHA256,
        )
        targeted = handoff.verify_frozen_run(
            semantic / "reports" / "affordance_targeted_v1_2_1" / handoff.TARGET_RUN_ID,
            handoff.TARGET_RUN_ID,
            handoff.TARGET_EVIDENCE_SHA256,
        )
        self.assertEqual(source["file_count"], 58)
        self.assertEqual(targeted["file_count"], 16)

    def test_prepare_builds_exactly_twelve_anonymous_profiles(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "combined"
            manifest = handoff.prepare_handoff(self.repo, output)
            self.assertEqual(manifest["profile_count"], 12)
            self.assertFalse(manifest["identity_inputs_in_compiler_bundle"])
            self.assertFalse(manifest["version_boundary"]["homogeneous_twelve_call_run"])
            self.assertEqual(manifest["version_boundary"]["v1_2_case_count"], 8)
            self.assertEqual(manifest["version_boundary"]["v1_2_1_targeted_case_count"], 4)
            self.assertEqual(json.loads((output / "case_order.json").read_text(encoding="utf-8")), list(handoff.CASE_ORDER))
            forbidden = {"identity", "canonical_name", "display_name", "source_identity", "player_identity_text", "prompt_zh"}
            for case_id in handoff.CASE_ORDER:
                profile = json.loads((output / "affordance_profiles" / f"{case_id}.json").read_text(encoding="utf-8"))
                self.assertTrue(forbidden.isdisjoint(profile))

    def test_targeted_profiles_are_copied_without_repair(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "combined"
            handoff.prepare_handoff(self.repo, output)
            targeted_root = self.repo / "tools" / "semantic" / "reports" / "affordance_targeted_v1_2_1" / handoff.TARGET_RUN_ID
            for case_id in handoff.TARGET_CASES:
                frozen = json.loads((targeted_root / "cases" / case_id / "result.json").read_text(encoding="utf-8"))["tool_input_received"]["affordance"]
                merged = json.loads((output / "affordance_profiles" / f"{case_id}.json").read_text(encoding="utf-8"))
                self.assertEqual(merged, frozen)

    def test_existing_output_is_never_overwritten(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "combined"
            output.mkdir()
            with self.assertRaises(handoff.CombinedHandoffError):
                handoff.prepare_handoff(self.repo, output)

    def test_analysis_counts_mechanical_sequences_not_identity_labels(self) -> None:
        records = []
        sequences = [
            ["bash", "sweep", "slam"],
            ["thrust", "spin", "slam"],
        ] * 6
        for index, sequence in enumerate(sequences, start=1):
            recipe = {
                stage: {"motion_family": sequence[min(stage_index, 2)], "root_motion_distance": float(index)}
                for stage_index, stage in enumerate(handoff.RECIPE_STAGES)
            }
            records.append(
                {
                    "case_id": f"A{index:02d}",
                    "status": "COMPILED",
                    "mechanism_axes": {
                        "handle_length": "short",
                        "body_length": "medium",
                        "grip_topology": "one_hand_handle",
                        "rigidity": "rigid",
                        "mass_distribution": "front",
                        "contact_surface": "broad",
                        "secondary_contact_surface": "none",
                        "has_point": sequence[0] == "thrust",
                        "has_edge": False,
                        "has_broad_face": True,
                        "has_barrel": False,
                        "has_stock": False,
                    },
                    "primitive_sequence": sequence,
                    "primitive_scores": {name: float(position) for position, name in enumerate(sorted(handoff.PRIMITIVES))},
                    "recipe_signature": f"recipe-{index}",
                    "recipe": recipe,
                }
            )
        labels = {case_id: f"label-{case_id}" for case_id in handoff.CASE_ORDER}
        sources = [{"case_id": case_id, "contract_version": "test"} for case_id in handoff.CASE_ORDER]
        summary = handoff.analyze_compiled({"identity_inputs_used": False, "records": records}, labels, sources)
        self.assertEqual(summary["unique_primitive_sequences"], 2)
        self.assertFalse(summary["single_sequence_degradation"])
        self.assertEqual(set(summary["primitive_counts"]), handoff.PRIMITIVES)

    def test_handoff_implementation_contains_no_provider_or_network_client(self) -> None:
        source = inspect.getsource(handoff)
        self.assertNotIn("AnthropicSemanticCompiler", source)
        self.assertNotIn("ANTHROPIC_API_KEY", source)
        self.assertNotIn("urllib", source)
        self.assertNotIn("requests", source)
        self.assertNotIn("http://", source)
        self.assertNotIn("https://", source)


if __name__ == "__main__":
    unittest.main()
