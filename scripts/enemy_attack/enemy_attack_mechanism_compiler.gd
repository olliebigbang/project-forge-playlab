class_name EnemyAttackMechanismCompiler
extends RefCounted

const RUNTIME_SCHEMA := "forge-enemy-attack-mechanism-v1"
const STATE_SEQUENCE: PackedStringArray = ["telegraph", "commit", "active", "recovery"]

const REQUIRED_AXES: PackedStringArray = [
	"delivery",
	"target_lock",
	"hit_shape",
	"depth_path",
	"tempo",
	"stability",
	"recovery",
]
const LEGAL_AXIS_VALUES := {
	"delivery": ["contact", "rush", "projectile", "marked_impact"],
	"target_lock": ["live_until_active", "direction_on_commit", "point_on_commit"],
	"hit_shape": ["capsule", "arc", "circle", "strip"],
	"depth_path": ["same_lane", "cross_depth", "depth_band"],
	"tempo": ["quick", "standard", "committed"],
	"stability": ["fragile", "tell_interruptible", "armored_commit"],
	"recovery": ["brief", "punishable", "extended"],
}

const REQUIRED_SELECTION_FIELDS: PackedStringArray = [
	"preferred_range",
	"depth_fit",
	"base_priority",
	"coordination_cost",
	"requires_clear_path",
	"selection_rank",
]
const LEGAL_SELECTION_VALUES := {
	"preferred_range": ["close", "mid", "far", "any"],
	"depth_fit": ["aligned", "tolerant", "any"],
}

const ALLOWED_TOP_LEVEL_FIELDS: PackedStringArray = ["attack_key", "axes", "selection"]
const ALLOWED_SELECTION_FIELDS: PackedStringArray = [
	"preferred_range",
	"depth_fit",
	"base_priority",
	"coordination_cost",
	"requires_clear_path",
	"selection_rank",
]

# Runtime values have declared data owners. Enemy identity and attack_key are
# deliberately absent: the opaque key is only used to address cooldown state.
const PARAMETER_OWNERS := {
	"timeline.telegraph_seconds": "tempo",
	"timeline.commit_seconds": "tempo",
	"timeline.active_seconds": "delivery",
	"attack_motion": "delivery",
	"telegraph.lock_event": "target_lock",
	"telegraph.tracks_target_during": "target_lock",
	"hit_region.shape": "hit_shape",
	"hit_region.length_pixels": "hit_shape",
	"hit_region.width_pixels": "hit_shape",
	"hit_region.radius_pixels": "hit_shape",
	"hit_region.arc_degrees": "hit_shape",
	"hit_region.path_mode": "depth_path",
	"hit_region.depth_tolerance_pixels": "depth_path",
	"interruptibility": "stability",
	"recovery": "recovery",
	"selection.preferred_range": "selection.preferred_range",
	"selection.depth_fit": "selection.depth_fit",
	"selection.base_priority": "selection.base_priority",
	"selection.coordination_cost": "selection.coordination_cost",
	"selection.requires_clear_path": "selection.requires_clear_path",
	"selection.selection_rank": "selection.selection_rank",
}


static func validate(declaration: Dictionary) -> Dictionary:
	if declaration.is_empty():
		return _failure("ENEMY_ATTACK_DECLARATION_MISSING")

	var errors: Array[String] = []
	for raw_key: Variant in declaration.keys():
		var key := str(raw_key)
		if key not in ALLOWED_TOP_LEVEL_FIELDS:
			errors.append("UNSUPPORTED_FIELD:%s" % key)

	var attack_key := str(declaration.get("attack_key", "")).strip_edges()
	if attack_key.is_empty():
		errors.append("ATTACK_KEY_MISSING")

	var axes_value: Variant = declaration.get("axes", null)
	if not axes_value is Dictionary:
		errors.append("ATTACK_AXES_MISSING")
	else:
		var axes := axes_value as Dictionary
		for raw_key: Variant in axes.keys():
			var key := str(raw_key)
			if key not in REQUIRED_AXES:
				errors.append("UNSUPPORTED_AXIS:%s" % key)
		for axis: String in REQUIRED_AXES:
			if not axes.has(axis):
				errors.append("ATTACK_AXIS_MISSING:%s" % axis)
				continue
			var value := str(axes.get(axis, ""))
			if value not in (LEGAL_AXIS_VALUES.get(axis, []) as Array):
				errors.append("ATTACK_AXIS_INVALID:%s:%s" % [axis, value])
		if errors.is_empty():
			errors.append_array(_combination_errors(axes))

	var selection_value: Variant = declaration.get("selection", null)
	if not selection_value is Dictionary:
		errors.append("ATTACK_SELECTION_MISSING")
	else:
		var selection := selection_value as Dictionary
		for raw_key: Variant in selection.keys():
			var key := str(raw_key)
			if key not in ALLOWED_SELECTION_FIELDS:
				errors.append("UNSUPPORTED_SELECTION_FIELD:%s" % key)
		for field: String in REQUIRED_SELECTION_FIELDS:
			if not selection.has(field):
				errors.append("ATTACK_SELECTION_FIELD_MISSING:%s" % field)
		if selection.has("preferred_range") and str(selection["preferred_range"]) not in LEGAL_SELECTION_VALUES["preferred_range"]:
			errors.append("ATTACK_SELECTION_INVALID:preferred_range")
		if selection.has("depth_fit") and str(selection["depth_fit"]) not in LEGAL_SELECTION_VALUES["depth_fit"]:
			errors.append("ATTACK_SELECTION_INVALID:depth_fit")
		if selection.has("base_priority"):
			if typeof(selection["base_priority"]) != TYPE_INT or int(selection["base_priority"]) < 0 or int(selection["base_priority"]) > 100:
				errors.append("ATTACK_SELECTION_INVALID:base_priority")
		if selection.has("coordination_cost"):
			if typeof(selection["coordination_cost"]) != TYPE_INT or int(selection["coordination_cost"]) < 1 or int(selection["coordination_cost"]) > 3:
				errors.append("ATTACK_SELECTION_INVALID:coordination_cost")
		if selection.has("requires_clear_path") and typeof(selection["requires_clear_path"]) != TYPE_BOOL:
			errors.append("ATTACK_SELECTION_INVALID:requires_clear_path")
		if selection.has("selection_rank"):
			if typeof(selection["selection_rank"]) != TYPE_INT or int(selection["selection_rank"]) < 0 or int(selection["selection_rank"]) > 999:
				errors.append("ATTACK_SELECTION_INVALID:selection_rank")

	if not errors.is_empty():
		return _failure(errors[0], errors)
	return {
		"ok": true,
		"complete": true,
		"player_confirmation_required": false,
		"identity_inputs_used": false,
	}


static func compile(declaration: Dictionary) -> Dictionary:
	var validation := validate(declaration)
	if not bool(validation.get("ok", false)):
		return validation

	var axes := _axis_snapshot(declaration["axes"] as Dictionary)
	var delivery := _delivery_profile(str(axes["delivery"]))
	var target_lock := _target_lock_profile(str(axes["target_lock"]))
	var hit_shape := _hit_shape_profile(str(axes["hit_shape"]))
	var depth_path := _depth_path_profile(str(axes["depth_path"]))
	var tempo := _tempo_profile(str(axes["tempo"]))
	var interruptibility := _stability_profile(str(axes["stability"]))
	var recovery := _recovery_profile(str(axes["recovery"]))

	var hit_region := {
		"shape": str(hit_shape["shape"]),
		"length_pixels": float(hit_shape["length_pixels"]),
		"width_pixels": float(hit_shape["width_pixels"]),
		"radius_pixels": float(hit_shape["radius_pixels"]),
		"arc_degrees": float(hit_shape["arc_degrees"]),
		"path_mode": str(depth_path["path_mode"]),
		"depth_tolerance_pixels": float(depth_path["depth_tolerance_pixels"]),
		"origin_mode": str(delivery["origin_mode"]),
		"sweep_mode": str(delivery["sweep_mode"]),
	}
	var geometry_signature := JSON.stringify(hit_region).sha256_text().left(16)
	hit_region["geometry_signature"] = geometry_signature

	var telegraph := {
		"duration_seconds": float(tempo["telegraph_seconds"]),
		"cue_family": str(delivery["cue_family"]),
		"lock_event": str(target_lock["lock_event"]),
		"aim_reference": str(target_lock["aim_reference"]),
		"tracks_target_during": (target_lock["tracks_target_during"] as Array).duplicate(),
		"preview_region": hit_region.duplicate(true),
		"preview_geometry_signature": geometry_signature,
	}
	var timeline := {
		"state_sequence": Array(STATE_SEQUENCE),
		"telegraph_seconds": float(tempo["telegraph_seconds"]),
		"commit_seconds": float(tempo["commit_seconds"]),
		"active_seconds": float(delivery["active_seconds"]),
		"recovery_seconds": float(recovery["duration_seconds"]),
	}
	var attack_motion := {
		"origin_mode": str(delivery["origin_mode"]),
		"sweep_mode": str(delivery["sweep_mode"]),
		"travel_speed_pixels_per_second": float(delivery["travel_speed_pixels_per_second"]),
		"hazard_lifetime_seconds": float(delivery["hazard_lifetime_seconds"]),
		"direction_changes_after_lock": false,
	}
	var selection := _compile_selection(declaration["selection"] as Dictionary)
	var mechanism_signature_source := {
		"schema": RUNTIME_SCHEMA,
		"axes": axes,
		"timeline": timeline,
		"telegraph": {
			"lock_event": telegraph["lock_event"],
			"aim_reference": telegraph["aim_reference"],
		},
		"hit_region": hit_region,
		"interruptibility": interruptibility,
		"recovery": recovery,
	}

	return {
		"ok": true,
		"schema": RUNTIME_SCHEMA,
		"attack_key": str(declaration["attack_key"]),
		"axes": axes,
		"axis_signature": JSON.stringify(axes).sha256_text().left(16),
		"mechanism_signature": JSON.stringify(mechanism_signature_source).sha256_text().left(16),
		"timeline": timeline,
		"telegraph": telegraph,
		"hit_region": hit_region,
		"attack_motion": attack_motion,
		"interruptibility": interruptibility,
		"recovery": recovery,
		"selection": selection,
		"parameter_owners": PARAMETER_OWNERS.duplicate(true),
		"identity_inputs_used": false,
		"player_confirmation_required": false,
	}


static func _combination_errors(axes: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var delivery := str(axes.get("delivery", ""))
	var target_lock := str(axes.get("target_lock", ""))
	var hit_shape := str(axes.get("hit_shape", ""))
	var legal_shapes := {
		"contact": ["capsule", "arc", "circle"],
		"rush": ["capsule", "strip"],
		"projectile": ["capsule"],
		"marked_impact": ["circle", "strip"],
	}
	if hit_shape not in (legal_shapes.get(delivery, []) as Array):
		errors.append("ATTACK_COMBINATION_INVALID:%s:%s" % [delivery, hit_shape])
	if delivery == "rush" and target_lock != "direction_on_commit":
		errors.append("ATTACK_COMBINATION_INVALID:rush_requires_direction_lock")
	if delivery == "marked_impact" and target_lock != "point_on_commit":
		errors.append("ATTACK_COMBINATION_INVALID:marked_impact_requires_point_lock")
	if delivery == "projectile" and target_lock == "point_on_commit":
		errors.append("ATTACK_COMBINATION_INVALID:projectile_cannot_use_point_lock")
	if target_lock == "live_until_active" and delivery not in ["contact", "projectile"]:
		errors.append("ATTACK_COMBINATION_INVALID:live_tracking_delivery")
	return errors


static func _axis_snapshot(raw_axes: Dictionary) -> Dictionary:
	var axes := {}
	for axis: String in REQUIRED_AXES:
		axes[axis] = str(raw_axes[axis])
	return axes


static func _delivery_profile(value: String) -> Dictionary:
	match value:
		"rush":
			return {
				"origin_mode": "attacker",
				"sweep_mode": "locked_translation",
				"cue_family": "path_lane",
				"active_seconds": 0.54,
				"travel_speed_pixels_per_second": 340.0,
				"hazard_lifetime_seconds": 0.54,
			}
		"projectile":
			return {
				"origin_mode": "detached",
				"sweep_mode": "ballistic_translation",
				"cue_family": "launch_lane",
				"active_seconds": 0.10,
				"travel_speed_pixels_per_second": 540.0,
				"hazard_lifetime_seconds": 1.35,
			}
		"marked_impact":
			return {
				"origin_mode": "locked_point",
				"sweep_mode": "stationary_impact",
				"cue_family": "ground_marker",
				"active_seconds": 0.16,
				"travel_speed_pixels_per_second": 0.0,
				"hazard_lifetime_seconds": 0.16,
			}
		_:
			return {
				"origin_mode": "attacker",
				"sweep_mode": "attached_sweep",
				"cue_family": "body_pose",
				"active_seconds": 0.20,
				"travel_speed_pixels_per_second": 0.0,
				"hazard_lifetime_seconds": 0.20,
			}


static func _target_lock_profile(value: String) -> Dictionary:
	match value:
		"direction_on_commit":
			return {
				"lock_event": "commit_start",
				"aim_reference": "direction",
				"tracks_target_during": ["telegraph"],
			}
		"point_on_commit":
			return {
				"lock_event": "commit_start",
				"aim_reference": "world_point",
				"tracks_target_during": ["telegraph"],
			}
		_:
			return {
				"lock_event": "active_start",
				"aim_reference": "target_position",
				"tracks_target_during": ["telegraph", "commit"],
			}


static func _hit_shape_profile(value: String) -> Dictionary:
	match value:
		"arc":
			return {
				"shape": "arc",
				"length_pixels": 94.0,
				"width_pixels": 30.0,
				"radius_pixels": 82.0,
				"arc_degrees": 112.0,
			}
		"circle":
			return {
				"shape": "circle",
				"length_pixels": 0.0,
				"width_pixels": 0.0,
				"radius_pixels": 68.0,
				"arc_degrees": 360.0,
			}
		"strip":
			return {
				"shape": "strip",
				"length_pixels": 320.0,
				"width_pixels": 54.0,
				"radius_pixels": 0.0,
				"arc_degrees": 0.0,
			}
		_:
			return {
				"shape": "capsule",
				"length_pixels": 116.0,
				"width_pixels": 42.0,
				"radius_pixels": 21.0,
				"arc_degrees": 0.0,
			}


static func _depth_path_profile(value: String) -> Dictionary:
	match value:
		"cross_depth":
			return {
				"path_mode": "diagonal_or_cross_depth",
				"depth_tolerance_pixels": 72.0,
			}
		"depth_band":
			return {
				"path_mode": "depth_band",
				"depth_tolerance_pixels": 118.0,
			}
		_:
			return {
				"path_mode": "same_lane",
				"depth_tolerance_pixels": 28.0,
			}


static func _tempo_profile(value: String) -> Dictionary:
	match value:
		"quick":
			return {
				"telegraph_seconds": 0.28,
				"commit_seconds": 0.07,
			}
		"committed":
			return {
				"telegraph_seconds": 0.78,
				"commit_seconds": 0.20,
			}
		_:
			return {
				"telegraph_seconds": 0.50,
				"commit_seconds": 0.12,
			}


static func _stability_profile(value: String) -> Dictionary:
	match value:
		"fragile":
			return {
				"telegraph": true,
				"commit": true,
				"active": true,
				"minimum_interrupt_strength": 0.75,
				"on_interrupt_next_phase": "recovery",
			}
		"armored_commit":
			return {
				"telegraph": true,
				"commit": false,
				"active": false,
				"minimum_interrupt_strength": 1.40,
				"on_interrupt_next_phase": "recovery",
			}
		_:
			return {
				"telegraph": true,
				"commit": false,
				"active": false,
				"minimum_interrupt_strength": 1.00,
				"on_interrupt_next_phase": "recovery",
			}


static func _recovery_profile(value: String) -> Dictionary:
	match value:
		"brief":
			return {
				"duration_seconds": 0.32,
				"movement_multiplier": 0.55,
				"turn_rate_multiplier": 0.65,
				"incoming_stagger_multiplier": 1.00,
			}
		"extended":
			return {
				"duration_seconds": 1.05,
				"movement_multiplier": 0.00,
				"turn_rate_multiplier": 0.15,
				"incoming_stagger_multiplier": 1.50,
			}
		_:
			return {
				"duration_seconds": 0.70,
				"movement_multiplier": 0.25,
				"turn_rate_multiplier": 0.35,
				"incoming_stagger_multiplier": 1.25,
			}


static func _compile_selection(raw: Dictionary) -> Dictionary:
	var range_profile := {}
	match str(raw["preferred_range"]):
		"close":
			range_profile = {"minimum_pixels": 0.0, "ideal_pixels": 68.0, "maximum_pixels": 120.0}
		"mid":
			range_profile = {"minimum_pixels": 80.0, "ideal_pixels": 190.0, "maximum_pixels": 320.0}
		"far":
			range_profile = {"minimum_pixels": 230.0, "ideal_pixels": 430.0, "maximum_pixels": 720.0}
		_:
			range_profile = {"minimum_pixels": 0.0, "ideal_pixels": 240.0, "maximum_pixels": 100000.0}

	var maximum_depth_delta := 100000.0
	match str(raw["depth_fit"]):
		"aligned":
			maximum_depth_delta = 32.0
		"tolerant":
			maximum_depth_delta = 96.0

	return {
		"preferred_range": str(raw["preferred_range"]),
		"minimum_distance_pixels": float(range_profile["minimum_pixels"]),
		"ideal_distance_pixels": float(range_profile["ideal_pixels"]),
		"maximum_distance_pixels": float(range_profile["maximum_pixels"]),
		"depth_fit": str(raw["depth_fit"]),
		"maximum_depth_delta_pixels": maximum_depth_delta,
		"base_priority": int(raw["base_priority"]),
		"coordination_cost": int(raw["coordination_cost"]),
		"requires_clear_path": bool(raw["requires_clear_path"]),
		"selection_rank": int(raw["selection_rank"]),
	}


static func _failure(code: String, errors: Array[String] = []) -> Dictionary:
	var all_errors := errors.duplicate()
	if all_errors.is_empty():
		all_errors.append(code)
	return {
		"ok": false,
		"complete": false,
		"error": code,
		"errors": all_errors,
		"player_confirmation_required": false,
		"identity_inputs_used": false,
	}
