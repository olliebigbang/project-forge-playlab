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

# Set false to restore the pre-v1.3 reach formula exactly. This is the A/B switch for
# playtesting: with it off, reach is driven by the three-value length ordinal, so any two
# objects sharing a bucket get identical reach -- old_mop and giant_wooden_spoon both
# compiled to 139.5 despite being 140cm and 120cm. With it on, reach follows the object's
# real length. Profiles without a real length (pre-v1.3) take the old path either way.
const USE_REAL_LENGTH_REACH := true

# Maps real centimetres onto the reach envelope the rest of the game already assumes, so
# the A/B comparison is about which objects differ from each other rather than about a
# global range change: 45cm lands at 85px and 140cm at 137px, inside the 84..138 band
# tests/test_combat_feel_slice_0.gd asserts.
const REACH_CM_BASE := 60.4
const REACH_CM_SLOPE := 0.547

# Set false to restore the pre-v1.3 render scale. Separate from the reach switch so the
# two can be judged independently in a playtest -- reach moves an invisible hitbox, this
# is the one the player actually sees.
#
# Why this is what makes real scale visible: every source sprite is the same length in
# its own frame (all four measure 86px), and the old scale came from the same three-value
# ordinal as reach, so giant_wooden_spoon and old_mop both drew at exactly 1.180. Same
# image, same multiplier, pixel-identical result -- the reach change was real but nothing
# on screen could show it. Scaling by real length reproduces what correctly-proportioned
# sprites would look like, without needing new sprites or re-derived anchors, because the
# grip anchors are already multiplied by render_scale downstream.
const USE_REAL_LENGTH_RENDER_SCALE := true

# old_mop keeps the scale it has today; everything else lands in proportion to it.
const RENDER_SCALE_REFERENCE_CM := 140.0
const RENDER_SCALE_AT_REFERENCE := 1.18

# Straight proportionality is physically honest and reads badly: a 45cm pan drew at 33px
# against a ~90px character and looked like a toy. Compressing by this exponent keeps the
# ordering strictly monotonic while pulling the short end up.
#
# It also fixes a second problem rather than trading against it. Reach is affine
# (a constant plus a term in cm), so a strictly proportional drawing diverged from it at
# the short end -- reach/drawn ran 1.35 for the mop and 2.61 for the pan, meaning the pan
# struck from well beyond its visible tip. Under the square root the same ratios sit
# inside 1.34-1.48, because a root is the right shape to track an affine curve here.
const RENDER_SCALE_LENGTH_EXPONENT := 0.5
# Legibility bounds only. This re-introduces the ceiling problem for extreme objects, the
# same way the reach clamp does: a 400cm object cannot draw 3.4x without filling the
# arena, so beyond these bounds length stops being visible again.
const RENDER_SCALE_MIN := 0.30
const RENDER_SCALE_MAX := 2.00

# Set false to restore the pre-v1.4 mass axis exactly. This is the A/B switch for
# playtesting, matching the two length switches above: with it off, the axis is driven by
# `mass_distribution`, which records where the weight sits and not how much of it there
# is -- so all four shipped objects read `front` or carry a stock, three of four compile
# to a mass axis of exactly 1.0, and a chicken leg swings slower than a sledgehammer
# because a drumstick is front-heavy. With it on, the axis follows the object's real mass.
# Profiles without a real mass (pre-v1.4) take the old path either way.
const USE_REAL_MASS_AXIS := true

# Set false to restore the pre-v1.4 weight class. Separate from the axis switch so the
# two can be judged independently: the axis moves timing and impact continuously, while
# this picks one of three labels that other systems branch on.
const USE_REAL_MASS_WEIGHT_CLASS := true

# The band is the one the three-value ordinal already spanned (rear 0.35 .. front 1.0),
# kept deliberately. Every downstream consumer is tuned against it -- the tempo
# thresholds, startup and recovery, knockback, stagger, hitstop and camera kick -- so real
# mass changes which object lands where inside the band, never how wide the band is. That
# is decision P08's middle layer: the real quantity fixes the ordering, game design fixes
# the usable range, and neither one gets to move the other.
const MASS_AXIS_MIN := 0.35
const MASS_AXIS_MAX := 1.00

# Ends of the compression curve, in kilograms, read off the probed object set: a chicken
# leg sits on the floor and a full fire extinguisher on the ceiling. Everything the game
# realistically sees lands between them.
const MASS_AXIS_FLOOR_KG := 0.15
const MASS_AXIS_CEILING_KG := 8.0

# Set false to restore the pre-commitment cancel window exactly. Same A/B shape as the
# length and mass switches above. Profiles without a real mass take the old path either
# way, so every frozen asset keeps the 0.38 it has today.
const USE_REAL_MASS_COMMITMENT := true

# The value every object in the game shared before this axis existed.
const EARLY_CANCEL_DEFAULT := 0.38

# How far into the startup a dodge still calls the swing off. The free end is deliberately
# generous: a light one-hand object should be usable as a probe, thrown out to see what the
# enemy does and taken back when the answer is bad. The locked end is not zero, because a
# window of exactly zero reads as an input drop rather than as weight.
const EARLY_CANCEL_FREE := 0.78
const EARLY_CANCEL_LOCKED := 0.04

# How much of the player is behind the swing, which mass alone cannot say. The same 5kg
# is a different commitment braced in one hand than swung on a two-hand shaft.
const COMMITMENT_GRIP_COUPLING := {
	"one_hand_handle": 0.00,
	"clamp_grip": 0.10,
	"two_hand_handle": 0.30,
	"body_grip": 0.42,
}

# Boundaries for the three-value label, in kilograms. Below the first is something you
# flick, above the second is something you heave.
const WEIGHT_CLASS_LIGHT_MAX_KG := 0.5
const WEIGHT_CLASS_HEAVY_MIN_KG := 3.0
const HANDLE_LENGTHS: PackedStringArray = ["none", "short", "medium", "long"]
const BODY_LENGTHS: PackedStringArray = ["short", "medium", "long"]
const GRIP_TOPOLOGIES: PackedStringArray = ["one_hand_handle", "two_hand_handle", "body_grip", "clamp_grip"]
const MASS_DISTRIBUTIONS: PackedStringArray = ["rear", "balanced", "front"]
const CONTACT_SURFACES: PackedStringArray = ["point", "edge", "broad", "whole_body"]
const SECONDARY_CONTACT_SURFACES: PackedStringArray = ["none", "point", "edge", "broad", "whole_body"]
const RIGIDITIES: PackedStringArray = ["rigid", "semi_rigid", "flexible"]
const PRIMITIVE_ORDER: PackedStringArray = ["bash", "sweep", "thrust", "slam", "spin"]


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
	var used: Array[String] = []
	var selected := {}
	for stage: String in ["hit_1", "hit_2", "hit_3", "charge", "dodge"]:
		var family := _select_primitive(base_scores, stage, used, affordance_profile)
		selected[stage] = family
		if stage.begins_with("hit_"):
			used.append(family)
	var recipe: Variant = RECIPE.new()
	recipe.compile_reason = "orthogonal affordance composition: %s" % JSON.stringify(_mechanism_axes(affordance_profile))
	recipe.mechanism_axes = _mechanism_axes(affordance_profile)
	recipe.primitive_scores = base_scores.duplicate(true)
	recipe.hit_1 = _synthesize_primitive(str(selected["hit_1"]), "hit_1", affordance_profile)
	recipe.hit_2 = _synthesize_primitive(str(selected["hit_2"]), "hit_2", affordance_profile)
	recipe.hit_3 = _synthesize_primitive(str(selected["hit_3"]), "hit_3", affordance_profile)
	recipe.charge_attack = _synthesize_primitive(str(selected["charge"]), "charge", affordance_profile)
	recipe.dodge_attack = _synthesize_primitive(str(selected["dodge"]), "dodge", affordance_profile)
	profile.combo_recipe = recipe
	profile.motion_family = _legacy_family(str(selected["charge"]))
	profile.reach_class = _reach_class(affordance_profile)
	profile.weight_class = _weight_class(affordance_profile)
	profile.tempo = _tempo_for_axes(affordance_profile)
	profile.contact_resolution = _contact_resolution(affordance_profile)
	profile.contact_mode = _legacy_contact_mode(affordance_profile.contact_surface)
	profile.combo_style = "orthogonal_per_hit"
	profile.charge_style = str(selected["charge"])
	profile.dodge_attack_style = str(selected["dodge"])
	profile.configure_timing_from_tempo()
	profile.early_startup_cancel_ratio = _early_startup_cancel_ratio(affordance_profile)
	profile.reach_pixels = _general_reach(affordance_profile, anchor_data, alpha_bounds)
	profile.swing_arc_degrees = _general_arc(affordance_profile)
	profile.hitbox_thickness = _general_hitbox_thickness(affordance_profile)
	profile.control_strength = _general_control_strength(affordance_profile)
	profile.impact_sharpness = _general_impact_sharpness(affordance_profile)
	profile.render_scale = _general_render_scale(affordance_profile)
	profile.mechanism_axes = recipe.mechanism_axes.duplicate(true)
	profile.primitive_scores = recipe.primitive_scores.duplicate(true)
	profile.compile_trace = {
		"composer": "orthogonal_affordance_v1",
		"selected": selected.duplicate(true),
		"identity_inputs_used": false,
		"silhouette_grip_inertia_proxy_raw": profile.silhouette_grip_inertia_proxy_raw,
		"anchor_source": anchor_data.get("anchor_sources", {}).duplicate(true),
		"auto_anchor_source": anchor_data.get("auto_anchor_source", {}).duplicate(true),
		"auto_confidence": anchor_data.get("auto_confidence", {}).duplicate(true),
		"confirmation_status": anchor_data.get("confirmation_status", {}).duplicate(true),
	}
	return profile


func _score_primitives(affordance_profile: Resource) -> Dictionary:
	var scores := {"bash": 0.0, "sweep": 0.0, "thrust": 0.0, "slam": 0.0, "spin": 0.0}
	_apply_contact_scores(scores, affordance_profile.contact_surface, 1.0)
	if affordance_profile.secondary_contact_surface != "none":
		_apply_contact_scores(scores, affordance_profile.secondary_contact_surface, 0.32)
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
	match affordance_profile.mass_distribution:
		"front": _add_scores(scores, {"slam": 0.95, "bash": 0.55})
		"rear": _add_scores(scores, {"bash": 0.85, "thrust": 0.20})
		"balanced": _add_scores(scores, {"sweep": 0.45, "thrust": 0.40, "spin": 0.20})
	match affordance_profile.grip_topology:
		"two_hand_handle": _add_scores(scores, {"sweep": 0.45, "thrust": 0.40, "slam": 0.30})
		"body_grip": _add_scores(scores, {"spin": 0.55, "bash": 0.45})
		"clamp_grip": _add_scores(scores, {"bash": 0.60, "slam": 0.30})
	if affordance_profile.has_point: _add_scores(scores, {"thrust": 0.85})
	if affordance_profile.has_edge: _add_scores(scores, {"sweep": 0.85})
	if affordance_profile.has_broad_face: _add_scores(scores, {"bash": 0.80, "slam": 0.45})
	if affordance_profile.has_barrel: _add_scores(scores, {"thrust": 0.75})
	if affordance_profile.has_stock: _add_scores(scores, {"bash": 0.90})
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
		if affordance_profile.has_stock:
			# A stock is itself a usable structural rear contact. A separately
			# declared secondary surface may refine its breadth, but is not required
			# to make the stock mechanically real.
			scores["bash"] = float(scores["bash"]) + 2.70
	var selected := PRIMITIVE_ORDER[0]
	var selected_score := -INF
	for family: String in PRIMITIVE_ORDER:
		var score := float(scores[family])
		if score > selected_score:
			selected = family
			selected_score = score
	return selected


func _synthesize_primitive(family: String, stage: String, affordance_profile: Resource) -> Resource:
	var angle_data: Array = {
		"bash": [-0.62, 0.30], "sweep": [-1.28, 1.10], "thrust": [-0.06, -0.06],
		"slam": [-1.82, 1.04], "spin": [-2.85, 3.25],
	}[family]
	if stage == "hit_2" and family in ["bash", "sweep"]:
		# Retrace the opening arc backwards: start where it ended, end where it began.
		# Negating the start instead of swapping to it kept the rotation going the same
		# way over a stub of the original span -- bash covered 18 degrees against the
		# opener's 53, sweep 10 against 136 -- so `forward_reverse_finisher` never had a
		# reverse in it, and no object in the game ever swung back.
		angle_data = [float(angle_data[1]), float(angle_data[0])]
	var length_axis := _length_axis(affordance_profile)
	var mass_axis := _mass_axis(affordance_profile)
	var stage_weight: float = {"hit_1": 0.84, "hit_2": 1.00, "hit_3": 1.20, "charge": 1.12, "dodge": 1.28}[stage]
	var startup: float = (0.88 + mass_axis * 0.16) * float({"hit_1": 0.88, "hit_2": 0.96, "hit_3": 1.18, "charge": 1.30, "dodge": 0.72}[stage])
	var recovery: float = (0.86 + mass_axis * 0.20) * float({"hit_1": 0.88, "hit_2": 0.98, "hit_3": 1.24, "charge": 1.32, "dodge": 0.78}[stage])
	var clamp_grip: bool = affordance_profile.grip_topology == "clamp_grip"
	if clamp_grip:
		# Clamp grips favor a short, restrained commitment without enlarging the
		# object's physical contact geometry.
		startup *= 0.94
		recovery *= 0.96
	var contact_anchor := _contact_anchor_for(family, stage, affordance_profile)
	var active_surface: String = affordance_profile.contact_surface
	if contact_anchor == "rear_contact":
		active_surface = affordance_profile.secondary_contact_surface \
			if affordance_profile.secondary_contact_surface != "none" else "broad"
	var contact_width: float = {"point": 0.66, "edge": 0.88, "broad": 1.18, "whole_body": 1.28}[active_surface]
	var root_distance: float = (5.0 + length_axis * 16.0 + (7.0 if affordance_profile.has_barrel else 0.0)) * stage_weight
	var extension: float = (24.0 + 22.0 * length_axis) if family == "thrust" else 0.0
	var movement_allowed := clampf((0.06 + 0.10 * length_axis) if family in ["sweep", "spin"] else 0.04, 0.0, 0.30)
	if clamp_grip:
		movement_allowed *= 0.85
	var finisher := 1.0 if stage not in ["hit_3", "charge"] else 1.22
	return _primitive(family, float(angle_data[0]), float(angle_data[1]), extension, startup, 1.0 + 0.08 * mass_axis, recovery, 0.84 + 0.28 * length_axis, 0.78 + 0.28 * length_axis, 0.86 + 0.20 * contact_width, {
		"contact_anchor": contact_anchor,
		"root_motion_distance": root_distance,
		"hitbox_width_multiplier": contact_width,
		"hitbox_length_multiplier": 0.82 + 0.30 * length_axis,
		"knockback_multiplier": (0.88 + 0.18 * mass_axis) * finisher,
		"stagger_multiplier": (0.90 + 0.20 * mass_axis) * finisher,
		"hitstop_multiplier": (0.82 + 0.22 * mass_axis) * finisher,
		"camera_kick_multiplier": (0.84 + 0.20 * mass_axis) * finisher,
		"movement_allowed_ratio": movement_allowed,
	})


func _contact_anchor_for(family: String, stage: String, affordance_profile: Resource) -> String:
	if family == "spin" or affordance_profile.contact_surface == "whole_body":
		return "whole_body"
	if family == "bash" and stage in ["hit_3", "charge"] and affordance_profile.has_stock:
		return "rear_contact"
	if family == "thrust" and affordance_profile.has_barrel:
		return "muzzle"
	return "tip"


func _mechanism_axes(affordance_profile: Resource) -> Dictionary:
	return affordance_profile.to_dict()


func _length_axis(affordance_profile: Resource) -> float:
	var values := {"none": 0.0, "short": 0.22, "medium": 0.58, "long": 1.0}
	return (float(values[affordance_profile.handle_length]) + float(values[affordance_profile.body_length])) * 0.5


func _mass_axis(affordance_profile: Resource) -> float:
	if USE_REAL_MASS_AXIS and affordance_profile.has_real_mass():
		# How heavy the object is, not where its weight sits. The two are independent,
		# and only the second was ever available here.
		return _mass_axis_from_kg(float(affordance_profile.real_mass_kg))
	# Mass closer to the grip reduces rotational commitment and delivered contact
	# force; mass farther forward increases both. Keep this ordering independent
	# of identity, selected Primitive, and any retained sample Recipe.
	return {"rear": 0.35, "balanced": 0.55, "front": 1.0}[affordance_profile.mass_distribution]


## Compress real kilograms onto the axis band the rest of the compiler is tuned against.
##
## Logarithmic, not proportional, and this is the axis where that matters most. Legal
## masses span a thousandfold and the objects actually drawn span about fiftyfold, while
## the band they feed spans 2.9x. Straight proportionality would pin everything under a
## kilogram to the floor and everything over three to the ceiling, leaving the middle --
## where nearly every hand weapon lives -- flat. That is the failure P07 caught on the
## length axis, where a proportional render scale drew the 45cm pan at 33px and had to
## become a square root. A root is not enough compression for a span this wide.
func _mass_axis_from_kg(mass_kg: float) -> float:
	var floor_log := log(MASS_AXIS_FLOOR_KG)
	var span := log(MASS_AXIS_CEILING_KG) - floor_log
	var position := clampf((log(maxf(mass_kg, MASS_AXIS_FLOOR_KG * 0.01)) - floor_log) / span, 0.0, 1.0)
	return MASS_AXIS_MIN + position * (MASS_AXIS_MAX - MASS_AXIS_MIN)


## How much of the startup is still the player's to take back.
##
## This is a different question from tempo, and the compiler could not previously answer
## it at all: `early_startup_cancel_ratio` sat at its 0.38 default for every object the
## player could draw, so a chicken leg and a sledgehammer were equally irrevocable.
##
## Kept orthogonal to tempo on purpose. Tempo is length plus mass; commitment is mass plus
## *grip*, and grip_topology appears nowhere in `_tempo_for_axes`. Two objects that swing
## for the same duration can therefore still differ in whether the swing can be called off,
## which is what makes this an axis rather than a second reading of the first one.
func _early_startup_cancel_ratio(affordance_profile: Resource) -> float:
	if not (USE_REAL_MASS_COMMITMENT and affordance_profile.has_real_mass()):
		return EARLY_CANCEL_DEFAULT
	return lerpf(EARLY_CANCEL_FREE, EARLY_CANCEL_LOCKED, _commitment(affordance_profile))


## 0 = a swing your wrist can stop, 1 = a swing your whole body is already inside.
##
## Mass says how much momentum is going into it; grip says how much of you is behind it.
## A 5kg head on a two-hand shaft commits the body, while the same 5kg braced in one hand
## is still a wrist away from being abandoned.
func _commitment(affordance_profile: Resource) -> float:
	var from_mass := (_mass_axis(affordance_profile) - MASS_AXIS_MIN) / (MASS_AXIS_MAX - MASS_AXIS_MIN)
	var from_grip: float = COMMITMENT_GRIP_COUPLING[affordance_profile.grip_topology]
	return clampf(from_mass + from_grip, 0.0, 1.0)


func _reach_class(affordance_profile: Resource) -> String:
	var axis := _length_axis(affordance_profile)
	return "short" if axis < 0.38 else ("long" if axis > 0.78 else "medium")


func _weight_class(affordance_profile: Resource) -> String:
	if USE_REAL_MASS_WEIGHT_CLASS and affordance_profile.has_real_mass():
		var mass_kg: float = float(affordance_profile.real_mass_kg)
		if mass_kg < WEIGHT_CLASS_LIGHT_MAX_KG:
			return "light"
		return "heavy" if mass_kg >= WEIGHT_CLASS_HEAVY_MIN_KG else "medium"
	# Pre-v1.4: "front-weighted" and "has a stock" were the only mass signals available,
	# and neither is a quantity -- every shipped object satisfies one of them.
	if affordance_profile.mass_distribution == "front" or affordance_profile.has_stock:
		return "heavy"
	if affordance_profile.rigidity == "flexible":
		return "light"
	return "medium"


# Material alone, with no mass threshold: P15 measured that a threshold resolves none of
# the collisions rigidity leaves, and that no balanced one clears P09's noise floor.
func _contact_resolution(affordance_profile: Resource) -> String:
	return {
		"rigid": "arrest", "semi_rigid": "follow_through", "flexible": "rebound",
	}[affordance_profile.rigidity]


func _tempo_for_axes(affordance_profile: Resource) -> String:
	var axis := _length_axis(affordance_profile) + _mass_axis(affordance_profile)
	return "rapid" if axis < 0.85 else ("committed" if axis > 1.55 else "balanced")


func _legacy_family(family: String) -> String:
	return {"bash": "slam", "slam": "slam", "thrust": "thrust", "sweep": "sweep", "spin": "sweep"}[family]


func _legacy_contact_mode(surface: String) -> String:
	return {"point": "point", "edge": "edge", "broad": "whole_body", "whole_body": "whole_body"}[surface]


func _general_reach(affordance_profile: Resource, anchor_data: Dictionary, alpha_bounds: Rect2i) -> float:
	# A protruding point remains mechanically legible even when it does not win
	# the discrete Primitive selection for this particular structure.
	var point_extension := 4.0 if affordance_profile.has_point else 0.0
	if USE_REAL_LENGTH_REACH and affordance_profile.has_real_length():
		# Reach is a property of the object, not of which bucket it landed in.
		var from_length: float = REACH_CM_BASE + REACH_CM_SLOPE * float(affordance_profile.real_length_cm)
		return clampf(from_length + point_extension, 72.0, 148.0)
	var axis := _length_axis(affordance_profile)
	var measured := _strike_span(anchor_data) * 0.48 + float(maxi(alpha_bounds.size.x, alpha_bounds.size.y)) * 0.56
	return clampf(68.0 + 66.0 * axis + measured * 0.12 + point_extension, 72.0, 148.0)


func _general_render_scale(affordance_profile: Resource) -> float:
	if USE_REAL_LENGTH_RENDER_SCALE and affordance_profile.has_real_length():
		var length_cm: float = float(affordance_profile.real_length_cm)
		var ratio: float = pow(length_cm / RENDER_SCALE_REFERENCE_CM, RENDER_SCALE_LENGTH_EXPONENT)
		return clampf(RENDER_SCALE_AT_REFERENCE * ratio, RENDER_SCALE_MIN, RENDER_SCALE_MAX)
	return 1.10 + 0.08 * _length_axis(affordance_profile)


func _general_arc(affordance_profile: Resource) -> float:
	var surface_bonus: float = {"point": -70.0, "edge": 28.0, "broad": 6.0, "whole_body": 58.0}[affordance_profile.contact_surface]
	# Rigidity and an available edge alter the usable rotational envelope without
	# forcing the selected Primitive to cross an argmax boundary.
	var rigidity_bonus: float = {"rigid": 0.0, "semi_rigid": 8.0, "flexible": 18.0}[affordance_profile.rigidity]
	var edge_bonus := 10.0 if affordance_profile.has_edge else 0.0
	return clampf(112.0 + 42.0 * _length_axis(affordance_profile) + surface_bonus + rigidity_bonus + edge_bonus, 22.0, 220.0)


func _general_hitbox_thickness(affordance_profile: Resource) -> float:
	var thickness: float = {"point": 36.0, "edge": 44.0, "broad": 58.0, "whole_body": 66.0}[affordance_profile.contact_surface]
	# A broad face remains visible in collision breadth even when the same
	# Primitive still wins.
	if affordance_profile.has_broad_face:
		thickness += 5.0
	return thickness


func _general_control_strength(affordance_profile: Resource) -> float:
	var strength := 1.22 if affordance_profile.contact_surface == "whole_body" else (1.08 if affordance_profile.body_length == "long" else 0.92)
	# A secondary usable surface contributes continuously to displacement and
	# control. It does not select an identity-specific move or require a named
	# rear-contact special case.
	strength += float({"none": 0.0, "point": 0.02, "edge": 0.04, "broad": 0.07, "whole_body": 0.10}[affordance_profile.secondary_contact_surface])
	return clampf(strength, 0.85, 1.42)


func _general_impact_sharpness(affordance_profile: Resource) -> float:
	return {"point": 1.22, "edge": 1.16, "broad": 1.08, "whole_body": 0.92}[affordance_profile.contact_surface]


func _base_profile(affordance_profile: Resource, anchor_data: Dictionary, alpha_bounds: Rect2i) -> Resource:
	var profile: Variant = PROFILE.new()
	var bounds_area := float(alpha_bounds.size.x * alpha_bounds.size.y)
	profile.silhouette_fill_ratio = bounds_area / (96.0 * 96.0)
	profile.silhouette_grip_inertia_proxy_raw = float(anchor_data.get("silhouette_grip_inertia_proxy_raw", 0.0))
	profile.contact_bulk_ratio = {"point": 0.18, "edge": 0.30, "broad": 0.52, "whole_body": 0.62}[affordance_profile.contact_surface]
	profile.grip_mode = "two_hand" if affordance_profile.grip_topology == "two_hand_handle" or _grip_span(anchor_data) >= 15.0 else ("center" if affordance_profile.handle_length == "none" else "one_hand")
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
	hitbox_multiplier: float,
	extras: Dictionary = {}
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
