extends Node2D
## Independent Church text-to-weapon UI. There is no sample selector or fallback.
## Generation may call paid providers only after the explicit generate action.
const SERVICE := preload("res://scripts/services/general_weapon_generation_service.gd")
const ARENA := preload("res://scripts/art_vertical_slice_v1/church_arena.gd")
const SAMPLE_UI := preload("res://scripts/art_vertical_slice_v1/art_slice_session.gd")
const ARMORY := preload("res://scripts/combat_feel/player_weapon_armory.gd")
const DIRECTOR := preload("res://scripts/enemy_attack/automatic_encounter_director.gd")
const CAPABILITIES := preload("res://scripts/combat_feel/weapon_capability_catalog.gd")
const ART_STYLE := preload("res://scripts/art_vertical_slice_v1/church_pixel_style.gd")
const STYLE_ID := "church_v1"

# Public state used by UI, offline contract tests and explicit external QA.
# success means validated generated entry ready; combat/victory/defeated are
# separate from generation success. Entering combat never implies saving.
var presentation_style_id := STYLE_ID
var forge_title := "教堂造物"
var forge_destination := "教堂"
var state := "idle"
var input_text := ""
var entry: Dictionary = {}
var generation_evidence: Dictionary = {}
var generation_token := 0
var error_code := ""
var save_error := ""
var saved := false
var elapsed := 0.0
var python_executable := "python"
var use_semantic_cache := true
var generation_stage := ""
var visual_requests := 0
var service: RefCounted
var arena: GameplayArena
var service_factory: Callable
var save_callable: Callable
var arena_factory: Callable
var ui_ready := false
var forge_page: Control
var battle_page: Control
var outcome_panel: PanelContainer
var input_field: TextEdit
var generate_button: Button
var cancel_button: Button
var battle_button: Button
var save_button: Button
var status_title: Label
var status_detail: Label
var provenance: Label
var preview_name: Label
var preview_empty: Label
var preview_sprite: TextureRect
var preview_stage: Control
var mechanism_summary: Label
var save_status: Label
var battle_status: Label
var battle_attack: Button
var battle_dodge: Button
var outcome_title: Label
var outcome_detail: Label
var preview_entry_id := 0
var smoke_requested := false


func configure_dependencies(next_service_factory: Callable = Callable(), next_save_callable: Callable = Callable(), next_arena_factory: Callable = Callable()) -> void:
	# Tests inject before adding the UI to a tree. They never touch real providers
	# or the real library. A service is newly created for every request.
	assert(state != "generating" and state != "combat")
	service_factory = next_service_factory
	save_callable = next_save_callable
	arena_factory = next_arena_factory


func _ready() -> void:
	var root := get_tree().root
	root.title = "Forge — Church AI Forge"
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(1280, 720)
	root.min_size = Vector2i(960, 540)
	Engine.max_fps = 60
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# The launcher may configure Python without exposing credentials to the UI.
	if OS.has_environment("FORGE_PYTHON"): python_executable = OS.get_environment("FORGE_PYTHON")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--fal-python="): python_executable = argument.trim_prefix("--fal-python=")
	initialize_ui()
	if "--smoke" in OS.get_cmdline_user_args():
		smoke_requested = true
		call_deferred("_smoke_empty_forge")


func initialize_ui() -> void:
	if ui_ready: return
	arena = arena_factory.call() as GameplayArena if arena_factory.is_valid() else ARENA.new() as GameplayArena
	add_child(arena)
	arena.set_process(false)
	arena.stage_completed.connect(_on_battle_complete)
	_build_ui()
	ui_ready = true
	_refresh_ui()


func begin_generation(text: String) -> Dictionary:
	if state == "combat": return {"ok": false, "error": "RETURN_TO_FORGE_FIRST"}
	if state == "generating": return {"ok": false, "error": "GENERATION_ALREADY_RUNNING"}
	input_text = text.strip_edges()
	if input_field != null: input_field.text = text
	generation_token += 1
	_clear_entry()
	error_code = ""
	if input_text.is_empty():
		state = "failed"
		error_code = "CHURCH_FORGE_IDENTITY_EMPTY"
		_refresh_ui()
		return {"ok": false, "error": error_code}
	if input_text.length() > 160:
		state = "failed"
		error_code = "CHURCH_FORGE_IDENTITY_TOO_LONG"
		_refresh_ui()
		return {"ok": false, "error": error_code}
	service = service_factory.call() if service_factory.is_valid() else SERVICE.new()
	service.art_style_id = presentation_style_id
	service.use_semantic_cache = use_semantic_cache
	state = "generating"
	generation_stage = "object_identity"
	visual_requests = 0
	elapsed = 0.0
	var token := generation_token
	var response: Dictionary = service.start(input_text, python_executable)
	accept_generation_result(token, response)
	_refresh_ui()
	return {"ok": state != "failed", "state": state, "generation_token": token, "error": error_code}


func poll_generation() -> void:
	if state != "generating" or service == null: return
	var token := generation_token
	var response: Dictionary = service.poll()
	accept_generation_result(token, response)


func accept_generation_result(token: int, response: Dictionary) -> bool:
	if token != generation_token or state != "generating": return false
	var status := str(response.get("status", "idle"))
	visual_requests = int(response.get("visual_requests", visual_requests))
	if status in ["running", "idle"]:
		generation_stage = str(response.get("stage", generation_stage))
		_refresh_ui()
		return true
	if status != "success" or not bool(response.get("ok", false)):
		state = "failed"
		error_code = str(response.get("failure_reason", response.get("error", "CHURCH_FORGE_GENERATION_FAILED")))
		_clear_entry()
		_refresh_ui()
		return true
	var candidate: Dictionary = response.get("entry", {})
	var evidence: Dictionary = response.get("generation_evidence", {})
	var validated := validate_entry(candidate, presentation_style_id)
	if not bool(validated.get("ok", false)) or str(evidence.get("art_style_id", "")) != presentation_style_id:
		state = "failed"
		error_code = str(validated.get("error", "CHURCH_FORGE_STYLE_EVIDENCE_MISSING"))
		_clear_entry()
		_refresh_ui()
		return true
	entry = candidate.duplicate(true)
	generation_evidence = evidence.duplicate(true)
	state = "success"
	error_code = ""
	_refresh_ui()
	return true


func cancel_generation() -> void:
	if state != "generating": return
	generation_token += 1
	if service != null: service.cancel_current()
	service = null
	state = "cancelled"
	_clear_entry()
	_refresh_ui()


func _clear_entry() -> void:
	entry.clear()
	generation_evidence.clear()
	saved = false
	save_error = ""
	preview_entry_id = 0


static func validate_entry(candidate: Dictionary, expected_style: String = STYLE_ID) -> Dictionary:
	if not bool(candidate.get("ok", false)) or not bool(candidate.get("accepted_visual", false)):
		return {"ok": false, "error": "CHURCH_FORGE_ACCEPTED_ENTRY_REQUIRED"}
	var blueprint := candidate.get("blueprint") as WeaponBlueprint
	var asset := candidate.get("asset") as WeaponVisualAsset
	if blueprint == null or asset == null or asset.source_image == null or asset.texture == null:
		return {"ok": false, "error": "CHURCH_FORGE_REAL_PIXELS_REQUIRED"}
	if asset.source_image.is_empty() or asset.opaque_bounds.size.x <= 0 or asset.opaque_bounds.size.y <= 0:
		return {"ok": false, "error": "CHURCH_FORGE_ALPHA_REQUIRED"}
	if bool(blueprint.modifiers.get("local_sample_only", false)):
		return {"ok": false, "error": "CHURCH_FORGE_LOCAL_SAMPLE_NOT_GENERATION"}
	if str(blueprint.modifiers.get("art_style_id", "")) != expected_style or str(blueprint.modifiers.get("art_style_version", "")) != ART_STYLE.version(expected_style):
		return {"ok": false, "error": "CHURCH_FORGE_BLUEPRINT_STYLE_MISMATCH"}
	var report: Dictionary = ART_STYLE.inspect(asset.source_image, expected_style)
	if not bool(report.get("ok", false)): return report
	var visual_evidence: Dictionary = candidate.get("visual_evidence", {})
	for evidence: Dictionary in [blueprint.modifiers.get("art_style_report", {}), visual_evidence.get("art_style", {})]:
		if not bool(evidence.get("ok", false)): return {"ok": false, "error": "CHURCH_FORGE_STYLE_REPORT_MISSING"}
		for key: String in ["id", "version", "opaque_pixels", "color_count", "hard_alpha"]:
			if evidence.get(key) != report.get(key): return {"ok": false, "error": "CHURCH_FORGE_STYLE_REPORT_STALE"}
	var texture_image := asset.texture.get_image()
	if texture_image == null: return {"ok": false, "error": "CHURCH_FORGE_TEXTURE_PIXELS_MISSING"}
	var source_rgba := asset.source_image.duplicate() as Image
	source_rgba.convert(Image.FORMAT_RGBA8)
	texture_image.convert(Image.FORMAT_RGBA8)
	if texture_image.get_size() != source_rgba.get_size() or texture_image.get_data() != source_rgba.get_data():
		return {"ok": false, "error": "CHURCH_FORGE_TEXTURE_SOURCE_MISMATCH"}
	return DIRECTOR.new()._validate_weapon_entry(candidate)


func enter_battle() -> Dictionary:
	if state != "success": return {"ok": false, "error": "CHURCH_FORGE_GENERATION_NOT_READY"}
	var validation := validate_entry(entry, presentation_style_id)
	if not bool(validation.get("ok", false)): return validation
	if not ui_ready: initialize_ui()
	var profiles: Array[Dictionary] = SAMPLE_UI.encounter_profiles()
	if profiles.size() != 2: return {"ok": false, "error": "CHURCH_ENEMY_BLUEPRINTS_UNAVAILABLE"}
	arena.start_stage("church_generated_weapon", entry.blueprint, entry.asset, profiles)
	arena.player_position = Vector2(350, 475)
	arena.facing = 1.0
	arena.invulnerable_timer = 0.0
	arena.flash_timer = 0.0
	arena.set_touch_vector(Vector2.ZERO)
	arena.set_touch_attack(false)
	arena.touch_dodge_requested = false
	arena.set_process(false)
	if not str(arena.melee_runtime.error).is_empty():
		arena.stop()
		return {"ok": false, "error": str(arena.melee_runtime.error)}
	state = "combat"
	_refresh_ui()
	return {"ok": true, "state": state}


func return_to_forge() -> void:
	if state not in ["combat", "victory", "defeated"]: return
	arena.stop()
	arena.set_touch_attack(false)
	arena.set_touch_vector(Vector2.ZERO)
	state = "success" if not entry.is_empty() else "idle"
	_refresh_ui()


func restart_battle() -> Dictionary:
	if state not in ["combat", "victory", "defeated"]: return {"ok": false, "error": "CHURCH_BATTLE_NOT_STARTED"}
	return_to_forge()
	return enter_battle()


func save_current_entry() -> Dictionary:
	if state != "success" or entry.is_empty(): return {"ok": false, "error": "CHURCH_FORGE_GENERATION_NOT_READY"}
	if saved: return {"ok": true, "already_saved": true, "library_key": entry.get("library_key", "")}
	var validation := validate_entry(entry, presentation_style_id)
	if not bool(validation.get("ok", false)): return validation
	# The only library mutation in this scene. Never called by generation,
	# preview, entering/finishing combat, returning, or the smoke harness.
	var result: Dictionary = save_callable.call(entry) if save_callable.is_valid() else ARMORY.new().save_entry(entry)
	if bool(result.get("ok", false)):
		saved = true
		save_error = ""
		entry["library_key"] = str(result.get("library_key", ""))
	else:
		save_error = str(result.get("error", "WEAPON_LIBRARY_SAVE_FAILED"))
	_refresh_ui()
	return result


func _process(delta: float) -> void:
	if state == "generating":
		elapsed += delta
		poll_generation()
	elif state == "combat" and arena != null:
		arena._process(delta)
		# Base arena retains 1 HP for training; real accumulated damage closes
		# this separate fight's loss loop. Same-frame success checks this too.
		if float(arena.metrics.get("damage_taken", 0.0)) >= 100.0:
			state = "defeated"
			arena.stop()
	_refresh_ui()


func _on_battle_complete(_stage: String, _metrics: Dictionary) -> void:
	if state != "combat" or not arena.enemies.is_empty(): return
	if float(arena.metrics.get("damage_taken", 0.0)) >= 100.0: return
	state = "victory"
	arena.stop()
	_refresh_ui()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	var key: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	if key == KEY_ESCAPE:
		if state == "generating": cancel_generation()
		elif state in ["combat", "victory", "defeated"]: return_to_forge()
		else: get_tree().quit()
		get_viewport().set_input_as_handled()
	elif key == KEY_R and state in ["combat", "victory", "defeated"]:
		restart_battle()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	generation_token += 1
	if service != null: service.cancel_current()
	service = null


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	forge_page = Control.new()
	forge_page.size = Vector2(1280, 720)
	layer.add_child(forge_page)
	_panel(forge_page, Rect2(20, 20, 1240, 88))
	_text(forge_page, forge_title, Vector2(42, 30), Vector2(620, 40), 30)
	_text(forge_page, "描述物品 → AI 理解结构与机制 → 同风格像素武器 → 带进" + forge_destination + "战斗", Vector2(42, 77), Vector2(1180, 25), 16)
	_panel(forge_page, Rect2(20, 126, 592, 554))
	_panel(forge_page, Rect2(634, 126, 626, 554))
	_text(forge_page, "你想把什么变成武器？", Vector2(42, 145), Vector2(540, 30), 22)
	input_field = TextEdit.new()
	input_field.position = Vector2(42, 190)
	input_field.size = Vector2(548, 152)
	input_field.placeholder_text = "随便描述一个物品和你在意的外形。\n不需要告诉 AI 怎么握、怎么打。"
	input_field.add_theme_font_override("font", SAMPLE_UI.FONT)
	input_field.add_theme_font_size_override("font_size", 20)
	input_field.add_theme_color_override("font_color", Color("eee6d3"))
	input_field.add_theme_color_override("font_placeholder_color", Color("aaa0ac"))
	var edit_style: StyleBoxFlat = SAMPLE_UI._panel_style()
	edit_style.bg_color = Color("242032")
	input_field.add_theme_stylebox_override("normal", edit_style)
	input_field.add_theme_stylebox_override("focus", edit_style)
	input_field.text_changed.connect(func() -> void: input_text = input_field.text)
	forge_page.add_child(input_field)
	generate_button = _button(forge_page, "生成这件武器", Rect2(42, 358, 280, 48))
	generate_button.pressed.connect(func() -> void: begin_generation(input_field.text))
	cancel_button = _button(forge_page, "取消生成", Rect2(338, 358, 252, 48))
	cancel_button.pressed.connect(cancel_generation)
	status_title = _text(forge_page, "先描述一件物品", Vector2(42, 426), Vector2(548, 30), 20)
	status_detail = _text(forge_page, "", Vector2(42, 466), Vector2(548, 100), 16)
	status_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_detail.clip_text = true
	provenance = _text(forge_page, "", Vector2(42, 586), Vector2(548, 48), 15)
	provenance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text(forge_page, "在线生成可能收费。仅点生成才发起请求；未点击保存不写武器库。", Vector2(42, 647), Vector2(548, 22), 12)
	preview_name = _text(forge_page, "武器预览", Vector2(656, 146), Vector2(574, 35), 23)
	preview_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	preview_stage = Control.new()
	preview_stage.position = Vector2(656, 192)
	preview_stage.size = Vector2(582, 238)
	preview_stage.clip_contents = true
	forge_page.add_child(preview_stage)
	var preview_background := ColorRect.new()
	preview_background.size = preview_stage.size
	preview_background.color = Color("211e2d")
	preview_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_stage.add_child(preview_background)
	preview_sprite = TextureRect.new()
	preview_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_stage.add_child(preview_sprite)
	preview_empty = _text(preview_stage, "真正通过校验的图片会显示在这里\n失败不会换成样品或默认枪", Vector2(22, 86), Vector2(538, 72), 19)
	preview_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mechanism_summary = _text(forge_page, "机制由 AI 和结构校验决定", Vector2(656, 448), Vector2(580, 96), 17)
	mechanism_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mechanism_summary.clip_text = true
	battle_button = _button(forge_page, "带这件武器进入教堂", Rect2(656, 556, 344, 50))
	battle_button.pressed.connect(_enter_battle_clicked)
	save_button = _button(forge_page, "保存到武器库", Rect2(1014, 556, 222, 50))
	save_button.pressed.connect(save_current_entry)
	save_status = _text(forge_page, "生成后可以直接试玩；保存是单独操作。", Vector2(656, 623), Vector2(580, 45), 14)
	save_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_build_battle_ui(layer)


func _build_battle_ui(layer: CanvasLayer) -> void:
	battle_page = Control.new()
	battle_page.size = Vector2(1280, 720)
	layer.add_child(battle_page)
	_panel(battle_page, Rect2(20, 18, 1240, 84))
	battle_status = _text(battle_page, "", Vector2(40, 27), Vector2(958, 66), 19)
	var back := _button(battle_page, "返回造物  ·  Esc", Rect2(1038, 34, 202, 46))
	back.pressed.connect(return_to_forge)
	_panel(battle_page, Rect2(20, 672, 918, 34))
	_text(battle_page, "WASD / 方向键移动   Space / J 攻击   Shift / K 闪避   R 重开   Esc 返回造物", Vector2(34, 677), Vector2(885, 25), 14)
	battle_dodge = _button(battle_page, "闪避", Rect2(956, 652, 134, 54))
	battle_dodge.pressed.connect(func() -> void:
		if state == "combat": arena.request_touch_dodge()
	)
	battle_attack = _button(battle_page, "攻击 / 长按", Rect2(1104, 652, 156, 54))
	battle_attack.button_down.connect(func() -> void:
		if state == "combat": arena.set_touch_attack(true); arena.request_touch_attack()
	)
	battle_attack.button_up.connect(func() -> void: arena.set_touch_attack(false))
	outcome_panel = PanelContainer.new()
	outcome_panel.position = Vector2(326, 238)
	outcome_panel.size = Vector2(628, 258)
	outcome_panel.add_theme_stylebox_override("panel", SAMPLE_UI._panel_style())
	battle_page.add_child(outcome_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	outcome_panel.add_child(box)
	outcome_title = SAMPLE_UI._label(Vector2.ZERO, Vector2.ZERO, 28)
	outcome_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(outcome_title)
	outcome_detail = SAMPLE_UI._label(Vector2.ZERO, Vector2.ZERO, 17)
	outcome_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(outcome_detail)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 16)
	box.add_child(actions)
	var restart := SAMPLE_UI._button("再试一次  ·  R", Vector2.ZERO, Vector2(240, 48))
	restart.custom_minimum_size = Vector2(240, 48)
	restart.pressed.connect(restart_battle)
	actions.add_child(restart)
	var return_button := SAMPLE_UI._button("返回造物", Vector2.ZERO, Vector2(240, 48))
	return_button.custom_minimum_size = Vector2(240, 48)
	return_button.pressed.connect(return_to_forge)
	actions.add_child(return_button)


func _enter_battle_clicked() -> void:
	var result := enter_battle()
	if not bool(result.get("ok", false)):
		error_code = str(result.get("error", "CHURCH_BATTLE_UNAVAILABLE"))
		status_detail.text = "战斗没有开始：" + error_code


func _refresh_ui() -> void:
	if not ui_ready: return
	var fighting := state in ["combat", "victory", "defeated"]
	forge_page.visible = not fighting
	battle_page.visible = fighting
	if fighting:
		var hp := maxf(0.0, 100.0 - float(arena.metrics.get("damage_taken", 0.0)))
		battle_status.text = "生命 %03d   ·   %s   ·   敌人 %d/2\n教堂术士：横扫 / 落点预告     焚行者：锁向突进 / 远程喷射" % [ceili(hp), entry.blueprint.display_name, arena.enemies.size()]
		battle_attack.text = "射击" if arena._uses_firearm_runtime() else "攻击 / 长按"
		battle_attack.disabled = state != "combat"
		battle_dodge.disabled = state != "combat"
		outcome_panel.visible = state in ["victory", "defeated"]
		outcome_title.text = "教堂试炼完成" if state == "victory" else "试炼未完成"
		outcome_detail.text = "武器和描述仍保留；返回造物后可继续查看或保存。"
		return
	input_field.editable = state != "generating"
	generate_button.disabled = state == "generating"
	cancel_button.disabled = state != "generating"
	battle_button.disabled = state != "success" or entry.is_empty()
	save_button.disabled = state != "success" or entry.is_empty() or saved
	save_button.text = "已保存" if saved else "保存到武器库"
	match state:
		"idle":
			status_title.text = "先描述一件物品"
			status_detail.text = "AI 判断结构与用途，本地机制负责校验和执行。你不需要选择握法、招式或填写参数。"
		"generating":
			status_title.text = stage_label(generation_stage)
			status_detail.text = "已等待 %.0f 秒 · 视觉请求 %d\n结果必须经过机制、像素和结构校验。可以取消；已发出的服务请求仍可能计费。" % [elapsed, visual_requests]
		"success":
			status_title.text = "这件武器已通过本地校验"
			status_detail.text = "查看物品是否画得像，再带进关卡试用。机制由 AI 声明、本地编译；风格检查不是审美认证。"
			if not error_code.is_empty(): status_detail.text = "战斗没有开始：" + error_code
		"cancelled":
			status_title.text = "生成已取消"
			status_detail.text = "描述已保留。迟到结果不会覆盖画面或自动进入战斗；已发出的服务请求仍可能计费。"
		"failed":
			status_title.text = "还没有可用的武器"
			status_detail.text = failure_message(error_code) + "\n" + error_code
	provenance.text = source_summary(generation_evidence) if state == "success" else "来源将逐项标注：实时 AI / 已验证缓存。\n语义可复用已验证缓存；图像缓存必须匹配当前场景风格。"
	preview_empty.visible = entry.is_empty()
	preview_sprite.visible = not entry.is_empty()
	if entry.is_empty():
		preview_name.text = "武器预览"
		preview_sprite.texture = null
		mechanism_summary.text = "机制由 AI 和结构校验决定。\n没有生成成功时，不显示默认枪或固定样品。"
	else:
		preview_name.text = entry.blueprint.display_name
		if preview_entry_id != entry.asset.get_instance_id():
			_update_preview()
		mechanism_summary.text = mechanism_text(entry)
	save_status.text = "已保存完整武器；本场景没有自动记录装备或覆盖上次存档。" if saved else "生成后可以直接试玩；保存是单独操作。"
	if not save_error.is_empty(): save_status.text = "保存未成功，可重试。\n" + save_error


func _update_preview() -> void:
	var asset: WeaponVisualAsset = entry.asset
	preview_entry_id = asset.get_instance_id()
	var atlas := AtlasTexture.new()
	atlas.atlas = asset.texture
	atlas.region = Rect2(asset.opaque_bounds)
	preview_sprite.texture = atlas
	var size := Vector2(asset.opaque_bounds.size)
	var zoom := maxf(1.0, minf(4.0, floorf(minf(558.0 / size.x, 214.0 / size.y))))
	preview_sprite.size = size * zoom
	preview_sprite.position = ((preview_stage.size - preview_sprite.size) * 0.5).floor()


static func stage_label(stage: String) -> String:
	return str({"object_identity": "AI 正在理解物品与结构", "firearm_identity": "AI 正在解析射击结构", "visual": "正在制作并校验教堂风格像素图"}.get(stage, "正在校验生成结果"))


static func source_summary(evidence: Dictionary) -> String:
	var semantic := "来源未标注"
	var visual := "来源未标注"
	if evidence.has("semantic_cache_hit"): semantic = "已验证缓存" if bool(evidence.semantic_cache_hit) else "实时 AI"
	if evidence.has("visual_cache_hit"): visual = "已验证缓存" if bool(evidence.visual_cache_hit) else "实时 AI"
	return "语义：%s   ·   图像：%s\n场景像素风格 · 技术校验通过" % [semantic, visual]


static func mechanism_text(weapon: Dictionary) -> String:
	var blueprint: WeaponBlueprint = weapon.blueprint
	var roles: String = CAPABILITIES.summary(weapon)
	if str(blueprint.affordance.get("state_topology", "fixed")) == "fixed":
		roles = roles.replace("展开与防御", "推挡与防御")
	if str(blueprint.affordance.get("weapon_domain", "")) == "handheld_firearm":
		var runtime: Dictionary = weapon.get("ranged_runtime_profile", {})
		return "%s\n%s · 弹匣 %d · 装填 %.1f 秒\nSpace / J 射击；移动与闪避改变站位。" % [roles, "自动射击" if bool(runtime.get("automatic_fire", false)) else "点按射击", int(runtime.get("magazine_size", 0)), float(runtime.get("reload_seconds", 0))]
	return "%s\n点按：编译出的三段动作；长按：结构允许的能力。\n出手距离、收招和接触部分由实际机制决定。" % roles


static func failure_message(code: String) -> String:
	if code == "CHURCH_FORGE_IDENTITY_EMPTY": return "请先写下想生成的物品。"
	if code == "CHURCH_FORGE_IDENTITY_TOO_LONG": return "描述请控制在 160 字以内，保留最重要的外形特征。"
	return "识别、图像或机制校验未完成；没有用样品替代，也没有开始战斗。可以修改描述后重新生成。"


static func _text(parent: Node, text: String, position_value: Vector2, size_value: Vector2, font_size: int) -> Label:
	var label: Label = SAMPLE_UI._label(position_value, size_value, font_size)
	label.text = text
	parent.add_child(label)
	return label


static func _button(parent: Node, text: String, rectangle: Rect2) -> Button:
	var button: Button = SAMPLE_UI._button(text, rectangle.position, rectangle.size)
	parent.add_child(button)
	return button


static func _panel(parent: Node, rectangle: Rect2) -> Panel:
	var panel := Panel.new()
	panel.position = rectangle.position
	panel.size = rectangle.size
	panel.add_theme_stylebox_override("panel", SAMPLE_UI._panel_style())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	return panel


func _smoke_empty_forge() -> void:
	await RenderingServer.frame_post_draw
	var directory := "res://.tools/church-forge/smoke-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := directory.path_join("empty-forge.png")
	var code := get_tree().root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("CHURCH_FORGE_EMPTY_SMOKE ", JSON.stringify({"state": state, "service_created": service != null, "entry_exists": not entry.is_empty(), "online_request_started": false, "desktop_manual_input": false, "screenshot": ProjectSettings.globalize_path(path)}))
	get_tree().quit(0 if code == OK and service == null and state == "idle" else 2)
