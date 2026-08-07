extends SceneTree

const LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")
const COMPILER := preload("res://scripts/combat_feel/melee_motion_compiler.gd")
const OUTPUT_DIR := "res://data/combat_feel/live_assets/motion_grammar_slice_1a/recipes"


func _init() -> void:
	call_deferred("_export")


func _export() -> void:
	var loader: Variant = LOADER.new()
	var compiler: Variant = COMPILER.new()
	var output_absolute := ProjectSettings.globalize_path(OUTPUT_DIR)
	if DirAccess.make_dir_recursive_absolute(output_absolute) != OK:
		push_error("MOTION_GRAMMAR_RECIPE_OUTPUT_DIRECTORY_FAILED")
		quit(1)
		return
	for asset_id: String in loader.motion_grammar_asset_ids():
		var loaded: Dictionary = loader.load_motion_grammar_asset(asset_id)
		if not bool(loaded.get("ok", false)):
			push_error(str(loaded.get("error", "MOTION_GRAMMAR_ASSET_LOAD_FAILED")))
			quit(1)
			return
		var visual_asset := loaded.get("asset") as WeaponVisualAsset
		var affordance := loaded.get("affordance_profile") as Resource
		var profile: Variant = compiler.compile(affordance, visual_asset.anchors_dict(), visual_asset.opaque_bounds)
		if profile is String:
			push_error(str(profile))
			quit(1)
			return
		var payload := {
			"schema": "forge-motion-grammar-slice-1a-recipe-v1",
			"asset_id": asset_id,
			"source_round_id": str(loaded.get("source_round_id", "")),
			"developer_only": bool(loaded.get("developer_only", false)),
			"affordance_profile": affordance.to_dict(),
			"combo_recipe": profile.combo_recipe.to_dict(),
		}
		var target := ProjectSettings.globalize_path(OUTPUT_DIR.path_join("%s.json" % asset_id))
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			push_error("MOTION_GRAMMAR_RECIPE_WRITE_FAILED:%s" % asset_id)
			quit(1)
			return
		file.store_string(JSON.stringify(payload, "  ", false) + "\n")
		file.close()
		print("EXPORTED ", target)
	quit(0)
