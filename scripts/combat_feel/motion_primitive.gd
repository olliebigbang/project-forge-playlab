class_name MotionPrimitive
extends Resource

const MOTION_FAMILIES: PackedStringArray = ["bash", "sweep", "thrust", "slam", "spin"]
const CONTACT_ANCHORS: PackedStringArray = ["tip", "muzzle", "rear_contact", "whole_body"]

@export_enum("bash", "sweep", "thrust", "slam", "spin") var motion_family := "sweep"
@export var start_angle := -1.18
@export var end_angle := 1.02
@export_enum("tip", "muzzle", "rear_contact", "whole_body") var contact_anchor := "tip"
@export var local_start_offset := Vector2.ZERO
@export var local_end_offset := Vector2.ZERO
@export var extension_pixels := 0.0
@export var root_motion_distance := 17.0
@export var startup_multiplier := 1.0
@export var active_multiplier := 1.0
@export var recovery_multiplier := 1.0
@export var reach_multiplier := 1.0
@export var movement_multiplier := 1.0
@export var hitbox_multiplier := 1.0
@export var hitbox_width_multiplier := 1.0
@export var hitbox_length_multiplier := 1.0
@export var knockback_multiplier := 1.0
@export var stagger_multiplier := 1.0
@export var hitstop_multiplier := 1.0
@export var camera_kick_multiplier := 1.0
@export_range(0.0, 1.0) var movement_allowed_ratio := 0.0


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if motion_family not in MOTION_FAMILIES:
		errors.append("INVALID_MOTION_FAMILY")
	if contact_anchor not in CONTACT_ANCHORS:
		errors.append("INVALID_CONTACT_ANCHOR")
	var numeric_values: Array[float] = [
		start_angle, end_angle, extension_pixels,
		local_start_offset.x, local_start_offset.y, local_end_offset.x, local_end_offset.y,
		root_motion_distance,
		startup_multiplier, active_multiplier, recovery_multiplier,
		reach_multiplier, movement_multiplier, hitbox_multiplier,
		hitbox_width_multiplier, hitbox_length_multiplier,
		knockback_multiplier, stagger_multiplier, hitstop_multiplier, camera_kick_multiplier,
		movement_allowed_ratio,
	]
	for value: float in numeric_values:
		if not is_finite(value):
			errors.append("NON_FINITE_MOTION_VALUE")
			break
	if extension_pixels < 0.0 or root_motion_distance < 0.0:
		errors.append("NEGATIVE_EXTENSION")
	if startup_multiplier <= 0.0 or active_multiplier <= 0.0 or recovery_multiplier <= 0.0:
		errors.append("INVALID_TIMING_MULTIPLIER")
	if reach_multiplier <= 0.0 or movement_multiplier <= 0.0 or hitbox_multiplier <= 0.0 \
		or hitbox_width_multiplier <= 0.0 or hitbox_length_multiplier <= 0.0 \
		or knockback_multiplier <= 0.0 or stagger_multiplier <= 0.0 \
		or hitstop_multiplier <= 0.0 or camera_kick_multiplier <= 0.0:
		errors.append("INVALID_SPATIAL_MULTIPLIER")
	if movement_allowed_ratio < 0.0 or movement_allowed_ratio > 1.0:
		errors.append("INVALID_MOVEMENT_ALLOWED_RATIO")
	return errors


func to_dict() -> Dictionary:
	return {
		"motion_family": motion_family,
		"contact_anchor": contact_anchor,
		"start_angle": start_angle,
		"end_angle": end_angle,
		"local_start_offset": [local_start_offset.x, local_start_offset.y],
		"local_end_offset": [local_end_offset.x, local_end_offset.y],
		"extension_pixels": extension_pixels,
		"root_motion_distance": root_motion_distance,
		"startup_multiplier": startup_multiplier,
		"active_multiplier": active_multiplier,
		"recovery_multiplier": recovery_multiplier,
		"reach_multiplier": reach_multiplier,
		"movement_multiplier": movement_multiplier,
		"hitbox_multiplier": hitbox_multiplier,
		"hitbox_width_multiplier": hitbox_width_multiplier,
		"hitbox_length_multiplier": hitbox_length_multiplier,
		"knockback_multiplier": knockback_multiplier,
		"stagger_multiplier": stagger_multiplier,
		"hitstop_multiplier": hitstop_multiplier,
		"camera_kick_multiplier": camera_kick_multiplier,
		"movement_allowed_ratio": movement_allowed_ratio,
	}
