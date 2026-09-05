extends RefCounted
## Content pacing, never a weapon-name recipe. The same rooms accept any
## validated weapon. Time is earned by defending an active objective, not idle.
const CATALOG := preload("res://scripts/enemy_attack/offline_enemy_blueprint_catalog.gd")
const CHAPTERS := ["烛光前厅", "回声长廊", "最后的圣坛"]
const LESSONS := ["引开落点，回到阵眼；横扫后再出手。", "突进锁定后横向闪开；别让两侧敌人夹住你。", "重击蓄势时先避让；抓住恢复窗口反击。"]
const SEAL_SECONDS := 85.0
const SEAL_RADIUS := 138.0
const CONTEST_RADIUS := 66.0
const SEAL_COUNT := 2

static func initial_spawns(_chapter: int) -> int:
	return 0

static func max_active_enemies(chapter: int) -> int:
	return 3 if chapter == 0 else 4

static func spawn_interval(chapter: int) -> float:
	return 12.0 - chapter * 1.0

static func max_active_attackers(chapter: int) -> int:
	return 1 if chapter == 0 else 2

static func seal_health_reward(_chapter: int) -> float:
	return 10.0

static func seal_supply_reward(_chapter: int) -> int:
	return 0

static func seal_position(chapter: int, seal: int, seed_value: int) -> Vector2:
	var left := ((chapter + seal + seed_value) % 2) == 0
	return Vector2(410 if left else 855, 465 if seal == 0 else 550)

static func make_profile(chapter: int, ordinal: int, seed_value: int, elite: bool = false) -> Dictionary:
	var catalog := CATALOG.load_validated()
	if not catalog.get("ok", false): return {}
	var ids := ["ember_priest", "mechanical_spider"]
	var selected: String = ids[posmod(ordinal + seed_value + chapter, 2)]
	if elite and chapter == 2: selected = "frost_siege_beast"
	var result: Dictionary = catalog.profiles_by_id.get(selected, {}).duplicate(true)
	if result.is_empty(): return {}
	result["display_name"] = "圣坛守门者" if elite else ("教堂术士" if selected == "ember_priest" else "焚行者")
	result["max_health"] = (290.0 + chapter * 75.0) if elite else (65.0 + chapter * 17.0)
	result["move_speed"] = float(result.get("move_speed", 60.0)) * (0.90 + chapter * 0.05)
	result["damage_multiplier"] = 0.80 + chapter * 0.12
	result["attack_tempo_multiplier"] = 1.0
	result["expedition_elite"] = elite
	result["spawn_position"] = Vector2(1030, 490)
	return result

static func weapon_help(weapon: Dictionary) -> String:
	var bp := weapon.get("blueprint") as WeaponBlueprint
	if bp == null: return "选择一件武器，或描述新的物品。"
	var axes: Dictionary = bp.affordance
	if axes.get("weapon_domain", "") == "handheld_firearm":
		var r: Dictionary = weapon.get("ranged_runtime_profile", {})
		return "%s射击 · 弹匣 %d 发\n在阵眼内保持射线；换弹时移动或闪避。" % ["按住" if r.get("automatic_fire", false) else "点按", int(r.get("magazine_size", 0))]
	var tips: Array[String] = []
	if axes.get("tether_mode", "none") in ["hook", "wrap"] or axes.get("flex_topology", "none") in ["linked_segments", "flexible_line"]:
		tips.append("软体轨迹能控制敌人；留出甩动和收回的空间。")
	elif axes.get("body_length", "medium") == "long":
		tips.append("长距离接触；站在敌人出手范围外抢先攻击。")
	elif axes.get("contact_surface", "") in ["broad", "whole_body"]:
		tips.append("近身推挡；把靠近阵眼的敌人逼开。")
	else: tips.append("贴近接触点出手；打空后先躲开反击。")
	if axes.get("activation_mode", "") == "charge_release": tips.append("长按蓄力，松手释放；蓄力时留意预警。")
	elif axes.get("functional_output", "contact_only") != "contact_only": tips.append("长按启动功能；注意作用方向与持续代价。")
	else: tips.append("点按连击；长按使用已编译的结构能力。")
	return "\n".join(tips)
