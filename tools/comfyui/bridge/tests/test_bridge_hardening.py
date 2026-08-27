from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw


COMFY_ROOT = Path(__file__).resolve().parents[2]
BRIDGE_ROOT = COMFY_ROOT / "bridge"
sys.path.insert(0, str(BRIDGE_ROOT))

import forge_comfy_bridge as bridge  # noqa: E402


class BridgeHardeningTests(unittest.TestCase):
    def test_transparent_black_ink_is_composited_on_white(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "transparent_sketch.png"
            target = root / "prepared.png"
            sketch = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
            ImageDraw.Draw(sketch).rectangle((20, 12, 44, 52), fill=(0, 0, 0, 255))
            sketch.save(source)

            self.assertTrue(bridge._prepare_input(source, target, (128, 128), (255, 0, 255)))
            with Image.open(target) as opened:
                prepared = opened.convert("RGB")

            self.assertEqual(prepared.getpixel((0, 0)), (255, 0, 255))
            self.assertEqual(prepared.getpixel((64, 64)), (20, 20, 24))
            dark_pixels = sum(
                1
                for y in range(prepared.height)
                for x in range(prepared.width)
                if max(prepared.getpixel((x, y))) < 64
            )
            self.assertGreater(dark_pixels, 100)
            self.assertLess(dark_pixels, prepared.width * prepared.height // 2)

    def test_api_base_accepts_only_canonical_ipv4_loopback(self) -> None:
        self.assertEqual(bridge.validate_api_base("http://127.0.0.1:1"), "http://127.0.0.1:1")
        self.assertEqual(bridge.validate_api_base("http://127.0.0.1:65535/"), "http://127.0.0.1:65535")
        rejected = (
            "http://127.0.0.1",
            "http://127.0.0.1:0",
            "http://127.0.0.1:65536",
            "http://127.0.0.1:08188",
            "http://127.0.0.1:8188@evil.example",
            "http://127.0.0.1:8188/evil",
            "http://127.0.0.1:8188?next=http://evil.example",
            "http://127.0.0.1:8188#fragment",
            "https://127.0.0.1:8188",
            "http://localhost:8188",
            "http://127.0.0.1.evil.example:8188",
        )
        for value in rejected:
            with self.subTest(value=value), self.assertRaisesRegex(
                bridge.BridgeError, "API_BASE_MUST_USE_127_0_0_1"
            ):
                bridge.validate_api_base(value)

    def test_load_config_uses_validated_canonical_api_base(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            config_path = Path(directory) / "config.json"
            config_path.write_text(json.dumps({"api_base": "http://127.0.0.1:8188/"}), encoding="utf-8")
            config = bridge.load_config(config_path)
            self.assertEqual(config["api_base"], "http://127.0.0.1:8188")

    def test_spike2_start_command_passes_its_own_config(self) -> None:
        script = (COMFY_ROOT / "scripts" / "start_comfyui.ps1").read_text(encoding="utf-8")
        readme = (COMFY_ROOT / "open_identity" / "README.md").read_text(encoding="utf-8")
        self.assertIn("[string]$ConfigPath", script)
        self.assertIn('config\\forge_comfy_config.local.json', script)
        self.assertIn("-ConfigPath .\\tools\\comfyui\\open_identity\\config\\forge_open_identity_config.local.json", readme)

    def test_active_prompt_policy_version_is_cross_layer_consistent(self) -> None:
        root = COMFY_ROOT.parents[1]
        prompt_source = (root / "scripts" / "services" / "open_identity_visual_prompt.gd").read_text(encoding="utf-8")
        provider_source = (root / "scripts" / "services" / "local_comfy_forge_visual_provider.gd").read_text(encoding="utf-8")
        self.assertEqual(bridge.PROMPT_POLICY_VERSION, "forge-open-identity-v3")
        self.assertIn('POLICY_VERSION := "forge-open-identity-v3"', prompt_source)
        self.assertIn('"--prompt-policy-version", OPEN_IDENTITY_PROMPT.POLICY_VERSION', provider_source)

    def test_visual_structure_brief_is_bounded_and_machine_owned(self) -> None:
        valid = {
            "schema": "forge-mechanism-visual-brief-v1",
            "source": "ai_mechanism_axes_visual_compiler_v1",
            "automatic": True,
            "player_confirmation_required": False,
            "axes": {"flex_topology": "flexible_line"},
            "required_roles": ["rigid_root", "deform_body"],
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "brief.json"
            path.write_text(json.dumps(valid), encoding="utf-8")
            parsed, digest = bridge._load_visual_structure_brief(path)
            self.assertEqual(parsed, valid)
            self.assertEqual(len(digest), 64)
            valid["player_confirmation_required"] = True
            path.write_text(json.dumps(valid), encoding="utf-8")
            with self.assertRaisesRegex(bridge.BridgeError, "VISUAL_STRUCTURE_BRIEF_CONTRACT_INVALID"):
                bridge._load_visual_structure_brief(path)

    def test_invalid_prompt_policy_version_fails_before_io(self) -> None:
        with self.assertRaisesRegex(bridge.BridgeError, "PROMPT_POLICY_VERSION_INVALID"):
            bridge.generate(
                Path("missing-config.json"),
                case_id="case",
                run_id="run",
                prompt="identity",
                generation_prompt="identity",
                seed=1,
                control_strength=0.0,
                sketch_path=None,
                prompt_policy_version="unversioned",
            )


if __name__ == "__main__":
    unittest.main()
