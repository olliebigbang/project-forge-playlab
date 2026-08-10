extends Node2D

const ANCHOR_RESOLVER := preload("res://scripts/systems/semantic_anchor_resolver.gd")
const LIVE_ANCHOR_CANVAS := preload("res://tools/live_e2e/godot/live_anchor_canvas.gd")
const LIVE_ARENA := preload("res://tools/live_e2e/godot/live_training_arena.gd")

const LIVE_ARGUMENT := "--forge-live-e2e-spike7"
const CASES: Array[Dictionary] = [
	{
		"case_id": "L01", "player_input": "一台会持续喷出冰雾的旧落地风扇。",
		"parts": ["风扇头", "支撑杆", "底座"], "second_anchor": "EffectOrigin",
		"second_question": "冰雾从哪里发出？"
	},
	{
		"case_id": "L02", "player_input": "一个扔出去绕一圈后会飞回来的红色旅行箱。",
		"parts": ["箱体", "提手", "箱角或轮子"], "second_anchor": "SpinPivot",
		"second_question": "你希望它围绕哪里旋转？"
	},
	{
		"case_id": "L03", "player_input": "一把我要拿来近距离砸敌人的巨大木勺。",
		"parts": ["勺头", "长柄", "木材身份"], "second_anchor": "StrikePoint",
		"second_question": "你想用哪一部分击中敌人？"
	}
]

var bridge_base := ""
var session_id := ""
var run_id := ""
var case_index := 0
var revision := 0
var current_response: Dictionary = {}
var current_image: Image
var current_texture: Texture2D
var current_blueprint: WeaponBlueprint
var current_calibration: SemanticAnchorCalibration
var training_asset: WeaponVisualAsset

var canvas_layer: CanvasLayer
var screen_root: Control
var input_line: LineEdit
var status_label: Label
var part_checks: Array[CheckBox] = []
var substitution_check: CheckBox
var static_effect_check: CheckBox
var anchor_canvas: LiveE2EAnchorCanvas
var anchor_steps: Array[String] = []
var anchor_step_index := 0
var anchor_started_msec := 0
var identity_started_msec := 0

var arena: LiveE2ETrainingArena
var training_active := false
var training_initial_position := Vector2.ZERO
var training_load_seconds := 0.0
var training_holding_png := PackedByteArray()
var training_attack_png := PackedByteArray()
var attack_capture_started := false
var moved_once := false
var attacked_once := false
var dodged_once := false
var training_status: Label
var behavior_check: CheckBox
var finish_training_button: Button

func _ready() -> void:
	canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 20
	add_child(canvas_layer)
	screen_root = Control.new()
	screen_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas_layer.add_child(screen_root)
	var arguments := OS.get_cmdline_user_args()
	if not arguments.has(LIVE_ARGUMENT):
		_show_fatal("本场景必须由 Live E2E 明确入口启动。默认玩家流程未改变。")
		return
	bridge_base = _argument_value(arguments, "--live-bridge=", "")
	session_id = _argument_value(arguments, "--live-session=", "")
	run_id = _argument_value(arguments, "--live-run=", "")
	if bridge_base != "http://127.0.0.1:8767" or session_id.is_empty() or run_id.is_empty():
		_show_fatal("Live E2E 参数无效；未调用任何模型。")
		return
	_show_wait("正在验证本地 Live E2E 桥接层……")
	var health := await _get_json("/health")
	if not bool(health.get("ok", false)):
		_show_fatal("本地桥接层不可用：%s" % str(health.get("failure_reason", "HEALTH_FAILED")))
		return
	var body: Dictionary = health["body"]
	if str(body.get("session_id", "")) != session_id or bool(body.get("mock_fallback", true)):
		_show_fatal("桥接会话边界验证失败。")
		return
	_show_intro()

func _process(_delta: float) -> void:
	if not training_active or arena == null:
		return
	if arena.player_position.distance_to(training_initial_position) > 12.0:
		moved_once = true
	if int(arena.metrics.get("dodge_count", 0)) > 0:
		dodged_once = true
	if arena.live_attack_visible():
		attacked_once = true
		if not attack_capture_started:
			attack_capture_started = true
			_capture_training_attack()
	if training_status != null:
		training_status.text = "移动：%s　攻击：%s　闪避：%s" % [_yes_no(moved_once), _yes_no(attacked_once), _yes_no(dodged_once)]
	if finish_training_button != null:
		finish_training_button.disabled = not (moved_once and attacked_once and dodged_once and behavior_check.button_pressed and not training_attack_png.is_empty())

func _show_intro() -> void:
	_clear_screen()
	var panel := _panel()
	var box := _vbox(panel, 96, 70, 1088, 580)
	box.add_child(_title("Forge Live End-to-End Spike 7"))
	box.add_child(_label("真实链路：中文输入 → Claude v1.1 → FLUX.2 → BiRefNet → 96×96 → 玩家确认 → 训练区", 22))
	box.add_child(_label("仅三项已批准案例，每项一次；无重试、无 Mock 回退、不接入战斗房间。", 20, Color("fbbf24")))
	box.add_child(_label("请在每张真实生成图上独立判断身份结构，并亲自完成握点、作用点与训练动作。", 20))
	var start := _button("开始 L01", func() -> void: _show_case_input())
	start.custom_minimum_size.y = 64
	box.add_child(start)

func _show_case_input() -> void:
	_cleanup_training()
	if case_index >= CASES.size():
		_finalize_session()
		return
	var case: Dictionary = CASES[case_index]
	_clear_screen()
	var box := _vbox(_panel(), 100, 55, 1080, 610)
	box.add_child(_title("%s · 玩家文字输入" % str(case["case_id"])))
	box.add_child(_label("请确认这就是本次批准的中文描述。提交后将发生一次真实 Claude 调用，失败不重试。", 20))
	input_line = LineEdit.new()
	input_line.text = str(case["player_input"])
	input_line.custom_minimum_size.y = 62
	input_line.add_theme_font_size_override("font_size", 24)
	box.add_child(input_line)
	status_label = _label("玩家输入会在失败时保留。", 18, Color("94a3b8"))
	box.add_child(status_label)
	var submit := _button("提交一次真实生成", Callable())
	submit.custom_minimum_size.y = 60
	submit.pressed.connect(func() -> void: _submit_current_case(submit))
	box.add_child(submit)

func _submit_current_case(button: Button) -> void:
	button.disabled = true
	input_line.editable = false
	status_label.text = "处理中：Claude → FLUX.2 → BiRefNet → 96×96。请等待，不会自动重试。"
	var case: Dictionary = CASES[case_index]
	var result := await _post_json("/case/start", {
		"session_id": session_id,
		"case_id": case["case_id"],
		"player_input": input_line.text
	})
	if not bool(result.get("ok", false)):
		status_label.text = "失败：%s / %s\n输入仍保留；本案例不会重试。" % [str(result.get("failure_stage", "request")), str(result.get("failure_reason", "UNKNOWN"))]
		return
	var body: Dictionary = result["body"]
	if str(body.get("status", "")) == "failed":
		_show_case_failure(body)
		return
	revision = int(body.get("revision", 0))
	current_response = body
	var decoded := Marshalls.base64_to_raw(str(body.get("sprite_png_base64", "")))
	current_image = Image.new()
	if current_image.load_png_from_buffer(decoded) != OK or current_image.get_size() != Vector2i(96, 96):
		_show_fatal("Godot 拒绝了无效的 96×96 Sprite；未进入身份确认。")
		return
	current_texture = ImageTexture.create_from_image(current_image)
	_show_identity_confirmation()

func _show_identity_confirmation() -> void:
	identity_started_msec = Time.get_ticks_msec()
	_clear_screen()
	var panel := _panel()
	var columns := HBoxContainer.new()
	columns.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	columns.add_theme_constant_override("separation", 34)
	columns.offset_left = 70
	columns.offset_top = 40
	columns.offset_right = -70
	columns.offset_bottom = -40
	panel.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 480
	columns.add_child(left)
	left.add_child(_title("%s · 真实生成物件" % str(current_response["case_id"])))
	var backdrop := ColorRect.new()
	backdrop.color = Color("25102f")
	backdrop.custom_minimum_size = Vector2(420, 420)
	left.add_child(backdrop)
	var preview := TextureRect.new()
	preview.texture = current_texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 18)
	backdrop.add_child(preview)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	right.add_child(_label("玩家原文：%s" % str(current_response["player_input"]), 21))
	right.add_child(_label("Claude 摘要：%s" % str(current_response["summary_zh"]), 20, Color("67e8f9")))
	right.add_child(_label("请只看实际图片判断：", 20, Color("fbbf24")))
	part_checks.clear()
	var parts: Array = current_response["expected_parts"]
	for part: Variant in parts:
		var check := CheckBox.new()
		check.text = "能看见关键结构：%s" % str(part)
		check.add_theme_font_size_override("font_size", 20)
		right.add_child(check)
		part_checks.append(check)
	substitution_check = CheckBox.new()
	substitution_check.text = "没有被替换成加特林／雨伞／大剑等固定武器"
	substitution_check.add_theme_font_size_override("font_size", 20)
	right.add_child(substitution_check)
	static_effect_check = CheckBox.new()
	static_effect_check.text = "静态 Sprite 没有烘焙悬浮雾、轨迹或攻击场景"
	static_effect_check.add_theme_font_size_override("font_size", 20)
	right.add_child(static_effect_check)
	right.add_spacer(false)
	right.add_child(_button("仍然能认出原物件", func() -> void: _submit_identity(true)))
	right.add_child(_button("不符合我的想法", func() -> void: _submit_identity(false), Color("7f1d1d")))

func _submit_identity(recognizable: bool) -> void:
	var screenshot := await _capture_screen_png()
	var parts: Array[bool] = []
	for check: CheckBox in part_checks:
		parts.append(check.button_pressed)
	var result := await _post_json("/case/identity", {
		"session_id": session_id,
		"case_id": current_response["case_id"],
		"revision": revision,
		"identity_recognizable": recognizable,
		"required_parts_preserved": parts,
		"no_fixed_weapon_substitution": substitution_check.button_pressed,
		"no_baked_dynamic_effect": static_effect_check.button_pressed,
		"confirmation_seconds": float(Time.get_ticks_msec() - identity_started_msec) / 1000.0,
		"screenshot_png_base64": Marshalls.raw_to_base64(screenshot)
	})
	if not bool(result.get("ok", false)):
		_show_fatal("身份确认提交失败：%s（不重试）" % str(result.get("failure_reason", "UNKNOWN")))
		return
	if not recognizable:
		_show_case_done("玩家已明确拒绝物件身份。本案例产品结论失败，未进入锚点或训练区。")
		return
	_show_anchor_confirmation()

func _show_anchor_confirmation() -> void:
	current_blueprint = _make_gameplay_projection()
	current_calibration = ANCHOR_RESOLVER.resolve(current_image, current_blueprint) as SemanticAnchorCalibration
	if current_calibration == null:
		_show_fatal("AnchorResolver 无法解析有效 Alpha；未进入训练区。")
		return
	current_calibration.case_id = str(current_response["case_id"])
	current_calibration.run_id = run_id
	current_calibration.source_sprite = "processed_sprite.png"
	anchor_steps = ["GripPrimary", str(current_response["second_anchor_type"])]
	anchor_step_index = 0
	anchor_started_msec = Time.get_ticks_msec()
	_clear_screen()
	var panel := _panel()
	var columns := HBoxContainer.new()
	columns.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	columns.offset_left = 60
	columns.offset_top = 45
	columns.offset_right = -60
	columns.offset_bottom = -45
	columns.add_theme_constant_override("separation", 42)
	panel.add_child(columns)
	anchor_canvas = LIVE_ANCHOR_CANVAS.new()
	anchor_canvas.anchor_confirmed.connect(_on_anchor_confirmed)
	columns.add_child(anchor_canvas)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	right.add_child(_title("玩家锚点确认"))
	var instruction := _label("", 24, Color("fbbf24"))
	instruction.name = "AnchorInstruction"
	right.add_child(instruction)
	right.add_child(_label("点击物件，或拖动十字标记。你也可以直接确认自动建议；确认动作仍会记录为玩家确认。", 19))
	var confirm := _button("确认当前位置", func() -> void: anchor_canvas.confirm_current())
	confirm.name = "AnchorConfirm"
	confirm.custom_minimum_size.y = 60
	right.add_child(confirm)
	_configure_anchor_step()

func _configure_anchor_step() -> void:
	var anchor_type := anchor_steps[anchor_step_index]
	var question := "你准备从哪里拿住它？" if anchor_type == "GripPrimary" else str(current_response["second_anchor_question"])
	var instruction := screen_root.find_child("AnchorInstruction", true, false) as Label
	instruction.text = "%d/2　%s" % [anchor_step_index + 1, question]
	var known: Dictionary = {}
	for key: String in current_calibration.auto_anchors.keys():
		if key != anchor_type:
			known[key] = current_calibration.anchor_point(key)
	var suggestion := current_calibration.anchor_point(anchor_type)
	if anchor_step_index == 0:
		anchor_canvas.configure(current_texture, anchor_type, suggestion, known)
	else:
		anchor_canvas.set_step(anchor_type, suggestion, known)

func _on_anchor_confirmed(anchor_type: String, point: Vector2, was_adjusted: bool) -> void:
	if anchor_type != anchor_steps[anchor_step_index]:
		return
	current_calibration.confirm_anchor(anchor_type, point, was_adjusted)
	if anchor_type == "GripPrimary":
		ANCHOR_RESOLVER.recompute_derived(current_calibration, current_image)
	anchor_step_index += 1
	if anchor_step_index < anchor_steps.size():
		_configure_anchor_step()
		return
	_submit_anchors()

func _submit_anchors() -> void:
	var errors := current_calibration.validation_errors()
	if not errors.is_empty():
		_show_fatal("锚点校验失败：%s" % ", ".join(errors))
		return
	var result := await _post_json("/case/anchors", {
		"session_id": session_id,
		"case_id": current_response["case_id"],
		"revision": revision,
		"confirmation_seconds": float(Time.get_ticks_msec() - anchor_started_msec) / 1000.0,
		"anchors": current_calibration.to_dict()
	})
	if not bool(result.get("ok", false)):
		_show_fatal("锚点确认提交失败：%s；未进入训练区。" % str(result.get("failure_reason", "UNKNOWN")))
		return
	training_asset = current_calibration.apply_to_asset()
	if training_asset == null:
		_show_fatal("锚点资产交付失败；未进入训练区。")
		return
	_enter_training()

func _enter_training() -> void:
	_clear_screen()
	var load_started := Time.get_ticks_msec()
	arena = LIVE_ARENA.new()
	add_child(arena)
	arena.start_stage("training", current_blueprint, training_asset)
	training_initial_position = arena.player_position
	training_active = true
	moved_once = false
	attacked_once = false
	dodged_once = false
	attack_capture_started = false
	training_attack_png = PackedByteArray()
	var overlay := PanelContainer.new()
	overlay.set_anchors_preset(Control.PRESET_TOP_WIDE)
	overlay.offset_left = 36
	overlay.offset_top = 22
	overlay.offset_right = -36
	overlay.offset_bottom = 152
	screen_root.add_child(overlay)
	var box := VBoxContainer.new()
	overlay.add_child(box)
	box.add_child(_label("%s 训练区（只接入训练，不接入战斗房间）" % str(current_response["case_id"]), 22, Color("67e8f9")))
	box.add_child(_label("移动：WASD/方向键　攻击：空格/J　闪避：K/Shift", 19))
	training_status = _label("移动：否　攻击：否　闪避：否", 18, Color("fbbf24"))
	box.add_child(training_status)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 18)
	box.add_child(actions)
	behavior_check = CheckBox.new()
	behavior_check.text = "我已看见攻击表现与行为家族一致"
	behavior_check.add_theme_font_size_override("font_size", 18)
	actions.add_child(behavior_check)
	var dodge_button := _button("执行闪避", func() -> void:
		if arena != null:
			arena.request_touch_dodge()
	)
	dodge_button.tooltip_text = "与 K/Shift 相同；用于键盘焦点未进入训练场时。"
	actions.add_child(dodge_button)
	finish_training_button = _button("完成本案例", func() -> void: _finish_training())
	finish_training_button.disabled = true
	actions.add_child(finish_training_button)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	training_load_seconds = float(Time.get_ticks_msec() - load_started) / 1000.0
	training_holding_png = await _capture_screen_png()

func _capture_training_attack() -> void:
	await RenderingServer.frame_post_draw
	training_attack_png = await _capture_screen_png()

func _finish_training() -> void:
	finish_training_button.disabled = true
	var result := await _post_json("/case/training", {
		"session_id": session_id,
		"case_id": current_response["case_id"],
		"revision": revision,
		"moved": moved_once,
		"attacked": attacked_once,
		"dodged": dodged_once,
		"behavior_family_observed": behavior_check.button_pressed,
		"training_load_seconds": training_load_seconds,
		"holding_png_base64": Marshalls.raw_to_base64(training_holding_png),
		"attack_png_base64": Marshalls.raw_to_base64(training_attack_png)
	})
	if not bool(result.get("ok", false)):
		_show_fatal("训练证据提交失败：%s" % str(result.get("failure_reason", "UNKNOWN")))
		return
	_show_case_done("身份、锚点、移动、攻击与闪避证据已原子交付。")

func _show_case_failure(body: Dictionary) -> void:
	_clear_screen()
	var box := _vbox(_panel(), 110, 85, 1060, 550)
	box.add_child(_title("%s 技术阶段失败" % str(body.get("case_id", ""))))
	box.add_child(_label("失败阶段：%s" % str(body.get("failure_stage", "UNKNOWN")), 22, Color("fb7185")))
	box.add_child(_label("准确原因：%s" % str(body.get("failure_reason", "UNKNOWN")), 20))
	box.add_child(_label("玩家输入已保存；没有重试，没有 Mock 回退。", 20, Color("fbbf24")))
	case_index += 1
	box.add_child(_button("继续下一批准案例", func() -> void: _show_case_input()))

func _show_case_done(message: String) -> void:
	_cleanup_training()
	_clear_screen()
	var box := _vbox(_panel(), 110, 85, 1060, 550)
	box.add_child(_title("%s 已完成" % str(current_response.get("case_id", ""))))
	box.add_child(_label(message, 22, Color("5eead4")))
	box.add_child(_label("当前案例资源已隔离；下一案例使用新的 revision，旧请求不能覆盖。", 19))
	case_index += 1
	box.add_child(_button("继续" if case_index < CASES.size() else "生成最终报告", func() -> void: _show_case_input()))

func _finalize_session() -> void:
	_show_wait("正在生成冻结报告与 SHA-256 证据……")
	var result := await _post_json("/session/finalize", {"session_id": session_id})
	if not bool(result.get("ok", false)):
		_show_fatal("最终报告生成失败：%s" % str(result.get("failure_reason", "UNKNOWN")))
		return
	var body: Dictionary = result["body"]
	_clear_screen()
	var box := _vbox(_panel(), 100, 65, 1080, 590)
	box.add_child(_title(str(body.get("classification", "LIVE END-TO-END NEEDS WORK"))))
	box.add_child(_label("报告：%s" % str(body.get("report_path", "")), 18))
	box.add_child(_label("关闭后入口脚本会停止 ComfyUI、清除 Key，并确认 8190/8188 关闭。", 20, Color("fbbf24")))
	box.add_child(_button("关闭 Live E2E", func() -> void: get_tree().quit()))

func _make_gameplay_projection() -> WeaponBlueprint:
	var blueprint := WeaponBlueprint.new()
	blueprint.id = "live-%s-%s" % [run_id, str(current_response["case_id"])]
	blueprint.display_name = str(current_response["canonical_name_zh"])
	blueprint.source_identity = str(current_response["player_input"])
	blueprint.player_identity_text = str(current_response["player_input"])
	blueprint.identity_confidence = 1.0
	blueprint.visual_description = str(current_response["canonical_name_zh"])
	blueprint.preserved_visual_features.clear()
	for part: Variant in current_response["expected_parts"]:
		blueprint.preserved_visual_features.append(str(part))
	blueprint.behavior_family = str(current_response["behavior_family"])
	blueprint.delivery = str(current_response["delivery"])
	blueprint.impact_mode = str(current_response["impact_mode"])
	blueprint.effect_type = str(current_response["effect_type"])
	blueprint.drawback = str(current_response["drawback"])
	blueprint.cadence = str(current_response["cadence_hint"])
	blueprint.weapon_form = "player_identity_object"
	blueprint.modifiers = {}
	match blueprint.behavior_family:
		"returning_thrown":
			blueprint.grip_profile = "throwable_center"
			blueprint.weight_class = "medium"
		"heavy_melee":
			blueprint.grip_profile = "two_hand_rear"
			blueprint.weight_class = "heavy"
		_:
			blueprint.grip_profile = "center_shaft"
			blueprint.weight_class = "medium"
	match blueprint.effect_type:
		"fire": blueprint.element = "fire"
		"electric": blueprint.element = "electric"
		"lifesteal": blueprint.element = "life"
		_: blueprint.element = "normal"
	return blueprint

func _get_json(route: String) -> Dictionary:
	return await _http_json(route, HTTPClient.METHOD_GET, {})

func _post_json(route: String, body: Dictionary) -> Dictionary:
	return await _http_json(route, HTTPClient.METHOD_POST, body)

func _http_json(route: String, method: int, body: Dictionary) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = 900.0
	add_child(request)
	var payload := "" if method == HTTPClient.METHOD_GET else JSON.stringify(body)
	var headers := PackedStringArray(["Content-Type: application/json", "Cache-Control: no-store"])
	var request_error := request.request(bridge_base + route, headers, method, payload)
	if request_error != OK:
		request.queue_free()
		return {"ok": false, "failure_stage": "bridge", "failure_reason": "HTTP_REQUEST_START_FAILED:%s" % error_string(request_error)}
	var completed: Array = await request.request_completed
	request.queue_free()
	var result_code := int(completed[0])
	var response_code := int(completed[1])
	var response_body: PackedByteArray = completed[3]
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "failure_stage": "bridge", "failure_reason": "HTTP_TRANSPORT_FAILED:%d" % result_code}
	var decoded: Variant = JSON.parse_string(response_body.get_string_from_utf8())
	if not (decoded is Dictionary):
		return {"ok": false, "failure_stage": "bridge", "failure_reason": "HTTP_JSON_INVALID"}
	var value := decoded as Dictionary
	if response_code < 200 or response_code >= 300:
		return {
			"ok": false,
			"failure_stage": str(value.get("failure_stage", "bridge")),
			"failure_reason": str(value.get("failure_reason", "HTTP_%d" % response_code))
		}
	return {"ok": true, "body": value}

func _capture_screen_png() -> PackedByteArray:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image().save_png_to_buffer()

func _cleanup_training() -> void:
	training_active = false
	if arena != null:
		arena.stop()
		arena.queue_free()
		arena = null

func _clear_screen() -> void:
	for child: Node in screen_root.get_children():
		screen_root.remove_child(child)
		child.queue_free()

func _panel() -> Panel:
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_root.add_child(panel)
	return panel

func _vbox(parent: Control, left: float, top: float, right: float, bottom: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.position = Vector2(left, top)
	box.size = Vector2(right - left, bottom - top)
	box.add_theme_constant_override("separation", 22)
	parent.add_child(box)
	return box

func _title(text: String) -> Label:
	return _label(text, 34, Color("f8fafc"))

func _label(text: String, size: int, color: Color = Color("e2e8f0")) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(text: String, callback: Callable, color: Color = Color("164e63")) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 21)
	button.add_theme_color_override("font_color", Color("f8fafc"))
	button.modulate = color.lightened(0.55)
	if callback.is_valid():
		button.pressed.connect(callback)
	return button

func _show_wait(message: String) -> void:
	_clear_screen()
	var box := _vbox(_panel(), 110, 120, 1060, 520)
	box.add_child(_title("Forge Live E2E"))
	box.add_child(_label(message, 24, Color("67e8f9")))

func _show_fatal(message: String) -> void:
	_cleanup_training()
	_clear_screen()
	var box := _vbox(_panel(), 100, 85, 1080, 570)
	box.add_child(_title("Live E2E 已停止"))
	box.add_child(_label(message, 23, Color("fb7185")))
	box.add_child(_label("没有自动重试，没有 Mock 回退；玩家输入与已完成证据保持不变。", 20, Color("fbbf24")))
	box.add_child(_button("关闭", func() -> void: get_tree().quit(), Color("7f1d1d")))

func _argument_value(arguments: PackedStringArray, prefix: String, fallback: String) -> String:
	for argument: String in arguments:
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return fallback

func _yes_no(value: bool) -> String:
	return "是" if value else "否"
