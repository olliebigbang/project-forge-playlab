extends SceneTree

const PROFILE := preload("res://scripts/combat_feel/combat_motion_profile.gd")
const PRIMITIVE := preload("res://scripts/combat_feel/motion_primitive.gd")
const RECIPE := preload("res://scripts/combat_feel/combo_recipe.gd")
const COMPILER := preload("res://scripts/combat_feel/melee_motion_compiler.gd")
const CONTROLLER := preload("res://scripts/combat_feel/melee_combat_controller.gd")
const FEEDBACK := preload("res://scripts/combat_feel/impact_feedback_profile.gd")
const LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")
const ENEMY := preload("res://scripts/combat_feel/combat_feel_enemy.gd")
const SLICE := preload("res://scripts/combat_feel/combat_feel_slice_0.gd")

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
	_test_34_compiler_outputs_three_valid_independent_primitives()
	_test_35_combo_locks_three_distinct_motion_families()
	_test_36_combo_timeout_returns_to_hit_one_primitive()
	_test_37_buffer_does_not_switch_current_primitive_early()
	_test_38_hitstop_keeps_current_primitive_locked()
	_test_39_slice_executes_current_primitive_consistently()
	_test_40_charge_and_dodge_use_recipe_primitives()
	_test_41_slice_compiles_legacy_live_without_affordance()
	_test_42_attack_press_enters_visible_startup_immediately()
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
	_check(edge_profile.motion_family == "sweep" and body_profile.motion_family == "slam" and point_profile.motion_family == "thrust", "02 legacy impact plus alpha contact mapping")

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
	_check(bool(loaded.get("ok", false)) and not bool(loaded.get("fixture", true)) and str(loaded.get("asset_id", "")) == "giant_wooden_spoon" and str(loaded.get("notice", "")).contains("REAL LIVE FORGE") and loaded.get("affordance_profile") is Resource, "24 default is frozen real Live Forge asset with an explicit affordance sidecar")

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
	_check(ok, "26 legacy alpha anchor motion profiles distinguish long heavy compact crisp and long control")

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
	var loaded: Dictionary = LOADER.new().load_open_playtest_round(round_directory, true)
	var loaded_blueprint := loaded.get("blueprint") as WeaponBlueprint
	var loaded_asset := loaded.get("asset") as WeaponVisualAsset
	var affordance := loaded.get("affordance_profile") as Resource
	var profile: Variant = COMPILER.new().compile(affordance, loaded_asset.anchors_dict(), loaded_asset.opaque_bounds)
	_check(bool(loaded.get("ok", false)) and not bool(loaded.get("fixture", true)) and loaded_blueprint != null and loaded_blueprint.behavior_family == "heavy_melee" and affordance != null and profile is Resource and profile.combo_recipe != null, "32 explicit orthogonal Open Playtest handoff requires and compiles its validated affordance sidecar")

func _test_33_open_playtest_ui_exposes_heavy_only_launch() -> void:
	var godot_source := _text("res://tools/open_playtest/godot/open_playtest.gd")
	var server_source := _text("res://tools/open_playtest/bridge/open_playtest_session.py")
	var ok: bool = godot_source.contains("进入近战手感测试") and godot_source.contains("_can_launch_current_heavy_melee") and godot_source.contains("--open-playtest-round=")
	ok = ok and godot_source.contains('behavior_family", "")) == "heavy_melee"') and godot_source.contains("and _affordance_grammar_ready()") and godot_source.contains("and training_asset != null")
	ok = ok and godot_source.contains("--require-affordance-grammar")
	ok = ok and server_source.contains("round_output_path") and not godot_source.contains("--fixture=")
	_check(ok, "33 Open Playtest exposes direct handoff only for heavy melee with validated affordance grammar")

func _test_34_compiler_outputs_three_valid_independent_primitives() -> void:
	var loaded: Dictionary = LOADER.new().load_fixture("M01")
	var profile: Variant = COMPILER.new().compile(loaded["blueprint"] as WeaponBlueprint, loaded["asset"] as WeaponVisualAsset)
	var recipe: Variant = profile.combo_recipe
	var values: Array = recipe.primitives() if recipe != null else []
	var independent: bool = values.size() == 3
	if independent:
		independent = not is_same(values[0], values[1]) and not is_same(values[0], values[2]) and not is_same(values[1], values[2])
	var finite_validation: bool = independent and recipe.validation_errors().is_empty()
	if finite_validation:
		values[0].start_angle = INF
		finite_validation = not recipe.validation_errors().is_empty()
	_check(independent and finite_validation, "34 compiler emits three valid independent primitives")

func _test_35_combo_locks_three_distinct_motion_families() -> void:
	var controller: Variant = CONTROLLER.new(); var profile: Variant = _mixed_recipe_profile(); controller.configure(profile)
	var families: Array[String] = []
	for index: int in range(3):
		controller.press_attack(); controller.release_attack()
		families.append(controller.current_primitive.motion_family if controller.current_primitive != null else "missing")
		_advance_to_idle(controller)
	_check(families == ["sweep", "thrust", "slam"], "35 hit 1 2 3 lock sweep thrust slam recipe")

func _test_36_combo_timeout_returns_to_hit_one_primitive() -> void:
	var controller: Variant = CONTROLLER.new(); var profile: Variant = _mixed_recipe_profile(); controller.configure(profile)
	controller.press_attack(); controller.release_attack(); _advance_to_idle(controller)
	controller.tick(profile.combo_window_seconds + 0.02)
	controller.press_attack(); controller.release_attack()
	_check(controller.combo_index == 1 and is_same(controller.current_primitive, profile.combo_recipe.hit_1), "36 combo timeout returns to hit one primitive")

func _test_37_buffer_does_not_switch_current_primitive_early() -> void:
	var controller: Variant = CONTROLLER.new(); var profile: Variant = _mixed_recipe_profile(); controller.configure(profile)
	controller.press_attack(); controller.release_attack()
	var first: Variant = controller.current_primitive
	controller.press_attack()
	var stayed_during_buffer: bool = controller.buffered_input and is_same(controller.current_primitive, first)
	controller.tick(controller.current_timing().get("startup", 0.1) + 0.001)
	stayed_during_buffer = stayed_during_buffer and is_same(controller.current_primitive, first)
	controller.tick(controller.current_timing().get("active", 0.1) + 0.001)
	stayed_during_buffer = stayed_during_buffer and controller.phase == "recovery" and is_same(controller.current_primitive, first)
	_check(stayed_during_buffer, "37 buffered input does not switch primitive before next attack")

func _test_38_hitstop_keeps_current_primitive_locked() -> void:
	var controller: Variant = CONTROLLER.new(); controller.configure(_mixed_recipe_profile())
	controller.press_attack(); controller.release_attack()
	controller.tick(controller.current_timing().get("startup", 0.1) + 0.001)
	var first: Variant = controller.current_primitive
	controller.begin_hitstop(0.09); controller.press_attack(); controller.tick(0.05)
	_check(controller.hitstop_remaining > 0.0 and is_same(controller.current_primitive, first), "38 hitstop keeps current primitive locked")

func _test_39_slice_executes_current_primitive_consistently() -> void:
	var source := _text("res://scripts/combat_feel/combat_feel_slice_0.gd")
	var attack_source := _function_source(source, "func _attack_contains", "func _current_damage")
	var pose_source := _function_source(source, "func _weapon_pose", "func _current_attack_primitive")
	var hitbox_source := _function_source(source, "func _draw_active_hitbox", "func _draw_real_weapon_comparison")
	var started_source := _function_source(source, "func _on_attack_started", "func _on_attack_phase_changed")
	var ok: bool = attack_source.contains("_current_attack_primitive()") and attack_source.contains("primitive.hitbox_multiplier")
	ok = ok and pose_source.contains("primitive.start_angle") and pose_source.contains("primitive.end_angle") and pose_source.contains("primitive.extension_pixels")
	ok = ok and hitbox_source.contains("_current_attack_primitive()") and hitbox_source.contains("primitive.hitbox_multiplier")
	ok = ok and started_source.contains("controller.current_primitive") and started_source.contains("primitive.root_motion_distance")
	ok = ok and not attack_source.contains("motion_profile.motion_family") and not hitbox_source.contains("motion_profile.motion_family")
	_check(ok, "39 pose advance collision and debug hitbox share current primitive")

func _test_40_charge_and_dodge_use_recipe_primitives() -> void:
	var profile: Variant = _mixed_recipe_profile(); profile.motion_family = "thrust"
	var controller: Variant = CONTROLLER.new(); controller.configure(profile)
	controller.press_attack(); controller.tick(profile.charge_threshold_seconds + 0.01)
	var charge_ok: bool = controller.attack_kind == "charge" and controller.combo_index == 0 and is_same(controller.current_primitive, profile.combo_recipe.charge_attack)
	controller.reset(); controller.configure(profile); controller.press_dodge(); controller.press_attack()
	var dodge_ok: bool = controller.attack_kind == "dodge" and controller.combo_index == 0 and is_same(controller.current_primitive, profile.combo_recipe.dodge_attack)
	_check(charge_ok and dodge_ok, "40 charge and dodge lock their recipe primitives")

func _test_41_slice_compiles_legacy_live_without_affordance() -> void:
	var loaded: Dictionary = LOADER.new().load_default_live()
	var arena: Variant = SLICE.new()
	arena.compiler = COMPILER.new()
	arena.blueprint = loaded.get("blueprint") as WeaponBlueprint
	arena.asset = loaded.get("asset") as WeaponVisualAsset
	arena.affordance_profile = null
	var compiled: Variant = arena._compile_loaded_weapon()
	var ok: bool = compiled is Resource and compiled.combo_recipe != null and compiled.validation_errors().is_empty()
	arena.free()
	_check(ok, "41 slice compiles legacy Live handoff without affordance sidecar")

func _test_42_attack_press_enters_visible_startup_immediately() -> void:
	var profile: Variant = _mixed_recipe_profile()
	var controller: Variant = CONTROLLER.new(); controller.configure(profile)
	controller.press_attack()
	var immediate: bool = controller.phase == "startup" and controller.priming_attack and is_same(controller.current_primitive, profile.combo_recipe.hit_1)
	controller.press_attack()
	immediate = immediate and not controller.buffered_input
	controller.release_attack()
	controller.tick(float(controller.current_timing().get("startup", 0.1)) + 0.001)
	var committed: bool = controller.phase == "active" and controller.attack_kind == "normal" and is_same(controller.current_primitive, profile.combo_recipe.hit_1)
	_check(immediate and committed, "42 attack press shows hit-one startup on the next frame and release commits it")

func _controller() -> Variant:
	var controller: Variant = CONTROLLER.new(); controller.configure(_profile()); return controller

func _compiled_recipe_asset(asset_id: String) -> Variant:
	var loaded: Dictionary = LOADER.new().load_recipe_asset(asset_id)
	if not bool(loaded.get("ok", false)):
		return COMPILER.UNSUPPORTED
	var visual_asset := loaded.get("asset") as WeaponVisualAsset
	return COMPILER.new().compile(
		loaded.get("affordance_profile") as Resource,
		visual_asset.anchors_dict(),
		visual_asset.opaque_bounds
	)

func _profile() -> Variant:
	var profile: Variant = PROFILE.new(); profile.configure_timing_from_tempo(); return profile

func _mixed_recipe_profile() -> Variant:
	var profile: Variant = _profile()
	var recipe: Variant = RECIPE.new()
	recipe.hit_1 = _test_primitive("sweep", -1.0, 1.0, 0.0)
	recipe.hit_2 = _test_primitive("thrust", -0.08, -0.08, 36.0)
	recipe.hit_3 = _test_primitive("slam", -1.6, 1.0, 0.0)
	recipe.charge_attack = _test_primitive("slam", -1.8, 1.1, 0.0)
	recipe.dodge_attack = _test_primitive("thrust", -0.05, -0.05, 44.0)
	recipe.compile_reason = "test sweep thrust slam recipe"
	profile.combo_recipe = recipe
	return profile

func _test_primitive(family: String, start_angle: float, end_angle: float, extension: float) -> Resource:
	var primitive: Variant = PRIMITIVE.new()
	primitive.motion_family = family
	primitive.start_angle = start_angle
	primitive.end_angle = end_angle
	primitive.extension_pixels = extension
	return primitive

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

func _function_source(source: String, start_marker: String, end_marker: String) -> String:
	var start := source.find(start_marker)
	var end := source.find(end_marker, start + start_marker.length())
	if start < 0 or end < 0:
		return ""
	return source.substr(start, end - start)

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1; print("PASS ", label)
	else:
		failed += 1; push_error("FAIL " + label)
