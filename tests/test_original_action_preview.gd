extends SceneTree
const LIB := preload("res://scripts/original_action_preview/action_library.gd")
const CONTROLLER := preload("res://scripts/original_action_preview/controller.gd")
const SESSION := preload("res://scenes/original_action_preview.tscn")
var checks: Array[Dictionary] = []
var visits: Dictionary = {}
var source: RefCounted
var scene: Node2D

func check(name: String, value: bool) -> void:
	checks.append({"name": name, "passed": value})
	if not value: push_error(name)

func run_steps(actor: RefCounted, seconds: float, controls: Dictionary = {}) -> void:
	for i: int in range(ceili(seconds * 120)):
		actor.step(1.0 / 120.0, controls)
		visits[actor.animation.clip] = true
		for event: Dictionary in actor.events:
			if event.type == "fx": visits[event.key] = true
			elif event.type == "shot": visits["weapon/Bullet"] = true
			elif event.type == "arrow": visits["weapon/Arrow"] = true
		actor.events.clear()
	visits.merge(actor.actual_visits, true)
	actor.events.clear()

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	source = LIB.new()
	check("all_sources_loaded", source.errors.is_empty())
	if not source.errors.is_empty(): print(source.errors); quit(1); return
	check("5_original_aseprite_sources", source.hashes.size() == 5)
	# Reach all advertised context clips through controls, not inspect()/gallery.
	for gear: String in ["sword", "gun", "unarmed"]:
		var contextual := CONTROLLER.new(source)
		contextual.equip(gear)
		run_steps(contextual, 0.2)
		for mode: int in range(3):
			run_steps(contextual, 0.2, {"move": Vector2.RIGHT, "run": mode == 1, "sprint": mode == 2})
			run_steps(contextual, 0.6)
		run_steps(contextual, 0.2, {"crouch": true})
		if gear == "unarmed": run_steps(contextual, 0.2, {"move": Vector2.RIGHT, "crouch": true})
		if gear == "sword":
			contextual.alternate_run = true
			run_steps(contextual, 0.2, {"move": Vector2.RIGHT, "run": true})
			run_steps(contextual, 0.2)
			run_steps(contextual, 1, {"quick": true})
			run_steps(contextual, 0.2)
			run_steps(contextual, 1, {"attack": true})
		if gear == "gun":
			run_steps(contextual, 1, {"crouch": true, "attack": true})
			run_steps(contextual, 1, {"reload": true})
		run_steps(contextual, 3, {"secondary": true})
		run_steps(contextual, 1)
		if gear == "unarmed":
			run_steps(contextual, 3, {"attack": true})
			run_steps(contextual, 0.1, {"guard": true})
			run_steps(contextual, 0.5, {"guard": true, "hit": true})
			for key: String in ["dodge", "dash", "slide", "stun"]:
				run_steps(contextual, 0.1)
				run_steps(contextual, 3, {key: true})
			for count: int in range(4):
				run_steps(contextual, 0.1)
				run_steps(contextual, 0.8, {"hit": true})
	check("fishing_real_canvas_143_104", source.frame("fishing/Idle").texture.get_size() == Vector2(143, 104))
	check("fishing_fixed_20px_canvas_offset", source.frame("fishing/Cast").pivot - source.frame("combat/SwordIdle").pivot == Vector2(20, 20))
	for item: Dictionary in source.catalog:
		check(item.key + "_scope_gate", source.clips.has(item.key) != bool(item.excluded))
	for key: String in source.clips:
		var actor := CONTROLLER.new(source)
		actor.inspect(key)
		var exact := true
		for index: int in range(source.clips[key].size()):
			exact = exact and actor.animation.index == index
			actor.animation.tick(float(source.frame(key, index).duration_ms - 1) / 1000)
			exact = exact and actor.animation.index == index
			actor.animation.tick(0.001)
			exact = exact and actor.animation.index == (index + 1) % source.clips[key].size()
		check(key + "_all_frames_original_dwell", exact)
	# Every fire clip must have its own actual source-weapon muzzle on every frame.
	for key: String in ["GunFire", "GunFire2H", "GunWalkFire", "GunRunFire", "GunSprintFire", "GunCrouchFire"]:
		for frame: Dictionary in source.clips["combat/" + key]: check(key + "_source_weapon_muzzle_%s" % frame.source_frame, frame.has("muzzle"))
	for equipment: String in ["sword", "gun", "unarmed"]:
		for pace: int in range(3):
			var a := CONTROLLER.new(source)
			a.equip(equipment)
			var controls := {"move": Vector2.RIGHT, "run": pace == 1, "sprint": pace == 2}
			run_steps(a, 0.2, controls)
			check("%s_%d_locomotion_moves" % [equipment, pace], a.feet.x > 360)
			if equipment == "unarmed": continue
			controls.attack = true
			var before: Vector2 = a.feet
			a.step(0.01, controls)
			var name := "SwordSprintSlash" if pace == 2 else "SwordRunSlash"
			if equipment == "gun": name = ["GunWalkFire", "GunRunFire", "GunSprintFire"][pace]
			check("%s_%d_selects_real_moving_attack" % [equipment, pace], a.animation.clip == "combat/" + name)
			check("%s_%d_attack_really_moves" % [equipment, pace], a.feet.x > before.x)
			check("%s_%d_attack_facing_locked" % [equipment, pace], a.facing == 1)
	var a := CONTROLLER.new(source)
	a.step(0.001, {"secondary": true})
	run_steps(a, 1.91)
	check("combo_not_cut_short", a.animation.clip == "combat/SwordCombo04" and a.animation.busy())
	run_steps(a, 0.02)
	check("combo_completes", not a.animation.busy())
	a.step(0.01, {"crouch": true, "attack": true, "move": Vector2.RIGHT})
	check("crouch_slash", a.animation.clip == "combat/CrouchSlash")
	check("armed_crouch_not_sliding", a.feet == Vector2(360, 580))
	a = CONTROLLER.new(source)
	a.equip("gun")
	run_steps(a, 8, {"attack": true})
	check("gun_auto_reload_and_repeats", a.actual_visits.has("combat/GunReload") and a.actual_visits.has("combat/GunFire") and a.ammo >= 0)
	a = CONTROLLER.new(source); a.equip("gun")
	a.step(0.001, {"move": Vector2.RIGHT, "attack": true})
	while a.animation.busy(): a.step(0.001, {})
	check("release_movement_during_fire_no_stale_walk_frame", a.animation.clip == "combat/GunAim")
	a = CONTROLLER.new(source); a.equip("gun")
	a.step(0.001, {"crouch": true, "attack": true})
	while a.animation.busy(): a.step(0.001, {})
	check("release_manual_crouch_no_stale_crouch_frame", a.animation.clip == "combat/GunAim")
	a = CONTROLLER.new(source)
	a.equip("fishing")
	run_steps(a, 1, {"attack": true})
	check("rod_prepare_then_charge", a.animation.clip == "fishing/Charge")
	run_steps(a, 0.01)
	check("release_casts", a.animation.clip == "fishing/Cast")
	run_steps(a, 1)
	check("rod_wait_after_cast", a.fishing_phase == "cast" and a.animation.clip == "fishing/Idle")
	a.step(0.01, {"attack": true})
	run_steps(a, 3)
	check("full_retrieve_original_chain", ["fishing/Reel", "fishing/Struggle", "fishing/Catch"].all(func(k: String) -> bool: return a.actual_visits.has(k)))
	check("rod_ready_again", a.fishing_phase == "ready")
	var feet: Vector2 = a.feet
	run_steps(a, 1, {"move": Vector2.RIGHT})
	check("no_fake_rod_walk", a.feet == feet and a.animation.clip == "fishing/Idle")
	a = CONTROLLER.new(source)
	a.equip("bow")
	run_steps(a, 1, {"attack": true})
	check("bow_draw_then_hold", a.animation.clip == "combat/BowAim")
	a.step(0.01, {})
	check("bow_release_original_fire", a.animation.clip == "combat/BowFire")
	check("bow_release_event_once", a.events.filter(func(e: Dictionary) -> bool: return e.type == "arrow").size() == 1)
	run_steps(a, 1)
	a = CONTROLLER.new(source)
	a.step(0.01, {"guard": true})
	check("guard_held", a.animation.clip == "combat/Guard")
	a.step(0.01, {"guard": true, "hit": true})
	check("guard_impact_not_damage", a.animation.clip == "combat/GuardImpact" and a.health == 100)
	a = CONTROLLER.new(source)
	for i: int in range(4):
		a.step(0.01, {"hit": true}); run_steps(a, 0.01)
	check("four_hits_enter_death", a.health == 0 and a.animation.clip == "body/Die")
	run_steps(a, 5, {"attack": true, "move": Vector2.RIGHT})
	check("death_holds_final_frame_without_sliding", a.animation.clip == "body/Die" and a.animation.index == source.clips["body/Die"].size() - 1 and a.feet.x == 360)
	for control: String in ["dodge", "dash", "slide"]:
		a = CONTROLLER.new(source)
		a.step(0.1, {control: true})
		check(control + "_moves_authored_full_body", a.feet.x > 360)
	scene = SESSION.instantiate()
	root.add_child(scene)
	scene.set_physics_process(false)
	scene.actor.equip("gun")
	scene.auto_crouch = false
	check("standing_source_muzzle_higher_than_crouching", scene.muzzle("combat/GunFire").y < scene.muzzle("combat/GunCrouchFire").y)
	check("standing_ray_misses_low_frog", not scene.ray_hits_target("combat/GunFire"))
	check("crouch_ray_meets_visible_frog", scene.ray_hits_target("combat/GunCrouchFire"))
	for face: float in [1, -1]:
		for distance: float in [220, 460]:
			scene.actor = CONTROLLER.new(source)
			scene.actor.equip("gun")
			scene.actor.feet = Vector2(640 - face * distance * 0.5, 580)
			scene.actor.facing = face
			scene.target_feet = Vector2(640 + face * distance * 0.5, 580)
			scene.shots.clear(); scene.projectiles.clear()
			scene.auto_crouch = true
			for tick: int in range(120): scene.advance(1.0 / 120.0, {"attack": tick == 0})
			check("%s_%s_auto_crouch_real_hit" % [face, distance], scene.shots.size() == 1 and scene.shots[0].clip == "combat/GunCrouchFire" and scene.shots[0].hit)
			check("%s_%s_bullet_horizontal_not_hidden_diagonal" % [face, distance], scene.shots[0].velocity.y == 0)
			var origin: Vector2 = scene.shots[0].origin
			check("%s_%s_origin_matches_source_muzzle" % [face, distance], origin == scene.muzzle("combat/GunCrouchFire"))
	# Same path, auto crouch off: visible standing shot must actually miss.
	scene.actor = CONTROLLER.new(source); scene.actor.equip("gun")
	scene.target_feet = Vector2(864, 580)
	scene.shots.clear(); scene.projectiles.clear(); scene.auto_crouch = false
	for tick: int in range(180): scene.advance(1.0 / 120.0, {"attack": tick == 0})
	check("standing_counterexample_misses", scene.shots.size() == 1 and not scene.shots[0].hit)
	scene.actor = CONTROLLER.new(source); scene.actor.equip("gun"); scene.auto_crouch = true
	scene.advance(0.001, {"attack": true})
	var posture_kept := true
	for tick: int in range(100):
		scene.advance(1.0 / 120.0)
		posture_kept = posture_kept and scene.actor.animation.clip in ["combat/GunCrouchFire", "combat/GunCrouch"]
	check("auto_crouch_never_pops_to_standing_after_shot", posture_kept)
	# No auto crouch when moving, or when the target is on a different ground row.
	scene.actor = CONTROLLER.new(source); scene.actor.equip("gun"); scene.auto_crouch = true
	scene.advance(0.01, {"move": Vector2.RIGHT, "attack": true})
	check("moving_fire_not_overridden_by_auto_crouch", scene.actor.animation.clip == "combat/GunWalkFire")
	scene.actor = CONTROLLER.new(source); scene.actor.equip("gun")
	scene.target_feet.y = 488
	scene.advance(0.01, {"attack": true})
	check("different_height_not_promised_by_crouch", scene.actor.animation.clip == "combat/GunFire")
	# Moving attacks were entered above with a first single step; their runtime
	# linkage is asserted separately. Mark only those actually tested routes.
	for key: String in ["combat/SwordRunSlash", "combat/SwordSprintSlash", "combat/GunWalkFire", "combat/GunRunFire", "combat/GunSprintFire", "combat/CrouchSlash"]:
		var route := CONTROLLER.new(source)
		route.equip("gun" if key.contains("Gun") else "sword")
		run_steps(route, 0.12, {"move": Vector2.RIGHT, "attack": true, "run": key.contains("Run"), "sprint": key.contains("Sprint"), "crouch": key.contains("Crouch")})
	for item: Dictionary in source.catalog:
		if item.contextual: check(item.key + "_actually_reachable_via_context_not_gallery", visits.has(item.key))
	for face: float in [1, -1]:
		for edge: float in [220, 1060]:
			scene.actor.equip("fishing"); scene.actor.facing = face
			scene.actor.feet = Vector2(edge, 488)
			scene.advance(0.001, {"attack": true})
			var inside := true
			for sample: Array in [["fishing/Cast", 1], ["fishing/Catch", 3]]:
				var frame: Dictionary = source.frame(sample[0], sample[1])
				var img: Image = frame.image
				for y: int in range(img.get_height()):
					for x: int in range(img.get_width()):
						if img.get_pixel(x, y).a < 0.5: continue
						var p: Vector2 = scene.actor_origin() + (Vector2(x + 0.5, y + 0.5) - frame.pivot) * Vector2(face, 1) * 4
						inside = inside and p.x >= 0 and p.x < 1280 and p.y >= 156 and p.y < 614
			check("longest_cast_inside_both_edges_and_below_hud_%s_%s" % [face, edge], inside)
	var passed := checks.all(func(c: Dictionary) -> bool: return c.passed)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.tools/original-actions"))
	var file := FileAccess.open("res://.tools/original-actions/test-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": passed, "checks": checks, "source_hashes": source.hashes, "catalog": source.catalog, "clips": source.clips.size(), "visited_in_controller_tests": visits.keys(), "ai_calls": 0}, "\t"))
	print("ORIGINAL_ACTIONS_TEST checks=", checks.size(), " passed=", passed, " clips=", source.clips.size())
	scene.queue_free()
	quit(0 if passed else 1)
