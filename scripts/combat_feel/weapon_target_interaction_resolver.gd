class_name WeaponTargetInteractionResolver
extends RefCounted

const RUNTIME_SCHEMA := "forge-weapon-target-interaction-v1"
const AUDIT_SCHEMA := "forge-weapon-target-interaction-finite-difference-audit-v1"

const EFFECT_AXES: PackedStringArray = [
	"wound", "impulse", "control", "breach", "pin", "bind", "suppress",
]
const LEVELS: PackedStringArray = ["none", "light", "medium", "strong"]

# Every final reaction parameter has one owner. Weapon structure may derive
# several effect axes, but the runtime matrix never hides a second writer.
const PARAMETER_OWNERS := {
	"damage_multiplier": "wound",
	"displacement_scale": "impulse",
	"stagger_seconds": "control",
	"armor_damage_ratio": "breach",
	"pin_seconds": "pin",
	"entangle_seconds": "bind",
	"suppression_seconds": "suppress",
}
const AUDITED_PARAMETERS: PackedStringArray = [
	"damage_multiplier", "displacement_scale", "stagger_seconds",
	"armor_damage_ratio", "pin_seconds", "entangle_seconds",
	"suppression_seconds",
]
const PARAMETER_BOUNDS := {
	"damage_multiplier": [1.0, 1.30],
	"displacement_scale": [0.35, 1.65],
	"stagger_seconds": [0.08, 0.55],
	"armor_damage_ratio": [0.0, 0.52],
	"pin_seconds": [0.0, 0.82],
	"entangle_seconds": [0.0, 1.10],
	"suppression_seconds": [0.0, 0.95],
}


static func default_effect_axes() -> Dictionary:
	var axes := {}
	for axis: String in EFFECT_AXES:
		axes[axis] = "none"
	return axes


static func compile(effect_axes: Dictionary, source: String) -> Dictionary:
	var errors := PackedStringArray()
	for axis: String in EFFECT_AXES:
		var value := str(effect_axes.get(axis, ""))
		if value not in LEVELS:
			errors.append("INVALID_TARGET_INTERACTION_AXIS:%s:%s" % [axis, value])
	if not errors.is_empty():
		return {
			"ok": false,
			"error": errors[0],
			"errors": errors,
			"player_confirmation_required": false,
		}
	var axes := _axis_snapshot(effect_axes)
	var raw_parameters := _raw_parameter_matrix(axes)
	var clamped := _clamp_parameter_matrix(raw_parameters)
	var final_parameters := clamped.get("parameters", {}) as Dictionary
	var result := {
		"ok": true,
		"schema": RUNTIME_SCHEMA,
		"source": source,
		"effect_axes": axes,
		"axis_signature": JSON.stringify(axes).sha256_text().left(16),
		"raw_parameters": raw_parameters,
		"final_parameters": final_parameters,
		"clamp_events": clamped.get("clamp_events", []),
		"parameter_owners": PARAMETER_OWNERS.duplicate(true),
		"player_mechanism_input_used": false,
		"player_confirmation_required": false,
	}
	for parameter: String in final_parameters:
		result[parameter] = final_parameters[parameter]
	return result


static func compile_melee(affordance: Variant, primitive: Variant) -> Dictionary:
	var axes := effect_axes_for_melee(affordance, primitive)
	var result := compile(axes, "melee_affordance_target_compiler_v1")
	if not bool(result.get("ok", false)):
		return result
	var tether_mode := str(_source_value(primitive, "tether_mode", _source_value(affordance, "tether_mode", "none")))
	result["delivery"] = "melee_contact"
	result["contact_surface"] = str(_source_value(primitive, "contact_surface", _source_value(affordance, "contact_surface", "broad")))
	result["tether_mode"] = tether_mode
	result["displacement_mode"] = "toward_source" if tether_mode == "hook" else ("hold" if tether_mode == "wrap" else "away")
	return result


static func compile_ranged(ranged_axes: Dictionary, ranged_runtime: Dictionary = {}) -> Dictionary:
	var axes := effect_axes_for_ranged(ranged_axes, ranged_runtime)
	var result := compile(axes, "ranged_mechanism_target_compiler_v1")
	if not bool(result.get("ok", false)):
		return result
	result["delivery"] = "projectile"
	result["displacement_mode"] = "away"
	return result


static func effect_axes_for_melee(affordance: Variant, primitive: Variant) -> Dictionary:
	var axes := default_effect_axes()
	var surface := str(_source_value(primitive, "contact_surface", _source_value(affordance, "contact_surface", "broad")))
	var family := str(_source_value(primitive, "motion_family", "bash"))
	match surface:
		"point":
			axes["wound"] = "light"
			axes["control"] = "medium"
			axes["breach"] = "medium"
			axes["pin"] = "strong" if family == "thrust" else "medium"
		"edge":
			axes["wound"] = "strong"
			axes["impulse"] = "light"
			axes["control"] = "light"
			axes["breach"] = "light"
		"broad":
			axes["wound"] = "light"
			axes["impulse"] = "strong"
			axes["control"] = "medium"
		"whole_body":
			axes["impulse"] = "medium"
			axes["control"] = "strong"

	var flex_topology := str(_source_value(primitive, "flex_topology", _source_value(affordance, "flex_topology", "none")))
	var tether_topology := str(_source_value(primitive, "tether_topology", _source_value(affordance, "tether_topology", "none")))
	var tether_mode := str(_source_value(primitive, "tether_mode", _source_value(affordance, "tether_mode", "none")))
	match tether_mode:
		"wrap":
			axes["bind"] = "strong"
			axes["control"] = _higher_level(str(axes["control"]), "strong")
			axes["impulse"] = "light"
		"hook":
			axes["bind"] = "light"
			axes["pin"] = "none"
			axes["control"] = _higher_level(str(axes["control"]), "medium")
		_:
			if flex_topology in ["flexible_line", "linked_segments"] or tether_topology != "none":
				axes["bind"] = "medium" if surface == "whole_body" else "light"

	var terminal_load_ratio := float(_source_value(primitive, "terminal_load_ratio", 0.0))
	if terminal_load_ratio >= 0.65:
		axes["impulse"] = _raise_level(str(axes["impulse"]))
		axes["control"] = _raise_level(str(axes["control"]))
	var knockback_multiplier := float(_source_value(primitive, "knockback_multiplier", 1.0))
	if knockback_multiplier >= 1.35:
		axes["impulse"] = _raise_level(str(axes["impulse"]))
	var stagger_multiplier := float(_source_value(primitive, "stagger_multiplier", 1.0))
	if stagger_multiplier >= 1.25:
		axes["control"] = _raise_level(str(axes["control"]))
	return axes


static func effect_axes_for_ranged(ranged_axes: Dictionary, ranged_runtime: Dictionary = {}) -> Dictionary:
	var axes := default_effect_axes()
	var impact_force := str(ranged_axes.get("impact_force", ""))
	if impact_force.is_empty():
		var damage := float(ranged_runtime.get("projectile_damage", 10.0))
		impact_force = "strong" if damage >= 13.0 else ("light" if damage <= 8.0 else "medium")
	var penetration := str(ranged_axes.get("penetration", ""))
	if penetration.is_empty():
		var armor_multiplier := float(ranged_runtime.get("armor_damage_multiplier", 0.72))
		penetration = "strong" if armor_multiplier >= 0.88 else ("light" if armor_multiplier <= 0.56 else "medium")
	var cadence := str(ranged_axes.get("cadence", ""))
	if cadence.is_empty():
		var interval := float(ranged_runtime.get("shot_interval_seconds", 0.17))
		cadence = "rapid" if interval <= 0.12 else ("deliberate" if interval >= 0.24 else "balanced")
	axes["impulse"] = _three_level(impact_force)
	axes["control"] = _three_level(impact_force)
	axes["breach"] = _three_level(penetration)
	axes["suppress"] = {"deliberate": "none", "balanced": "light", "rapid": "strong"}.get(cadence, "light")
	return axes


static func resolve(
	profile: Dictionary,
	target_context: Dictionary,
	base_damage: float,
	base_reaction: Dictionary = {}
) -> Dictionary:
	if not bool(profile.get("ok", false)):
		return profile
	var parameters := profile.get("final_parameters", {}) as Dictionary
	var mass_class := str(target_context.get("mass_class", "medium"))
	var mass_scale := float({"light": 1.25, "medium": 1.0, "heavy": 0.68}.get(mass_class, 1.0))
	var armor_integrity := clampf(float(target_context.get("armor_integrity", 0.0)), 0.0, 1.0)
	var armored := armor_integrity > 0.0
	var damage_multiplier := float(parameters.get("damage_multiplier", 1.0))
	var displacement_scale := float(parameters.get("displacement_scale", 1.0)) * mass_scale
	var stagger_seconds := float(parameters.get("stagger_seconds", 0.08)) * lerpf(0.82, 1.08, mass_scale / 1.25)
	var armor_damage := float(parameters.get("armor_damage_ratio", 0.0)) if armored else 0.0
	var pin_seconds := float(parameters.get("pin_seconds", 0.0)) * mass_scale
	var entangle_seconds := float(parameters.get("entangle_seconds", 0.0)) * mass_scale
	var suppression_seconds := float(parameters.get("suppression_seconds", 0.0))
	var base_knockback: Vector2 = base_reaction.get("knockback", Vector2.ZERO)
	var base_stagger := float(base_reaction.get("stagger", 0.0))
	var knockback := base_knockback * displacement_scale
	var stagger_strength := maxf(base_stagger, stagger_seconds * 2.2)
	var armor_break := armored and armor_damage >= armor_integrity
	var displacement_mode := str(profile.get("displacement_mode", "away"))
	var primary := _primary_reaction(
		displacement_mode,
		damage_multiplier,
		displacement_scale,
		stagger_seconds,
		pin_seconds,
		entangle_seconds,
		suppression_seconds,
		armor_break
	)
	var target_state := str(target_context.get("state", ""))
	var interrupts := target_state in ["tell", "attack", "charge"] and (
		stagger_seconds >= 0.28
		or pin_seconds >= 0.18
		or entangle_seconds >= 0.22
		or suppression_seconds >= 0.55
		or armor_break
	)
	var immobilize := pin_seconds >= 0.48 or entangle_seconds >= 0.68
	var control_lock := entangle_seconds > 0.0 or suppression_seconds > 0.0
	var status := _status_for(primary)
	var status_seconds := maxf(stagger_seconds, maxf(pin_seconds, maxf(entangle_seconds, suppression_seconds)))
	return {
		"ok": true,
		"schema": RUNTIME_SCHEMA,
		"source": str(profile.get("source", "")),
		"effect_axes": (profile.get("effect_axes", {}) as Dictionary).duplicate(true),
		"final_parameters": parameters.duplicate(true),
		"verb": primary,
		"primary_reaction": primary,
		"status": status,
		"status_seconds": status_seconds,
		"damage_multiplier": damage_multiplier,
		"damage": maxf(0.0, base_damage * damage_multiplier),
		"health_damage": maxf(0.0, base_damage * damage_multiplier),
		"knockback": knockback,
		"displacement_scale": displacement_scale,
		"displacement_pixels": 22.0 * displacement_scale,
		"displacement_mode": displacement_mode,
		"stagger": stagger_strength,
		"stagger_seconds": stagger_seconds,
		"armor_damage": armor_damage,
		"armor_break": armor_break,
		"pin_seconds": pin_seconds,
		"entangle_seconds": entangle_seconds,
		"suppression_seconds": suppression_seconds,
		"immobilize": immobilize,
		"control_lock": control_lock,
		"interrupts_attack": interrupts,
		"player_mechanism_input_used": false,
		"player_confirmation_required": false,
	}


static func finite_difference_audit() -> Dictionary:
	var baseline_axes := default_effect_axes()
	var baseline := compile(baseline_axes, "finite_difference_baseline")
	var baseline_final := baseline.get("final_parameters", {}) as Dictionary
	var axis_cases := {}
	var observed_coverage := {}
	var zero_effect_axes: Array[String] = []
	var covered_effects: Array[Dictionary] = []
	var signatures := {}
	for parameter: String in AUDITED_PARAMETERS:
		observed_coverage[parameter] = []
	for axis: String in EFFECT_AXES:
		var cases: Array[Dictionary] = []
		var changed_for_axis: Array[String] = []
		for level: String in LEVELS:
			if level == "none":
				continue
			var candidate_axes := baseline_axes.duplicate(true)
			candidate_axes[axis] = level
			var compiled := compile(candidate_axes, "finite_difference:%s:%s" % [axis, level])
			var final_parameters := compiled.get("final_parameters", {}) as Dictionary
			var deltas := {}
			for parameter: String in AUDITED_PARAMETERS:
				var delta := _parameter_delta(baseline_final.get(parameter), final_parameters.get(parameter))
				deltas[parameter] = delta
				if not is_zero_approx(delta) and parameter not in changed_for_axis:
					changed_for_axis.append(parameter)
					(observed_coverage[parameter] as Array).append(axis)
					if str(PARAMETER_OWNERS.get(parameter, "")) != axis:
						covered_effects.append({"axis": axis, "parameter": parameter, "level": level})
			cases.append({
				"level": level,
				"final_parameters": final_parameters.duplicate(true),
				"deltas": deltas,
			})
		axis_cases[axis] = cases
		if changed_for_axis.is_empty():
			zero_effect_axes.append(axis)
		var signature_parts := PackedStringArray()
		changed_for_axis.sort()
		for parameter: String in changed_for_axis:
			signature_parts.append(parameter)
		var signature := ",".join(signature_parts)
		if not signature.is_empty():
			if not signatures.has(signature):
				signatures[signature] = []
			(signatures[signature] as Array).append(axis)
	var duplicate_direction_groups: Array[Array] = []
	for signature: String in signatures:
		var group := signatures[signature] as Array
		if group.size() > 1:
			duplicate_direction_groups.append(group.duplicate())
	var parameter_coverage := {}
	var uncovered_parameters: Array[String] = []
	var owner_mismatches: Array[Dictionary] = []
	for parameter: String in AUDITED_PARAMETERS:
		var observed_axes := observed_coverage[parameter] as Array
		var declared_owner := str(PARAMETER_OWNERS.get(parameter, ""))
		parameter_coverage[parameter] = {
			"declared_owner": declared_owner,
			"observed_axes": observed_axes.duplicate(),
			"covered": not observed_axes.is_empty(),
		}
		if observed_axes.is_empty():
			uncovered_parameters.append(parameter)
		elif observed_axes.size() != 1 or str(observed_axes[0]) != declared_owner:
			owner_mismatches.append({
				"parameter": parameter,
				"declared_owner": declared_owner,
				"observed_axes": observed_axes.duplicate(),
			})
	return {
		"ok": true,
		"schema": AUDIT_SCHEMA,
		"runtime_schema": RUNTIME_SCHEMA,
		"baseline_effect_axes": baseline_axes,
		"baseline_final_parameters": baseline_final.duplicate(true),
		"axis_cases": axis_cases,
		"parameter_coverage": parameter_coverage,
		"zero_effect_axes": zero_effect_axes,
		"duplicate_direction_groups": duplicate_direction_groups,
		"covered_effects": covered_effects,
		"uncovered_parameters": uncovered_parameters,
		"owner_mismatches": owner_mismatches,
		"passed": (
			zero_effect_axes.is_empty()
			and duplicate_direction_groups.is_empty()
			and covered_effects.is_empty()
			and uncovered_parameters.is_empty()
			and owner_mismatches.is_empty()
		),
		"player_confirmation_required": false,
	}


static func _raw_parameter_matrix(axes: Dictionary) -> Dictionary:
	return {
		"damage_multiplier": float({"none": 1.0, "light": 1.06, "medium": 1.16, "strong": 1.30}[str(axes["wound"])]),
		"displacement_scale": float({"none": 0.35, "light": 0.75, "medium": 1.15, "strong": 1.65}[str(axes["impulse"])]),
		"stagger_seconds": float({"none": 0.08, "light": 0.14, "medium": 0.28, "strong": 0.55}[str(axes["control"])]),
		"armor_damage_ratio": float({"none": 0.0, "light": 0.12, "medium": 0.28, "strong": 0.52}[str(axes["breach"])]),
		"pin_seconds": float({"none": 0.0, "light": 0.18, "medium": 0.48, "strong": 0.82}[str(axes["pin"])]),
		"entangle_seconds": float({"none": 0.0, "light": 0.22, "medium": 0.68, "strong": 1.10}[str(axes["bind"])]),
		"suppression_seconds": float({"none": 0.0, "light": 0.18, "medium": 0.55, "strong": 0.95}[str(axes["suppress"])]),
	}


static func _clamp_parameter_matrix(raw: Dictionary) -> Dictionary:
	var final := {}
	var clamp_events: Array[Dictionary] = []
	for parameter: String in AUDITED_PARAMETERS:
		var bounds := PARAMETER_BOUNDS[parameter] as Array
		var raw_value := float(raw.get(parameter, 0.0))
		var final_value := clampf(raw_value, float(bounds[0]), float(bounds[1]))
		final[parameter] = final_value
		if not is_equal_approx(raw_value, final_value):
			clamp_events.append({
				"parameter": parameter,
				"raw": raw_value,
				"final": final_value,
				"minimum": bounds[0],
				"maximum": bounds[1],
			})
	return {"parameters": final, "clamp_events": clamp_events}


static func _axis_snapshot(effect_axes: Dictionary) -> Dictionary:
	var result := {}
	for axis: String in EFFECT_AXES:
		result[axis] = str(effect_axes.get(axis, ""))
	return result


static func _source_value(source: Variant, property_name: String, fallback: Variant) -> Variant:
	if source == null:
		return fallback
	if source is Dictionary:
		return (source as Dictionary).get(property_name, fallback)
	var value: Variant = source.get(property_name)
	return fallback if value == null else value


static func _raise_level(level: String) -> String:
	var index := LEVELS.find(level)
	return LEVELS[mini(LEVELS.size() - 1, maxi(0, index + 1))]


static func _higher_level(left: String, right: String) -> String:
	return left if LEVELS.find(left) >= LEVELS.find(right) else right


static func _three_level(value: String) -> String:
	return {"light": "light", "medium": "medium", "strong": "strong"}.get(value, "medium")


static func _primary_reaction(
	displacement_mode: String,
	damage_multiplier: float,
	displacement_scale: float,
	stagger_seconds: float,
	pin_seconds: float,
	entangle_seconds: float,
	suppression_seconds: float,
	armor_break: bool
) -> String:
	if armor_break:
		return "armor_break"
	if displacement_mode == "toward_source" and entangle_seconds > 0.0:
		return "hook_pull"
	if entangle_seconds >= 0.68:
		return "entangle"
	if pin_seconds >= 0.48:
		return "pin"
	if suppression_seconds > 0.0:
		return "suppress"
	if displacement_scale >= 1.45:
		return "shove"
	if damage_multiplier >= 1.20:
		return "cleave"
	if stagger_seconds >= 0.28:
		return "stagger"
	return "impact"


static func _status_for(primary: String) -> String:
	return {
		"armor_break": "ARMOR BROKEN",
		"hook_pull": "HOOKED",
		"entangle": "ENTANGLED",
		"pin": "PINNED",
		"suppress": "SUPPRESSED",
		"shove": "DISPLACED",
		"cleave": "WOUNDED",
		"stagger": "STAGGERED",
		"impact": "IMPACT",
	}.get(primary, "IMPACT")


static func _parameter_delta(left: Variant, right: Variant) -> float:
	if left == null or right == null:
		return 0.0
	return float(right) - float(left)
