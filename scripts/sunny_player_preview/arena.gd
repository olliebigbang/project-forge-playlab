extends GameplayArena
## Isolated presentation adapter; the shared combat runtime is not modified.
const RIG := preload("res://scripts/sunny_player_preview/pixel_player_rig.gd")
const LANE_AIM := preload("res://scripts/sunny_player_preview/lane_aim.gd")
const NATIVE_PIXEL := 2.0
const BACKGROUND := preload("res://assets/sunny_arena_preview_v1/clearing_generated_v3.png")
const FROG := preload("res://assets/sunny_arena_preview_v1/frog_idle.png")
const FLOOR := Rect2(140, 424, 1000, 216)
const FOOT_OFFSET := Vector2(0, 48)
var rig := RIG.new()
var walk_clock := 0.0
var moving := false
var body_frame: Dictionary = {}
var fit_cache: Dictionary = {}
var damage_delivered := 0.0
var last_draw_rig: Dictionary = {}
var grip_rig: PixelWeaponVisualRig
var aim_rotation := 0.0
var aim_target_id := ""
var aim_target_point := Vector2.ZERO
var target_damage: Dictionary = {}
var shot_records: Array[Dictionary] = []

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var cutout := ShaderMaterial.new()
	cutout.shader = preload("res://scripts/sunny_player_preview/crisp_alpha.gdshader")
	material = cutout
	body_frame = rig.sample(0, false, false)

func start_stage(next_stage: String, next_blueprint: WeaponBlueprint, next_asset: WeaponVisualAsset, next_enemies: Array[Dictionary] = []) -> void:
	fit_cache.clear()
	grip_rig = null
	aim_rotation = 0.0
	aim_target_id = ""
	target_damage.clear()
	shot_records.clear()
	damage_delivered = 0
	walk_clock = 0
	super.start_stage(next_stage, next_blueprint, next_asset, next_enemies)
	player_position = Vector2(400, 568)
	facing = 1
	body_frame = rig.sample(0, false, false)
	if melee_runtime.profile != null: _build_melee_frame()

func _update_player(delta: float) -> void:
	var previous := player_position
	super._update_player(delta)
	var feet := (player_position + FOOT_OFFSET).clamp(FLOOR.position, FLOOR.end)
	player_position = feet - FOOT_OFFSET
	moving = player_position.distance_to(previous) > 0.01
	if moving: walk_clock += delta
	else: walk_clock = 0
	body_frame = rig.sample(walk_clock, moving, dodge_timer > 0)
	_update_height_aim()

func _update_height_aim() -> void:
	if not _uses_firearm_runtime():
		aim_rotation = 0.0
		aim_target_id = ""
		return
	var target := LANE_AIM.select_target(player_position, facing, enemies, aim_target_id)
	if target.is_empty():
		aim_rotation = 0.0
		aim_target_id = ""
		return
	aim_target_id = str(target.get("id", ""))
	aim_target_point = _target_body_center(target)
	# Solve from the real moving muzzle, including the hand-reach constraint.
	# Recoil remains additive; this does not cancel a weapon's recoil axes.
	# Direct fixed-point iteration oscillates for a long barrel near a target.
	# Bracket the ray error instead; the muzzle itself moves with the held gun.
	var lower := -LANE_AIM.MAX_ANGLE
	var upper := LANE_AIM.MAX_ANGLE
	for iteration: int in range(18):
		var trial := (lower + upper) * 0.5
		aim_rotation = trial * facing
		var delta := aim_target_point - _muzzle_world()
		var cross_error := cos(trial) * delta.y - sin(trial) * delta.x * facing
		if cross_error > 0: lower = trial
		else: upper = trial

func _target_body_center(enemy: Dictionary) -> Vector2:
	return Vector2(enemy.pos) + FOOT_OFFSET + Vector2(0, -38)

func _firearm_action_sample() -> Dictionary:
	var action := super._firearm_action_sample()
	if not action.is_empty():
		action.root_pose.rotation = float(action.root_pose.rotation) + aim_rotation
	return action

func _firearm_recoil_rotation() -> float:
	return super._firearm_recoil_rotation() + aim_rotation

func _safe_projectile_origin(requested_origin: Vector2) -> Vector2:
	# This preview has an actual height-aware muzzle. Never teleport emission
	# backwards to a different point just to produce a close-range hit.
	return requested_origin

func _fire_bullet() -> void:
	var previous_count := projectiles.size()
	var origin := _muzzle_world()
	var visual_angle := float(_firearm_action_sample().get("root_pose", {}).get("rotation", 0.0))
	super._fire_bullet()
	for index: int in range(previous_count, projectiles.size()):
		projectiles[index]["ground_lane_y"] = player_position.y
		shot_records.append({"target_id": aim_target_id, "ground_y": player_position.y, "muzzle": origin, "projectile_origin": projectiles[index].origin, "visual_angle": visual_angle, "base_bullet_angle": _firearm_recoil_rotation(), "facing": facing, "target_point": aim_target_point})

func _weapon_fit() -> Dictionary:
	if not fit_cache.is_empty(): return fit_cache
	var fit: Dictionary = WEAPON_PLAYER_FIT.compile(blueprint, asset)
	var scale := float(fit.get("draw_scale", 1.0)) * 2.0
	var axes := blueprint.affordance
	var dimensions := Vector2(asset.opaque_bounds.size)
	if str(axes.get("support_mode", "")) in ["two_hand_shouldered", "two_hand_free"]:
		scale = minf(scale, 128.0 / maxf(dimensions.x, dimensions.y))
	var slenderness := maxf(dimensions.x, dimensions.y) / maxf(1.0, minf(dimensions.x, dimensions.y))
	var compact := not _uses_firearm_runtime() and slenderness < 2.2 and str(axes.get("flex_topology", "none")) == "none" and str(axes.get("tether_topology", "none")) == "none"
	if compact: scale = minf(scale, 52.0 / maxf(dimensions.x, dimensions.y))
	# Give linked silhouettes a bounded readability floor, without doubling
	# the whole object until its links dwarf the authored character's arms.
	if str(axes.get("flex_topology", "none")) == "linked_segments" or str(axes.get("tether_topology", "none")) == "linked_segments":
		scale = maxf(scale, RIG.SCALE * 0.625)
	var raw_delta := asset.grip_secondary - asset.grip_primary
	if fit.get("support_required", false) and raw_delta.length() > 0:
		# Keep both actual grips within this body's achievable span. This is a
		# local presentation scale; declarations/weapon library are unchanged.
		scale = minf(scale, 82.0 / raw_delta.length())
	fit["draw_scale"] = scale
	fit["secondary_grip_delta"] = raw_delta * scale
	fit["compact_silhouette"] = compact
	fit_cache = fit
	return fit_cache

func _hand_solution() -> Dictionary:
	if body_frame.is_empty(): body_frame = rig.sample(0, false, false)
	var fit := _weapon_fit()
	var shoulders: Dictionary = rig.shoulders(body_frame, player_position + FOOT_OFFSET, facing)
	var action := _firearm_action_sample()
	var action_root: Dictionary = action.get("root_pose", {})
	var pose: Dictionary = melee_runtime.pose(facing)
	var offset := Vector2(action_root.get("offset", Vector2.ZERO)) if _uses_firearm_runtime() else Vector2(pose.get("offset", Vector2.ZERO))
	var angle := float(action_root.get("rotation", 0.0)) if _uses_firearm_runtime() else float(pose.get("angle", 0.0))
	var two_hands := bool(fit.get("support_required", false))
	var grips := _actual_grip_points(Vector2.ZERO, angle)
	var delta := Vector2(grips.secondary) - Vector2(grips.primary)
	var desired := Vector2(shoulders.primary) + Vector2((22.0 if two_hands else 47.0) * facing, 13.0) + offset
	if _uses_firearm_runtime() and str(blueprint.affordance.get("support_mode", "")) == "two_hand_shouldered":
		# Lower the grip as the muzzle tilts, then tuck it back toward the
		# chest. Rotating a rifle around the former high hand puts its stock
		# into the neck. Both real grips must still satisfy the arm constraints.
		var depression := maxf(0.0, sin(angle * facing))
		desired = Vector2(shoulders.primary) + Vector2((33.0 - 28.0 * depression) * facing, 31.0 + 20.0 * depression) + offset
	var primary := RIG.constrain_grip(desired, shoulders.primary, shoulders.support, delta, two_hands, facing, angle)
	if fit.get("compact_silhouette", false):
		var best_score := _compact_pose_score(primary, desired, angle, float(fit.draw_scale))
		# Search the actual wrist reach disc, including the back/low directions
		# missing from the former positive-shift grid. Avoid the torso as well
		# as the head: moving a pot out of the face and into the chest is not a fix.
		for radius: float in [RIG.MAX_REACH, RIG.MAX_REACH * 0.8, RIG.MAX_REACH * 0.5]:
			for direction_index: int in range(48):
				var direction := Vector2.from_angle(direction_index * TAU / 48.0)
				var candidate := Vector2(shoulders.primary) + direction * radius - RIG.wrist_offset(facing, angle)
				candidate = RIG.constrain_grip(candidate, shoulders.primary, shoulders.support, delta, two_hands, facing, angle)
				var score := _compact_pose_score(candidate, desired, angle, float(fit.draw_scale))
				if score < best_score:
					best_score = score
					primary = candidate
	var wrist_delta := RIG.wrist_offset(facing, angle)
	return {"primary": primary, "secondary": primary + delta, "primary_wrist": primary + wrist_delta, "support_wrist": primary + delta + wrist_delta, "weapon_origin": primary - Vector2(grips.primary), "primary_shoulder": shoulders.primary, "support_shoulder": shoulders.support, "offset": offset, "two_hands": two_hands, "angle": angle, "body_frame": int(body_frame.index)}

func _actual_grip_points(origin: Vector2, angle: float) -> Dictionary:
	var draw_scale := float(_weapon_fit().draw_scale)
	if not _uses_soft_mechanism_visual():
		var delta := (asset.grip_secondary - asset.grip_primary) * draw_scale
		return {"primary": origin, "secondary": origin + Vector2(delta.x * facing, delta.y).rotated(angle)}
	if grip_rig == null:
		grip_rig = PixelWeaponVisualRig.new()
		# Bind the anchors with the very same source-part rule as the visible
		# pixels. A supporting hand must follow a bent link, not its rigid pose.
		for anchor: Vector2 in [asset.grip_primary, asset.grip_secondary]:
			var part: Dictionary = asset.visual_rig._assign_part(anchor)
			grip_rig.bindings.append(asset.visual_rig._make_binding(anchor, Color.WHITE, part))
	var geometry := _soft_weapon_geometry(origin, angle)
	geometry.merge({"source_grip": asset.grip_primary, "facing": facing, "scale": draw_scale, "pixel_snap": false})
	geometry["include_metadata"] = false
	var pixels: Array = PIXEL_WEAPON_DEFORMER.deform(grip_rig, geometry).pixels
	return {"primary": Vector2(pixels[0].position), "secondary": Vector2(pixels[1].position)}

func _weapon_bounds(hand: Vector2, angle: float, draw_scale: float) -> Rect2:
	var source_bounds := Rect2(asset.opaque_bounds)
	var transformed := Rect2()
	var first := true
	for corner: Vector2 in [source_bounds.position, source_bounds.position + Vector2(source_bounds.size.x, 0), source_bounds.end, source_bounds.position + Vector2(0, source_bounds.size.y)]:
		var point := (corner - asset.grip_primary) * draw_scale
		point = hand + Vector2(point.x * facing, point.y).rotated(angle)
		if first:
			transformed = Rect2(point, Vector2.ZERO)
			first = false
		else: transformed = transformed.expand(point)
	return transformed

func _body_part_bounds(local: Rect2) -> Rect2:
	var origin := local.position
	if facing < 0: origin.x = -origin.x - local.size.x
	return Rect2(player_position + FOOT_OFFSET + origin, local.size)

func _head_overlap_area(hand: Vector2, angle: float, draw_scale: float) -> float:
	var transformed := _weapon_bounds(hand, angle, draw_scale)
	var head_world := _body_part_bounds(rig.head_rect(body_frame)).grow(2)
	return transformed.intersection(head_world).get_area() if transformed.intersects(head_world) else 0.0

func _compact_pose_score(hand: Vector2, desired: Vector2, angle: float, draw_scale: float) -> float:
	var weapon := _weapon_bounds(hand, angle, draw_scale)
	var head := _body_part_bounds(rig.head_rect(body_frame)).grow(2)
	var torso := _body_part_bounds(rig.torso_rect(body_frame)).grow(-4)
	var head_overlap := weapon.intersection(head).get_area() if weapon.intersects(head) else 0.0
	var torso_overlap := weapon.intersection(torso).get_area() if weapon.intersects(torso) else 0.0
	return head_overlap * 1000000 + torso_overlap * 1000 + hand.distance_squared_to(desired)

func _build_melee_frame() -> void:
	super._build_melee_frame()
	if melee_frame.is_empty(): return
	# Quantize the actual rendered/contact pixels together to this scene's
	# native grid. Sub-pixel fragments otherwise disappear in the world viewport.
	var native_pixels: Dictionary = {}
	for pixel: Dictionary in melee_frame.get("pixels", []):
		var point := Vector2(pixel.position).snapped(Vector2.ONE * NATIVE_PIXEL)
		var key := Vector2i(point)
		var copy := pixel.duplicate()
		copy.position = point
		copy.size = maxf(NATIVE_PIXEL, float(pixel.get("size", 1.0)))
		# Keep authored painter order rather than selecting the darkest pixel,
		# which erases highlights and makes small links read as a solid rod.
		native_pixels[key] = copy
	melee_frame.pixels = native_pixels.values()
	var contacts := PackedVector2Array()
	for point: Vector2 in melee_frame.get("contacts", PackedVector2Array()): contacts.append(point.snapped(Vector2.ONE * NATIVE_PIXEL))
	melee_frame.contacts = contacts

func _firearm_hand_base() -> Vector2:
	var solution := _hand_solution()
	return Vector2(solution.weapon_origin) - Vector2(solution.offset)

func _draw() -> void:
	draw_texture_rect(BACKGROUND, Rect2(0, 0, 1280, 720), false)
	if blueprint == null or asset == null: return
	var units: Array[Dictionary] = [{"player": true, "y": player_position.y}]
	for enemy: Dictionary in enemies: units.append({"player": false, "y": Vector2(enemy.pos).y, "enemy": enemy})
	units.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.y) < float(b.y))
	for unit: Dictionary in units:
		if unit.player: _draw_player_and_weapon()
		else: _draw_practice_target(unit.enemy)
	_draw_attacks()

func _draw_player_and_weapon() -> void:
	var feet := player_position + FOOT_OFFSET
	draw_rect(Rect2(feet + Vector2(-24, 0), Vector2(48, 4)), Color("ad8742"))
	var solution := _hand_solution()
	var back: Dictionary = {}
	if solution.two_hands: back = rig.draw_arm(self, solution.support_shoulder, solution.secondary, facing, true, solution.angle)
	rig.draw_body(self, body_frame, feet, facing, not solution.two_hands)
	# Reuse the original weapon renderer, including pixel deformation and the
	# same anchors used by hit geometry and firearm muzzle/projectile emission.
	super._draw_player_weapon_and_arms(player_position)
	if solution.two_hands: rig.draw_fist(self, back.elbow, solution.secondary, facing, true, solution.angle)
	if _uses_soft_mechanism_visual():
		# During an overhead arc the projected strand passes behind the head.
		# The same source pixels/contacts still exist; only normal actor
		# occlusion order changes. Hands remain in front of their real grips.
		rig.draw_part(self, body_frame, "Head", feet, facing)
	# The near arm belongs in front of the object; otherwise linked pixels
	# conceal the wrist even though its mathematical anchor is correct.
	var front: Dictionary = rig.draw_arm(self, solution.primary_shoulder, solution.primary, facing, false, solution.angle)
	rig.draw_fist(self, front.elbow, solution.primary, facing, false, solution.angle)
	last_draw_rig = {"front": front, "back": back, "solution": solution}

func _draw_player_pixel_arm(_start: Vector2, _elbow: Vector2, _finish: Vector2, _sleeve: Color) -> void:
	pass # Authored source arm pixels are drawn by the rig, never legacy lines.

func _draw_player_pixel_hand(_point: Vector2, _skin: Color) -> void:
	pass # Authored fist pixels, not a rectangle pasted over the object.

func _spawn_stage() -> void:
	enemies.clear()
	_spawn_enemy("target", Vector2(780, 516), 150)
	_spawn_enemy("target", Vector2(980, 572), 150)

func _face_nearest_enemy_for_attack() -> void:
	pass # This presentation sample lets the user inspect both facing directions.

func _damage_enemy(enemy: Dictionary, amount: float, hurt_seconds: float = 0.12) -> void:
	damage_delivered += amount
	var target_id := str(enemy.get("id", ""))
	target_damage[target_id] = float(target_damage.get(target_id, 0.0)) + amount
	super._damage_enemy(enemy, amount, hurt_seconds)

func _update_enemies(delta: float) -> void:
	super._update_enemies(delta)
	for enemy: Dictionary in enemies:
		enemy.pos = (Vector2(enemy.pos) + FOOT_OFFSET).clamp(FLOOR.position, FLOOR.end) - FOOT_OFFSET

func _draw_practice_target(enemy: Dictionary) -> void:
	var feet := Vector2(enemy.pos) + FOOT_OFFSET
	draw_rect(Rect2(feet + Vector2(-28, 0), Vector2(56, 4)), Color("ad8742"))
	var index := int(stage_elapsed * 4) % 4
	draw_texture_rect_region(FROG, Rect2(feet - Vector2(70, 108), Vector2(140, 128)), Rect2(index * 35, 0, 35, 32), Color("ffc9a0") if float(enemy.hurt) > 0 else Color.WHITE)
	draw_rect(Rect2(feet + Vector2(-32, -104), Vector2(64, 5)), Color("314b45"))
	draw_rect(Rect2(feet + Vector2(-32, -104), Vector2(64 * float(enemy.hp) / float(enemy.max_hp), 5)), Color("77be78"))

func _projectile_contacts_enemy(start: Vector2, finish: Vector2, projectile: Dictionary, enemy: Dictionary) -> bool:
	if projectile.has("ground_lane_y") and absf(Vector2(enemy.pos).y - float(projectile.ground_lane_y)) > LANE_AIM.LANE_HALF_WIDTH: return false
	var feet := Vector2(enemy.pos) + FOOT_OFFSET
	var top := feet + Vector2(0, -58)
	var bottom := feet + Vector2(0, -12)
	var radius := 24.0 + float(projectile.get("projectile_radius_pixels", 4))
	if Geometry2D.segment_intersects_segment(start, finish, top, bottom) != null: return true
	return minf(minf(_distance_to_segment(top, start, finish), _distance_to_segment(bottom, start, finish)), minf(_distance_to_segment(start, top, bottom), _distance_to_segment(finish, top, bottom))) <= radius

func _check_completion(_delta: float) -> void:
	pass # Practice targets regenerate; this scene is not the campaign.
