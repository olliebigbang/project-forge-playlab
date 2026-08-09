extends SceneTree

const LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")
const COMPILER := preload("res://scripts/combat_feel/melee_motion_compiler.gd")

const OVERRIDE_DIR := "res://artifacts/real_scale_poc/affordance_v1_3/%s/object_affordance_profile.json"


func _initialize() -> void:
	var loader: Variant = LOADER.new()
	var compiler: Variant = COMPILER.new()
	var targets := [
		["frying_pan", "recipe"],
		["shotgun_melee", "motion_grammar"],
		["giant_wooden_spoon", "live"],
		["old_mop", "recipe"],
	]
	print("object              cm     OFF      ON     diff")
	for target: Array in targets:
		var id := str(target[0])
		var kind := str(target[1])
		var loaded: Dictionary
		match kind:
			"recipe": loaded = loader.load_recipe_asset(id)
			"motion_grammar": loaded = loader.load_motion_grammar_asset(id)
			_: loaded = loader.load_frozen_live(id)
		if not bool(loaded.get("ok", false)):
			print("%-18s LOAD FAILED: %s" % [id, loaded.get("error", "?")])
			continue
		var asset: Variant = loaded.get("asset")
		var frozen: Resource = loaded.get("affordance_profile") as Resource
		var upgraded: Resource = loader.load_affordance_override(OVERRIDE_DIR % id)
		if frozen == null or upgraded == null:
			print("%-18s PROFILE MISSING" % id)
			continue
		var off_profile: Variant = compiler.compile(frozen, asset.anchors_dict(), asset.opaque_bounds)
		var on_profile: Variant = compiler.compile(upgraded, asset.anchors_dict(), asset.opaque_bounds)
		if off_profile is String or on_profile is String:
			print("%-18s COMPILE FAILED" % id)
			continue
		print("%-18s %4.0f  %6.1f  %6.1f  %+6.1f" % [
			id,
			upgraded.real_length_cm,
			off_profile.reach_pixels,
			on_profile.reach_pixels,
			on_profile.reach_pixels - off_profile.reach_pixels,
		])
	quit()
