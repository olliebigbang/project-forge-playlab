class_name SketchCanvas
extends Control

signal sketch_changed

const SOURCE_SIZE := 512
var strokes: Array[PackedVector2Array] = []
var current_stroke := PackedVector2Array()
var drawing := false

func _ready() -> void:
	custom_minimum_size = Vector2(360, 360)
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	set_process_unhandled_input(true)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_stroke(event.position)
		else:
			_end_stroke()
		accept_event()
	elif event is InputEventMouseMotion and drawing:
		_add_point(event.position)
		accept_event()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_begin_stroke(event.position)
		else:
			_end_stroke()
		accept_event()
	elif event is InputEventScreenDrag and drawing:
		_add_point(event.position)
		accept_event()

func clear_strokes() -> void:
	strokes.clear()
	current_stroke = PackedVector2Array()
	drawing = false
	queue_redraw()
	sketch_changed.emit()

func undo_last() -> void:
	if not strokes.is_empty():
		strokes.pop_back()
	queue_redraw()
	sketch_changed.emit()

func has_ink() -> bool:
	return not strokes.is_empty()

func restore_geometry(summary: Dictionary) -> void:
	strokes.clear()
	var raw_strokes: Array = summary.get("raw_strokes", [])
	for raw_value: Variant in raw_strokes:
		if not raw_value is Array:
			continue
		var restored := PackedVector2Array()
		for point_value: Variant in raw_value:
			if point_value is Array and (point_value as Array).size() >= 2:
				var point := point_value as Array
				restored.append(Vector2(
					clampf(float(point[0]), 0.0, 1.0) * maxf(1.0, size.x),
					clampf(float(point[1]), 0.0, 1.0) * maxf(1.0, size.y)
				))
		if not restored.is_empty():
			strokes.append(restored)
	current_stroke = PackedVector2Array()
	drawing = false
	queue_redraw()
	sketch_changed.emit()

func geometry_summary() -> Dictionary:
	if strokes.is_empty():
		return {
			"raw_strokes": [], "stroke_count": 0, "bounding_box": [0, 0, 0, 0],
			"aspect_ratio": 1.0, "ink_coverage": 0.0, "dominant_axis": "unknown",
			"centroid": [0.5, 0.5], "occupancy_grid_8x8": _empty_grid(), "preview_png": PackedByteArray()
		}
	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	var total := Vector2.ZERO
	var point_count := 0
	var raw: Array = []
	var grid: Array = _empty_grid()
	for stroke: PackedVector2Array in strokes:
		var raw_stroke: Array = []
		for point: Vector2 in stroke:
			var normalized := Vector2(point.x / maxf(1.0, size.x), point.y / maxf(1.0, size.y))
			min_point = min_point.min(normalized)
			max_point = max_point.max(normalized)
			total += normalized
			point_count += 1
			raw_stroke.append([snappedf(normalized.x, 0.001), snappedf(normalized.y, 0.001)])
			var gx := clampi(int(normalized.x * 8.0), 0, 7)
			var gy := clampi(int(normalized.y * 8.0), 0, 7)
			grid[gy][gx] = 1
		raw.append(raw_stroke)
	var bounds_size := max_point - min_point
	var centroid := total / float(maxi(1, point_count))
	var occupied := 0
	for row: Array in grid:
		for cell: int in row:
			occupied += cell
	return {
		"raw_strokes": raw, "stroke_count": strokes.size(),
		"bounding_box": [min_point.x, min_point.y, bounds_size.x, bounds_size.y],
		"aspect_ratio": bounds_size.x / maxf(0.02, bounds_size.y),
		"ink_coverage": float(occupied) / 64.0,
		"dominant_axis": "horizontal" if bounds_size.x >= bounds_size.y else "vertical",
		"centroid": [centroid.x, centroid.y], "occupancy_grid_8x8": grid,
		"preview_png": export_png()
	}

func export_png() -> PackedByteArray:
	var image := Image.create(SOURCE_SIZE, SOURCE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for stroke: PackedVector2Array in strokes:
		if stroke.size() == 1:
			_stamp(image, _to_source(stroke[0]), 5)
		for index: int in range(1, stroke.size()):
			_raster_line(image, _to_source(stroke[index - 1]), _to_source(stroke[index]), 5)
	return image.save_png_to_buffer()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("fffdf5"), true)
	for index: int in range(1, 8):
		var p := float(index) / 8.0
		draw_line(Vector2(size.x * p, 0), Vector2(size.x * p, size.y), Color("e7e3d8"), 1.0)
		draw_line(Vector2(0, size.y * p), Vector2(size.x, size.y * p), Color("e7e3d8"), 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color("374151"), false, 2.0)
	for stroke: PackedVector2Array in strokes:
		if stroke.size() >= 2:
			draw_polyline(stroke, Color("111827"), 7.0, true)
		elif stroke.size() == 1:
			draw_circle(stroke[0], 3.5, Color("111827"))
	if current_stroke.size() >= 2:
		draw_polyline(current_stroke, Color("111827"), 7.0, true)

func _begin_stroke(point: Vector2) -> void:
	drawing = true
	current_stroke = PackedVector2Array([_clamp_point(point)])
	queue_redraw()

func _add_point(point: Vector2) -> void:
	var clamped := _clamp_point(point)
	if current_stroke.is_empty() or current_stroke[-1].distance_to(clamped) >= 2.0:
		current_stroke.append(clamped)
		queue_redraw()

func _end_stroke() -> void:
	if not drawing:
		return
	drawing = false
	if not current_stroke.is_empty():
		strokes.append(current_stroke)
	current_stroke = PackedVector2Array()
	queue_redraw()
	sketch_changed.emit()

func _clamp_point(point: Vector2) -> Vector2:
	return Vector2(clampf(point.x, 0.0, size.x), clampf(point.y, 0.0, size.y))

func _to_source(point: Vector2) -> Vector2i:
	return Vector2i(roundi(point.x / maxf(1.0, size.x) * SOURCE_SIZE), roundi(point.y / maxf(1.0, size.y) * SOURCE_SIZE))

func _raster_line(image: Image, from: Vector2i, to: Vector2i, radius: int) -> void:
	var steps := maxi(abs(to.x - from.x), abs(to.y - from.y))
	for index: int in range(steps + 1):
		var t := float(index) / float(maxi(1, steps))
		_stamp(image, Vector2i(roundi(lerpf(from.x, to.x, t)), roundi(lerpf(from.y, to.y, t))), radius)

func _stamp(image: Image, center: Vector2i, radius: int) -> void:
	for y: int in range(maxi(0, center.y - radius), mini(SOURCE_SIZE, center.y + radius + 1)):
		for x: int in range(maxi(0, center.x - radius), mini(SOURCE_SIZE, center.x + radius + 1)):
			if Vector2(x, y).distance_to(center) <= radius:
				image.set_pixel(x, y, Color.BLACK)

func _empty_grid() -> Array:
	var grid: Array = []
	for _row: int in range(8):
		grid.append([0, 0, 0, 0, 0, 0, 0, 0])
	return grid
