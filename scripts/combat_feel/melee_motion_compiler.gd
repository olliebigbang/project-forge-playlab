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

const UNSUPPORTED := "unsupported"
const HANDLE_LENGTHS: PackedStringArray = ["short", "medium", "long"]
const BODY_LENGTHS: PackedStringArray = ["short", "medium", "long"]
const MASS_DISTRIBUTIONS: PackedStringArray = ["rear", "balanced", "front"]
const CONTACT_SURFACES: PackedStringArray = ["point", "edge", "broad", "whole_body"]
const RIGIDITIES: PackedStringArray = ["rigid", "semi_rigid", "flexible"]


func compile(source: Variant, detail: Variant, alpha_bounds: Rect2i = Rect2i()) -> Variant:
	if source is WeaponBlueprint and detail is WeaponVisualAsset:
		return _compile_legacy(source as WeaponBlueprint, detail as WeaponVisualAsset)
	if source is Resource and detail is Dictionary:
		return _compile_affordance(source as Resource, detail as Dictionary, alpha_bounds)
	return UNSUPPORTED


func _compile_affordance(affordance_profile: Resource, anchor_data: Dictionary, alpha_bounds: Rect2i) -> Variant:
	if not _inputs_are_valid(affordance_profile, anchor_data, alpha_bounds):
		return UNSUPPORTED
	if _matches_short_front_broad(affordance_profile):
		return _compile_short_front_broad(affordance_profile, anchor_data, alpha_bounds)
	if _matches_long_broad(affordance_profile):
		return _compile_long_broad(affordance_profile, anchor_data, alpha_bounds)
	return UNSUPPORTED


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
	return recipe


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
