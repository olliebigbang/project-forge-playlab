extends SceneTree

const AFFORDANCE := preload("res://scripts/combat_feel/object_affordance_profile.gd")
const COMPILER := preload("res://scripts/combat_feel/melee_motion_compiler.gd")
const CONTROLLER := preload("res://scripts/combat_feel/melee_combat_controller.gd")
const FEEDBACK := preload("res://scripts/combat_feel/impact_feedback_profile.gd")
const LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")
const SLICE := preload("res://scripts/combat_feel/combat_feel_slice_0.gd")

var passed := 0
var failed := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_real_asset_evidence()
	_test_pan_recipe()
	_test_broom_recipe()
	_test_recipe_signatures_and_gameplay_differ()
	_test_compiler_has_no_identity_input()
	_test_same_structure_ignores_different_names()
	_test_unsupported_has_no_sweep_fallback()
	_test_runtime_executes_each_recipe_primitive()
	_test_spin_has_stronger_multi_target_coverage()
	print("PAN_BROOM_RECIPE_SLICE_1B_TESTS passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _test_real_asset_evidence() -> void:
	var pan: Dictionary = LOADER.new().load_recipe_asset("frying_pan")
	var broom: Dictionary = LOADER.new().load_recipe_asset("old_mop")
	var ok: bool = bool(pan.get("ok", false)) and bool(broom.get("ok", false))
	ok = ok and str(pan.get("source_round_id", "")) == "R0001-17630115"
	ok = ok and str(broom.get("source_round_id", "")) == "R0020-03582d76"
	ok = ok and (pan.get("asset") as WeaponVisualAsset).anchor_source == "live_player_confirmed"
	ok = ok and (broom.get("asset") as WeaponVisualAsset).anchor_source == "live_player_confirmed"
	_check(ok, "01 frozen player-confirmed pan and mop evidence loads with hashes")


func _test_pan_recipe() -> void:
	var profile: Variant = _compiled("frying_pan")
	var ok: bool = profile is Resource
	if ok:
		ok = profile.combo_recipe.primitive_sequence() == PackedStringArray(["bash", "bash", "slam"])
		ok = ok and profile.combo_recipe.hit_2.start_angle > profile.combo_recipe.hit_2.end_angle
	_check(ok, "02 short short front broad compiles bash bash reverse then slam")


func _test_broom_recipe() -> void:
	var profile: Variant = _compiled("old_mop")
	var ok: bool = profile is Resource
	if ok:
		ok = profile.combo_recipe.primitive_sequence() == PackedStringArray(["sweep", "thrust", "spin"])
		ok = ok and profile.combo_recipe.hit_2.extension_pixels > 0.0
		ok = ok and absf(profile.combo_recipe.hit_3.end_angle - profile.combo_recipe.hit_3.start_angle) > TAU * 0.90
	_check(ok, "03 long long broad compiles sweep thrust push then spin")


func _test_recipe_signatures_and_gameplay_differ() -> void:
	var pan: Variant = _compiled("frying_pan")
	var broom: Variant = _compiled("old_mop")
	var pan_first: Variant = pan.combo_recipe.hit_1
	var broom_first: Variant = broom.combo_recipe.hit_1
	var pan_hitstop: Resource = FEEDBACK.for_attack(pan, "normal", 1)
	var broom_hitstop: Resource = FEEDBACK.for_attack(broom, "normal", 1)
	var differences := 0
	if pan.combo_recipe.signature() != broom.combo_recipe.signature(): differences += 1
	if pan.reach_pixels < broom.reach_pixels: differences += 1
	if pan.timing_for("normal", 1, pan_first).startup < broom.timing_for("normal", 1, broom_first).startup: differences += 1
	if pan_first.movement_multiplier < broom_first.movement_multiplier: differences += 1
	if pan.hitbox_thickness * pan_first.hitbox_multiplier < broom.hitbox_thickness * broom_first.hitbox_multiplier: differences += 1
	if pan_hitstop.hitstop_seconds > broom_hitstop.hitstop_seconds: differences += 1
	_check(differences >= 5, "04 signatures and at least three real gameplay dimensions differ")


func _test_compiler_has_no_identity_input() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/combat_feel/melee_motion_compiler.gd")
	var lowered := source.to_lower()
	var ok := source.contains("func compile(affordance_profile: Resource, anchor_data: Dictionary, alpha_bounds: Rect2i)")
	for forbidden: String in ["weaponblueprint", "display_name", "canonical_name", "player_identity", "player_text", "source_identity"]:
		ok = ok and not lowered.contains(forbidden)
	_check(ok, "05 compiler reads structure anchors and alpha bounds but no identity text")


func _test_same_structure_ignores_different_names() -> void:
	var loaded: Dictionary = LOADER.new().load_recipe_asset("frying_pan")
	var asset := loaded.get("asset") as WeaponVisualAsset
	var first_profile: Resource = loaded.get("affordance_profile") as Resource
	var second_profile: Variant = AFFORDANCE.new()
	second_profile.handle_length = first_profile.handle_length
	second_profile.body_length = first_profile.body_length
	second_profile.mass_distribution = first_profile.mass_distribution
	second_profile.contact_surface = first_profile.contact_surface
	second_profile.rigidity = first_profile.rigidity
	var first_name := "Kitchen Pan Alpha"
	var second_name := "Unrelated Label Beta"
	var first: Variant = COMPILER.new().compile(first_profile, asset.anchors_dict(), asset.opaque_bounds)
	var second: Variant = COMPILER.new().compile(second_profile, asset.anchors_dict(), asset.opaque_bounds)
	var ok: bool = first_name != second_name and first.combo_recipe.signature() == second.combo_recipe.signature()
	ok = ok and is_equal_approx(first.reach_pixels, second.reach_pixels)
	_check(ok, "06 different names with identical structure compile identically")


func _test_unsupported_has_no_sweep_fallback() -> void:
	var loaded: Dictionary = LOADER.new().load_recipe_asset("frying_pan")
	var asset := loaded.get("asset") as WeaponVisualAsset
	var unmatched: Variant = AFFORDANCE.new()
	unmatched.handle_length = "medium"
	unmatched.body_length = "long"
	unmatched.mass_distribution = "rear"
	unmatched.contact_surface = "edge"
	unmatched.rigidity = "flexible"
	var result: Variant = COMPILER.new().compile(unmatched, asset.anchors_dict(), asset.opaque_bounds)
	_check(result == COMPILER.UNSUPPORTED, "07 unmatched structure returns unsupported without sweep fallback")


func _test_runtime_executes_each_recipe_primitive() -> void:
	var pan_sequence := _runtime_sequence(_compiled("frying_pan"))
	var broom_sequence := _runtime_sequence(_compiled("old_mop"))
	_check(
		pan_sequence == PackedStringArray(["bash", "bash", "slam"])
		and broom_sequence == PackedStringArray(["sweep", "thrust", "spin"]),
		"08 runtime locks hit one two three to each compiled primitive"
	)


func _test_spin_has_stronger_multi_target_coverage() -> void:
	var broom_profile: Resource = _compiled("old_mop") as Resource
	var broom_arena: Variant = _arena_on_hit(broom_profile, 3)
	var broom_hand: Vector2 = broom_arena._hand_world_position()
	var broom_front: bool = broom_arena._attack_contains(broom_hand + Vector2(92, 0))
	var broom_rear: bool = broom_arena._attack_contains(broom_hand + Vector2(-92, 0))
	var pan_profile: Resource = _compiled("frying_pan") as Resource
	var pan_arena: Variant = _arena_on_hit(pan_profile, 3)
	var pan_hand: Vector2 = pan_arena._hand_world_position()
	var pan_front: bool = pan_arena._attack_contains(pan_hand + Vector2(56, 28))
	var pan_rear: bool = pan_arena._attack_contains(pan_hand + Vector2(-56, 0))
	broom_arena.free()
	pan_arena.free()
	_check(broom_front and broom_rear and pan_front and not pan_rear, "09 spin covers front and rear targets while slam stays focused")


func _compiled(asset_id: String) -> Variant:
	var loaded: Dictionary = LOADER.new().load_recipe_asset(asset_id)
	if not bool(loaded.get("ok", false)):
		return COMPILER.UNSUPPORTED
	var asset := loaded.get("asset") as WeaponVisualAsset
	return COMPILER.new().compile(
		loaded.get("affordance_profile") as Resource,
		asset.anchors_dict(),
		asset.opaque_bounds
	)


func _runtime_sequence(profile: Resource) -> PackedStringArray:
	var controller: Variant = CONTROLLER.new()
	controller.configure(profile)
	var sequence := PackedStringArray()
	for hit_index: int in range(3):
		controller.press_attack()
		controller.release_attack()
		sequence.append(str(controller.current_primitive.motion_family))
		_advance_to_idle(controller)
	return sequence


func _arena_on_hit(profile: Resource, hit_index: int) -> Variant:
	var arena: Variant = SLICE.new()
	arena.motion_profile = profile
	arena.controller = CONTROLLER.new()
	arena.controller.configure(profile)
	arena.player_position = Vector2(300, 400)
	arena.player_facing = 1.0
	for index: int in range(1, hit_index + 1):
		arena.controller.press_attack()
		arena.controller.release_attack()
		if index < hit_index:
			_advance_to_idle(arena.controller)
	arena.controller.tick(float(arena.controller.current_timing().get("startup", 0.1)) + 0.001)
	return arena


func _advance_to_idle(controller: Variant) -> void:
	controller.tick(1.0)
	controller.tick(1.0)
	controller.tick(1.0)


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		push_error("FAIL " + label)
