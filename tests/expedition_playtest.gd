extends SceneTree
## Scripted normal input only. No health, objective, enemy or damage overrides.
## --render captures actual engine frames; default is accelerated fixed-step QA.
const UI := preload("res://scripts/art_vertical_slice_v1/church_expedition.gd")
const SUNNY_UI := preload("res://scripts/sunny_expedition/session.gd")
const WEAPON_LIBRARY := preload("res://scripts/combat_feel/weapon_library_store.gd")
const EXPEDITION_LIBRARY := preload("res://scripts/art_vertical_slice_v1/expedition_library.gd")
var imported_library_root := ""
var imported_library_key := ""
var camp_library_keys := PackedStringArray()
var structural_bot := false
var ability_until := -1.0
var sunny := false
var ui: Node
var render := false
var batch_render := false
var chosen := 0
var requested_identity := ""
var seed_value := 14
var naive := false
var hub_only := false
var evidence := ""
var clock := 0.0
var steps := 0
var captured := {}
var last_dodge := -10.0
var last_attack := -10.0
var last_log := -30.0
var chapter_results: Array = []
var run_started := false
var real_started := 0
var frame_samples: Array[float] = []
var maximum_seconds := 1300.0
var tracked_enemy := ""
var kite_side := 1.0
var camp_swap := false
var quick_trial := false
var equipment_history: Array[String] = []

func _initialize() -> void:
	for name: String in ["ANTHROPIC_API_KEY", "FAL_KEY", "FAL_API_KEY"]: OS.unset_environment(name)
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--sunny": sunny = true
		if arg.begins_with("--library-root="): imported_library_root = arg.trim_prefix("--library-root=")
		if arg.begins_with("--library-key="): imported_library_key = arg.trim_prefix("--library-key=")
		if arg.begins_with("--camp-library-keys="): camp_library_keys = arg.trim_prefix("--camp-library-keys=").split(","); camp_swap = true
		if arg == "--structural-bot": structural_bot = true
		if arg == "--camp-swap": camp_swap = true
		if arg == "--render": render = true
		if arg == "--batch-render": render = true; batch_render = true
		if arg == "--naive": naive = true
		if arg == "--hub-only": hub_only = true; render = true; batch_render = true
		if arg == "--trial": quick_trial = true
		if arg.begins_with("--weapon="): chosen = int(arg.trim_prefix("--weapon="))
		if arg.begins_with("--identity="): requested_identity = arg.trim_prefix("--identity=")
		if arg.begins_with("--seed="): seed_value = int(arg.trim_prefix("--seed="))
		if arg.begins_with("--seconds="): maximum_seconds = clampf(float(arg.trim_prefix("--seconds=")), 1, 1300)
	evidence = "res://.tools/expedition-playtest/%d-%d" % [int(Time.get_unix_time_from_system()), OS.get_process_id()]
	DirAccess.make_dir_recursive_absolute(evidence)
	OS.set_environment("FORGE_WEAPON_LIBRARY_ROOT", evidence.path_join("isolated-library"))
	call_deferred("run")

func run() -> void:
	ui = SUNNY_UI.new() if sunny else UI.new(); ui.include_user_library = false
	root.add_child(ui); await process_frame
	ui.set_process(false); ui.arena.audio_enabled = false
	if not requested_identity.is_empty():
		chosen = -1
		for index: int in range(ui.shelf.size()):
			if str(ui.shelf[index].identity).contains(requested_identity): chosen = index; break
		if chosen < 0: printerr("PLAYTEST_IDENTITY_NOT_FOUND ", requested_identity); quit(2); return
	print("PLAYTEST_CATALOG ", ui.shelf.map(func(w: Dictionary) -> String: return str(w.identity)))
	ui.select_weapon(chosen)
	if not imported_library_key.is_empty():
		var source_store := WEAPON_LIBRARY.new(); source_store.root_path = imported_library_root
		var imported := source_store.load_entry(imported_library_key)
		if imported.get("ok", false):
			# Read and style-adapt an immutable source package in memory. The source
			# library is never rewritten by this playtest.
			imported = EXPEDITION_LIBRARY.prepare(imported, "sunny_v1" if sunny else "church_v1")
		if not imported.get("ok", false) or not ui.validate_entry(imported, "sunny_v1" if sunny else "church_v1").get("ok", false):
			printerr("PLAYTEST_IMPORTED_ENTRY_INVALID"); quit(2); return
		# Read the immutable source; all campaign/save operations remain isolated.
		ui.shelf.push_front(imported); ui.select_weapon(0)
	seed(seed_value)
	equipment_history.append(str(ui.entry.identity))
	await capture("hub")
	if hub_only:
		print("HUB_ONLY_EVIDENCE ", ProjectSettings.globalize_path(evidence))
		ui.queue_free(); await process_frame; quit(0); return
	if sunny and quick_trial: ui.start_trial_run(seed_value)
	else: ui.start_new_run(seed_value)
	if sunny and ui.flow == "route_choice":
		await capture("story-route-%d" % (ui.run_chapter + 1))
		ui.choose_story_route(str(["brook", "grove", "ridge"][ui.run_chapter % 3]))
	await capture("briefing")
	ui.begin_chapter(); real_started = Time.get_ticks_msec()
	while clock < maximum_seconds and ui.flow not in ["result", "defeated"]:
		if sunny and ui.flow == "route_choice":
			chapter_results.append(ui.totals.duplicate(true))
			await capture("chapter-%d-route" % ui.run_chapter)
			ui.choose_story_route(str(["brook", "grove", "ridge"][ui.run_chapter % 3]))
			await capture("chapter-%d-briefing" % (ui.run_chapter + 1))
			ui.begin_chapter()
		if ui.flow == "camp":
			chapter_results.append(ui.totals.duplicate(true))
			await capture("chapter-%d-camp" % ui.run_chapter)
			if camp_swap:
				ui._dialog_secondary()
				if not camp_library_keys.is_empty():
					var store := WEAPON_LIBRARY.new(); store.root_path = imported_library_root
					var replacement := store.load_entry(camp_library_keys[mini(ui.run_chapter - 1, camp_library_keys.size() - 1)])
					if not replacement.get("ok", false): printerr("CAMP_IMPORTED_ENTRY_INVALID"); quit(2); return
					ui.shelf.push_front(replacement); ui.select_weapon(0)
				else: ui.select_weapon(2 if ui.run_chapter == 1 else 4)
				equipment_history.append(str(ui.entry.identity))
				await capture("chapter-%d-weapon-change" % ui.run_chapter)
				ui._resume_after_selection()
			else: ui.begin_chapter()
		if ui.flow == "upgrade":
			var upgrade_number: int = ui.arena.upgrade_history.size() + 1
			await capture("chapter-%d-upgrade-%d" % [ui.run_chapter + 1, upgrade_number])
			# Exercise a different column at each roadpost. This is a normal player
			# choice, not a health, damage, objective or position override.
			var upgrade_result: Dictionary = ui.choose_upgrade((upgrade_number - 1) % 3)
			if not upgrade_result.get("ok", false):
				printerr("PLAYTEST_UPGRADE_FAILED ", upgrade_result)
				quit(2)
				return
		if ui.flow != "combat": break
		var delta := 1.0 / 30.0
		if render and not batch_render: await process_frame; delta = minf(root.get_process_delta_time(), 0.05)
		bot(delta)
		var tick_start := Time.get_ticks_usec()
		ui._process(delta)
		frame_samples.append((Time.get_ticks_usec() - tick_start) / 1000.0)
		clock += delta; steps += 1
		if int(clock) >= last_log + 30:
			last_log = int(clock)
			print("EXPEDITION_PROGRESS ", JSON.stringify({"weapon": chosen, "seconds": snappedf(clock,0.1), "chapter": ui.run_chapter + 1, "phase": ui.arena.phase, "seal": ui.arena.seal_index, "charge": snappedf(ui.arena.seal_progress,0.1), "health": snappedf(ui.arena.player_health,0.1), "enemies": ui.arena.enemies.size(), "flow": ui.flow}))
		if render and ui.flow == "combat":
			var prefix := "chapter-%d-" % (ui.run_chapter + 1)
			if clock > 1 and not captured.has(prefix + "combat"): await capture(prefix + "combat")
			if ui.arena.enemies.any(func(enemy: Dictionary) -> bool: return bool(enemy.get("expedition_champion", false))) and not captured.has(prefix + "champion"): await capture(prefix + "champion")
			if ui.arena.phase == "guardian" and not captured.has(prefix + "guardian"): await capture(prefix + "guardian")
			if ui.arena.seal_index == 1 and not captured.has(prefix + "second-seal"): await capture(prefix + "second-seal")
			if (ui.arena.melee_runtime.active() or ui.arena.muzzle_flash_timer > 0) and not captured.has(prefix + "attack"): await capture(prefix + "attack")
		if (not render or batch_render) and steps % 120 == 0: await process_frame
	await capture(ui.flow)
	if ui.flow == "combat" and not ui.arena.melee_frame.is_empty():
		var contact_bounds := Rect2()
		var first := true
		for point: Vector2 in ui.arena.melee_frame.contacts:
			if first: contact_bounds = Rect2(point, Vector2.ZERO); first = false
			else: contact_bounds = contact_bounds.expand(point)
		print("MELEE_CONTEXT ", JSON.stringify({"player": ui.arena.player_position, "frame": ui.arena.authored_evidence, "hand": ui.arena.melee_frame.hand, "contact_bounds": contact_bounds, "enemies": ui.arena.enemies.map(func(e: Dictionary) -> Dictionary: return {"pos":e.pos, "hp":e.hp})}))
	frame_samples.sort()
	var report := {"campaign": "sunny" if sunny else "church", "weapon_index": chosen, "identity": ui.entry.blueprint.display_name, "input": "naive_attack" if naive else "objective_and_warning_aware_bot", "flow": ui.flow, "simulated_seconds": snappedf(clock,0.1), "wall_seconds": (Time.get_ticks_msec()-real_started)/1000.0, "real_godot_render": render, "manual_desktop": false, "online_calls": 0, "health": ui.arena.player_health, "metrics": ui.totals if ui.flow == "result" else ui.arena.metrics, "chapters": chapter_results, "runtime_error": ui.arena.melee_runtime.error, "step_ms_p50": frame_samples[frame_samples.size()/2] if not frame_samples.is_empty() else 0, "step_ms_p95": frame_samples[int(frame_samples.size()*0.95)] if not frame_samples.is_empty() else 0, "not_full_frame_benchmark": true, "captures": captured.keys()}
	report["equipment_history"] = equipment_history
	report["seed"] = seed_value
	report["imported_library_key"] = imported_library_key
	report["structural_hold_inputs"] = structural_bot
	report["run_mode"] = ui.run_mode if sunny else "church"
	report["upgrades"] = ui.arena.upgrade_history.duplicate(true)
	var file := FileAccess.open(evidence.path_join("report.json"), FileAccess.WRITE); file.store_string(JSON.stringify(report,"  ")); file.close()
	if ui.flow != "result": print("FAILURE_CONTEXT ", JSON.stringify({"player":ui.arena.player_position,"muzzle":ui.arena._muzzle_world(),"facing":ui.arena.facing,"tracked_enemy":tracked_enemy,"enemies":ui.arena.enemies.map(func(e:Dictionary)->Dictionary: return {"id":e.id,"pos":e.pos,"hp":e.hp,"phase":e.get("attack_phase","")}),"ranged":ui.arena.ranged_runtime_profile}))
	print("EXPEDITION_PLAYTEST_RESULT ", JSON.stringify(report)); print("EVIDENCE ", ProjectSettings.globalize_path(evidence))
	ui.queue_free(); await process_frame
	quit(0 if report.flow == "result" else 1)

func bot(_delta: float) -> void:
	var arena: Node = ui.arena
	var target := {}
	var nearest := INF
	for enemy: Dictionary in arena.enemies:
		var distance: float = arena.player_position.distance_to(enemy.pos)
		if distance < nearest: nearest = distance; target = enemy
	var firearm: bool = arena._uses_firearm_runtime()
	var field_weapon := structural_bot and not firearm \
		and str(arena.blueprint.affordance.get("functional_output", "contact_only")) != "contact_only"
	var field_source_forward := 0.0
	if firearm:
		var tracked := {}
		for enemy: Dictionary in arena.enemies:
			if str(enemy.id) == tracked_enemy: tracked = enemy; break
		if tracked.is_empty() and not target.is_empty():
			tracked_enemy = str(target.id)
			kite_side = -1 if float(target.pos.x) > arena.player_position.x else 1
		elif not tracked.is_empty(): target = tracked
		if not target.is_empty(): nearest = arena.player_position.distance_to(target.pos)
	var desired: Vector2 = arena.seal_position
	var movement := Vector2.ZERO
	var warned := false
	var evade := Vector2.ZERO
	var dodge_now := false
	if not naive:
		# Respond to the already visible warning, BEFORE queuing a fresh melee
		# swing. This bot uses normal input and cannot cancel a locked animation.
		for enemy: Dictionary in arena.enemies:
			var runtime: Variant = enemy.get("attack_runtime")
			if runtime == null or runtime.phase not in ["telegraph", "commit", "active"]: continue
			var offset: Vector2 = arena.player_position - Vector2(enemy.pos)
			var direction: Vector2 = runtime.locked_direction
			var region: Dictionary = runtime.current_attack.get("hit_region", {})
			var danger: bool = runtime.current_hit_contains(enemy.pos, arena.player_position)
			if runtime.current_delivery() == "marked_impact":
				danger = arena.player_position.distance_to(runtime.locked_point) < float(region.get("radius_pixels", 80)) + 24
			elif runtime.current_delivery() in ["rush", "projectile"]:
				danger = offset.length() < 550 and offset.dot(direction) > -25 and absf(offset.cross(direction)) < float(region.get("width_pixels", 60)) * 0.5 + 32
			if danger:
				warned = true
				var side := direction.orthogonal()
				if side.y * (505 - arena.player_position.y) < 0: side = -side
				evade += side
				if runtime.phase in ["commit", "active"]: dodge_now = true
		for hazard: Dictionary in arena.enemy_attack_hazards:
			if arena.player_position.distance_to(hazard.pos) < 110:
				warned = true; dodge_now = true
				evade += Vector2(0, 1 if arena.player_position.y < 505 else -1)
	if not target.is_empty():
		var offset: Vector2 = Vector2(target.pos) - arena.player_position
		var melee_spacing := 62.0
		if structural_bot and not firearm and str(arena.blueprint.affordance.get("body_length", "")) == "long":
			# The old input bot stood at the same 62 px for a small hammer and a
			# long shaft, inside the latter's visible contact region. Stand back
			# using the displayed span; this changes only movement/attack inputs.
			melee_spacing = clampf(float(arena._weapon_fit().get("rendered_span_pixels", 62)) * 0.85 + 20, 62, 210)
		if field_weapon:
			# A field begins at its real working origin, which can sit well beyond the
			# player's body. Stand inside the compiled field band instead of at the
			# legacy 62 px contact distance (which may put a target behind a nozzle).
			field_source_forward = maxf(0.0, (arena._muzzle_world().x - arena.player_position.x) * arena.facing)
			var field_reach := float(arena.melee_runtime.profile.reach_pixels) if arena.melee_runtime.profile != null else 108.0
			melee_spacing = clampf(field_source_forward + field_reach * 0.48, 90.0, 260.0)
		if naive or arena.phase == "guardian" or (firearm and nearest < 110.0) or (not firearm and not field_weapon and nearest < maxf(155, melee_spacing + 35)) or (arena.contested and not field_weapon):
			var separation := 200.0 if firearm else melee_spacing
			desired = Vector2(target.pos) - Vector2(signf(offset.x) * separation, 0)
			if firearm: desired.x = float(target.pos.x) + kite_side * separation
			elif structural_bot and absf(arena._clamp_to_floor(desired).x - desired.x) > 10:
				# An input bot cannot back into space outside the arena. Walk around
				# the target to the free side; no teleports or collision overrides.
				desired.x = float(target.pos.x) + signf(offset.x) * separation
				if absf(offset.x) < 80: desired.y = float(target.pos.y) + (75 if float(target.pos.y) < 505 else -75)
		elif firearm or field_weapon: desired = arena.seal_position + Vector2(0, clampf(float(target.pos.y) - arena.seal_position.y, -28, 28))
		if firearm and (arena.phase == "guardian" or arena.contested):
			desired.y = float(target.pos.y)
		if firearm and absf(arena._clamp_to_floor(desired).x - desired.x) > 20:
			kite_side = -kite_side; desired.x = float(target.pos.x) + kite_side * 200.0
		if firearm and absf(offset.x) < 95 and offset.x * kite_side > 0:
			desired.y = float(target.pos.y) + (85 if float(target.pos.y) < 495 else -85)
		var field_target_in_band := not field_weapon or nearest >= maxf(40.0, field_source_forward * 0.82)
		if not warned and field_target_in_band and offset.length() < (900 if firearm else maxf(150, melee_spacing + 35)):
			if firearm: arena.set_touch_attack(fmod(clock, 0.32) < 0.18)
			else:
				var use_ability := structural_bot and str(arena.blueprint.affordance.get("activation_mode", "passive")) != "passive"
				if use_ability:
					if not arena.melee_runtime.busy() and clock > ability_until + 0.20:
						ability_until = clock + 1.25; last_attack = clock
					arena.set_touch_attack(clock < ability_until)
				else:
					arena.set_touch_attack(false)
					if not arena.melee_runtime.busy() and clock - last_attack > 0.20:
						arena.request_touch_attack(); last_attack = clock
		else: arena.set_touch_attack(false)
		if absf(offset.y) < 23 and absf(offset.x) > 1 and arena.facing != signf(offset.x): movement.x = signf(offset.x) * 0.2
	var to_goal: Vector2 = desired - arena.player_position
	if absf(to_goal.x) > 12: movement.x = signf(to_goal.x)
	if absf(to_goal.y) > 9: movement.y = signf(to_goal.y)
	if firearm and not naive:
		# Take short stationary firing windows. Walking uses the original standing
		# GunWalk clip; stopping allows the real crouch pose to hit low silhouettes.
		# This is ordinary stop/attack input, not an aim or collision override.
		var target_offset: Vector2 = Vector2(target.pos) - Vector2(arena.player_position) if not target.is_empty() else Vector2.ZERO
		var can_settle := not target.is_empty() and absf(target_offset.y) < 20 and nearest > 110 and nearest < 650
		# A support gun cannot backpedal in this authored body rig. Permit a short,
		# stationary close-range firing window once normal movement has turned the
		# body toward the target; otherwise the input-only route bot can orbit a
		# survivor forever without testing the actual gun runtime.
		var can_fire_close: bool = not target.is_empty() and absf(target_offset.y) < 45 \
			and nearest > 26 and nearest <= 110 and target_offset.x * arena.facing > 0
		if not warned and (can_settle or can_fire_close) and fmod(clock, 0.9) < 0.6:
			movement = Vector2.ZERO
			arena.set_touch_attack(fmod(clock, 0.32) < 0.18)
		else: arena.set_touch_attack(false)
		var turn_offset: Vector2 = target_offset
		if not target.is_empty() and turn_offset.x * arena.facing < 0:
			# Normal movement cannot backpedal while keeping aim. When kiting puts a
			# target behind the player, cross its lane deliberately so the authored
			# body turns around instead of waiting forever with the gun facing away.
			movement.x = signf(turn_offset.x)
			if absf(turn_offset.y) < 36: movement.y = 1.0 if arena.player_position.y < 505 else -1.0
			arena.set_touch_attack(false)
	if not naive:
		if warned:
			movement = evade.normalized()
			if dodge_now and clock - last_dodge > 0.55:
				arena.request_touch_dodge(); last_dodge = clock
		if arena.player_health < 58: arena.use_supply()
	arena.set_touch_vector(movement.limit_length(1))

func capture(label: String) -> void:
	if not render or captured.has(label): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(evidence.path_join(label + ".png")); captured[label] = true
