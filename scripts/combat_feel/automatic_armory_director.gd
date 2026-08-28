class_name AutomaticArmoryDirector
extends RefCounted

const CANDIDATE_PROVIDER := preload("res://scripts/services/automatic_armory_candidate_provider.gd")
const IDENTITY_PROVIDER := preload("res://scripts/services/firearm_identity_ai_provider.gd")
const IDENTITY_RESOLVER := preload("res://scripts/combat_feel/firearm_identity_ai_resolver.gd")
const INTERPRETER := preload("res://scripts/services/open_identity_interpreter.gd")
const VISUAL_PROVIDER := preload("res://scripts/services/fal_firearm_visual_provider.gd")
const RANGED_AXES := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")
const REJECTION_HISTORY_PATH := "user://playlab/automatic_armory/rejected_candidates_v1.json"
const REJECTION_HISTORY_SCHEMA := "forge-automatic-armory-rejections-v1"
const REJECTION_COOLDOWN_SECONDS := 86400

const ROLE_ORDER: Array[String] = [
	"close_quarters", "precision", "sidearm", "scatter", "support", "service",
]
const ROLE_LABELS := {
	"close_quarters": "近距离快速武器",
	"precision": "远距离精确武器",
	"sidearm": "轻便副武器",
	"scatter": "近距离霰弹武器",
	"support": "持续火力武器",
	"service": "通用步枪",
}

var state := "idle"
var target_role := ""
var candidate_identity := ""
var candidate_reason_zh := ""
var python_executable := "python"
var existing_identities: Array[String] = []
var excluded_identities: Array[String] = []
var candidate_provider: RefCounted
var identity_provider: RefCounted
var visual_provider: RefCounted
var blueprint: WeaponBlueprint
var retry_count := 0
var max_visual_retries := 1
var candidate_attempt_count := 0
var max_candidate_attempts := 2
var total_visual_requests := 0
var max_total_visual_requests := 3
var last_result: Dictionary = {}
var result_delivered := true


func plan(entries: Array[Dictionary]) -> Dictionary:
	var occupied := {}
	var identities: Array[String] = []
	for entry: Dictionary in entries:
		var identity := _entry_identity(entry)
		if not identity.is_empty():
			identities.append(identity)
		var role := role_for_entry(entry)
		if not role.is_empty():
			occupied[role] = int(occupied.get(role, 0)) + 1
	for role: String in ROLE_ORDER:
		if int(occupied.get(role, 0)) == 0:
			return {
				"ok": true,
				"needs_generation": true,
				"target_role": role,
				"target_role_label_zh": role_label(role),
				"existing_identities": identities,
				"occupied_roles": occupied.duplicate(true),
				"player_confirmation_required": false,
			}
	return {
		"ok": true,
		"needs_generation": false,
		"target_role": "",
		"existing_identities": identities,
		"occupied_roles": occupied.duplicate(true),
		"player_confirmation_required": false,
	}


func start(
	entries: Array[Dictionary],
	next_python_executable: String = "python",
	initial_excluded_identities: Array[String] = []
) -> Dictionary:
	if state in ["candidate", "identity", "visual"]:
		return _failure("AUTOMATIC_ARMORY_ALREADY_RUNNING")
	reset()
	python_executable = next_python_executable.strip_edges()
	if python_executable.is_empty():
		python_executable = "python"
	var next_plan := plan(entries)
	if not bool(next_plan.get("needs_generation", false)):
		state = "complete"
		last_result = {
			"ok": true,
			"status": "complete",
			"generated": false,
			"reason": "mechanism_roles_complete",
			"player_confirmation_required": false,
		}
		return last_result.duplicate(true)
	target_role = str(next_plan.get("target_role", ""))
	for raw_identity: Variant in next_plan.get("existing_identities", []):
		existing_identities.append(str(raw_identity))
	excluded_identities.append_array(_recent_rejected_identities())
	for identity: String in initial_excluded_identities:
		if not identity.strip_edges().is_empty() and not _contains_identity(excluded_identities, identity):
			excluded_identities.append(identity.strip_edges())
	candidate_provider = CANDIDATE_PROVIDER.new()
	var configured: Dictionary = candidate_provider.configure(python_executable)
	if not bool(configured.get("ok", false)):
		return _finish_failure(str(configured.get(
			"error", "AUTOMATIC_ARMORY_CANDIDATE_PROVIDER_UNAVAILABLE"
		)))
	result_delivered = false
	_request_candidate()
	return {
		"ok": true,
		"status": "running",
		"stage": state,
		"target_role": target_role,
		"target_role_label_zh": role_label(target_role),
		"player_confirmation_required": false,
	}


func poll() -> Dictionary:
	if state in ["complete", "failed"]:
		return _deliver_finished()
	if state == "candidate":
		var candidate_result: Dictionary = candidate_provider.poll()
		var candidate_status := str(candidate_result.get("status", ""))
		if candidate_status in ["running", "idle"]:
			return _running_snapshot()
		if candidate_status != "success":
			_finish_failure(str(candidate_result.get(
				"failure_reason", "AUTOMATIC_ARMORY_CANDIDATE_SELECTION_FAILED"
			)))
			return _deliver_finished()
		var candidate := candidate_result.get("candidate", {}) as Dictionary
		candidate_identity = str(candidate.get("canonical_name", "")).strip_edges()
		candidate_reason_zh = str(candidate.get("selection_reason_zh", "")).strip_edges()
		if candidate_identity.is_empty() or _identity_already_present(candidate_identity):
			if _try_next_candidate("AUTOMATIC_ARMORY_CANDIDATE_DUPLICATE"):
				return _running_snapshot()
			_finish_failure("AUTOMATIC_ARMORY_CANDIDATE_DUPLICATE")
			return _deliver_finished()
		_start_identity_resolution()
		if state == "failed":
			return _deliver_finished()
		return _running_snapshot()
	if state == "identity":
		var identity_result: Dictionary = identity_provider.poll()
		var identity_status := str(identity_result.get("status", ""))
		if identity_status in ["running", "idle"]:
			return _running_snapshot()
		if identity_status != "success":
			var identity_error := str(identity_result.get(
				"failure_reason", "AUTOMATIC_ARMORY_IDENTITY_FAILED"
			))
			if _try_next_candidate(identity_error):
				return _running_snapshot()
			_finish_failure(identity_error)
			return _deliver_finished()
		var accepted: Dictionary = IDENTITY_RESOLVER.accept_ai_response(
			candidate_identity,
			identity_result.get("response", {}) as Dictionary,
			str(identity_result.get("source", "")),
			true
		)
		if not bool(accepted.get("ok", false)):
			var accepted_error := str(accepted.get("error", "AUTOMATIC_ARMORY_IDENTITY_REJECTED"))
			if _try_next_candidate(accepted_error):
				return _running_snapshot()
			_finish_failure(accepted_error)
			return _deliver_finished()
		_accept_identity_profile(accepted)
		if state == "failed":
			return _deliver_finished()
		return _running_snapshot()
	if state == "visual":
		var visual_result: Dictionary = visual_provider.poll()
		var visual_status := str(visual_result.get("status", ""))
		if visual_status in ["running", "idle"]:
			return _running_snapshot()
		if (
			visual_status == "failed"
			and bool(visual_result.get("retry_required", false))
			and retry_count < max_visual_retries
			and total_visual_requests < max_total_visual_requests
		):
			retry_count += 1
			blueprint.modifiers["mechanism_visual_retry_count"] = retry_count
			blueprint.modifiers["mechanism_visual_retry_prompt"] = str(visual_result.get(
				"retry_prompt",
				"Preserve the exact named firearm and make every required silhouette landmark readable."
			))
			visual_provider.request_visual(
				blueprint, candidate_identity, PackedByteArray(), 0.0
			)
			total_visual_requests += 1
			return _running_snapshot()
		if visual_status != "success":
			var visual_error := str(visual_result.get(
				"failure_reason", "AUTOMATIC_ARMORY_VISUAL_FAILED"
			))
			if _try_next_candidate(visual_error):
				return _running_snapshot()
			_record_rejection(visual_error)
			_finish_failure(visual_error)
			return _deliver_finished()
		_finish_success(visual_result)
		return _deliver_finished()
	return {"status": "idle"}


func reset() -> void:
	if candidate_provider != null and candidate_provider.has_method("cancel_current"):
		candidate_provider.cancel_current()
	if identity_provider != null and identity_provider.has_method("cancel_current"):
		identity_provider.cancel_current()
	if visual_provider != null and visual_provider.has_method("cancel_current"):
		visual_provider.cancel_current()
	state = "idle"
	target_role = ""
	candidate_identity = ""
	candidate_reason_zh = ""
	existing_identities.clear()
	excluded_identities.clear()
	candidate_provider = null
	identity_provider = null
	visual_provider = null
	blueprint = null
	retry_count = 0
	candidate_attempt_count = 0
	total_visual_requests = 0
	last_result.clear()
	result_delivered = true


func _start_identity_resolution() -> void:
	var cached: Dictionary = IDENTITY_RESOLVER.resolve_identity(candidate_identity)
	if bool(cached.get("ok", false)):
		_accept_identity_profile(cached)
		return
	identity_provider = IDENTITY_PROVIDER.new()
	identity_provider.timeout_seconds = 120.0
	var configured: Dictionary = identity_provider.configure(python_executable)
	if not bool(configured.get("ok", false)):
		_finish_failure(str(configured.get("error", "AUTOMATIC_ARMORY_IDENTITY_PROVIDER_FAILED")))
		return
	state = "identity"
	identity_provider.request_identity(candidate_identity)


func _accept_identity_profile(profile: Dictionary) -> void:
	var interpreted: Dictionary = INTERPRETER.new().interpret_with_ai_firearm_profile(
		candidate_identity, PackedByteArray(), {}, profile
	)
	if not bool(interpreted.get("ok", false)):
		_finish_failure(str(interpreted.get("error", "AUTOMATIC_ARMORY_INTERPRETATION_FAILED")))
		return
	if bool(interpreted.get("player_confirmation_required", true)):
		_finish_failure("AUTOMATIC_ARMORY_PLAYER_CONFIRMATION_FORBIDDEN")
		return
	blueprint = interpreted.get("blueprint") as WeaponBlueprint
	if blueprint == null or blueprint.behavior_family != "sustained_ranged":
		_finish_failure("AUTOMATIC_ARMORY_BLUEPRINT_INVALID")
		return
	var actual_role := role_for_declaration(blueprint.affordance)
	if actual_role != target_role:
		if not _try_next_candidate("AUTOMATIC_ARMORY_MECHANISM_ROLE_MISMATCH"):
			_finish_failure("AUTOMATIC_ARMORY_MECHANISM_ROLE_MISMATCH")
		return
	visual_provider = VISUAL_PROVIDER.new()
	visual_provider.timeout_seconds = 600.0
	var configured: Dictionary = visual_provider.configure(python_executable)
	if not bool(configured.get("ok", false)):
		_finish_failure(str(configured.get("error", "AUTOMATIC_ARMORY_VISUAL_PROVIDER_FAILED")))
		return
	state = "visual"
	visual_provider.request_visual(blueprint, candidate_identity, PackedByteArray(), 0.0)
	total_visual_requests += 1


func _finish_success(visual_result: Dictionary) -> void:
	var asset := visual_result.get("asset") as WeaponVisualAsset
	var runtime: Dictionary = RANGED_AXES.compile(
		blueprint.affordance, blueprint.affordance_source
	)
	if asset == null or not bool(runtime.get("ok", false)):
		_finish_failure("AUTOMATIC_ARMORY_FINAL_HANDOFF_INVALID")
		return
	blueprint.modifiers["ranged_runtime_profile"] = runtime.duplicate(true)
	var output_directory := str(visual_result.get("output_directory", ""))
	var entry := {
		"ok": true,
		"identity": candidate_identity,
		"display_name": blueprint.display_name,
		"blueprint": blueprint,
		"asset": asset,
		"ranged_runtime_profile": runtime.duplicate(true),
		"sprite_path": output_directory.path_join("processed_sprite.png"),
		"cache_directory": output_directory,
		"source_kind": "automatic_armory_generated",
		"cache_status": str(visual_result.get("cache_status", "generated_then_cached")),
		"paid_api_call_used_for_selection": true,
	}
	state = "complete"
	last_result = {
		"ok": true,
		"status": "success",
		"generated": true,
		"target_role": target_role,
		"target_role_label_zh": role_label(target_role),
		"candidate_identity": candidate_identity,
		"candidate_reason_zh": candidate_reason_zh,
		"automatic_retries": retry_count,
		"candidate_attempts": candidate_attempt_count,
		"total_visual_requests": total_visual_requests,
		"entry": entry,
		"player_confirmation_required": false,
	}


func _finish_failure(error: String) -> Dictionary:
	state = "failed"
	last_result = {
		"ok": false,
		"status": "failed",
		"failure_reason": error,
		"target_role": target_role,
		"target_role_label_zh": role_label(target_role),
		"candidate_identity": candidate_identity,
		"automatic_retries": retry_count,
		"candidate_attempts": candidate_attempt_count,
		"total_visual_requests": total_visual_requests,
		"player_confirmation_required": false,
	}
	result_delivered = false
	return last_result.duplicate(true)


func _deliver_finished() -> Dictionary:
	if result_delivered:
		return {"status": "idle"}
	result_delivered = true
	return last_result.duplicate(true)


func _running_snapshot() -> Dictionary:
	return {
		"status": "running",
		"stage": state,
		"target_role": target_role,
		"target_role_label_zh": role_label(target_role),
		"candidate_identity": candidate_identity,
		"player_confirmation_required": false,
	}


func _identity_already_present(identity: String) -> bool:
	var normalized := _normalize(identity)
	for existing: String in existing_identities:
		if _normalize(existing) == normalized:
			return true
	return false


func _request_candidate() -> void:
	candidate_attempt_count += 1
	candidate_identity = ""
	candidate_reason_zh = ""
	blueprint = null
	retry_count = 0
	state = "candidate"
	candidate_provider.request_candidate(target_role, existing_identities, excluded_identities)


func _try_next_candidate(error: String) -> bool:
	if candidate_identity.is_empty() or candidate_attempt_count >= max_candidate_attempts:
		return false
	if total_visual_requests >= max_total_visual_requests:
		return false
	_record_rejection(error)
	if not _contains_identity(excluded_identities, candidate_identity):
		excluded_identities.append(candidate_identity)
	_request_candidate()
	return true


func _recent_rejected_identities() -> Array[String]:
	var result: Array[String] = []
	if not FileAccess.file_exists(REJECTION_HISTORY_PATH):
		return result
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REJECTION_HISTORY_PATH))
	if not parsed is Dictionary:
		return result
	var history := parsed as Dictionary
	if str(history.get("schema", "")) != REJECTION_HISTORY_SCHEMA:
		return result
	var now := int(Time.get_unix_time_from_system())
	for raw_entry: Variant in history.get("entries", []):
		if not raw_entry is Dictionary:
			continue
		var entry := raw_entry as Dictionary
		var identity := str(entry.get("identity", "")).strip_edges()
		var rejected_at := int(entry.get("rejected_unix_time", 0))
		if not identity.is_empty() and now - rejected_at <= REJECTION_COOLDOWN_SECONDS:
			if not _contains_identity(result, identity):
				result.append(identity)
	return result


func _record_rejection(error: String) -> void:
	if candidate_identity.is_empty():
		return
	var history := {
		"schema": REJECTION_HISTORY_SCHEMA,
		"entries": [],
	}
	if FileAccess.file_exists(REJECTION_HISTORY_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REJECTION_HISTORY_PATH))
		if parsed is Dictionary and str((parsed as Dictionary).get("schema", "")) == REJECTION_HISTORY_SCHEMA:
			history = (parsed as Dictionary).duplicate(true)
	var entries := history.get("entries", []) as Array
	var retained: Array[Dictionary] = []
	for raw_entry: Variant in entries:
		if not raw_entry is Dictionary:
			continue
		var entry := raw_entry as Dictionary
		if _normalize(str(entry.get("identity", ""))) != _normalize(candidate_identity):
			retained.append(entry.duplicate(true))
	retained.append({
		"identity": candidate_identity,
		"target_role": target_role,
		"failure_reason": error,
		"rejected_unix_time": int(Time.get_unix_time_from_system()),
	})
	while retained.size() > 32:
		retained.remove_at(0)
	history["entries"] = retained
	_write_json_atomic(REJECTION_HISTORY_PATH, history)


func _contains_identity(identities: Array[String], identity: String) -> bool:
	var normalized := _normalize(identity)
	for existing: String in identities:
		if _normalize(existing) == normalized:
			return true
	return false


func _write_json_atomic(target: String, value: Dictionary) -> Error:
	var absolute_target := ProjectSettings.globalize_path(target)
	if DirAccess.make_dir_recursive_absolute(absolute_target.get_base_dir()) != OK:
		return ERR_CANT_CREATE
	var temporary := "%s.%s.tmp" % [absolute_target, str(Time.get_ticks_usec())]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(value, "  "))
	file.close()
	if FileAccess.file_exists(absolute_target):
		DirAccess.remove_absolute(absolute_target)
	var error := DirAccess.rename_absolute(temporary, absolute_target)
	if error != OK and FileAccess.file_exists(temporary):
		DirAccess.remove_absolute(temporary)
	return error


static func role_for_entry(entry: Dictionary) -> String:
	var blueprint_value := entry.get("blueprint") as WeaponBlueprint
	if blueprint_value == null:
		return ""
	return role_for_declaration(blueprint_value.affordance)


static func role_for_declaration(declaration: Dictionary) -> String:
	var family := str(declaration.get("firearm_family", ""))
	var action := str(declaration.get("action_mechanism", ""))
	if family == "submachine_gun":
		return "close_quarters"
	if family == "precision_rifle" or action == "bolt_action":
		return "precision"
	if family in ["semi_auto_pistol", "revolver"]:
		return "sidearm"
	if family == "shotgun":
		return "scatter"
	if family == "light_machine_gun":
		return "support"
	if family == "rifle":
		return "service"
	return ""


static func role_label(role: String) -> String:
	return str(ROLE_LABELS.get(role, "新机制武器"))


func _entry_identity(entry: Dictionary) -> String:
	var identity := str(entry.get("identity", "")).strip_edges()
	if not identity.is_empty():
		return identity
	var blueprint_value := entry.get("blueprint") as WeaponBlueprint
	return blueprint_value.display_name if blueprint_value != null else ""


func _normalize(value: String) -> String:
	var normalized := value.strip_edges().to_upper()
	for separator: String in [" ", "-", "_", "·", ".", "/", "\\", "（", "）", "(", ")", "&"]:
		normalized = normalized.replace(separator, "")
	return normalized


func _failure(error: String) -> Dictionary:
	return {
		"ok": false,
		"status": "failed",
		"error": error,
		"failure_reason": error,
		"player_confirmation_required": false,
	}
