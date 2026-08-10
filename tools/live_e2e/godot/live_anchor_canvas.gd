class_name LiveE2EAnchorCanvas
extends Control

signal anchor_confirmed(anchor_type: String, point: Vector2, was_adjusted: bool)

var sprite_texture: Texture2D
var current_anchor_type := "GripPrimary"
var current_point := Vector2(48, 48)
var other_points: Dictionary = {}
var dragging := false
var current_point_was_adjusted := false

const DISPLAY_SIZE := Vector2(432, 432)
const SPRITE_SIZE := Vector2(96, 96)

func configure(texture: Texture2D, anchor_type: String, point: Vector2, known_points: Dictionary) -> void:
	sprite_texture = texture
	current_anchor_type = anchor_type
	current_point = point
	other_points = known_points.duplicate(true)
	current_point_was_adjusted = false
	custom_minimum_size = DISPLAY_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()

func set_step(anchor_type: String, point: Vector2, known_points: Dictionary) -> void:
	current_anchor_type = anchor_type
	current_point = point
	other_points = known_points.duplicate(true)
	dragging = false
	current_point_was_adjusted = false
	queue_redraw()

func confirm_current() -> void:
	anchor_confirmed.emit(current_anchor_type, current_point, current_point_was_adjusted)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				dragging = true
				_set_from_display(button.position)
			else:
				dragging = false
	elif event is InputEventMouseMotion and dragging:
		_set_from_display((event as InputEventMouseMotion).position)

func _set_from_display(display_point: Vector2) -> void:
	var local := (display_point / DISPLAY_SIZE) * SPRITE_SIZE
	var next_point := local.clamp(Vector2.ZERO, SPRITE_SIZE - Vector2.ONE)
	if not next_point.is_equal_approx(current_point):
		current_point_was_adjusted = true
	current_point = next_point
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, DISPLAY_SIZE), Color("271036"), true)
	var cell := DISPLAY_SIZE.x / 12.0
	for index: int in range(13):
		var at := float(index) * cell
		draw_line(Vector2(at, 0), Vector2(at, DISPLAY_SIZE.y), Color(1, 1, 1, 0.035), 1.0)
		draw_line(Vector2(0, at), Vector2(DISPLAY_SIZE.x, at), Color(1, 1, 1, 0.035), 1.0)
	if sprite_texture != null:
		draw_texture_rect(sprite_texture, Rect2(Vector2.ZERO, DISPLAY_SIZE), false)
	for name: String in other_points.keys():
		var point: Vector2 = other_points[name]
		_draw_marker(point, name, Color(1.0, 0.8, 0.25, 0.75), false)
	_draw_marker(current_point, current_anchor_type, _anchor_color(current_anchor_type), true)

func _draw_marker(point: Vector2, label: String, color: Color, active: bool) -> void:
	var display := point / SPRITE_SIZE * DISPLAY_SIZE
	draw_circle(display, 12.0 if active else 8.0, color, false, 3.0)
	draw_line(display - Vector2(17, 0), display + Vector2(17, 0), color, 2.0)
	draw_line(display - Vector2(0, 17), display + Vector2(0, 17), color, 2.0)
	draw_string(ThemeDB.fallback_font, display + Vector2(14, -12), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, color)

func _anchor_color(anchor_type: String) -> Color:
	match anchor_type:
		"GripPrimary": return Color("5eead4")
		"EffectOrigin": return Color("38bdf8")
		"SpinPivot": return Color("c084fc")
		_: return Color("fb7185")
