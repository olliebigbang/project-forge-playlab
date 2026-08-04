from __future__ import annotations

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))

import gate_b_4a_runner as gate  # noqa: E402


class GateB4AOfflineTests(unittest.TestCase):
    def test_frozen_sources_extract_exact_seven_field_allowlist(self) -> None:
        expected_identity = {
            "canonical_name_en",
            "required_identity_parts",
            "material_hints",
            "silhouette_hints",
            "optional_decorations",
        }
        expected_visual = {"prompt_en", "negative_prompt_en"}
        for case_id in gate.CASE_ORDER:
            with self.subTest(case_id=case_id):
                case = gate.load_source_case(case_id)
                handoff = case["handoff"]
                self.assertEqual(set(handoff), {"identity", "visual"})
                self.assertEqual(set(handoff["identity"]), expected_identity)
                self.assertEqual(set(handoff["visual"]), expected_visual)
                self.assertTrue(gate._is_english_only(handoff))
                self.assertEqual(case["handoff_sha256"], gate.HANDOFF_HASHES[case_id])

    def test_source_is_result_not_raw_response_or_player_text(self) -> None:
        for case_id in gate.CASE_ORDER:
            source = json.loads((gate.SOURCE_RUN / case_id / "result.json").read_text(encoding="utf-8"))
            extracted = gate.load_source_case(case_id)["handoff"]
            self.assertEqual(source["result"], source["tool_input_received"])
            self.assertNotIn(source["input_text"], json.dumps(extracted, ensure_ascii=False))
            self.assertNotIn("combat", extracted)
            self.assertNotIn("confidence", extracted)
            self.assertNotIn("display_name_en", json.dumps(extracted))
            self.assertNotIn("must_preserve", json.dumps(extracted))
            self.assertNotIn("must_not_replace_with", json.dumps(extracted))

    def test_effective_prompts_preserve_every_allowed_value_in_order(self) -> None:
        for case_id in gate.CASE_ORDER:
            case = gate.load_source_case(case_id)
            handoff = case["handoff"]
            positive = case["effective_positive_prompt"]
            negative = case["effective_negative_prompt"]
            cursor = -1
            ordered_values = [
                handoff["identity"]["canonical_name_en"],
                *handoff["identity"]["required_identity_parts"],
                *handoff["identity"]["material_hints"],
                *handoff["identity"]["silhouette_hints"],
                *handoff["identity"]["optional_decorations"],
                handoff["visual"]["prompt_en"],
            ]
            for value in ordered_values:
                next_cursor = positive.find(value, cursor + 1)
                self.assertGreater(next_cursor, cursor, (case_id, value))
                cursor = next_cursor
            self.assertIn(handoff["visual"]["negative_prompt_en"], negative)
            self.assertIn(gate.SYSTEM_POSITIVE, positive)
            self.assertIn(gate.SYSTEM_NEGATIVE, negative)
            self.assertTrue(positive.isascii())
            self.assertTrue(negative.isascii())

    def test_plan_is_exactly_two_common_seeds_and_eight_attempts(self) -> None:
        frozen = gate.build_frozen_handoff()
        self.assertEqual(frozen["seeds"], [4041001, 4041002])
        self.assertEqual(frozen["planned_submission_count"], 8)
        self.assertEqual(
            [(item["case_id"], item["seed"]) for item in frozen["ordered_plan"]],
            [(case_id, seed) for case_id in gate.CASE_ORDER for seed in gate.SEEDS],
        )
        self.assertNotIn(3, {sum(1 for item in frozen["ordered_plan"] if item["case_id"] == case_id) for case_id in gate.CASE_ORDER})

    def test_workflow_and_sampler_are_frozen(self) -> None:
        workflow_path = gate.COMFY_ROOT / "workflows" / "forge_object_sprite_v0.json"
        self.assertEqual(gate.sha256_file(workflow_path), gate.WORKFLOW_SHA256)
        workflow = json.loads(workflow_path.read_text(encoding="utf-8"))
        sampler = workflow["6"]["inputs"]
        self.assertEqual(sampler["steps"], 26)
        self.assertEqual(sampler["cfg"], 6.5)
        self.assertEqual(sampler["sampler_name"], "dpmpp_2m")
        self.assertEqual(sampler["scheduler"], "karras")
        self.assertEqual(sampler["denoise"], 1.0)

    def test_injected_workflows_only_vary_approved_prompt_seed_and_output(self) -> None:
        workflow = json.loads((gate.COMFY_ROOT / "workflows" / "forge_object_sprite_v0.json").read_text(encoding="utf-8"))
        frozen = gate.build_frozen_handoff()
        normalized_graphs = []
        for item in frozen["ordered_plan"]:
            case = frozen["cases"][item["case_id"]]
            graph = gate.inject_workflow(
                workflow,
                checkpoint="RealVisXL_V5.0_fp16.safetensors",
                positive_prompt=case["effective_positive_prompt"],
                negative_prompt=case["effective_negative_prompt"],
                input_image="placeholder.png",
                seed=item["seed"],
                denoise=1.0,
                output_prefix="output",
            )
            normalized = copy.deepcopy(graph)
            normalized["4"]["inputs"]["text"] = "PROMPT"
            normalized["5"]["inputs"]["text"] = "NEGATIVE"
            normalized["6"]["inputs"]["seed"] = 0
            normalized["8"]["inputs"]["filename_prefix"] = "OUTPUT"
            normalized_graphs.append(normalized)
        self.assertTrue(all(graph == normalized_graphs[0] for graph in normalized_graphs))

    def test_failed_submission_is_recorded_once_without_retry(self) -> None:
        frozen = gate.build_frozen_handoff()
        workflow = json.loads((gate.COMFY_ROOT / "workflows" / "forge_object_sprite_v0.json").read_text(encoding="utf-8"))
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            config = {
                "output_root": str(temp / "output"),
                "input_directory": str(temp / "input"),
                "comfy_output_directory": str(temp / "comfy"),
                "generation_width": 512,
                "generation_height": 512,
                "background_rgb": [255, 0, 255],
                "checkpoint": "RealVisXL_V5.0_fp16.safetensors",
                "workflow_file": str(gate.COMFY_ROOT / "workflows" / "forge_object_sprite_v0.json"),
                "timeout_seconds": 120,
                "sprite_size": 96,
                "max_colors": 32,
                "outline": True,
                "selected_install_label": "test",
                "api_base": "http://127.0.0.1:8188",
            }
            runtime = {
                "workflow_sha256": gate.WORKFLOW_SHA256,
                "checkpoint_sha256": gate.CHECKPOINT_SHA256,
                "sampler": {"steps": 26, "cfg": 6.5, "sampler_name": "dpmpp_2m", "scheduler": "karras", "denoise": 1.0},
                "generation_dimensions": [512, 512],
            }
            item = frozen["ordered_plan"][0]
            with mock.patch.object(gate, "PROJECT_ROOT", temp), mock.patch.object(
                gate, "_submit_and_wait", side_effect=gate.BridgeError("TEST_FAILURE")
            ) as submit:
                result = gate._run_one(
                    config=config,
                    runtime=runtime,
                    frozen_hash="f" * 64,
                    run_id="offline-test",
                    item=item,
                    case=frozen["cases"][item["case_id"]],
                    workflow=workflow,
                )
            self.assertEqual(submit.call_count, 1)
            self.assertTrue(result["request_attempted"])
            self.assertEqual(result["status"], "failed")
            manifest = json.loads((temp / "output" / "offline-test" / "B01" / "seed_4041001" / "manifest.json").read_text())
            self.assertEqual(manifest["retry_count"], 0)
            self.assertEqual(manifest["failure_reason"], "TEST_FAILURE")

    def test_reservation_is_exclusive(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            reservation = Path(directory) / "reservation.json"
            with mock.patch.object(gate, "RESERVATION_PATH", reservation):
                with mock.patch.object(gate, "sha256_file", return_value="a" * 64):
                    gate._reserve_run("b" * 64, Path(__file__))
                    with self.assertRaises(FileExistsError):
                        gate._reserve_run("b" * 64, Path(__file__))

    def test_generation_runner_cannot_read_human_rubric_or_expected_answers(self) -> None:
        source = Path(gate.__file__).read_text(encoding="utf-8").lower()
        self.assertNotIn("human_review_rubric", source)
        for identity_token in ("vacuum cleaner", "alarm clock", "stapler", "goblet", "rear hinge"):
            self.assertNotIn(identity_token, source)

    def test_loopback_is_exact_and_lifecycle_refuses_reuse(self) -> None:
        lifecycle = (ROOT / "gate_b_4a_lifecycle.ps1").read_text(encoding="utf-8")
        self.assertIn('http://127.0.0.1:8188', lifecycle)
        self.assertIn('--listen 127.0.0.1 --port 8188', lifecycle)
        self.assertIn('refuses to reuse any existing process', lifecycle)
        self.assertIn('port_8188_closed = $true', lifecycle)
        self.assertNotIn('--listen 0.0.0.0', lifecycle)

    def test_postprocess_is_unchanged(self) -> None:
        self.assertEqual(gate.sha256_file(gate.COMFY_ROOT / "postprocess" / "process_sprite.py"), gate.POSTPROCESS_SHA256)

    def test_frozen_history_still_matches(self) -> None:
        protected = gate._verify_spike2_history()
        self.assertEqual(len(protected["image_evidence_hashes"]), 15)
        self.assertEqual(protected["baseline"]["raw_identity_recognizable"], {"passed": 2, "total": 5})


if __name__ == "__main__":
    unittest.main(verbosity=2)
