class_name GameplayArena
extends Node2D

signal stage_completed(stage_name: String, metrics: Dictionary)
signal metrics_changed(metrics: Dictionary)

const RULES := preload("res://scripts/systems/combat_rules.gd")
const WORLD_RECT := Rect2(34, 116, 1212, 568)

var stage_name := "training"
var blueprint: WeaponBlueprint
var asset: WeaponVisualAsset
var player_position := Vector2(250, 420)
var player_health := 100.0
var facing := 1.0
var enemies: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var boomerang: Dictionary = {}
var active := false
var debug_anchors := false
var touch_vector := Vector2.ZERO
var touch_attack := false
var touch_attack_requested := false
var touch_dodge_requested := false
var attack_was_down := false
var attack_charge := 0.0
var shot_cooldown := 0.0
var overheat := 0.0
var overheat_lock := 0.0
var melee_timer := 0.0
var melee_connected: Dictionary = {}
var dodge_timer := 0.0
var invulnerable_timer := 0.0
var stage_elapsed := 0.0
var completion_delay := -1.0
var flash_timer := 0.0
var metrics := {"damage_taken": 0.0, "overheat_count": 0, "dodge_count": 0, "defeated": 0}

func start_stage(next_stage: String, next_blueprint: WeaponBlueprint, next_asset: WeaponVisualAsset) -> void:
	stage_name = next_stage
	blueprint = next_blueprint
	asset = next_asset
	player_position = Vector2(250, 420)
	player_health = 100.0
	projectiles.clear()
	boomerang.clear()
	attack_charge = 0.0
	overheat = 0.0
	overheat_lock = 0.0
	melee_timer = 0.0
	touch_attack = false
	touch_attack_requested = false
	attack_was_down = false
	dodge_timer = 0.0
	stage_elapsed = 0.0
	completion_delay = -1.0
	metrics = {"damage_taken": 0.0, "overheat_count": 0, "dodge_count": 0, "defeated": 0}
	_spawn_stage()
	active = true
	set_process(true)
	queue_redraw()

func stop() -> void:
	active = false
	set_process(false)

func set_touch_vector(value: Vector2) -> void:
	touch_vector = value

func set_touch_attack(value: bool) -> void:
	touch_attack = value

func request_touch_attack() -> void:
	# Latch tap-style melee/throw inputs until the next gameplay frame. A fast
	# UI click can otherwise send button_down and button_up between two frames.
	touch_attack_requested = true

func request_touch_dodge() -> void:
	touch_dodge_requested = true

func _process(delta: float) -> void:
	if not active or blueprint == null or asset == null:
		return
	stage_elapsed += delta
	shot_cooldown = maxf(0.0, shot_cooldown - delta)
	overheat_lock = maxf(0.0, overheat_lock - delta)
	invulnerable_timer = maxf(0.0, invulnerable_timer - delta)
	flash_timer = maxf(0.0, flash_timer - delta)
	_update_player(delta)
	_update_attacks(delta)
	_update_projectiles(delta)
	_update_enemies(delta)
	_check_completion(delta)
	queue_redraw()

func _update_player(delta: float) -> void:
	var keyboard := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var movement := keyboard if keyboard.length() > 0.05 else touch_vector
	if absf(movement.x) > 0.08:
		facing = signf(movement.x)
	var speed := 220.0
	if blueprint.weight_class == "heavy":
		speed = 158.0
	if attack_charge > 0.0 or melee_timer > 0.0:
		speed *= 0.62
	if dodge_timer > 0.0:
		dodge_timer -= delta
		speed = 510.0
	var wants_dodge := Input.is_action_just_pressed("dodge") or touch_dodge_requested
	touch_dodge_requested = false
	if wants_dodge and dodge_timer <= 0.0:
		dodge_timer = 0.20
		invulnerable_timer = 0.26
		metrics["dodge_count"] = int(metrics["dodge_count"]) + 1
		metrics_changed.emit(metrics)
	player_position += movement.limit_length(1.0) * speed * delta
	player_position.x = clampf(player_position.x, WORLD_RECT.position.x + 34.0, WORLD_RECT.end.x - 34.0)
	player_position.y = clampf(player_position.y, WORLD_RECT.position.y + 48.0, WORLD_RECT.end.y - 28.0)

func _update_attacks(delta: float) -> void:
	var attack_down := Input.is_action_pressed("attack") or touch_attack
	var just_pressed := touch_attack_requested or (attack_down and not attack_was_down)
	touch_attack_requested = false
	attack_was_down = attack_down
	match blueprint.behavior_family:
		"returning_thrown": _update_returning_attack(just_pressed, delta)
		"heavy_melee": _update_melee_attack(just_pressed, delta)
		_: _update_sustained_attack(attack_down, delta)

func _update_sustained_attack(attack_down: bool, delta: float) -> void:
	var heat_multiplier := float(blueprint.modifiers.get("heat_multiplier", 1.0))
	var rate_multiplier := float(blueprint.modifiers.get("fire_rate_multiplier", 1.0))
	if overheat_lock > 0.0:
		attack_charge = 0.0
		overheat = maxf(0.0, overheat - delta * 0.45)
		return
	if attack_down:
		attack_charge += delta
		if attack_charge >= 0.34 and shot_cooldown <= 0.0:
			_fire_bullet()
			shot_cooldown = 0.11 / maxf(0.2, rate_multiplier)
			overheat += 0.035 * heat_multiplier
			if overheat >= 1.0:
				overheat = 1.0
				overheat_lock = 1.45
				metrics["overheat_count"] = int(metrics["overheat_count"]) + 1
				metrics_changed.emit(metrics)
	else:
		attack_charge = maxf(0.0, attack_charge - delta * 2.0)
		overheat = maxf(0.0, overheat - delta * 0.28)

func _update_returning_attack(just_pressed: bool, delta: float) -> void:
	if just_pressed and boomerang.is_empty():
		boomerang = {
			"pos": _muzzle_world(), "origin": player_position, "direction": facing,
			"distance": 0.0, "returning": false, "hit_out": {}, "hit_back": {}
		}
	if boomerang.is_empty():
		return
	var position: Vector2 = boomerang["pos"]
	if not bool(boomerang["returning"]):
		position.x += float(boomerang["direction"]) * 430.0 * delta
		boomerang["distance"] = float(boomerang["distance"]) + 430.0 * delta
		if float(boomerang["distance"]) >= 340.0:
			boomerang["returning"] = true
	else:
		position = position.move_toward(player_position, 470.0 * delta)
		if position.distance_to(player_position) < 24.0:
			boomerang.clear()
			return
	boomerang["pos"] = position
	var hit_set: Dictionary = boomerang["hit_back"] if bool(boomerang["returning"]) else boomerang["hit_out"]
	for enemy: Dictionary in enemies:
		var enemy_id := int(enemy["id"])
		if not hit_set.has(enemy_id) and position.distance_to(enemy["pos"]) < 32.0:
			hit_set[enemy_id] = true
			_damage_enemy(enemy, RULES.damage_against(blueprint.behavior_family, enemy["type"], _is_front_hit(enemy), blueprint.modifiers))
			_chain_damage(enemy, 8.0)

func _update_melee_attack(just_pressed: bool, delta: float) -> void:
	var startup_multiplier := float(blueprint.modifiers.get("startup_multiplier", 1.0))
	if just_pressed and melee_timer <= 0.0:
		melee_timer = 0.75 * startup_multiplier
		melee_connected.clear()
	if melee_timer <= 0.0:
		return
	melee_timer -= delta
	var active_window := melee_timer < 0.34 and melee_timer > 0.08
	if not active_window:
		return
	var range := 105.0 * float(blueprint.modifiers.get("area_multiplier", 1.0))
	for enemy: Dictionary in enemies:
		var enemy_id := int(enemy["id"])
		var direction_to_enemy: Vector2 = enemy["pos"] - player_position
		if not melee_connected.has(enemy_id) and direction_to_enemy.length() <= range and signf(direction_to_enemy.x) == facing:
			melee_connected[enemy_id] = true
			var damage := RULES.damage_against(blueprint.behavior_family, enemy["type"], _is_front_hit(enemy), blueprint.modifiers)
			_damage_enemy(enemy, damage)
			player_health = minf(100.0, player_health + damage * 0.10)

func _fire_bullet() -> void:
	projectiles.append({
		"pos": _muzzle_world(), "vel": Vector2(facing * 610.0, randf_range(-12.0, 12.0)),
		"life": 1.45, "pierces": 1 if bool(blueprint.modifiers.get("limited_pierce", false)) else 0,
		"hit": {}
	})

func _update_projectiles(delta: float) -> void:
	for projectile: Dictionary in projectiles:
		projectile["pos"] = Vector2(projectile["pos"]) + Vector2(projectile["vel"]) * delta
		projectile["life"] = float(projectile["life"]) - delta
		for enemy: Dictionary in enemies:
			var enemy_id := int(enemy["id"])
			var hit: Dictionary = projectile["hit"]
			if not hit.has(enemy_id) and Vector2(projectile["pos"]).distance_to(enemy["pos"]) < 23.0:
				hit[enemy_id] = true
				_damage_enemy(enemy, RULES.damage_against(blueprint.behavior_family, enemy["type"], _is_front_hit(enemy), blueprint.modifiers))
				enemy["burn"] = 2.2
				if int(projectile["pierces"]) > 0:
					projectile["pierces"] = int(projectile["pierces"]) - 1
				else:
					projectile["life"] = 0.0
	projectiles = projectiles.filter(func(projectile: Dictionary) -> bool: return float(projectile["life"]) > 0.0 and WORLD_RECT.grow(80).has_point(projectile["pos"]))

func _update_enemies(delta: float) -> void:
	for enemy: Dictionary in enemies:
		enemy["hurt"] = maxf(0.0, float(enemy.get("hurt", 0.0)) - delta)
		enemy["cooldown"] = maxf(0.0, float(enemy.get("cooldown", 0.0)) - delta)
		if float(enemy.get("burn", 0.0)) > 0.0:
			enemy["burn"] = float(enemy["burn"]) - delta
			enemy["hp"] = float(enemy["hp"]) - 5.0 * delta
		if stage_name == "training":
			if enemy["type"] == "moving_target":
				enemy["pos"] = Vector2(enemy["pos"]) + Vector2(float(enemy["patrol"]), 0) * 75.0 * delta
				if float(Vector2(enemy["pos"]).x) < 680.0 or float(Vector2(enemy["pos"]).x) > 1120.0:
					enemy["patrol"] = -float(enemy["patrol"])
			if float(enemy["hp"]) <= 0.0:
				enemy["hp"] = float(enemy["max_hp"])
			continue
		var to_player := player_position - Vector2(enemy["pos"])
		enemy["facing"] = signf(to_player.x)
		var speed := 54.0
		if enemy["type"] == "rusher":
			enemy["charge"] = float(enemy.get("charge", 0.0)) + delta
			if float(enemy["charge"]) > 1.35:
				speed = 235.0
			if float(enemy["charge"]) > 1.75:
				enemy["charge"] = 0.0
		elif enemy["type"] == "swarmling":
			speed = 82.0
		elif enemy["type"] == "guard":
			speed = 42.0
		if to_player.length() > 28.0:
			enemy["pos"] = Vector2(enemy["pos"]) + to_player.normalized() * speed * delta
		elif float(enemy["cooldown"]) <= 0.0 and invulnerable_timer <= 0.0:
			var damage := 5.0 if enemy["type"] == "swarmling" else 9.0
			player_health = maxf(1.0, player_health - damage)
			metrics["damage_taken"] = float(metrics["damage_taken"]) + damage
			enemy["cooldown"] = 0.85
			flash_timer = 0.14
			metrics_changed.emit(metrics)
	var before := enemies.size()
	enemies = enemies.filter(func(enemy: Dictionary) -> bool: return float(enemy["hp"]) > 0.0)
	metrics["defeated"] = int(metrics["defeated"]) + before - enemies.size()

func _damage_enemy(enemy: Dictionary, amount: float) -> void:
	enemy["hp"] = float(enemy["hp"]) - amount
	enemy["hurt"] = 0.12

func _chain_damage(source: Dictionary, amount: float) -> void:
	for enemy: Dictionary in enemies:
		if enemy != source and Vector2(enemy["pos"]).distance_to(source["pos"]) < 105.0:
			_damage_enemy(enemy, amount)

func _is_front_hit(enemy: Dictionary) -> bool:
	var enemy_facing := float(enemy.get("facing", -1.0))
	var incoming_side := signf(player_position.x - Vector2(enemy["pos"]).x)
	return enemy_facing == incoming_side

func _check_completion(delta: float) -> void:
	if stage_name == "training":
		return
	if enemies.is_empty() and completion_delay < 0.0:
		completion_delay = 0.9
	if completion_delay >= 0.0:
		completion_delay -= delta
		if completion_delay <= 0.0:
			active = false
			metrics["elapsed_seconds"] = snappedf(stage_elapsed, 0.1)
			stage_completed.emit(stage_name, metrics.duplicate(true))

func _spawn_stage() -> void:
	enemies.clear()
	match stage_name:
		"room_1":
			_spawn_enemy("swarmling", Vector2(800, 250), 24.0)
			_spawn_enemy("swarmling", Vector2(900, 420), 24.0)
			_spawn_enemy("swarmling", Vector2(760, 560), 24.0)
			_spawn_enemy("rusher", Vector2(1090, 360), 58.0)
		"room_2":
			_spawn_enemy("guard", Vector2(850, 350), 120.0)
			_spawn_enemy("rusher", Vector2(1050, 520), 64.0)
			_spawn_enemy("swarmling", Vector2(980, 220), 28.0)
		_:
			_spawn_enemy("target", Vector2(760, 350), 150.0)
			_spawn_enemy("moving_target", Vector2(980, 520), 150.0)

func _spawn_enemy(type_name: String, position: Vector2, health: float) -> void:
	enemies.append({
		"id": enemies.size() + 1, "type": type_name, "pos": position, "hp": health,
		"max_hp": health, "facing": -1.0, "cooldown": 0.0, "hurt": 0.0,
		"burn": 0.0, "charge": 0.0, "patrol": 1.0
	})

func _muzzle_world() -> Vector2:
	if asset == null:
		return player_position
	var hand := Vector2(19.0 * facing, -10.0)
	var relative := asset.muzzle - asset.grip_primary
	return player_position + hand + Vector2(relative.x * 1.15 * facing, relative.y * 1.15)

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color("09131f"), true)
	draw_rect(WORLD_RECT, Color("172535"), true)
	draw_rect(WORLD_RECT, Color("3c5269"), false, 3.0)
	for x: int in range(80, 1240, 80):
		draw_line(Vector2(x, WORLD_RECT.position.y), Vector2(x, WORLD_RECT.end.y), Color(0.2, 0.31, 0.4, 0.26), 1.0)
	for y: int in range(156, 684, 66):
		draw_line(Vector2(WORLD_RECT.position.x, y), Vector2(WORLD_RECT.end.x, y), Color(0.2, 0.31, 0.4, 0.22), 1.0)
	_draw_enemies()
	_draw_player_and_weapon()
	_draw_attacks()

func _draw_player_and_weapon() -> void:
	var body_color := Color("fb7185") if flash_timer > 0.0 else Color("67e8f9")
	draw_circle(player_position + Vector2(0, -25), 13.0, Color("dbeafe"))
	draw_rect(Rect2(player_position + Vector2(-15, -12), Vector2(30, 42)), body_color, true)
	draw_line(player_position + Vector2(-8, 30), player_position + Vector2(-13, 49), Color("94a3b8"), 7.0)
	draw_line(player_position + Vector2(8, 30), player_position + Vector2(13, 49), Color("94a3b8"), 7.0)
	var hand_primary := player_position + Vector2(19.0 * facing, -10.0)
	var relative_secondary := (asset.grip_secondary - asset.grip_primary) * 1.15
	var hand_secondary := hand_primary + Vector2(relative_secondary.x * facing, relative_secondary.y)
	draw_line(player_position + Vector2(0, -5), hand_primary, Color("f0c7a6"), 7.0)
	draw_line(player_position + Vector2(2, 1), hand_secondary, Color("f0c7a6"), 7.0)
	draw_set_transform(hand_primary, 0.0, Vector2(facing, 1.0))
	var local_position := -asset.grip_primary * 1.15
	draw_texture_rect(asset.texture, Rect2(local_position, Vector2(asset.canvas_size) * 1.15), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_circle(hand_primary, 5.0, Color("f8d8b9"))
	draw_circle(hand_secondary, 5.0, Color("f8d8b9"))
	draw_line(player_position + Vector2(0, -30), player_position + Vector2(18.0 * facing, -30), Color("fef08a"), 3.0)
	if debug_anchors:
		_draw_world_anchor(hand_primary, asset.grip_primary, asset.grip_primary, "GripPrimary", Color("5eead4"))
		_draw_world_anchor(hand_primary, asset.grip_secondary, asset.grip_primary, "GripSecondary", Color("facc15"))
		_draw_world_anchor(hand_primary, asset.muzzle, asset.grip_primary, "Muzzle", Color("38bdf8"))
		_draw_world_anchor(hand_primary, asset.tip, asset.grip_primary, "Tip", Color("fb7185"))
		_draw_world_anchor(hand_primary, asset.spin_pivot, asset.grip_primary, "SpinPivot", Color("c084fc"))

func _draw_world_anchor(hand: Vector2, point: Vector2, grip: Vector2, label: String, color: Color) -> void:
	var relative := (point - grip) * 1.15
	var world := hand + Vector2(relative.x * facing, relative.y)
	draw_circle(world, 5.0, color)
	draw_string(ThemeDB.fallback_font, world + Vector2(6, -5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)

func _draw_attacks() -> void:
	for projectile: Dictionary in projectiles:
		var position: Vector2 = projectile["pos"]
		draw_circle(position, 8.0, Color(0.1, 0.6, 1.0, 0.25))
		draw_circle(position, 4.0, Color("67e8f9"))
		draw_line(position - Vector2(facing * 15.0, 0), position, Color("2563eb"), 3.0)
	if not boomerang.is_empty():
		var position: Vector2 = boomerang["pos"]
		draw_arc(position, 20.0, 0.0, TAU, 16, Color("5eead4"), 5.0)
		draw_line(position - Vector2(16, 0), position + Vector2(16, 0), Color("a78bfa"), 4.0)
	if blueprint != null and blueprint.behavior_family == "heavy_melee" and melee_timer > 0.08 and melee_timer < 0.34:
		draw_arc(player_position, 104.0, -0.8 if facing > 0 else PI - 0.8, 0.8 if facing > 0 else PI + 0.8, 24, Color("fb7185"), 8.0)
	if blueprint != null and blueprint.behavior_family == "sustained_ranged" and attack_charge > 0.0:
		var muzzle := _muzzle_world()
		draw_circle(muzzle, 6.0 + minf(attack_charge, 0.35) * 15.0, Color(0.15, 0.78, 1.0, 0.7), false, 3.0)

func _draw_enemies() -> void:
	for enemy: Dictionary in enemies:
		var position: Vector2 = enemy["pos"]
		var color := Color("f8fafc") if float(enemy["hurt"]) > 0.0 else Color("f59e0b")
		match enemy["type"]:
			"swarmling":
				draw_circle(position, 15.0, color)
				draw_circle(position + Vector2(-5, -2), 2.0, Color("111827"))
				draw_circle(position + Vector2(5, -2), 2.0, Color("111827"))
			"rusher":
				draw_colored_polygon(PackedVector2Array([position + Vector2(-20, -18), position + Vector2(24, 0), position + Vector2(-20, 18)]), color)
				if float(enemy.get("charge", 0.0)) > 1.05:
					draw_arc(position, 29.0, 0, TAU, 24, Color("ef4444"), 3.0)
			"guard":
				draw_rect(Rect2(position - Vector2(18, 22), Vector2(36, 44)), color, true)
				var shield_x := 23.0 * float(enemy["facing"])
				draw_rect(Rect2(position + Vector2(shield_x - 6, -27), Vector2(12, 54)), Color("64748b"), true)
			"moving_target":
				draw_circle(position, 25.0, Color("475569"))
				draw_circle(position, 14.0, Color("38bdf8"))
				draw_circle(position, 5.0, Color("f8fafc"))
			_:
				draw_rect(Rect2(position - Vector2(8, 34), Vector2(16, 68)), Color("64748b"), true)
				draw_circle(position - Vector2(0, 33), 25.0, Color("ef4444"), false, 7.0)
		if float(enemy.get("burn", 0.0)) > 0.0:
			draw_circle(position + Vector2(0, -30), 8.0, Color("38bdf8"))
		var max_hp := float(enemy["max_hp"])
		var ratio := clampf(float(enemy["hp"]) / maxf(1.0, max_hp), 0.0, 1.0)
		draw_rect(Rect2(position + Vector2(-24, -40), Vector2(48, 5)), Color("0f172a"), true)
		draw_rect(Rect2(position + Vector2(-24, -40), Vector2(48 * ratio, 5)), Color("4ade80"), true)
