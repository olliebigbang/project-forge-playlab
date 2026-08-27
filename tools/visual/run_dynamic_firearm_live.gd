extends SceneTree

const IDENTITY_RESOLVER := preload("res://scripts/combat_feel/firearm_identity_ai_resolver.gd")
const IDENTITY_PROVIDER := preload("res://scripts/services/firearm_identity_ai_provider.gd")
const INTERPRETER := preload("res://scripts/services/open_identity_interpreter.gd")
const VISUAL_PROVIDER := preload("res://scripts/services/fal_firearm_visual_provider.gd")

var identity := ""
var python_path := "python"
var identity_provider
var visual_provider
var blueprint: WeaponBlueprint
var stage := "idle"
var retry_count := 0
var max_retries := 0
var identity_cache_hit := false
var finished := false


func _initialize() -> void:
	identity = _argument_value("--identity=", "M16A2").strip_edges()
	python_path = _argument_value("--python=", "python").strip_edges()
	max_retries = clampi(int(_argument_value("--max-retries=", "1")), 0, 2)
	if identity.is_empty():
		_finish("DYNAMIC_FIREARM_IDENTITY_EMPTY", 2)
		return
	var cached: Dictionary = IDENTITY_RESOLVER.resolve_identity(identity)
	if bool(cached.get("ok", false)):
		identity_cache_hit = true
		var interpreted: Dictionary = INTERPRETER.new().interpret_with_ai_firearm_profile(
			identity, PackedByteArray(), {}, cached
		)
		if not _accept_interpretation(interpreted):
			return
		_start_visual_request()
		return
	identity_provider = IDENTITY_PROVIDER.new()
	identity_provider.timeout_seconds = 120.0
	var configured: Dictionary = identity_provider.configure(python_path)
	if not bool(configured.get("ok", false)):
		_finish(str(configured.get("error", "DYNAMIC_FIREARM_IDENTITY_PROVIDER_FAILED")), 2)
		return
	stage = "identity"
	identity_provider.request_identity(identity)


func _process(_delta: float) -> bool:
	if finished:
		return false
	if stage == "identity":
		_poll_identity()
	elif stage == "visual":
		_poll_visual()
	return false


func _poll_identity() -> void:
	var result: Dictionary = identity_provider.poll()
	var status := str(result.get("status", ""))
	if status == "running" or status == "idle":
		return
	if status != "success":
		_finish(str(result.get("failure_reason", "DYNAMIC_FIREARM_IDENTITY_FAILED")), 1)
		return
	var response := result.get("response", {}) as Dictionary
	var accepted: Dictionary = IDENTITY_RESOLVER.accept_ai_response(
		identity,
		response,
		str(result.get("source", "")),
		true
	)
	if not bool(accepted.get("ok", false)):
		_finish(str(accepted.get("error", "DYNAMIC_FIREARM_IDENTITY_REJECTED")), 1)
		return
	var interpreted: Dictionary = INTERPRETER.new().interpret_with_ai_firearm_profile(
		identity, PackedByteArray(), {}, accepted
	)
	if not _accept_interpretation(interpreted):
		return
	_start_visual_request()


func _accept_interpretation(interpreted: Dictionary) -> bool:
	if not bool(interpreted.get("ok", false)):
		_finish(str(interpreted.get("error", "DYNAMIC_FIREARM_INTERPRETATION_FAILED")), 1)
		return false
	if bool(interpreted.get("player_confirmation_required", true)):
		_finish("DYNAMIC_FIREARM_PLAYER_CONFIRMATION_FORBIDDEN", 2)
		return false
	blueprint = interpreted.get("blueprint") as WeaponBlueprint
	if blueprint == null or blueprint.behavior_family != "sustained_ranged":
		_finish("DYNAMIC_FIREARM_BLUEPRINT_INVALID", 1)
		return false
	if not str(blueprint.modifiers.get("firearm_identity_id", "")).begins_with("ai_"):
		_finish("DYNAMIC_FIREARM_AI_IDENTITY_ID_MISSING", 2)
		return false
	if str(blueprint.modifiers.get("firearm_visual_reference_id", "")) != "auto_wikimedia_v1":
		_finish("DYNAMIC_FIREARM_AUTO_REFERENCE_MISSING", 2)
		return false
	return true


func _start_visual_request() -> void:
	visual_provider = VISUAL_PROVIDER.new()
	visual_provider.timeout_seconds = 600.0
	var configured: Dictionary = visual_provider.configure(python_path)
	if not bool(configured.get("ok", false)):
		_finish(str(configured.get("error", "DYNAMIC_FIREARM_VISUAL_PROVIDER_FAILED")), 2)
		return
	stage = "visual"
	visual_provider.request_visual(blueprint, identity, PackedByteArray(), 0.0)


func _poll_visual() -> void:
	var result: Dictionary = visual_provider.poll()
	var status := str(result.get("status", ""))
	if status == "running" or status == "idle":
		return
	if (
		status == "failed"
		and bool(result.get("retry_required", false))
		and retry_count < max_retries
	):
		retry_count += 1
		blueprint.modifiers["mechanism_visual_retry_count"] = retry_count
		blueprint.modifiers["mechanism_visual_retry_prompt"] = str(result.get(
			"retry_prompt",
			"Preserve the exact named firearm and make every required silhouette landmark readable."
		))
		print("DYNAMIC_FIREARM_LIVE_RETRY=%d:%s" % [
			retry_count, str(result.get("failure_reason", "")),
		])
		_start_visual_request()
		return
	var manifest := result.get("manifest", {}) as Dictionary
	var reference := manifest.get("identity_reference", {}) as Dictionary
	var visual_verification := manifest.get("ai_visual_identity_verification", {}) as Dictionary
	var gate := result.get("firearm_visual_identity_gate", {}) as Dictionary
	var safe_result := {
		"status": status,
		"failure_reason": str(result.get("failure_reason", "")),
		"identity": identity,
		"canonical_identity": blueprint.display_name,
		"identity_cache_hit": identity_cache_hit,
		"identity_id": str(blueprint.modifiers.get("firearm_identity_id", "")),
		"output_directory": str(result.get("output_directory", "")),
		"reference_used": bool(reference.get("used", false)),
		"reference_id": str(reference.get("reference_id", "")),
		"reference_license": str(reference.get("license", "")),
		"reference_source_page": str(reference.get("source_page", "")),
		"reference_cache_hit": bool((reference.get("source_fetch", {}) as Dictionary).get("cache_hit", false)),
		"visual_cache_hit": bool((manifest.get("cache", {}) as Dictionary).get("hit", false)),
		"reference_verification_passed": bool((reference.get("automatic_reference_verification", {}) as Dictionary).get("passed", false)),
		"candidate_verification_passed": bool(visual_verification.get("passed", false)),
		"godot_gate_passed": bool(gate.get("ok", false)),
		"finished_art": bool(manifest.get("finished_art", false)),
		"presentable_to_player": bool(manifest.get("presentable_to_player", false)),
		"automatic_retries": retry_count,
		"player_confirmation_required": false,
	}
	print("DYNAMIC_FIREARM_LIVE_RESULT=%s" % JSON.stringify(safe_result))
	finished = true
	quit(0 if status == "success" else 1)


func _finish(error: String, code: int) -> void:
	if finished:
		return
	finished = true
	print("DYNAMIC_FIREARM_LIVE_RESULT=%s" % JSON.stringify({
		"status": "failed",
		"failure_reason": error,
		"identity": identity,
		"player_confirmation_required": false,
	}))
	quit(code)


func _argument_value(prefix: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return fallback
