extends SceneTree
const LIBRARY := preload("res://scripts/original_sword_preview/sword_library.gd")
const PLAYER := preload("res://scripts/original_sword_preview/clip_player.gd")
var checks: Array[Dictionary] = []

func check(name: String, passed: bool) -> void:
	checks.append({"name": name, "passed": passed})
	if not passed: push_error(name)

func _initialize() -> void:
	var source := LIBRARY.new()
	check("source_load_without_fallback", source.errors.is_empty())
	if not source.errors.is_empty(): quit(1); return
	var expected := {"SwordIdle": [7, 100], "SwordWalk": [8, 100], "SwordRun": [8, 80], "SwordSlash01": [8, 80], "StandingSlash": [5, 70], "SwordCombo01": [6, 80], "SwordCombo02": [5, 80], "SwordCombo03": [5, 80], "SwordCombo04": [8, 80]}
	for clip: String in expected:
		check(clip + "_original_frame_count", source.clips[clip].size() == int(expected[clip][0]))
		var timings_ok := true
		for frame: Dictionary in source.clips[clip]: timings_ok = timings_ok and int(frame.duration_ms) == int(expected[clip][1])
		check(clip + "_independently_read_source_durations", timings_ok)
	var bytes := FileAccess.get_file_as_bytes(LIBRARY.SOURCE)
	check("reject_truncated_metadata", LIBRARY.read_metadata(bytes.slice(0, 150)).is_empty())
	var corrupt := bytes.duplicate()
	corrupt[4] = 0
	check("reject_invalid_magic", LIBRARY.read_metadata(corrupt).is_empty())
	for action: int in range(3):
		for face: float in [-1.0, 1.0]:
			var player := PLAYER.new(source)
			player.facing = face
			check("start_%d_%s" % [action, face], player.start_action(action))
			check("cannot_cut_off_authored_move_%d_%s" % [action, face], not player.start_action((action + 1) % 3))
			player.locomotion(true, true, -face)
			check("attack_facing_locked_%d_%s" % [action, face], player.facing == face)
			var all_frames := true
			for clip: String in LIBRARY.ACTIONS[action]:
				for index: int in range(source.clips[clip].size()):
					all_frames = all_frames and player.clip == clip and player.frame_index == index
					var duration: float = source.clips[clip][index].duration_ms
					player.tick((duration - 1) / 1000.0)
					all_frames = all_frames and player.clip == clip and player.frame_index == index
					player.tick(0.001)
			check("every_source_frame_exact_dwell_%d_%s" % [action, face], all_frames)
			check("returns_to_sword_idle_%d_%s" % [action, face], player.clip == "SwordIdle" and not player.attacking and player.completed_actions == 1)
	var player := PLAYER.new(source)
	player.locomotion(true, false, -1)
	check("real_sword_walk", player.clip == "SwordWalk" and player.facing == -1)
	player.locomotion(true, true, 1)
	check("real_sword_run", player.clip == "SwordRun" and player.facing == 1)
	player.locomotion(false, false, 0)
	player.tick(0.1)
	check("idle_actually_animated", player.clip == "SwordIdle" and player.frame_index == 1)
	player.inspect_step(-1)
	check("inspection_previous_frame", player.frame_index == 0)
	player.inspect_step(-1)
	check("inspection_wrap", player.frame_index == 6)
	player = PLAYER.new(source)
	player.start_action(1)
	player.tick(1.92)
	check("combo_total_1920ms_and_no_discarded_time", player.completed_actions == 1 and player.clip == "SwordIdle" and absf(player.elapsed_ms) < 0.001)
	var passed := checks.all(func(c: Dictionary) -> bool: return c.passed)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.tools/original-sword"))
	var file := FileAccess.open("res://.tools/original-sword/geometry.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": passed, "checks": checks, "source_sha256": source.source_hash, "live_ai_calls": 0}, "\t"))
	print("ORIGINAL_SWORD_TEST ", checks.size(), " checks, passed=", passed)
	quit(0 if passed else 1)
