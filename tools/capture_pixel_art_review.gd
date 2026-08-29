extends SceneTree

const LOOP_SCENE := preload("res://scenes/automatic_level_loop.tscn")

var output_directory := "res://screenshots/pixel_art_v1"


func _initialize() -> void:
	call_deferred("_capture_review_set")


func _capture_review_set() -> void:
	var absolute_output := ProjectSettings.globalize_path(output_directory)
	DirAccess.make_dir_recursive_absolute(absolute_output)
	var loop := LOOP_SCENE.instantiate() as AutomaticLevelLoop
	# The review capture is deterministic and must not launch background AI work.
	loop.automatic_armory_attempted = true
	root.add_child(loop)
	await process_frame
	var entries: Array[Dictionary] = loop.armory.load_entries()
	if entries.is_empty():
		printerr("PIXEL_ART_CAPTURE_NO_WEAPON")
		quit(1)
		return
	loop._begin_run(entries[0])
	loop._start_next_encounter()
	for encounter_index: int in range(3):
		await create_timer(0.72).timeout
		await process_frame
		await process_frame
		var capture_path := absolute_output.path_join(
			"encounter_%d.png" % (encounter_index + 1)
		)
		var viewport_texture := root.get_viewport().get_texture()
		if viewport_texture == null:
			printerr("PIXEL_ART_CAPTURE_RENDERER_UNAVAILABLE")
			quit(2)
			return
		var capture := viewport_texture.get_image()
		if capture == null or capture.is_empty():
			printerr("PIXEL_ART_CAPTURE_IMAGE_EMPTY")
			quit(2)
			return
		var save_error := capture.save_png(capture_path)
		if save_error != OK:
			printerr("PIXEL_ART_CAPTURE_SAVE_FAILED:%s:%d" % [capture_path, save_error])
			quit(1)
			return
		print("CAPTURED | %s" % capture_path)
		if encounter_index >= 2:
			break
		loop._on_stage_completed(
			str(loop.current_encounter.get("stage_name", "")),
			{"defeated": 1, "elapsed_seconds": 1.0, "damage_taken": 0.0, "shots_fired": 1}
		)
		loop._start_next_encounter()
	loop.queue_free()
	await process_frame
	quit(0)
