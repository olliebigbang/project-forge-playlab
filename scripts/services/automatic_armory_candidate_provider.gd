class_name AutomaticArmoryCandidateProvider
extends RefCounted

const BRIDGE_SCRIPT := "res://tools/semantic/bridge/automatic_armory_candidate_bridge.py"
const REQUEST_SCHEMA := "forge-automatic-armory-candidate-request-v2"
const RESULT_SCHEMA := "forge-automatic-armory-candidate-bridge-result-v2"
const OUTPUT_ROOT := "user://playlab/automatic_armory/requests"

var python_executable := "python"
var timeout_seconds := 70.0
var offline_fixture_path := ""
var process_id := -1
var active_revision := 0
var started_msec := 0
var process_exited_msec := 0
var active_output_directory := ""
var delivered := true
var failure_reason := ""


func configure(next_python_executable: String = "python") -> Dictionary:
	python_executable = next_python_executable.strip_edges()
	if python_executable.is_empty():
		python_executable = "python"
	if not FileAccess.file_exists(ProjectSettings.globalize_path(BRIDGE_SCRIPT)):
		return _failure("AUTOMATIC_ARMORY_CANDIDATE_BRIDGE_MISSING")
	if offline_fixture_path.is_empty():
		if not OS.has_environment("ANTHROPIC_API_KEY"):
			return _failure("AUTOMATIC_ARMORY_AI_KEY_MISSING")
		if not OS.has_environment("FORGE_SEMANTIC_MODEL"):
			return _failure("AUTOMATIC_ARMORY_AI_MODEL_MISSING")
	return {"ok": true, "bridge_path": ProjectSettings.globalize_path(BRIDGE_SCRIPT)}


func request_candidate(
	target_role: String,
	existing_identities: Array[String],
	excluded_identities: Array[String] = []
) -> int:
	cancel_current()
	active_revision += 1
	delivered = false
	failure_reason = ""
	started_msec = Time.get_ticks_msec()
	process_exited_msec = 0
	var run_id := "request_%d_r%d" % [
		roundi(Time.get_unix_time_from_system() * 1000.0), active_revision,
	]
	active_output_directory = ProjectSettings.globalize_path(OUTPUT_ROOT.path_join(run_id))
	if DirAccess.make_dir_recursive_absolute(active_output_directory) != OK:
		failure_reason = "AUTOMATIC_ARMORY_REQUEST_DIRECTORY_CREATE_FAILED"
		return active_revision
	var request_path := active_output_directory.path_join("request.json")
	if _write_json_atomic(request_path, {
		"schema": REQUEST_SCHEMA,
		"target_role": target_role,
		"existing_identities": existing_identities.duplicate(),
		"excluded_identities": excluded_identities.duplicate(),
	}) != OK:
		failure_reason = "AUTOMATIC_ARMORY_REQUEST_WRITE_FAILED"
		return active_revision
	var arguments: Array[String] = [
		"-E", "-S", "-B",
		ProjectSettings.globalize_path(BRIDGE_SCRIPT),
		"--request", request_path,
		"--output-dir", active_output_directory,
	]
	if not offline_fixture_path.is_empty():
		arguments.append_array([
			"--offline-fixture", ProjectSettings.globalize_path(offline_fixture_path),
		])
	process_id = OS.create_process(python_executable, arguments)
	if process_id <= 0:
		failure_reason = "AUTOMATIC_ARMORY_CANDIDATE_PROCESS_START_FAILED"
	return active_revision


func poll() -> Dictionary:
	if active_revision <= 0 or delivered:
		return {"status": "idle"}
	if not failure_reason.is_empty():
		delivered = true
		return _failure(failure_reason)
	if Time.get_ticks_msec() - started_msec > int(timeout_seconds * 1000.0):
		if process_id > 0 and OS.is_process_running(process_id):
			OS.kill(process_id)
		delivered = true
		return _failure("AUTOMATIC_ARMORY_CANDIDATE_TIMEOUT")
	var result_path := active_output_directory.path_join("result.json")
	if FileAccess.file_exists(result_path):
		return _load_result(result_path)
	if process_id > 0 and OS.is_process_running(process_id):
		return {"status": "running", "revision": active_revision}
	if process_id > 0:
		if process_exited_msec == 0:
			process_exited_msec = Time.get_ticks_msec()
			return {"status": "running", "revision": active_revision}
		if Time.get_ticks_msec() - process_exited_msec < 1000:
			return {"status": "running", "revision": active_revision}
		delivered = true
		return _failure("AUTOMATIC_ARMORY_CANDIDATE_EXITED_WITHOUT_RESULT")
	return {"status": "running", "revision": active_revision}


func cancel_current() -> void:
	if process_id > 0 and OS.is_process_running(process_id):
		OS.kill(process_id)
	process_id = -1
	process_exited_msec = 0
	delivered = true


func _load_result(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		delivered = true
		return _failure("AUTOMATIC_ARMORY_CANDIDATE_RESULT_INVALID_JSON")
	var result := parsed as Dictionary
	delivered = true
	if str(result.get("schema", "")) != RESULT_SCHEMA:
		return _failure("AUTOMATIC_ARMORY_CANDIDATE_RESULT_SCHEMA_INVALID")
	if str(result.get("status", "")) != "success":
		return _failure(str(result.get(
			"failure_reason", "AUTOMATIC_ARMORY_CANDIDATE_FAILED"
		)))
	if not result.get("candidate", {}) is Dictionary:
		return _failure("AUTOMATIC_ARMORY_CANDIDATE_MISSING")
	return {
		"status": "success",
		"revision": active_revision,
		"source": str(result.get("source", "")),
		"provider": str(result.get("provider", "")),
		"model_id": str(result.get("model_id", "")),
		"candidate": (result.get("candidate", {}) as Dictionary).duplicate(true),
		"output_directory": active_output_directory,
		"player_confirmation_required": false,
	}


func _write_json_atomic(target: String, value: Dictionary) -> Error:
	var temporary := "%s.%s.tmp" % [target, str(Time.get_ticks_usec())]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(value, "  "))
	file.close()
	var error := DirAccess.rename_absolute(temporary, target)
	if error != OK and FileAccess.file_exists(temporary):
		DirAccess.remove_absolute(temporary)
	return error


func _failure(error: String) -> Dictionary:
	return {
		"ok": false,
		"status": "failed",
		"failure_reason": error,
		"error": error,
		"revision": active_revision,
		"output_directory": active_output_directory,
		"player_confirmation_required": false,
	}
