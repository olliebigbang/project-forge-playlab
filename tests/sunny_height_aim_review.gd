extends SceneTree
const SESSION := preload("res://scripts/sunny_player_preview/session.gd")
var evidence := ""

func _initialize() -> void:
	_run.call_deferred()

func _capture(label: String) -> String:
	await RenderingServer.frame_post_draw
	var path := evidence.path_join(label + ".png")
	root.get_texture().get_image().save_png(path)
	return ProjectSettings.globalize_path(path)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Actual OpenGL required for visual aim evidence.")
		quit(1)
		return
	seed(834705)
	var session := SESSION.new()
	root.add_child(session)
	session.set_physics_process(false)
	evidence = "res://.tools/sunny-player/aim-review-%s-%s" % [int(Time.get_unix_time_from_system()), OS.get_process_id()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence))
	print("SUNNY_AIM_REVIEW ", ProjectSettings.globalize_path(evidence))
	var records: Array[Dictionary] = []
	for selected: int in [0, 1]:
		for face: float in [1.0, -1.0]:
			for distance: float in [80.0, 140.0, 300.0]:
				session._select(selected)
				var arena: GameplayArena = session.arena
				arena.player_position = Vector2(900 if face < 0 else 360, arena.FLOOR.end.y - arena.FOOT_OFFSET.y)
				arena.facing = face
				arena.enemies.clear()
				arena._spawn_enemy("target", arena.player_position + Vector2(distance * face, 0), 150)
				arena.touch_attack = false
				arena._process(1.0 / 60)
				session.queue_redraw()
				var label := "%02d-%s-%d-lowest" % [selected + 1, "right" if face > 0 else "left", distance]
				var pose: String = await _capture(label + "-aim")
				arena.touch_attack = true
				arena.request_touch_attack()
				var frames := 0
				var firing := ""
				for tick: int in range(120):
					arena._process(1.0 / 60)
					session.queue_redraw()
					if firing.is_empty() and (tick == 1 or arena.damage_delivered > 0): firing = await _capture(label + "-fire")
					await process_frame
					frames += 1
					if arena.damage_delivered > 0: break
				var hit: String = await _capture(label + "-hit")
				records.append({"name": arena.blueprint.display_name, "distance": distance, "face": face, "ground_y": arena.player_position.y, "damage": arena.damage_delivered, "frames_to_hit": frames, "aim": pose, "fire": firing, "hit": hit, "shot_records": arena.shot_records.duplicate(true), "passed": arena.damage_delivered > 0})
	var passed := records.size() == 12
	for result: Dictionary in records: passed = passed and result.passed
	var report := {"passed": passed, "records": records, "real_godot_render": true, "desktop_manual_input": false, "live_ai_calls": 0}
	var file := FileAccess.open(evidence.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SUNNY_AIM_COMPLETE ", JSON.stringify({"passed": passed, "cases": records.size()}))
	quit(0 if passed else 1)
