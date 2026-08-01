class_name TouchStick
extends Control

signal vector_changed(value: Vector2)

var active_pointer := -1
var current := Vector2.ZERO
var radius := 52.0

func _ready() -> void:
	custom_minimum_size = Vector2(136, 136)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and active_pointer == -1:
			active_pointer = event.index
			_update_vector(event.position)
		elif not event.pressed and event.index == active_pointer:
			active_pointer = -1
			current = Vector2.ZERO
			vector_changed.emit(current)
			queue_redraw()
	elif event is InputEventScreenDrag and event.index == active_pointer:
		_update_vector(event.position)
	elif event is InputEventMouseButton:
		if event.pressed:
			active_pointer = 0
			_update_vector(event.position)
		else:
			active_pointer = -1
			current = Vector2.ZERO
			vector_changed.emit(current)
			queue_redraw()
	elif event is InputEventMouseMotion and active_pointer == 0 and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_update_vector(event.position)

func _draw() -> void:
	var center := size * 0.5
	draw_circle(center, radius, Color(0.15, 0.23, 0.34, 0.55))
	draw_circle(center, radius, Color("64748b"), false, 3.0)
	draw_circle(center + current * radius, 24.0, Color(0.22, 0.83, 0.83, 0.82))

func _update_vector(point: Vector2) -> void:
	var center := size * 0.5
	current = ((point - center) / radius).limit_length(1.0)
	vector_changed.emit(current)
	queue_redraw()

