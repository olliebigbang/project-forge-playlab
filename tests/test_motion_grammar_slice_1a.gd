extends SceneTree

const AFFORDANCE := preload("res://scripts/combat_feel/object_affordance_profile.gd")
const COMPILER := preload("res://scripts/combat_feel/melee_motion_compiler.gd")
const CONTROLLER := preload("res://scripts/combat_feel/melee_combat_controller.gd")
const FEEDBACK := preload("res://scripts/combat_feel/impact_feedback_profile.gd")
const LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")
const PRIMITIVE := preload("res://scripts/combat_feel/motion_primitive.gd")
const SLICE := preload("res://scripts/combat_feel/combat_feel_slice_0.gd")
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
	_test_all_five_primitives_execute_across_real_recipes()
	_test_charge_and_dodge_execute_recipe_primitives()
	_test_press_response_and_visible_articulated_poses()
	_test_blind_comparison_contract()
	_test_failed_blind_dimensions_have_clear_margin()
	_test_rule_c_contact_reliability()
	_test_per_hit_attempt_stats_contract()
	_test_handleless_affordance_loader_contract()
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
		ok = pan.combo_recipe.validation_errors().is_empty()
		ok = ok and broom.combo_recipe.validation_errors().is_empty()
		ok = ok and shotgun.combo_recipe.validation_errors().is_empty()
		ok = ok and pan.combo_recipe.signature() != broom.combo_recipe.signature()
		ok = ok and pan.combo_recipe.signature() != shotgun.combo_recipe.signature()
		ok = ok and broom.combo_recipe.signature() != shotgun.combo_recipe.signature()
		ok = ok and pan.compile_trace.get("composer") == "orthogonal_affordance_v1"
		ok = ok and not bool(pan.compile_trace.get("identity_inputs_used", true))
	_check(ok, "03 distinct affordance axes produce valid distinct recipes with an identity-free trace")


func _test_compiler_structure_signature_has_no_identity() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/combat_feel/melee_motion_compiler.gd")
	var start := source.find("func _compile_affordance")
	var finish := source.find("func _compile_legacy", start)
	var compose_start := source.find("func _compose_orthogonal_profile")
	var compose_finish := source.find("func _primitive", compose_start)
	var structure_source := source.substr(start, finish - start) if start >= 0 and finish > start else ""
	if compose_start >= 0 and compose_finish > compose_start:
		structure_source += source.substr(compose_start, compose_finish - compose_start)
	var lowered := structure_source.to_lower()
	var ok: bool = structure_source.contains("affordance_profile: Resource, anchor_data: Dictionary, alpha_bounds: Rect2i")
	for forbidden: String in ["weaponblueprint", "display_name", "canonical_name", "source_identity", "player_identity", "asset_id", "run_id", "frying_pan", "old_mop", "shotgun_melee"]:
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
	unsupported.handle_length = "none"
	unsupported.body_length = "medium"
	unsupported.grip_topology = "one_hand_handle"
	unsupported.rigidity = "flexible"
	unsupported.mass_distribution = "balanced"
	unsupported.contact_surface = "edge"
	unsupported.secondary_contact_surface = "none"
	unsupported.has_edge = true
	var result: Variant = COMPILER.new().compile(unsupported, asset.anchors_dict(), asset.opaque_bounds)
	_check(result == "UNSUPPORTED_AFFORDANCE_FOR_SLICE_1A", "07 incomplete or contradictory affordance fails closed instead of using a sweep fallback")


func _test_runtime_uses_each_hit_primitive() -> void:
	var ok := true
	for asset_id: String in ["frying_pan", "old_mop", "shotgun_melee"]:
		var profile: Resource = _compiled(asset_id) as Resource
		var expected: PackedStringArray = profile.combo_recipe.primitive_sequence()
		var observed := _runtime_sequence(profile)
		var distinct := {}
		for family: String in observed: distinct[family] = true
		ok = ok and observed == expected and distinct.size() >= 2
	_check(ok, "08 existing controller locks and executes each recipe hit in order")


func _test_shotgun_rear_contact() -> void:
	var loaded: Dictionary = LOADER.new().load_motion_grammar_asset("shotgun_melee")
	var asset := loaded.get("asset") as WeaponVisualAsset
	var profile: Resource = _compiled("shotgun_melee") as Resource
	var hit_three: Variant = profile.combo_recipe.hit_3
	var ok: bool = hit_three.contact_anchor == "rear_contact"
	ok = ok and asset.muzzle.x > asset.grip_primary.x and asset.rear_contact.x < asset.grip_primary.x
	ok = ok and asset.rear_contact != asset.grip_primary
	_check(ok, "09 barrel and secondary stock axes make the third hit use normalized rear contact")


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


func _test_all_five_primitives_execute_across_real_recipes() -> void:
	var observed: Dictionary = {}
	var loaded: Dictionary = LOADER.new().load_motion_grammar_asset("frying_pan")
	var asset := loaded.get("asset") as WeaponVisualAsset
	for basis: Resource in _orthogonal_basis_profiles():
		var profile: Variant = COMPILER.new().compile(basis, asset.anchors_dict(), asset.opaque_bounds)
		if profile is Resource:
			for primitive: Resource in profile.combo_recipe.all_primitives():
				observed[primitive.motion_family] = true
	var ok: bool = observed.size() == 5
	for family: String in PRIMITIVE.MOTION_FAMILIES:
		ok = ok and observed.has(family)
	_check(ok, "13 an orthogonal synthetic basis makes all five generic primitives reachable without corpus tuning")


func _test_charge_and_dodge_execute_recipe_primitives() -> void:
	var profile: Resource = _compiled("shotgun_melee") as Resource
	var controller: Variant = CONTROLLER.new(); controller.configure(profile)
	controller.press_attack(); controller.tick(profile.charge_threshold_seconds + 0.01)
	var charge_ok: bool = controller.attack_kind == "charge" and is_same(controller.current_primitive, profile.combo_recipe.charge_attack)
	controller.reset(); controller.configure(profile); controller.press_dodge(); controller.press_attack()
	var dodge_ok: bool = controller.attack_kind == "dodge" and is_same(controller.current_primitive, profile.combo_recipe.dodge_attack)
	_check(charge_ok and dodge_ok, "14 Charge and Dodge execute their compiled Recipe primitives")


func _test_press_response_and_visible_articulated_poses() -> void:
	var profile: Resource = _compiled("old_mop") as Resource
	var controller: Variant = CONTROLLER.new(); controller.configure(profile)
	controller.press_attack()
	var immediate: bool = controller.phase == "startup" and controller.current_primitive != null
	var arena: Variant = SLICE.new()
	arena.motion_profile = profile
	arena.controller = controller
	arena.player_facing = 1.0
	var pose_signatures: Dictionary = {}
	var visible_amplitude := true
	for family: String in PRIMITIVE.MOTION_FAMILIES:
		var primitive: Variant = PRIMITIVE.new()
		primitive.motion_family = family
		controller.current_primitive = primitive
		controller.phase = "active"
		controller.phase_duration = 1.0
		controller.phase_elapsed = 0.55
		var pose: Dictionary = arena._character_pose()
		pose_signatures[JSON.stringify(pose)] = true
		match family:
			"sweep":
				visible_amplitude = visible_amplitude and absf(float(pose["torso_rotation"])) >= 0.35
				visible_amplitude = visible_amplitude and Vector2(pose["main_elbow_local"]).x >= 20.0
			"bash":
				visible_amplitude = visible_amplitude and Vector2(pose["body_offset"]).x >= 12.0
				visible_amplitude = visible_amplitude and Vector2(pose["hand_local"]).x >= 31.0
			"thrust":
				visible_amplitude = visible_amplitude and Vector2(pose["hand_local"]).x >= 38.0
				visible_amplitude = visible_amplitude and Vector2(pose["front_foot_local"]).x >= 20.0
			"spin":
				visible_amplitude = visible_amplitude and absf(float(pose["torso_rotation"])) >= 0.55
				visible_amplitude = visible_amplitude and float(pose["crouch"]) >= 8.0
	controller.current_primitive = PRIMITIVE.new()
	controller.current_primitive.motion_family = "slam"
	controller.phase = "startup"
	controller.phase_duration = 1.0
	controller.phase_elapsed = 0.70
	var slam_windup: Dictionary = arena._character_pose()
	controller.phase = "active"
	controller.phase_elapsed = 0.55
	var slam_contact: Dictionary = arena._character_pose()
	visible_amplitude = visible_amplitude and Vector2(slam_windup["hand_local"]).y <= -38.0
	visible_amplitude = visible_amplitude and Vector2(slam_contact["hand_local"]).y >= 4.0
	visible_amplitude = visible_amplitude and float(slam_contact["crouch"]) >= 10.0
	var slice_source := FileAccess.get_file_as_string(SLICE_PATH)
	var articulated_render := slice_source.contains("draw_line(main_shoulder, main_elbow")
	articulated_render = articulated_render and slice_source.contains("draw_line(main_elbow, weapon_origin")
	articulated_render = articulated_render and slice_source.contains("draw_line(support_shoulder, support_elbow")
	articulated_render = articulated_render and slice_source.contains("draw_line(support_elbow, second_hand")
	articulated_render = articulated_render and slice_source.contains("--pose-capture-dir=")
	articulated_render = articulated_render and slice_source.contains("func _capture_pose_visibility")
	arena.free()
	_check(immediate and pose_signatures.size() == 5 and visible_amplitude and articulated_render, "15 press responds immediately and five primitives drive visibly large torso stance and shoulder-elbow-hand poses")


func _test_blind_comparison_contract() -> void:
	var runner := FileAccess.get_file_as_string("res://scripts/run_motion_grammar_slice_1a.ps1")
	var slice_source := FileAccess.get_file_as_string(SLICE_PATH)
	var ok := runner.contains("[switch]$BlindComparison") and runner.contains("Get-Random")
	ok = ok and runner.contains("shortest_reach") and runner.contains("widest_range")
	ok = ok and runner.contains("heaviest_third_hit") and runner.contains("best_control") and runner.contains("most_forward_progress")
	ok = ok and runner.contains("blind_comparison_results.jsonl") and runner.contains("TECHNICAL PASS / FEEL NEEDS WORK")
	ok = ok and slice_source.contains("identity, Recipe and Affordance hidden") and slice_source.contains("--blind-result-path=")
	_check(ok, "16 BlindComparison randomizes A/B/C hides labels asks five questions and saves the human verdict")


func _test_failed_blind_dimensions_have_clear_margin() -> void:
	var pan: Resource = _compiled("frying_pan") as Resource
	var broom: Resource = _compiled("old_mop") as Resource
	var shotgun: Resource = _compiled("shotgun_melee") as Resource
	var pan_root := float(pan.combo_recipe.hit_1.root_motion_distance + pan.combo_recipe.hit_2.root_motion_distance + pan.combo_recipe.hit_3.root_motion_distance)
	var broom_root := float(broom.combo_recipe.hit_1.root_motion_distance + broom.combo_recipe.hit_2.root_motion_distance + broom.combo_recipe.hit_3.root_motion_distance)
	var shotgun_root := float(shotgun.combo_recipe.hit_1.root_motion_distance + shotgun.combo_recipe.hit_2.root_motion_distance + shotgun.combo_recipe.hit_3.root_motion_distance)
	var broom_width: float = broom.hitbox_thickness * maxf(
		broom.combo_recipe.hit_1.hitbox_width_multiplier,
		maxf(broom.combo_recipe.hit_2.hitbox_width_multiplier, broom.combo_recipe.hit_3.hitbox_width_multiplier)
	)
	var pan_width: float = pan.hitbox_thickness * maxf(
		pan.combo_recipe.hit_1.hitbox_width_multiplier,
		maxf(pan.combo_recipe.hit_2.hitbox_width_multiplier, pan.combo_recipe.hit_3.hitbox_width_multiplier)
	)
	var shotgun_width: float = shotgun.hitbox_thickness * maxf(
		shotgun.combo_recipe.hit_1.hitbox_width_multiplier,
		maxf(shotgun.combo_recipe.hit_2.hitbox_width_multiplier, shotgun.combo_recipe.hit_3.hitbox_width_multiplier)
	)
	var ok: bool = pan.reach_pixels < shotgun.reach_pixels and pan.reach_pixels < broom.reach_pixels
	ok = ok and broom_width > pan_width and broom_width > shotgun_width
	ok = ok and shotgun_root > pan_root and shotgun_root > broom_root
	_check(ok, "17 generic composition preserves only ordinal Pan-short Broom-wide Shotgun-forward properties")


func _test_rule_c_contact_reliability() -> void:
	var loaded: Dictionary = LOADER.new().load_motion_grammar_asset("shotgun_melee")
	var asset := loaded.get("asset") as WeaponVisualAsset
	var profile: Resource = _compiled("shotgun_melee") as Resource
	var first: Variant = profile.combo_recipe.hit_1
	var third: Variant = profile.combo_recipe.hit_3
	var arena: Variant = SLICE.new()
	arena.asset = asset
	arena.motion_profile = profile
	arena.controller = CONTROLLER.new()
	arena.controller.configure(profile)
	arena.player_position = Vector2(300.0, 400.0)
	arena.player_facing = 1.0
	arena.controller.attack_kind = "normal"
	arena.controller.combo_index = 1
	arena.controller.current_primitive = first
	arena.controller.phase = "active"
	arena.controller.phase_duration = 1.0
	arena.controller.phase_elapsed = 0.5
	var hand: Vector2 = arena._hand_world_position()
	var first_thickness: float = profile.hitbox_thickness * first.hitbox_multiplier * first.hitbox_width_multiplier
	var tolerance: float = arena._thrust_rear_tolerance(first, first_thickness)
	var near_after_lunge_hits: bool = arena._attack_contains(hand + Vector2(-minf(20.0, tolerance - 1.0), 0.0))
	var far_behind_misses: bool = not arena._attack_contains(hand + Vector2(-tolerance - 8.0, 0.0))
	arena.player_facing = -1.0
	hand = arena._hand_world_position()
	var mirrored_near_hits: bool = arena._attack_contains(hand + Vector2(minf(20.0, tolerance - 1.0), 0.0))
	var mirrored_far_misses: bool = not arena._attack_contains(hand + Vector2(tolerance + 8.0, 0.0))
	arena.player_facing = 1.0
	arena.controller.combo_index = 3
	arena.controller.current_primitive = third
	var third_thickness: float = profile.hitbox_thickness * third.hitbox_multiplier * third.hitbox_width_multiplier
	var contact: Vector2 = arena._primitive_contact_world(third, arena._hand_world_position())
	var third_radius: float = third_thickness * 0.58
	var stock_edge_hits: bool = arena._attack_contains(contact + Vector2(third_radius - 1.0, 0.0))
	var outside_stock_misses: bool = not arena._attack_contains(contact + Vector2(third_radius + 8.0, 0.0))
	var ok: bool = first.contact_anchor == "muzzle" and third.contact_anchor == "rear_contact"
	ok = ok and tolerance > 0.0 and third_radius > 0.0
	ok = ok and near_after_lunge_hits and far_behind_misses and mirrored_near_hits and mirrored_far_misses
	ok = ok and stock_edge_hits and outside_stock_misses
	arena.free()
	_check(ok, "18 point-front thrust tolerates close targets and secondary rear bash has bounded wider contact")


func _test_per_hit_attempt_stats_contract() -> void:
	var source := FileAccess.get_file_as_string(SLICE_PATH)
	var started := _function_source(source, "func _on_attack_started", "func _on_attack_phase_changed")
	var phases := _function_source(source, "func _on_attack_phase_changed", "func _resolve_melee_hits")
	var hits := _function_source(source, "func _resolve_melee_hits", "func _attack_contains")
	var collision := _function_source(source, "func _attack_contains", "func _current_damage")
	var debug_draw := _function_source(source, "func _draw_active_hitbox", "func _draw_real_weapon_comparison")
	var ok: bool = started.contains("normal_attack_attempts")
	ok = ok and phases.contains("normal_attack_whiffs") and hits.contains("normal_attack_hits")
	ok = ok and source.contains('"normal_attack_stats": _normal_attack_stats()')
	ok = ok and collision.contains("_thrust_hitbox_rect") and debug_draw.contains("_thrust_hitbox_rect")
	_check(ok, "19 per-hit attempts hits whiffs are recorded and thrust collision matches debug geometry")


func _test_handleless_affordance_loader_contract() -> void:
	var data := {
		"handle_length": "none", "body_length": "medium", "grip_topology": "body_grip",
		"rigidity": "rigid", "mass_distribution": "balanced", "contact_surface": "whole_body",
		"secondary_contact_surface": "none", "has_point": false, "has_edge": false,
		"has_broad_face": false, "has_barrel": false, "has_stock": false,
		"confidence": 0.80, "evidence_parts": ["seat body", "four legs"],
	}
	var loader: Variant = LOADER.new()
	var valid: Variant = loader._affordance_profile_from_dict(data)
	var invalid_data: Dictionary = data.duplicate(true)
	invalid_data["grip_topology"] = "one_hand_handle"
	var invalid: Variant = loader._affordance_profile_from_dict(invalid_data)
	var loaded: Dictionary = loader.load_motion_grammar_asset("frying_pan")
	var asset := loaded.get("asset") as WeaponVisualAsset
	var compiled: Variant = COMPILER.new().compile(valid, asset.anchors_dict(), asset.opaque_bounds)
	_check(valid is Resource and invalid == null and compiled is Resource, "20 handle_length none is accepted only with body or clamp grip across loader and compiler")


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
		"handle_length", "body_length", "grip_topology", "rigidity", "mass_distribution",
		"contact_surface", "secondary_contact_surface", "has_point", "has_edge",
		"has_broad_face", "has_barrel", "has_stock", "confidence", "evidence_parts",
	]:
		copied.set(property, source.get(property))
	return copied


func _orthogonal_basis_profiles() -> Array[Resource]:
	var values: Array[Resource] = []
	for data: Dictionary in [
		{"handle": "short", "body": "short", "grip": "one_hand_handle", "surface": "broad", "secondary": "none", "rigidity": "rigid", "mass": "front", "point": false, "edge": false, "broad": true, "barrel": false, "stock": false},
		{"handle": "long", "body": "long", "grip": "two_hand_handle", "surface": "edge", "secondary": "none", "rigidity": "semi_rigid", "mass": "balanced", "point": false, "edge": true, "broad": false, "barrel": false, "stock": false},
		{"handle": "long", "body": "long", "grip": "two_hand_handle", "surface": "point", "secondary": "broad", "rigidity": "rigid", "mass": "rear", "point": true, "edge": false, "broad": false, "barrel": true, "stock": true},
		{"handle": "none", "body": "medium", "grip": "body_grip", "surface": "whole_body", "secondary": "none", "rigidity": "flexible", "mass": "balanced", "point": false, "edge": false, "broad": false, "barrel": false, "stock": false},
	]:
		var profile: Variant = AFFORDANCE.new()
		profile.handle_length = data["handle"]
		profile.body_length = data["body"]
		profile.grip_topology = data["grip"]
		profile.contact_surface = data["surface"]
		profile.secondary_contact_surface = data["secondary"]
		profile.rigidity = data["rigidity"]
		profile.mass_distribution = data["mass"]
		profile.has_point = data["point"]
		profile.has_edge = data["edge"]
		profile.has_broad_face = data["broad"]
		profile.has_barrel = data["barrel"]
		profile.has_stock = data["stock"]
		profile.confidence = 1.0
		profile.evidence_parts = PackedStringArray(["orthogonal synthetic basis"])
		values.append(profile)
	return values


func _function_source(source: String, start_marker: String, end_marker: String) -> String:
	var start := source.find(start_marker)
	var finish := source.find(end_marker, start + start_marker.length())
	if start < 0 or finish <= start:
		return ""
	return source.substr(start, finish - start)


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		push_error("FAIL " + label)
