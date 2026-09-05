extends SceneTree
## Offline GPU review of production Sunny melee actions. Selection is made by
## compiled structural grammar, never by item identity. No provider or save is
## touched; the screenshots are evidence, not a manual-play claim.
const SUNNY_UI := preload("res://scripts/sunny_expedition/session.gd")
const SUNNY_ARENA := preload("res://scripts/sunny_expedition/arena.gd")

var evidence := "res://.tools/action-grammar-review/gpu-%d" % OS.get_process_id()
var captures: Array[String] = []
var failures: Array[String] = []
var measurements: Array[Dictionary] = []


func _initialize() -> void:
	for key: String in ["ANTHROPIC_API_KEY", "FAL_KEY", "FAL_API_KEY"]:
		OS.unset_environment(key)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence))
	call_deferred("_run")


func _run() -> void:
	root.title = "Forge — structural melee action review"
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.show()
	var ui := SUNNY_UI.new()
	ui.include_user_library = false
	root.add_child(ui)
	await process_frame
	var entries: Array[Dictionary] = []
	for index: int in range(ui.shelf.size()):
		ui.select_weapon(index)
		var item: Dictionary = ui.entry
		var blueprint := item.get("blueprint") as WeaponBlueprint
		var asset := item.get("asset") as WeaponVisualAsset
		if blueprint == null or asset == null:
			continue
		var probe := SUNNY_ARENA.new()
		probe.melee_runtime.configure(blueprint, asset)
		var profile: Resource = probe.melee_runtime.profile
		var grammar := str(profile.compile_trace.get("presentation_grammar", "generic")) if profile != null else "generic"
		probe.free()
		if grammar in ["polearm_point", "weighted_flexible"]:
			entries.append({"item": item, "grammar": grammar})
	ui.queue_free()
	await process_frame
	for entry: Dictionary in entries:
		await _review_entry(entry)
	if entries.size() != 2:
		failures.append("EXPECTED_TWO_STRUCTURAL_GRAMMARS_GOT_%d" % entries.size())
	var report := {
		"real_godot_render": DisplayServer.get_name() != "headless",
		"desktop_manual_input": false,
		"online_calls": 0,
		"grammar_count": entries.size(),
		"captures": captures,
		"measurements": measurements,
		"failures": failures,
	}
	var file := FileAccess.open(evidence.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("STRUCTURAL_MELEE_RENDER_REVIEW ", JSON.stringify(report))
	print("EVIDENCE ", ProjectSettings.globalize_path(evidence))
	quit(0 if failures.is_empty() else 1)


func _review_entry(entry: Dictionary) -> void:
	var item: Dictionary = entry.item
	var grammar := str(entry.grammar)
	var source_asset := item.get("asset") as WeaponVisualAsset
	if source_asset != null and source_asset.visual_rig != null:
		var source_body: PackedVector2Array = source_asset.visual_rig.source_path_for_role("deform_body")
		var source_tether: PackedVector2Array = source_asset.visual_rig.source_path_for_role("tether")
		var source_blueprint := item.get("blueprint") as WeaponBlueprint
		measurements.append({
			"grammar": grammar,
			"sample": "source_geometry",
			"display_name": str(source_blueprint.display_name),
			"flex_topology": str(source_blueprint.affordance.get("flex_topology", "none")),
			"tether_topology": str(source_blueprint.affordance.get("tether_topology", "none")),
			"terminal_load": str(source_blueprint.affordance.get("terminal_load", "none")),
			"grip_primary": [source_asset.grip_primary.x, source_asset.grip_primary.y],
			"tip": [source_asset.tip.x, source_asset.tip.y],
			"body_source_start": [source_body[0].x, source_body[0].y] if not source_body.is_empty() else [],
			"body_source_finish": [source_body[-1].x, source_body[-1].y] if not source_body.is_empty() else [],
			"start_to_grip_px": source_body[0].distance_to(source_asset.grip_primary) if not source_body.is_empty() else 0.0,
			"finish_to_grip_px": source_body[-1].distance_to(source_asset.grip_primary) if not source_body.is_empty() else 0.0,
			"tether_source_start": [source_tether[0].x, source_tether[0].y] if not source_tether.is_empty() else [],
			"tether_source_finish": [source_tether[-1].x, source_tether[-1].y] if not source_tether.is_empty() else [],
		})
	var arena := SUNNY_ARENA.new()
	root.add_child(arena)
	var started: Dictionary = arena.begin_chapter(0, 14, item, 100.0, 2)
	if not bool(started.get("ok", false)):
		failures.append("%s_BEGIN_CHAPTER_FAILED_%s" % [grammar, str(started.get("error", "unknown"))])
	arena.set_process(false)
	arena.audio_enabled = false
	arena.enemies.clear()
	arena.spawn_tells.clear()
	arena.player_position = Vector2(470, 470)
	arena.facing = 1.0
	var body_actions: Dictionary = {}
	var sample_specs := [
		{"label": "windup", "motion": 0.20},
		{"label": "active_start", "motion": 0.31},
		{"label": "swing", "motion": 0.46},
		{"label": "release", "motion": 0.64},
		{"label": "late_active", "motion": 0.79},
		{"label": "recovery", "motion": 0.88},
	]
	for expected_combo: int in range(1, 4):
		_prepare_combo(arena)
		var actual_combo := int(arena.melee_runtime.controller.combo_index)
		var primitive: Resource = arena.melee_runtime.primitive()
		if actual_combo != expected_combo:
			failures.append("%s_EXPECTED_COMBO_%d_GOT_%d" % [grammar, expected_combo, actual_combo])
		var local_points := PackedVector2Array()
		var sample_angles := PackedFloat32Array()
		var maximum_forward := -INF
		var maximum_path_length := 0.0
		var minimum_longitudinal_scale := INF
		var minimum_depth_layer := INF
		var maximum_depth_layer := -INF
		var sampled_planes: Dictionary = {}
		for sample: Dictionary in sample_specs:
			_set_motion_ratio(arena, float(sample.motion))
			arena.melee_frame_key = ""
			arena.attachment_key = ""
			arena.grip_cache_key = ""
			arena._build_melee_frame()
			var hand := Vector2(arena.melee_frame.get("hand", Vector2.ZERO))
			var attachment: Dictionary = arena._attachment()
			var actual_grip := Vector2(attachment.get("hand", hand))
			var contact := _representative_contact(arena.melee_frame, hand)
			var local := Vector2((contact.x - hand.x) * arena.facing, contact.y - hand.y)
			local_points.append(local)
			sample_angles.append(local.angle())
			var forward := local.x
			for live_contact: Vector2 in arena.melee_frame.get("contacts", PackedVector2Array()):
				forward = maxf(forward, (live_contact.x - hand.x) * arena.facing)
			maximum_forward = maxf(maximum_forward, forward)
			var geometry: Dictionary = arena.melee_frame.get("geometry", {})
			maximum_path_length = maxf(maximum_path_length, _polyline_length(geometry.get("body", PackedVector2Array())) + _polyline_length(geometry.get("tether", PackedVector2Array())))
			var plane := str(arena.melee_frame.get("trajectory_plane", "screen_arc"))
			var longitudinal_scale := float(arena.melee_frame.get("longitudinal_scale", 1.0))
			var depth_layer := float(arena.melee_frame.get("depth_layer", 0.0))
			sampled_planes[plane] = true
			minimum_longitudinal_scale = minf(minimum_longitudinal_scale, longitudinal_scale)
			minimum_depth_layer = minf(minimum_depth_layer, depth_layer)
			maximum_depth_layer = maxf(maximum_depth_layer, depth_layer)
			var body_frame: Dictionary = arena._source_pose()
			body_actions[str(body_frame.get("key", "missing"))] = true
			measurements.append({
				"grammar": grammar,
				"combo": expected_combo,
				"presentation": str(primitive.presentation_family),
				"sample": str(sample.label),
				"motion_ratio": float(sample.motion),
				"phase": str(arena.melee_runtime.controller.phase),
				"body_action": str(body_frame.get("key", "missing")),
				"contact_from_hand": [snappedf(local.x, 0.1), snappedf(local.y, 0.1)],
				"weapon_origin": [snappedf(hand.x, 0.1), snappedf(hand.y, 0.1)],
				"actual_grip": [snappedf(actual_grip.x, 0.1), snappedf(actual_grip.y, 0.1)],
				"origin_from_grip": [snappedf((hand.x - actual_grip.x) * arena.facing, 0.1), snappedf(hand.y - actual_grip.y, 0.1)],
				"body_start_from_grip": _path_start_from_grip(arena.melee_frame.get("geometry", {}), actual_grip, arena.facing),
				"actual_attack_ratio": snappedf(float((arena.melee_frame.get("geometry", {}) as Dictionary).get("attack_ratio", arena.melee_runtime.motion_ratio())), 0.001),
				"trajectory_plane": plane,
				"longitudinal_scale": snappedf(longitudinal_scale, 0.001),
				"depth_layer": snappedf(depth_layer, 0.001),
				"forward_px": snappedf(forward, 0.1),
				"path_length_px": snappedf(maximum_path_length, 0.1),
			})
			var filename := "%s-%d-%s-%s.png" % [grammar, expected_combo, str(primitive.presentation_family), str(sample.label)]
			arena.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			var code := root.get_texture().get_image().save_png(evidence.path_join(filename))
			if code == OK:
				captures.append(filename)
			else:
				failures.append("CAPTURE_FAILED_%s_%d" % [filename, code])
		var minimum := Vector2(INF, INF)
		var maximum := Vector2(-INF, -INF)
		for local: Vector2 in local_points:
			minimum.x = minf(minimum.x, local.x); minimum.y = minf(minimum.y, local.y)
			maximum.x = maxf(maximum.x, local.x); maximum.y = maxf(maximum.y, local.y)
		var angular_span := _maximum_angle_difference(sample_angles)
		var horizontal_span := maximum.x - minimum.x
		var vertical_span := maximum.y - minimum.y
		measurements.append({
			"grammar": grammar,
			"combo": expected_combo,
			"presentation": str(primitive.presentation_family),
			"sample": "summary",
			"maximum_forward_px": snappedf(maximum_forward, 0.1),
			"minimum_forward_px": snappedf(minimum.x, 0.1),
			"horizontal_span_px": snappedf(horizontal_span, 0.1),
			"vertical_span_px": snappedf(vertical_span, 0.1),
			"angular_span_radians": snappedf(angular_span, 0.01),
			"maximum_path_length_px": snappedf(maximum_path_length, 0.1),
			"trajectory_planes": sampled_planes.keys(),
			"minimum_longitudinal_scale": snappedf(minimum_longitudinal_scale, 0.001),
			"depth_layer_span": snappedf(maximum_depth_layer - minimum_depth_layer, 0.001),
		})
		if maximum_forward < 42.0:
			failures.append("%s_COMBO_%d_CONTACT_BUNCHED_AT_HAND_%.1f" % [grammar, expected_combo, maximum_forward])
		if grammar == "polearm_point":
			var required_arc: float = float([0.16, 0.72, 0.90][expected_combo - 1])
			if angular_span < required_arc:
				failures.append("%s_COMBO_%d_COLLAPSED_TO_ONE_FORWARD_POSE_%.2f" % [grammar, expected_combo, angular_span])
			if expected_combo == 2:
				if not sampled_planes.has("ground_sweep") or minimum.x > -30.0 or horizontal_span < vertical_span * 1.6 or minimum_longitudinal_scale > 0.55 or maximum_depth_layer - minimum_depth_layer < 0.45:
					failures.append("%s_COMBO_2_DID_NOT_CROSS_REAR_TO_FRONT_GROUND_PLANE_%s" % [grammar, str([minimum, maximum, minimum_longitudinal_scale, minimum_depth_layer, maximum_depth_layer])])
		else:
			if minimum.x > -12.0 or maximum_forward < 42.0 or vertical_span < 18.0 or horizontal_span < vertical_span * 2.0 or angular_span < 1.35:
				failures.append("%s_COMBO_%d_TERMINAL_DID_NOT_WIND_ORBIT_CAST_%s" % [grammar, expected_combo, str([minimum, maximum, angular_span])])
			if maximum_path_length < 44.0:
				failures.append("%s_COMBO_%d_CHAIN_PATH_TOO_SHORT_%.1f" % [grammar, expected_combo, maximum_path_length])
	if body_actions.size() < 3:
		failures.append("%s_REUSED_ONE_BODY_ACTION_%s" % [grammar, str(body_actions.keys())])
	arena.queue_free()
	await process_frame


func _prepare_combo(arena: Node) -> void:
	var controller: RefCounted = arena.melee_runtime.controller
	controller.phase = "idle"
	controller.phase_elapsed = 0.0
	controller.phase_duration = 0.0
	controller.current_primitive = null
	controller.hitstop_remaining = 0.0
	controller.buffered_input = false
	controller.holding_attack = false
	controller.priming_attack = false
	arena.melee_runtime.input_attack(true, false)


func _set_motion_ratio(arena: Node, ratio: float) -> void:
	var controller: RefCounted = arena.melee_runtime.controller
	var local_ratio := 0.0
	if ratio < 0.30:
		controller.phase = "startup"
		local_ratio = ratio / 0.30
	elif ratio < 0.82:
		controller.phase = "active"
		local_ratio = (ratio - 0.30) / 0.52
	else:
		controller.phase = "recovery"
		local_ratio = (ratio - 0.82) / 0.18
	var timing: Dictionary = controller.current_timing()
	controller.phase_duration = maxf(0.001, float(timing.get(controller.phase, 0.1)))
	controller.phase_elapsed = controller.phase_duration * clampf(local_ratio, 0.0, 0.9999)


func _representative_contact(frame: Dictionary, hand: Vector2) -> Vector2:
	var geometry: Dictionary = frame.get("geometry", {})
	if geometry.has("contact"):
		return Vector2(geometry.contact)
	var result := hand
	var farthest := -1.0
	for contact: Vector2 in frame.get("contacts", PackedVector2Array()):
		var distance := hand.distance_squared_to(contact)
		if distance > farthest:
			farthest = distance
			result = contact
	return result


func _maximum_angle_difference(angles: PackedFloat32Array) -> float:
	var maximum := 0.0
	for a: float in angles:
		for b: float in angles:
			maximum = maxf(maximum, absf(wrapf(a - b, -PI, PI)))
	return maximum


func _polyline_length(path: PackedVector2Array) -> float:
	var result := 0.0
	for index: int in range(path.size() - 1):
		result += path[index].distance_to(path[index + 1])
	return result


func _path_start_from_grip(geometry: Dictionary, grip: Vector2, facing: float) -> Array:
	var body: PackedVector2Array = geometry.get("body", PackedVector2Array())
	if body.is_empty():
		return []
	return [
		snappedf((body[0].x - grip.x) * facing, 0.1),
		snappedf(body[0].y - grip.y, 0.1),
	]
