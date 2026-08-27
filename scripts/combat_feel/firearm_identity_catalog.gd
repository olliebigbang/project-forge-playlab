class_name FirearmIdentityCatalog
extends RefCounted

const CATALOG_PATH := "res://data/combat_feel/firearm_identity_profiles_v1.json"


static func resolve_identity(player_text: String) -> Dictionary:
	var normalized_input := _normalize(player_text)
	if normalized_input.is_empty():
		return _failure("FIREARM_IDENTITY_EMPTY")
	var catalog := _load_catalog()
	if not bool(catalog.get("ok", false)):
		return catalog
	var best_entry: Dictionary = {}
	var best_alias := ""
	var best_score := -1.0
	for raw_entry: Variant in catalog.get("entries", []):
		if not raw_entry is Dictionary:
			continue
		var entry := raw_entry as Dictionary
		for raw_alias: Variant in entry.get("aliases", []):
			var alias := str(raw_alias)
			var normalized_alias := _normalize(alias)
			if normalized_alias.is_empty():
				continue
			var score := -1.0
			if normalized_input == normalized_alias:
				score = 2.0 + float(normalized_alias.length()) / 1000.0
			elif normalized_alias.length() >= 4 and normalized_input.contains(normalized_alias):
				score = 1.0 + float(normalized_alias.length()) / float(maxi(1, normalized_input.length()))
			if score > best_score:
				best_score = score
				best_entry = entry
				best_alias = alias
	if best_entry.is_empty():
		return _failure("FIREARM_IDENTITY_NOT_IN_AI_CACHE")
	var result := best_entry.duplicate(true)
	result["ok"] = true
	result["matched_alias"] = best_alias
	result["match_score"] = best_score
	result["catalog_schema"] = str(catalog.get("schema", ""))
	result["catalog_source"] = str(catalog.get("source", ""))
	return result


static func all_profiles() -> Array[Dictionary]:
	var catalog := _load_catalog()
	var profiles: Array[Dictionary] = []
	if not bool(catalog.get("ok", false)):
		return profiles
	for raw_entry: Variant in catalog.get("entries", []):
		if raw_entry is Dictionary:
			profiles.append((raw_entry as Dictionary).duplicate(true))
	return profiles


static func _load_catalog() -> Dictionary:
	if not FileAccess.file_exists(CATALOG_PATH):
		return _failure("FIREARM_IDENTITY_CATALOG_MISSING")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if not parsed is Dictionary:
		return _failure("FIREARM_IDENTITY_CATALOG_INVALID_JSON")
	var catalog := parsed as Dictionary
	if str(catalog.get("schema", "")) != "forge-firearm-identity-profiles-v1":
		return _failure("FIREARM_IDENTITY_CATALOG_SCHEMA_INVALID")
	if not catalog.get("entries", []) is Array or (catalog.get("entries", []) as Array).is_empty():
		return _failure("FIREARM_IDENTITY_CATALOG_EMPTY")
	var result := catalog.duplicate(true)
	result["ok"] = true
	return result


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
