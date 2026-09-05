class_name OpenIdentityTrainingArena
extends "res://scripts/systems/gameplay_arena.gd"

# Training-only presentation for open identities. It consumes the behavior
# contract without introducing object-specific weapon classes or new families.

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
			if blueprint.effect_type == "electric_current":
				_chain_damage(enemy, 8.0)

func _update_melee_attack(just_pressed: bool, delta: float, held: bool = false) -> void:
	super._update_melee_attack(just_pressed, delta, held)


func _update_projectiles(delta: float) -> void:
	for projectile: Dictionary in projectiles:
		var travel_step := Vector2(projectile["vel"]) * delta
		projectile["pos"] = Vector2(projectile["pos"]) + travel_step
		projectile["distance_travelled"] = float(projectile.get("distance_travelled", 0.0)) + travel_step.length()
		projectile["life"] = float(projectile["life"]) - delta
		for enemy: Dictionary in enemies:
			var enemy_id := int(enemy["id"])
			var hit: Dictionary = projectile["hit"]
			if not hit.has(enemy_id) and Vector2(projectile["pos"]).distance_to(enemy["pos"]) < 23.0:
				hit[enemy_id] = true
				_resolve_projectile_hit(projectile, enemy)
				match blueprint.effect_type:
					"thermal_emission": enemy["burn"] = 2.2
					"electric_current": _chain_damage(enemy, 6.0)
				if int(projectile["pierces"]) > 0:
					projectile["pierces"] = int(projectile["pierces"]) - 1
				else:
					projectile["life"] = 0.0
	projectiles = projectiles.filter(func(projectile: Dictionary) -> bool:
		return float(projectile["life"]) > 0.0 and WORLD_RECT.grow(80).has_point(projectile["pos"])
	)

func _draw_player_and_weapon() -> void:
	super._draw_player_and_weapon()


func _draw_attacks() -> void:
	for projectile: Dictionary in projectiles:
		var position: Vector2 = projectile["pos"]
		match blueprint.effect_type:
			"ballistic_projectile":
				var velocity: Vector2 = projectile.get("vel", Vector2(facing, 0.0))
				var direction := velocity.normalized() if velocity.length() > 0.001 else Vector2(facing, 0.0)
				var radius := float(projectile.get("projectile_radius_pixels", 3.0))
				var tracer_width := float(projectile.get("tracer_width_pixels", 3.0))
				var tracer_length := float(projectile.get("tracer_length_pixels", 14.0))
				draw_line(position - direction * tracer_length, position + direction * radius, Color("f8fafc"), tracer_width)
				draw_circle(position + direction * radius, radius, Color("fde047"))
			"forge_fastener":
				draw_line(position - Vector2(8.0 * facing, 0), position + Vector2(7.0 * facing, 0), Color("cbd5e1"), 4.0)
				draw_circle(position - Vector2(7.0 * facing, 0), 4.0, Color("64748b"))
			"thermal_emission":
				draw_circle(position, 11.0, Color(0.88, 0.94, 1.0, 0.22))
				draw_arc(position, 8.0, 0.0, TAU, 12, Color("e2e8f0"), 3.0)
			"electric_current":
				var direction := Vector2(12.0 * facing, 0)
				draw_polyline(PackedVector2Array([
					position - direction,
					position + Vector2(-3.0 * facing, -6),
					position + Vector2(3.0 * facing, 5),
					position + direction
				]), Color("67e8f9"), 3.0)
			_:
				draw_colored_polygon(PackedVector2Array([
					position + Vector2(0, -6), position + Vector2(7, 0),
					position + Vector2(0, 6), position + Vector2(-7, 0)
				]), Color("a78bfa"))
	if not boomerang.is_empty():
		var object_position: Vector2 = boomerang["pos"]
		var spin := float(Time.get_ticks_msec()) / 125.0 * float(boomerang.get("direction", 1.0))
		draw_set_transform(object_position, spin, Vector2(0.82, 0.82))
		draw_texture_rect(asset.texture, Rect2(-asset.spin_pivot, Vector2(asset.canvas_size)), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_arc(object_position, 32.0, 0.0, TAU, 24, Color(0.36, 0.91, 0.83, 0.55), 2.0)
	if blueprint.delivery == "continuous_emission" and attack_charge > 0.0:
		var effect_origin := _muzzle_world()
		draw_arc(effect_origin, 6.0 + minf(attack_charge, 0.35) * 15.0, 0.0, TAU, 16, Color("5eead4"), 3.0)
	_draw_firearm_muzzle_flash()
