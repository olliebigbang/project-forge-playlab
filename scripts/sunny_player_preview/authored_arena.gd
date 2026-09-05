extends "res://scripts/authored_player/arena.gd"
const BACKGROUND := preload("res://assets/sunny_arena_preview_v1/clearing_generated_v3.png")
const FROG := preload("res://assets/sunny_arena_preview_v1/frog_idle.png")
const FLOOR := Rect2(140, 424, 1000, 216)
var damage_delivered := 0.0
var target_damage: Dictionary = {}
var frog_image: Image

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frog_image = FROG.get_image()

func start_stage(next_stage: String, next_blueprint: WeaponBlueprint, next_asset: WeaponVisualAsset, next_enemies: Array[Dictionary] = []) -> void:
	damage_delivered = 0; target_damage.clear()
	super.start_stage(next_stage, next_blueprint, next_asset, next_enemies)
	player_position = Vector2(400, 558); facing = 1

func _update_player(delta: float) -> void:
	super._update_player(delta)
	player_position = (player_position + FEET_OFFSET).clamp(FLOOR.position, FLOOR.end) - FEET_OFFSET

func _spawn_stage() -> void:
	enemies.clear()
	_spawn_enemy("target", Vector2(780, 504), 150)
	_spawn_enemy("target", Vector2(980, 558), 150)

func _face_nearest_enemy_for_attack() -> void:
	pass # Keep both facing directions inspectable in this practice room.

func _damage_enemy(enemy: Dictionary, amount: float, hurt_seconds: float = 0.12) -> void:
	damage_delivered += amount
	target_damage[str(enemy.id)] = float(target_damage.get(str(enemy.id), 0)) + amount
	super._damage_enemy(enemy, amount, hurt_seconds)

func _projectile_contacts_enemy(start: Vector2, finish: Vector2, projectile: Dictionary, enemy: Dictionary) -> bool:
	if projectile.has("ground_lane_y") and absf(float(projectile.ground_lane_y) - Vector2(enemy.pos).y) > 30: return false
	# Static third native frame, exactly as the accepted original-action sample.
	# Collision samples the visible alpha, not a taller invisible capsule.
	var feet := Vector2(enemy.pos) + FEET_OFFSET
	var radius := maxf(1, float(projectile.get("projectile_radius_pixels", 1)))
	var steps := maxi(1, ceili(start.distance_to(finish) / 2))
	if frog_image == null: frog_image = FROG.get_image()
	for i: int in range(steps + 1):
		var point := start.lerp(finish, float(i) / steps)
		for offset: Vector2 in [Vector2.ZERO, Vector2(0, radius), Vector2(0, -radius)]:
			var pixel := Vector2i(((point + offset - feet) / 3 + Vector2(16, 27)).floor())
			if Rect2i(0, 0, 32, 32).has_point(pixel) and frog_image.get_pixelv(pixel + Vector2i(64, 0)).a > 0.5: return true
	return false

func _draw() -> void:
	draw_texture_rect(BACKGROUND, Rect2(0, 0, 1280, 720), false)
	if blueprint == null: return
	var units: Array[Dictionary] = [{"player": true, "y": player_position.y}]
	for enemy: Dictionary in enemies: units.append({"player": false, "y": Vector2(enemy.pos).y, "enemy": enemy})
	units.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.y) < float(b.y))
	for unit: Dictionary in units:
		if unit.player: _draw_player_and_weapon()
		else:
			var enemy: Dictionary = unit.enemy
			var feet := Vector2(enemy.pos) + FEET_OFFSET
			draw_texture_rect_region(FROG, Rect2(feet - Vector2(48, 81), Vector2(96, 96)), Rect2(64, 0, 32, 32))
			draw_rect(Rect2(feet + Vector2(-30, -80), Vector2(60, 4)), Color("314b45"))
			draw_rect(Rect2(feet + Vector2(-30, -80), Vector2(60 * float(enemy.hp) / float(enemy.max_hp), 4)), Color("77be78"))
	_draw_attacks()

func _check_completion(_delta: float) -> void:
	pass # Recoverable practice targets, not a campaign completion shortcut.
