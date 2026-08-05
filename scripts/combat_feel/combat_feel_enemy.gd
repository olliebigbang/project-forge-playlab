class_name CombatFeelEnemy
extends Node2D

signal player_struck(damage: float, direction: Vector2)
signal defeated(enemy: Node2D)

const PUPPET := "slag_puppet"
const RAM := "forge_ram"

var enemy_id := 0
var enemy_kind := PUPPET
var state := "approach"
var state_time := 0.0
var max_health := 80.0
var health := 80.0
var facing := -1.0
var locked_direction := Vector2.LEFT
var velocity := Vector2.ZERO
var flash_time := 0.0
var stagger_time := 0.0
var recoil_tilt := 0.0
var recoil_visual_time := 0.0
var dead_time := 0.0
var tell_seconds := 0.52
var recovery_seconds := 0.68
var arena_bounds := Rect2(45, 145, 1190, 530)
var _player_hit_this_attack := false

func setup(kind: String, id_value: int, spawn_position: Vector2) -> void:
	enemy_kind = kind
	enemy_id = id_value
	position = spawn_position
	if enemy_kind == RAM:
		max_health = 150.0
		health = 150.0
		state = "hold_distance"
		tell_seconds = 0.72
		recovery_seconds = 1.05
	else:
		max_health = 78.0
		health = 78.0
		state = "approach"
		tell_seconds = 0.48
		recovery_seconds = 0.62
	queue_redraw()

func simulate(delta: float, player_position: Vector2, frozen: bool = false) -> void:
	flash_time = maxf(0.0, flash_time - delta)
	recoil_visual_time = maxf(0.0, recoil_visual_time - delta)
	if recoil_visual_time <= 0.0:
		recoil_tilt = move_toward(recoil_tilt, 0.0, 7.5 * delta)
	if state == "dead":
		dead_time += delta
		position += velocity * delta
		velocity *= 0.93
		queue_redraw()
		return
	if frozen: return
	if stagger_time > 0.0:
		stagger_time = maxf(0.0, stagger_time - delta)
		position += velocity * delta
		velocity = velocity.move_toward(Vector2.ZERO, 520.0 * delta)
		queue_redraw()
		return
	state_time += delta
	if enemy_kind == RAM: _simulate_ram(delta, player_position)
	else: _simulate_puppet(delta, player_position)
	position.x = clampf(position.x, arena_bounds.position.x + 24.0, arena_bounds.end.x - 24.0)
	position.y = clampf(position.y, arena_bounds.position.y + 35.0, arena_bounds.end.y - 20.0)
	queue_redraw()

func apply_hit(damage: float, knockback: Vector2, stagger_strength: float, recoil_degrees: float = 7.0) -> bool:
	if state == "dead": return false
	health -= damage
	flash_time = 0.11
	velocity = knockback
	stagger_time = 0.14 + 0.30 * stagger_strength
	recoil_visual_time = stagger_time
	recoil_tilt = deg_to_rad(recoil_degrees) * (-signf(knockback.x) if absf(knockback.x) > 0.1 else -facing)
	if stagger_strength >= 1.20 and enemy_kind == PUPPET: stagger_time = 0.82
	elif stagger_strength >= 0.95 and enemy_kind == PUPPET: stagger_time = 0.68
	if health <= 0.0:
		state = "dead"
		state_time = 0.0
		dead_time = 0.0
		velocity = knockback * 0.72 + Vector2(0, -80)
		defeated.emit(self)
	queue_redraw()
	return true

func is_attack_dangerous() -> bool:
	return state in ["attack", "charge"]

func is_telegraphing() -> bool:
	return state == "tell"

func force_state(next_state: String) -> void:
	state = next_state
	state_time = 0.0
	queue_redraw()

func _simulate_puppet(delta: float, player_position: Vector2) -> void:
	var to_player := player_position - position
	facing = signf(to_player.x) if absf(to_player.x) > 1.0 else facing
	match state:
		"approach":
			if to_player.length() > 78.0: position += to_player.normalized() * 55.0 * delta
			else: _enter_state("tell")
		"tell":
			if state_time >= tell_seconds: _enter_state("attack")
		"attack":
			position += Vector2(facing * 105.0, 0) * delta
			if not _player_hit_this_attack and position.distance_to(player_position) < 55.0:
				_player_hit_this_attack = true
				player_struck.emit(9.0, Vector2(facing, 0))
			if state_time >= 0.20: _enter_state("recovery")
		"recovery":
			if state_time >= recovery_seconds: _enter_state("approach")

func _simulate_ram(delta: float, player_position: Vector2) -> void:
	var to_player := player_position - position
	if state != "charge": facing = signf(to_player.x) if absf(to_player.x) > 1.0 else facing
	match state:
		"hold_distance":
			var desired := 260.0
			if to_player.length() < desired - 45.0: position -= to_player.normalized() * 44.0 * delta
			elif to_player.length() > desired + 55.0: position += to_player.normalized() * 38.0 * delta
			if state_time >= 0.82: _enter_state("tell")
		"tell":
			if state_time >= tell_seconds:
				locked_direction = to_player.normalized()
				_enter_state("charge")
		"charge":
			position += locked_direction * 360.0 * delta
			if not _player_hit_this_attack and position.distance_to(player_position) < 58.0:
				_player_hit_this_attack = true
				player_struck.emit(18.0, locked_direction)
			if state_time >= 0.66 or not arena_bounds.grow(-12.0).has_point(position): _enter_state("recovery")
		"recovery":
			if state_time >= recovery_seconds: _enter_state("hold_distance")

func _enter_state(next_state: String) -> void:
	state = next_state
	state_time = 0.0
	_player_hit_this_attack = false

func _draw() -> void:
	if enemy_kind == RAM: _draw_ram()
	else: _draw_puppet()
	var ratio := clampf(health / maxf(1.0, max_health), 0.0, 1.0)
	draw_rect(Rect2(-28, -50, 56, 5), Color("14202b"), true)
	draw_rect(Rect2(-28, -50, 56 * ratio, 5), Color("6ee7a8"), true)

func _draw_puppet() -> void:
	var body := Color("fff7df") if flash_time > 0.0 else Color("514a45")
	var death_rotation := minf(dead_time * 1.8, 1.42) if state == "dead" else recoil_tilt
	draw_set_transform(Vector2.ZERO, death_rotation * facing)
	draw_colored_polygon(PackedVector2Array([Vector2(-18, -20), Vector2(15, -23), Vector2(23, 20), Vector2(-16, 25)]), body)
	draw_circle(Vector2(0, -31), 14.0, Color("8c7656"))
	draw_circle(Vector2(0, -31), 8.0, Color("272522"))
	draw_circle(Vector2(0, 1), 7.0 + (2.0 if state == "tell" else 0.0), Color("ffb23f"))
	draw_arc(Vector2(0, 1), 11.0, 0, TAU, 18, Color("fce18a"), 2.0)
	var arm_lift := -18.0 if state == "tell" else (8.0 if state == "attack" else -2.0)
	draw_line(Vector2(12, -12), Vector2(30 * facing, arm_lift), Color("b88b52"), 9.0)
	draw_circle(Vector2(31 * facing, arm_lift), 7.0, Color("d6a04f"))
	draw_line(Vector2(-8, 22), Vector2(-12, 37), Color("77675a"), 8.0)
	draw_line(Vector2(8, 22), Vector2(12, 37), Color("77675a"), 8.0)
	if state == "tell":
		draw_arc(Vector2(30 * facing, arm_lift), 15.0, 0, TAU, 20, Color("ff5a4f"), 3.0)
	draw_set_transform(Vector2.ZERO)

func _draw_ram() -> void:
	var body := Color("fff7df") if flash_time > 0.0 else Color("4b6670")
	var crouch := 9.0 if state == "tell" else 0.0
	draw_set_transform(Vector2.ZERO, recoil_tilt)
	draw_colored_polygon(PackedVector2Array([Vector2(-32, -17 + crouch), Vector2(22, -22 + crouch), Vector2(34, 14), Vector2(-28, 24)]), body)
	draw_rect(Rect2(-22, -10 + crouch, 38, 23), Color("263943"), true)
	draw_circle(Vector2(-7, 0 + crouch), 8.0, Color("ff8b3d"))
	draw_line(Vector2(23 * facing, -8 + crouch), Vector2(43 * facing, -1 + crouch), Color("e8d9ad"), 9.0)
	draw_colored_polygon(PackedVector2Array([Vector2(40 * facing, -8 + crouch), Vector2(55 * facing, -1 + crouch), Vector2(40 * facing, 6 + crouch)]), Color("ffd881"))
	draw_circle(Vector2(-19, 22), 9.0, Color("171f25"))
	draw_circle(Vector2(19, 22), 9.0, Color("171f25"))
	if state == "tell":
		draw_arc(Vector2(-7, crouch), 15.0, 0, TAU, 20, Color("ff4f40"), 4.0)
		draw_line(Vector2(50 * facing, -18), Vector2(82 * facing, -18), Color(1, 0.3, 0.2, 0.65), 4.0)
	if state == "charge":
		for index: int in range(3):
			draw_line(Vector2(-34 * facing - index * 12 * facing, -8 + index * 8), Vector2(-48 * facing - index * 12 * facing, -8 + index * 8), Color("d5f5f2"), 3.0)
	draw_set_transform(Vector2.ZERO)
