extends SceneTree

const AFFORDANCE := preload("res://scripts/combat_feel/object_affordance_profile.gd")
const COMPILER := preload("res://scripts/combat_feel/melee_motion_compiler.gd")
const CONTROLLER := preload("res://scripts/combat_feel/melee_combat_controller.gd")
const SLICE := preload("res://scripts/combat_feel/combat_feel_slice_0.gd")
const FEEDBACK := preload("res://scripts/combat_feel/impact_feedback_profile.gd")
const VISUAL_ASSET := preload("res://scripts/data/weapon_visual_asset.gd")

const ANCHORS := {
	"GripPrimary": [24.0, 48.0],
	"GripSecondary": [38.0, 48.0],
	"StrikePoint": [78.0, 48.0],
	"Muzzle": [82.0, 48.0],
	"rear_contact": [10.0, 48.0],
}
const ALPHA_BOUNDS := Rect2i(8, 28, 80, 40)
const ACTIVE_PHASE_RATIOS: Array[float] = [0.0, 0.20, 0.40, 0.60, 0.80, 1.0]
const GRID_STEP := 8
const GRID_X_MIN := -192
const GRID_X_MAX := 264
const GRID_Y_MIN := -192
const GRID_Y_MAX := 192


func _init() -> void:
	call_deferred("_export")


func _export() -> void:
	var arguments := _arguments()
	var output_path := str(arguments.get("output", ""))
	var profiles_directory := str(arguments.get("profiles-dir", ""))
	var case_order_path := str(arguments.get("case-order", ""))
	if output_path.is_empty() or profiles_directory.is_empty() or case_order_path.is_empty():
		_fail("AFFORDANCE_RUNTIME_REALIZATION_ARGUMENT_INVALID")
		return
	var baseline_payload := _baseline_payload()
	var baseline_result := _compile_and_measure(baseline_payload)
	if not bool(baseline_result.get("ok", false)):
		_fail("AFFORDANCE_RUNTIME_REALIZATION_BASELINE_FAILED")
		return
	var scenarios: Array[Dictionary] = []
	for scenario: Dictionary in _scenarios():
		var payload: Dictionary = baseline_payload.duplicate(true)
		var changes: Dictionary = scenario["changes"]
		for field: String in changes:
			payload[field] = changes[field]
		var measured := _compile_and_measure(payload)
		if not bool(measured.get("ok", false)):
			_fail("AFFORDANCE_RUNTIME_REALIZATION_SCENARIO_FAILED:%s" % str(scenario["id"]))
			return
		measured["id"] = scenario["id"]
		measured["axis"] = scenario["axis"]
		measured["changes"] = changes.duplicate(true)
		measured["expected"] = scenario["expected"]
		scenarios.append(measured)
	var frozen_cases := _load_and_measure_frozen_cases(profiles_directory, case_order_path)
	if frozen_cases.is_empty():
		_fail("AFFORDANCE_RUNTIME_REALIZATION_FROZEN_CASES_FAILED")
		return
	var output := {
		"schema": "forge-affordance-runtime-realization-raw-v1",
		"compiler": "MeleeMotionCompiler",
		"collision_consumer": "CombatFeelSlice0._attack_contains",
		"timing_consumer": "CombatMotionProfile.timing_for",
		"feedback_consumer": "ImpactFeedbackProfile.for_attack",
		"pose_consumer": "CombatFeelSlice0._character_pose",
		"identity_inputs_used": false,
		"runtime_weights_modified": false,
		"anchors": ANCHORS.duplicate(true),
		"alpha_bounds": [ALPHA_BOUNDS.position.x, ALPHA_BOUNDS.position.y, ALPHA_BOUNDS.size.x, ALPHA_BOUNDS.size.y],
		"sampling": {
			"grid_step": GRID_STEP,
			"grid_bounds": [GRID_X_MIN, GRID_Y_MIN, GRID_X_MAX, GRID_Y_MAX],
			"active_phase_ratios": ACTIVE_PHASE_RATIOS,
			"formation_targets": _formation_targets_json(),
		},
		"baseline": baseline_result,
		"scenarios": scenarios,
		"frozen_cases": frozen_cases,
	}
	var temporary := "%s.%s.tmp" % [output_path, str(Time.get_ticks_usec())]
	var stream := FileAccess.open(temporary, FileAccess.WRITE)
	if stream == null:
		_fail("AFFORDANCE_RUNTIME_REALIZATION_WRITE_FAILED")
		return
	stream.store_string(JSON.stringify(output, "  ") + "\n")
	stream.flush()
	stream.close()
	if DirAccess.rename_absolute(temporary, output_path) != OK:
		_fail("AFFORDANCE_RUNTIME_REALIZATION_ATOMIC_RENAME_FAILED")
		return
	print("AFFORDANCE_RUNTIME_REALIZATION_EXPORT=PASS scenarios=%d frozen_cases=%d" % [scenarios.size(), frozen_cases.size()])
	quit(0)


func _arguments() -> Dictionary:
	var result := {}
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--") or not argument.contains("="):
			continue
		var separator := argument.find("=")
		result[argument.substr(2, separator - 2)] = argument.substr(separator + 1)
	return result


func _baseline_payload() -> Dictionary:
	return {
		"handle_length": "medium",
		"body_length": "medium",
		"grip_topology": "one_hand_handle",
		"rigidity": "rigid",
		"mass_distribution": "balanced",
		"contact_surface": "broad",
		"secondary_contact_surface": "none",
		"has_point": false,
		"has_edge": false,
		"has_broad_face": false,
		"has_barrel": false,
		"has_stock": false,
		"confidence": 0.80,
		"evidence_parts": ["anonymous structural baseline"],
	}


func _scenarios() -> Array[Dictionary]:
	return [
		{"id": "handle_short", "axis": "handle_length", "changes": {"handle_length": "short"}, "expected": "runtime_effect"},
		{"id": "handle_long", "axis": "handle_length", "changes": {"handle_length": "long"}, "expected": "runtime_effect"},
		{"id": "body_short", "axis": "body_length", "changes": {"body_length": "short"}, "expected": "runtime_effect"},
		{"id": "body_long", "axis": "body_length", "changes": {"body_length": "long"}, "expected": "runtime_effect"},
		{"id": "grip_two_hand", "axis": "grip_topology", "changes": {"grip_topology": "two_hand_handle"}, "expected": "runtime_effect"},
		{"id": "grip_clamp", "axis": "grip_topology", "changes": {"grip_topology": "clamp_grip"}, "expected": "runtime_effect"},
		{"id": "grip_handleless_body", "axis": "grip_mode", "changes": {"handle_length": "none", "grip_topology": "body_grip"}, "expected": "runtime_effect"},
		{"id": "rigidity_semi", "axis": "rigidity", "changes": {"rigidity": "semi_rigid"}, "expected": "runtime_effect"},
		{"id": "rigidity_flexible", "axis": "rigidity", "changes": {"rigidity": "flexible"}, "expected": "runtime_effect"},
		{"id": "mass_rear", "axis": "mass_distribution", "changes": {"mass_distribution": "rear"}, "expected": "runtime_effect"},
		{"id": "mass_front", "axis": "mass_distribution", "changes": {"mass_distribution": "front"}, "expected": "runtime_effect"},
		{"id": "primary_point", "axis": "contact_surface", "changes": {"contact_surface": "point"}, "expected": "runtime_effect"},
		{"id": "primary_edge", "axis": "contact_surface", "changes": {"contact_surface": "edge"}, "expected": "runtime_effect"},
		{"id": "primary_whole_body", "axis": "contact_surface", "changes": {"contact_surface": "whole_body"}, "expected": "runtime_effect"},
		{"id": "secondary_point", "axis": "secondary_contact_surface", "changes": {"secondary_contact_surface": "point"}, "expected": "runtime_effect"},
		{"id": "secondary_edge", "axis": "secondary_contact_surface", "changes": {"secondary_contact_surface": "edge"}, "expected": "runtime_effect"},
		{"id": "secondary_broad", "axis": "secondary_contact_surface", "changes": {"secondary_contact_surface": "broad"}, "expected": "runtime_effect"},
		{"id": "secondary_whole_body", "axis": "secondary_contact_surface", "changes": {"secondary_contact_surface": "whole_body"}, "expected": "runtime_effect"},
		{"id": "feature_point", "axis": "has_point", "changes": {"has_point": true}, "expected": "runtime_effect"},
		{"id": "feature_edge", "axis": "has_edge", "changes": {"has_edge": true}, "expected": "runtime_effect"},
		{"id": "feature_broad_face", "axis": "has_broad_face", "changes": {"has_broad_face": true}, "expected": "runtime_effect"},
		{"id": "feature_barrel", "axis": "has_barrel", "changes": {"has_barrel": true}, "expected": "runtime_effect"},
		{"id": "feature_stock", "axis": "has_stock", "changes": {"has_stock": true}, "expected": "runtime_effect"},
		{"id": "confidence_high", "axis": "confidence", "changes": {"confidence": 0.95}, "expected": "invariant"},
		{"id": "evidence_changed", "axis": "evidence_parts", "changes": {"evidence_parts": ["different anonymous evidence wording"]}, "expected": "invariant"},
	]


func _compile_and_measure(payload: Dictionary) -> Dictionary:
	var affordance: Resource = _affordance_from_dict(payload)
	if affordance == null:
		return {"ok": false, "errors": ["AFFORDANCE_INVALID"]}
	var profile: Variant = COMPILER.new().compile(affordance, ANCHORS, ALPHA_BOUNDS)
	if not profile is Resource or profile.combo_recipe == null:
		return {"ok": false, "errors": [str(profile)]}
	return {
		"ok": true,
		"affordance": affordance.to_dict(),
		"profile": profile.to_dict(),
		"runtime": _measure_profile(profile),
	}


func _affordance_from_dict(payload: Dictionary) -> Resource:
	var affordance: Resource = AFFORDANCE.new()
	for field: String in [
		"handle_length", "body_length", "grip_topology", "rigidity",
		"mass_distribution", "contact_surface", "secondary_contact_surface",
		"has_point", "has_edge", "has_broad_face", "has_barrel", "has_stock",
		"confidence",
	]:
		if not payload.has(field):
			return null
		affordance.set(field, payload[field])
	var evidence_value: Variant = payload.get("evidence_parts", [])
	if not evidence_value is Array:
		return null
	for evidence: Variant in evidence_value:
		affordance.evidence_parts.append(str(evidence))
	return null if not affordance.validation_errors().is_empty() else affordance


func _measure_profile(profile: Resource) -> Dictionary:
	var hit_records: Array[Dictionary] = []
	var combo_cells := {}
	var combo_formation := {}
	for combo_index: int in range(1, 4):
		var primitive: Variant = profile.combo_recipe.primitive_for(combo_index)
		var hit := _measure_hit(profile, primitive, combo_index)
		for key: Variant in hit["_cells"]:
			combo_cells[key] = true
		for slot: Variant in hit["_formation_slots"]:
			combo_formation[slot] = true
		hit.erase("_cells")
		hit.erase("_formation_slots")
		hit_records.append(hit)
	var bounds := _cell_bounds(combo_cells)
	var startup_total := 0.0
	var active_total := 0.0
	var recovery_total := 0.0
	var root_motion_total := 0.0
	var hitstop_total := 0.0
	var knockback_total := 0.0
	var stagger_total := 0.0
	var camera_total := 0.0
	var movement_allowed_total := 0.0
	var sequence: Array[String] = []
	for hit: Dictionary in hit_records:
		sequence.append(str(hit["primitive"]))
		startup_total += float(hit["timing"]["startup"])
		active_total += float(hit["timing"]["active"])
		recovery_total += float(hit["timing"]["recovery"])
		root_motion_total += float(hit["root_motion_distance"])
		hitstop_total += float(hit["feedback"]["hitstop_seconds"])
		knockback_total += float(hit["feedback"]["knockback_strength"])
		stagger_total += float(hit["feedback"]["stagger_strength"])
		camera_total += float(hit["feedback"]["camera_shake_strength"])
		movement_allowed_total += float(hit["movement_allowed_ratio"])
	return {
		"primitive_sequence": sequence,
		"grip_mode": profile.grip_mode,
		"two_hand_support_drawn": profile.grip_mode == "two_hand",
		"hits": hit_records,
		"combo": {
			"collision_cell_count": combo_cells.size(),
			"collision_area": float(combo_cells.size() * GRID_STEP * GRID_STEP),
			"forward_extent": bounds["max_x"],
			"rear_extent": bounds["min_x"],
			"vertical_span": bounds["max_y"] - bounds["min_y"] + GRID_STEP,
			"formation_hit_count": combo_formation.size(),
			"root_motion_total": root_motion_total,
			"startup_total": startup_total,
			"active_total": active_total,
			"recovery_total": recovery_total,
			"hitstop_total": hitstop_total,
			"knockback_total": knockback_total,
			"stagger_total": stagger_total,
			"camera_shake_total": camera_total,
			"movement_allowed_average": movement_allowed_total / 3.0,
		},
	}


func _measure_hit(profile: Resource, primitive: Resource, combo_index: int) -> Dictionary:
	var probe: Node2D = SLICE.new()
	probe.asset = _neutral_asset()
	probe.motion_profile = profile
	probe.controller = CONTROLLER.new()
	probe.controller.configure(profile)
	probe.controller.attack_kind = "normal"
	probe.controller.combo_index = combo_index
	probe.controller.current_primitive = primitive
	probe.controller.phase = "active"
	probe.controller.phase_duration = 1.0
	probe.player_facing = 1.0
	probe.player_position = Vector2(float(primitive.root_motion_distance), 0.0)
	var cells := {}
	var formation_slots := {}
	var formation := _formation_targets()
	for phase_ratio: float in ACTIVE_PHASE_RATIOS:
		probe.controller.phase_elapsed = phase_ratio
		for y: int in range(GRID_Y_MIN, GRID_Y_MAX + 1, GRID_STEP):
			for x: int in range(GRID_X_MIN, GRID_X_MAX + 1, GRID_STEP):
				if probe._attack_contains(Vector2(x, y)):
					cells[Vector2i(x, y)] = true
		for slot: int in range(formation.size()):
			if probe._attack_contains(formation[slot]):
				formation_slots[slot] = true
	probe.controller.phase_elapsed = 0.50
	var pose: Dictionary = probe._character_pose()
	var contact: Vector2 = probe._primitive_contact_world(primitive, probe._hand_world_position())
	var bounds := _cell_bounds(cells)
	var refined_forward_extent := _refined_forward_extent(probe, float(bounds["max_x"]))
	var timing: Dictionary = profile.timing_for("normal", combo_index, primitive)
	var feedback: Resource = FEEDBACK.for_attack(profile, "normal", combo_index, primitive)
	var result := {
		"combo_index": combo_index,
		"primitive": primitive.motion_family,
		"contact_anchor": primitive.contact_anchor,
		"collision_cell_count": cells.size(),
		"collision_area": float(cells.size() * GRID_STEP * GRID_STEP),
		"forward_extent": refined_forward_extent,
		"rear_extent": bounds["min_x"],
		"vertical_span": bounds["max_y"] - bounds["min_y"] + GRID_STEP,
		"formation_hit_count": formation_slots.size(),
		"root_motion_distance": primitive.root_motion_distance,
		"movement_allowed_ratio": primitive.movement_allowed_ratio,
		"contact_midpoint": [contact.x, contact.y],
		"timing": {
			"startup": timing["startup"],
			"active": timing["active"],
			"recovery": timing["recovery"],
		},
		"feedback": {
			"hitstop_seconds": feedback.hitstop_seconds,
			"knockback_strength": feedback.knockback_strength,
			"stagger_strength": feedback.stagger_strength,
			"camera_shake_strength": feedback.camera_shake_strength,
		},
		"pose": {
			"body_offset_x": float(Vector2(pose["body_offset"]).x),
			"body_offset_y": float(Vector2(pose["body_offset"]).y),
			"hand_local_x": float(Vector2(pose["hand_local"]).x),
			"hand_local_y": float(Vector2(pose["hand_local"]).y),
			"torso_rotation": float(pose["torso_rotation"]),
			"crouch": float(pose["crouch"]),
		},
		"_cells": cells,
		"_formation_slots": formation_slots,
	}
	probe.free()
	return result


func _refined_forward_extent(probe: Node2D, coarse_max_x: float) -> float:
	var best := coarse_max_x
	var start_x := floori(coarse_max_x) - GRID_STEP
	var end_x := ceili(coarse_max_x) + GRID_STEP * 2
	for phase_ratio: float in ACTIVE_PHASE_RATIOS:
		probe.controller.phase_elapsed = phase_ratio
		for y: int in range(GRID_Y_MIN, GRID_Y_MAX + 1, 4):
			for x: int in range(start_x, end_x + 1):
				if probe._attack_contains(Vector2(x, y)):
					best = maxf(best, float(x))
	return best


func _cell_bounds(cells: Dictionary) -> Dictionary:
	if cells.is_empty():
		return {"min_x": 0.0, "max_x": 0.0, "min_y": 0.0, "max_y": 0.0}
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for key: Variant in cells:
		var point: Vector2i = key
		min_x = minf(min_x, float(point.x))
		max_x = maxf(max_x, float(point.x))
		min_y = minf(min_y, float(point.y))
		max_y = maxf(max_y, float(point.y))
	return {"min_x": min_x, "max_x": max_x, "min_y": min_y, "max_y": max_y}


func _neutral_asset() -> RefCounted:
	var asset: RefCounted = VISUAL_ASSET.new()
	asset.canvas_size = Vector2i(96, 96)
	asset.opaque_bounds = ALPHA_BOUNDS
	asset.grip_primary = Vector2(24.0, 48.0)
	asset.grip_secondary = Vector2(38.0, 48.0)
	asset.tip = Vector2(78.0, 48.0)
	asset.muzzle = Vector2(82.0, 48.0)
	asset.spin_pivot = Vector2(48.0, 48.0)
	# Deliberately omit an explicit rear contact so a stock probe must exercise
	# the same generic bounds/axis fallback used by a newly generated asset.
	asset.rear_contact = asset.grip_primary
	return asset


func _formation_targets() -> Array[Vector2]:
	var targets: Array[Vector2] = []
	for x: float in [48.0, 88.0, 128.0, 168.0]:
		for y: float in [-56.0, -28.0, 0.0, 28.0, 56.0]:
			targets.append(Vector2(x, y))
	return targets


func _formation_targets_json() -> Array[Array]:
	var result: Array[Array] = []
	for target: Vector2 in _formation_targets():
		result.append([target.x, target.y])
	return result


func _load_and_measure_frozen_cases(profiles_directory: String, case_order_path: String) -> Array[Dictionary]:
	var order_value: Variant = _read_json(case_order_path)
	if not order_value is Array or order_value.size() != 12:
		return []
	var results: Array[Dictionary] = []
	for case_value: Variant in order_value:
		var case_id := str(case_value)
		var profile_path := profiles_directory.path_join("%s.json" % case_id)
		var payload_value: Variant = _read_json(profile_path)
		if not payload_value is Dictionary:
			return []
		var measured := _compile_and_measure(payload_value)
		if not bool(measured.get("ok", false)):
			return []
		measured["case_id"] = case_id
		results.append(measured)
	return results


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var stream := FileAccess.open(path, FileAccess.READ)
	if stream == null:
		return null
	var value: Variant = JSON.parse_string(stream.get_as_text())
	stream.close()
	return value


func _fail(code: String) -> void:
	push_error(code)
	quit(1)
