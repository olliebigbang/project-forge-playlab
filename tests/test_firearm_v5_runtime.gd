extends SceneTree

const ARENA := preload("res://scripts/systems/gameplay_arena.gd")
const BLUEPRINT := preload("res://scripts/data/weapon_blueprint.gd")
const AXES := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	_run("A pellet cluster spends one round and covers its declared cone", _test_pellet_cluster)
	_run("Pellet damage and minimum falloff are consumed by real projectile damage", _test_pellet_damage_and_falloff)
	_run("Bolt pump and cylinder actions lock firing for cadence plus overhead", _test_cycle_actions_and_cadence)
	_run("The last mechanical round cycles before reload starts", _test_cycle_then_reload_sequence)
	_run("Magazine and belt-box feeds replace the whole feed package", _test_package_reload_modes)
	_run("Per-round reload gains rounds and can be interrupted to attack", _test_interruptible_per_round_reload)
	_run("Cylinder reload advances in non-interruptible declared batches", _test_cylinder_batch_reload)
	_run("Sustained fire adds capped climb and recovers only after release window", _test_sustained_climb)
	_run("V4 profiles keep their single-projectile and whole-magazine defaults", _test_v4_defaults)
	_run("Runtime behavior contains no firearm model or family branch", _test_identity_free_runtime)
	print("FIREARM V5 RUNTIME RESULT: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _run(label: String, callable: Callable) -> void:
	var result: Variant = callable.call()
	if result is bool and bool(result):
		passed += 1
		print("PASS | %s" % label)
	else:
		failed += 1
		printerr("FAIL | %s | %s" % [label, str(result)])


func _test_pellet_cluster() -> Variant:
	var arena := _arena({
		"pellet_count": 5,
		"pellet_spread_degrees": 20.0,
		"pellet_damage_multiplier": 0.4,
		"damage_falloff_min_multiplier": 0.25,
		"muzzle_flash_seconds": 0.09,
		"muzzle_flash_scale": 1.8,
	})
	var ammo_before := arena.ammo_in_magazine
	arena._update_firearm_attack(true, true)
	if arena.projectiles.size() != 5 or arena.ammo_in_magazine != ammo_before - 1:
		return _dispose_failure(arena, "cluster=%d ammo=%d/%d" % [arena.projectiles.size(), arena.ammo_in_magazine, ammo_before])
	if int(arena.metrics.get("shots_fired", 0)) != 1:
		return _dispose_failure(arena, "pellets were counted as separate trigger shots")
	var expected_angles: Array[float] = [-10.0, -5.0, 0.0, 5.0, 10.0]
	for pellet_index: int in range(expected_angles.size()):
		var projectile := arena.projectiles[pellet_index] as Dictionary
		if not is_equal_approx(float(projectile.get("pellet_angle_degrees", 99.0)), expected_angles[pellet_index]):
			return _dispose_failure(arena, "non-deterministic pellet angle: %s" % str(projectile))
		var velocity_angle := rad_to_deg(Vector2(projectile.get("vel", Vector2.ZERO)).angle())
		if not is_equal_approx(velocity_angle, expected_angles[pellet_index]):
			return _dispose_failure(arena, "velocity did not cover declared cone: %s" % str(velocity_angle))
	if not is_equal_approx(arena.muzzle_flash_timer, 0.09) or not is_equal_approx(arena.muzzle_flash_scale, 1.8):
		return _dispose_failure(arena, "muzzle flash fields did not reach runtime state")
	arena.free()
	return true


func _test_pellet_damage_and_falloff() -> Variant:
	var arena := _arena({
		"projectile_damage": 20.0,
		"pellet_count": 3,
		"pellet_spread_degrees": 12.0,
		"pellet_damage_multiplier": 0.4,
		"damage_falloff_start_pixels": 100.0,
		"damage_falloff_end_pixels": 200.0,
		"damage_falloff_min_multiplier": 0.25,
	})
	arena._update_firearm_attack(true, true)
	var projectile := arena.projectiles[1] as Dictionary
	var target := {"id": 1, "type": "target", "pos": Vector2(300, 420), "hp": 100.0, "facing": -1.0}
	var near_damage := arena._projectile_damage_against(projectile, target)
	projectile["distance_travelled"] = 200.0
	var far_damage := arena._projectile_damage_against(projectile, target)
	var ok := is_equal_approx(near_damage, 8.0) and is_equal_approx(far_damage, 2.0)
	arena.free()
	return true if ok else "near=%s far=%s" % [near_damage, far_damage]


func _test_cycle_actions_and_cadence() -> Variant:
	for action_code: int in [1, 2, 3]:
		var arena := _arena({
			"cycle_action_code": action_code,
			"cycle_required": true,
			"cycle_overhead_seconds": 0.42,
			"shot_interval_seconds": 0.18,
		})
		arena._update_firearm_attack(true, true)
		if not is_equal_approx(arena.manual_cycle_timer, 0.60) or arena.active_cycle_action_code != action_code:
			return _dispose_failure(arena, "action %d did not start 0.60 second lock" % action_code)
		arena.shot_cooldown = 0.0
		arena._update_firearm_attack(true, true)
		if arena.projectiles.size() != 1:
			return _dispose_failure(arena, "action %d allowed a shot during cycle" % action_code)
		arena._update_firearm_timers(0.59)
		arena._update_firearm_attack(true, true)
		if arena.projectiles.size() != 1:
			return _dispose_failure(arena, "action %d lock ended early" % action_code)
		arena._update_firearm_timers(0.02)
		arena._update_firearm_attack(true, true)
		if arena.projectiles.size() != 2 or arena.active_cycle_action_code != action_code:
			return _dispose_failure(arena, "action %d did not reopen after its real timer" % action_code)
		arena.free()
	var deliberate := _arena({"cycle_required": true, "cycle_overhead_seconds": 0.42, "shot_interval_seconds": 0.18})
	var rapid := _arena({"cycle_required": true, "cycle_overhead_seconds": 0.42, "shot_interval_seconds": 0.10})
	deliberate._update_firearm_attack(true, true)
	rapid._update_firearm_attack(true, true)
	var cadence_ok := is_equal_approx(deliberate.manual_cycle_timer, 0.60) and is_equal_approx(rapid.manual_cycle_timer, 0.52)
	deliberate.free()
	rapid.free()
	return true if cadence_ok else "cadence did not remain causal inside cycle total"


func _test_cycle_then_reload_sequence() -> Variant:
	var arena := _arena({
		"magazine_size": 1,
		"cycle_action_code": 2,
		"cycle_required": true,
		"cycle_overhead_seconds": 0.30,
		"shot_interval_seconds": 0.20,
		"reload_seconds": 0.40,
		"reload_feed_code": 1,
		"reload_rounds_per_step": 1,
	})
	arena._update_firearm_attack(true, true)
	if arena.ammo_in_magazine != 0 or arena.manual_cycle_timer <= 0.0 or arena.reload_timer > 0.0 or not arena.pending_reload_after_cycle:
		return _dispose_failure(arena, "last shot did not enter cycle-only phase")
	arena._update_firearm_timers(0.49)
	if arena.manual_cycle_timer <= 0.0 or arena.reload_timer > 0.0:
		return _dispose_failure(arena, "reload overlapped the mechanical cycle")
	arena._update_firearm_timers(0.02)
	if arena.manual_cycle_timer > 0.0 or not is_equal_approx(arena.reload_timer, 0.39) or arena.pending_reload_after_cycle:
		return _dispose_failure(arena, "reload did not start from only the post-cycle delta")
	arena._update_firearm_timers(0.39)
	var ok := arena.ammo_in_magazine == 1 and arena.reload_timer <= 0.0
	arena.free()
	return true if ok else "post-cycle reload did not complete"


func _test_package_reload_modes() -> Variant:
	for feed_code: int in [0, 3]:
		var arena := _arena({"magazine_size": 9, "reload_feed_code": feed_code, "reload_seconds": 0.35})
		arena.ammo_in_magazine = 0
		arena._begin_firearm_reload()
		arena._update_firearm_timers(0.36)
		if arena.ammo_in_magazine != 9 or arena.reload_timer > 0.0:
			return _dispose_failure(arena, "feed %d did not replace full package" % feed_code)
		arena.free()
	return true


func _test_interruptible_per_round_reload() -> Variant:
	var arena := _arena({
		"magazine_size": 5,
		"reload_feed_code": 1,
		"reload_rounds_per_step": 1,
		"reload_seconds": 0.25,
	})
	arena.ammo_in_magazine = 0
	arena._begin_firearm_reload()
	arena._update_firearm_timers(0.25)
	if arena.ammo_in_magazine != 1 or arena.reload_timer <= 0.0:
		return _dispose_failure(arena, "first per-round step did not add one live round")
	arena._update_firearm_attack(true, true)
	var ok := (
		arena.projectiles.size() == 1
		and arena.ammo_in_magazine == 0
		and int(arena.metrics.get("reload_interrupt_count", 0)) == 1
		and arena.reload_timer > 0.0
	)
	arena.free()
	return true if ok else "attack did not interrupt per-round reload and consume its loaded round"


func _test_cylinder_batch_reload() -> Variant:
	var arena := _arena({
		"magazine_size": 6,
		"reload_feed_code": 2,
		"reload_rounds_per_step": 2,
		"reload_seconds": 0.25,
	})
	arena.ammo_in_magazine = 0
	arena._begin_firearm_reload()
	arena._update_firearm_timers(0.25)
	if arena.ammo_in_magazine != 2 or arena.reload_timer <= 0.0:
		return _dispose_failure(arena, "cylinder did not load its declared first batch")
	arena._update_firearm_attack(true, true)
	if not arena.projectiles.is_empty() or arena.ammo_in_magazine != 2:
		return _dispose_failure(arena, "cylinder batch reload was incorrectly interruptible")
	arena._update_firearm_timers(0.50)
	var ok := arena.ammo_in_magazine == 6 and arena.reload_timer <= 0.0
	arena.free()
	return true if ok else "cylinder did not finish in two-round batches"


func _test_sustained_climb() -> Variant:
	var arena := _arena({
		"automatic_fire": true,
		"shot_interval_seconds": 0.10,
		"magazine_size": 12,
		"sustained_climb_per_shot_degrees": 2.5,
		"sustained_climb_cap_degrees": 6.0,
		"sustained_recovery_multiplier": 0.5,
		"sustained_window_seconds": 0.20,
		"muzzle_climb_recovery_degrees_per_second": 20.0,
	})
	for shot_index: int in range(4):
		arena.shot_cooldown = 0.0
		arena._update_firearm_attack(true, shot_index == 0)
	if not is_equal_approx(arena.sustained_muzzle_climb_degrees, 6.0):
		return _dispose_failure(arena, "sustained climb missed its declared cap")
	var expected_rotation := deg_to_rad(-arena.weapon_muzzle_climb_degrees - 6.0)
	if not is_equal_approx(arena._firearm_recoil_rotation(), expected_rotation):
		return _dispose_failure(arena, "extra climb did not reach real weapon rotation")
	arena._update_firearm_timers(0.19)
	if not is_equal_approx(arena.sustained_muzzle_climb_degrees, 6.0):
		return _dispose_failure(arena, "sustained climb recovered while still inside fire window")
	arena._update_firearm_timers(0.11)
	var expected_after_recovery := 5.0
	var ok := is_equal_approx(arena.sustained_muzzle_climb_degrees, expected_after_recovery)
	arena.free()
	return true if ok else "sustained recovery did not consume only post-window time"


func _test_v4_defaults() -> Variant:
	var arena := _arena({
		"manual_cycle_required": true,
		"manual_cycle_overhead_seconds": 0.40,
		"shot_interval_seconds": 0.20,
	})
	var ammo_before := arena.ammo_in_magazine
	arena._update_firearm_attack(true, true)
	if arena.projectiles.size() != 1 or arena.ammo_in_magazine != ammo_before - 1:
		return _dispose_failure(arena, "V4 shot stopped being one projectile per round")
	if not is_equal_approx(arena.manual_cycle_timer, 0.60) or arena.sustained_muzzle_climb_degrees != 0.0:
		return _dispose_failure(arena, "V4 manual-cycle fallback changed")
	var projectile := arena.projectiles[0] as Dictionary
	projectile["distance_travelled"] = float(projectile.get("damage_falloff_end_pixels", 0.0))
	var base_damage := float(projectile.get("damage", 0.0))
	var far_damage := arena._projectile_damage_against(projectile, {"id": 8, "type": "target", "pos": Vector2.ZERO, "hp": 100.0, "facing": -1.0})
	var ok := is_equal_approx(far_damage, base_damage * 0.55)
	arena.free()
	return true if ok else "V4 default falloff no longer bottoms at 0.55"


func _test_identity_free_runtime() -> Variant:
	var source := FileAccess.get_file_as_string("res://scripts/systems/gameplay_arena.gd").to_lower()
	for forbidden: String in ["qbz", "m4a1", "m16", "m24", "glock", "type_81", "qsz", "shotgun", "rifle", "pistol"]:
		if source.contains(forbidden):
			return "identity/family branch leaked into runtime: %s" % forbidden
	return true


func _arena(overrides: Dictionary = {}) -> GameplayArena:
	var arena := ARENA.new() as GameplayArena
	var blueprint := BLUEPRINT.new() as WeaponBlueprint
	blueprint.behavior_family = "sustained_ranged"
	blueprint.affordance = {"weapon_domain": "handheld_firearm"}
	blueprint.affordance_source = "ai:test"
	arena.blueprint = blueprint
	arena.player_position = Vector2(250, 420)
	arena.facing = 1.0
	var runtime := _base_runtime()
	runtime.merge(overrides, true)
	arena.ranged_runtime_profile = runtime
	arena.ammo_in_magazine = int(runtime.get("magazine_size", 8))
	arena.metrics = {
		"shots_fired": 0,
		"reload_count": 0,
		"reload_interrupt_count": 0,
		"manual_cycle_count": 0,
	}
	return arena


func _base_runtime() -> Dictionary:
	return {
		"ok": true,
		"schema": AXES.RUNTIME_SCHEMA,
		"automatic_fire": false,
		"burst_size": 0,
		"manual_cycle_required": false,
		"manual_cycle_overhead_seconds": 0.0,
		"shot_interval_seconds": 0.18,
		"recoil_pixels": 6.0,
		"recoil_recovery_pixels_per_second": 70.0,
		"muzzle_climb_degrees_per_shot": 4.0,
		"muzzle_climb_recovery_degrees_per_second": 24.0,
		"spread_velocity": 12.0,
		"projectile_speed": 600.0,
		"projectile_life_seconds": 1.2,
		"projectile_damage": 12.0,
		"damage_falloff_start_pixels": 400.0,
		"damage_falloff_end_pixels": 800.0,
		"magazine_size": 8,
		"reload_seconds": 0.50,
	}


func _dispose_failure(arena: GameplayArena, message: String) -> String:
	arena.free()
	return message
