from __future__ import annotations

import json
import sys
import tempfile
import threading
import unittest
from pathlib import Path


OPEN_ROOT = Path(__file__).resolve().parents[1]
PLAYLAB = OPEN_ROOT.parents[1]
sys.path.insert(0, str(OPEN_ROOT / "bridge"))

import open_playtest_session as open_session
import live_orchestrator as live


class _FakeCompiler:
    calls_made = 0


def _make_session(root: Path) -> open_session.OpenPlaytestSession:
    session = open_session.OpenPlaytestSession.__new__(open_session.OpenPlaytestSession)
    session.config = {
        "contract": open_session.OPEN_CONTRACT,
        "recent_limit": 10,
        "history_limit": 200,
        "session_call_limit": 20,
        "input_max_characters": 500,
        "retry_limit": 0,
        "mock_fallback": False,
    }
    session.session_id = "open-test-session"
    session.run_id = session.session_id
    session.runtime_root = root / "runtime"
    session.pipeline_root = session.runtime_root / "pipeline"
    session.output_root = root / "output"
    session.report_root = session.output_root
    session.output_root.mkdir(parents=True)
    session.runtime_root.mkdir(parents=True)
    session.lock = threading.RLock()
    session.revision = 0
    session.rounds = {}
    session.active_round_id = None
    session.request_ids = set()
    session.compiler = _FakeCompiler()
    session.technical_contract = "forge-open-playtest-technical-v1"
    session.flux_output_group = "open_playtest_stage"
    session.biref_output_namespace = "ForgeOpenPlaytest"
    session.history = open_session.LocalHistoryStore(root / "history")
    return session


def _add_round(session: open_session.OpenPlaytestSession, root: Path, stage: str) -> open_session.OpenRound:
    state = live.CaseState(
        config={
            "case_id": "R0001-deadbeef",
            "seed": 12,
            "required_identity_parts": ["body", "handle"],
            "second_anchor_type": "EffectOrigin",
            "second_anchor_question": "力量从哪里发出？",
            "expected_behavior_family": "sustained_ranged",
        },
        revision=1,
        stage=stage,
        semantic_blueprint={
            "identity": {
                "canonical_name_zh": "木椅",
                "canonical_name_en": "wooden chair",
                "display_name_zh": "螺丝喷射木椅",
                "display_name_en": "Screw-Spitting Wooden Chair",
                "required_identity_parts": ["seat", "legs"],
            },
            "combat": {
                "behavior_family": "sustained_ranged",
                "delivery": "continuous_emission",
                "impact_mode": "projectile_hit",
                "effect_type": "forge_fastener",
                "drawback": "slow movement",
                "cadence_hint": "rapid",
            },
        },
    )
    output = root / "output" / "rounds" / "R0001-deadbeef"
    output.mkdir(parents=True)
    value = open_session.OpenRound(
        state=state,
        player_input="一把会连续发射螺丝的木椅",
        client_request_id="request-12345678",
        started_at_utc="2026-08-04T00:00:00.000Z",
        started_monotonic=0.0,
        stage_started_monotonic=0.0,
        output_dir=output,
    )
    session.rounds["R0001-deadbeef"] = value
    session.active_round_id = "R0001-deadbeef"
    session.revision = 1
    return value


class OpenPlaytestTests(unittest.TestCase):
    def test_config_keeps_mock_default_and_explicit_real_mode(self) -> None:
        config = json.loads((OPEN_ROOT / "config" / "open_playtest_config.json").read_text(encoding="utf-8"))
        self.assertEqual(config["default_player_mode"], "MOCK")
        self.assertEqual(config["explicit_launch_argument"], "--forge-open-playtest")
        self.assertFalse(config["mock_fallback"])
        self.assertEqual(config["retry_limit"], 0)
        self.assertTrue(config["training_only"])
        self.assertFalse(config["sketch_enabled"])

    def test_project_default_scene_and_mock_provider_are_unchanged(self) -> None:
        project = (PLAYLAB / "project.godot").read_text(encoding="utf-8")
        provider = (PLAYLAB / "scripts" / "open_identity_spike.gd").read_text(encoding="utf-8")
        self.assertIn('run/main_scene="res://scenes/open_identity_spike.tscn"', project)
        self.assertIn("var provider_mode := MODE_MOCK", provider)

    def test_open_scene_requires_explicit_argument_and_loopback_bridge(self) -> None:
        source = (OPEN_ROOT / "godot" / "open_playtest.gd").read_text(encoding="utf-8")
        self.assertIn('const OPEN_ARGUMENT := "--forge-open-playtest"', source)
        self.assertIn('const EXPECTED_BRIDGE := "http://127.0.0.1:8771"', source)
        self.assertIn("进入 OPEN PLAYTEST MODE", source)

    def test_ui_contains_required_loop_and_disclaimer(self) -> None:
        source = (OPEN_ROOT / "godot" / "open_playtest.gd").read_text(encoding="utf-8")
        for phrase in (
            "FORGE", "CLEAR", "HISTORY / RECENT INPUTS", "Claude / FLUX.2 Klein 4B / BiRefNet",
            "仍然能认出这是原物件吗", "RETRY THIS IDEA", "FORGE NEW IDEA", "SAVE THIS RESULT",
            "数值、完整特效、敌人平衡和正式玩法尚未完成",
        ):
            self.assertIn(phrase, source)

    def test_stage_list_is_complete(self) -> None:
        self.assertEqual(open_session.PIPELINE_STAGES, (
            "semantic_compiling", "image_generating", "background_removing",
            "sprite_processing", "confirm_identity", "confirm_anchors",
            "ready_in_training_zone",
        ))

    def test_history_json_and_csv_are_atomic_and_recent_is_newest_first(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            store = open_session.LocalHistoryStore(Path(temp), history_limit=20)
            for index in range(12):
                store.upsert({"round_id": f"R{index}", "timestamp": str(index), "user_input": f"想法{index}"})
            self.assertEqual(len(store.recent(10)), 10)
            self.assertEqual(store.recent(10)[0]["round_id"], "R11")
            self.assertTrue(store.json_path.is_file())
            self.assertTrue(store.csv_path.is_file())
            self.assertFalse(list(Path(temp).glob("*.tmp")))

    def test_identity_rejection_preserves_input_and_ends_before_anchors(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            session = _make_session(root)
            value = _add_round(session, root, "confirm_identity")
            result = session.confirm_identity({
                "session_id": session.session_id,
                "round_id": "R0001-deadbeef",
                "revision": 1,
                "identity_confirmed": False,
                "user_notes": "看起来像普通枪",
            })
            self.assertEqual(result["status"], "identity_rejected")
            self.assertEqual(value.player_input, "一把会连续发射螺丝的木椅")
            self.assertIsNone(value.state.anchors)
            self.assertFalse(value.state.identity_review["identity_confirmed"])

    def test_stale_anchor_request_cannot_overwrite_current_round(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            session = _make_session(root)
            _add_round(session, root, "confirm_anchors")
            with self.assertRaisesRegex(live.LivePipelineError, "STALE_REQUEST_REJECTED"):
                session.confirm_anchors({
                    "session_id": session.session_id,
                    "round_id": "R0001-deadbeef",
                    "revision": 0,
                    "anchors": {},
                })

    def test_behavior_declares_only_required_second_anchor(self) -> None:
        self.assertEqual(open_session.BEHAVIOR_ANCHORS["sustained_ranged"][0], "EffectOrigin")
        self.assertEqual(open_session.BEHAVIOR_ANCHORS["returning_thrown"][0], "SpinPivot")
        self.assertEqual(open_session.BEHAVIOR_ANCHORS["heavy_melee"][0], "StrikePoint")
        self.assertEqual(len(open_session.BEHAVIOR_ANCHORS), 3)

    def test_valid_anchors_unlock_training_and_no_object_mapping_is_used(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            session = _make_session(root)
            value = _add_round(session, root, "confirm_anchors")
            result = session.confirm_anchors({
                "session_id": session.session_id,
                "round_id": "R0001-deadbeef",
                "revision": 1,
                "anchors": {
                    "required_anchor_types": ["GripPrimary", "EffectOrigin"],
                    "corrected_anchors": {"GripPrimary": [20, 48], "EffectOrigin": [82, 42]},
                    "anchor_source": {"GripPrimary": "player_confirmed", "EffectOrigin": "player_confirmed"},
                },
            })
            self.assertTrue(result["can_enter_training"])
            self.assertEqual(value.state.stage, "ready_in_training_zone")
        source = (OPEN_ROOT / "bridge" / "open_playtest_session.py").read_text(encoding="utf-8").lower()
        for forbidden in ("vacuum cleaner", "alarm clock", "stapler", "goblet", "umbrella", "gatling", "greatsword"):
            self.assertNotIn(forbidden, source)

    def test_training_records_available_actions_without_formal_rooms(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            session = _make_session(root)
            value = _add_round(session, root, "ready_in_training_zone")
            result = session.complete_training({
                "session_id": session.session_id,
                "round_id": "R0001-deadbeef",
                "revision": 1,
                "moved": True,
                "attacked": True,
                "dodged": True,
            })
            self.assertEqual(result["status"], "training_completed")
            self.assertEqual(value.state.stage, "completed")
            self.assertTrue(value.state.training["entered_training"])

    def test_melee_touch_attack_is_latched_and_range_is_explained(self) -> None:
        arena = (PLAYLAB / "scripts" / "systems" / "gameplay_arena.gd").read_text(encoding="utf-8")
        ui = (OPEN_ROOT / "godot" / "open_playtest.gd").read_text(encoding="utf-8")
        self.assertIn("touch_attack_requested", arena)
        self.assertIn("request_touch_attack", arena)
        self.assertIn("arena.request_touch_attack()", ui)
        self.assertIn("一个武器长度内", ui)
        self.assertIn("只表示输入已触发", ui)

    def test_generated_melee_sprite_visibly_swings_around_primary_grip(self) -> None:
        arena = (PLAYLAB / "scripts" / "systems" / "gameplay_arena.gd").read_text(encoding="utf-8")
        self.assertIn("func _melee_weapon_rotation()", arena)
        self.assertIn("draw_set_transform(hand_primary, weapon_rotation", arena)
        self.assertIn(".rotated(weapon_rotation)", arena)
        self.assertIn("inverse_lerp(0.34, 0.08, melee_timer)", arena)
        self.assertIn("rotation = lerpf(-1.12, 1.18, strike)", arena)

    def test_training_preview_and_combat_feel_are_explicitly_distinguished(self) -> None:
        ui = (OPEN_ROOT / "godot" / "open_playtest.gd").read_text(encoding="utf-8")
        for phrase in (
            "基础训练预览（非完整战斗动作）",
            "这里只验证握持、基础挥动和锚点",
            "这里不提供完整三段连击或正式打击感",
            "基础挥动预览",
            "完整三段攻击仅在 Combat Feel Slice 中测试",
            "当前只是基础预览。完整三连和打击感请进入近战手感测试。",
        ):
            self.assertIn(phrase, ui)

    def test_heavy_melee_identity_prompt_and_primary_handoff_use_real_round(self) -> None:
        ui = (OPEN_ROOT / "godot" / "open_playtest.gd").read_text(encoding="utf-8")
        self.assertIn("该武器支持完整近战手感测试", ui)
        self.assertIn('dialog.ok_button_text = "进入近战手感测试"', ui)
        self.assertIn('dialog.cancel_button_text = "稍后"', ui)
        self.assertIn("dialog.popup_centered(Vector2i(760, 280))", ui)
        self.assertNotIn("dialog.custom_minimum_size", ui)
        self.assertIn('primary_action.call_deferred("grab_focus")', ui)
        self.assertIn('"--open-playtest-round=%s" % round_output_path', ui)
        self.assertIn("and training_asset != null", ui)
        self.assertNotIn("--fixture=", ui)

    def test_round_in_progress_can_resume_without_another_model_request(self) -> None:
        ui = (OPEN_ROOT / "godot" / "open_playtest.gd").read_text(encoding="utf-8")
        self.assertIn("恢复当前进行中的轮次", ui)
        self.assertIn('if reason == "ROUND_IN_PROGRESS"', ui)
        self.assertIn('var recent := await _get_json("/history?', ui)
        self.assertIn('var result := await _get_json(route)', ui)
        self.assertIn("不会创建第二个请求", ui)
        resume_start = ui.index("func _resume_current_round()")
        resume_end = ui.index("func _show_resume_unavailable", resume_start)
        resume_source = ui[resume_start:resume_end]
        self.assertNotIn('"/round/start"', resume_source)
        self.assertNotIn("_start_forge", resume_source)

    def test_save_is_local_and_requires_terminal_round(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            session = _make_session(root)
            value = _add_round(session, root, "completed")
            result = session.save_result({
                "session_id": session.session_id,
                "round_id": "R0001-deadbeef",
                "revision": 1,
                "subjective_rating": 4,
                "keep_idea": True,
                "user_notes": "值得继续",
            })
            self.assertEqual(result["status"], "saved_locally")
            self.assertTrue(value.saved_locally)
            self.assertTrue((root / "history" / "playtest_history.json").is_file())

    def test_server_disables_access_logs_and_limits_request_size(self) -> None:
        source = (OPEN_ROOT / "bridge" / "open_playtest_server.py").read_text(encoding="utf-8")
        self.assertIn("MAX_REQUEST_BYTES", source)
        self.assertIn("127.0.0.1", source)
        self.assertIn("def log_message", source)
        self.assertNotIn("0.0.0.0", source)

    def test_nonterminal_round_blocks_a_second_paid_request(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            session = _make_session(root)
            _add_round(session, root, "image_generating")
            with self.assertRaisesRegex(live.LivePipelineError, "ROUND_IN_PROGRESS"):
                session.start_round({
                    "session_id": session.session_id,
                    "client_request_id": "second-request-123",
                    "player_input": "另一件新物件",
                })

    def test_log_contract_contains_all_requested_fields(self) -> None:
        expected = {
            "timestamp", "user_input", "semantic_summary", "behavior_family",
            "canonical_identity", "display_name", "raw_image_path",
            "processed_sprite_path", "identity_confirmed", "anchor_confirmed",
            "entered_training", "user_notes", "total_forge_seconds",
            "stage_timings_json", "subjective_rating", "keep_idea",
        }
        self.assertTrue(expected.issubset(set(open_session.HISTORY_FIELDS)))

    def test_launcher_prompts_at_most_once_and_clears_secret_environment(self) -> None:
        launcher = (OPEN_ROOT / "scripts" / "run_open_playtest_interactive.ps1").read_text(encoding="utf-8")
        self.assertEqual(launcher.count("Read-Host"), 1)
        self.assertIn("-AsSecureString", launcher)
        self.assertIn("Remove-Item Env:\\ANTHROPIC_API_KEY", launcher)
        self.assertIn("Remove-Item Env:\\FORGE_SEMANTIC_MODEL", launcher)
        self.assertNotIn("Set-Content", launcher)
        self.assertNotIn(".env", launcher)

    def test_launcher_owns_loopback_services_and_stops_them(self) -> None:
        launcher = (OPEN_ROOT / "scripts" / "run_open_playtest_interactive.ps1").read_text(encoding="utf-8")
        self.assertIn("127.0.0.1:8190", launcher)
        self.assertIn("127.0.0.1:8771", launcher)
        self.assertIn("start_live_comfyui.ps1", launcher)
        self.assertIn("stop_live_comfyui.ps1", launcher)
        self.assertIn("OPEN_PLAYTEST_PORT_CLEANUP_FAILED", launcher)

    def test_godot_scene_references_training_only_not_combat_rooms(self) -> None:
        source = (OPEN_ROOT / "godot" / "open_playtest.gd").read_text(encoding="utf-8")
        self.assertIn("live_training_arena.gd", source)
        for forbidden in ("room1.tscn", "room2.tscn", "combat_room", "sketch_canvas"):
            self.assertNotIn(forbidden, source.lower())

    def test_docs_explain_local_only_records_and_continuous_loop(self) -> None:
        readme = (OPEN_ROOT / "README.md").read_text(encoding="utf-8")
        log_format = (OPEN_ROOT / "LOG_FORMAT.md").read_text(encoding="utf-8")
        self.assertIn(".\\scripts\\run_open_playtest.ps1", readme)
        self.assertIn("不是每个点子输入一次", readme)
        self.assertIn("不做云同步", readme)
        self.assertIn("stage_timings", log_format)
        self.assertIn("Key、请求头和未脱敏 API 响应不属于日志合同", log_format)

    def test_live_pipeline_extension_defaults_remain_frozen(self) -> None:
        source = (PLAYLAB / "tools" / "live_e2e" / "bridge" / "live_orchestrator.py").read_text(encoding="utf-8")
        self.assertIn('self.technical_contract = CONTRACT', source)
        self.assertIn('self.flux_output_group = "live_e2e_stage"', source)
        self.assertIn('self.biref_output_namespace = "ForgeLive"', source)

    def test_runtime_paths_are_ignored_but_source_and_docs_are_not(self) -> None:
        ignored = (PLAYLAB / ".gitignore").read_text(encoding="utf-8")
        for entry in ("tools/open_playtest/runtime/", "tools/open_playtest/output/", "tools/open_playtest/local_history/"):
            self.assertIn(entry, ignored)


if __name__ == "__main__":
    unittest.main()
