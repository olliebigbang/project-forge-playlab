extends SceneTree
const SESSION := preload("res://scenes/original_action_preview.tscn")
const CONTROLLER := preload("res://scripts/original_action_preview/controller.gd")
const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
const SELECTED := ["combat/SwordRunSlash", "combat/SwordSprintSlash", "combat/CrouchSlash", "combat/GunFire", "combat/GunFire2H", "combat/GunCrouchFire", "combat/GunWalkFire", "combat/GunRunFire", "combat/GunSprintFire", "combat/GunReload", "combat/BowDraw", "combat/BowFire", "fishing/Prepare", "fishing/Charge", "fishing/Cast", "fishing/Idle", "fishing/Reel", "fishing/Struggle", "fishing/Catch", "body/Roll", "body/Slide", "combat/GuardImpact"]
var scene: Node2D
var output := ""
var records: Array[Dictionary] = []
var checks: Array[Dictionary] = []

class Sheet extends Node2D:
	var cells: Array[Dictionary] = []
	var title := ""
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1152, 860), Color("18383e"))
		draw_string(FONT, Vector2(16, 30), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
		for i: int in range(cells.size()):
			var cell: Dictionary = cells[i]
			var p := Vector2(i % 3 * 384, int(i / 3) * 268 + 44)
			draw_string(FONT, p + Vector2(12, 20), str(cell.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
			var size: Vector2 = cell.region.size * 0.5
			draw_texture_rect_region(cell.texture, Rect2(p + Vector2((384 - size.x) / 2, 40), size), cell.region)

func _initialize() -> void:
	if DisplayServer.get_name() == "headless": quit(1); return
	output = "res://.tools/original-actions/review-%d-%d" % [Time.get_unix_time_from_system(), OS.get_process_id()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	scene = SESSION.instantiate()
	root.add_child(scene)
	_run.call_deferred()

func capture(name: String = "") -> Image:
	scene.set_physics_process(false)
	scene.paused = true
	var before := [scene.actor.animation.clip, scene.actor.animation.index, scene.actor.facing, scene.actor.feet]
	scene.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image()
	checks.append({"name": "frozen_" + name, "passed": before == [scene.actor.animation.clip, scene.actor.animation.index, scene.actor.facing, scene.actor.feet]})
	if not name.is_empty(): checks.append({"name": "saved_" + name, "passed": result.save_png(output.path_join(name + ".png")) == OK})
	return result

func compare(actual: Image) -> Dictionary:
	var frame: Dictionary = scene.actor.animation.current()
	var original: Image = frame.image
	var origin: Vector2 = scene.actor_origin()
	var count := 0
	var wrong := 0
	for y: int in range(original.get_height()):
		for x: int in range(original.get_width()):
			var expected := original.get_pixel(x, y)
			if expected.a < 0.999: continue
			for sy: int in range(4):
				for sx: int in range(4):
					var px := int(origin.x + (x - frame.pivot.x) * 4 + sx) if scene.actor.facing > 0 else int(origin.x - (x - frame.pivot.x) * 4 - sx - 1)
					var py := int(origin.y + (y - frame.pivot.y) * 4 + sy)
					count += 1
					if px < 0 or px >= actual.get_width() or py < 0 or py >= actual.get_height(): wrong += 1; continue
					var color := actual.get_pixel(px, py)
					if maxf(absf(color.r - expected.r), maxf(absf(color.g - expected.g), absf(color.b - expected.b))) > 0.012: wrong += 1
	return {"passed": wrong == 0, "screen_pixels": count, "mismatched": wrong}

func _run() -> void:
	scene.set_physics_process(false)
	scene.actor.feet = Vector2(624, 580)
	scene.inspect_mode = true
	var cells: Array[Dictionary] = []
	var sheet_index := 1
	for face: float in [1, -1]:
		for key: String in scene.library.clips:
			for index: int in range(scene.library.clips[key].size()):
				scene.actor.inspect(key)
				scene.actor.animation.index = index
				scene.actor.facing = face
				var save_name := ""
				if key in SELECTED and index == mini(2, scene.library.clips[key].size() - 1): save_name = key.replace("/", "-") + ("-right" if face > 0 else "-left")
				var actual := await capture(save_name)
				var record := compare(actual)
				record.merge({"clip": key, "frame": index, "face": face})
				records.append(record)
				if not save_name.is_empty():
					var frame: Dictionary = scene.actor.animation.current()
					var size: Vector2 = frame.texture.get_size()
					var pivot: Vector2 = frame.pivot
					var offset := pivot if face > 0 else Vector2(size.x - pivot.x, pivot.y)
					cells.append({"name": save_name, "texture": ImageTexture.create_from_image(actual), "region": Rect2(scene.actor_origin() - offset * 4, size * 4)})
					if cells.size() == 9:
						await sheet(cells, sheet_index)
						cells = []; sheet_index += 1
	if not cells.is_empty(): await sheet(cells, sheet_index)
	# Exercise actual session/controller event routing and moving visible projectiles.
	for lowered: bool in [false, true]:
		scene.actor = CONTROLLER.new(scene.library)
		scene.actor.equip("gun")
		scene.target_feet = Vector2(864, 580)
		scene.inspect_mode = false
		scene.auto_crouch = lowered
		scene.shots.clear(); scene.projectiles.clear(); scene.hits = 0
		scene.paused = false
		scene.advance(0.001, {"attack": true})
		await capture("runtime-" + ("crouch" if lowered else "standing") + "-muzzle")
		scene.paused = false
		for tick: int in range(18): scene.advance(1.0 / 60)
		await capture("runtime-" + ("crouch" if lowered else "standing") + "-flight")
		scene.paused = false
		for tick: int in range(40): scene.advance(1.0 / 60)
		await capture("runtime-" + ("crouch" if lowered else "standing") + "-result")
		checks.append({"name": "rendered_crouch_hit_standing_miss_" + str(lowered), "passed": scene.hits == (1 if lowered else 0)})
	# Ensure alternate left-facing fishing canvas never clips the screen edges.
	for face: float in [1, -1]:
		for side: float in [220, 1060]:
			scene.actor.equip("fishing"); scene.actor.facing = face
			scene.actor.feet = Vector2(side, 488)
			scene.paused = false
			scene.inspect_mode = false
			# Reach Cast02 through the actual press/hold/release state machine.
			scene.advance(0.001, {"attack": true})
			for tick: int in range(120): scene.advance(1.0 / 120.0, {"attack": true})
			scene.advance(0.001, {})
			var timeout := 0
			while not (scene.actor.animation.clip == "fishing/Cast" and scene.actor.animation.index == 1) and timeout < 300:
				scene.advance(1.0 / 120.0, {}); timeout += 1
			checks.append({"name": "actual_cast02_at_boundary_%s_%s" % [face, side], "passed": scene.actor.animation.clip == "fishing/Cast" and scene.actor.animation.index == 1})
			scene.inspect_mode = true
			var shot := await capture("fishing-Cast02-edge-%s-%s" % [face, side])
			checks.append({"name": "fishing_edge_source_pixels_%s_%s" % [face, side], "passed": compare(shot).passed})
			scene.inspect_mode = false; scene.paused = false
			for tick: int in range(120): scene.advance(1.0 / 120.0, {})
			scene.advance(0.001, {"attack": true})
			timeout = 0
			while not (scene.actor.animation.clip == "fishing/Catch" and scene.actor.animation.index == 3) and timeout < 600:
				scene.advance(1.0 / 120.0, {}); timeout += 1
			checks.append({"name": "actual_catch04_at_top_%s_%s" % [face, side], "passed": scene.actor.animation.clip == "fishing/Catch" and scene.actor.animation.index == 3})
			scene.inspect_mode = true
			shot = await capture("fishing-Catch04-top-%s-%s" % [face, side])
			checks.append({"name": "fishing_top_source_pixels_%s_%s" % [face, side], "passed": compare(shot).passed})
	var passed := checks.all(func(c: Dictionary) -> bool: return c.passed) and records.all(func(r: Dictionary) -> bool: return r.passed)
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": passed, "records": records, "checks": checks, "renderer": RenderingServer.get_video_adapter_name(), "source_hashes": scene.library.hashes, "desktop_manual": false}, "\t"))
	print("ORIGINAL_ACTION_RENDER ", output, " states=", records.size(), " checks=", checks.size(), " passed=", passed)
	quit(0 if passed else 1)

func sheet(cells: Array[Dictionary], number: int) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1152, 860)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(viewport)
	var node := Sheet.new()
	node.cells = cells
	node.title = "Original authored action frames · actual GPU captures · %d" % number
	viewport.add_child(node)
	await process_frame
	await RenderingServer.frame_post_draw
	checks.append({"name": "contact_sheet_%d" % number, "passed": viewport.get_texture().get_image().save_png(output.path_join("sheet-%d.png" % number)) == OK})
	viewport.queue_free()
