extends SceneTree
const SESSION := preload("res://scenes/original_sword_preview.tscn")
const LIBRARY := preload("res://scripts/original_sword_preview/sword_library.gd")
const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
var scene: Node2D
var output := ""
var records: Array[Dictionary] = []
var checks: Array[Dictionary] = []

class ContactSheet extends Node2D:
	var cells: Array[Dictionary] = []
	var title := ""
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1024, 540), Color("18383e"))
		draw_string(FONT, Vector2(16, 28), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color.WHITE)
		for index: int in range(cells.size()):
			var cell: Dictionary = cells[index]
			var pos := Vector2(index % 4 * 256, (index / 4) * 244 + 40)
			draw_string(FONT, pos + Vector2(14, 24), "帧 %d · %d ms" % [index + 1, cell.duration_ms], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
			# Crop an actual frozen game screenshot in the GPU. No pose redraw.
			draw_texture_rect_region(cell.texture, Rect2(pos + Vector2(32, 40), Vector2(192, 168)), cell.region)

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Requires real graphics, not headless.")
		quit(1)
		return
	output = "res://.tools/original-sword/review-%d-%d" % [Time.get_unix_time_from_system(), OS.get_process_id()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	scene = SESSION.instantiate()
	root.add_child(scene)
	scene.set_physics_process(false)
	scene.autoplay = false
	scene.paused = true
	_run.call_deferred()

func _capture(name: String) -> Image:
	# Root attachment in SceneTree._initialize precedes normal scene readiness.
	# Freeze here, after _ready, so a render wait cannot consume a requested pose.
	scene.set_physics_process(false)
	var was_paused: bool = scene.paused
	scene.paused = true
	var requested := [scene.player.clip, scene.player.frame_index, scene.player.facing, scene.feet]
	scene.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	checks.append({"name": name + "_requested_pose_preserved", "passed": requested == [scene.player.clip, scene.player.frame_index, scene.player.facing, scene.feet]})
	checks.append({"name": name + "_saved", "passed": image.save_png(output.path_join(name + ".png")) == OK})
	scene.paused = was_paused
	return image

func _run() -> void:
	scene.set_physics_process(false)
	for face: float in [1, -1]:
		for clip: String in LIBRARY.CLIPS:
			var cells: Array[Dictionary] = []
			for index: int in range(scene.library.clips[clip].size()):
				scene.player.inspect_clip(clip, index, face)
				scene.last_action = "原始帧查看"
				var name := "%s-%s-%02d" % [clip, "right" if face > 0 else "left", index + 1]
				var screenshot := await _capture(name)
				var compare := compare_source(screenshot)
				compare["clip"] = clip
				compare["frame"] = index
				compare["facing"] = face
				compare["path"] = name + ".png"
				compare["duration_ms"] = scene.player.current_frame().duration_ms
				records.append(compare)
				cells.append({"texture": ImageTexture.create_from_image(screenshot), "duration_ms": compare.duration_ms, "region": Rect2(scene.actor_origin() - Vector2(192, 336), Vector2(384, 336))})
			await _sheet(clip, face, cells)
	# Input handling and the continuously advancing production playback path.
	scene.player = preload("res://scripts/original_sword_preview/clip_player.gd").new(scene.library)
	scene.paused = false
	_send(KEY_K)
	checks.append({"name": "K_starts_original_combo", "passed": scene.player.clip == "SwordCombo01" and scene.player.attacking})
	for tick: int in range(115): scene.advance(1.0 / 60.0)
	checks.append({"name": "combo_still_finishing_at_1916ms", "passed": scene.player.attacking and scene.player.clip == "SwordCombo04"})
	scene.advance(1.0 / 60.0)
	checks.append({"name": "combo_completed_by_1933ms", "passed": not scene.player.attacking and scene.player.completed_actions == 1})
	_send(KEY_J)
	_send(KEY_T)
	scene.advance(0.16)
	checks.append({"name": "quarter_speed_dwell", "passed": scene.player.frame_index == 0 and absf(scene.player.elapsed_ms - 40) < 0.001})
	_send(KEY_P)
	var before: int = scene.player.frame_index
	scene.advance(5.0)
	checks.append({"name": "pause_holds_frame", "passed": scene.player.frame_index == before})
	_send(KEY_RIGHT)
	checks.append({"name": "paused_next_frame_key", "passed": scene.player.frame_index == before + 1})
	await _capture("paused-inspection")
	_send(KEY_R)
	checks.append({"name": "reset_restores_demo_original_speed", "passed": scene.autoplay and not scene.slow and not scene.paused})
	scene.autoplay = false
	scene.advance(0.1, -1, false)
	checks.append({"name": "move_uses_sword_walk_left", "passed": scene.player.clip == "SwordWalk" and scene.player.facing == -1})
	scene.advance(0.1, 1, true)
	checks.append({"name": "run_uses_sword_run_right", "passed": scene.player.clip == "SwordRun" and scene.player.facing == 1})
	await _capture("running")
	checks.append({"name": "running_capture_is_SwordRun", "passed": scene.player.clip == "SwordRun"})
	# Ensure the entire untouched canvas fits at both manual movement limits.
	for edge: float in [224, 1056]:
		scene.feet.x = edge
		scene.player.inspect_clip("SwordSlash01", 2, -1 if edge == 224 else 1)
		await _capture("edge-%d" % int(edge))
		checks.append({"name": "edge_%d_capture_is_maximum_slash_frame" % int(edge), "passed": scene.player.clip == "SwordSlash01" and scene.player.frame_index == 2})
		checks.append({"name": "edge_%d_pixels_unclipped" % int(edge), "passed": compare_source(root.get_texture().get_image()).passed})
	scene.feet = Vector2(624, 566)
	root.size = Vector2i(960, 540)
	await _capture("window-960x540")
	checks.append({"name": "controls_within_1280_design_canvas", "passed": scene.buttons.all(func(b: Button) -> bool: return Rect2(0, 0, 1280, 720).encloses(b.get_rect()))})
	var passed := records.all(func(r: Dictionary) -> bool: return r.passed) and checks.all(func(c: Dictionary) -> bool: return c.passed)
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": passed, "real_godot_render": true, "desktop_manual_input": false, "source_sha256": scene.library.source_hash, "records": records, "checks": checks, "live_ai_calls": 0}, "\t"))
	print("SWORD_RENDER_REVIEW ", ProjectSettings.globalize_path(output))
	print("SWORD_RENDER_COMPLETE ", JSON.stringify({"passed": passed, "source_frames_both_facings": records.size(), "checks": checks.size()}))
	quit(0 if passed else 1)

func _send(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	scene._unhandled_key_input(event)

func compare_source(actual: Image) -> Dictionary:
	var original: Image = scene.player.current_frame().texture.get_image()
	var origin: Vector2 = scene.actor_origin()
	var checked := 0
	var wrong := 0
	for y: int in range(original.get_height()):
		for x: int in range(original.get_width()):
			var expected := original.get_pixel(x, y)
			if expected.a < 0.999: continue
			checked += 1
			for sy: int in range(4):
				for sx: int in range(4):
					var px := int(origin.x + (x - 48) * 4 + sx) if scene.player.facing > 0 else int(origin.x - (x - 48) * 4 - sx - 1)
					var py := int(origin.y + (y - 84) * 4 + sy)
					if px < 0 or px >= actual.get_width() or py < 0 or py >= actual.get_height(): wrong += 1; continue
					var color := actual.get_pixel(px, py)
					if maxf(absf(color.r - expected.r), maxf(absf(color.g - expected.g), absf(color.b - expected.b))) > 0.012: wrong += 1
	return {"passed": checked > 0 and wrong == 0, "opaque_source_pixels": checked, "checked_screen_pixels": checked * 16, "mismatched_screen_pixels": wrong}

func _sheet(clip: String, face: float, cells: Array[Dictionary]) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1024, 540)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(viewport)
	var sheet := ContactSheet.new()
	sheet.cells = cells
	sheet.title = "%s · %s · actual game frame crops" % [clip, "RIGHT" if face > 0 else "LEFT"]
	viewport.add_child(sheet)
	await process_frame
	await RenderingServer.frame_post_draw
	var result := viewport.get_texture().get_image().save_png(output.path_join("sheet-%s-%s.png" % [clip, "right" if face > 0 else "left"]))
	checks.append({"name": "sheet_%s_%s" % [clip, face], "passed": result == OK})
	viewport.queue_free()
