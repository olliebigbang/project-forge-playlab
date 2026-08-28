class_name FirearmActionChoreography
extends RefCounted

# A presentation-only adapter for the V5 firearm runtime.  It deliberately
# consumes numeric mechanism fields rather than identity or family names so the
# same axes always produce the same pose in every arena.

const SCHEMA := "forge-firearm-action-choreography-v1"
const DRAW_SCALE := 1.15

const CYCLE_SELF_LOADING := 0
const CYCLE_BOLT := 1
const CYCLE_PUMP := 2
const CYCLE_CYLINDER := 3

const RELOAD_MAGAZINE := 0
const RELOAD_SINGLE_ROUND := 1
const RELOAD_CYLINDER := 2
const RELOAD_BELT := 3


static func sample(
	runtime: Dictionary,
	timers: Dictionary,
	ammo: Dictionary,
	facing: float
) -> Dictionary:
	var safe_facing := -1.0 if facing < 0.0 else 1.0
	var recoil_pixels := maxf(0.0, float(timers.get("recoil_pixels", 0.0)))
	var climb_degrees := float(timers.get("muzzle_climb_degrees", 0.0))
	var reload_seconds := maxf(0.01, float(runtime.get("reload_seconds", 1.2)))
	var reload_timer := maxf(0.0, float(timers.get("reload_timer", 0.0)))
	var reload_progress := clampf(1.0 - reload_timer / reload_seconds, 0.0, 1.0)
	var cycle_duration := _cycle_duration(runtime)
	var cycle_timer := maxf(0.0, float(timers.get("cycle_timer", 0.0)))
	var cycle_progress := clampf(1.0 - cycle_timer / cycle_duration, 0.0, 1.0)
	var flash_duration := maxf(0.01, float(runtime.get("muzzle_flash_seconds", 0.065)))
	var flash_timer := maxf(0.0, float(timers.get("muzzle_flash_timer", 0.0)))
	var shot_progress := clampf(1.0 - flash_timer / flash_duration, 0.0, 1.0)
	var cycle_code := clampi(int(runtime.get("cycle_action_code", CYCLE_SELF_LOADING)), 0, 3)
	var reload_code := clampi(int(runtime.get("reload_feed_code", RELOAD_MAGAZINE)), 0, 3)

	var root_rotation := deg_to_rad(-climb_degrees) * safe_facing
	var root_offset := Vector2(-recoil_pixels * safe_facing, -recoil_pixels * 0.12)
	if reload_timer > 0.0:
		root_rotation += sin(reload_progress * PI) * 0.48 * safe_facing
		root_offset.y += sin(reload_progress * PI) * 3.0

	var cycle_pose := _cycle_pose(cycle_code, cycle_timer, cycle_progress, flash_timer, shot_progress)
	var reload_pose := _reload_pose(reload_code, reload_timer, reload_progress, ammo)
	var ejection_pose := _ejection_pose(
		cycle_code,
		cycle_timer,
		cycle_progress,
		flash_timer,
		shot_progress,
		reload_code,
		reload_timer,
		reload_progress
	)
	var base_flash_scale := clampf(float(runtime.get("muzzle_flash_scale", 1.0)), 0.35, 3.0)
	var pellet_count := maxi(1, int(runtime.get("pellet_count", 1)))
	var pellet_width := 1.0 + minf(0.9, float(pellet_count - 1) * 0.07)
	var spread := clampf(float(runtime.get("spread", runtime.get("spread_velocity", 0.0))), 0.0, 30.0)
	var spread_height := 1.0 + spread * 0.012

	return {
		"schema": SCHEMA,
		"root_pose": {
			"offset": root_offset,
			"rotation": root_rotation,
			"scale": Vector2(safe_facing, 1.0),
		},
		"cycle_overlay_pose": cycle_pose,
		"reload_object_pose": reload_pose,
		"ejection_pose": ejection_pose,
		"flash_scale": base_flash_scale,
		"flash_pose": {
			"visible": flash_timer > 0.0,
			"scale": Vector2(base_flash_scale * pellet_width, base_flash_scale * spread_height),
			"pellet_count": pellet_count,
			"spread": spread,
		},
		"cycle_action_code": cycle_code,
		"reload_feed_code": reload_code,
		"player_confirmation_required": false,
	}


static func world_anchor(
	hand_root: Vector2,
	local_anchor: Vector2,
	grip_anchor: Vector2,
	root_pose: Dictionary,
	draw_scale: float = DRAW_SCALE
) -> Vector2:
	var facing_scale := root_pose.get("scale", Vector2.ONE) as Vector2
	var relative := (local_anchor - grip_anchor) * draw_scale
	relative.x *= -1.0 if facing_scale.x < 0.0 else 1.0
	return (
		hand_root
		+ (root_pose.get("offset", Vector2.ZERO) as Vector2)
		+ relative.rotated(float(root_pose.get("rotation", 0.0)))
	)


static func weapon_origin(grip_anchor: Vector2, draw_scale: float = DRAW_SCALE) -> Vector2:
	return -grip_anchor * draw_scale


static func _cycle_duration(runtime: Dictionary) -> float:
	var overhead := float(runtime.get(
		"cycle_overhead_seconds",
		runtime.get("manual_cycle_overhead_seconds", 0.0)
	))
	return maxf(
		0.01,
		float(runtime.get("shot_interval_seconds", 0.18))
			+ overhead
	)


static func _cycle_pose(
	code: int,
	cycle_timer: float,
	cycle_progress: float,
	flash_timer: float,
	shot_progress: float
) -> Dictionary:
	var pose := {
		"visible": false,
		"kind": "none",
		"local_position": Vector2.ZERO,
		"rotation": 0.0,
		"progress": 0.0,
	}
	match code:
		CYCLE_SELF_LOADING:
			pose["visible"] = flash_timer > 0.0
			pose["kind"] = "self_loading_bolt"
			pose["local_position"] = Vector2(-7.0 * sin(shot_progress * PI), 0.0)
			pose["progress"] = shot_progress
		CYCLE_BOLT:
			pose["visible"] = cycle_timer > 0.0
			pose["kind"] = "bolt_handle"
			pose["local_position"] = Vector2(-11.0 * sin(cycle_progress * PI), 0.0)
			pose["rotation"] = -0.55 * sin(cycle_progress * PI)
			pose["progress"] = cycle_progress
		CYCLE_PUMP:
			pose["visible"] = cycle_timer > 0.0
			pose["kind"] = "pump_fore_end"
			pose["local_position"] = Vector2(-14.0 * sin(cycle_progress * PI), 0.0)
			pose["progress"] = cycle_progress
		CYCLE_CYLINDER:
			pose["visible"] = flash_timer > 0.0 or cycle_timer > 0.0
			pose["kind"] = "cylinder_index"
			pose["rotation"] = (shot_progress if flash_timer > 0.0 else cycle_progress) * PI / 3.0
			pose["progress"] = shot_progress if flash_timer > 0.0 else cycle_progress
	return pose


static func _reload_pose(code: int, reload_timer: float, progress: float, ammo: Dictionary) -> Dictionary:
	var magazine_size := maxi(1, int(ammo.get("magazine_size", 1)))
	var ammo_in_magazine := clampi(int(ammo.get("ammo_in_magazine", 0)), 0, magazine_size)
	var pose := {
		"visible": reload_timer > 0.0,
		"kind": ["magazine", "single_round", "speedloader", "belt_box"][code],
		"local_position": Vector2.ZERO,
		"rotation": 0.0,
		"progress": progress,
		"round_fraction": float(ammo_in_magazine) / float(magazine_size),
	}
	if reload_timer <= 0.0:
		return pose
	var lift := sin(progress * PI)
	match code:
		RELOAD_MAGAZINE:
			pose["local_position"] = Vector2(8.0, 30.0 - lift * 15.0)
			pose["rotation"] = (1.0 - progress) * 0.24
		RELOAD_SINGLE_ROUND:
			pose["local_position"] = Vector2(26.0 - progress * 18.0, 17.0 + lift * 4.0)
			pose["rotation"] = progress * 0.35
		RELOAD_CYLINDER:
			pose["local_position"] = Vector2(4.0, 15.0 + lift * 8.0)
			pose["rotation"] = progress * TAU
		RELOAD_BELT:
			pose["local_position"] = Vector2(10.0, 27.0 - lift * 10.0)
			pose["rotation"] = -0.12 * lift
	return pose


static func _ejection_pose(
	code: int,
	cycle_timer: float,
	cycle_progress: float,
	flash_timer: float,
	shot_progress: float,
	reload_code: int,
	reload_timer: float,
	reload_progress: float
) -> Dictionary:
	var active_progress := shot_progress
	var visible := flash_timer > 0.0 and code == CYCLE_SELF_LOADING
	var kind := "spent_casing"
	if code in [CYCLE_BOLT, CYCLE_PUMP]:
		active_progress = cycle_progress
		visible = cycle_timer > 0.0 and cycle_progress > 0.22 and cycle_progress < 0.78
		kind = "spent_shell" if code == CYCLE_PUMP else "spent_casing"
	elif code == CYCLE_CYLINDER:
		active_progress = reload_progress
		visible = reload_code == RELOAD_CYLINDER and reload_timer > 0.0 and reload_progress > 0.14 and reload_progress < 0.48
		kind = "spent_casing_cluster"
	return {
		"visible": visible,
		"kind": kind,
		"local_position": Vector2(8.0 - active_progress * 7.0, -8.0 - sin(active_progress * PI) * 11.0),
		"rotation": active_progress * TAU * 1.4,
		"progress": active_progress,
	}
