class_name WeaponPreview
extends Control

const UI_FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")

var asset: WeaponVisualAsset
var show_debug := false
var selected_anchor := "grip_primary"
var editable := false
var title := ""

const ANCHOR_COLORS := {
	"grip_primary": Color("5eead4"), "grip_secondary": Color("facc15"),
	"muzzle": Color("38bdf8"), "tip": Color("fb7185"), "spin_pivot": Color("c084fc")
}

func _ready() -> void:
	custom_minimum_size = Vector2(300, 260)
	focus_mode = Control.FOCUS_ALL

func configure(value: WeaponVisualAsset, debug: bool = false, can_edit: bool = false, heading: String = "") -> void:
	asset = value
	show_debug = debug
	editable = can_edit
	title = heading
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if not editable or asset == null:
		return
	if event is InputEventMouseButton and event.pressed:
		var nearest := ""
		var distance := 20.0
		for anchor_name: String in ANCHOR_COLORS.keys():
			var screen_point := _asset_to_screen(asset.get(anchor_name))
			var candidate_distance := screen_point.distance_to(event.position)
			if candidate_distance < distance:
				distance = candidate_distance
				nearest = anchor_name
		if not nearest.is_empty():
			selected_anchor = nearest
			grab_focus()
			queue_redraw()
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		asset.set(selected_anchor, _screen_to_asset(event.position))
		queue_redraw()
	if event is InputEventKey and event.pressed:
		var offset := Vector2.ZERO
		match event.keycode:
			KEY_LEFT: offset.x = -1
			KEY_RIGHT: offset.x = 1
			KEY_UP: offset.y = -1
			KEY_DOWN: offset.y = 1
		if offset != Vector2.ZERO:
			asset.set(selected_anchor, asset.get(selected_anchor) + offset)
			queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("111827"), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color("334155"), false, 2.0)
	if asset == null or asset.texture == null:
		return
	var rect := _weapon_rect()
	draw_texture_rect(asset.texture, rect, false)
	if not title.is_empty():
		draw_string(UI_FONT, Vector2(14, 24), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("f8fafc"))
	if not show_debug:
		return
	var bounds_position := _asset_to_screen(Vector2(asset.opaque_bounds.position))
	var bounds_size := Vector2(asset.opaque_bounds.size) * _scale_factor()
	draw_rect(Rect2(bounds_position, bounds_size), Color("a3e635"), false, 2.0)
	var center_y := _asset_to_screen(Vector2(0, asset.spin_pivot.y)).y
	draw_line(Vector2(rect.position.x, center_y), Vector2(rect.end.x, center_y), Color("64748b"), 1.0)
	for anchor_name: String in ANCHOR_COLORS.keys():
		var point := _asset_to_screen(asset.get(anchor_name))
		var color: Color = ANCHOR_COLORS[anchor_name]
		draw_circle(point, 6.0 if anchor_name == selected_anchor else 4.0, color)
		draw_string(ThemeDB.fallback_font, point + Vector2(7, -5), anchor_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
	var details := "confidence %.2f  |  %s" % [asset.anchor_confidence, asset.anchor_source]
	draw_string(ThemeDB.fallback_font, Vector2(14, size.y - 14), details, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("cbd5e1"))

func _weapon_rect() -> Rect2:
	var scale := _scale_factor()
	var weapon_size := Vector2(asset.canvas_size) * scale
	return Rect2((size - weapon_size) * 0.5, weapon_size)

func _scale_factor() -> float:
	return minf((size.x - 28.0) / 96.0, (size.y - 48.0) / 96.0)

func _asset_to_screen(point: Vector2) -> Vector2:
	return _weapon_rect().position + point * _scale_factor()

func _screen_to_asset(point: Vector2) -> Vector2:
	return ((point - _weapon_rect().position) / _scale_factor()).clamp(Vector2.ZERO, Vector2(asset.canvas_size - Vector2i.ONE))
