extends SceneTree

const DRIVER := preload("res://scripts/enemy_attack/enemy_attack_runtime_driver.gd")
const INTERACTION := preload("res://scripts/combat_feel/weapon_target_interaction_resolver.gd")
const ENEMY := preload("res://scripts/combat_feel/combat_feel_enemy.gd")
const ARENA := preload("res://scripts/systems/gameplay_arena.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	_run("Compiled enemy attacks execute the fixed four-phase runtime", _test_runtime_phase_sequence)
	_run("Commit locking prevents hidden post-lock steering", _test_direction_lock)
	_run("Telegraph preview and hit test share one geometry contract", _test_geometry_agreement)
	_run("The existing combat enemy naturally runs compiled attacks", _test_live_enemy_runtime)
	_run("Strong weapon control interrupts a fragile telegraph", _test_fragile_attack_interrupt)
	_run("Weak weapon reaction does not invent an interruption", _test_weak_reaction_does_not_interrupt)
	_run("Armored commit resists control during its protected phase", _test_armored_commit_protection)
	_run("Ranged arena enemies use the same attack and interruption bridge", _test_ranged_arena_bridge)
	_run("Projectile activation preserves its committed direction and compiled lifetime", _test_projectile_activation_event)
	_run("Marked impact activates at its committed point with the compiled circle", _test_marked_activation_event)
	_run("Ranged arena materializes and resolves both detached hazard families", _test_arena_detached_hazards)
	_run("Runtime bridge remains identity-free and asks no player question", _test_runtime_boundary)
	print("COMBAT_MECHANISM_INTEGRATION_TESTS passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _run(label: String, callable: Callable) -> void:
	var result: Variant = callable.call()
	if result is bool and bool(result):
		passed += 1
		print("PASS | %s" % label)
	else:
		failed += 1
		printerr("FAIL | %s | %s" % [label, str(result)])


func _test_runtime_phase_sequence() -> Variant:
	var driver: RefCounted = DRIVER.new()
	var configured: Dictionary = driver.configure([_declaration({})])
	if not bool(configured.get("ok", false)):
		return configured
	var begun: Dictionary = driver.begin_attack(_context(64.0, 0.0), Vector2.ZERO, Vector2(64, 0))
	if str(begun.get("phase", "")) != "telegraph":
		return begun
	var timeline := driver.current_attack.get("timeline", {}) as Dictionary
	var pre_active := float(timeline["telegraph_seconds"]) + float(timeline["commit_seconds"])
	var active: Dictionary = driver.step(pre_active + 0.01, Vector2.ZERO, Vector2(64, 0))
	if str(active.get("phase", "")) != "active" or not driver.is_attack_dangerous():
		return active
	var recovery: Dictionary = driver.step(float(timeline["active_seconds"]), Vector2.ZERO, Vector2(64, 0))
	if str(recovery.get("phase", "")) != "recovery":
		return recovery
	var idle: Dictionary = driver.step(float(timeline["recovery_seconds"]) + 0.01, Vector2.ZERO, Vector2(64, 0))
	return true if str(idle.get("phase", "")) == "idle" and bool(idle.get("completed_attack", false)) else idle


func _test_direction_lock() -> Variant:
	var driver: RefCounted = DRIVER.new()
	driver.configure([_declaration({
		"delivery": "rush", "target_lock": "direction_on_commit",
		"hit_shape": "strip", "depth_path": "cross_depth",
	})])
	driver.begin_attack(_context(240.0, 0.0), Vector2.ZERO, Vector2(240, 0))
	var telegraph_seconds := float((driver.current_attack.get("timeline", {}) as Dictionary)["telegraph_seconds"])
	driver.step(telegraph_seconds + 0.001, Vector2.ZERO, Vector2(240, 0))
	var locked: Vector2 = driver.locked_direction
	driver.step(0.04, Vector2.ZERO, Vector2(0, 240))
	return true if driver.phase == "commit" and driver.locked_direction.is_equal_approx(locked) else driver.snapshot()


func _test_geometry_agreement() -> Variant:
	var driver: RefCounted = DRIVER.new()
	driver.configure([_declaration({"hit_shape": "arc", "target_lock": "live_until_active"})])
	var begun: Dictionary = driver.begin_attack(_context(60.0, 0.0), Vector2.ZERO, Vector2(60, 0))
	var telegraph := begun.get("telegraph", {}) as Dictionary
	var preview := telegraph.get("preview_region", {}) as Dictionary
	var hit_region := begun.get("hit_region", {}) as Dictionary
	var same_signature := str(preview.get("geometry_signature", "")) == str(hit_region.get("geometry_signature", ""))
	var front_hit: bool = driver.current_hit_contains(Vector2.ZERO, Vector2(60, 0))
	var rear_miss: bool = not driver.current_hit_contains(Vector2.ZERO, Vector2(-60, 0))
	return true if same_signature and front_hit and rear_miss else begun


func _test_live_enemy_runtime() -> Variant:
	var enemy: Node2D = ENEMY.new()
	var spawn := Vector2(500, 400)
	var target := Vector2(555, 400)
	enemy.setup(ENEMY.PUPPET, 1, spawn)
	var strikes: Array[float] = []
	enemy.player_struck.connect(func(damage: float, _direction: Vector2) -> void: strikes.append(damage))
	enemy.simulate(0.01, target)
	var began_compiled: bool = enemy.attack_runtime.is_running() and enemy.attack_runtime.phase == "telegraph" and enemy.state == "tell"
	enemy.simulate(enemy.tell_seconds + 0.03, target)
	var active: bool = enemy.attack_runtime.phase == "active" and enemy.state == "attack" and enemy.is_attack_dangerous()
	var hit_once := strikes.size() == 1 and is_equal_approx(strikes[0], 9.0)
	enemy.simulate(0.04, target)
	hit_once = hit_once and strikes.size() == 1
	var diagnostics := {
		"began": began_compiled,
		"active": active,
		"strikes": strikes,
		"contains": enemy.attack_runtime.current_hit_contains(enemy.position, target),
		"runtime": enemy.attack_runtime.snapshot(),
	}
	enemy.free()
	return true if began_compiled and active and hit_once else diagnostics


func _test_fragile_attack_interrupt() -> Variant:
	var enemy: Node2D = ENEMY.new()
	enemy.setup(ENEMY.PUPPET, 2, Vector2.ZERO)
	enemy.simulate(0.01, Vector2(55, 0))
	var outcome := _control_outcome("strong", enemy.target_interaction_context())
	enemy.apply_hit(1.0, Vector2.ZERO, float(outcome.get("stagger", 0.0)), 0.0, outcome)
	var result: bool = enemy.attack_runtime.phase == "recovery" and enemy.state == "recovery"
	enemy.free()
	return true if result else outcome


func _test_weak_reaction_does_not_interrupt() -> Variant:
	var enemy: Node2D = ENEMY.new()
	enemy.setup(ENEMY.PUPPET, 3, Vector2.ZERO)
	enemy.simulate(0.01, Vector2(55, 0))
	var outcome := _control_outcome("light", enemy.target_interaction_context())
	enemy.apply_hit(1.0, Vector2.ZERO, float(outcome.get("stagger", 0.0)), 0.0, outcome)
	var result: bool = enemy.attack_runtime.phase == "telegraph"
	enemy.free()
	return true if result else outcome


func _test_armored_commit_protection() -> Variant:
	var enemy: Node2D = ENEMY.new()
	enemy.setup(ENEMY.RAM, 4, Vector2.ZERO)
	enemy.simulate(0.83, Vector2(260, 0))
	var timeline := enemy.attack_runtime.current_attack.get("timeline", {}) as Dictionary
	enemy.simulate(float(timeline.get("telegraph_seconds", 0.0)) + 0.001, Vector2(260, 0))
	if enemy.attack_runtime.phase != "commit":
		var snapshot: Dictionary = enemy.attack_runtime.snapshot()
		enemy.free()
		return snapshot
	var outcome := _control_outcome("strong", enemy.target_interaction_context())
	enemy.apply_hit(1.0, Vector2.ZERO, float(outcome.get("stagger", 0.0)), 0.0, outcome)
	var protected: bool = enemy.attack_runtime.phase == "commit" and enemy.state == "tell"
	enemy.free()
	return true if protected else outcome


func _test_runtime_boundary() -> Variant:
	var source := FileAccess.get_file_as_string("res://scripts/enemy_attack/enemy_attack_runtime_driver.gd").to_lower()
	for forbidden: String in ["slag_puppet", "forge_ram", "enemy_kind", "player_choice", "ask_player"]:
		if source.contains(forbidden):
			return "identity or player input leaked into runtime: %s" % forbidden
	var driver: RefCounted = DRIVER.new()
	var configured: Dictionary = driver.configure([_declaration({})])
	return true if not bool(configured.get("identity_inputs_used", true)) and not bool(configured.get("player_confirmation_required", true)) else configured


func _test_ranged_arena_bridge() -> Variant:
	var arena: Node2D = ARENA.new()
	arena.stage_name = "wave"
	arena.player_position = Vector2(500, 400)
	arena._spawn_enemy("swarmling", Vector2(430, 400), 40.0)
	var enemy: Dictionary = arena.enemies[0]
	arena._update_enemies(0.01)
	var attack_runtime: Variant = enemy.get("attack_runtime", null)
	var began: bool = attack_runtime != null and attack_runtime.phase == "telegraph"
	var outcome := _control_outcome("strong", arena._target_interaction_context(enemy))
	arena._apply_target_interaction(enemy, outcome)
	var interrupted: bool = attack_runtime.phase == "recovery" and str(enemy.get("attack_phase", "")) == "recovery"
	arena.free()
	return true if began and interrupted else {"began": began, "interrupted": interrupted, "outcome": outcome}


func _test_projectile_activation_event() -> Variant:
	var driver: RefCounted = DRIVER.new()
	driver.configure([_declaration({
		"delivery": "projectile", "target_lock": "direction_on_commit", "hit_shape": "capsule",
	})])
	driver.begin_attack(_context(300.0, 0.0), Vector2.ZERO, Vector2(300, 0))
	var timeline := driver.current_attack.get("timeline", {}) as Dictionary
	driver.step(float(timeline["telegraph_seconds"]) + 0.001, Vector2.ZERO, Vector2(300, 0))
	var result: Dictionary = driver.step(float(timeline["commit_seconds"]) + 0.001, Vector2.ZERO, Vector2(0, 300))
	var event := result.get("activation_event", {}) as Dictionary
	var velocity: Vector2 = Vector2(event.get("velocity", Vector2.ZERO))
	var region := event.get("hit_region", {}) as Dictionary
	var ok := str(event.get("delivery", "")) == "projectile"
	ok = ok and velocity.x > 500.0 and absf(velocity.y) < 0.001
	ok = ok and is_equal_approx(float(event.get("hazard_lifetime_seconds", 0.0)), 1.35)
	ok = ok and str(region.get("shape", "")) == "capsule"
	return true if ok else event


func _test_marked_activation_event() -> Variant:
	var driver: RefCounted = DRIVER.new()
	driver.configure([_declaration({
		"delivery": "marked_impact", "target_lock": "point_on_commit",
		"hit_shape": "circle", "depth_path": "depth_band",
	})])
	var committed_point := Vector2(280, 45)
	driver.begin_attack(_context(committed_point.length(), committed_point.y), Vector2.ZERO, committed_point)
	var timeline := driver.current_attack.get("timeline", {}) as Dictionary
	driver.step(float(timeline["telegraph_seconds"]) + 0.001, Vector2.ZERO, committed_point)
	var result: Dictionary = driver.step(float(timeline["commit_seconds"]) + 0.001, Vector2.ZERO, Vector2(-250, -80))
	var event := result.get("activation_event", {}) as Dictionary
	var region := event.get("hit_region", {}) as Dictionary
	var ok := str(event.get("delivery", "")) == "marked_impact"
	ok = ok and Vector2(event.get("origin", Vector2.ZERO)).is_equal_approx(committed_point)
	ok = ok and Vector2(event.get("velocity", Vector2.ONE)).is_zero_approx()
	ok = ok and str(region.get("shape", "")) == "circle" and is_equal_approx(float(region.get("radius_pixels", 0.0)), 68.0)
	return true if ok else event


func _test_arena_detached_hazards() -> Variant:
	var projectile_arena: Node2D = ARENA.new()
	projectile_arena.stage_name = "wave"
	projectile_arena.player_position = Vector2(700, 400)
	projectile_arena._spawn_enemy("guard", Vector2(300, 400), 100.0)
	var guard: Dictionary = projectile_arena.enemies[0]
	projectile_arena._update_enemies(0.01)
	var guard_runtime: Variant = guard["attack_runtime"]
	var guard_timeline := guard_runtime.current_attack.get("timeline", {}) as Dictionary
	projectile_arena._update_enemies(float(guard_timeline["telegraph_seconds"]) + float(guard_timeline["commit_seconds"]) + 0.01)
	var projectile_spawned: bool = projectile_arena.enemy_attack_hazards.size() == 1 \
		and str(projectile_arena.enemy_attack_hazards[0].get("delivery", "")) == "projectile"
	var projectile_health: float = float(projectile_arena.player_health)
	projectile_arena._update_enemy_attack_hazards(0.75)
	var projectile_hit: bool = projectile_arena.player_health < projectile_health and projectile_arena.enemy_attack_hazards.is_empty()
	projectile_arena.free()

	var marked_arena: Node2D = ARENA.new()
	marked_arena.stage_name = "wave"
	marked_arena.player_position = Vector2(700, 400)
	marked_arena._spawn_enemy("rusher", Vector2(300, 400), 100.0)
	var rusher: Dictionary = marked_arena.enemies[0]
	marked_arena._update_enemies(0.01)
	var rusher_runtime: Variant = rusher["attack_runtime"]
	var rusher_timeline := rusher_runtime.current_attack.get("timeline", {}) as Dictionary
	marked_arena._update_enemies(float(rusher_timeline["telegraph_seconds"]) + float(rusher_timeline["commit_seconds"]) + 0.01)
	var marked_spawned: bool = marked_arena.enemy_attack_hazards.size() == 1 \
		and str(marked_arena.enemy_attack_hazards[0].get("delivery", "")) == "marked_impact"
	var marked_health: float = float(marked_arena.player_health)
	marked_arena._update_enemy_attack_hazards(0.01)
	var marked_hit: bool = marked_arena.player_health < marked_health and marked_arena.enemy_attack_hazards.is_empty()
	marked_arena.free()
	return true if projectile_spawned and projectile_hit and marked_spawned and marked_hit else {
		"projectile_spawned": projectile_spawned,
		"projectile_hit": projectile_hit,
		"marked_spawned": marked_spawned,
		"marked_hit": marked_hit,
	}


func _control_outcome(level: String, context: Dictionary) -> Dictionary:
	var axes: Dictionary = INTERACTION.default_effect_axes()
	axes["control"] = level
	var profile: Dictionary = INTERACTION.compile(axes, "integration_test")
	return INTERACTION.resolve(profile, context, 1.0, {"knockback": Vector2.ZERO, "stagger": 0.0})


func _context(distance: float, depth_delta: float) -> Dictionary:
	return {
		"distance_pixels": distance,
		"depth_delta_pixels": depth_delta,
		"available_coordination_budget": 1,
		"clear_path": true,
	}


func _declaration(overrides: Dictionary) -> Dictionary:
	var axes := {
		"delivery": "contact",
		"target_lock": "direction_on_commit",
		"hit_shape": "capsule",
		"depth_path": "same_lane",
		"tempo": "standard",
		"stability": "fragile",
		"recovery": "punishable",
	}
	for key: Variant in overrides:
		axes[key] = overrides[key]
	return {
		"attack_key": "slot_integration",
		"axes": axes,
		"selection": {
			"preferred_range": "any",
			"depth_fit": "any",
			"base_priority": 50,
			"coordination_cost": 1,
			"requires_clear_path": false,
			"selection_rank": 10,
		},
	}
