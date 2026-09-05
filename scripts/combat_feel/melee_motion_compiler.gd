class_name MeleeMotionCompiler
extends RefCounted

const PROFILE := preload("res://scripts/combat_feel/combat_motion_profile.gd")
const PRIMITIVE := preload("res://scripts/combat_feel/motion_primitive.gd")
const RECIPE := preload("res://scripts/combat_feel/combo_recipe.gd")

const IMPACT_TO_MOTION := {
	"strike_edge": ["sweep", "edge"], "edge": ["sweep", "edge"],
	"strike_point": ["thrust", "point"], "point": ["thrust", "point"],
	"whole_body_collision": ["slam", "whole_body"],
	"body_collision": ["slam", "whole_body"], "body_contact": ["slam", "whole_body"],
	"whole_body": ["slam", "whole_body"],
}

const UNSUPPORTED := "UNSUPPORTED_AFFORDANCE_FOR_SLICE_1A"
const HANDLE_LENGTHS: PackedStringArray = ["none", "short", "medium", "long"]
const BODY_LENGTHS: PackedStringArray = ["short", "medium", "long"]
const GRIP_TOPOLOGIES: PackedStringArray = ["one_hand_handle", "two_hand_handle", "body_grip", "clamp_grip"]
const MASS_DISTRIBUTIONS: PackedStringArray = ["rear", "balanced", "front"]
const CONTACT_SURFACES: PackedStringArray = ["point", "edge", "broad", "whole_body"]
const SECONDARY_CONTACT_SURFACES: PackedStringArray = ["none", "point", "edge", "broad", "whole_body"]
const RIGIDITIES: PackedStringArray = ["rigid", "semi_rigid", "flexible"]
const FLEX_TOPOLOGIES: PackedStringArray = ["none", "bending_shaft", "flexible_line", "linked_segments"]
const TETHER_TOPOLOGIES: PackedStringArray = ["none", "flexible_line", "linked_segments"]
const TERMINAL_LOADS: PackedStringArray = ["none", "light", "heavy"]
const TETHER_MODES: PackedStringArray = ["none", "wrap", "hook"]
const TETHER_DEPLOYMENTS: PackedStringArray = ["none", "fixed_length", "cast_retract", "launch_tension"]
const STATE_TOPOLOGIES: PackedStringArray = ["fixed", "hinged", "folding", "telescoping", "radial_expand", "rotary"]
const ACTIVATION_MODES: PackedStringArray = ["passive", "momentary", "toggle", "charge_release", "continuous_hold"]
const FUNCTIONAL_OUTPUTS: PackedStringArray = ["contact_only", "directed_stream", "radial_field", "pull_field"]
const PRIMITIVE_ORDER: PackedStringArray = ["bash", "sweep", "thrust", "slam", "spin"]
const RIGIDITY_RUNTIME := {
	"rigid": {
		"angle_span": 0.94, "extension": 1.04, "root_motion": 1.02,
		"startup": 0.96, "active": 0.90, "recovery": 0.94,
		"knockback": 1.06, "stagger": 1.08, "hitstop": 1.10,
		"camera": 1.08, "movement_allowed": 0.88,
	},
	"semi_rigid": {
		"angle_span": 1.06, "extension": 0.96, "root_motion": 0.96,
		"startup": 1.02, "active": 1.08, "recovery": 1.06,
		"knockback": 0.96, "stagger": 0.95, "hitstop": 0.90,
		"camera": 0.94, "movement_allowed": 1.10,
	},
	"flexible": {
		"angle_span": 1.18, "extension": 0.88, "root_motion": 0.90,
		"startup": 1.10, "active": 1.18, "recovery": 1.16,
		"knockback": 0.86, "stagger": 0.84, "hitstop": 0.74,
		"camera": 0.80, "movement_allowed": 1.30,
	},
}
const GRIP_RUNTIME := {
	"one_hand_handle": {
		"angle_span": 0.96, "startup": 0.94, "root_motion": 1.04,
		"movement_allowed": 1.00, "control": 0.92,
		"early_cancel": 0.55, "late_cancel": 0.42,
		"combo_window": 0.52, "dodge_window": 0.34, "charge_threshold": 0.30,
	},
	"two_hand_handle": {
		"angle_span": 1.04, "startup": 1.06, "root_motion": 0.90,
		"movement_allowed": 0.66, "control": 1.14,
		"early_cancel": 0.25, "late_cancel": 0.70,
		"combo_window": 0.42, "dodge_window": 0.22, "charge_threshold": 0.38,
	},
	"body_grip": {
		"angle_span": 1.12, "startup": 1.10, "root_motion": 0.72,
		"movement_allowed": 0.48, "control": 1.04,
		"early_cancel": 0.15, "late_cancel": 0.78,
		"combo_window": 0.36, "dodge_window": 0.18, "charge_threshold": 0.42,
	},
	"clamp_grip": {
		"angle_span": 0.68, "startup": 0.86, "root_motion": 0.54,
		"movement_allowed": 0.30, "control": 0.86,
		"early_cancel": 0.48, "late_cancel": 0.50,
		"combo_window": 0.48, "dodge_window": 0.28, "charge_threshold": 0.24,
	},
}
const RIGIDITY_TRAJECTORY := {
	"rigid": {"lag": 0.0, "follow_through": 0.04},
	"semi_rigid": {"lag": 0.22, "follow_through": 0.22},
	"flexible": {"lag": 0.46, "follow_through": 0.48},
}
const FLEX_RUNTIME := {
	"none": {"lag": 0.00, "follow": 0.00, "active": 1.00, "recovery": 1.00, "contact_start": 0.00},
	"bending_shaft": {"lag": 0.08, "follow": 0.12, "active": 1.06, "recovery": 1.04, "contact_start": 0.18},
	"flexible_line": {"lag": 0.20, "follow": 0.28, "active": 1.16, "recovery": 1.10, "contact_start": 0.58},
	"linked_segments": {"lag": 0.15, "follow": 0.34, "active": 1.12, "recovery": 1.16, "contact_start": 0.70},
}
const TETHER_RUNTIME := {
	"none": {"lag": 0.00, "follow": 0.00, "active": 1.00, "recovery": 1.00, "contact_start": 0.00, "origin_ratio": 1.00},
	"flexible_line": {"lag": 0.18, "follow": 0.26, "active": 1.13, "recovery": 1.09, "contact_start": 0.66, "origin_ratio": 0.58},
	"linked_segments": {"lag": 0.14, "follow": 0.32, "active": 1.10, "recovery": 1.14, "contact_start": 0.74, "origin_ratio": 0.54},
}
const TERMINAL_LOAD_RUNTIME := {
	"none": {"ratio": 0.00, "follow": 0.00, "recovery": 1.00, "damage": 1.00, "impact": 1.00},
	"light": {"ratio": 0.38, "follow": 0.06, "recovery": 1.05, "damage": 1.08, "impact": 1.10},
	"heavy": {"ratio": 1.00, "follow": 0.14, "recovery": 1.16, "damage": 1.22, "impact": 1.28},
}
const TETHER_DEPLOYMENT_RUNTIME := {
	"none": {"reach": 1.00, "active": 1.00, "recovery": 1.00},
	"fixed_length": {"reach": 1.00, "active": 1.00, "recovery": 1.00},
	"cast_retract": {"reach": 1.24, "active": 1.24, "recovery": 1.12},
	"launch_tension": {"reach": 1.34, "active": 1.20, "recovery": 1.18},
}
const TETHER_STRENGTH := {"none": 0.0, "wrap": 0.0, "hook": 220.0}
const CONTACT_DAMAGE := {
	"point": 1.16,
	"edge": 1.06,
	"broad": 1.00,
	"whole_body": 0.86,
}
const ACTIVATION_RUNTIME := {
	"passive": {"startup": 1.00, "active": 1.00, "recovery": 1.00, "reach": 1.00, "width": 1.00},
	"momentary": {"startup": 0.92, "active": 1.12, "recovery": 0.96, "reach": 1.05, "width": 1.06},
	"toggle": {"startup": 1.04, "active": 1.28, "recovery": 1.04, "reach": 1.08, "width": 1.18},
	"charge_release": {"startup": 1.18, "active": 1.16, "recovery": 1.18, "reach": 1.24, "width": 1.12},
	"continuous_hold": {"startup": 1.02, "active": 1.72, "recovery": 1.10, "reach": 1.18, "width": 1.20},
}
const STATE_RUNTIME := {
	"fixed": {"reach": 1.00, "width": 1.00, "damage": 1.00},
	"hinged": {"reach": 1.02, "width": 1.34, "damage": 1.04},
	"folding": {"reach": 1.18, "width": 1.16, "damage": 1.02},
	"telescoping": {"reach": 1.42, "width": 0.86, "damage": 1.08},
	"radial_expand": {"reach": 1.08, "width": 1.82, "damage": 0.94},
	"rotary": {"reach": 1.04, "width": 1.52, "damage": 1.10},
}
const OUTPUT_RUNTIME := {
	"contact_only": {"reach": 1.00, "width": 1.00, "active": 1.00, "damage": 1.00, "knockback": 1.00},
	"directed_stream": {"reach": 1.52, "width": 1.24, "active": 1.48, "damage": 0.72, "knockback": 0.92},
	"radial_field": {"reach": 1.12, "width": 1.68, "active": 1.42, "damage": 0.68, "knockback": 1.18},
	"pull_field": {"reach": 1.38, "width": 1.38, "active": 1.46, "damage": 0.62, "knockback": 0.88},
}


func compile(source: Variant, detail: Variant, alpha_bounds: Rect2i = Rect2i()) -> Variant:
	if source is WeaponBlueprint and detail is WeaponVisualAsset:
		return _compile_legacy(source as WeaponBlueprint, detail as WeaponVisualAsset)
	if source is Resource and detail is Dictionary:
		return _compile_affordance(source as Resource, detail as Dictionary, alpha_bounds)
	return UNSUPPORTED


func _compile_affordance(affordance_profile: Resource, anchor_data: Dictionary, alpha_bounds: Rect2i) -> Variant:
	if not _inputs_are_valid(affordance_profile, anchor_data, alpha_bounds):
		return UNSUPPORTED
	return _compose_orthogonal_profile(affordance_profile, anchor_data, alpha_bounds)


func _compile_legacy(blueprint: WeaponBlueprint, asset: WeaponVisualAsset) -> Resource:
	var profile: Variant = PROFILE.new()
	var mapped: Array = IMPACT_TO_MOTION.get(blueprint.impact_mode, ["slam", "whole_body"])
	profile.silhouette_fill_ratio = _silhouette_fill_ratio(asset)
	profile.contact_bulk_ratio = _contact_bulk_ratio(asset)
	profile.motion_family = _resolve_motion_family(str(mapped[0]), profile.contact_bulk_ratio)
	profile.contact_mode = str(mapped[1])
	profile.reach_class = _classify_reach(asset)
	profile.weight_class = _classify_weight(blueprint, asset, profile.silhouette_fill_ratio)
	profile.tempo = _classify_tempo(profile)
	profile.grip_mode = _classify_grip(blueprint, asset)
	profile.combo_style = {"sweep": "forward_reverse_finisher", "slam": "side_backhand_overhead", "thrust": "jab_drive_lunge"}.get(profile.motion_family, "alternating")
	profile.charge_style = {"sweep": "wide_commitment", "slam": "overhead_ground_impact", "thrust": "narrow_long_lunge"}.get(profile.motion_family, "wide_commitment")
	profile.dodge_attack_style = {"sweep": "sliding_sweep", "slam": "advancing_slap", "thrust": "dash_thrust"}.get(profile.motion_family, "advancing_strike")
	profile.configure_timing_from_tempo()
	profile.reach_pixels = {"short": 84.0, "medium": 108.0, "long": 138.0}.get(profile.reach_class, 108.0)
	profile.swing_arc_degrees = _swing_arc(profile)
	profile.hitbox_thickness = _hitbox_thickness(profile)
	profile.control_strength = _control_strength(profile)
	profile.impact_sharpness = _impact_sharpness(profile)
	profile.render_scale = {"short": 1.10, "medium": 1.22, "long": 1.34}.get(profile.reach_class, 1.22)
	profile.combo_recipe = _compile_legacy_combo_recipe(profile.motion_family)
	return profile


func _compile_legacy_combo_recipe(base_family: String) -> Resource:
	var recipe: Variant = RECIPE.new()
	recipe.compile_reason = "legacy Blueprint plus visual compatibility path"
	match base_family:
		"slam":
			recipe.hit_1 = _primitive("slam", -1.42, 0.76, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0)
			recipe.hit_2 = _primitive("slam", -1.42, 0.76, 0.0, 1.06, 1.08, 1.08, 1.0, 1.08, 1.0)
			recipe.hit_3 = _primitive("slam", -1.72, 1.02, 0.0, 1.23, 1.30, 1.34, 1.18, 1.20, 1.0)
		"thrust":
			recipe.hit_1 = _primitive("thrust", -0.08, -0.08, 32.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0)
			recipe.hit_2 = _primitive("thrust", -0.08, -0.08, 32.0, 1.06, 1.08, 1.08, 1.0, 1.08, 1.0)
			recipe.hit_3 = _primitive("thrust", -0.08, -0.08, 48.0, 1.23, 1.30, 1.34, 1.18, 1.20, 1.0)
		_:
			recipe.hit_1 = _primitive("sweep", -1.18, 1.02, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0)
			recipe.hit_2 = _primitive("sweep", 1.02, -1.10, 0.0, 1.06, 1.08, 1.08, 1.0, 1.08, 1.0)
			recipe.hit_3 = _primitive("sweep", -1.58, 1.24, 0.0, 1.23, 1.30, 1.34, 1.18, 1.20, 1.0)
	recipe.charge_attack = _primitive(base_family, -1.58, 1.24, 0.0, 1.28, 1.35, 1.38, 1.24, 0.72, 1.15)
	recipe.dodge_attack = _primitive(base_family, -0.92, 0.82, 0.0, 0.68, 0.95, 0.72, 1.12, 1.35, 1.0)
	return recipe


func _compose_orthogonal_profile(
	affordance_profile: Resource,
	anchor_data: Dictionary,
	alpha_bounds: Rect2i
) -> Resource:
	var profile: Variant = _base_profile(affordance_profile, anchor_data, alpha_bounds)
	var base_scores := _score_primitives(affordance_profile)
	var effective_secondary := _effective_secondary_surface(affordance_profile)
	var used: Array[String] = []
	var selected := {}
	for stage: String in ["hit_1", "hit_2", "hit_3", "charge", "dodge"]:
		var family: String
		if stage in ["hit_3", "charge"] and affordance_profile.activation_mode != "passive":
			family = _stateful_family(affordance_profile, _family_for_contact(affordance_profile.contact_surface, stage))
		elif stage == "hit_1" or stage in ["charge", "dodge"]:
			family = _family_for_contact(affordance_profile.contact_surface, stage)
		elif stage == "hit_3" and effective_secondary != "none":
			family = _family_for_contact(effective_secondary, stage)
		else:
			family = _select_primitive(base_scores, stage, used, affordance_profile)
		selected[stage] = family
		if stage.begins_with("hit_"):
			used.append(family)
	var presentation_grammar := _structural_presentation_grammar(affordance_profile)
	if presentation_grammar == "polearm_point":
		selected = {"hit_1": "thrust", "hit_2": "thrust", "hit_3": "thrust", "charge": "thrust", "dodge": "thrust"}
	elif presentation_grammar == "weighted_flexible":
		# A flexible weighted endpoint is cast and recovered. It never borrows the
		# rigid-weapon thrust or a multi-turn sword spin merely to vary a combo.
		selected = {"hit_1": "sweep", "hit_2": "sweep", "hit_3": "sweep", "charge": "sweep", "dodge": "sweep"}
	var recipe: Variant = RECIPE.new()
	recipe.compile_reason = "orthogonal affordance composition v6 (%s): %s" % [presentation_grammar, JSON.stringify(_mechanism_axes(affordance_profile))]
	recipe.mechanism_axes = _mechanism_axes(affordance_profile)
	recipe.primitive_scores = base_scores.duplicate(true)
	var tether_origin_ratio := _tether_origin_ratio(anchor_data, affordance_profile.tether_topology)
	recipe.hit_1 = _synthesize_primitive(str(selected["hit_1"]), "hit_1", affordance_profile, tether_origin_ratio)
	recipe.hit_2 = _synthesize_primitive(str(selected["hit_2"]), "hit_2", affordance_profile, tether_origin_ratio)
	recipe.hit_3 = _synthesize_primitive(str(selected["hit_3"]), "hit_3", affordance_profile, tether_origin_ratio)
	recipe.charge_attack = _synthesize_primitive(str(selected["charge"]), "charge", affordance_profile, tether_origin_ratio)
	recipe.dodge_attack = _synthesize_primitive(str(selected["dodge"]), "dodge", affordance_profile, tether_origin_ratio)
	_apply_structural_presentation(recipe, presentation_grammar)
	profile.combo_recipe = recipe
	profile.motion_family = _legacy_family(str(selected["charge"]))
	profile.reach_class = _reach_class(affordance_profile)
	profile.weight_class = _weight_class(affordance_profile)
	profile.tempo = _tempo_for_axes(affordance_profile)
	profile.contact_mode = _legacy_contact_mode(affordance_profile.contact_surface)
	profile.combo_style = "orthogonal_per_hit"
	profile.charge_style = str(selected["charge"])
	profile.dodge_attack_style = str(selected["dodge"])
	profile.configure_timing_from_tempo()
	_apply_grip_profile(profile, affordance_profile)
	profile.reach_pixels = _general_reach(affordance_profile, anchor_data, alpha_bounds)
	profile.swing_arc_degrees = _general_arc(affordance_profile)
	profile.hitbox_thickness = _general_hitbox_thickness(affordance_profile)
	profile.control_strength = _general_control_strength(affordance_profile)
	profile.impact_sharpness = _general_impact_sharpness(affordance_profile)
	profile.render_scale = 1.08 + 0.12 * _body_axis(affordance_profile)
	profile.grip_topology = affordance_profile.grip_topology
	profile.rigidity_mode = affordance_profile.rigidity
	profile.primary_contact_surface = affordance_profile.contact_surface
	profile.secondary_contact_surface = effective_secondary
	profile.secondary_contact_stage = "hit_3" if effective_secondary != "none" else "none"
	profile.flex_topology = affordance_profile.flex_topology
	profile.tether_topology = affordance_profile.tether_topology
	profile.terminal_load = affordance_profile.terminal_load
	profile.tether_mode = affordance_profile.tether_mode
	profile.tether_deployment = affordance_profile.tether_deployment
	profile.state_topology = affordance_profile.state_topology
	profile.activation_mode = affordance_profile.activation_mode
	profile.functional_output = affordance_profile.functional_output
	profile.handle_leverage_ratio = _handle_axis(affordance_profile)
	profile.body_coverage_ratio = _body_axis(affordance_profile)
	profile.mass_inertia_ratio = _mass_axis(affordance_profile)
	profile.terminal_load_ratio = float(TERMINAL_LOAD_RUNTIME[affordance_profile.terminal_load]["ratio"])
	profile.tether_origin_ratio = tether_origin_ratio
	profile.close_range_deadzone_pixels = _handle_deadzone(affordance_profile)
	profile.mechanism_axes = recipe.mechanism_axes.duplicate(true)
	profile.primitive_scores = recipe.primitive_scores.duplicate(true)
	profile.compile_trace = {
		"composer": "orthogonal_affordance_v6",
		"selected": selected.duplicate(true),
		"presentation_grammar": presentation_grammar,
		"effective_secondary_contact": effective_secondary,
		"axis_roles": {
			"handle_length": "lever_and_inner_deadzone",
			"body_length": "physical_extent_and_coverage",
			"grip_topology": "pose_mobility_and_cancel_rules",
			"rigidity": "trajectory_lag_and_follow_through",
			"mass_distribution": "tempo_inertia_and_recovery_carry",
			"contact_surface": "hit_shape_and_reaction",
			"secondary_contact_surface": "reserved_hit_3_contact",
			"flex_topology": "wave_propagation_and_live_contact_segment",
			"tether_topology": "independent_secondary_soft_path_and_contact_delay",
			"terminal_load": "endpoint_radius_damage_and_follow_through",
			"tether_mode": "reserved_hit_3_pull_or_hold_reaction",
			"tether_deployment": "attached_line_payout_endpoint_flight_and_recovery",
			"state_topology": "reserved_hit_3_and_charge_shape_change",
			"activation_mode": "state_timing_and_sustain",
			"functional_output": "stateful_collision_volume_and_force_direction",
		},
		"identity_inputs_used": false,
		"silhouette_mechanics": (anchor_data.get("silhouette_mechanics", {}) as Dictionary).duplicate(true),
	}
	return profile


func _structural_presentation_grammar(affordance_profile: Resource) -> String:
	var long_lever: bool = affordance_profile.handle_length == "long" or affordance_profile.body_length == "long"
	var no_soft_path: bool = affordance_profile.flex_topology == "none" and affordance_profile.tether_topology == "none"
	if affordance_profile.rigidity == "rigid" \
		and affordance_profile.grip_topology == "two_hand_handle" \
		and affordance_profile.contact_surface == "point" \
		and long_lever and no_soft_path and not affordance_profile.has_barrel:
		return "polearm_point"
	if affordance_profile.flex_topology in ["flexible_line", "linked_segments"] \
		and affordance_profile.terminal_load != "none":
		return "weighted_flexible"
	return "generic"


func _apply_structural_presentation(recipe: Resource, grammar: String) -> void:
	if grammar == "generic":
		return
	var slots := {
		"hit_1": recipe.hit_1,
		"hit_2": recipe.hit_2,
		"hit_3": recipe.hit_3,
		"charge": recipe.charge_attack,
		"dodge": recipe.dodge_attack,
	}
	if grammar == "polearm_point":
		var pole_specs := {
			# A point lever needs more than pitch. Hit 2 is a ground-plane sweep:
			# its far endpoint begins behind the body, foreshortens while crossing
			# the depth axis, and finishes in front. Hit 3 keeps the vertical plant.
			"hit_1": ["pole_jab", 0.16, -0.10, 0.82, "thrust_line"],
			"hit_2": ["pole_rake", -2.72, 0.38, 0.78, "ground_sweep"],
			"hit_3": ["pole_pin", -0.92, 0.55, 0.72, "screen_arc"],
			"charge": ["pole_charge", -1.10, 0.60, 0.86, "screen_arc"],
			"dodge": ["pole_dodge", 0.20, -0.18, 0.94, "thrust_line"],
		}
		for stage: String in slots:
			var primitive: Resource = slots[stage]
			var spec: Array = pole_specs[stage]
			primitive.presentation_family = spec[0]
			primitive.start_angle = spec[1]
			primitive.end_angle = spec[2]
			primitive.extension_pixels *= float(spec[3])
			primitive.trajectory_plane = spec[4]
			if str(spec[4]) == "ground_sweep":
				primitive.local_start_offset = Vector2(-6.0, -3.0)
				primitive.local_end_offset = Vector2(10.0, 5.0)
		return
	var weighted_specs := {
		"hit_1": ["weighted_cast_low", 0.95, -0.15, "ground_orbit"],
		"hit_2": ["weighted_lash_cross", -0.78, 0.42, "ground_sweep"],
		"hit_3": ["weighted_retract", 0.48, -0.08, "ground_orbit"],
		"charge": ["weighted_cast_charge", 1.08, -0.32, "ground_orbit"],
		"dodge": ["weighted_dodge_lash", 0.38, -0.18, "ground_sweep"],
	}
	for stage: String in slots:
		var primitive: Resource = slots[stage]
		var spec: Array = weighted_specs[stage]
		primitive.presentation_family = spec[0]
		primitive.start_angle = spec[1]
		primitive.end_angle = spec[2]
		primitive.trajectory_plane = spec[3]
		# The visible terminal mass remains the live contact. Keep the contact
		# lane focused on the cast instead of the former 238-degree spin sector.
		primitive.contact_anchor = "tip"
		primitive.contact_arc_degrees = minf(primitive.contact_arc_degrees, 138.0)


func _score_primitives(affordance_profile: Resource) -> Dictionary:
	var scores := {"bash": 0.0, "sweep": 0.0, "thrust": 0.0, "slam": 0.0, "spin": 0.0}
	_apply_contact_scores(scores, affordance_profile.contact_surface, 1.0)
	match affordance_profile.handle_length:
		"none": _add_scores(scores, {"bash": 0.55, "slam": 0.45, "spin": 0.35})
		"short": _add_scores(scores, {"bash": 0.85, "slam": 0.65})
		"medium": _add_scores(scores, {"bash": 0.35, "sweep": 0.35, "thrust": 0.30})
		"long": _add_scores(scores, {"sweep": 0.85, "thrust": 0.75, "spin": 0.65})
	match affordance_profile.body_length:
		"short": _add_scores(scores, {"bash": 0.45, "slam": 0.30})
		"medium": _add_scores(scores, {"bash": 0.20, "sweep": 0.25})
		"long": _add_scores(scores, {"thrust": 0.75, "sweep": 0.55, "spin": 0.50})
	match affordance_profile.rigidity:
		"rigid": _add_scores(scores, {"thrust": 0.70, "bash": 0.55, "slam": 0.30})
		"semi_rigid": _add_scores(scores, {"sweep": 0.55, "spin": 0.50})
		"flexible": _add_scores(scores, {"spin": 1.00, "sweep": 0.85, "thrust": -0.45})
	match affordance_profile.flex_topology:
		"bending_shaft": _add_scores(scores, {"sweep": 0.70, "thrust": 0.30, "spin": 0.10})
		"flexible_line": _add_scores(scores, {"sweep": 0.80, "spin": 0.75, "thrust": -0.35})
		"linked_segments": _add_scores(scores, {"spin": 0.95, "bash": 0.55, "sweep": 0.30})
	match affordance_profile.mass_distribution:
		"front": _add_scores(scores, {"slam": 0.95, "bash": 0.55})
		"rear": _add_scores(scores, {"bash": 0.85, "thrust": 0.20})
		"balanced": _add_scores(scores, {"sweep": 0.45, "thrust": 0.40, "spin": 0.20})
	match affordance_profile.grip_topology:
		"two_hand_handle": _add_scores(scores, {"sweep": 0.45, "thrust": 0.40, "slam": 0.30})
		"body_grip": _add_scores(scores, {"spin": 0.55, "bash": 0.45})
		"clamp_grip": _add_scores(scores, {"bash": 0.60, "slam": 0.30})
	# Capability flags do not add a second copy of the primary contact score.
	# When they expose a genuinely different usable surface they are normalized
	# into one reserved secondary-contact hit by _effective_secondary_surface().
	return scores


func _apply_contact_scores(scores: Dictionary, surface: String, scale: float) -> void:
	match surface:
		"point": _add_scores(scores, {"thrust": 3.40 * scale, "bash": 0.45 * scale})
		"edge": _add_scores(scores, {"sweep": 3.25 * scale, "slam": 0.80 * scale, "spin": 0.40 * scale})
		"broad": _add_scores(scores, {"bash": 2.60 * scale, "slam": 2.10 * scale, "sweep": 1.10 * scale})
		"whole_body": _add_scores(scores, {"spin": 2.55 * scale, "sweep": 2.40 * scale, "slam": 1.80 * scale, "bash": 0.50 * scale})


func _add_scores(scores: Dictionary, additions: Dictionary) -> void:
	for key: Variant in additions:
		scores[str(key)] = float(scores.get(str(key), 0.0)) + float(additions[key])


func _family_for_contact(surface: String, stage: String) -> String:
	match surface:
		"point": return "thrust"
		"edge": return "sweep"
		"broad": return "slam" if stage == "charge" else "bash"
		"whole_body": return "sweep" if stage == "hit_1" else "spin"
	return "bash"


func _stateful_family(affordance_profile: Resource, fallback: String) -> String:
	match str(affordance_profile.functional_output):
		"directed_stream", "pull_field": return "thrust"
		"radial_field": return "spin"
	match str(affordance_profile.state_topology):
		"telescoping": return "thrust"
		"hinged", "folding": return "sweep"
		"radial_expand", "rotary": return "spin"
	return fallback


func _effective_secondary_surface(affordance_profile: Resource) -> String:
	if affordance_profile.secondary_contact_surface != "none":
		return affordance_profile.secondary_contact_surface
	if affordance_profile.has_stock:
		return "broad"
	# A capability already named as the primary contact is covered by that axis;
	# it must not secretly double the same score. A different capability becomes
	# a real rear/alternate contact and reserves hit three.
	if affordance_profile.has_point and affordance_profile.contact_surface != "point":
		return "point"
	if affordance_profile.has_edge and affordance_profile.contact_surface != "edge":
		return "edge"
	if affordance_profile.has_broad_face and affordance_profile.contact_surface != "broad":
		return "broad"
	return "none"


func _select_primitive(base_scores: Dictionary, stage: String, used: Array[String], affordance_profile: Resource) -> String:
	var scores: Dictionary = base_scores.duplicate(true)
	var biases := {
		"hit_1": {"bash": 0.75, "thrust": 0.70, "sweep": 0.45, "slam": -0.45, "spin": -0.65},
		"hit_2": {"sweep": 0.65, "spin": 0.55, "thrust": 0.35, "bash": 0.10, "slam": -0.25},
		"hit_3": {"slam": 1.20, "spin": 1.00, "bash": 0.90, "sweep": 0.20, "thrust": 0.10},
		"charge": {"slam": 1.35, "bash": 0.75, "sweep": 0.60, "spin": 0.35, "thrust": 0.20},
		"dodge": {"thrust": 1.20, "sweep": 0.80, "bash": 0.50, "spin": 0.15, "slam": -0.30},
	}
	_add_scores(scores, biases[stage])
	if stage == "hit_2" and not used.is_empty():
		# A continuation should prefer a different available mechanism instead of
		# replaying the opener merely because one axis has a dominant raw score.
		scores[used[0]] = float(scores[used[0]]) - 4.00
	if stage == "hit_3":
		for family: String in used:
			scores[family] = float(scores[family]) - 3.00
	var selected := PRIMITIVE_ORDER[0]
	var selected_score := -INF
	for family: String in PRIMITIVE_ORDER:
		var score := float(scores[family])
		if score > selected_score:
			selected = family
			selected_score = score
	return selected


func _synthesize_primitive(
	family: String,
	stage: String,
	affordance_profile: Resource,
	tether_origin_ratio: float
) -> Resource:
	var angle_data: Array = {
		"bash": [-0.62, 0.30], "sweep": [-1.28, 1.10], "thrust": [-0.06, -0.06],
		"slam": [-1.82, 1.04], "spin": [-2.85, 3.25],
	}[family]
	var effective_secondary := _effective_secondary_surface(affordance_profile)
	var active_state: bool = stage in ["hit_3", "charge"] and affordance_profile.activation_mode != "passive"
	var uses_secondary: bool = stage == "hit_3" and effective_secondary != "none" and not active_state
	var active_surface: String = effective_secondary if uses_secondary else affordance_profile.contact_surface
	if stage == "hit_2" and family in ["bash", "sweep"]:
		# Reverse the same arc, not [end, -start], which collapses a 136-degree
		# sweep into a barely visible 10-degree movement.
		angle_data = [float(angle_data[1]), float(angle_data[0])]
	var rigidity_runtime: Dictionary = RIGIDITY_RUNTIME[affordance_profile.rigidity]
	var grip_runtime: Dictionary = GRIP_RUNTIME[affordance_profile.grip_topology]
	var flex_runtime: Dictionary = FLEX_RUNTIME[affordance_profile.flex_topology]
	var tether_runtime: Dictionary = TETHER_RUNTIME[affordance_profile.tether_topology]
	var terminal_runtime: Dictionary = TERMINAL_LOAD_RUNTIME[affordance_profile.terminal_load]
	var activation_runtime: Dictionary = ACTIVATION_RUNTIME[affordance_profile.activation_mode] if active_state else ACTIVATION_RUNTIME["passive"]
	var state_runtime: Dictionary = STATE_RUNTIME[affordance_profile.state_topology] if active_state else STATE_RUNTIME["fixed"]
	var output_runtime: Dictionary = OUTPUT_RUNTIME[affordance_profile.functional_output] if active_state else OUTPUT_RUNTIME["contact_only"]
	var state_extent := 0.0
	if active_state:
		state_extent = 1.0 if stage == "charge" else (0.58 if affordance_profile.activation_mode == "charge_release" else 0.82)
	var delivery_stage := stage in ["hit_3", "charge"]
	var active_deployment := str(affordance_profile.tether_deployment) if delivery_stage else (
		"fixed_length" if str(affordance_profile.tether_topology) != "none" else "none"
	)
	var deployment_runtime: Dictionary = TETHER_DEPLOYMENT_RUNTIME[active_deployment]
	var contact_anchor := _contact_anchor_for(family, stage, affordance_profile)
	if uses_secondary and contact_anchor == "rear_contact":
		angle_data = _rear_contact_angle_data(family)
	if family != "thrust":
		var angle_midpoint := (float(angle_data[0]) + float(angle_data[1])) * 0.5
		var angle_half_span := (float(angle_data[1]) - float(angle_data[0])) * 0.5 \
			* float(rigidity_runtime["angle_span"]) * float(grip_runtime["angle_span"])
		angle_data = [angle_midpoint - angle_half_span, angle_midpoint + angle_half_span]
	var handle_axis := _handle_axis(affordance_profile)
	var body_axis := _body_axis(affordance_profile)
	var mass_axis := _mass_axis(affordance_profile)
	var stage_weight: float = {"hit_1": 0.84, "hit_2": 1.00, "hit_3": 1.20, "charge": 1.12, "dodge": 1.28}[stage]
	var lever_commitment := 1.0 if family == "thrust" else 0.94 + 0.14 * handle_axis
	var startup: float = (0.88 + mass_axis * 0.16) \
		* float({"hit_1": 0.88, "hit_2": 0.96, "hit_3": 1.18, "charge": 1.30, "dodge": 0.72}[stage]) \
		* float(rigidity_runtime["startup"]) * float(grip_runtime["startup"]) * lever_commitment \
		* float(activation_runtime["startup"])
	var recovery: float = (0.86 + mass_axis * 0.20) \
		* float({"hit_1": 0.88, "hit_2": 0.98, "hit_3": 1.24, "charge": 1.32, "dodge": 0.78}[stage]) \
		* float(rigidity_runtime["recovery"]) * float(flex_runtime["recovery"]) \
		* float(tether_runtime["recovery"]) * float(terminal_runtime["recovery"]) \
		* float(deployment_runtime["recovery"]) \
		* float(activation_runtime["recovery"]) \
		* (0.96 + 0.08 * handle_axis if family != "thrust" else 1.0)
	var contact_width: float = {"point": 0.66, "edge": 0.88, "broad": 1.18, "whole_body": 1.28}[active_surface]
	var root_distance: float = (4.0 + handle_axis * 10.0 + body_axis * 8.0 + (7.0 if affordance_profile.has_barrel else 0.0)) \
		* stage_weight * float(rigidity_runtime["root_motion"]) * float(grip_runtime["root_motion"]) \
		* (0.78 + 0.38 * mass_axis)
	var extension: float = ((18.0 + 12.0 * handle_axis + 26.0 * body_axis) * float(rigidity_runtime["extension"])) \
		if family == "thrust" else 0.0
	var movement_allowed := clampf((0.08 + 0.12 * handle_axis) if family in ["sweep", "spin"] else 0.06, 0.0, 0.34)
	movement_allowed *= float(rigidity_runtime["movement_allowed"]) * float(grip_runtime["movement_allowed"])
	var deadzone := 0.0 if active_surface == "whole_body" else _handle_deadzone(affordance_profile)
	if uses_secondary:
		deadzone *= 0.40
	var trajectory: Dictionary = RIGIDITY_TRAJECTORY[affordance_profile.rigidity]
	var trajectory_lag := clampf(
		float(trajectory["lag"]) + float(flex_runtime["lag"]) \
			+ float(tether_runtime["lag"]) + float(terminal_runtime["ratio"]) * 0.04,
		0.0,
		1.0
	)
	var follow_through := clampf(
		float(trajectory["follow_through"]) + float(flex_runtime["follow"]) \
			+ float(tether_runtime["follow"]) + float(terminal_runtime["follow"]),
		0.0,
		1.2
	)
	var active_tether: String = str(affordance_profile.tether_mode) if stage == "hit_3" else "none"
	var tether_stagger: float = 1.45 if active_tether == "wrap" else 1.0
	var finisher := 1.0 if stage not in ["hit_3", "charge"] else 1.22
	var state_reach: float = float(activation_runtime["reach"]) * float(state_runtime["reach"]) * float(output_runtime["reach"])
	var state_width: float = float(activation_runtime["width"]) * float(state_runtime["width"]) * float(output_runtime["width"])
	return _primitive(family, float(angle_data[0]), float(angle_data[1]), extension, startup, (1.0 + 0.08 * mass_axis) * float(rigidity_runtime["active"]) * float(flex_runtime["active"]) * float(tether_runtime["active"]) * float(deployment_runtime["active"]) * float(activation_runtime["active"]) * float(output_runtime["active"]), recovery, (0.88 + 0.08 * handle_axis + 0.14 * body_axis) * float(deployment_runtime["reach"]) * state_reach, 0.82 + 0.18 * handle_axis, 0.88 + 0.18 * contact_width, {
		"contact_anchor": contact_anchor,
		"contact_surface": active_surface,
		"uses_secondary_contact": uses_secondary,
		"root_motion_distance": root_distance,
		"inertia_ratio": mass_axis,
		"trajectory_lag_ratio": trajectory_lag,
		"follow_through_radians": follow_through,
		"flex_topology": affordance_profile.flex_topology,
		"tether_topology": affordance_profile.tether_topology,
		"tether_origin_ratio": tether_origin_ratio,
		"terminal_load_ratio": float(terminal_runtime["ratio"]),
		"soft_contact_start_ratio": maxf(float(flex_runtime["contact_start"]), float(tether_runtime["contact_start"])),
		"tether_mode": active_tether,
		"tether_strength": float(TETHER_STRENGTH[active_tether]),
		"tether_deployment": active_deployment,
		"state_topology": affordance_profile.state_topology,
		"activation_mode": affordance_profile.activation_mode,
		"functional_output": affordance_profile.functional_output,
		"state_extent_ratio": state_extent,
		"inner_deadzone_pixels": deadzone,
		"contact_arc_degrees": _contact_arc_degrees(active_surface, handle_axis, body_axis, affordance_profile),
		"damage_multiplier": float(CONTACT_DAMAGE[active_surface]) * float(terminal_runtime["damage"]) * float(state_runtime["damage"]) * float(output_runtime["damage"]),
		"hitbox_width_multiplier": contact_width * state_width,
		"hitbox_length_multiplier": 0.82 + 0.10 * handle_axis + 0.28 * body_axis,
		"knockback_multiplier": (0.82 + 0.28 * mass_axis) * finisher * float(rigidity_runtime["knockback"]) * float(grip_runtime["control"]) * float(terminal_runtime["impact"]) * float(output_runtime["knockback"]),
		"stagger_multiplier": (0.84 + 0.26 * mass_axis) * finisher * float(rigidity_runtime["stagger"]) * float(grip_runtime["control"]) * float(terminal_runtime["impact"]) * tether_stagger,
		"hitstop_multiplier": (0.82 + 0.22 * mass_axis) * finisher * float(rigidity_runtime["hitstop"]),
		"camera_kick_multiplier": (0.84 + 0.20 * mass_axis) * finisher * float(rigidity_runtime["camera"]),
		"movement_allowed_ratio": movement_allowed,
	})


func _contact_anchor_for(family: String, stage: String, affordance_profile: Resource) -> String:
	var effective_secondary := _effective_secondary_surface(affordance_profile)
	# Flexible structures deliver their live endpoint at StrikePoint. This keeps a
	# hook, lash tip or linked terminal mass at the drawn front end instead of
	# reusing the rigid-weapon rear-contact convention.
	if affordance_profile.flex_topology != "none" or affordance_profile.tether_topology != "none":
		return "tip"
	if stage == "hit_3" and effective_secondary != "none":
		# A second kind of surface does NOT establish that it is on the back.
		# Only an explicitly declared stock licenses the rear broad contact.
		# Otherwise use the measured strike/output region we actually possess,
		# retaining secondary surface/arc/impact without inventing a rear blade.
		if effective_secondary == "whole_body": return "whole_body"
		if effective_secondary == "broad" and affordance_profile.has_stock: return "rear_contact"
		if effective_secondary == "point" and affordance_profile.has_barrel: return "muzzle"
		return "tip"
	if family == "spin" or affordance_profile.contact_surface == "whole_body":
		return "whole_body"
	if family == "thrust" and affordance_profile.has_barrel:
		return "muzzle"
	return "tip"


func _rear_contact_angle_data(family: String) -> Array:
	# A rear contact must be rotated toward the target. Merely changing the anchor
	# would leave the stock/spike behind the player and make the second surface a
	# hidden collision-only effect.
	match family:
		"thrust": return [PI - 0.06, PI - 0.06]
		"sweep": return [PI - 1.10, PI + 1.18]
		"slam": return [PI - 1.42, PI + 0.92]
		"spin": return [PI - 2.85, PI + 3.25]
		_: return [PI - 0.62, PI + 0.30]


func _contact_arc_degrees(surface: String, handle_axis: float, body_axis: float, affordance_profile: Resource) -> float:
	var base: float = {"point": 18.0, "edge": 112.0, "broad": 58.0, "whole_body": 238.0}[surface]
	var body_bonus := body_axis * (34.0 if surface in ["edge", "whole_body"] else 18.0)
	var handle_bonus := handle_axis * (24.0 if surface == "edge" else 10.0)
	var grip_scale := float(GRIP_RUNTIME[affordance_profile.grip_topology]["angle_span"])
	return clampf((base + body_bonus + handle_bonus) * grip_scale, 12.0, 360.0)


func _mechanism_axes(affordance_profile: Resource) -> Dictionary:
	return affordance_profile.to_dict()


func _handle_axis(affordance_profile: Resource) -> float:
	return float({"none": 0.0, "short": 0.25, "medium": 0.60, "long": 1.0}[affordance_profile.handle_length])


func _body_axis(affordance_profile: Resource) -> float:
	return float({"short": 0.20, "medium": 0.58, "long": 1.0}[affordance_profile.body_length])


func _handle_deadzone(affordance_profile: Resource) -> float:
	return float({"none": 0.0, "short": 2.0, "medium": 9.0, "long": 20.0}[affordance_profile.handle_length])


func _mass_axis(affordance_profile: Resource) -> float:
	# Mass closer to the grip reduces rotational commitment and delivered contact
	# force; mass farther forward increases both. Keep this ordering independent
	# of identity, selected Primitive, and any retained sample Recipe.
	return {"rear": 0.16, "balanced": 0.54, "front": 1.0}[affordance_profile.mass_distribution]


func _reach_class(affordance_profile: Resource) -> String:
	# Both dimensions contribute to tip distance, but with different weights and
	# independent runtime roles. This is not the former handle/body average.
	var axis := 0.38 * _handle_axis(affordance_profile) + 0.62 * _body_axis(affordance_profile)
	return "short" if axis < 0.38 else ("long" if axis > 0.78 else "medium")


func _weight_class(affordance_profile: Resource) -> String:
	return {"rear": "light", "balanced": "medium", "front": "heavy"}[affordance_profile.mass_distribution]


func _tempo_for_axes(affordance_profile: Resource) -> String:
	# Mass distribution owns momentum tempo. Length no longer pushes an unrelated
	# weapon across the same three tempo bins.
	return {"rear": "rapid", "balanced": "balanced", "front": "committed"}[affordance_profile.mass_distribution]


func _legacy_family(family: String) -> String:
	return {"bash": "slam", "slam": "slam", "thrust": "thrust", "sweep": "sweep", "spin": "sweep"}[family]


func _legacy_contact_mode(surface: String) -> String:
	return {"point": "point", "edge": "edge", "broad": "whole_body", "whole_body": "whole_body"}[surface]


func _general_reach(affordance_profile: Resource, anchor_data: Dictionary, alpha_bounds: Rect2i) -> float:
	var measured := _strike_span(anchor_data) * 0.48 + float(maxi(alpha_bounds.size.x, alpha_bounds.size.y)) * 0.56
	return clampf(
		56.0 + 30.0 * _handle_axis(affordance_profile) + 48.0 * _body_axis(affordance_profile) + measured * 0.14,
		72.0,
		168.0
	)


func _general_arc(affordance_profile: Resource) -> float:
	return _contact_arc_degrees(
		affordance_profile.contact_surface,
		_handle_axis(affordance_profile),
		_body_axis(affordance_profile),
		affordance_profile
	)


func _general_hitbox_thickness(affordance_profile: Resource) -> float:
	return float({"point": 30.0, "edge": 42.0, "broad": 62.0, "whole_body": 70.0}[affordance_profile.contact_surface])


func _general_control_strength(affordance_profile: Resource) -> float:
	return 0.88 + 0.24 * _body_axis(affordance_profile)


func _general_impact_sharpness(affordance_profile: Resource) -> float:
	return {"point": 1.22, "edge": 1.16, "broad": 1.08, "whole_body": 0.92}[affordance_profile.contact_surface]


func _base_profile(affordance_profile: Resource, anchor_data: Dictionary, alpha_bounds: Rect2i) -> Resource:
	var profile: Variant = PROFILE.new()
	var bounds_area := float(alpha_bounds.size.x * alpha_bounds.size.y)
	profile.silhouette_fill_ratio = bounds_area / (96.0 * 96.0)
	profile.contact_bulk_ratio = {"point": 0.18, "edge": 0.30, "broad": 0.52, "whole_body": 0.62}[affordance_profile.contact_surface]
	profile.grip_mode = "two_hand" if affordance_profile.grip_topology == "two_hand_handle" else ("center" if affordance_profile.grip_topology == "body_grip" else "one_hand")
	return profile


func _apply_grip_profile(profile: Resource, affordance_profile: Resource) -> void:
	var runtime: Dictionary = GRIP_RUNTIME[affordance_profile.grip_topology]
	profile.early_startup_cancel_ratio = float(runtime["early_cancel"])
	profile.late_recovery_cancel_ratio = float(runtime["late_cancel"])
	profile.combo_window_seconds = float(runtime["combo_window"])
	profile.dodge_attack_window_seconds = float(runtime["dodge_window"])
	profile.charge_threshold_seconds = float(runtime["charge_threshold"])


func _primitive(
	family: String,
	start_angle: float,
	end_angle: float,
	extension_pixels: float,
	startup_multiplier: float,
	active_multiplier: float,
	recovery_multiplier: float,
	reach_multiplier: float,
	movement_multiplier: float,
	hitbox_multiplier: float,
	extras: Dictionary = {}
) -> Resource:
	var primitive: Variant = PRIMITIVE.new()
	primitive.motion_family = family
	primitive.contact_surface = {
		"thrust": "point", "sweep": "edge", "bash": "broad",
		"slam": "broad", "spin": "whole_body",
	}.get(family, "edge")
	primitive.contact_arc_degrees = {
		"thrust": 18.0, "sweep": 120.0, "bash": 58.0,
		"slam": 72.0, "spin": 360.0,
	}.get(family, 110.0)
	primitive.damage_multiplier = float(CONTACT_DAMAGE[primitive.contact_surface])
	primitive.start_angle = start_angle
	primitive.end_angle = end_angle
	primitive.extension_pixels = extension_pixels
	primitive.startup_multiplier = startup_multiplier
	primitive.active_multiplier = active_multiplier
	primitive.recovery_multiplier = recovery_multiplier
	primitive.reach_multiplier = reach_multiplier
	primitive.movement_multiplier = movement_multiplier
	primitive.hitbox_multiplier = hitbox_multiplier
	for key: String in extras:
		primitive.set(key, extras[key])
	return primitive


func _inputs_are_valid(affordance_profile: Resource, anchor_data: Dictionary, alpha_bounds: Rect2i) -> bool:
	if affordance_profile == null or alpha_bounds.size.x <= 0 or alpha_bounds.size.y <= 0:
		return false
	if affordance_profile.has_method("validation_errors") and not affordance_profile.validation_errors().is_empty():
		return false
	if affordance_profile.handle_length not in HANDLE_LENGTHS:
		return false
	if affordance_profile.body_length not in BODY_LENGTHS:
		return false
	if affordance_profile.grip_topology not in GRIP_TOPOLOGIES:
		return false
	if affordance_profile.mass_distribution not in MASS_DISTRIBUTIONS:
		return false
	if affordance_profile.contact_surface not in CONTACT_SURFACES:
		return false
	if affordance_profile.secondary_contact_surface not in SECONDARY_CONTACT_SURFACES:
		return false
	if affordance_profile.rigidity not in RIGIDITIES:
		return false
	if affordance_profile.flex_topology not in FLEX_TOPOLOGIES:
		return false
	if affordance_profile.tether_topology not in TETHER_TOPOLOGIES:
		return false
	if affordance_profile.terminal_load not in TERMINAL_LOADS:
		return false
	if affordance_profile.tether_mode not in TETHER_MODES:
		return false
	if affordance_profile.tether_deployment not in TETHER_DEPLOYMENTS:
		return false
	if affordance_profile.state_topology not in STATE_TOPOLOGIES:
		return false
	if affordance_profile.activation_mode not in ACTIVATION_MODES:
		return false
	if affordance_profile.functional_output not in FUNCTIONAL_OUTPUTS:
		return false
	return _anchor_point(anchor_data, ["GripPrimary", "grip_primary"]) != Vector2.INF \
		and _anchor_point(anchor_data, ["StrikePoint", "strike_point", "tip"]) != Vector2.INF


func _strike_span(anchor_data: Dictionary) -> float:
	var grip := _anchor_point(anchor_data, ["GripPrimary", "grip_primary"])
	var strike := _anchor_point(anchor_data, ["StrikePoint", "strike_point", "tip"])
	return grip.distance_to(strike)


func _grip_span(anchor_data: Dictionary) -> float:
	var primary := _anchor_point(anchor_data, ["GripPrimary", "grip_primary"])
	var secondary := _anchor_point(anchor_data, ["GripSecondary", "grip_secondary"])
	return 0.0 if secondary == Vector2.INF else primary.distance_to(secondary)


func _tether_origin_ratio(anchor_data: Dictionary, topology: String) -> float:
	if topology == "none":
		return 1.0
	var fallback := float(TETHER_RUNTIME[topology]["origin_ratio"])
	var grip := _anchor_point(anchor_data, ["TetherGrip", "GripPrimary", "grip_primary"])
	var origin := _anchor_point(anchor_data, ["TetherOrigin", "LineOrigin", "tether_origin", "line_origin"])
	var strike := _anchor_point(anchor_data, ["StrikePoint", "strike_point", "tip"])
	if grip == Vector2.INF or origin == Vector2.INF or strike == Vector2.INF:
		return fallback
	var body_length := grip.distance_to(origin)
	var tether_length := origin.distance_to(strike)
	if body_length < 1.0 or tether_length < 1.0:
		return fallback
	# This is a ratio along the two-part mechanism path, not a projection on the
	# direct Grip-to-Strike ray. It therefore also works when the line hangs down
	# from a bent shaft instead of remaining collinear with it.
	return clampf(body_length / (body_length + tether_length), 0.15, 0.90)


func _anchor_point(anchor_data: Dictionary, keys: Array[String]) -> Vector2:
	for key: String in keys:
		if not anchor_data.has(key):
			continue
		var value: Variant = anchor_data[key]
		if value is Vector2:
			return value
		if value is Array and value.size() >= 2:
			return Vector2(float(value[0]), float(value[1]))
	return Vector2.INF


func _resolve_motion_family(mapped_family: String, contact_bulk: float) -> String:
	if mapped_family == "thrust" and contact_bulk >= 0.24:
		return "sweep"
	return mapped_family


func _classify_reach(asset: WeaponVisualAsset) -> String:
	if asset == null:
		return "medium"
	var strike_point := asset.tip if asset.tip != Vector2.ZERO else asset.muzzle
	var anchor_distance := asset.grip_primary.distance_to(strike_point)
	var major_axis := float(maxi(asset.opaque_bounds.size.x, asset.opaque_bounds.size.y))
	var bounded_score := clampf(anchor_distance * 0.68 + major_axis * 0.42, 24.0, 150.0)
	if bounded_score < 61.0:
		return "short"
	if bounded_score > 88.0:
		return "long"
	return "medium"


func _classify_weight(blueprint: WeaponBlueprint, asset: WeaponVisualAsset, fill_ratio: float) -> String:
	var coverage := 0.0
	var body_area := 0.0
	if asset != null:
		body_area = float(asset.opaque_bounds.size.x * asset.opaque_bounds.size.y)
		coverage = body_area / maxf(1.0, float(asset.canvas_size.x * asset.canvas_size.y))
	var score := clampf(coverage * 0.72 + body_area / 24000.0 + fill_ratio * 0.82, 0.0, 1.5)
	match blueprint.weight_class:
		"light": score -= 0.22
		"heavy": score += 0.28
	match blueprint.silhouette_mass_distribution:
		"front_heavy", "top_heavy": score += 0.12
		"thin", "minimal": score -= 0.10
	if score < 0.40:
		return "light"
	if score > 0.82:
		return "heavy"
	return "medium"


func _classify_tempo(profile: Resource) -> String:
	if profile.reach_class == "short":
		return "rapid"
	if profile.reach_class == "long" and profile.silhouette_fill_ratio < 0.20:
		return "balanced"
	return {"light": "rapid", "medium": "balanced", "heavy": "committed"}.get(profile.weight_class, "balanced")


func _silhouette_fill_ratio(asset: WeaponVisualAsset) -> float:
	if asset == null or asset.source_image == null or asset.opaque_bounds.size.x <= 0 or asset.opaque_bounds.size.y <= 0:
		return 0.0
	var filled := 0
	for y: int in range(asset.opaque_bounds.position.y, asset.opaque_bounds.end.y):
		for x: int in range(asset.opaque_bounds.position.x, asset.opaque_bounds.end.x):
			if asset.source_image.get_pixel(x, y).a >= 0.12:
				filled += 1
	return float(filled) / maxf(1.0, float(asset.opaque_bounds.size.x * asset.opaque_bounds.size.y))


func _contact_bulk_ratio(asset: WeaponVisualAsset) -> float:
	if asset == null or asset.source_image == null:
		return 0.0
	var center := Vector2i(roundi(asset.tip.x), roundi(asset.tip.y))
	var radius := 11
	var samples := 0
	var filled := 0
	for y: int in range(center.y - radius, center.y + radius + 1):
		for x: int in range(center.x - radius, center.x + radius + 1):
			if x < 0 or y < 0 or x >= asset.source_image.get_width() or y >= asset.source_image.get_height():
				continue
			if Vector2i(x, y).distance_squared_to(center) > radius * radius:
				continue
			samples += 1
			if asset.source_image.get_pixel(x, y).a >= 0.12:
				filled += 1
	return float(filled) / maxf(1.0, float(samples))


func _swing_arc(profile: Resource) -> float:
	if profile.motion_family == "thrust":
		return 22.0
	if profile.motion_family == "slam":
		return 92.0
	var arc := 145.0
	if profile.reach_class == "long":
		arc += 24.0
	if profile.silhouette_fill_ratio < 0.20:
		arc += 18.0
	return clampf(arc, 120.0, 190.0)


func _hitbox_thickness(profile: Resource) -> float:
	if profile.motion_family == "thrust":
		return 42.0
	if profile.motion_family == "slam":
		return 58.0
	return 48.0 + (10.0 if profile.reach_class == "long" else 0.0)


func _control_strength(profile: Resource) -> float:
	var value := 1.0
	if profile.motion_family == "sweep":
		value += 0.16
	if profile.reach_class == "long":
		value += 0.12
	if profile.silhouette_fill_ratio < 0.20:
		value += 0.14
	return clampf(value, 0.85, 1.42)


func _impact_sharpness(profile: Resource) -> float:
	var value := 1.0
	if profile.reach_class == "short":
		value += 0.22
	if profile.contact_mode == "whole_body":
		value += 0.12
	if profile.tempo == "committed":
		value -= 0.08
	return clampf(value, 0.82, 1.34)


func _classify_grip(blueprint: WeaponBlueprint, asset: WeaponVisualAsset) -> String:
	if blueprint.grip_profile == "two_hand_rear":
		return "two_hand"
	if blueprint.grip_profile == "throwable_center":
		return "center"
	if asset != null and asset.grip_primary.distance_to(asset.grip_secondary) >= 15.0:
		return "two_hand"
	return "one_hand"
