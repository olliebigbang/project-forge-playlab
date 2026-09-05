extends SceneTree

const ARENA := preload("res://scripts/sunny_expedition/arena.gd")
const RULES := preload("res://scripts/sunny_expedition/rules.gd")
const CATALOG := preload("res://scripts/enemy_attack/offline_enemy_blueprint_catalog.gd")
const LIBRARY := preload("res://scripts/art_vertical_slice_v1/expedition_library.gd")
const VISUAL_ADAPTER := preload("res://scripts/sunny_expedition/enemy_visual_adapter.gd")

var directory := ""
var failures: Array[String] = []
var samples: Array[Dictionary] = []
var files: Array[String] = []

func _initialize() -> void:
	for key: String in ["ANTHROPIC_API_KEY", "FAL_KEY", "FAL_API_KEY"]: OS.unset_environment(key)
	directory = "res://.tools/sunny-enemy-roster/%d-%d" % [int(Time.get_unix_time_from_system()), OS.get_process_id()]
	DirAccess.make_dir_recursive_absolute(directory)
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	root.size = Vector2i(1280, 720)
	var library := LIBRARY.new(); library.style_id = "sunny_v1"
	var entries: Array[Dictionary] = library.load_all(false)
	if entries.is_empty(): printerr("SUNNY_ENEMY_REVIEW_WEAPON_MISSING"); quit(2); return
	var catalog := CATALOG.load_validated(RULES.SUNNY_CATALOG_PATH)
	if not bool(catalog.get("ok", false)): printerr("SUNNY_ENEMY_REVIEW_CATALOG_INVALID"); quit(2); return
	var arena := ARENA.new(); root.add_child(arena); arena.audio_enabled = false
	await process_frame
	var start := arena.begin_chapter(0, 14, entries[0], 100, 2)
	if not bool(start.get("ok", false)): printerr("SUNNY_ENEMY_REVIEW_ARENA_FAILED"); quit(2); return
	arena.set_process(false); arena.enemies.clear(); arena.spawn_tells.clear(); arena.spawn_clock = 100
	arena.player_position = Vector2(175, 525); arena.facing = 1
	var ids := ["spring_hopper", "spore_raider", "wind_wisp", "thorn_guardian"]
	var points := [Vector2(390, 475), Vector2(585, 540), Vector2(800, 470), Vector2(1040, 535)]
	for index: int in range(ids.size()):
		var profile: Dictionary = (catalog.profiles_by_id.get(ids[index], {}) as Dictionary).duplicate(true)
		profile["display_name"] = RULES.DISPLAY_NAMES[ids[index]]
		if ids[index] == "thorn_guardian":
			profile["enemy_modifier_declarations"] = RULES.make_profile(0, 0, 0, true).get("enemy_modifier_declarations", [])
		arena._spawn_enemy_blueprint(profile, points[index])
		var enemy: Dictionary = arena.enemies.back()
		enemy["expedition_elite"] = ids[index] == "thorn_guardian"
		enemy["facing"] = -1.0
		arena.enemy_is_moving[enemy.id] = index in [1, 2, 3]
	await capture(arena, "four-roles-idle.png")
	_set_attack_phase(arena, 0, "commit", 0.95)
	_record_samples(arena, "close_commit_end")
	await capture(arena, "four-roles-close-commit-end.png")
	_set_attack_phase(arena, 0, "active", 0.02)
	_record_samples(arena, "close_active_start")
	await capture(arena, "four-roles-close-active-start.png")
	_assert_continuity("close_commit_end", "close_active_start")
	_set_attack_phase(arena, 0, "active", 0.52)
	_record_samples(arena, "close_active_effect")
	await capture(arena, "four-roles-close-active-effect.png")
	_set_attack_phase(arena, 1, "commit", 0.95)
	_record_samples(arena, "far_commit_end")
	await capture(arena, "four-roles-far-commit-end.png")
	_set_attack_phase(arena, 1, "active", 0.02)
	_record_samples(arena, "far_active_start")
	await capture(arena, "four-roles-far-active-start.png")
	_assert_continuity("far_commit_end", "far_active_start")
	_set_attack_phase(arena, 1, "active", 0.48)
	_record_samples(arena, "far_active_effect")
	await capture(arena, "four-roles-far-active-effect.png")
	_assert_effect_separation()
	_prepare_wisp_lane_warning(arena, catalog.profiles_by_id as Dictionary)
	await capture(arena, "wind-wisp-lane-warning.png")
	_activate_wisp_lane(arena)
	await capture(arena, "wind-wisp-lane-active.png")
	_prepare_modifier_roster(arena, catalog.profiles_by_id as Dictionary)
	await capture(arena, "three-mechanism-champions.png")
	_spawn_modifier_hazard_examples(arena)
	await capture(arena, "three-mechanism-hazards.png")
	var report := {
		"real_gpu": true,
		"automatic_capture": true,
		"desktop_manual_input": false,
		"online_calls": 0,
		"source_family": "Ansimuz SunnyLand fantasy enemies, CC0",
		"roles": ids,
		"modifier_families": ["echo", "residue", "barrier"],
		"files": files,
		"samples": samples,
		"failures": failures,
	}
	var file := FileAccess.open(directory.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("SUNNY_ENEMY_ROSTER_EVIDENCE ", ProjectSettings.globalize_path(directory))
	arena.free(); quit(0 if failures.is_empty() else 1)


func _prepare_wisp_lane_warning(arena: Node, profiles: Dictionary) -> void:
	arena.enemies.clear()
	arena.enemy_attack_hazards.clear()
	arena.player_position = Vector2(175, 505)
	var profile := (profiles.get("wind_wisp", {}) as Dictionary).duplicate(true)
	profile["display_name"] = RULES.DISPLAY_NAMES["wind_wisp"]
	arena._spawn_enemy_blueprint(profile, Vector2(900, 505))
	var enemy: Dictionary = arena.enemies[0]
	enemy["facing"] = -1.0
	var runtime: RefCounted = enemy.attack_runtime
	var locked_target := Vector2(500, 505)
	var started: Dictionary = runtime.begin_attack({
		"distance_pixels": Vector2(enemy.pos).distance_to(locked_target),
		"depth_delta_pixels": locked_target.y - Vector2(enemy.pos).y,
		"available_coordination_budget": 1,
		"clear_path": true,
	}, Vector2(enemy.pos), locked_target)
	if not bool(started.get("ok", false)) or str(started.get("delivery", "")) != "marked_impact":
		failures.append("wind wisp far lane did not select marked_impact")
		return
	runtime.step(0.78, Vector2(enemy.pos), locked_target)
	enemy["attack_phase"] = runtime.phase


func _activate_wisp_lane(arena: Node) -> void:
	if arena.enemies.is_empty():
		return
	var enemy: Dictionary = arena.enemies[0]
	var runtime: RefCounted = enemy.attack_runtime
	# Move the player after commit. The active lane must remain at the warned
	# point and direction instead of following the new position.
	var result: Dictionary = runtime.step(0.20, Vector2(enemy.pos), Vector2(675, 440))
	var activation := result.get("activation_event", {}) as Dictionary
	if not bool(activation.get("ok", false)):
		failures.append("wind wisp lane activation event missing")
		return
	if Vector2(activation.get("origin", Vector2.ZERO)) != Vector2(500, 505):
		failures.append("wind wisp lane moved after commit")
		return
	arena._spawn_enemy_attack_hazard(enemy, activation)
	enemy["attack_phase"] = runtime.phase


func _prepare_modifier_roster(arena: Node, profiles: Dictionary) -> void:
	arena.enemies.clear()
	arena.enemy_attack_hazards.clear()
	var declarations := [
		{"blueprint_id": "spore_raider", "family": "echo", "point": Vector2(410, 520)},
		{"blueprint_id": "spring_hopper", "family": "residue", "point": Vector2(720, 505)},
		{"blueprint_id": "thorn_guardian", "family": "barrier", "point": Vector2(1015, 520)},
	]
	for declaration: Dictionary in declarations:
		var profile := (profiles.get(declaration.blueprint_id, {}) as Dictionary).duplicate(true)
		profile["display_name"] = RULES.DISPLAY_NAMES[declaration.blueprint_id]
		profile["enemy_modifier_declarations"] = [{"modifier_key": "visual_review_%s" % declaration.family, "family": declaration.family}]
		arena._spawn_enemy_blueprint(profile, Vector2(declaration.point))
		var enemy: Dictionary = arena.enemies.back()
		enemy["expedition_champion"] = true
		enemy["facing"] = -1.0
		var runtime: RefCounted = enemy.attack_runtime
		runtime.current_attack = (runtime.compiled_attacks[0] as Dictionary).duplicate(true)
		runtime.locked_direction = Vector2.LEFT
		runtime.locked_point = Vector2(enemy.pos) + Vector2(-86, 0)
		if str(declaration.family) == "echo":
			runtime.phase = "commit"
			runtime.phase_elapsed = float((runtime.current_attack.timeline as Dictionary).get("commit_seconds", 0.0))
			runtime.step(0.01, Vector2(enemy.pos), arena.player_position)
			runtime.phase = "recovery"
			runtime.phase_elapsed = 0.0
		else:
			runtime.phase = "telegraph"
			runtime.phase_elapsed = 0.16
		enemy["attack_phase"] = runtime.phase


func _spawn_modifier_hazard_examples(arena: Node) -> void:
	var echo_owner: Dictionary = arena.enemies[0]
	var residue_owner: Dictionary = arena.enemies[1]
	arena._spawn_enemy_attack_hazard(echo_owner, {
		"schema": "forge-enemy-attack-echo-event-v1",
		"delivery": "contact",
		"origin": Vector2(475, 500),
		"locked_direction": Vector2.RIGHT,
		"hazard_lifetime_seconds": 0.65,
		"hit_region": {"shape": "arc", "radius_pixels": 72.0, "arc_degrees": 95.0, "path_mode": "same_lane", "depth_tolerance_pixels": 50.0},
		"danger_zone": {"mode": "instant", "contact_mode": "single"},
		"damage_multiplier": 0.58,
	})
	arena._spawn_enemy_attack_hazard(residue_owner, {
		"schema": "forge-enemy-attack-activation-event-v1",
		"delivery": "rush",
		"origin": Vector2(745, 505),
		"locked_direction": Vector2.RIGHT,
		"hazard_lifetime_seconds": 1.65,
		"hit_region": {"shape": "strip", "length_pixels": 112.0, "width_pixels": 46.0, "path_mode": "same_lane", "depth_tolerance_pixels": 50.0},
		"danger_zone": {"mode": "lingering", "contact_mode": "continuous", "repeat_hit_cooldown_seconds": 0.38, "damage_multiplier": 0.45, "persists_after_active": true, "modifier_source": "residue"},
	})


func _set_attack_phase(arena: Node, attack_index: int, attack_phase: String, progress: float) -> void:
	for enemy: Dictionary in arena.enemies:
		var runtime: RefCounted = enemy.attack_runtime
		var selected_index := mini(attack_index, runtime.compiled_attacks.size() - 1)
		runtime.current_attack = runtime.compiled_attacks[selected_index].duplicate(true)
		runtime.phase = attack_phase
		var duration := float((runtime.current_attack.get("timeline", {}) as Dictionary).get("%s_seconds" % attack_phase, 0.0))
		runtime.phase_elapsed = duration * progress
		runtime.locked_direction = Vector2.LEFT
		enemy.attack_phase = attack_phase


func _record_samples(arena: Node, label: String) -> void:
	for enemy: Dictionary in arena.enemies:
		var sample: Dictionary = arena.enemy_frame_sample(enemy, {})
		var anchor_sample := sample.duplicate()
		anchor_sample["root"] = Vector2(enemy.pos) + Vector2(arena._enemy_ground_draw_offset()) + Vector2(sample.offset)
		var launch := Vector2.ZERO
		if (sample.get("anchors", {}) as Dictionary).has("launch"):
			launch = VISUAL_ADAPTER.world_anchor(anchor_sample, "launch")
		samples.append({
			"label": label,
			"blueprint_id": str(enemy.blueprint_id),
			"delivery": str(sample.delivery),
			"phase": str(sample.phase),
			"frame": int(sample.frame),
			"continuous_action_progress": snappedf(float(sample.continuous_action_progress), 0.001),
			"body_pixels": (sample.opaque_points as PackedVector2Array).size(),
			"effect_pixels": (sample.effect_points as PackedVector2Array).size(),
			"launch_anchor": launch,
		})


func _assert_continuity(commit_label: String, active_label: String) -> void:
	for commit: Dictionary in samples:
		if str(commit.label) != commit_label:
			continue
		for active: Dictionary in samples:
			if str(active.label) != active_label or str(active.blueprint_id) != str(commit.blueprint_id):
				continue
			if int(active.frame) < int(commit.frame) or int(active.frame) > int(commit.frame) + 1:
				failures.append("%s %s frame restarted %d -> %d" % [commit_label, commit.blueprint_id, int(commit.frame), int(active.frame)])


func _assert_effect_separation() -> void:
	for required_id: String in ["spore_raider", "thorn_guardian"]:
		var found := false
		for sample: Dictionary in samples:
			if str(sample.label) == "far_active_effect" and str(sample.blueprint_id) == required_id:
				found = true
				if int(sample.effect_pixels) <= 0:
					failures.append("%s ranged effect was not separated from body Alpha" % required_id)
				if int(sample.body_pixels) <= 0:
					failures.append("%s body Alpha became empty" % required_id)
				if Vector2(sample.launch_anchor) == Vector2.ZERO:
					failures.append("%s launch anchor missing" % required_id)
		if not found:
			failures.append("%s ranged effect sample missing" % required_id)

func capture(arena: Node, filename: String) -> void:
	arena.queue_redraw(); await process_frame; await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var result := image.save_png(directory.path_join(filename))
	if result != OK:
		failures.append("SUNNY_ENEMY_REVIEW_SAVE_FAILED:%s" % filename)
	else:
		files.append(filename)
