extends Node2D

const ARENA := preload("res://scripts/systems/gameplay_arena.gd")
const PROVIDER := preload("res://scripts/enemy_attack/enemy_ai_blueprint_provider.gd")
const RESOLVER := preload("res://scripts/enemy_attack/enemy_ai_blueprint_resolver.gd")
const MOCK_GENERATOR := preload("res://scripts/services/mock_weapon_image_generator.gd")
const PLAYER_ARMORY := preload("res://scripts/combat_feel/player_weapon_armory.gd")
const RANGED_AXIS_RESOLVER := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")

var arena: Node2D
var provider: RefCounted = PROVIDER.new()
var armory: RefCounted = PLAYER_ARMORY.new()
var armory_entries: Array[Dictionary] = []
var weapon_blueprint: WeaponBlueprint
var weapon_asset: WeaponVisualAsset
var current_enemy_blueprint: Dictionary = {}
var current_concept := ""
var state := "input"
var generation_started_msec := 0
var skip_cache := false
var pending_auto_concept := ""

var status_label: Label
var input_panel: Control
var weapon_panel: Control
var weapon_list: HBoxContainer
var armory_message: Label
var concept_input: LineEdit
var generate_button: Button
var input_message: Label
var selected_weapon_label: Label


func _ready() -> void:
	arena = ARENA.new()
	arena.visible = false
	arena.stage_completed.connect(_on_stage_completed)
	add_child(arena)
	_build_ui()
	var options := _command_line_options()
	skip_cache = bool(options.get("skip_cache", false))
	provider.offline_fixture_path = str(options.get("offline_fixture", ""))
	var configured: Dictionary = provider.configure(str(options.get("python", "python")))
	if not bool(configured.get("ok", false)):
		_show_input_error(str(configured.get("error", "AI_ENEMY_PROVIDER_CONFIG_FAILED")))
		return
	pending_auto_concept = str(options.get("auto_concept", "")).strip_edges()
	if _take_ranged_handoff():
		_continue_after_weapon_selection()
		return
	armory_entries = armory.load_entries()
	_show_weapon_picker()


func _take_ranged_handoff() -> bool:
	var handoff: Node = get_node_or_null("/root/MechanismHandoff")
	if handoff == null or not handoff.has_method("take_ranged"):
		return false
	var payload: Dictionary = handoff.call("take_ranged") as Dictionary
	if payload.is_empty():
		return false
	return _equip_weapon(
		payload.get("blueprint") as WeaponBlueprint,
		payload.get("asset") as WeaponVisualAsset,
		payload.get("ranged_runtime_profile", {}) as Dictionary
	)


func _equip_weapon(
	blueprint: WeaponBlueprint,
	asset: WeaponVisualAsset,
	runtime_profile: Dictionary
) -> bool:
	if blueprint == null or asset == null or not bool(runtime_profile.get("ok", false)):
		return false
	weapon_blueprint = blueprint
	weapon_asset = asset
	weapon_blueprint.modifiers["ranged_runtime_profile"] = runtime_profile.duplicate(true)
	if selected_weapon_label != null:
		selected_weapon_label.text = "当前武器：%s" % weapon_blueprint.display_name
	return true


func _continue_after_weapon_selection() -> void:
	if not pending_auto_concept.is_empty():
		concept_input.text = pending_auto_concept
		pending_auto_concept = ""
		_begin_generation()
		return
	_show_input()


func _select_armory_weapon(index: int) -> void:
	if index < 0 or index >= armory_entries.size():
		return
	var entry := armory_entries[index]
	if not _equip_weapon(
		entry.get("blueprint") as WeaponBlueprint,
		entry.get("asset") as WeaponVisualAsset,
		entry.get("ranged_runtime_profile", {}) as Dictionary
	):
		armory_message.text = "这把枪的图片或机制卡已经损坏，未装备。"
		return
	_continue_after_weapon_selection()


func _use_developer_weapon_fixture() -> void:
	_build_weapon_fixture()
	if weapon_blueprint == null or weapon_asset == null:
		armory_message.text = "开发测试枪创建失败。"
		return
	var runtime: Dictionary = weapon_blueprint.modifiers.get("ranged_runtime_profile", {}) as Dictionary
	if runtime.is_empty():
		runtime = RANGED_AXIS_RESOLVER.compile(
			weapon_blueprint.affordance,
			weapon_blueprint.affordance_source
		)
	_equip_weapon(weapon_blueprint, weapon_asset, runtime)
	_continue_after_weapon_selection()


func _process(_delta: float) -> void:
	if state == "generating":
		var elapsed := float(Time.get_ticks_msec() - generation_started_msec) / 1000.0
		status_label.text = (
			"AI 敌人生成器\n"
			+ "正在把“%s”编译成外观、两套攻击和选择规则…… %.1f 秒\n" % [current_concept, elapsed]
			+ "玩家不需要决定敌人怎么打；AI 输出后由 Godot 严格检查。"
		)
		var result: Dictionary = provider.poll()
		if str(result.get("status", "")) == "success":
			_accept_generation(result)
		elif str(result.get("status", "")) == "failed":
			_show_input_error(_friendly_error(str(result.get("error", "AI_ENEMY_GENERATION_FAILED"))))
	elif state == "combat" and not current_enemy_blueprint.is_empty():
		_update_combat_status()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_R and state == "combat":
		_start_combat(current_enemy_blueprint)
	elif event.physical_keycode == KEY_N and state in ["combat", "complete"]:
		_show_input()
	elif event.physical_keycode == KEY_B and state in ["input", "combat", "complete"]:
		_show_weapon_picker()
	elif event.physical_keycode == KEY_ESCAPE:
		if state == "generating":
			provider.cancel_current()
			_show_input()
		elif state == "combat":
			_show_input()
		else:
			get_tree().quit()


func _begin_generation() -> void:
	if weapon_blueprint == null or weapon_asset == null:
		_show_weapon_picker()
		return
	var concept := concept_input.text.strip_edges()
	if concept.is_empty() or concept.length() > 160:
		_show_input_error("请输入 1—160 个字符的敌人概念。")
		return
	current_concept = concept
	if not skip_cache and provider.offline_fixture_path.is_empty():
		var cached: Dictionary = RESOLVER.resolve_cached(concept)
		if bool(cached.get("ok", false)):
			_start_combat(cached)
			return
	state = "generating"
	input_panel.visible = false
	weapon_panel.visible = false
	arena.visible = false
	generation_started_msec = Time.get_ticks_msec()
	provider.request_blueprint(concept)


func _accept_generation(result: Dictionary) -> void:
	var accepted: Dictionary = RESOLVER.accept_ai_response(
		current_concept,
		result.get("response", {}) as Dictionary,
		str(result.get("source", "AI_ENEMY_UNKNOWN")),
		provider.offline_fixture_path.is_empty()
	)
	if not bool(accepted.get("ok", false)):
		_show_input_error(_friendly_error(str(accepted.get("error", "AI_ENEMY_BLUEPRINT_REJECTED"))))
		return
	_start_combat(accepted)


func _start_combat(profile: Dictionary) -> void:
	if weapon_blueprint == null or weapon_asset == null:
		_show_weapon_picker()
		return
	current_enemy_blueprint = profile.duplicate(true)
	state = "combat"
	input_panel.visible = false
	weapon_panel.visible = false
	arena.visible = true
	var enemy_blueprints: Array[Dictionary] = [current_enemy_blueprint]
	arena.start_stage("ai_enemy", weapon_blueprint, weapon_asset, enemy_blueprints)
	_update_combat_status()
	print("AI_ENEMY_PLAYTEST_COMBAT_READY name=%s attacks=%d" % [
		str(current_enemy_blueprint.get("display_name", "AI 敌人")),
		(current_enemy_blueprint.get("attack_declarations", []) as Array).size(),
	])


func _on_stage_completed(_stage_name: String, _metrics: Dictionary) -> void:
	state = "complete"
	arena.visible = false
	input_panel.visible = true
	generate_button.text = "AI 生成下一个敌人"
	input_message.text = "已击败“%s”。修改上面的描述可生成另一个敌人。" % str(current_enemy_blueprint.get("display_name", "AI 敌人"))
	status_label.text = "战斗完成\nEnter 或按钮：生成下一个敌人　Esc：退出"
	concept_input.grab_focus()


func _show_input() -> void:
	if weapon_blueprint == null or weapon_asset == null:
		_show_weapon_picker()
		return
	provider.cancel_current()
	state = "input"
	arena.stop()
	arena.visible = false
	input_panel.visible = true
	weapon_panel.visible = false
	generate_button.disabled = false
	generate_button.text = "AI 生成并开战"
	input_message.text = "只描述敌人是什么；AI 自动决定身体、攻击、锁定、节奏和恢复。"
	status_label.text = "AI 敌人生成器 · 当前武器：%s\n输入任意敌人概念，生成完成后直接进入战斗。" % weapon_blueprint.display_name
	concept_input.grab_focus()


func _show_input_error(message: String) -> void:
	state = "input"
	arena.stop()
	arena.visible = false
	input_panel.visible = true
	weapon_panel.visible = false
	generate_button.disabled = false
	input_message.text = message
	status_label.text = "生成没有通过本地检查\n请直接换一个敌人描述或重试；不需要填写战斗参数。"
	concept_input.grab_focus()


func _update_combat_status() -> void:
	var attack_labels := current_enemy_blueprint.get("attack_labels_zh", []) as Array
	var phase_lines: Array[String] = []
	for enemy: Dictionary in arena.enemies:
		var runtime: Variant = enemy.get("attack_runtime", null)
		var delivery := "none"
		var phase := str(enemy.get("attack_phase", "idle"))
		if runtime != null and runtime.is_running():
			delivery = runtime.current_delivery()
			phase = str(runtime.phase)
		phase_lines.append("%s/%s" % [phase, delivery])
	status_label.text = (
		"%s · %s　|　玩家武器：%s\n" % [
			str(current_enemy_blueprint.get("display_name", "AI 敌人")),
			str(current_enemy_blueprint.get("battle_role_zh", "")),
			weapon_blueprint.display_name if weapon_blueprint != null else "未装备",
		]
		+ "AI 攻击：%s　|　状态：%s\n" % ["、".join(attack_labels), "　".join(phase_lines)]
		+ "WASD 移动　空格/J 射击　Shift/K 闪避　R 重开　N 换敌人　B 换武器　Esc 返回"
	)


func _show_weapon_picker() -> void:
	provider.cancel_current()
	state = "weapon_select"
	if arena != null:
		arena.stop()
		arena.visible = false
	input_panel.visible = false
	weapon_panel.visible = true
	armory_entries = armory.load_entries()
	_rebuild_weapon_cards()
	if armory_entries.is_empty():
		armory_message.text = "还没有通过检查的 AI 枪械缓存。请先从 Forge 生成一把枪；下面的加特林只用于开发测试。"
	else:
		armory_message.text = "选择一把已经生成成功的枪。读取缓存不会调用 FAL，也不会产生新的图片费用。"
	status_label.text = "玩家武器库\n先选武器，再输入或生成敌人。每把枪保留自己的射击机制。"
	var names: Array[String] = []
	for entry: Dictionary in armory_entries:
		names.append(str(entry.get("display_name", "未知武器")))
	print("PLAYER_ARMORY_READY entries=%d names=%s" % [armory_entries.size(), ",".join(names)])


func _rebuild_weapon_cards() -> void:
	for child: Node in weapon_list.get_children():
		weapon_list.remove_child(child)
		child.queue_free()
	for index: int in range(armory_entries.size()):
		var entry := armory_entries[index]
		var blueprint := entry.get("blueprint") as WeaponBlueprint
		var asset := entry.get("asset") as WeaponVisualAsset
		var runtime := entry.get("ranged_runtime_profile", {}) as Dictionary
		if blueprint == null or asset == null:
			continue
		var card := VBoxContainer.new()
		card.custom_minimum_size = Vector2(220, 310)
		card.add_theme_constant_override("separation", 8)
		weapon_list.add_child(card)
		var preview := TextureRect.new()
		preview.custom_minimum_size = Vector2(210, 120)
		preview.texture = asset.texture
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		card.add_child(preview)
		var name_label := Label.new()
		name_label.text = blueprint.display_name
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_override("font", load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font)
		name_label.add_theme_font_size_override("font_size", 19)
		card.add_child(name_label)
		var mechanism := Label.new()
		mechanism.text = "%s　%s\n后坐 %.1f　伤害 %.1f　弹匣 %d%s" % [
			_ranged_fire_mode_label(runtime),
			_ranged_timing_label(runtime),
			float(runtime.get("recoil_pixels", 0.0)),
			float(runtime.get("projectile_damage", 0.0)),
			int(runtime.get("magazine_size", 0)),
			"\n旧版机制轴已自动迁移" if bool(entry.get("legacy_axis_migration", false)) else "",
		]
		mechanism.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mechanism.add_theme_font_override("font", load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font)
		mechanism.add_theme_font_size_override("font_size", 14)
		mechanism.modulate = Color("bae6fd")
		card.add_child(mechanism)
		var equip := Button.new()
		equip.text = "装备这把枪"
		equip.custom_minimum_size = Vector2(200, 48)
		equip.add_theme_font_override("font", load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font)
		var selected_index := index
		equip.pressed.connect(func() -> void: _select_armory_weapon(selected_index))
		card.add_child(equip)


func _ranged_fire_mode_label(runtime: Dictionary) -> String:
	if bool(runtime.get("manual_cycle_required", false)):
		return "按一下单发，随后自动拉栓"
	if bool(runtime.get("automatic_fire", false)):
		return "按住连射"
	var burst_size := int(runtime.get("burst_size", 0))
	if burst_size > 1:
		return "按一下 %d 连发" % burst_size
	return "按一下单发"


func _ranged_timing_label(runtime: Dictionary) -> String:
	if bool(runtime.get("manual_cycle_required", false)):
		return "拉栓锁定 %.2f 秒" % float(runtime.get("manual_cycle_lock_seconds", 0.0))
	return "%.2f 秒/发" % float(runtime.get("shot_interval_seconds", 0.0))


func _build_weapon_fixture() -> void:
	weapon_blueprint = WeaponBlueprint.fixed_blueprint("gatling")
	weapon_blueprint.display_name = "AI 敌人测试步枪"
	weapon_blueprint.effect_type = "ballistic_projectile"
	weapon_blueprint.affordance = _playtest_firearm_axes()
	weapon_blueprint.affordance_source = "AI_ENEMY_PLAYTEST_WEAPON_FIXTURE"
	var generated: Dictionary = MOCK_GENERATOR.new().generate(weapon_blueprint)
	if not bool(generated.get("ok", false)):
		push_error("AI_ENEMY_PLAYTEST_WEAPON_FAILED")
		return
	weapon_asset = generated.get("asset") as WeaponVisualAsset


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var top_panel := ColorRect.new()
	top_panel.position = Vector2(18, 14)
	top_panel.size = Vector2(1244, 92)
	top_panel.color = Color(0.02, 0.05, 0.09, 0.90)
	layer.add_child(top_panel)
	status_label = Label.new()
	status_label.position = Vector2(30, 22)
	status_label.size = Vector2(1220, 80)
	status_label.add_theme_font_override("font", load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font)
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.add_theme_color_override("font_color", Color("e2e8f0"))
	layer.add_child(status_label)

	weapon_panel = Control.new()
	layer.add_child(weapon_panel)
	var armory_card := ColorRect.new()
	armory_card.position = Vector2(70, 132)
	armory_card.size = Vector2(1140, 540)
	armory_card.color = Color("172535")
	weapon_panel.add_child(armory_card)
	var armory_title := Label.new()
	armory_title.text = "选择玩家武器"
	armory_title.position = Vector2(108, 158)
	armory_title.size = Vector2(620, 48)
	armory_title.add_theme_font_override("font", load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font)
	armory_title.add_theme_font_size_override("font_size", 28)
	weapon_panel.add_child(armory_title)
	armory_message = Label.new()
	armory_message.position = Vector2(108, 204)
	armory_message.size = Vector2(850, 46)
	armory_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	armory_message.add_theme_font_override("font", load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font)
	armory_message.add_theme_font_size_override("font_size", 15)
	weapon_panel.add_child(armory_message)
	var refresh_button := Button.new()
	refresh_button.text = "重新读取缓存"
	refresh_button.position = Vector2(970, 158)
	refresh_button.size = Vector2(190, 46)
	refresh_button.add_theme_font_override("font", load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font)
	refresh_button.pressed.connect(_show_weapon_picker)
	weapon_panel.add_child(refresh_button)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(104, 260)
	scroll.size = Vector2(1070, 325)
	weapon_panel.add_child(scroll)
	weapon_list = HBoxContainer.new()
	weapon_list.add_theme_constant_override("separation", 18)
	scroll.add_child(weapon_list)
	var fixture_button := Button.new()
	fixture_button.text = "仅开发测试：使用加特林"
	fixture_button.position = Vector2(910, 608)
	fixture_button.size = Vector2(264, 42)
	fixture_button.add_theme_font_override("font", load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font)
	fixture_button.pressed.connect(_use_developer_weapon_fixture)
	weapon_panel.add_child(fixture_button)
	weapon_panel.visible = false

	input_panel = Control.new()
	layer.add_child(input_panel)
	var card := ColorRect.new()
	card.position = Vector2(226, 180)
	card.size = Vector2(828, 340)
	card.color = Color("172535")
	input_panel.add_child(card)
	var title := Label.new()
	title.text = "描述一个敌人"
	title.position = Vector2(270, 215)
	title.size = Vector2(740, 50)
	title.add_theme_font_override("font", load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font)
	title.add_theme_font_size_override("font_size", 30)
	input_panel.add_child(title)
	concept_input = LineEdit.new()
	concept_input.position = Vector2(270, 282)
	concept_input.size = Vector2(740, 58)
	concept_input.text = "机械蜘蛛"
	concept_input.placeholder_text = "例如：机械蜘蛛、火焰祭司、冰霜攻城兽"
	concept_input.add_theme_font_override("font", load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font)
	concept_input.add_theme_font_size_override("font_size", 20)
	concept_input.text_submitted.connect(func(_text: String) -> void: _begin_generation())
	input_panel.add_child(concept_input)
	generate_button = Button.new()
	generate_button.text = "AI 生成并开战"
	generate_button.position = Vector2(270, 360)
	generate_button.size = Vector2(250, 58)
	generate_button.add_theme_font_override("font", load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font)
	generate_button.add_theme_font_size_override("font_size", 18)
	generate_button.pressed.connect(_begin_generation)
	input_panel.add_child(generate_button)
	var change_weapon_button := Button.new()
	change_weapon_button.text = "更换玩家武器"
	change_weapon_button.position = Vector2(540, 360)
	change_weapon_button.size = Vector2(190, 58)
	change_weapon_button.add_theme_font_override("font", load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font)
	change_weapon_button.add_theme_font_size_override("font_size", 17)
	change_weapon_button.pressed.connect(_show_weapon_picker)
	input_panel.add_child(change_weapon_button)
	selected_weapon_label = Label.new()
	selected_weapon_label.text = "当前武器：未选择"
	selected_weapon_label.position = Vector2(750, 360)
	selected_weapon_label.size = Vector2(260, 58)
	selected_weapon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	selected_weapon_label.add_theme_font_override("font", load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font)
	selected_weapon_label.add_theme_font_size_override("font_size", 15)
	input_panel.add_child(selected_weapon_label)
	input_message = Label.new()
	input_message.position = Vector2(270, 438)
	input_message.size = Vector2(740, 52)
	input_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	input_message.add_theme_font_override("font", load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font)
	input_message.add_theme_font_size_override("font_size", 16)
	input_panel.add_child(input_message)


func _command_line_options() -> Dictionary:
	var options := {"python": "python", "offline_fixture": "", "auto_concept": "", "skip_cache": false}
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--enemy-ai-python="):
			options["python"] = argument.trim_prefix("--enemy-ai-python=")
		elif argument.begins_with("--enemy-ai-fixture="):
			options["offline_fixture"] = argument.trim_prefix("--enemy-ai-fixture=")
		elif argument.begins_with("--auto-enemy="):
			options["auto_concept"] = argument.trim_prefix("--auto-enemy=")
		elif argument == "--skip-enemy-cache":
			options["skip_cache"] = true
	return options


func _friendly_error(code: String) -> String:
	if code.contains("MISSING_API_KEY"):
		return "AI 密钥没有传入游戏进程，请使用 AI 敌人试玩启动脚本。"
	if code.contains("TIMEOUT"):
		return "AI 请求超时，没有采用不完整结果。可以直接重试。"
	if code.contains("HTTP_429"):
		return "AI 服务当前繁忙，没有采用不完整结果。稍后可直接重试。"
	return "AI 输出未通过严格检查：%s" % code


func _playtest_firearm_axes() -> Dictionary:
	return {
		"weapon_domain": "handheld_firearm", "layout": "conventional_rifle",
		"stock_structure": "fixed", "feed_position": "ahead_of_grip",
		"magazine_shape": "curved", "barrel_length": "medium", "upper_profile": "top_rail",
		"support_mode": "two_hand_shouldered", "fire_control": "select_fire_auto",
		"cadence": "balanced", "recoil": "medium", "recoil_recovery": "balanced",
		"muzzle_climb": "medium", "accuracy": "controlled", "impact_force": "medium",
		"penetration": "medium", "reload": "standard", "effective_range": "long",
		"handling": "balanced", "magazine_capacity": "standard", "confidence": 0.99,
	}
