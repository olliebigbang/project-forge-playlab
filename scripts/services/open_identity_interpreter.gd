class_name OpenIdentityInterpreter
extends WeaponInterpreter

const BLUEPRINT_SCRIPT := preload("res://scripts/data/weapon_blueprint.gd")
const DELTA_SCRIPT := preload("res://scripts/data/blueprint_delta.gd")
const VISUAL_PROMPT_SCRIPT := preload("res://scripts/services/open_identity_visual_prompt.gd")

const IDENTITY_QUESTION := "你画的是什么？"
const BEHAVIOR_QUESTION := "你希望它怎么打：持续发射、飞出后返回，还是作为重物近战？"
const SOURCE_LABEL := "PLAYER TEXT PASSTHROUGH + LOCAL RULE BEHAVIOR COMPILER"

# These lists contain actions only. Object nouns must never select a behavior family.
const RETURNING_ACTIONS: Array[String] = [
	"飞出去", "飞出", "飞回", "返回", "回来", "回旋", "投掷", "抛出",
	"returning", "returns", "return", "thrown", "throw"
]
const HEAVY_ACTIONS: Array[String] = [
	"吸血", "挥砍", "劈砍", "重击", "猛击", "砸向", "敲击", "近战",
	"lifesteal", "life steal", "melee", "slash", "heavy strike"
]
const SUSTAINED_ACTIONS: Array[String] = [
	"连续", "持续", "发射", "射击", "扫射", "喷射", "喷出", "放出", "释放",
	"continuous", "sustained", "shoot", "firing", "fires", "emit", "spray", "stream"
]

func interpret(player_text: String, sketch_png: PackedByteArray, geometry: Dictionary, _current: WeaponBlueprint = null, _modification: String = "", clarification: String = "") -> Dictionary:
	var raw_text := player_text.strip_edges()
	var parsed_clarification := _parse_clarification(clarification)
	var identity := raw_text
	var identity_was_clarified := false
	if identity.is_empty():
		identity = str(parsed_clarification.get("identity", "")).strip_edges()
		if identity.is_empty() and not clarification.strip_edges().is_empty() and str(parsed_clarification.get("behavior", "")).is_empty():
			identity = clarification.strip_edges()
		identity_was_clarified = not identity.is_empty()
	if identity.is_empty():
		return _clarification_result("identity", IDENTITY_QUESTION, 0.0, "player_identity_missing")

	var explicit_behavior := _canonical_family(str(parsed_clarification.get("behavior", "")))
	if explicit_behavior.is_empty() and not raw_text.is_empty():
		explicit_behavior = _canonical_family(clarification)
	var family := explicit_behavior
	if family.is_empty():
		var detected_families := _matching_behavior_families(identity)
		if detected_families.size() == 1:
			family = detected_families[0]
		elif detected_families.size() > 1:
			var behavior_was_already_clarified := not raw_text.is_empty() and not clarification.strip_edges().is_empty()
			if behavior_was_already_clarified:
				return _error_result("BEHAVIOR_CLARIFICATION_UNRECOGNIZED", identity)
			var conflict := _clarification_result("behavior", BEHAVIOR_QUESTION, 0.24, "behavior_action_conflict")
			conflict["player_identity_text"] = identity
			conflict["source_identity"] = identity
			conflict["identity_was_clarified"] = identity_was_clarified
			conflict["behavior_candidates"] = detected_families
			return conflict
	if family.is_empty():
		var behavior_was_already_clarified := not raw_text.is_empty() and not clarification.strip_edges().is_empty()
		if behavior_was_already_clarified:
			return _error_result("BEHAVIOR_CLARIFICATION_UNRECOGNIZED", identity)
		var result := _clarification_result("behavior", BEHAVIOR_QUESTION, 0.38, "behavior_action_unclear")
		result["player_identity_text"] = identity
		result["source_identity"] = identity
		result["identity_was_clarified"] = identity_was_clarified
		return result

	var blueprint := BLUEPRINT_SCRIPT.new() as WeaponBlueprint
	blueprint.id = "open-identity-%s" % identity.sha256_text().left(16)
	blueprint.display_name = identity.left(48)
	blueprint.fantasy_summary = "%s；战斗行为仅编译为 %s，视觉身份保持玩家原文。" % [identity, family]
	blueprint.source_identity = identity
	blueprint.player_identity_text = identity
	blueprint.identity_confidence = 1.0
	blueprint.preserved_visual_features = ["player_identity_text_verbatim=%s" % identity]
	blueprint.visual_description = identity
	blueprint.weapon_form = "open_identity_object"
	blueprint.palette_hint = "preserve_source_identity"
	blueprint.confidence = 0.78 if explicit_behavior.is_empty() else 0.92
	_apply_behavior_profile(blueprint, family, identity)
	_apply_geometry_evidence(blueprint, sketch_png, geometry)
	blueprint.visual_prompt = VISUAL_PROMPT_SCRIPT.build(blueprint)
	blueprint.validate_and_repair()
	return {
		"ok": true,
		"needs_clarification": false,
		"confidence": blueprint.confidence,
		"blueprint": blueprint,
		"explanation": player_explanation(blueprint),
		"source": SOURCE_LABEL,
		"ai_interpretation_used": false,
		"identity_semantics_understood": false,
		"identity_passthrough": true,
		"identity_was_clarified": identity_was_clarified,
		"behavior_compiler": "deterministic_action_rules"
	}

func apply_delta(current: WeaponBlueprint, request: String) -> Dictionary:
	if current == null:
		return _error_result("CURRENT_BLUEPRINT_MISSING", "")
	var changed := WeaponBlueprint.from_dict(current.to_dict())
	var original_identity := changed.player_identity_text
	var requested_family := _detect_behavior_family(request.strip_edges())
	var delta := DELTA_SCRIPT.new() as BlueprintDelta
	delta.requested_change = request.strip_edges()
	if requested_family.is_empty():
		delta.accepted_change = "identity_preserving_tuning"
		delta.effect_delta = "unchanged"
		delta.drawback_delta = "unchanged"
		delta.visual_delta = "source_identity_unchanged"
		delta.tradeoff = changed.drawback
		delta.player_summary = "未识别到新的战斗动作；保留原行为和物件身份。"
	else:
		delta.accepted_change = "behavior_family_changed"
		delta.cadence_delta = requested_family
		delta.effect_delta = "compiled_from_player_action_words"
		delta.drawback_delta = "family_drawback_applied"
		delta.visual_delta = "source_identity_unchanged"
		delta.tradeoff = _drawback_for_family(requested_family)
		delta.player_summary = "只调整战斗行为；玩家物件身份保持不变。"
		_apply_behavior_profile(changed, requested_family, request)
	changed.source_identity = original_identity
	changed.player_identity_text = original_identity
	changed.visual_description = original_identity
	changed.visual_prompt = VISUAL_PROMPT_SCRIPT.build(changed)
	changed.validate_and_repair()
	return {
		"ok": delta.is_valid(),
		"delta": delta,
		"blueprint": changed,
		"explanation": player_explanation(changed),
		"source": SOURCE_LABEL,
		"ai_interpretation_used": false,
		"identity_semantics_understood": false,
		"identity_passthrough": true,
		"behavior_compiler": "deterministic_action_rules"
	}

func player_explanation(blueprint: WeaponBlueprint) -> String:
	var identity := blueprint.player_identity_text
	match blueprint.behavior_family:
		"returning_thrown":
			return "保留“%s”的原本外形；整个物件飞出、命中并返回，代价是返回前不能再次投出。" % identity
		"heavy_melee":
			return "保留“%s”的原本外形；整个物件作为近战打击区域，代价是起手和恢复较慢。" % identity
		_:
			return "保留“%s”的原本外形；Forge 只增加可读的力量出口以持续释放效果，代价是持续使用会过载。" % identity

func _apply_behavior_profile(blueprint: WeaponBlueprint, family: String, action_text: String) -> void:
	blueprint.behavior_family = family
	var effect := _effect_from_action_words(action_text)
	blueprint.effect_type = str(effect["effect_type"])
	blueprint.element = str(effect["element"])
	blueprint.signature_effect = str(effect["signature_effect"])
	match family:
		"returning_thrown":
			blueprint.cadence = "single_return"
			blueprint.delivery = "whole_object_return"
			blueprint.impact_mode = "body_collision"
			blueprint.drawback = "return_delay"
			blueprint.weight_class = "medium"
			blueprint.grip_profile = "throwable_center"
		"heavy_melee":
			blueprint.cadence = "slow_strike"
			blueprint.delivery = "whole_object_strike"
			blueprint.impact_mode = "body_contact"
			blueprint.drawback = "slow_startup"
			blueprint.weight_class = "heavy"
			blueprint.grip_profile = "two_hand_rear"
		_:
			blueprint.cadence = "continuous"
			blueprint.delivery = "continuous_emission"
			blueprint.impact_mode = "repeated_impact"
			blueprint.drawback = "overload"
			blueprint.weight_class = "medium"
			blueprint.grip_profile = "rear_grip"

func _effect_from_action_words(text: String) -> Dictionary:
	var normalized := text.to_lower()
	if _contains_any(normalized, ["螺丝", "螺钉", "screw", "bolt", "fastener"]):
		return {"effect_type": "forge_fastener", "element": "normal", "signature_effect": "impact"}
	if _contains_any(normalized, ["吸血", "生命汲取", "lifesteal", "life steal"]):
		return {"effect_type": "lifesteal", "element": "life", "signature_effect": "lifesteal"}
	if _contains_any(normalized, ["电流", "闪电", "雷电", "electric", "lightning"]):
		return {"effect_type": "electric_current", "element": "electric", "signature_effect": "chain"}
	if _contains_any(normalized, ["高温", "蒸汽", "火焰", "flame", "steam"]):
		return {"effect_type": "thermal_emission", "element": "fire", "signature_effect": "burn"}
	return {"effect_type": "player_described_effect", "element": "normal", "signature_effect": "impact"}

func _apply_geometry_evidence(blueprint: WeaponBlueprint, sketch_png: PackedByteArray, geometry: Dictionary) -> void:
	if sketch_png.is_empty() and geometry.is_empty():
		return
	blueprint.preserved_visual_features.append("rough_player_sketch_present")
	if geometry.has("aspect_ratio"):
		var aspect := clampf(float(geometry.get("aspect_ratio", blueprint.silhouette_aspect)), 0.5, 4.5)
		blueprint.silhouette_aspect = aspect
		blueprint.preserved_visual_features.append("sketch_aspect_ratio=%.3f" % aspect)
	if geometry.has("dominant_axis"):
		var axis := str(geometry.get("dominant_axis", "unknown"))
		blueprint.preserved_visual_features.append("sketch_dominant_axis=%s" % axis)

func _detect_behavior_family(text: String) -> String:
	var families := _matching_behavior_families(text)
	return families[0] if families.size() == 1 else ""

func _matching_behavior_families(text: String) -> Array[String]:
	var normalized := text.strip_edges().to_lower()
	var families: Array[String] = []
	if _contains_any(normalized, RETURNING_ACTIONS):
		families.append("returning_thrown")
	if _contains_any(normalized, HEAVY_ACTIONS):
		families.append("heavy_melee")
	if _contains_any(normalized, SUSTAINED_ACTIONS):
		families.append("sustained_ranged")
	return families

func _canonical_family(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	if normalized in WeaponBlueprint.BEHAVIOR_FAMILIES:
		return normalized
	return _detect_behavior_family(normalized)

func _parse_clarification(value: String) -> Dictionary:
	var stripped := value.strip_edges()
	var parsed := {"identity": "", "behavior": ""}
	const IDENTITY_PREFIX := "IDENTITY::"
	const BEHAVIOR_SEPARATOR := "::BEHAVIOR::"
	if not stripped.begins_with(IDENTITY_PREFIX):
		if stripped.begins_with("BEHAVIOR::"):
			parsed["behavior"] = stripped.trim_prefix("BEHAVIOR::")
		return parsed
	var separator_index := stripped.find(BEHAVIOR_SEPARATOR)
	if separator_index < 0:
		parsed["identity"] = stripped.trim_prefix(IDENTITY_PREFIX)
		return parsed
	parsed["identity"] = stripped.substr(IDENTITY_PREFIX.length(), separator_index - IDENTITY_PREFIX.length())
	parsed["behavior"] = stripped.substr(separator_index + BEHAVIOR_SEPARATOR.length())
	return parsed

func _clarification_result(kind: String, question: String, confidence_value: float, reason: String) -> Dictionary:
	return {
		"ok": true,
		"needs_clarification": true,
		"clarification_kind": kind,
		"question": question,
		"confidence": confidence_value,
		"reason": reason,
		"source": SOURCE_LABEL,
		"ai_interpretation_used": false,
		"identity_semantics_understood": false,
		"identity_passthrough": true,
		"behavior_compiler": "deterministic_action_rules"
	}

func _error_result(code: String, identity: String) -> Dictionary:
	return {
		"ok": false,
		"needs_clarification": false,
		"error": code,
		"player_identity_text": identity,
		"source": SOURCE_LABEL,
		"ai_interpretation_used": false,
		"identity_semantics_understood": false,
		"identity_passthrough": true,
		"behavior_compiler": "deterministic_action_rules"
	}

func _drawback_for_family(family: String) -> String:
	match family:
		"returning_thrown": return "return_delay"
		"heavy_melee": return "slow_startup"
		_: return "overload"

func _contains_any(text: String, needles: Array[String]) -> bool:
	for needle: String in needles:
		if text.contains(needle):
			return true
	return false
