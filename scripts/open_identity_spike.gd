extends Node2D

const OPEN_INTERPRETER := preload("res://scripts/services/open_identity_interpreter.gd")
const OPEN_VISUAL_PROMPT := preload("res://scripts/services/open_identity_visual_prompt.gd")
const LOCAL_PROVIDER := preload("res://scripts/services/local_comfy_forge_visual_provider.gd")
const FAL_FIREARM_PROVIDER := preload("res://scripts/services/fal_firearm_visual_provider.gd")
const FAL_GENERAL_OBJECT_PROVIDER := preload("res://scripts/services/fal_general_object_visual_provider.gd")
const MOCK_PROVIDER := preload("res://scripts/services/mock_forge_visual_provider.gd")
const SKETCH_CANVAS := preload("res://scripts/ui/sketch_canvas.gd")
const WEAPON_PREVIEW := preload("res://scripts/ui/weapon_preview.gd")
const TOUCH_STICK := preload("res://scripts/ui/touch_stick.gd")
const GAMEPLAY_ARENA := preload("res://scripts/systems/open_identity_training_arena.gd")
const MECHANISM_AXIS_RESOLVER := preload("res://scripts/combat_feel/mechanism_axis_resolver.gd")
const MELEE_MOTION_COMPILER := preload("res://scripts/combat_feel/melee_motion_compiler.gd")
const COMBAT_FEEL_ASSET_LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")
const MECHANISM_VISUAL_BRIEF := preload("res://scripts/combat_feel/mechanism_visual_brief.gd")
const MECHANISM_VISUAL_READABILITY := preload("res://scripts/combat_feel/mechanism_visual_readability_gate.gd")
const MECHANISM_SCAFFOLD_PIPELINE := preload("res://scripts/combat_feel/mechanism_visual_scaffold_pipeline.gd")
const RANGED_AXIS_RESOLVER := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")
const FIREARM_VISUAL_BRIEF := preload("res://scripts/combat_feel/firearm_visual_brief.gd")
const FIREARM_VISUAL_IDENTITY_CARD := preload("res://scripts/combat_feel/firearm_visual_identity_card.gd")
const FIREARM_SCAFFOLD_PIPELINE := preload("res://scripts/combat_feel/firearm_visual_scaffold_pipeline.gd")
const FIREARM_IDENTITY_AI_RESOLVER := preload("res://scripts/combat_feel/firearm_identity_ai_resolver.gd")
const FIREARM_IDENTITY_AI_PROVIDER := preload("res://scripts/services/firearm_identity_ai_provider.gd")
const GENERAL_OBJECT_AI_RESOLVER := preload("res://scripts/combat_feel/general_object_ai_resolver.gd")
const GENERAL_OBJECT_AI_PROVIDER := preload("res://scripts/services/general_object_ai_provider.gd")
const MODE_MOCK := "MOCK"
const MODE_LOCAL_COMFYUI := "LOCAL_COMFYUI"
const MODE_FAL_FIREARM := "FAL_FIREARM"
const MAX_MECHANISM_VISUAL_RETRIES := 2

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
var current_mechanism_resolution: Dictionary = {}
var current_affordance_profile: Resource
var current_melee_motion_profile: Resource
var current_ranged_mechanism: Dictionary = {}
var hud_stats: Label
var mechanism_visual_retry_count := 0
var current_mechanism_visual_gate: Dictionary = {}
var firearm_identity_provider
var firearm_identity_pending := false
var firearm_identity_started_msec := 0
var pending_firearm_identity := ""
var general_object_provider
var general_object_pending := false
var general_object_started_msec := 0
var pending_general_object_identity := ""

func _ready() -> void:
	if _has_user_argument("--mode=combat-feel-slice-0"):
		get_tree().call_deferred("change_scene_to_file", "res://scenes/combat_feel_slice_0.tscn")
		return
	randomize()
	_build_theme()
	provider_mode = _argument_value("--visual-provider=", MODE_MOCK).to_upper()
	if provider_mode not in [MODE_LOCAL_COMFYUI, MODE_FAL_FIREARM, MODE_MOCK]:
		provider_mode = MODE_MOCK
	arena = GAMEPLAY_ARENA.new() as GameplayArena
	add_child(arena)
	arena.visible = false
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	_show_forge()

func _process(_delta: float) -> void:
	if general_object_pending:
		_poll_general_object_ai()
		return
	if firearm_identity_pending:
		_poll_firearm_identity_ai()
		return
	if not generation_pending or provider == null:
		return
	var result: Dictionary = provider.poll()
	match str(result.get("status", "idle")):
		"running":
			if status_label != null and is_instance_valid(status_label):
				var elapsed := float(Time.get_ticks_msec() - generation_started_msec) / 1000.0
				status_label.text = (
					("FAL 正在辨认枪型、转成像素图并等待 Godot 自动验收…… %.1f / 240 秒" % elapsed
					if _requires_ranged_mechanism_profile()
					else "FAL 正在画出原物件、转成像素图并等待机制轴验收…… %.1f / 240 秒" % elapsed)
					if provider_mode == MODE_FAL_FIREARM
					else "本地 ComfyUI 正在生成、去背景并验证 Alpha…… %.1f / 120 秒" % elapsed
				)
		"success":
			generation_pending = false
			current_asset = result.get("asset") as WeaponVisualAsset
			current_manifest = result.get("manifest", {})
			current_output_directory = str(result.get("output_directory", ""))
			current_visual_source = str(result.get("provider", provider_mode))
			_ingest_ai_affordance_payload(
				result.get("ai_affordance", {}),
				str(result.get("ai_affordance_source", ""))
			)
			_ingest_ai_visual_rig_payload(
				result.get("ai_visual_rig", {}),
				str(result.get("ai_visual_rig_source", ""))
			)
			if current_asset == null:
				if not _activate_mechanism_scaffold_fallback("LOCAL_COMFYUI_RETURNED_NO_ASSET"):
					_show_generation_failure("LOCAL_COMFYUI_RETURNED_NO_ASSET")
			elif not _manifest_contains_identity():
				current_asset = null
				if not _activate_mechanism_scaffold_fallback("GENERATION_PROMPT_IDENTITY_EVIDENCE_MISSING"):
					_show_generation_failure("GENERATION_PROMPT_IDENTITY_EVIDENCE_MISSING")
			else:
				var visual_rig_result := _attach_current_ai_visual_rig()
				_persist_mechanism_visual_gate(visual_rig_result.get("readability_gate", visual_rig_result))
				if not bool(visual_rig_result.get("ok", false)):
					if not _begin_automatic_mechanism_visual_retry(visual_rig_result):
						var visual_error := str(visual_rig_result.get("error", "AI_VISUAL_RIG_INVALID"))
						if not _activate_mechanism_scaffold_fallback(visual_error):
							_show_generation_failure(visual_error)
				else:
					if _requires_ranged_mechanism_profile():
						visual_identity_confirmed = true
					_show_review()
		"failed":
			generation_pending = false
			var provider_error := str(result.get("failure_reason", "LOCAL_COMFYUI_FAILED"))
			if not _begin_automatic_mechanism_visual_retry(result):
				if not _activate_mechanism_scaffold_fallback(provider_error):
					_show_generation_failure(provider_error)

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
	firearm_identity_pending = false
	pending_firearm_identity = ""
	general_object_pending = false
	pending_general_object_identity = ""
	visual_identity_confirmed = false
	_reset_mechanism_state()
	if provider != null:
		provider.cancel_current()
	provider = null
	if firearm_identity_provider != null:
		firearm_identity_provider.cancel_current()
	firearm_identity_provider = null
	if general_object_provider != null:
		general_object_provider.cancel_current()
	general_object_provider = null
	arena.stop()
	arena.visible = false
	var root := _new_page()
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	root.add_child(outer)
	outer.add_child(_header(
		"FORGE PLAYLAB V1 · OPEN IDENTITY SPIKE 2",
		"玩家描述或画出物件；AI 语义与机制轴自动决定怎么握、哪里打和动作特点。本 Spike 仅进入 Forge 与训练区。"
	))
	var top_controls := HBoxContainer.new()
	top_controls.add_theme_constant_override("separation", 8)
	outer.add_child(top_controls)
	for pair: Array in [["只输入文字", "description"], ["文字 + 草图", "description_sketch"], ["只输入草图", "sketch"]]:
		top_controls.add_child(_button(str(pair[0]), func() -> void: _set_input_mode(str(pair[1]))))
	top_controls.add_spacer(false)
	top_controls.add_child(_button("FAL AI（枪械成品图）", func() -> void: _set_provider_mode(MODE_FAL_FIREARM)))
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
	left.add_child(_section_title("描述想画的物件"))
	description_edit = TextEdit.new()
	description_edit.custom_minimum_size = Vector2(0, 145)
	description_edit.placeholder_text = "例如：中国95式步枪、M4A1、81杠、92式手枪，或描述其他想画的物件。"
	description_edit.text = saved_description
	description_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	left.add_child(description_edit)
	var boundary := Label.new()
	boundary.text = "玩家只负责物件身份；AI 语义声明机制轴，轮廓测量负责校验。缺少 AI 机制声明时不会让玩家补选。"
	boundary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	boundary.modulate = Color("bae6fd")
	left.add_child(boundary)
	left.add_child(_badge(_provider_badge_text(), Color("164e63") if provider_mode in [MODE_LOCAL_COMFYUI, MODE_FAL_FIREARM] else Color("854d0e")))
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
	if _general_object_ai_enabled():
		var visual_text := "FAL 画原物件并转像素；Godot 验机制结构" if provider_mode == MODE_FAL_FIREARM else "%s 负责视觉" % provider_mode
		return "%s · 任意物品名称 AI 解析已开启；握法和攻击模式不询问玩家" % visual_text
	if _firearm_ai_enabled():
		var visual_text := "FAL 负责枪械成品像素图" if provider_mode == MODE_FAL_FIREARM else "%s 负责视觉" % provider_mode
		return "%s · 任意枪械名称 AI 解析已开启；射击机制与结构验收都不询问玩家" % visual_text
	if provider_mode == MODE_MOCK:
		return "MOCK · 四种缓存枪械可离线生成；任意新型号需要开发者启动枪械名称 AI"
	if provider_mode == MODE_FAL_FIREARM:
		return "FAL_FIREARM · 云端画成品枪图 · Godot 只验结构 · 会产生 API 费用"
	return "LOCAL_COMFYUI · 127.0.0.1 · 桌面运行 · 不调用付费 API"

func _submit_forge() -> void:
	if description_edit == null or sketch_canvas == null:
		return
	_capture_forge_input()
	var has_description := not saved_description.is_empty()
	var has_sketch := int(saved_geometry.get("stroke_count", 0)) > 0
	if input_mode == "description" and not has_description:
		_show_error("请先写下想画的物件。")
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
	if _should_request_general_object_ai(result, interpretation_text):
		var cached: Dictionary = GENERAL_OBJECT_AI_RESOLVER.resolve_identity(interpretation_text)
		if bool(cached.get("ok", false)):
			var cached_interpretation: Dictionary = interpreter.interpret_with_ai_object_profile(
				interpretation_text, saved_sketch_png, saved_geometry, cached
			)
			_handle_interpretation_result(cached_interpretation)
			return
		_begin_general_object_ai(interpretation_text)
		return
	if _should_request_firearm_identity_ai(result, interpretation_text):
		_begin_firearm_identity_ai(interpretation_text)
		return
	_handle_interpretation_result(result)


func _general_object_ai_enabled() -> bool:
	return _argument_value("--object-ai=", "off").to_lower() == "anthropic"


func _should_request_general_object_ai(result: Dictionary, identity: String) -> bool:
	if not _general_object_ai_enabled() or identity.strip_edges().is_empty():
		return false
	if bool(result.get("ok", false)):
		var blueprint := result.get("blueprint") as WeaponBlueprint
		return blueprint != null and blueprint.behavior_family == "heavy_melee" and blueprint.affordance.is_empty()
	return (
		str(result.get("error", "")) == "AI_BEHAVIOR_REANALYSIS_REQUIRED"
		and str(result.get("reason", "")) == "behavior_action_unclear"
	)


func _begin_general_object_ai(identity: String) -> void:
	if OS.has_feature("web"):
		_show_ai_semantic_failure("AI_GENERAL_OBJECT_DESKTOP_ONLY")
		return
	if general_object_provider != null:
		general_object_provider.cancel_current()
	var ai_provider = GENERAL_OBJECT_AI_PROVIDER.new()
	var configured: Dictionary = ai_provider.configure(
		_argument_value("--object-ai-python=", _argument_value("--firearm-ai-python=", "python"))
	)
	if not bool(configured.get("ok", false)):
		_show_ai_semantic_failure(str(configured.get("error", "AI_GENERAL_OBJECT_PROVIDER_CONFIG_FAILED")))
		return
	general_object_provider = ai_provider
	pending_general_object_identity = identity.strip_edges()
	general_object_started_msec = Time.get_ticks_msec()
	general_object_pending = true
	ai_provider.request_identity(pending_general_object_identity)
	_show_general_object_resolving()


func _poll_general_object_ai() -> void:
	if general_object_provider == null:
		general_object_pending = false
		_show_ai_semantic_failure("AI_GENERAL_OBJECT_PROVIDER_MISSING")
		return
	var result: Dictionary = general_object_provider.poll()
	match str(result.get("status", "idle")):
		"running":
			if status_label != null and is_instance_valid(status_label):
				var elapsed := float(Time.get_ticks_msec() - general_object_started_msec) / 1000.0
				status_label.text = "AI 正在把物件翻译成握法、软硬、接触面和动作轴…… %.1f / 70 秒" % elapsed
		"success":
			general_object_pending = false
			var identity := pending_general_object_identity
			var payload := (result.get("response", {}) as Dictionary).duplicate(true)
			if not payload.has("model_id"):
				payload["model_id"] = str(result.get("model_id", ""))
			var compiled := _accept_general_object_ai_payload(
				identity, payload, str(result.get("source", "")), true
			)
			pending_general_object_identity = ""
			if not bool(compiled.get("ok", false)):
				var error := str(compiled.get("error", "AI_GENERAL_OBJECT_RESPONSE_REJECTED"))
				if error == "AI_GENERAL_OBJECT_FIREARM_ROUTE_REQUIRED" and _firearm_ai_enabled():
					_begin_firearm_identity_ai(identity)
					return
				_show_ai_semantic_failure(error)
				return
			_handle_interpretation_result(compiled.get("interpretation", {}) as Dictionary)
		"failed":
			general_object_pending = false
			pending_general_object_identity = ""
			_show_ai_semantic_failure(str(result.get("failure_reason", "AI_GENERAL_OBJECT_BRIDGE_FAILED")))


func _accept_general_object_ai_payload(
	identity: String,
	payload: Dictionary,
	source: String,
	persist: bool = true
) -> Dictionary:
	var accepted: Dictionary = GENERAL_OBJECT_AI_RESOLVER.accept_ai_response(
		identity, payload, source, persist
	)
	if not bool(accepted.get("ok", false)):
		return accepted
	var interpretation: Dictionary = interpreter.interpret_with_ai_object_profile(
		identity, saved_sketch_png, saved_geometry, accepted
	)
	if not bool(interpretation.get("ok", false)):
		return interpretation
	return {
		"ok": true,
		"profile": accepted,
		"interpretation": interpretation,
		"player_confirmation_required": false,
	}


func _show_general_object_resolving() -> void:
	state = "general_object_resolving"
	if arena != null:
		arena.visible = false
	var root := _new_page()
	var card := _center_card(900, 460)
	root.add_child(card)
	var content := card.get_child(0) as VBoxContainer
	content.add_child(_badge("AI 通用物品解析", Color("7c3aed")))
	content.add_child(_large_label("正在识别“%s”" % pending_general_object_identity, 30))
	var explanation := Label.new()
	explanation.text = "AI 自动填写完整机制轴；本地校验通过后才会画图和编译动作，不会让玩家决定怎么打。"
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(explanation)
	status_label = Label.new()
	status_label.text = "请求已提交；物体结构不明确、机制矛盾或属于载具时会停止。"
	status_label.modulate = Color("ddd6fe")
	content.add_child(status_label)
	content.add_child(_button("取消并返回 Forge", _show_forge))


func _firearm_ai_enabled() -> bool:
	return _argument_value("--firearm-ai=", "off").to_lower() == "anthropic"


func _should_request_firearm_identity_ai(result: Dictionary, identity: String) -> bool:
	return (
		_firearm_ai_enabled()
		and not identity.strip_edges().is_empty()
		and not bool(result.get("ok", false))
		and str(result.get("error", "")) == "AI_BEHAVIOR_REANALYSIS_REQUIRED"
		and str(result.get("reason", "")) == "behavior_action_unclear"
	)


func _begin_firearm_identity_ai(identity: String) -> void:
	if OS.has_feature("web"):
		_show_ai_semantic_failure("AI_FIREARM_IDENTITY_DESKTOP_ONLY")
		return
	if firearm_identity_provider != null:
		firearm_identity_provider.cancel_current()
	var ai_provider = FIREARM_IDENTITY_AI_PROVIDER.new()
	var configured: Dictionary = ai_provider.configure(
		_argument_value("--firearm-ai-python=", "python")
	)
	if not bool(configured.get("ok", false)):
		_show_ai_semantic_failure(str(configured.get("error", "AI_FIREARM_PROVIDER_CONFIG_FAILED")))
		return
	firearm_identity_provider = ai_provider
	pending_firearm_identity = identity.strip_edges()
	firearm_identity_started_msec = Time.get_ticks_msec()
	firearm_identity_pending = true
	ai_provider.request_identity(pending_firearm_identity)
	_show_firearm_identity_resolving()


func _poll_firearm_identity_ai() -> void:
	if firearm_identity_provider == null:
		firearm_identity_pending = false
		_show_ai_semantic_failure("AI_FIREARM_PROVIDER_MISSING")
		return
	var result: Dictionary = firearm_identity_provider.poll()
	match str(result.get("status", "idle")):
		"running":
			if status_label != null and is_instance_valid(status_label):
				var elapsed := float(Time.get_ticks_msec() - firearm_identity_started_msec) / 1000.0
				status_label.text = "AI 正在把型号翻译成结构与机制轴…… %.1f / 70 秒" % elapsed
		"success":
			firearm_identity_pending = false
			var payload := (result.get("response", {}) as Dictionary).duplicate(true)
			if not payload.has("model_id"):
				payload["model_id"] = str(result.get("model_id", ""))
			var compiled := _accept_firearm_identity_ai_payload(
				pending_firearm_identity,
				payload,
				str(result.get("source", "")),
				true
			)
			pending_firearm_identity = ""
			if not bool(compiled.get("ok", false)):
				_show_ai_semantic_failure(str(compiled.get("error", "AI_FIREARM_RESPONSE_REJECTED")))
				return
			_handle_interpretation_result(compiled.get("interpretation", {}) as Dictionary)
		"failed":
			firearm_identity_pending = false
			pending_firearm_identity = ""
			_show_ai_semantic_failure(str(result.get("failure_reason", "AI_FIREARM_BRIDGE_FAILED")))


func _accept_firearm_identity_ai_payload(
	identity: String,
	payload: Dictionary,
	source: String,
	persist: bool = true
) -> Dictionary:
	var accepted: Dictionary = FIREARM_IDENTITY_AI_RESOLVER.accept_ai_response(
		identity,
		payload,
		source,
		persist
	)
	if not bool(accepted.get("ok", false)):
		return accepted
	var interpretation: Dictionary = interpreter.interpret_with_ai_firearm_profile(
		identity,
		saved_sketch_png,
		saved_geometry,
		accepted
	)
	if not bool(interpretation.get("ok", false)):
		return interpretation
	return {
		"ok": true,
		"profile": accepted,
		"interpretation": interpretation,
		"player_confirmation_required": false,
	}


func _show_firearm_identity_resolving() -> void:
	state = "firearm_identity_resolving"
	if arena != null:
		arena.visible = false
	var root := _new_page()
	var card := _center_card(900, 460)
	root.add_child(card)
	var content := card.get_child(0) as VBoxContainer
	content.add_child(_badge("AI 枪械型号解析", Color("1d4ed8")))
	content.add_child(_large_label("正在识别“%s”" % pending_firearm_identity, 30))
	var explanation := Label.new()
	explanation.text = "AI 只填写受限的结构与机制卡；本地校验通过后才会画枪。玩家不需要选择射击方式。"
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(explanation)
	status_label = Label.new()
	status_label.text = "请求已提交；没有通过校验时会停止，不会套用通用枪。"
	status_label.modulate = Color("bae6fd")
	content.add_child(status_label)
	content.add_child(_button("取消并返回 Forge", _show_forge))

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
	if not clarified_identity.is_empty():
		return "IDENTITY::%s" % clarified_identity
	return ""

func _clear_persisted_clarification() -> void:
	clarified_input_signature = ""
	clarified_identity = ""
	pending_input_signature = ""
	clarification_used = false

func _handle_interpretation_result(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		var interpretation_error := str(result.get("error", "INTERPRETATION_FAILED"))
		if interpretation_error.begins_with("AI_"):
			_show_ai_semantic_failure(interpretation_error)
		else:
			_show_generation_failure(interpretation_error)
		return
	if bool(result.get("needs_clarification", false)):
		if str(result.get("clarification_kind", "")) != "identity":
			_show_ai_semantic_failure("AI_BEHAVIOR_CLASSIFICATION_REQUIRED")
			return
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
	mechanism_visual_retry_count = 0
	current_mechanism_visual_gate.clear()
	if bool(result.get("ai_interpretation_used", false)):
		_ingest_ai_affordance_payload(
			result.get("affordance", current_blueprint.affordance),
			str(result.get("affordance_source", current_interpretation_source))
		)
	if _requires_mechanism_profile():
		var contract: Dictionary = MECHANISM_AXIS_RESOLVER.validate_ai_declaration(
			current_blueprint.affordance,
			current_blueprint.affordance_source
		)
		if not bool(contract.get("ok", false)):
			_show_ai_semantic_failure(str(contract.get("error", "AI_AFFORDANCE_MISSING")))
			return
		current_blueprint.visual_structure_brief = MECHANISM_VISUAL_BRIEF.compile(
			current_blueprint.affordance,
			current_blueprint.affordance_source
		)
		current_blueprint.visual_structure_brief_source = str(current_blueprint.visual_structure_brief.get("source", ""))
		var brief_errors := MECHANISM_VISUAL_BRIEF.validation_errors(current_blueprint.visual_structure_brief)
		if not brief_errors.is_empty():
			_show_ai_semantic_failure(str(brief_errors[0]))
			return
		current_blueprint.visual_prompt = OPEN_VISUAL_PROMPT.build(current_blueprint)
	elif _requires_ranged_mechanism_profile():
		var ranged_contract: Dictionary = RANGED_AXIS_RESOLVER.validate_ai_declaration(
			current_blueprint.affordance,
			current_blueprint.affordance_source
		)
		if not bool(ranged_contract.get("ok", false)):
			_show_ai_semantic_failure(str(ranged_contract.get("error", "AI_RANGED_AXES_MISSING")))
			return
		current_blueprint.visual_structure_brief = FIREARM_VISUAL_BRIEF.compile(
			current_blueprint.affordance,
			current_blueprint.affordance_source,
			FIREARM_VISUAL_IDENTITY_CARD.compile(current_blueprint)
		)
		current_blueprint.visual_structure_brief_source = str(current_blueprint.visual_structure_brief.get("source", ""))
		var ranged_brief_errors := FIREARM_VISUAL_BRIEF.validation_errors(current_blueprint.visual_structure_brief)
		if not ranged_brief_errors.is_empty():
			_show_ai_semantic_failure(str(ranged_brief_errors[0]))
			return
		current_blueprint.visual_prompt = OPEN_VISUAL_PROMPT.build(current_blueprint)
	if provider_mode == MODE_MOCK:
		if not _activate_mechanism_scaffold_fallback("EXTERNAL_VISUAL_PROVIDER_NOT_CONFIGURED"):
			_show_generation_failure("MOCK_CANNOT_RENDER_ARBITRARY_PLAYER_IDENTITY")
		return
	_begin_visual_generation()

func _ingest_ai_affordance_payload(payload: Variant, source: String) -> void:
	if current_blueprint == null or not payload is Dictionary or (payload as Dictionary).is_empty():
		return
	current_blueprint.affordance = (payload as Dictionary).duplicate(true)
	current_blueprint.affordance_source = source.strip_edges()


func _ingest_ai_visual_rig_payload(payload: Variant, source: String) -> void:
	if current_blueprint == null or not payload is Dictionary or (payload as Dictionary).is_empty():
		return
	current_blueprint.visual_rig = (payload as Dictionary).duplicate(true)
	current_blueprint.visual_rig_source = source.strip_edges()


func _attach_current_ai_visual_rig() -> Dictionary:
	if current_blueprint == null or current_asset == null:
		return {"ok": false, "error": "AI_VISUAL_RIG_ASSET_MISSING"}
	if _requires_ranged_mechanism_profile():
		var compiled_ranged := RANGED_AXIS_RESOLVER.compile(
			current_blueprint.affordance,
			current_blueprint.affordance_source
		)
		if not bool(compiled_ranged.get("ok", false)):
			return compiled_ranged
		current_ranged_mechanism = compiled_ranged.duplicate(true)
		var visual_gate := (
			current_manifest.get("firearm_visual_identity_gate", {}) as Dictionary
		).duplicate(true)
		if not bool(visual_gate.get("ok", false)):
			return {
				"ok": false,
				"error": str(visual_gate.get("error", "FIREARM_VISUAL_IDENTITY_GATE_MISSING")),
				"retry_required": true,
				"player_confirmation_required": false,
			}
		current_mechanism_visual_gate = visual_gate.duplicate(true)
		return {
			"ok": true,
			"automatic": true,
			"visual_rig": {},
			"readability_gate": visual_gate,
			"player_confirmation_required": false,
		}
	var affordance := current_blueprint.affordance
	var uses_soft_visuals := str(affordance.get("flex_topology", "none")) != "none" \
		or str(affordance.get("tether_topology", "none")) != "none"
	var resolution: Dictionary = MECHANISM_AXIS_RESOLVER.resolve_ai(
		current_asset,
		current_blueprint.affordance,
		current_blueprint.affordance_source
	)
	if not bool(resolution.get("ok", false)) or not resolution.get("profile") is Resource:
		var resolution_failure := {
			"ok": false,
			"error": str(resolution.get("error", "AI_VISUAL_RIG_AUTOBUILD_AFFORDANCE_MISSING")),
			"retry_required": true,
			"player_confirmation_required": false,
			"axis_resolution": resolution,
		}
		if str(resolution_failure["error"]) == "AI_GEOMETRY_CONFLICT":
			resolution_failure["retry_prompt"] = "Keep the same identity; make visible mass placement and contact geometry agree with every declared mechanism axis."
		return resolution_failure
	var affordance_profile := resolution.get("profile") as Resource
	var attachment: Dictionary
	if current_blueprint.visual_rig.is_empty():
		if uses_soft_visuals:
			attachment = COMBAT_FEEL_ASSET_LOADER.new().build_automatic_visual_rig(
				current_asset,
				affordance_profile
			)
		else:
			attachment = {"ok": true, "automatic": true, "visual_rig": {}}
	else:
		attachment = COMBAT_FEEL_ASSET_LOADER.new().attach_ai_visual_rig(
			current_asset,
			current_blueprint.visual_rig
		)
	attachment["player_confirmation_required"] = false
	if not bool(attachment.get("ok", false)):
		attachment["retry_required"] = true
		return attachment
	if current_asset.visual_rig != null:
		var axis_errors := current_asset.visual_rig.axis_errors(affordance_profile)
		if not axis_errors.is_empty():
			return {
				"ok": false,
				"error": "AI_VISUAL_RIG_AXIS_MISMATCH:%s" % ",".join(axis_errors),
				"retry_required": true,
				"player_confirmation_required": false,
			}
	var readability: Dictionary = MECHANISM_VISUAL_READABILITY.evaluate(
		current_asset,
		affordance_profile,
		current_blueprint.visual_structure_brief
	)
	current_mechanism_visual_gate = readability.duplicate(true)
	attachment["readability_gate"] = readability
	if not bool(readability.get("ok", false)):
		return readability
	return attachment


func _begin_automatic_mechanism_visual_retry(result: Dictionary) -> bool:
	if current_blueprint == null or provider_mode not in [MODE_LOCAL_COMFYUI, MODE_FAL_FIREARM]:
		return false
	var error := str(result.get("error", ""))
	var structural_failure := bool(result.get("retry_required", false)) and (
		error.begins_with("AI_VISUAL_READABILITY_")
		or error.begins_with("AI_VISUAL_RIG_")
		or error == "AI_GEOMETRY_CONFLICT"
		or error.begins_with("MECHANISM_SCAFFOLD_")
		or error.begins_with("FIREARM_VISUAL_")
	)
	if not structural_failure or mechanism_visual_retry_count >= MAX_MECHANISM_VISUAL_RETRIES:
		return false
	mechanism_visual_retry_count += 1
	current_blueprint.modifiers["mechanism_visual_retry_count"] = mechanism_visual_retry_count
	current_blueprint.modifiers["mechanism_visual_retry_prompt"] = str(result.get(
		"retry_prompt",
		"Keep the same identity; separate grip, mass, contacts, moving structures, and terminal parts in the 96px silhouette."
	))
	if _requires_ranged_mechanism_profile():
		current_blueprint.visual_structure_brief = FIREARM_VISUAL_BRIEF.compile(
			current_blueprint.affordance,
			current_blueprint.affordance_source,
			FIREARM_VISUAL_IDENTITY_CARD.compile(current_blueprint)
		)
	else:
		current_blueprint.visual_structure_brief = MECHANISM_VISUAL_BRIEF.compile(
			current_blueprint.affordance,
			current_blueprint.affordance_source
		)
	current_blueprint.visual_structure_brief_source = str(current_blueprint.visual_structure_brief.get("source", ""))
	current_blueprint.visual_prompt = OPEN_VISUAL_PROMPT.build(current_blueprint)
	current_asset = null
	current_blueprint.visual_rig.clear()
	current_blueprint.visual_rig_source = ""
	call_deferred("_begin_visual_generation")
	return true


func _activate_mechanism_scaffold_fallback(reason: String) -> bool:
	var uses_ranged_scaffold := _requires_ranged_mechanism_profile()
	if not _requires_mechanism_profile() and not uses_ranged_scaffold:
		return false
	if uses_ranged_scaffold:
		# A firearm scaffold is useful evidence for the generator and tests, but it
		# is not player-facing art. Persist it as a diagnostic and stop honestly.
		var diagnostic := FIREARM_SCAFFOLD_PIPELINE.fallback(current_blueprint)
		if bool(diagnostic.get("ok", false)):
			var diagnostic_run_id := "%s_%d_%d" % [
				current_blueprint.id.validate_filename(),
				roundi(Time.get_unix_time_from_system() * 1000.0),
				Time.get_ticks_usec(),
			]
			var persisted_diagnostic := FIREARM_SCAFFOLD_PIPELINE.persist_fallback(
				"user://playlab/firearm_scaffold_diagnostic/%s" % diagnostic_run_id,
				current_blueprint,
				diagnostic,
				reason
			)
			if bool(persisted_diagnostic.get("ok", false)):
				current_manifest = (persisted_diagnostic.get("manifest", {}) as Dictionary).duplicate(true)
				current_output_directory = str(persisted_diagnostic.get("output_directory", ""))
		current_asset = null
		current_visual_source = "HIDDEN FIREARM STRUCTURE SCAFFOLD · NOT FINISHED ART"
		return false
	var fallback_result: Dictionary
	fallback_result = MECHANISM_SCAFFOLD_PIPELINE.fallback(current_blueprint)
	if not bool(fallback_result.get("ok", false)):
		return false
	current_blueprint.visual_structure_brief = (
		fallback_result.get("visual_structure_brief", {}) as Dictionary
	).duplicate(true)
	current_blueprint.visual_structure_brief_source = str(
		current_blueprint.visual_structure_brief.get("source", "")
	)
	current_blueprint.visual_rig.clear()
	current_blueprint.visual_rig_source = ""
	current_blueprint.modifiers["mechanism_scaffold_fallback_reason"] = reason
	current_asset = fallback_result.get("asset") as WeaponVisualAsset
	if current_asset == null:
		return false
	_reset_mechanism_state()
	var visual_rig_result := _attach_current_ai_visual_rig()
	if not bool(visual_rig_result.get("ok", false)):
		return false
	var run_id := "%s_%d_%d" % [
		current_blueprint.id.validate_filename(),
		roundi(Time.get_unix_time_from_system() * 1000.0),
		Time.get_ticks_usec(),
	]
	var fallback_directory := "user://playlab/mechanism_scaffold_fallback/%s" % run_id
	var persisted: Dictionary
	persisted = MECHANISM_SCAFFOLD_PIPELINE.persist_fallback(
		fallback_directory,
		current_blueprint,
		fallback_result,
		reason
	)
	if not bool(persisted.get("ok", false)):
		return false
	current_manifest = (persisted.get("manifest", {}) as Dictionary).duplicate(true)
	current_output_directory = str(persisted.get("output_directory", ""))
	current_visual_source = "MECHANISM AXIS SCAFFOLD FALLBACK"
	visual_identity_confirmed = false
	generation_pending = false
	_persist_mechanism_visual_gate(visual_rig_result.get("readability_gate", visual_rig_result))
	_show_review()
	return true


func _persist_mechanism_visual_gate(gate: Variant) -> void:
	if current_output_directory.is_empty() or not gate is Dictionary or (gate as Dictionary).is_empty():
		return
	var path := current_output_directory.path_join("mechanism_visual_gate.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(gate, "  "))


func _ai_semantic_failure_zh(code: String) -> String:
	if code.contains("MISSING_API_KEY"):
		return "开发者还没有启动名称 AI，当前不会对陌生物品发起请求。"
	if code.contains("MISSING_MODEL_ID"):
		return "开发者没有配置语义模型。"
	if code == "AI_FIREARM_STRUCTURE_FAMILY_UNSUPPORTED":
		return "AI 认出了这是枪械，但当前像素结构轴还不能诚实表现这种枪型。"
	if code == "AI_VEHICLE_PLATFORM_COMPILER_REQUIRED":
		return "AI 认出了这是坦克或其他武装载具；它需要载具编译器，不能作为手持武器。"
	if code == "AI_FIREARM_IDENTITY_REJECTED":
		return "AI 判断这个名称不是手持枪械。"
	if code in ["AI_FIREARM_IDENTITY_UNCERTAIN", "AI_FIREARM_CONFIDENCE_TOO_LOW"]:
		return "AI 对这个型号没有足够把握，因此没有套用通用枪。"
	if code.begins_with("AI_FIREARM_BRIDGE_"):
		return "枪械名称 AI 没有返回可用结果；没有生成或缓存猜测。"
	if code == "AI_GENERAL_OBJECT_FIREARM_ROUTE_REQUIRED":
		return "AI 判断这是枪械，必须转交枪械结构解析器。"
	if code == "AI_GENERAL_OBJECT_POWERED_VEHICLE_ACTOR_REQUIRED":
		return "AI 判断这是带动力的载具；它需要载具与底盘编译器，不能缩成普通手持物。"
	if code == "AI_GENERAL_OBJECT_LIVING_ACTOR_REQUIRED":
		return "AI 判断这是活体或角色，而不是可生成的物件。"
	if code in ["AI_GENERAL_OBJECT_IDENTITY_UNCERTAIN", "AI_GENERAL_OBJECT_CONFIDENCE_TOO_LOW"]:
		return "AI 对物件结构没有足够把握，因此没有套用通用攻击。"
	if code.begins_with("AI_GENERAL_OBJECT_BRIDGE_"):
		return "通用物品 AI 没有返回完整结构卡；没有生成或缓存猜测。"
	return "AI 没有返回完整且一致的身份与机制声明。"


func _show_ai_semantic_failure(code: String) -> void:
	state = "ai_semantic_failed"
	generation_pending = false
	if arena != null:
		arena.visible = false
	var root := _new_page()
	var card := _center_card(940, 500)
	root.add_child(card)
	var content := card.get_child(0) as VBoxContainer
	content.add_child(_badge("AI 语义机制未就绪", Color("991b1b")))
	content.add_child(_large_label("没有开始画图，也不会问玩家怎么打", 30))
	var details := Label.new()
	details.text = "%s\n\n错误代码：%s\n物件身份仍由玩家描述；机制由 AI 返回。当前结果缺失或冲突，所以流程在生成图片前停止。" % [
		_ai_semantic_failure_zh(code), code
	]
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(details)
	var source := Label.new()
	source.text = "解释来源：%s\n机制来源：%s\n玩家机制输入：未使用" % [
		current_interpretation_source if not current_interpretation_source.is_empty() else "缺失",
		current_blueprint.affordance_source if current_blueprint != null and not current_blueprint.affordance_source.is_empty() else "缺失",
	]
	source.modulate = Color("94a3b8")
	content.add_child(source)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	content.add_child(actions)
	actions.add_child(_button("返回 Forge", _show_forge, true))
	actions.add_child(_button("载入固定 LOCAL SAMPLE", _start_local_sample))

func _show_clarification(question: String) -> void:
	if pending_clarification_kind != "identity":
		_show_ai_semantic_failure("AI_BEHAVIOR_CLASSIFICATION_REQUIRED")
		return
	state = "clarification"
	var root := _new_page()
	var card := _center_card(900, 500)
	root.add_child(card)
	var content := card.get_child(0) as VBoxContainer
	content.add_child(_badge("只确认物件身份", Color("7c3aed")))
	content.add_child(_large_label(question, 32))
	identity_answer_edit = LineEdit.new()
	identity_answer_edit.placeholder_text = "输入你画的物件名称"
	content.add_child(identity_answer_edit)
	var identity_hint := Label.new()
	identity_hint.text = "这里只确认画的是什么。握法、打击部位和动作特点不会询问玩家。"
	identity_hint.modulate = Color("cbd5e1")
	content.add_child(identity_hint)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	content.add_child(actions)
	actions.add_child(_button("确认物件名称", _answer_identity_clarification, true))
	error_label = Label.new()
	error_label.modulate = Color("fca5a5")
	content.add_child(error_label)
	content.add_child(_button("返回 Forge", _show_forge))

func _answer_identity_clarification() -> void:
	if pending_input_signature.is_empty() or pending_input_signature != current_input_signature:
		_show_generation_failure("CLARIFICATION_INPUT_CHANGED")
		return
	if pending_clarification_kind != "identity":
		_show_ai_semantic_failure("PLAYER_MECHANISM_CLARIFICATION_FORBIDDEN")
		return
	if identity_answer_edit == null or identity_answer_edit.text.strip_edges().is_empty():
		_show_error("请先回答：你画的是什么？")
		return
	var identity_answer := identity_answer_edit.text.strip_edges()
	var clarification := "IDENTITY::%s" % identity_answer
	clarified_input_signature = pending_input_signature
	clarified_identity = identity_answer
	pending_clarification_kind = ""
	pending_input_signature = ""
	var result: Dictionary = interpreter.interpret(
		"", saved_sketch_png, saved_geometry, null, "", clarification
	)
	if _should_request_general_object_ai(result, identity_answer):
		var cached: Dictionary = GENERAL_OBJECT_AI_RESOLVER.resolve_identity(identity_answer)
		if bool(cached.get("ok", false)):
			_handle_interpretation_result(interpreter.interpret_with_ai_object_profile(
				identity_answer, saved_sketch_png, saved_geometry, cached
			))
			return
		_begin_general_object_ai(identity_answer)
		return
	if _should_request_firearm_identity_ai(result, identity_answer):
		_begin_firearm_identity_ai(identity_answer)
		return
	_handle_interpretation_result(result)

func _begin_visual_generation() -> void:
	if provider_mode == MODE_FAL_FIREARM and _requires_ranged_mechanism_profile():
		_begin_fal_firearm_generation()
	elif provider_mode == MODE_FAL_FIREARM and _requires_mechanism_profile():
		_begin_fal_general_object_generation()
	else:
		_begin_local_generation()


func _begin_fal_firearm_generation() -> void:
	if OS.has_feature("web"):
		_show_generation_failure("FIREARM_VISUAL_FAL_DESKTOP_ONLY")
		return
	if not _requires_ranged_mechanism_profile():
		_show_generation_failure("FIREARM_VISUAL_FAL_REQUIRES_HANDHELD_FIREARM")
		return
	var fal_provider = FAL_FIREARM_PROVIDER.new()
	provider = fal_provider
	var python_path := _argument_value(
		"--fal-python=",
		_argument_value("--firearm-ai-python=", "python")
	)
	var configured: Dictionary = fal_provider.configure(python_path)
	if not bool(configured.get("ok", false)):
		_show_generation_failure(str(configured.get("error", "FIREARM_VISUAL_FAL_CONFIG_FAILED")))
		return
	visual_identity_confirmed = false
	current_blueprint.visual_rig.clear()
	current_blueprint.visual_rig_source = ""
	fal_provider.request_visual(
		current_blueprint,
		current_blueprint.player_identity_text,
		PackedByteArray(),
		0.0
	)
	generation_pending = true
	generation_started_msec = Time.get_ticks_msec()
	_show_generating()


func _begin_fal_general_object_generation() -> void:
	if OS.has_feature("web"):
		_show_generation_failure("GENERAL_OBJECT_VISUAL_FAL_DESKTOP_ONLY")
		return
	if not _requires_mechanism_profile():
		_show_generation_failure("GENERAL_OBJECT_VISUAL_FAL_REQUIRES_MELEE_OBJECT")
		return
	var fal_provider = FAL_GENERAL_OBJECT_PROVIDER.new()
	provider = fal_provider
	var python_path := _argument_value(
		"--fal-python=", _argument_value("--object-ai-python=", "python")
	)
	var configured: Dictionary = fal_provider.configure(python_path)
	if not bool(configured.get("ok", false)):
		if not _activate_mechanism_scaffold_fallback(str(configured.get("error", "GENERAL_OBJECT_VISUAL_FAL_CONFIG_FAILED"))):
			_show_generation_failure(str(configured.get("error", "GENERAL_OBJECT_VISUAL_FAL_CONFIG_FAILED")))
		return
	visual_identity_confirmed = false
	current_blueprint.visual_rig.clear()
	current_blueprint.visual_rig_source = ""
	fal_provider.request_visual(
		current_blueprint,
		current_blueprint.player_identity_text,
		PackedByteArray(),
		0.0
	)
	generation_pending = true
	generation_started_msec = Time.get_ticks_msec()
	_show_generating()


func _begin_local_generation() -> void:
	if OS.has_feature("web"):
		if not _activate_mechanism_scaffold_fallback("LOCAL_COMFYUI_DESKTOP_ONLY"):
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
		var config_error := str(configured.get("error", "COMFYUI_CONFIG_FAILED"))
		if not _activate_mechanism_scaffold_fallback(config_error):
			_show_generation_failure(config_error)
		return
	# The bridge performs its health check inside the child process. Keeping it
	# there prevents the Godot main thread from freezing on an unavailable API.
	visual_identity_confirmed = false
	current_blueprint.visual_rig.clear()
	current_blueprint.visual_rig_source = ""
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
	content.add_child(_badge(
		("FAL AI · 枪械成品像素图" if _requires_ranged_mechanism_profile() else "FAL AI · 原物件像素图")
		if provider_mode == MODE_FAL_FIREARM else "LOCAL_COMFYUI · 真实生成",
		Color("164e63")
	))
	var generation_title := "正在保留物件身份并生成视觉"
	if mechanism_visual_retry_count > 0:
		generation_title = "结构不够清楚，AI 正在自动重画（%d/%d）" % [mechanism_visual_retry_count, MAX_MECHANISM_VISUAL_RETRIES]
	content.add_child(_large_label(generation_title, 32))
	status_label = Label.new()
	status_label.text = (
		("请求已提交；AI 先画准确枪型，再转为有限色像素图。Godot 自动验收，不会把隐藏方块骨架展示给玩家。"
		if _requires_ranged_mechanism_profile()
		else "请求已提交；AI 先画原物件，再转为有限色像素图。Godot 自动检查机制结构，玩家只确认它是否仍像原物件。")
		if provider_mode == MODE_FAL_FIREARM
		else "请求已提交；外部画图只负责外观。隐藏机制骨架只用于约束和诊断，不会冒充成品武器。"
	)
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
	if current_blueprint != null and provider_mode in [MODE_LOCAL_COMFYUI, MODE_FAL_FIREARM]:
		actions.add_child(_button(
			"重试 FAL 生成" if provider_mode == MODE_FAL_FIREARM else "重试本地生成",
			_begin_visual_generation
		))
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
	_reset_mechanism_state()
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
	var review_subtitle := "AI 已完成枪械成品图和结构验收；玩家只查看结果。" \
		if _requires_ranged_mechanism_profile() else "确认物件身份，再只进入训练区。"
	outer.add_child(_header("开放身份锻造结果", review_subtitle))
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
	var visual_mode := str(current_manifest.get("visual_mode", ""))
	var is_mechanism_fallback := visual_mode in ["mechanism_scaffold_fallback", "firearm_scaffold_fallback"]
	var has_ai_affordance := not current_blueprint.affordance.is_empty() and not current_blueprint.affordance_source.is_empty()
	details.add_child(_badge(
		"LOCAL SAMPLE · 固定回归图 · 未解释输入"
		if is_sample
		else (
			"机制轴骨架保底 · 外部画图未成功"
			if is_mechanism_fallback
			else (
				"%s · 机制轴和成品结构已自动验收" % current_visual_source
				if has_ai_affordance
				else "%s · 身份原文透传 · 缺少 AI 机制声明" % current_visual_source
			)
		),
		Color("854d0e") if is_sample or is_mechanism_fallback or not has_ai_affordance else Color("164e63")
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
	elif is_mechanism_fallback:
		evidence.text = "解释来源：%s\n视觉来源：%s\n外部画图：未成功，当前显示的是 AI 机制轴直接画出的 96 像素结构骨架\n输出：%s\n玩家只确认它是否仍像原物件；攻击方式、动作和碰撞仍由 AI 机制轴自动决定。" % [
			current_interpretation_source,
			current_visual_source,
			_display_output_path(current_output_directory),
		]
	elif _requires_ranged_mechanism_profile() and bool(current_manifest.get("firearm_visual_gate_passed", false)):
		var firearm_gate := current_manifest.get("firearm_visual_identity_gate", {}) as Dictionary
		evidence.text = "解释来源：%s\n视觉来源：%s\nAI 成品图：通过枪械结构验收\n验收方式：型号原文 + 机制轴 + 枪托/机匣/握把/弹匣/枪口可见区域\n输出：%s\n玩家不决定攻击方式，也不承担机制确认。" % [
			current_interpretation_source,
			current_visual_source,
			_display_output_path(current_output_directory),
		]
		if firearm_gate.is_empty():
			evidence.text += "\n警告：验收记录缺失。"
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
		var accept_text := "仍能认出原物件，进入训练区"
		if _requires_mechanism_profile():
			accept_text = "仍能认出原物件，查看 AI 机制卡"
		elif _requires_ranged_mechanism_profile():
			accept_text = "AI 验收已通过，查看射击机制卡"
		actions.add_child(_button(accept_text, _accept_visual_identity, true))
		actions.add_child(_button("身份不对，保留输入返回 Forge", _reject_visual_identity))

func _accept_visual_identity() -> void:
	visual_identity_confirmed = true
	if _requires_mechanism_profile():
		var resolved := _resolve_ai_mechanism()
		if not bool(resolved.get("ok", false)):
			_show_ai_mechanism_failure(resolved)
			return
		_apply_ai_mechanism_resolution(resolved)
		_show_mechanism_summary()
	elif _requires_ranged_mechanism_profile():
		var ranged_resolved := _resolve_ai_ranged_mechanism()
		if not bool(ranged_resolved.get("ok", false)):
			_show_ai_semantic_failure(str(ranged_resolved.get("error", "AI_RANGED_AXES_INVALID")))
			return
		_apply_ai_ranged_mechanism(ranged_resolved)
		_show_ranged_mechanism_summary()
	else:
		_start_training()

func _reject_visual_identity() -> void:
	visual_identity_confirmed = false
	current_asset = null
	_show_forge()

func _reset_mechanism_state() -> void:
	current_mechanism_resolution.clear()
	current_affordance_profile = null
	current_melee_motion_profile = null
	current_ranged_mechanism.clear()

func _requires_mechanism_profile() -> bool:
	return current_blueprint != null and current_blueprint.behavior_family == "heavy_melee"

func _requires_ranged_mechanism_profile() -> bool:
	return (
		current_blueprint != null
		and current_blueprint.behavior_family == "sustained_ranged"
		and str(current_blueprint.affordance.get("weapon_domain", "")) == "handheld_firearm"
	)

func _ranged_mechanism_value_label(axis: String, value: String) -> String:
	var labels: Dictionary = RANGED_AXIS_RESOLVER.OPTION_LABELS_ZH.get(axis, {})
	return str(labels.get(value, value))

func _mechanism_value_label(axis: String, value: String) -> String:
	var labels: Dictionary = MECHANISM_AXIS_RESOLVER.OPTION_LABELS_ZH.get(axis, {})
	return str(labels.get(value, value))

func _resolve_ai_mechanism() -> Dictionary:
	if not _requires_mechanism_profile() or current_asset == null:
		return {
			"ok": false,
			"error": "MECHANISM_AUTOMATION_PREREQUISITE_MISSING",
			"retry_required": true,
			"player_confirmation_required": false,
		}
	var resolution: Dictionary = MECHANISM_AXIS_RESOLVER.resolve_ai(
		current_asset,
		current_blueprint.affordance,
		current_blueprint.affordance_source
	)
	if not bool(resolution.get("ok", false)):
		return resolution
	if not bool(resolution.get("complete", false)) or not resolution.get("profile") is Resource:
		return {
			"ok": false,
			"error": "AI_AFFORDANCE_INCOMPLETE",
			"resolution": resolution,
			"retry_required": true,
			"player_confirmation_required": false,
		}
	var affordance := resolution.get("profile") as Resource
	var compiled: Variant = MELEE_MOTION_COMPILER.new().compile(affordance, current_asset.anchors_dict(), current_asset.opaque_bounds)
	if not compiled is Resource:
		return {
			"ok": false,
			"error": str(compiled),
			"resolution": resolution,
			"retry_required": true,
			"player_confirmation_required": false,
		}
	if not compiled.validation_errors().is_empty():
		return {
			"ok": false,
			"error": "COMPILED_MECHANISM_PROFILE_INVALID",
			"resolution": resolution,
			"retry_required": true,
			"player_confirmation_required": false,
		}
	return {
		"ok": true,
		"resolution": resolution,
		"affordance_profile": affordance,
		"motion_profile": compiled,
		"automatic": true,
		"player_mechanism_input_used": false,
		"player_confirmation_required": false,
	}

func _apply_ai_mechanism_resolution(resolved: Dictionary) -> void:
	current_mechanism_resolution = (resolved.get("resolution", {}) as Dictionary).duplicate(true)
	current_affordance_profile = resolved.get("affordance_profile") as Resource
	current_melee_motion_profile = resolved.get("motion_profile") as Resource

func _resolve_ai_ranged_mechanism() -> Dictionary:
	if not _requires_ranged_mechanism_profile() or current_asset == null:
		return {
			"ok": false,
			"error": "RANGED_MECHANISM_AUTOMATION_PREREQUISITE_MISSING",
			"player_confirmation_required": false,
		}
	return RANGED_AXIS_RESOLVER.compile(
		current_blueprint.affordance,
		current_blueprint.affordance_source
	)

func _apply_ai_ranged_mechanism(resolved: Dictionary) -> void:
	current_ranged_mechanism = resolved.duplicate(true)
	if current_blueprint != null:
		current_blueprint.modifiers["ranged_runtime_profile"] = resolved.duplicate(true)

func _ranged_mechanism_is_ready() -> bool:
	return (
		bool(current_ranged_mechanism.get("ok", false))
		and str(current_ranged_mechanism.get("schema", "")) == RANGED_AXIS_RESOLVER.RUNTIME_SCHEMA
		and not str(current_ranged_mechanism.get("axis_signature", "")).is_empty()
	)

func _ranged_fire_mode_text(runtime: Dictionary) -> String:
	if bool(runtime.get("automatic_fire", false)):
		return "按住连续射击"
	var burst_size := int(runtime.get("burst_size", 0))
	if burst_size > 1:
		return "每次按下自动打出 %d 发短点射" % burst_size
	return "每次按下只发射一发"

func _ranged_attack_input_text(runtime: Dictionary) -> String:
	if bool(runtime.get("automatic_fire", false)):
		return "按住连射"
	if int(runtime.get("burst_size", 0)) > 1:
		return "点按三连发"
	return "点按射击"

func _mechanism_error_zh(code: String) -> String:
	if code in ["AI_AFFORDANCE_MISSING", "AI_AFFORDANCE_SOURCE_MISSING"] or code.begins_with("AI_AFFORDANCE_MISSING_"):
		return "AI 没有返回完整的机制轴。"
	if code == "UNTRUSTED_AI_AFFORDANCE_SOURCE":
		return "机制轴没有可信的 AI 来源标记。"
	if code == "AI_GEOMETRY_CONFLICT":
		return "AI 的机制判断与稳定轮廓证据冲突。"
	if code == "INVALID_AFFORDANCE_COMBINATION":
		return "AI 返回的握柄和握法互相矛盾。"
	return "自动机制卡不能生成：%s" % code

func _show_ai_mechanism_failure(result: Dictionary) -> void:
	state = "mechanism_failed"
	arena.visible = false
	var root := _new_page()
	var card := _center_card(960, 540)
	root.add_child(card)
	var content := card.get_child(0) as VBoxContainer
	content.add_child(_badge("AI 机制轴未通过", Color("991b1b")))
	content.add_child(_large_label("已停止生成动作，不让玩家补答案", 30))
	var code := str(result.get("error", "AI_MECHANISM_RESOLUTION_FAILED"))
	var details := Label.new()
	details.text = "%s\n系统需要完整 AI 机制声明，并用真实 Alpha、GripPrimary 和 StrikePoint 做轮廓校验。信息缺失或两者冲突时，只能交给 AI 重判。" % _mechanism_error_zh(code)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(details)
	var conflicts: Array = result.get("conflicts", [])
	if not conflicts.is_empty():
		var conflict_lines := PackedStringArray()
		for raw_conflict: Variant in conflicts:
			var conflict: Dictionary = raw_conflict
			var axis := str(conflict.get("axis", ""))
			conflict_lines.append("%s：AI=%s，轮廓=%s" % [
				str(MECHANISM_AXIS_RESOLVER.AXIS_LABELS_ZH.get(axis, axis)),
				_mechanism_value_label(axis, str(conflict.get("ai_value", ""))),
				_mechanism_value_label(axis, str(conflict.get("geometry_value", ""))),
			])
		var conflict_label := Label.new()
		conflict_label.text = "冲突证据\n• %s" % "\n• ".join(conflict_lines)
		conflict_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		conflict_label.modulate = Color("fca5a5")
		content.add_child(conflict_label)
	var source_label := Label.new()
	source_label.text = "机制来源：%s\n错误码：%s\n玩家机制输入：未使用" % [
		current_blueprint.affordance_source if current_blueprint != null and not current_blueprint.affordance_source.is_empty() else "缺失",
		code,
	]
	source_label.modulate = Color("94a3b8")
	content.add_child(source_label)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	content.add_child(actions)
	actions.add_child(_button("返回 Forge", _show_forge, true))
	actions.add_child(_button("返回看图", _show_review))

func _show_mechanism_summary() -> void:
	if not _mechanism_profile_is_ready():
		var resolved := _resolve_ai_mechanism()
		if not bool(resolved.get("ok", false)):
			_show_ai_mechanism_failure(resolved)
			return
		_apply_ai_mechanism_resolution(resolved)
	if not _mechanism_profile_is_ready():
		_show_ai_mechanism_failure({"ok": false, "error": "AI_AFFORDANCE_INCOMPLETE"})
		return
	state = "mechanism_summary"
	var root := _new_page(24)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	root.add_child(outer)
	outer.add_child(_header("AI 机制卡已生成", "AI 判断用途，真实轮廓负责校验；玩家只确认物件画得像不像，名称不参与动作配方。"))
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 22)
	outer.add_child(columns)
	var preview := WEAPON_PREVIEW.new() as WeaponPreview
	preview.custom_minimum_size = Vector2(480, 450)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.configure(current_asset, false, false, current_blueprint.display_name)
	columns.add_child(preview)
	var details := VBoxContainer.new()
	details.custom_minimum_size = Vector2(650, 0)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 8)
	columns.add_child(details)
	details.add_child(_badge("AI 完整声明 · 轮廓校验通过 · 已编译", Color("166534")))
	var measured_axis_labels := PackedStringArray()
	var geometry_axes: Dictionary = ((current_mechanism_resolution.get("geometry_validation", {}) as Dictionary).get("axes", {}) as Dictionary)
	for axis: String in MECHANISM_AXIS_RESOLVER.REQUIRED_AXES:
		if str((geometry_axes.get(axis, {}) as Dictionary).get("status", "")) == "measured":
			measured_axis_labels.append(str(MECHANISM_AXIS_RESOLVER.AXIS_LABELS_ZH[axis]))
	var source := Label.new()
	source.text = "机制来源：%s · AI 置信度：%.2f\n轮廓稳定校验：%s\n玩家机制输入：未使用" % [
		current_blueprint.affordance_source,
		float(current_affordance_profile.confidence),
		"、".join(measured_axis_labels) if not measured_axis_labels.is_empty() else "无可稳定定类的轴",
	]
	source.modulate = Color("94a3b8")
	details.add_child(source)
	for axis: String in MECHANISM_AXIS_RESOLVER.REQUIRED_AXES:
		var value := str(current_affordance_profile.get(axis))
		var line := Label.new()
		line.text = "%s  →  %s" % [str(MECHANISM_AXIS_RESOLVER.AXIS_LABELS_ZH[axis]), _mechanism_value_label(axis, value)]
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.add_child(line)
	var structural_tags := PackedStringArray()
	for pair: Array in [
		["has_point", "有尖端"], ["has_edge", "有刃边"], ["has_broad_face", "有宽面"],
		["has_barrel", "有筒身"], ["has_stock", "有后托"],
	]:
		if bool(current_affordance_profile.get(str(pair[0]))):
			structural_tags.append(str(pair[1]))
	var tag_line := Label.new()
	tag_line.text = "结构标签  →  %s" % ("、".join(structural_tags) if not structural_tags.is_empty() else "无额外标签")
	tag_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(tag_line)
	var recipe: Resource = current_melee_motion_profile.combo_recipe
	var sequence: PackedStringArray = recipe.primitive_sequence()
	var result_label := Label.new()
	result_label.text = "机制派生特点\n• 三段动作：%s\n• 有效距离：%.1f\n• 挥动覆盖：%.1f°\n• 接触跨度：%.1f" % [
		" → ".join(_motion_labels_zh(sequence)),
		float(current_melee_motion_profile.reach_pixels),
		float(current_melee_motion_profile.swing_arc_degrees),
		float(current_melee_motion_profile.hitbox_thickness),
	]
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.modulate = Color("bae6fd")
	details.add_child(result_label)
	error_label = Label.new()
	error_label.modulate = Color("fca5a5")
	details.add_child(error_label)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	outer.add_child(actions)
	actions.add_child(_button("进入机制训练区", _start_mechanism_training, true))
	actions.add_child(_button("返回 Forge", _show_forge))

func _motion_labels_zh(sequence: PackedStringArray) -> PackedStringArray:
	var labels := {"bash": "撞击", "sweep": "横扫", "thrust": "突刺", "slam": "下砸", "spin": "旋身扫击"}
	var result := PackedStringArray()
	for family: String in sequence:
		result.append(str(labels.get(family, family)))
	return result

func _show_ranged_mechanism_summary() -> void:
	if not _ranged_mechanism_is_ready():
		var resolved := _resolve_ai_ranged_mechanism()
		if not bool(resolved.get("ok", false)):
			_show_ai_semantic_failure(str(resolved.get("error", "AI_RANGED_AXES_INVALID")))
			return
		_apply_ai_ranged_mechanism(resolved)
	state = "ranged_mechanism_summary"
	var root := _new_page(24)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	root.add_child(outer)
	outer.add_child(_header("AI 射击卡 V3 已生成", "型号提供身份事实；单发、三连发或连射，以及射速、后坐、命中冲击和供弹，全部由机制轴编译。"))
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 22)
	outer.add_child(columns)
	var preview := WEAPON_PREVIEW.new() as WeaponPreview
	preview.custom_minimum_size = Vector2(470, 440)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.configure(current_asset, false, false, current_blueprint.display_name)
	columns.add_child(preview)
	var details := VBoxContainer.new()
	details.custom_minimum_size = Vector2(660, 0)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 6)
	columns.add_child(details)
	details.add_child(_badge("AI 型号声明 · V3 机制轴完整 · 因果参数已编译", Color("166534")))
	var source := Label.new()
	source.text = "机制来源：%s · AI 置信度：%.2f\n玩家机制输入：未使用 · 玩家只确认外形身份" % [
		current_blueprint.affordance_source,
		float(current_ranged_mechanism.get("confidence", 0.0)),
	]
	source.modulate = Color("94a3b8")
	details.add_child(source)
	var structure := Label.new()
	structure.text = "可见结构  →  %s / %s / %s / %s" % [
		_ranged_mechanism_value_label("layout", str(current_blueprint.affordance.get("layout", ""))),
		_ranged_mechanism_value_label("stock_structure", str(current_blueprint.affordance.get("stock_structure", ""))),
		_ranged_mechanism_value_label("feed_position", str(current_blueprint.affordance.get("feed_position", ""))),
		_ranged_mechanism_value_label("upper_profile", str(current_blueprint.affordance.get("upper_profile", ""))),
	]
	structure.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(structure)
	for axis: String in RANGED_AXIS_RESOLVER.MECHANISM_AXES:
		var line := Label.new()
		var value := str(current_blueprint.affordance.get(axis, ""))
		line.text = "%s  →  %s" % [
			str(RANGED_AXIS_RESOLVER.AXIS_LABELS_ZH.get(axis, axis)),
			_ranged_mechanism_value_label(axis, value),
		]
		details.add_child(line)
	var result_label := Label.new()
	result_label.text = "编译后的游戏表现\n• %s\n• 每 %.2f 秒一发；后坐 %.1f 像素，以 %.1f 像素/秒回正；单发上跳 %.1f°\n• 单发伤害 %.1f；正面护甲保留 %.0f%%；可继续穿过 %d 个目标\n• 散布 %.1f；弹匣 %d 发；换弹 %.2f 秒" % [
		_ranged_fire_mode_text(current_ranged_mechanism),
		float(current_ranged_mechanism.get("shot_interval_seconds", 0.0)),
		float(current_ranged_mechanism.get("recoil_pixels", 0.0)),
		float(current_ranged_mechanism.get("recoil_recovery_pixels_per_second", 0.0)),
		float(current_ranged_mechanism.get("muzzle_climb_degrees_per_shot", 0.0)),
		float(current_ranged_mechanism.get("projectile_damage", 0.0)),
		float(current_ranged_mechanism.get("armor_damage_multiplier", 0.0)) * 100.0,
		int(current_ranged_mechanism.get("pierce_budget", 0)),
		float(current_ranged_mechanism.get("spread_velocity", 0.0)),
		int(current_ranged_mechanism.get("magazine_size", 0)),
		float(current_ranged_mechanism.get("reload_seconds", 0.0)),
	]
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.modulate = Color("bae6fd")
	details.add_child(result_label)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	outer.add_child(actions)
	actions.add_child(_button("进入射击训练区", _start_training, true))
	actions.add_child(_button("带这把枪打 AI 敌人", _start_enemy_playtest))
	actions.add_child(_button("返回 Forge", _show_forge))

func _mechanism_profile_is_ready() -> bool:
	return (
		current_affordance_profile != null
		and current_melee_motion_profile != null
		and current_affordance_profile.validation_errors().is_empty()
		and current_melee_motion_profile.validation_errors().is_empty()
	)

func _start_mechanism_training() -> void:
	if not _training_identity_is_confirmed() or not _mechanism_profile_is_ready():
		_show_error("身份尚未确认，或 AI 自动机制卡尚未就绪。")
		return
	var handoff: Node = get_node_or_null("/root/MechanismHandoff")
	if handoff == null:
		_show_error("机制交接器不存在。")
		return
	var handoff_error := str(handoff.call("store", current_blueprint, current_asset, current_affordance_profile))
	if not handoff_error.is_empty():
		_show_error(_mechanism_error_zh(handoff_error))
		return
	get_tree().change_scene_to_file("res://scenes/combat_feel_slice_0.tscn")


func _start_enemy_playtest() -> void:
	if current_blueprint == null or current_asset == null or not _ranged_mechanism_is_ready():
		_show_error("枪械图片或 AI 自动机制卡尚未就绪。")
		return
	var handoff: Node = get_node_or_null("/root/MechanismHandoff")
	if handoff == null or not handoff.has_method("store_ranged"):
		_show_error("枪械试玩交接器不存在。")
		return
	var handoff_error := str(handoff.call(
		"store_ranged",
		current_blueprint,
		current_asset,
		current_ranged_mechanism
	))
	if not handoff_error.is_empty():
		_show_error("枪械无法进入试玩：%s" % handoff_error)
		return
	get_tree().change_scene_to_file("res://scenes/ai_enemy_playtest.tscn")

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
	if _requires_mechanism_profile():
		if _mechanism_profile_is_ready():
			_start_mechanism_training()
			return
		var resolved := _resolve_ai_mechanism()
		if not bool(resolved.get("ok", false)):
			_show_ai_mechanism_failure(resolved)
			return
		_apply_ai_mechanism_resolution(resolved)
		_show_mechanism_summary()
		return
	if _requires_ranged_mechanism_profile() and not _ranged_mechanism_is_ready():
		var ranged_resolved := _resolve_ai_ranged_mechanism()
		if not bool(ranged_resolved.get("ok", false)):
			_show_ai_semantic_failure(str(ranged_resolved.get("error", "AI_RANGED_AXES_INVALID")))
			return
		_apply_ai_ranged_mechanism(ranged_resolved)
		_show_ranged_mechanism_summary()
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
	var attack_help := "Space / J 攻击"
	if _requires_ranged_mechanism_profile():
		attack_help = "Space / J %s" % _ranged_attack_input_text(current_ranged_mechanism)
	help.text = "WASD / 方向键移动 · %s · Shift / K 闪避 · F3 锚点调试" % attack_help
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
	if arena._uses_firearm_runtime():
		var magazine_size := int(arena.ranged_runtime_profile.get("magazine_size", 0))
		var reload_text := " · 换弹 %.1fs" % arena.reload_timer if arena.reload_timer > 0.0 else ""
		hud_stats.text = "%s · 生命 %d · 弹匣 %d/%d%s · 已射 %d" % [
			current_blueprint.display_name.left(18),
			roundi(arena.player_health),
			arena.ammo_in_magazine,
			magazine_size,
			reload_text,
			int(data.get("shots_fired", 0)),
		]
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
