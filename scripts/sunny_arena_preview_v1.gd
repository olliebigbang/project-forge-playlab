extends Node2D
## Isolated environment proof, not a new combat system or a player reskin.
## The original SunnyLand fox/frogs only test scale and floor readability.
const BACKGROUND := preload("res://assets/sunny_arena_preview_v1/clearing_generated_v3.png")
const PREVIOUS_BACKGROUND := preload("res://assets/sunny_arena_preview_v1/clearing_generated_v2.png")
const FOX_IDLE := preload("res://assets/sunny_arena_preview_v1/fox_idle.png")
const FOX_RUN := preload("res://assets/sunny_arena_preview_v1/fox_run.png")
const FROG_IDLE := preload("res://assets/sunny_arena_preview_v1/frog_idle.png")
const BUSH := preload("res://assets/sunny_arena_preview_v1/bush.png")
const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
const FLOOR := Rect2(58, 210, 524, 114)
const PREVIOUS_FLOOR := Rect2(58, 224, 524, 100)
const START := Vector2(172, 284)
const SPEED := 108.0
const FROGS: Array[Vector2] = [Vector2(423, 266), Vector2(498, 310)]
const OCCLUDER := Vector2(563, 198)
const PREVIOUS_OCCLUDER := Vector2(563, 219)
const WARNING_CENTER := Vector2(423, 278)
const WARNING_RADIUS := Vector2(49, 18)
const EVIDENCE_ROOT := "res://.tools/sunny-arena-preview-v1"
const HELP := "WASD 移动 · B 前后对照 · J 预警 · H 纯场景 · Tab 文字 · Esc 退出"

var player := START
var facing := 1.0
var clock := 0.0
var moving := false
var clean_view := false
var warnings := false
var actors := true
var replay := false
var frame := 0
var evidence_dir := ""
var shots: Array[Dictionary] = []
var capture_pending := false
var checks: Array[Dictionary] = []
var world_canvas: WorldCanvas
var previous_version := false
var freeze_pose := false


class WorldCanvas extends Node2D:
	var session: Node2D
	func _draw() -> void:
		session.draw_world(self)


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var root := get_tree().root
	root.title = "Forge — SunnyLand 优化版 V3（离线）"
	root.content_scale_size = Vector2i(640, 360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER
	root.size = Vector2i(1280, 720)
	root.min_size = Vector2i(640, 360)
	Engine.max_fps = 60
	# Background and source actors share ONE native pixel grid. A separate low
	# resolution world viewport avoids shrinking the Chinese UI to 5px glyphs.
	var world := SubViewport.new()
	world.size = Vector2i(320, 180)
	world.disable_3d = true
	world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(world)
	world_canvas = WorldCanvas.new()
	world_canvas.session = self
	world_canvas.scale = Vector2(0.5, 0.5)
	world.add_child(world_canvas)
	var display := Sprite2D.new()
	display.texture = world.get_texture()
	display.centered = false
	display.scale = Vector2(2, 2)
	display.z_index = -1
	add_child(display)
	var args := OS.get_cmdline_user_args()
	replay = "--replay" in args
	_run_geometry_checks()
	if "--verify" in args:
		print("SUNNY_GEOMETRY_CHECKS ", JSON.stringify(checks))
		get_tree().quit(0 if _checks_passed() else 1)
	elif replay:
		if DisplayServer.get_name() == "headless":
			push_error("Replay requires real graphics. Use --verify for headless geometry checks.")
			get_tree().quit(1)
			return
		_new_evidence_dir()
		print("SUNNY_REPLAY_START ", ProjectSettings.globalize_path(evidence_dir))
	queue_redraw()


static func clamp_to_floor(point: Vector2, area: Rect2 = FLOOR) -> Vector2:
	return point.clamp(area.position, area.end)


static func move_step(point: Vector2, direction: Vector2, delta: float, area: Rect2 = FLOOR) -> Vector2:
	return clamp_to_floor(point + direction.limit_length(1.0) * SPEED * delta, area)


func active_floor() -> Rect2:
	return PREVIOUS_FLOOR if previous_version else FLOOR


func set_previous_version(enabled: bool) -> void:
	previous_version = enabled
	# Comparison changes art and its visible floor bounds only. Keep the pose,
	# position, clock and warning unchanged whenever the shared floor permits it.
	player = clamp_to_floor(player, active_floor())


func _physics_process(delta: float) -> void:
	if not freeze_pose: clock += delta
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if replay:
		# Automated inputs exercise the same move_step used by interactive input.
		direction = _replay_direction()
	var previous := player
	player = move_step(player, direction, delta, active_floor())
	moving = player.distance_to(previous) > 0.001
	if absf(direction.x) > 0.01: facing = signf(direction.x)
	if replay and not capture_pending:
		frame += 1
		_replay_sample()
	world_canvas.queue_redraw()
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_ESCAPE: get_tree().quit()
		KEY_TAB: clean_view = not clean_view
		KEY_B: set_previous_version(not previous_version)
		KEY_J, KEY_SPACE: warnings = not warnings
		KEY_H: actors = not actors
		KEY_R: player = START
		KEY_F8:
			if evidence_dir.is_empty(): _new_evidence_dir()
			if not capture_pending: _capture("manual-request-%s" % Time.get_ticks_msec())
	get_viewport().set_input_as_handled()


func _draw() -> void:
	if not clean_view: _draw_labels()


func draw_world(canvas: Node2D) -> void:
	# Source raster is retained without edits. The runtime world viewport samples
	# every world element on the same 320x180 grid, with no bilinear filtering.
	canvas.draw_texture_rect(PREVIOUS_BACKGROUND if previous_version else BACKGROUND, Rect2(0, 0, 640, 360), false)
	if actors:
		var bush_position := PREVIOUS_OCCLUDER if previous_version else OCCLUDER
		var entries: Array[Dictionary] = [{"y": player.y, "kind": "fox", "point": player}, {"y": bush_position.y, "kind": "bush", "point": bush_position}]
		for point: Vector2 in FROGS: entries.append({"y": point.y, "kind": "frog", "point": point})
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.y) < float(b.y))
		for entry: Dictionary in entries:
			var point: Vector2 = entry.point
			if entry.kind == "bush":
				canvas.draw_texture_rect(BUSH, Rect2(point.round() - Vector2(46, 52), Vector2(92, 56)), false)
			else:
				_draw_ellipse(canvas, point.round() + Vector2(0, 1), Vector2(17, 4), Color("866b3f"), true)
				if entry.kind == "fox":
					var sheet := FOX_RUN if moving else FOX_IDLE
					var count := 6 if moving else 4
					_draw_actor(canvas, sheet, Vector2(33, 32), int(clock * (10.0 if moving else 5.0)) % count, point, facing)
				else:
					_draw_actor(canvas, FROG_IDLE, Vector2(35, 32), int(clock * 4.0) % 4, point, 1.0)
	if warnings and actors:
		# Deliberately labelled visual-only contrast swatch. No damage or enemy AI.
		# The border is always drawn above sprites, as in the production arena.
		_draw_ellipse(canvas, WARNING_CENTER, WARNING_RADIUS, Color(0.65, 0.02, 0.10, 0.22), true)
		_draw_ellipse(canvas, WARNING_CENTER, WARNING_RADIUS + Vector2(2, 2), Color("522849"), false)
		_draw_ellipse(canvas, WARNING_CENTER, WARNING_RADIUS, Color("e42b46"), false)


func _draw_actor(canvas: Node2D, sheet: Texture2D, frame_size: Vector2, index: int, feet: Vector2, direction: float) -> void:
	canvas.draw_set_transform(feet.round(), 0.0, Vector2(direction, 1))
	# Measured opaque bottom: frog idle row 26, Foxy idle row 31 (all frames).
	# Anchor visible feet to the same floor coordinate as the shadow/depth sort,
	# rather than anchoring the frog's five transparent padding rows to the floor.
	var source_feet_y := 27.0 if sheet == FROG_IDLE else 32.0
	canvas.draw_texture_rect_region(sheet, Rect2(-frame_size.x, -source_feet_y * 2, frame_size.x * 2, 64), Rect2(Vector2(index * frame_size.x, 0), frame_size))
	canvas.draw_set_transform(Vector2.ZERO)


func _draw_ellipse(canvas: Node2D, center: Vector2, radius: Vector2, color: Color, filled: bool) -> void:
	var points := PackedVector2Array()
	for index: int in range(64):
		var angle := float(index) / 64.0 * TAU
		points.append((center + Vector2(cos(angle), sin(angle)) * radius).round())
	if filled: canvas.draw_colored_polygon(points, color)
	else:
		points.append(points[0])
		canvas.draw_polyline(points, color, 2.0, false)


func _draw_labels() -> void:
	draw_rect(Rect2(9, 9, 278, 43), Color("193f42"))
	var version_label := "上一版 V2 · 按 B 回到优化版" if previous_version else "晴日空场 · 优化版 V3"
	draw_string(FONT, Vector2(17, 27), version_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("fff1cc"))
	draw_string(FONT, Vector2(17, 44), "原包角色测试比例｜不是最终主角", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("c6dfc9"))
	draw_rect(Rect2(9, 332, 622, 22), Color("193f42"))
	draw_string(FONT, Vector2(17, 347), HELP, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("fff1cc"))
	if warnings and actors:
		draw_rect(Rect2(464, 10, 167, 21), Color("193f42"))
		draw_string(FONT, Vector2(472, 25), "预警仅验配色，不是敌人招式", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("fff1cc"))


func _new_evidence_dir() -> void:
	evidence_dir = EVIDENCE_ROOT.path_join("review-%s-%s" % [int(Time.get_unix_time_from_system()), OS.get_process_id()])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_dir))


func _capture(label: String) -> void:
	if capture_pending: return
	capture_pending = true
	await RenderingServer.frame_post_draw
	var path := evidence_dir.path_join(label + ".png")
	var code := get_tree().root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	shots.append({"label": label, "path": ProjectSettings.globalize_path(path), "saved": code == OK, "player": [player.x, player.y], "moving": moving, "facing": facing, "variant": "v2" if previous_version else "v3", "pose_clock": clock, "warnings": warnings})
	capture_pending = false


func _replay_direction() -> Vector2:
	if frame < 24: return Vector2.ZERO
	if frame < 114: return Vector2.UP
	if frame < 204: return Vector2.DOWN
	if frame < 294: return Vector2.RIGHT
	if frame < 384: return Vector2.LEFT
	return Vector2.ZERO


func _replay_sample() -> void:
	match frame:
		18: _capture("01-default")
		108: _capture("02-far-edge")
		198: _capture("03-near-edge")
		288: _capture("04-walk-right")
		378: _capture("05-walk-left")
		384:
			player = Vector2(441, 260)
			warnings = true
		390: _capture("06-behind-frog")
		396: player = Vector2(441, 282)
		402: _capture("07-in-front-of-frog")
		408:
			player = START
			clean_view = true
			warnings = false
			facing = 1.0
			clock = 0.0
			freeze_pose = true
		414: _capture("08-clean-with-original-sprites")
		420: actors = false
		426: _capture("09-clean-environment")
		432: set_previous_version(true)
		438: _capture("10-previous-environment")
		444: actors = true
		450: _capture("11-previous-with-original-sprites")
		456: set_previous_version(false)
		462: _capture("12-current-with-original-sprites")
		468:
			var saved := shots.size() == 12
			for shot: Dictionary in shots: saved = saved and bool(shot.saved)
			checks.append({"name": "twelve_real_render_screenshots", "passed": saved})
			var report := {"schema": "sunny-environment-preview-v3", "checks": checks, "screenshots": shots, "real_godot_render": true, "desktop_manual_input": false, "ai_generation_during_runtime": false, "game_saves_modified": false, "combat_integration": false, "dead_revolver_integrated": false, "reference_sprites": "original SunnyLand free pack", "world_viewport": [320, 180], "ui_viewport": [640, 360], "display": [1280, 720], "current_floor": [FLOOR.position.x, FLOOR.position.y, FLOOR.size.x, FLOOR.size.y], "previous_floor": [PREVIOUS_FLOOR.position.x, PREVIOUS_FLOOR.position.y, PREVIOUS_FLOOR.size.x, PREVIOUS_FLOOR.size.y]}
			var file := FileAccess.open(evidence_dir.path_join("report.json"), FileAccess.WRITE)
			if file == null:
				get_tree().quit(1)
				return
			file.store_string(JSON.stringify(report, "\t"))
			file.close()
			print("SUNNY_REPLAY_COMPLETE ", ProjectSettings.globalize_path(evidence_dir), " ", JSON.stringify(checks))
			get_tree().quit(0 if _checks_passed() else 1)


func _run_geometry_checks() -> void:
	checks = [
		{"name": "clamp_far_left", "passed": clamp_to_floor(Vector2(-100, -100)) == FLOOR.position},
		{"name": "clamp_near_right", "passed": clamp_to_floor(Vector2(900, 900)) == FLOOR.end},
		{"name": "unclamped_interior", "passed": clamp_to_floor(START) == START},
		{"name": "bush_outside_walk_plane", "passed": OCCLUDER.y < FLOOR.position.y},
		{"name": "two_dimensional_motion", "passed": move_step(START, Vector2.UP, 0.1).y < START.y and move_step(START, Vector2.RIGHT, 0.1).x > START.x},
		{"name": "diagonal_speed_normalized", "passed": is_equal_approx(move_step(START, Vector2.ONE, 0.1).distance_to(START), SPEED * 0.1)},
		{"name": "warning_fits_visible_floor", "passed": FLOOR.has_point(WARNING_CENTER - WARNING_RADIUS) and FLOOR.has_point(WARNING_CENTER + WARNING_RADIUS)},
		{"name": "spritesheet_frame_counts", "passed": FOX_IDLE.get_width() == 33 * 4 and FOX_RUN.get_width() == 33 * 6 and FROG_IDLE.get_width() == 35 * 4},
		{"name": "more_depth_without_less_width", "passed": FLOOR.size.y > PREVIOUS_FLOOR.size.y and FLOOR.size.x == PREVIOUS_FLOOR.size.x},
		{"name": "previous_floor_bounds_preserved", "passed": clamp_to_floor(Vector2(172, 198), PREVIOUS_FLOOR) == Vector2(172, 224)},
		{"name": "previous_bush_outside_walk_plane", "passed": PREVIOUS_OCCLUDER.y < PREVIOUS_FLOOR.position.y},
		{"name": "help_fits_viewport", "passed": FONT.get_string_size(HELP, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x <= 606}
	]
	var start_state := player
	set_previous_version(true)
	set_previous_version(false)
	checks.append({"name": "comparison_preserves_shared_position", "passed": player == start_state and not previous_version})


func _checks_passed() -> bool:
	for check: Dictionary in checks:
		if not bool(check.passed): return false
	return true
