extends Control
## Small pixel HUD meter with no inherited font/style minimum size.
var track_color := Color("32224c")
var tint := Color("d0a46d")
var value := 0.0:
	set(next):
		value = clampf(next, 0, 100)
		queue_redraw()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), track_color)
	draw_rect(Rect2(Vector2.ZERO, Vector2(floorf(size.x * value / 100), size.y)), tint)
