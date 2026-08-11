extends SceneTree

## Which axes can actually change which motions the combo selects?
##
## The existing axis-causality audit asks "does varying this axis change anything in the
## compiled profile", and almost everything answers yes, because nearly every axis feeds
## some multiplier. This asks the narrower question that T77 turns on: can the axis change
## *which three motions you swing*, or only how hard they land?
##
## Method is a single-axis sweep from a real baseline. Every legal alternative value for
## one field is compiled on its own, with everything else held, and the resulting
## (hit_1, hit_2, hit_3) family triple recorded.

const AFFORDANCE := preload("res://scripts/combat_feel/object_affordance_profile.gd")
const COMPILER := preload("res://scripts/combat_feel/melee_motion_compiler.gd")
const LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")

const SIDECAR := "res://artifacts/mass_axis_poc/affordance_v1_4/%s/object_affordance_profile.json"

const SWEEPS := {
	"contact_surface": ["point", "edge", "broad", "whole_body"],
	"secondary_contact_surface": ["none", "point", "edge", "broad", "whole_body"],
	"handle_length": ["none", "short", "medium", "long"],
	"body_length": ["short", "medium", "long"],
	"grip_topology": ["one_hand_handle", "two_hand_handle", "body_grip", "clamp_grip"],
	"rigidity": ["rigid", "semi_rigid", "flexible"],
	"mass_distribution": ["rear", "balanced", "front"],
	"has_point": [false, true],
	"has_edge": [false, true],
	"has_broad_face": [false, true],
	"has_barrel": [false, true],
	"has_stock": [false, true],
	"real_mass_kg": [0.12, 0.7, 2.5, 5.0],
	"real_length_cm": [13.0, 45.0, 100.0, 200.0],
}

var anchors: Dictionary
var bounds: Rect2i


func _initialize() -> void:
	var loader: Variant = LOADER.new()
	var carrier: Dictionary = loader.load_recipe_asset("frying_pan")
	if not bool(carrier.get("ok", false)):
		print("carrier failed")
		quit()
		return
	var asset: Variant = carrier.get("asset")
	anchors = asset.anchors_dict()
	bounds = asset.opaque_bounds

	for baseline_id: String in ["frying_pan", "old_mop", "shotgun_melee"]:
		_sweep_from(loader.load_affordance_override(SIDECAR % baseline_id), baseline_id)
	quit()


func _sweep_from(baseline: Resource, label: String) -> void:
	if baseline == null:
		print("%s: sidecar missing" % label)
		return
	var base_combo := _combo(baseline)
	print("")
	print("BASELINE %s -> %s" % [label, base_combo])
	print("   %-28s %8s %10s   %s" % ["axis", "legal", "distinct", "combos reachable by moving this axis alone"])
	for field: String in SWEEPS:
		var seen: Dictionary = {}
		var legal := 0
		for value: Variant in SWEEPS[field]:
			var candidate: Resource = baseline.duplicate()
			candidate.set(field, value)
			if not candidate.validation_errors().is_empty():
				continue
			var combo := _combo(candidate)
			if combo.is_empty():
				continue
			legal += 1
			seen[combo] = true
		var names: Array = seen.keys()
		names.sort()
		var marker := "  <-- moves selection" if names.size() > 1 else ""
		print("   %-28s %8d %10d   %s%s" % [field, legal, names.size(), ", ".join(names), marker])


func _combo(affordance: Resource) -> String:
	var compiled: Variant = COMPILER.new().compile(affordance, anchors, bounds)
	if compiled is String or compiled.combo_recipe == null:
		return ""
	var recipe: Variant = compiled.combo_recipe
	return "%s/%s/%s" % [
		recipe.hit_1.motion_family, recipe.hit_2.motion_family, recipe.hit_3.motion_family,
	]
