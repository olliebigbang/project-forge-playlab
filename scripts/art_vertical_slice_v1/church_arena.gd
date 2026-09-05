extends "res://scripts/authored_player/arena.gd"
## Church presentation adapter. Combat, anchors, weapon pixels and enemy attack
## clocks remain owned by GameplayArena. Background/enemy sheets are CC0;
## native player motion uses the separately licensed Dead Revolver source.
const CHURCH := preload("res://assets/art_vertical_slice_v1/church_backgrounds.png")
const COLUMN := preload("res://assets/art_vertical_slice_v1/church_column.png")
const TILES := preload("res://assets/art_vertical_slice_v1/church_tileset.png")
const PLAYER_WALK := preload("res://assets/art_vertical_slice_v1/player_walk.png")
const PLAYER_HURT := preload("res://assets/art_vertical_slice_v1/player_hurt.png")
const WIZARD_IDLE := preload("res://assets/art_vertical_slice_v1/wizard_idle.png")
const WIZARD_FIRE := preload("res://assets/art_vertical_slice_v1/wizard_fire.png")
const GHOUL_RUN := preload("res://assets/art_vertical_slice_v1/ghoul_run.png")
const GHOUL_RUSH := preload("res://assets/art_vertical_slice_v1/ghoul_rush.png")
const WALK_AREA := Rect2(100, 335, 1080, 265)
var player_walk_clock := 0.0
var player_is_moving := false
var enemy_is_moving: Dictionary = {}
var drawing_depth_sorted_units := false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _update_player(delta: float) -> void:
	var previous := player_position
	super._update_player(delta)
	player_position = _clamp_to_floor(player_position)
	player_is_moving = player_position.distance_to(previous) > 0.1
	if player_is_moving: player_walk_clock += delta
	else: player_walk_clock = 0.0


func _update_enemies(delta: float) -> void:
	var positions: Dictionary = {}
	for enemy: Dictionary in enemies: positions[enemy.id] = enemy.pos
	super._update_enemies(delta)
	for enemy: Dictionary in enemies:
		enemy.pos = _clamp_to_floor(Vector2(enemy.pos))
		enemy_is_moving[enemy.id] = Vector2(enemy.pos).distance_to(Vector2(positions.get(enemy.id, enemy.pos))) > 0.1


func _clamp_to_floor(point: Vector2) -> Vector2:
	return Vector2(clampf(point.x, WALK_AREA.position.x, WALK_AREA.end.x), clampf(point.y, WALK_AREA.position.y, WALK_AREA.end.y))


func _projectile_contacts_enemy(start: Vector2, finish: Vector2, projectile: Dictionary, enemy: Dictionary) -> bool:
	# Licensed sprites have height above their root/feet. A torso capsule accepts
	# a shot visibly crossing the body, not an unrelated circle at root height.
	# Weapon muzzle and trajectory stay untouched, including recoil and spread.
	var point := Vector2(enemy.pos)
	var standing := str(enemy.get("blueprint_id", "")) == "ember_priest"
	var top := point + Vector2(0, -34 if standing else -20)
	var bottom := point + Vector2(0, 14)
	var radius := 16.0 + clampf(float(projectile.get("projectile_radius_pixels", 4)), 1, 8)
	if start == finish:
		var nearest := Vector2(point.x, clampf(start.y, top.y, bottom.y))
		return start.distance_squared_to(nearest) <= radius * radius
	if Geometry2D.segment_intersects_segment(start, finish, top, bottom) != null: return true
	return minf(minf(_distance_to_segment(top, start, finish), _distance_to_segment(bottom, start, finish)), minf(_distance_to_segment(start, top, bottom), _distance_to_segment(finish, top, bottom))) <= radius


func _draw() -> void:
	_draw_church()
	if blueprint == null or asset == null: return
	var sorted: Array[Dictionary] = enemies.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Vector2(a.pos).y < Vector2(b.pos).y)
	var player_drawn := false
	drawing_depth_sorted_units = true
	for enemy: Dictionary in sorted:
		if not player_drawn and player_position.y < Vector2(enemy.pos).y:
			_draw_player_and_weapon()
			player_drawn = true
		_draw_enemy(enemy)
	if not player_drawn: _draw_player_and_weapon()
	drawing_depth_sorted_units = false
	for enemy: Dictionary in enemies: _draw_enemy_attack_preview(enemy)
	_draw_attacks()
	# Foreground edge does not cover the playable floor (feet stop at y=646).
	for x: int in range(0, 1280, 96):
		draw_texture_rect_region(TILES, Rect2(x, 654, 96, 64), Rect2(64, 160, 48, 32), Color("aaa2ba"))


func _draw_church() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color("272637"))
	# Author's window / altar modules at native 2x; no blur or arbitrary stretch.
	draw_texture_rect_region(CHURCH, Rect2(96, 0, 352, 384), Rect2(0, 0, 176, 192))
	draw_texture_rect_region(CHURCH, Rect2(832, 0, 352, 384), Rect2(0, 0, 176, 192))
	draw_texture_rect_region(CHURCH, Rect2(480, 0, 320, 384), Rect2(304, 0, 160, 192))
	draw_texture_rect(COLUMN, Rect2(0, 0, 228, 380), false)
	draw_texture_rect(COLUMN, Rect2(1052, 0, 228, 380), false)
	# Quiet walkable plane assembled from the source stone palette. Background
	# details stay at the perimeter, leaving attack silhouettes unobstructed.
	_draw_stone_floor()
	# Side borders establish the playable floor, using the same source atlas.
	for y: int in range(380, 654, 64):
		draw_texture_rect_region(TILES, Rect2(0, y, 64, 64), Rect2(16, 112, 32, 32), Color("91819d"))
		draw_texture_rect_region(TILES, Rect2(1216, y, 64, 64), Rect2(16, 112, 32, 32), Color("91819d"))
	draw_rect(Rect2(64, 378, 1152, 4), Color("181722"))
	draw_rect(Rect2(64, 382, 1152, 2), Color("50405b"))


func _draw_stone_floor() -> void:
	draw_rect(Rect2(0, 378, 1280, 278), Color("302d3e"))
	# Project the seams toward a common vanishing point: compressed rear rows,
	# wider front slabs and converging longitudinal seams read as a FLOOR, not
	# another front-facing wall. Render at 2px steps with no antialiased strokes.
	var rows := [384.0, 406.0, 434.0, 470.0, 516.0, 574.0, 654.0]
	for row: int in range(rows.size() - 1):
		var top: float = rows[row]
		var bottom: float = rows[row + 1]
		var offset := 96.0 if row % 2 else 0.0
		for column: int in range(-10, 11):
			var left := 640.0 + column * 192.0 + offset
			var right := left + 192.0
			var points := PackedVector2Array([
				_floor_project(left, top), _floor_project(right, top),
				_floor_project(right, bottom), _floor_project(left, bottom),
			])
			if points[1].x <= 64 or points[0].x >= 1216: continue
			var stone := Color("3b354b") if posmod(row * 7 + column * 3, 5) == 0 else Color("373243")
			draw_colored_polygon(points, stone)
			draw_line(points[0], points[1], Color("494055"), 2.0, false)
			draw_line(points[1], points[2], Color("292636"), 2.0, false)
			draw_line(points[2], points[3], Color("292636"), 2.0, false)


func _floor_project(x: float, y: float) -> Vector2:
	var depth := (y - 180.0) / (654.0 - 180.0)
	return Vector2(snappedf(clampf(640.0 + (x - 640.0) * depth, 64.0, 1216.0), 2.0), y)


func _draw_enemy_attack_preview(enemy: Dictionary) -> void:
	# One warning pass after depth sorting: a foreground actor must not erase
	# another enemy's dangerous boundary. Regions still come from the runtime.
	if not drawing_depth_sorted_units: super._draw_enemy_attack_preview(enemy)


func _draw_attack_hit_region(origin: Vector2, direction: Vector2, region: Dictionary, color: Color) -> void:
	var readable := color.lightened(0.15)
	readable.a = maxf(color.a, 0.82)
	super._draw_attack_hit_region(origin, direction, region, readable)


func player_frame_index() -> int:
	return int(player_walk_clock * 9.0) % 6 if player_is_moving else 1


func _draw_player_body(pixel_position: Vector2) -> void:
	# Use the unarmed walking stance instead of the source's raised boxing fists.
	# Split at the waist: walking legs animate, a stable torso keeps the gun grip
	# from bobbing independently of its physical anchors. Source frame is 82x60.
	var lower_frame := player_frame_index()
	draw_set_transform(_snap_enemy_pixel(pixel_position), 0.0, Vector2(facing, 1.0))
	var tint := Color("f6b080") if flash_timer > 0.0 else Color.WHITE
	draw_texture_rect_region(PLAYER_WALK, Rect2(-82, -74, 164, 70), Rect2(82, 0, 82, 35), tint)
	draw_texture_rect_region(PLAYER_WALK, Rect2(-82, -4, 164, 50), Rect2(lower_frame * 82, 35, 82, 25), tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_player_pixel_arm(start: Vector2, elbow: Vector2, finish: Vector2, _sleeve: Color) -> void:
	# Match the source hero's bare arms. Same endpoints as production weapon fit.
	var a := _snap_enemy_pixel(start)
	var b := _snap_enemy_pixel(elbow)
	var c := _snap_enemy_pixel(finish)
	draw_line(a, b, Color("331a19"), 6.0, false)
	draw_line(b, c, Color("331a19"), 6.0, false)
	draw_line(a, b, Color("a4493e"), 4.0, false)
	draw_line(b, c, Color("c56336"), 4.0, false)
	draw_rect(Rect2(c - Vector2(2, 2), Vector2(4, 4)), Color("e1924d"))


func _draw_player_pixel_hand(point: Vector2, _skin: Color) -> void:
	var p := _snap_enemy_pixel(point)
	draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), Color("331a19"))
	draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), Color("e1924d"))


func enemy_frame_sample(enemy: Dictionary, compiled_attack: Dictionary) -> Dictionary:
	var id := str(enemy.get("blueprint_id", ""))
	var runtime: Variant = enemy.get("attack_runtime")
	var phase := str(runtime.phase) if runtime != null else "idle"
	var progress := _enemy_sprite_phase_progress(compiled_attack, phase, float(runtime.phase_elapsed)) if runtime != null else 0.0
	var texture: Texture2D
	var frame := 0
	var size := Vector2(81, 66)
	if id == "ember_priest":
		texture = WIZARD_IDLE
		frame = int(stage_elapsed * 6.0) % 5
		if phase != "idle":
			texture = WIZARD_FIRE
			match phase:
				"telegraph": frame = mini(3, int(progress * 4.0))
				"commit": frame = 4 + mini(1, int(progress * 2.0))
				"active": frame = 6 + mini(2, int(progress * 3.0))
				"recovery": frame = 9
	elif id == "mechanical_spider":
		size = Vector2(57, 60)
		texture = GHOUL_RUN
		frame = int(stage_elapsed * 9.0) % 8 if bool(enemy_is_moving.get(enemy.id, false)) else 0
		if phase in ["telegraph", "commit"]:
			texture = GHOUL_RUSH
			frame = mini(2, int(progress * 3.0))
		elif phase == "active":
			texture = GHOUL_RUSH
			frame = 3 + mini(4, int(progress * 5.0))
	else: return {}
	var direction := float(enemy.get("facing", -1.0))
	if runtime != null and phase != "idle" and absf(Vector2(runtime.locked_direction).x) > 0.001:
		direction = signf(Vector2(runtime.locked_direction).x)
	return {"texture": texture, "frame": frame, "size": size, "phase": phase, "facing": direction}


func _draw_enemy_formal_sprite(enemy: Dictionary, compiled_attack: Dictionary) -> bool:
	var sample := enemy_frame_sample(enemy, compiled_attack)
	if sample.is_empty(): return false
	var frame_size: Vector2 = sample.size
	var base := _snap_enemy_pixel(Vector2(enemy.pos))
	# Both enemy sheets face LEFT. Positive world facing therefore mirrors them.
	draw_set_transform(base, 0.0, Vector2(-float(sample.facing), 1.0))
	var tint := Color("ffb488") if float(enemy.get("hurt", 0.0)) > 0.0 else Color.WHITE
	draw_texture_rect_region(sample.texture, Rect2(-frame_size.x, 46 - frame_size.y * 2, frame_size.x * 2, frame_size.y * 2), Rect2(float(sample.frame) * frame_size.x, 0, frame_size.x, frame_size.y), tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true
