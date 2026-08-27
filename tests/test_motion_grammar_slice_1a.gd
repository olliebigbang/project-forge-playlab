extends SceneTree

const AFFORDANCE := preload("res://scripts/combat_feel/object_affordance_profile.gd")
const COMPILER := preload("res://scripts/combat_feel/melee_motion_compiler.gd")
const AXIS_RESOLVER := preload("res://scripts/combat_feel/mechanism_axis_resolver.gd")
const CONTROLLER := preload("res://scripts/combat_feel/melee_combat_controller.gd")
const FEEDBACK := preload("res://scripts/combat_feel/impact_feedback_profile.gd")
const LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")
const PRIMITIVE := preload("res://scripts/combat_feel/motion_primitive.gd")
const SLICE := preload("res://scripts/combat_feel/combat_feel_slice_0.gd")
const PIXEL_VISUAL_RIG := preload("res://scripts/data/pixel_weapon_visual_rig.gd")
const PIXEL_DEFORMER := preload("res://scripts/combat_feel/pixel_weapon_deformer.gd")
const ANCHOR_RESOLVER := preload("res://scripts/systems/anchor_resolver.gd")
const SLICE_PATH := "res://scripts/combat_feel/combat_feel_slice_0.gd"
const CHICKEN_SPRITE_PATH := "res://tools/comfyui/open_identity/output/spike2_case_04/seed_52002_policy1/processed_sprite.png"

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
	_test_anonymous_rear_mass_and_stock_runtime_axes()
	_test_anonymous_rigidity_axis_reaches_every_primitive()
	_test_secondary_contacts_have_distinct_runtime_channels()
	_test_real_silhouette_mechanics_use_stable_contact_projection()
	_test_mechanism_draft_measures_only_stable_visible_axes()
	_test_ai_mechanism_resolution_builds_a_valid_profile_automatically()
	_test_mechanism_draft_ignores_identity_and_does_not_guess_narrow_function()
	_test_generated_chicken_and_invalid_declarations_fail_safely()
	_test_generalization_silhouettes_keep_ambiguous_axes_unresolved()
	_test_ai_mechanism_missing_or_conflicting_evidence_fails_closed()
	_test_v2_handle_and_body_have_distinct_runtime_roles()
	_test_v2_grips_change_cancel_mobility_and_pose_rules()
	_test_v2_mass_owns_tempo_and_recovery_carry()
	_test_v2_contact_surfaces_change_shape_damage_and_reaction()
	_test_v2_secondary_contact_reserves_hit_three()
	_test_v2_redundant_capability_flags_are_covered_not_double_counted()
	_test_v2_rigidity_moves_the_real_contact_hitbox()
	_test_v3_soft_axes_are_conditionally_required_from_ai()
	_test_v3_flex_topologies_own_wave_and_live_contact_segment()
	_test_v3_terminal_load_owns_endpoint_impact()
	_test_v3_tether_mode_owns_hit_three_reaction()
	_test_v4_tether_topology_is_an_independent_soft_path()
	_test_v4_fishing_rod_asset_compiles_from_ai_axes_without_name_rules()
	_test_v7_tether_deployment_owns_endpoint_timeline()
	_test_v5_ai_visual_rig_binds_every_visible_source_pixel()
	_test_v5_original_pixels_follow_body_tether_and_terminal_paths()
	_test_v5_topology_axes_produce_distinct_pixel_geometry()
	_test_v5_render_and_collision_share_the_same_soft_paths()
	_test_v5_four_anonymous_visual_structures_validate_without_identity_rules()
	_test_v5_builtin_structure_samples_load_through_one_generic_pipeline()
	_test_v5_soft_body_starts_at_its_visual_connection_not_the_hand_pivot()
	_test_v6_missing_sidecar_autobuilds_anonymous_soft_structures()
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
		ok = ok and pan.compile_trace.get("composer") == "orthogonal_affordance_v4"
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
	unsupported.flex_topology = "flexible_line"
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
	ok = ok and broom_root > shotgun_root and shotgun_root > pan_root
	_check(ok, "17 generic composition preserves short broad and long front-versus-rear inertia ordering")


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
	var deadzone: float = first.inner_deadzone_pixels
	var inside_handle_misses: bool = not arena._attack_contains(hand + Vector2(maxf(0.0, deadzone - 1.0), 0.0))
	var point_lane_hits: bool = arena._attack_contains(hand + Vector2(deadzone + 2.0, 0.0))
	var beyond_reach_misses: bool = not arena._attack_contains(hand + Vector2(profile.reach_pixels * first.reach_multiplier * first.hitbox_length_multiplier + 8.0, 0.0))
	arena.player_facing = -1.0
	hand = arena._hand_world_position()
	var mirrored_inside_misses: bool = not arena._attack_contains(hand + Vector2(-maxf(0.0, deadzone - 1.0), 0.0))
	var mirrored_lane_hits: bool = arena._attack_contains(hand + Vector2(-deadzone - 2.0, 0.0))
	arena.player_facing = 1.0
	arena.controller.combo_index = 3
	arena.controller.current_primitive = third
	var third_thickness: float = profile.hitbox_thickness * third.hitbox_multiplier * third.hitbox_width_multiplier
	var contact: Vector2 = arena._primitive_contact_world(third, arena._hand_world_position())
	var third_radius: float = arena._contact_radius(third_thickness, third)
	var stock_edge_hits: bool = arena._attack_contains(contact + Vector2(third_radius - 1.0, 0.0))
	var outside_stock_misses: bool = not arena._attack_contains(contact + Vector2(third_radius + 8.0, 0.0))
	var ok: bool = first.contact_anchor == "muzzle" and first.contact_surface == "point" and third.contact_anchor == "rear_contact"
	ok = ok and deadzone > 0.0 and third_radius > 0.0
	ok = ok and inside_handle_misses and point_lane_hits and beyond_reach_misses and mirrored_inside_misses and mirrored_lane_hits
	ok = ok and stock_edge_hits and outside_stock_misses
	arena.free()
	_check(ok, "18 point thrust has a handle deadzone and bounded lane while the reserved rear broad hit uses its own contact radius")


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
	ok = ok and collision.contains("_point_lane_contains") and debug_draw.contains("_point_lane_polygon")
	ok = ok and collision.contains("_contact_band_contains") and debug_draw.contains("_draw_contact_band")
	_check(ok, "19 per-hit attempts hits whiffs are recorded and trajectory collision matches debug geometry")


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


func _test_anonymous_rear_mass_and_stock_runtime_axes() -> void:
	var baseline: Variant = AFFORDANCE.new()
	baseline.handle_length = "medium"
	baseline.body_length = "medium"
	baseline.grip_topology = "one_hand_handle"
	baseline.rigidity = "rigid"
	baseline.mass_distribution = "balanced"
	baseline.contact_surface = "broad"
	baseline.secondary_contact_surface = "none"
	baseline.confidence = 1.0
	baseline.evidence_parts = PackedStringArray(["anonymous structural probe"])
	var rear: Resource = _copy_affordance(baseline)
	rear.mass_distribution = "rear"
	var stock: Resource = _copy_affordance(baseline)
	stock.has_stock = true
	var anchors := {
		"GripPrimary": [24.0, 48.0], "GripSecondary": [38.0, 48.0],
		"StrikePoint": [78.0, 48.0], "Muzzle": [82.0, 48.0],
	}
	var bounds := Rect2i(8, 28, 80, 40)
	var baseline_profile: Resource = COMPILER.new().compile(baseline, anchors, bounds)
	var rear_profile: Resource = COMPILER.new().compile(rear, anchors, bounds)
	var stock_profile: Resource = COMPILER.new().compile(stock, anchors, bounds)
	var baseline_first: Resource = baseline_profile.combo_recipe.hit_1
	var rear_first: Resource = rear_profile.combo_recipe.hit_1
	var baseline_timing: Dictionary = baseline_profile.timing_for("normal", 1, baseline_first)
	var rear_timing: Dictionary = rear_profile.timing_for("normal", 1, rear_first)
	var baseline_feedback: Resource = FEEDBACK.for_attack(baseline_profile, "normal", 1, baseline_first)
	var rear_feedback: Resource = FEEDBACK.for_attack(rear_profile, "normal", 1, rear_first)
	var stock_third: Resource = stock_profile.combo_recipe.hit_3
	var neutral_asset := WeaponVisualAsset.new()
	neutral_asset.canvas_size = Vector2i(96, 96)
	neutral_asset.opaque_bounds = bounds
	neutral_asset.grip_primary = Vector2(24.0, 48.0)
	neutral_asset.grip_secondary = Vector2(38.0, 48.0)
	neutral_asset.tip = Vector2(78.0, 48.0)
	neutral_asset.muzzle = Vector2(82.0, 48.0)
	neutral_asset.rear_contact = neutral_asset.grip_primary
	var controller: Variant = CONTROLLER.new()
	controller.configure(stock_profile)
	controller.attack_kind = "normal"
	controller.combo_index = 3
	controller.current_primitive = stock_third
	controller.phase = "active"
	controller.phase_duration = 1.0
	controller.phase_elapsed = 0.5
	var arena: Variant = SLICE.new()
	arena.asset = neutral_asset
	arena.motion_profile = stock_profile
	arena.controller = controller
	arena.player_position = Vector2.ZERO
	arena.player_facing = 1.0
	var rear_contact: Vector2 = arena._resolved_rear_contact()
	var ok: bool = float(rear_timing["startup"]) < float(baseline_timing["startup"])
	ok = ok and rear_feedback.knockback_strength < baseline_feedback.knockback_strength
	ok = ok and stock_third.motion_family == "bash" and stock_third.contact_anchor == "rear_contact"
	ok = ok and rear_contact.x < neutral_asset.grip_primary.x
	arena.free()
	_check(ok, "21 anonymous rear mass and stock axes reach timing feedback and rear contact without identity input")


func _test_anonymous_rigidity_axis_reaches_every_primitive() -> void:
	var rigid: Variant = AFFORDANCE.new()
	rigid.handle_length = "short"
	rigid.body_length = "short"
	rigid.grip_topology = "one_hand_handle"
	rigid.rigidity = "rigid"
	rigid.mass_distribution = "front"
	rigid.contact_surface = "broad"
	rigid.secondary_contact_surface = "none"
	rigid.has_broad_face = true
	rigid.confidence = 1.0
	rigid.evidence_parts = PackedStringArray(["anonymous rigidity probe"])
	var semi_rigid: Resource = _copy_affordance(rigid)
	semi_rigid.rigidity = "semi_rigid"
	var flexible: Resource = _copy_affordance(rigid)
	flexible.rigidity = "flexible"
	flexible.flex_topology = "bending_shaft"
	var compiler: Variant = COMPILER.new()
	var anchors := {
		"GripPrimary": [24.0, 48.0], "StrikePoint": [78.0, 48.0],
	}
	var bounds := Rect2i(8, 28, 80, 40)
	var rigid_profile: Resource = compiler.compile(rigid, anchors, bounds)
	var semi_profile: Resource = compiler.compile(semi_rigid, anchors, bounds)
	var flexible_profile: Resource = compiler.compile(flexible, anchors, bounds)
	var ok: bool = rigid_profile.combo_recipe.signature() != semi_profile.combo_recipe.signature()
	ok = ok and semi_profile.combo_recipe.signature() != flexible_profile.combo_recipe.signature()
	ok = ok and rigid_profile.combo_recipe.signature() != flexible_profile.combo_recipe.signature()
	for family: String in PRIMITIVE.MOTION_FAMILIES:
		var rigid_primitive: Resource = compiler._synthesize_primitive(family, "hit_1", rigid, 1.0)
		var semi_primitive: Resource = compiler._synthesize_primitive(family, "hit_1", semi_rigid, 1.0)
		var flexible_primitive: Resource = compiler._synthesize_primitive(family, "hit_1", flexible, 1.0)
		ok = ok and rigid_primitive.active_multiplier < semi_primitive.active_multiplier
		ok = ok and semi_primitive.active_multiplier < flexible_primitive.active_multiplier
		ok = ok and rigid_primitive.recovery_multiplier < semi_primitive.recovery_multiplier
		ok = ok and semi_primitive.recovery_multiplier < flexible_primitive.recovery_multiplier
		ok = ok and rigid_primitive.hitstop_multiplier > semi_primitive.hitstop_multiplier
		ok = ok and semi_primitive.hitstop_multiplier > flexible_primitive.hitstop_multiplier
		ok = ok and rigid_primitive.camera_kick_multiplier > semi_primitive.camera_kick_multiplier
		ok = ok and semi_primitive.camera_kick_multiplier > flexible_primitive.camera_kick_multiplier
		ok = ok and rigid_primitive.root_motion_distance > semi_primitive.root_motion_distance
		ok = ok and semi_primitive.root_motion_distance > flexible_primitive.root_motion_distance
		ok = ok and rigid_primitive.movement_allowed_ratio < semi_primitive.movement_allowed_ratio
		ok = ok and semi_primitive.movement_allowed_ratio < flexible_primitive.movement_allowed_ratio
		if family == "thrust":
			ok = ok and rigid_primitive.extension_pixels > semi_primitive.extension_pixels
			ok = ok and semi_primitive.extension_pixels > flexible_primitive.extension_pixels
		else:
			var rigid_span := absf(rigid_primitive.end_angle - rigid_primitive.start_angle)
			var semi_span := absf(semi_primitive.end_angle - semi_primitive.start_angle)
			var flexible_span := absf(flexible_primitive.end_angle - flexible_primitive.start_angle)
			ok = ok and rigid_span < semi_span and semi_span < flexible_span
	_check(ok, "22 anonymous rigidity axis changes trajectory timing movement and impact for every primitive without identity input")


func _test_secondary_contacts_have_distinct_runtime_channels() -> void:
	var baseline: Variant = AFFORDANCE.new()
	baseline.handle_length = "medium"
	baseline.body_length = "medium"
	baseline.grip_topology = "one_hand_handle"
	baseline.rigidity = "rigid"
	baseline.mass_distribution = "balanced"
	baseline.contact_surface = "broad"
	baseline.secondary_contact_surface = "none"
	baseline.confidence = 1.0
	baseline.evidence_parts = PackedStringArray(["anonymous secondary-contact probe"])
	var anchors := {
		"GripPrimary": [24.0, 48.0], "GripSecondary": [38.0, 48.0],
		"StrikePoint": [78.0, 48.0],
	}
	var bounds := Rect2i(8, 8, 80, 80)
	var compiler: Variant = COMPILER.new()
	var neutral: Resource = compiler.compile(baseline, anchors, bounds)
	var profiles := {}
	for surface: String in ["point", "edge", "broad", "whole_body"]:
		var affordance: Resource = _copy_affordance(baseline)
		affordance.secondary_contact_surface = surface
		profiles[surface] = compiler.compile(affordance, anchors, bounds)
	var point: Resource = profiles["point"]
	var edge: Resource = profiles["edge"]
	var broad: Resource = profiles["broad"]
	var whole_body: Resource = profiles["whole_body"]
	var expected := {
		"point": ["thrust", "point", "rear_contact"],
		"edge": ["sweep", "edge", "rear_contact"],
		"broad": ["bash", "broad", "rear_contact"],
		"whole_body": ["spin", "whole_body", "whole_body"],
	}
	var signatures := {}
	var ok: bool = true
	for surface: String in profiles:
		var profile: Resource = profiles[surface]
		var third: Resource = profile.combo_recipe.hit_3
		var wanted: Array = expected[surface]
		ok = ok and third.motion_family == wanted[0]
		ok = ok and third.contact_surface == wanted[1]
		ok = ok and third.contact_anchor == wanted[2]
		ok = ok and third.uses_secondary_contact
		ok = ok and not profile.combo_recipe.hit_1.uses_secondary_contact
		ok = ok and not profile.combo_recipe.hit_2.uses_secondary_contact
		ok = ok and is_equal_approx(profile.reach_pixels, neutral.reach_pixels)
		ok = ok and is_equal_approx(profile.swing_arc_degrees, neutral.swing_arc_degrees)
		ok = ok and is_equal_approx(profile.hitbox_thickness, neutral.hitbox_thickness)
		signatures[JSON.stringify(third.to_dict())] = true
	ok = ok and signatures.size() == 4
	_check(ok, "23 every secondary surface becomes a distinct reserved hit-three contact without globally buffing the main contact")


func _test_real_silhouette_mechanics_use_stable_contact_projection() -> void:
	var loaded: Dictionary = LOADER.new().load_motion_grammar_asset("frying_pan")
	var pan := loaded.get("asset") as WeaponVisualAsset
	var chicken_image := Image.load_from_file(ProjectSettings.globalize_path(CHICKEN_SPRITE_PATH))
	var chicken_blueprint := WeaponBlueprint.new()
	chicken_blueprint.behavior_family = "heavy_melee"
	chicken_blueprint.grip_profile = "two_hand_rear"
	var chicken := ANCHOR_RESOLVER.resolve(chicken_image, chicken_blueprint)
	var assets: Array[WeaponVisualAsset] = []
	if pan != null:
		assets.append(pan)
	if chicken != null:
		assets.append(chicken)
	var ok := assets.size() == 2
	for asset: WeaponVisualAsset in assets:
		var metrics: Dictionary = asset.silhouette_mechanics()
		var stability: Dictionary = asset.silhouette_mechanics_stability(2.0)
		var contact_data: Array = metrics.get("contact_point", [])
		var direction := (asset.tip - asset.grip_primary).normalized()
		var contact := Vector2(float(contact_data[0]), float(contact_data[1])) if contact_data.size() >= 2 else Vector2.ZERO
		var metric_stability: Dictionary = stability.get("metrics", {})
		var curvature_stability: Dictionary = metric_stability.get("normalized_local_curvature", {})
		var span_stability: Dictionary = metric_stability.get("contact_span_ratio", {})
		var mass_stability: Dictionary = metric_stability.get("mass_projection_ratio", {})
		ok = ok and not metrics.is_empty() and int(stability.get("sample_count", 0)) == 243
		ok = ok and float(metrics.get("feret_diameter_pixels", 0.0)) > 0.0
		ok = ok and float(metrics.get("normalized_silhouette_inertia", 0.0)) > 0.0
		ok = ok and float(metrics.get("grip_to_strike_ratio", 0.0)) > 0.0
		ok = ok and bool(metrics.get("mass_projection_ratio_valid", false))
		ok = ok and is_finite(float(metrics.get("mass_projection_ratio", NAN)))
		ok = ok and float(metrics.get("contact_span_ratio", 0.0)) > 0.0
		ok = ok and float(metrics.get("normalized_local_curvature", 0.0)) > 0.0
		ok = ok and (contact - asset.grip_primary).dot(direction) >= (asset.tip - asset.grip_primary).dot(direction) - 0.5
		ok = ok and float(curvature_stability.get("max_relative_deviation", INF)) < 0.35
		ok = ok and float(span_stability.get("max_relative_deviation", INF)) < 0.25
		ok = ok and int(mass_stability.get("invalid_sample_count", -1)) == 0
	_check(ok, "24 pan and chicken real alpha metrics remain bounded under anchor and mask perturbation")


func _test_mechanism_draft_measures_only_stable_visible_axes() -> void:
	var loaded: Dictionary = LOADER.new().load_motion_grammar_asset("frying_pan")
	var draft: Dictionary = AXIS_RESOLVER.draft(loaded.get("asset") as WeaponVisualAsset)
	var axes: Dictionary = draft.get("axes", {})
	var pending := Array(draft.get("needs_ai_axes", PackedStringArray()))
	var mass: Dictionary = axes.get("mass_distribution", {})
	var contact: Dictionary = axes.get("contact_surface", {})
	var ok: bool = bool(draft.get("ok", false)) and not bool(draft.get("complete", true))
	ok = ok and not bool(draft.get("identity_inputs_used", true))
	ok = ok and str(mass.get("value", "")) == "front" and str(mass.get("status", "")) == "measured"
	ok = ok and str(contact.get("value", "")) == "broad" and str(contact.get("status", "")) == "measured"
	ok = ok and pending == ["handle_length", "body_length", "grip_topology", "rigidity", "secondary_contact_surface", "flex_topology", "tether_topology", "terminal_load", "tether_mode", "tether_deployment"]
	ok = ok and not draft.has("questions") and not bool(draft.get("player_confirmation_required", true))
	ok = ok and not bool(draft.get("player_mechanism_input_used", true))
	_check(ok, "25 stable pan alpha fills visible axes; invisible facts are sent to AI without player questions")


func _test_ai_mechanism_resolution_builds_a_valid_profile_automatically() -> void:
	var loaded: Dictionary = LOADER.new().load_motion_grammar_asset("frying_pan")
	var asset := loaded.get("asset") as WeaponVisualAsset
	var frozen_profile := loaded.get("affordance_profile") as Resource
	var resolved: Dictionary = AXIS_RESOLVER.resolve_ai(asset, frozen_profile.to_dict(), "ai_semantic_v1_2")
	var profile: Resource = resolved.get("profile") as Resource
	var compiled: Variant = COMPILER.new().compile(profile, asset.anchors_dict(), asset.opaque_bounds) if profile != null else null
	var ok: bool = bool(resolved.get("ok", false)) and bool(resolved.get("complete", false)) and profile != null
	ok = ok and bool(resolved.get("automatic", false)) and not bool(resolved.get("player_mechanism_input_used", true))
	ok = ok and not bool(resolved.get("player_confirmation_required", true)) and not resolved.has("questions")
	if profile != null:
		ok = ok and profile.validation_errors().is_empty()
		ok = ok and profile.handle_length == "short" and profile.body_length == "short"
		ok = ok and profile.grip_topology == "one_hand_handle" and profile.rigidity == "rigid"
		ok = ok and profile.mass_distribution == "front" and profile.contact_surface == "broad"
		ok = ok and profile.secondary_contact_surface == "none" and profile.has_broad_face
	for axis: String in AXIS_RESOLVER.REQUIRED_AXES:
		var axis_result: Dictionary = (resolved.get("axes", {}) as Dictionary).get(axis, {})
		ok = ok and str(axis_result.get("status", "")) == "ai_declared"
		ok = ok and str(axis_result.get("source", "")) == "ai_semantic_affordance"
	ok = ok and compiled is Resource
	_check(ok, "26 complete AI affordance plus geometry validation builds a compiler-ready profile automatically")


func _test_mechanism_draft_ignores_identity_and_does_not_guess_narrow_function() -> void:
	var loader: Variant = LOADER.new()
	var pan := loader.load_motion_grammar_asset("frying_pan").get("asset") as WeaponVisualAsset
	var declarations := {
		"handle_length": "short",
		"body_length": "short",
		"grip_topology": "one_hand_handle",
		"rigidity": "rigid",
		"secondary_contact_surface": "none",
	}
	var first_declarations: Dictionary = declarations.duplicate(true)
	first_declarations["identity"] = "平底锅"
	var second_declarations: Dictionary = declarations.duplicate(true)
	second_declarations["identity"] = "木椅"
	var first: Dictionary = AXIS_RESOLVER.draft(pan, first_declarations)
	var second: Dictionary = AXIS_RESOLVER.draft(pan, second_declarations)
	var first_profile: Resource = first.get("profile") as Resource
	var second_profile: Resource = second.get("profile") as Resource
	var shotgun := loader.load_motion_grammar_asset("shotgun_melee").get("asset") as WeaponVisualAsset
	var narrow: Dictionary = AXIS_RESOLVER.draft(shotgun)
	var contact: Dictionary = (narrow.get("axes", {}) as Dictionary).get("contact_surface", {})
	var ok: bool = first_profile != null and second_profile != null
	if ok:
		ok = first_profile.to_dict() == second_profile.to_dict()
	ok = ok and not bool(first.get("identity_inputs_used", true)) and not bool(second.get("identity_inputs_used", true))
	ok = ok and str(contact.get("value", "")) == "" and str(contact.get("status", "")) == "needs_ai"
	ok = ok and str(contact.get("suggestion", "")) != "point"
	_check(ok, "27 names cannot change axes and a narrow silhouette is not guessed as point versus edge versus whole-body")


func _test_generated_chicken_and_invalid_declarations_fail_safely() -> void:
	var chicken_image := Image.load_from_file(ProjectSettings.globalize_path(CHICKEN_SPRITE_PATH))
	var chicken_blueprint := WeaponBlueprint.new()
	chicken_blueprint.behavior_family = "heavy_melee"
	chicken_blueprint.grip_profile = "two_hand_rear"
	var chicken := ANCHOR_RESOLVER.resolve(chicken_image, chicken_blueprint)
	var chicken_draft: Dictionary = AXIS_RESOLVER.draft(chicken)
	var chicken_contact: Dictionary = (chicken_draft.get("axes", {}) as Dictionary).get("contact_surface", {})
	var invalid: Dictionary = AXIS_RESOLVER.draft(chicken, {"rigidity": "probably_rigid"})
	var ok: bool = str(chicken_contact.get("value", "")) == "broad"
	ok = ok and str(chicken_contact.get("status", "")) == "measured"
	ok = ok and not bool(invalid.get("ok", true)) and str(invalid.get("error", "")) == "INVALID_DECLARATION:rigidity"
	_check(ok, "28 generated chicken broad contact is stable while invalid semantic declarations fail closed")


func _test_generalization_silhouettes_keep_ambiguous_axes_unresolved() -> void:
	var loader: Variant = LOADER.new()
	var mop := loader.load_motion_grammar_asset("old_mop").get("asset") as WeaponVisualAsset
	var mop_axes: Dictionary = AXIS_RESOLVER.draft(mop).get("axes", {})
	var mop_mass: Dictionary = mop_axes.get("mass_distribution", {})
	var mop_contact: Dictionary = mop_axes.get("contact_surface", {})
	var drafts := {}
	var index: Dictionary = loader._read_json(loader.GENERALIZATION_INDEX_PATH)
	for value: Variant in index.get("assets", []):
		var entry: Dictionary = value
		var loaded: Dictionary = loader.load_live(str(entry["sprite"]), str(entry["blueprint"]), str(entry["anchors"]))
		drafts[str(entry["id"])] = AXIS_RESOLVER.draft(loaded.get("asset") as WeaponVisualAsset)
	var sword_axes: Dictionary = (drafts["longsword_generalization"].get("axes", {}) as Dictionary)
	var spear_axes: Dictionary = (drafts["spear_generalization"].get("axes", {}) as Dictionary)
	var chair_axes: Dictionary = (drafts["wooden_chair_generalization"].get("axes", {}) as Dictionary)
	var sword_mass: Dictionary = sword_axes.get("mass_distribution", {})
	var sword_contact: Dictionary = sword_axes.get("contact_surface", {})
	var spear_mass: Dictionary = spear_axes.get("mass_distribution", {})
	var spear_contact: Dictionary = spear_axes.get("contact_surface", {})
	var chair_mass: Dictionary = chair_axes.get("mass_distribution", {})
	var chair_contact: Dictionary = chair_axes.get("contact_surface", {})
	var ok: bool = str(mop_mass.get("value", "")) == "front" and str(mop_mass.get("status", "")) == "measured"
	ok = ok and str(mop_contact.get("value", "")) == "" and str(mop_contact.get("morphology", "")) == "broad_contact"
	ok = ok and str(sword_mass.get("value", "")) == "balanced" and str(sword_mass.get("status", "")) == "measured"
	ok = ok and str(sword_contact.get("value", "")) == "" and str(sword_contact.get("morphology", "")) == "narrow_contact"
	ok = ok and str(spear_mass.get("value", "")) == "" and str(spear_contact.get("value", "")) == ""
	ok = ok and str(chair_mass.get("value", "")) == "" and str(chair_contact.get("value", "")) == ""
	_check(ok, "29 mop sword spear and chair calibration accepts stable geometry but leaves functional ambiguity for AI semantics")


func _test_ai_mechanism_missing_or_conflicting_evidence_fails_closed() -> void:
	var loaded: Dictionary = LOADER.new().load_motion_grammar_asset("frying_pan")
	var asset := loaded.get("asset") as WeaponVisualAsset
	var frozen_profile := loaded.get("affordance_profile") as Resource
	var ai_data: Dictionary = frozen_profile.to_dict()
	var missing_source: Dictionary = AXIS_RESOLVER.resolve_ai(asset, ai_data, "")
	var untrusted_source: Dictionary = AXIS_RESOLVER.resolve_ai(asset, ai_data, "player_form")
	var anthropic_contract: Dictionary = AXIS_RESOLVER.validate_ai_declaration(ai_data, "anthropic:claude-sonnet-5")
	var incomplete: Dictionary = AXIS_RESOLVER.resolve_ai(asset, {"rigidity": "rigid"}, "ai_semantic_v1_2")
	var conflicting_data := ai_data.duplicate(true)
	conflicting_data["mass_distribution"] = "rear"
	conflicting_data["contact_surface"] = "edge"
	var conflict: Dictionary = AXIS_RESOLVER.resolve_ai(asset, conflicting_data, "ai_semantic_v1_2")
	var conflicts: Array = conflict.get("conflicts", [])
	var conflict_axes := PackedStringArray()
	for raw_conflict: Variant in conflicts:
		conflict_axes.append(str((raw_conflict as Dictionary).get("axis", "")))
	var ok := not bool(missing_source.get("ok", true))
	ok = ok and str(missing_source.get("error", "")) == "AI_AFFORDANCE_SOURCE_MISSING"
	ok = ok and not bool(untrusted_source.get("ok", true)) and str(untrusted_source.get("error", "")) == "UNTRUSTED_AI_AFFORDANCE_SOURCE"
	ok = ok and bool(anthropic_contract.get("ok", false)) and bool(anthropic_contract.get("geometry_validation_pending", false))
	ok = ok and not bool(incomplete.get("ok", true)) and str(incomplete.get("error", "")).begins_with("AI_AFFORDANCE_MISSING_")
	ok = ok and not bool(conflict.get("ok", true)) and str(conflict.get("error", "")) == "AI_GEOMETRY_CONFLICT"
	ok = ok and conflict_axes.has("mass_distribution") and conflict_axes.has("contact_surface")
	ok = ok and bool(conflict.get("retry_required", false)) and not bool(conflict.get("player_confirmation_required", true))
	ok = ok and not conflict.has("questions")
	_check(ok, "30 missing AI evidence and stable geometry conflicts fail closed without asking the player")


func _test_v2_handle_and_body_have_distinct_runtime_roles() -> void:
	var baseline := _anonymous_profile()
	var long_handle := _copy_affordance(baseline)
	long_handle.handle_length = "long"
	var long_body := _copy_affordance(baseline)
	long_body.body_length = "long"
	var base_profile := _compile_anonymous(baseline)
	var handle_profile := _compile_anonymous(long_handle)
	var body_profile := _compile_anonymous(long_body)
	var base_first: Resource = base_profile.combo_recipe.hit_1
	var handle_first: Resource = handle_profile.combo_recipe.hit_1
	var body_first: Resource = body_profile.combo_recipe.hit_1
	var ok: bool = handle_profile.handle_leverage_ratio > base_profile.handle_leverage_ratio
	ok = ok and handle_profile.close_range_deadzone_pixels > base_profile.close_range_deadzone_pixels
	ok = ok and is_equal_approx(handle_profile.body_coverage_ratio, base_profile.body_coverage_ratio)
	ok = ok and body_profile.body_coverage_ratio > base_profile.body_coverage_ratio
	ok = ok and is_equal_approx(body_profile.close_range_deadzone_pixels, base_profile.close_range_deadzone_pixels)
	ok = ok and is_equal_approx(body_profile.handle_leverage_ratio, base_profile.handle_leverage_ratio)
	ok = ok and body_first.hitbox_length_multiplier - base_first.hitbox_length_multiplier \
		> handle_first.hitbox_length_multiplier - base_first.hitbox_length_multiplier
	ok = ok and handle_profile.reach_pixels > base_profile.reach_pixels and body_profile.reach_pixels > base_profile.reach_pixels
	_check(ok, "31 handle length owns leverage and inner deadzone while body length owns physical coverage")


func _test_v2_grips_change_cancel_mobility_and_pose_rules() -> void:
	var one := _anonymous_profile()
	var two := _copy_affordance(one)
	two.grip_topology = "two_hand_handle"
	var clamp := _copy_affordance(one)
	clamp.grip_topology = "clamp_grip"
	var one_profile := _compile_anonymous(one)
	var two_profile := _compile_anonymous(two)
	var clamp_profile := _compile_anonymous(clamp)
	var one_first: Resource = one_profile.combo_recipe.hit_1
	var two_first: Resource = two_profile.combo_recipe.hit_1
	var clamp_first: Resource = clamp_profile.combo_recipe.hit_1
	var poses := {}
	for profile: Resource in [one_profile, two_profile, clamp_profile]:
		var controller: Variant = CONTROLLER.new()
		controller.configure(profile)
		controller.current_primitive = profile.combo_recipe.hit_1
		controller.phase = "active"
		controller.phase_duration = 1.0
		controller.phase_elapsed = 0.55
		var arena: Variant = SLICE.new()
		arena.motion_profile = profile
		arena.controller = controller
		arena.player_facing = 1.0
		poses[JSON.stringify(arena._character_pose())] = true
		arena.free()
	var ok: bool = one_profile.early_startup_cancel_ratio > two_profile.early_startup_cancel_ratio
	ok = ok and one_profile.late_recovery_cancel_ratio < two_profile.late_recovery_cancel_ratio
	ok = ok and one_profile.dodge_attack_window_seconds > two_profile.dodge_attack_window_seconds
	ok = ok and one_first.movement_allowed_ratio > two_first.movement_allowed_ratio
	ok = ok and clamp_first.movement_allowed_ratio < two_first.movement_allowed_ratio
	ok = ok and clamp_first.contact_arc_degrees < two_first.contact_arc_degrees
	ok = ok and one_profile.grip_mode == "one_hand" and two_profile.grip_mode == "two_hand"
	ok = ok and poses.size() == 3
	_check(ok, "32 grip topology changes cancel windows attack mobility arc and articulated stance")


func _test_v2_mass_owns_tempo_and_recovery_carry() -> void:
	var rear := _anonymous_profile()
	rear.mass_distribution = "rear"
	var balanced := _copy_affordance(rear)
	balanced.mass_distribution = "balanced"
	var front := _copy_affordance(rear)
	front.mass_distribution = "front"
	var rear_profile := _compile_anonymous(rear)
	var balanced_profile := _compile_anonymous(balanced)
	var front_profile := _compile_anonymous(front)
	var rear_first: Resource = rear_profile.combo_recipe.hit_1
	var balanced_first: Resource = balanced_profile.combo_recipe.hit_1
	var front_first: Resource = front_profile.combo_recipe.hit_1
	var arena: Variant = SLICE.new()
	var rear_carry: float = 1.0 - float(arena._root_motion_progress("active", 1.0, rear_first.inertia_ratio))
	var balanced_carry: float = 1.0 - float(arena._root_motion_progress("active", 1.0, balanced_first.inertia_ratio))
	var front_carry: float = 1.0 - float(arena._root_motion_progress("active", 1.0, front_first.inertia_ratio))
	arena.free()
	var ok: bool = rear_profile.tempo == "rapid" and balanced_profile.tempo == "balanced" and front_profile.tempo == "committed"
	ok = ok and rear_first.inertia_ratio < balanced_first.inertia_ratio and balanced_first.inertia_ratio < front_first.inertia_ratio
	ok = ok and rear_carry < balanced_carry and balanced_carry < front_carry
	ok = ok and rear_first.root_motion_distance < balanced_first.root_motion_distance
	ok = ok and balanced_first.root_motion_distance < front_first.root_motion_distance
	_check(ok, "33 mass distribution owns rapid-balanced-committed tempo and progressive recovery carry")


func _test_v2_contact_surfaces_change_shape_damage_and_reaction() -> void:
	var signatures := {}
	var profiles := {}
	for surface: String in ["point", "edge", "broad", "whole_body"]:
		var affordance := _anonymous_profile()
		affordance.contact_surface = surface
		profiles[surface] = _compile_anonymous(affordance)
		var profile: Resource = profiles[surface]
		var first: Resource = profile.combo_recipe.hit_1
		var feedback: Resource = FEEDBACK.for_attack(profile, "normal", 1, first)
		signatures[JSON.stringify([
			first.motion_family, first.contact_surface, first.contact_arc_degrees,
			first.damage_multiplier, feedback.knockback_strength, feedback.stagger_strength,
		])] = true
	var point_first: Resource = (profiles["point"] as Resource).combo_recipe.hit_1
	var edge_first: Resource = (profiles["edge"] as Resource).combo_recipe.hit_1
	var broad_first: Resource = (profiles["broad"] as Resource).combo_recipe.hit_1
	var whole_first: Resource = (profiles["whole_body"] as Resource).combo_recipe.hit_1
	var point_feedback: Resource = FEEDBACK.for_attack(profiles["point"], "normal", 1, point_first)
	var broad_feedback: Resource = FEEDBACK.for_attack(profiles["broad"], "normal", 1, broad_first)
	var ok: bool = signatures.size() == 4
	ok = ok and point_first.motion_family == "thrust" and edge_first.motion_family == "sweep"
	ok = ok and broad_first.motion_family == "bash" and whole_first.motion_family == "sweep"
	ok = ok and point_first.damage_multiplier > edge_first.damage_multiplier
	ok = ok and edge_first.damage_multiplier > whole_first.damage_multiplier
	ok = ok and broad_feedback.knockback_strength > point_feedback.knockback_strength
	_check(ok, "34 primary contact selects a distinct hit shape damage tradeoff and enemy reaction")


func _test_v2_secondary_contact_reserves_hit_three() -> void:
	var baseline := _anonymous_profile()
	var secondary := _copy_affordance(baseline)
	secondary.secondary_contact_surface = "point"
	var base_profile := _compile_anonymous(baseline)
	var secondary_profile := _compile_anonymous(secondary)
	var third: Resource = secondary_profile.combo_recipe.hit_3
	var ok: bool = base_profile.combo_recipe.hit_1.to_dict() == secondary_profile.combo_recipe.hit_1.to_dict()
	ok = ok and base_profile.combo_recipe.hit_2.to_dict() == secondary_profile.combo_recipe.hit_2.to_dict()
	ok = ok and base_profile.combo_recipe.hit_3.to_dict() != third.to_dict()
	ok = ok and third.uses_secondary_contact and third.contact_surface == "point"
	ok = ok and third.motion_family == "thrust" and third.contact_anchor == "rear_contact"
	ok = ok and secondary_profile.secondary_contact_stage == "hit_3"
	_check(ok, "35 a secondary surface changes one reserved move instead of weakly buffing every move")


func _test_v2_redundant_capability_flags_are_covered_not_double_counted() -> void:
	var broad := _anonymous_profile()
	broad.contact_surface = "broad"
	var redundant := _copy_affordance(broad)
	redundant.has_broad_face = true
	var alternate := _copy_affordance(broad)
	alternate.has_point = true
	var broad_profile := _compile_anonymous(broad)
	var redundant_profile := _compile_anonymous(redundant)
	var alternate_profile := _compile_anonymous(alternate)
	var ok: bool = broad_profile.combo_recipe.signature() == redundant_profile.combo_recipe.signature()
	ok = ok and is_equal_approx(broad_profile.hitbox_thickness, redundant_profile.hitbox_thickness)
	ok = ok and redundant_profile.secondary_contact_surface == "none"
	ok = ok and alternate_profile.secondary_contact_surface == "point"
	ok = ok and alternate_profile.combo_recipe.hit_3.uses_secondary_contact
	ok = ok and alternate_profile.combo_recipe.signature() != broad_profile.combo_recipe.signature()
	_check(ok, "36 a capability matching the primary surface is covered once while a genuinely different capability becomes a secondary move")


func _test_v2_rigidity_moves_the_real_contact_hitbox() -> void:
	var loaded: Dictionary = LOADER.new().load_motion_grammar_asset("frying_pan")
	var asset := loaded.get("asset") as WeaponVisualAsset
	var rigid_affordance: Resource = _copy_affordance(loaded.get("affordance_profile") as Resource)
	var flexible_affordance: Resource = _copy_affordance(rigid_affordance)
	rigid_affordance.rigidity = "rigid"
	flexible_affordance.rigidity = "flexible"
	flexible_affordance.flex_topology = "bending_shaft"
	var compiler: Variant = COMPILER.new()
	var rigid_profile: Resource = compiler.compile(rigid_affordance, asset.anchors_dict(), asset.opaque_bounds) as Resource
	var flexible_profile: Resource = compiler.compile(flexible_affordance, asset.anchors_dict(), asset.opaque_bounds) as Resource
	var arenas: Array = []
	for profile: Resource in [rigid_profile, flexible_profile]:
		var arena: Variant = SLICE.new()
		arena.asset = asset
		arena.motion_profile = profile
		arena.controller = CONTROLLER.new()
		arena.controller.configure(profile)
		arena.controller.attack_kind = "normal"
		arena.controller.combo_index = 1
		arena.controller.current_primitive = profile.combo_recipe.hit_1
		arena.controller.phase = "active"
		arena.controller.phase_duration = 1.0
		arena.controller.phase_elapsed = 0.02
		arena.player_position = Vector2(300.0, 400.0)
		arena.player_facing = 1.0
		arenas.append(arena)
	var rigid_arena: Variant = arenas[0]
	var flexible_arena: Variant = arenas[1]
	var rigid_hand: Vector2 = rigid_arena._hand_world_position()
	var flexible_hand: Vector2 = flexible_arena._hand_world_position()
	var rigid_contact: Vector2 = rigid_arena._primitive_contact_world(rigid_arena.controller.current_primitive, rigid_hand)
	var flexible_contact: Vector2 = flexible_arena._primitive_contact_world(flexible_arena.controller.current_primitive, flexible_hand)
	var rigid_primitive: Resource = rigid_arena.controller.current_primitive
	var rigid_thickness: float = rigid_profile.hitbox_thickness * rigid_primitive.hitbox_multiplier * rigid_primitive.hitbox_width_multiplier
	var rigid_radius: float = rigid_arena._contact_radius(rigid_thickness, rigid_primitive)
	var separation: Vector2 = rigid_contact - flexible_contact
	var rigid_only_target := rigid_contact + separation.normalized() * maxf(0.0, rigid_radius - 1.0)
	var ok: bool = rigid_primitive.trajectory_lag_ratio < flexible_arena.controller.current_primitive.trajectory_lag_ratio
	ok = ok and separation.length() > 1.0
	ok = ok and rigid_arena._attack_contains(rigid_only_target)
	ok = ok and not flexible_arena._attack_contains(rigid_only_target)
	for arena: Variant in arenas:
		arena.free()
	_check(ok, "37 rigidity lag moves the visible contact and the real hitbox together at the same attack time")


func _test_v3_soft_axes_are_conditionally_required_from_ai() -> void:
	var loaded: Dictionary = LOADER.new().load_motion_grammar_asset("frying_pan")
	var asset := loaded.get("asset") as WeaponVisualAsset
	var rigid_legacy: Dictionary = (loaded.get("affordance_profile") as Resource).to_dict()
	for axis: String in ["flex_topology", "tether_topology", "terminal_load", "tether_mode", "tether_deployment"]:
		rigid_legacy.erase(axis)
	var rigid_contract: Dictionary = AXIS_RESOLVER.validate_ai_declaration(rigid_legacy, "ai_semantic_v1_3")
	var flexible_missing: Dictionary = rigid_legacy.duplicate(true)
	flexible_missing["rigidity"] = "flexible"
	var missing_contract: Dictionary = AXIS_RESOLVER.validate_ai_declaration(flexible_missing, "ai_semantic_v1_3")
	var complete_soft: Dictionary = rigid_legacy.duplicate(true)
	complete_soft["rigidity"] = "flexible"
	complete_soft["flex_topology"] = "flexible_line"
	complete_soft["tether_topology"] = "none"
	complete_soft["terminal_load"] = "light"
	complete_soft["tether_mode"] = "wrap"
	complete_soft["tether_deployment"] = "none"
	var resolved: Dictionary = AXIS_RESOLVER.resolve_ai(asset, complete_soft, "ai_semantic_v1_3")
	var profile := resolved.get("profile") as Resource
	var ok: bool = bool(rigid_contract.get("ok", false))
	ok = ok and not bool(missing_contract.get("ok", true))
	ok = ok and str(missing_contract.get("error", "")) == "AI_AFFORDANCE_MISSING_AXIS:flex_topology"
	ok = ok and bool(resolved.get("ok", false)) and bool(resolved.get("automatic", false))
	ok = ok and not bool(resolved.get("player_confirmation_required", true)) and not resolved.has("questions")
	ok = ok and profile != null and profile.flex_topology == "flexible_line" and profile.terminal_load == "light" and profile.tether_mode == "wrap"
	_check(ok, "38 rigid AI declarations default soft axes to none while flexible declarations must provide all soft factors without asking the player")


func _test_v3_flex_topologies_own_wave_and_live_contact_segment() -> void:
	var signatures := {}
	var profiles := {}
	for topology: String in ["bending_shaft", "flexible_line", "linked_segments"]:
		var affordance := _soft_affordance()
		affordance.flex_topology = topology
		var profile := _compile_anonymous(affordance)
		profiles[topology] = profile
		signatures[profile.combo_recipe.signature()] = true
	var bend_first: Resource = (profiles["bending_shaft"] as Resource).combo_recipe.hit_1
	var line_first: Resource = (profiles["flexible_line"] as Resource).combo_recipe.hit_1
	var linked_first: Resource = (profiles["linked_segments"] as Resource).combo_recipe.hit_1
	var arena: Variant = SLICE.new()
	var bend_deadzone: float = arena._soft_contact_deadzone(bend_first, Vector2(100.0, 0.0), 100.0, 0.0)
	var line_deadzone: float = arena._soft_contact_deadzone(line_first, Vector2(100.0, 0.0), 100.0, 0.0)
	var linked_deadzone: float = arena._soft_contact_deadzone(linked_first, Vector2(100.0, 0.0), 100.0, 0.0)
	var bend_motion: float = arena._trajectory_motion_ratio(bend_first, 0.55)
	var line_motion: float = arena._trajectory_motion_ratio(line_first, 0.55)
	arena.free()
	var ok: bool = signatures.size() == 3
	ok = ok and bend_first.soft_contact_start_ratio < line_first.soft_contact_start_ratio
	ok = ok and line_first.soft_contact_start_ratio < linked_first.soft_contact_start_ratio
	ok = ok and bend_deadzone < line_deadzone and line_deadzone < linked_deadzone
	ok = ok and line_first.active_multiplier > bend_first.active_multiplier
	ok = ok and linked_first.follow_through_radians > bend_first.follow_through_radians
	ok = ok and line_motion < bend_motion
	_check(ok, "39 bending shafts flexible lines and linked segments have different propagation curves and live contact portions")


func _test_v3_terminal_load_owns_endpoint_impact() -> void:
	var profiles := {}
	for load_value: String in ["none", "light", "heavy"]:
		var affordance := _soft_affordance()
		affordance.terminal_load = load_value
		profiles[load_value] = _compile_anonymous(affordance)
	var none_first: Resource = (profiles["none"] as Resource).combo_recipe.hit_1
	var light_first: Resource = (profiles["light"] as Resource).combo_recipe.hit_1
	var heavy_first: Resource = (profiles["heavy"] as Resource).combo_recipe.hit_1
	var arena: Variant = SLICE.new()
	var none_radius: float = arena._contact_radius(40.0, none_first)
	var light_radius: float = arena._contact_radius(40.0, light_first)
	var heavy_radius: float = arena._contact_radius(40.0, heavy_first)
	arena.free()
	var ok: bool = (profiles["none"] as Resource).combo_recipe.primitive_sequence() == (profiles["light"] as Resource).combo_recipe.primitive_sequence()
	ok = ok and (profiles["light"] as Resource).combo_recipe.primitive_sequence() == (profiles["heavy"] as Resource).combo_recipe.primitive_sequence()
	ok = ok and none_first.terminal_load_ratio < light_first.terminal_load_ratio and light_first.terminal_load_ratio < heavy_first.terminal_load_ratio
	ok = ok and none_first.damage_multiplier < light_first.damage_multiplier and light_first.damage_multiplier < heavy_first.damage_multiplier
	ok = ok and none_first.follow_through_radians < light_first.follow_through_radians and light_first.follow_through_radians < heavy_first.follow_through_radians
	ok = ok and none_first.recovery_multiplier < light_first.recovery_multiplier and light_first.recovery_multiplier < heavy_first.recovery_multiplier
	ok = ok and none_radius < light_radius and light_radius < heavy_radius
	_check(ok, "40 terminal load changes endpoint radius impact and follow-through without selecting a different move family")


func _test_v3_tether_mode_owns_hit_three_reaction() -> void:
	var fishing := _soft_affordance()
	fishing.flex_topology = "bending_shaft"
	fishing.tether_topology = "flexible_line"
	fishing.terminal_load = "light"
	fishing.tether_mode = "hook"
	fishing.tether_deployment = "cast_retract"
	fishing.secondary_contact_surface = "point"
	fishing.has_point = true
	var fishing_profile := _compile_anonymous(fishing)
	var first: Resource = fishing_profile.combo_recipe.hit_1
	var third: Resource = fishing_profile.combo_recipe.hit_3
	var wrap := _soft_affordance()
	wrap.flex_topology = "flexible_line"
	wrap.tether_mode = "wrap"
	var wrap_profile := _compile_anonymous(wrap)
	var wrap_third: Resource = wrap_profile.combo_recipe.hit_3
	var arena: Variant = SLICE.new()
	arena.player_position = Vector2.ZERO
	var hook_feedback: Resource = FEEDBACK.for_attack(fishing_profile, "normal", 3, third)
	var wrap_feedback: Resource = FEEDBACK.for_attack(wrap_profile, "normal", 3, wrap_third)
	var hook_reaction: Dictionary = arena._hit_reaction(Vector2(100.0, 0.0), hook_feedback, third)
	var wrap_reaction: Dictionary = arena._hit_reaction(Vector2(100.0, 0.0), wrap_feedback, wrap_third)
	arena.free()
	var hook_knockback: Vector2 = hook_reaction["knockback"]
	var wrap_knockback: Vector2 = wrap_reaction["knockback"]
	var ok: bool = first.tether_mode == "none" and third.tether_mode == "hook"
	ok = ok and third.uses_secondary_contact and third.contact_surface == "point" and third.contact_anchor == "tip"
	ok = ok and hook_knockback.x < 0.0 and third.tether_strength > 0.0
	ok = ok and wrap_third.tether_mode == "wrap" and wrap_knockback.x > 0.0
	ok = ok and wrap_knockback.length() < wrap_feedback.knockback_strength * 0.25
	ok = ok and float(wrap_reaction["stagger"]) > wrap_feedback.stagger_strength
	_check(ok, "41 hook pulls toward the player and wrap suppresses knockback for a stronger hold only on hit three")


func _test_v4_tether_topology_is_an_independent_soft_path() -> void:
	var profiles := {}
	for topology: String in ["none", "flexible_line", "linked_segments"]:
		var affordance := _soft_affordance()
		affordance.tether_topology = topology
		affordance.tether_deployment = "fixed_length" if topology != "none" else "none"
		profiles[topology] = _compile_anonymous(affordance)
	var none_profile := profiles["none"] as Resource
	var line_profile := profiles["flexible_line"] as Resource
	var linked_profile := profiles["linked_segments"] as Resource
	var none_first: Resource = none_profile.combo_recipe.hit_1
	var line_first: Resource = line_profile.combo_recipe.hit_1
	var linked_first: Resource = linked_profile.combo_recipe.hit_1
	var arena: Variant = SLICE.new()
	var none_motion: float = arena._trajectory_motion_ratio(none_first, 0.55)
	var line_motion: float = arena._trajectory_motion_ratio(line_first, 0.55)
	var paths: Dictionary = arena._soft_mechanism_paths(
		Vector2.ZERO,
		Vector2(100.0, 0.0),
		line_first,
		Vector2(58.0, -24.0)
	)
	var body: PackedVector2Array = paths.get("body", PackedVector2Array())
	var tether: PackedVector2Array = paths.get("tether", PackedVector2Array())
	arena.free()
	var signatures := {
		none_profile.combo_recipe.signature(): true,
		line_profile.combo_recipe.signature(): true,
		linked_profile.combo_recipe.signature(): true,
	}
	var ok: bool = signatures.size() == 3
	ok = ok and none_profile.combo_recipe.primitive_sequence() == line_profile.combo_recipe.primitive_sequence()
	ok = ok and line_profile.combo_recipe.primitive_sequence() == linked_profile.combo_recipe.primitive_sequence()
	ok = ok and none_first.tether_topology == "none" and is_equal_approx(none_first.tether_origin_ratio, 1.0)
	ok = ok and line_first.tether_topology == "flexible_line" and line_first.tether_origin_ratio > 0.0 and line_first.tether_origin_ratio < 1.0
	ok = ok and linked_first.tether_topology == "linked_segments"
	ok = ok and line_first.trajectory_lag_ratio > none_first.trajectory_lag_ratio
	ok = ok and line_first.active_multiplier > none_first.active_multiplier
	ok = ok and line_first.soft_contact_start_ratio > none_first.soft_contact_start_ratio
	ok = ok and line_motion < none_motion
	ok = ok and body.size() >= 2 and tether.size() >= 2
	if body.size() >= 2 and tether.size() >= 2:
		ok = ok and body[body.size() - 1].distance_to(tether[0]) < 0.001
		ok = ok and tether[tether.size() - 1].distance_to(Vector2(100.0, 0.0)) < 0.001
	_check(ok, "42 an attached line or chain adds a second connected propagation path without changing the generic move family")


func _test_v4_fishing_rod_asset_compiles_from_ai_axes_without_name_rules() -> void:
	var loaded: Dictionary = LOADER.new().load_soft_weapon_asset("fishing_rod_builtin")
	var asset := loaded.get("asset") as WeaponVisualAsset
	var affordance := loaded.get("affordance_profile") as Resource
	var compiled: Resource
	if asset != null and affordance != null:
		compiled = COMPILER.new().compile(affordance, asset.anchors_dict(), asset.opaque_bounds) as Resource
	var resolution: Dictionary = loaded.get("mechanism_resolution", {})
	var ok: bool = bool(loaded.get("ok", false)) and asset != null and affordance != null and compiled != null
	ok = ok and bool(loaded.get("developer_only", false)) and not bool(loaded.get("normal_player_flow", true))
	ok = ok and bool(loaded.get("automatic_mechanism", false)) and bool(resolution.get("automatic", false))
	ok = ok and not bool(resolution.get("player_confirmation_required", true)) and not resolution.has("questions")
	if asset != null:
		ok = ok and asset.source_image.get_size() == Vector2i(96, 96)
		ok = ok and asset.tether_origin != asset.tip and asset.tether_origin != asset.grip_primary
	if affordance != null:
		ok = ok and affordance.flex_topology == "bending_shaft"
		ok = ok and affordance.tether_topology == "flexible_line"
		ok = ok and affordance.terminal_load == "light" and affordance.tether_mode == "hook"
		ok = ok and affordance.tether_deployment == "cast_retract"
	if compiled != null:
		var first: Resource = compiled.combo_recipe.hit_1
		var third: Resource = compiled.combo_recipe.hit_3
		ok = ok and compiled.validation_errors().is_empty()
		ok = ok and compiled.combo_recipe.primitive_sequence() == PackedStringArray(["sweep", "spin", "thrust"])
		ok = ok and first.tether_mode == "none" and third.tether_mode == "hook"
		ok = ok and first.tether_deployment == "fixed_length" and third.tether_deployment == "cast_retract"
		ok = ok and third.uses_secondary_contact and third.contact_surface == "point"
		ok = ok and third.flex_topology == "bending_shaft" and third.tether_topology == "flexible_line"
		ok = ok and third.tether_origin_ratio > 0.0 and third.tether_origin_ratio < 1.0
		if asset != null:
			var body_length := asset.grip_primary.distance_to(asset.tether_origin)
			var line_length := asset.tether_origin.distance_to(asset.tip)
			ok = ok and is_equal_approx(third.tether_origin_ratio, body_length / (body_length + line_length))
		ok = ok and third.tether_strength > 0.0
	var mechanism_sources := "\n".join([
		FileAccess.get_file_as_string("res://scripts/combat_feel/melee_motion_compiler.gd"),
		FileAccess.get_file_as_string("res://scripts/combat_feel/mechanism_axis_resolver.gd"),
		FileAccess.get_file_as_string("res://scripts/combat_feel/combat_feel_slice_0.gd"),
	]).to_lower()
	ok = ok and not mechanism_sources.contains("fishing_rod")
	_check(ok, "43 the generated 96px rod is resolved by AI axes into bending shaft plus flexible line with no player question or fishing-rod rule")


func _test_v7_tether_deployment_owns_endpoint_timeline() -> void:
	var arena: Variant = SLICE.new()
	arena.player_facing = 1.0
	var primitive: Variant = PRIMITIVE.new()
	primitive.tether_topology = "flexible_line"
	primitive.tether_origin_ratio = 0.55
	primitive.tether_deployment = "cast_retract"
	var origin := Vector2(52.0, 18.0)
	var resting := Vector2(82.0, 76.0)
	var target := Vector2(148.0, 22.0)
	var loaded: Dictionary = arena._tether_deployment_state(primitive, origin, target, resting, 0.26)
	var outbound: Dictionary = arena._tether_deployment_state(primitive, origin, target, resting, 0.46)
	var tensioned: Dictionary = arena._tether_deployment_state(primitive, origin, target, resting, 0.70)
	var retracting: Dictionary = arena._tether_deployment_state(primitive, origin, target, resting, 0.90)
	var settled: Dictionary = arena._tether_deployment_state(primitive, origin, target, resting, 1.0)
	var launched: Resource = primitive.duplicate()
	launched.tether_deployment = "launch_tension"
	var held: Dictionary = arena._tether_deployment_state(launched, origin, target, resting, 0.92)
	var fixed: Resource = primitive.duplicate()
	fixed.tether_deployment = "fixed_length"
	var fixed_state: Dictionary = arena._tether_deployment_state(fixed, origin, target, resting, 0.46)
	var loaded_contact := Vector2(loaded.get("contact", Vector2.ZERO))
	var outbound_contact := Vector2(outbound.get("contact", Vector2.ZERO))
	var retract_contact := Vector2(retracting.get("contact", Vector2.ZERO))
	var ok := str(loaded.get("phase", "")) == "loaded"
	ok = ok and origin.distance_to(loaded_contact) < origin.distance_to(resting) * 0.45
	ok = ok and str(outbound.get("phase", "")) == "outbound"
	ok = ok and outbound_contact.x > loaded_contact.x and outbound_contact.x < target.x
	ok = ok and outbound_contact.y < maxf(loaded_contact.y, target.y)
	ok = ok and Vector2(tensioned.get("contact", Vector2.ZERO)).distance_to(target) < 0.001
	ok = ok and str(retracting.get("phase", "")) == "retract"
	ok = ok and origin.distance_to(retract_contact) < origin.distance_to(target)
	ok = ok and Vector2(settled.get("contact", Vector2.ZERO)).distance_to(resting) < 0.001
	ok = ok and str(held.get("phase", "")) == "tensioned" and Vector2(held.get("contact", Vector2.ZERO)).distance_to(target) < 0.001
	ok = ok and str(fixed_state.get("phase", "")) == "fixed" and Vector2(fixed_state.get("contact", Vector2.ZERO)).distance_to(resting) < 0.001
	arena.free()
	_check(ok, "43a line deployment independently loads casts reaches retracts or stays tensioned while fixed-length lines keep the old endpoint")


func _test_v5_ai_visual_rig_binds_every_visible_source_pixel() -> void:
	var loader: Variant = LOADER.new()
	var loaded: Dictionary = loader.load_soft_weapon_asset("fishing_rod_builtin")
	var asset := loaded.get("asset") as WeaponVisualAsset
	var rig: PixelWeaponVisualRig = asset.visual_rig if asset != null else null
	var summary: Dictionary = rig.summary() if rig != null else {}
	var without_rig: Dictionary = loader.load_live(
		"res://data/combat_feel/live_assets/soft_weapon_v1/fishing_rod_builtin/processed_sprite.png",
		"res://data/combat_feel/live_assets/soft_weapon_v1/fishing_rod_builtin/semantic_blueprint.json",
		"res://data/combat_feel/live_assets/soft_weapon_v1/fishing_rod_builtin/anchors.json"
	)
	var ok: bool = bool(loaded.get("ok", false)) and rig != null
	ok = ok and bool(loaded.get("automatic_visual_rig", false))
	ok = ok and bool(summary.get("automatic", false)) and not bool(summary.get("player_confirmation_required", true))
	ok = ok and int(summary.get("bound_pixels", 0)) == int(summary.get("source_opaque_pixels", -1))
	ok = ok and int(summary.get("unassigned_pixels", -1)) == 0
	for role: String in ["rigid_root", "deform_body", "tether", "terminal"]:
		ok = ok and rig.pixel_count(role) > 0
	var automatic_asset := without_rig.get("asset") as WeaponVisualAsset
	var automatic_rig: PixelWeaponVisualRig = automatic_asset.visual_rig if automatic_asset != null else null
	var automatic_summary: Dictionary = automatic_rig.summary() if automatic_rig != null else {}
	ok = ok and bool(without_rig.get("ok", false)) and bool(without_rig.get("automatic_visual_rig", false))
	ok = ok and automatic_asset != null and automatic_rig != null
	ok = ok and automatic_asset.visual_rig_source == "ai_axes_plus_alpha_path_v1"
	ok = ok and not bool(automatic_summary.get("player_confirmation_required", true))
	ok = ok and int(automatic_summary.get("bound_pixels", 0)) == int(automatic_summary.get("source_opaque_pixels", -1))
	for role: String in ["rigid_root", "deform_body", "tether", "terminal"]:
		ok = ok and automatic_rig.pixel_count(role) > 0
	ok = ok and automatic_asset.tether_origin.distance_to(automatic_asset.grip_primary) > 8.0
	ok = ok and automatic_asset.tether_origin.distance_to(automatic_asset.tip) > 8.0
	_check(ok, "44 explicit AI structure binds every source pixel and a missing sidecar is rebuilt automatically from AI axes plus the real Alpha path without asking the player")


func _test_v5_original_pixels_follow_body_tether_and_terminal_paths() -> void:
	var loaded: Dictionary = LOADER.new().load_soft_weapon_asset("fishing_rod_builtin")
	var asset := loaded.get("asset") as WeaponVisualAsset
	var rig: PixelWeaponVisualRig = asset.visual_rig if asset != null else null
	var bent_body := PackedVector2Array([Vector2.ZERO, Vector2(38.0, -28.0), Vector2(78.0, 0.0)])
	var bent_tether := PackedVector2Array([Vector2(78.0, 0.0), Vector2(102.0, 34.0), Vector2(132.0, 0.0)])
	var straight_body := PackedVector2Array([Vector2.ZERO, Vector2(78.0, 0.0)])
	var straight_tether := PackedVector2Array([Vector2(78.0, 0.0), Vector2(132.0, 0.0)])
	var common := {
		"weapon_origin": Vector2.ZERO,
		"source_grip": asset.grip_primary if asset != null else Vector2.ZERO,
		"contact": Vector2(132.0, 0.0),
		"weapon_angle": 0.0,
		"facing": 1.0,
		"scale": 1.0,
		"pixel_snap": false,
	}
	var bent_geometry := common.duplicate(true)
	bent_geometry["body"] = bent_body
	bent_geometry["tether"] = bent_tether
	var straight_geometry := common.duplicate(true)
	straight_geometry["body"] = straight_body
	straight_geometry["tether"] = straight_tether
	var bent: Dictionary = PIXEL_DEFORMER.deform(rig, bent_geometry)
	var straight: Dictionary = PIXEL_DEFORMER.deform(rig, straight_geometry)
	var raster: Dictionary = PIXEL_DEFORMER.rasterize(bent, 6, 3)
	var raster_image := raster.get("image") as Image
	var bent_centroids: Dictionary = bent.get("role_centroids", {})
	var straight_centroids: Dictionary = straight.get("role_centroids", {})
	var bent_pixels: Array = bent.get("pixels", [])
	var ok: bool = rig != null and bent_pixels.size() == rig.bindings.size()
	ok = ok and raster_image != null
	if raster_image != null:
		ok = ok and raster_image.get_used_rect().has_area()
	if rig != null and bent_pixels.size() == rig.bindings.size():
		for index: int in range(rig.bindings.size()):
			ok = ok and Color(bent_pixels[index].get("color", Color.TRANSPARENT)).is_equal_approx(
				Color(rig.bindings[index].get("color", Color.WHITE))
			)
	ok = ok and Vector2(bent_centroids.get("rigid_root", Vector2.ZERO)).distance_to(
		Vector2(straight_centroids.get("rigid_root", Vector2.ONE * 999.0))
	) < 0.001
	ok = ok and Vector2(bent_centroids.get("deform_body", Vector2.ZERO)).distance_to(
		Vector2(straight_centroids.get("deform_body", Vector2.ZERO))
	) > 4.0
	ok = ok and Vector2(bent_centroids.get("tether", Vector2.ZERO)).distance_to(
		Vector2(straight_centroids.get("tether", Vector2.ZERO))
	) > 4.0
	ok = ok and Vector2(bent_centroids.get("terminal", Vector2.ZERO)).distance_to(Vector2(132.0, 0.0)) < 12.0
	_check(ok, "45 original RGBA pixels stay intact while rigid root body tether and terminal follow their own connected transforms")


func _test_v5_topology_axes_produce_distinct_pixel_geometry() -> void:
	var arena: Variant = SLICE.new()
	var paths: Dictionary = {}
	for topology: String in ["bending_shaft", "flexible_line", "linked_segments"]:
		var primitive: Variant = PRIMITIVE.new()
		primitive.flex_topology = topology
		primitive.tether_topology = "none"
		paths[topology] = arena._soft_mechanism_paths(Vector2.ZERO, Vector2(100.0, 0.0), primitive).get("body", PackedVector2Array())
	arena.free()
	var shaft: PackedVector2Array = paths["bending_shaft"]
	var line: PackedVector2Array = paths["flexible_line"]
	var linked: PackedVector2Array = paths["linked_segments"]
	var shaft_signature: Dictionary = PIXEL_DEFORMER.path_signature(shaft)
	var line_signature: Dictionary = PIXEL_DEFORMER.path_signature(line)
	var linked_signature: Dictionary = PIXEL_DEFORMER.path_signature(linked)
	var ok: bool = shaft.size() == 15 and line.size() == 15 and linked.size() == 10
	ok = ok and float(line_signature.get("length", 0.0)) > float(shaft_signature.get("length", 0.0))
	ok = ok and float(linked_signature.get("maximum_corner_radians", 0.0)) > float(shaft_signature.get("maximum_corner_radians", 0.0))
	ok = ok and shaft != line and line != linked and shaft != linked
	_check(ok, "46 bending shaft continuous line and linked segments create measurably different pixel paths from one changed mechanism axis")


func _test_v5_render_and_collision_share_the_same_soft_paths() -> void:
	var body := PackedVector2Array([Vector2.ZERO, Vector2(45.0, -25.0), Vector2(80.0, 0.0)])
	var tether := PackedVector2Array([Vector2(80.0, 0.0), Vector2(105.0, 30.0), Vector2(130.0, 5.0)])
	var joined := PIXEL_DEFORMER.joined_paths(body, tether)
	var active := PIXEL_DEFORMER.trim_polyline(joined, 0.55)
	var source := FileAccess.get_file_as_string(SLICE_PATH)
	var collision_source := _function_source(source, "func _soft_visual_attack_contains", "func _draw_soft_visual_hitbox")
	var draw_source := _function_source(source, "func _draw_soft_visual_hitbox", "func _draw_active_hitbox")
	var ok: bool = joined.size() == 5 and joined[2].distance_to(tether[0]) < 0.001
	ok = ok and active.size() >= 2
	ok = ok and PIXEL_DEFORMER.distance_to_polyline(Vector2(105.0, 28.0), joined, 0.55) < 3.0
	ok = ok and PIXEL_DEFORMER.distance_to_polyline(Vector2(25.0, -14.0), joined, 0.55) > 20.0
	ok = ok and collision_source.contains("PIXEL_WEAPON_DEFORMER.joined_paths")
	ok = ok and draw_source.contains("PIXEL_WEAPON_DEFORMER.joined_paths")
	_check(ok, "47 visible soft pixels and active collision both consume the same joined body-and-tether path including the same live contact portion")


func _test_v5_four_anonymous_visual_structures_validate_without_identity_rules() -> void:
	var image := _anonymous_pixel_strip_image()
	var cases: Array[Dictionary] = [
		{
			"profile": _soft_affordance(),
			"contract": _anonymous_visual_rig_contract(true, true, true),
		},
		{
			"profile": _soft_affordance(),
			"contract": _anonymous_visual_rig_contract(true, false, false),
			"flex": "flexible_line",
		},
		{
			"profile": _soft_affordance(),
			"contract": _anonymous_visual_rig_contract(true, false, false),
			"flex": "linked_segments",
		},
		{
			"profile": _anonymous_profile(),
			"contract": _anonymous_visual_rig_contract(false, false, false),
		},
	]
	var ok := true
	for entry: Dictionary in cases:
		var profile: Resource = entry["profile"]
		if entry.has("flex"):
			profile.flex_topology = str(entry["flex"])
		if bool(entry["contract"].get("has_tether", false)):
			profile.tether_topology = "flexible_line"
			profile.terminal_load = "light"
			profile.tether_mode = "hook"
			profile.tether_deployment = "cast_retract"
		var rig: PixelWeaponVisualRig = PIXEL_VISUAL_RIG.from_dict(entry["contract"], image)
		ok = ok and rig.validation_errors().is_empty() and rig.axis_errors(profile).is_empty()
	var mechanism_sources := "\n".join([
		FileAccess.get_file_as_string("res://scripts/data/pixel_weapon_visual_rig.gd"),
		FileAccess.get_file_as_string("res://scripts/combat_feel/pixel_weapon_deformer.gd"),
		FileAccess.get_file_as_string("res://scripts/combat_feel/automatic_pixel_visual_rig_builder.gd"),
		FileAccess.get_file_as_string("res://scripts/combat_feel/combat_feel_slice_0.gd"),
	]).to_lower()
	for forbidden: String in ["fishing_rod", "whip", "braid", "stick_weapon"]:
		ok = ok and not mechanism_sources.contains(forbidden)
	_check(ok, "48 composite rod line continuous lash linked braid and rigid control validate as anonymous structures without weapon-name branches")


func _test_v5_builtin_structure_samples_load_through_one_generic_pipeline() -> void:
	var loader: Variant = LOADER.new()
	var expected := {
		"fishing_rod_builtin": ["bending_shaft", "flexible_line", "light", "hook", "cast_retract"],
		"continuous_lash_builtin": ["flexible_line", "none", "none", "wrap", "none"],
		"linked_braid_builtin": ["linked_segments", "none", "light", "none", "none"],
		"rigid_staff_builtin": ["none", "none", "none", "none", "none"],
	}
	var ok: bool = loader.soft_weapon_asset_ids() == Array(expected.keys())
	for asset_id: String in expected:
		var loaded: Dictionary = loader.load_soft_weapon_asset(asset_id)
		var asset := loaded.get("asset") as WeaponVisualAsset
		var profile := loaded.get("affordance_profile") as Resource
		var axes: Array = expected[asset_id]
		ok = ok and bool(loaded.get("ok", false)) and asset != null and profile != null
		if asset != null:
			ok = ok and asset.source_image.get_size() == Vector2i(96, 96) and asset.has_pixel_visual_rig()
		if profile != null:
			ok = ok and [profile.flex_topology, profile.tether_topology, profile.terminal_load, profile.tether_mode, profile.tether_deployment] == axes
			var compiled: Resource = COMPILER.new().compile(profile, asset.anchors_dict(), asset.opaque_bounds) as Resource if asset != null else null
			ok = ok and compiled != null and compiled.validation_errors().is_empty()
		ok = ok and bool(loaded.get("automatic_mechanism", false)) and bool(loaded.get("automatic_visual_rig", false))
		ok = ok and not bool((loaded.get("mechanism_resolution", {}) as Dictionary).get("player_confirmation_required", true))
	_check(ok, "49 four recognizable pixel structures load through one automatic AI-axis and visual-rig pipeline including a rigid control")


func _test_v5_soft_body_starts_at_its_visual_connection_not_the_hand_pivot() -> void:
	var loader: Variant = LOADER.new()
	var loaded: Dictionary = loader.load_soft_weapon_asset("continuous_lash_builtin")
	var asset := loaded.get("asset") as WeaponVisualAsset
	var profile: Resource
	if asset != null:
		profile = COMPILER.new().compile(loaded.get("affordance_profile") as Resource, asset.anchors_dict(), asset.opaque_bounds) as Resource
	var arena: Variant = SLICE.new()
	arena.asset = asset
	arena.motion_profile = profile
	arena.controller = CONTROLLER.new()
	if profile != null:
		arena.controller.configure(profile)
		arena.controller.current_primitive = profile.combo_recipe.hit_1
		arena.controller.combo_index = 1
		arena.controller.attack_kind = "normal"
		arena.controller.phase = "active"
		arena.controller.phase_duration = 1.0
		arena.controller.phase_elapsed = 0.52
	var geometry: Dictionary = arena._soft_visual_geometry(arena.controller.current_primitive) if profile != null else {}
	var body: PackedVector2Array = geometry.get("body", PackedVector2Array())
	var weapon_origin := Vector2(geometry.get("weapon_origin", Vector2.ZERO))
	var body_origin := Vector2(geometry.get("body_origin", Vector2.ZERO))
	var ok: bool = asset != null and profile != null and not geometry.is_empty()
	ok = ok and body_origin.distance_to(weapon_origin) > 4.0
	ok = ok and body.size() >= 2 and body[0].distance_to(body_origin) < 0.001
	var source := FileAccess.get_file_as_string("res://scripts/open_identity_spike.gd")
	ok = ok and source.contains("_attach_current_ai_visual_rig")
	ok = ok and source.contains("build_automatic_visual_rig")
	ok = ok and source.contains('"player_confirmation_required": false')
	arena.free()
	_check(ok, "50 a handled soft body begins at its declared fixture connection and the live AI flow rebuilds missing visual structure without asking the player")


func _test_v6_missing_sidecar_autobuilds_anonymous_soft_structures() -> void:
	var image := _anonymous_pixel_strip_image()
	var cases: Array[Dictionary] = []
	var composite := _soft_affordance()
	composite.flex_topology = "bending_shaft"
	composite.tether_topology = "flexible_line"
	composite.terminal_load = "light"
	composite.tether_mode = "hook"
	composite.tether_deployment = "cast_retract"
	cases.append({"profile": composite, "roles": ["rigid_root", "deform_body", "tether", "terminal"]})
	var continuous := _soft_affordance()
	continuous.flex_topology = "flexible_line"
	cases.append({"profile": continuous, "roles": ["rigid_root", "deform_body"]})
	var linked := _soft_affordance()
	linked.flex_topology = "linked_segments"
	cases.append({"profile": linked, "roles": ["rigid_root", "deform_body"]})
	var attached_only := _soft_affordance()
	attached_only.flex_topology = "none"
	attached_only.tether_topology = "flexible_line"
	attached_only.terminal_load = "light"
	attached_only.tether_mode = "wrap"
	attached_only.tether_deployment = "fixed_length"
	cases.append({"profile": attached_only, "roles": ["rigid_root", "rigid_body", "tether", "terminal"]})
	var ok := true
	for entry: Dictionary in cases:
		var asset := WeaponVisualAsset.new()
		asset.source_image = image.duplicate()
		asset.canvas_size = image.get_size()
		asset.opaque_bounds = image.get_used_rect()
		asset.grip_primary = Vector2(12.0, 49.0)
		asset.tip = Vector2(88.0, 77.0)
		var built: Dictionary = LOADER.new().build_automatic_visual_rig(asset, entry["profile"] as Resource)
		var rig: PixelWeaponVisualRig = asset.visual_rig
		ok = ok and bool(built.get("ok", false)) and rig != null
		ok = ok and not bool(built.get("player_confirmation_required", true))
		ok = ok and asset.visual_rig_source == "ai_axes_plus_alpha_path_v1"
		if rig != null:
			ok = ok and rig.validation_errors().is_empty() and rig.axis_errors(entry["profile"] as Resource).is_empty()
			ok = ok and rig.bindings.size() == rig.source_opaque_pixels
			for role: String in entry["roles"]:
				ok = ok and rig.pixel_count(role) > 0
	_check(ok, "51 absent sidecars for anonymous composite continuous linked and attached-only structures are inferred from mechanism axes and Alpha without identity branches or player questions")


func _anonymous_pixel_strip_image() -> Image:
	var image := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(4, 43, 19, 13), Color("8b5a2b"))
	_draw_test_pixel_line(image, Vector2i(17, 49), Vector2i(64, 49), Color("5b8fb9"), 2)
	_draw_test_pixel_line(image, Vector2i(64, 49), Vector2i(88, 77), Color("d8c36a"), 1)
	image.fill_rect(Rect2i(84, 73, 9, 10), Color("d97732"))
	return image


func _anonymous_visual_rig_contract(has_body: bool, has_tether: bool, has_terminal: bool) -> Dictionary:
	var root_polygon: Array = [[2.0, 39.0], [25.0, 39.0], [25.0, 59.0], [2.0, 59.0]]
	if not has_body:
		root_polygon = [[0.0, 0.0], [95.0, 0.0], [95.0, 95.0], [0.0, 95.0]]
	var parts: Array[Dictionary] = [{
		"id": "part_0",
		"role": "rigid_root",
		"pivot": [12.0, 49.0],
		"mask_polygon": root_polygon,
		"priority": 100,
		"z_index": 0,
	}]
	if has_body:
		parts.append({
			"id": "part_1",
			"role": "deform_body",
			"source_path": [[17.0, 49.0], [40.0, 49.0], [64.0, 49.0]],
			"mask_radius": 5.0,
			"priority": 20,
			"z_index": 1,
		})
	if has_tether:
		parts.append({
			"id": "part_2",
			"role": "tether",
			"source_path": [[64.0, 49.0], [76.0, 63.0], [88.0, 77.0]],
			"mask_radius": 4.0,
			"priority": 30,
			"z_index": 2,
		})
	if has_terminal:
		parts.append({
			"id": "part_3",
			"role": "terminal",
			"pivot": [88.0, 77.0],
			"source_direction": [0.65, 0.76],
			"mask_polygon": [[82.0, 70.0], [95.0, 70.0], [95.0, 86.0], [82.0, 86.0]],
			"priority": 110,
			"z_index": 3,
		})
	return {
		"schema": "forge-pixel-weapon-visual-rig-v1",
		"source": "ai_anonymous_structure_probe_v1",
		"automatic": true,
		"player_confirmation_required": false,
		"confidence": 0.95,
		"has_tether": has_tether,
		"parts": parts,
	}


func _draw_test_pixel_line(image: Image, start: Vector2i, finish: Vector2i, color: Color, radius: int) -> void:
	var delta := finish - start
	var steps := maxi(abs(delta.x), abs(delta.y))
	for step: int in range(steps + 1):
		var ratio := float(step) / maxf(1.0, float(steps))
		var center := Vector2i(roundi(lerpf(float(start.x), float(finish.x), ratio)), roundi(lerpf(float(start.y), float(finish.y), ratio)))
		for offset_y: int in range(-radius, radius + 1):
			for offset_x: int in range(-radius, radius + 1):
				var pixel := center + Vector2i(offset_x, offset_y)
				if pixel.x >= 0 and pixel.y >= 0 and pixel.x < image.get_width() and pixel.y < image.get_height():
					image.set_pixelv(pixel, color)


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
		"contact_surface", "secondary_contact_surface", "flex_topology", "tether_topology", "terminal_load", "tether_mode", "tether_deployment", "has_point", "has_edge",
		"has_broad_face", "has_barrel", "has_stock", "confidence", "evidence_parts",
	]:
		copied.set(property, source.get(property))
	return copied


func _anonymous_profile() -> Resource:
	var profile: Variant = AFFORDANCE.new()
	profile.handle_length = "medium"
	profile.body_length = "medium"
	profile.grip_topology = "one_hand_handle"
	profile.rigidity = "rigid"
	profile.mass_distribution = "balanced"
	profile.contact_surface = "broad"
	profile.secondary_contact_surface = "none"
	profile.confidence = 1.0
	profile.evidence_parts = PackedStringArray(["anonymous mechanism-axis v3 probe"])
	return profile


func _soft_affordance() -> Resource:
	var profile: Variant = AFFORDANCE.new()
	profile.handle_length = "medium"
	profile.body_length = "long"
	profile.grip_topology = "two_hand_handle"
	profile.rigidity = "flexible"
	profile.flex_topology = "bending_shaft"
	profile.tether_topology = "none"
	profile.terminal_load = "none"
	profile.tether_mode = "none"
	profile.tether_deployment = "none"
	profile.mass_distribution = "rear"
	profile.contact_surface = "whole_body"
	profile.secondary_contact_surface = "none"
	profile.confidence = 1.0
	profile.evidence_parts = PackedStringArray(["anonymous soft mechanism-axis v3 probe"])
	return profile


func _compile_anonymous(profile: Resource) -> Resource:
	return COMPILER.new().compile(
		profile,
		{
			"GripPrimary": [24.0, 48.0],
			"GripSecondary": [38.0, 48.0],
			"StrikePoint": [78.0, 48.0],
			"Muzzle": [82.0, 48.0],
		},
		Rect2i(8, 24, 80, 48)
	) as Resource


func _orthogonal_basis_profiles() -> Array[Resource]:
	var values: Array[Resource] = []
	for data: Dictionary in [
		{"handle": "short", "body": "short", "grip": "one_hand_handle", "surface": "broad", "secondary": "none", "rigidity": "rigid", "flex": "none", "mass": "front", "point": false, "edge": false, "broad": true, "barrel": false, "stock": false},
		{"handle": "long", "body": "long", "grip": "two_hand_handle", "surface": "edge", "secondary": "none", "rigidity": "semi_rigid", "flex": "none", "mass": "balanced", "point": false, "edge": true, "broad": false, "barrel": false, "stock": false},
		{"handle": "long", "body": "long", "grip": "two_hand_handle", "surface": "point", "secondary": "broad", "rigidity": "rigid", "flex": "none", "mass": "rear", "point": true, "edge": false, "broad": false, "barrel": true, "stock": true},
		{"handle": "none", "body": "medium", "grip": "body_grip", "surface": "whole_body", "secondary": "none", "rigidity": "flexible", "flex": "bending_shaft", "mass": "balanced", "point": false, "edge": false, "broad": false, "barrel": false, "stock": false},
	]:
		var profile: Variant = AFFORDANCE.new()
		profile.handle_length = data["handle"]
		profile.body_length = data["body"]
		profile.grip_topology = data["grip"]
		profile.contact_surface = data["surface"]
		profile.secondary_contact_surface = data["secondary"]
		profile.rigidity = data["rigidity"]
		profile.flex_topology = data["flex"]
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
