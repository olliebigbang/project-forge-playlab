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

func compile(blueprint: WeaponBlueprint, asset: WeaponVisualAsset) -> Resource:
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
	profile.combo_recipe = _compile_combo_recipe(profile.motion_family)
	return profile

func _compile_combo_recipe(base_family: String) -> Resource:
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

func _resolve_motion_family(mapped_family: String, contact_bulk: float) -> String:
	# A semantic strike point is not automatically a stabbing tip. A broad,
	# alpha-backed contact region swings; only a genuinely narrow tip thrusts.
	if mapped_family == "thrust" and contact_bulk >= 0.24:
		return "sweep"
	return mapped_family

func _classify_reach(asset: WeaponVisualAsset) -> String:
	if asset == null: return "medium"
	var strike_point := asset.tip if asset.tip != Vector2.ZERO else asset.muzzle
	var anchor_distance := asset.grip_primary.distance_to(strike_point)
	var major_axis := float(maxi(asset.opaque_bounds.size.x, asset.opaque_bounds.size.y))
	var bounded_score := clampf(anchor_distance * 0.68 + major_axis * 0.42, 24.0, 150.0)
	if bounded_score < 61.0: return "short"
	if bounded_score > 88.0: return "long"
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
	if score < 0.40: return "light"
	if score > 0.82: return "heavy"
	return "medium"

func _classify_tempo(profile: Resource) -> String:
	# Short compact objects recover quickly; long sparse objects retain control
	# without inheriting the same commitment as a long, visibly massive object.
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
	if profile.motion_family == "thrust": return 22.0
	if profile.motion_family == "slam": return 92.0
	var arc := 145.0
	if profile.reach_class == "long": arc += 24.0
	if profile.silhouette_fill_ratio < 0.20: arc += 18.0
	return clampf(arc, 120.0, 190.0)

func _hitbox_thickness(profile: Resource) -> float:
	if profile.motion_family == "thrust": return 42.0
	if profile.motion_family == "slam": return 58.0
	return 48.0 + (10.0 if profile.reach_class == "long" else 0.0)

func _control_strength(profile: Resource) -> float:
	var value := 1.0
	if profile.motion_family == "sweep": value += 0.16
	if profile.reach_class == "long": value += 0.12
	if profile.silhouette_fill_ratio < 0.20: value += 0.14
	return clampf(value, 0.85, 1.42)

func _impact_sharpness(profile: Resource) -> float:
	var value := 1.0
	if profile.reach_class == "short": value += 0.22
	if profile.contact_mode == "whole_body": value += 0.12
	if profile.tempo == "committed": value -= 0.08
	return clampf(value, 0.82, 1.34)

func _classify_grip(blueprint: WeaponBlueprint, asset: WeaponVisualAsset) -> String:
	if blueprint.grip_profile == "two_hand_rear": return "two_hand"
	if blueprint.grip_profile == "throwable_center": return "center"
	if asset != null and asset.grip_primary.distance_to(asset.grip_secondary) >= 15.0: return "two_hand"
	return "one_hand"
