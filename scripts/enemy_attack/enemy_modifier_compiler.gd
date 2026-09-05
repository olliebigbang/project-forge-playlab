class_name EnemyModifierCompiler
extends RefCounted

const SCHEMA := "forge-enemy-modifier-stack-v1"
const ALLOWED_FIELDS: PackedStringArray = ["modifier_key", "family"]
const LEGAL_FAMILIES: PackedStringArray = ["echo", "barrier", "residue"]


static func compile_stack(declarations: Array) -> Dictionary:
	var compiled: Array[Dictionary] = []
	var seen_families: Dictionary = {}
	for index: int in range(declarations.size()):
		var raw: Variant = declarations[index]
		if not raw is Dictionary:
			return _failure("MODIFIER_DECLARATION_NOT_DICTIONARY:%d" % index)
		var result := _compile_one(raw as Dictionary)
		if not bool(result.get("ok", false)):
			return result
		var family := str(result.get("family", ""))
		if seen_families.has(family):
			return _failure("MODIFIER_FAMILY_DUPLICATED:%s" % family)
		seen_families[family] = true
		compiled.append(result)

	var echo := _neutral_echo()
	var barrier := _neutral_barrier()
	var residue := _neutral_residue()
	var keys: Array[String] = []
	for modifier: Dictionary in compiled:
		keys.append(str(modifier.get("modifier_key", "")))
		match str(modifier.get("family", "")):
			"echo": echo = (modifier.get("runtime", {}) as Dictionary).duplicate(true)
			"barrier": barrier = (modifier.get("runtime", {}) as Dictionary).duplicate(true)
			"residue": residue = (modifier.get("runtime", {}) as Dictionary).duplicate(true)

	var signature_source := {
		"families": seen_families.keys(),
		"echo": echo,
		"barrier": barrier,
		"residue": residue,
	}
	return {
		"ok": true,
		"schema": SCHEMA,
		"modifier_keys": keys,
		"families": seen_families.keys(),
		"echo": echo,
		"barrier": barrier,
		"residue": residue,
		"modifier_signature": JSON.stringify(signature_source).sha256_text().left(16),
		"identity_inputs_used": false,
		"player_confirmation_required": false,
	}


static func _compile_one(declaration: Dictionary) -> Dictionary:
	for raw_key: Variant in declaration.keys():
		var key := str(raw_key)
		if key not in ALLOWED_FIELDS:
			return _failure("UNSUPPORTED_MODIFIER_FIELD:%s" % key)
	var modifier_key := str(declaration.get("modifier_key", "")).strip_edges()
	if modifier_key.is_empty():
		return _failure("MODIFIER_KEY_MISSING")
	var family := str(declaration.get("family", ""))
	if family not in LEGAL_FAMILIES:
		return _failure("MODIFIER_FAMILY_INVALID:%s" % family)
	var runtime := {}
	match family:
		"echo":
			runtime = {
				"enabled": true,
				"repeat_count": 1,
				"delay_seconds": 0.42,
				"damage_multiplier": 0.58,
				"region_scale": 0.90,
			}
		"barrier":
			runtime = {
				"enabled": true,
				"charges": 1,
				"guard_arc_degrees": 360.0,
				"damage_multiplier": 0.18,
				"stagger_multiplier": 0.25,
				"break_strength": 1.35,
			}
		"residue":
			runtime = {
				"enabled": true,
				"hazard_mode_override": "lingering",
				"minimum_duration_seconds": 1.65,
				"repeat_hit_cooldown_seconds": 0.38,
				"damage_multiplier": 0.45,
			}
	return {
		"ok": true,
		"modifier_key": modifier_key,
		"family": family,
		"runtime": runtime,
		"identity_inputs_used": false,
		"player_confirmation_required": false,
	}


static func _neutral_echo() -> Dictionary:
	return {
		"enabled": false,
		"repeat_count": 0,
		"delay_seconds": 0.0,
		"damage_multiplier": 1.0,
		"region_scale": 1.0,
	}


static func _neutral_barrier() -> Dictionary:
	return {
		"enabled": false,
		"charges": 0,
		"guard_arc_degrees": 0.0,
		"damage_multiplier": 1.0,
		"stagger_multiplier": 1.0,
		"break_strength": 0.0,
	}


static func _neutral_residue() -> Dictionary:
	return {
		"enabled": false,
		"hazard_mode_override": "",
		"minimum_duration_seconds": 0.0,
		"repeat_hit_cooldown_seconds": 0.0,
		"damage_multiplier": 1.0,
	}


static func _failure(code: String) -> Dictionary:
	return {
		"ok": false,
		"schema": SCHEMA,
		"error": code,
		"identity_inputs_used": false,
		"player_confirmation_required": false,
	}
