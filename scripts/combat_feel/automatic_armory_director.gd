class_name AutomaticArmoryDirector
extends RefCounted

const CANDIDATE_PROVIDER := preload("res://scripts/services/automatic_armory_candidate_provider.gd")
const GENERATOR := preload("res://scripts/services/general_weapon_generation_service.gd")
const CAPABILITIES := preload("res://scripts/combat_feel/weapon_capability_catalog.gd")
const LIBRARY := preload("res://scripts/combat_feel/weapon_library_store.gd")
const ROLE_ORDER := CAPABILITIES.ROLE_ORDER
const ROLE_LABELS := CAPABILITIES.LABELS

var state := "idle"
var target_role := ""
var candidate_identity := ""
var candidate_reason_zh := ""
var python_executable := "python"
var existing_identities: Array[String] = []
var excluded_identities: Array[String] = []
var candidate_provider: RefCounted
var generator: RefCounted
var history_store: RefCounted = LIBRARY.new()
var candidate_provider_factory: Callable
var generation_service_factory: Callable
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
		if not identity.is_empty() and identities.size() < 64 and not _contains_identity(identities, identity):
			identities.append(identity.left(80))
		for role: String in CAPABILITIES.roles_for_entry(entry):
			occupied[role] = int(occupied.get(role, 0)) + 1
	var role := ""
	for candidate: String in ROLE_ORDER:
		if int(occupied.get(candidate, 0)) == 0:
			role = candidate
			break
	return {
		"ok": true, "needs_generation": not role.is_empty(), "target_role": role,
		"target_role_label_zh": role_label(role), "existing_identities": identities,
		"occupied_roles": occupied, "player_confirmation_required": false,
	}


func start(entries: Array[Dictionary], next_python_executable: String = "python", initial_excluded_identities: Array[String] = []) -> Dictionary:
	if state in ["candidate", "generating"]:
		return _failure("AUTOMATIC_ARMORY_ALREADY_RUNNING")
	reset()
	python_executable = next_python_executable
	var next_plan := plan(entries)
	if not bool(next_plan.get("needs_generation", false)):
		state = "complete"
		last_result = {"ok": true, "status": "complete", "generated": false, "reason": "mechanism_roles_complete", "player_confirmation_required": false}
		return last_result.duplicate(true)
	target_role = str(next_plan["target_role"])
	existing_identities.assign(next_plan["existing_identities"])
	excluded_identities.append_array(_recent_rejected_identities())
	for identity: String in initial_excluded_identities:
		if not identity.strip_edges().is_empty() and not _contains_identity(excluded_identities, identity):
			excluded_identities.append(identity.left(80))
	candidate_provider = candidate_provider_factory.call() if candidate_provider_factory.is_valid() else CANDIDATE_PROVIDER.new()
	var configured: Dictionary = candidate_provider.configure(python_executable)
	if not bool(configured.get("ok", false)):
		return _finish_failure(str(configured.get("error", "AUTOMATIC_ARMORY_CANDIDATE_UNAVAILABLE")))
	result_delivered = false
	_request_candidate()
	return _running_snapshot()


func poll() -> Dictionary:
	if state in ["complete", "failed"]:
		return _deliver_finished()
	if state == "candidate":
		var response: Dictionary = candidate_provider.poll()
		if str(response.get("status", "")) in ["idle", "running"]:
			return _running_snapshot()
		if str(response.get("status", "")) != "success":
			_finish_failure(str(response.get("failure_reason", "AUTOMATIC_ARMORY_CANDIDATE_FAILED")))
			return _deliver_finished()
		var candidate := response.get("candidate", {}) as Dictionary
		candidate_identity = str(candidate.get("canonical_name", "")).strip_edges()
		candidate_reason_zh = str(candidate.get("selection_reason_zh", ""))
		if candidate_identity.is_empty() or _contains_identity(existing_identities, candidate_identity) or _contains_identity(excluded_identities, candidate_identity):
			return _retry_or_finish("AUTOMATIC_ARMORY_CANDIDATE_DUPLICATE")
		generator = generation_service_factory.call() if generation_service_factory.is_valid() else GENERATOR.new()
		generator.max_visual_requests = mini(2, max_total_visual_requests - total_visual_requests)
		state = "generating"
		var started: Dictionary = generator.start(candidate_identity, python_executable, target_role)
		if str(started.get("status", "")) == "failed":
			return _retry_or_finish(str(started.get("failure_reason", "AUTOMATIC_ARMORY_GENERATION_FAILED")))
		return _running_snapshot()
	if state == "generating":
		var response: Dictionary = generator.poll()
		if str(response.get("status", "")) in ["idle", "running"]:
			return _running_snapshot()
		total_visual_requests += int(response.get("visual_requests", 0))
		if str(response.get("status", "")) != "success":
			return _retry_or_finish(str(response.get("failure_reason", "AUTOMATIC_ARMORY_GENERATION_FAILED")))
		var entry := response.get("entry", {}) as Dictionary
		if target_role not in CAPABILITIES.roles_for_entry(entry):
			return _retry_or_finish("AUTOMATIC_ARMORY_CAPABILITY_MISMATCH")
		state = "complete"
		last_result = {
			"ok": true, "status": "success", "generated": true, "target_role": target_role,
			"target_role_label_zh": role_label(target_role), "candidate_identity": candidate_identity,
			"candidate_reason_zh": candidate_reason_zh, "candidate_attempts": candidate_attempt_count,
			"total_visual_requests": total_visual_requests, "entry": entry,
			"player_confirmation_required": false,
		}
		return _deliver_finished()
	return {"status": "idle"}


func reset() -> void:
	if candidate_provider != null and candidate_provider.has_method("cancel_current"):
		candidate_provider.cancel_current()
	if generator != null and generator.has_method("cancel_current"):
		generator.cancel_current()
	state = "idle"
	target_role = ""
	candidate_identity = ""
	candidate_reason_zh = ""
	existing_identities.clear()
	excluded_identities.clear()
	candidate_provider = null
	generator = null
	candidate_attempt_count = 0
	total_visual_requests = 0
	last_result.clear()
	result_delivered = true


func _request_candidate() -> void:
	candidate_attempt_count += 1
	candidate_identity = ""
	state = "candidate"
	candidate_provider.request_candidate(target_role, existing_identities, excluded_identities)


func _retry_or_finish(error: String) -> Dictionary:
	_record_rejection(error)
	if not candidate_identity.is_empty() and not _contains_identity(excluded_identities, candidate_identity):
		excluded_identities.append(candidate_identity)
	if candidate_attempt_count < max_candidate_attempts and total_visual_requests < max_total_visual_requests:
		if generator != null:
			generator.cancel_current()
		_request_candidate()
		return _running_snapshot()
	_finish_failure(error)
	return _deliver_finished()


func _recent_rejected_identities() -> Array[String]:
	var identities: Array[String] = []
	var session: Dictionary = history_store.read_session()
	for entry: Dictionary in session.get("reward_rejections", []):
		if int(Time.get_unix_time_from_system()) - int(entry.get("time", 0)) <= 86400:
			identities.append(str(entry.get("identity", "")))
	return identities


func _record_rejection(error: String) -> void:
	if candidate_identity.is_empty():
		return
	var session: Dictionary = history_store.read_session()
	var history := (session.get("reward_rejections", []) as Array).duplicate(true)
	history.append({"identity": candidate_identity, "time": int(Time.get_unix_time_from_system()), "error": error, "capability": target_role})
	while history.size() > 32:
		history.remove_at(0)
	history_store.update_session({"reward_rejections": history})


func _finish_failure(error: String) -> Dictionary:
	state = "failed"
	last_result = _failure(error)
	result_delivered = false
	return last_result.duplicate(true)


func _deliver_finished() -> Dictionary:
	if result_delivered:
		return {"status": "idle"}
	result_delivered = true
	return last_result.duplicate(true)


func _running_snapshot() -> Dictionary:
	return {"ok": true, "status": "running", "stage": state, "target_role": target_role, "target_role_label_zh": role_label(target_role), "candidate_identity": candidate_identity, "player_confirmation_required": false}


static func role_label(role: String) -> String:
	return str(ROLE_LABELS.get(role, "新机制武器"))


func _entry_identity(entry: Dictionary) -> String:
	var blueprint := entry.get("blueprint") as WeaponBlueprint
	return str(entry.get("identity", blueprint.player_identity_text if blueprint != null else "")).strip_edges()


func _contains_identity(identities: Array[String], identity: String) -> bool:
	for existing: String in identities:
		if _normalize(existing) == _normalize(identity):
			return true
	return false


func _normalize(value: String) -> String:
	var normalized := value.strip_edges().to_upper()
	for separator: String in [" ", "-", "_", "·", ".", "/", "\\", "（", "）", "(", ")", "&"]:
		normalized = normalized.replace(separator, "")
	return normalized


func _failure(error: String) -> Dictionary:
	return {"ok": false, "status": "failed", "error": error, "failure_reason": error, "target_role": target_role, "candidate_attempts": candidate_attempt_count, "total_visual_requests": total_visual_requests, "player_confirmation_required": false}
