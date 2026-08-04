class_name LocalComfyForgeVisualProvider
extends "res://scripts/services/forge_visual_provider.gd"

const ANCHOR_RESOLVER := preload("res://scripts/systems/anchor_resolver.gd")
const OPEN_IDENTITY_PROMPT := preload("res://scripts/services/open_identity_visual_prompt.gd")

var config_path := "res://tools/comfyui/config/forge_comfy_config.local.json"
var config: Dictionary = {}
var requested_profile := ""
var developer_sketch_edit_enabled := false
var process_id := -1
var active_revision := 0
var active_blueprint: WeaponBlueprint
var active_output_directory := ""
var started_msec := 0
var process_exited_msec := 0
var delivered := false
var failure_reason := ""
var output_case_id := "interactive"
var last_generation_prompt := ""

func configure(next_config_path: String) -> Dictionary:
	config_path = next_config_path
	var absolute_config := _absolute_path(config_path)
	if not FileAccess.file_exists(absolute_config):
		return {"ok": false, "error": "COMFYUI_CONFIG_NOT_FOUND", "path": absolute_config}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(absolute_config))
	if not parsed is Dictionary:
		return {"ok": false, "error": "COMFYUI_CONFIG_INVALID_JSON"}
	config = parsed as Dictionary
	if not requested_profile.is_empty() and str(config.get("comfy_profile", "")) != requested_profile:
		config.clear()
		return {"ok": false, "error": "COMFYUI_PROFILE_CONFIG_MISMATCH"}
	if not _is_strict_loopback_api_url(str(config.get("api_base", ""))):
		config.clear()
		return {"ok": false, "error": "COMFYUI_API_MUST_USE_LOOPBACK"}
	return {"ok": true}

func health_check() -> Dictionary:
	if config.is_empty():
		var configured := configure(config_path)
		if not bool(configured.get("ok", false)):
			return configured
	var output: Array = []
	var exit_code := OS.execute(
		str(config.get("python_executable", "")),
		[
			_resolve_config_path(str(config.get("bridge_script", ""))),
			"--config", _absolute_path(config_path), "health"
		],
		output,
		true,
		true
	)
	if exit_code != 0:
		return {"ok": false, "error": "COMFYUI_HEALTH_CHECK_FAILED", "details": "\n".join(output)}
	var parsed: Variant = JSON.parse_string("\n".join(output))
	if not parsed is Dictionary or not bool((parsed as Dictionary).get("ok", false)):
		return {"ok": false, "error": "COMFYUI_HEALTH_RESPONSE_INVALID"}
	return parsed as Dictionary

func request_visual(
	blueprint: WeaponBlueprint,
	prompt: String,
	sketch_png: PackedByteArray,
	control_strength: float = 0.45
) -> int:
	cancel_current()
	request_revision += 1
	active_revision = request_revision
	active_blueprint = blueprint
	delivered = false
	failure_reason = ""
	started_msec = Time.get_ticks_msec()
	process_exited_msec = 0
	var case_id := output_case_id
	var run_id := "request_%d_r%d" % [roundi(Time.get_unix_time_from_system() * 1000.0), active_revision]
	active_output_directory = _resolve_config_path(str(config.get("output_root", "")))
	var output_group := str(config.get("output_group", "")).strip_edges()
	if not output_group.is_empty():
		active_output_directory = active_output_directory.path_join(output_group)
	active_output_directory = active_output_directory.path_join(case_id).path_join(run_id)
	last_generation_prompt = blueprint.visual_prompt
	if not blueprint.player_identity_text.strip_edges().is_empty() or not blueprint.source_identity.strip_edges().is_empty():
		last_generation_prompt = OPEN_IDENTITY_PROMPT.build(blueprint)
	if last_generation_prompt.strip_edges().is_empty():
		failure_reason = "GENERATION_PROMPT_EMPTY"
		return active_revision
	var arguments: Array[String] = [
		_resolve_config_path(str(config.get("bridge_script", ""))),
		"--config", _absolute_path(config_path),
		"generate",
		"--case-id", case_id,
		"--run-id", run_id,
		"--prompt=%s" % prompt,
		"--generation-prompt=%s" % last_generation_prompt,
		"--prompt-policy-version", OPEN_IDENTITY_PROMPT.POLICY_VERSION,
		"--seed", str(randi_range(1, 2147483646)),
		"--control-strength", str(clampf(control_strength, 0.0, 1.0))
	]
	var profiled_bridge := config.has("comfy_profile")
	var may_submit_sketch := not profiled_bridge or developer_sketch_edit_enabled
	if not sketch_png.is_empty() and may_submit_sketch:
		var request_directory := "user://playlab/comfy_spike/requests"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(request_directory))
		var sketch_path := request_directory.path_join("%s.png" % run_id)
		var temp_path := sketch_path + ".tmp"
		var sketch_file := FileAccess.open(temp_path, FileAccess.WRITE)
		if sketch_file == null:
			failure_reason = "SKETCH_TEMP_WRITE_FAILED"
			return active_revision
		sketch_file.store_buffer(sketch_png)
		sketch_file.close()
		var absolute_temp := ProjectSettings.globalize_path(temp_path)
		var absolute_sketch := ProjectSettings.globalize_path(sketch_path)
		if FileAccess.file_exists(absolute_sketch):
			DirAccess.remove_absolute(absolute_sketch)
		if DirAccess.rename_absolute(absolute_temp, absolute_sketch) != OK:
			failure_reason = "SKETCH_ATOMIC_RENAME_FAILED"
			return active_revision
		if profiled_bridge:
			arguments.append_array(["--mode", "edit", "--sketch", absolute_sketch, "--flux2-enable-sketch-edit"])
		else:
			arguments.append_array(["--sketch", absolute_sketch])
	process_id = OS.create_process(str(config.get("python_executable", "")), arguments)
	if process_id <= 0:
		failure_reason = "COMFYUI_BRIDGE_PROCESS_START_FAILED"
	return active_revision

func poll() -> Dictionary:
	if active_revision <= 0 or delivered:
		return {"status": "idle"}
	if not failure_reason.is_empty():
		delivered = true
		return _failure(failure_reason)
	var timeout_msec := int(float(config.get("timeout_seconds", 120.0)) * 1000.0)
	if Time.get_ticks_msec() - started_msec > timeout_msec:
		if process_id > 0 and OS.is_process_running(process_id):
			OS.kill(process_id)
		delivered = true
		return _failure("COMFYUI_TIMEOUT")
	var manifest_path := active_output_directory.path_join("manifest.json")
	if FileAccess.file_exists(manifest_path):
		return _load_completed_result(manifest_path)
	if process_id > 0 and OS.is_process_running(process_id):
		return {"status": "running", "revision": active_revision}
	if process_id > 0:
		if process_exited_msec == 0:
			process_exited_msec = Time.get_ticks_msec()
			return {"status": "running", "revision": active_revision}
		if Time.get_ticks_msec() - process_exited_msec < 2000:
			return {"status": "running", "revision": active_revision}
		delivered = true
		return _failure("COMFYUI_BRIDGE_EXITED_WITHOUT_ATOMIC_RESULT")
	return {"status": "running", "revision": active_revision}

func load_atomic_result(directory: String, blueprint: WeaponBlueprint) -> Dictionary:
	active_blueprint = blueprint
	active_output_directory = _absolute_path(directory)
	active_revision = request_revision
	delivered = false
	return _load_completed_result(active_output_directory.path_join("manifest.json"))

func cancel_current() -> void:
	super.cancel_current()
	if process_id > 0 and OS.is_process_running(process_id):
		OS.kill(process_id)
	process_id = -1
	process_exited_msec = 0
	active_revision = 0
	delivered = true

func _load_completed_result(manifest_path: String) -> Dictionary:
	if not accepts_revision(active_revision):
		delivered = true
		return _failure("STALE_RESULT_IGNORED")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary:
		delivered = true
		return _failure("MANIFEST_INVALID_JSON")
	var manifest := parsed as Dictionary
	if str(manifest.get("status", "")) != "success":
		delivered = true
		return _failure(str(manifest.get("failure_reason", "COMFYUI_GENERATION_FAILED")))
	var sprite_path := active_output_directory.path_join("processed_sprite.png")
	if not FileAccess.file_exists(sprite_path):
		delivered = true
		return _failure("PROCESSED_SPRITE_MISSING")
	var image := Image.load_from_file(sprite_path)
	if image == null or image.get_size() != Vector2i(96, 96):
		delivered = true
		return _failure("PROCESSED_SPRITE_MUST_BE_96X96")
	var asset: WeaponVisualAsset = ANCHOR_RESOLVER.resolve(image, active_blueprint)
	if asset == null:
		delivered = true
		return _failure("PROCESSED_SPRITE_ALPHA_INVALID")
	delivered = true
	return {
		"status": "success", "revision": active_revision, "provider": MODE_LOCAL_COMFYUI,
		"asset": asset, "manifest": manifest, "output_directory": active_output_directory
	}
func _failure(reason: String) -> Dictionary:
	return {
		"status": "failed", "failure_reason": reason,
		"revision": active_revision, "provider": MODE_LOCAL_COMFYUI,
		"output_directory": active_output_directory
	}

func _absolute_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path.simplify_path()

func _resolve_config_path(path: String) -> String:
	if path.is_absolute_path():
		return path.simplify_path()
	return _absolute_path(config_path).get_base_dir().path_join(path).simplify_path()

func _is_strict_loopback_api_url(value: String) -> bool:
	var matcher := RegEx.new()
	if matcher.compile("^http://127\\.0\\.0\\.1:([0-9]{1,5})$") != OK:
		return false
	var result := matcher.search(value)
	if result == null:
		return false
	var port := int(result.get_string(1))
	return port >= 1 and port <= 65535
