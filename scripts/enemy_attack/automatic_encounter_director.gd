class_name AutomaticEncounterDirector
extends RefCounted

const CATALOG := preload("res://scripts/enemy_attack/offline_enemy_blueprint_catalog.gd")
const MECHANISM_AXIS_RESOLVER := preload("res://scripts/combat_feel/mechanism_axis_resolver.gd")
const RANGED_AXIS_RESOLVER := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")

const RUN_SCHEMA := "forge-automatic-encounter-run-v1"

var catalog: Dictionary = {}
var state := "unconfigured"
var encounter_index := -1
var active_encounter: Dictionary = {}
var completed_encounters: Array[Dictionary] = []
var equipped_weapon: Dictionary = {}


func configure(catalog_path: String = CATALOG.DEFAULT_PATH) -> Dictionary:
	catalog = CATALOG.load_validated(catalog_path)
	if not bool(catalog.get("ok", false)):
		state = "invalid"
		return catalog.duplicate(true)
	state = "ready"
	encounter_index = -1
	active_encounter.clear()
	completed_encounters.clear()
	equipped_weapon.clear()
	return snapshot()


func begin_run(weapon_entry: Dictionary) -> Dictionary:
	if not bool(catalog.get("ok", false)):
		return _failure("AUTOMATIC_LEVEL_CATALOG_NOT_READY")
	var weapon_validation := _validate_weapon_entry(weapon_entry)
	if not bool(weapon_validation.get("ok", false)):
		return weapon_validation
	equipped_weapon = {
		"kind": str(weapon_validation.get("kind", "")),
		"blueprint": weapon_entry.get("blueprint"),
		"asset": weapon_entry.get("asset"),
		"ranged_runtime_profile": (weapon_entry.get("ranged_runtime_profile", {}) as Dictionary).duplicate(true),
		"affordance_profile": weapon_entry.get("affordance_profile"),
		"display_name": str(weapon_entry.get("display_name", (weapon_entry.get("blueprint") as WeaponBlueprint).display_name)),
	}
	encounter_index = -1
	active_encounter.clear()
	completed_encounters.clear()
	state = "between_encounters"
	return snapshot()


func begin_next_encounter() -> Dictionary:
	if state != "between_encounters":
		return _failure("AUTOMATIC_LEVEL_NOT_BETWEEN_ENCOUNTERS")
	var encounters := catalog.get("encounters", []) as Array
	var next_index := encounter_index + 1
	if next_index >= encounters.size():
		state = "completed"
		return snapshot()
	var declaration := (encounters[next_index] as Dictionary).duplicate(true)
	var pressure := (declaration.get("pressure", {}) as Dictionary).duplicate(true)
	var profiles: Array[Dictionary] = []
	for raw_id: Variant in declaration.get("blueprint_ids", []):
		var profile := ((catalog.get("profiles_by_id", {}) as Dictionary).get(str(raw_id), {}) as Dictionary).duplicate(true)
		if profile.is_empty():
			return _failure("AUTOMATIC_LEVEL_BLUEPRINT_MISSING:%s" % str(raw_id))
		profile["max_health"] = float(profile.get("max_health", 80.0)) * float(pressure.get("health_multiplier", 1.0))
		profile["move_speed"] = float(profile.get("move_speed", 54.0)) * float(pressure.get("movement_multiplier", 1.0))
		profile["damage_multiplier"] = float(pressure.get("damage_multiplier", 1.0))
		profile["attack_tempo_multiplier"] = float(pressure.get("attack_tempo_multiplier", 1.0))
		profile["pressure_profile"] = pressure.duplicate(true)
		profiles.append(profile)
	encounter_index = next_index
	active_encounter = declaration
	active_encounter["profiles"] = profiles
	active_encounter["encounter_number"] = encounter_index + 1
	active_encounter["encounter_total"] = encounters.size()
	active_encounter["stage_name"] = "automatic_encounter_%02d" % (encounter_index + 1)
	state = "combat"
	var result := active_encounter.duplicate(true)
	result["ok"] = true
	result["player_enemy_input_required"] = false
	result["player_confirmation_required"] = false
	return result


func complete_active_encounter(metrics: Dictionary) -> Dictionary:
	if state != "combat" or active_encounter.is_empty():
		return _failure("AUTOMATIC_LEVEL_NO_ACTIVE_ENCOUNTER")
	completed_encounters.append({
		"encounter_id": str(active_encounter.get("encounter_id", "")),
		"metrics": metrics.duplicate(true),
	})
	active_encounter.clear()
	if encounter_index + 1 >= (catalog.get("encounters", []) as Array).size():
		state = "completed"
	else:
		state = "between_encounters"
	return snapshot()


func fail_run(reason: String, metrics: Dictionary = {}) -> Dictionary:
	if state not in ["combat", "between_encounters"]:
		return _failure("AUTOMATIC_LEVEL_NOT_RUNNING")
	state = "failed"
	active_encounter.clear()
	var result := snapshot()
	result["failure_reason"] = reason
	result["failure_metrics"] = metrics.duplicate(true)
	return result


func weapon_handoff() -> Dictionary:
	return equipped_weapon.duplicate(true)


func snapshot() -> Dictionary:
	return {
		"ok": state != "invalid",
		"schema": RUN_SCHEMA,
		"state": state,
		"encounter_index": encounter_index,
		"encounter_count": (catalog.get("encounters", []) as Array).size(),
		"completed_count": completed_encounters.size(),
		"sequence_signature": str(catalog.get("sequence_signature", "")),
		"weapon_display_name": str(equipped_weapon.get("display_name", "")),
		"online_api_required": false,
		"player_enemy_input_required": false,
		"player_confirmation_required": false,
	}


func _validate_weapon_entry(entry: Dictionary) -> Dictionary:
	var blueprint := entry.get("blueprint") as WeaponBlueprint
	var asset := entry.get("asset") as WeaponVisualAsset
	if blueprint == null or asset == null:
		return _failure("AUTOMATIC_LEVEL_WEAPON_ENTRY_INCOMPLETE")
	if blueprint.behavior_family == "heavy_melee":
		return _validate_mechanism_weapon(blueprint, asset, entry.get("affordance_profile"))
	var runtime := entry.get("ranged_runtime_profile", {}) as Dictionary
	if not bool(runtime.get("ok", false)):
		return _failure("AUTOMATIC_LEVEL_WEAPON_ENTRY_INCOMPLETE")
	var compiled: Dictionary = RANGED_AXIS_RESOLVER.compile(blueprint.affordance, blueprint.affordance_source)
	if not bool(compiled.get("ok", false)):
		return _failure("AUTOMATIC_LEVEL_WEAPON_AXES_INVALID")
	if (
		str(runtime.get("schema", "")) != str(compiled.get("schema", ""))
		or str(runtime.get("axis_signature", "")) != str(compiled.get("axis_signature", ""))
		or runtime.get("final_parameters", {}) != compiled.get("final_parameters", {})
	):
		return _failure("AUTOMATIC_LEVEL_WEAPON_HANDOFF_MISMATCH")
	return {"ok": true, "kind": "ranged_firearm"}


func _validate_mechanism_weapon(
	blueprint: WeaponBlueprint,
	asset: WeaponVisualAsset,
	affordance_profile: Variant
) -> Dictionary:
	if affordance_profile == null or not affordance_profile.has_method("validation_errors"):
		return _failure("AUTOMATIC_LEVEL_MECHANISM_PROFILE_MISSING")
	var errors: Array = affordance_profile.call("validation_errors") as Array
	if not errors.is_empty():
		return _failure("AUTOMATIC_LEVEL_MECHANISM_PROFILE_INVALID")
	var resolved: Dictionary = MECHANISM_AXIS_RESOLVER.resolve_ai(
		asset,
		blueprint.affordance,
		blueprint.affordance_source
	)
	if not bool(resolved.get("ok", false)):
		return _failure("AUTOMATIC_LEVEL_MECHANISM_AXES_INVALID")
	var expected_profile: Variant = resolved.get("profile")
	if (
		expected_profile == null
		or not expected_profile.has_method("to_dict")
		or not affordance_profile.has_method("to_dict")
		or expected_profile.call("to_dict") != affordance_profile.call("to_dict")
	):
		return _failure("AUTOMATIC_LEVEL_MECHANISM_HANDOFF_MISMATCH")
	var uses_soft_visuals := str(affordance_profile.get("flex_topology")) != "none" \
		or str(affordance_profile.get("tether_topology")) != "none"
	if uses_soft_visuals and not asset.has_pixel_visual_rig():
		return _failure("AUTOMATIC_LEVEL_MECHANISM_VISUAL_RIG_MISSING")
	if asset.visual_rig != null:
		var visual_axis_errors: Array[String] = asset.visual_rig.axis_errors(affordance_profile)
		if not visual_axis_errors.is_empty():
			return _failure("AUTOMATIC_LEVEL_MECHANISM_VISUAL_RIG_MISMATCH")
	return {"ok": true, "kind": "mechanism_weapon"}


func _failure(error: String) -> Dictionary:
	return {
		"ok": false,
		"error": error,
		"state": state,
		"online_api_required": false,
		"player_enemy_input_required": false,
		"player_confirmation_required": false,
	}
