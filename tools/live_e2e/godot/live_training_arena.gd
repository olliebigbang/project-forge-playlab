class_name LiveE2ETrainingArena
extends "res://scripts/systems/open_identity_training_arena.gd"

# Spike 7 only adds schema-v1.1 effect presentation.  Attack behavior, targets,
# timing and values continue to come from the existing training arena.

func _draw_attacks() -> void:
	super._draw_attacks()
	if blueprint == null:
		return
	match blueprint.effect_type:
		"ice": _draw_ice_mist()
		"fire": _draw_fire_effect()
		"electric": _draw_electric_effect()
		"steam": _draw_steam_effect()
		"poison": _draw_poison_effect()
		"light": _draw_light_effect()

func _draw_ice_mist() -> void:
	if blueprint.delivery == "continuous_emission" and attack_charge > 0.0:
		var origin := _muzzle_world()
		var clock := float(Time.get_ticks_msec()) * 0.005
		for index: int in range(7):
			var phase := clock + float(index) * 0.83
			var offset := Vector2(facing * (10.0 + index * 8.0), sin(phase) * (4.0 + index))
			draw_circle(origin + offset, 5.0 + float(index) * 0.75, Color(0.64, 0.91, 1.0, 0.20))
	for projectile: Dictionary in projectiles:
		draw_circle(Vector2(projectile["pos"]), 9.0, Color(0.73, 0.94, 1.0, 0.30))

func _draw_fire_effect() -> void:
	for projectile: Dictionary in projectiles:
		draw_circle(Vector2(projectile["pos"]), 8.0, Color(1.0, 0.42, 0.16, 0.45))

func _draw_electric_effect() -> void:
	for projectile: Dictionary in projectiles:
		var point := Vector2(projectile["pos"])
		draw_polyline(PackedVector2Array([point + Vector2(-9, -4), point, point + Vector2(9, 4)]), Color("67e8f9"), 3.0)

func _draw_steam_effect() -> void:
	for projectile: Dictionary in projectiles:
		draw_circle(Vector2(projectile["pos"]), 10.0, Color(0.9, 0.94, 0.96, 0.24))

func _draw_poison_effect() -> void:
	for projectile: Dictionary in projectiles:
		draw_circle(Vector2(projectile["pos"]), 8.0, Color(0.36, 0.9, 0.42, 0.45))

func _draw_light_effect() -> void:
	for projectile: Dictionary in projectiles:
		draw_circle(Vector2(projectile["pos"]), 10.0, Color(1.0, 0.95, 0.55, 0.35))

func live_attack_visible() -> bool:
	match blueprint.behavior_family if blueprint != null else "":
		"returning_thrown": return not boomerang.is_empty()
		"heavy_melee": return melee_timer > 0.0
		_: return attack_charge >= 0.34 or not projectiles.is_empty()
