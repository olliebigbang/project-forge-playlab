extends SceneTree

const CATALOG := preload("res://scripts/combat_feel/firearm_identity_catalog.gd")
const PIXEL_SCAFFOLD := preload("res://scripts/combat_feel/firearm_pixel_scaffold.gd")
const AXES := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")
const TILE_SIZE := Vector2i(384, 384)


func _initialize() -> void:
	var requested_directory := _argument_value("--firearm-output-dir=", "res://output/firearm-identity-v1")
	var output_directory := ProjectSettings.globalize_path(requested_directory) if requested_directory.begins_with("res://") or requested_directory.begins_with("user://") else requested_directory.simplify_path()
	if DirAccess.make_dir_recursive_absolute(output_directory) != OK:
		printerr("FIREARM_EXPORT_DIRECTORY_FAILED:%s" % output_directory)
		quit(1)
		return
	var contact_sheet := Image.create(TILE_SIZE.x * 2, TILE_SIZE.y * 2, false, Image.FORMAT_RGBA8)
	contact_sheet.fill(Color("101722"))
	var manifest_entries: Array[Dictionary] = []
	var profiles := CATALOG.all_profiles()
	for index: int in range(profiles.size()):
		var profile := profiles[index]
		var declaration := profile.get("declaration", {}) as Dictionary
		var source := str(declaration.get("source", ""))
		var built: Dictionary = PIXEL_SCAFFOLD.build(declaration, source)
		var image := built.get("image") as Image
		if not bool(built.get("ok", false)) or image == null:
			printerr("FIREARM_EXPORT_BUILD_FAILED:%s:%s" % [str(profile.get("id", "")), str(built.get("error", ""))])
			quit(1)
			return
		var profile_id := str(profile.get("id", ""))
		var sprite_path := output_directory.path_join("%s.png" % profile_id)
		if image.save_png(sprite_path) != OK:
			printerr("FIREARM_EXPORT_SAVE_FAILED:%s" % profile_id)
			quit(1)
			return
		var enlarged := image.duplicate()
		enlarged.resize(TILE_SIZE.x, TILE_SIZE.y, Image.INTERPOLATE_NEAREST)
		var tile_column := index % 2
		var tile_row := floori(float(index) / 2.0)
		var tile_position := Vector2i(tile_column * TILE_SIZE.x, tile_row * TILE_SIZE.y)
		contact_sheet.blend_rect(enlarged, Rect2i(Vector2i.ZERO, enlarged.get_size()), tile_position)
		var runtime: Dictionary = AXES.compile(declaration, source)
		manifest_entries.append({
			"id": profile_id,
			"canonical_name_zh": str(profile.get("canonical_name_zh", "")),
			"tile": [tile_column, tile_row],
			"sprite": sprite_path,
			"structure_axes": (built.get("contract", {}) as Dictionary).get("axes", {}),
			"anchors": (built.get("contract", {}) as Dictionary).get("anchors", {}),
			"runtime_matrix": {
				"automatic_fire": bool(runtime.get("automatic_fire", false)),
				"shot_interval_seconds": float(runtime.get("shot_interval_seconds", 0.0)),
				"recoil_pixels": float(runtime.get("recoil_pixels", 0.0)),
				"spread_velocity": float(runtime.get("spread_velocity", 0.0)),
				"magazine_size": int(runtime.get("magazine_size", 0)),
				"reload_seconds": float(runtime.get("reload_seconds", 0.0)),
			},
		})
	var contact_path := output_directory.path_join("contact_sheet.png")
	if contact_sheet.save_png(contact_path) != OK:
		printerr("FIREARM_EXPORT_CONTACT_SHEET_FAILED")
		quit(1)
		return
	var manifest := {
		"schema": "forge-firearm-acceptance-set-v1",
		"tile_order": "left-to-right, top-to-bottom",
		"entries": manifest_entries,
	}
	var manifest_file := FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE)
	if manifest_file == null:
		printerr("FIREARM_EXPORT_MANIFEST_FAILED")
		quit(1)
		return
	manifest_file.store_string(JSON.stringify(manifest, "  "))
	manifest_file.close()
	print("FIREARM_ACCEPTANCE_SET_EXPORTED:%s" % output_directory)
	quit(0)


func _argument_value(prefix: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return fallback
