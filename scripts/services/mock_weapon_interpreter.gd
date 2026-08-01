class_name MockWeaponInterpreter
extends WeaponInterpreter

const BLUEPRINT_SCRIPT := preload("res://scripts/data/weapon_blueprint.gd")
const DELTA_SCRIPT := preload("res://scripts/data/blueprint_delta.gd")

func interpret(player_text: String, _sketch_png: PackedByteArray, geometry: Dictionary, _current: WeaponBlueprint = null, _modification: String = "", clarification: String = "") -> Dictionary:
	var normalized := player_text.strip_edges().to_lower()
	var blueprint: WeaponBlueprint
	var family_hint := _family_hint(normalized, clarification)
	if family_hint == "unclear":
		return {
			"ok": true, "needs_clarification": true, "confidence": 0.42,
			"question": "你希望它主要用于近距离挥砍，还是飞出去攻击？"
		}
	match family_hint:
		"returning_thrown": blueprint = BLUEPRINT_SCRIPT.fixed_blueprint("umbrella")
		"heavy_melee": blueprint = BLUEPRINT_SCRIPT.fixed_blueprint("greatsword")
		_: blueprint = BLUEPRINT_SCRIPT.fixed_blueprint("gatling")
	_apply_geometry(blueprint, geometry)
	return {
		"ok": true, "needs_clarification": false, "confidence": blueprint.confidence,
		"blueprint": blueprint, "explanation": player_explanation(blueprint), "source": "LOCAL MOCK"
	}

func apply_delta(current: WeaponBlueprint, request: String) -> Dictionary:
	var delta := DELTA_SCRIPT.new() as BlueprintDelta
	delta.requested_change = request.strip_edges()
	var changed := WeaponBlueprint.from_dict(current.to_dict())
	var normalized := request.to_lower()
	if _contains_any(normalized, ["穿透", "pierce"]):
		delta.accepted_change = "limited_pierce"
		delta.effect_delta = "limited_pierce"
		delta.visual_delta = "longer_projectile_trace"
		delta.tradeoff = "lower_projectile_damage"
		delta.player_summary = "可以增加有限穿透；代价是单发伤害降低。"
		changed.modifiers["limited_pierce"] = true
		changed.modifiers["damage_multiplier"] = 0.78
	elif _contains_any(normalized, ["不要过热", "降低过热", "less heat", "no overheat"]):
		delta.accepted_change = "slower_overheat"
		delta.cadence_delta = "lower_sustained_intensity"
		delta.drawback_delta = "reduced_not_removed"
		delta.visual_delta = "smaller_blue_flame"
		delta.tradeoff = "lower_fire_rate"
		delta.player_summary = "可以降低过热速度，但会同时降低持续射击强度。"
		changed.modifiers["heat_multiplier"] = 0.58
		changed.modifiers["fire_rate_multiplier"] = 0.72
	elif _contains_any(normalized, ["更快", "轻", "faster", "lighter"]):
		delta.accepted_change = "lighter_frame"
		delta.cadence_delta = "faster_startup"
		delta.weight_delta = "one_step_lighter"
		delta.effect_delta = "lower_impact"
		delta.visual_delta = "slimmer_silhouette"
		delta.tradeoff = "lower_damage"
		delta.player_summary = "可以减轻并加快启动；代价是冲击伤害降低。"
		changed.weight_class = "medium"
		changed.silhouette_aspect += 0.25
		changed.modifiers["startup_multiplier"] = 0.72
		changed.modifiers["damage_multiplier"] = 0.82
	elif _contains_any(normalized, ["范围", "更大", "area", "bigger"]):
		delta.accepted_change = "wider_effect"
		delta.effect_delta = "larger_radius"
		delta.visual_delta = "wider_head"
		delta.tradeoff = "longer_recovery"
		delta.player_summary = "可以扩大命中范围；代价是攻击后的恢复时间更长。"
		changed.modifiers["area_multiplier"] = 1.4
		changed.modifiers["recovery_multiplier"] = 1.25
	else:
		delta.accepted_change = "balanced_tuning"
		delta.effect_delta = "clearer_signature"
		delta.visual_delta = "stronger_element_color"
		delta.tradeoff = "slightly_longer_recovery"
		delta.player_summary = "这项表达超出 V1 的精确词表；已改为强化标志效果，代价是恢复稍慢。"
		changed.modifiers["signature_multiplier"] = 1.25
		changed.modifiers["recovery_multiplier"] = 1.12
	changed.display_name += "·改"
	changed.fantasy_summary = delta.player_summary
	changed.validate_and_repair()
	return {"ok": delta.is_valid(), "delta": delta, "blueprint": changed, "explanation": player_explanation(changed)}

func player_explanation(blueprint: WeaponBlueprint) -> String:
	match blueprint.behavior_family:
		"returning_thrown":
			return "我会把它锻造成一柄机械回旋武器。它会飞出并沿电弧返回，去程和回程都能命中；武器返回前不能再次投掷。"
		"heavy_melee":
			return "我会把它锻造成一柄双手重型锯剑。它启动较慢，但命中会回收少量生命；攻击期间机动性会下降。"
		_:
			return "我会把它锻造成一把重型连续射击武器。它会先旋转枪管，再持续喷射蓝焰弹丸；连续开火会过热，持有时移动较慢。"

func _family_hint(text: String, clarification: String) -> String:
	var combined := text + " " + clarification.to_lower()
	if _contains_any(combined, ["伞", "返回", "回旋", "投掷", "飞出去", "umbrella", "return", "throw"]):
		return "returning_thrown"
	if _contains_any(combined, ["剑", "锯", "近距离", "挥砍", "吸血", "sword", "melee", "slash"]):
		return "heavy_melee"
	if _contains_any(combined, ["枪", "加特林", "射击", "蓝火", "gatling", "gun", "fire"]):
		return "sustained_ranged"
	if text.is_empty():
		return "unclear"
	return "sustained_ranged"

func _apply_geometry(blueprint: WeaponBlueprint, geometry: Dictionary) -> void:
	if geometry.is_empty() or int(geometry.get("stroke_count", 0)) == 0:
		return
	blueprint.silhouette_aspect = clampf(float(geometry.get("aspect_ratio", blueprint.silhouette_aspect)), 0.7, 4.2)
	var axis := str(geometry.get("dominant_axis", "horizontal"))
	if axis == "vertical" and blueprint.behavior_family == "returning_thrown":
		blueprint.silhouette_curvature = "arched_vertical"
	blueprint.confidence = 0.86

func _contains_any(text: String, needles: Array[String]) -> bool:
	for needle: String in needles:
		if text.contains(needle):
			return true
	return false

