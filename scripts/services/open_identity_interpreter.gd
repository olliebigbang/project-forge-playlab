class_name OpenIdentityInterpreter
extends WeaponInterpreter

const BLUEPRINT_SCRIPT := preload("res://scripts/data/weapon_blueprint.gd")
const DELTA_SCRIPT := preload("res://scripts/data/blueprint_delta.gd")
const VISUAL_PROMPT_SCRIPT := preload("res://scripts/services/open_identity_visual_prompt.gd")
const FIREARM_IDENTITY_CATALOG := preload("res://scripts/combat_feel/firearm_identity_catalog.gd")
const FIREARM_IDENTITY_AI_RESOLVER := preload("res://scripts/combat_feel/firearm_identity_ai_resolver.gd")
const RANGED_AXIS_RESOLVER := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")
const MECHANISM_AXIS_RESOLVER := preload("res://scripts/combat_feel/mechanism_axis_resolver.gd")

const IDENTITY_QUESTION := "你画的是什么？"
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
		if identity.is_empty() and not clarification.strip_edges().is_empty():
			identity = clarification.strip_edges()
		identity_was_clarified = not identity.is_empty()
	if identity.is_empty():
		return _clarification_result("identity", IDENTITY_QUESTION, 0.0, "player_identity_missing")

	var firearm_identity: Dictionary = FIREARM_IDENTITY_CATALOG.resolve_identity(identity)
	if not bool(firearm_identity.get("ok", false)):
		firearm_identity = FIREARM_IDENTITY_AI_RESOLVER.resolve_identity(identity)
	var has_ai_firearm_identity := bool(firearm_identity.get("ok", false))
	var family := ""
	var detected_families := _matching_behavior_families(identity)
	if detected_families.size() == 1:
		family = detected_families[0]
	elif detected_families.size() > 1:
		var conflict := _error_result("AI_BEHAVIOR_REANALYSIS_REQUIRED", identity)
		conflict["reason"] = "behavior_action_conflict"
		conflict["player_identity_text"] = identity
		conflict["source_identity"] = identity
		conflict["identity_was_clarified"] = identity_was_clarified
		conflict["behavior_candidates"] = detected_families
		conflict["player_confirmation_required"] = false
		return conflict
	elif has_ai_firearm_identity:
		family = "sustained_ranged"
	if family.is_empty():
		var result := _error_result("AI_BEHAVIOR_REANALYSIS_REQUIRED", identity)
		result["reason"] = "behavior_action_unclear"
		result["player_identity_text"] = identity
		result["source_identity"] = identity
		result["identity_was_clarified"] = identity_was_clarified
		result["player_confirmation_required"] = false
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
	blueprint.confidence = 0.78
	_apply_behavior_profile(blueprint, family, identity)
	if has_ai_firearm_identity and family == "sustained_ranged":
		_apply_ai_firearm_identity(blueprint, firearm_identity)
	_apply_geometry_evidence(blueprint, sketch_png, geometry)
	blueprint.visual_prompt = VISUAL_PROMPT_SCRIPT.build(blueprint)
	blueprint.validate_and_repair()
	var ai_firearm_used := has_ai_firearm_identity and family == "sustained_ranged"
	return {
		"ok": true,
		"needs_clarification": false,
		"confidence": blueprint.confidence,
		"blueprint": blueprint,
		"explanation": player_explanation(blueprint),
		"source": str(firearm_identity.get("catalog_source", SOURCE_LABEL)) if ai_firearm_used else SOURCE_LABEL,
		"ai_interpretation_used": ai_firearm_used,
		"identity_semantics_understood": ai_firearm_used,
		"identity_passthrough": not ai_firearm_used,
		"identity_was_clarified": identity_was_clarified,
		"behavior_compiler": "ai_firearm_identity_profile_v1" if ai_firearm_used else "deterministic_action_rules",
		"affordance": blueprint.affordance.duplicate(true),
		"affordance_source": blueprint.affordance_source,
	}


func interpret_with_ai_firearm_profile(
	player_text: String,
	sketch_png: PackedByteArray,
	geometry: Dictionary,
	profile: Dictionary
) -> Dictionary:
	var identity := player_text.strip_edges()
	if identity.is_empty():
		return _error_result("AI_FIREARM_IDENTITY_EMPTY", identity)
	if profile.is_empty() or not profile.get("declaration", {}) is Dictionary:
		return _error_result("AI_FIREARM_PROFILE_MISSING", identity)
	var declaration := profile.get("declaration", {}) as Dictionary
	var source := str(declaration.get("source", profile.get("catalog_source", "")))
	var validation := RANGED_AXIS_RESOLVER.validate_ai_declaration(declaration, source)
	if not bool(validation.get("ok", false)):
		return validation
	var blueprint := BLUEPRINT_SCRIPT.new() as WeaponBlueprint
	blueprint.id = "open-identity-%s" % identity.sha256_text().left(16)
	blueprint.display_name = identity.left(48)
	blueprint.fantasy_summary = "%s；枪械身份与战斗行为由 AI 结构卡编译，视觉身份保持玩家原文。" % identity
	blueprint.source_identity = identity
	blueprint.player_identity_text = identity
	blueprint.identity_confidence = 1.0
	blueprint.preserved_visual_features = ["player_identity_text_verbatim=%s" % identity]
	blueprint.visual_description = identity
	blueprint.weapon_form = "open_identity_object"
	blueprint.palette_hint = "preserve_source_identity"
	blueprint.confidence = float(validation.get("confidence", 0.0))
	_apply_behavior_profile(blueprint, "sustained_ranged", identity)
	_apply_ai_firearm_identity(blueprint, profile)
	_apply_geometry_evidence(blueprint, sketch_png, geometry)
	blueprint.visual_prompt = VISUAL_PROMPT_SCRIPT.build(blueprint)
	blueprint.validate_and_repair()
	return {
		"ok": true,
		"needs_clarification": false,
		"confidence": blueprint.confidence,
		"blueprint": blueprint,
		"explanation": player_explanation(blueprint),
		"source": source,
		"ai_interpretation_used": true,
		"identity_semantics_understood": true,
		"identity_passthrough": false,
		"identity_was_clarified": false,
		"behavior_compiler": "ai_firearm_identity_dynamic_v1",
		"affordance": blueprint.affordance.duplicate(true),
		"affordance_source": blueprint.affordance_source,
		"player_confirmation_required": false,
	}


func interpret_with_ai_object_profile(
	player_text: String,
	sketch_png: PackedByteArray,
	geometry: Dictionary,
	profile: Dictionary
) -> Dictionary:
	var identity := player_text.strip_edges()
	if identity.is_empty():
		return _error_result("AI_GENERAL_OBJECT_IDENTITY_EMPTY", identity)
	if profile.is_empty() or not profile.get("declaration", {}) is Dictionary:
		return _error_result("AI_GENERAL_OBJECT_PROFILE_MISSING", identity)
	if str(profile.get("behavior_family", "")) != "heavy_melee":
		return _error_result("AI_GENERAL_OBJECT_BEHAVIOR_FAMILY_INVALID", identity)
	var declaration := (profile.get("declaration", {}) as Dictionary).duplicate(true)
	var source := str(declaration.get("source", profile.get("catalog_source", "")))
	var validation := MECHANISM_AXIS_RESOLVER.validate_ai_declaration(declaration, source)
	if not bool(validation.get("ok", false)):
		return validation
	var blueprint := BLUEPRINT_SCRIPT.new() as WeaponBlueprint
	blueprint.id = "open-object-%s" % identity.sha256_text().left(16)
	blueprint.display_name = identity.left(48)
	blueprint.fantasy_summary = "%s；物件结构与攻击方式由 AI 机制轴编译，玩家不选择打法。" % identity
	blueprint.source_identity = identity
	blueprint.player_identity_text = identity
	blueprint.identity_confidence = float(declaration.get("confidence", 0.0))
	blueprint.preserved_visual_features = ["player_identity_text_verbatim=%s" % identity]
	for raw_part: Variant in profile.get("required_identity_parts_zh", []):
		blueprint.preserved_visual_features.append("required_visible_part=%s" % str(raw_part))
	blueprint.visual_description = "%s; %s" % [
		identity,
		str(profile.get("visual_description_en", identity)),
	]
	blueprint.weapon_form = "general_object_%s" % str(profile.get("scale_treatment", "handheld"))
	blueprint.palette_hint = "preserve_source_identity"
	blueprint.confidence = float(declaration.get("confidence", 0.0))
	_apply_behavior_profile(blueprint, "heavy_melee", identity)
	blueprint.grip_profile = {
		"one_hand_handle": "rear_grip",
		"two_hand_handle": "two_hand_rear",
		"body_grip": "throwable_center",
		"clamp_grip": "throwable_center",
	}.get(str(declaration.get("grip_topology", "body_grip")), "throwable_center")
	blueprint.affordance = declaration
	blueprint.affordance_source = source
	blueprint.silhouette_aspect = {"short": 1.25, "medium": 2.0, "long": 3.4}.get(
		str(declaration.get("body_length", "medium")), 2.0
	)
	blueprint.silhouette_curvature = "curved" if str(declaration.get("rigidity", "rigid")) != "rigid" else "structural"
	blueprint.silhouette_mass_distribution = str(declaration.get("mass_distribution", "balanced"))
	blueprint.silhouette_handle_region = "center" if str(declaration.get("grip_topology", "")) in ["body_grip", "clamp_grip"] else "rear"
	blueprint.modifiers["general_object_profile_id"] = str(profile.get("id", ""))
	blueprint.modifiers["general_object_canonical_name"] = str(profile.get("canonical_name", identity))
	blueprint.modifiers["general_object_scale_treatment"] = str(profile.get("scale_treatment", "handheld"))
	blueprint.modifiers["general_object_visual_exclusions"] = (profile.get("confusable_exclusions_en", []) as Array).duplicate()
	_apply_geometry_evidence(blueprint, sketch_png, geometry)
	blueprint.visual_prompt = VISUAL_PROMPT_SCRIPT.build(blueprint)
	blueprint.validate_and_repair()
	return {
		"ok": true,
		"needs_clarification": false,
		"confidence": blueprint.confidence,
		"blueprint": blueprint,
		"explanation": "AI 已从“%s”的真实结构生成握法、软硬、重量分布、接触面和软线机制；动作由机制轴自动编译。" % identity,
		"source": source,
		"ai_interpretation_used": true,
		"identity_semantics_understood": true,
		"identity_passthrough": false,
		"identity_was_clarified": false,
		"behavior_compiler": "ai_general_object_affordance_v1",
		"affordance": blueprint.affordance.duplicate(true),
		"affordance_source": blueprint.affordance_source,
		"player_confirmation_required": false,
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
	if blueprint.behavior_family == "sustained_ranged" and str(blueprint.affordance.get("weapon_domain", "")) == "handheld_firearm":
		var fire_control := str(blueprint.affordance.get("fire_control", "semi_auto"))
		var firing_text := "每按一次发射一发"
		if fire_control == "select_fire_auto":
			firing_text = "按住连续射击"
		elif fire_control == "three_round_burst":
			firing_text = "每按一次自动完成三连发"
		elif fire_control == "manual_cycle":
			firing_text = "每按一次发射一发，随后自动完成拉栓，上膛结束前无法再次开火"
		return "AI 已把“%s”识别为具体枪械；外形按枪托、握把、弹匣和枪口位置绘制，%s，后坐、散布、弹匣和换弹全部由远程机制轴决定。" % [identity, firing_text]
	match blueprint.behavior_family:
		"returning_thrown":
			return "保留“%s”的原本外形；整个物件飞出、命中并返回，代价是返回前不能再次投出。" % identity
		"heavy_melee":
			return "保留“%s”的原本外形；整个物件作为近战打击区域，代价是起手和恢复较慢。" % identity
		_:
			return "保留“%s”的原本外形；Forge 只增加可读的力量出口以持续释放效果，代价是持续使用会过载。" % identity


func _apply_ai_firearm_identity(blueprint: WeaponBlueprint, profile: Dictionary) -> void:
	var declaration := (profile.get("declaration", {}) as Dictionary).duplicate(true)
	var source := str(declaration.get("source", profile.get("catalog_source", "")))
	var validation := RANGED_AXIS_RESOLVER.validate_ai_declaration(declaration, source)
	if not bool(validation.get("ok", false)):
		return
	blueprint.display_name = str(profile.get("canonical_name_zh", blueprint.player_identity_text)).left(48)
	blueprint.visual_description = "%s; %s" % [
		blueprint.player_identity_text,
		str(profile.get("visual_description_en", blueprint.player_identity_text)),
	]
	blueprint.preserved_visual_features = [
		"player_identity_text_verbatim=%s" % blueprint.player_identity_text,
		"ai_firearm_identity_profile=%s" % str(profile.get("id", "")),
	]
	for raw_part: Variant in profile.get("required_identity_parts_zh", []):
		blueprint.preserved_visual_features.append("required_visible_part=%s" % str(raw_part))
	blueprint.weapon_form = "firearm_%s" % str(declaration.get("layout", "unknown"))
	blueprint.delivery = "firearm_projectile"
	blueprint.impact_mode = "projectile_impact"
	blueprint.effect_type = "ballistic_projectile"
	blueprint.element = "normal"
	blueprint.signature_effect = "impact"
	blueprint.drawback = "magazine_reload"
	blueprint.cadence = str(declaration.get("fire_control", "semi_auto"))
	blueprint.grip_profile = "two_hand_rear" if str(declaration.get("support_mode", "")) == "two_hand_shouldered" else "rear_grip"
	blueprint.weight_class = {"agile": "light", "balanced": "medium", "heavy": "heavy"}.get(str(declaration.get("handling", "balanced")), "medium")
	blueprint.palette_hint = str(declaration.get("finish_palette", "gunmetal_black"))
	blueprint.silhouette_aspect = 2.0 if str(declaration.get("layout", "")) == "pistol" else 4.1
	blueprint.silhouette_curvature = "compact" if str(declaration.get("layout", "")) in ["bullpup", "pistol"] else "linear"
	blueprint.silhouette_mass_distribution = "rear" if str(declaration.get("feed_position", "")) in ["behind_grip", "in_grip"] else "balanced"
	blueprint.silhouette_handle_region = "center" if str(declaration.get("layout", "")) == "bullpup" else "rear"
	blueprint.affordance = declaration
	blueprint.affordance_source = source
	blueprint.confidence = float(validation.get("confidence", 0.0))
	blueprint.modifiers["firearm_identity_id"] = str(profile.get("id", ""))
	blueprint.modifiers["firearm_identity_match_alias"] = str(profile.get("matched_alias", ""))
	if profile.get("visual_identity_card", {}) is Dictionary:
		blueprint.modifiers["firearm_visual_identity_card"] = (
			profile.get("visual_identity_card", {}) as Dictionary
		).duplicate(true)
	var visual_reference_id := str(profile.get("visual_reference_id", "")).strip_edges()
	if not visual_reference_id.is_empty():
		blueprint.modifiers["firearm_visual_reference_id"] = visual_reference_id.left(96)

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

func _parse_clarification(value: String) -> Dictionary:
	var stripped := value.strip_edges()
	var parsed := {"identity": ""}
	const IDENTITY_PREFIX := "IDENTITY::"
	if stripped.begins_with(IDENTITY_PREFIX):
		parsed["identity"] = stripped.trim_prefix(IDENTITY_PREFIX)
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
