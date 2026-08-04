extends SceneTree

const RESOLVER := preload("res://scripts/systems/anchor_resolver.gd")

func _initialize() -> void:
	var output_root := _argument_value("--output-root=", "res://tools/comfyui/output")
	var cases_path := _argument_value("--cases=", "res://tools/comfyui/test_cases/cases.json")
	var absolute_root := ProjectSettings.globalize_path(output_root) if output_root.begins_with("res://") else output_root
	var absolute_cases := ProjectSettings.globalize_path(cases_path) if cases_path.begins_with("res://") else cases_path
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(absolute_cases))
	if not parsed is Dictionary:
		printerr("Invalid cases JSON")
		quit(2)
		return
	var case_map: Dictionary = {}
	for case_data: Dictionary in (parsed as Dictionary).get("cases", []):
		case_map[str(case_data.get("case_id", ""))] = case_data
	var written := 0
	for case_id: String in DirAccess.get_directories_at(absolute_root):
		if not case_map.has(case_id):
			continue
		var case_data: Dictionary = case_map[case_id]
		var blueprint := WeaponBlueprint.new()
		blueprint.id = "spike_%s" % case_id
		blueprint.behavior_family = str(case_data.get("behavior_family", "sustained_ranged"))
		blueprint.grip_profile = str(case_data.get("grip_profile", "rear_grip"))
		blueprint.validate_and_repair()
		var case_directory := absolute_root.path_join(case_id)
		for run_id: String in DirAccess.get_directories_at(case_directory):
			var run_directory := case_directory.path_join(run_id)
			var manifest_path := run_directory.path_join("manifest.json")
			if not FileAccess.file_exists(manifest_path):
				continue
			var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
			if not manifest is Dictionary or str((manifest as Dictionary).get("status", "")) != "success":
				continue
			var image := Image.load_from_file(run_directory.path_join("processed_sprite.png"))
			if image == null or image.get_size() != Vector2i(96, 96):
				continue
			var asset: WeaponVisualAsset = RESOLVER.resolve(image, blueprint)
			if asset == null:
				continue
			var anchors := {
				"GripPrimary": [roundi(asset.grip_primary.x), roundi(asset.grip_primary.y)],
				"GripSecondary": [roundi(asset.grip_secondary.x), roundi(asset.grip_secondary.y)],
				"Muzzle": [roundi(asset.muzzle.x), roundi(asset.muzzle.y)],
				"EffectOrigin": [roundi(asset.muzzle.x), roundi(asset.muzzle.y)],
				"Tip": [roundi(asset.tip.x), roundi(asset.tip.y)],
				"SpinPivot": [roundi(asset.spin_pivot.x), roundi(asset.spin_pivot.y)],
				"confidence": asset.anchor_confidence,
				"anchor_source": asset.anchor_source
			}
			var file := FileAccess.open(run_directory.path_join("anchors.json"), FileAccess.WRITE)
			if file != null:
				file.store_string(JSON.stringify(anchors, "  "))
				written += 1
	print("ANCHORS_WRITTEN=%d" % written)
	quit(0)

func _argument_value(prefix: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return fallback
