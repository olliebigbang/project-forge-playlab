extends Node2D

const ANCHOR_RESOLVER := preload("res://scripts/systems/semantic_anchor_resolver.gd")
const ANCHOR_CANVAS := preload("res://tools/live_e2e/godot/live_anchor_canvas.gd")
const TRAINING_ARENA := preload("res://tools/live_e2e/godot/live_training_arena.gd")
const COMBAT_FEEL_SCENE := "res://scenes/combat_feel_slice_0.tscn"

const OPEN_ARGUMENT := "--forge-open-playtest"
const EXPECTED_BRIDGE := "http://127.0.0.1:8771"
const STAGES: Array[String] = [
	"semantic_compiling",
	"image_generating",
	"background_removing",
	"sprite_processing",
	"confirm_identity",
	"confirm_anchors",
	"ready_in_training_zone",
]
const STAGE_NAMES := {
	"semantic_compiling": "语义编译",
	"image_generating": "图像生成",
	"background_removing": "背景移除",
	"sprite_processing": "Sprite 处理",
	"confirm_identity": "确认物件身份",
	"confirm_anchors": "确认握持点 / 作用点",
	"ready_in_training_zone": "训练区就绪",
}
const RESUMABLE_STAGES: Array[String] = [
	"semantic_compiling",
	"image_generating",
	"background_removing",
	"sprite_processing",
	"confirm_identity",
	"confirm_anchors",
]

var bridge_base := ""
var session_id := ""
var semantic_mode := ""
var semantic_contract := ""
var current_round_id := ""
var revision := 0
var current_input := ""
var current_response: Dictionary = {}
var current_stage := ""
var request_in_flight := false
var identity_confirmed_for_round := false
var launch_combat_after_anchors := false

var canvas_layer: CanvasLayer
var screen_root: Control
var input_edit: TextEdit
var status_label: Label
var stage_label: Label
var identity_notes: TextEdit
var feedback_notes: TextEdit
var feedback_rating: OptionButton
var feedback_keep: CheckBox

var raw_image := Image.new()
var raw_texture: Texture2D
var sprite_image := Image.new()
var sprite_texture: Texture2D
var blueprint: WeaponBlueprint
var calibration: SemanticAnchorCalibration
var training_asset: WeaponVisualAsset
var anchor_canvas: LiveE2EAnchorCanvas
var anchor_steps: Array[String] = []
var anchor_step_index := 0

var arena: LiveE2ETrainingArena
var training_active := false
var training_initial_position := Vector2.ZERO
var moved_once := false
var attacked_once := false
var dodged_once := false
var training_status: Label
var training_preview_tip: Label
var training_preview_tip_shown := false
var combat_launch_status: Label


func _ready() -> void:
	canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 20
	add_child(canvas_layer)
	screen_root = Control.new()
	screen_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas_layer.add_child(screen_root)
	var arguments := OS.get_cmdline_user_args()
	if not arguments.has(OPEN_ARGUMENT):
		_show_fatal("此场景只能从显式 Open Playtest 启动脚本进入；默认 MOCK 流程未改变。")
		return
	bridge_base = _argument_value(arguments, "--open-bridge=", "")
	session_id = _argument_value(arguments, "--open-session=", "")
	semantic_mode = _argument_value(arguments, "--open-semantic-mode=", "")
	if bridge_base != EXPECTED_BRIDGE or session_id.is_empty() or semantic_mode not in ["v1_1", "affordance_v1_2_2"]:
		_show_fatal("Open Playtest 启动参数无效；没有调用任何模型。")
		return
	_show_wait("正在验证本地试玩桥接层……")
	var health := await _get_json("/health")
	if not bool(health.get("ok", false)):
		_show_fatal("本地试玩桥接层不可用：%s" % str(health.get("failure_reason", "HEALTH_FAILED")))
		return
	var body: Dictionary = health["body"]
	var expected_contract := "forge-semantic-v1.2.2-candidate" if semantic_mode == "affordance_v1_2_2" else "forge-semantic-v1.1"
	if str(body.get("session_id", "")) != session_id or bool(body.get("mock_fallback", true)) or str(body.get("semantic_mode", "")) != semantic_mode or str(body.get("semantic_contract", "")) != expected_contract:
		_show_fatal("试玩会话边界验证失败；未使用 Mock 回退。")
		return
	semantic_contract = str(body.get("semantic_contract", ""))
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
		if blueprint.behavior_family == "heavy_melee" and not training_preview_tip_shown:
			training_preview_tip_shown = true
			if training_preview_tip != null:
				training_preview_tip.text = "当前只是基础预览。完整三连和打击感请进入近战手感测试。"
	if training_status != null:
		training_status.text = "移动：%s　攻击：%s　闪避：%s" % [
			_yes_no(moved_once), _yes_no(attacked_once), _yes_no(dodged_once)
		]


func _show_intro() -> void:
	_clear_screen()
	var box := _vbox(_panel(), 100, 55, 1080, 650)
	box.add_child(_title("Forge Open Playtest Mode"))
	box.add_child(_label("开放中文输入 → Claude → FLUX.2 Klein 4B → BiRefNet → 96×96 → 玩家确认 → 训练区", 21, Color("67e8f9")))
	box.add_child(_label(_semantic_mode_label(), 20, Color("a7f3d0") if semantic_mode == "affordance_v1_2_2" else Color("94a3b8")))
	box.add_child(_label("当前是实验版试玩模式：\n• 图像与基础攻击可验证\n• 数值、完整特效、敌人平衡和正式玩法尚未完成", 22, Color("fbbf24")))
	box.add_child(_label("边界：只进入训练区；不接入战斗房间；不启用草图；失败不重试，也不会自动回退 Mock。", 19))
	box.add_child(_label("当前 Provider：Claude / FLUX.2 Klein 4B / BiRefNet\n默认玩家模式仍为：MOCK", 19, Color("94a3b8")))
	var enter := _button("进入 OPEN PLAYTEST MODE", func() -> void: _show_forge_screen(false))
	enter.custom_minimum_size.y = 66
	box.add_child(enter)
	box.add_child(_button("恢复当前进行中的轮次（不重新调用模型）", func() -> void: _resume_current_round()))


func _show_forge_screen(clear_input: bool) -> void:
	_cleanup_training()
	if clear_input:
		current_input = ""
	_clear_screen()
	var panel := _panel()
	var columns := HBoxContainer.new()
	columns.position = Vector2(42, 32)
	columns.size = Vector2(1196, 650)
	columns.add_theme_constant_override("separation", 24)
	panel.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 760
	left.add_theme_constant_override("separation", 13)
	columns.add_child(left)
	left.add_child(_title("OPEN PLAYTEST MODE"))
	left.add_child(_label("Provider：Claude / FLUX.2 Klein 4B / BiRefNet　|　仅训练区", 18, Color("67e8f9")))
	left.add_child(_label(_semantic_mode_label(), 17, Color("a7f3d0") if semantic_mode == "affordance_v1_2_2" else Color("94a3b8")))
	left.add_child(_label("当前是实验版：图像与基础攻击可验证；数值、完整特效、敌人平衡和正式玩法尚未完成。", 17, Color("fbbf24")))
	left.add_child(_label("输入任意新的中文物件与动作描述（最多 500 字）：", 20))
	input_edit = TextEdit.new()
	input_edit.text = current_input
	input_edit.custom_minimum_size = Vector2(740, 155)
	input_edit.placeholder_text = "例如：一台会持续喷出彩色泡泡的老式收音机。"
	input_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input_edit.add_theme_font_size_override("font_size", 22)
	left.add_child(input_edit)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	left.add_child(actions)
	var forge_button := _button("FORGE", func() -> void: _start_forge())
	forge_button.custom_minimum_size = Vector2(210, 54)
	actions.add_child(forge_button)
	actions.add_child(_button("CLEAR", func() -> void:
		if not request_in_flight:
			input_edit.clear()
			current_input = ""
	))
	actions.add_child(_button("SUMMARY", func() -> void: _show_summary()))
	status_label = _label("等待输入。每次点击 FORGE 只执行一轮，不自动重试。", 18, Color("94a3b8"))
	left.add_child(status_label)
	stage_label = _label(_stage_text(""), 18)
	left.add_child(stage_label)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	columns.add_child(right)
	right.add_child(_label("HISTORY / RECENT INPUTS（最近 10 条）", 21, Color("67e8f9")))
	var recent := await _get_json("/history?session_id=%s" % session_id.uri_encode())
	if bool(recent.get("ok", false)):
		var records: Array = recent["body"].get("records", [])
		if records.is_empty():
			right.add_child(_label("尚无本地试玩记录。", 17, Color("94a3b8")))
		else:
			for record_value: Variant in records:
				var record := record_value as Dictionary
				var text := "%s\n%s · 身份:%s · 训练:%s" % [
					str(record.get("user_input", "")).left(30),
					str(record.get("canonical_identity", "未生成")),
					_tri_state(record.get("identity_confirmed")),
					_yes_no(bool(record.get("entered_training", false))),
				]
				right.add_child(_label(text, 15, Color("cbd5e1")))
	else:
		right.add_child(_label("记录读取失败，但不会触发模型调用。", 16, Color("fb7185")))


func _start_forge() -> void:
	if request_in_flight:
		return
	current_input = input_edit.text.strip_edges()
	if current_input.is_empty():
		status_label.text = "请输入中文描述后再点击 FORGE。"
		return
	if current_input.length() > 500:
		status_label.text = "输入超过 500 字；本轮未提交。"
		return
	identity_confirmed_for_round = false
	launch_combat_after_anchors = false
	training_asset = null
	calibration = null
	blueprint = null
	request_in_flight = true
	input_edit.editable = false
	status_label.text = "正在创建唯一请求；旧请求不能覆盖新请求。"
	current_stage = "semantic_compiling"
	stage_label.text = _stage_text(current_stage)
	var client_request_id := "%s-%s" % [str(Time.get_unix_time_from_system()).replace(".", ""), _random_suffix()]
	var result := await _post_json("/round/start", {
		"session_id": session_id,
		"client_request_id": client_request_id,
		"player_input": current_input,
	})
	if not bool(result.get("ok", false)):
		request_in_flight = false
		input_edit.editable = true
		_show_failure(str(result.get("failure_stage", "request")), str(result.get("failure_reason", "UNKNOWN")))
		return
	var body: Dictionary = result["body"]
	current_round_id = str(body["round_id"])
	revision = int(body["revision"])
	_poll_round(current_round_id, revision)


func _poll_round(expected_round: String, expected_revision: int) -> void:
	while request_in_flight and current_round_id == expected_round and revision == expected_revision:
		await get_tree().create_timer(0.5).timeout
		var route := "/round/status?session_id=%s&round_id=%s&revision=%d" % [
			session_id.uri_encode(), expected_round.uri_encode(), expected_revision
		]
		var result := await _get_json(route)
		if not bool(result.get("ok", false)):
			request_in_flight = false
			_show_failure(str(result.get("failure_stage", "bridge")), str(result.get("failure_reason", "STATUS_FAILED")))
			return
		var body: Dictionary = result["body"]
		if current_round_id != expected_round or revision != expected_revision:
			return
		current_stage = str(body.get("stage", ""))
		status_label.text = "处理中：%s。0 自动重试，0 Mock 回退。" % str(STAGE_NAMES.get(current_stage, current_stage))
		stage_label.text = _stage_text(current_stage)
		if current_stage == "failed":
			request_in_flight = false
			_show_failure(str(body.get("failure_stage", "unknown")), str(body.get("failure_reason", "UNKNOWN")))
			return
		if current_stage == "confirm_identity":
			request_in_flight = false
			current_response = body
			if not _load_result_images(body):
				_show_failure("godot_delivery", "RAW_OR_SPRITE_PNG_INVALID")
				return
			_show_identity_confirmation()
			return


func _resume_current_round() -> void:
	if request_in_flight:
		return
	_show_wait("正在读取当前会话状态；不会调用 Claude、FLUX 或 BiRefNet……")
	var recent := await _get_json("/history?session_id=%s" % session_id.uri_encode())
	if not bool(recent.get("ok", false)):
		_show_resume_unavailable("无法读取本地会话记录。")
		return
	var candidate: Dictionary = {}
	for value: Variant in recent["body"].get("records", []):
		var record := value as Dictionary
		if str(record.get("status", "")) in RESUMABLE_STAGES:
			candidate = record
			break
	if candidate.is_empty():
		_show_resume_unavailable("当前没有可恢复的进行中轮次。")
		return
	current_round_id = str(candidate.get("round_id", ""))
	revision = int(candidate.get("revision", 0))
	current_input = str(candidate.get("user_input", current_input))
	if current_round_id.is_empty() or revision <= 0:
		_show_resume_unavailable("进行中轮次缺少安全恢复标识。")
		return
	var route := "/round/status?session_id=%s&round_id=%s&revision=%d" % [
		session_id.uri_encode(), current_round_id.uri_encode(), revision
	]
	var result := await _get_json(route)
	if not bool(result.get("ok", false)):
		_show_resume_unavailable("进行中轮次状态读取失败：%s" % str(result.get("failure_reason", "STATUS_FAILED")))
		return
	var body: Dictionary = result["body"]
	current_stage = str(body.get("stage", ""))
	if current_stage in ["semantic_compiling", "image_generating", "background_removing", "sprite_processing"]:
		await _show_forge_screen(false)
		request_in_flight = true
		status_label.text = "已恢复进行中的生成；不会创建第二个请求。"
		stage_label.text = _stage_text(current_stage)
		_poll_round(current_round_id, revision)
		return
	if current_stage not in ["confirm_identity", "confirm_anchors"]:
		_show_resume_unavailable("该轮次当前阶段无法由此界面恢复：%s" % current_stage)
		return
	current_response = body
	if not _load_result_images(body):
		_show_resume_unavailable("现有轮次的 Raw 或 Sprite 文件校验失败。")
		return
	if current_stage == "confirm_identity":
		identity_confirmed_for_round = false
		_show_identity_confirmation()
		return
	identity_confirmed_for_round = true
	launch_combat_after_anchors = false
	if str(current_response.get("behavior_family", "")) == "heavy_melee":
		_show_heavy_melee_entry_prompt()
	else:
		_show_anchor_confirmation()


func _show_resume_unavailable(message: String) -> void:
	_clear_screen()
	var box := _vbox(_panel(), 140, 120, 1140, 580)
	box.add_child(_title("无法恢复当前轮次"))
	box.add_child(_label(message, 21, Color("fb7185")))
	box.add_child(_label("没有创建新请求，也没有调用任何模型。玩家输入仍然保留。", 19, Color("fbbf24")))
	box.add_child(_button("返回试玩输入", func() -> void: _show_forge_screen(false)))


func _load_result_images(body: Dictionary) -> bool:
	var raw_bytes := Marshalls.base64_to_raw(str(body.get("raw_png_base64", "")))
	var sprite_bytes := Marshalls.base64_to_raw(str(body.get("sprite_png_base64", "")))
	raw_image = Image.new()
	sprite_image = Image.new()
	if raw_image.load_png_from_buffer(raw_bytes) != OK:
		return false
	if sprite_image.load_png_from_buffer(sprite_bytes) != OK or sprite_image.get_size() != Vector2i(96, 96):
		return false
	if not sprite_image.detect_alpha():
		return false
	raw_texture = ImageTexture.create_from_image(raw_image)
	sprite_texture = ImageTexture.create_from_image(sprite_image)
	return true


func _show_identity_confirmation() -> void:
	_clear_screen()
	var panel := _panel()
	var columns := HBoxContainer.new()
	columns.position = Vector2(36, 30)
	columns.size = Vector2(1208, 660)
	columns.add_theme_constant_override("separation", 24)
	panel.add_child(columns)
	var images := VBoxContainer.new()
	images.custom_minimum_size.x = 650
	columns.add_child(images)
	images.add_child(_title("确认物件身份"))
	var previews := HBoxContainer.new()
	previews.add_theme_constant_override("separation", 16)
	images.add_child(previews)
	previews.add_child(_image_card("FLUX 原始图", raw_texture, Vector2(315, 315), Color("25102f")))
	previews.add_child(_image_card("96×96 透明 Sprite", sprite_texture, Vector2(315, 315), Color("132333")))
	images.add_child(_label("玩家原文：%s" % current_input, 19))
	images.add_child(_label("AI 解释：%s" % str(current_response.get("semantic_summary", "")), 19, Color("67e8f9")))
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 14)
	columns.add_child(right)
	right.add_child(_label("仍然能认出这是原物件吗？", 27, Color("fbbf24")))
	right.add_child(_label("基础身份：%s\n行为家族：%s" % [
		str(current_response.get("canonical_name_zh", "")), str(current_response.get("behavior_family", ""))
	], 20))
	var parts: Array = current_response.get("required_identity_parts", [])
	var part_names := PackedStringArray()
	for part: Variant in parts:
		part_names.append(str(part))
	right.add_child(_label("身份关键结构（仅供查看，不要求逐项勾选）：\n• %s" % "\n• ".join(part_names), 18, Color("cbd5e1")))
	right.add_child(_label("可选失败原因 / 试玩备注：", 17))
	identity_notes = TextEdit.new()
	identity_notes.custom_minimum_size.y = 105
	identity_notes.placeholder_text = "可留空；如果选择“否”，建议写下看成了什么或缺少什么。"
	identity_notes.add_theme_font_size_override("font_size", 18)
	right.add_child(identity_notes)
	right.add_child(_button("是，继续确认握持点与作用点", func() -> void: _submit_identity(true)))
	right.add_child(_button("否，本轮结束", func() -> void: _submit_identity(false), Color("7f1d1d")))


func _submit_identity(confirmed: bool) -> void:
	var result := await _post_json("/round/identity", {
		"session_id": session_id,
		"round_id": current_round_id,
		"revision": revision,
		"identity_confirmed": confirmed,
		"user_notes": identity_notes.text,
	})
	if not bool(result.get("ok", false)):
		_show_failure(str(result.get("failure_stage", "identity_confirmation")), str(result.get("failure_reason", "UNKNOWN")))
		return
	identity_confirmed_for_round = confirmed
	if confirmed:
		if str(current_response.get("behavior_family", "")) == "heavy_melee":
			_show_heavy_melee_entry_prompt()
		else:
			_show_anchor_confirmation()
	else:
		_show_round_complete("你已判定物件身份不正确；本轮未进入锚点或训练区。")


func _show_heavy_melee_entry_prompt() -> void:
	launch_combat_after_anchors = false
	if not _affordance_grammar_ready():
		_show_anchor_confirmation()
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "完整近战手感测试"
	dialog.dialog_text = "该武器支持完整近战手感测试。\n训练区只提供基础挥动预览。\n是否现在进入近战手感测试？\n\n选择进入后，先确认握持点与作用点，再直接载入当前真实生成武器。"
	dialog.ok_button_text = "进入近战手感测试"
	dialog.cancel_button_text = "稍后"
	dialog.exclusive = true
	screen_root.add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		launch_combat_after_anchors = true
		_show_anchor_confirmation()
	)
	dialog.canceled.connect(func() -> void:
		launch_combat_after_anchors = false
		_show_anchor_confirmation()
	)
	dialog.popup_centered(Vector2i(760, 280))
	dialog.get_ok_button().call_deferred("grab_focus")


func _show_anchor_confirmation() -> void:
	blueprint = _make_gameplay_projection()
	calibration = ANCHOR_RESOLVER.resolve(sprite_image, blueprint) as SemanticAnchorCalibration
	if calibration == null:
		_show_failure("anchor_resolver", "VALID_ALPHA_COULD_NOT_BE_RESOLVED")
		return
	calibration.case_id = current_round_id
	calibration.run_id = session_id
	calibration.source_sprite = "processed_sprite.png"
	anchor_steps = ["GripPrimary", str(current_response["second_anchor_type"])]
	anchor_step_index = 0
	_clear_screen()
	var panel := _panel()
	var columns := HBoxContainer.new()
	columns.position = Vector2(56, 44)
	columns.size = Vector2(1168, 630)
	columns.add_theme_constant_override("separation", 40)
	panel.add_child(columns)
	anchor_canvas = ANCHOR_CANVAS.new()
	anchor_canvas.anchor_confirmed.connect(_on_anchor_confirmed)
	columns.add_child(anchor_canvas)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	if str(current_response.get("behavior_family", "")) == "heavy_melee" and not _affordance_grammar_ready():
		right.add_child(_label("当前语义结果没有经过验证的 Affordance 机制轴；本轮只提供基础训练预览，不会静默回退旧近战动作。", 17, Color("fb923c")))
	right.add_child(_title("确认锚点"))
	var instruction := _label("", 24, Color("fbbf24"))
	instruction.name = "AnchorInstruction"
	right.add_child(instruction)
	right.add_child(_label("先确认 GripPrimary，再确认行为需要的作用点。点击物件或拖动十字；自动解析只提供建议。", 19))
	var confirm := _button("确认当前位置", func() -> void: anchor_canvas.confirm_current())
	confirm.custom_minimum_size.y = 62
	right.add_child(confirm)
	_configure_anchor_step()


func _configure_anchor_step() -> void:
	var anchor_type := anchor_steps[anchor_step_index]
	var question := "你准备从哪里拿住它？" if anchor_type == "GripPrimary" else str(current_response["second_anchor_question"])
	var instruction := screen_root.find_child("AnchorInstruction", true, false) as Label
	instruction.text = "%d/2　%s（%s）" % [anchor_step_index + 1, question, anchor_type]
	var known: Dictionary = {}
	for key: String in calibration.auto_anchors.keys():
		if key != anchor_type:
			known[key] = calibration.anchor_point(key)
	var suggestion := calibration.anchor_point(anchor_type)
	if anchor_step_index == 0:
		anchor_canvas.configure(sprite_texture, anchor_type, suggestion, known)
	else:
		anchor_canvas.set_step(anchor_type, suggestion, known)


func _on_anchor_confirmed(anchor_type: String, point: Vector2) -> void:
	if anchor_type != anchor_steps[anchor_step_index]:
		return
	calibration.set_manual_anchor(anchor_type, point, 0.95)
	calibration.anchor_source[anchor_type] = "player_confirmed_open_playtest"
	if anchor_type == "GripPrimary":
		ANCHOR_RESOLVER.recompute_derived(calibration, sprite_image)
	anchor_step_index += 1
	if anchor_step_index < anchor_steps.size():
		_configure_anchor_step()
		return
	_submit_anchors()


func _submit_anchors() -> void:
	var errors := calibration.validation_errors()
	if not errors.is_empty():
		_show_failure("anchor_confirmation", ", ".join(errors))
		return
	var result := await _post_json("/round/anchors", {
		"session_id": session_id,
		"round_id": current_round_id,
		"revision": revision,
		"anchors": calibration.to_dict(),
	})
	if not bool(result.get("ok", false)):
		_show_failure(str(result.get("failure_stage", "anchor_confirmation")), str(result.get("failure_reason", "UNKNOWN")))
		return
	training_asset = calibration.apply_to_asset()
	if training_asset == null:
		_show_failure("anchor_delivery", "TRAINING_ASSET_INVALID")
		return
	if launch_combat_after_anchors:
		launch_combat_after_anchors = false
		_show_combat_feel_handoff()
		_launch_combat_feel()
		return
	_enter_training()


func _show_combat_feel_handoff() -> void:
	_clear_screen()
	var box := _vbox(_panel(), 170, 115, 1110, 600)
	box.add_child(_title("正在进入近战手感测试"))
	box.add_child(_label("将载入当前真实生成的 heavy_melee 武器、玩家确认锚点和通用 motion profile。", 22, Color("67e8f9")))
	box.add_child(_label("Combat Feel Slice 才包含三段连击、蓄力重击、闪避后攻击、敌人、hitstop 与命中反馈。\n不会使用 developer fixture，也不会回退固定武器。", 20, Color("fbbf24")))
	combat_launch_status = _label("正在打开独立近战手感测试窗口……", 20, Color("cbd5e1"))
	box.add_child(combat_launch_status)
	box.add_child(_button("稍后返回基础训练预览", func() -> void: _enter_training()))


func _enter_training() -> void:
	_clear_screen()
	arena = TRAINING_ARENA.new()
	add_child(arena)
	arena.start_stage("training", blueprint, training_asset)
	training_initial_position = arena.player_position
	training_active = true
	moved_once = false
	attacked_once = false
	dodged_once = false
	training_preview_tip_shown = false
	var overlay := PanelContainer.new()
	overlay.position = Vector2(28, 18)
	overlay.size = Vector2(1224, 242)
	screen_root.add_child(overlay)
	var box := VBoxContainer.new()
	overlay.add_child(box)
	box.add_child(_label("OPEN PLAYTEST · 基础训练预览（非完整战斗动作）", 23, Color("fbbf24")))
	if blueprint.behavior_family == "heavy_melee":
		box.add_child(_label("当前为基础训练预览：这里只验证握持、基础挥动和锚点。\n这里不提供完整三段连击或正式打击感。\n如需测试近战手感，请点击“进入近战手感测试（TEST HEAVY MELEE FEEL）”。", 18, Color("fb923c")))
	else:
		box.add_child(_label("当前只验证握持、基础攻击预览和锚点；这里不是完整战斗测试。", 18, Color("fb923c")))
	box.add_child(_label("键盘：WASD/方向键移动　空格/J攻击　K/Shift闪避", 17))
	if blueprint.behavior_family == "heavy_melee":
		box.add_child(_label("近战提示：先靠近蓝色圆靶到一个武器长度内再预览挥动；“攻击：是”只表示输入已触发。完整三段攻击仅在 Combat Feel Slice 中测试。", 16, Color("fde68a")))
	training_status = _label("移动：否　攻击：否　闪避：否", 17, Color("fbbf24"))
	box.add_child(training_status)
	training_preview_tip = _label("", 16, Color("67e8f9"))
	box.add_child(training_preview_tip)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	box.add_child(actions)
	var left_button := _button("←", Callable())
	left_button.button_down.connect(func() -> void: arena.set_touch_vector(Vector2.LEFT))
	left_button.button_up.connect(func() -> void: arena.set_touch_vector(Vector2.ZERO))
	actions.add_child(left_button)
	var right_button := _button("→", Callable())
	right_button.button_down.connect(func() -> void: arena.set_touch_vector(Vector2.RIGHT))
	right_button.button_up.connect(func() -> void: arena.set_touch_vector(Vector2.ZERO))
	actions.add_child(right_button)
	var attack_text := "基础挥动预览" if blueprint.behavior_family == "heavy_melee" else "基础攻击预览"
	var attack_button := _button(attack_text, Callable())
	if blueprint.behavior_family == "heavy_melee":
		attack_button.tooltip_text = "非完整战斗动作；完整三段攻击仅在 Combat Feel Slice 中测试。"
	if blueprint.behavior_family in ["heavy_melee", "returning_thrown"]:
		attack_button.pressed.connect(func() -> void: arena.request_touch_attack())
	else:
		attack_button.button_down.connect(func() -> void: arena.set_touch_attack(true))
		attack_button.button_up.connect(func() -> void: arena.set_touch_attack(false))
	actions.add_child(attack_button)
	actions.add_child(_button("闪避", func() -> void: arena.request_touch_dodge()))
	actions.add_child(_button("结束训练并评价", func() -> void: _finish_training()))


func _finish_training() -> void:
	training_active = false
	if arena != null:
		arena.set_touch_attack(false)
		arena.set_touch_vector(Vector2.ZERO)
	var result := await _post_json("/round/training", {
		"session_id": session_id,
		"round_id": current_round_id,
		"revision": revision,
		"moved": moved_once,
		"attacked": attacked_once,
		"dodged": dodged_once,
	})
	if not bool(result.get("ok", false)):
		_show_failure(str(result.get("failure_stage", "training")), str(result.get("failure_reason", "UNKNOWN")))
		return
	_show_round_complete("基础训练预览已完成。可记录评分并保存到本机试玩日志。")


func _show_round_complete(message: String) -> void:
	_cleanup_training()
	_clear_screen()
	var box := _vbox(_panel(), 120, 45, 1060, 675)
	box.add_child(_title("本轮试玩完成"))
	box.add_child(_label(message, 21, Color("5eead4")))
	box.add_child(_label("输入：%s\n生成：%s\n行为：%s" % [
		current_input,
		str(current_response.get("display_name_zh", current_response.get("canonical_name_zh", "未生成"))),
		str(current_response.get("behavior_family", "未生成")),
	], 19))
	box.add_child(_label("主观评分（1低—5高）：", 18))
	feedback_rating = OptionButton.new()
	for score: int in range(1, 6):
		feedback_rating.add_item(str(score), score)
	feedback_rating.select(2)
	feedback_rating.custom_minimum_size.y = 48
	box.add_child(feedback_rating)
	feedback_keep = CheckBox.new()
	feedback_keep.text = "我想保留这个点子"
	feedback_keep.add_theme_font_size_override("font_size", 19)
	box.add_child(feedback_keep)
	feedback_notes = TextEdit.new()
	feedback_notes.custom_minimum_size.y = 90
	feedback_notes.placeholder_text = "试玩备注（可选）"
	feedback_notes.add_theme_font_size_override("font_size", 18)
	box.add_child(feedback_notes)
	if _can_launch_current_heavy_melee():
		box.add_child(_label("完整近战手感请在 Combat Feel Slice 中判断；上面的基础训练预览不代表最终动作差异。", 18, Color("fbbf24")))
		var primary_action := _primary_button("进入近战手感测试", func() -> void: _launch_combat_feel())
		box.add_child(primary_action)
		primary_action.call_deferred("grab_focus")
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	box.add_child(actions)
	actions.add_child(_button("SAVE THIS RESULT", func() -> void: _save_result()))
	actions.add_child(_button("RETRY THIS IDEA", func() -> void: _show_forge_screen(false)))
	actions.add_child(_button("FORGE NEW IDEA", func() -> void: _show_forge_screen(true)))
	actions.add_child(_button("SUMMARY", func() -> void: _show_summary()))


func _launch_combat_feel() -> void:
	if not _can_launch_current_heavy_melee():
		_set_combat_launch_status("无法启动：仅已确认身份和锚点的真实 heavy_melee 结果可以进入；不会回退 fixture。", true)
		return
	var round_output_path := str(current_response.get("round_output_path", ""))
	if round_output_path.is_empty():
		_set_combat_launch_status("无法启动：本轮最终资产目录缺失。输入和当前结果仍保留。", true)
		return
	var arguments := PackedStringArray([
		"--path", ProjectSettings.globalize_path("res://"), COMBAT_FEEL_SCENE,
		"--", "--mode=combat-feel-slice-0", "--open-playtest-round=%s" % round_output_path,
		"--require-affordance-grammar",
	])
	var process_id := OS.create_process(OS.get_executable_path(), arguments)
	if process_id <= 0:
		_set_combat_launch_status("无法启动 Combat Feel Slice；本轮结果未被修改。", true)
		return
	_set_combat_launch_status("已打开 Combat Feel Slice：当前真实生成武器已直接交付。", false)


func _can_launch_current_heavy_melee() -> bool:
	return (
		identity_confirmed_for_round
		and str(current_response.get("behavior_family", "")) == "heavy_melee"
		and _affordance_grammar_ready()
		and training_asset != null
		and calibration != null
	)


func _affordance_grammar_ready() -> bool:
	return bool(current_response.get("affordance_grammar_ready", false))


func _set_combat_launch_status(message: String, is_error: bool) -> void:
	var color := Color("fb7185") if is_error else Color("5eead4")
	if combat_launch_status != null and is_instance_valid(combat_launch_status):
		combat_launch_status.text = message
		combat_launch_status.add_theme_color_override("font_color", color)
		return
	if feedback_notes != null and is_instance_valid(feedback_notes):
		feedback_notes.get_parent().add_child(_label(message, 18, color))


func _save_result() -> void:
	var result := await _post_json("/round/save", {
		"session_id": session_id,
		"round_id": current_round_id,
		"revision": revision,
		"subjective_rating": feedback_rating.get_item_id(feedback_rating.selected),
		"keep_idea": feedback_keep.button_pressed,
		"user_notes": feedback_notes.text,
	})
	if not bool(result.get("ok", false)):
		_show_failure(str(result.get("failure_stage", "save")), str(result.get("failure_reason", "UNKNOWN")))
		return
	var saved := _label("已保存到本机 JSON/CSV；没有同步到云端或正式资产库。", 18, Color("5eead4"))
	feedback_notes.get_parent().add_child(saved)


func _show_summary() -> void:
	_cleanup_training()
	_show_wait("正在读取本地试玩总结……")
	var result := await _get_json("/summary?session_id=%s" % session_id.uri_encode())
	if not bool(result.get("ok", false)):
		_show_failure(str(result.get("failure_stage", "history")), str(result.get("failure_reason", "UNKNOWN")))
		return
	_clear_screen()
	var box := _vbox(_panel(), 70, 35, 1210, 685)
	box.add_child(_title("Open Playtest 本地总结"))
	box.add_child(_label("仅显示最近 10 条；数据保存在本机 JSON/CSV，不做云同步。", 18, Color("94a3b8")))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 510
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 12)
	scroll.add_child(rows)
	var records: Array = result["body"].get("records", [])
	if records.is_empty():
		rows.add_child(_label("还没有试玩记录。", 20))
	else:
		for value: Variant in records:
			var record := value as Dictionary
			rows.add_child(_label("%s\n输入：%s\n生成：%s　身份：%s　训练：%s　评分：%s　保留：%s" % [
				str(record.get("timestamp", "")),
				str(record.get("user_input", "")),
				str(record.get("display_name", "未生成")),
				_tri_state(record.get("identity_confirmed")),
				_yes_no(bool(record.get("entered_training", false))),
				str(record.get("subjective_rating", "—")),
				_tri_state(record.get("keep_idea")),
			], 17, Color("cbd5e1")))
	box.add_child(_button("返回试玩输入", func() -> void: _show_forge_screen(false)))


func _show_failure(stage: String, reason: String) -> void:
	request_in_flight = false
	_cleanup_training()
	_clear_screen()
	var box := _vbox(_panel(), 120, 80, 1060, 610)
	box.add_child(_title("本轮失败：%s" % stage))
	box.add_child(_label("准确原因：%s" % reason, 20, Color("fb7185")))
	box.add_child(_label("玩家输入已保留：\n%s" % current_input, 20))
	box.add_child(_label("没有自动重试，没有固定武器替换，也没有 Mock 回退。", 19, Color("fbbf24")))
	if reason == "ROUND_IN_PROGRESS":
		var resume := _primary_button("恢复当前进行中的轮次", func() -> void: _resume_current_round())
		box.add_child(resume)
		resume.call_deferred("grab_focus")
	box.add_child(_button("REFORGE SAME IDEA", func() -> void: _show_forge_screen(false)))
	box.add_child(_button("TRY NEW IDEA", func() -> void: _show_forge_screen(true)))
	box.add_child(_button("查看本地总结", func() -> void: _show_summary()))


func _make_gameplay_projection() -> WeaponBlueprint:
	var value := WeaponBlueprint.new()
	value.id = "open-%s-%s" % [session_id, current_round_id]
	value.display_name = str(current_response.get("display_name_zh", current_response.get("canonical_name_zh", "试玩物件")))
	value.source_identity = current_input
	value.player_identity_text = current_input
	value.identity_confidence = 1.0
	value.visual_description = str(current_response.get("canonical_name_zh", ""))
	value.preserved_visual_features.clear()
	for part: Variant in current_response.get("required_identity_parts", []):
		value.preserved_visual_features.append(str(part))
	value.behavior_family = str(current_response["behavior_family"])
	value.delivery = str(current_response["delivery"])
	value.impact_mode = str(current_response["impact_mode"])
	value.effect_type = str(current_response["effect_type"])
	value.drawback = str(current_response["drawback"])
	value.cadence = str(current_response["cadence_hint"])
	value.weapon_form = "player_identity_object"
	value.modifiers = {}
	match value.behavior_family:
		"returning_thrown":
			value.grip_profile = "throwable_center"
			value.weight_class = "medium"
		"heavy_melee":
			value.grip_profile = "two_hand_rear"
			value.weight_class = "heavy"
		_:
			value.grip_profile = "center_shaft"
			value.weight_class = "medium"
	match value.effect_type:
		"fire", "thermal_emission": value.element = "fire"
		"electric", "electric_current": value.element = "electric"
		"lifesteal": value.element = "life"
		_: value.element = "normal"
	return value


func _get_json(route: String) -> Dictionary:
	return await _http_json(route, HTTPClient.METHOD_GET, {})


func _post_json(route: String, body: Dictionary) -> Dictionary:
	return await _http_json(route, HTTPClient.METHOD_POST, body)


func _http_json(route: String, method: int, body: Dictionary) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = 30.0
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
	var response := decoded as Dictionary
	if response_code < 200 or response_code >= 300:
		return {
			"ok": false,
			"failure_stage": str(response.get("failure_stage", "bridge")),
			"failure_reason": str(response.get("failure_reason", "HTTP_%d" % response_code)),
		}
	return {"ok": true, "body": response}


func _cleanup_training() -> void:
	training_active = false
	training_preview_tip = null
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
	box.add_theme_constant_override("separation", 17)
	parent.add_child(box)
	return box


func _title(text: String) -> Label:
	return _label(text, 33, Color("f8fafc"))


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
	button.add_theme_font_size_override("font_size", 19)
	button.add_theme_color_override("font_color", Color("f8fafc"))
	button.modulate = color.lightened(0.55)
	if callback.is_valid():
		button.pressed.connect(callback)
	return button


func _primary_button(text: String, callback: Callable) -> Button:
	var button := _button(text, callback, Color("0f766e"))
	button.custom_minimum_size.y = 72
	button.add_theme_font_size_override("font_size", 24)
	button.add_theme_color_override("font_focus_color", Color("ffffff"))
	button.add_theme_color_override("font_hover_color", Color("ffffff"))
	button.tooltip_text = "载入当前真实生成武器；不使用 fixture。"
	return button


func _image_card(caption: String, texture: Texture2D, size: Vector2, color: Color) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.custom_minimum_size = size
	box.add_child(_label(caption, 17, Color("cbd5e1")))
	var background := ColorRect.new()
	background.color = color
	background.custom_minimum_size = Vector2(size.x, size.y - 28.0)
	box.add_child(background)
	var preview := TextureRect.new()
	preview.texture = texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	background.add_child(preview)
	return box


func _semantic_mode_label() -> String:
	if semantic_mode == "affordance_v1_2_2":
		return "显式实验语义模式：AFFORDANCE GRAMMAR · %s" % semantic_contract
	return "默认语义模式：%s · 不生成 Motion Grammar Affordance" % semantic_contract


func _stage_text(active: String) -> String:
	var lines: Array[String] = []
	var active_index := STAGES.find(active)
	for index: int in range(STAGES.size()):
		var stage: String = STAGES[index]
		var marker := "○"
		if active_index >= 0 and index < active_index:
			marker = "✓"
		elif stage == active:
			marker = "▶"
		lines.append("%s %s" % [marker, str(STAGE_NAMES[stage])])
	return "\n".join(lines)


func _show_wait(message: String) -> void:
	_clear_screen()
	var box := _vbox(_panel(), 120, 130, 1060, 530)
	box.add_child(_title("Forge Open Playtest"))
	box.add_child(_label(message, 23, Color("67e8f9")))


func _show_fatal(message: String) -> void:
	_cleanup_training()
	_clear_screen()
	var box := _vbox(_panel(), 100, 90, 1080, 590)
	box.add_child(_title("Open Playtest 未启动"))
	box.add_child(_label(message, 22, Color("fb7185")))
	box.add_child(_label("默认 MOCK 未改变；没有自动联网或 Mock 回退。", 19, Color("fbbf24")))
	box.add_child(_button("关闭", func() -> void: get_tree().quit(), Color("7f1d1d")))


func _argument_value(arguments: PackedStringArray, prefix: String, fallback: String) -> String:
	for argument: String in arguments:
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return fallback


func _random_suffix() -> String:
	return "%08x" % randi()


func _yes_no(value: bool) -> String:
	return "是" if value else "否"


func _tri_state(value: Variant) -> String:
	if value == null:
		return "未评价"
	return "是" if bool(value) else "否"
