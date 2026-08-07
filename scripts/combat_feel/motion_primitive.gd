class_name MotionPrimitive
extends Resource

const MOTION_FAMILIES: PackedStringArray = ["sweep", "slam", "thrust"]

@export_enum("sweep", "slam", "thrust") var motion_family := "sweep"
@export var start_angle := -1.18
@export var end_angle := 1.02
@export var extension_pixels := 0.0
@export var startup_multiplier := 1.0
@export var active_multiplier := 1.0
@export var recovery_multiplier := 1.0
@export var reach_multiplier := 1.0
@export var movement_multiplier := 1.0
@export var hitbox_multiplier := 1.0


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if motion_family not in MOTION_FAMILIES:
		errors.append("INVALID_MOTION_FAMILY")
	var numeric_values: Array[float] = [
		start_angle, end_angle, extension_pixels,
		startup_multiplier, active_multiplier, recovery_multiplier,
		reach_multiplier, movement_multiplier, hitbox_multiplier,
	]
	for value: float in numeric_values:
		if not is_finite(value):
			errors.append("NON_FINITE_MOTION_VALUE")
			break
	if extension_pixels < 0.0:
		errors.append("NEGATIVE_EXTENSION")
	if startup_multiplier <= 0.0 or active_multiplier <= 0.0 or recovery_multiplier <= 0.0:
		errors.append("INVALID_TIMING_MULTIPLIER")
	if reach_multiplier <= 0.0 or movement_multiplier <= 0.0 or hitbox_multiplier <= 0.0:
		errors.append("INVALID_SPATIAL_MULTIPLIER")
	return errors


func to_dict() -> Dictionary:
	return {
		"motion_family": motion_family,
		"start_angle": start_angle,
		"end_angle": end_angle,
		"extension_pixels": extension_pixels,
		"startup_multiplier": startup_multiplier,
		"active_multiplier": active_multiplier,
		"recovery_multiplier": recovery_multiplier,
		"reach_multiplier": reach_multiplier,
		"movement_multiplier": movement_multiplier,
		"hitbox_multiplier": hitbox_multiplier,
	}
