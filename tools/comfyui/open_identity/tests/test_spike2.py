from __future__ import annotations

import hashlib
import json
import unittest
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[4]
SPIKE_ROOT = ROOT / "tools" / "comfyui" / "open_identity"


class OpenIdentitySpike2Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.compiled = json.loads((SPIKE_ROOT / "reports" / "compiled_cases.json").read_text(encoding="utf-8"))
        cls.cases = cls.compiled["cases"]

    def test_five_blueprints_preserve_verbatim_identity(self) -> None:
        self.assertFalse(self.compiled["identity_semantics_understood"])
        generated = [case for case in self.cases if case.get("generate_visual")]
        self.assertEqual(len(generated), 5)
        for case in generated:
            blueprint = case["blueprint"]
            self.assertEqual(blueprint["player_identity_text"], case["player_text"])
            self.assertEqual(blueprint["source_identity"], case["player_text"])
            self.assertEqual(blueprint["visual_description"], case["player_text"])
            self.assertEqual(blueprint["weapon_form"], "open_identity_object")
            self.assertFalse(case["ai_interpretation_used"])
            self.assertFalse(case["identity_semantics_understood"])

    def test_three_distinct_identities_share_sustained_behavior(self) -> None:
        identities = {
            case["blueprint"]["player_identity_text"]
            for case in self.cases
            if case.get("blueprint", {}).get("behavior_family") == "sustained_ranged"
        }
        self.assertEqual(len(identities), 3)

    def test_abstract_sketch_requires_exact_identity_clarification(self) -> None:
        sketch_case = next(case for case in self.cases if case["case_id"] == "spike2_case_06")
        # The test is backed by a real PNG rather than a marker byte array.
        sketch_path = SPIKE_ROOT / "test_cases" / sketch_case["sketch"]
        with Image.open(sketch_path) as sketch:
            self.assertEqual(sketch.size, (512, 512))
        self.assertGreater(sketch_case["sketch_bytes"], 100)
        self.assertTrue(sketch_case["needs_clarification"])
        self.assertEqual(sketch_case["clarification_kind"], "identity")
        self.assertEqual(sketch_case["question"], "你画的是什么？")
        self.assertNotIn("blueprint", sketch_case)

    def test_official_visual_manifests_prove_identity_prompt_delivery(self) -> None:
        for case in (case for case in self.cases if case.get("generate_visual")):
            run = SPIKE_ROOT / "output" / case["case_id"] / "seed_52002_policy1"
            manifest = json.loads((run / "manifest.json").read_text(encoding="utf-8"))
            identity = case["player_text"]
            self.assertEqual(manifest["status"], "success")
            self.assertEqual(manifest["prompt"], identity)
            self.assertEqual(manifest["player_identity_text"], identity)
            self.assertIn(identity, manifest["generation_prompt"])
            self.assertEqual(manifest["prompt_policy_version"], "forge-open-identity-v1")

    def test_official_sprites_are_valid_transparent_96px(self) -> None:
        for case in (case for case in self.cases if case.get("generate_visual")):
            path = SPIKE_ROOT / "output" / case["case_id"] / "seed_52002_policy1" / "processed_sprite.png"
            with Image.open(path) as source:
                sprite = source.convert("RGBA")
            self.assertEqual(sprite.size, (96, 96))
            self.assertLess(sprite.getchannel("A").getextrema()[0], 255)
            self.assertGreater(sprite.getchannel("A").getextrema()[1], 0)

    def test_generation_logs_keep_manifest_backed_timing_audit(self) -> None:
        logs = sorted((SPIKE_ROOT / "output").glob("*/*/generation.log"))
        self.assertEqual(len(logs), 10)
        for log_path in logs:
            manifest = json.loads(log_path.with_name("manifest.json").read_text(encoding="utf-8"))
            log = log_path.read_text(encoding="utf-8")
            self.assertIn("audit_enriched_from_manifest=true", log)
            self.assertIn(f"generation_seconds={manifest['generation_seconds']}", log)
            self.assertIn(f"postprocess_seconds={manifest['postprocess_seconds']}", log)

    def test_official_visual_evidence_hashes_are_immutable(self) -> None:
        evidence = json.loads((SPIKE_ROOT / "reports" / "evidence_hashes.json").read_text(encoding="utf-8"))
        self.assertEqual(evidence["algorithm"], "SHA-256")
        self.assertEqual(evidence["prompt_policy"], "forge-open-identity-v1")
        self.assertEqual(len(evidence["files"]), 15)
        for relative_path, expected_hash in evidence["files"].items():
            actual_hash = hashlib.sha256((ROOT / relative_path).read_bytes()).hexdigest()
            self.assertEqual(actual_hash, expected_hash, relative_path)

    def test_runner_cannot_silently_relabel_or_overwrite_official_evidence(self) -> None:
        runner = (SPIKE_ROOT / "run_visual_cases.py").read_text(encoding="utf-8")
        self.assertIn('default_label = PROMPT_POLICY_VERSION.replace("forge-open-identity-v", "policy")', runner)
        self.assertIn("prompt_policy_version=args.prompt_policy_version", runner)
        self.assertIn('f"generation_summary_{safe_label}.json"', runner)
        self.assertIn("if report_path.exists() and not args.overwrite_summary", runner)
        self.assertLess(runner.index("if report_path.exists()"), runner.index('for test_case in payload["cases"]'))
        handoff = (SPIKE_ROOT / "verify_training_handoff.gd").read_text(encoding="utf-8")
        self.assertIn('open_identity_training_arena.gd', handoff)
        self.assertIn('as OpenIdentityTrainingArena', handoff)

    def test_active_scene_is_training_only_and_mock_is_explicit(self) -> None:
        project = (ROOT / "project.godot").read_text(encoding="utf-8")
        source = (ROOT / "scripts" / "open_identity_spike.gd").read_text(encoding="utf-8")
        self.assertIn('run/main_scene="res://scenes/open_identity_spike.tscn"', project)
        self.assertIn('arena.start_stage("training", current_blueprint, current_asset)', source)
        self.assertNotIn('"room_1"', source)
        self.assertNotIn('"room_2"', source)
        self.assertNotIn("ProceduralWeaponRenderer", source)
        self.assertIn("MOCK_CANNOT_RENDER_ARBITRARY_PLAYER_IDENTITY", source)


if __name__ == "__main__":
    unittest.main()
