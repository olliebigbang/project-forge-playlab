extends GameplayArena
## Production animation adapter: the mechanism runtime still owns attacks,
## ammo, timing, recoil, movement, deformation and enemy interactions.
const SOURCE_RIG := preload("res://scripts/authored_player/source_rig.gd")
const MELEE_CLIP := preload("res://scripts/authored_player/melee_clip.gd")
const SOURCE_SCALE := 3.0
const FEET_OFFSET := Vector2(0, 46)
var source_rig := SOURCE_RIG.new()
var authored_clock := 0.0
var authored_moving := false
var authored_crouched := false
var force_crouch := false
var auto_crouch := true
var shot_age := 10.0
var hurt_age := 10.0
var last_health := 100.0
var authored_fit: Dictionary = {}
var authored_evidence: Dictionary = {}
var shot_records: Array[Dictionary] = []
var authored_grip_rig: PixelWeaponVisualRig
var attachment_key := ""
var attachment_cache: Dictionary = {}
var grip_cache_key := ""
var grip_cache: Dictionary = {}

func start_stage(next_stage: String, next_blueprint: WeaponBlueprint, next_asset: WeaponVisualAsset, next_enemies: Array[Dictionary] = []) -> void:
	preload("res://scripts/combat_feel/automatic_pixel_visual_rig_builder.gd").refresh_automatic_terminal_binding(next_asset)
	preload("res://scripts/services/fal_general_object_visual_provider.gd").new().refresh_automatic_handle_binding(next_asset, next_blueprint)
	authored_fit.clear()
	authored_grip_rig = null
	attachment_key = ""; attachment_cache.clear(); grip_cache_key = ""; grip_cache.clear()
	authored_clock = 0; shot_age = 10; hurt_age = 10; last_health = 100
	authored_moving = false; authored_crouched = false
	shot_records.clear()
	super.start_stage(next_stage, next_blueprint, next_asset, next_enemies)

func _update_player(delta: float) -> void:
	authored_clock += delta
	shot_age += delta; hurt_age += delta
	if player_health < last_health: hurt_age = 0
	last_health = player_health
	var before := player_position
	super._update_player(delta)
	authored_moving = before.distance_squared_to(player_position) > 0.01
	authored_crouched = false
	if _uses_firearm_runtime() and dodge_timer <= 0 and not authored_moving:
		authored_crouched = force_crouch or Input.is_physical_key_pressed(KEY_C)
		if auto_crouch and not authored_crouched: authored_crouched = _should_crouch_for_target()

func _source_pose(crouch_override: int = -1) -> Dictionary:
	var crouched := authored_crouched if crouch_override < 0 else crouch_override == 1
	var clip := "body/Walk" if authored_moving else "body/Idle"
	var time := authored_clock
	var looping := true
	if player_health <= 0:
		clip = "body/Die"; time = hurt_age; looping = false
	elif dodge_timer > 0:
		clip = "body/Roll"; time = (1.0 - dodge_timer / 0.20) * source_rig.duration(clip); looping = false
	elif melee_runtime.busy():
		var primitive: Variant = melee_runtime.primitive()
		var controller: Variant = melee_runtime.controller
		# Structural axes select an authored movement family, never object names.
		if _uses_authored_blade_action():
			return MELEE_CLIP.sample_blade(source_rig, int(controller.combo_index), str(controller.attack_kind), str(controller.phase), controller.phase_ratio())
		elif primitive != null and str(primitive.presentation_family) != "default":
			return MELEE_CLIP.sample_presentation(source_rig, str(primitive.presentation_family), str(controller.phase), controller.phase_ratio())
		elif primitive != null and str(primitive.tether_deployment) in ["cast_retract", "launch_tension"]:
			clip = "fishing/Charge" if controller.phase == "startup" else ("fishing/Cast" if controller.phase == "active" else "fishing/Reel")
			time = controller.phase_ratio() * source_rig.duration(clip)
		else:
			# Movement/charging changes runtime timing, not the physical action:
			# a moving thrust still uses a thrust body, not a backward run-slash.
			return MELEE_CLIP.sample(source_rig, str(primitive.motion_family), str(controller.phase), controller.phase_ratio())
		looping = false
	elif _uses_firearm_runtime():
		if reload_timer > 0:
			clip = "combat/GunReload"
			time = (1.0 - reload_timer / maxf(0.001, float(ranged_runtime_profile.get("reload_seconds", 1.0)))) * source_rig.duration(clip)
			looping = false
		elif shot_age < 0.23:
			clip = "combat/GunWalkFire" if authored_moving else ("combat/GunCrouchFire" if crouched else ("combat/GunFire2H" if _weapon_fit().support_required else "combat/GunFire"))
			time = shot_age / 0.23 * source_rig.duration(clip); looping = false
		else:
			clip = "combat/GunWalk" if authored_moving else ("combat/GunCrouch" if crouched else "combat/GunAim")
	elif blueprint != null and str(blueprint.affordance.get("tether_deployment", "none")) in ["cast_retract", "launch_tension"]:
		# There is no authored rod walk. Use real walking legs/body with held arms,
		# not a motionless fishing silhouette sliding across the floor.
		clip = "combat/SwordWalk" if authored_moving else "fishing/Idle"
	elif blueprint != null and blueprint.behavior_family == "heavy_melee":
		clip = "combat/SwordWalk" if authored_moving else "combat/SwordIdle"
	elif not boomerang.is_empty():
		clip = "combat/ThrowOverarm"; time = shot_age; looping = false
	if hurt_age < 0.18 and not melee_runtime.busy() and dodge_timer <= 0 and player_health > 0:
		clip = "combat/Hit"; time = hurt_age; looping = false
	return source_rig.sample(clip, time, looping)

func _weapon_fit() -> Dictionary:
	if not authored_fit.is_empty(): return authored_fit
	var fit := super._weapon_fit().duplicate(true)
	if asset == null or not fit.get("ok", false): return fit
	var scale := float(fit.draw_scale) * 1.5
	var span := maxf(1, asset.opaque_bounds.size.x)
	if _uses_firearm_runtime(): scale = minf(scale, (100.0 if fit.support_required else 44.0) / span)
	elif not _uses_soft_mechanism_visual() and span / maxf(1, asset.opaque_bounds.size.y) < 2.0:
		# Body grip is not evidence of a compact object. Thin long bodies keep
		# their declared length; only genuinely compact silhouettes get this cap.
		scale = minf(scale, 54.0 / maxf(span, asset.opaque_bounds.size.y))
	if fit.support_required:
		# Fit the object to two actual hands, never replace GripSecondary with
		# a made-up delta or extend the supporting arm off its shoulder.
		scale = minf(scale, 42.0 / maxf(1, asset.grip_secondary.distance_to(asset.grip_primary)))
	if _uses_authored_blade_action():
		# Match an AI blade to the source sword's grip-to-tip span. Long blades
		# keep the full authored reach; medium/short blades remain visibly smaller
		# instead of being enlarged into the source sword by object identity.
		var reference: Vector2 = _reference_weapon_vector(source_rig.frame("combat/SwordIdle", 0))
		var generated_span: float = asset.grip_primary.distance_to(asset.tip)
		var length_ratio: float = {"short": 0.56, "medium": 0.82, "long": 1.0}.get(str(blueprint.affordance.get("body_length", "medium")), 0.82)
		if reference.length() > 2.0 and generated_span > 4.0:
			scale = minf(scale, reference.length() * SOURCE_SCALE * length_ratio / generated_span)
	fit.draw_scale = scale
	fit.secondary_grip_delta = (asset.grip_secondary - asset.grip_primary) * scale
	fit.rendered_span_pixels = span * scale
	authored_fit = fit
	return fit

func _attachment(crouch_override: int = -1) -> Dictionary:
	var frame := _source_pose(crouch_override)
	var authored_blade: bool = _uses_authored_blade_action() and Dictionary(frame.get("images", {})).has("Weapon")
	var motion_pose: Dictionary = melee_runtime.pose(facing)
	var longitudinal_scale := float(motion_pose.get("longitudinal_scale", 1.0))
	var trajectory_plane := str(motion_pose.get("trajectory_plane", "screen_arc"))
	var depth_layer := float(motion_pose.get("depth_layer", 0.0))
	var nearest_body := INF
	if _uses_firearm_runtime():
		for enemy: Dictionary in enemies:
			var offset := Vector2(enemy.pos) - player_position
			if float(enemy.hp) > 0 and absf(offset.y) < 30 and offset.x * facing > 18: nearest_body = minf(nearest_body, offset.x * facing)
	var key := str([player_position, facing, frame.key, frame.index, melee_runtime.motion_ratio(), melee_runtime.state_power(), melee_runtime.busy(), longitudinal_scale, depth_layer, dodge_timer > 0, reload_timer, manual_cycle_timer, weapon_recoil_offset, weapon_muzzle_climb_degrees, sustained_muzzle_climb_degrees, nearest_body])
	if key == attachment_key and not attachment_cache.is_empty(): return attachment_cache
	var feet := (player_position + FEET_OFFSET).round()
	# Blade choreography must remain the source frame itself. Generic items may
	# still use a donor limb when their authored frame contains a motion smear.
	var front_frame := frame if authored_blade else source_rig.full_arm_frame(frame)
	var primary := SOURCE_RIG.world(front_frame.primary.hand, front_frame, feet, facing, SOURCE_SCALE)
	var shoulder := SOURCE_RIG.world(front_frame.primary.shoulder, front_frame, feet, facing, SOURCE_SCALE)
	# The source far-arm export contains only its unoccluded few pixels, not a
	# complete limb. Use the authored full near-arm silhouette as a rear-arm
	# donor; do not mistake a visible fingertip for a 7-pixel complete arm.
	var support_frame := front_frame if authored_blade else front_frame.duplicate(true)
	if not authored_blade:
		support_frame.pivot = Vector2(front_frame.pivot) + Vector2(2, 0)
		support_frame.support = front_frame.primary
		support_frame.parts.LeftArm = front_frame.parts.RightArm
		support_frame.images.LeftArm = front_frame.images.RightArm
		support_frame.arm_pixels.LeftArm = front_frame.arm_pixels.RightArm
	var support_shoulder := SOURCE_RIG.world(support_frame.support.shoulder, support_frame, feet, facing, SOURCE_SCALE)
	var fit := _weapon_fit()
	if not authored_blade and not _uses_firearm_runtime() and not melee_runtime.busy() and dodge_timer <= 0 and bool(fit.get("support_required", false)):
		# Two-handed readiness holds the real shaft in front of the waist, not
		# the original one-handed sword idle's hand hanging behind the hip.
		primary = shoulder + Vector2(18 * facing, 27)
	var angle := float(motion_pose.get("angle", 0.0))
	if authored_blade: angle = _authored_blade_angle(frame, float(fit.draw_scale))
	var authored_barrel_grip_y := -INF
	if _uses_firearm_runtime():
		var original_action := super._firearm_action_sample()
		angle = float(original_action.root_pose.rotation)
		primary += Vector2(original_action.root_pose.offset)
		var reference: Image = frame.images.get("Weapon")
		if reference != null and reference.get_used_rect().has_area():
			var reference_muzzle := Vector2(reference.get_used_rect().get_center())
			var reference_y := SOURCE_RIG.world(reference_muzzle, frame, feet, facing, SOURCE_SCALE).y
			# A tall AI receiver must not lift the barrel above the authored aim
			# plane. Retarget the HAND to the true AI grip, not the bullet origin.
			authored_barrel_grip_y = reference_y - (asset.muzzle.y - asset.grip_primary.y) * float(fit.draw_scale) + Vector2(original_action.root_pose.offset).y
			primary.y = authored_barrel_grip_y
	var delta := Vector2(fit.get("secondary_grip_delta", Vector2.ZERO))
	delta.x *= longitudinal_scale
	delta = Vector2(delta.x * facing, delta.y).rotated(angle)
	var support := SOURCE_RIG.world(frame.support.hand, frame, feet, facing, SOURCE_SCALE)
	if melee_runtime.busy() and not authored_blade:
		var controller: Variant = melee_runtime.controller
		var offset := Vector2(melee_runtime.pose(facing).get("offset", Vector2.ZERO))
		var weight := 1.0
		if controller.phase == "startup": weight = smoothstep(0.4, 1.0, controller.phase_ratio())
		elif controller.phase == "recovery": weight = 1.0 - smoothstep(0.0, 1.0, controller.phase_ratio())
		# Native run-slash hands can be BEHIND the torso on frames whose source
		# sword's strike has already ended. Production timing comes from axes,
		# so bring the real held pixels into the compiled forward contact phase.
		# Keep the original whole-body anticipation and recovery outside it.
		var contact_hand := shoulder + Vector2(20 * facing, 14) + offset
		primary = (primary + offset).lerp(contact_hand, weight)
	var primary_reach := maxf(12, float(front_frame.primary.get("reach", 16)) * SOURCE_SCALE - 0.25)
	if melee_runtime.busy() and not authored_blade: primary = shoulder + (primary - shoulder).limit_length(primary_reach)
	var actual_grips := _actual_grips(primary, angle, float(fit.draw_scale), longitudinal_scale)
	delta = Vector2(actual_grips.secondary) - Vector2(actual_grips.primary)
	if fit.get("support_required", false):
		var support_reach := primary_reach
		for _i: int in range(24):
			primary = shoulder + (primary - shoulder).limit_length(primary_reach)
			var center := support_shoulder - delta
			primary = center + (primary - center).limit_length(support_reach)
		support = primary + delta
	# Horizontal held tools/guns belong below the chin, not through the face.
	# Solve both arm reach discs at that height, moving the entire real object.
	var primitive: Variant = melee_runtime.primitive()
	var level_pose := _uses_firearm_runtime() or (primitive != null and str(primitive.motion_family) == "thrust")
	if level_pose and not authored_blade and dodge_timer <= 0 and reload_timer <= 0 and absf(angle) < 0.35:
		var head: Image = frame.images.Head
		var head_bottom := SOURCE_RIG.world(Vector2(head.get_used_rect().end), frame, feet, facing, SOURCE_SCALE).y
		var top := (float(asset.opaque_bounds.position.y) - asset.grip_primary.y) * float(fit.draw_scale)
		var wanted_y := maxf(maxf(primary.y, authored_barrel_grip_y), head_bottom + 3.0 - top)
		var centers: Array[Vector2] = [shoulder]
		if fit.get("support_required", false): centers.append(support_shoulder - delta)
		var lo := -INF
		var hi := INF
		for center: Vector2 in centers:
			var height := wanted_y - center.y
			if absf(height) >= primary_reach: lo = INF; hi = -INF; break
			var half := sqrt(primary_reach * primary_reach - height * height)
			lo = maxf(lo, center.x - half); hi = minf(hi, center.x + half)
		if lo <= hi:
			primary = Vector2(clampf(primary.x, lo, hi), wanted_y)
			if fit.get("support_required", false): support = primary + delta
	if _uses_firearm_runtime() and is_finite(nearest_body) and dodge_timer <= 0 and reload_timer <= 0:
		var muzzle_delta := (asset.muzzle - asset.grip_primary) * float(fit.draw_scale)
		muzzle_delta = Vector2(muzzle_delta.x * facing, muzzle_delta.y).rotated(angle)
		var barrel_forward := (primary.x + muzzle_delta.x - player_position.x) * facing
		if barrel_forward > nearest_body - 5:
			# Close quarters: visibly tuck the source arm and entire gun back.
			# The bullet still starts on that real barrel; no origin teleport.
			primary.x -= facing * minf(38, barrel_forward - nearest_body + 5)
			primary = shoulder + (primary - shoulder).limit_length(primary_reach)
			if fit.get("support_required", false):
				var center := support_shoulder - delta
				primary = center + (primary - center).limit_length(primary_reach)
				support = primary + delta
	if melee_runtime.busy() and not authored_blade and not _uses_soft_mechanism_visual():
		primary = _clear_head_with_real_weapon(primary, angle, float(fit.draw_scale), frame, feet, shoulder, support_shoulder - delta, primary_reach, bool(fit.get("support_required", false)), longitudinal_scale)
		if fit.get("support_required", false): support = primary + delta
	var origin := primary
	if _uses_soft_mechanism_visual():
		origin += primary - Vector2(_actual_grips(primary, angle, float(fit.draw_scale), longitudinal_scale).primary)
		actual_grips = _actual_grips(origin, angle, float(fit.draw_scale), longitudinal_scale)
		primary = actual_grips.primary
		if fit.get("support_required", false): support = actual_grips.secondary
	attachment_key = key
	attachment_cache = {
		"frame": frame,
		"front_frame": front_frame,
		"support_frame": support_frame,
		"feet": feet,
		"origin": origin,
		"hand": primary,
		"support": support,
		"shoulder": shoulder,
		"support_shoulder": support_shoulder,
		"angle": angle,
		"fit": fit,
		"authored_blade": authored_blade,
		"trajectory_plane": trajectory_plane,
		"longitudinal_scale": longitudinal_scale,
		"depth_layer": depth_layer,
	}
	return attachment_cache

func _uses_authored_blade_action() -> bool:
	if blueprint == null or asset == null or blueprint.behavior_family != "heavy_melee": return false
	var axes: Dictionary = blueprint.affordance
	return (
		str(axes.get("rigidity", "")) == "rigid"
		and str(axes.get("contact_surface", "")) == "edge"
		and bool(axes.get("has_edge", false))
		and str(axes.get("grip_topology", "")) == "one_hand_handle"
		and str(axes.get("flex_topology", "none")) == "none"
		and str(axes.get("tether_topology", "none")) == "none"
		and str(axes.get("state_topology", "fixed")) == "fixed"
		and str(axes.get("activation_mode", "passive")) == "passive"
		and str(axes.get("functional_output", "contact_only")) == "contact_only"
	)

func _reference_weapon_vector(frame: Dictionary) -> Vector2:
	var images: Dictionary = frame.get("images", {})
	var reference: Image = images.get("Weapon")
	if reference == null or not reference.get_used_rect().has_area(): return Vector2.ZERO
	var hand := Vector2((frame.get("primary", {}) as Dictionary).get("hand", Vector2.ZERO))
	var farthest := Vector2.ZERO
	var best := 0.0
	var weapon_points: PackedVector2Array = frame.get("weapon_pixels", PackedVector2Array())
	for point: Vector2 in weapon_points:
		var delta := point - hand
		if delta.length_squared() > best:
			best = delta.length_squared()
			farthest = delta
	return farthest

func _authored_blade_angle(frame: Dictionary, scale: float) -> float:
	var reference: Vector2 = _reference_weapon_vector(frame)
	var generated: Vector2 = (asset.tip - asset.grip_primary) * scale
	if reference.length() <= 2.0 or generated.length() <= 2.0:
		return float(melee_runtime.pose(facing).get("angle", 0.0))
	var source_world: Vector2 = Vector2(reference.x * facing, reference.y) * SOURCE_SCALE
	var generated_world: Vector2 = Vector2(generated.x * facing, generated.y)
	return generated_world.angle_to(source_world)

func _clear_head_with_real_weapon(hand: Vector2, angle: float, scale: float, frame: Dictionary, feet: Vector2, shoulder: Vector2, support_center: Vector2, reach: float, two_hand: bool, longitudinal_scale: float = 1.0) -> Vector2:
	var head: Rect2 = frame.images.Head.get_used_rect()
	if not head.has_area():
		# Some authored overhead frames bake the head into Torso. Use the top of
		# that actual core silhouette, rather than treating an empty Head as none.
		var core := Rect2(frame.images.Torso.get_used_rect())
		head = Rect2(core.position, Vector2(core.size.x, minf(10, core.size.y)))
	var h1 := SOURCE_RIG.world(head.position, frame, feet, facing, SOURCE_SCALE)
	var h2 := SOURCE_RIG.world(head.end, frame, feet, facing, SOURCE_SCALE)
	var avoid := Rect2(h1, Vector2.ZERO).expand(h2).grow(2)
	var body := Rect2(asset.opaque_bounds)
	var local := Rect2()
	var first := true
	for corner: Vector2 in [body.position, Vector2(body.end.x, body.position.y), body.end, Vector2(body.position.x, body.end.y)]:
		var p := (corner - asset.grip_primary) * scale
		p.x *= longitudinal_scale
		p = Vector2(p.x * facing, p.y).rotated(angle)
		if first: local = Rect2(p, Vector2.ZERO); first = false
		else: local = local.expand(p)
	if not Rect2(hand + local.position, local.size).intersects(avoid): return hand
	var best := hand
	var score := INF
	for radius: float in [reach * 0.5, reach * 0.75, reach * 0.98]:
		for i: int in range(32):
			var candidate := shoulder + Vector2.from_angle(TAU * i / 32.0) * radius
			if two_hand and candidate.distance_to(support_center) > reach: continue
			if Rect2(candidate + local.position, local.size).intersects(avoid): continue
			var cost := hand.distance_squared_to(candidate)
			if (candidate.x - shoulder.x) * facing < 0: cost += reach * reach
			if cost < score: score = cost; best = candidate
	return best

func _actual_grips(origin: Vector2, angle: float, draw_scale: float, longitudinal_scale: float = 1.0) -> Dictionary:
	if not _uses_soft_mechanism_visual() or asset.visual_rig == null:
		var local := (asset.grip_secondary - asset.grip_primary) * draw_scale
		local.x *= longitudinal_scale
		return {"primary": origin, "secondary": origin + Vector2(local.x * facing, local.y).rotated(angle)}
	if authored_grip_rig == null:
		authored_grip_rig = PixelWeaponVisualRig.new()
		for anchor: Vector2 in [asset.grip_primary, asset.grip_secondary]:
			var part: Dictionary = asset.visual_rig._assign_part(anchor)
			authored_grip_rig.bindings.append(asset.visual_rig._make_binding(anchor, Color.WHITE, part))
	# Geometry is translation-equivariant: cache local grip deformation, then
	# translate. Four attachment probes must not rebuild an entire chain.
	var key := str([angle, facing, draw_scale, longitudinal_scale, melee_runtime.motion_ratio(), melee_runtime.state_power(), _melee_axis_reach()])
	if key == grip_cache_key and not grip_cache.is_empty():
		return {"primary": origin + Vector2(grip_cache.primary), "secondary": origin + Vector2(grip_cache.secondary)}
	var geometry := _soft_weapon_geometry(Vector2.ZERO, angle, longitudinal_scale)
	geometry.merge({"source_grip": asset.grip_primary, "facing": facing, "scale": draw_scale, "longitudinal_scale": longitudinal_scale, "pixel_snap": false, "include_metadata": false})
	var pixels: Array = PIXEL_WEAPON_DEFORMER.deform(authored_grip_rig, geometry).pixels
	grip_cache_key = key
	grip_cache = {"primary": Vector2(pixels[0].position), "secondary": Vector2(pixels[1].position)}
	return {"primary": origin + Vector2(grip_cache.primary), "secondary": origin + Vector2(grip_cache.secondary)}

func _melee_frame_contains(target: Vector2, target_radius: float = 24.0) -> bool:
	if not melee_runtime.active(): return false
	for enemy: Dictionary in enemies:
		if Vector2(enemy.pos).distance_squared_to(target) > 0.01: continue
		# Source body/hand height changed; melee must hit the same visible torso
		# used by projectiles, not an unrelated floor-root circle below the art.
		for point: Vector2 in melee_frame.get("contacts", PackedVector2Array()):
			if _projectile_contacts_enemy(point, point, {"projectile_radius_pixels": 1.0}, enemy): return true
		var field: PackedVector2Array = melee_frame.get("field", PackedVector2Array())
		if not field.is_empty(): return super._melee_frame_contains(target, target_radius)
		return false
	return super._melee_frame_contains(target, target_radius)

func _melee_root_pose() -> Dictionary:
	var attachment := _attachment()
	return {
		"hand": attachment.origin,
		"angle": attachment.angle,
		"trajectory_plane": str(attachment.get("trajectory_plane", "screen_arc")),
		"longitudinal_scale": float(attachment.get("longitudinal_scale", 1.0)),
		"depth_layer": float(attachment.get("depth_layer", 0.0)),
	}

func _firearm_hand_base() -> Vector2:
	return Vector2(_attachment().hand)

func _firearm_action_sample() -> Dictionary:
	var sample := super._firearm_action_sample()
	# Native whole-body firing/reload supplies body movement. Keep mechanism
	# recoil angle, cycle/ejection overlays; do not add a second floating root.
	sample.root_pose = {"offset": Vector2.ZERO, "rotation": float(_attachment().angle), "scale": Vector2(facing, 1)}
	return sample

func _safe_projectile_origin(requested_origin: Vector2) -> Vector2:
	return requested_origin # Never teleport a bullet backwards to hit a near target.

func _fire_bullet() -> void:
	shot_age = 0.0 # The authored fire pose exists BEFORE its actual muzzle emits.
	if not authored_moving and auto_crouch and not force_crouch and not Input.is_physical_key_pressed(KEY_C):
		authored_crouched = _should_crouch_for_target()
	var count := projectiles.size()
	super._fire_bullet()
	for i: int in range(count, projectiles.size()):
		projectiles[i].ground_lane_y = player_position.y
		projectiles[i].ground_lane_origin_y = player_position.y
	shot_records.append({"origin": _muzzle_world(), "crouched": authored_crouched, "clip": _source_pose().key, "axis_signature": ranged_runtime_profile.get("axis_signature", ""), "rotation": _firearm_recoil_rotation()})
	if shot_records.size() > 100: shot_records.pop_front()

func _should_crouch_for_target() -> bool:
	var target: Dictionary = {}
	var nearest := INF
	for enemy: Dictionary in enemies:
		var offset := Vector2(enemy.pos) - player_position
		if float(enemy.hp) <= 0 or absf(offset.y) > 30 or offset.x * facing < 30: continue
		if offset.length_squared() < nearest: target = enemy; nearest = offset.length_squared()
	if target.is_empty(): return false
	# Probe the SAME visible target collision and real AI muzzle at both poses.
	# No diagonal auto-aim and no lower invisible hitbox added to the player.
	var standing := _flat_muzzle_for_pose(0)
	var crouching := _flat_muzzle_for_pose(1)
	var end_x := Vector2(target.pos).x + 60 * facing
	var probe := {"projectile_radius_pixels": 1.0, "ground_lane_y": player_position.y}
	return not _projectile_contacts_enemy(standing, Vector2(end_x, standing.y), probe, target) and _projectile_contacts_enemy(crouching, Vector2(end_x, crouching.y), probe, target)

func _flat_muzzle_for_pose(crouch: int) -> Vector2:
	var p := _attachment(crouch)
	var local := (asset.muzzle - asset.grip_primary) * float(p.fit.draw_scale)
	return Vector2(p.hand) + Vector2(local.x * facing, local.y)

func _draw_player_and_weapon() -> void:
	if blueprint == null or asset == null: return
	var p := _attachment()
	var frame: Dictionary = p.frame
	var tint := Color("ffacac") if flash_timer > 0 else Color.WHITE
	_draw_player_pixel_shadow(player_position)
	if bool(p.get("authored_blade", false)):
		_draw_authored_blade_player(p, frame, tint)
		return
	# Draw source back arm, complete authored legs/torso/head, then the actual
	# generated weapon and front arm. The reference Weapon is never painted.
	# Rigid passive edge tools reuse the source hand and sword trajectory while
	# their real generated blade remains the only visible weapon.
	var returning_object := blueprint.delivery == "whole_object_return" and not boomerang.is_empty()
	var uses_melee_frame := not returning_object and melee_runtime.profile != null
	if uses_melee_frame: _build_melee_frame()
	var melee_behind: bool = uses_melee_frame \
		and melee_runtime.busy() \
		and str(melee_frame.get("trajectory_plane", "screen_arc")) in ["ground_sweep", "ground_orbit"] \
		and float(melee_frame.get("depth_layer", 0.0)) < -0.04
	var back := source_rig.draw_arm(self, p.support_frame, "LeftArm", p.feet, facing, SOURCE_SCALE, p.support, tint * Color("c3c7d8")) if p.fit.support_required else {}
	if not p.fit.support_required: source_rig.draw_part(self, frame, "LeftArm", p.feet, facing, SOURCE_SCALE, tint)
	var front := {}
	if melee_behind:
		_draw_melee_frame_weapon(p.hand)
		front = source_rig.draw_arm(self, p.front_frame, "RightArm", p.feet, facing, SOURCE_SCALE, p.hand, tint)
	for part: String in ["LeftLeg", "Torso", "RightLeg"]: source_rig.draw_part(self, frame, part, p.feet, facing, SOURCE_SCALE, tint)
	source_rig.draw_underarm(self, frame, p.feet, facing, SOURCE_SCALE, tint)
	source_rig.draw_part(self, frame, "Head", p.feet, facing, SOURCE_SCALE, tint)
	if returning_object:
		pass
	elif uses_melee_frame:
		if not melee_behind: _draw_melee_frame_weapon(p.hand)
	else:
		var scale := float(p.fit.draw_scale)
		draw_set_transform(p.hand, p.angle, Vector2(facing * scale, scale))
		draw_texture_rect(asset.texture, Rect2(-asset.grip_primary, Vector2(asset.canvas_size)), false)
		if _uses_firearm_runtime(): _draw_firearm_action_overlays(_firearm_action_sample(), p.hand, p.angle)
		draw_set_transform(Vector2.ZERO)
	if not melee_behind:
		front = source_rig.draw_arm(self, p.front_frame, "RightArm", p.feet, facing, SOURCE_SCALE, p.hand, tint)
	if _uses_soft_mechanism_visual(): source_rig.draw_part(self, frame, "Head", p.feet, facing, SOURCE_SCALE, tint)
	authored_evidence = {"clip": frame.key, "frame": frame.index, "front": front, "back": back, "hand": p.hand, "support": p.support, "angle": p.angle, "crouched": authored_crouched, "source_scale": SOURCE_SCALE, "reference_weapon_drawn": false, "authored_blade_route": bool(p.get("authored_blade", false)), "trajectory_plane": str(melee_frame.get("trajectory_plane", "screen_arc")) if uses_melee_frame else "screen_arc", "depth_layer": float(melee_frame.get("depth_layer", 0.0)) if uses_melee_frame else 0.0}

func _draw_melee_frame_weapon(hand: Vector2) -> void:
	for pixel: Dictionary in melee_frame.get("pixels", []):
		var size := float(pixel.get("size", 1))
		draw_rect(Rect2(Vector2(pixel.position) - Vector2.ONE * size * 0.5, Vector2.ONE * size), Color(pixel.color))
	_draw_melee_state_effect(hand)

func _draw_authored_blade_player(p: Dictionary, frame: Dictionary, tint: Color) -> void:
	# Exact source layers and order, without IK, donor limbs, connected-component
	# filtering or pose correction. Only the source example sword is omitted.
	for part: String in ["LeftLeg", "LeftArm", "Torso", "RightLeg", "Head"]:
		source_rig.draw_raw_part(self, frame, part, p.feet, facing, SOURCE_SCALE, tint)
	var smear_drawn: bool = melee_runtime.busy() and source_rig.draw_weapon_smear(self, frame, p.feet, facing, SOURCE_SCALE)
	_build_melee_frame()
	for pixel: Dictionary in melee_frame.get("pixels", []):
		var size := float(pixel.get("size", 1))
		draw_rect(Rect2(Vector2(pixel.position) - Vector2.ONE * size * 0.5, Vector2.ONE * size), Color(pixel.color))
	_draw_melee_state_effect(p.hand)
	source_rig.draw_raw_part(self, frame, "RightArm", p.feet, facing, SOURCE_SCALE, tint)
	authored_evidence = {"clip": frame.key, "frame": frame.index, "front": {"raw_source": true}, "back": {"raw_source": true}, "hand": p.hand, "support": p.support, "angle": p.angle, "crouched": authored_crouched, "source_scale": SOURCE_SCALE, "reference_weapon_drawn": false, "authored_blade_route": true, "raw_source_layers": true, "source_weapon_smear_drawn": smear_drawn}
