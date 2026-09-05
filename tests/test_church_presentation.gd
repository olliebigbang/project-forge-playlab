extends SceneTree
const ARENA := preload("res://scripts/art_vertical_slice_v1/church_arena.gd")
const CATALOG := preload("res://scripts/enemy_attack/offline_enemy_blueprint_catalog.gd")
const DRIVER := preload("res://scripts/enemy_attack/enemy_attack_runtime_driver.gd")
var passed := 0
var failed := 0

func _initialize() -> void: call_deferred("_run")

func _check(label: String, ok: bool) -> void:
	if ok: passed += 1; print("PASS | ", label)
	else: failed += 1; printerr("FAIL | ", label)

func _run() -> void:
	var arena := ARENA.new()
	_check("Walk plane retains two-dimensional depth", ARENA.WALK_AREA.size.y >= 250.0)
	_check("Player feet remain inside authored floor", arena._clamp_to_floor(Vector2(400, 9999)).y + 46.0 < 654.0)
	_check("Rear floor projection is compressed", absf(arena._floor_project(900, 384).x - 640.0) < absf(arena._floor_project(900, 654).x - 640.0))
	_check("Presentation does not replace physical weapon renderer", not "func _draw_player_weapon_and_arms" in FileAccess.get_file_as_string("res://scripts/art_vertical_slice_v1/church_arena.gd"))
	for texture: Texture2D in [ARENA.PLAYER_WALK, ARENA.WIZARD_IDLE, ARENA.WIZARD_FIRE, ARENA.GHOUL_RUN, ARENA.GHOUL_RUSH]:
		var image := texture.get_image()
		var hard_alpha := true
		for y: int in range(image.get_height()):
			for x: int in range(image.get_width()):
				var alpha := image.get_pixel(x, y).a
				if alpha > 0.001 and alpha < 0.999: hard_alpha = false
		_check("Source sheet hard alpha: " + texture.resource_path.get_file(), hard_alpha)
	var catalog: Dictionary = CATALOG.load_validated()
	for id: String in ["ember_priest", "mechanical_spider"]:
		var runtime := DRIVER.new()
		runtime.configure(catalog.profiles_by_id[id].attack_declarations)
		runtime.current_attack = runtime.compiled_attacks[0].duplicate(true)
		var enemy := {"id": 1, "blueprint_id": id, "facing": -1.0, "attack_runtime": runtime}
		for phase: String in ["idle", "telegraph", "commit", "active", "recovery"]:
			runtime.phase = phase
			runtime.phase_elapsed = 0.0
			var before := runtime.current_attack.duplicate(true)
			var sample := arena.enemy_frame_sample(enemy, runtime.current_attack)
			var within_sheet: bool = int(sample.frame) >= 0 and (int(sample.frame) + 1) * int(sample.size.x) <= sample.texture.get_width()
			_check(id + " " + phase + " samples valid frame without changing mechanism", within_sheet and sample.phase == phase and runtime.phase == phase and runtime.phase_elapsed == 0.0 and before == runtime.current_attack)
			if id == "ember_priest" and phase == "active": _check("Wizard release begins on source release frame, not windup", sample.frame == 6)
	_check("Unknown visual identity does not silently become a Church enemy", arena.enemy_frame_sample({"blueprint_id": "unknown"}, {}).is_empty())
	arena.free()
	print("CHURCH_PRESENTATION_TESTS passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)
