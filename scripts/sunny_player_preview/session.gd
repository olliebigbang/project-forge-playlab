extends Node2D
const ARENA := preload("res://scripts/sunny_player_preview/arena.gd")
const LIBRARY := preload("res://scripts/art_vertical_slice_v1/expedition_library.gd")
const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
var arena: GameplayArena
var entries: Array[Dictionary] = []
var selected := 0
var replay := false
var clean := false
var frame := 0
var shots: Array[Dictionary] = []
var records: Array[Dictionary] = []
var markers: Dictionary = {}
var evidence := ""
var pending := false
var errors: Array[String] = []
var maximum_arm_error := 0.0
var maximum_reach_error := 0.0
var maximum_grip_error := 0.0
var maximum_head_overlap := 0.0
var phase_history: Dictionary = {}
var library_hashes: Array[String] = []

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var root := get_tree().root
	root.title = "Forge — Sunny 持械小样 V2.1（离线）"
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER
	root.size = Vector2i(1280, 720)
	root.min_size = Vector2i(640, 360)
	Engine.max_fps = 60
	var world := SubViewport.new()
	world.size = Vector2i(640, 360)
	world.disable_3d = true
	world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(world)
	arena = ARENA.new()
	arena.scale = Vector2(0.5, 0.5)
	world.add_child(arena)
	var display := Sprite2D.new()
	display.texture = world.get_texture()
	display.centered = false
	display.scale = Vector2(2, 2)
	display.z_index = -1
	add_child(display)
	var loader := LIBRARY.new()
	entries = loader.load_all(false)
	if entries.size() != 5:
		errors.append("Bundled five-weapon library unavailable: " + str(loader.diagnostics))
		print(errors)
		get_tree().quit(1)
		return
	for entry: Dictionary in entries: library_hashes.append(var_to_bytes(entry.blueprint.to_dict()).hex_encode().sha256_text())
	replay = "--replay" in OS.get_cmdline_user_args()
	if replay:
		if DisplayServer.get_name() == "headless":
			push_error("This replay requires real graphics.")
			get_tree().quit(1)
			return
		_new_evidence()
	_select(1 if "--check-handgun" in OS.get_cmdline_user_args() and not replay else 0)
	queue_redraw()

func _select(index: int) -> void:
	selected = posmod(index, entries.size())
	arena.start_stage("training", entries[selected].blueprint, entries[selected].asset)
	arena.set_process(false)
	if replay:
		var reach := (arena.asset.tip - arena.asset.grip_primary).length() * float(arena._weapon_fit().draw_scale)
		arena.player_position = Vector2(520 if arena._uses_firearm_runtime() else 780 - clampf(reach * 0.66 + 38, 70, 200), 568)
	markers.clear()
	phase_history.clear()
	maximum_arm_error = 0
	maximum_reach_error = 0
	maximum_grip_error = 0
	maximum_head_overlap = 0

func _physics_process(delta: float) -> void:
	if entries.is_empty() or pending: return
	if replay:
		frame += 1
		_replay_inputs()
	arena._process(1.0 / 60.0 if replay else delta)
	if replay:
		_inspect_pose()
		_replay_shots()
	queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if replay: return
	match event.keycode:
		KEY_ESCAPE: get_tree().quit()
		KEY_TAB: clean = not clean
		KEY_R: _select(selected)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5: _select(event.keycode - KEY_1)
		KEY_F8:
			if evidence.is_empty(): _new_evidence()
			_capture("manual-request-%d" % Time.get_ticks_msec())
	get_viewport().set_input_as_handled()

func _draw() -> void:
	if clean or entries.is_empty(): return
	draw_style_box(_panel(), Rect2(16, 16, 1248, 104))
	var name := str(entries[selected].blueprint.display_name)
	draw_string(FONT, Vector2(32, 46), "晴日持械 V2.1 · " + name.left(34), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("fff0c7"))
	var status := "双手握持" if arena._weapon_fit().get("support_required", false) else "单手握持"
	status += " · 弹匣 %d" % arena.ammo_in_magazine if arena._uses_firearm_runtime() else " · " + str(arena.melee_runtime.controller.phase)
	status += " · 累计伤害 %.0f" % arena.damage_delivered
	status += " · 同排自动压低枪口" if arena._uses_firearm_runtime() else " · 实体接触"
	draw_string(FONT, Vector2(32, 74), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("d5e6c7"))
	# Keep instructions out of the foreground where a hanging soft object can
	# extend below its holder's feet, even at the permitted front boundary.
	draw_string(FONT, Vector2(32, 103), "WASD 移动 · J/空格攻击 · K/Shift 闪避 · 1–5 换武器 · R 重置 · Tab 隐藏 · Esc 退出   |   蛙是可恢复练习靶", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("fff0c7"))

func _panel() -> StyleBoxFlat:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("203e43")
	panel.corner_radius_top_left = 8
	panel.corner_radius_top_right = 8
	panel.corner_radius_bottom_left = 8
	panel.corner_radius_bottom_right = 8
	return panel

func _replay_inputs() -> void:
	var local := frame % 360
	arena.touch_vector = Vector2.ZERO
	arena.touch_attack = (local >= 24 and local < 120) or local >= 248
	if local == 24 or local == 248: arena.request_touch_attack()
	if local >= 142 and local < 184: arena.touch_vector = Vector2.RIGHT
	if local >= 184 and local < 232: arena.touch_vector = Vector2.LEFT
	if local == 216: arena.request_touch_dodge()
	if local >= 354:
		arena.touch_attack = false
		arena.touch_vector = Vector2.ZERO
	if local == 354:
		arena.facing = 1
		arena.player_position = Vector2(640, arena.FLOOR.end.y - arena.FOOT_OFFSET.y)
		if not arena._uses_firearm_runtime():
			arena.melee_runtime.configure(arena.blueprint, arena.asset)
			arena.melee_frame_key = ""
	if local == 357: arena.facing = -1

func _inspect_pose() -> void:
	var solution: Dictionary = arena._hand_solution()
	var primary: Vector2 = solution.primary_wrist
	var shoulder: Vector2 = solution.primary_shoulder
	var elbow: Vector2 = arena.RIG.joint(shoulder, primary, arena.facing)
	maximum_arm_error = maxf(maximum_arm_error, absf(elbow.distance_to(primary) - arena.RIG.LOWER_LENGTH))
	maximum_reach_error = maxf(maximum_reach_error, primary.distance_to(shoulder) - arena.RIG.MAX_REACH)
	var action: Dictionary = arena._firearm_action_sample().get("root_pose", {})
	var visual_origin := arena._firearm_hand_base() + (Vector2(action.get("offset", Vector2.ZERO)) if arena._uses_firearm_runtime() else Vector2(arena.melee_runtime.pose(arena.facing).get("offset", Vector2.ZERO)))
	var visual_grips: Dictionary = arena._actual_grip_points(visual_origin, float(solution.angle))
	maximum_grip_error = maxf(maximum_grip_error, Vector2(visual_grips.primary).distance_to(Vector2(solution.primary)))
	if arena._weapon_fit().get("compact_silhouette", false):
		maximum_head_overlap = maxf(maximum_head_overlap, arena._head_overlap_area(visual_origin, float(solution.angle), float(arena._weapon_fit().draw_scale)))
	if solution.two_hands:
		var rear: Vector2 = solution.support_wrist
		var rear_shoulder: Vector2 = solution.support_shoulder
		var rear_elbow: Vector2 = arena.RIG.joint(rear_shoulder, rear, arena.facing)
		maximum_arm_error = maxf(maximum_arm_error, absf(rear_elbow.distance_to(rear) - arena.RIG.LOWER_LENGTH))
		maximum_reach_error = maxf(maximum_reach_error, rear.distance_to(rear_shoulder) - arena.RIG.MAX_REACH)
		maximum_grip_error = maxf(maximum_grip_error, Vector2(solution.secondary).distance_to(Vector2(visual_grips.secondary)))
	var phase := "firearm" if arena._uses_firearm_runtime() else str(arena.melee_runtime.controller.phase)
	phase_history[phase] = true

func _replay_shots() -> void:
	var local := frame % 360
	var prefix := "%02d-" % (selected + 1)
	if local == 18: _capture(prefix + "idle-right")
	if local == 174: _capture(prefix + "walk-right")
	if local == 210: _capture(prefix + "walk-left")
	if local == 220: _capture(prefix + "dodge-left")
	if local == 356: _capture(prefix + "front-boundary-idle-right")
	if local == 358: _capture(prefix + "front-boundary-idle-left")
	var phase := "fire" if arena._uses_firearm_runtime() and arena.muzzle_flash_timer > 0 else str(arena.melee_runtime.controller.phase)
	if phase in ["startup", "active", "recovery", "fire"]:
		var key := phase + ("-right" if arena.facing > 0 else "-left")
		if not markers.has(key):
			markers[key] = true
			_capture(prefix + key)
	if phase == "active" and arena.melee_runtime.controller.phase_ratio() >= 0.45:
		var peak_key := "active-peak-" + ("right" if arena.facing > 0 else "left")
		if not markers.has(peak_key):
			markers[peak_key] = true
			_capture(prefix + peak_key)
	if local == 0:
		var unchanged := library_hashes[selected] == var_to_bytes(entries[selected].blueprint.to_dict()).hex_encode().sha256_text()
		records.append({"name": entries[selected].blueprint.display_name, "source": "bundled_existing_ai_weapon", "arm_length_error_pixels": maximum_arm_error, "reach_violation_pixels": maximum_reach_error, "grip_error_pixels": maximum_grip_error, "compact_head_overlap_area": maximum_head_overlap, "damage_delivered": arena.damage_delivered, "target_damage": arena.target_damage.duplicate(), "shot_records": arena.shot_records.duplicate(true), "metrics": arena.metrics.duplicate(true), "phases": phase_history.keys(), "blueprint_unchanged": unchanged})
		if selected + 1 < entries.size(): _select(selected + 1)
		else: _finish()

func _new_evidence() -> void:
	evidence = "res://.tools/sunny-player/review-%s-%s" % [int(Time.get_unix_time_from_system()), OS.get_process_id()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence))
	print("SUNNY_PLAYER_REVIEW ", ProjectSettings.globalize_path(evidence))

func _capture(label: String) -> void:
	if pending: return
	pending = true
	await RenderingServer.frame_post_draw
	var path := evidence.path_join(label + ".png")
	var result := get_tree().root.get_texture().get_image().save_png(path)
	shots.append({"label": label, "saved": result == OK, "path": ProjectSettings.globalize_path(path), "facing": arena.facing, "moving": arena.moving, "body_pose": arena.body_frame.pose, "body_frame": arena.body_frame.index, "rig": arena.last_draw_rig, "damage": arena.damage_delivered})
	if replay and "--rig-details" in OS.get_cmdline_user_args():
		# A second real render target magnifies the exact frozen world texture.
		# No re-posed character, screenshot paintover, or smoothed interpolation.
		var detail := SubViewport.new()
		detail.size = Vector2i(900, 610)
		detail.disable_3d = true
		detail.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(detail)
		var zoom := Sprite2D.new()
		zoom.texture = arena.get_viewport().get_texture()
		zoom.centered = false
		zoom.region_enabled = true
		zoom.region_rect = Rect2((arena.player_position + arena.FOOT_OFFSET) * 0.5 - Vector2(70 if arena.facing > 0 else 110, 100), Vector2(180, 122))
		zoom.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		zoom.scale = Vector2(5, 5)
		detail.add_child(zoom)
		await RenderingServer.frame_post_draw
		var close_path := evidence.path_join(label + "-rig-detail.png")
		var close_result := detail.get_texture().get_image().save_png(close_path)
		shots[-1]["detail_path"] = ProjectSettings.globalize_path(close_path)
		shots[-1]["detail_saved"] = close_result == OK
		detail.queue_free()
	pending = false

func _finish() -> void:
	var passed := records.size() == 5 and shots.size() >= 30
	for record: Dictionary in records:
		passed = passed and record.blueprint_unchanged and float(record.arm_length_error_pixels) < 1.0 and float(record.reach_violation_pixels) < 1.0 and float(record.grip_error_pixels) < 0.1 and float(record.compact_head_overlap_area) < 1.0 and float(record.damage_delivered) > 0
	for shot: Dictionary in shots: passed = passed and shot.saved and bool(shot.get("detail_saved", true))
	var report := {"passed": passed, "records": records, "screenshots": shots, "real_godot_render": true, "desktop_manual_input": false, "live_ai_calls": 0, "user_library_read": false, "production_scene_modified": false}
	var file := FileAccess.open(evidence.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SUNNY_PLAYER_COMPLETE ", JSON.stringify({"passed": passed, "records": records, "screenshots": shots.size()}))
	get_tree().quit(0 if passed else 1)
