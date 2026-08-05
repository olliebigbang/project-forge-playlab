extends SceneTree

const PROFILE := preload("res://scripts/combat_feel/combat_motion_profile.gd")
const COMPILER := preload("res://scripts/combat_feel/melee_motion_compiler.gd")
const CONTROLLER := preload("res://scripts/combat_feel/melee_combat_controller.gd")
const FEEDBACK := preload("res://scripts/combat_feel/impact_feedback_profile.gd")
const LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")
const ENEMY := preload("res://scripts/combat_feel/combat_feel_enemy.gd")

var passed := 0
var failed := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_01_profile_enums()
	_test_02_impact_mapping()
	_test_03_reach_bounded()
	_test_04_weight_bounded()
	_test_05_combo_sequence()
	_test_06_single_input_buffer()
	_test_07_combo_timeout_reset()
	_test_08_charge_threshold()
	_test_09_dodge_attack_window()
	_test_10_legal_cancel_windows()
	_test_11_active_cannot_cancel()
	_test_12_one_hit_per_enemy_per_attack()
	_test_13_finisher_feedback_stronger()
	_test_14_hitstop_preserves_buffer()
	_test_15_slag_puppet_state_order()
	_test_16_ram_locks_direction()
	_test_17_ram_miss_enters_recovery()
	_test_18_room_completion_controls()
	_test_19_non_heavy_rejected()
	_test_20_no_object_specific_attack_classes()
	_test_21_no_model_calls()
	_test_22_formal_repositories_out_of_scope()
	_test_23_no_v2_entry()
	_test_24_default_is_real_live_asset()
	_test_25_live_asset_integrity_and_anchor()
	_test_26_shape_driven_weapon_distinction()
	_test_27_feedback_has_four_clear_tiers()
	_test_28_enemy_recoil_and_launch_input()
	_test_29_whiff_hit_heavy_audio_are_distinct()
	_test_30_no_implicit_fixture_fallback()
	_test_31_missing_real_assets_are_not_misrepresented()
	_test_32_open_playtest_round_direct_handoff()
	_test_33_open_playtest_ui_exposes_heavy_only_launch()
	print("COMBAT_FEEL_SLICE_0_TESTS passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_01_profile_enums() -> void:
	_check(PROFILE.MOTION_FAMILIES == PackedStringArray(["sweep", "slam", "thrust"]) and PROFILE.WEIGHT_CLASSES.size() == 3 and PROFILE.REACH_CLASSES.size() == 3, "01 profile legal enums")

func _test_02_impact_mapping() -> void:
	var loader: Variant = LOADER.new()
	var compiler: Variant = COMPILER.new()
	var broad: Dictionary = loader.load_fixture("M01")
	var broad_blueprint := broad["blueprint"] as WeaponBlueprint
	broad_blueprint.impact_mode = "strike_edge"
	var edge_profile: Variant = compiler.compile(broad_blueprint, broad["asset"] as WeaponVisualAsset)
	broad_blueprint.impact_mode = "whole_body_collision"
	var body_profile: Variant = compiler.compile(broad_blueprint, broad["asset"] as WeaponVisualAsset)
	var narrow: Dictionary = loader.load_fixture("THRUST")
	var narrow_blueprint := narrow["blueprint"] as WeaponBlueprint
	narrow_blueprint.impact_mode = "strike_point"
	var point_profile: Variant = compiler.compile(narrow_blueprint, narrow["asset"] as WeaponVisualAsset)
	_check(edge_profile.motion_family == "sweep" and body_profile.motion_family == "slam" and point_profile.motion_family == "thrust", "02 impact plus alpha contact mapping")

func _test_03_reach_bounded() -> void:
	var loader: Variant = LOADER.new(); var compiler: Variant = COMPILER.new(); var ok := true
	for id: String in ["M01", "M02", "M03", "THRUST"]:
		var loaded: Dictionary = loader.load_fixture(id)
		var profile: Variant = compiler.compile(loaded["blueprint"] as WeaponBlueprint, loaded["asset"] as WeaponVisualAsset)
		ok = ok and profile.reach_class in PROFILE.REACH_CLASSES and profile.reach_pixels >= 84.0 and profile.reach_pixels <= 138.0
	_check(ok, "03 bounded reach classification")

func _test_04_weight_bounded() -> void:
	var loader: Variant = LOADER.new(); var compiler: Variant = COMPILER.new(); var ok := true
	for id: String in ["M01", "M02", "M03"]:
		var loaded: Dictionary = loader.load_fixture(id)
		var profile: Variant = compiler.compile(loaded["blueprint"] as WeaponBlueprint, loaded["asset"] as WeaponVisualAsset)
		ok = ok and profile.weight_class in PROFILE.WEIGHT_CLASSES
	_check(ok, "04 bounded weight classification")

func _test_05_combo_sequence() -> void:
	var controller: Variant = _controller()
	var sequence: Array[int] = []
	for index: int in range(3):
		controller.press_attack(); controller.release_attack(); sequence.append(controller.combo_index)
		_advance_to_idle(controller)
	_check(sequence == [1, 2, 3], "05 three-hit combo order")

func _test_06_single_input_buffer() -> void:
	var controller: Variant = _controller(); controller.press_attack(); controller.release_attack()
	controller.press_attack(); controller.press_attack(); controller.press_attack()
	_check(controller.buffered_input and controller.buffer_age == 0.0, "06 buffer stores one primary input")

func _test_07_combo_timeout_reset() -> void:
	var controller: Variant = _controller(); controller.press_attack(); controller.release_attack(); _advance_to_idle(controller)
	controller.tick(controller.profile.combo_window_seconds + 0.02)
	_check(controller.combo_index == 0, "07 combo timeout reset")

func _test_08_charge_threshold() -> void:
	var controller: Variant = _controller(); controller.press_attack(); controller.tick(controller.profile.charge_threshold_seconds + 0.01); controller.release_attack()
	_check(controller.attack_kind == "charge" and controller.combo_index == 0, "08 charge threshold")

func _test_09_dodge_attack_window() -> void:
	var controller: Variant = _controller(); var dodged: bool = controller.press_dodge(); controller.press_attack(); controller.release_attack()
	_check(dodged and controller.attack_kind == "dodge", "09 dodge attack window")

func _test_10_legal_cancel_windows() -> void:
	var controller: Variant = _controller(); controller.press_attack(); controller.release_attack()
	var early: bool = controller.press_dodge()
	controller.reset(); controller.configure(_profile()); controller.press_attack(); controller.release_attack()
	controller.tick(1.0)
	controller.tick(1.0)
	controller.tick(controller.profile.recovery_seconds * 0.7)
	var late: bool = controller.press_dodge()
	_check(early and late, "10 legal startup/recovery cancels")

func _test_11_active_cannot_cancel() -> void:
	var controller: Variant = _controller(); controller.press_attack(); controller.release_attack(); controller.tick(controller.profile.startup_seconds + 0.001)
	_check(controller.phase == "active" and not controller.press_dodge(), "11 active phase cannot cancel")

func _test_12_one_hit_per_enemy_per_attack() -> void:
	var controller: Variant = _controller(); controller.press_attack(); controller.release_attack(); controller.tick(controller.profile.startup_seconds + 0.001)
	_check(controller.register_hit(7) and not controller.register_hit(7), "12 enemy hit once per attack")

func _test_13_finisher_feedback_stronger() -> void:
	var profile: Variant = _profile(); var first: Variant = FEEDBACK.for_attack(profile, "normal", 1); var third: Variant = FEEDBACK.for_attack(profile, "normal", 3)
	_check(third.hitstop_seconds > first.hitstop_seconds and third.knockback_strength > first.knockback_strength and third.particle_scale > first.particle_scale, "13 third hit feedback stronger")

func _test_14_hitstop_preserves_buffer() -> void:
	var controller: Variant = _controller(); controller.press_attack(); controller.release_attack(); controller.tick(controller.profile.startup_seconds + 0.001)
	controller.begin_hitstop(0.09); controller.press_attack(); controller.tick(0.05)
	_check(controller.buffered_input and controller.hitstop_remaining > 0.0, "14 hitstop preserves buffered input")

func _test_15_slag_puppet_state_order() -> void:
	var enemy: Node2D = ENEMY.new(); enemy.setup(ENEMY.PUPPET, 1, Vector2.ZERO)
	enemy.simulate(0.01, Vector2(30, 0)); var told: bool = enemy.state == "tell"
	enemy.simulate(enemy.tell_seconds + 0.01, Vector2(30, 0)); var attacked: bool = enemy.state == "attack"
	enemy.simulate(0.22, Vector2(300, 0)); var recovered: bool = enemy.state == "recovery"
	_check(told and attacked and recovered, "15 Slag Puppet tell/attack/recovery")
	enemy.free()

func _test_16_ram_locks_direction() -> void:
	var enemy: Node2D = ENEMY.new(); enemy.setup(ENEMY.RAM, 2, Vector2(500, 400)); enemy.force_state("tell")
	enemy.simulate(enemy.tell_seconds + 0.01, Vector2(800, 400)); var locked: Vector2 = enemy.locked_direction
	enemy.simulate(0.1, Vector2(200, 600))
	_check(enemy.state == "charge" and enemy.locked_direction.is_equal_approx(locked), "16 Forge Ram direction remains locked")
	enemy.free()

func _test_17_ram_miss_enters_recovery() -> void:
	var enemy: Node2D = ENEMY.new(); enemy.setup(ENEMY.RAM, 2, Vector2(1220, 400)); enemy.force_state("charge"); enemy.locked_direction = Vector2.RIGHT
	enemy.simulate(0.1, Vector2(200, 400))
	_check(enemy.state == "recovery", "17 Forge Ram miss/boundary recovery")
	enemy.free()

func _test_18_room_completion_controls() -> void:
	var text := _text("res://scripts/combat_feel/combat_feel_slice_0.gd")
	_check(text.contains("VICTORY") and text.contains("DEFEAT") and text.contains("RETRY") and text.contains("RETURN TO FORGE"), "18 victory defeat retry controls")

func _test_19_non_heavy_rejected() -> void:
	_check(LOADER.behavior_supported("heavy_melee") and not LOADER.behavior_supported("sustained_ranged") and not LOADER.behavior_supported("returning_thrown"), "19 non-heavy entry rejected")

func _test_20_no_object_specific_attack_classes() -> void:
	var filenames := DirAccess.get_files_at("res://scripts/combat_feel")
	var joined := " ".join(filenames).to_lower()
	var compiler_text := _text("res://scripts/combat_feel/melee_motion_compiler.gd")
	_check(not joined.contains("spoon") and not joined.contains("pan") and not joined.contains("mop") and not compiler_text.contains("木勺") and not compiler_text.contains("平底锅") and not compiler_text.contains("拖把"), "20 no object-specific attack class or mapping")

func _test_21_no_model_calls() -> void:
	var combined := _combat_source().to_lower()
	_check(not combined.contains("httprequest") and not combined.contains("anthropic_api_key") and not combined.contains("comfyui") and not combined.contains("birefnet") and not combined.contains("flux"), "21 no Anthropic FLUX or BiRefNet calls")

func _test_22_formal_repositories_out_of_scope() -> void:
	var combined := _combat_source().to_lower()
	_check(not combined.contains("project-forge-claude") and not combined.contains("documents/project forge") and not combined.contains("documents\\project forge"), "22 formal repositories out of scope")

func _test_23_no_v2_entry() -> void:
	var combined := _combat_source().to_lower()
	_check(not combined.contains("--mode=v2") and not combined.contains("start_v2") and not combined.contains("combat_feel_slice_1"), "23 no V2 entry")

func _test_24_default_is_real_live_asset() -> void:
	var loaded: Dictionary = LOADER.new().load_default_live()
	_check(bool(loaded.get("ok", false)) and not bool(loaded.get("fixture", true)) and str(loaded.get("asset_id", "")) == "giant_wooden_spoon" and str(loaded.get("notice", "")).contains("REAL LIVE FORGE"), "24 default is frozen real Live Forge asset")

func _test_25_live_asset_integrity_and_anchor() -> void:
	var loaded: Dictionary = LOADER.new().load_frozen_live("giant_wooden_spoon")
	var live_asset := loaded.get("asset") as WeaponVisualAsset
	var live_blueprint := loaded.get("blueprint") as WeaponBlueprint
	var ok: bool = bool(loaded.get("ok", false)) and live_asset != null and live_blueprint != null
	if ok:
		ok = live_asset.canvas_size == Vector2i(96, 96) and live_asset.anchor_source == "live_player_confirmed" and live_asset.grip_primary.is_equal_approx(Vector2(17, 64)) and live_asset.tip.is_equal_approx(Vector2(88, 25)) and live_blueprint.behavior_family == "heavy_melee"
	_check(ok, "25 real sprite hash alpha blueprint and confirmed anchor")

func _test_26_shape_driven_weapon_distinction() -> void:
	var loader: Variant = LOADER.new(); var compiler: Variant = COMPILER.new()
	var profiles: Array = []
	for id: String in ["M01", "M02", "M03"]:
		var loaded: Dictionary = loader.load_fixture(id)
		profiles.append(compiler.compile(loaded["blueprint"] as WeaponBlueprint, loaded["asset"] as WeaponVisualAsset))
	var ok: bool = profiles[0].reach_class == "long" and profiles[0].tempo == "committed"
	ok = ok and profiles[1].reach_class == "short" and profiles[1].tempo == "rapid" and profiles[1].motion_family == "slam"
	ok = ok and profiles[2].reach_class == "long" and profiles[2].tempo == "balanced" and profiles[2].motion_family == "sweep"
	ok = ok and profiles[2].control_strength > profiles[1].control_strength
	_check(ok, "26 generic alpha anchor motion profiles distinguish long heavy compact crisp and long control")

func _test_27_feedback_has_four_clear_tiers() -> void:
	var profile: Variant = _profile()
	var first: Variant = FEEDBACK.for_attack(profile, "normal", 1)
	var second: Variant = FEEDBACK.for_attack(profile, "normal", 2)
	var third: Variant = FEEDBACK.for_attack(profile, "normal", 3)
	var charge: Variant = FEEDBACK.for_attack(profile, "charge", 0)
	_check(first.hitstop_seconds < second.hitstop_seconds and second.hitstop_seconds < third.hitstop_seconds and third.hitstop_seconds < charge.hitstop_seconds and third.ring_count >= 2 and charge.launch_strength > third.launch_strength, "27 first second third charge feedback tiers")

func _test_28_enemy_recoil_and_launch_input() -> void:
	var enemy: Node2D = ENEMY.new(); enemy.setup(ENEMY.PUPPET, 9, Vector2(500, 400))
	var applied: bool = enemy.apply_hit(10.0, Vector2(220, -88), 1.2, 17.0)
	_check(applied and enemy.stagger_time >= 0.82 and absf(enemy.recoil_tilt) > 0.1 and enemy.velocity.y < 0.0, "28 enemy recoil stagger knockback and launch")
	enemy.free()

func _test_29_whiff_hit_heavy_audio_are_distinct() -> void:
	var source := _text("res://scripts/combat_feel/combat_feel_slice_0.gd")
	_check(source.contains("\"whiff\"") and source.contains("\"hit\"") and source.contains("\"heavy_hit\"") and source.contains("_on_attack_phase_changed"), "29 whiff hit heavy-hit audio paths")

func _test_30_no_implicit_fixture_fallback() -> void:
	var scene_source := _text("res://scripts/combat_feel/combat_feel_slice_0.gd")
	var runner_source := _text("res://scripts/run_combat_feel_slice.ps1")
	_check(not scene_source.contains("_argument_value(\"--fixture=\"") and scene_source.contains("load_default_live") and runner_source.contains("--live-weapon") and runner_source.contains("--developer-fixture"), "30 no implicit developer fixture fallback")

func _test_31_missing_real_assets_are_not_misrepresented() -> void:
	var index_text := _text("res://data/combat_feel/live_assets/revision_a/index.json")
	var parsed: Variant = JSON.parse_string(index_text)
	var index: Dictionary = parsed if parsed is Dictionary else {}
	var missing: Array = index.get("missing_required_verification_assets", [])
	_check(missing.size() == 2 and index_text.contains("NO_FROZEN_REAL_OPEN_PLAYTEST_RESULT_FOUND") and not index_text.contains("developer_fixture"), "31 absent frying pan and mop stay explicit rather than fake Live assets")

func _test_32_open_playtest_round_direct_handoff() -> void:
	var round_directory := ProjectSettings.globalize_path("res://data/combat_feel/live_assets/revision_a/giant_wooden_spoon")
	var loaded: Dictionary = LOADER.new().load_open_playtest_round(round_directory)
	var loaded_blueprint := loaded.get("blueprint") as WeaponBlueprint
	_check(bool(loaded.get("ok", false)) and not bool(loaded.get("fixture", true)) and loaded_blueprint != null and loaded_blueprint.behavior_family == "heavy_melee", "32 finalized Open Playtest directory loads directly")

func _test_33_open_playtest_ui_exposes_heavy_only_launch() -> void:
	var godot_source := _text("res://tools/open_playtest/godot/open_playtest.gd")
	var server_source := _text("res://tools/open_playtest/bridge/open_playtest_session.py")
	var ok: bool = godot_source.contains("进入近战手感测试") and godot_source.contains("_can_launch_current_heavy_melee") and godot_source.contains("--open-playtest-round=")
	ok = ok and godot_source.contains('behavior_family", "")) == "heavy_melee"') and godot_source.contains("and training_asset != null")
	ok = ok and server_source.contains("round_output_path") and not godot_source.contains("--fixture=")
	_check(ok, "33 Open Playtest exposes direct handoff only for heavy melee")

func _controller() -> Variant:
	var controller: Variant = CONTROLLER.new(); controller.configure(_profile()); return controller

func _profile() -> Variant:
	var profile: Variant = PROFILE.new(); profile.configure_timing_from_tempo(); return profile

func _advance_to_idle(controller: Variant) -> void:
	controller.tick(1.0)
	controller.tick(1.0)
	controller.tick(1.0)

func _combat_source() -> String:
	var combined := ""
	for filename: String in DirAccess.get_files_at("res://scripts/combat_feel"):
		if filename.ends_with(".gd"): combined += _text("res://scripts/combat_feel/" + filename)
	return combined

func _text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1; print("PASS ", label)
	else:
		failed += 1; push_error("FAIL " + label)
