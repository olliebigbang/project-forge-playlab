extends SceneTree

const AI_RESOLVER := preload("res://scripts/combat_feel/firearm_identity_ai_resolver.gd")
const INTERPRETER := preload("res://scripts/services/open_identity_interpreter.gd")
const PIXEL_SCAFFOLD := preload("res://scripts/combat_feel/firearm_pixel_scaffold.gd")
const RANGED_AXES := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")


func _initialize() -> void:
	var output_root := _argument_value("--result-root=", "")
	var persist_cache := _argument_value("--persist-cache=", "false").to_lower() == "true"
	if output_root.is_empty():
		printerr("FIREARM_AI_LIVE_RESULT_ROOT_MISSING")
		quit(1)
		return
	if output_root.begins_with("res://") or output_root.begins_with("user://"):
		output_root = ProjectSettings.globalize_path(output_root)
	if not DirAccess.dir_exists_absolute(output_root):
		printerr("FIREARM_AI_LIVE_RESULT_ROOT_INVALID")
		quit(1)
		return
	var interpreter: WeaponInterpreter = INTERPRETER.new()
	var records: Array[Dictionary] = []
	var unexpected_failures := 0
	var directories := DirAccess.get_directories_at(output_root)
	directories.sort()
	for directory: String in directories:
		var case_directory := output_root.path_join(directory)
		var result_path := case_directory.path_join("result.json")
		if not FileAccess.file_exists(result_path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(result_path))
		if not parsed is Dictionary:
			records.append({"case": directory, "ok": false, "error": "RESULT_INVALID_JSON"})
			unexpected_failures += 1
			continue
		var bridge_result := parsed as Dictionary
		if str(bridge_result.get("status", "")) != "success" or not bridge_result.get("response", {}) is Dictionary:
			records.append({"case": directory, "ok": false, "error": str(bridge_result.get("failure_reason", "BRIDGE_FAILED"))})
			unexpected_failures += 1
			continue
		var response := bridge_result.get("response", {}) as Dictionary
		var identity := str(response.get("requested_identity", ""))
		var classification := str(response.get("classification", ""))
		var source := str(bridge_result.get("source", ""))
		var accepted: Dictionary = AI_RESOLVER.accept_ai_response(
			identity, response, source, persist_cache
		)
		if not bool(accepted.get("ok", false)):
			var expected_boundary := (
				classification == "vehicle_weapon_platform"
				and str(accepted.get("error", "")) == "AI_VEHICLE_PLATFORM_COMPILER_REQUIRED"
			) or (
				classification == "handheld_firearm_unsupported"
				and str(accepted.get("error", "")) == "AI_FIREARM_STRUCTURE_FAMILY_UNSUPPORTED"
			)
			records.append({
				"case": directory,
				"identity": identity,
				"classification": classification,
				"ok": expected_boundary,
				"boundary": true,
				"error": str(accepted.get("error", "")),
				"player_confirmation_required": false,
			})
			if not expected_boundary:
				unexpected_failures += 1
			continue
		var interpretation: Dictionary = interpreter.interpret_with_ai_firearm_profile(
			identity, PackedByteArray(), {}, accepted
		)
		if not bool(interpretation.get("ok", false)):
			records.append({"case": directory, "identity": identity, "ok": false, "error": str(interpretation.get("error", "INTERPRETATION_FAILED"))})
			unexpected_failures += 1
			continue
		var blueprint := interpretation.get("blueprint") as WeaponBlueprint
		var built: Dictionary = PIXEL_SCAFFOLD.build(blueprint.affordance, blueprint.affordance_source)
		var runtime: Dictionary = RANGED_AXES.compile(blueprint.affordance, blueprint.affordance_source)
		var image := built.get("image") as Image
		if not bool(built.get("ok", false)) or image == null or not bool(runtime.get("ok", false)):
			records.append({"case": directory, "identity": identity, "ok": false, "error": "GODOT_COMPILER_REJECTED"})
			unexpected_failures += 1
			continue
		var sprite_path := case_directory.path_join("generated_sprite.png")
		if image.save_png(sprite_path) != OK:
			records.append({"case": directory, "identity": identity, "ok": false, "error": "SPRITE_SAVE_FAILED"})
			unexpected_failures += 1
			continue
		records.append({
			"case": directory,
			"identity": identity,
			"canonical_name": str(accepted.get("canonical_name_zh", identity)),
			"classification": classification,
			"confidence": float(response.get("confidence", 0.0)),
			"ok": true,
			"boundary": false,
			"sprite": sprite_path,
			"axes": (runtime.get("axes", {}) as Dictionary).duplicate(true),
			"axis_signature": str(runtime.get("axis_signature", "")),
			"player_confirmation_required": false,
		})
	var manifest_path := output_root.path_join("godot_validation_manifest.json")
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		printerr("FIREARM_AI_LIVE_MANIFEST_WRITE_FAILED")
		quit(1)
		return
	file.store_string(JSON.stringify({
		"schema": "forge-firearm-ai-live-godot-validation-v1",
		"persisted_to_validated_cache": persist_cache,
		"records": records,
		"unexpected_failures": unexpected_failures,
	}, "  "))
	file.close()
	for record: Dictionary in records:
		print("%s | %s | %s" % [
			"PASS" if bool(record.get("ok", false)) else "FAIL",
			str(record.get("identity", record.get("case", ""))),
			str(record.get("classification", record.get("error", ""))),
		])
	print("FIREARM_AI_LIVE_GODOT_RESULT records=%d unexpected_failures=%d" % [records.size(), unexpected_failures])
	quit(0 if unexpected_failures == 0 else 1)


func _argument_value(prefix: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return fallback
