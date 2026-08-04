from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np
from PIL import Image, ImageDraw


COMFY_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(COMFY_ROOT / "bridge"))
sys.path.insert(0, str(COMFY_ROOT / "postprocess"))

import forge_comfy_bridge as bridge  # noqa: E402
from process_sprite import SpritePostprocessError, process_sprite  # noqa: E402


class SpikeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.workflow_path = COMFY_ROOT / "workflows" / "forge_object_sprite_v0.json"
        self.workflow = json.loads(self.workflow_path.read_text(encoding="utf-8"))

    def test_workflow_template_injects_every_parameter(self) -> None:
        graph = bridge.inject_workflow(
            self.workflow,
            checkpoint="checkpoint.safetensors",
            positive_prompt="positive",
            negative_prompt="negative",
            input_image="input.png",
            seed=99,
            denoise=0.57,
            output_prefix="Spike/test/raw",
        )
        self.assertNotIn("_forge", graph)
        self.assertEqual(graph["1"]["inputs"]["ckpt_name"], "checkpoint.safetensors")
        self.assertEqual(graph["4"]["inputs"]["text"], "positive")
        self.assertEqual(graph["5"]["inputs"]["text"], "negative")
        self.assertEqual(graph["2"]["inputs"]["image"], "input.png")
        self.assertEqual(graph["6"]["inputs"]["seed"], 99)
        self.assertEqual(graph["6"]["inputs"]["denoise"], 0.57)
        self.assertEqual(graph["8"]["inputs"]["filename_prefix"], "Spike/test/raw")

    def test_open_identity_prompt_is_first_bounded_and_weight_safe(self) -> None:
        identity = "会连续发射螺丝的木椅"
        model_prompt = bridge.sanitize_model_prompt(
            f"Recognizable original object: (({identity})).\nPreserve [chair-like evidence]."
        )
        self.assertIn(identity, model_prompt)
        for token in "()[]{}<>":
            self.assertNotIn(token, model_prompt)
        self.assertLessEqual(len(model_prompt), 1400)
        positive = bridge.compose_positive_prompt(model_prompt)
        self.assertTrue(positive.startswith(model_prompt))
        self.assertGreater(positive.find(bridge.SYSTEM_POSITIVE), positive.find(identity))

    def test_model_prompt_rejects_empty_control_only_input(self) -> None:
        with self.assertRaisesRegex(bridge.BridgeError, "GENERATION_PROMPT_EMPTY"):
            bridge.sanitize_model_prompt("\x00\x01\r\n\t")

    def test_timeout_cancels_without_unbounded_polling(self) -> None:
        responses = [{"prompt_id": "job-1"}, {}]
        with patch.object(bridge, "_json_request", side_effect=responses), patch.object(
            bridge.time, "monotonic", side_effect=[0.0, 0.0, 2.0]
        ), patch.object(bridge.time, "sleep"), patch.object(bridge, "_cancel") as cancel:
            with self.assertRaisesRegex(bridge.BridgeError, "COMFYUI_TIMEOUT"):
                bridge._submit_and_wait({"api_base": "http://127.0.0.1:8188", "poll_interval_seconds": 0.1}, {}, 1.0)
            cancel.assert_called_once_with(unittest.mock.ANY, "job-1")

    def test_corrupt_png_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "raw.png").write_bytes(b"not a png")
            with self.assertRaisesRegex(SpritePostprocessError, "INVALID_SOURCE_PNG"):
                process_sprite(root / "raw.png", root / "sprite.png", root / "mask.png")

    def test_no_subject_alpha_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            Image.new("RGB", (256, 256), (255, 0, 255)).save(root / "raw.png")
            with self.assertRaises(SpritePostprocessError):
                process_sprite(root / "raw.png", root / "sprite.png", root / "mask.png")

    def test_valid_sprite_is_96_and_has_alpha(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            raw = Image.new("RGB", (256, 256), (238, 90, 205))
            draw = ImageDraw.Draw(raw)
            draw.rounded_rectangle((45, 95, 205, 160), radius=18, fill=(40, 80, 130), outline=(10, 20, 30), width=6)
            raw.save(root / "raw.png")
            metadata = process_sprite(root / "raw.png", root / "sprite.png", root / "mask.png")
            sprite = Image.open(root / "sprite.png").convert("RGBA")
            self.assertEqual(sprite.size, (96, 96))
            self.assertGreater(sprite.getchannel("A").getextrema()[1], 0)
            self.assertEqual(metadata["processed_dimensions"], [96, 96])

    def test_temporary_run_is_not_a_final_result(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            temporary = root / ".tmp" / "case_a-run"
            temporary.mkdir(parents=True)
            (temporary / "manifest.json").write_text('{"status":"success"}', encoding="utf-8")
            final = root / "case_a" / "run"
            self.assertFalse((final / "manifest.json").is_file())

    def test_all_delivered_manifests_have_required_fields(self) -> None:
        manifests = sorted((COMFY_ROOT / "output").glob("case_*/seed_*/manifest.json"))
        self.assertEqual(len(manifests), 15)
        for path in manifests:
            payload = json.loads(path.read_text(encoding="utf-8"))
            self.assertFalse(bridge.REQUIRED_MANIFEST_FIELDS - payload.keys(), path)

    def test_all_successful_runs_have_parseable_anchors(self) -> None:
        successes = 0
        for manifest_path in sorted((COMFY_ROOT / "output").glob("case_*/seed_*/manifest.json")):
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            if manifest["status"] != "success":
                continue
            successes += 1
            anchors = json.loads((manifest_path.parent / "anchors.json").read_text(encoding="utf-8"))
            for field in ("GripPrimary", "GripSecondary", "Muzzle", "Tip", "SpinPivot"):
                self.assertEqual(len(anchors[field]), 2)
        self.assertEqual(successes, 11)

    def test_failed_runs_do_not_claim_processed_sprite(self) -> None:
        for manifest_path in sorted((COMFY_ROOT / "output").glob("case_*/seed_*/manifest.json")):
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            if manifest["status"] == "failed":
                self.assertFalse((manifest_path.parent / "processed_sprite.png").exists())

    def test_unavailable_comfyui_is_explicit(self) -> None:
        with self.assertRaisesRegex(bridge.BridgeError, "COMFYUI_UNAVAILABLE"):
            bridge.health_check({"api_base": "http://127.0.0.1:9"})

    def test_system_prompt_excludes_people_and_sheets(self) -> None:
        for term in ("no person", "no hand", "no text", "no UI"):
            self.assertIn(term, bridge.SYSTEM_POSITIVE)
        for term in ("portrait", "human", "weapon sheet", "inventory grid", "cropped object"):
            self.assertIn(term, bridge.SYSTEM_NEGATIVE)


if __name__ == "__main__":
    unittest.main()
