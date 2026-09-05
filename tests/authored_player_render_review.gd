extends SceneTree
const SUNNY := preload("res://scripts/sunny_player_preview/authored_arena.gd")
const CHURCH := preload("res://scripts/art_vertical_slice_v1/church_arena.gd")
const LIBRARY := preload("res://scripts/art_vertical_slice_v1/expedition_library.gd")
var evidence := ""
var samples: Array[Dictionary] = []

func _initialize() -> void:
	evidence = "res://.tools/authored-player/review-%d-%d" % [int(Time.get_unix_time_from_system()), OS.get_process_id()]
	DirAccess.make_dir_recursive_absolute(evidence)
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	root.size = Vector2i(1280, 720)
	var entries: Array[Dictionary] = LIBRARY.new().load_all(false)
	for themed: int in range(2):
		var arena: GameplayArena = SUNNY.new() if themed == 0 else CHURCH.new()
		root.add_child(arena)
		for w: int in range(entries.size()):
			arena.start_stage("training", entries[w].blueprint, entries[w].asset)
			arena.set_process(false)
			arena.player_position = Vector2(620, 510)
			for face: int in [1, -1]:
				arena.facing = face
				var taken := {}
				for i: int in range(130):
					arena.touch_attack = i >= 5 and i < 60
					if i == 5: arena.request_touch_attack()
					arena.touch_vector = Vector2.RIGHT * face if i >= 90 and i < 110 else Vector2.ZERO
					if i == 112: arena.request_touch_dodge()
					arena._process(1.0 / 60)
					arena.facing = face
					var phase := str(arena.melee_runtime.controller.phase)
					var label := "idle" if i == 0 else ""
					if arena._uses_firearm_runtime() and i == 7: label = "fire"
					if not arena._uses_firearm_runtime() and phase in ["startup", "active", "recovery"] and arena.melee_runtime.controller.phase_ratio() >= 0.45 and not taken.has(phase): label = phase; taken[phase] = true
					if i == 98: label = "walk"
					if i == 116: label = "roll"
					if not label.is_empty(): await capture(arena, "%d-%d-%d-%s" % [themed, w, face, label])
				if arena._uses_firearm_runtime():
					arena.authored_moving = false; arena.authored_crouched = true; arena.shot_age = 0.03; arena.dodge_timer = 0
					await capture(arena, "%d-%d-%d-crouch" % [themed, w, face])
		arena.queue_free(); await process_frame
	var file := FileAccess.open(evidence.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"samples": samples, "count": samples.size(), "real_godot": true, "input": "scripted", "online_calls": 0}, "  "))
	print("AUTHORED_RENDER_EVIDENCE ", ProjectSettings.globalize_path(evidence))
	quit(0)

func capture(arena: GameplayArena, label: String) -> void:
	arena.queue_redraw()
	await process_frame; await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(evidence.path_join(label + ".png"))
	var crop := img.get_region(Rect2i(Vector2i(arena.player_position) - Vector2i(180, 160), Vector2i(360, 240)))
	crop.save_png(evidence.path_join(label + "-actor.png"))
	samples.append({"file": label + ".png", "actor": arena.authored_evidence, "weapon": arena.blueprint.display_name, "phase": arena.melee_runtime.controller.phase})
