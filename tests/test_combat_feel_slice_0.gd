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
	print("COMBAT_FEEL_SLICE_0_TESTS passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_01_profile_enums() -> void:
	_check(PROFILE.MOTION_FAMILIES == PackedStringArray(["sweep", "slam", "thrust"]) and PROFILE.WEIGHT_CLASSES.size() == 3 and PROFILE.REACH_CLASSES.size() == 3, "01 profile legal enums")

func _test_02_impact_mapping() -> void:
	var loader: Variant = LOADER.new()
	var compiler: Variant = COMPILER.new()
	var expected := {"strike_edge": "sweep", "whole_body_collision": "slam", "strike_point": "thrust"}
	var ok := true
	for impact: String in expected:
		var loaded: Dictionary = loader.load_fixture("M01")
		var blueprint := loaded["blueprint"] as WeaponBlueprint
		blueprint.impact_mode = impact
		var profile: Variant = compiler.compile(blueprint, loaded["asset"] as WeaponVisualAsset)
		ok = ok and profile.motion_family == expected[impact]
	_check(ok, "02 impact_mode mapping")

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
