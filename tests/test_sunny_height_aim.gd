extends SceneTree
const ARENA := preload("res://scripts/sunny_player_preview/arena.gd")
const LIBRARY := preload("res://scripts/art_vertical_slice_v1/expedition_library.gd")
var cases: Array[Dictionary] = []
var checks: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(834705)
	var arena := ARENA.new()
	root.add_child(arena)
	var entries: Array[Dictionary] = LIBRARY.new().load_all(false)
	for entry: Dictionary in entries:
		arena.start_stage("training", entry.blueprint, entry.asset)
		arena.set_process(false)
		if not arena._uses_firearm_runtime(): continue
		for face: float in [-1.0, 1.0]:
			for ground_y: float in [516.0, 572.0, 592.0]:
				for distance: float in [80.0, 140.0, 300.0, 650.0]:
					arena.start_stage("training", entry.blueprint, entry.asset)
					arena.set_process(false)
					arena.player_position = Vector2(1100 if face < 0 else 180, ground_y)
					arena.facing = face
					arena.enemies.clear()
					arena._spawn_enemy("target", arena.player_position + Vector2(distance * face, 0), 10000)
					var target: Dictionary = arena.enemies[0]
					arena._update_height_aim()
					var muzzle := arena._muzzle_world()
					var angle := arena._firearm_recoil_rotation()
					var ray := Vector2(face, 0).rotated(angle)
					var center := arena._target_body_center(target)
					var error := arena._distance_to_segment(center, muzzle, muzzle + ray * 1200)
					var visual_angle: float = arena._firearm_action_sample().root_pose.rotation
					arena._fire_bullet()
					var emitted: Dictionary = arena.projectiles[0].duplicate(true)
					var lane_y := ground_y + 56
					var other := target.duplicate(true)
					other.pos = Vector2(target.pos.x, lane_y)
					var offlane_rejected := not arena._projectile_contacts_enemy(Vector2(other.pos) - Vector2(100, 0), Vector2(other.pos) + Vector2(100, 0), emitted, other)
					for tick: int in range(180):
						arena._update_projectiles(1.0 / 60)
						if arena.projectiles.is_empty(): break
					var result := {"name": entry.blueprint.display_name, "facing": face, "ground_y": ground_y, "distance": distance, "aim_degrees": rad_to_deg(angle), "ray_error": error, "muzzle_origin_error": Vector2(emitted.origin).distance_to(muzzle), "visual_angle_error": absf(angle - visual_angle), "damage": arena.damage_delivered, "offlane_rejected": offlane_rejected}
					result.passed = error < 24 and result.muzzle_origin_error < 0.001 and result.visual_angle_error < 0.001 and result.damage > 0 and offlane_rejected
					cases.append(result)
	var picker_enemies: Array[Dictionary] = [{"id": "behind", "pos": Vector2(-50, 0), "hp": 10}, {"id": "offlane", "pos": Vector2(50, 56), "hp": 10}, {"id": "dead", "pos": Vector2(70, 0), "hp": 0}]
	checks.append({"name": "no_backward_offlane_or_dead_lock", "passed": arena.LANE_AIM.select_target(Vector2.ZERO, 1, picker_enemies).is_empty()})
	picker_enemies.append({"id": "valid", "pos": Vector2(200, 0), "hp": 10})
	checks.append({"name": "select_same_ground_lane", "passed": arena.LANE_AIM.select_target(Vector2.ZERO, 1, picker_enemies).get("id", "") == "valid"})
	var passed := cases.size() == 48
	for item: Dictionary in cases: passed = passed and item.passed
	for item: Dictionary in checks: passed = passed and item.passed
	var report := {"passed": passed, "cases": cases, "checks": checks, "source": "offline real runtime projectiles, seeded spread", "live_ai_calls": 0}
	var file := FileAccess.open("res://.tools/sunny-player/height-aim.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SUNNY_HEIGHT_AIM ", JSON.stringify(report))
	arena.queue_free()
	quit(0 if passed else 1)
