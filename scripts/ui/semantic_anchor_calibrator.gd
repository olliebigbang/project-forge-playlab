class_name SemanticAnchorCalibrator
extends Control

signal anchor_changed(anchor_type: String, point: Vector2)
signal step_changed(step: int, anchor_type: String)
signal calibration_completed

const UI_FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
const RESOLVER := preload("res://scripts/systems/semantic_anchor_resolver.gd")

const GRIP_COLOR := Color("5eead4")
const SECONDARY_COLOR := Color("facc15")
const EFFECT_COLOR := Color("38bdf8")
const STRIKE_COLOR := Color("fb7185")
const SPIN_COLOR := Color("c084fc")

var calibration
var source_image: Image
var current_step := 0
var dragging := false
var heading := ""

func _ready() -> void:
	custom_minimum_size = Vector2(620, 500)
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_CROSS

func configure(value: RefCounted, image: Image, title: String = "") -> void:
	calibration = value
	source_image = image
	heading = title
	current_step = 0
	dragging = false
	queue_redraw()
	step_changed.emit(current_step, current_anchor_type())

func current_anchor_type() -> String:
	if current_step == 0:
		return "GripPrimary"
	if calibration != null and calibration.required_anchor_types.has("EffectOrigin"):
		return "EffectOrigin"
	return "StrikePoint"

func confirm_current_step() -> void:
	if calibration == null or source_image == null:
		return
	if current_step == 0:
		RESOLVER.recompute_derived(calibration, source_image)
		current_step = 1
		step_changed.emit(current_step, current_anchor_type())
		queue_redraw()
	else:
		RESOLVER.recompute_derived(calibration, source_image)
		calibration_completed.emit()

func return_to_grip_step() -> void:
	current_step = 0
	step_changed.emit(current_step, current_anchor_type())
	queue_redraw()

func use_auto_for_current() -> void:
	if calibration == null:
		return
	var anchor_type := current_anchor_type()
	calibration.retain_auto_anchor(anchor_type)
	anchor_changed.emit(anchor_type, calibration.anchor_point(anchor_type))
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if calibration == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			dragging = _sprite_rect().has_point(event.position)
		if dragging and event.pressed:
			_set_current_anchor(_screen_to_asset(event.position))
			if is_inside_tree():
				grab_focus()
			accept_event()
		elif not event.pressed:
			dragging = false
	elif event is InputEventMouseMotion and dragging:
		_set_current_anchor(_screen_to_asset(event.position))
		accept_event()
	elif event is InputEventScreenTouch:
		if event.pressed:
			dragging = _sprite_rect().has_point(event.position)
		if dragging and event.pressed:
			_set_current_anchor(_screen_to_asset(event.position))
			accept_event()
		elif not event.pressed:
			dragging = false
	elif event is InputEventScreenDrag and dragging:
		_set_current_anchor(_screen_to_asset(event.position))
		accept_event()
	elif event is InputEventKey and event.pressed:
		var offset := Vector2.ZERO
		match event.keycode:
			KEY_LEFT: offset.x = -1.0
			KEY_RIGHT: offset.x = 1.0
			KEY_UP: offset.y = -1.0
			KEY_DOWN: offset.y = 1.0
		if offset != Vector2.ZERO:
			_set_current_anchor(calibration.anchor_point(current_anchor_type()) + offset)
			accept_event()

func _set_current_anchor(point: Vector2) -> void:
	var anchor_type := current_anchor_type()
	var clamped := point.clamp(Vector2.ZERO, Vector2(calibration.asset.canvas_size - Vector2i.ONE))
	calibration.set_manual_anchor(anchor_type, clamped)
	anchor_changed.emit(anchor_type, clamped)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0b1220"), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color("334155"), false, 2.0)
	if calibration == null or calibration.asset == null or calibration.asset.texture == null:
		return
	_draw_checkerboard(_sprite_rect())
	draw_texture_rect(calibration.asset.texture, _sprite_rect(), false)
	if not heading.is_empty():
		draw_string(UI_FONT, Vector2(18, 28), heading, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("f8fafc"))
	var auto_point := _asset_to_screen(calibration.auto_anchors.get(current_anchor_type(), Vector2.ZERO))
	draw_arc(auto_point, 11.0, 0.0, TAU, 24, Color(0.58, 0.65, 0.75, 0.8), 2.0)
	draw_string(UI_FONT, auto_point + Vector2(13, -8), "自动建议", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("94a3b8"))
	_draw_all_semantic_anchors()
	var instruction := "步骤 1/2｜安装握持夹具：点击或拖动主握点" if current_step == 0 else "步骤 2/2｜刻下力量出口：点击或拖动作用点"
	draw_string(UI_FONT, Vector2(18, size.y - 42), instruction, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("e2e8f0"))
	draw_string(UI_FONT, Vector2(18, size.y - 16), "灰圈为原 AnchorResolver 建议；方向键可微调 1 像素", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("94a3b8"))

func _draw_all_semantic_anchors() -> void:
	for anchor_type: String in calibration.required_anchor_types:
		var point := _asset_to_screen(calibration.anchor_point(anchor_type))
		match anchor_type:
			"GripPrimary": _draw_grip_fixture(point, GRIP_COLOR, anchor_type == current_anchor_type())
			"GripSecondary": _draw_grip_fixture(point, SECONDARY_COLOR, false)
			"SpinPivot": _draw_spin_rune(point)
			"EffectOrigin": _draw_effect_rune(point, EFFECT_COLOR, anchor_type == current_anchor_type())
			"StrikePoint": _draw_effect_rune(point, STRIKE_COLOR, anchor_type == current_anchor_type())

func _draw_grip_fixture(point: Vector2, color: Color, active: bool) -> void:
	var radius := 13.0 if active else 10.0
	draw_arc(point, radius, -2.55, -0.58, 12, color, 3.0)
	draw_arc(point, radius, 0.58, 2.55, 12, color, 3.0)
	draw_line(point + Vector2(-radius - 4, -7), point + Vector2(-radius - 4, 7), color, 4.0)
	draw_line(point + Vector2(radius + 4, -7), point + Vector2(radius + 4, 7), color, 4.0)
	draw_circle(point, 3.5, color)

func _draw_effect_rune(point: Vector2, color: Color, active: bool) -> void:
	var radius := 14.0 if active else 11.0
	draw_arc(point, radius, 0.0, TAU, 24, color, 3.0)
	draw_arc(point, radius * 0.52, 0.0, TAU, 18, Color(color, 0.75), 2.0)
	for index: int in range(8):
		var direction := Vector2.RIGHT.rotated(float(index) * TAU / 8.0)
		draw_line(point + direction * (radius + 2.0), point + direction * (radius + 8.0), color, 2.0)
	draw_circle(point, 3.0, color)

func _draw_spin_rune(point: Vector2) -> void:
	draw_arc(point, 12.0, 0.35, TAU - 0.35, 24, SPIN_COLOR, 2.5)
	var arrow := point + Vector2(11.0, -4.0)
	draw_colored_polygon(PackedVector2Array([arrow, arrow + Vector2(6, 1), arrow + Vector2(2, 6)]), SPIN_COLOR)
	draw_circle(point, 3.0, SPIN_COLOR)

func _draw_checkerboard(rect: Rect2) -> void:
	var cell := 16.0
	var rows := ceili(rect.size.y / cell)
	var columns := ceili(rect.size.x / cell)
	for row: int in range(rows):
		for column: int in range(columns):
			var color := Color("263244") if (row + column) % 2 == 0 else Color("334155")
			draw_rect(Rect2(rect.position + Vector2(column, row) * cell, Vector2(cell, cell)), color, true)

func _sprite_rect() -> Rect2:
	var available := Vector2(size.x - 80.0, size.y - 120.0)
	var scale := minf(available.x / 96.0, available.y / 96.0)
	var sprite_size := Vector2(calibration.asset.canvas_size) * scale
	return Rect2(Vector2((size.x - sprite_size.x) * 0.5, 48.0), sprite_size)

func _asset_to_screen(point: Vector2) -> Vector2:
	return _sprite_rect().position + point * (_sprite_rect().size.x / 96.0)

func _screen_to_asset(point: Vector2) -> Vector2:
	return (point - _sprite_rect().position) / (_sprite_rect().size.x / 96.0)
