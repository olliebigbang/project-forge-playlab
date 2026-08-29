class_name WeaponStrategyCompiler
extends RefCounted

const TARGET_INTERACTION := preload("res://scripts/combat_feel/weapon_target_interaction_resolver.gd")
const SCHEMA := "forge-weapon-strategy-profile-v1"


static func compile(
	blueprint: WeaponBlueprint,
	asset: WeaponVisualAsset,
	ranged_runtime: Dictionary = {}
) -> Dictionary:
	if blueprint == null or asset == null:
		return _failure("WEAPON_STRATEGY_INPUT_MISSING")
	var affordance := blueprint.affordance
	var firearm := bool(ranged_runtime.get("ok", false)) \
		and str(affordance.get("weapon_domain", "")) == "handheld_firearm"
	var reach := 0.45
	var area := 0.20
	var cadence := 0.45
	var impact := 0.50
	var penetration := 0.30
	var control := 0.30
	var defense := 0.0
	var mobility := 0.55
	var commitment := 0.45
	var interaction: Dictionary
	if firearm:
		reach = _unit(float(ranged_runtime.get("damage_falloff_start_pixels", 480.0)), 270.0, 720.0)
		var pellet_count := maxi(1, int(ranged_runtime.get("pellet_count", 1)))
		var spread := float(ranged_runtime.get("pellet_spread_degrees", 0.0))
		area = clampf((float(pellet_count - 1) / 7.0) * 0.72 + spread / 60.0, 0.05, 1.0)
		cadence = 1.0 - _unit(float(ranged_runtime.get("shot_interval_seconds", 0.17)), 0.08, 0.36)
		impact = _unit(float(ranged_runtime.get("projectile_damage", 10.0)), 5.0, 18.0)
		penetration = _unit(float(ranged_runtime.get("armor_damage_multiplier", 0.72)), 0.45, 1.0)
		mobility = _unit(float(ranged_runtime.get("movement_multiplier", 0.90)), 0.70, 1.0)
		commitment = clampf(
			(1.0 - mobility) * 0.45
			+ _unit(float(ranged_runtime.get("reload_seconds", 1.18)), 0.60, 2.0) * 0.35
			+ _unit(float(ranged_runtime.get("recoil_pixels", 7.0)), 2.0, 14.0) * 0.20,
			0.0,
			1.0
		)
		interaction = TARGET_INTERACTION.compile_ranged(affordance, ranged_runtime)
		control = clampf(
			float(interaction.get("stagger_seconds", 0.08)) / 0.55 * 0.48
			+ float(interaction.get("suppression_seconds", 0.0)) / 0.95 * 0.52,
			0.0,
			1.0
		)
	else:
		var body_length := str(affordance.get("body_length", "medium"))
		reach = float({"short": 0.28, "medium": 0.55, "long": 0.82}.get(body_length, 0.55))
		var state := str(affordance.get("state_topology", "fixed"))
		var output := str(affordance.get("functional_output", "contact_only"))
		var flex := str(affordance.get("flex_topology", "none"))
		var tether := str(affordance.get("tether_topology", "none"))
		var tether_mode := str(affordance.get("tether_mode", "none"))
		if state == "telescoping" or output in ["directed_stream", "pull_field"]:
			reach = minf(1.0, reach + 0.25)
		if tether != "none" or flex in ["flexible_line", "linked_segments"]:
			reach = minf(1.0, reach + 0.18)
		area = float({"point": 0.18, "edge": 0.42, "broad": 0.68, "whole_body": 0.58}.get(
			str(affordance.get("contact_surface", "whole_body")), 0.38
		))
		if state in ["radial_expand", "rotary"] or output == "radial_field":
			area = 1.0
		cadence = float({"rear": 0.66, "balanced": 0.52, "front": 0.32}.get(
			str(affordance.get("mass_distribution", "balanced")), 0.52
		))
		impact = float({"rear": 0.38, "balanced": 0.58, "front": 0.82}.get(
			str(affordance.get("mass_distribution", "balanced")), 0.58
		))
		if str(affordance.get("terminal_load", "none")) == "heavy":
			impact = minf(1.0, impact + 0.18)
		penetration = float({"point": 0.76, "edge": 0.60, "broad": 0.18, "whole_body": 0.28}.get(
			str(affordance.get("contact_surface", "whole_body")), 0.28
		))
		interaction = TARGET_INTERACTION.compile_melee(affordance, affordance)
		control = clampf(
			float(interaction.get("stagger_seconds", 0.08)) / 0.55 * 0.42
			+ float(interaction.get("entangle_seconds", 0.0)) / 1.10 * 0.40
			+ (0.18 if tether_mode == "hook" else 0.0),
			0.0,
			1.0
		)
		defense = clampf(
			(0.46 if bool(affordance.get("has_broad_face", false)) else 0.0)
			+ (0.34 if state in ["hinged", "radial_expand"] else 0.0)
			+ (0.24 if output == "radial_field" else 0.0),
			0.0,
			1.0
		)
		commitment = clampf((1.0 - cadence) * 0.72 + impact * 0.28, 0.0, 1.0)
		mobility = clampf(0.88 - commitment * 0.52, 0.24, 0.92)

	var profile := {
		"ok": true,
		"schema": SCHEMA,
		"firearm": firearm,
		"reach": reach,
		"area": area,
		"cadence": cadence,
		"impact": impact,
		"penetration": penetration,
		"control": control,
		"defense": defense,
		"mobility": mobility,
		"commitment": commitment,
		"melee_lunge_pixels": 0.0 if firearm else lerpf(10.0, 34.0, mobility) * (1.0 - defense * 0.35),
		"active_guard_damage_multiplier": lerpf(1.0, 0.46, defense),
		"target_interaction_profile": interaction.duplicate(true),
		"identity_inputs_used": false,
		"player_confirmation_required": false,
	}
	profile["battle_tips_zh"] = _battle_tips(profile)
	return profile


static func battle_tip(profile: Dictionary, encounter_number: int) -> String:
	var tips := profile.get("battle_tips_zh", []) as Array
	if tips.is_empty():
		return "观察预警，利用武器的距离和出手节奏。"
	return str(tips[clampi(encounter_number - 1, 0, tips.size() - 1)])


static func _battle_tips(profile: Dictionary) -> Array[String]:
	var reach := float(profile.get("reach", 0.0))
	var area := float(profile.get("area", 0.0))
	var cadence := float(profile.get("cadence", 0.0))
	var penetration := float(profile.get("penetration", 0.0))
	var control := float(profile.get("control", 0.0))
	var defense := float(profile.get("defense", 0.0))
	var first := "等预警落空后贴近反击。"
	if reach >= 0.68:
		first = "留在预警范围外，用长距离安全反击。"
	elif control >= 0.58:
		first = "用控制效果打断蓄势，再跟进伤害。"
	var second := "持续横移，引出飞扑后打它的收招。"
	if area >= 0.62 or cadence >= 0.72:
		second = "用覆盖或连续压制封住移动路线，别和它赛跑。"
	elif control >= 0.52:
		second = "先缠住、钩回或压停高速目标，再安全输出。"
	var third := "避开正面硬保护，等冲撞结束后集中输出。"
	if penetration >= 0.68:
		third = "穿透能力足够：对准正面持续破甲，再扩大伤害。"
	elif defense >= 0.62:
		third = "攻击展开时能减伤：顶住一轮，再抓恢复窗口。"
	elif control >= 0.62:
		third = "在蓄势阶段用强控制尝试打断，失败就立即闪避。"
	return [first, second, third]


static func _unit(value: float, low: float, high: float) -> float:
	return clampf(inverse_lerp(low, high, value), 0.0, 1.0)


static func _failure(error: String) -> Dictionary:
	return {
		"ok": false,
		"schema": SCHEMA,
		"error": error,
		"identity_inputs_used": false,
		"player_confirmation_required": false,
	}
