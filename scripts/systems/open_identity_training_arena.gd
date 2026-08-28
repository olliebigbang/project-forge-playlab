class_name OpenIdentityTrainingArena
extends "res://scripts/systems/gameplay_arena.gd"

# Training-only presentation for open identities. It consumes the behavior
# contract without introducing object-specific weapon classes or new families.

const FIREARM_ACTION_CHOREOGRAPHY := preload(
	"res://scripts/combat_feel/firearm_action_choreography.gd"
)

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
	var attack_range := 105.0 * float(blueprint.modifiers.get("area_multiplier", 1.0))
	for enemy: Dictionary in enemies:
		var enemy_id := int(enemy["id"])
		var direction_to_enemy: Vector2 = enemy["pos"] - player_position
		if not melee_connected.has(enemy_id) and direction_to_enemy.length() <= attack_range and signf(direction_to_enemy.x) == facing:
			melee_connected[enemy_id] = true
			var damage := RULES.damage_against(blueprint.behavior_family, enemy["type"], _is_front_hit(enemy), blueprint.modifiers)
			_damage_enemy(enemy, damage)
			if blueprint.effect_type == "lifesteal":
				player_health = minf(100.0, player_health + damage * 0.10)

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
	var body_color := Color("fb7185") if flash_timer > 0.0 else Color("67e8f9")
	draw_circle(player_position + Vector2(0, -25), 13.0, Color("dbeafe"))
	draw_rect(Rect2(player_position + Vector2(-15, -12), Vector2(30, 42)), body_color, true)
	draw_line(player_position + Vector2(-8, 30), player_position + Vector2(-13, 49), Color("94a3b8"), 7.0)
	draw_line(player_position + Vector2(8, 30), player_position + Vector2(13, 49), Color("94a3b8"), 7.0)
	var firearm_action := _firearm_action_sample()
	var root_pose := firearm_action.get("root_pose", {}) as Dictionary
	var hand_base := player_position + Vector2(19.0 * facing, -10.0)
	var hand_primary := hand_base
	var weapon_rotation := 0.0
	if _uses_firearm_runtime():
		hand_primary += root_pose.get("offset", Vector2.ZERO) as Vector2
		weapon_rotation = float(root_pose.get("rotation", 0.0))
	elif blueprint.delivery == "whole_object_strike" and melee_timer > 0.0:
		var swing_progress := clampf((0.75 - melee_timer) / 0.67, 0.0, 1.0)
		weapon_rotation = lerpf(-0.65, 0.75, swing_progress) * facing
	var relative_secondary := (asset.grip_secondary - asset.grip_primary) * 1.15
	var relative_secondary_world := Vector2(relative_secondary.x * facing, relative_secondary.y).rotated(weapon_rotation)
	var one_hand_firearm := _uses_firearm_runtime() and str(blueprint.affordance.get("support_mode", "")) == "one_hand"
	var hand_secondary := player_position + Vector2(-9.0 * facing, 12.0) if one_hand_firearm else hand_primary + relative_secondary_world
	draw_line(player_position + Vector2(0, -5), hand_primary, Color("f0c7a6"), 7.0)
	draw_line(player_position + Vector2(2, 1), hand_secondary, Color("f0c7a6"), 7.0)
	var object_is_in_flight := blueprint.delivery == "whole_object_return" and not boomerang.is_empty()
	if not object_is_in_flight:
		draw_set_transform(hand_primary, weapon_rotation, Vector2(facing, 1.0))
		var local_position := FIREARM_ACTION_CHOREOGRAPHY.weapon_origin(asset.grip_primary)
		draw_texture_rect(asset.texture, Rect2(local_position, Vector2(asset.canvas_size) * 1.15), false)
		if _uses_firearm_runtime():
			_draw_firearm_action_overlays(firearm_action, hand_primary, weapon_rotation)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_circle(hand_primary, 7.0, Color("5eead4"), false, 2.0)
	draw_circle(hand_primary, 4.0, Color("f8d8b9"))
	draw_circle(hand_secondary, 4.0, Color("f8d8b9"))
	draw_line(player_position + Vector2(0, -30), player_position + Vector2(18.0 * facing, -30), Color("fef08a"), 3.0)
	if debug_anchors and not object_is_in_flight:
		if _uses_firearm_runtime():
			_draw_firearm_world_anchor(hand_base, asset.grip_primary, root_pose, "GripPrimary", Color("5eead4"))
			_draw_firearm_world_anchor(hand_base, asset.grip_secondary, root_pose, "GripSecondary", Color("facc15"))
			_draw_firearm_world_anchor(hand_base, asset.muzzle, root_pose, "EffectOrigin", Color("38bdf8"))
			_draw_firearm_world_anchor(hand_base, asset.tip, root_pose, "StrikePoint", Color("fb7185"))
		else:
			_draw_world_anchor(hand_primary, asset.grip_primary, asset.grip_primary, "GripPrimary", Color("5eead4"))
			_draw_world_anchor(hand_primary, asset.grip_secondary, asset.grip_primary, "GripSecondary", Color("facc15"))
			_draw_world_anchor(hand_primary, asset.muzzle, asset.grip_primary, "EffectOrigin", Color("38bdf8"))
			_draw_world_anchor(hand_primary, asset.tip, asset.grip_primary, "StrikePoint", Color("fb7185"))
			_draw_world_anchor(hand_primary, asset.spin_pivot, asset.grip_primary, "SpinPivot", Color("c084fc"))


func _muzzle_world() -> Vector2:
	if not _uses_firearm_runtime() or asset == null:
		return super._muzzle_world()
	var action := _firearm_action_sample()
	return FIREARM_ACTION_CHOREOGRAPHY.world_anchor(
		player_position + Vector2(19.0 * facing, -10.0),
		asset.muzzle,
		asset.grip_primary,
		action.get("root_pose", {}) as Dictionary
	)


func _firearm_action_sample() -> Dictionary:
	if not _uses_firearm_runtime():
		return {}
	return FIREARM_ACTION_CHOREOGRAPHY.sample(
		ranged_runtime_profile,
		{
			"recoil_pixels": weapon_recoil_offset,
			"muzzle_climb_degrees": weapon_muzzle_climb_degrees,
			"cycle_timer": manual_cycle_timer,
			"reload_timer": reload_timer,
			"muzzle_flash_timer": muzzle_flash_timer,
		},
		{
			"ammo_in_magazine": ammo_in_magazine,
			"magazine_size": int(ranged_runtime_profile.get("magazine_size", 1)),
		},
		facing
	)


func _draw_firearm_world_anchor(
	hand_base: Vector2,
	point: Vector2,
	root_pose: Dictionary,
	label: String,
	color: Color
) -> void:
	var world := FIREARM_ACTION_CHOREOGRAPHY.world_anchor(
		hand_base,
		point,
		asset.grip_primary,
		root_pose
	)
	draw_circle(world, 5.0, color)
	draw_string(ThemeDB.fallback_font, world + Vector2(6, -5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)


func _draw_firearm_action_overlays(action: Dictionary, hand: Vector2, root_rotation: float) -> void:
	_draw_cycle_overlay(action.get("cycle_overlay_pose", {}) as Dictionary, hand, root_rotation)
	_draw_reload_object(action.get("reload_object_pose", {}) as Dictionary, hand, root_rotation)
	_draw_ejected_case(action.get("ejection_pose", {}) as Dictionary, hand, root_rotation)


func _draw_cycle_overlay(pose: Dictionary, hand: Vector2, root_rotation: float) -> void:
	if not bool(pose.get("visible", false)):
		return
	var local_position := Vector2(7.0, -8.0) + (pose.get("local_position", Vector2.ZERO) as Vector2)
	var position := hand + Vector2(local_position.x * facing, local_position.y).rotated(root_rotation)
	draw_set_transform(position, root_rotation + float(pose.get("rotation", 0.0)) * facing, Vector2(facing, 1.0))
	match str(pose.get("kind", "")):
		"self_loading_bolt":
			draw_rect(Rect2(-5, -2, 10, 4), Color("d7e1e8"), true)
		"bolt_handle":
			draw_line(Vector2(-2, 0), Vector2(6, 6), Color("d7e1e8"), 3.0)
			draw_circle(Vector2(7, 7), 3.0, Color("7d8b96"))
		"pump_fore_end":
			draw_rect(Rect2(16, 8, 22, 9), Color("8b5a36"), true)
			draw_line(Vector2(18, 11), Vector2(36, 11), Color("c58a54"), 2.0)
		"cylinder_index":
			draw_circle(Vector2.ZERO, 8.0, Color("343e47"))
			for angle: float in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
				draw_circle(Vector2.from_angle(angle) * 4.0, 1.5, Color("9eabb4"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_reload_object(pose: Dictionary, hand: Vector2, root_rotation: float) -> void:
	if not bool(pose.get("visible", false)):
		return
	var local_position := pose.get("local_position", Vector2.ZERO) as Vector2
	var position := hand + Vector2(local_position.x * facing, local_position.y).rotated(root_rotation)
	draw_set_transform(position, root_rotation + float(pose.get("rotation", 0.0)) * facing, Vector2(facing, 1.0))
	match str(pose.get("kind", "")):
		"magazine":
			draw_rect(Rect2(-5, -10, 10, 22), Color("252c33"), true)
			draw_line(Vector2(-3, -7), Vector2(3, 8), Color("77838d"), 2.0)
		"single_round":
			draw_rect(Rect2(-6, -2, 10, 4), Color("c7893d"), true)
			draw_circle(Vector2(5, 0), 2.0, Color("e7c15d"))
		"speedloader":
			draw_circle(Vector2.ZERO, 8.0, Color("b5c0c8"), false, 3.0)
			for angle: float in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
				draw_circle(Vector2.from_angle(angle) * 4.0, 2.0, Color("d49a42"))
		"belt_box":
			draw_rect(Rect2(-10, -7, 20, 16), Color("46523d"), true)
			for index: int in range(4):
				draw_circle(Vector2(-8 + index * 5, -10), 2.0, Color("d49a42"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_ejected_case(pose: Dictionary, hand: Vector2, root_rotation: float) -> void:
	if not bool(pose.get("visible", false)):
		return
	var local_position := pose.get("local_position", Vector2.ZERO) as Vector2
	var position := hand + Vector2(local_position.x * facing, local_position.y).rotated(root_rotation)
	draw_set_transform(position, root_rotation + float(pose.get("rotation", 0.0)) * facing, Vector2(facing, 1.0))
	var size := Vector2(8, 4) if str(pose.get("kind", "")) == "spent_shell" else Vector2(6, 3)
	draw_rect(Rect2(-size * 0.5, size), Color("d49a42"), true)
	if str(pose.get("kind", "")) == "spent_casing_cluster":
		draw_rect(Rect2(Vector2(-2, 4), size), Color("d49a42"), true)
		draw_rect(Rect2(Vector2(3, -3), size), Color("d49a42"), true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

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
	if blueprint.delivery == "whole_object_strike" and melee_timer > 0.08 and melee_timer < 0.34:
		var strike_color := Color("fb7185") if blueprint.effect_type == "lifesteal" else Color("fbbf24")
		draw_arc(player_position, 104.0, -0.8 if facing > 0 else PI - 0.8, 0.8 if facing > 0 else PI + 0.8, 24, strike_color, 8.0)
	if blueprint.delivery == "continuous_emission" and attack_charge > 0.0:
		var effect_origin := _muzzle_world()
		draw_arc(effect_origin, 6.0 + minf(attack_charge, 0.35) * 15.0, 0.0, TAU, 16, Color("5eead4"), 3.0)
	if muzzle_flash_timer > 0.0:
		var flash_muzzle := _muzzle_world()
		var flash_pose := (_firearm_action_sample().get("flash_pose", {}) as Dictionary)
		var flash_scale := flash_pose.get("scale", Vector2.ONE) as Vector2
		draw_colored_polygon(PackedVector2Array([
			flash_muzzle + Vector2(0, -7.0 * flash_scale.y),
			flash_muzzle + Vector2(17.0 * facing * flash_scale.x, 0),
			flash_muzzle + Vector2(0, 7.0 * flash_scale.y),
			flash_muzzle + Vector2(5.0 * facing * flash_scale.x, 0),
		]), Color("fde047"))
