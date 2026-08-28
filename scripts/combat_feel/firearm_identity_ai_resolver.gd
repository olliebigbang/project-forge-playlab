class_name FirearmIdentityAIResolver
extends RefCounted

const FIREARM_CATALOG := preload("res://scripts/combat_feel/firearm_identity_catalog.gd")
const RANGED_AXES := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")

const CACHE_PATH := "user://playlab/firearm_identity_ai/cache_v4.json"
const CACHE_SCHEMA := "forge-firearm-identity-ai-cache-v4"
const RESPONSE_SCHEMA := "forge-firearm-identity-ai-response-v4"
const SUPPORTED_CLASSIFICATION := "handheld_firearm_supported"
const AUTO_VISUAL_REFERENCE_ID := "auto_wikimedia_v1"
const CLASSIFICATIONS: PackedStringArray = [
	SUPPORTED_CLASSIFICATION,
	"handheld_firearm_unsupported",
	"vehicle_weapon_platform",
	"not_firearm",
	"unknown",
]
const FINISH_PALETTES: PackedStringArray = [
	"gunmetal_black", "olive_black", "wood_steel", "dark_polymer",
]
const VISUAL_AXIS_KEYS: PackedStringArray = [
	"stock_profile",
	"upper_landmark",
	"magazine_profile",
	"fore_end_profile",
	"receiver_profile",
]
const MAX_CACHE_ENTRIES := 256
const MIN_ACCEPTED_CONFIDENCE := 0.72


static func resolve_identity(player_text: String, cache_path: String = CACHE_PATH) -> Dictionary:
	var catalog_result := FIREARM_CATALOG.resolve_identity(player_text)
	if bool(catalog_result.get("ok", false)):
		return catalog_result
	var normalized := _normalize(player_text)
	if normalized.is_empty():
		return _failure("AI_FIREARM_IDENTITY_EMPTY")
	var cache := _load_cache(cache_path)
	if not bool(cache.get("ok", false)):
		return _failure("AI_FIREARM_IDENTITY_NOT_CACHED")
	for raw_entry: Variant in cache.get("entries", []):
		if not raw_entry is Dictionary:
			continue
		var entry := raw_entry as Dictionary
		var matched_alias := _matching_cached_alias(entry, normalized)
		if matched_alias.is_empty():
			continue
		var profile := entry.get("profile", {}) as Dictionary
		var profile_validation := _validate_cached_profile(profile)
		if not bool(profile_validation.get("ok", false)):
			return profile_validation
		var result := profile.duplicate(true)
		result["ok"] = true
		result["matched_alias"] = matched_alias
		result["match_score"] = 3.0
		result["catalog_schema"] = CACHE_SCHEMA
		result["catalog_source"] = str((profile.get("declaration", {}) as Dictionary).get("source", ""))
		result["cache_hit"] = true
		result["player_confirmation_required"] = false
		return result
	return _failure("AI_FIREARM_IDENTITY_NOT_CACHED")


static func _matching_cached_alias(entry: Dictionary, normalized_input: String) -> String:
	var profile := entry.get("profile", {}) as Dictionary
	var candidates: Array[String] = [
		str(entry.get("player_identity_text", "")),
		str(profile.get("canonical_name_zh", "")),
	]
	for raw_alias: Variant in profile.get("aliases", []):
		candidates.append(str(raw_alias))
	for candidate: String in candidates:
		if not candidate.strip_edges().is_empty() and _normalize(candidate) == normalized_input:
			return candidate.strip_edges()
	# Older cache rows may not have preserved their original spelling.
	if str(entry.get("normalized_identity", "")) == normalized_input:
		return str(entry.get("player_identity_text", normalized_input)).strip_edges()
	return ""


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
	result["matched_alias"] = player_text.strip_edges()
	result["match_score"] = 3.0
	result["catalog_schema"] = CACHE_SCHEMA
	result["catalog_source"] = source.strip_edges()
	result["cache_hit"] = false
	result["player_confirmation_required"] = false
	return result


static func validate_ai_response(player_text: String, payload: Dictionary, source: String) -> Dictionary:
	if payload.is_empty():
		return _failure("AI_FIREARM_RESPONSE_MISSING")
	if str(payload.get("schema", "")) != RESPONSE_SCHEMA:
		return _failure("AI_FIREARM_RESPONSE_SCHEMA_INVALID")
	var requested_identity := str(payload.get("requested_identity", "")).strip_edges()
	if requested_identity != player_text.strip_edges():
		return _failure("AI_FIREARM_IDENTITY_ECHO_MISMATCH")
	var classification := str(payload.get("classification", ""))
	if classification not in CLASSIFICATIONS:
		return _failure("AI_FIREARM_CLASSIFICATION_INVALID")
	var confidence := float(payload.get("confidence", -1.0))
	if confidence < 0.0 or confidence > 1.0:
		return _failure("AI_FIREARM_CONFIDENCE_INVALID")
	if classification != SUPPORTED_CLASSIFICATION:
		return _classification_failure(classification, confidence)
	if confidence < MIN_ACCEPTED_CONFIDENCE:
		return _failure("AI_FIREARM_CONFIDENCE_TOO_LOW")
	var canonical_name := str(payload.get("canonical_name", "")).strip_edges()
	var visual_description := str(payload.get("visual_description_en", "")).strip_edges()
	if canonical_name.is_empty():
		return _failure("AI_FIREARM_CANONICAL_NAME_MISSING")
	if visual_description.length() < 12 or visual_description.length() > 360:
		return _failure("AI_FIREARM_VISUAL_DESCRIPTION_INVALID")
	var visible_parts := _validated_string_array(payload.get("required_identity_parts_zh", []), 2, 6, 64)
	if not bool(visible_parts.get("ok", false)):
		return _failure(str(visible_parts.get("error", "AI_FIREARM_VISIBLE_PARTS_INVALID")))
	var evidence := _validated_string_array(payload.get("identity_evidence", []), 1, 6, 240)
	if not bool(evidence.get("ok", false)):
		return _failure(str(evidence.get("error", "AI_FIREARM_IDENTITY_EVIDENCE_INVALID")))
	var visual_axes := _validated_visual_axes(payload.get("visual_identity_axes", {}))
	if not bool(visual_axes.get("ok", false)):
		return _failure(str(visual_axes.get("error", "AI_FIREARM_VISUAL_AXES_INVALID")))
	var landmarks := _validated_string_array(payload.get("required_landmarks_en", []), 2, 8, 180)
	if not bool(landmarks.get("ok", false)):
		return _failure("AI_FIREARM_VISUAL_LANDMARKS_INVALID")
	var exclusions := _validated_string_array(payload.get("confusable_exclusions_en", []), 1, 8, 220)
	if not bool(exclusions.get("ok", false)):
		return _failure("AI_FIREARM_VISUAL_EXCLUSIONS_INVALID")
	if not payload.get("declaration", {}) is Dictionary:
		return _failure("AI_FIREARM_DECLARATION_INVALID")
	var declaration := (payload.get("declaration", {}) as Dictionary).duplicate(true)
	var finish_palette := str(declaration.get("finish_palette", "gunmetal_black"))
	if finish_palette not in FINISH_PALETTES:
		return _failure("AI_FIREARM_FINISH_PALETTE_INVALID")
	declaration["source"] = source.strip_edges()
	declaration["confidence"] = confidence
	var axis_validation := RANGED_AXES.validate_ai_declaration(declaration, source)
	if not bool(axis_validation.get("ok", false)):
		var result := axis_validation.duplicate(true)
		result["player_confirmation_required"] = false
		return result
	var family_error := _mechanism_family_error(declaration)
	if not family_error.is_empty():
		return _failure(family_error)
	var profile_id := "ai_%s" % _normalize(player_text).sha256_text().left(16)
	var profile := {
		"id": profile_id,
		"canonical_name_zh": canonical_name,
		"aliases": [player_text.strip_edges(), canonical_name],
		"visual_description_en": visual_description,
		"required_identity_parts_zh": visible_parts.get("values", []),
		"identity_evidence": evidence.get("values", []),
		"visual_identity_card": {
			"visual_axes": visual_axes.get("values", {}),
			"required_landmarks_en": landmarks.get("values", []),
			"confusable_exclusions_en": exclusions.get("values", []),
		},
		"visual_reference_id": AUTO_VISUAL_REFERENCE_ID,
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


static func _classification_failure(classification: String, confidence: float) -> Dictionary:
	var error := "AI_FIREARM_IDENTITY_UNCERTAIN"
	match classification:
		"handheld_firearm_unsupported":
			error = "AI_FIREARM_STRUCTURE_FAMILY_UNSUPPORTED"
		"vehicle_weapon_platform":
			error = "AI_VEHICLE_PLATFORM_COMPILER_REQUIRED"
		"not_firearm":
			error = "AI_FIREARM_IDENTITY_REJECTED"
	return {
		"ok": false,
		"error": error,
		"classification": classification,
		"confidence": confidence,
		"recognized_by_ai": true,
		"player_confirmation_required": false,
	}


static func _validated_string_array(value: Variant, minimum: int, maximum: int, max_length: int) -> Dictionary:
	if not value is Array:
		return {"ok": false, "error": "AI_FIREARM_STRING_ARRAY_INVALID"}
	var raw_values := value as Array
	if raw_values.size() < minimum or raw_values.size() > maximum:
		return {"ok": false, "error": "AI_FIREARM_STRING_ARRAY_SIZE_INVALID"}
	var values: Array[String] = []
	for raw_value: Variant in raw_values:
		var text := str(raw_value).strip_edges()
		if text.is_empty() or text.length() > max_length:
			return {"ok": false, "error": "AI_FIREARM_STRING_ARRAY_ITEM_INVALID"}
		if text in values:
			return {"ok": false, "error": "AI_FIREARM_STRING_ARRAY_DUPLICATE"}
		values.append(text)
	return {"ok": true, "values": values}


static func _validated_visual_axes(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "error": "AI_FIREARM_VISUAL_AXES_INVALID"}
	var raw_axes := value as Dictionary
	if raw_axes.size() != VISUAL_AXIS_KEYS.size():
		return {"ok": false, "error": "AI_FIREARM_VISUAL_AXES_INVALID"}
	var axes := {}
	for key: String in VISUAL_AXIS_KEYS:
		if not raw_axes.has(key):
			return {"ok": false, "error": "AI_FIREARM_VISUAL_AXIS_MISSING:%s" % key}
		var axis_value := str(raw_axes.get(key, "")).strip_edges()
		if (
			axis_value.length() < 3
			or axis_value.length() > 96
			or axis_value == "not_applicable"
			or axis_value.to_lower().contains("identity_specific")
		):
			return {"ok": false, "error": "AI_FIREARM_VISUAL_AXIS_INVALID:%s" % key}
		axes[key] = axis_value
	return {"ok": true, "values": axes}


static func _validate_cached_profile(profile: Dictionary) -> Dictionary:
	if profile.is_empty() or not profile.get("declaration", {}) is Dictionary:
		return _failure("AI_FIREARM_CACHE_PROFILE_INVALID")
	var declaration := profile.get("declaration", {}) as Dictionary
	var source := str(declaration.get("source", ""))
	var validation := RANGED_AXES.validate_ai_declaration(declaration, source)
	if not bool(validation.get("ok", false)):
		return _failure("AI_FIREARM_CACHE_PROFILE_INVALID")
	if not _mechanism_family_error(declaration).is_empty():
		return _failure("AI_FIREARM_CACHE_PROFILE_INVALID")
	if str(profile.get("canonical_name_zh", "")).strip_edges().is_empty():
		return _failure("AI_FIREARM_CACHE_PROFILE_INVALID")
	if not profile.get("visual_identity_card", {}) is Dictionary:
		return _failure("AI_FIREARM_CACHE_PROFILE_INVALID")
	var card := profile.get("visual_identity_card", {}) as Dictionary
	if not bool(_validated_visual_axes(card.get("visual_axes", {})).get("ok", false)):
		return _failure("AI_FIREARM_CACHE_PROFILE_INVALID")
	if not bool(_validated_string_array(card.get("required_landmarks_en", []), 2, 8, 180).get("ok", false)):
		return _failure("AI_FIREARM_CACHE_PROFILE_INVALID")
	if not bool(_validated_string_array(card.get("confusable_exclusions_en", []), 1, 8, 220).get("ok", false)):
		return _failure("AI_FIREARM_CACHE_PROFILE_INVALID")
	if str(profile.get("visual_reference_id", "")) != AUTO_VISUAL_REFERENCE_ID:
		return _failure("AI_FIREARM_CACHE_PROFILE_INVALID")
	return {"ok": true}


static func _mechanism_family_error(declaration: Dictionary) -> String:
	var layout := str(declaration.get("layout", ""))
	var action := str(declaration.get("action_mechanism", ""))
	var feed_system := str(declaration.get("feed_system", ""))
	var shot_pattern := str(declaration.get("shot_pattern", ""))
	var sustained := str(declaration.get("sustained_climb", ""))
	var fire_control := str(declaration.get("fire_control", ""))
	if layout == "conventional_shotgun" and (
		action != "pump_action"
		or feed_system != "internal_tube"
		or shot_pattern != "pellet_cloud"
		or fire_control != "semi_auto"
	):
		return "AI_FIREARM_SHOTGUN_MECHANISM_CONFLICT"
	if layout == "revolver" and (
		action != "revolving_cylinder"
		or feed_system != "revolving_cylinder"
		or shot_pattern != "single_projectile"
		or fire_control != "semi_auto"
	):
		return "AI_FIREARM_REVOLVER_MECHANISM_CONFLICT"
	if layout == "belt_fed_support" and (
		action != "self_loading"
		or feed_system != "belt_box"
		or shot_pattern != "single_projectile"
		or sustained != "progressive"
		or fire_control != "select_fire_auto"
	):
		return "AI_FIREARM_SUPPORT_MECHANISM_CONFLICT"
	if layout in ["bullpup", "conventional_rifle", "pistol"] and (
		feed_system != "detachable_box" or shot_pattern != "single_projectile"
	):
		return "AI_FIREARM_MAGAZINE_FED_MECHANISM_CONFLICT"
	if layout in ["bullpup", "conventional_rifle", "pistol"] and action not in ["self_loading", "bolt_action"]:
		return "AI_FIREARM_ACTION_MECHANISM_CONFLICT"
	if action == "bolt_action" and layout != "conventional_rifle":
		return "AI_FIREARM_BOLT_ACTION_MECHANISM_CONFLICT"
	if layout in ["bullpup", "pistol"] and action != "self_loading":
		return "AI_FIREARM_SELF_LOADING_MECHANISM_CONFLICT"
	return ""


static func _load_cache(cache_path: String) -> Dictionary:
	var absolute_path := ProjectSettings.globalize_path(cache_path)
	if not FileAccess.file_exists(absolute_path):
		return {"ok": true, "schema": CACHE_SCHEMA, "entries": []}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(absolute_path))
	if not parsed is Dictionary:
		return _failure("AI_FIREARM_CACHE_INVALID_JSON")
	var cache := parsed as Dictionary
	if str(cache.get("schema", "")) != CACHE_SCHEMA or not cache.get("entries", []) is Array:
		return _failure("AI_FIREARM_CACHE_SCHEMA_INVALID")
	var result := cache.duplicate(true)
	result["ok"] = true
	return result


static func _store_profile(player_text: String, profile: Dictionary, model_id: String, cache_path: String) -> Dictionary:
	var cache := _load_cache(cache_path)
	if not bool(cache.get("ok", false)):
		cache = {"ok": true, "schema": CACHE_SCHEMA, "entries": []}
	var normalized := _normalize(player_text)
	var entries: Array = cache.get("entries", [])
	var next_entries: Array = []
	for raw_entry: Variant in entries:
		if not raw_entry is Dictionary:
			continue
		if str((raw_entry as Dictionary).get("normalized_identity", "")) != normalized:
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
	var directory := absolute_path.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return _failure("AI_FIREARM_CACHE_DIRECTORY_CREATE_FAILED")
	var temporary_path := absolute_path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return _failure("AI_FIREARM_CACHE_TEMP_WRITE_FAILED")
	file.store_string(JSON.stringify({"schema": CACHE_SCHEMA, "entries": next_entries}, "  "))
	file.close()
	if FileAccess.file_exists(absolute_path) and DirAccess.remove_absolute(absolute_path) != OK:
		return _failure("AI_FIREARM_CACHE_REPLACE_FAILED")
	if DirAccess.rename_absolute(temporary_path, absolute_path) != OK:
		return _failure("AI_FIREARM_CACHE_ATOMIC_RENAME_FAILED")
	return {"ok": true, "path": absolute_path}


static func _normalize(value: String) -> String:
	var normalized := value.strip_edges().to_upper()
	for separator: String in [" ", "-", "_", "·", ".", "/", "\\", "（", "）", "(", ")"]:
		normalized = normalized.replace(separator, "")
	return normalized


static func _failure(error: String) -> Dictionary:
	return {
		"ok": false,
		"error": error,
		"player_confirmation_required": false,
	}
