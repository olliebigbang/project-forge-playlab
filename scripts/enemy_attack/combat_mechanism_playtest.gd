extends Node2D

const ARENA := preload("res://scripts/systems/open_identity_training_arena.gd")
const MOCK_GENERATOR := preload("res://scripts/services/mock_weapon_image_generator.gd")

var arena: Node2D
var blueprint: WeaponBlueprint
var visual_asset: WeaponVisualAsset
var status_label: Label


func _ready() -> void:
	blueprint = WeaponBlueprint.fixed_blueprint("gatling")
	blueprint.display_name = "机制试玩步枪"
	blueprint.effect_type = "ballistic_projectile"
	blueprint.affordance = _playtest_firearm_axes()
	blueprint.affordance_source = "AI_DEVELOPER_PLAYTEST_FIXTURE"
	var generated: Dictionary = MOCK_GENERATOR.new().generate(blueprint)
	if not bool(generated.get("ok", false)):
		printerr("COMBAT_MECHANISM_PLAYTEST_ASSET_FAILED:%s" % str(generated.get("error", "UNKNOWN")))
		get_tree().quit(1)
		return
	visual_asset = generated.get("asset") as WeaponVisualAsset
	if visual_asset == null:
		printerr("COMBAT_MECHANISM_PLAYTEST_ASSET_MISSING")
		get_tree().quit(1)
		return
	arena = ARENA.new()
	add_child(arena)
	_build_overlay()
	_start_round()


func _process(_delta: float) -> void:
	if arena == null or status_label == null:
		return
	var enemy_lines: Array[String] = []
	for enemy: Dictionary in arena.enemies:
		var runtime: Variant = enemy.get("attack_runtime", null)
		var delivery := "none"
		if runtime != null and runtime.is_running():
			delivery = runtime.current_delivery()
		enemy_lines.append("%s  %s / %s" % [str(enemy.get("type", "target")), str(enemy.get("attack_phase", "idle")), delivery])
	status_label.text = (
		"敌人攻击 × 武器反应 试玩\n"
		+ "WASD/方向键移动　空格或 J 射击　Shift 或 K 闪避　R 重开　Esc 退出\n"
		+ "生命 %.0f　敌方弹体/地面危险区 %d\n" % [float(arena.player_health), arena.enemy_attack_hazards.size()]
		+ "玩家枪械：%s\n" % _firearm_mechanism_text(arena.ranged_runtime_profile as Dictionary)
		+ "看本体：炮管＝弹体　撞角＝冲撞　聚焦核心＝落点　挥击肢体＝近战\n"
		+ "看范围：断续射线＝弹道　连续箭头＝冲撞通道　同心准星＝落点\n"
		+ "敌人状态：" + "　|　".join(enemy_lines)
	)


func _firearm_mechanism_text(runtime: Dictionary) -> String:
	var trigger_text := "按一下单发"
	if bool(runtime.get("automatic_fire", false)):
		trigger_text = "按住连射"
	elif int(runtime.get("burst_size", 0)) > 1:
		trigger_text = "按一下 %d 连发" % int(runtime.get("burst_size", 0))
	var cycle_text := str({
		1: "每发后拉栓",
		2: "每发后泵动",
		3: "扳机带动转轮",
	}.get(int(runtime.get("cycle_action_code", 0)), "自动循环"))
	var shot_text := "单弹丸"
	if int(runtime.get("pellet_count", 1)) > 1:
		shot_text = "%d 颗霰弹/枪" % int(runtime.get("pellet_count", 1))
	var reload_text := str({
		0: "整匣更换",
		1: "逐发装填（可射击打断）",
		2: "转轮分批装填",
		3: "整箱更换弹链",
	}.get(int(runtime.get("reload_feed_code", 0)), "整匣更换"))
	return "%s · %s · %s · %s" % [trigger_text, cycle_text, shot_text, reload_text]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R:
			_start_round()
		elif event.physical_keycode == KEY_ESCAPE:
			get_tree().quit()


func _start_round() -> void:
	if arena == null:
		return
	arena.start_stage("room_2", blueprint, visual_asset)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var panel := ColorRect.new()
	panel.position = Vector2(18, 14)
	panel.size = Vector2(1244, 142)
	panel.color = Color(0.02, 0.05, 0.09, 0.88)
	layer.add_child(panel)
	status_label = Label.new()
	status_label.position = Vector2(30, 22)
	status_label.size = Vector2(1220, 134)
	status_label.add_theme_font_override("font", load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font)
	status_label.add_theme_font_size_override("font_size", 15)
	status_label.add_theme_color_override("font_color", Color("e2e8f0"))
	layer.add_child(status_label)


func _playtest_firearm_axes() -> Dictionary:
	return {
		"weapon_domain": "handheld_firearm",
		"firearm_family": "rifle",
		"layout": "conventional_rifle",
		"stock_structure": "fixed",
		"feed_position": "ahead_of_grip",
		"magazine_shape": "curved",
		"barrel_length": "medium",
		"upper_profile": "top_rail",
		"support_mode": "two_hand_shouldered",
		"fire_control": "select_fire_auto",
		"action_mechanism": "self_loading",
		"feed_system": "detachable_box",
		"shot_pattern": "single_projectile",
		"sustained_climb": "progressive",
		"cadence": "balanced",
		"recoil": "medium",
		"recoil_recovery": "balanced",
		"muzzle_climb": "medium",
		"accuracy": "controlled",
		"impact_force": "medium",
		"penetration": "medium",
		"reload": "standard",
		"effective_range": "long",
		"handling": "balanced",
		"magazine_capacity": "standard",
		"confidence": 0.99,
	}
