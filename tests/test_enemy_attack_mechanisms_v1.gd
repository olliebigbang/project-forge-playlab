extends SceneTree

const COMPILER := preload("res://scripts/enemy_attack/enemy_attack_mechanism_compiler.gd")
const SELECTOR := preload("res://scripts/enemy_attack/enemy_attack_selector.gd")

var passed := 0
var failed := 0


func _init() -> void:
	_test_anonymous_declaration_compiles_to_four_phase_contract()
	_test_telegraph_and_hit_region_share_one_geometry()
	_test_four_delivery_families_compile_without_enemy_identity()
	_test_target_lock_is_explicit_and_stops_post_lock_steering()
	_test_interruptibility_profiles_are_phase_specific()
	_test_recovery_profiles_create_distinct_punish_windows()
	_test_each_mechanism_axis_has_a_finite_difference()
	_test_invalid_identity_fields_and_incompatible_combinations_fail_closed()
	_test_selector_chooses_by_range_and_depth_context()
	_test_selector_filters_path_budget_and_cooldown()
	_test_selector_repeat_penalty_and_rank_are_deterministic()
	_test_mechanism_sources_have_no_enemy_identity_branches()
	print("ENEMY ATTACK MECHANISMS V1 RESULT: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _test_anonymous_declaration_compiles_to_four_phase_contract() -> void:
	var compiled: Dictionary = COMPILER.compile(_declaration())
	var timeline := compiled.get("timeline", {}) as Dictionary
	var ok := bool(compiled.get("ok", false))
	ok = ok and str(compiled.get("schema", "")) == "forge-enemy-attack-mechanism-v1"
	ok = ok and timeline.get("state_sequence", []) == ["telegraph", "commit", "active", "recovery"]
	ok = ok and not bool(compiled.get("identity_inputs_used", true))
	ok = ok and not bool(compiled.get("player_confirmation_required", true))
	ok = ok and not str(compiled.get("mechanism_signature", "")).is_empty()
	_check(ok, "01 anonymous attack data compiles to the fixed telegraph commit active recovery contract")


func _test_telegraph_and_hit_region_share_one_geometry() -> void:
	var compiled: Dictionary = COMPILER.compile(_declaration())
	var telegraph := compiled.get("telegraph", {}) as Dictionary
	var hit_region := compiled.get("hit_region", {}) as Dictionary
	var preview := telegraph.get("preview_region", {}) as Dictionary
	var ok := bool(compiled.get("ok", false))
	ok = ok and str(telegraph.get("preview_geometry_signature", "")) == str(hit_region.get("geometry_signature", ""))
	ok = ok and str(preview.get("geometry_signature", "")) == str(hit_region.get("geometry_signature", ""))
	for field: String in ["shape", "length_pixels", "width_pixels", "radius_pixels", "arc_degrees", "path_mode", "depth_tolerance_pixels"]:
		ok = ok and preview.get(field) == hit_region.get(field)
	_check(ok, "02 telegraph preview and active hit region consume exactly the same compiled geometry")


func _test_four_delivery_families_compile_without_enemy_identity() -> void:
	var declarations: Array[Dictionary] = [
		_declaration({"delivery": "contact", "target_lock": "live_until_active", "hit_shape": "arc"}, {}, "slot_contact"),
		_declaration({"delivery": "rush", "target_lock": "direction_on_commit", "hit_shape": "strip", "depth_path": "cross_depth"}, {}, "slot_rush"),
		_declaration({"delivery": "projectile", "target_lock": "direction_on_commit", "hit_shape": "capsule"}, {}, "slot_projectile"),
		_declaration({"delivery": "marked_impact", "target_lock": "point_on_commit", "hit_shape": "circle", "depth_path": "depth_band"}, {}, "slot_marked"),
	]
	var origins: Array[String] = []
	var cues: Array[String] = []
	var ok := true
	for declaration: Dictionary in declarations:
		var compiled: Dictionary = COMPILER.compile(declaration)
		ok = ok and bool(compiled.get("ok", false))
		origins.append(str((compiled.get("attack_motion", {}) as Dictionary).get("origin_mode", "")))
		cues.append(str((compiled.get("telegraph", {}) as Dictionary).get("cue_family", "")))
	ok = ok and origins == ["attacker", "attacker", "detached", "locked_point"]
	ok = ok and cues == ["body_pose", "path_lane", "launch_lane", "ground_marker"]
	_check(ok, "03 contact rush projectile and marked impact compile through one anonymous data path")


func _test_target_lock_is_explicit_and_stops_post_lock_steering() -> void:
	var direction_attack: Dictionary = COMPILER.compile(_declaration(
		{"target_lock": "direction_on_commit", "hit_shape": "capsule"},
		{},
		"slot_direction"
	))
	var point_attack: Dictionary = COMPILER.compile(_declaration(
		{"delivery": "marked_impact", "target_lock": "point_on_commit", "hit_shape": "circle"},
		{},
		"slot_point"
	))
	var direction_telegraph := direction_attack.get("telegraph", {}) as Dictionary
	var point_telegraph := point_attack.get("telegraph", {}) as Dictionary
	var motion := direction_attack.get("attack_motion", {}) as Dictionary
	var ok := str(direction_telegraph.get("lock_event", "")) == "commit_start"
	ok = ok and str(direction_telegraph.get("aim_reference", "")) == "direction"
	ok = ok and direction_telegraph.get("tracks_target_during", []) == ["telegraph"]
	ok = ok and str(point_telegraph.get("aim_reference", "")) == "world_point"
	ok = ok and not bool(motion.get("direction_changes_after_lock", true))
	_check(ok, "04 lock event aim reference and tracking window are explicit with no hidden post-lock steering")


func _test_interruptibility_profiles_are_phase_specific() -> void:
	var fragile: Dictionary = COMPILER.compile(_declaration({"stability": "fragile"}))
	var tell_only: Dictionary = COMPILER.compile(_declaration({"stability": "tell_interruptible"}))
	var armored: Dictionary = COMPILER.compile(_declaration({"stability": "armored_commit"}))
	var fragile_rules := fragile.get("interruptibility", {}) as Dictionary
	var tell_rules := tell_only.get("interruptibility", {}) as Dictionary
	var armored_rules := armored.get("interruptibility", {}) as Dictionary
	var ok := bool(fragile_rules.get("telegraph", false)) and bool(fragile_rules.get("commit", false)) and bool(fragile_rules.get("active", false))
	ok = ok and bool(tell_rules.get("telegraph", false)) and not bool(tell_rules.get("commit", true)) and not bool(tell_rules.get("active", true))
	ok = ok and float(armored_rules.get("minimum_interrupt_strength", 0.0)) > float(tell_rules.get("minimum_interrupt_strength", 0.0))
	ok = ok and str(armored_rules.get("on_interrupt_next_phase", "")) == "recovery"
	_check(ok, "05 stability axis compiles explicit phase interrupt rules and interruption always exits to recovery")


func _test_recovery_profiles_create_distinct_punish_windows() -> void:
	var brief := (COMPILER.compile(_declaration({"recovery": "brief"})).get("recovery", {}) as Dictionary)
	var punishable := (COMPILER.compile(_declaration({"recovery": "punishable"})).get("recovery", {}) as Dictionary)
	var extended := (COMPILER.compile(_declaration({"recovery": "extended"})).get("recovery", {}) as Dictionary)
	var ok := float(brief.get("duration_seconds", 0.0)) < float(punishable.get("duration_seconds", 0.0))
	ok = ok and float(punishable.get("duration_seconds", 0.0)) < float(extended.get("duration_seconds", 0.0))
	ok = ok and float(brief.get("movement_multiplier", 0.0)) > float(punishable.get("movement_multiplier", 0.0))
	ok = ok and float(punishable.get("incoming_stagger_multiplier", 0.0)) < float(extended.get("incoming_stagger_multiplier", 0.0))
	_check(ok, "06 recovery axis independently controls punish duration mobility and stagger vulnerability")


func _test_each_mechanism_axis_has_a_finite_difference() -> void:
	var baseline: Dictionary = COMPILER.compile(_declaration(
		{
			"delivery": "contact",
			"target_lock": "direction_on_commit",
			"hit_shape": "capsule",
			"depth_path": "same_lane",
			"tempo": "standard",
			"stability": "tell_interruptible",
			"recovery": "punishable",
		}
	))
	var alternatives := {
		"delivery": "projectile",
		"target_lock": "live_until_active",
		"hit_shape": "arc",
		"depth_path": "cross_depth",
		"tempo": "quick",
		"stability": "fragile",
		"recovery": "extended",
	}
	var ok := bool(baseline.get("ok", false))
	var baseline_signature := str(baseline.get("mechanism_signature", ""))
	for axis: String in alternatives:
		var changed_axes := {
			"delivery": "contact",
			"target_lock": "direction_on_commit",
			"hit_shape": "capsule",
			"depth_path": "same_lane",
			"tempo": "standard",
			"stability": "tell_interruptible",
			"recovery": "punishable",
		}
		changed_axes[axis] = alternatives[axis]
		var changed: Dictionary = COMPILER.compile(_declaration(changed_axes))
		ok = ok and bool(changed.get("ok", false))
		ok = ok and str(changed.get("mechanism_signature", "")) != baseline_signature
	var owners := baseline.get("parameter_owners", {}) as Dictionary
	for owned_parameter: String in [
		"timeline.telegraph_seconds",
		"timeline.active_seconds",
		"telegraph.lock_event",
		"hit_region.shape",
		"hit_region.path_mode",
		"interruptibility",
		"recovery",
	]:
		ok = ok and owners.has(owned_parameter)
	_check(ok, "07 every mechanism axis creates a finite compiled difference and every runtime family has a declared owner")


func _test_invalid_identity_fields_and_incompatible_combinations_fail_closed() -> void:
	var identity_declaration := _declaration()
	identity_declaration["enemy_name"] = "identity_should_not_be_read"
	var identity_result: Dictionary = COMPILER.compile(identity_declaration)
	var invalid_rush: Dictionary = COMPILER.compile(_declaration(
		{"delivery": "rush", "target_lock": "live_until_active", "hit_shape": "strip"}
	))
	var missing_axis := _declaration()
	(missing_axis["axes"] as Dictionary).erase("recovery")
	var missing_result: Dictionary = COMPILER.compile(missing_axis)
	var ok := not bool(identity_result.get("ok", true)) and str(identity_result.get("error", "")) == "UNSUPPORTED_FIELD:enemy_name"
	ok = ok and not bool(invalid_rush.get("ok", true))
	ok = ok and str(invalid_rush.get("error", "")).begins_with("ATTACK_COMBINATION_INVALID")
	ok = ok and not bool(missing_result.get("ok", true)) and str(missing_result.get("error", "")) == "ATTACK_AXIS_MISSING:recovery"
	ok = ok and not bool(identity_result.get("player_confirmation_required", true))
	_check(ok, "08 identity fields missing axes and unsafe delivery-lock combinations fail closed without player questions")


func _test_selector_chooses_by_range_and_depth_context() -> void:
	var close_attack: Dictionary = COMPILER.compile(_declaration(
		{"delivery": "contact", "target_lock": "direction_on_commit", "hit_shape": "capsule"},
		{"preferred_range": "close", "depth_fit": "aligned", "base_priority": 30, "selection_rank": 1},
		"slot_close"
	))
	var far_attack: Dictionary = COMPILER.compile(_declaration(
		{"delivery": "projectile", "target_lock": "direction_on_commit", "hit_shape": "capsule"},
		{"preferred_range": "far", "depth_fit": "tolerant", "base_priority": 30, "selection_rank": 2},
		"slot_far"
	))
	var close_choice: Dictionary = SELECTOR.select_attack([far_attack, close_attack], _context(70.0, 8.0, 3, true))
	var far_choice: Dictionary = SELECTOR.select_attack([close_attack, far_attack], _context(430.0, 60.0, 3, true))
	var no_depth_choice: Dictionary = SELECTOR.select_attack([close_attack], _context(70.0, 50.0, 3, true))
	var ok := str(close_choice.get("attack_key", "")) == "slot_close"
	ok = ok and str(far_choice.get("attack_key", "")) == "slot_far"
	ok = ok and not bool(no_depth_choice.get("ok", true)) and str(no_depth_choice.get("error", "")) == "NO_ELIGIBLE_ATTACK"
	_check(ok, "09 selector uses compiled range and depth fit instead of enemy identity")


func _test_selector_filters_path_budget_and_cooldown() -> void:
	var expensive: Dictionary = COMPILER.compile(_declaration(
		{"delivery": "projectile", "target_lock": "direction_on_commit", "hit_shape": "capsule"},
		{
			"preferred_range": "far",
			"depth_fit": "any",
			"base_priority": 100,
			"coordination_cost": 3,
			"requires_clear_path": true,
			"selection_rank": 0,
		},
		"slot_expensive"
	))
	var fallback: Dictionary = COMPILER.compile(_declaration(
		{"delivery": "contact", "target_lock": "direction_on_commit", "hit_shape": "capsule"},
		{"preferred_range": "any", "depth_fit": "any", "base_priority": 10, "selection_rank": 5},
		"slot_fallback"
	))
	var blocked_context := _context(300.0, 0.0, 1, false)
	var fallback_choice: Dictionary = SELECTOR.select_attack([expensive, fallback], blocked_context)
	var cooldown_context := blocked_context.duplicate(true)
	cooldown_context["cooldown_remaining_by_key"] = {"slot_fallback": 0.4}
	var no_choice: Dictionary = SELECTOR.select_attack([expensive, fallback], cooldown_context)
	var reasons := _rejection_reasons(no_choice.get("rejected", []) as Array)
	var ok := str(fallback_choice.get("attack_key", "")) == "slot_fallback"
	ok = ok and not bool(no_choice.get("ok", true))
	ok = ok and reasons.has("COORDINATION_BUDGET") and reasons.has("COOLDOWN_ACTIVE")
	_check(ok, "10 selector enforces clear path coordination budget and per-slot cooldown eligibility")


func _test_selector_repeat_penalty_and_rank_are_deterministic() -> void:
	var first: Dictionary = COMPILER.compile(_declaration(
		{"delivery": "contact", "target_lock": "direction_on_commit", "hit_shape": "capsule"},
		{"preferred_range": "any", "depth_fit": "any", "base_priority": 50, "selection_rank": 1},
		"slot_first"
	))
	var second: Dictionary = COMPILER.compile(_declaration(
		{"delivery": "contact", "target_lock": "live_until_active", "hit_shape": "arc"},
		{"preferred_range": "any", "depth_fit": "any", "base_priority": 50, "selection_rank": 2},
		"slot_second"
	))
	var context := _context(180.0, 0.0, 3, true)
	var ranked_choice: Dictionary = SELECTOR.select_attack([second, first], context)
	context["previous_mechanism_signature"] = str(first.get("mechanism_signature", ""))
	var varied_choice: Dictionary = SELECTOR.select_attack([first, second], context)
	var ok := str(ranked_choice.get("attack_key", "")) == "slot_first"
	ok = ok and str(varied_choice.get("attack_key", "")) == "slot_second"
	ok = ok and float((varied_choice.get("score_breakdown", {}) as Dictionary).get("repeat_penalty", -1.0)) == 0.0
	_check(ok, "11 deterministic rank breaks equal scores and mechanism-signature repeat penalty promotes variation")


func _test_mechanism_sources_have_no_enemy_identity_branches() -> void:
	var source := "\n".join([
		FileAccess.get_file_as_string("res://scripts/enemy_attack/enemy_attack_mechanism_compiler.gd"),
		FileAccess.get_file_as_string("res://scripts/enemy_attack/enemy_attack_selector.gd"),
	]).to_lower()
	var ok := true
	for forbidden: String in ["enemy_kind", "slag_puppet", "forge_ram", "match enemy", "if enemy"]:
		ok = ok and not source.contains(forbidden)
	_check(ok, "12 compiler and selector contain no enemy-name or enemy-kind dispatch")


func _declaration(
	axis_overrides: Dictionary = {},
	selection_overrides: Dictionary = {},
	attack_key: String = "slot_0"
) -> Dictionary:
	var axes := {
		"delivery": "contact",
		"target_lock": "live_until_active",
		"hit_shape": "arc",
		"depth_path": "same_lane",
		"tempo": "standard",
		"stability": "tell_interruptible",
		"recovery": "punishable",
	}
	for axis: String in axis_overrides:
		axes[axis] = axis_overrides[axis]
	var selection := {
		"preferred_range": "close",
		"depth_fit": "aligned",
		"base_priority": 50,
		"coordination_cost": 1,
		"requires_clear_path": false,
		"selection_rank": 10,
	}
	for field: String in selection_overrides:
		selection[field] = selection_overrides[field]
	return {
		"attack_key": attack_key,
		"axes": axes,
		"selection": selection,
	}


func _context(distance: float, depth_delta: float, budget: int, clear_path: bool) -> Dictionary:
	return {
		"distance_pixels": distance,
		"depth_delta_pixels": depth_delta,
		"available_coordination_budget": budget,
		"clear_path": clear_path,
		"cooldown_remaining_by_key": {},
	}


func _rejection_reasons(rejected: Array) -> Array[String]:
	var reasons: Array[String] = []
	for raw_entry: Variant in rejected:
		if raw_entry is Dictionary:
			reasons.append(str((raw_entry as Dictionary).get("reason", "")))
	return reasons


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		push_error("FAIL " + label)
