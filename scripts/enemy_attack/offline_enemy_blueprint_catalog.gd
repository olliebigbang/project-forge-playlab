class_name OfflineEnemyBlueprintCatalog
extends RefCounted

const RESOLVER := preload("res://scripts/enemy_attack/enemy_ai_blueprint_resolver.gd")
const DEFAULT_PATH := "res://data/enemy_attack/offline_encounter_catalog_v1.json"
const SCHEMA := "forge-offline-encounter-catalog-v1"


static func load_validated(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("OFFLINE_ENEMY_CATALOG_MISSING")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return _failure("OFFLINE_ENEMY_CATALOG_INVALID_JSON")
	var source := parsed as Dictionary
	if str(source.get("schema", "")) != SCHEMA:
		return _failure("OFFLINE_ENEMY_CATALOG_SCHEMA_INVALID")
	if not source.get("blueprints", null) is Array or not source.get("encounters", null) is Array:
		return _failure("OFFLINE_ENEMY_CATALOG_SHAPE_INVALID")

	var profiles_by_id: Dictionary = {}
	var profile_order: Array[String] = []
	for raw_entry: Variant in source.get("blueprints", []):
		if not raw_entry is Dictionary:
			return _failure("OFFLINE_ENEMY_BLUEPRINT_ENTRY_INVALID")
		var entry := raw_entry as Dictionary
		var catalog_id := str(entry.get("catalog_id", "")).strip_edges()
		var response := entry.get("response", {}) as Dictionary
		var concept := str(response.get("requested_concept", ""))
		if catalog_id.is_empty() or profiles_by_id.has(catalog_id):
			return _failure("OFFLINE_ENEMY_BLUEPRINT_ID_INVALID:%s" % catalog_id)
		var validation: Dictionary = RESOLVER.validate_ai_response(
			concept,
			response,
			"OFFLINE_ACCEPTED_ENEMY_CATALOG_V1"
		)
		if not bool(validation.get("ok", false)):
			var failed := _failure("OFFLINE_ENEMY_BLUEPRINT_REJECTED:%s" % catalog_id)
			failed["resolver_error"] = validation.duplicate(true)
			return failed
		var profile := (validation.get("profile", {}) as Dictionary).duplicate(true)
		profile["catalog_id"] = catalog_id
		profile["offline_accepted_blueprint"] = true
		profiles_by_id[catalog_id] = profile
		profile_order.append(catalog_id)

	var encounters: Array[Dictionary] = []
	var encounter_ids: Dictionary = {}
	for raw_encounter: Variant in source.get("encounters", []):
		if not raw_encounter is Dictionary:
			return _failure("OFFLINE_ENCOUNTER_INVALID")
		var encounter := (raw_encounter as Dictionary).duplicate(true)
		var encounter_id := str(encounter.get("encounter_id", "")).strip_edges()
		var blueprint_ids := encounter.get("blueprint_ids", []) as Array
		if encounter_id.is_empty() or encounter_ids.has(encounter_id) or blueprint_ids.is_empty():
			return _failure("OFFLINE_ENCOUNTER_ID_INVALID:%s" % encounter_id)
		var pressure_validation := _validate_pressure(encounter.get("pressure", {}))
		if not bool(pressure_validation.get("ok", false)):
			return pressure_validation
		for raw_id: Variant in blueprint_ids:
			if not profiles_by_id.has(str(raw_id)):
				return _failure("OFFLINE_ENCOUNTER_BLUEPRINT_UNKNOWN:%s" % str(raw_id))
		encounter_ids[encounter_id] = true
		encounters.append(encounter)
	if encounters.size() < 2 or encounters.size() > 3:
		return _failure("OFFLINE_ENCOUNTER_COUNT_INVALID")

	var sequence_ids: Array[String] = []
	for encounter: Dictionary in encounters:
		sequence_ids.append(str(encounter.get("encounter_id", "")))
	return {
		"ok": true,
		"schema": SCHEMA,
		"catalog_id": str(source.get("catalog_id", "")),
		"profiles_by_id": profiles_by_id,
		"profile_order": profile_order,
		"encounters": encounters,
		"sequence_signature": JSON.stringify(sequence_ids).sha256_text().left(16),
		"online_api_required": false,
		"player_enemy_input_required": false,
		"player_confirmation_required": false,
	}


static func _validate_pressure(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("OFFLINE_ENCOUNTER_PRESSURE_INVALID")
	var pressure := value as Dictionary
	var bounds := {
		"health_multiplier": Vector2(1.0, 1.6),
		"movement_multiplier": Vector2(1.0, 1.3),
		"damage_multiplier": Vector2(1.0, 1.4),
		"attack_tempo_multiplier": Vector2(0.72, 1.0),
	}
	for key: String in bounds:
		if not pressure.has(key) or typeof(pressure[key]) not in [TYPE_INT, TYPE_FLOAT]:
			return _failure("OFFLINE_ENCOUNTER_PRESSURE_FIELD_INVALID:%s" % key)
		var interval := bounds[key] as Vector2
		var number := float(pressure[key])
		if not is_finite(number) or number < interval.x or number > interval.y:
			return _failure("OFFLINE_ENCOUNTER_PRESSURE_FIELD_INVALID:%s" % key)
	return {"ok": true}


static func _failure(error: String) -> Dictionary:
	return {
		"ok": false,
		"error": error,
		"online_api_required": false,
		"player_enemy_input_required": false,
		"player_confirmation_required": false,
	}
