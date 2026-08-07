extends SceneTree

const AFFORDANCE := preload("res://scripts/combat_feel/object_affordance_profile.gd")
const COMPILER := preload("res://scripts/combat_feel/melee_motion_compiler.gd")
const CONTROLLER := preload("res://scripts/combat_feel/melee_combat_controller.gd")
const FEEDBACK := preload("res://scripts/combat_feel/impact_feedback_profile.gd")
const LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")
const PRIMITIVE := preload("res://scripts/combat_feel/motion_primitive.gd")
const SLICE_PATH := "res://scripts/combat_feel/combat_feel_slice_0.gd"

var passed := 0
var failed := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_real_assets_and_developer_boundary()
	_test_five_primitives_are_legal()
	_test_three_structure_rules()
	_test_compiler_structure_signature_has_no_identity()
	_test_identical_structure_compiles_identically()
	_test_different_structure_compiles_differently()
	_test_unsupported_fails_closed()
	_test_runtime_uses_each_hit_primitive()
	_test_shotgun_rear_contact()
	_test_per_hit_spatial_and_feedback_are_consumed()
	_test_exported_recipes_match_runtime()
	_test_shotgun_entry_is_visible_and_selectable()
	print("MOTION_GRAMMAR_SLICE_1A_TESTS passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _test_real_assets_and_developer_boundary() -> void:
	var loader: Variant = LOADER.new()
	var pan: Dictionary = loader.load_motion_grammar_asset("frying_pan")
	var broom: Dictionary = loader.load_motion_grammar_asset("old_mop")
	var shotgun: Dictionary = loader.load_motion_grammar_asset("shotgun_melee")
	var ok: bool = bool(pan.get("ok", false)) and bool(broom.get("ok", false)) and bool(shotgun.get("ok", false))
	ok = ok and (pan.get("asset") as WeaponVisualAsset).source_image.get_size() == Vector2i(96, 96)
	ok = ok and (broom.get("asset") as WeaponVisualAsset).source_image.get_size() == Vector2i(96, 96)
	ok = ok and (shotgun.get("asset") as WeaponVisualAsset).source_image.get_size() == Vector2i(96, 96)
	ok = ok and bool(shotgun.get("developer_only", false)) and not bool(shotgun.get("normal_player_flow", true))
	ok = ok and str(shotgun.get("source_behavior_family", "")) == "sustained_ranged"
	ok = ok and (shotgun.get("blueprint") as WeaponBlueprint).behavior_family == "heavy_melee"
	_check(ok, "01 three real assets load; shotgun override remains developer-only and in-memory")


func _test_five_primitives_are_legal() -> void:
	var ok: bool = PRIMITIVE.MOTION_FAMILIES == PackedStringArray(["bash", "sweep", "thrust", "slam", "spin"])
	for family: String in PRIMITIVE.MOTION_FAMILIES:
		var primitive: Variant = PRIMITIVE.new()
		primitive.motion_family = family
		ok = ok and primitive.validation_errors().is_empty()
	_check(ok, "02 exactly five generic motion primitives validate")


func _test_three_structure_rules() -> void:
	var pan: Resource = _compiled("frying_pan") as Resource
	var broom: Resource = _compiled("old_mop") as Resource
	var shotgun: Resource = _compiled("shotgun_melee") as Resource
	var ok: bool = pan != null and broom != null and shotgun != null
	if ok:
		ok = pan.combo_recipe.primitive_sequence() == PackedStringArray(["bash", "bash", "slam"])
		ok = ok and broom.combo_recipe.primitive_sequence() == PackedStringArray(["sweep", "thrust", "spin"])
		ok = ok and shotgun.combo_recipe.primitive_sequence() == PackedStringArray(["thrust", "sweep", "bash"])
		ok = ok and pan.combo_recipe.signature() != broom.combo_recipe.signature()
		ok = ok and pan.combo_recipe.signature() != shotgun.combo_recipe.signature()
		ok = ok and broom.combo_recipe.signature() != shotgun.combo_recipe.signature()
	_check(ok, "03 Rules A B C produce distinct bash/bash/slam sweep/thrust/spin thrust/sweep/bash recipes")


func _test_compiler_structure_signature_has_no_identity() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/combat_feel/melee_motion_compiler.gd")
	var start := source.find("func _compile_affordance")
	var finish := source.find("func _compile_legacy", start)
	var structure_source := source.substr(start, finish - start) if start >= 0 and finish > start else ""
	var lowered := structure_source.to_lower()
	var ok: bool = structure_source.contains("affordance_profile: Resource, anchor_data: Dictionary, alpha_bounds: Rect2i")
	for forbidden: String in ["weaponblueprint", "display_name", "canonical_name", "source_identity", "player_identity", "asset_id", "run_id", "pan", "broom", "shotgun"]:
		ok = ok and not lowered.contains(forbidden)
	_check(ok, "04 structure compiler accepts affordance anchors bounds and no object identity")


func _test_identical_structure_compiles_identically() -> void:
	var loaded: Dictionary = LOADER.new().load_motion_grammar_asset("frying_pan")
	var original: Resource = loaded.get("affordance_profile") as Resource
	var duplicate: Resource = _copy_affordance(original)
	var asset := loaded.get("asset") as WeaponVisualAsset
	var first: Variant = COMPILER.new().compile(original, asset.anchors_dict(), asset.opaque_bounds)
	var second: Variant = COMPILER.new().compile(duplicate, asset.anchors_dict(), asset.opaque_bounds)
	_check(first.combo_recipe.signature() == second.combo_recipe.signature(), "05 identical affordance compiles identically without a name input")


func _test_different_structure_compiles_differently() -> void:
	var pan: Resource = _compiled("frying_pan") as Resource
	var broom: Resource = _compiled("old_mop") as Resource
	_check(pan.combo_recipe.signature() != broom.combo_recipe.signature(), "06 different affordance compiles differently even though compiler receives no name")


func _test_unsupported_fails_closed() -> void:
	var loaded: Dictionary = LOADER.new().load_motion_grammar_asset("frying_pan")
	var asset := loaded.get("asset") as WeaponVisualAsset
	var unsupported: Variant = AFFORDANCE.new()
	unsupported.handle_length = "medium"
	unsupported.body_length = "medium"
	unsupported.rigidity = "flexible"
	unsupported.mass_distribution = "balanced"
	unsupported.contact_surface = "edge"
	unsupported.has_edge = true
	var result: Variant = COMPILER.new().compile(unsupported, asset.anchors_dict(), asset.opaque_bounds)
	_check(result == "UNSUPPORTED_AFFORDANCE_FOR_SLICE_1A", "07 unmatched affordance fails closed with the exact error")


func _test_runtime_uses_each_hit_primitive() -> void:
	var ok: bool = _runtime_sequence(_compiled("frying_pan")) == PackedStringArray(["bash", "bash", "slam"])
	ok = ok and _runtime_sequence(_compiled("old_mop")) == PackedStringArray(["sweep", "thrust", "spin"])
	ok = ok and _runtime_sequence(_compiled("shotgun_melee")) == PackedStringArray(["thrust", "sweep", "bash"])
	_check(ok, "08 existing controller locks and executes each recipe hit in order")


func _test_shotgun_rear_contact() -> void:
	var loaded: Dictionary = LOADER.new().load_motion_grammar_asset("shotgun_melee")
	var asset := loaded.get("asset") as WeaponVisualAsset
	var profile: Resource = _compiled("shotgun_melee") as Resource
	var hit_three: Variant = profile.combo_recipe.hit_3
	var ok: bool = hit_three.contact_anchor == "rear_contact"
	ok = ok and asset.muzzle.x > asset.grip_primary.x and asset.rear_contact.x < asset.grip_primary.x
	ok = ok and asset.rear_contact != asset.grip_primary
	_check(ok, "09 barrel-stock Rule C third hit uses normalized rear contact")


func _test_per_hit_spatial_and_feedback_are_consumed() -> void:
	var shotgun: Resource = _compiled("shotgun_melee") as Resource
	var first: Variant = shotgun.combo_recipe.hit_1
	var third: Variant = shotgun.combo_recipe.hit_3
	var first_feedback: Resource = FEEDBACK.for_attack(shotgun, "normal", 1, first)
	var third_feedback: Resource = FEEDBACK.for_attack(shotgun, "normal", 3, third)
	var source := FileAccess.get_file_as_string(SLICE_PATH)
	var ok: bool = first.root_motion_distance != third.root_motion_distance
	ok = ok and first.hitbox_width_multiplier != third.hitbox_width_multiplier
	ok = ok and third_feedback.hitstop_seconds > first_feedback.hitstop_seconds
	ok = ok and source.contains("primitive.root_motion_distance")
	ok = ok and source.contains("primitive.hitbox_width_multiplier")
	ok = ok and source.contains("primitive.hitbox_length_multiplier")
	ok = ok and source.contains("FEEDBACK.for_attack(motion_profile, controller.attack_kind, controller.combo_index, controller.current_primitive)")
	ok = ok and source.contains("primitive.movement_allowed_ratio")
	_check(ok, "10 runtime consumes primitive root motion hitbox movement and impact multipliers")


func _test_exported_recipes_match_runtime() -> void:
	var ok := true
	for asset_id: String in ["frying_pan", "old_mop", "shotgun_melee"]:
		var path := "res://data/combat_feel/live_assets/motion_grammar_slice_1a/recipes/%s.json" % asset_id
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary:
			ok = false
			continue
		var recipe_data: Dictionary = parsed.get("combo_recipe", {})
		var profile: Resource = _compiled(asset_id) as Resource
		ok = ok and str(recipe_data.get("recipe_signature", "")) == profile.combo_recipe.signature()
	_check(ok, "11 exported recipe JSON matches the deterministic runtime compiler output")


func _test_shotgun_entry_is_visible_and_selectable() -> void:
	var runner := FileAccess.get_file_as_string("res://scripts/run_motion_grammar_slice_1a.ps1")
	var slice_source := FileAccess.get_file_as_string(SLICE_PATH)
	var ok := runner.contains("3. Shotgun melee")
	ok = ok and runner.contains("ShotgunMelee") and runner.contains("shotgun_melee")
	ok = ok and slice_source.contains("SHOTGUN STOCK MELEE — DEV OVERRIDE")
	ok = ok and slice_source.contains("ASSET %s  |  ACTUAL RECIPE")
	_check(ok, "12 launcher exposes Shotgun and the scene identifies the loaded asset")


func _compiled(asset_id: String) -> Variant:
	var loaded: Dictionary = LOADER.new().load_motion_grammar_asset(asset_id)
	if not bool(loaded.get("ok", false)):
		return null
	var asset := loaded.get("asset") as WeaponVisualAsset
	return COMPILER.new().compile(loaded.get("affordance_profile") as Resource, asset.anchors_dict(), asset.opaque_bounds)


func _runtime_sequence(profile: Resource) -> PackedStringArray:
	var controller: Variant = CONTROLLER.new()
	controller.configure(profile)
	var sequence := PackedStringArray()
	for _index: int in range(3):
		controller.press_attack()
		controller.release_attack()
		sequence.append(str(controller.current_primitive.motion_family))
		controller.tick(1.0)
		controller.tick(1.0)
		controller.tick(1.0)
	return sequence


func _copy_affordance(source: Resource) -> Resource:
	var copied: Variant = AFFORDANCE.new()
	for property: String in [
		"handle_length", "body_length", "rigidity", "mass_distribution", "contact_surface",
		"has_point", "has_edge", "has_broad_face", "has_barrel", "has_stock",
	]:
		copied.set(property, source.get(property))
	return copied


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		push_error("FAIL " + label)
