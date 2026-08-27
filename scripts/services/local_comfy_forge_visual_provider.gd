class_name LocalComfyForgeVisualProvider
extends "res://scripts/services/forge_visual_provider.gd"

const ANCHOR_RESOLVER := preload("res://scripts/systems/anchor_resolver.gd")
const OPEN_IDENTITY_PROMPT := preload("res://scripts/services/open_identity_visual_prompt.gd")
const MECHANISM_SCAFFOLD_PIPELINE := preload("res://scripts/combat_feel/mechanism_visual_scaffold_pipeline.gd")
const FIREARM_SCAFFOLD_PIPELINE := preload("res://scripts/combat_feel/firearm_visual_scaffold_pipeline.gd")

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
var active_mechanism_preparation: Dictionary = {}
var active_mechanism_request_files: Dictionary = {}
var last_mechanism_preflight: Dictionary = {}
var active_firearm_preparation: Dictionary = {}
var active_firearm_request_files: Dictionary = {}
var last_firearm_visual_gate: Dictionary = {}

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
	active_mechanism_preparation.clear()
	active_mechanism_request_files.clear()
	last_mechanism_preflight.clear()
	active_firearm_preparation.clear()
	active_firearm_request_files.clear()
	last_firearm_visual_gate.clear()
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
	if blueprint.behavior_family == "heavy_melee":
		active_mechanism_preparation = MECHANISM_SCAFFOLD_PIPELINE.prepare(blueprint)
		if not bool(active_mechanism_preparation.get("ok", false)):
			failure_reason = str(active_mechanism_preparation.get("error", "MECHANISM_SCAFFOLD_PREPARE_FAILED"))
			return active_revision
		blueprint.visual_structure_brief = (
			active_mechanism_preparation.get("visual_structure_brief", {}) as Dictionary
		).duplicate(true)
		blueprint.visual_structure_brief_source = str(blueprint.visual_structure_brief.get("source", ""))
	elif (
		blueprint.behavior_family == "sustained_ranged"
		and str(blueprint.affordance.get("weapon_domain", "")) == "handheld_firearm"
	):
		active_firearm_preparation = FIREARM_SCAFFOLD_PIPELINE.prepare(blueprint)
		if not bool(active_firearm_preparation.get("ok", false)):
			failure_reason = str(active_firearm_preparation.get("error", "FIREARM_VISUAL_PREPARE_FAILED"))
			return active_revision
		blueprint.visual_structure_brief = (
			active_firearm_preparation.get("visual_structure_brief", {}) as Dictionary
		).duplicate(true)
		blueprint.visual_structure_brief_source = str(blueprint.visual_structure_brief.get("source", ""))
	var effective_control_strength := clampf(control_strength, 0.0, 1.0)
	if not active_mechanism_preparation.is_empty():
		effective_control_strength = maxf(effective_control_strength, 0.80)
	elif not active_firearm_preparation.is_empty():
		# The scaffold locks roles and proportions but must leave enough denoise for
		# the provider to render recognisable finished identity details.
		effective_control_strength = maxf(effective_control_strength, 0.62)
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
		"--control-strength", str(effective_control_strength)
	]
	var request_directory := "user://playlab/comfy_spike/requests"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(request_directory))
	if not active_mechanism_preparation.is_empty():
		active_mechanism_request_files = MECHANISM_SCAFFOLD_PIPELINE.persist_request_inputs(
			request_directory,
			run_id,
			active_mechanism_preparation
		)
		if not bool(active_mechanism_request_files.get("ok", false)):
			failure_reason = str(active_mechanism_request_files.get("error", "MECHANISM_SCAFFOLD_REQUEST_PERSIST_FAILED"))
			return active_revision
		arguments.append_array([
			"--visual-structure-brief",
			str(active_mechanism_request_files.get("visual_structure_brief_path", "")),
			"--visual-retry-count",
			str(clampi(int(blueprint.modifiers.get("mechanism_visual_retry_count", 0)), 0, 2)),
		])
	elif not active_firearm_preparation.is_empty():
		active_firearm_request_files = FIREARM_SCAFFOLD_PIPELINE.persist_request_inputs(
			request_directory,
			run_id,
			active_firearm_preparation
		)
		if not bool(active_firearm_request_files.get("ok", false)):
			failure_reason = str(active_firearm_request_files.get("error", "FIREARM_VISUAL_REQUEST_PERSIST_FAILED"))
			return active_revision
		arguments.append_array([
			"--visual-structure-brief",
			str(active_firearm_request_files.get("visual_structure_brief_path", "")),
			"--visual-retry-count",
			str(clampi(int(blueprint.modifiers.get("mechanism_visual_retry_count", 0)), 0, 2)),
		])
	elif not blueprint.visual_structure_brief.is_empty():
		var brief_path := request_directory.path_join("%s.visual_structure_brief.json" % run_id)
		var brief_temp_path := brief_path + ".tmp"
		var brief_file := FileAccess.open(brief_temp_path, FileAccess.WRITE)
		if brief_file == null:
			failure_reason = "VISUAL_STRUCTURE_BRIEF_TEMP_WRITE_FAILED"
			return active_revision
		brief_file.store_string(JSON.stringify(blueprint.visual_structure_brief, "  "))
		brief_file.close()
		var absolute_brief_temp := ProjectSettings.globalize_path(brief_temp_path)
		var absolute_brief := ProjectSettings.globalize_path(brief_path)
		if FileAccess.file_exists(absolute_brief):
			DirAccess.remove_absolute(absolute_brief)
		if DirAccess.rename_absolute(absolute_brief_temp, absolute_brief) != OK:
			failure_reason = "VISUAL_STRUCTURE_BRIEF_ATOMIC_RENAME_FAILED"
			return active_revision
		arguments.append_array([
			"--visual-structure-brief", absolute_brief,
			"--visual-retry-count", str(clampi(int(blueprint.modifiers.get("mechanism_visual_retry_count", 0)), 0, 2)),
		])
	var profiled_bridge := config.has("comfy_profile")
	if not active_mechanism_preparation.is_empty():
		var structural_reference := str(active_mechanism_request_files.get("reference_path", ""))
		if profiled_bridge:
			arguments.append_array([
				"--mode", "edit",
				"--reference", structural_reference,
				"--flux2-enable-sketch-edit",
			])
		else:
			arguments.append_array(["--sketch", structural_reference])
	elif not active_firearm_preparation.is_empty():
		var firearm_reference := str(active_firearm_request_files.get("reference_path", ""))
		if profiled_bridge:
			arguments.append_array([
				"--mode", "edit",
				"--reference", firearm_reference,
				"--flux2-enable-sketch-edit",
			])
		else:
			arguments.append_array(["--sketch", firearm_reference])
	else:
		var may_submit_sketch := not profiled_bridge or developer_sketch_edit_enabled
		if not sketch_png.is_empty() and may_submit_sketch:
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
	active_mechanism_preparation.clear()
	active_mechanism_request_files.clear()
	last_mechanism_preflight.clear()
	active_firearm_preparation.clear()
	active_firearm_request_files.clear()
	last_firearm_visual_gate.clear()
	active_blueprint = blueprint
	if (
		blueprint != null
		and blueprint.behavior_family == "sustained_ranged"
		and str(blueprint.affordance.get("weapon_domain", "")) == "handheld_firearm"
	):
		active_firearm_preparation = FIREARM_SCAFFOLD_PIPELINE.prepare(blueprint)
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
	active_mechanism_preparation.clear()
	active_mechanism_request_files.clear()
	last_mechanism_preflight.clear()
	active_firearm_preparation.clear()
	active_firearm_request_files.clear()
	last_firearm_visual_gate.clear()

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
	var asset: WeaponVisualAsset
	var mechanism_resolution: Dictionary = {}
	var firearm_resolution: Dictionary = {}
	if not active_mechanism_preparation.is_empty():
		mechanism_resolution = MECHANISM_SCAFFOLD_PIPELINE.resolve_asset(
			image,
			active_blueprint,
			active_mechanism_preparation.get("contract", {}) as Dictionary
		)
		last_mechanism_preflight = (
			mechanism_resolution.get("preflight", {}) as Dictionary
		).duplicate(true)
		if not bool(mechanism_resolution.get("ok", false)):
			MECHANISM_SCAFFOLD_PIPELINE.persist_generation_rejection(
				active_output_directory,
				active_mechanism_preparation,
				mechanism_resolution,
				manifest
			)
			delivered = true
			return _failure(str(mechanism_resolution.get("error", "MECHANISM_SCAFFOLD_OUTPUT_REJECTED")))
		asset = mechanism_resolution.get("asset") as WeaponVisualAsset
	elif not active_firearm_preparation.is_empty():
		firearm_resolution = FIREARM_SCAFFOLD_PIPELINE.resolve_asset(
			image,
			active_blueprint,
			active_firearm_preparation
		)
		last_firearm_visual_gate = (
			firearm_resolution.get("visual_identity_gate", firearm_resolution) as Dictionary
		).duplicate(true)
		if not bool(firearm_resolution.get("ok", false)):
			FIREARM_SCAFFOLD_PIPELINE.persist_generation_rejection(
				active_output_directory,
				active_firearm_preparation,
				firearm_resolution,
				manifest
			)
			delivered = true
			return _failure(str(firearm_resolution.get("error", "FIREARM_VISUAL_OUTPUT_REJECTED")))
		asset = firearm_resolution.get("asset") as WeaponVisualAsset
	else:
		asset = ANCHOR_RESOLVER.resolve(image, active_blueprint)
	if asset == null:
		delivered = true
		return _failure("PROCESSED_SPRITE_ALPHA_INVALID")
	var ai_affordance: Dictionary = {}
	var affordance_path := active_output_directory.path_join("object_affordance_profile.json")
	if not active_mechanism_preparation.is_empty() or not active_firearm_preparation.is_empty():
		ai_affordance = active_blueprint.affordance.duplicate(true)
		ai_affordance["source"] = active_blueprint.affordance_source
	elif FileAccess.file_exists(affordance_path):
		var parsed_affordance: Variant = JSON.parse_string(FileAccess.get_file_as_string(affordance_path))
		if not parsed_affordance is Dictionary:
			delivered = true
			return _failure("AI_AFFORDANCE_INVALID_JSON")
		ai_affordance = (parsed_affordance as Dictionary).duplicate(true)
	var ai_visual_rig: Dictionary = {}
	var visual_rig_path := active_output_directory.path_join("visual_rig.json")
	if (
		active_mechanism_preparation.is_empty()
		and active_firearm_preparation.is_empty()
		and FileAccess.file_exists(visual_rig_path)
	):
		var parsed_visual_rig: Variant = JSON.parse_string(FileAccess.get_file_as_string(visual_rig_path))
		if not parsed_visual_rig is Dictionary:
			delivered = true
			return _failure("AI_VISUAL_RIG_INVALID_JSON")
		ai_visual_rig = (parsed_visual_rig as Dictionary).duplicate(true)
	if not active_mechanism_preparation.is_empty():
		var persisted := MECHANISM_SCAFFOLD_PIPELINE.persist_generation_handoff(
			active_output_directory,
			active_mechanism_preparation,
			mechanism_resolution,
			manifest,
			true
		)
		if not bool(persisted.get("ok", false)):
			delivered = true
			return _failure(str(persisted.get("error", "MECHANISM_SCAFFOLD_HANDOFF_FAILED")))
		manifest = (persisted.get("manifest", {}) as Dictionary).duplicate(true)
	elif not active_firearm_preparation.is_empty():
		var firearm_persisted := FIREARM_SCAFFOLD_PIPELINE.persist_generation_handoff(
			active_output_directory,
			active_firearm_preparation,
			firearm_resolution,
			manifest
		)
		if not bool(firearm_persisted.get("ok", false)):
			delivered = true
			return _failure(str(firearm_persisted.get("error", "FIREARM_VISUAL_HANDOFF_FAILED")))
		manifest = (firearm_persisted.get("manifest", {}) as Dictionary).duplicate(true)
	delivered = true
	return {
		"status": "success", "revision": active_revision, "provider": MODE_LOCAL_COMFYUI,
		"asset": asset, "manifest": manifest, "output_directory": active_output_directory,
		"ai_affordance": ai_affordance,
		"ai_affordance_source": str(ai_affordance.get(
			"source",
			manifest.get("ai_affordance_source", active_blueprint.affordance_source if active_blueprint != null else "")
		)),
		"ai_visual_rig": ai_visual_rig,
		"ai_visual_rig_source": str(ai_visual_rig.get("source", manifest.get("ai_visual_rig_source", ""))),
		"firearm_visual_identity_gate": (
			firearm_resolution.get("visual_identity_gate", {}) as Dictionary
		).duplicate(true),
	}
func _failure(reason: String) -> Dictionary:
	var result := {
		"status": "failed", "failure_reason": reason,
		"error": reason,
		"revision": active_revision, "provider": MODE_LOCAL_COMFYUI,
		"output_directory": active_output_directory,
		"retry_required": _is_structural_output_failure(reason),
		"player_confirmation_required": false,
	}
	if not last_mechanism_preflight.is_empty():
		result["mechanism_preflight"] = last_mechanism_preflight.duplicate(true)
	if not last_firearm_visual_gate.is_empty():
		result["firearm_visual_identity_gate"] = last_firearm_visual_gate.duplicate(true)
	return result


func _is_structural_output_failure(reason: String) -> bool:
	return (
		reason.begins_with("MECHANISM_SCAFFOLD_IMAGE_")
		or reason.begins_with("MECHANISM_SCAFFOLD_TRANSPARENCY_")
		or reason.begins_with("MECHANISM_SCAFFOLD_ALPHA_MUST_")
		or reason.begins_with("MECHANISM_SCAFFOLD_TOO_")
		or reason.begins_with("MECHANISM_SCAFFOLD_ALPHA_IOU_")
		or reason.begins_with("MECHANISM_SCAFFOLD_ANCHOR_ALPHA_")
		or reason.begins_with("FIREARM_VISUAL_")
	)

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
