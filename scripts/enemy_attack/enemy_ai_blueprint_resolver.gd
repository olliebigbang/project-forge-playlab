class_name EnemyAIBlueprintResolver
extends RefCounted

const ATTACK_COMPILER := preload("res://scripts/enemy_attack/enemy_attack_mechanism_compiler.gd")
const CACHE_PATH := "user://playlab/enemy_ai/cache_v1.json"
const CACHE_SCHEMA := "forge-enemy-ai-blueprint-cache-v1"
const RESPONSE_SCHEMA := "forge-enemy-ai-blueprint-response-v1"
const PROFILE_SCHEMA := "forge-enemy-combat-blueprint-v1"
const MAX_CACHE_ENTRIES := 128

const VISUAL_LEGAL := {
	"body_plan": ["biped", "quadruped", "arachnid", "serpentine", "floating", "tracked"],
	"scale": ["small", "medium", "large"],
	"material": ["flesh", "chitin", "metal", "stone", "spectral"],
	"palette": ["ember", "venom", "frost", "arcane", "electric", "industrial"],
	"signature_feature": ["mandibles", "horns", "dorsal_spines", "halo", "tail", "shoulder_core"],
}
const MECHANICAL_LEGAL := {
	"mass_class": ["light", "medium", "heavy"],
	"armor_class": ["none", "light", "heavy"],
	"durability": ["fragile", "standard", "sturdy"],
	"mobility": ["slow", "steady", "fast"],
}
const HEALTH_BY_DURABILITY := {"fragile": 52.0, "standard": 78.0, "sturdy": 118.0}
const ARMOR_BY_CLASS := {"none": 0.0, "light": 0.45, "heavy": 1.0}
const SPEED_BY_MOBILITY := {"slow": 42.0, "steady": 58.0, "fast": 78.0}


static func resolve_cached(concept: String, cache_path: String = CACHE_PATH) -> Dictionary:
	var normalized := _normalize(concept)
	if normalized.is_empty():
		return _failure("AI_ENEMY_CONCEPT_EMPTY")
	var cache := _load_cache(cache_path)
	if not bool(cache.get("ok", false)):
		return _failure("AI_ENEMY_BLUEPRINT_NOT_CACHED")
	for raw_entry: Variant in cache.get("entries", []):
		if not raw_entry is Dictionary:
			continue
		var entry := raw_entry as Dictionary
		if str(entry.get("normalized_concept", "")) != normalized:
			continue
		var profile := entry.get("profile", {}) as Dictionary
		var validation := _validate_profile(profile)
		if not bool(validation.get("ok", false)):
			return validation
		var result := profile.duplicate(true)
		result["ok"] = true
		result["cache_hit"] = true
		result["player_confirmation_required"] = false
		return result
	return _failure("AI_ENEMY_BLUEPRINT_NOT_CACHED")


static func accept_ai_response(
	concept: String,
	payload: Dictionary,
	source: String,
	persist: bool = true,
	cache_path: String = CACHE_PATH
) -> Dictionary:
	var validation := validate_ai_response(concept, payload, source)
	if not bool(validation.get("ok", false)):
		return validation
	var profile := (validation.get("profile", {}) as Dictionary).duplicate(true)
	if persist:
		var stored := _store_profile(concept, profile, str(payload.get("model_id", "")), cache_path)
		if not bool(stored.get("ok", false)):
			return stored
	var result := profile.duplicate(true)
	result["ok"] = true
	result["cache_hit"] = false
	result["player_confirmation_required"] = false
	return result


static func validate_ai_response(concept: String, payload: Dictionary, source: String) -> Dictionary:
	if concept.strip_edges().is_empty() or concept.strip_edges().length() > 160:
		return _failure("AI_ENEMY_CONCEPT_INVALID")
	if str(payload.get("schema", "")) != RESPONSE_SCHEMA:
		return _failure("AI_ENEMY_RESPONSE_SCHEMA_INVALID")
	if str(payload.get("requested_concept", "")) != concept.strip_edges():
		return _failure("AI_ENEMY_CONCEPT_ECHO_MISMATCH")
	var name := str(payload.get("canonical_name_zh", "")).strip_edges()
	var role := str(payload.get("battle_role_zh", "")).strip_edges()
	if name.is_empty() or name.length() > 48:
		return _failure("AI_ENEMY_CANONICAL_NAME_INVALID")
	if role.length() < 2 or role.length() > 80:
		return _failure("AI_ENEMY_BATTLE_ROLE_INVALID")
	var confidence := float(payload.get("confidence", -1.0))
	if confidence < 0.0 or confidence > 1.0:
		return _failure("AI_ENEMY_CONFIDENCE_INVALID")
	var visual := _validated_enum_object(payload.get("visual_axes", null), VISUAL_LEGAL, "AI_ENEMY_VISUAL")
	if not bool(visual.get("ok", false)):
		return visual
	var mechanical := _validated_enum_object(payload.get("mechanical_profile", null), MECHANICAL_LEGAL, "AI_ENEMY_MECHANICAL")
	if not bool(mechanical.get("ok", false)):
		return mechanical
	if not payload.get("attacks", null) is Array:
		return _failure("AI_ENEMY_ATTACKS_INVALID")
	var raw_attacks := payload.get("attacks", []) as Array
	if raw_attacks.size() != 2:
		return _failure("AI_ENEMY_ATTACK_COUNT_INVALID")
	var declarations: Array[Dictionary] = []
	var attack_labels: Array[String] = []
	var deliveries: Dictionary = {}
	var selection_ranks: Dictionary = {}
	var has_engagement := false
	var has_pressure := false
	for index: int in range(raw_attacks.size()):
		var raw_attack: Variant = raw_attacks[index]
		if not raw_attack is Dictionary:
			return _failure("AI_ENEMY_ATTACK_INVALID:%d" % index)
		var attack := raw_attack as Dictionary
		var label := str(attack.get("slot_label_zh", "")).strip_edges()
		if label.length() < 2 or label.length() > 32 or label in attack_labels:
			return _failure("AI_ENEMY_ATTACK_LABEL_INVALID:%d" % index)
		if not attack.get("axes", null) is Dictionary or not attack.get("selection", null) is Dictionary:
			return _failure("AI_ENEMY_ATTACK_CONTRACT_INVALID:%d" % index)
		var normalized_selection := (attack.get("selection", {}) as Dictionary).duplicate(true)
		for integer_field: String in ["base_priority", "coordination_cost", "selection_rank"]:
			if normalized_selection.has(integer_field):
				normalized_selection[integer_field] = int(normalized_selection[integer_field])
		var declaration := {
			"attack_key": "slot_ai_%02d" % (index + 1),
			"axes": (attack.get("axes", {}) as Dictionary).duplicate(true),
			"selection": normalized_selection,
		}
		var compiled: Dictionary = ATTACK_COMPILER.compile(declaration)
		if not bool(compiled.get("ok", false)):
			var failed := _failure("AI_ENEMY_ATTACK_COMPILE_FAILED:%d" % index)
			failed["compiler_error"] = compiled.duplicate(true)
			return failed
		var delivery := str((declaration["axes"] as Dictionary).get("delivery", ""))
		var preferred_range := str((declaration["selection"] as Dictionary).get("preferred_range", ""))
		var selection_rank := int((declaration["selection"] as Dictionary).get("selection_rank", -1))
		if deliveries.has(delivery):
			return _failure("AI_ENEMY_ATTACK_DELIVERY_DUPLICATE")
		if selection_ranks.has(selection_rank):
			return _failure("AI_ENEMY_ATTACK_SELECTION_RANK_DUPLICATE")
		deliveries[delivery] = true
		selection_ranks[selection_rank] = true
		has_engagement = has_engagement or (delivery in ["contact", "rush"] and preferred_range in ["close", "mid"])
		has_pressure = has_pressure or (delivery in ["projectile", "marked_impact"] and preferred_range == "far")
		declarations.append(declaration)
		attack_labels.append(label)
	if not has_engagement or not has_pressure:
		return _failure("AI_ENEMY_ATTACK_RANGE_COVERAGE_INVALID")
	var visual_axes := visual.get("values", {}) as Dictionary
	var mechanical_profile := mechanical.get("values", {}) as Dictionary
	var durability := str(mechanical_profile["durability"])
	var armor_class := str(mechanical_profile["armor_class"])
	var mobility := str(mechanical_profile["mobility"])
	var profile := {
		"schema": PROFILE_SCHEMA,
		"id": "ai_enemy_%s" % _normalize(concept).sha256_text().left(16),
		"display_name": name,
		"requested_concept": concept.strip_edges(),
		"battle_role_zh": role,
		"confidence": confidence,
		"visual_identity_axes": visual_axes.duplicate(true),
		"mass_class": str(mechanical_profile["mass_class"]),
		"armor_integrity": float(ARMOR_BY_CLASS[armor_class]),
		"max_health": float(HEALTH_BY_DURABILITY[durability]),
		"move_speed": float(SPEED_BY_MOBILITY[mobility]),
		"attack_declarations": declarations,
		"attack_labels_zh": attack_labels,
		"source": source.strip_edges(),
		"ai_model_id": str(payload.get("model_id", "")),
		"identity_inputs_used_during_generation": true,
		"runtime_identity_inputs_used": false,
		"player_confirmation_required": false,
	}
	return {"ok": true, "profile": profile, "player_confirmation_required": false}


static func _validated_enum_object(value: Variant, legal: Dictionary, error_prefix: String) -> Dictionary:
	if not value is Dictionary:
		return _failure("%s_INVALID" % error_prefix)
	var raw := value as Dictionary
	if raw.size() != legal.size():
		return _failure("%s_INVALID" % error_prefix)
	var values := {}
	for key: String in legal:
		var item := str(raw.get(key, ""))
		if not raw.has(key) or item not in (legal[key] as Array):
			return _failure("%s_AXIS_INVALID:%s" % [error_prefix, key])
		values[key] = item
	return {"ok": true, "values": values}


static func _validate_profile(profile: Dictionary) -> Dictionary:
	if str(profile.get("schema", "")) != PROFILE_SCHEMA:
		return _failure("AI_ENEMY_CACHE_PROFILE_INVALID")
	if str(profile.get("display_name", "")).strip_edges().is_empty():
		return _failure("AI_ENEMY_CACHE_PROFILE_INVALID")
	if not bool(_validated_enum_object(profile.get("visual_identity_axes", null), VISUAL_LEGAL, "AI_ENEMY_CACHE_VISUAL").get("ok", false)):
		return _failure("AI_ENEMY_CACHE_PROFILE_INVALID")
	if not profile.get("attack_declarations", null) is Array:
		return _failure("AI_ENEMY_CACHE_PROFILE_INVALID")
	var declarations := profile.get("attack_declarations", []) as Array
	if declarations.size() != 2:
		return _failure("AI_ENEMY_CACHE_PROFILE_INVALID")
	for declaration: Variant in declarations:
		if not declaration is Dictionary:
			return _failure("AI_ENEMY_CACHE_PROFILE_INVALID")
		var selection := (declaration as Dictionary).get("selection", {}) as Dictionary
		for integer_field: String in ["base_priority", "coordination_cost", "selection_rank"]:
			if selection.has(integer_field):
				selection[integer_field] = int(selection[integer_field])
		if not bool(ATTACK_COMPILER.compile(declaration as Dictionary).get("ok", false)):
			return _failure("AI_ENEMY_CACHE_PROFILE_INVALID")
	return {"ok": true}


static func _load_cache(cache_path: String) -> Dictionary:
	var absolute_path := ProjectSettings.globalize_path(cache_path)
	if not FileAccess.file_exists(absolute_path):
		return {"ok": true, "schema": CACHE_SCHEMA, "entries": []}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(absolute_path))
	if not parsed is Dictionary:
		return _failure("AI_ENEMY_CACHE_INVALID_JSON")
	var cache := parsed as Dictionary
	if str(cache.get("schema", "")) != CACHE_SCHEMA or not cache.get("entries", null) is Array:
		return _failure("AI_ENEMY_CACHE_SCHEMA_INVALID")
	var result := cache.duplicate(true)
	result["ok"] = true
	return result


static func _store_profile(concept: String, profile: Dictionary, model_id: String, cache_path: String) -> Dictionary:
	var cache := _load_cache(cache_path)
	if not bool(cache.get("ok", false)):
		cache = {"ok": true, "schema": CACHE_SCHEMA, "entries": []}
	var normalized := _normalize(concept)
	var next_entries: Array = []
	for raw_entry: Variant in cache.get("entries", []):
		if not raw_entry is Dictionary:
			continue
		if str((raw_entry as Dictionary).get("normalized_concept", "")) != normalized:
			next_entries.append((raw_entry as Dictionary).duplicate(true))
	next_entries.append({
		"normalized_concept": normalized,
		"concept": concept.strip_edges(),
		"profile": profile.duplicate(true),
		"model_id": model_id,
		"cached_unix_time": int(Time.get_unix_time_from_system()),
	})
	while next_entries.size() > MAX_CACHE_ENTRIES:
		next_entries.pop_front()
	var absolute_path := ProjectSettings.globalize_path(cache_path)
	if DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir()) != OK:
		return _failure("AI_ENEMY_CACHE_DIRECTORY_CREATE_FAILED")
	var temporary_path := absolute_path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return _failure("AI_ENEMY_CACHE_TEMP_WRITE_FAILED")
	file.store_string(JSON.stringify({"schema": CACHE_SCHEMA, "entries": next_entries}, "  "))
	file.close()
	if FileAccess.file_exists(absolute_path) and DirAccess.remove_absolute(absolute_path) != OK:
		return _failure("AI_ENEMY_CACHE_REPLACE_FAILED")
	if DirAccess.rename_absolute(temporary_path, absolute_path) != OK:
		return _failure("AI_ENEMY_CACHE_ATOMIC_RENAME_FAILED")
	return {"ok": true, "path": absolute_path}


static func _normalize(value: String) -> String:
	var normalized := value.strip_edges().to_upper()
	for separator: String in [" ", "-", "_", "·", ".", "/", "\\", "（", "）", "(", ")"]:
		normalized = normalized.replace(separator, "")
	return normalized


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error, "player_confirmation_required": false}
