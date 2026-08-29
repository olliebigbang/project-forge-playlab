class_name MotionPrimitive
extends Resource

const MOTION_FAMILIES: PackedStringArray = ["bash", "sweep", "thrust", "slam", "spin"]
const CONTACT_ANCHORS: PackedStringArray = ["tip", "muzzle", "rear_contact", "whole_body"]
const CONTACT_SURFACES: PackedStringArray = ["point", "edge", "broad", "whole_body"]
const FLEX_TOPOLOGIES: PackedStringArray = ["none", "bending_shaft", "flexible_line", "linked_segments"]
const TETHER_TOPOLOGIES: PackedStringArray = ["none", "flexible_line", "linked_segments"]
const TETHER_MODES: PackedStringArray = ["none", "wrap", "hook"]
const TETHER_DEPLOYMENTS: PackedStringArray = ["none", "fixed_length", "cast_retract", "launch_tension"]
const STATE_TOPOLOGIES: PackedStringArray = ["fixed", "hinged", "folding", "telescoping", "radial_expand", "rotary"]
const ACTIVATION_MODES: PackedStringArray = ["passive", "momentary", "toggle", "charge_release", "continuous_hold"]
const FUNCTIONAL_OUTPUTS: PackedStringArray = ["contact_only", "directed_stream", "radial_field", "pull_field"]

@export_enum("bash", "sweep", "thrust", "slam", "spin") var motion_family := "sweep"
@export var start_angle := -1.18
@export var end_angle := 1.02
@export_enum("tip", "muzzle", "rear_contact", "whole_body") var contact_anchor := "tip"
@export_enum("point", "edge", "broad", "whole_body") var contact_surface := "edge"
@export var uses_secondary_contact := false
@export var local_start_offset := Vector2.ZERO
@export var local_end_offset := Vector2.ZERO
@export var extension_pixels := 0.0
@export var root_motion_distance := 17.0
@export_range(0.0, 1.0) var inertia_ratio := 0.5
@export_range(0.0, 1.0) var trajectory_lag_ratio := 0.0
@export_range(0.0, 1.2) var follow_through_radians := 0.0
@export_enum("none", "bending_shaft", "flexible_line", "linked_segments") var flex_topology := "none"
@export_enum("none", "flexible_line", "linked_segments") var tether_topology := "none"
@export_range(0.0, 1.0) var tether_origin_ratio := 1.0
@export_range(0.0, 1.0) var terminal_load_ratio := 0.0
@export_range(0.0, 0.95) var soft_contact_start_ratio := 0.0
@export_enum("none", "wrap", "hook") var tether_mode := "none"
@export var tether_strength := 0.0
@export_enum("none", "fixed_length", "cast_retract", "launch_tension") var tether_deployment := "none"
@export_enum("fixed", "hinged", "folding", "telescoping", "radial_expand", "rotary") var state_topology := "fixed"
@export_enum("passive", "momentary", "toggle", "charge_release", "continuous_hold") var activation_mode := "passive"
@export_enum("contact_only", "directed_stream", "radial_field", "pull_field") var functional_output := "contact_only"
@export_range(0.0, 1.0) var state_extent_ratio := 0.0
@export var inner_deadzone_pixels := 0.0
@export_range(1.0, 360.0) var contact_arc_degrees := 110.0
@export var damage_multiplier := 1.0
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
	if contact_surface not in CONTACT_SURFACES:
		errors.append("INVALID_CONTACT_SURFACE")
	if flex_topology not in FLEX_TOPOLOGIES:
		errors.append("INVALID_FLEX_TOPOLOGY")
	if tether_topology not in TETHER_TOPOLOGIES:
		errors.append("INVALID_TETHER_TOPOLOGY")
	if tether_mode not in TETHER_MODES:
		errors.append("INVALID_TETHER_MODE")
	if tether_deployment not in TETHER_DEPLOYMENTS:
		errors.append("INVALID_TETHER_DEPLOYMENT")
	if state_topology not in STATE_TOPOLOGIES:
		errors.append("INVALID_STATE_TOPOLOGY")
	if activation_mode not in ACTIVATION_MODES:
		errors.append("INVALID_ACTIVATION_MODE")
	if functional_output not in FUNCTIONAL_OUTPUTS:
		errors.append("INVALID_FUNCTIONAL_OUTPUT")
	var numeric_values: Array[float] = [
		start_angle, end_angle, extension_pixels,
		local_start_offset.x, local_start_offset.y, local_end_offset.x, local_end_offset.y,
		root_motion_distance, inertia_ratio, trajectory_lag_ratio, follow_through_radians,
		tether_origin_ratio, terminal_load_ratio, soft_contact_start_ratio, tether_strength,
		state_extent_ratio,
		inner_deadzone_pixels, contact_arc_degrees, damage_multiplier,
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
	if extension_pixels < 0.0 or root_motion_distance < 0.0 or inner_deadzone_pixels < 0.0:
		errors.append("NEGATIVE_EXTENSION")
	if inertia_ratio < 0.0 or inertia_ratio > 1.0 \
		or trajectory_lag_ratio < 0.0 or trajectory_lag_ratio > 1.0 \
		or follow_through_radians < 0.0 or follow_through_radians > 1.2:
		errors.append("INVALID_TRAJECTORY_PARAMETER")
	if terminal_load_ratio < 0.0 or terminal_load_ratio > 1.0 \
		or tether_origin_ratio < 0.0 or tether_origin_ratio > 1.0 \
		or soft_contact_start_ratio < 0.0 or soft_contact_start_ratio > 0.95 \
		or tether_strength < 0.0:
		errors.append("INVALID_SOFT_BODY_PARAMETER")
	if state_extent_ratio < 0.0 or state_extent_ratio > 1.0:
		errors.append("INVALID_STATE_EXTENT")
	if state_extent_ratio > 0.0 and activation_mode == "passive":
		errors.append("STATE_EXTENT_REQUIRES_ACTIVATION")
	var has_soft_path := flex_topology != "none" or tether_topology != "none"
	if not has_soft_path and (terminal_load_ratio > 0.0 or soft_contact_start_ratio > 0.0 or tether_mode != "none"):
		errors.append("SOFT_BODY_PARAMETER_WITHOUT_SOFT_PATH")
	if tether_mode != "none" \
		and flex_topology not in ["flexible_line", "linked_segments"] \
		and tether_topology == "none":
		errors.append("TETHER_MODE_REQUIRES_LINE_OR_LINKS")
	if tether_topology != "none" and (tether_origin_ratio <= 0.0 or tether_origin_ratio >= 1.0):
		errors.append("INVALID_TETHER_ORIGIN_RATIO")
	if tether_topology == "none" and tether_deployment != "none":
		errors.append("TETHER_DEPLOYMENT_REQUIRES_ATTACHED_TETHER")
	if tether_topology != "none" and tether_deployment == "none":
		errors.append("ATTACHED_TETHER_REQUIRES_DEPLOYMENT")
	if contact_arc_degrees < 1.0 or contact_arc_degrees > 360.0 or damage_multiplier <= 0.0:
		errors.append("INVALID_CONTACT_PARAMETER")
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
		"contact_surface": contact_surface,
		"uses_secondary_contact": uses_secondary_contact,
		"start_angle": start_angle,
		"end_angle": end_angle,
		"local_start_offset": [local_start_offset.x, local_start_offset.y],
		"local_end_offset": [local_end_offset.x, local_end_offset.y],
		"extension_pixels": extension_pixels,
		"root_motion_distance": root_motion_distance,
		"inertia_ratio": inertia_ratio,
		"trajectory_lag_ratio": trajectory_lag_ratio,
		"follow_through_radians": follow_through_radians,
		"flex_topology": flex_topology,
		"tether_topology": tether_topology,
		"tether_origin_ratio": tether_origin_ratio,
		"terminal_load_ratio": terminal_load_ratio,
		"soft_contact_start_ratio": soft_contact_start_ratio,
		"tether_mode": tether_mode,
		"tether_strength": tether_strength,
		"tether_deployment": tether_deployment,
		"state_topology": state_topology,
		"activation_mode": activation_mode,
		"functional_output": functional_output,
		"state_extent_ratio": state_extent_ratio,
		"inner_deadzone_pixels": inner_deadzone_pixels,
		"contact_arc_degrees": contact_arc_degrees,
		"damage_multiplier": damage_multiplier,
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
