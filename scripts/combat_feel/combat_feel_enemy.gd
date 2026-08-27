class_name CombatFeelEnemy
extends Node2D

signal player_struck(damage: float, direction: Vector2)
signal defeated(enemy: Node2D)
signal mechanism_applied(enemy: Node2D, verb: String, status: String)

const ATTACK_RUNTIME := preload("res://scripts/enemy_attack/enemy_attack_runtime_driver.gd")
const PUPPET := "slag_puppet"
const RAM := "forge_ram"

const PUPPET_ATTACK_DECLARATIONS := [{
	"attack_key": "slot_contact_arc",
	"axes": {
		"delivery": "contact", "target_lock": "live_until_active",
		"hit_shape": "arc", "depth_path": "same_lane", "tempo": "standard",
		"stability": "fragile", "recovery": "punishable",
	},
	"selection": {
		"preferred_range": "close", "depth_fit": "aligned", "base_priority": 60,
		"coordination_cost": 1, "requires_clear_path": false, "selection_rank": 10,
	},
}]
const RAM_ATTACK_DECLARATIONS := [{
	"attack_key": "slot_locked_rush",
	"axes": {
		"delivery": "rush", "target_lock": "direction_on_commit",
		"hit_shape": "strip", "depth_path": "cross_depth", "tempo": "committed",
		"stability": "armored_commit", "recovery": "extended",
	},
	"selection": {
		"preferred_range": "mid", "depth_fit": "tolerant", "base_priority": 70,
		"coordination_cost": 1, "requires_clear_path": true, "selection_rank": 10,
	},
}]

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
var mechanism_status := ""
var mechanism_status_time := 0.0
var last_mechanism_verb := "none"
var target_mass_class := "medium"
var armor_integrity := 0.0
var last_target_interaction: Dictionary = {}
var attack_runtime: RefCounted = ATTACK_RUNTIME.new()
var compiled_attacks_ready := false
var _player_hit_this_attack := false

func setup(kind: String, id_value: int, spawn_position: Vector2) -> void:
	enemy_kind = kind
	enemy_id = id_value
	position = spawn_position
	if enemy_kind == RAM:
		max_health = 150.0
		health = 150.0
		target_mass_class = "heavy"
		armor_integrity = 0.65
		state = "hold_distance"
		tell_seconds = 0.72
		recovery_seconds = 1.05
	else:
		max_health = 78.0
		health = 78.0
		target_mass_class = "medium"
		armor_integrity = 0.0
		state = "approach"
		tell_seconds = 0.48
		recovery_seconds = 0.62
	var declarations: Array = RAM_ATTACK_DECLARATIONS if enemy_kind == RAM else PUPPET_ATTACK_DECLARATIONS
	var configured: Dictionary = attack_runtime.configure(declarations)
	compiled_attacks_ready = bool(configured.get("ok", false))
	if compiled_attacks_ready:
		tell_seconds = attack_runtime.telegraph_total_seconds()
		recovery_seconds = attack_runtime.recovery_total_seconds()
	queue_redraw()

func simulate(delta: float, player_position: Vector2, frozen: bool = false) -> void:
	flash_time = maxf(0.0, flash_time - delta)
	recoil_visual_time = maxf(0.0, recoil_visual_time - delta)
	mechanism_status_time = maxf(0.0, mechanism_status_time - delta)
	if mechanism_status_time <= 0.0 and not mechanism_status.is_empty():
		mechanism_status = ""
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
	if attack_runtime.is_running():
		_simulate_compiled_attack(delta, player_position)
		position.x = clampf(position.x, arena_bounds.position.x + 24.0, arena_bounds.end.x - 24.0)
		position.y = clampf(position.y, arena_bounds.position.y + 35.0, arena_bounds.end.y - 20.0)
		queue_redraw()
		return
	if enemy_kind == RAM: _simulate_ram(delta, player_position)
	else: _simulate_puppet(delta, player_position)
	position.x = clampf(position.x, arena_bounds.position.x + 24.0, arena_bounds.end.x - 24.0)
	position.y = clampf(position.y, arena_bounds.position.y + 35.0, arena_bounds.end.y - 20.0)
	queue_redraw()

func apply_hit(
	damage: float,
	knockback: Vector2,
	stagger_strength: float,
	recoil_degrees: float = 7.0,
	mechanism: Dictionary = {}
) -> bool:
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
	elif not mechanism.is_empty():
		_apply_mechanism(mechanism)
	queue_redraw()
	return true


func _apply_mechanism(mechanism: Dictionary) -> void:
	last_target_interaction = mechanism.duplicate(true)
	last_mechanism_verb = str(mechanism.get("verb", "none"))
	mechanism_status = str(mechanism.get("status", ""))
	mechanism_status_time = maxf(0.0, float(mechanism.get("status_seconds", 0.0)))
	var armor_before := armor_integrity
	armor_integrity = maxf(0.0, armor_integrity - float(mechanism.get("armor_damage", 0.0)))
	if bool(mechanism.get("armor_break", false)) or (armor_before > 0.0 and armor_integrity <= 0.0):
		last_mechanism_verb = "armor_break"
		mechanism_status = "ARMOR BROKEN"
		mechanism_status_time = maxf(mechanism_status_time, 0.72)
	if bool(mechanism.get("immobilize", false)):
		velocity = Vector2.ZERO
	if bool(mechanism.get("control_lock", false)):
		velocity *= 0.35
	stagger_time = maxf(stagger_time, float(mechanism.get("stagger_seconds", 0.0)))
	stagger_time = maxf(stagger_time, mechanism_status_time)
	recoil_visual_time = maxf(recoil_visual_time, mechanism_status_time)
	var runtime_interrupt := {"interrupted": false}
	if attack_runtime.is_running():
		runtime_interrupt = attack_runtime.try_interrupt(mechanism)
	if bool(runtime_interrupt.get("interrupted", false)):
		_set_runtime_state("recovery")
	elif attack_runtime.is_running() and str(runtime_interrupt.get("reason", "")) == "PHASE_PROTECTED":
		# The hit still deals damage and can move the target, but a protected
		# committed phase is not silently converted into a cancelled attack.
		stagger_time = minf(stagger_time, 0.05)
	elif bool(mechanism.get("interrupts_attack", false)) and state in ["tell", "attack", "charge"]:
		_enter_state("recovery")
	mechanism_applied.emit(self, last_mechanism_verb, mechanism_status)


func target_interaction_context() -> Dictionary:
	return {
		"mass_class": target_mass_class,
		"armor_integrity": armor_integrity,
		"state": attack_runtime.phase if attack_runtime.is_running() else state,
	}

func is_attack_dangerous() -> bool:
	return attack_runtime.is_attack_dangerous() if attack_runtime.is_running() else state in ["attack", "charge"]

func is_telegraphing() -> bool:
	return attack_runtime.is_telegraphing() if attack_runtime.is_running() else state == "tell"

func force_state(next_state: String) -> void:
	attack_runtime.reset()
	state = next_state
	state_time = 0.0
	queue_redraw()

func _simulate_puppet(delta: float, player_position: Vector2) -> void:
	var to_player := player_position - position
	facing = signf(to_player.x) if absf(to_player.x) > 1.0 else facing
	match state:
		"approach":
			if to_player.length() > 78.0: position += to_player.normalized() * 55.0 * delta
			elif not _begin_compiled_attack(player_position): _enter_state("tell")
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
			if state_time >= 0.82 and not _begin_compiled_attack(player_position): _enter_state("tell")
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


func _begin_compiled_attack(player_position: Vector2) -> bool:
	if not compiled_attacks_ready:
		return false
	var to_player := player_position - position
	var selected: Dictionary = attack_runtime.begin_attack({
		"distance_pixels": to_player.length(),
		"depth_delta_pixels": to_player.y,
		"available_coordination_budget": 1,
		"clear_path": true,
	}, position, player_position)
	if not bool(selected.get("ok", false)):
		return false
	locked_direction = Vector2(selected.get("locked_direction", locked_direction))
	tell_seconds = attack_runtime.telegraph_total_seconds()
	recovery_seconds = attack_runtime.recovery_total_seconds()
	_set_runtime_state("tell")
	return true


func _simulate_compiled_attack(delta: float, player_position: Vector2) -> void:
	var result: Dictionary = attack_runtime.step(delta, position, player_position)
	locked_direction = Vector2(result.get("locked_direction", locked_direction))
	var delivery := str(result.get("delivery", attack_runtime.current_delivery()))
	match str(result.get("phase", "idle")):
		"telegraph", "commit": _set_runtime_state("tell")
		"active": _set_runtime_state("charge" if delivery == "rush" else "attack")
		"recovery": _set_runtime_state("recovery")
		"idle": _set_runtime_state("hold_distance" if enemy_kind == RAM else "approach")
	var active_seconds := float(result.get("active_seconds_this_step", 0.0))
	if active_seconds > 0.0:
		var motion := result.get("attack_motion", {}) as Dictionary
		if delivery == "rush":
			position += locked_direction * float(motion.get("travel_speed_pixels_per_second", 0.0)) * active_seconds
		if not attack_runtime.active_hit_registered and attack_runtime.current_hit_contains(position, player_position):
			attack_runtime.register_active_hit()
			var damage: float = float({"contact": 9.0, "rush": 18.0, "projectile": 11.0, "marked_impact": 14.0}.get(delivery, 9.0))
			player_struck.emit(float(damage), locked_direction)
	if delivery == "rush" and attack_runtime.phase == "active" and not arena_bounds.grow(-12.0).has_point(position):
		attack_runtime.force_recovery("arena_boundary")
		_set_runtime_state("recovery")


func _set_runtime_state(next_state: String) -> void:
	if state != next_state:
		state = next_state
		state_time = 0.0
		_player_hit_this_attack = false

func _draw() -> void:
	if enemy_kind == RAM: _draw_ram()
	else: _draw_puppet()
	_draw_compiled_attack_preview()
	var ratio := clampf(health / maxf(1.0, max_health), 0.0, 1.0)
	draw_rect(Rect2(-28, -50, 56, 5), Color("14202b"), true)
	draw_rect(Rect2(-28, -50, 56 * ratio, 5), Color("6ee7a8"), true)
	_draw_mechanism_status()


func _draw_compiled_attack_preview() -> void:
	if not attack_runtime.is_telegraphing() or attack_runtime.current_attack.is_empty():
		return
	var region := attack_runtime.current_attack.get("hit_region", {}) as Dictionary
	var color := Color(1.0, 0.28, 0.20, 0.62)
	var direction: Vector2 = Vector2(attack_runtime.locked_direction).normalized()
	var angle: float = direction.angle()
	match str(region.get("shape", "capsule")):
		"arc":
			var half_arc := deg_to_rad(float(region.get("arc_degrees", 0.0)) * 0.5)
			draw_arc(Vector2.ZERO, float(region.get("radius_pixels", 0.0)), angle - half_arc, angle + half_arc, 24, color, 4.0)
		"circle":
			var local_point: Vector2 = Vector2(attack_runtime.locked_point) - position
			draw_circle(local_point, float(region.get("radius_pixels", 0.0)), color, false, 4.0)
		"strip", "capsule":
			var length := float(region.get("length_pixels", 0.0))
			var half_width := float(region.get("width_pixels", 0.0)) * 0.5
			var side: Vector2 = direction.orthogonal() * half_width
			draw_line(side, direction * length + side, color, 3.0)
			draw_line(-side, direction * length - side, color, 3.0)
			draw_line(direction * length + side, direction * length - side, color, 3.0)


func _draw_mechanism_status() -> void:
	if mechanism_status.is_empty():
		return
	var color := Color("e2e8f0")
	match last_mechanism_verb:
		"pin":
			color = Color("22d3ee")
			draw_line(Vector2(-13, 25), Vector2(-13, 42), color, 3.0)
			draw_line(Vector2(13, 25), Vector2(13, 42), color, 3.0)
		"cleave":
			color = Color("fb7185")
			draw_line(Vector2(-28, 17), Vector2(27, -24), color, 4.0)
		"shove":
			color = Color("facc15")
			draw_line(Vector2(-38 * facing, 2), Vector2(-58 * facing, 2), color, 5.0)
			draw_colored_polygon(PackedVector2Array([
				Vector2(-58 * facing, 2), Vector2(-48 * facing, -6), Vector2(-48 * facing, 10),
			]), color)
		"sweep_control":
			color = Color("c084fc")
			draw_arc(Vector2.ZERO, 43.0, 0.0, TAU, 32, color, 4.0)
		"entangle":
			color = Color("c084fc")
			draw_arc(Vector2.ZERO, 38.0, 0.0, TAU, 28, color, 4.0)
			draw_arc(Vector2.ZERO, 29.0, 0.0, TAU, 24, color, 3.0)
		"hook_pull":
			color = Color("22d3ee")
			draw_line(Vector2(-42 * facing, 0), Vector2(-12 * facing, 0), color, 4.0)
			draw_colored_polygon(PackedVector2Array([
				Vector2(-42 * facing, 0), Vector2(-31 * facing, -8), Vector2(-31 * facing, 8),
			]), color)
		"suppress":
			color = Color("f59e0b")
			for offset: float in [-9.0, 0.0, 9.0]:
				draw_line(Vector2(-34, -29 + offset), Vector2(34, -29 + offset), color, 2.0)
		"armor_break":
			color = Color("fb7185")
			draw_line(Vector2(-22, -21), Vector2(5, 6), color, 4.0)
			draw_line(Vector2(5, 6), Vector2(-3, 23), color, 4.0)
		"stagger":
			color = Color("facc15")
			draw_arc(Vector2.ZERO, 34.0, -2.7, -0.4, 18, color, 3.0)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(-56, -58),
		mechanism_status,
		HORIZONTAL_ALIGNMENT_CENTER,
		112,
		14,
		color
	)

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
