class_name WeaponBlueprint
extends RefCounted

const BEHAVIOR_FAMILIES: PackedStringArray = ["sustained_ranged", "returning_thrown", "heavy_melee"]
const GRIP_PROFILES: PackedStringArray = ["rear_grip", "bottom_handle", "center_shaft", "two_hand_rear", "throwable_center"]
const ELEMENTS: PackedStringArray = ["normal", "fire", "electric", "life"]
const WEIGHT_CLASSES: PackedStringArray = ["light", "medium", "heavy"]

var id: String = ""
var display_name: String = ""
var fantasy_summary: String = ""
var behavior_family: String = "sustained_ranged"
var weapon_form: String = "launcher"
var cadence: String = "continuous"
var delivery: String = "projectile"
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
	if display_name.is_empty():
		display_name = "无名锻造物"
		reasons.append("display_name_created")
	if fantasy_summary.is_empty():
		fantasy_summary = "一件仍待验证的武器幻想。"
		reasons.append("fantasy_summary_created")
	confidence = clampf(confidence, 0.0, 1.0)
	silhouette_aspect = clampf(silhouette_aspect, 0.5, 4.5)
	return reasons

func to_dict() -> Dictionary:
	return {
		"id": id, "display_name": display_name, "fantasy_summary": fantasy_summary,
		"behavior_family": behavior_family, "weapon_form": weapon_form, "cadence": cadence,
		"delivery": delivery, "element": element, "signature_effect": signature_effect,
		"drawback": drawback, "weight_class": weight_class, "grip_profile": grip_profile,
		"visual_prompt": visual_prompt, "palette_hint": palette_hint,
		"silhouette_aspect": silhouette_aspect, "silhouette_curvature": silhouette_curvature,
		"silhouette_mass_distribution": silhouette_mass_distribution,
		"silhouette_handle_region": silhouette_handle_region, "confidence": confidence,
		"clarification_question": clarification_question, "modifiers": modifiers.duplicate(true)
	}

static func from_dict(data: Dictionary) -> WeaponBlueprint:
	var blueprint := WeaponBlueprint.new()
	for key: String in blueprint.to_dict().keys():
		if data.has(key):
			blueprint.set(key, data[key])
	blueprint.validate_and_repair()
	return blueprint

static func fixed_blueprint(kind: String) -> WeaponBlueprint:
	match kind:
		"umbrella":
			return from_dict({
				"id": "thunder-return-umbrella", "display_name": "雷鸣回旋伞",
				"fantasy_summary": "一柄飞出后沿电弧返回的机械伞刃。",
				"behavior_family": "returning_thrown", "weapon_form": "mechanical_umbrella",
				"cadence": "single_return", "delivery": "thrown_arc", "element": "electric",
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
				"behavior_family": "heavy_melee", "weapon_form": "chainsaw_greatsword",
				"cadence": "slow_strike", "delivery": "melee_arc", "element": "life",
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
				"behavior_family": "sustained_ranged", "weapon_form": "heavy_gatling",
				"cadence": "continuous", "delivery": "projectile", "element": "fire",
				"signature_effect": "burn", "drawback": "overheat", "weight_class": "heavy",
				"grip_profile": "two_hand_rear", "visual_prompt": "heavy multi barrel gatling with blue furnace fire",
				"palette_hint": "gunmetal_blue", "silhouette_aspect": 2.8,
				"silhouette_curvature": "angular", "silhouette_mass_distribution": "front_heavy",
				"silhouette_handle_region": "rear"
			})

