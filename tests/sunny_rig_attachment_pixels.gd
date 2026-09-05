extends SceneTree
const RIG := preload("res://scripts/sunny_player_preview/pixel_player_rig.gd")
const CUTOUT := preload("res://scripts/sunny_player_preview/crisp_alpha.gdshader")
const CELL := Vector2i(80, 100)
var records: Array[Dictionary] = []

class BodyCanvas extends Node2D:
	var rig: RefCounted
	var cells: Array[Dictionary] = []
	func _draw() -> void:
		for cell: Dictionary in cells:
			rig.draw_part(self, cell.frame, "Torso", cell.feet, cell.facing)
			rig.draw_part(self, cell.frame, "Head", cell.feet, cell.facing)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Actual rendering required for pixel attachment test")
		quit(1)
		return
	var rig := RIG.new()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 600)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var canvas := BodyCanvas.new()
	canvas.rig = rig
	canvas.scale = Vector2(0.5, 0.5)
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var material := ShaderMaterial.new()
	material.shader = CUTOUT
	canvas.material = material
	viewport.add_child(canvas)
	for pose: String in rig.poses:
		for index: int in rig.poses[pose].size():
			for facing: float in [1.0, -1.0]:
				var cell_index := canvas.cells.size()
				var origin := Vector2i(cell_index % 8, cell_index / 8) * CELL
				canvas.cells.append({"pose": pose, "index": index, "frame": rig.poses[pose][index], "facing": facing, "feet": Vector2(origin + Vector2i(40, 96)) * 2, "origin": origin})
	canvas.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var rendered := viewport.get_texture().get_image()
	for cell: Dictionary in canvas.cells:
		var head := rig.head_rect(cell.frame)
		var torso := rig.torso_rect(cell.frame)
		var head_point := head.position + Vector2(22, 22)
		var torso_point := torso.position + Vector2(22, 32)
		var head_pixel := Vector2i((Vector2(cell.feet) + Vector2(head_point.x * cell.facing, head_point.y)) * 0.5)
		var torso_pixel := Vector2i((Vector2(cell.feet) + Vector2(torso_point.x * cell.facing, torso_point.y)) * 0.5)
		var connected := _connected(rendered, head_pixel, torso_pixel, Rect2i(cell.origin, CELL))
		var head_neck := head.position + (rig.HEAD_NECK - rig.HEAD_REGION.position) / rig.HEAD_REGION.size * rig.HEAD_SIZE
		var neck_error := head_neck.distance_to(rig.neck_local(cell.frame))
		records.append({"pose": cell.pose, "frame": cell.index, "facing": cell.facing, "head_pixel": head_pixel, "torso_pixel": torso_pixel, "pixel_connected": connected, "neck_anchor_error": neck_error, "passed": connected and neck_error < 0.001})
	var directory := "res://.tools/sunny-player/attachments-%s-%s" % [int(Time.get_unix_time_from_system()), OS.get_process_id()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	rendered.save_png(directory.path_join("all-body-frames.png"))
	var passed := records.size() == 46
	for record: Dictionary in records: passed = passed and record.passed
	var file := FileAccess.open(directory.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": passed, "records": records, "real_godot_render": true, "connectivity": "4-neighbour opaque rendered pixels, head core to torso core"}, "\t"))
	file.close()
	print("RIG_ATTACHMENT_PIXELS ", JSON.stringify({"passed": passed, "frames": records.size(), "evidence": ProjectSettings.globalize_path(directory)}))
	quit(0 if passed else 1)

func _connected(img: Image, start: Vector2i, finish: Vector2i, region: Rect2i) -> bool:
	if img.get_pixelv(start).a < 0.9 or img.get_pixelv(finish).a < 0.9: return false
	var queue: Array[Vector2i] = [start]
	var visited := {start: true}
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		if current == finish: return true
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var candidate := current + direction
			if not region.has_point(candidate) or visited.has(candidate) or img.get_pixelv(candidate).a < 0.9: continue
			visited[candidate] = true
			queue.append(candidate)
	return false
