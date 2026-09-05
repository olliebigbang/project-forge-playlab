class_name SunnyMetaProgression
extends RefCounted
## Capped, horizontal Roguelite progression for the Sunny expedition.
## It unlocks choice breadth and rerolls, never permanent combat statistics.

const SCHEMA := "sunny-meta-progression-v1"
const MAX_VALUE := 9999
const FAMILY_LABELS := {
	"ranged_cycle": "投射循环",
	"flexible_control": "柔性控制",
	"active_output": "功能输出",
	"point_lever": "尖端杠杆",
	"edge_contact": "刃边接触",
	"broad_impact": "宽面冲击",
}
const MILESTONES := [
	{"id": "reroll_1", "insight": 1, "label": "路标重铸 I"},
	{"id": "advanced_modules", "insight": 4, "label": "进阶模块池"},
	{"id": "reroll_2", "insight": 7, "label": "路标重铸 II"},
]


static func empty() -> Dictionary:
	return {
		"schema": SCHEMA,
		"insight": 0,
		"completed_runs": 0,
		"mastered_families": [],
	}


static func valid(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var data := value as Dictionary
	if str(data.get("schema", "")) != SCHEMA:
		return false
	for key: String in ["insight", "completed_runs"]:
		var number: Variant = data.get(key, null)
		if typeof(number) not in [TYPE_INT, TYPE_FLOAT]:
			return false
		if not is_finite(float(number)) or float(number) != floorf(float(number)):
			return false
		if int(number) < 0 or int(number) > MAX_VALUE:
			return false
	var families: Variant = data.get("mastered_families", null)
	if not families is Array or families.size() > FAMILY_LABELS.size():
		return false
	var seen := {}
	for family: Variant in families:
		if not family is String or not FAMILY_LABELS.has(family) or seen.has(family):
			return false
		seen[family] = true
	return true


static func normalize(value: Variant) -> Dictionary:
	if not valid(value):
		return empty()
	var source := value as Dictionary
	return {
		"schema": SCHEMA,
		"insight": int(source.insight),
		"completed_runs": int(source.completed_runs),
		"mastered_families": (source.mastered_families as Array).duplicate(),
	}


static func family_for(blueprint: WeaponBlueprint) -> String:
	if blueprint == null:
		return ""
	var axes: Dictionary = blueprint.affordance
	if str(axes.get("weapon_domain", "")) == "handheld_firearm":
		return "ranged_cycle"
	if str(axes.get("flex_topology", "none")) != "none" or str(axes.get("tether_topology", "none")) != "none":
		return "flexible_control"
	if str(axes.get("state_topology", "fixed")) != "fixed" or str(axes.get("functional_output", "contact_only")) != "contact_only":
		return "active_output"
	match str(axes.get("contact_surface", "whole_body")):
		"point": return "point_lever"
		"edge": return "edge_contact"
		_: return "broad_impact"


static func family_label(family: String) -> String:
	return str(FAMILY_LABELS.get(family, "未知结构"))


static func runtime_context(value: Variant) -> Dictionary:
	var data := normalize(value)
	var insight := int(data.insight)
	return {
		"rerolls_per_run": 2 if insight >= 7 else (1 if insight >= 1 else 0),
		"advanced_modules_unlocked": insight >= 4,
		"insight": insight,
	}


static func unlocked_ids(value: Variant) -> Array[String]:
	var insight := int(normalize(value).insight)
	var result: Array[String] = []
	for milestone: Dictionary in MILESTONES:
		if insight >= int(milestone.insight):
			result.append(str(milestone.id))
	return result


static func record_completion(value: Variant, blueprint: WeaponBlueprint) -> Dictionary:
	var before := normalize(value)
	var family := family_for(blueprint)
	var families: Array = (before.mastered_families as Array).duplicate()
	var new_family := not family.is_empty() and family not in families
	var earned := 1 + (1 if new_family else 0)
	if new_family:
		families.append(family)
	var after := {
		"schema": SCHEMA,
		"insight": mini(MAX_VALUE, int(before.insight) + earned),
		"completed_runs": mini(MAX_VALUE, int(before.completed_runs) + 1),
		"mastered_families": families,
	}
	var previous_unlocks := unlocked_ids(before)
	var new_unlocks: Array[String] = []
	for unlock_id: String in unlocked_ids(after):
		if unlock_id not in previous_unlocks:
			new_unlocks.append(unlock_id)
	return {
		"progression": after,
		"reward": {
			"insight_earned": earned,
			"previous_insight": int(before.insight),
			"total_insight": int(after.insight),
			"family": family,
			"family_label": family_label(family),
			"new_family": new_family,
			"new_unlocks": new_unlocks,
		},
	}


static func unlock_label(unlock_id: String) -> String:
	for milestone: Dictionary in MILESTONES:
		if str(milestone.id) == unlock_id:
			return str(milestone.label)
	return "新工坊能力"


static func short_summary(value: Variant) -> String:
	var data := normalize(value)
	return "工坊见闻 %d · 结构 %d/6" % [int(data.insight), (data.mastered_families as Array).size()]


static func next_milestone_text(value: Variant) -> String:
	var insight := int(normalize(value).insight)
	for milestone: Dictionary in MILESTONES:
		if insight < int(milestone.insight):
			return "再获 %d 见闻解锁「%s」" % [int(milestone.insight) - insight, str(milestone.label)]
	return "局外工坊能力已全部解锁"
