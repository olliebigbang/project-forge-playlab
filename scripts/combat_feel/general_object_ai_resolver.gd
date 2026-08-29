class_name GeneralObjectAIResolver
extends RefCounted

const MECHANISM_AXES := preload("res://scripts/combat_feel/mechanism_axis_resolver.gd")
const AFFORDANCE_PROFILE := preload("res://scripts/combat_feel/object_affordance_profile.gd")

const CACHE_PATH := "user://playlab/general_object_ai/cache_v1.json"
const CACHE_SCHEMA := "forge-general-object-ai-cache-v1"
const RESPONSE_SCHEMA := "forge-general-object-ai-response-v1"
const SUPPORTED_CLASSIFICATION := "improvised_object_supported"
const CLASSIFICATIONS: PackedStringArray = [
	SUPPORTED_CLASSIFICATION,
	"firearm_route_required",
	"powered_vehicle_actor_required",
	"living_actor_required",
	"unknown",
]
const SCALE_TREATMENTS: PackedStringArray = ["handheld", "bulky_two_hand", "oversized_fantasy"]
const MAX_CACHE_ENTRIES := 256
const MIN_ACCEPTED_CONFIDENCE := 0.72


static func resolve_identity(player_text: String, cache_path: String = CACHE_PATH) -> Dictionary:
	var normalized := _normalize(player_text)
	if normalized.is_empty():
		return _failure("AI_GENERAL_OBJECT_IDENTITY_EMPTY")
	var cache := _load_cache(cache_path)
	if not bool(cache.get("ok", false)):
		return _failure("AI_GENERAL_OBJECT_IDENTITY_NOT_CACHED")
	for raw_entry: Variant in cache.get("entries", []):
		if not raw_entry is Dictionary:
			continue
		var entry := raw_entry as Dictionary
		if str(entry.get("normalized_identity", "")) != normalized:
			continue
		var profile := entry.get("profile", {}) as Dictionary
		var validation := _validate_cached_profile(profile)
		if not bool(validation.get("ok", false)):
			return validation
		var result := profile.duplicate(true)
		result["ok"] = true
		result["matched_identity"] = player_text.strip_edges()
		result["cache_hit"] = true
		result["player_confirmation_required"] = false
		return result
	return _failure("AI_GENERAL_OBJECT_IDENTITY_NOT_CACHED")


static func accept_ai_response(
	player_text: String,
	payload: Dictionary,
	source: String,
	persist: bool = true,
	cache_path: String = CACHE_PATH
) -> Dictionary:
	var validation := validate_ai_response(player_text, payload, source)
	if not bool(validation.get("ok", false)):
		return validation
	var profile := (validation.get("profile", {}) as Dictionary).duplicate(true)
	if persist:
		var stored := _store_profile(player_text, profile, str(payload.get("model_id", "")), cache_path)
		if not bool(stored.get("ok", false)):
			return stored
	var result := profile.duplicate(true)
	result["ok"] = true
	result["matched_identity"] = player_text.strip_edges()
	result["cache_hit"] = false
	result["player_confirmation_required"] = false
	return result


static func validate_ai_response(player_text: String, payload: Dictionary, source: String) -> Dictionary:
	if payload.is_empty():
		return _failure("AI_GENERAL_OBJECT_RESPONSE_MISSING")
	if str(payload.get("schema", "")) != RESPONSE_SCHEMA:
		return _failure("AI_GENERAL_OBJECT_RESPONSE_SCHEMA_INVALID")
	if str(payload.get("requested_identity", "")).strip_edges() != player_text.strip_edges():
		return _failure("AI_GENERAL_OBJECT_IDENTITY_ECHO_MISMATCH")
	var classification := str(payload.get("classification", ""))
	if classification not in CLASSIFICATIONS:
		return _failure("AI_GENERAL_OBJECT_CLASSIFICATION_INVALID")
	var confidence := float(payload.get("confidence", -1.0))
	if confidence < 0.0 or confidence > 1.0:
		return _failure("AI_GENERAL_OBJECT_CONFIDENCE_INVALID")
	if classification != SUPPORTED_CLASSIFICATION:
		return _classification_failure(classification, confidence)
	if confidence < MIN_ACCEPTED_CONFIDENCE:
		return _failure("AI_GENERAL_OBJECT_CONFIDENCE_TOO_LOW")
	if str(payload.get("behavior_family", "")) != "heavy_melee":
		return _failure("AI_GENERAL_OBJECT_BEHAVIOR_FAMILY_INVALID")
	var scale_treatment := str(payload.get("scale_treatment", ""))
	if scale_treatment not in SCALE_TREATMENTS:
		return _failure("AI_GENERAL_OBJECT_SCALE_TREATMENT_INVALID")
	var canonical_name := str(payload.get("canonical_name", "")).strip_edges()
	var visual_description := str(payload.get("visual_description_en", "")).strip_edges()
	if canonical_name.is_empty() or canonical_name.length() > 96:
		return _failure("AI_GENERAL_OBJECT_CANONICAL_NAME_INVALID")
	if visual_description.length() < 12 or visual_description.length() > 360:
		return _failure("AI_GENERAL_OBJECT_VISUAL_DESCRIPTION_INVALID")
	var visible_parts := _validated_string_array(payload.get("required_identity_parts_zh", []), 2, 6, 64)
	if not bool(visible_parts.get("ok", false)):
		return _failure("AI_GENERAL_OBJECT_VISIBLE_PARTS_INVALID")
	var evidence := _validated_string_array(payload.get("identity_evidence", []), 1, 6, 240)
	if not bool(evidence.get("ok", false)):
		return _failure("AI_GENERAL_OBJECT_IDENTITY_EVIDENCE_INVALID")
	var exclusions := _validated_string_array(payload.get("confusable_exclusions_en", []), 1, 8, 220)
	if not bool(exclusions.get("ok", false)):
		return _failure("AI_GENERAL_OBJECT_VISUAL_EXCLUSIONS_INVALID")
	if not payload.get("declaration", {}) is Dictionary:
		return _failure("AI_GENERAL_OBJECT_DECLARATION_INVALID")
	var declaration := (payload.get("declaration", {}) as Dictionary).duplicate(true)
	_canonicalize_redundant_contact_flags(declaration)
	declaration["confidence"] = confidence
	declaration["evidence_parts"] = evidence.get("values", [])
	declaration["source"] = source.strip_edges()
	var axis_validation := MECHANISM_AXES.validate_ai_declaration(declaration, source)
	if not bool(axis_validation.get("ok", false)):
		var rejected := axis_validation.duplicate(true)
		rejected["player_confirmation_required"] = false
		return rejected
	var relationship_errors := _declaration_relationship_errors(declaration)
	if not relationship_errors.is_empty():
		return _failure("AI_GENERAL_OBJECT_DECLARATION_CONFLICT:%s" % ",".join(relationship_errors))
	var profile := {
		"id": "object_%s" % _normalize(player_text).sha256_text().left(16),
		"canonical_name": canonical_name,
		"aliases": [player_text.strip_edges(), canonical_name],
		"visual_description_en": visual_description,
		"required_identity_parts_zh": visible_parts.get("values", []),
		"confusable_exclusions_en": exclusions.get("values", []),
		"identity_evidence": evidence.get("values", []),
		"behavior_family": "heavy_melee",
		"scale_treatment": scale_treatment,
		"declaration": declaration,
		"ai_model_id": str(payload.get("model_id", "")),
		"player_confirmation_required": false,
	}
	return {
		"ok": true,
		"profile": profile,
		"classification": classification,
		"confidence": confidence,
		"source": source.strip_edges(),
		"player_confirmation_required": false,
	}


static func _canonicalize_redundant_contact_flags(declaration: Dictionary) -> void:
	var surfaces: Array[String] = [
		str(declaration.get("contact_surface", "")),
		str(declaration.get("secondary_contact_surface", "")),
	]
	for requirement: Array in [
		["point", "has_point"],
		["edge", "has_edge"],
		["broad", "has_broad_face"],
	]:
		if str(requirement[0]) in surfaces:
			declaration[str(requirement[1])] = true


static func _classification_failure(classification: String, confidence: float) -> Dictionary:
	var error := "AI_GENERAL_OBJECT_IDENTITY_UNCERTAIN"
	match classification:
		"firearm_route_required":
			error = "AI_GENERAL_OBJECT_FIREARM_ROUTE_REQUIRED"
		"powered_vehicle_actor_required":
			error = "AI_GENERAL_OBJECT_POWERED_VEHICLE_ACTOR_REQUIRED"
		"living_actor_required":
			error = "AI_GENERAL_OBJECT_LIVING_ACTOR_REQUIRED"
	return {
		"ok": false,
		"error": error,
		"classification": classification,
		"confidence": confidence,
		"recognized_by_ai": classification != "unknown",
		"player_confirmation_required": false,
	}


static func _validated_string_array(value: Variant, minimum: int, maximum: int, max_length: int) -> Dictionary:
	if not value is Array:
		return {"ok": false}
	var raw_values := value as Array
	if raw_values.size() < minimum or raw_values.size() > maximum:
		return {"ok": false}
	var values: Array[String] = []
	for raw_value: Variant in raw_values:
		var text := str(raw_value).strip_edges()
		if text.is_empty() or text.length() > max_length or text in values:
			return {"ok": false}
		values.append(text)
	return {"ok": true, "values": values}


static func _declaration_relationship_errors(declaration: Dictionary) -> Array[String]:
	var profile: ObjectAffordanceProfile = AFFORDANCE_PROFILE.new()
	for axis: String in MECHANISM_AXES.REQUIRED_AXES:
		profile.set(axis, str(declaration.get(axis, "")))
	for flag: String in MECHANISM_AXES.REQUIRED_FLAGS:
		profile.set(flag, bool(declaration.get(flag, false)))
	profile.confidence = float(declaration.get("confidence", 0.0))
	var evidence := PackedStringArray()
	for raw_evidence: Variant in declaration.get("evidence_parts", []):
		evidence.append(str(raw_evidence))
	profile.evidence_parts = evidence
	var errors := profile.validation_errors()
	var surfaces: Array[String] = [profile.contact_surface, profile.secondary_contact_surface]
	for requirement: Array in [
		["point", "has_point"],
		["edge", "has_edge"],
		["broad", "has_broad_face"],
	]:
		if str(requirement[0]) in surfaces and not bool(declaration.get(str(requirement[1]), false)):
			errors.append("CONTACT_REQUIRES_%s" % str(requirement[1]).to_upper())
	return errors


static func _validate_cached_profile(profile: Dictionary) -> Dictionary:
	if profile.is_empty() or not profile.get("declaration", {}) is Dictionary:
		return _failure("AI_GENERAL_OBJECT_CACHE_PROFILE_INVALID")
	var declaration := profile.get("declaration", {}) as Dictionary
	var source := str(declaration.get("source", ""))
	var validation := MECHANISM_AXES.validate_ai_declaration(declaration, source)
	if not bool(validation.get("ok", false)):
		return _failure("AI_GENERAL_OBJECT_CACHE_PROFILE_INVALID")
	if str(profile.get("canonical_name", "")).strip_edges().is_empty():
		return _failure("AI_GENERAL_OBJECT_CACHE_PROFILE_INVALID")
	if str(profile.get("behavior_family", "")) != "heavy_melee":
		return _failure("AI_GENERAL_OBJECT_CACHE_PROFILE_INVALID")
	if str(profile.get("scale_treatment", "")) not in SCALE_TREATMENTS:
		return _failure("AI_GENERAL_OBJECT_CACHE_PROFILE_INVALID")
	return {"ok": true}


static func _load_cache(cache_path: String) -> Dictionary:
	var absolute_path := ProjectSettings.globalize_path(cache_path)
	if not FileAccess.file_exists(absolute_path):
		return {"ok": true, "schema": CACHE_SCHEMA, "entries": []}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(absolute_path))
	if not parsed is Dictionary:
		return _failure("AI_GENERAL_OBJECT_CACHE_INVALID_JSON")
	var cache := parsed as Dictionary
	if str(cache.get("schema", "")) != CACHE_SCHEMA or not cache.get("entries", []) is Array:
		return _failure("AI_GENERAL_OBJECT_CACHE_SCHEMA_INVALID")
	var result := cache.duplicate(true)
	result["ok"] = true
	return result


static func _store_profile(player_text: String, profile: Dictionary, model_id: String, cache_path: String) -> Dictionary:
	var cache := _load_cache(cache_path)
	if not bool(cache.get("ok", false)):
		cache = {"ok": true, "schema": CACHE_SCHEMA, "entries": []}
	var normalized := _normalize(player_text)
	var next_entries: Array = []
	for raw_entry: Variant in cache.get("entries", []):
		if raw_entry is Dictionary and str((raw_entry as Dictionary).get("normalized_identity", "")) != normalized:
			next_entries.append((raw_entry as Dictionary).duplicate(true))
	next_entries.append({
		"normalized_identity": normalized,
		"player_identity_text": player_text.strip_edges(),
		"profile": profile.duplicate(true),
		"model_id": model_id,
		"cached_unix_time": int(Time.get_unix_time_from_system()),
	})
	while next_entries.size() > MAX_CACHE_ENTRIES:
		next_entries.pop_front()
	var absolute_path := ProjectSettings.globalize_path(cache_path)
	if DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir()) != OK:
		return _failure("AI_GENERAL_OBJECT_CACHE_DIRECTORY_CREATE_FAILED")
	var temporary_path := absolute_path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return _failure("AI_GENERAL_OBJECT_CACHE_TEMP_WRITE_FAILED")
	file.store_string(JSON.stringify({"schema": CACHE_SCHEMA, "entries": next_entries}, "  "))
	file.close()
	if FileAccess.file_exists(absolute_path) and DirAccess.remove_absolute(absolute_path) != OK:
		return _failure("AI_GENERAL_OBJECT_CACHE_REPLACE_FAILED")
	if DirAccess.rename_absolute(temporary_path, absolute_path) != OK:
		return _failure("AI_GENERAL_OBJECT_CACHE_ATOMIC_RENAME_FAILED")
	return {"ok": true, "path": absolute_path}


static func _normalize(value: String) -> String:
	var normalized := value.strip_edges().to_upper()
	for separator: String in [" ", "-", "_", "·", ".", "/", "\\", "（", "）", "(", ")"]:
		normalized = normalized.replace(separator, "")
	return normalized


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error, "player_confirmation_required": false}
