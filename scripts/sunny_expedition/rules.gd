extends RefCounted
## Presentation and chapter content only; enemy attacks still compile from axes.
const BASE := preload("res://scripts/art_vertical_slice_v1/expedition_rules.gd")
const CATALOG := preload("res://scripts/enemy_attack/offline_enemy_blueprint_catalog.gd")
const SUNNY_CATALOG_PATH := "res://data/enemy_attack/sunny_enemy_catalog_v1.json"
const CHAPTERS := ["蒲公英驿道", "回声溪桥", "荆棘后的空白"]
const LESSONS := [
	"四种怪物会混合进场：推开弹簧菇，躲开毒雾菇冲刺，打断晴风幽灵，最后破开荆棘守望者。",
	"敌人开始交叉掩护：先清除封路者，再抓住冲刺怪的长收招反击。",
	"守望者会把前两段机制混在一起；保留闪避处理红色预警，集中破防。",
]
const ROSTER := ["spring_hopper", "spore_raider", "wind_wisp", "thorn_guardian"]
const DISPLAY_NAMES := {
	"spring_hopper": "弹簧菇怪",
	"spore_raider": "毒雾菇巡游者",
	"wind_wisp": "晴风幽灵",
	"thorn_guardian": "荆棘食人花",
}
## Fast public-playtest route: four short holds and exactly seven ordinary
## enemies, followed by one guardian. This preserves the full route/build loop
## without making every weapon audition a forty-eight-enemy endurance run.
const SEAL_SECONDS := 8.0
const SEAL_RADIUS := 138.0
const CONTEST_RADIUS := 66.0
const SEAL_COUNT := 4
const ROUTE_WORLD_LENGTH := 4480.0
const ROADPOSTS := [Vector2(900, 455), Vector2(1840, 520), Vector2(2810, 455), Vector2(3820, 520)]
const SEGMENT_ENEMY_BUDGETS := [2, 2, 2, 1]
const REGULAR_ENEMY_BUDGET := 7
const TOTAL_ENEMY_BUDGET := 8
const STORY_SEGMENT_ENEMY_BUDGETS := [
	[3, 3, 3, 2],
	[3, 4, 3, 3],
	[4, 4, 4, 3],
]
const STORY_TOTAL_ENEMY_BUDGETS := [12, 14, 16]
const CHAMPION_INTERVAL := 15

static func initial_spawns(_chapter: int) -> int:
	return segment_spawns(0)


static func segment_spawns(seal: int) -> int:
	if seal < 0 or seal >= SEGMENT_ENEMY_BUDGETS.size():
		return 0
	return int(SEGMENT_ENEMY_BUDGETS[seal])


static func story_segment_spawns(chapter: int, seal: int) -> int:
	var chapter_budgets: Array = STORY_SEGMENT_ENEMY_BUDGETS[clampi(chapter, 0, STORY_SEGMENT_ENEMY_BUDGETS.size() - 1)]
	if seal < 0 or seal >= chapter_budgets.size():
		return 0
	return int(chapter_budgets[seal])

static func max_active_enemies(_chapter: int) -> int:
	return 2

static func spawn_interval(_chapter: int) -> float:
	return 8.5

static func max_active_attackers(_chapter: int) -> int:
	return 2

static func seal_health_reward(_chapter: int) -> float:
	# The old three-chapter route refilled between chapters. The first continuous
	# map port copied too much of that sustain: multi-seed measurement showed
	# firearm and rigid-long damage was erased at every roadpost, while globally
	# raising enemy damage would disproportionately punish committed flexible
	# weapons. Keep an earned breather, but let damage carry into the next leg.
	return 10.0

static func seal_supply_reward(_chapter: int) -> int:
	# One replacement charge rewards progress without automatically refilling
	# both inventory slots at every roadpost. The run still starts with two.
	return 1

static func seal_position(chapter: int, seal: int, seed_value: int) -> Vector2:
	# The order stays left-to-right. The seed changes reinforcements, not the
	# direction of travel; a forward route must never send the player backwards.
	return ROADPOSTS[clampi(seal, 0, ROADPOSTS.size() - 1)]

static func make_profile(chapter: int, ordinal: int, seed_value: int, elite: bool = false) -> Dictionary:
	var catalog := CATALOG.load_validated(SUNNY_CATALOG_PATH)
	if not bool(catalog.get("ok", false)): return {}
	var selected := "thorn_guardian" if elite else str(ROSTER[posmod(ordinal + seed_value, ROSTER.size())])
	var profile: Dictionary = (catalog.profiles_by_id.get(selected, {}) as Dictionary).duplicate(true)
	if profile.is_empty(): return {}
	profile["display_name"] = str(DISPLAY_NAMES.get(selected, profile.get("display_name", "林地生物")))
	# A reinforcement periodically becomes a mechanism champion. This is based on
	# route cadence and its compiled attack axes, never on the monster's name.
	# Each roadpost lasts long enough to surface at least one before its reward.
	var champion := not elite \
		and ordinal >= ROSTER.size() \
		and posmod(ordinal - ROSTER.size(), CHAMPION_INTERVAL) == 0
	var modifier_family := "barrier" if elite else (_champion_modifier_family(profile) if champion else "")
	var base_health := float(profile.get("max_health", 65.0))
	var chapter_health_mul: float = float([1.0, 1.10, 1.22][clampi(chapter, 0, 2)])
	var chapter_damage_mul: float = float([1.0, 1.07, 1.14][clampi(chapter, 0, 2)])
	profile["max_health"] = (410.0 if elite else base_health * (1.35 if champion else 1.22)) * chapter_health_mul
	profile["move_speed"] = float(profile.get("move_speed", 60.0)) * 0.96
	profile["damage_multiplier"] = (1.0 if elite or champion else 0.92) * chapter_damage_mul
	# 1.03 was clamped back to 1.0 by the runtime and therefore had no effect.
	# Keep the clean default until the measurement pass tunes a real pressure value.
	profile["attack_tempo_multiplier"] = 1.0
	profile["enemy_modifier_declarations"] = [] if modifier_family.is_empty() else [{
		"modifier_key": "sunny_elite_shell" if elite else "sunny_champion_%d" % ordinal,
		"family": modifier_family,
	}]
	profile["expedition_elite"] = elite
	profile["expedition_champion"] = champion
	profile["reward_core_family"] = _core_family_for_modifier(modifier_family)
	profile["spawn_position"] = Vector2(1030, 490)
	return profile


static func _champion_modifier_family(profile: Dictionary) -> String:
	var has_residual_hazard := false
	for declaration: Dictionary in profile.get("attack_declarations", []) as Array:
		var axes: Dictionary = declaration.get("axes", {})
		if str(axes.get("defense_mode", "none")) != "none":
			return "barrier"
		if str(axes.get("hazard_mode", "instant")) in ["lingering", "pulsing"]:
			has_residual_hazard = true
	return "residue" if has_residual_hazard else "echo"


static func _core_family_for_modifier(modifier_family: String) -> String:
	return {
		"barrier": "stability",
		"residue": "control",
		"echo": "tempo",
	}.get(modifier_family, "")

static func weapon_help(weapon: Dictionary) -> String:
	var help := BASE.weapon_help(weapon).replace("阵眼", "路标")
	var bp := weapon.get("blueprint") as WeaponBlueprint
	if bp != null and bp.affordance.get("weapon_domain", "") == "handheld_firearm":
		help += "\n打低矮敌人时停步蹲射（自动，也可按 C）。"
	return help
