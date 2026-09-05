class_name SunnyMechanismUpgradeSystem
extends RefCounted
## Run-only upgrade choices compiled from the current weapon structure.
## No option is selected by object identity or display name.

const CHOICE_COUNT := 3
const CORE_LABELS := {
	"impact": "冲击核心",
	"control": "控制核心",
	"tempo": "节奏核心",
	"stability": "稳定核心",
}


static func build_choices(
	blueprint: WeaponBlueprint,
	ranged_runtime: Dictionary,
	roadpost_index: int,
	run_seed: int,
	taken_ids: Array[String],
	reward_context: Dictionary = {},
	meta_context: Dictionary = {}
) -> Array[Dictionary]:
	if blueprint == null:
		return []
	var axes: Dictionary = blueprint.affordance
	var is_ranged := str(axes.get("weapon_domain", "")) == "handheld_firearm"
	var advanced := bool(meta_context.get("advanced_modules_unlocked", false))
	var groups: Array[Array] = _ranged_groups(ranged_runtime, advanced) \
		if is_ranged \
		else _melee_groups(axes, advanced)
	var result: Array[Dictionary] = []
	for group_index: int in range(mini(CHOICE_COUNT, groups.size())):
		var group: Array = groups[group_index]
		var available: Array[Dictionary] = []
		for candidate: Dictionary in group:
			if str(candidate.get("id", "")) not in taken_ids:
				available.append(candidate)
		if available.is_empty():
			for candidate: Dictionary in group:
				available.append(candidate)
		if available.is_empty():
			continue
		# The advantage column for a physical object always leads with the
		# contact/soft-structure-specific option. Other columns and later picks
		# remain seed-varied. This prevents a fork and a broad pot from presenting
		# the same first card despite having different mechanism axes.
		var pick_index := 0 if not is_ranged and group_index == 0 else posmod(run_seed * 17 + roadpost_index * 11 + group_index * 5, available.size())
		result.append(available[pick_index].duplicate(true))
	var material_cost := maxi(0, int(reward_context.get("material_cost", 0)))
	var core_family := str(reward_context.get("core_family", ""))
	if not core_family.is_empty():
		_ensure_core_compatible_choice(result, groups, core_family, taken_ids, run_seed, roadpost_index)
	for option: Dictionary in result:
		option["module_family"] = _module_family(option.get("effects", {}) as Dictionary)
		option["material_cost"] = material_cost
		option["material_available"] = maxi(0, int(reward_context.get("material_count", 0)))
	if not core_family.is_empty():
		for option: Dictionary in result:
			if str(option.get("module_family", "")) == core_family:
				_apply_core_infusion(option, core_family, is_ranged)
				break
	return result


static func core_label(core_family: String) -> String:
	return str(CORE_LABELS.get(core_family, "结构核心"))


static func _ensure_core_compatible_choice(
	result: Array[Dictionary],
	groups: Array[Array],
	core_family: String,
	taken_ids: Array[String],
	run_seed: int,
	roadpost_index: int
) -> void:
	for option: Dictionary in result:
		if _module_family(option.get("effects", {}) as Dictionary) == core_family:
			return
	# Preserve the three category columns. Replace only one card inside its own
	# column when the stored core would otherwise have no compatible socket.
	for group_index: int in range(mini(result.size(), groups.size())):
		var compatible: Array[Dictionary] = []
		for candidate: Dictionary in groups[group_index]:
			if str(candidate.get("id", "")) in taken_ids:
				continue
			if _module_family(candidate.get("effects", {}) as Dictionary) == core_family:
				compatible.append(candidate)
		if compatible.is_empty():
			continue
		var pick := posmod(run_seed * 13 + roadpost_index * 7 + group_index * 3, compatible.size())
		result[group_index] = compatible[pick].duplicate(true)
		return


static func _module_family(effects: Dictionary) -> String:
	# Family comes only from the compiled effect channels. Object names and
	# weapon identities never participate in reward compatibility.
	for key: String in ["spread_mul", "recoil_mul", "active_guard_mul"]:
		if effects.has(key):
			return "stability"
	for key: String in ["ranged_status_mul", "melee_status_mul", "ranged_knockback_mul", "melee_knockback_mul", "pierce_add", "active_mul"]:
		if effects.has(key):
			return "control"
	for key: String in ["shot_interval_mul", "reload_mul", "startup_mul", "recovery_mul", "root_motion_mul", "firing_move_mul"]:
		if effects.has(key):
			return "tempo"
	return "impact"


static func _apply_core_infusion(option: Dictionary, core_family: String, is_ranged: bool) -> void:
	var effects: Dictionary = (option.get("effects", {}) as Dictionary).duplicate(true)
	var bonus_text := ""
	match core_family:
		"stability":
			if is_ranged:
				_multiply_effect(effects, "spread_mul", 0.78)
				_multiply_effect(effects, "recoil_mul", 0.78)
				bonus_text = "散布与后坐力再降低22%"
			else:
				_multiply_effect(effects, "active_guard_mul", 0.82)
				_multiply_effect(effects, "melee_armor_mul", 1.20)
				bonus_text = "出招防护与破甲能力进一步增强"
		"control":
			if is_ranged:
				_multiply_effect(effects, "ranged_knockback_mul", 1.20)
				_multiply_effect(effects, "ranged_status_mul", 1.20)
			else:
				_multiply_effect(effects, "melee_knockback_mul", 1.20)
				_multiply_effect(effects, "melee_status_mul", 1.20)
			bonus_text = "控制作用再提高20%"
		"tempo":
			if is_ranged:
				_multiply_effect(effects, "shot_interval_mul", 0.90)
				_multiply_effect(effects, "reload_mul", 0.90)
			else:
				_multiply_effect(effects, "startup_mul", 0.90)
				_multiply_effect(effects, "recovery_mul", 0.90)
			bonus_text = "起手与循环再加快10%"
		_:
			_multiply_effect(effects, "ranged_damage_mul" if is_ranged else "melee_damage_mul", 1.12)
			bonus_text = "直接作用强度再提高12%"
	option["effects"] = effects
	option["core_infused"] = true
	option["core_family"] = core_family
	option["detail"] = "%s 核心追加：%s。" % [str(option.get("detail", "")), bonus_text]
	option["basis"] = "%s · %s兼容" % [str(option.get("basis", "")), core_label(core_family)]


static func _multiply_effect(effects: Dictionary, key: String, multiplier: float) -> void:
	effects[key] = float(effects.get(key, 1.0)) * multiplier


static func _option(
	id: String,
	category: String,
	title: String,
	detail: String,
	basis: String,
	effects: Dictionary
) -> Dictionary:
	return {
		"id": id,
		"category": category,
		"title": title,
		"detail": detail,
		"basis": basis,
		"effects": effects.duplicate(true),
	}


static func _advanced_option(
	id: String,
	category: String,
	title: String,
	detail: String,
	basis: String,
	effects: Dictionary
) -> Dictionary:
	var option := _option(id, category, title, detail, basis, effects)
	option["meta_unlock"] = "advanced_modules"
	return option


static func _ranged_groups(runtime: Dictionary, advanced: bool = false) -> Array[Array]:
	var pattern := "pellet_cloud" if int(runtime.get("pellet_count", 1)) > 1 else "single_projectile"
	var feed := str({0: "detachable_box", 1: "internal_tube", 2: "revolving_cylinder", 3: "belt_box"}.get(int(runtime.get("reload_feed_code", 0)), "detachable_box"))
	var basis := "投射结构 %s · 供弹结构 %s" % [pattern, feed]
	var advantage: Array = [
		_option("ranged_piercing_path", "强化优势", "贯穿弹道", "子弹多穿透1个目标；单发伤害降低10%。", basis, {"pierce_add": 1, "ranged_damage_mul": 0.90}),
		_option("ranged_weighted_payload", "强化优势", "加重弹头", "伤害提高25%、破甲提高40%；弹速降低18%，射击间隔增加8%。", basis, {"ranged_damage_mul": 1.25, "ranged_armor_mul": 1.40, "projectile_speed_mul": 0.82, "shot_interval_mul": 1.08}),
		_option("ranged_suppression_impact", "强化优势", "冲击压制", "击退与硬直提高50%；射击间隔增加15%。", basis, {"ranged_knockback_mul": 1.50, "ranged_status_mul": 1.50, "shot_interval_mul": 1.15}),
	]
	var style: Array = [
		_option("ranged_fast_cycle", "改变打法", "快速循环", "射击与装填加快18%；单发伤害降低12%。", basis, {"shot_interval_mul": 0.82, "reload_mul": 0.82, "ranged_damage_mul": 0.88}),
		_option("ranged_stable_line", "改变打法", "稳定射线", "散布与后坐力降低35%；移动射击速度降低15%。", basis, {"spread_mul": 0.65, "recoil_mul": 0.65, "firing_move_mul": 0.85}),
		_option("ranged_long_reach", "改变打法", "远距校准", "弹道寿命和有效射程提高30%；装填时间增加10%。", basis, {"projectile_life_mul": 1.30, "falloff_range_mul": 1.30, "reload_mul": 1.10}),
	]
	if int(runtime.get("pellet_count", 1)) > 1:
		style.push_front(_option("ranged_wide_pattern", "改变打法", "扩散覆盖", "弹丸夹角扩大35%、击退提高25%；每颗弹丸伤害降低8%。", basis, {"pellet_spread_mul": 1.35, "ranged_knockback_mul": 1.25, "pellet_damage_mul": 0.92}))
	var gamble: Array = [
		_option("ranged_deep_magazine", "高收益代价", "扩容供弹", "弹匣容量提高50%并立即补入新增弹药；装填时间增加30%。", basis, {"magazine_mul": 1.50, "reload_mul": 1.30}),
		_option("ranged_overpressure", "高收益代价", "超压发射", "单发伤害提高38%；后坐力提高40%，射击间隔增加28%。", basis, {"ranged_damage_mul": 1.38, "recoil_mul": 1.40, "shot_interval_mul": 1.28}),
		_option("ranged_mobile_burst", "高收益代价", "移动火力", "移动射击速度提高25%；散布增加35%，伤害降低10%。", basis, {"firing_move_mul": 1.25, "spread_mul": 1.35, "ranged_damage_mul": 0.90}),
	]
	if advanced:
		advantage.append(_advanced_option("ranged_breach_calibration", "强化优势", "破阵校射", "破甲提高55%、硬直提高25%；射击间隔增加12%。", basis, {"ranged_armor_mul": 1.55, "ranged_status_mul": 1.25, "shot_interval_mul": 1.12}))
		style.append(_advanced_option("ranged_march_reload", "改变打法", "行进装填", "装填加快28%、移动射击速度提高15%；单发伤害降低10%。", basis, {"reload_mul": 0.72, "firing_move_mul": 1.15, "ranged_damage_mul": 0.90}))
		gamble.append(_advanced_option("ranged_unstable_pressure", "高收益代价", "不稳定高压", "单发伤害提高55%；后坐力提高70%、装填时间增加25%。", basis, {"ranged_damage_mul": 1.55, "recoil_mul": 1.70, "reload_mul": 1.25}))
	return [advantage, style, gamble]


static func _melee_groups(axes: Dictionary, advanced: bool = false) -> Array[Array]:
	var contact := str(axes.get("contact_surface", "whole_body"))
	var mass := str(axes.get("mass_distribution", "balanced"))
	var flex := str(axes.get("flex_topology", "none"))
	var tether := str(axes.get("tether_topology", "none"))
	var output := str(axes.get("functional_output", "contact_only"))
	var basis := "主接触面 %s · 重量分布 %s" % [contact, mass]
	var advantage: Array = [
		_option("melee_momentum", "强化优势", "惯性重击", "伤害提高25%、击退提高45%；收招延长15%。", basis, {"melee_damage_mul": 1.25, "melee_knockback_mul": 1.45, "recovery_mul": 1.15}),
		_option("melee_breaking_contact", "强化优势", "破势接触", "破甲提高65%、硬直提高35%；伤害降低8%。", basis, {"melee_armor_mul": 1.65, "melee_stagger_mul": 1.35, "melee_damage_mul": 0.92}),
		_option("melee_focused_contact", "强化优势", "接触集中", "起手加快10%、伤害提高18%；击退降低15%。", basis, {"startup_mul": 0.90, "melee_damage_mul": 1.18, "melee_knockback_mul": 0.85}),
	]
	match contact:
		"point":
			advantage.push_front(_option("melee_point_puncture", "强化优势", "尖端贯入", "尖端伤害提高20%、破甲提高40%；击退降低20%。", basis, {"melee_damage_mul": 1.20, "melee_armor_mul": 1.40, "melee_knockback_mul": 0.80}))
		"edge":
			advantage.push_front(_option("melee_edge_followthrough", "强化优势", "刃边续斩", "伤害提高15%、有效攻击时间提高20%；收招延长10%。", basis, {"melee_damage_mul": 1.15, "active_mul": 1.20, "recovery_mul": 1.10}))
		"broad":
			advantage.push_front(_option("melee_broad_shove", "强化优势", "宽面推阵", "击退提高60%、有效攻击时间提高20%；伤害降低15%。", basis, {"melee_knockback_mul": 1.60, "active_mul": 1.20, "melee_damage_mul": 0.85}))
		_:
			advantage.push_front(_option("melee_body_impact", "强化优势", "整体现冲", "伤害提高10%、硬直提高50%；收招延长10%。", basis, {"melee_damage_mul": 1.10, "melee_stagger_mul": 1.50, "recovery_mul": 1.10}))
	if flex != "none" or tether != "none":
		advantage.push_front(_option("melee_soft_control", "强化优势", "柔性控场", "束缚状态提高45%、有效攻击时间提高15%；伤害降低10%。", "软体结构 %s · 牵引结构 %s" % [flex, tether], {"melee_status_mul": 1.45, "active_mul": 1.15, "melee_damage_mul": 0.90}))
	var style: Array = [
		_option("melee_flow", "改变打法", "连势收招", "起手与收招加快18%；伤害降低10%。", basis, {"startup_mul": 0.82, "recovery_mul": 0.82, "melee_damage_mul": 0.90}),
		_option("melee_chase", "改变打法", "踏步追击", "攻击踏步距离提高40%；收招延长12%。", basis, {"root_motion_mul": 1.40, "recovery_mul": 1.12}),
		_option("melee_active_window", "改变打法", "持续攻击面", "有效攻击时间提高35%，更容易覆盖多个目标；伤害降低10%。", basis, {"active_mul": 1.35, "melee_damage_mul": 0.90}),
	]
	var gamble: Array = [
		_option("melee_committed_power", "高收益代价", "全力出手", "伤害提高40%；起手延长18%、收招延长28%，攻击中移动更慢。", basis, {"melee_damage_mul": 1.40, "startup_mul": 1.18, "recovery_mul": 1.28, "attack_move_mul": 0.75}),
		_option("melee_active_guard", "高收益代价", "借势护身", "有效攻击时承伤降低28%；收招延长15%。", basis, {"active_guard_mul": 0.72, "recovery_mul": 1.15}),
		_option("melee_counterweight", "高收益代价", "反配重", "伤害与击退提高15%；踏步距离降低25%、起手延长12%。", basis, {"melee_damage_mul": 1.15, "melee_knockback_mul": 1.15, "root_motion_mul": 0.75, "startup_mul": 1.12}),
	]
	if flex != "none" or tether != "none":
		gamble.push_front(_option("melee_soft_bind", "高收益代价", "软体束缚", "缠绕、钉住和压制时间提高60%；伤害降低16%、收招延长12%。", "软体结构 %s · 牵引结构 %s" % [flex, tether], {"melee_status_mul": 1.60, "melee_damage_mul": 0.84, "recovery_mul": 1.12}))
	if output != "contact_only":
		gamble.push_front(_option("melee_output_amplifier", "高收益代价", "功能增压", "长按功能输出的伤害与作用力增强；收招延长20%。", "功能输出 %s" % output, {"state_damage_mul": 1.35, "state_force_mul": 1.45, "recovery_mul": 1.20}))
	if advanced:
		advantage.append(_advanced_option("melee_decisive_window", "强化优势", "短窗决断", "伤害提高50%、破甲提高25%；有效攻击时间缩短22%。", basis, {"melee_damage_mul": 1.50, "melee_armor_mul": 1.25, "active_mul": 0.78}))
		style.append(_advanced_option("melee_line_break_step", "改变打法", "穿阵步", "攻击踏步提高70%、起手加快8%；收招延长12%。", basis, {"root_motion_mul": 1.70, "startup_mul": 0.92, "recovery_mul": 1.12}))
		gamble.append(_advanced_option("melee_last_stake", "高收益代价", "孤注重击", "伤害提高60%；起手延长32%、收招延长42%，攻击中移动更慢。", basis, {"melee_damage_mul": 1.60, "startup_mul": 1.32, "recovery_mul": 1.42, "attack_move_mul": 0.62}))
	return [advantage, style, gamble]
