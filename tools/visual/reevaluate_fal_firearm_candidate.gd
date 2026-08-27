extends SceneTree

const INTERPRETER := preload("res://scripts/services/open_identity_interpreter.gd")
const PROVIDER := preload("res://scripts/services/fal_firearm_visual_provider.gd")


func _initialize() -> void:
	var source_directory := _argument_value("--source-dir=", "").simplify_path()
	var target_directory := _argument_value("--target-dir=", "").simplify_path()
	var identity := _argument_value("--identity=", "M4A1")
	var verification_path := _argument_value("--visual-verification=", "").simplify_path()
	if source_directory.is_empty() or target_directory.is_empty():
		_finish({"status": "failed", "failure_reason": "REEVALUATE_DIRECTORY_MISSING"}, 2)
		return
	if DirAccess.make_dir_recursive_absolute(target_directory) != OK:
		_finish({"status": "failed", "failure_reason": "REEVALUATE_TARGET_CREATE_FAILED"}, 2)
		return
	for file_name: String in ["ai_raw.png", "raw_pixel_art.png", "request.json"]:
		var copied := _copy_file(
			source_directory.path_join(file_name),
			target_directory.path_join(file_name)
		)
		if copied != OK:
			_finish({"status": "failed", "failure_reason": "REEVALUATE_COPY_FAILED:%s" % file_name}, 2)
			return
	var source_manifest_path := source_directory.path_join("manifest.json")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(source_manifest_path))
	if not parsed is Dictionary:
		_finish({"status": "failed", "failure_reason": "REEVALUATE_MANIFEST_INVALID"}, 2)
		return
	var manifest := (parsed as Dictionary).duplicate(true)
	if (
		str(manifest.get("schema", "")) != "forge-fal-firearm-visual-manifest-v1"
		or str(manifest.get("provider", "")) != "FAL_FIREARM"
	):
		_finish({"status": "failed", "failure_reason": "REEVALUATE_MANIFEST_SCHEMA_INVALID"}, 2)
		return
	if not verification_path.is_empty():
		var verification_value: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(verification_path)
		)
		if not verification_value is Dictionary:
			_finish({"status": "failed", "failure_reason": "REEVALUATE_VISUAL_VERIFICATION_INVALID"}, 2)
			return
		var verification := verification_value as Dictionary
		if str(verification.get("schema", "")) != "forge-firearm-ai-visual-verification-v1":
			_finish({"status": "failed", "failure_reason": "REEVALUATE_VISUAL_VERIFICATION_SCHEMA_INVALID"}, 2)
			return
		manifest["ai_visual_identity_verification"] = verification.duplicate(true)
		_write_json(
			target_directory.path_join("ai_visual_identity_verification.json"),
			verification
		)
	var request_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(source_directory.path_join("request.json"))
	)
	if request_value is Dictionary:
		var request := request_value as Dictionary
		manifest["identity"] = str(request.get("identity", identity))
		manifest["canonical_identity"] = str(request.get("canonical_name", identity))
		if not manifest.get("models", {}) is Dictionary or (manifest.get("models", {}) as Dictionary).is_empty():
			manifest["models"] = {
				"identity_renderer": (
					"fal-ai/gpt-image-1.5/edit"
					if not str(request.get("identity_reference_id", "")).is_empty()
					else "fal-ai/gpt-image-1.5"
				),
				"pixelizer": "fal-ai/image2pixel",
			}
	manifest["status"] = "success"
	manifest["visual_mode"] = "fal_ai_pixel_candidate"
	manifest["finished_art"] = false
	manifest["presentable_to_player"] = false
	for stale_key: String in [
		"failure_reason",
		"firearm_visual_gate_passed",
		"firearm_visual_rejection",
		"firearm_visual_identity_gate",
	]:
		manifest.erase(stale_key)
	if _write_json(target_directory.path_join("manifest.json"), manifest) != OK:
		_finish({"status": "failed", "failure_reason": "REEVALUATE_MANIFEST_WRITE_FAILED"}, 2)
		return
	var interpreted: Dictionary = INTERPRETER.new().interpret(identity, PackedByteArray(), {})
	var blueprint := interpreted.get("blueprint") as WeaponBlueprint
	if blueprint == null:
		_finish({"status": "failed", "failure_reason": "REEVALUATE_INTERPRETATION_FAILED"}, 2)
		return
	var result: Dictionary = PROVIDER.new().load_atomic_result(target_directory, blueprint)
	_finish({
		"status": str(result.get("status", "")),
		"failure_reason": str(result.get("failure_reason", "")),
		"provider": str(result.get("provider", "")),
		"output_directory": str(result.get("output_directory", "")),
		"gate_ok": bool((result.get("firearm_visual_identity_gate", {}) as Dictionary).get("ok", false)),
		"visual_mode": str((result.get("manifest", {}) as Dictionary).get("visual_mode", "")),
		"finished_art": bool((result.get("manifest", {}) as Dictionary).get("finished_art", false)),
	}, 0 if str(result.get("status", "")) == "success" else 1)


func _copy_file(source: String, target: String) -> Error:
	var input := FileAccess.open(source, FileAccess.READ)
	if input == null:
		return FileAccess.get_open_error()
	var bytes := input.get_buffer(input.get_length())
	input.close()
	var output := FileAccess.open(target, FileAccess.WRITE)
	if output == null:
		return FileAccess.get_open_error()
	output.store_buffer(bytes)
	output.close()
	return OK


func _write_json(path: String, value: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(value, "  "))
	file.close()
	return OK


func _finish(result: Dictionary, code: int) -> void:
	print("FAL_FIREARM_REEVALUATE_RESULT=%s" % JSON.stringify(result))
	quit(code)


func _argument_value(prefix: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return fallback
