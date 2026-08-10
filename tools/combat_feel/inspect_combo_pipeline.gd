extends SceneTree

## Is the three-hit combo a pipeline, or three unrelated swings?
##
## Prints, for each shipped object, which primitive each stage selects and how far it
## actually sweeps -- the angles printed here are the ones `_weapon_pose` lerps, so they
## are what the player sees.

const LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")
const COMPILER := preload("res://scripts/combat_feel/melee_motion_compiler.gd")

const OVERRIDE_DIR := "res://artifacts/mass_axis_poc/affordance_v1_4/%s/object_affordance_profile.json"


func _initialize() -> void:
	var loader: Variant = LOADER.new()
	var compiler: Variant = COMPILER.new()
	var carrier: Dictionary = loader.load_recipe_asset("frying_pan")
	if not bool(carrier.get("ok", false)):
		print("carrier failed: %s" % carrier.get("error", "?"))
		quit()
		return
	var asset: Variant = carrier.get("asset")

	print("   %-20s %-26s %-26s %s" % ["object", "hit_1", "hit_2", "hit_3"])
	for id: String in ["chicken_leg", "frying_pan", "old_mop", "giant_wooden_spoon", "shotgun_melee", "sledgehammer"]:
		var affordance: Resource = loader.load_affordance_override(OVERRIDE_DIR % id)
		if affordance == null:
			print("   %-20s SIDECAR MISSING" % id)
			continue
		var compiled: Variant = compiler.compile(affordance, asset.anchors_dict(), asset.opaque_bounds)
		if compiled is String:
			print("   %-20s COMPILE FAILED" % id)
			continue
		var recipe: Variant = compiled.combo_recipe
		print("   %-20s %-26s %-26s %s" % [
			id,
			_describe(recipe.hit_1),
			_describe(recipe.hit_2),
			_describe(recipe.hit_3),
		])
	print("")
	print("   arc is end_angle - start_angle in degrees; sign is the direction of rotation.")
	quit()


func _describe(primitive: Variant) -> String:
	if primitive == null:
		return "(none)"
	var arc := rad_to_deg(float(primitive.end_angle) - float(primitive.start_angle))
	return "%-6s %+7.0f° [%+.2f->%+.2f]" % [primitive.motion_family, arc, primitive.start_angle, primitive.end_angle]
