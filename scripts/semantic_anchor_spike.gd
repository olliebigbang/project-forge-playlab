extends Node2D

const GAMEPLAY_ARENA := preload("res://scripts/systems/gameplay_arena.gd")
const CALIBRATOR := preload("res://scripts/ui/semantic_anchor_calibrator.gd")
const FIXTURE_OVERLAY := preload("res://scripts/ui/forge_fixture_overlay.gd")
const SEMANTIC_RESOLVER := preload("res://scripts/systems/semantic_anchor_resolver.gd")

var arena: GameplayArena
var fixture_overlay
var ui_layer: CanvasLayer
var page: Control
var calibrator
var calibration
var training_asset: WeaponVisualAsset
var blueprint: WeaponBlueprint
var source_image: Image
var case_id := ""
var run_id := ""
var sprite_directory := ""
var output_path := ""
var status_label: Label
var step_label: Label
var confirm_button: Button
var training_button: Button
var capture_path := ""
var capture_mode := ""
var capture_frames := -1

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("07111f"))
	sprite_directory = _resolve_sprite_directory()
	if not _load_sprite_and_semantics():
		return
	arena = GAMEPLAY_ARENA.new() as GameplayArena
	add_child(arena)
	arena.visible = false
	fixture_overlay = FIXTURE_OVERLAY.new()
	add_child(fixture_overlay)
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	_show_calibration()
	capture_path = _argument_value("--capture-path=", "")
	capture_mode = _argument_value("--capture-mode=", "")
	if _argument_value("--calibration-step=", "grip") == "action":
		calibrator.confirm_current_step()
	if _argument_value("--auto-training=", "false") == "true":
		_save_and_start_training()
	if capture_mode == "calibration" and not capture_path.is_empty():
		capture_frames = 30

func _process(_delta: float) -> void:
	if capture_frames < 0:
		return
	capture_frames -= 1
	if capture_frames == 0:
		DirAccess.make_dir_recursive_absolute(capture_path.get_base_dir())
		var image := get_viewport().get_texture().get_image()
		var error := image.save_png(capture_path)
		print("SEMANTIC_ANCHOR_CAPTURE=%s ERROR=%d" % [capture_path, error])
		get_tree().quit(error)

func _load_sprite_and_semantics() -> bool:
	var manifest_path := sprite_directory.path_join("manifest.json")
	var sprite_path := sprite_directory.path_join("processed_sprite.png")
	if not FileAccess.file_exists(manifest_path) or not FileAccess.file_exists(sprite_path):
		printerr("Spike 1 requires an existing successful Spike 0 directory: %s" % sprite_directory)
		get_tree().quit(2)
		return false
	var manifest_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not manifest_value is Dictionary or str((manifest_value as Dictionary).get("status", "")) != "success":
		printerr("Spike 0 manifest is not successful: %s" % manifest_path)
		get_tree().quit(2)
		return false
	case_id = str((manifest_value as Dictionary).get("case_id", ""))
	run_id = str((manifest_value as Dictionary).get("run_id", sprite_directory.get_file()))
	var case_data := _case_data(case_id)
	if case_data.is_empty():
		printerr("No behavior declaration for case: %s" % case_id)
		get_tree().quit(2)
		return false
	blueprint = WeaponBlueprint.new()
	blueprint.id = "semantic_%s" % case_id
	blueprint.display_name = "Forge 语义锚点样本"
	blueprint.behavior_family = str(case_data.get("behavior_family", "sustained_ranged"))
	blueprint.grip_profile = str(case_data.get("grip_profile", "rear_grip"))
	blueprint.validate_and_repair()
	source_image = Image.load_from_file(sprite_path)
	if source_image == null or source_image.get_size() != Vector2i(96, 96):
		printerr("Processed sprite must be 96x96: %s" % sprite_path)
		get_tree().quit(2)
		return false
	calibration = SEMANTIC_RESOLVER.resolve(source_image, blueprint)
	if calibration == null:
		printerr("Semantic AnchorResolver rejected sprite Alpha: %s" % sprite_path)
		get_tree().quit(2)
		return false
	calibration.case_id = case_id
	calibration.run_id = run_id
	calibration.source_sprite = ProjectSettings.localize_path(sprite_path)
	output_path = "res://tools/comfyui/anchor_calibration/output/%s/%s/semantic_anchors.json" % [case_id, run_id]
	_load_optional_manual_points(case_id, run_id)
	return true

func _show_calibration() -> void:
	arena.visible = false
	arena.stop()
	_clear_page()
	page = Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(page)
	var background := ColorRect.new()
	background.color = Color("07111f")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	page.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	var title := Label.new()
	title.text = "FORGE SEMANTIC ANCHOR CALIBRATION SPIKE 1"
	title.add_theme_font_size_override("font_size", 26)
	root.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "只使用现有透明 Sprite｜旧 AnchorResolver 保留为灰色默认建议｜仅训练区"
	subtitle.modulate = Color("94a3b8")
	root.add_child(subtitle)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 22)
	root.add_child(columns)
	calibrator = CALIBRATOR.new()
	calibrator.custom_minimum_size = Vector2(760, 520)
	calibrator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	calibrator.size_flags_vertical = Control.SIZE_EXPAND_FILL
	calibrator.configure(calibration, source_image, sprite_directory.get_file())
	calibrator.step_changed.connect(_on_step_changed)
	calibrator.anchor_changed.connect(_on_anchor_changed)
	calibrator.calibration_completed.connect(_on_calibration_completed)
	columns.add_child(calibrator)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(390, 0)
	side.add_theme_constant_override("separation", 12)
	columns.add_child(side)
	step_label = Label.new()
	step_label.add_theme_font_size_override("font_size", 24)
	step_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(step_label)
	var required := Label.new()
	required.text = "行为声明：%s\n必需锚点：\n• %s" % [blueprint.behavior_family, "\n• ".join(calibration.required_anchor_types)]
	required.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	required.modulate = Color("bae6fd")
	side.add_child(required)
	var explanation := Label.new()
	explanation.text = "玩家只校准两个语义点。双手副握点由主握点、Alpha 与质心重新建议；回旋轴心固定取 Alpha 质心。"
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.modulate = Color("cbd5e1")
	side.add_child(explanation)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.modulate = Color("86efac")
	side.add_child(status_label)
	side.add_spacer(false)
	confirm_button = _button("确认夹具位置", calibrator.confirm_current_step, true)
	side.add_child(confirm_button)
	side.add_child(_button("采用自动建议", calibrator.use_auto_for_current))
	side.add_child(_button("返回安装握持夹具", calibrator.return_to_grip_step))
	training_button = _button("保存并进入训练区", _save_and_start_training, true)
	training_button.visible = false
	side.add_child(training_button)
	_on_step_changed(calibrator.current_step, calibrator.current_anchor_type())

func _on_step_changed(step: int, anchor_type: String) -> void:
	if step_label == null:
		return
	if step == 0:
		step_label.text = "1. 安装握持夹具\n校准 %s" % anchor_type
		confirm_button.text = "确认夹具位置"
	else:
		step_label.text = "2. 刻下力量出口\n校准 %s" % anchor_type
		confirm_button.text = "确认力量出口"
	_on_anchor_changed(anchor_type, calibration.anchor_point(anchor_type))

func _on_anchor_changed(anchor_type: String, point: Vector2) -> void:
	if status_label == null:
		return
	status_label.text = "当前点：%s (%.1f, %.1f)｜来源：%s｜置信度：%.2f" % [
		anchor_type,
		point.x,
		point.y,
		str(calibration.anchor_source.get(anchor_type, "auto")),
		float(calibration.confidence.get(anchor_type, 0.0)),
	]

func _on_calibration_completed() -> void:
	status_label.text = "两步校准完成。派生锚点已按 Alpha 重新计算。"
	training_button.visible = true
	confirm_button.disabled = true

func _save_and_start_training() -> void:
	SEMANTIC_RESOLVER.recompute_derived(calibration, source_image)
	training_asset = calibration.build_asset_copy()
	var error: Error = calibration.save_json(output_path)
	if error != OK:
		status_label.text = "保存失败：%s" % error_string(error)
		return
	_show_training()

func _show_training() -> void:
	_clear_page()
	page = Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(page)
	arena.visible = true
	arena.debug_anchors = false
	arena.start_stage("training", blueprint, training_asset)
	fixture_overlay.configure(arena, calibration)
	var panel := ColorRect.new()
	panel.color = Color(0.02, 0.05, 0.09, 0.94)
	panel.position = Vector2(18, 14)
	panel.size = Vector2(1244, 92)
	page.add_child(panel)
	var title := Label.new()
	title.text = "SEMANTIC ANCHOR SPIKE 1｜仅训练区"
	title.position = Vector2(20, 8)
	title.add_theme_font_size_override("font_size", 24)
	panel.add_child(title)
	var summary := Label.new()
	summary.text = "Forge 夹具与作用符文已挂载｜必需锚点：%s" % ", ".join(calibration.required_anchor_types)
	summary.position = Vector2(20, 43)
	summary.size = Vector2(1120, 42)
	panel.add_child(summary)
	var back := _button("返回校准", _show_calibration)
	back.position = Vector2(1080, 20)
	back.size = Vector2(140, 52)
	panel.add_child(back)
	var help := Label.new()
	help.text = "WASD 移动｜Space / J 攻击｜这里只验证握持、作用点与 Forge 视觉归属"
	help.position = Vector2(34, 102)
	page.add_child(help)
	if capture_mode == "training" and not capture_path.is_empty():
		capture_frames = 30

func _load_optional_manual_points(case_id: String, run_id: String) -> void:
	var target_path := _argument_value("--calibration-targets=", "")
	if target_path.is_empty() or not FileAccess.file_exists(target_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(target_path))
	if not parsed is Dictionary:
		return
	for entry: Dictionary in (parsed as Dictionary).get("runs", []):
		if str(entry.get("case_id", "")) != case_id or str(entry.get("run_id", "")) != run_id:
			continue
		var manual_points: Dictionary = entry.get("manual_points", {})
		var point_confidence: Dictionary = entry.get("point_confidence", {})
		for anchor_type: String in manual_points.keys():
			var pair: Array = manual_points[anchor_type]
			calibration.set_manual_anchor(anchor_type, Vector2(float(pair[0]), float(pair[1])), float(point_confidence.get(anchor_type, 0.95)))
		SEMANTIC_RESOLVER.recompute_derived(calibration, source_image)
		return

func _case_data(case_id: String) -> Dictionary:
	var path := ProjectSettings.globalize_path("res://tools/comfyui/test_cases/cases.json")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {}
	for case_data: Dictionary in (parsed as Dictionary).get("cases", []):
		if str(case_data.get("case_id", "")) == case_id:
			return case_data
	return {}

func _resolve_sprite_directory() -> String:
	var requested := _argument_value("--sprite-dir=", "")
	if requested.is_empty():
		var corpus: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/comfyui/anchor_calibration/test_cases/corpus.json"))
		if corpus is Dictionary:
			var runs: Array = (corpus as Dictionary).get("runs", [])
			if not runs.is_empty() and runs[0] is Dictionary:
				requested = str((runs[0] as Dictionary).get("sprite_path", "")).get_base_dir()
	return ProjectSettings.globalize_path(requested) if requested.begins_with("res://") else requested.simplify_path()

func _clear_page() -> void:
	if page != null and is_instance_valid(page):
		page.queue_free()

func _button(text: String, callback: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 48)
	button.pressed.connect(callback)
	if primary:
		button.modulate = Color("bae6fd")
	return button

func _argument_value(prefix: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return fallback
