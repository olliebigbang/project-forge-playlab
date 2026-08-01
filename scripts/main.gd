extends Node2D

const MOCK_INTERPRETER := preload("res://scripts/services/mock_weapon_interpreter.gd")
const MOCK_IMAGE_GENERATOR := preload("res://scripts/services/mock_weapon_image_generator.gd")
const SKETCH_CANVAS := preload("res://scripts/ui/sketch_canvas.gd")
const WEAPON_PREVIEW := preload("res://scripts/ui/weapon_preview.gd")
const TOUCH_STICK := preload("res://scripts/ui/touch_stick.gd")
const GAMEPLAY_ARENA := preload("res://scripts/systems/gameplay_arena.gd")
const EVENT_LOGGER := preload("res://scripts/systems/event_logger.gd")
const FLOW_POLICY := preload("res://scripts/systems/flow_policy.gd")
const ANCHOR_RESOLVER := preload("res://scripts/systems/anchor_resolver.gd")

var interpreter := MOCK_INTERPRETER.new() as MockWeaponInterpreter
var image_generator := MOCK_IMAGE_GENERATOR.new() as MockWeaponImageGenerator
var logger := EVENT_LOGGER.new() as PlaylabEventLogger
var flow_policy := FLOW_POLICY.new() as FlowPolicy
var ui_layer: CanvasLayer
var page: Control
var arena: GameplayArena
var input_mode := "description_sketch"
var description_edit: TextEdit
var sketch_canvas: SketchCanvas
var error_label: Label
var current_blueprint: WeaponBlueprint
var current_asset: WeaponVisualAsset
var current_explanation := ""
var saved_description := ""
var saved_geometry: Dictionary = {}
var saved_sketch_png := PackedByteArray()
var clarification_used := false
var initial_change_used := false
var first_generation_msec := 0
var state := "forge"
var hud_stats: Label
var capture_mode := ""
var app_theme: Theme

func _ready() -> void:
	randomize()
	_build_theme()
	arena = GAMEPLAY_ARENA.new() as GameplayArena
	add_child(arena)
	arena.visible = false
	arena.stage_completed.connect(_on_stage_completed)
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	logger.log_event("session_started", {"build": "v1", "offline": true})
	capture_mode = _capture_argument()
	match capture_mode:
		"gallery": _show_gallery()
		"anchors":
			_prepare_fixed("gatling")
			_show_anchor_debug()
		"holding":
			_prepare_fixed("greatsword")
			_start_gameplay("training", false)
		"muzzle":
			_prepare_fixed("gatling")
			_start_gameplay("training", true)
			arena.set_touch_attack(true)
		_: _show_forge()

func _process(_delta: float) -> void:
	# Defensive idempotent guard for room completion while the HUD page is replaced.
	if state in ["room_1", "room_2"] and not arena.active and arena.enemies.is_empty():
		var completed_state := state
		state = "transitioning"
		_on_stage_completed(completed_state, arena.metrics.duplicate(true))

func _build_theme() -> void:
	var theme := Theme.new()
	var cjk_font := load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font
	theme.default_font = cjk_font
	theme.default_font_size = 18
	theme.set_color("font_color", "Label", Color("e5edf7"))
	theme.set_color("font_color", "Button", Color("f8fafc"))
	theme.set_color("font_color", "LineEdit", Color("111827"))
	theme.set_color("font_color", "TextEdit", Color("111827"))
	var button_box := StyleBoxFlat.new()
	button_box.bg_color = Color("2563a8")
	button_box.corner_radius_top_left = 8
	button_box.corner_radius_top_right = 8
	button_box.corner_radius_bottom_left = 8
	button_box.corner_radius_bottom_right = 8
	button_box.content_margin_left = 16
	button_box.content_margin_right = 16
	button_box.content_margin_top = 10
	button_box.content_margin_bottom = 10
	theme.set_stylebox("normal", "Button", button_box)
	var hover := button_box.duplicate() as StyleBoxFlat
	hover.bg_color = Color("3182ce")
	theme.set_stylebox("hover", "Button", hover)
	var pressed := button_box.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("164e75")
	theme.set_stylebox("pressed", "Button", pressed)
	var field_box := StyleBoxFlat.new()
	field_box.bg_color = Color("f8fafc")
	field_box.corner_radius_top_left = 6
	field_box.corner_radius_top_right = 6
	field_box.corner_radius_bottom_left = 6
	field_box.corner_radius_bottom_right = 6
	field_box.content_margin_left = 10
	field_box.content_margin_right = 10
	field_box.content_margin_top = 8
	field_box.content_margin_bottom = 8
	theme.set_stylebox("normal", "LineEdit", field_box)
	theme.set_stylebox("normal", "TextEdit", field_box)
	app_theme = theme
	RenderingServer.set_default_clear_color(Color("07111f"))
	set_process(true)

func _show_forge() -> void:
	state = "forge"
	flow_policy.in_combat = false
	arena.visible = false
	arena.stop()
	var root := _new_page()
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	root.add_child(outer)
	outer.add_child(_header("FORGE PLAYLAB V1", "一句话、一张粗草图，或两者一起。离线 Mock，不会上传内容。"))
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 10)
	outer.add_child(modes)
	for pair: Array in [["只描述", "description"], ["草图 + 描述（推荐）", "description_sketch"], ["只画草图", "sketch"]]:
		var mode_button := _button(pair[0], func() -> void: _set_input_mode(pair[1]))
		modes.add_child(mode_button)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 22)
	outer.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(530, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	left.add_child(_section_title("描述你的武器幻想"))
	description_edit = TextEdit.new()
	description_edit.custom_minimum_size = Vector2(0, 145)
	description_edit.placeholder_text = "例如：一把冒蓝火的重型加特林。"
	description_edit.text = saved_description if not saved_description.is_empty() else "一把冒蓝火的重型加特林。"
	description_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	left.add_child(description_edit)
	var note := Label.new()
	note.text = "草图只影响轮廓、比例与重心，不决定伤害或战斗数值。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color("94a3b8")
	left.add_child(note)
	var local_badge := _badge("LOCAL MOCK · 无网络 · 无密钥 · 无付费调用", Color("164e63"))
	left.add_child(local_badge)
	error_label = Label.new()
	error_label.modulate = Color("fca5a5")
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(error_label)
	left.add_spacer(false)
	var forge_actions := HBoxContainer.new()
	forge_actions.add_theme_constant_override("separation", 10)
	left.add_child(forge_actions)
	forge_actions.add_child(_button("开始锻造", _submit_forge, true))
	forge_actions.add_child(_button("开发者武器画廊", _show_gallery))
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(500, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	var sketch_title := HBoxContainer.new()
	right.add_child(sketch_title)
	var title_label := _section_title("512 × 512 意图草图")
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sketch_title.add_child(title_label)
	sketch_title.add_child(_button("撤销一步", func() -> void: sketch_canvas.undo_last()))
	sketch_title.add_child(_button("清除", func() -> void: sketch_canvas.clear_strokes()))
	sketch_canvas = SKETCH_CANVAS.new() as SketchCanvas
	sketch_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(sketch_canvas)

func _set_input_mode(next_mode: String) -> void:
	input_mode = next_mode
	if error_label != null:
		var names := {"description": "只描述", "description_sketch": "草图 + 描述", "sketch": "只画草图"}
		error_label.text = "已选择：%s" % names[next_mode]
	logger.log_event("input_mode_selected", {"mode": next_mode})

func _submit_forge() -> void:
	if description_edit == null or sketch_canvas == null:
		return
	saved_description = description_edit.text.strip_edges()
	saved_geometry = sketch_canvas.geometry_summary()
	saved_sketch_png = saved_geometry.get("preview_png", PackedByteArray())
	var has_description := not saved_description.is_empty()
	var has_sketch := int(saved_geometry.get("stroke_count", 0)) > 0
	if input_mode == "description" and not has_description:
		_show_error("请写下一句武器描述。")
		return
	if input_mode == "sketch" and not has_sketch:
		_show_error("请先画一笔；画得粗糙完全没关系。")
		return
	if input_mode == "description_sketch" and not (has_description and has_sketch):
		_show_error("推荐模式需要一句描述和至少一笔草图；也可以切换到单一输入模式。")
		return
	logger.log_event("description_submitted", {"character_count": saved_description.length(), "input_mode": input_mode})
	if has_sketch:
		logger.log_event("sketch_completed", {
			"stroke_count": saved_geometry.get("stroke_count", 0),
			"aspect_ratio": saved_geometry.get("aspect_ratio", 1.0),
			"ink_coverage": saved_geometry.get("ink_coverage", 0.0)
		})
	var result: Dictionary = interpreter.interpret(saved_description, saved_sketch_png, saved_geometry)
	if not bool(result.get("ok", false)):
		_show_generation_failure(str(result.get("error", "UNKNOWN_INTERPRETER_ERROR")))
		return
	if bool(result.get("needs_clarification", false)) and not clarification_used:
		clarification_used = true
		logger.log_event("clarification_shown", {"confidence": result.get("confidence", 0.0)})
		_show_clarification(str(result["question"]))
		return
	_finish_interpretation(result)

func _show_clarification(question: String) -> void:
	state = "clarification"
	var root := _new_page()
	var card := _center_card(760, 420)
	root.add_child(card)
	var content := card.get_child(0) as VBoxContainer
	content.add_child(_badge("只问这一次", Color("7c3aed")))
	content.add_child(_large_label(question, 30))
	var hint := Label.new()
	hint.text = "你的草图已保留。回答后不会继续追问。"
	hint.modulate = Color("cbd5e1")
	content.add_child(hint)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	content.add_child(actions)
	actions.add_child(_button("近距离挥砍", func() -> void: _answer_clarification("近距离挥砍"), true))
	actions.add_child(_button("飞出去攻击", func() -> void: _answer_clarification("飞出去攻击"), true))

func _answer_clarification(answer: String) -> void:
	logger.log_event("clarification_answered", {"answer_category": "melee" if answer.contains("近") else "thrown"})
	var result: Dictionary = interpreter.interpret(saved_description, saved_sketch_png, saved_geometry, null, "", answer)
	if not bool(result.get("ok", false)):
		_show_generation_failure(str(result.get("error", "UNKNOWN_INTERPRETER_ERROR")))
		return
	_finish_interpretation(result)

func _finish_interpretation(result: Dictionary) -> void:
	current_blueprint = result.get("blueprint") as WeaponBlueprint
	if current_blueprint == null:
		_show_generation_failure("NO_BLUEPRINT_RETURNED")
		return
	current_explanation = str(result.get("explanation", ""))
	logger.log_event("blueprint_created", {"weapon_id": current_blueprint.id, "confidence": current_blueprint.confidence})
	var visual: Dictionary = image_generator.generate(current_blueprint, null, saved_geometry)
	if not bool(visual.get("ok", false)):
		_show_generation_failure(str(visual.get("error", "UNKNOWN_VISUAL_ERROR")))
		return
	current_asset = visual.get("asset") as WeaponVisualAsset
	first_generation_msec = logger.started_msec if first_generation_msec == 0 else first_generation_msec
	logger.log_event("visual_created", {"weapon_id": current_blueprint.id, "generator": "local_procedural"})
	logger.log_event("anchors_resolved", {
		"confidence": current_asset.anchor_confidence, "source": current_asset.anchor_source,
		"first_weapon_generation_ms": Time.get_ticks_msec() - logger.started_msec
	})
	_show_review()

func _show_review() -> void:
	state = "review"
	var root := _new_page()
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	root.add_child(outer)
	outer.add_child(_header("锻造解释", "玩家可见描述只来自受支持标签；内部枚举不会显示。"))
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 24)
	outer.add_child(columns)
	var preview := WEAPON_PREVIEW.new() as WeaponPreview
	preview.custom_minimum_size = Vector2(520, 440)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.configure(current_asset, false, false, current_blueprint.display_name)
	columns.add_child(preview)
	var details := VBoxContainer.new()
	details.custom_minimum_size = Vector2(560, 0)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(details)
	details.add_child(_badge("LOCAL SAMPLE · 程序化像素武器", Color("164e63")))
	details.add_child(_large_label(current_blueprint.display_name, 34))
	var explanation := Label.new()
	explanation.text = current_explanation
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.custom_minimum_size = Vector2(0, 100)
	details.add_child(explanation)
	var strengths := Label.new()
	strengths.text = _player_facing_traits(current_blueprint)
	strengths.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	strengths.modulate = Color("bae6fd")
	details.add_child(strengths)
	var modification := LineEdit.new()
	modification.placeholder_text = "可选：首次确认前修改一次，例如“增加穿透”"
	details.add_child(modification)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	details.add_child(actions)
	actions.add_child(_button("确认并试武器", _confirm_weapon, true))
	actions.add_child(_button("应用一次修改", func() -> void: _apply_initial_change(modification.text)))
	details.add_child(_button("开发者锚点调试", _show_anchor_debug))

func _apply_initial_change(request: String) -> void:
	if initial_change_used:
		_show_transient_message("首次确认前的修改已经使用。")
		return
	if request.strip_edges().is_empty():
		_show_transient_message("请先写下要改变的地方。")
		return
	initial_change_used = true
	var result: Dictionary = interpreter.apply_delta(current_blueprint, request)
	if not bool(result.get("ok", false)):
		_show_generation_failure("BLUEPRINT_DELTA_REJECTED")
		return
	current_blueprint = result["blueprint"] as WeaponBlueprint
	current_explanation = str(result["explanation"])
	var visual: Dictionary = image_generator.generate(current_blueprint, null, saved_geometry)
	current_asset = visual["asset"] as WeaponVisualAsset
	_show_review()

func _confirm_weapon() -> void:
	logger.log_event("weapon_confirmed", {"weapon_id": current_blueprint.id})
	_start_gameplay("training")

func _start_gameplay(stage_name: String, debug: bool = false) -> void:
	state = stage_name
	flow_policy.in_combat = stage_name != "training"
	var root := _new_page(16)
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay)
	arena.visible = true
	arena.debug_anchors = debug
	arena.start_stage(stage_name, current_blueprint, current_asset)
	var top := HBoxContainer.new()
	top.position = Vector2(24, 16)
	top.size = Vector2(1232, 84)
	top.mouse_filter = Control.MOUSE_FILTER_PASS
	overlay.add_child(top)
	var title := Label.new()
	title.text = _stage_title(stage_name)
	title.add_theme_font_size_override("font_size", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	hud_stats = Label.new()
	hud_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud_stats.custom_minimum_size = Vector2(390, 0)
	top.add_child(hud_stats)
	if stage_name == "training":
		top.add_child(_button("进入房间一", _finish_training, true))
	elif not capture_mode.is_empty():
		top.add_child(_badge("截图验证模式", Color("7c3aed")))
	var help := Label.new()
	help.text = "WASD / 方向键移动 · Space / J 攻击 · Shift / K 闪避 · F3 锚点"
	help.position = Vector2(34, 91)
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(help)
	var stick := TOUCH_STICK.new() as TouchStick
	stick.position = Vector2(48, 548)
	stick.vector_changed.connect(arena.set_touch_vector)
	overlay.add_child(stick)
	var attack := Button.new()
	attack.text = "攻击"
	attack.position = Vector2(1082, 574)
	attack.size = Vector2(126, 62)
	attack.button_down.connect(func() -> void: arena.set_touch_attack(true))
	attack.button_up.connect(func() -> void: arena.set_touch_attack(false))
	overlay.add_child(attack)
	var dodge := Button.new()
	dodge.text = "闪避"
	dodge.position = Vector2(930, 604)
	dodge.size = Vector2(122, 54)
	dodge.pressed.connect(arena.request_touch_dodge)
	overlay.add_child(dodge)
	if not arena.metrics_changed.is_connected(_update_hud):
		arena.metrics_changed.connect(_update_hud)
	_update_hud(arena.metrics)
	if stage_name == "room_1":
		logger.log_event("room_1_started")
	elif stage_name == "room_2":
		logger.log_event("room_2_started")

func _finish_training() -> void:
	logger.log_event("training_completed", {"seconds": snappedf(arena.stage_elapsed, 0.1), "overheat_count": arena.metrics["overheat_count"]})
	_start_gameplay("room_1")

func _on_stage_completed(completed_stage: String, metrics: Dictionary) -> void:
	if completed_stage == "room_1":
		logger.log_event("room_1_completed", metrics)
		_show_intermission()
	elif completed_stage == "room_2":
		logger.log_event("room_2_completed", metrics)
		logger.log_event("session_completed", {"modified": flow_policy.intermission_change_used})
		_show_survey()

func _show_intermission() -> void:
	state = "intermission"
	flow_policy.in_combat = false
	arena.visible = false
	var root := _new_page()
	var card := _center_card(900, 520)
	root.add_child(card)
	var content := card.get_child(0) as VBoxContainer
	content.add_child(_badge("房间间 FORGE · 仅一次机会", Color("7c3aed")))
	content.add_child(_large_label("前方传来沉重的金属摩擦声。", 32))
	var hint := Label.new()
	hint.text = "你可以保留当前武器、用一句话修改，或完全重铸。这里不会提前列出敌人名单。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(hint)
	var modification := LineEdit.new()
	modification.placeholder_text = "例如：增加穿透 / 降低过热 / 让它更轻"
	content.add_child(modification)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	content.add_child(actions)
	actions.add_child(_button("保留当前武器", func() -> void: _start_gameplay("room_2"), true))
	actions.add_child(_button("修改一次", func() -> void: _apply_intermission_change(modification.text)))
	actions.add_child(_button("完全重铸", func() -> void: _recast_intermission(modification.text)))

func _apply_intermission_change(request: String) -> void:
	if request.strip_edges().is_empty():
		_show_transient_message("请用一句话写下修改意图。")
		return
	if not flow_policy.consume_intermission_change():
		_show_transient_message("房间间修改已经使用。")
		return
	logger.log_event("modification_requested", {"character_count": request.length(), "recast": false})
	var result: Dictionary = interpreter.apply_delta(current_blueprint, request)
	if not bool(result.get("ok", false)):
		_show_generation_failure("BLUEPRINT_DELTA_REJECTED")
		return
	current_blueprint = result["blueprint"] as WeaponBlueprint
	current_explanation = str(result["explanation"])
	var delta: BlueprintDelta = result["delta"]
	logger.log_event("blueprint_delta_applied", {"accepted_change": delta.accepted_change, "tradeoff": delta.tradeoff})
	var visual: Dictionary = image_generator.generate(current_blueprint, null, saved_geometry)
	if not bool(visual.get("ok", false)):
		_show_generation_failure(str(visual.get("error", "DELTA_VISUAL_FAILED")))
		return
	current_asset = visual["asset"] as WeaponVisualAsset
	_show_delta_result(delta)

func _recast_intermission(request: String) -> void:
	if not flow_policy.consume_intermission_change():
		_show_transient_message("房间间修改已经使用。")
		return
	var recast_text := request.strip_edges()
	if recast_text.is_empty():
		recast_text = "会飞出去再返回的机械闪电伞。"
	logger.log_event("modification_requested", {"character_count": recast_text.length(), "recast": true})
	var result: Dictionary = interpreter.interpret(recast_text, PackedByteArray(), {})
	if bool(result.get("needs_clarification", false)):
		result = interpreter.interpret(recast_text, PackedByteArray(), {}, null, "", "飞出去攻击")
	current_blueprint = result["blueprint"] as WeaponBlueprint
	current_explanation = str(result["explanation"])
	var visual: Dictionary = image_generator.generate(current_blueprint)
	current_asset = visual["asset"] as WeaponVisualAsset
	logger.log_event("blueprint_delta_applied", {"accepted_change": "full_recast", "tradeoff": current_blueprint.drawback})
	_start_gameplay("room_2")

func _show_delta_result(delta: BlueprintDelta) -> void:
	var root := _new_page()
	var card := _center_card(900, 500)
	root.add_child(card)
	var content := card.get_child(0) as VBoxContainer
	content.add_child(_badge("修改已通过本地规则验证", Color("166534")))
	content.add_child(_large_label("变化会同时影响外观、行为与代价", 30))
	var summary := Label.new()
	summary.text = delta.player_summary
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_font_size_override("font_size", 22)
	content.add_child(summary)
	content.add_child(_button("带着修改后的武器进入房间二", func() -> void: _start_gameplay("room_2"), true))

func _show_survey() -> void:
	state = "survey"
	flow_policy.in_combat = false
	arena.visible = false
	var root := _new_page(30)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(1120, 760)
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	content.add_child(_header("试玩问卷", "1 = 完全不同意，5 = 完全同意。自由回答只记录长度，不记录原文。"))
	var questions := [
		"这件武器看起来像我想象的东西", "这件武器打起来像我想象的东西",
		"我能理解它的强项和缺点", "修改后第二场战斗有明显变化", "我还想再创造一件武器"
	]
	var ratings: Array[SpinBox] = []
	for index: int in range(questions.size()):
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%d. %s" % [index + 1, questions[index]]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var rating := SpinBox.new()
		rating.min_value = 1
		rating.max_value = 5
		rating.value = 3
		rating.custom_minimum_size = Vector2(120, 0)
		row.add_child(rating)
		ratings.append(rating)
		content.add_child(row)
	var fake_part := LineEdit.new()
	fake_part.placeholder_text = "哪一部分最像假的？"
	content.add_child(fake_part)
	var desired_change := LineEdit.new()
	desired_change.placeholder_text = "你最想改变什么？"
	content.add_child(desired_change)
	content.add_child(_button("提交问卷", func() -> void: _submit_survey(ratings, fake_part.text.length(), desired_change.text.length()), true))

func _submit_survey(ratings: Array[SpinBox], fake_length: int, change_length: int) -> void:
	var values: Array[int] = []
	for rating: SpinBox in ratings:
		values.append(roundi(rating.value))
	logger.log_event("survey_submitted", {"ratings": values, "fake_answer_length": fake_length, "change_answer_length": change_length})
	_show_complete()

func _show_complete() -> void:
	state = "complete"
	var root := _new_page()
	var card := _center_card(820, 460)
	root.add_child(card)
	var content := card.get_child(0) as VBoxContainer
	content.add_child(_badge("V1 试玩完成", Color("166534")))
	content.add_child(_large_label("谢谢。你的武器已完成两次战斗验证。", 34))
	var path := Label.new()
	path.text = "本地日志：user://playlab/events.jsonl\n没有上传原始草图或完整自由文本。"
	path.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(path)
	content.add_child(_button("重新开始", _reset_session))

func _reset_session() -> void:
	current_blueprint = null
	current_asset = null
	saved_description = ""
	saved_geometry = {}
	clarification_used = false
	initial_change_used = false
	flow_policy = FLOW_POLICY.new() as FlowPolicy
	_show_forge()

func _show_gallery() -> void:
	state = "gallery"
	arena.visible = false
	var root := _new_page()
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	root.add_child(outer)
	outer.add_child(_header("三件固定测试武器", "同一套 96×96 真像素规则；颜色、比例、轮廓与 Blueprint 相互一致。"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(row)
	for kind: String in ["gatling", "umbrella", "greatsword"]:
		var blueprint := WeaponBlueprint.fixed_blueprint(kind)
		var generated: Dictionary = image_generator.generate(blueprint)
		var generated_asset := generated["asset"] as WeaponVisualAsset
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(column)
		var preview := WEAPON_PREVIEW.new() as WeaponPreview
		preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
		preview.configure(generated_asset, true, false, blueprint.display_name)
		column.add_child(preview)
		var traits := Label.new()
		traits.text = _player_facing_traits(blueprint)
		traits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		traits.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(traits)
	if capture_mode.is_empty():
		outer.add_child(_button("返回 Forge", _show_forge))

func _show_anchor_debug() -> void:
	state = "anchor_debug"
	arena.visible = false
	var root := _new_page()
	var outer := VBoxContainer.new()
	root.add_child(outer)
	outer.add_child(_header("开发者锚点调试", "点击标记后可拖拽，或用方向键逐像素微调；保存为 user:// metadata JSON。"))
	var preview := WEAPON_PREVIEW.new() as WeaponPreview
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.configure(current_asset, true, true, current_blueprint.display_name)
	outer.add_child(preview)
	var actions := HBoxContainer.new()
	outer.add_child(actions)
	actions.add_child(_button("保存锚点覆盖", func() -> void: _save_anchor_override(preview)))
	if capture_mode.is_empty():
		actions.add_child(_button("返回武器解释", _show_review))

func _save_anchor_override(preview: WeaponPreview) -> void:
	var result := ANCHOR_RESOLVER.save_override(current_blueprint.id, preview.asset)
	_show_transient_message("锚点覆盖已保存。" if result == OK else "保存失败：%s" % error_string(result))

func _show_generation_failure(code: String) -> void:
	state = "error"
	var root := _new_page()
	var card := _center_card(800, 440)
	root.add_child(card)
	var content := card.get_child(0) as VBoxContainer
	content.add_child(_badge("生成没有成功", Color("991b1b")))
	content.add_child(_large_label("输入和草图已保留", 32))
	var details := Label.new()
	details.text = "错误：%s\n你可以重试，或明确进入本地样例模式。失败不会自动装备无关武器。" % code
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(details)
	content.add_child(_button("返回重试", _show_forge, true))
	content.add_child(_button("进入 LOCAL SAMPLE", func() -> void: _prepare_fixed_and_review("gatling")))

func _prepare_fixed(kind: String) -> void:
	current_blueprint = WeaponBlueprint.fixed_blueprint(kind)
	current_explanation = interpreter.player_explanation(current_blueprint)
	var generated: Dictionary = image_generator.generate(current_blueprint)
	current_asset = generated["asset"] as WeaponVisualAsset

func _prepare_fixed_and_review(kind: String) -> void:
	_prepare_fixed(kind)
	_show_review()

func _update_hud(data: Dictionary) -> void:
	if hud_stats == null or not is_instance_valid(hud_stats):
		return
	hud_stats.text = "%s  ·  生命 %d  ·  过热 %d%%  ·  闪避 %d" % [
		current_blueprint.display_name, roundi(arena.player_health), roundi(arena.overheat * 100.0), int(data.get("dodge_count", 0))
	]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug") and arena.visible:
		arena.debug_anchors = not arena.debug_anchors

func _new_page(margin: int = 28) -> MarginContainer:
	if page != null and is_instance_valid(page):
		page.queue_free()
	page = MarginContainer.new()
	page.position = Vector2.ZERO
	page.size = Vector2(1280, 720)
	page.theme = app_theme
	page.add_theme_constant_override("margin_left", margin)
	page.add_theme_constant_override("margin_right", margin)
	page.add_theme_constant_override("margin_top", margin)
	page.add_theme_constant_override("margin_bottom", margin)
	ui_layer.add_child(page)
	return page as MarginContainer

func _header(title: String, subtitle: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.add_child(_large_label(title, 34))
	var sub := Label.new()
	sub.text = subtitle
	sub.modulate = Color("a9bad0")
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sub)
	return box

func _section_title(text: String) -> Label:
	return _large_label(text, 22)

func _large_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _button(text: String, callback: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	if primary:
		button.add_theme_font_size_override("font_size", 20)
	return button

func _badge(text: String, color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return panel

func _center_card(width: float, height: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, height)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("142235")
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_left = 18
	style.corner_radius_bottom_right = 18
	style.content_margin_left = 34
	style.content_margin_right = 34
	style.content_margin_top = 30
	style.content_margin_bottom = 30
	panel.add_theme_stylebox_override("panel", style)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	panel.add_child(content)
	return panel

func _show_error(message: String) -> void:
	if error_label != null:
		error_label.text = message

func _show_transient_message(message: String) -> void:
	var label := Label.new()
	label.text = message
	label.position = Vector2(420, 660)
	label.add_theme_font_size_override("font_size", 20)
	label.modulate = Color("fef08a")
	ui_layer.add_child(label)
	var tween := create_tween()
	tween.tween_interval(2.0)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)

func _player_facing_traits(blueprint: WeaponBlueprint) -> String:
	match blueprint.behavior_family:
		"returning_thrown": return "飞出与返回均可命中 · 电弧连锁 · 返回前不能再投"
		"heavy_melee": return "重型近战 · 命中吸取生命 · 启动较慢"
		_: return "按住连射 · 蓝焰与燃烧 · 过热停火 · 重型移动"

func _stage_title(stage_name: String) -> String:
	match stage_name:
		"room_1": return "房间一 · 数量与冲锋压力"
		"room_2": return "房间二 · 护卫与混合压力"
		_: return "试武器区 · 无失败条件"

func _capture_argument() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			return argument.trim_prefix("--capture=")
	return ""
