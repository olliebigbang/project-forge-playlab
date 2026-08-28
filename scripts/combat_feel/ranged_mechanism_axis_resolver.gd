class_name RangedMechanismAxisResolver
extends RefCounted

const RUNTIME_SCHEMA := "forge-ranged-runtime-profile-v4"
const AUDIT_SCHEMA := "forge-ranged-mechanism-finite-difference-audit-v4"

const STRUCTURAL_AXES: PackedStringArray = [
	"weapon_domain", "layout", "stock_structure", "feed_position",
	"magazine_shape", "barrel_length", "upper_profile", "support_mode",
]
const MECHANISM_AXES: PackedStringArray = [
	"fire_control", "cadence", "recoil", "recoil_recovery", "muzzle_climb",
	"accuracy", "impact_force", "penetration", "reload", "effective_range",
	"handling", "magazine_capacity",
]
const REQUIRED_AXES: PackedStringArray = [
	"weapon_domain", "layout", "stock_structure", "feed_position",
	"magazine_shape", "barrel_length", "upper_profile", "support_mode",
	"fire_control", "cadence", "recoil", "recoil_recovery", "muzzle_climb",
	"accuracy", "impact_force", "penetration", "reload", "effective_range",
	"handling", "magazine_capacity",
]

const LEGAL_VALUES := {
	"weapon_domain": ["handheld_firearm"],
	"layout": ["bullpup", "conventional_rifle", "pistol"],
	"stock_structure": ["integrated", "telescoping", "fixed", "none"],
	"feed_position": ["behind_grip", "ahead_of_grip", "in_grip"],
	"magazine_shape": ["straight", "curved", "in_grip"],
	"barrel_length": ["short", "medium", "long"],
	"upper_profile": ["carry_handle", "top_rail", "raised_gas_tube", "slide"],
	"support_mode": ["one_hand", "two_hand_shouldered"],
	"fire_control": ["semi_auto", "three_round_burst", "select_fire_auto", "manual_cycle"],
	"cadence": ["deliberate", "balanced", "rapid"],
	"recoil": ["light", "medium", "strong"],
	"recoil_recovery": ["quick", "balanced", "slow"],
	"muzzle_climb": ["low", "medium", "high"],
	"accuracy": ["precise", "controlled", "loose"],
	"impact_force": ["light", "medium", "strong"],
	"penetration": ["light", "medium", "strong"],
	"reload": ["quick", "standard", "slow"],
	"effective_range": ["short", "medium", "long"],
	"handling": ["agile", "balanced", "heavy"],
	"magazine_capacity": ["compact", "standard", "extended"],
}

const AXIS_LABELS_ZH := {
	"weapon_domain": "武器平台",
	"layout": "枪身布局",
	"stock_structure": "枪托结构",
	"feed_position": "供弹位置",
	"magazine_shape": "弹匣轮廓",
	"barrel_length": "枪管长度",
	"upper_profile": "上方轮廓",
	"support_mode": "持枪方式",
	"fire_control": "击发方式",
	"cadence": "射击节奏",
	"recoil": "后坐冲量",
	"recoil_recovery": "后坐恢复",
	"muzzle_climb": "枪口上跳",
	"accuracy": "基础散布",
	"impact_force": "命中冲击",
	"penetration": "穿透能力",
	"reload": "换弹复杂度",
	"effective_range": "有效距离",
	"handling": "操控惯性",
	"magazine_capacity": "弹匣容量",
}

const OPTION_LABELS_ZH := {
	"weapon_domain": {"handheld_firearm": "手持枪械"},
	"layout": {"bullpup": "无托式", "conventional_rifle": "常规步枪", "pistol": "手枪"},
	"stock_structure": {"integrated": "一体式后托", "telescoping": "伸缩托", "fixed": "固定托", "none": "无枪托"},
	"feed_position": {"behind_grip": "握把后供弹", "ahead_of_grip": "握把前供弹", "in_grip": "握把内供弹"},
	"magazine_shape": {"straight": "直弹匣", "curved": "弯弹匣", "in_grip": "藏在握把内"},
	"barrel_length": {"short": "短", "medium": "中等", "long": "长"},
	"upper_profile": {"carry_handle": "提把轮廓", "top_rail": "平直导轨", "raised_gas_tube": "抬高导气结构", "slide": "手枪套筒"},
	"support_mode": {"one_hand": "单手", "two_hand_shouldered": "双手抵肩"},
	"fire_control": {
		"semi_auto": "按一下打一发",
		"three_round_burst": "按一下三连发",
		"select_fire_auto": "按住连续射击",
		"manual_cycle": "每发后自动拉栓",
	},
	"cadence": {"deliberate": "从容", "balanced": "均衡", "rapid": "快速"},
	"recoil": {"light": "轻", "medium": "中", "strong": "强"},
	"recoil_recovery": {"quick": "快速回正", "balanced": "均衡回正", "slow": "缓慢回正"},
	"muzzle_climb": {"low": "低", "medium": "中", "high": "高"},
	"accuracy": {"precise": "集中", "controlled": "可控", "loose": "较散"},
	"impact_force": {"light": "轻", "medium": "中", "strong": "强"},
	"penetration": {"light": "低", "medium": "中", "strong": "高"},
	"reload": {"quick": "快", "standard": "标准", "slow": "慢"},
	"effective_range": {"short": "短", "medium": "中", "long": "长"},
	"handling": {"agile": "灵活", "balanced": "均衡", "heavy": "沉重"},
	"magazine_capacity": {"compact": "小", "standard": "标准", "extended": "大"},
}

# Every audited parameter has exactly one declared owner. Multi-output axes are
# allowed, but hidden model-name branches and ownerless runtime numbers are not.
const PARAMETER_OWNERS := {
	"automatic_fire": "fire_control",
	"burst_size": "fire_control",
	"manual_cycle_required": "fire_control",
	"manual_cycle_lock_seconds": "fire_control",
	"shot_interval_seconds": "cadence",
	"recoil_pixels": "recoil",
	"recoil_recovery_pixels_per_second": "recoil_recovery",
	"muzzle_climb_recovery_degrees_per_second": "recoil_recovery",
	"muzzle_climb_degrees_per_shot": "muzzle_climb",
	"spread_velocity": "accuracy",
	"projectile_damage": "impact_force",
	"hit_stagger_seconds": "impact_force",
	"projectile_radius_pixels": "impact_force",
	"armor_damage_multiplier": "penetration",
	"pierce_budget": "penetration",
	"tracer_width_pixels": "penetration",
	"reload_seconds": "reload",
	"projectile_speed": "effective_range",
	"projectile_life_seconds": "effective_range",
	"damage_falloff_start_pixels": "effective_range",
	"damage_falloff_end_pixels": "effective_range",
	"tracer_length_pixels": "effective_range",
	"movement_multiplier": "handling",
	"firing_movement_multiplier": "handling",
	"magazine_size": "magazine_capacity",
}
const AUDITED_PARAMETERS: PackedStringArray = [
	"automatic_fire", "burst_size", "manual_cycle_required", "manual_cycle_lock_seconds",
	"shot_interval_seconds", "recoil_pixels",
	"recoil_recovery_pixels_per_second", "muzzle_climb_recovery_degrees_per_second",
	"muzzle_climb_degrees_per_shot", "spread_velocity", "projectile_damage",
	"hit_stagger_seconds", "projectile_radius_pixels", "armor_damage_multiplier",
	"pierce_budget", "tracer_width_pixels",
	"reload_seconds", "projectile_speed", "projectile_life_seconds",
	"damage_falloff_start_pixels", "damage_falloff_end_pixels", "tracer_length_pixels",
	"movement_multiplier", "firing_movement_multiplier", "magazine_size",
]
const PARAMETER_BOUNDS := {
	"shot_interval_seconds": [0.08, 0.36],
	"burst_size": [0, 3],
	"manual_cycle_lock_seconds": [0.0, 1.20],
	"recoil_pixels": [2.0, 14.0],
	"recoil_recovery_pixels_per_second": [30.0, 130.0],
	"muzzle_climb_recovery_degrees_per_second": [10.0, 45.0],
	"muzzle_climb_degrees_per_shot": [1.0, 11.0],
	"spread_velocity": [2.0, 26.0],
	"projectile_damage": [5.0, 18.0],
	"hit_stagger_seconds": [0.06, 0.22],
	"projectile_radius_pixels": [2.0, 6.0],
	"armor_damage_multiplier": [0.45, 1.0],
	"pierce_budget": [0, 2],
	"tracer_width_pixels": [1.0, 5.0],
	"reload_seconds": [0.60, 2.0],
	"projectile_speed": [500.0, 820.0],
	"projectile_life_seconds": [0.70, 1.75],
	"damage_falloff_start_pixels": [220.0, 780.0],
	"damage_falloff_end_pixels": [420.0, 1180.0],
	"tracer_length_pixels": [8.0, 26.0],
	"movement_multiplier": [0.70, 1.0],
	"firing_movement_multiplier": [0.55, 0.98],
	"magazine_size": [6, 40],
}
const INTEGER_PARAMETERS: PackedStringArray = ["burst_size", "pierce_budget", "magazine_size"]
const BOOLEAN_PARAMETERS: PackedStringArray = ["automatic_fire", "manual_cycle_required"]


static func validate_ai_declaration(payload: Dictionary, source: String) -> Dictionary:
	if payload.is_empty():
		return _failure("AI_RANGED_AXES_MISSING")
	var declared_source := source.strip_edges()
	if declared_source.is_empty():
		declared_source = str(payload.get("source", "")).strip_edges()
	if declared_source.is_empty():
		return _failure("AI_RANGED_AXES_SOURCE_MISSING")
	if not _trusted_source(declared_source):
		return _failure("UNTRUSTED_AI_RANGED_AXES_SOURCE")
	var errors := PackedStringArray()
	for axis: String in REQUIRED_AXES:
		if not payload.has(axis):
			errors.append("AI_RANGED_AXIS_MISSING:%s" % axis)
			continue
		var value := str(payload.get(axis, ""))
		if value not in (LEGAL_VALUES.get(axis, []) as Array):
			errors.append("AI_RANGED_AXIS_INVALID:%s:%s" % [axis, value])
	var confidence := float(payload.get("confidence", -1.0))
	if confidence < 0.0 or confidence > 1.0:
		errors.append("AI_RANGED_CONFIDENCE_INVALID")
	if errors.is_empty():
		errors.append_array(_combination_errors(payload))
	if not errors.is_empty():
		return {
			"ok": false,
			"error": errors[0],
			"errors": errors,
			"player_confirmation_required": false,
		}
	return {
		"ok": true,
		"complete": true,
		"source": declared_source,
		"confidence": confidence,
		"axes": _axis_snapshot(payload),
		"player_confirmation_required": false,
	}


static func compile(payload: Dictionary, source: String) -> Dictionary:
	var validation := validate_ai_declaration(payload, source)
	if not bool(validation.get("ok", false)):
		return validation
	var raw_parameters := _raw_parameter_matrix(payload)
	var clamped := _clamp_parameter_matrix(raw_parameters)
	var final_parameters := clamped.get("parameters", {}) as Dictionary
	var axes := _axis_snapshot(payload)
	var result := {
		"ok": true,
		"schema": RUNTIME_SCHEMA,
		"source": str(validation.get("source", source)),
		"confidence": float(validation.get("confidence", 0.0)),
		"axes": axes,
		"axis_signature": JSON.stringify(axes).sha256_text().left(16),
		"raw_parameters": raw_parameters,
		"final_parameters": final_parameters,
		"clamp_events": clamped.get("clamp_events", []),
		"parameter_owners": PARAMETER_OWNERS.duplicate(true),
		"muzzle_flash_seconds": 0.065,
		"player_mechanism_input_used": false,
		"player_confirmation_required": false,
	}
	for parameter: String in final_parameters:
		result[parameter] = final_parameters[parameter]
	return result


static func finite_difference_audit(payload: Dictionary, source: String) -> Dictionary:
	var baseline := compile(payload, source)
	if not bool(baseline.get("ok", false)):
		return baseline
	var baseline_raw := baseline.get("raw_parameters", {}) as Dictionary
	var baseline_final := baseline.get("final_parameters", {}) as Dictionary
	var axis_cases := {}
	var observed_coverage := {}
	var zero_effect_axes: Array[String] = []
	var covered_effects: Array[Dictionary] = []
	var direction_signatures := {}
	for parameter: String in AUDITED_PARAMETERS:
		observed_coverage[parameter] = []
	for axis: String in MECHANISM_AXES:
		var cases: Array[Dictionary] = []
		var changed_parameters: Array[String] = []
		var legal_values := LEGAL_VALUES.get(axis, []) as Array
		for alternative: String in legal_values:
			var changed_payload := payload.duplicate(true)
			changed_payload[axis] = alternative
			var compiled := compile(changed_payload, source)
			if not bool(compiled.get("ok", false)):
				return _failure("FINITE_DIFFERENCE_CASE_INVALID:%s:%s" % [axis, alternative])
			var raw := compiled.get("raw_parameters", {}) as Dictionary
			var final := compiled.get("final_parameters", {}) as Dictionary
			var delta := {}
			var changed_in_case: Array[String] = []
			for parameter: String in AUDITED_PARAMETERS:
				var raw_changed := _parameter_changed(baseline_raw.get(parameter), raw.get(parameter))
				var final_changed := _parameter_changed(baseline_final.get(parameter), final.get(parameter))
				if final_changed:
					delta[parameter] = _parameter_delta(baseline_final.get(parameter), final.get(parameter))
					changed_in_case.append(parameter)
					if parameter not in changed_parameters:
						changed_parameters.append(parameter)
					var observers := observed_coverage.get(parameter, []) as Array
					if axis not in observers:
						observers.append(axis)
					observed_coverage[parameter] = observers
				elif raw_changed:
					covered_effects.append({
						"axis": axis,
						"value": alternative,
						"parameter": parameter,
						"raw": raw.get(parameter),
						"final": final.get(parameter),
						"reason": "FINAL_CLAMP_COVERED_RAW_CHANGE",
					})
			cases.append({
				"value": alternative,
				"is_baseline": alternative == str(payload.get(axis, "")),
				"final_parameters": final.duplicate(true),
				"delta_from_baseline": delta,
				"changed_parameters": changed_in_case,
				"clamp_events": (compiled.get("clamp_events", []) as Array).duplicate(true),
			})
		if changed_parameters.is_empty():
			zero_effect_axes.append(axis)
		axis_cases[axis] = {
			"baseline_value": str(payload.get(axis, "")),
			"changed_parameters": changed_parameters,
			"cases": cases,
		}
		var low_payload := payload.duplicate(true)
		var high_payload := payload.duplicate(true)
		low_payload[axis] = str(legal_values.front())
		high_payload[axis] = str(legal_values.back())
		var low_final := (compile(low_payload, source).get("final_parameters", {}) as Dictionary)
		var high_final := (compile(high_payload, source).get("final_parameters", {}) as Dictionary)
		var direction_parts: Array[String] = []
		for parameter: String in AUDITED_PARAMETERS:
			var direction := signf(_parameter_delta(low_final.get(parameter), high_final.get(parameter)))
			if direction != 0.0:
				direction_parts.append("%s:%d" % [parameter, int(direction)])
		direction_signatures[axis] = "|".join(direction_parts)
	var duplicate_direction_groups: Array[Array] = []
	var signature_groups := {}
	for axis: String in MECHANISM_AXES:
		var signature := str(direction_signatures.get(axis, ""))
		if signature.is_empty():
			continue
		var group := signature_groups.get(signature, []) as Array
		group.append(axis)
		signature_groups[signature] = group
	for signature: String in signature_groups:
		var group := signature_groups[signature] as Array
		if group.size() > 1:
			duplicate_direction_groups.append(group)
	var coverage := {}
	var uncovered_parameters: Array[String] = []
	var owner_mismatches: Array[Dictionary] = []
	for parameter: String in AUDITED_PARAMETERS:
		var declared_owner := str(PARAMETER_OWNERS.get(parameter, ""))
		var observed_axes := observed_coverage.get(parameter, []) as Array
		coverage[parameter] = {
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
		"baseline_axes": _axis_snapshot(payload),
		"baseline_final_parameters": baseline_final.duplicate(true),
		"axis_cases": axis_cases,
		"parameter_coverage": coverage,
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


static func _raw_parameter_matrix(payload: Dictionary) -> Dictionary:
	var cadence := str(payload.get("cadence", "balanced"))
	var recoil := str(payload.get("recoil", "medium"))
	var recoil_recovery := str(payload.get("recoil_recovery", "balanced"))
	var muzzle_climb := str(payload.get("muzzle_climb", "medium"))
	var accuracy := str(payload.get("accuracy", "controlled"))
	var impact_force := str(payload.get("impact_force", "medium"))
	var penetration := str(payload.get("penetration", "medium"))
	var reload := str(payload.get("reload", "standard"))
	var effective_range := str(payload.get("effective_range", "medium"))
	var handling := str(payload.get("handling", "balanced"))
	var capacity := str(payload.get("magazine_capacity", "standard"))
	return {
		"automatic_fire": str(payload.get("fire_control", "semi_auto")) == "select_fire_auto",
		"burst_size": 3 if str(payload.get("fire_control", "semi_auto")) == "three_round_burst" else 0,
		"manual_cycle_required": str(payload.get("fire_control", "semi_auto")) == "manual_cycle",
		"manual_cycle_lock_seconds": 0.82 if str(payload.get("fire_control", "semi_auto")) == "manual_cycle" else 0.0,
		"shot_interval_seconds": float({"deliberate": 0.28, "balanced": 0.17, "rapid": 0.10}[cadence]),
		"recoil_pixels": float({"light": 3.0, "medium": 7.0, "strong": 12.0}[recoil]),
		"recoil_recovery_pixels_per_second": float({"quick": 112.0, "balanced": 70.0, "slow": 42.0}[recoil_recovery]),
		"muzzle_climb_recovery_degrees_per_second": float({"quick": 38.0, "balanced": 24.0, "slow": 15.0}[recoil_recovery]),
		"muzzle_climb_degrees_per_shot": float({"low": 2.5, "medium": 5.5, "high": 9.0}[muzzle_climb]),
		"spread_velocity": float({"precise": 4.0, "controlled": 11.0, "loose": 22.0}[accuracy]),
		"projectile_damage": float({"light": 7.0, "medium": 10.0, "strong": 14.0}[impact_force]),
		"hit_stagger_seconds": float({"light": 0.08, "medium": 0.12, "strong": 0.18}[impact_force]),
		"projectile_radius_pixels": float({"light": 2.5, "medium": 4.0, "strong": 5.5}[impact_force]),
		"armor_damage_multiplier": float({"light": 0.50, "medium": 0.72, "strong": 0.92}[penetration]),
		"pierce_budget": int({"light": 0, "medium": 1, "strong": 2}[penetration]),
		"tracer_width_pixels": float({"light": 2.0, "medium": 3.0, "strong": 4.0}[penetration]),
		"reload_seconds": float({"quick": 0.78, "standard": 1.18, "slow": 1.62}[reload]),
		"projectile_speed": float({"short": 570.0, "medium": 660.0, "long": 745.0}[effective_range]),
		"projectile_life_seconds": float({"short": 0.82, "medium": 1.20, "long": 1.55}[effective_range]),
		"damage_falloff_start_pixels": float({"short": 270.0, "medium": 480.0, "long": 720.0}[effective_range]),
		"damage_falloff_end_pixels": float({"short": 500.0, "medium": 800.0, "long": 1120.0}[effective_range]),
		"tracer_length_pixels": float({"short": 10.0, "medium": 16.0, "long": 24.0}[effective_range]),
		"movement_multiplier": float({"agile": 1.0, "balanced": 0.90, "heavy": 0.78}[handling]),
		"firing_movement_multiplier": float({"agile": 0.95, "balanced": 0.82, "heavy": 0.65}[handling]),
		"magazine_size": int({"compact": 10, "standard": 24, "extended": 32}[capacity]),
	}


static func _clamp_parameter_matrix(raw: Dictionary) -> Dictionary:
	var final := {}
	var clamp_events: Array[Dictionary] = []
	for parameter: String in AUDITED_PARAMETERS:
		var raw_value: Variant = raw.get(parameter)
		if parameter in BOOLEAN_PARAMETERS:
			final[parameter] = bool(raw_value)
			continue
		var bounds := PARAMETER_BOUNDS.get(parameter, []) as Array
		if bounds.size() != 2:
			continue
		var final_value: Variant
		if parameter in INTEGER_PARAMETERS:
			final_value = clampi(int(raw_value), int(bounds[0]), int(bounds[1]))
		else:
			final_value = clampf(float(raw_value), float(bounds[0]), float(bounds[1]))
		final[parameter] = final_value
		if _parameter_changed(raw_value, final_value):
			clamp_events.append({
				"parameter": parameter,
				"raw": raw_value,
				"final": final_value,
				"minimum": bounds[0],
				"maximum": bounds[1],
			})
	return {"parameters": final, "clamp_events": clamp_events}


static func _parameter_changed(left: Variant, right: Variant) -> bool:
	if left is bool or right is bool:
		return bool(left) != bool(right)
	if left == null or right == null:
		return left != right
	return not is_equal_approx(float(left), float(right))


static func _parameter_delta(left: Variant, right: Variant) -> float:
	if left is bool or right is bool:
		return float(int(bool(right)) - int(bool(left)))
	if left == null or right == null:
		return 0.0
	return float(right) - float(left)


static func _axis_snapshot(payload: Dictionary) -> Dictionary:
	var result := {}
	for axis: String in REQUIRED_AXES:
		result[axis] = str(payload.get(axis, ""))
	return result


static func _combination_errors(payload: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var layout := str(payload.get("layout", ""))
	var stock := str(payload.get("stock_structure", ""))
	var feed := str(payload.get("feed_position", ""))
	var magazine := str(payload.get("magazine_shape", ""))
	var support := str(payload.get("support_mode", ""))
	var barrel := str(payload.get("barrel_length", ""))
	var upper := str(payload.get("upper_profile", ""))
	match layout:
		"bullpup":
			if feed != "behind_grip" or stock != "integrated" or support != "two_hand_shouldered":
				errors.append("AI_RANGED_STRUCTURE_CONFLICT:BULLPUP")
		"conventional_rifle":
			if feed != "ahead_of_grip" or stock == "none" or support != "two_hand_shouldered":
				errors.append("AI_RANGED_STRUCTURE_CONFLICT:CONVENTIONAL")
		"pistol":
			if feed != "in_grip" or magazine != "in_grip" or stock != "none" or support != "one_hand" or barrel != "short" or upper != "slide":
				errors.append("AI_RANGED_STRUCTURE_CONFLICT:PISTOL")
	return errors


static func _trusted_source(source: String) -> bool:
	var normalized := source.strip_edges().to_upper()
	return normalized.begins_with("AI_") or normalized.contains("_AI_")


static func _failure(error: String) -> Dictionary:
	return {
		"ok": false,
		"error": error,
		"retry_required": true,
		"player_confirmation_required": false,
	}
