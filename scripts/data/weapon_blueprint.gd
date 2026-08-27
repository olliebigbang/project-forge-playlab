class_name WeaponBlueprint
extends RefCounted

const BEHAVIOR_FAMILIES: PackedStringArray = ["sustained_ranged", "returning_thrown", "heavy_melee"]
const GRIP_PROFILES: PackedStringArray = ["rear_grip", "bottom_handle", "center_shaft", "two_hand_rear", "throwable_center"]
const ELEMENTS: PackedStringArray = ["normal", "fire", "electric", "life"]
const WEIGHT_CLASSES: PackedStringArray = ["light", "medium", "heavy"]

var id: String = ""
var display_name: String = ""
var fantasy_summary: String = ""
var source_identity: String = ""
var player_identity_text: String = ""
var identity_confidence: float = 0.0
var preserved_visual_features: Array[String] = []
var visual_description: String = ""
var behavior_family: String = "sustained_ranged"
var weapon_form: String = "launcher"
var cadence: String = "continuous"
var delivery: String = "projectile"
var impact_mode: String = "repeated_impact"
var effect_type: String = "described_effect"
var element: String = "normal"
var signature_effect: String = "impact"
var drawback: String = "recovery"
var weight_class: String = "medium"
var grip_profile: String = "rear_grip"
var visual_prompt: String = ""
var palette_hint: String = "steel"
var silhouette_aspect: float = 2.2
var silhouette_curvature: String = "angular"
var silhouette_mass_distribution: String = "balanced"
var silhouette_handle_region: String = "rear"
var affordance: Dictionary = {}
var affordance_source: String = ""
var visual_rig: Dictionary = {}
var visual_rig_source: String = ""
var visual_structure_brief: Dictionary = {}
var visual_structure_brief_source: String = ""
var confidence: float = 1.0
var clarification_question: String = ""
var modifiers: Dictionary = {}

func validate_and_repair() -> Array[String]:
	var reasons: Array[String] = []
	if not behavior_family in BEHAVIOR_FAMILIES:
		reasons.append("behavior_family_repaired")
		behavior_family = "sustained_ranged"
	if not grip_profile in GRIP_PROFILES:
		reasons.append("grip_profile_repaired")
		grip_profile = "rear_grip"
	if not element in ELEMENTS:
		reasons.append("element_repaired")
		element = "normal"
	if not weight_class in WEIGHT_CLASSES:
		reasons.append("weight_class_repaired")
		weight_class = "medium"
	if id.is_empty():
		id = "weapon-%s" % str(Time.get_ticks_msec())
		reasons.append("id_created")
	if source_identity.is_empty() and not player_identity_text.is_empty():
		source_identity = player_identity_text
		reasons.append("source_identity_repaired_from_player_text")
	if player_identity_text.is_empty() and not source_identity.is_empty():
		player_identity_text = source_identity
		reasons.append("player_identity_text_repaired_from_source")
	if visual_description.is_empty() and not player_identity_text.is_empty():
		visual_description = player_identity_text
		reasons.append("visual_description_repaired_from_identity")
	if display_name.is_empty():
		display_name = player_identity_text.left(32) if not player_identity_text.is_empty() else "无名锻造物"
		reasons.append("display_name_created")
	if fantasy_summary.is_empty():
		fantasy_summary = "一件仍待验证的武器幻想。"
		reasons.append("fantasy_summary_created")
	confidence = clampf(confidence, 0.0, 1.0)
	identity_confidence = clampf(identity_confidence, 0.0, 1.0)
	silhouette_aspect = clampf(silhouette_aspect, 0.5, 4.5)
	return reasons

func to_dict() -> Dictionary:
	return {
		"id": id, "display_name": display_name, "fantasy_summary": fantasy_summary,
		"source_identity": source_identity, "player_identity_text": player_identity_text,
		"identity_confidence": identity_confidence,
		"preserved_visual_features": preserved_visual_features.duplicate(),
		"visual_description": visual_description,
		"behavior_family": behavior_family, "weapon_form": weapon_form, "cadence": cadence,
		"delivery": delivery, "impact_mode": impact_mode, "effect_type": effect_type,
		"element": element, "signature_effect": signature_effect,
		"drawback": drawback, "weight_class": weight_class, "grip_profile": grip_profile,
		"visual_prompt": visual_prompt, "palette_hint": palette_hint,
		"silhouette_aspect": silhouette_aspect, "silhouette_curvature": silhouette_curvature,
		"silhouette_mass_distribution": silhouette_mass_distribution,
		"silhouette_handle_region": silhouette_handle_region,
		"affordance": affordance.duplicate(true), "affordance_source": affordance_source,
		"visual_rig": visual_rig.duplicate(true), "visual_rig_source": visual_rig_source,
		"visual_structure_brief": visual_structure_brief.duplicate(true),
		"visual_structure_brief_source": visual_structure_brief_source,
		"confidence": confidence,
		"clarification_question": clarification_question, "modifiers": modifiers.duplicate(true)
	}

static func from_dict(data: Dictionary) -> WeaponBlueprint:
	var blueprint := WeaponBlueprint.new()
	for key: String in blueprint.to_dict().keys():
		if data.has(key):
			if key == "preserved_visual_features":
				blueprint.preserved_visual_features.clear()
				for feature: Variant in data[key]:
					blueprint.preserved_visual_features.append(str(feature))
			elif key == "affordance":
				blueprint.affordance = (data[key] as Dictionary).duplicate(true) if data[key] is Dictionary else {}
			elif key == "visual_rig":
				blueprint.visual_rig = (data[key] as Dictionary).duplicate(true) if data[key] is Dictionary else {}
			elif key == "visual_structure_brief":
				blueprint.visual_structure_brief = (data[key] as Dictionary).duplicate(true) if data[key] is Dictionary else {}
			else:
				blueprint.set(key, data[key])
	blueprint.validate_and_repair()
	return blueprint

static func fixed_blueprint(kind: String) -> WeaponBlueprint:
	match kind:
		"umbrella":
			return from_dict({
				"id": "thunder-return-umbrella", "display_name": "雷鸣回旋伞",
				"fantasy_summary": "一柄飞出后沿电弧返回的机械伞刃。",
				"source_identity": "机械闪电伞", "player_identity_text": "机械闪电伞",
				"identity_confidence": 1.0, "preserved_visual_features": ["伞面", "中轴", "握柄"],
				"visual_description": "mechanical lightning umbrella",
				"behavior_family": "returning_thrown", "weapon_form": "mechanical_umbrella",
				"cadence": "single_return", "delivery": "whole_object_return", "impact_mode": "body_collision",
				"effect_type": "electric_arc", "element": "electric",
				"signature_effect": "chain", "drawback": "return_delay", "weight_class": "medium",
				"grip_profile": "center_shaft", "visual_prompt": "mechanical lightning umbrella side view",
				"palette_hint": "storm_cyan", "silhouette_aspect": 1.45,
				"silhouette_curvature": "arched", "silhouette_mass_distribution": "front_heavy",
				"silhouette_handle_region": "center"
			})
		"greatsword":
			return from_dict({
				"id": "bloodtooth-chainsaw-greatsword", "display_name": "血齿链锯大剑",
				"fantasy_summary": "一柄缓慢启动、命中会回收生命的重型锯齿大剑。",
				"source_identity": "链锯大剑", "player_identity_text": "链锯大剑",
				"identity_confidence": 1.0, "preserved_visual_features": ["锯齿刃", "双手握柄"],
				"visual_description": "blood tooth chainsaw greatsword",
				"behavior_family": "heavy_melee", "weapon_form": "chainsaw_greatsword",
				"cadence": "slow_strike", "delivery": "whole_object_strike", "impact_mode": "body_contact",
				"effect_type": "lifesteal", "element": "life",
				"signature_effect": "lifesteal", "drawback": "slow_startup", "weight_class": "heavy",
				"grip_profile": "two_hand_rear", "visual_prompt": "blood tooth chainsaw greatsword side view",
				"palette_hint": "bone_crimson", "silhouette_aspect": 3.2,
				"silhouette_curvature": "serrated", "silhouette_mass_distribution": "front_heavy",
				"silhouette_handle_region": "rear"
			})
		_:
			return from_dict({
				"id": "blue-core-gatling", "display_name": "幽蓝炉心加特林",
				"fantasy_summary": "一把先旋转枪管、再持续喷射蓝焰弹丸的重型武器。",
				"source_identity": "重型多管加特林", "player_identity_text": "重型多管加特林",
				"identity_confidence": 1.0, "preserved_visual_features": ["多管结构", "后部握柄"],
				"visual_description": "heavy multi barrel gatling with blue furnace fire",
				"behavior_family": "sustained_ranged", "weapon_form": "heavy_gatling",
				"cadence": "continuous", "delivery": "continuous_emission", "impact_mode": "repeated_impact",
				"effect_type": "blue_fire_projectiles", "element": "fire",
				"signature_effect": "burn", "drawback": "overheat", "weight_class": "heavy",
				"grip_profile": "two_hand_rear", "visual_prompt": "heavy multi barrel gatling with blue furnace fire",
				"palette_hint": "gunmetal_blue", "silhouette_aspect": 2.8,
				"silhouette_curvature": "angular", "silhouette_mass_distribution": "front_heavy",
				"silhouette_handle_region": "rear"
			})
