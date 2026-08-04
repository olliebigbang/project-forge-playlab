extends SceneTree

const INTERPRETER := preload("res://scripts/services/open_identity_interpreter.gd")
const INPUT_PATH := "res://tools/comfyui/open_identity/test_cases/cases.json"
const OUTPUT_PATH := "res://tools/comfyui/open_identity/reports/compiled_cases.json"

func _initialize() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INPUT_PATH))
	if not parsed is Dictionary:
		printerr("SPIKE2_CASE_FILE_INVALID")
		quit(2)
		return
	var interpreter := INTERPRETER.new()
	var compiled: Array[Dictionary] = []
	var failures: Array[String] = []
	for value: Variant in (parsed as Dictionary).get("cases", []):
		var test_case := value as Dictionary
		var is_sketch_only := bool(test_case.get("sketch_only", false))
		var sketch := PackedByteArray()
		if is_sketch_only:
			var sketch_path := INPUT_PATH.get_base_dir().path_join(str(test_case.get("sketch", "")))
			if not FileAccess.file_exists(sketch_path):
				failures.append("%s abstract sketch missing" % str(test_case.get("case_id", "")))
			else:
				sketch = FileAccess.get_file_as_bytes(sketch_path)
				var sketch_image := Image.new()
				if sketch_image.load_png_from_buffer(sketch) != OK:
					failures.append("%s abstract sketch invalid" % str(test_case.get("case_id", "")))
		var geometry := {"stroke_count": 3, "aspect_ratio": 1.2, "dominant_axis": "unknown"} if is_sketch_only else {}
		var result: Dictionary = interpreter.interpret(
			"" if is_sketch_only else str(test_case.get("player_text", "")),
			sketch,
			geometry
		)
		var record := test_case.duplicate(true)
		record["ok"] = bool(result.get("ok", false))
		record["needs_clarification"] = bool(result.get("needs_clarification", false))
		record["clarification_kind"] = str(result.get("clarification_kind", ""))
		record["question"] = str(result.get("question", ""))
		record["ai_interpretation_used"] = bool(result.get("ai_interpretation_used", true))
		record["identity_semantics_understood"] = bool(result.get("identity_semantics_understood", false))
		record["identity_passthrough"] = bool(result.get("identity_passthrough", false))
		record["sketch_bytes"] = sketch.size()
		var blueprint := result.get("blueprint") as WeaponBlueprint
		if blueprint != null:
			record["blueprint"] = blueprint.to_dict()
			if blueprint.player_identity_text != str(test_case.get("player_text", "")):
				failures.append("%s identity changed" % str(test_case.get("case_id", "")))
			if blueprint.behavior_family != str(test_case.get("expected_behavior_family", "")):
				failures.append("%s behavior changed" % str(test_case.get("case_id", "")))
		elif not is_sketch_only:
			failures.append("%s blueprint missing" % str(test_case.get("case_id", "")))
		if bool(result.get("ai_interpretation_used", true)):
			failures.append("%s falsely claimed AI" % str(test_case.get("case_id", "")))
		if is_sketch_only and str(result.get("question", "")) != str(test_case.get("expected_clarification", "")):
			failures.append("%s clarification changed" % str(test_case.get("case_id", "")))
		compiled.append(record)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_PATH.get_base_dir()))
	var output := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if output == null:
		printerr("SPIKE2_COMPILED_CASE_WRITE_FAILED")
		quit(2)
		return
	output.store_string(JSON.stringify({
		"spike": "Forge Open Identity Interpretation Spike 2",
		"interpreter_mode": "PLAYER TEXT PASSTHROUGH + LOCAL RULE BEHAVIOR COMPILER",
		"ai_interpretation_used": false,
		"identity_semantics_understood": false,
		"cases": compiled,
		"failures": failures
	}, "  "))
	output.close()
	print("SPIKE2_COMPILED=%d FAILURES=%d" % [compiled.size(), failures.size()])
	quit(0 if failures.is_empty() else 2)
