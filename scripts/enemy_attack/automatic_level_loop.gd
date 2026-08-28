class_name AutomaticLevelLoop
extends Node2D

const ARENA := preload("res://scripts/systems/gameplay_arena.gd")
const ARMORY := preload("res://scripts/combat_feel/player_weapon_armory.gd")
const DIRECTOR := preload("res://scripts/enemy_attack/automatic_encounter_director.gd")
const RANGED_AXIS_RESOLVER := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")

var arena: GameplayArena
var armory: RefCounted = ARMORY.new()
var director: RefCounted = DIRECTOR.new()
var armory_entries: Array[Dictionary] = []
var equipped_entry: Dictionary = {}
var current_encounter: Dictionary = {}
var state := "boot"
var intermission_seconds := 0.0
var run_health := 100.0
var encounter_start_health := 100.0
var run_metrics := {
	"damage_taken": 0.0,
	"defeated": 0,
	"shots_fired": 0,
	"reload_count": 0,
	"elapsed_seconds": 0.0,
}

var status_label: Label
var weapon_panel: Control
var weapon_list: HBoxContainer
var armory_message: Label
var combat_controls: Control
var message_panel: Control
var message_title: Label
var message_body: Label
var primary_button: Button
var secondary_button: Button


func _ready() -> void:
	arena = ARENA.new() as GameplayArena
	arena.visible = false
	arena.stage_completed.connect(_on_stage_completed)
	add_child(arena)
	_build_ui()
	var configured: Dictionary = director.configure()
	if not bool(configured.get("ok", false)):
		_show_fatal_error("离线敌人蓝图没有通过机制检查：%s" % str(configured.get("error", "未知错误")))
		return
	if _take_ranged_handoff():
		_begin_run(equipped_entry)
		return
	_show_weapon_picker()


func _process(delta: float) -> void:
	if state == "between_encounters":
		intermission_seconds = maxf(0.0, intermission_seconds - delta)
		if intermission_seconds <= 0.0:
			_start_next_encounter()
	elif state == "combat":
		_update_combat_status()
		var encounter_damage := float(arena.metrics.get("damage_taken", 0.0))
		if arena.player_health <= 1.0 and encounter_damage >= encounter_start_health:
			_finish_failure("生命耗尽")


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_ESCAPE:
		get_tree().change_scene_to_file("res://scenes/open_identity_spike.tscn")
	elif event.physical_keycode == KEY_R and state in ["completed", "failed"]:
		_begin_run(equipped_entry)
	elif event.physical_keycode == KEY_B and state in ["completed", "failed", "weapon_select"]:
		_show_weapon_picker()


func _take_ranged_handoff() -> bool:
	var handoff: Node = get_node_or_null("/root/MechanismHandoff")
	if handoff == null or not handoff.has_method("take_ranged"):
		return false
	var payload: Dictionary = handoff.call("take_ranged") as Dictionary
	if payload.is_empty():
		return false
	var blueprint := payload.get("blueprint") as WeaponBlueprint
	equipped_entry = {
		"blueprint": blueprint,
		"asset": payload.get("asset"),
		"ranged_runtime_profile": (payload.get("ranged_runtime_profile", {}) as Dictionary).duplicate(true),
		"display_name": blueprint.display_name if blueprint != null else "",
		"source_kind": "runtime_mechanism_handoff",
	}
	return true


func _show_weapon_picker() -> void:
	arena.stop()
	arena.visible = false
	state = "weapon_select"
	weapon_panel.visible = true
	combat_controls.visible = false
	message_panel.visible = false
	armory_entries = armory.load_entries()
	_rebuild_weapon_cards()
	if armory_entries.is_empty():
		armory_message.text = "本地武器库里还没有通过图片和机制检查的枪。请先在 Forge 生成一把枪，再回来开战。"
	else:
		armory_message.text = "只选你的武器。敌人、出现顺序和攻击方式全部由系统用离线验收蓝图安排。"
	status_label.text = "三战短关卡 · 选择武器\n不会要求你输入敌人，也不会在线等待 AI。"


func _begin_run(entry: Dictionary) -> void:
	var started: Dictionary = director.begin_run(entry)
	if not bool(started.get("ok", false)):
		_show_fatal_error("这把枪的机制交接不完整：%s" % str(started.get("error", "未知错误")))
		return
	equipped_entry = entry.duplicate(true)
	run_health = 100.0
	run_metrics = {
		"damage_taken": 0.0,
		"defeated": 0,
		"shots_fired": 0,
		"reload_count": 0,
		"elapsed_seconds": 0.0,
	}
	weapon_panel.visible = false
	combat_controls.visible = false
	_schedule_next_encounter(0.85)


func _schedule_next_encounter(delay_seconds: float) -> void:
	state = "between_encounters"
	intermission_seconds = delay_seconds
	message_panel.visible = true
	primary_button.visible = false
	secondary_button.visible = false
	var next_number := int((director.snapshot() as Dictionary).get("completed_count", 0)) + 1
	message_title.text = "准备第 %d 战" % next_number
	message_body.text = "系统正在从已验收的敌人机制蓝图安排下一场战斗。\n你不需要选择敌人或确认它怎么攻击。"
	status_label.text = "已装备：%s　生命：%d\n下一场战斗会自动开始。" % [
		_weapon_display_name(),
		roundi(run_health),
	]


func _start_next_encounter() -> void:
	var encounter: Dictionary = director.begin_next_encounter()
	if str(encounter.get("state", "")) == "completed":
		_finish_success()
		return
	if not bool(encounter.get("ok", false)):
		_show_fatal_error("关卡无法继续：%s" % str(encounter.get("error", "未知错误")))
		return
	current_encounter = encounter.duplicate(true)
	var weapon: Dictionary = director.weapon_handoff()
	var blueprint := weapon.get("blueprint") as WeaponBlueprint
	var asset := weapon.get("asset") as WeaponVisualAsset
	var runtime := weapon.get("ranged_runtime_profile", {}) as Dictionary
	blueprint.modifiers["ranged_runtime_profile"] = runtime.duplicate(true)
	var profiles: Array[Dictionary] = []
	for raw_profile: Variant in encounter.get("profiles", []):
		profiles.append((raw_profile as Dictionary).duplicate(true))
	arena.start_stage(str(encounter.get("stage_name", "automatic_encounter")), blueprint, asset, profiles)
	encounter_start_health = run_health
	arena.player_health = run_health
	arena.visible = true
	combat_controls.visible = true
	message_panel.visible = false
	state = "combat"
	_update_combat_status()


func _on_stage_completed(_stage_name: String, metrics: Dictionary) -> void:
	if state != "combat":
		return
	run_health = maxf(1.0, arena.player_health)
	_accumulate_metrics(metrics)
	var progressed: Dictionary = director.complete_active_encounter(metrics)
	arena.visible = false
	combat_controls.visible = false
	if str(progressed.get("state", "")) == "completed":
		_finish_success()
	else:
		_schedule_next_encounter(1.25)


func _finish_success() -> void:
	state = "completed"
	arena.stop()
	arena.visible = false
	combat_controls.visible = false
	message_panel.visible = true
	message_title.text = "三战完成"
	message_body.text = "你带着 %s 击败了 %d 个敌人，剩余生命 %d。\n敌人的身份和攻击方式全程由离线机制蓝图自动安排。" % [
		_weapon_display_name(),
		int(run_metrics.get("defeated", 0)),
		roundi(run_health),
	]
	_configure_result_buttons()
	status_label.text = "关卡完成　总受伤 %.0f　总射击 %d\nR 再来一次　B 换武器　Esc 返回 Forge" % [
		float(run_metrics.get("damage_taken", 0.0)),
		int(run_metrics.get("shots_fired", 0)),
	]


func _finish_failure(reason: String) -> void:
	if state != "combat":
		return
	_accumulate_metrics(arena.metrics)
	director.fail_run(reason, arena.metrics)
	run_health = 0.0
	state = "failed"
	arena.stop()
	arena.visible = false
	combat_controls.visible = false
	message_panel.visible = true
	message_title.text = "本次挑战失败"
	message_body.text = "%s。已经完成 %d / %d 场。\n武器和敌人编排不变，可以直接重试。" % [
		reason,
		int((director.snapshot() as Dictionary).get("completed_count", 0)),
		int((director.snapshot() as Dictionary).get("encounter_count", 0)),
	]
	_configure_result_buttons()
	status_label.text = "挑战结束\nR 重新开始　B 换武器　Esc 返回 Forge"


func _show_fatal_error(message: String) -> void:
	state = "error"
	if arena != null:
		arena.stop()
		arena.visible = false
	weapon_panel.visible = false
	combat_controls.visible = false
	message_panel.visible = true
	message_title.text = "关卡没有启动"
	message_body.text = message
	primary_button.visible = false
	secondary_button.visible = true
	secondary_button.text = "返回 Forge"
	status_label.text = "本地检查未通过，没有调用在线服务。"


func _configure_result_buttons() -> void:
	primary_button.visible = true
	primary_button.text = "再来一次"
	secondary_button.visible = true
	secondary_button.text = "更换武器"


func _accumulate_metrics(metrics: Dictionary) -> void:
	for key: String in ["damage_taken", "elapsed_seconds"]:
		run_metrics[key] = float(run_metrics.get(key, 0.0)) + float(metrics.get(key, 0.0))
	for key: String in ["defeated", "shots_fired", "reload_count"]:
		run_metrics[key] = int(run_metrics.get(key, 0)) + int(metrics.get(key, 0))


func _update_combat_status() -> void:
	var enemy_names: Array[String] = []
	var attack_names: Array[String] = []
	for raw_profile: Variant in current_encounter.get("profiles", []):
		var profile := raw_profile as Dictionary
		enemy_names.append(str(profile.get("display_name", "敌人")))
		for raw_label: Variant in profile.get("attack_labels_zh", []):
			attack_names.append(str(raw_label))
	var runtime_states: Array[String] = []
	for enemy: Dictionary in arena.enemies:
		var runtime: Variant = enemy.get("attack_runtime", null)
		if runtime != null and runtime.is_running():
			runtime_states.append("%s/%s" % [str(runtime.phase), runtime.current_delivery()])
	var magazine_size := int(arena.ranged_runtime_profile.get("magazine_size", 0))
	status_label.text = (
		"%s　%d / %d　|　%s　|　生命 %d　弹匣 %d/%d\n" % [
			str(current_encounter.get("title_zh", "战斗")),
			int(current_encounter.get("encounter_number", 1)),
			int(current_encounter.get("encounter_total", 1)),
			"、".join(enemy_names),
			roundi(arena.player_health),
			arena.ammo_in_magazine,
			magazine_size,
		]
		+ "%s\n" % str(current_encounter.get("brief_zh", ""))
		+ "敌人招式：%s　状态：%s" % ["、".join(attack_names), "　".join(runtime_states)]
	)


func _rebuild_weapon_cards() -> void:
	for child: Node in weapon_list.get_children():
		weapon_list.remove_child(child)
		child.queue_free()
	for index: int in range(armory_entries.size()):
		var entry := armory_entries[index]
		var blueprint := entry.get("blueprint") as WeaponBlueprint
		var asset := entry.get("asset") as WeaponVisualAsset
		var runtime := entry.get("ranged_runtime_profile", {}) as Dictionary
		if blueprint == null or asset == null or not bool(runtime.get("ok", false)):
			continue
		var card := VBoxContainer.new()
		card.custom_minimum_size = Vector2(220, 300)
		card.add_theme_constant_override("separation", 8)
		weapon_list.add_child(card)
		var preview := TextureRect.new()
		preview.custom_minimum_size = Vector2(210, 122)
		preview.texture = asset.texture
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		card.add_child(preview)
		var name_label := Label.new()
		name_label.text = blueprint.display_name
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 19)
		card.add_child(name_label)
		var mechanism := Label.new()
		mechanism.text = "%s　%s\n%s　%s\n伤害 %.0f　后坐 %.0f　容量 %d" % [
			_fire_mode_label(runtime),
			_fire_timing_label(runtime),
			_shot_pattern_label(runtime),
			_reload_feed_label(runtime),
			float(runtime.get("projectile_damage", 0.0)),
			float(runtime.get("recoil_pixels", 0.0)),
			int(runtime.get("magazine_size", 0)),
		]
		mechanism.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mechanism.add_theme_font_size_override("font_size", 14)
		mechanism.modulate = Color("bae6fd")
		card.add_child(mechanism)
		var select := Button.new()
		select.text = "带它进入三战"
		select.custom_minimum_size = Vector2(200, 48)
		var selected_index := index
		select.pressed.connect(func() -> void: _select_armory_weapon(selected_index))
		card.add_child(select)


func _select_armory_weapon(index: int) -> void:
	if index < 0 or index >= armory_entries.size():
		return
	_begin_run(armory_entries[index])


func _weapon_display_name() -> String:
	var blueprint := equipped_entry.get("blueprint") as WeaponBlueprint
	return blueprint.display_name if blueprint != null else str(equipped_entry.get("display_name", "武器"))


func _fire_mode_label(runtime: Dictionary) -> String:
	if bool(runtime.get("automatic_fire", false)):
		return "按住连射"
	var burst_size := int(runtime.get("burst_size", 0))
	return "按一下 %d 连发" % burst_size if burst_size > 1 else "按一下单发"


func _fire_timing_label(runtime: Dictionary) -> String:
	if bool(runtime.get("cycle_required", false)):
		return "%s，总锁定 %.2f 秒" % [
			_cycle_action_label(int(runtime.get("cycle_action_code", 0))),
			RANGED_AXIS_RESOLVER.cycle_lock_total_seconds(runtime),
		]
	return "%.2f 秒/发" % float(runtime.get("shot_interval_seconds", 0.0))


func _cycle_action_label(action_code: int) -> String:
	return str({1: "每发后拉栓", 2: "每发后泵动", 3: "扳机带动转轮"}.get(action_code, "自动完成循环"))


func _shot_pattern_label(runtime: Dictionary) -> String:
	var pellet_count := maxi(1, int(runtime.get("pellet_count", 1)))
	if pellet_count > 1:
		return "每枪 %d 颗霰弹，覆盖 %.0f°" % [
			pellet_count,
			float(runtime.get("pellet_spread_degrees", 0.0)),
		]
	return "每枪 1 颗弹丸"


func _reload_feed_label(runtime: Dictionary) -> String:
	var step_seconds := float(runtime.get("reload_seconds", 0.0))
	var rounds_per_step := maxi(1, int(runtime.get("reload_rounds_per_step", 1)))
	match int(runtime.get("reload_feed_code", 0)):
		1:
			return "逐发装填 %.2f 秒/次，可开枪打断" % step_seconds
		2:
			return "转轮每次装 %d 发，%.2f 秒/次" % [rounds_per_step, step_seconds]
		3:
			return "整箱更换弹链 %.2f 秒" % step_seconds
		_:
			return "整匣更换 %.2f 秒" % step_seconds


func _build_ui() -> void:
	var font := load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var top := ColorRect.new()
	top.position = Vector2(18, 12)
	top.size = Vector2(1244, 116)
	top.color = Color(0.02, 0.05, 0.09, 0.94)
	layer.add_child(top)
	status_label = Label.new()
	status_label.position = Vector2(32, 20)
	status_label.size = Vector2(1214, 100)
	status_label.add_theme_font_override("font", font)
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.add_theme_color_override("font_color", Color("e2e8f0"))
	layer.add_child(status_label)

	weapon_panel = Control.new()
	layer.add_child(weapon_panel)
	var armory_card := ColorRect.new()
	armory_card.position = Vector2(70, 150)
	armory_card.size = Vector2(1140, 516)
	armory_card.color = Color("172535")
	weapon_panel.add_child(armory_card)
	var title := Label.new()
	title.text = "选择你的武器"
	title.position = Vector2(108, 174)
	title.size = Vector2(620, 46)
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 28)
	weapon_panel.add_child(title)
	armory_message = Label.new()
	armory_message.position = Vector2(108, 220)
	armory_message.size = Vector2(900, 52)
	armory_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	armory_message.add_theme_font_override("font", font)
	armory_message.add_theme_font_size_override("font_size", 15)
	weapon_panel.add_child(armory_message)
	var refresh := Button.new()
	refresh.text = "重新读取武器库"
	refresh.position = Vector2(960, 174)
	refresh.size = Vector2(208, 46)
	refresh.add_theme_font_override("font", font)
	refresh.pressed.connect(_show_weapon_picker)
	weapon_panel.add_child(refresh)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(104, 286)
	scroll.size = Vector2(1070, 338)
	weapon_panel.add_child(scroll)
	weapon_list = HBoxContainer.new()
	weapon_list.add_theme_constant_override("separation", 18)
	scroll.add_child(weapon_list)

	combat_controls = Control.new()
	layer.add_child(combat_controls)
	var help := Label.new()
	help.text = "WASD 移动　空格/J 射击　Shift/K 闪避　Esc 返回 Forge"
	help.position = Vector2(38, 680)
	help.size = Vector2(760, 30)
	help.add_theme_font_override("font", font)
	help.add_theme_font_size_override("font_size", 15)
	combat_controls.add_child(help)
	var attack := Button.new()
	attack.text = "射击"
	attack.position = Vector2(1090, 638)
	attack.size = Vector2(126, 62)
	attack.add_theme_font_override("font", font)
	attack.button_down.connect(func() -> void: arena.set_touch_attack(true))
	attack.button_up.connect(func() -> void: arena.set_touch_attack(false))
	combat_controls.add_child(attack)
	var dodge := Button.new()
	dodge.text = "闪避"
	dodge.position = Vector2(940, 650)
	dodge.size = Vector2(122, 50)
	dodge.add_theme_font_override("font", font)
	dodge.pressed.connect(func() -> void: arena.request_touch_dodge())
	combat_controls.add_child(dodge)
	combat_controls.visible = false

	message_panel = Control.new()
	layer.add_child(message_panel)
	var message_card := ColorRect.new()
	message_card.position = Vector2(274, 222)
	message_card.size = Vector2(732, 300)
	message_card.color = Color("172535")
	message_panel.add_child(message_card)
	message_title = Label.new()
	message_title.position = Vector2(316, 258)
	message_title.size = Vector2(648, 48)
	message_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_title.add_theme_font_override("font", font)
	message_title.add_theme_font_size_override("font_size", 30)
	message_panel.add_child(message_title)
	message_body = Label.new()
	message_body.position = Vector2(320, 328)
	message_body.size = Vector2(640, 92)
	message_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_body.add_theme_font_override("font", font)
	message_body.add_theme_font_size_override("font_size", 17)
	message_panel.add_child(message_body)
	primary_button = Button.new()
	primary_button.position = Vector2(380, 442)
	primary_button.size = Vector2(240, 54)
	primary_button.add_theme_font_override("font", font)
	primary_button.add_theme_font_size_override("font_size", 18)
	primary_button.pressed.connect(func() -> void: _begin_run(equipped_entry))
	message_panel.add_child(primary_button)
	secondary_button = Button.new()
	secondary_button.position = Vector2(658, 442)
	secondary_button.size = Vector2(240, 54)
	secondary_button.add_theme_font_override("font", font)
	secondary_button.add_theme_font_size_override("font_size", 18)
	secondary_button.pressed.connect(func() -> void:
		if state == "error":
			get_tree().change_scene_to_file("res://scenes/open_identity_spike.tscn")
		else:
			_show_weapon_picker()
	)
	message_panel.add_child(secondary_button)
	message_panel.visible = false
