class_name MeleeMotionCompiler
extends RefCounted

const PROFILE := preload("res://scripts/combat_feel/combat_motion_profile.gd")

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
	profile.motion_family = str(mapped[0])
	profile.contact_mode = str(mapped[1])
	profile.reach_class = _classify_reach(asset)
	profile.weight_class = _classify_weight(blueprint, asset)
	profile.tempo = {"light": "rapid", "medium": "balanced", "heavy": "committed"}.get(profile.weight_class, "balanced")
	profile.grip_mode = _classify_grip(blueprint, asset)
	profile.combo_style = {"sweep": "forward_reverse_finisher", "slam": "side_backhand_overhead", "thrust": "jab_drive_lunge"}.get(profile.motion_family, "alternating")
	profile.charge_style = {"sweep": "wide_commitment", "slam": "overhead_ground_impact", "thrust": "narrow_long_lunge"}.get(profile.motion_family, "wide_commitment")
	profile.dodge_attack_style = {"sweep": "sliding_sweep", "slam": "advancing_slap", "thrust": "dash_thrust"}.get(profile.motion_family, "advancing_strike")
	profile.configure_timing_from_tempo()
	profile.reach_pixels = {"short": 84.0, "medium": 108.0, "long": 138.0}.get(profile.reach_class, 108.0)
	return profile

func _classify_reach(asset: WeaponVisualAsset) -> String:
	if asset == null: return "medium"
	var strike_point := asset.tip if asset.tip != Vector2.ZERO else asset.muzzle
	var anchor_distance := asset.grip_primary.distance_to(strike_point)
	var major_axis := float(maxi(asset.opaque_bounds.size.x, asset.opaque_bounds.size.y))
	var bounded_score := clampf(anchor_distance * 0.68 + major_axis * 0.42, 24.0, 150.0)
	if bounded_score < 61.0: return "short"
	if bounded_score > 92.0: return "long"
	return "medium"

func _classify_weight(blueprint: WeaponBlueprint, asset: WeaponVisualAsset) -> String:
	var coverage := 0.0
	var body_area := 0.0
	if asset != null:
		body_area = float(asset.opaque_bounds.size.x * asset.opaque_bounds.size.y)
		coverage = body_area / maxf(1.0, float(asset.canvas_size.x * asset.canvas_size.y))
	var score := clampf(coverage * 1.5 + body_area / 15000.0, 0.0, 1.5)
	match blueprint.weight_class:
		"light": score -= 0.22
		"heavy": score += 0.28
	match blueprint.silhouette_mass_distribution:
		"front_heavy", "top_heavy": score += 0.12
		"thin", "minimal": score -= 0.10
	if score < 0.40: return "light"
	if score > 0.82: return "heavy"
	return "medium"

func _classify_grip(blueprint: WeaponBlueprint, asset: WeaponVisualAsset) -> String:
	if blueprint.grip_profile == "two_hand_rear": return "two_hand"
	if blueprint.grip_profile == "throwable_center": return "center"
	if asset != null and asset.grip_primary.distance_to(asset.grip_secondary) >= 15.0: return "two_hand"
	return "one_hand"
