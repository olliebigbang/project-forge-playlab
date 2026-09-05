extends SceneTree
const RIG := preload("res://scripts/sunny_player_preview/pixel_player_rig.gd")
const ARENA := preload("res://scripts/sunny_player_preview/arena.gd")
const LIBRARY := preload("res://scripts/art_vertical_slice_v1/expedition_library.gd")
var checks: Array[Dictionary] = []
var weapon_metrics: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func check_value(label: String, value: bool) -> void:
	checks.append({"name": label, "passed": value})

func _run() -> void:
	var rig := RIG.new()
	check_value("source_parts_23_body_frames", rig.poses.Idle.size() == 7 and rig.poses["Combat/GunWalk"].size() == 8 and rig.poses["Combat/GunRun"].size() == 8)
	var atlas := rig.ATLAS.get_image()
	check_value("new_neck_sockets_on_actual_opaque_skin", atlas.get_pixelv(rig.HEAD_NECK).a >= 0.94 and atlas.get_pixelv(rig.TORSO_NECK).a >= 0.94)
	check_value("new_shoulder_sockets_on_actual_sleeves", atlas.get_pixelv(rig.PRIMARY_SHOULDER).a >= 0.94 and atlas.get_pixelv(rig.SUPPORT_SHOULDER).a >= 0.94)
	var fixed_neck := true
	for pose: String in rig.poses:
		for frame: Dictionary in rig.poses[pose]:
			var neck_from_head := rig.head_rect(frame).position + (rig.HEAD_NECK - rig.HEAD_REGION.position) / rig.HEAD_REGION.size * rig.HEAD_SIZE
			fixed_neck = fixed_neck and neck_from_head.distance_to(rig.neck_local(frame)) < 0.001
	check_value("all_23_frames_share_new_torso_neck_socket", fixed_neck)
	var maximum_length_error := 0.0
	var maximum_reach_error := 0.0
	var combinations := 0
	for facing: float in [-1.0, 1.0]:
		for rotation_index: int in range(25):
			var angle := -PI + rotation_index * TAU / 24.0
			for span: float in [0.0, 16.0, 40.0, 82.0]:
				for shift: Vector2 in [Vector2(-28, -28), Vector2(0, 0), Vector2(28, 28)]:
					var shoulders: Dictionary = rig.shoulders(rig.sample(0, false, false), Vector2(600, 600), facing)
					var delta := Vector2(span * facing, 0).rotated(angle)
					var hand := RIG.constrain_hand(Vector2(shoulders.primary) + Vector2(22 * facing, 13) + shift, shoulders.primary, shoulders.support, delta, span > 0)
					var pairs: Array = [[shoulders.primary, hand]]
					if span > 0: pairs.append([shoulders.support, hand + delta])
					for pair: Array in pairs:
						var elbow := RIG.joint(pair[0], pair[1], facing)
						maximum_length_error = maxf(maximum_length_error, absf(elbow.distance_to(pair[1]) - RIG.LOWER_LENGTH))
						maximum_reach_error = maxf(maximum_reach_error, Vector2(pair[0]).distance_to(pair[1]) - RIG.MAX_REACH)
					combinations += 1
	check_value("600_pose_sweep_fixed_arm_lengths", combinations == 600 and maximum_length_error < 0.05)
	check_value("600_pose_sweep_no_overstretch", maximum_reach_error < 0.05)
	var arena := ARENA.new()
	root.add_child(arena)
	var entries: Array[Dictionary] = LIBRARY.new().load_all(false)
	check_value("five_bundled_validated_weapons", entries.size() == 5)
	for entry: Dictionary in entries:
		arena.start_stage("training", entry.blueprint, entry.asset)
		arena.set_process(false)
		var fit: Dictionary = arena._weapon_fit()
		weapon_metrics.append({"name": entry.blueprint.display_name, "axes": entry.blueprint.affordance, "grip_primary": entry.asset.grip_primary, "grip_secondary": entry.asset.grip_secondary, "tip": entry.asset.tip, "bounds": entry.asset.opaque_bounds, "fit": fit.duplicate(true), "bindings": entry.asset.visual_rig.bindings.size() if entry.asset.visual_rig != null else 0})
		var delta: Vector2 = (entry.asset.grip_secondary - entry.asset.grip_primary) * float(fit.draw_scale)
		check_value(str(entry.blueprint.display_name) + "/secondary_is_real_anchor", Vector2(fit.secondary_grip_delta).distance_to(delta) < 0.001)
		var original_name: String = entry.blueprint.display_name
		var old_solution: Dictionary = arena._hand_solution()
		entry.blueprint.display_name = "identity must not drive poses"
		arena.fit_cache.clear()
		var new_solution: Dictionary = arena._hand_solution()
		check_value(original_name + "/identity_independent", Vector2(old_solution.primary).distance_to(Vector2(new_solution.primary)) < 0.001)
		entry.blueprint.display_name = original_name
		for face: float in [-1.0, 1.0]:
			arena.facing = face
			if not arena._uses_firearm_runtime():
				arena.melee_runtime.configure(arena.blueprint, arena.asset)
				arena.melee_frame_key = ""
			var solution: Dictionary = arena._hand_solution()
			check_value(original_name + "/wrist_is_not_grip_center/" + str(face), Vector2(solution.primary).distance_to(Vector2(solution.primary_wrist)) > 4.99 and Vector2(solution.primary).distance_to(Vector2(solution.primary_wrist)) < 5.01)
			var wrist_elbow := rig.joint(solution.primary_shoulder, solution.primary_wrist, face)
			check_value(original_name + "/forearm_ends_at_wrist/" + str(face), absf(wrist_elbow.distance_to(Vector2(solution.primary_wrist)) - rig.LOWER_LENGTH) < 0.01)
			var actual_grips: Dictionary = arena._actual_grip_points(arena._firearm_hand_base(), float(solution.angle))
			check_value(original_name + "/grip_origin/" + str(face), Vector2(actual_grips.primary).distance_to(Vector2(solution.primary)) < 0.001)
			check_value(original_name + "/support_on_deformed_anchor/" + str(face), Vector2(actual_grips.secondary).distance_to(Vector2(solution.secondary)) < 0.001)
			if not arena._uses_firearm_runtime():
				arena.melee_runtime.input_attack(true, false)
				for tick: int in range(240):
					arena.melee_runtime.tick(1.0 / 60.0)
					if arena.melee_runtime.active(): break
				arena._build_melee_frame()
				var visible: Dictionary = {}
				var on_grid := true
				for pixel: Dictionary in arena.melee_frame.pixels:
					var point := Vector2(pixel.position)
					on_grid = on_grid and point == point.snapped(Vector2.ONE * arena.NATIVE_PIXEL) and float(pixel.size) >= arena.NATIVE_PIXEL
					visible[Vector2i(point)] = true
				var contacts_visible: bool = arena.melee_runtime.active() and not arena.melee_frame.contacts.is_empty()
				for point: Vector2 in arena.melee_frame.contacts:
					contacts_visible = contacts_visible and visible.has(Vector2i(point))
				check_value(original_name + "/native_pixel_grid/" + str(face), on_grid and not visible.is_empty())
				check_value(original_name + "/contacts_on_actual_visible_pixels/" + str(face), contacts_visible)
	var passed := true
	for check: Dictionary in checks: passed = passed and check.passed
	var report := {"passed": passed, "checks": checks, "pose_combinations": combinations, "max_arm_error": maximum_length_error, "max_reach_error": maximum_reach_error, "live_ai_calls": 0, "weapon_metrics": weapon_metrics}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.tools/sunny-player"))
	var file := FileAccess.open("res://.tools/sunny-player/geometry.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	print("SUNNY_PLAYER_GEOMETRY ", JSON.stringify(report))
	arena.queue_free()
	quit(0 if passed else 1)
