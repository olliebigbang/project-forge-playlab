extends SceneTree

const INTERPRETER := preload("res://scripts/services/open_identity_interpreter.gd")
const PROVIDER := preload("res://scripts/services/fal_firearm_visual_provider.gd")
const TILE_SIZE := Vector2i(384, 384)
const CASES: Array[Dictionary] = [
	{"id": "qbz_95", "identity": "中国95式步枪"},
	{"id": "m4a1", "identity": "M4A1"},
	{"id": "type_81", "identity": "81杠"},
	{"id": "qsz_92", "identity": "92式手枪"},
]

var provider
var current_blueprint: WeaponBlueprint
var current_case_index := -1
var current_retry_index := 0
var max_retries := 2
var output_directory := ""
var case_results: Array[Dictionary] = []
var attempt_results: Array[Dictionary] = []
var accepted_images: Dictionary = {}
var finished := false


func _initialize() -> void:
	max_retries = clampi(int(_argument_value("--max-retries=", "2")), 0, 2)
	var requested_output := _argument_value(
		"--acceptance-output-dir=",
		"res://output/firearm-automatic-acceptance-v3"
	)
	output_directory = _absolute_path(requested_output)
	if DirAccess.make_dir_recursive_absolute(output_directory) != OK:
		_finish_with_error("FIREARM_ACCEPTANCE_OUTPUT_DIRECTORY_FAILED")
		return
	provider = PROVIDER.new()
	var configured: Dictionary = provider.configure(_argument_value("--fal-python=", "python"))
	if not bool(configured.get("ok", false)):
		_finish_with_error(str(configured.get("error", "FIREARM_ACCEPTANCE_PROVIDER_CONFIG_FAILED")))
		return
	_start_next_case()


func _process(_delta: float) -> bool:
	if finished or provider == null or current_case_index < 0:
		return false
	var result: Dictionary = provider.poll()
	var status := str(result.get("status", ""))
	if status not in ["success", "failed"]:
		return false
	var attempt := _capture_attempt(result)
	attempt_results.append(attempt)
	if status == "success":
		_capture_success(result, attempt)
		_start_next_case()
		return false
	if bool(result.get("retry_required", false)) and current_retry_index < max_retries:
		current_retry_index += 1
		current_blueprint.modifiers["mechanism_visual_retry_count"] = current_retry_index
		current_blueprint.modifiers["mechanism_visual_retry_prompt"] = str(result.get(
			"retry_prompt",
			"Redraw the exact named model with every identity landmark visible."
		))
		print("FIREARM_ACCEPTANCE_RETRY=%s:%d:%s" % [
			str(CASES[current_case_index].get("id", "")),
			current_retry_index,
			str(result.get("failure_reason", "")),
		])
		provider.request_visual(current_blueprint, current_blueprint.player_identity_text, PackedByteArray(), 0.0)
		return false
	case_results.append({
		"id": str(CASES[current_case_index].get("id", "")),
		"identity": str(CASES[current_case_index].get("identity", "")),
		"status": "failed",
		"failure_reason": str(result.get("failure_reason", "FIREARM_ACCEPTANCE_EXHAUSTED")),
		"attempts": _attempts_for_case(str(CASES[current_case_index].get("id", ""))),
		"player_confirmation_required": false,
	})
	_start_next_case()
	return false


func _start_next_case() -> void:
	current_case_index += 1
	current_retry_index = 0
	if current_case_index >= CASES.size():
		_finalize_report()
		return
	var test_case := CASES[current_case_index]
	var identity := str(test_case.get("identity", ""))
	var interpreted: Dictionary = INTERPRETER.new().interpret(identity, PackedByteArray(), {})
	current_blueprint = interpreted.get("blueprint") as WeaponBlueprint
	if current_blueprint == null:
		case_results.append({
			"id": str(test_case.get("id", "")),
			"identity": identity,
			"status": "failed",
			"failure_reason": "FIREARM_ACCEPTANCE_INTERPRETATION_FAILED",
			"attempts": [],
			"player_confirmation_required": false,
		})
		_start_next_case()
		return
	print("FIREARM_ACCEPTANCE_START=%s:%s" % [str(test_case.get("id", "")), identity])
	provider.request_visual(current_blueprint, identity, PackedByteArray(), 0.0)


func _capture_attempt(result: Dictionary) -> Dictionary:
	var case_id := str(CASES[current_case_index].get("id", ""))
	var status := str(result.get("status", "failed"))
	var suffix := "accepted" if status == "success" else "rejected"
	var candidate_name := "candidate_%02d_%s" % [current_retry_index + 1, suffix]
	var destination := _unique_directory(output_directory.path_join(case_id).path_join(candidate_name))
	var source := str(result.get("output_directory", ""))
	var copied := _copy_directory(source, destination)
	var manifest := result.get("manifest", {}) as Dictionary
	if manifest.is_empty() and FileAccess.file_exists(source.path_join("manifest.json")):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(source.path_join("manifest.json")))
		if parsed is Dictionary:
			manifest = parsed as Dictionary
	var verification := manifest.get("ai_visual_identity_verification", {}) as Dictionary
	var cache := manifest.get("cache", {}) as Dictionary
	return {
		"case_id": case_id,
		"retry_index": current_retry_index,
		"status": status,
		"failure_reason": str(result.get("failure_reason", "")),
		"source_directory": source,
		"evidence_directory": destination if copied else "",
		"evidence_copy_ok": copied,
		"cache_hit": bool(cache.get("hit", false)),
		"cache_key": str(cache.get("key", "")),
		"ai_visual_identity_passed": bool(verification.get("passed", false)),
		"ai_visual_identity_verification": verification.duplicate(true),
		"geometry_gate_passed": bool((result.get("firearm_visual_identity_gate", {}) as Dictionary).get("ok", false)),
		"player_confirmation_required": false,
	}


func _capture_success(result: Dictionary, attempt: Dictionary) -> void:
	var case_id := str(CASES[current_case_index].get("id", ""))
	var evidence_directory := str(attempt.get("evidence_directory", ""))
	var sprite_path := evidence_directory.path_join("processed_sprite.png")
	if not FileAccess.file_exists(sprite_path):
		sprite_path = str(result.get("output_directory", "")).path_join("processed_sprite.png")
	var image := Image.load_from_file(sprite_path)
	if image != null and not image.is_empty():
		accepted_images[case_id] = image
	case_results.append({
		"id": case_id,
		"identity": str(CASES[current_case_index].get("identity", "")),
		"canonical_name": current_blueprint.display_name,
		"status": "accepted",
		"accepted_sprite": sprite_path,
		"accepted_attempt": current_retry_index + 1,
		"cache_hit": bool(attempt.get("cache_hit", false)),
		"cache_key": str(attempt.get("cache_key", "")),
		"attempts": _attempts_for_case(case_id),
		"visual_identity_card": (
			current_blueprint.visual_structure_brief.get("visual_identity_card", {}) as Dictionary
		).duplicate(true),
		"mechanism_axes": current_blueprint.affordance.duplicate(true),
		"player_confirmation_required": false,
	})


func _attempts_for_case(case_id: String) -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	for attempt: Dictionary in attempt_results:
		if str(attempt.get("case_id", "")) == case_id:
			values.append(attempt.duplicate(true))
	return values


func _finalize_report() -> void:
	var distinctness := _distinctness_matrix()
	var all_accepted := case_results.size() == CASES.size()
	for result: Dictionary in case_results:
		if str(result.get("status", "")) != "accepted":
			all_accepted = false
	var contact_sheet_path := output_directory.path_join("accepted_contact_sheet.png")
	var contact_sheet_ok := _save_contact_sheet(contact_sheet_path)
	var cache_hits := 0
	for result: Dictionary in case_results:
		cache_hits += int(bool(result.get("cache_hit", false)))
	var report := {
		"schema": "forge-firearm-automatic-acceptance-matrix-v1",
		"pipeline_version": PROVIDER.VISUAL_PIPELINE_VERSION,
		"all_accepted": all_accepted,
		"accepted_count": accepted_images.size(),
		"case_count": CASES.size(),
		"candidate_count": attempt_results.size(),
		"cache_hits": cache_hits,
		"results": case_results,
		"distinctness": distinctness,
		"contact_sheet": contact_sheet_path if contact_sheet_ok else "",
		"automatic": true,
		"player_mechanism_input_used": false,
		"player_confirmation_required": false,
	}
	var report_path := output_directory.path_join("acceptance_matrix.json")
	if _write_json_atomic(report_path, report) != OK:
		_finish_with_error("FIREARM_ACCEPTANCE_REPORT_WRITE_FAILED")
		return
	finished = true
	print("FIREARM_ACCEPTANCE_MATRIX_RESULT=%s" % JSON.stringify({
		"all_accepted": all_accepted,
		"accepted_count": accepted_images.size(),
		"candidate_count": attempt_results.size(),
		"cache_hits": cache_hits,
		"output_directory": output_directory,
		"report": report_path,
	}))
	quit(0 if all_accepted and bool(distinctness.get("passed", false)) else 1)


func _distinctness_matrix() -> Dictionary:
	var pairs: Array[Dictionary] = []
	var ids: Array = accepted_images.keys()
	ids.sort()
	var passed := ids.size() == CASES.size()
	for left_index: int in range(ids.size()):
		for right_index: int in range(left_index + 1, ids.size()):
			var left_id := str(ids[left_index])
			var right_id := str(ids[right_index])
			var left := accepted_images[left_id] as Image
			var right := accepted_images[right_id] as Image
			var alpha_difference := _alpha_difference(left, right)
			var rgba_difference := _rgba_difference(left, right)
			var pair_passed := alpha_difference >= 80 and rgba_difference >= 120
			passed = passed and pair_passed
			pairs.append({
				"left": left_id,
				"right": right_id,
				"alpha_difference_pixels": alpha_difference,
				"rgba_difference_pixels": rgba_difference,
				"passed": pair_passed,
			})
	return {
		"schema": "forge-firearm-blind-distinctness-v1",
		"minimum_alpha_difference_pixels": 80,
		"minimum_rgba_difference_pixels": 120,
		"pairs": pairs,
		"passed": passed,
	}


func _save_contact_sheet(path: String) -> bool:
	var sheet := Image.create(TILE_SIZE.x * 2, TILE_SIZE.y * 2, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("101722"))
	for index: int in range(CASES.size()):
		var case_id := str(CASES[index].get("id", ""))
		if not accepted_images.has(case_id):
			continue
		var enlarged := (accepted_images[case_id] as Image).duplicate()
		enlarged.resize(TILE_SIZE.x, TILE_SIZE.y, Image.INTERPOLATE_NEAREST)
		var destination := Vector2i((index % 2) * TILE_SIZE.x, (index / 2) * TILE_SIZE.y)
		sheet.blend_rect(enlarged, Rect2i(Vector2i.ZERO, enlarged.get_size()), destination)
	return sheet.save_png(path) == OK


func _copy_directory(source: String, destination: String) -> bool:
	if source.is_empty() or not DirAccess.dir_exists_absolute(source):
		return false
	if DirAccess.make_dir_recursive_absolute(destination) != OK:
		return false
	var directory := DirAccess.open(source)
	if directory == null:
		return false
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		if name not in [".", ".."]:
			var source_path := source.path_join(name)
			var destination_path := destination.path_join(name)
			if directory.current_is_dir():
				if not _copy_directory(source_path, destination_path):
					directory.list_dir_end()
					return false
			elif DirAccess.copy_absolute(source_path, destination_path) != OK:
				directory.list_dir_end()
				return false
		name = directory.get_next()
	directory.list_dir_end()
	return true


func _unique_directory(base: String) -> String:
	if not DirAccess.dir_exists_absolute(base):
		return base
	var suffix := 2
	while DirAccess.dir_exists_absolute("%s_v%d" % [base, suffix]):
		suffix += 1
	return "%s_v%d" % [base, suffix]


func _alpha_difference(left: Image, right: Image) -> int:
	var difference := 0
	for y: int in range(mini(left.get_height(), right.get_height())):
		for x: int in range(mini(left.get_width(), right.get_width())):
			if (left.get_pixel(x, y).a > 0.1) != (right.get_pixel(x, y).a > 0.1):
				difference += 1
	return difference


func _rgba_difference(left: Image, right: Image) -> int:
	var difference := 0
	for y: int in range(mini(left.get_height(), right.get_height())):
		for x: int in range(mini(left.get_width(), right.get_width())):
			if left.get_pixel(x, y) != right.get_pixel(x, y):
				difference += 1
	return difference


func _write_json_atomic(target: String, value: Dictionary) -> Error:
	var temporary := "%s.%s.tmp" % [target, str(Time.get_ticks_usec())]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(value, "  "))
	file.close()
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(target)
	var error := DirAccess.rename_absolute(temporary, target)
	if error != OK and FileAccess.file_exists(temporary):
		DirAccess.remove_absolute(temporary)
	return error


func _finish_with_error(error: String) -> void:
	finished = true
	printerr("FIREARM_ACCEPTANCE_MATRIX_FAILED=%s" % error)
	quit(2)


func _argument_value(prefix: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return fallback


func _absolute_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path.simplify_path()
