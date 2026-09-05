extends SceneTree
## Diagnostic-only enemy balance probe. It never changes production tuning.
## Static blueprint calculations, normal-input bot simulation and real-render
## sampling are explicitly separated in the emitted report.

const SUNNY_ARENA := preload("res://scripts/sunny_expedition/arena.gd")
const SUNNY_RULES := preload("res://scripts/sunny_expedition/rules.gd")
const EXPEDITION_LIBRARY := preload("res://scripts/art_vertical_slice_v1/expedition_library.gd")
const ENEMY_CATALOG := preload("res://scripts/enemy_attack/offline_enemy_blueprint_catalog.gd")
const ATTACK_RUNTIME := preload("res://scripts/enemy_attack/enemy_attack_runtime_driver.gd")


class ProbeArena:
	extends SUNNY_ARENA

	var damage_events: Array[Dictionary] = []
	var current_enemy_context: Dictionary = {}
	var recorded_hazard_hits: Dictionary = {}
	var enemy_source_registry: Dictionary = {}

	func _update_compiled_enemy_attack(enemy: Dictionary, runtime: Variant, delta: float) -> void:
		current_enemy_context = _source_identity(enemy)
		current_enemy_context.merge({
			"attack_key": str(runtime.current_attack.get("attack_key", "")),
			"delivery": str(runtime.current_delivery()),
			"effect_family": "base",
			"source_kind": "direct_active",
		}, true)
		super._update_compiled_enemy_attack(enemy, runtime, delta)
		current_enemy_context = {}

	func _spawn_enemy_attack_hazard(enemy: Dictionary, activation_event: Dictionary) -> void:
		var previous_count := enemy_attack_hazards.size()
		super._spawn_enemy_attack_hazard(enemy, activation_event)
		var identity := _source_identity(enemy)
		for index: int in range(previous_count, enemy_attack_hazards.size()):
			enemy_attack_hazards[index]["probe_source"] = identity.duplicate(true)

	func _take_player_damage(amount: float) -> float:
		var source := current_enemy_context.duplicate(true)
		for hazard: Dictionary in enemy_attack_hazards:
			var event_serial := int(hazard.get("damage_event_serial", 0))
			if not bool(hazard.get("hit_player", false)) and event_serial <= 0:
				continue
			var hazard_key := str([
				int(hazard.get("owner_id", -1)),
				str(hazard.get("attack_key", "")),
				str(hazard.get("mechanism_signature", "")),
				Vector2(hazard.get("pos", Vector2.ZERO)).round(),
				event_serial,
			])
			if recorded_hazard_hits.has(hazard_key):
				continue
			recorded_hazard_hits[hazard_key] = true
			source = _hazard_source(hazard)
			break
		var before := player_health
		var applied := super._take_player_damage(amount)
		if applied > 0.0:
			source["requested_damage"] = snappedf(amount, 0.001)
			source["applied_damage"] = snappedf(before - player_health, 0.001)
			source["chapter_clock"] = snappedf(chapter_clock, 0.001)
			damage_events.append(source)
		return applied

	func _hazard_source(hazard: Dictionary) -> Dictionary:
		var owner_id := int(hazard.get("owner_id", -1))
		var source := (hazard.get("probe_source", {}) as Dictionary).duplicate(true)
		if source.is_empty():
			source = (enemy_source_registry.get(str(owner_id), {}) as Dictionary).duplicate(true)
		if source.is_empty():
			source = {
				"owner_id": owner_id,
				"blueprint_id": "owner_no_longer_present",
				"display_name": "已离场敌人",
				"cohort_key": "owner_no_longer_present|unknown|none",
				"attacker_role": "unknown",
				"modifier_family": "none",
			}
		var effect_family := str(hazard.get("effect_family", ""))
		if effect_family.is_empty():
			effect_family = "base"
		source.merge({
			"attack_key": str(hazard.get("attack_key", "")),
			"delivery": str(hazard.get("delivery", "")),
			"effect_family": effect_family,
			"source_kind": "%s_hazard" % effect_family,
		}, true)
		return source

	func _source_identity(enemy: Dictionary) -> Dictionary:
		var role := "elite" if bool(enemy.get("expedition_elite", false)) else (
			"champion" if bool(enemy.get("expedition_champion", false)) else "ordinary"
		)
		var modifier_family := "none"
		var runtime: Variant = enemy.get("attack_runtime")
		if runtime != null:
			var families := runtime.compiled_modifiers.get("families", []) as Array
			if not families.is_empty():
				modifier_family = str(families[0])
		var blueprint_id := str(enemy.get("blueprint_id", "unknown"))
		var identity := {
			"owner_id": int(enemy.get("id", -1)),
			"blueprint_id": blueprint_id,
			"display_name": str(enemy.get("display_name", enemy.get("type", "敌人"))),
			"attacker_role": role,
			"modifier_family": modifier_family,
			"cohort_key": "%s|%s|%s" % [blueprint_id, role, modifier_family],
		}
		enemy_source_registry[str(identity.owner_id)] = identity.duplicate(true)
		return identity


var output_directory := ""
var render_mode := false
var maximum_seconds := 430.0
var seed_value := 14
var seed_values: Array[int] = [14]
var failures: Array[String] = []


func _initialize() -> void:
	for name: String in ["ANTHROPIC_API_KEY", "FAL_KEY", "FAL_API_KEY", "OPENAI_API_KEY"]:
		OS.unset_environment(name)
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--render":
			render_mode = true
		elif arg.begins_with("--output="):
			output_directory = arg.trim_prefix("--output=")
		elif arg.begins_with("--seconds="):
			maximum_seconds = clampf(float(arg.trim_prefix("--seconds=")), 5.0, 900.0)
		elif arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))
			seed_values = [seed_value]
		elif arg.begins_with("--seeds="):
			seed_values.clear()
			for raw_seed: String in arg.trim_prefix("--seeds=").split(","):
				if raw_seed.strip_edges().is_valid_int():
					var parsed_seed := int(raw_seed.strip_edges())
					if parsed_seed not in seed_values:
						seed_values.append(parsed_seed)
			if seed_values.is_empty():
				seed_values = [14]
			seed_value = seed_values[0]
	if output_directory.is_empty():
		output_directory = ProjectSettings.globalize_path(
			"res://.tools/enemy-balance-probe/%d-%d" % [int(Time.get_unix_time_from_system()), OS.get_process_id()]
		)
	DirAccess.make_dir_recursive_absolute(output_directory)
	call_deferred("_run")


func _run() -> void:
	var static_report := _static_blueprint_report()
	var entries := _representative_entries()
	if not bool(entries.get("ok", false)):
		failures.append(str(entries.get("error", "REPRESENTATIVE_WEAPONS_MISSING")))
	var run_reports: Array[Dictionary] = []
	if failures.is_empty():
		for current_seed: int in seed_values:
			for family: String in ["firearm", "rigid_long", "flexible"]:
				run_reports.append(await _run_weapon(family, entries[family], current_seed))
	var report := {
		"schema": "forge-enemy-balance-measurement-v2",
		"generated_at_unix": Time.get_unix_time_from_system(),
		"seed": seed_value,
		"seeds": seed_values,
		"layers": {
			"static_calculation": true,
			"normal_input_bot": true,
			"real_godot_render": render_mode and DisplayServer.get_name() != "headless",
			"desktop_manual_input": false,
		},
		"online_calls": 0,
		"display_server": DisplayServer.get_name(),
		"video_adapter": RenderingServer.get_video_adapter_name() if render_mode else "not_sampled_in_headless_layer",
		"personal_weapon_library_read": false,
		"personal_weapon_library_written": false,
		"production_tuning_modified": false,
		"static": static_report,
		"runs": run_reports,
		"cross_seed_summary": _cross_seed_summary(run_reports),
		"failures": failures,
		"limitations": [
			"机器人只代表一种确定性输入策略，不代表玩家胜率。",
			"step_ms只包围关卡更新；render_frame_wall_ms是实际渲染帧墙钟时间，不是纯GPU profiler。",
			"预警命中率按进入active的攻击与实际伤害事件计数；持续危险区的每次真实伤害脉冲独立计数。",
			"敌人寿命来自进入和离开实时敌人数组的时间；限时结束时仍存活的样本标为survivor，不混进击杀寿命。",
		],
	}
	var report_path := output_directory.path_join("report.json")
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("ENEMY_BALANCE_PROBE_V1 ", JSON.stringify({
		"ok": failures.is_empty(),
		"render": render_mode,
		"runs": run_reports.size(),
		"seeds": seed_values,
		"report": report_path,
		"online_calls": 0,
	}))
	quit(0 if failures.is_empty() else 2)


func _static_blueprint_report() -> Dictionary:
	var catalog := ENEMY_CATALOG.load_validated(SUNNY_RULES.SUNNY_CATALOG_PATH)
	if not bool(catalog.get("ok", false)):
		failures.append(str(catalog.get("error", "ENEMY_CATALOG_INVALID")))
		return {}
	var enemies: Array[Dictionary] = []
	for blueprint_id: String in SUNNY_RULES.ROSTER:
		var profile: Dictionary = SUNNY_RULES.make_profile(0, SUNNY_RULES.ROSTER.find(blueprint_id) - seed_value, seed_value, false)
		if str(profile.get("catalog_id", "")) != blueprint_id:
			profile = (catalog.profiles_by_id.get(blueprint_id, {}) as Dictionary).duplicate(true)
			profile["damage_multiplier"] = 0.92
			profile["attack_tempo_multiplier"] = 1.0
		var runtime := ATTACK_RUNTIME.new()
		var configured: Dictionary = runtime.configure(
			profile.get("attack_declarations", []) as Array,
			float(profile.get("attack_tempo_multiplier", 1.0)),
			profile.get("enemy_modifier_declarations", []) as Array
		)
		if not bool(configured.get("ok", false)):
			failures.append("STATIC_COMPILE_FAILED:%s" % blueprint_id)
			continue
		var attacks: Array[Dictionary] = []
		for attack: Dictionary in runtime.compiled_attacks:
			var axes := attack.get("axes", {}) as Dictionary
			var timeline := attack.get("timeline", {}) as Dictionary
			var delivery := str(axes.get("delivery", "contact"))
			var damage := float({"contact": 6.0, "rush": 12.0, "projectile": 8.0, "marked_impact": 10.0}.get(delivery, 6.0)) * float(profile.get("damage_multiplier", 1.0))
			var danger_zone := attack.get("danger_zone", {}) as Dictionary
			var hazard_mode := str(danger_zone.get("mode", "instant"))
			var hazard_contacts := 1
			if hazard_mode == "lingering":
				var repeat_seconds := maxf(0.001, float(danger_zone.get("repeat_hit_cooldown_seconds", 0.32)))
				hazard_contacts = maxi(1, ceili(float(danger_zone.get("duration_seconds", 0.0)) / repeat_seconds))
			elif hazard_mode == "pulsing":
				var pulse_seconds := maxf(0.001, float(danger_zone.get("pulse_interval_seconds", 0.60)))
				hazard_contacts = maxi(1, ceili(float(danger_zone.get("duration_seconds", 0.0)) / pulse_seconds))
			var contact_damage := damage * float(danger_zone.get("damage_multiplier", 1.0))
			var warning := float(timeline.get("telegraph_seconds", 0.0)) + float(timeline.get("commit_seconds", 0.0))
			var cycle := warning + float(timeline.get("active_seconds", 0.0)) + float(timeline.get("recovery_seconds", 0.0)) + runtime.post_attack_cooldown_seconds
			attacks.append({
				"attack_key": str(attack.get("attack_key", "")),
				"slot_label_zh": str(attack.get("slot_label_zh", "")),
				"delivery": delivery,
				"warning_seconds": snappedf(warning, 0.001),
				"active_seconds": snappedf(float(timeline.get("active_seconds", 0.0)), 0.001),
				"recovery_seconds": snappedf(float(timeline.get("recovery_seconds", 0.0)), 0.001),
				"nominal_damage": snappedf(contact_damage, 0.001),
				"hazard_mode": hazard_mode,
				"maximum_hazard_contacts_if_player_remains": hazard_contacts,
				"maximum_hazard_damage_if_player_remains": snappedf(contact_damage * float(hazard_contacts), 0.001),
				"minimum_cycle_seconds": snappedf(cycle, 0.001),
				"nominal_threat_per_second": snappedf(contact_damage / maxf(0.001, cycle), 0.001),
			})
		enemies.append({
			"blueprint_id": blueprint_id,
			"display_name": str(SUNNY_RULES.DISPLAY_NAMES.get(blueprint_id, blueprint_id)),
			"normal_health": snappedf(float(profile.get("max_health", 0.0)), 0.01),
			"attacks": attacks,
		})
	return {
		"source": SUNNY_RULES.SUNNY_CATALOG_PATH,
		"calculation_only": true,
		"enemy_count": enemies.size(),
		"enemies": enemies,
		"route": {
			"world_length_pixels": SUNNY_RULES.ROUTE_WORLD_LENGTH,
			"roadposts": SUNNY_RULES.SEAL_COUNT,
			"roadpost_hold_seconds_each": SUNNY_RULES.SEAL_SECONDS,
			"minimum_uncontested_hold_seconds": SUNNY_RULES.SEAL_COUNT * SUNNY_RULES.SEAL_SECONDS,
			"initial_spawn_count": SUNNY_RULES.initial_spawns(0),
			"initial_spawn_stagger_seconds": 0.55,
			"reinforcement_interval_seconds": SUNNY_RULES.spawn_interval(0),
			"maximum_active_enemies": SUNNY_RULES.max_active_enemies(0),
			"maximum_simultaneous_attackers": SUNNY_RULES.max_active_attackers(0),
		},
	}


func _representative_entries() -> Dictionary:
	var catalog := EXPEDITION_LIBRARY.new()
	catalog.style_id = "sunny_v1"
	var shelf: Array[Dictionary] = catalog.load_all(false)
	var selected := {"ok": true}
	for entry: Dictionary in shelf:
		var blueprint := entry.get("blueprint") as WeaponBlueprint
		if blueprint == null:
			continue
		var axes: Dictionary = blueprint.affordance
		var tags: Array = axes.get("structure_tags", []) as Array
		if not selected.has("firearm") and str(axes.get("weapon_domain", "")) == "handheld_firearm":
			selected["firearm"] = entry
		elif not selected.has("rigid_long") and str(axes.get("body_length", "")) == "long" \
			and str(axes.get("rigidity", axes.get("flexibility", "rigid"))) in ["rigid", "hard"] \
			and (bool(axes.get("has_point", false)) or "has_point" in tags or str(axes.get("contact_surface", "")) == "point"):
			selected["rigid_long"] = entry
		elif not selected.has("flexible") and (
			str(axes.get("flex_topology", "none")) in ["flexible_line", "linked_segments"]
			or str(axes.get("tether_segment", "none")) != "none"
			or str(axes.get("body_flexibility", "rigid")) in ["flexible", "segmented"]
		):
			selected["flexible"] = entry
	for family: String in ["firearm", "rigid_long", "flexible"]:
		if not selected.has(family):
			return {"ok": false, "error": "PACKAGED_REPRESENTATIVE_MISSING:%s" % family}
	return selected


func _run_weapon(family: String, entry: Dictionary, current_seed: int) -> Dictionary:
	# Every row must be reproducible on its own. Without this reset, firearm
	# spread and other global random calls inherit the previous weapon run, so
	# moving a seed earlier or later in the matrix changes its supposed baseline.
	seed(current_seed)
	var arena := ProbeArena.new()
	root.add_child(arena)
	await process_frame
	arena.set_process(false)
	arena.audio_enabled = false
	arena.upgrade_requested.connect(func(_choices: Array) -> void:
		arena.apply_pending_upgrade(0)
	)
	var begun: Dictionary = arena.begin_chapter(0, current_seed, entry, 100.0, 2)
	if not bool(begun.get("ok", false)):
		failures.append("RUN_BEGIN_FAILED:%s:%s" % [family, str(begun.get("error", ""))])
		arena.queue_free()
		await process_frame
		return {"family": family, "ok": false, "error": begun.get("error", "")}

	var clock := 0.0
	var state_by_enemy: Dictionary = {}
	var spawn_ids: Dictionary = {}
	var aggregates: Dictionary = {}
	var step_ms: Array[float] = []
	var render_frame_wall_ms: Array[float] = []
	var maximum_concurrent := 0
	var maximum_tells := 0
	var screenshot_count := 0
	var last_dodge := -10.0
	var last_defeated_count := 0
	var last_defeat_clock := 0.0
	var last_route_progress := 0.0
	var last_route_progress_clock := 0.0
	while clock < maximum_seconds and arena.active and arena.player_health > 0.0:
		var delta := 1.0 / 30.0
		if render_mode:
			var frame_start := Time.get_ticks_usec()
			await process_frame
			render_frame_wall_ms.append((Time.get_ticks_usec() - frame_start) / 1000.0)
			delta = clampf(root.get_process_delta_time(), 1.0 / 120.0, 0.05)
		_bot_input(arena, clock, family, last_dodge)
		if arena.dodge_timer > 0.0:
			last_dodge = clock
		var tick_start := Time.get_ticks_usec()
		arena._process(delta)
		step_ms.append((Time.get_ticks_usec() - tick_start) / 1000.0)
		clock += delta
		var defeated_count := int(arena.metrics.get("defeated", 0))
		if defeated_count > last_defeated_count:
			last_defeated_count = defeated_count
			last_defeat_clock = clock
		var route_progress := float(arena.seal_index) + float(arena.seal_progress) / maxf(0.001, SUNNY_RULES.SEAL_SECONDS)
		if route_progress > last_route_progress + 0.001:
			last_route_progress = route_progress
			last_route_progress_clock = clock
		_measure_enemy_states(arena, state_by_enemy, spawn_ids, aggregates, clock, delta)
		maximum_concurrent = maxi(maximum_concurrent, arena.enemies.size())
		maximum_tells = maxi(maximum_tells, arena.spawn_tells.size())
		if render_mode and screenshot_count < 2 and (clock > 1.0 + screenshot_count * 8.0):
			await RenderingServer.frame_post_draw
			var shot_path := output_directory.path_join("seed-%d-%s-%d.png" % [current_seed, family, screenshot_count + 1])
			if root.get_texture().get_image().save_png(shot_path) == OK:
				screenshot_count += 1

	var damage_by_source := _damage_source_summary(arena.damage_events, "blueprint_id")
	var damage_by_cohort := _damage_source_summary(arena.damage_events, "cohort_key")
	var damage_by_effect := _damage_source_summary(arena.damage_events, "effect_family")
	var damage_by_modifier := _damage_source_summary(arena.damage_events, "modifier_family")
	for key: String in aggregates:
		var row: Dictionary = aggregates[key]
		row["survivors"] = maxi(0, int(row.spawned) - int(row.defeated))
		row["defeat_rate"] = snappedf(float(row.defeated) / maxf(1.0, float(row.spawned)), 0.001)
		row["defeated_lifetime_seconds"] = _summary(row.lifetime_samples)
		row.erase("lifetime_samples")
		row["hit_events"] = int(damage_by_cohort.get(key, {}).get("hit_events", 0))
		row["damage_taken"] = snappedf(float(damage_by_cohort.get(key, {}).get("damage", 0.0)), 0.001)
		row["hit_rate_per_active"] = snappedf(float(row.hit_events) / maxf(1.0, float(row.active_entries)), 0.001)
		row["damage_per_world_second"] = snappedf(float(row.damage_taken) / maxf(0.001, clock), 0.001)
		row["damage_per_enemy_alive_second"] = snappedf(float(row.damage_taken) / maxf(0.001, float(row.alive_seconds)), 0.001)
		row["warning_seconds_observed"] = _summary(row.warning_samples)
		row.erase("warning_samples")
		var warning_by_delivery := {}
		for delivery: String in (row.warning_samples_by_delivery as Dictionary):
			warning_by_delivery[delivery] = _summary((row.warning_samples_by_delivery as Dictionary)[delivery] as Array)
		row["warning_seconds_by_delivery"] = warning_by_delivery
		row.erase("warning_samples_by_delivery")
	var blueprint := entry.get("blueprint") as WeaponBlueprint
	var result := {
		"ok": true,
		"seed": current_seed,
		"family": family,
		"weapon": blueprint.display_name,
		"mechanism": _weapon_mechanism_label(blueprint.affordance),
		"simulated_seconds": snappedf(clock, 0.1),
		"completed": arena.phase == "complete",
		"ending_phase": arena.phase,
		"roadpost_index": arena.seal_index,
		"roadpost_progress": snappedf(arena.seal_progress, 0.1),
		"player_health": snappedf(arena.player_health, 0.1),
		"normal_input_only": true,
		"health_or_enemy_overrides": false,
		"spawned_total": spawn_ids.size(),
		"maximum_concurrent_enemies": maximum_concurrent,
		"maximum_pending_spawn_tells": maximum_tells,
		"seconds_since_last_defeat": snappedf(clock - last_defeat_clock, 0.1),
		"seconds_since_route_progress": snappedf(clock - last_route_progress_clock, 0.1),
		"end_state": {
			"player_position": arena.player_position,
			"facing": arena.facing,
			"seal_position": arena.seal_position,
			"contested": arena.contested,
			"enemy_count": arena.enemies.size(),
			"hazard_count": arena.enemy_attack_hazards.size(),
			"enemies": arena.enemies.map(func(enemy: Dictionary) -> Dictionary: return _enemy_end_snapshot(enemy)),
		},
		"player_damage_events": arena.damage_events,
		"damage_sources": damage_by_source,
		"damage_sources_by_cohort": damage_by_cohort,
		"damage_by_effect_family": damage_by_effect,
		"damage_by_attacker_modifier": damage_by_modifier,
		"enemy_observations": aggregates.values(),
		"step_ms": _summary(step_ms),
		"real_godot_render": render_mode and DisplayServer.get_name() != "headless",
		"render_frame_wall_ms": _summary(render_frame_wall_ms),
		"rendered_screenshots": screenshot_count,
		"not_pure_gpu_profiler": true,
		"metrics": arena.metrics.duplicate(true),
	}
	arena.queue_free()
	await process_frame
	return result


func _enemy_end_snapshot(enemy: Dictionary) -> Dictionary:
	var runtime: Variant = enemy.get("attack_runtime")
	return {
		"blueprint_id": str(enemy.get("blueprint_id", "unknown")),
		"role": "elite" if bool(enemy.get("expedition_elite", false)) else ("champion" if bool(enemy.get("expedition_champion", false)) else "ordinary"),
		"position": Vector2(enemy.get("pos", Vector2.ZERO)),
		"health": snappedf(float(enemy.get("hp", 0.0)), 0.1),
		"phase": str(runtime.phase) if runtime != null else "none",
		"delivery": str(runtime.current_delivery()) if runtime != null else "none",
	}


func _bot_input(arena: ProbeArena, clock: float, family: String, last_dodge: float) -> void:
	var nearest := {}
	var nearest_distance := INF
	for enemy: Dictionary in arena.enemies:
		var distance := arena.player_position.distance_to(Vector2(enemy.pos))
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = enemy
	var movement := Vector2.ZERO
	var desired := arena.seal_position
	var evade := Vector2.ZERO
	var danger := false
	for enemy: Dictionary in arena.enemies:
		var runtime: Variant = enemy.get("attack_runtime")
		if runtime == null or runtime.phase not in ["telegraph", "commit", "active"]:
			continue
		if runtime.current_hit_contains(Vector2(enemy.pos), arena.player_position):
			danger = true
			evade += Vector2(runtime.locked_direction).orthogonal()
	for hazard: Dictionary in arena.enemy_attack_hazards:
		if arena.player_position.distance_to(Vector2(hazard.get("pos", Vector2.ZERO))) < 105.0:
			danger = true
			evade += Vector2(0, -1.0 if arena.player_position.y > 490.0 else 1.0)

	if not nearest.is_empty():
		var target := Vector2(nearest.pos)
		var offset := target - arena.player_position
		var firearm := family == "firearm"
		var spacing := 220.0 if firearm else (128.0 if family == "rigid_long" else 105.0)
		if not firearm:
			# A beat-em-up melee input must deliberately enter the target's depth
			# lane. Approaching on the radial line can stop diagonally outside the
			# visible contact strip even though the bodies look close on screen.
			desired = Vector2(target.x - signf(offset.x) * spacing, target.y)
		elif nearest_distance < spacing - 22.0:
			# Keep firearm spacing on the horizontal combat lane. A radial retreat
			# can point outside a corner of the world while leaving the gun more than
			# one lane above/below its target, causing a false infinite stalemate.
			# If that side is outside the playable floor, cross past the enemy to the
			# other side; otherwise a target inside the muzzle can never be hit.
			var separation_side := -signf(offset.x) if absf(offset.x) > 0.1 else -arena.facing
			desired = Vector2(target.x + separation_side * spacing, target.y)
			var clamped_retreat: Vector2 = arena._clamp_to_floor(desired)
			if absf(clamped_retreat.x - desired.x) > 1.0:
				desired.x = target.x - separation_side * spacing
		elif nearest_distance > spacing + 70.0 and (arena.contested or arena.phase == "guardian"):
			var approach_side := -signf(offset.x) if absf(offset.x) > 0.1 else -arena.facing
			desired = Vector2(target.x + approach_side * spacing, target.y)
			var clamped_approach: Vector2 = arena._clamp_to_floor(desired)
			if absf(clamped_approach.x - desired.x) > 1.0:
				desired.x = target.x - approach_side * spacing
		if absf(offset.x) > 2.0 and offset.x * arena.facing < 0.0:
			movement.x = signf(offset.x)
		var aligned := absf(offset.y) < (34.0 if firearm else 58.0)
		if not danger and aligned and nearest_distance < (760.0 if firearm else spacing + 75.0):
			if firearm:
				arena.set_touch_attack(fmod(clock, 0.36) < 0.20)
				if nearest_distance > 95.0:
					desired.y = target.y
			else:
				# Ordinary short press/release cadence. Holding the button would test
				# a charged ability instead of the three-hit base route.
				arena.set_touch_attack(fmod(clock, 0.48) < 0.08)
		else:
			arena.set_touch_attack(false)
	else:
		arena.set_touch_attack(false)
	var to_goal := desired - arena.player_position
	if absf(to_goal.x) > 12.0:
		movement.x = signf(to_goal.x)
	if absf(to_goal.y) > 10.0:
		movement.y = signf(to_goal.y)
	if danger:
		movement = evade.normalized() if evade.length_squared() > 0.01 else Vector2(0, 1)
		if clock - last_dodge > 0.65:
			arena.request_touch_dodge()
	if arena.player_health < 48.0:
		arena.use_supply()
	arena.set_touch_vector(movement.limit_length(1.0))


func _measure_enemy_states(arena: ProbeArena, states: Dictionary, spawn_ids: Dictionary, aggregates: Dictionary, clock: float, delta: float) -> void:
	var living_ids := {}
	for enemy: Dictionary in arena.enemies:
		var enemy_id := int(enemy.get("id", -1))
		var id_key := str(enemy_id)
		living_ids[id_key] = true
		var identity := arena._source_identity(enemy)
		var blueprint_id := str(identity.get("blueprint_id", "unknown"))
		var cohort_key := str(identity.get("cohort_key", "%s|ordinary|none" % blueprint_id))
		if not spawn_ids.has(id_key):
			spawn_ids[id_key] = cohort_key
		if not aggregates.has(cohort_key):
			aggregates[cohort_key] = {
				"cohort_key": cohort_key,
				"blueprint_id": blueprint_id,
				"display_name": str(enemy.get("display_name", enemy.get("type", blueprint_id))),
				"attacker_role": str(identity.get("attacker_role", "ordinary")),
				"modifier_family": str(identity.get("modifier_family", "none")),
				"spawned": 0,
				"defeated": 0,
				"alive_seconds": 0.0,
				"attack_attempts": 0,
				"attack_attempts_by_delivery": {},
				"active_entries": 0,
				"active_entries_by_delivery": {},
				"active_danger_seconds": 0.0,
				"warning_samples": [],
				"warning_samples_by_delivery": {},
				"lifetime_samples": [],
			}
		var row: Dictionary = aggregates[cohort_key]
		if not states.has(id_key):
			row.spawned = int(row.spawned) + 1
			states[id_key] = {
				"phase": "idle",
				"delivery": "",
				"warning_started": -1.0,
				"spawned_at": clock,
				"cohort_key": cohort_key,
			}
		row.alive_seconds = float(row.alive_seconds) + delta
		var runtime: Variant = enemy.get("attack_runtime")
		var phase := str(runtime.phase) if runtime != null else str(enemy.get("attack_phase", "idle"))
		var previous: Dictionary = states[id_key]
		if phase == "telegraph" and str(previous.phase) != "telegraph":
			var attempt_delivery := str(runtime.current_delivery()) if runtime != null else "unknown"
			row.attack_attempts = int(row.attack_attempts) + 1
			var attempts_by_delivery := row.attack_attempts_by_delivery as Dictionary
			attempts_by_delivery[attempt_delivery] = int(attempts_by_delivery.get(attempt_delivery, 0)) + 1
			row.attack_attempts_by_delivery = attempts_by_delivery
			previous.delivery = attempt_delivery
			previous.warning_started = clock
		if phase == "active":
			row.active_danger_seconds = float(row.active_danger_seconds) + delta
			if str(previous.phase) != "active":
				var active_delivery := str(runtime.current_delivery()) if runtime != null else str(previous.get("delivery", "unknown"))
				row.active_entries = int(row.active_entries) + 1
				var entries_by_delivery := row.active_entries_by_delivery as Dictionary
				entries_by_delivery[active_delivery] = int(entries_by_delivery.get(active_delivery, 0)) + 1
				row.active_entries_by_delivery = entries_by_delivery
				if float(previous.warning_started) >= 0.0:
					var warning_seconds := clock - float(previous.warning_started)
					(row.warning_samples as Array).append(warning_seconds)
					var samples_by_delivery := row.warning_samples_by_delivery as Dictionary
					var delivery_samples := samples_by_delivery.get(active_delivery, []) as Array
					delivery_samples.append(warning_seconds)
					samples_by_delivery[active_delivery] = delivery_samples
					row.warning_samples_by_delivery = samples_by_delivery
		previous.phase = phase
		states[id_key] = previous
	for id_key: String in states.keys():
		if not living_ids.has(id_key):
			var departed: Dictionary = states[id_key]
			var cohort_key := str(departed.get("cohort_key", ""))
			if aggregates.has(cohort_key):
				var row: Dictionary = aggregates[cohort_key]
				row.defeated = int(row.defeated) + 1
				(row.lifetime_samples as Array).append(maxf(0.0, clock - float(departed.get("spawned_at", clock))))
			states.erase(id_key)


func _damage_source_summary(events: Array[Dictionary], grouping_field: String) -> Dictionary:
	var grouped := {}
	for event: Dictionary in events:
		var group_key := str(event.get(grouping_field, "unknown"))
		if group_key.is_empty():
			group_key = "unknown"
		if not grouped.has(group_key):
			grouped[group_key] = {"hit_events": 0, "damage": 0.0, "by_attack": {}}
		var row: Dictionary = grouped[group_key]
		row.hit_events = int(row.hit_events) + 1
		row.damage = float(row.damage) + float(event.get("applied_damage", 0.0))
		var attack_key := "%s/%s" % [str(event.get("delivery", "unknown")), str(event.get("attack_key", "unknown"))]
		var attacks: Dictionary = row.by_attack
		var attack_row := attacks.get(attack_key, {"hit_events": 0, "damage": 0.0}) as Dictionary
		attack_row.hit_events = int(attack_row.hit_events) + 1
		attack_row.damage = snappedf(float(attack_row.damage) + float(event.get("applied_damage", 0.0)), 0.001)
		attacks[attack_key] = attack_row
		row.by_attack = attacks
		row.damage = snappedf(float(row.damage), 0.001)
		grouped[group_key] = row
	return grouped


func _cross_seed_summary(runs: Array[Dictionary]) -> Dictionary:
	var by_family := {}
	for family: String in ["firearm", "rigid_long", "flexible"]:
		by_family[family] = {
			"runs": 0,
			"completed": 0,
			"simulated_seconds": [],
			"completion_seconds": [],
			"damage_taken": [],
			"defeated": [],
			"route_progress": [],
			"damage_by_effect_family": {},
			"damage_by_attacker_modifier": {},
		}
	for run: Dictionary in runs:
		var family := str(run.get("family", "unknown"))
		if not by_family.has(family):
			continue
		var row: Dictionary = by_family[family]
		row.runs = int(row.runs) + 1
		var duration := float(run.get("simulated_seconds", 0.0))
		(row.simulated_seconds as Array).append(duration)
		if bool(run.get("completed", false)):
			row.completed = int(row.completed) + 1
			(row.completion_seconds as Array).append(duration)
		var metrics := run.get("metrics", {}) as Dictionary
		(row.damage_taken as Array).append(float(metrics.get("damage_taken", 0.0)))
		(row.defeated as Array).append(float(metrics.get("defeated", 0)))
		var route_progress := float(run.get("roadpost_index", 0)) + float(run.get("roadpost_progress", 0.0)) / maxf(0.001, SUNNY_RULES.SEAL_SECONDS)
		(row.route_progress as Array).append(route_progress)
		_merge_grouped_damage(row.damage_by_effect_family, run.get("damage_by_effect_family", {}) as Dictionary)
		_merge_grouped_damage(row.damage_by_attacker_modifier, run.get("damage_by_attacker_modifier", {}) as Dictionary)
	for family: String in by_family:
		var row: Dictionary = by_family[family]
		row["completion_rate"] = snappedf(float(row.completed) / maxf(1.0, float(row.runs)), 0.001)
		for field: String in ["simulated_seconds", "completion_seconds", "damage_taken", "defeated", "route_progress"]:
			row[field] = _summary(row[field] as Array)
	return {
		"seed_count": seed_values.size(),
		"weapon_family_count": by_family.size(),
		"by_weapon_family": by_family,
	}


func _merge_grouped_damage(target: Dictionary, source: Dictionary) -> void:
	for group_key: String in source:
		var source_row := source[group_key] as Dictionary
		var target_row := target.get(group_key, {"hit_events": 0, "damage": 0.0}) as Dictionary
		target_row.hit_events = int(target_row.hit_events) + int(source_row.get("hit_events", 0))
		target_row.damage = snappedf(float(target_row.damage) + float(source_row.get("damage", 0.0)), 0.001)
		target[group_key] = target_row


func _summary(values: Array) -> Dictionary:
	if values.is_empty():
		return {"count": 0, "minimum": 0.0, "p50": 0.0, "p95": 0.0, "maximum": 0.0, "mean": 0.0}
	var sorted: Array[float] = []
	var total := 0.0
	for value: Variant in values:
		var number := float(value)
		sorted.append(number)
		total += number
	sorted.sort()
	return {
		"count": sorted.size(),
		"minimum": snappedf(sorted[0], 0.001),
		"p50": snappedf(sorted[sorted.size() / 2], 0.001),
		"p95": snappedf(sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))], 0.001),
		"maximum": snappedf(sorted[-1], 0.001),
		"mean": snappedf(total / sorted.size(), 0.001),
	}


func _weapon_mechanism_label(axes: Dictionary) -> String:
	if str(axes.get("weapon_domain", "")) == "handheld_firearm":
		return "firearm"
	if str(axes.get("flex_topology", "none")) in ["flexible_line", "linked_segments"] or str(axes.get("tether_segment", "none")) != "none":
		return "weighted_flexible"
	if str(axes.get("body_length", "")) == "long":
		return "rigid_long"
	return "other"
