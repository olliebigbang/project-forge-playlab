from __future__ import annotations

import base64
import json
import os
import socket
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image


LIVE_ROOT = Path(__file__).resolve().parents[1]
PLAYLAB = LIVE_ROOT.parents[1]
sys.path.insert(0, str(LIVE_ROOT / "bridge"))

from live_orchestrator import (  # noqa: E402
    LivePipelineError,
    safe_png_from_base64,
    write_json_replace_in_stage,
    write_new,
)
from live_preflight import capture_history, verify_history  # noqa: E402
from static_visual_projection import PHYSICAL_FIXTURES, project_static_visual  # noqa: E402


def blueprint(effect: str = "ice") -> dict:
    return {
        "identity": {
            "canonical_name_zh": "旧落地风扇",
            "canonical_name_en": "old standing fan",
            "display_name_zh": "冰芯旧落地风扇",
            "display_name_en": "Frost-Core Old Standing Fan",
            "category": "appliance",
            "required_identity_parts": ["fan head", "support pole", "base"],
            "material_hints": ["aged painted metal"],
            "silhouette_hints": ["round head above a tall narrow pole and broad base"],
            "optional_decorations": ["small forge bolts"],
        },
        "combat": {
            "behavior_family": "sustained_ranged",
            "delivery": "continuous_emission",
            "impact_mode": "repeated_impact",
            "effect_type": effect,
            "drawback": "slow movement while emitting",
        },
        "visual": {
            "prompt_en": "an old standing fan that continuously emits ice mist",
            "negative_prompt_en": "person, hands, text",
            "must_preserve": ["fan head", "support pole", "base"],
            "must_not_replace_with": ["gun", "umbrella", "greatsword"],
        },
    }


class LiveE2ETests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.config = json.loads((LIVE_ROOT / "config" / "live_cases.json").read_text(encoding="utf-8"))
        cls.server_source = (LIVE_ROOT / "bridge" / "live_server.py").read_text(encoding="utf-8")
        cls.orchestrator_source = (LIVE_ROOT / "bridge" / "live_orchestrator.py").read_text(encoding="utf-8")
        cls.godot_source = (LIVE_ROOT / "godot" / "live_e2e.gd").read_text(encoding="utf-8")
        cls.start_source = (LIVE_ROOT / "scripts" / "run_live_e2e_interactive.ps1").read_text(encoding="utf-8")

    def test_01_default_main_scene_unchanged(self) -> None:
        text = (PLAYLAB / "project.godot").read_text(encoding="utf-8")
        self.assertIn('run/main_scene="res://scenes/open_identity_spike.tscn"', text)

    def test_02_default_provider_remains_mock(self) -> None:
        text = (PLAYLAB / "scripts" / "open_identity_spike.gd").read_text(encoding="utf-8")
        self.assertIn("var provider_mode := MODE_MOCK", text)

    def test_03_live_requires_explicit_server_argument(self) -> None:
        self.assertIn("--forge-live-e2e-spike7", self.server_source)
        self.assertIn("LIVE_E2E_EXPLICIT_LAUNCH_REQUIRED", self.server_source)

    def test_04_live_requires_explicit_godot_argument(self) -> None:
        self.assertIn('const LIVE_ARGUMENT := "--forge-live-e2e-spike7"', self.godot_source)

    def test_05_exactly_three_cases(self) -> None:
        self.assertEqual([case["case_id"] for case in self.config["cases"]], ["L01", "L02", "L03"])

    def test_06_exact_inputs_are_frozen(self) -> None:
        self.assertEqual(self.config["cases"][0]["player_input"], "一台会持续喷出冰雾的旧落地风扇。")
        self.assertEqual(self.config["cases"][2]["player_input"], "一把我要拿来近距离砸敌人的巨大木勺。")

    def test_07_seed_is_fixed_and_unique(self) -> None:
        seeds = [case["seed"] for case in self.config["cases"]]
        self.assertEqual(len(seeds), len(set(seeds)))
        self.assertEqual(seeds, [7071001, 7071002, 7071003])

    def test_08_retry_limit_is_zero(self) -> None:
        self.assertEqual(self.config["retry_limit"], 0)
        self.assertIn('"retry_count": 0', self.orchestrator_source)

    def test_09_mock_fallback_is_disabled(self) -> None:
        self.assertFalse(self.config["mock_fallback"])
        self.assertNotIn("MockForgeVisualProvider", self.orchestrator_source)

    def test_10_static_projection_preserves_identity(self) -> None:
        projected, _ = project_static_visual(blueprint())
        self.assertEqual(projected["identity"]["canonical_name_en"], "old standing fan")
        self.assertIn("fan head", projected["visual"]["prompt_en"])

    def test_11_dynamic_ice_mist_does_not_enter_static_prompt(self) -> None:
        projected, _ = project_static_visual(blueprint("ice"))
        self.assertNotIn("ice mist", projected["visual"]["prompt_en"].lower())
        self.assertIn("frost core", projected["visual"]["prompt_en"].lower())

    def test_12_static_prompt_blocks_dynamic_trails(self) -> None:
        projected, _ = project_static_visual(blueprint("electric"))
        self.assertIn("electric trail", projected["visual"]["negative_prompt_en"].lower())
        self.assertNotIn("lightning arc", projected["visual"]["prompt_en"].lower())

    def test_13_all_effects_map_to_physical_fixtures(self) -> None:
        for effect in ("fire", "electric", "steam", "poison", "light"):
            self.assertTrue(PHYSICAL_FIXTURES[effect])
            self.assertNotIn("trail", " ".join(PHYSICAL_FIXTURES[effect]))

    def test_14_source_blueprint_is_not_mutated(self) -> None:
        source = blueprint()
        before = json.dumps(source, sort_keys=True)
        project_static_visual(source)
        self.assertEqual(json.dumps(source, sort_keys=True), before)

    def test_15_claude_failure_precedes_flux(self) -> None:
        semantic = self.orchestrator_source.index("self.compiler.compile")
        flux = self.orchestrator_source.index("flux_bridge.generate")
        self.assertLess(semantic, flux)
        self.assertIn("remaining_semantic_call_limit", self.orchestrator_source)
        self.assertIn("response = self._technical_success_response(state, player_input)", self.orchestrator_source)
        self.assertIn('"case_id": state.config["case_id"]', self.orchestrator_source)

    def test_16_flux_failure_precedes_birefnet(self) -> None:
        flux = self.orchestrator_source.index("flux_bridge.generate")
        biref = self.orchestrator_source.index("self._run_birefnet")
        self.assertLess(flux, biref)

    def test_17_birefnet_precedes_sprite_delivery(self) -> None:
        biref = self.orchestrator_source.index("self._run_birefnet")
        post = self.orchestrator_source.index("process_birefnet_sprite", biref)
        self.assertLess(biref, post)

    def test_18_identity_gate_precedes_anchor_gate(self) -> None:
        identity = self.godot_source.index("_show_identity_confirmation")
        anchor = self.godot_source.index("_show_anchor_confirmation", identity)
        self.assertLess(identity, anchor)

    def test_19_anchor_gate_precedes_training(self) -> None:
        anchor = self.godot_source.index("_submit_anchors")
        training = self.godot_source.index("_enter_training", anchor)
        self.assertLess(anchor, training)

    def test_20_stale_revision_is_rejected(self) -> None:
        self.assertIn("STALE_REQUEST_REJECTED", self.orchestrator_source)
        self.assertIn('payload.get("revision") != state.revision', self.orchestrator_source)

    def test_21_atomic_case_publish_uses_replace(self) -> None:
        self.assertIn("os.replace(stage, final)", self.orchestrator_source)
        self.assertIn('write_json_replace_in_stage(stage / "stage_metrics.json"', self.orchestrator_source)
        self.assertIn("CASE_EVIDENCE_ALREADY_EXISTS", self.orchestrator_source)

    def test_22_new_file_writer_refuses_overwrite(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "evidence.bin"
            write_new(path, b"one")
            with self.assertRaises(FileExistsError):
                write_new(path, b"two")
            mutable = Path(temp) / "unpublished_stage_metrics.json"
            mutable.write_text('{"version":1}\n', encoding="utf-8")
            write_json_replace_in_stage(mutable, {"version": 2})
            self.assertEqual(json.loads(mutable.read_text(encoding="utf-8")), {"version": 2})

    def test_23_invalid_png_is_rejected(self) -> None:
        with self.assertRaises(LivePipelineError):
            safe_png_from_base64(base64.b64encode(b"not png").decode("ascii"), "TEST")

    def test_24_valid_png_is_accepted(self) -> None:
        with tempfile.SpooledTemporaryFile() as stream:
            Image.new("RGBA", (16, 16), (255, 0, 255, 0)).save(stream, format="PNG")
            stream.seek(0)
            payload = stream.read()
        self.assertEqual(safe_png_from_base64(base64.b64encode(payload).decode("ascii"), "TEST"), payload)

    def test_25_training_requires_move_attack_and_dodge(self) -> None:
        self.assertIn("moved_once and attacked_once and dodged_once", self.godot_source)
        self.assertIn('dodge_button := _button("执行闪避"', self.godot_source)
        self.assertIn("arena.request_touch_dodge()", self.godot_source)

    def test_26_schema_effect_is_rendered_by_godot(self) -> None:
        arena = (LIVE_ROOT / "godot" / "live_training_arena.gd").read_text(encoding="utf-8")
        for effect in ("ice", "fire", "electric", "steam", "poison", "light"):
            self.assertIn(f'"{effect}"', arena)

    def test_27_no_combat_room_scene_reference(self) -> None:
        combined = self.godot_source + (LIVE_ROOT / "godot" / "live_e2e.tscn").read_text(encoding="utf-8")
        self.assertNotIn("room_one", combined.lower())
        self.assertNotIn("room_two", combined.lower())
        self.assertNotIn("combat_room", combined.lower())

    def test_28_v2_is_not_started(self) -> None:
        self.assertNotIn("start_v2", self.godot_source.lower())
        self.assertIn('"v2_started": False', self.orchestrator_source)

    def test_29_secure_key_prompt_is_required(self) -> None:
        self.assertIn("Read-Host", self.start_source)
        self.assertIn("-AsSecureString", self.start_source)
        self.assertIn("ZeroFreeBSTR", self.start_source)

    def test_30_key_is_cleared_in_finally(self) -> None:
        self.assertIn("Remove-Item Env:\\ANTHROPIC_API_KEY", self.start_source)
        self.assertIn("finally", self.start_source)

    def test_31_only_loopback_services_are_configured(self) -> None:
        self.assertEqual(self.config["api_base"], "http://127.0.0.1:8190")
        self.assertEqual(self.config["bridge_base"], "http://127.0.0.1:8767")

    def test_32_8188_is_not_active_during_offline_test(self) -> None:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
            probe.settimeout(0.2)
            self.assertNotEqual(probe.connect_ex(("127.0.0.1", 8188)), 0)

    def test_33_historical_evidence_self_verifies(self) -> None:
        snapshot = capture_history(PLAYLAB)
        verify_history(PLAYLAB, snapshot)

    def test_34_live_code_has_no_dotenv_writer(self) -> None:
        for path in LIVE_ROOT.rglob("*"):
            if path.resolve() == Path(__file__).resolve():
                continue
            if path.is_file() and path.suffix in {".py", ".gd", ".ps1", ".json"}:
                source = path.read_text(encoding="utf-8", errors="replace").lower()
                self.assertNotIn("dotenv", source)
                self.assertNotIn('open(".env"', source)
                self.assertNotIn("set-content .env", source)

    def test_35_no_case_specific_visual_branch(self) -> None:
        source = (LIVE_ROOT / "bridge" / "static_visual_projection.py").read_text(encoding="utf-8")
        for case_id in ("L01", "L02", "L03"):
            self.assertNotIn(case_id, source)

    def test_36_birefnet_workflow_is_hash_pinned(self) -> None:
        self.assertIn("BIREF_WORKFLOW_SHA256", self.orchestrator_source)
        self.assertIn("load_approved_workflow", self.orchestrator_source)

    def test_37_official_spike6_postprocessor_is_reused(self) -> None:
        self.assertIn("from process_birefnet_sprite import", self.orchestrator_source)
        self.assertNotIn("grabCut", self.orchestrator_source)

    def test_38_outputs_require_96_rgba_alpha(self) -> None:
        self.assertIn('sprite.size != (96, 96)', self.orchestrator_source)
        self.assertIn('sprite.mode != "RGBA"', self.orchestrator_source)

    def test_39_no_price_estimation(self) -> None:
        self.assertNotIn("cost_usd", self.orchestrator_source)
        self.assertIn("semantic_input_tokens", self.orchestrator_source)

    def test_40_process_cleanup_checks_all_live_ports(self) -> None:
        for port in ("8190", "8188", "8767"):
            self.assertIn(port, self.start_source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
