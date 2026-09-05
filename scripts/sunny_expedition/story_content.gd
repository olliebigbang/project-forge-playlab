class_name SunnyStoryContent
extends RefCounted
## First playable story region. Text lives beside its mechanical route contract
## so a choice cannot promise an effect that the combat scene never receives.

const MODE_STORY := "story"
const MODE_TRIAL := "trial"
const STORY_CHAPTER_COUNT := 3
const TRIAL_CHAPTER_COUNT := 1

const CHAPTERS := [
	"蒲公英驿道",
	"回声溪桥",
	"荆棘后的空白",
]

const QUEST_TITLE := "第一章 · 被忘掉的送货单"
const QUEST_SUMMARY := "邮差阿禾记得包裹的重量，却忘了里面是什么。沿三段旧路追查“忘潮”，把失物的记忆带回工坊。"

const ROUTES := {
	"brook": {
		"title": "沿溪桥走",
		"short": "溪桥",
		"effect": "敌人移动较慢，适合观察新武器",
		"combat": {"enemy_move_mul": 0.84, "enemy_health_mul": 1.0, "enemy_damage_mul": 0.94, "starting_materials": 0, "starting_core": ""},
	},
	"grove": {
		"title": "穿菌伞林",
		"short": "菌伞林",
		"effect": "先获得3锻材，但毒雾与冲刺怪更常出现",
		"combat": {"enemy_move_mul": 1.0, "enemy_health_mul": 1.04, "enemy_damage_mul": 1.0, "starting_materials": 3, "starting_core": "", "roster_offset": 1},
	},
	"ridge": {
		"title": "登旧风坡",
		"short": "旧风坡",
		"effect": "敌人更强；开局获得稳定核心，可做高收益构筑",
		"combat": {"enemy_move_mul": 1.08, "enemy_health_mul": 1.16, "enemy_damage_mul": 1.14, "starting_materials": 0, "starting_core": "stability", "roster_offset": 2},
	},
}


static func normalize_mode(value: Variant) -> String:
	return MODE_STORY if str(value) == MODE_STORY else MODE_TRIAL


static func normalize_route(value: Variant) -> String:
	var route := str(value)
	return route if ROUTES.has(route) else "brook"


static func route_ids() -> Array[String]:
	return ["brook", "grove", "ridge"]


static func route(value: Variant) -> Dictionary:
	return (ROUTES[normalize_route(value)] as Dictionary).duplicate(true)


static func route_label(value: Variant) -> String:
	return str(route(value).get("short", "溪桥"))


static func route_combat(value: Variant) -> Dictionary:
	return (route(value).get("combat", {}) as Dictionary).duplicate(true)


static func prologue() -> String:
	return "邮差阿禾：“送货单有重量、有磨损，唯独物品的名字被抹掉了。村里丢失的东西都是这样。”\n用工坊还原你记得的任意物品，再选路追查忘潮：\n%s" % route_choice_summary()


static func briefing(chapter: int, route_id: String, weapon_name: String) -> String:
	var route_data := route(route_id)
	var story_lines := [
		"阿禾在路牌背面找到同一种白色擦痕。清开驿道，确认它通向哪里。",
		"溪水会重复路人忘掉的词。守住路标，从回声里辨认包裹的旧名字。",
		"所有线索都停在一片没有名字的荆棘前。破开守望者，把记忆带回村子。",
	]
	return "%s\n\n路线：%s · %s。\n本段有四处路标；前三处会把回收材料编译成机制强化。\n当前造物：%s" % [story_lines[clampi(chapter, 0, story_lines.size() - 1)], str(route_data.title), str(route_data.effect), weapon_name]


static func interlude(completed_chapter: int) -> String:
	var lines := [
		"路牌恢复了一个字：‘归’。阿禾确信，这不是怪物留下的抓痕，而是有人在主动删去物品的名字。",
		"溪水吐出第二个字：‘还’。包裹里装的也许不是宝物，而是一件有人拼命想让世界忘掉的日常用品。",
	]
	return lines[clampi(completed_chapter, 0, lines.size() - 1)] + "\n\n下一段从哪条路走？\n" + route_choice_summary()


static func route_choice_summary() -> String:
	return "溪桥：追击较慢｜菌伞林：锻材+3、毒雾更多\n旧风坡：敌人更强，稳定核心+1"


static func ending(weapon_name: String) -> String:
	return "送货单重新显出：“请归还一件无人记得、却仍有人需要的东西。”\n阿禾把空白包裹放进工坊；下一件被描述的物品，会让这段记忆长出另一种战斗方式。\n带回造物：%s" % weapon_name
