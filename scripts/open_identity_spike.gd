extends Node2D

const OPEN_INTERPRETER := preload("res://scripts/services/open_identity_interpreter.gd")
const OPEN_VISUAL_PROMPT := preload("res://scripts/services/open_identity_visual_prompt.gd")
const LOCAL_PROVIDER := preload("res://scripts/services/local_comfy_forge_visual_provider.gd")
const MOCK_PROVIDER := preload("res://scripts/services/mock_forge_visual_provider.gd")
const SKETCH_CANVAS := preload("res://scripts/ui/sketch_canvas.gd")
const WEAPON_PREVIEW := preload("res://scripts/ui/weapon_preview.gd")
const TOUCH_STICK := preload("res://scripts/ui/touch_stick.gd")
const GAMEPLAY_ARENA := preload("res://scripts/systems/open_identity_training_arena.gd")
const MODE_MOCK := "MOCK"
const MODE_LOCAL_COMFYUI := "LOCAL_COMFYUI"

var interpreter := OPEN_INTERPRETER.new()
var provider
var provider_mode := MODE_MOCK
var arena: GameplayArena
var ui_layer: CanvasLayer
var page: Control
var app_theme: Theme
var state := "forge"
var input_mode := "description"
var description_edit: TextEdit
var sketch_canvas: SketchCanvas
var error_label: Label
var status_label: Label
var identity_answer_edit: LineEdit
var pending_clarification_kind := ""
var current_input_signature := ""
var pending_input_signature := ""
var clarified_input_signature := ""
var clarified_identity := ""
var clarified_behavior_family := ""
var clarification_used := false
var generation_pending := false
var generation_started_msec := 0
var current_blueprint: WeaponBlueprint
var current_asset: WeaponVisualAsset
var current_explanation := ""
var current_interpretation_source := ""
var current_visual_source := ""
var current_manifest: Dictionary = {}
var current_output_directory := ""
var saved_description := ""
var saved_canvas_geometry: Dictionary = {}
var saved_geometry: Dictionary = {}
var saved_sketch_png := PackedByteArray()
var visual_identity_confirmed := false
var hud_stats: Label

func _ready() -> void:
	randomize()
	_build_theme()
	provider_mode = _argument_value("--visual-provider=", MODE_MOCK).to_upper()
	if provider_mode not in [MODE_LOCAL_COMFYUI, MODE_MOCK]:
		provider_mode = MODE_MOCK
	arena = GAMEPLAY_ARENA.new() as GameplayArena
	add_child(arena)
	arena.visible = false
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	_show_forge()

func _process(_delta: float) -> void:
	if not generation_pending or provider == null:
		return
	var result: Dictionary = provider.poll()
	match str(result.get("status", "idle")):
		"running":
			if status_label != null and is_instance_valid(status_label):
				var elapsed := float(Time.get_ticks_msec() - generation_started_msec) / 1000.0
				status_label.text = "本地 ComfyUI 正在生成、去背景并验证 Alpha…… %.1f / 120 秒" % elapsed
		"success":
			generation_pending = false
			current_asset = result.get("asset") as WeaponVisualAsset
			current_manifest = result.get("manifest", {})
			current_output_directory = str(result.get("output_directory", ""))
			current_visual_source = MODE_LOCAL_COMFYUI
			if current_asset == null:
				_show_generation_failure("LOCAL_COMFYUI_RETURNED_NO_ASSET")
			elif not _manifest_contains_identity():
				current_asset = null
				_show_generation_failure("GENERATION_PROMPT_IDENTITY_EVIDENCE_MISSING")
			else:
				_show_review()
		"failed":
			generation_pending = false
			_show_generation_failure(str(result.get("failure_reason", "LOCAL_COMFYUI_FAILED")))

func _build_theme() -> void:
	app_theme = Theme.new()
	var cjk_font := load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font
	app_theme.default_font = cjk_font
	app_theme.default_font_size = 18
	app_theme.set_color("font_color", "Label", Color("e5edf7"))
	app_theme.set_color("font_color", "Button", Color("f8fafc"))
	app_theme.set_color("font_color", "LineEdit", Color("111827"))
	app_theme.set_color("font_color", "TextEdit", Color("111827"))
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
	app_theme.set_stylebox("normal", "Button", button_box)
	var hover := button_box.duplicate() as StyleBoxFlat
	hover.bg_color = Color("3182ce")
	app_theme.set_stylebox("hover", "Button", hover)
	var pressed := button_box.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("164e75")
	app_theme.set_stylebox("pressed", "Button", pressed)
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
	app_theme.set_stylebox("normal", "LineEdit", field_box)
	app_theme.set_stylebox("normal", "TextEdit", field_box)
	RenderingServer.set_default_clear_color(Color("07111f"))

func _show_forge() -> void:
	state = "forge"
	generation_pending = false
	visual_identity_confirmed = false
	if provider != null:
		provider.cancel_current()
	provider = null
	arena.stop()
	arena.visible = false
	var root := _new_page()
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	root.add_child(outer)
	outer.add_child(_header(
		"FORGE PLAYLAB V1 · OPEN IDENTITY SPIKE 2",
		"物件身份决定长什么样；三种行为家族只决定怎么打。本 Spike 仅进入 Forge 与训练区。"
	))
	var top_controls := HBoxContainer.new()
	top_controls.add_theme_constant_override("separation", 8)
	outer.add_child(top_controls)
	for pair: Array in [["只输入文字", "description"], ["文字 + 草图", "description_sketch"], ["只输入草图", "sketch"]]:
		top_controls.add_child(_button(str(pair[0]), func() -> void: _set_input_mode(str(pair[1]))))
	top_controls.add_spacer(false)
	top_controls.add_child(_button("LOCAL_COMFYUI（真实视觉）", func() -> void: _set_provider_mode(MODE_LOCAL_COMFYUI)))
	top_controls.add_child(_button("MOCK（仅固定样例）", func() -> void: _set_provider_mode(MODE_MOCK)))
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 20)
	outer.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(540, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	left.add_child(_section_title("描述这个物件，以及它怎么打"))
	description_edit = TextEdit.new()
	description_edit.custom_minimum_size = Vector2(0, 145)
	description_edit.placeholder_text = "例如：一件会飞出去撞击后返回的旧家具。"
	description_edit.text = saved_description
	description_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	left.add_child(description_edit)
	var boundary := Label.new()
	boundary.text = "身份解释：玩家原文透传。行为解释：本地动作规则。AI 语义解释：尚未验证。"
	boundary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	boundary.modulate = Color("bae6fd")
	left.add_child(boundary)
	left.add_child(_badge(_provider_badge_text(), Color("164e63") if provider_mode == MODE_LOCAL_COMFYUI else Color("854d0e")))
	error_label = Label.new()
	error_label.modulate = Color("fca5a5")
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(error_label)
	left.add_spacer(false)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	left.add_child(actions)
	actions.add_child(_button("按当前身份锻造", _submit_forge, true))
	actions.add_child(_button("载入固定 LOCAL SAMPLE", _start_local_sample))
	var sample_note := Label.new()
	sample_note.text = "LOCAL SAMPLE 明确是固定回归图，不会声称理解上方输入。"
	sample_note.modulate = Color("fcd34d")
	left.add_child(sample_note)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(500, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	var sketch_title := HBoxContainer.new()
	right.add_child(sketch_title)
	var title_label := _section_title("粗草图：只提供轮廓、比例和结构证据")
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sketch_title.add_child(title_label)
	sketch_title.add_child(_button("撤销", func() -> void: sketch_canvas.undo_last()))
	sketch_title.add_child(_button("清除", func() -> void: sketch_canvas.clear_strokes()))
	sketch_canvas = SKETCH_CANVAS.new() as SketchCanvas
	sketch_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(sketch_canvas)
	if not saved_canvas_geometry.is_empty() and int(saved_canvas_geometry.get("stroke_count", 0)) > 0:
		call_deferred("_restore_saved_sketch")

func _restore_saved_sketch() -> void:
	if sketch_canvas != null and is_instance_valid(sketch_canvas):
		sketch_canvas.restore_geometry(saved_canvas_geometry)

func _set_input_mode(next_mode: String) -> void:
	input_mode = next_mode
	if error_label != null:
		var labels := {"description": "只输入文字", "description_sketch": "文字 + 草图", "sketch": "只输入草图"}
		error_label.text = "输入模式：%s" % str(labels.get(next_mode, next_mode))

func _set_provider_mode(next_mode: String) -> void:
	provider_mode = next_mode
	if error_label != null:
		error_label.text = _provider_badge_text()

func _provider_badge_text() -> String:
	if provider_mode == MODE_MOCK:
		return "MOCK · 只允许明确固定 LOCAL SAMPLE · 不理解玩家输入"
	return "LOCAL_COMFYUI · 127.0.0.1 · 桌面运行 · 不调用付费 API"

func _submit_forge() -> void:
	if description_edit == null or sketch_canvas == null:
		return
	_capture_forge_input()
	var has_description := not saved_description.is_empty()
	var has_sketch := int(saved_geometry.get("stroke_count", 0)) > 0
	if input_mode == "description" and not has_description:
		_show_error("请先写下物件身份和它怎么打。")
		return
	if input_mode == "sketch" and not has_sketch:
		_show_error("请先画一笔；系统不会把空白草图默认成固定武器。")
		return
	if input_mode == "description_sketch" and not (has_description and has_sketch):
		_show_error("文字 + 草图模式需要两种证据都存在。")
		return
	current_input_signature = _input_signature(input_mode, saved_description, saved_geometry)
	if current_input_signature != clarified_input_signature:
		_clear_persisted_clarification()
	clarification_used = not _stored_clarification().is_empty()
	var interpretation_text := "" if input_mode == "sketch" else saved_description
	var result: Dictionary = interpreter.interpret(
		interpretation_text,
		saved_sketch_png,
		saved_geometry,
		null,
		"",
		_stored_clarification()
	)
	_handle_interpretation_result(result)

func _capture_forge_input() -> void:
	if description_edit == null or sketch_canvas == null:
		return
	saved_description = description_edit.text.strip_edges()
	saved_canvas_geometry = sketch_canvas.geometry_summary()
	if input_mode == "description":
		# A drawing left on the canvas is preserved for the player, but it is not
		# submitted as evidence while text-only mode is selected.
		saved_geometry = {}
		saved_sketch_png = PackedByteArray()
	else:
		saved_geometry = saved_canvas_geometry.duplicate(true)
		saved_sketch_png = saved_geometry.get("preview_png", PackedByteArray())

func _input_signature(mode: String, text: String, geometry: Dictionary) -> String:
	var evidence := [mode, text, geometry.get("raw_strokes", [])]
	return JSON.stringify(evidence).sha256_text()

func _stored_clarification() -> String:
	if current_input_signature.is_empty() or current_input_signature != clarified_input_signature:
		return ""
	if not clarified_identity.is_empty() and not clarified_behavior_family.is_empty():
		return "IDENTITY::%s::BEHAVIOR::%s" % [clarified_identity, clarified_behavior_family]
	if not clarified_behavior_family.is_empty():
		return "BEHAVIOR::%s" % clarified_behavior_family
	return ""

func _clear_persisted_clarification() -> void:
	clarified_input_signature = ""
	clarified_identity = ""
	clarified_behavior_family = ""
	pending_input_signature = ""
	clarification_used = false

func _handle_interpretation_result(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		_show_generation_failure(str(result.get("error", "INTERPRETATION_FAILED")))
		return
	if bool(result.get("needs_clarification", false)):
		if clarification_used:
			_show_generation_failure("CLARIFICATION_LIMIT_REACHED")
			return
		clarification_used = true
		pending_clarification_kind = str(result.get("clarification_kind", "behavior"))
		pending_input_signature = current_input_signature
		_show_clarification(str(result.get("question", "请补充一次信息。")))
		return
	current_blueprint = result.get("blueprint") as WeaponBlueprint
	if current_blueprint == null:
		_show_generation_failure("INTERPRETER_RETURNED_NO_BLUEPRINT")
		return
	current_explanation = str(result.get("explanation", ""))
	current_interpretation_source = str(result.get("source", "PLAYER TEXT PASSTHROUGH"))
	if bool(result.get("ai_interpretation_used", true)):
		_show_generation_failure("UNAPPROVED_AI_INTERPRETATION_CLAIM")
		return
	if provider_mode == MODE_MOCK:
		_show_generation_failure("MOCK_CANNOT_RENDER_ARBITRARY_PLAYER_IDENTITY")
		return
	_begin_local_generation()

func _show_clarification(question: String) -> void:
	state = "clarification"
	var root := _new_page()
	var card := _center_card(900, 500)
	root.add_child(card)
	var content := card.get_child(0) as VBoxContainer
	content.add_child(_badge("只澄清这一次", Color("7c3aed")))
	content.add_child(_large_label(question, 32))
	if pending_clarification_kind == "identity":
		identity_answer_edit = LineEdit.new()
		identity_answer_edit.placeholder_text = "输入你画的物件名称"
		content.add_child(identity_answer_edit)
		var identity_hint := Label.new()
		identity_hint.text = "本机没有获批准的视觉语言模型。请同时选择它怎么打，避免系统再猜一次。"
		identity_hint.modulate = Color("cbd5e1")
		content.add_child(identity_hint)
	else:
		var behavior_hint := Label.new()
		behavior_hint.text = "物件身份已经保留；这里只确认战斗行为，不会改变它的名称或外形。"
		behavior_hint.modulate = Color("cbd5e1")
		content.add_child(behavior_hint)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	content.add_child(actions)
	actions.add_child(_button("持续释放 / 连续发射", func() -> void: _answer_clarification("sustained_ranged"), true))
	actions.add_child(_button("整个物件飞出并返回", func() -> void: _answer_clarification("returning_thrown"), true))
	actions.add_child(_button("整个物件近身重击", func() -> void: _answer_clarification("heavy_melee"), true))
	error_label = Label.new()
	error_label.modulate = Color("fca5a5")
	content.add_child(error_label)
	content.add_child(_button("返回 Forge", _show_forge))

func _answer_clarification(family: String) -> void:
	if pending_input_signature.is_empty() or pending_input_signature != current_input_signature:
		_show_generation_failure("CLARIFICATION_INPUT_CHANGED")
		return
	var clarification := "BEHAVIOR::%s" % family
	var player_text := saved_description
	var identity_answer := ""
	if pending_clarification_kind == "identity":
		if identity_answer_edit == null or identity_answer_edit.text.strip_edges().is_empty():
			_show_error("请先回答：你画的是什么？")
			return
		identity_answer = identity_answer_edit.text.strip_edges()
		player_text = ""
		clarification = "IDENTITY::%s::BEHAVIOR::%s" % [identity_answer, family]
	clarified_input_signature = pending_input_signature
	clarified_behavior_family = family
	clarified_identity = identity_answer
	pending_clarification_kind = ""
	pending_input_signature = ""
	var result: Dictionary = interpreter.interpret(
		player_text, saved_sketch_png, saved_geometry, null, "", clarification
	)
	if bool(result.get("needs_clarification", false)):
		_show_generation_failure("CLARIFICATION_LIMIT_REACHED")
		return
	_handle_interpretation_result(result)

func _begin_local_generation() -> void:
	if OS.has_feature("web"):
		_show_generation_failure("LOCAL_COMFYUI_DESKTOP_ONLY")
		return
	var local_provider = LOCAL_PROVIDER.new()
	local_provider.output_case_id = "open_identity_spike2"
	local_provider.developer_sketch_edit_enabled = _has_user_argument("--flux2-enable-sketch-edit")
	var requested_profile := _argument_value("--comfy-profile=", "")
	local_provider.requested_profile = requested_profile
	provider = local_provider
	var default_config_path := "res://tools/comfyui/open_identity/config/forge_open_identity_config.local.json"
	if not requested_profile.is_empty():
		default_config_path = "res://tools/comfyui/config/profiles/%s.runtime.local.json" % requested_profile
	var config_path := _argument_value("--comfy-config=", default_config_path)
	var configured: Dictionary = local_provider.configure(config_path)
	if not bool(configured.get("ok", false)):
		_show_generation_failure(str(configured.get("error", "COMFYUI_CONFIG_FAILED")))
		return
	# The bridge performs its health check inside the child process. Keeping it
	# there prevents the Godot main thread from freezing on an unavailable API.
	visual_identity_confirmed = false
	local_provider.request_visual(
		current_blueprint,
		current_blueprint.player_identity_text,
		saved_sketch_png,
		0.45
	)
	generation_pending = true
	generation_started_msec = Time.get_ticks_msec()
	_show_generating()

func _show_generating() -> void:
	state = "generating"
	var root := _new_page()
	var card := _center_card(850, 400)
	root.add_child(card)
	var content := card.get_child(0) as VBoxContainer
	content.add_child(_badge("LOCAL_COMFYUI · 真实生成", Color("164e63")))
	content.add_child(_large_label("正在保留物件身份并生成视觉", 32))
	status_label = Label.new()
	status_label.text = "请求已提交；120 秒后明确超时，不会自动换成固定武器。"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(status_label)
	var identity := Label.new()
	identity.text = "玩家身份原文：%s" % current_blueprint.player_identity_text
	identity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	identity.modulate = Color("bae6fd")
	content.add_child(identity)
	content.add_child(_button("取消并返回 Forge（保留输入）", _cancel_generation, true))

func _cancel_generation() -> void:
	if provider != null:
		provider.cancel_current()
	generation_pending = false
	_show_forge()

func _show_generation_failure(code: String) -> void:
	state = "error"
	generation_pending = false
	var root := _new_page()
	var card := _center_card(860, 460)
	root.add_child(card)
	var content := card.get_child(0) as VBoxContainer
	content.add_child(_badge("没有生成成功", Color("991b1b")))
	content.add_child(_large_label("玩家文字与草图仍然保留", 32))
	var details := Label.new()
	details.text = "错误：%s\n不会自动改成加特林、雨伞或大剑，也不会伪装成真实理解成功。" % code
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(details)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	content.add_child(actions)
	actions.add_child(_button("返回 Forge", _show_forge, true))
	if current_blueprint != null and provider_mode == MODE_LOCAL_COMFYUI:
		actions.add_child(_button("重试本地生成", _begin_local_generation))
	content.add_child(_button("明确载入固定 LOCAL SAMPLE", _start_local_sample))

func _start_local_sample() -> void:
	if state == "forge" and description_edit != null and is_instance_valid(description_edit):
		_capture_forge_input()
	if provider != null:
		provider.cancel_current()
	generation_pending = false
	visual_identity_confirmed = true
	current_blueprint = WeaponBlueprint.fixed_blueprint("gatling")
	current_blueprint.modifiers["local_sample_only"] = true
	current_explanation = "这是固定的 LOCAL SAMPLE，只验证渲染与训练区加载；它没有解释玩家输入。"
	current_interpretation_source = "EXPLICIT FIXED LOCAL SAMPLE"
	current_visual_source = "LOCAL SAMPLE · PROCEDURAL FIXTURE"
	current_manifest = {}
	current_output_directory = ""
	var mock_provider = MOCK_PROVIDER.new()
	provider = mock_provider
	mock_provider.request_visual(current_blueprint, "", PackedByteArray())
	var result: Dictionary = mock_provider.poll()
	current_asset = result.get("asset") as WeaponVisualAsset
	if current_asset == null:
		_show_generation_failure("LOCAL_SAMPLE_FAILED")
		return
	_show_review()

func _show_review() -> void:
	state = "review"
	arena.visible = false
	var root := _new_page()
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	root.add_child(outer)
	outer.add_child(_header("开放身份锻造结果", "确认物件身份，再只进入训练区。"))
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 22)
	outer.add_child(columns)
	var preview := WEAPON_PREVIEW.new() as WeaponPreview
	preview.custom_minimum_size = Vector2(520, 450)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.configure(current_asset, false, false, current_blueprint.display_name)
	columns.add_child(preview)
	var details := VBoxContainer.new()
	details.custom_minimum_size = Vector2(580, 0)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(details)
	var is_sample := bool(current_blueprint.modifiers.get("local_sample_only", false))
	details.add_child(_badge(
		"LOCAL SAMPLE · 固定回归图 · 未解释输入" if is_sample else "LOCAL_COMFYUI · 身份原文透传 · 未使用 AI 解释",
		Color("854d0e") if is_sample else Color("164e63")
	))
	details.add_child(_large_label(current_blueprint.display_name, 30))
	var identity := Label.new()
	identity.text = "source_identity：%s\nplayer_identity_text：%s\nbehavior_family：%s" % [
		current_blueprint.source_identity,
		current_blueprint.player_identity_text,
		current_blueprint.behavior_family
	]
	identity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	identity.modulate = Color("bae6fd")
	details.add_child(identity)
	var explanation := Label.new()
	explanation.text = current_explanation
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(explanation)
	var behavior := Label.new()
	behavior.text = _behavior_summary(current_blueprint)
	behavior.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	behavior.modulate = Color("cbd5e1")
	details.add_child(behavior)
	var evidence := Label.new()
	if is_sample:
		evidence.text = "解释来源：%s\n视觉来源：%s" % [current_interpretation_source, current_visual_source]
	else:
		var generation_prompt := str(current_manifest.get("generation_prompt", ""))
		var prompt_contains_identity := generation_prompt.contains(current_blueprint.player_identity_text)
		evidence.text = "解释来源：%s\n视觉来源：%s\n原文进入 generation_prompt：%s\n输出：%s\n注意：提示词证据不等于图像身份正确；本机没有 VLM，必须由玩家确认。" % [
			current_interpretation_source,
			current_visual_source,
			"是" if prompt_contains_identity else "否（结果拒绝晋级）",
			_display_output_path(current_output_directory)
		]
	evidence.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	evidence.modulate = Color("94a3b8")
	details.add_child(evidence)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	details.add_child(actions)
	if is_sample:
		actions.add_child(_button("进入训练区（LOCAL SAMPLE）", _start_training, true))
		actions.add_child(_button("返回 Forge", _show_forge))
	else:
		actions.add_child(_button("仍能认出原物件，进入训练区", _accept_visual_identity, true))
		actions.add_child(_button("身份不对，保留输入返回 Forge", _reject_visual_identity))

func _accept_visual_identity() -> void:
	visual_identity_confirmed = true
	_start_training()

func _reject_visual_identity() -> void:
	visual_identity_confirmed = false
	current_asset = null
	_show_forge()

func _behavior_summary(blueprint: WeaponBlueprint) -> String:
	return "delivery：%s · impact_mode：%s · effect_type：%s · drawback：%s" % [
		blueprint.delivery, blueprint.impact_mode, blueprint.effect_type, blueprint.drawback
	]

func _start_training() -> void:
	if current_blueprint == null or current_asset == null:
		_show_generation_failure("TRAINING_ASSET_MISSING")
		return
	if not _training_identity_is_confirmed():
		_show_generation_failure("VISUAL_IDENTITY_CONFIRMATION_REQUIRED")
		return
	state = "training"
	var root := _new_page(16)
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay)
	arena.visible = true
	arena.debug_anchors = false
	arena.start_stage("training", current_blueprint, current_asset)
	var top := HBoxContainer.new()
	top.position = Vector2(24, 12)
	top.size = Vector2(1210, 88)
	top.mouse_filter = Control.MOUSE_FILTER_PASS
	overlay.add_child(top)
	var title := Label.new()
	title.text = "开放身份训练区 · 不接入战斗房间"
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	hud_stats = Label.new()
	hud_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud_stats.custom_minimum_size = Vector2(420, 0)
	top.add_child(hud_stats)
	top.add_child(_button("返回 Forge", _show_forge, true))
	var help := Label.new()
	help.text = "WASD / 方向键移动 · Space / J 攻击 · Shift / K 闪避 · F3 锚点调试"
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

func _training_identity_is_confirmed() -> bool:
	if current_blueprint == null:
		return false
	# Authorization belongs to this scene state, never to mutable Blueprint data.
	# The explicit LOCAL SAMPLE path sets this flag itself before showing review.
	return visual_identity_confirmed

func _update_hud(data: Dictionary) -> void:
	if hud_stats == null or not is_instance_valid(hud_stats):
		return
	hud_stats.text = "%s · 生命 %d · 过载 %d%% · 闪避 %d" % [
		current_blueprint.display_name.left(22),
		roundi(arena.player_health),
		roundi(arena.overheat * 100.0),
		int(data.get("dodge_count", 0))
	]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug") and state == "training":
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
	box.add_child(_large_label(title, 32))
	var sub := Label.new()
	sub.text = subtitle
	sub.modulate = Color("a9bad0")
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sub)
	return box

func _section_title(text: String) -> Label:
	return _large_label(text, 21)

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
	content.add_theme_constant_override("separation", 16)
	panel.add_child(content)
	return panel

func _show_error(message: String) -> void:
	if error_label != null and is_instance_valid(error_label):
		error_label.text = message

func _display_output_path(path: String) -> String:
	var display := path.replace("\\", "/")
	var marker := display.find("tools/comfyui/output/")
	return display.substr(marker) if marker >= 0 else display

func _manifest_contains_identity() -> bool:
	if current_blueprint == null:
		return false
	var generation_prompt := str(current_manifest.get("positive_prompt", current_manifest.get("generation_prompt", "")))
	var model_identity := OPEN_VISUAL_PROMPT._model_text(
		current_blueprint.player_identity_text,
		OPEN_VISUAL_PROMPT.MAX_IDENTITY_CHARACTERS
	)
	return not model_identity.is_empty() and generation_prompt.contains(model_identity)

func _argument_value(prefix: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return fallback

func _has_user_argument(expected: String) -> bool:
	for argument: String in OS.get_cmdline_user_args():
		if argument == expected:
			return true
	return false
