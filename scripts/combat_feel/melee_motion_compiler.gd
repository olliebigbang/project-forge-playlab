class_name MeleeMotionCompiler
extends RefCounted

const PROFILE := preload("res://scripts/combat_feel/combat_motion_profile.gd")
const PRIMITIVE := preload("res://scripts/combat_feel/motion_primitive.gd")
const RECIPE := preload("res://scripts/combat_feel/combo_recipe.gd")

const UNSUPPORTED := "unsupported"
const HANDLE_LENGTHS: PackedStringArray = ["short", "medium", "long"]
const BODY_LENGTHS: PackedStringArray = ["short", "medium", "long"]
const MASS_DISTRIBUTIONS: PackedStringArray = ["rear", "balanced", "front"]
const CONTACT_SURFACES: PackedStringArray = ["point", "edge", "broad", "whole_body"]
const RIGIDITIES: PackedStringArray = ["rigid", "semi_rigid", "flexible"]


func compile(affordance_profile: Resource, anchor_data: Dictionary, alpha_bounds: Rect2i) -> Variant:
	if not _inputs_are_valid(affordance_profile, anchor_data, alpha_bounds):
		return UNSUPPORTED
	if _matches_short_front_broad(affordance_profile):
		return _compile_short_front_broad(affordance_profile, anchor_data, alpha_bounds)
	if _matches_long_broad(affordance_profile):
		return _compile_long_broad(affordance_profile, anchor_data, alpha_bounds)
	return UNSUPPORTED


func _compile_short_front_broad(
	affordance_profile: Resource,
	anchor_data: Dictionary,
	alpha_bounds: Rect2i
) -> Resource:
	var profile: Variant = _base_profile(affordance_profile, anchor_data, alpha_bounds)
	profile.motion_family = "slam"
	profile.weight_class = "heavy"
	profile.reach_class = "short"
	profile.tempo = "committed"
	profile.contact_mode = "whole_body"
	profile.combo_style = "bash_reverse_slam"
	profile.charge_style = "overhead_ground_impact"
	profile.dodge_attack_style = "advancing_slap"
	profile.configure_timing_from_tempo()
	profile.reach_pixels = _short_reach(anchor_data, alpha_bounds)
	profile.swing_arc_degrees = 88.0
	profile.hitbox_thickness = 52.0
	profile.control_strength = 0.96
	profile.impact_sharpness = 1.30
	profile.render_scale = 1.18
	var recipe: Variant = RECIPE.new()
	recipe.hit_1 = _primitive("bash", -0.74, 0.32, 0.0, 0.42, 0.85, 0.48, 0.86, 0.48, 0.78)
	recipe.hit_2 = _primitive("bash", 0.64, -0.40, 0.0, 0.46, 0.90, 0.52, 0.90, 0.42, 0.82)
	recipe.hit_3 = _primitive("slam", -1.78, 1.05, 0.0, 0.90, 1.15, 1.05, 1.00, 0.32, 1.05)
	profile.combo_recipe = recipe
	return profile


func _compile_long_broad(
	affordance_profile: Resource,
	anchor_data: Dictionary,
	alpha_bounds: Rect2i
) -> Resource:
	var profile: Variant = _base_profile(affordance_profile, anchor_data, alpha_bounds)
	profile.motion_family = "sweep"
	profile.weight_class = "medium"
	profile.reach_class = "long"
	profile.tempo = "balanced"
	profile.contact_mode = "whole_body"
	profile.combo_style = "sweep_push_spin"
	profile.charge_style = "wide_commitment"
	profile.dodge_attack_style = "sliding_sweep"
	profile.configure_timing_from_tempo()
	profile.reach_pixels = _long_reach(anchor_data, alpha_bounds)
	profile.swing_arc_degrees = 210.0
	profile.hitbox_thickness = 64.0
	profile.control_strength = 1.38
	profile.impact_sharpness = 0.96
	profile.render_scale = 1.28
	var recipe: Variant = RECIPE.new()
	recipe.hit_1 = _primitive("sweep", -1.35, 1.15, 0.0, 0.95, 1.00, 0.92, 1.08, 1.12, 1.15)
	recipe.hit_2 = _primitive("thrust", -0.05, -0.05, 42.0, 1.08, 0.92, 0.98, 1.18, 1.35, 1.05)
	recipe.hit_3 = _primitive("spin", -2.85, 3.25, 0.0, 1.18, 1.18, 1.22, 1.32, 1.18, 1.35)
	profile.combo_recipe = recipe
	return profile


func _base_profile(affordance_profile: Resource, anchor_data: Dictionary, alpha_bounds: Rect2i) -> Resource:
	var profile: Variant = PROFILE.new()
	var bounds_area := float(alpha_bounds.size.x * alpha_bounds.size.y)
	profile.silhouette_fill_ratio = bounds_area / (96.0 * 96.0)
	profile.contact_bulk_ratio = 0.62 if affordance_profile.contact_surface == "whole_body" else 0.48
	profile.grip_mode = "two_hand" if _grip_span(anchor_data) >= 15.0 else "one_hand"
	return profile


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
	hitbox_multiplier: float
) -> Resource:
	var primitive: Variant = PRIMITIVE.new()
	primitive.motion_family = family
	primitive.start_angle = start_angle
	primitive.end_angle = end_angle
	primitive.extension_pixels = extension_pixels
	primitive.startup_multiplier = startup_multiplier
	primitive.active_multiplier = active_multiplier
	primitive.recovery_multiplier = recovery_multiplier
	primitive.reach_multiplier = reach_multiplier
	primitive.movement_multiplier = movement_multiplier
	primitive.hitbox_multiplier = hitbox_multiplier
	return primitive


func _inputs_are_valid(affordance_profile: Resource, anchor_data: Dictionary, alpha_bounds: Rect2i) -> bool:
	if affordance_profile == null or alpha_bounds.size.x <= 0 or alpha_bounds.size.y <= 0:
		return false
	if affordance_profile.handle_length not in HANDLE_LENGTHS:
		return false
	if affordance_profile.body_length not in BODY_LENGTHS:
		return false
	if affordance_profile.mass_distribution not in MASS_DISTRIBUTIONS:
		return false
	if affordance_profile.contact_surface not in CONTACT_SURFACES:
		return false
	if affordance_profile.rigidity not in RIGIDITIES:
		return false
	return _anchor_point(anchor_data, ["GripPrimary", "grip_primary"]) != Vector2.INF \
		and _anchor_point(anchor_data, ["StrikePoint", "strike_point", "tip"]) != Vector2.INF


func _matches_short_front_broad(affordance_profile: Resource) -> bool:
	return affordance_profile.handle_length == "short" \
		and affordance_profile.body_length == "short" \
		and affordance_profile.mass_distribution == "front" \
		and affordance_profile.contact_surface == "broad"


func _matches_long_broad(affordance_profile: Resource) -> bool:
	return affordance_profile.handle_length == "long" \
		and affordance_profile.body_length == "long" \
		and affordance_profile.contact_surface in ["broad", "whole_body"]


func _short_reach(anchor_data: Dictionary, alpha_bounds: Rect2i) -> float:
	var anchor_span := _strike_span(anchor_data)
	var major_axis := float(maxi(alpha_bounds.size.x, alpha_bounds.size.y))
	return clampf(anchor_span * 0.35 + major_axis * 0.55, 84.0, 94.0)


func _long_reach(anchor_data: Dictionary, alpha_bounds: Rect2i) -> float:
	var anchor_span := _strike_span(anchor_data)
	var major_axis := float(maxi(alpha_bounds.size.x, alpha_bounds.size.y))
	return clampf(anchor_span * 0.70 + major_axis * 0.82, 126.0, 148.0)


func _strike_span(anchor_data: Dictionary) -> float:
	var grip := _anchor_point(anchor_data, ["GripPrimary", "grip_primary"])
	var strike := _anchor_point(anchor_data, ["StrikePoint", "strike_point", "tip"])
	return grip.distance_to(strike)


func _grip_span(anchor_data: Dictionary) -> float:
	var primary := _anchor_point(anchor_data, ["GripPrimary", "grip_primary"])
	var secondary := _anchor_point(anchor_data, ["GripSecondary", "grip_secondary"])
	return 0.0 if secondary == Vector2.INF else primary.distance_to(secondary)


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
