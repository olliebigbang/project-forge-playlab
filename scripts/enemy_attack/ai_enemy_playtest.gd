extends Node2D

const ARENA := preload("res://scripts/systems/gameplay_arena.gd")
const PROVIDER := preload("res://scripts/enemy_attack/enemy_ai_blueprint_provider.gd")
const RESOLVER := preload("res://scripts/enemy_attack/enemy_ai_blueprint_resolver.gd")
const MOCK_GENERATOR := preload("res://scripts/services/mock_weapon_image_generator.gd")

var arena: Node2D
var provider: RefCounted = PROVIDER.new()
var weapon_blueprint: WeaponBlueprint
var weapon_asset: WeaponVisualAsset
var current_enemy_blueprint: Dictionary = {}
var current_concept := ""
var state := "input"
var generation_started_msec := 0
var skip_cache := false

var status_label: Label
var input_panel: Control
var concept_input: LineEdit
var generate_button: Button
var input_message: Label


func _ready() -> void:
	_build_weapon_fixture()
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
	var auto_concept := str(options.get("auto_concept", "")).strip_edges()
	if not auto_concept.is_empty():
		concept_input.text = auto_concept
		_begin_generation()
	else:
		_show_input()


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
	elif event.physical_keycode == KEY_ESCAPE:
		if state == "generating":
			provider.cancel_current()
			_show_input()
		elif state == "combat":
			_show_input()
		else:
			get_tree().quit()


func _begin_generation() -> void:
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
	current_enemy_blueprint = profile.duplicate(true)
	state = "combat"
	input_panel.visible = false
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
	provider.cancel_current()
	state = "input"
	arena.stop()
	arena.visible = false
	input_panel.visible = true
	generate_button.disabled = false
	generate_button.text = "AI 生成并开战"
	input_message.text = "只描述敌人是什么；AI 自动决定身体、攻击、锁定、节奏和恢复。"
	status_label.text = "AI 敌人生成器\n输入任意敌人概念，生成完成后直接进入战斗。"
	concept_input.grab_focus()


func _show_input_error(message: String) -> void:
	state = "input"
	arena.stop()
	arena.visible = false
	input_panel.visible = true
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
		"%s · %s\n" % [
			str(current_enemy_blueprint.get("display_name", "AI 敌人")),
			str(current_enemy_blueprint.get("battle_role_zh", "")),
		]
		+ "AI 攻击：%s　|　状态：%s\n" % ["、".join(attack_labels), "　".join(phase_lines)]
		+ "WASD 移动　空格/J 射击　Shift/K 闪避　R 重开　N 换敌人　Esc 返回"
	)


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
