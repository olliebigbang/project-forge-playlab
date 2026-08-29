class_name CombatMotionProfile
extends Resource

const MOTION_FAMILIES: PackedStringArray = ["sweep", "slam", "thrust"]
const WEIGHT_CLASSES: PackedStringArray = ["light", "medium", "heavy"]
const REACH_CLASSES: PackedStringArray = ["short", "medium", "long"]
const TEMPOS: PackedStringArray = ["rapid", "balanced", "committed"]
const CONTACT_MODES: PackedStringArray = ["edge", "point", "whole_body"]
const GRIP_MODES: PackedStringArray = ["one_hand", "two_hand", "center"]
const GRIP_TOPOLOGIES: PackedStringArray = ["one_hand_handle", "two_hand_handle", "body_grip", "clamp_grip"]
const RIGIDITIES: PackedStringArray = ["rigid", "semi_rigid", "flexible"]
const CONTACT_SURFACES: PackedStringArray = ["point", "edge", "broad", "whole_body"]
const FLEX_TOPOLOGIES: PackedStringArray = ["none", "bending_shaft", "flexible_line", "linked_segments"]
const TETHER_TOPOLOGIES: PackedStringArray = ["none", "flexible_line", "linked_segments"]
const TERMINAL_LOADS: PackedStringArray = ["none", "light", "heavy"]
const TETHER_MODES: PackedStringArray = ["none", "wrap", "hook"]
const TETHER_DEPLOYMENTS: PackedStringArray = ["none", "fixed_length", "cast_retract", "launch_tension"]
const STATE_TOPOLOGIES: PackedStringArray = ["fixed", "hinged", "folding", "telescoping", "radial_expand", "rotary"]
const ACTIVATION_MODES: PackedStringArray = ["passive", "momentary", "toggle", "charge_release", "continuous_hold"]
const FUNCTIONAL_OUTPUTS: PackedStringArray = ["contact_only", "directed_stream", "radial_field", "pull_field"]

@export_enum("sweep", "slam", "thrust") var motion_family := "sweep"
@export_enum("light", "medium", "heavy") var weight_class := "medium"
@export_enum("short", "medium", "long") var reach_class := "medium"
@export_enum("rapid", "balanced", "committed") var tempo := "balanced"
@export_enum("edge", "point", "whole_body") var contact_mode := "edge"
@export_enum("one_hand", "two_hand", "center") var grip_mode := "one_hand"
@export var combo_style := "alternating"
@export var charge_style := "wide_commitment"
@export var dodge_attack_style := "advancing_strike"
@export var combo_recipe: Resource
@export var mechanism_axes: Dictionary = {}
@export var primitive_scores: Dictionary = {}
@export var compile_trace: Dictionary = {}

# Slice-only starting values. They stay centralized instead of being spread
# through player, enemy, or fixture-specific scripts.
@export var startup_seconds := 0.19
@export var active_seconds := 0.10
@export var recovery_seconds := 0.25
@export var combo_window_seconds := 0.46
@export var input_buffer_seconds := 0.16
@export var charge_threshold_seconds := 0.30
@export var dodge_attack_window_seconds := 0.26
@export var early_startup_cancel_ratio := 0.38
@export var late_recovery_cancel_ratio := 0.55
@export var reach_pixels := 104.0
@export var movement_commitment := 0.62
@export var silhouette_fill_ratio := 0.35
@export var contact_bulk_ratio := 0.20
@export var swing_arc_degrees := 110.0
@export var hitbox_thickness := 46.0
@export var control_strength := 1.0
@export var impact_sharpness := 1.0
@export var render_scale := 1.18

# Mechanism-axis V4 runtime contract. These values are compiled from anonymous
# structure and are consumed directly by movement, collision, pose and impact.
# They do not contain an object name or a player-selected attack style.
@export_enum("one_hand_handle", "two_hand_handle", "body_grip", "clamp_grip") var grip_topology := "one_hand_handle"
@export_enum("rigid", "semi_rigid", "flexible") var rigidity_mode := "rigid"
@export_enum("point", "edge", "broad", "whole_body") var primary_contact_surface := "edge"
@export_enum("none", "point", "edge", "broad", "whole_body") var secondary_contact_surface := "none"
@export var secondary_contact_stage := "none"
@export_enum("none", "bending_shaft", "flexible_line", "linked_segments") var flex_topology := "none"
@export_enum("none", "flexible_line", "linked_segments") var tether_topology := "none"
@export_enum("none", "light", "heavy") var terminal_load := "none"
@export_enum("none", "wrap", "hook") var tether_mode := "none"
@export_enum("none", "fixed_length", "cast_retract", "launch_tension") var tether_deployment := "none"
@export_enum("fixed", "hinged", "folding", "telescoping", "radial_expand", "rotary") var state_topology := "fixed"
@export_enum("passive", "momentary", "toggle", "charge_release", "continuous_hold") var activation_mode := "passive"
@export_enum("contact_only", "directed_stream", "radial_field", "pull_field") var functional_output := "contact_only"
@export_range(0.0, 1.0) var handle_leverage_ratio := 0.5
@export_range(0.0, 1.0) var body_coverage_ratio := 0.5
@export_range(0.0, 1.0) var mass_inertia_ratio := 0.5
@export_range(0.0, 1.0) var terminal_load_ratio := 0.0
@export_range(0.0, 1.0) var tether_origin_ratio := 1.0
@export var close_range_deadzone_pixels := 0.0

func configure_timing_from_tempo() -> void:
	match tempo:
		"rapid":
			startup_seconds = 0.13
			active_seconds = 0.08
			recovery_seconds = 0.18
			movement_commitment = 0.82
		"committed":
			startup_seconds = 0.29
			active_seconds = 0.13
			recovery_seconds = 0.36
			movement_commitment = 0.42
		_:
			startup_seconds = 0.19
			active_seconds = 0.10
			recovery_seconds = 0.25
			movement_commitment = 0.62

func timing_for(attack_kind: String, combo_index: int, primitive: Variant = null) -> Dictionary:
	var startup := startup_seconds
	var active := active_seconds
	var recovery := recovery_seconds
	var reach_scale := 1.0
	var movement_scale := 1.0
	var selected_primitive: Variant = primitive
	if selected_primitive == null and combo_recipe != null:
		var recipe: Variant = combo_recipe
		selected_primitive = recipe.primitive_for_attack(attack_kind, combo_index)
	if selected_primitive != null:
		startup *= selected_primitive.startup_multiplier
		active *= selected_primitive.active_multiplier
		recovery *= selected_primitive.recovery_multiplier
		reach_scale = selected_primitive.reach_multiplier
		movement_scale = selected_primitive.movement_multiplier
	elif attack_kind == "charge":
		startup *= 1.28; active *= 1.35; recovery *= 1.38
		reach_scale = 1.24; movement_scale = 0.72
	elif attack_kind == "dodge":
		startup *= 0.68; active *= 0.95; recovery *= 0.72
		reach_scale = 1.12; movement_scale = 1.35
	elif combo_index == 2:
		startup *= 1.06; active *= 1.08; recovery *= 1.08; movement_scale = 1.08
	elif combo_index >= 3:
		startup *= 1.23; active *= 1.30; recovery *= 1.34
		reach_scale = 1.18; movement_scale = 1.20
	return {
		"startup": startup, "active": active, "recovery": recovery,
		"reach_scale": reach_scale, "movement_scale": movement_scale,
	}
func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if motion_family not in MOTION_FAMILIES: errors.append("INVALID_MOTION_FAMILY")
	if weight_class not in WEIGHT_CLASSES: errors.append("INVALID_WEIGHT_CLASS")
	if reach_class not in REACH_CLASSES: errors.append("INVALID_REACH_CLASS")
	if tempo not in TEMPOS: errors.append("INVALID_TEMPO")
	if contact_mode not in CONTACT_MODES: errors.append("INVALID_CONTACT_MODE")
	if grip_mode not in GRIP_MODES: errors.append("INVALID_GRIP_MODE")
	if grip_topology not in GRIP_TOPOLOGIES: errors.append("INVALID_GRIP_TOPOLOGY")
	if rigidity_mode not in RIGIDITIES: errors.append("INVALID_RIGIDITY_MODE")
	if primary_contact_surface not in CONTACT_SURFACES: errors.append("INVALID_PRIMARY_CONTACT_SURFACE")
	if secondary_contact_surface != "none" and secondary_contact_surface not in CONTACT_SURFACES:
		errors.append("INVALID_SECONDARY_CONTACT_SURFACE")
	if secondary_contact_stage not in ["none", "hit_3"]:
		errors.append("INVALID_SECONDARY_CONTACT_STAGE")
	if flex_topology not in FLEX_TOPOLOGIES: errors.append("INVALID_FLEX_TOPOLOGY")
	if tether_topology not in TETHER_TOPOLOGIES: errors.append("INVALID_TETHER_TOPOLOGY")
	if terminal_load not in TERMINAL_LOADS: errors.append("INVALID_TERMINAL_LOAD")
	if tether_mode not in TETHER_MODES: errors.append("INVALID_TETHER_MODE")
	if tether_deployment not in TETHER_DEPLOYMENTS: errors.append("INVALID_TETHER_DEPLOYMENT")
	if state_topology not in STATE_TOPOLOGIES: errors.append("INVALID_STATE_TOPOLOGY")
	if activation_mode not in ACTIVATION_MODES: errors.append("INVALID_ACTIVATION_MODE")
	if functional_output not in FUNCTIONAL_OUTPUTS: errors.append("INVALID_FUNCTIONAL_OUTPUT")
	if activation_mode == "passive" and (state_topology != "fixed" or functional_output != "contact_only"):
		errors.append("ACTIVE_STATE_OR_OUTPUT_REQUIRES_ACTIVATION")
	if rigidity_mode == "flexible" and flex_topology == "none": errors.append("FLEXIBLE_PROFILE_REQUIRES_FLEX_TOPOLOGY")
	if rigidity_mode != "flexible" and flex_topology != "none": errors.append("FLEX_TOPOLOGY_REQUIRES_FLEXIBLE_PROFILE")
	var has_soft_path := flex_topology != "none" or tether_topology != "none"
	if not has_soft_path and (terminal_load != "none" or tether_mode != "none"):
		errors.append("SOFT_PROFILE_FACTORS_REQUIRE_SOFT_PATH")
	if tether_mode != "none" \
		and flex_topology not in ["flexible_line", "linked_segments"] \
		and tether_topology == "none":
		errors.append("TETHER_MODE_REQUIRES_LINE_OR_LINKS")
	if tether_mode == "hook" and primary_contact_surface != "point" and secondary_contact_surface != "point":
		errors.append("HOOK_TETHER_REQUIRES_POINT_CONTACT")
	if tether_topology == "none" and tether_deployment != "none":
		errors.append("TETHER_DEPLOYMENT_REQUIRES_ATTACHED_TETHER")
	if tether_topology != "none" and tether_deployment == "none":
		errors.append("ATTACHED_TETHER_REQUIRES_DEPLOYMENT")
	if handle_leverage_ratio < 0.0 or handle_leverage_ratio > 1.0 \
		or body_coverage_ratio < 0.0 or body_coverage_ratio > 1.0 \
		or mass_inertia_ratio < 0.0 or mass_inertia_ratio > 1.0 \
		or terminal_load_ratio < 0.0 or terminal_load_ratio > 1.0 \
		or tether_origin_ratio < 0.0 or tether_origin_ratio > 1.0 \
		or close_range_deadzone_pixels < 0.0:
		errors.append("INVALID_MECHANISM_RUNTIME_VALUE")
	if startup_seconds <= 0.0 or active_seconds <= 0.0 or recovery_seconds <= 0.0:
		errors.append("INVALID_TIMING")
	if combo_recipe != null:
		var recipe: Variant = combo_recipe
		errors.append_array(recipe.validation_errors())
	return errors

func to_dict() -> Dictionary:
	var recipe: Variant = combo_recipe
	return {
		"motion_family": motion_family, "weight_class": weight_class,
		"reach_class": reach_class, "tempo": tempo, "contact_mode": contact_mode,
		"grip_mode": grip_mode, "combo_style": combo_style,
		"charge_style": charge_style, "dodge_attack_style": dodge_attack_style,
		"mechanism_axes": mechanism_axes.duplicate(true),
		"primitive_scores": primitive_scores.duplicate(true),
		"compile_trace": compile_trace.duplicate(true),
		"combo_recipe": recipe.to_dict() if recipe != null else null,
		"startup": startup_seconds, "active": active_seconds,
		"recovery": recovery_seconds, "combo_window": combo_window_seconds,
		"input_buffer": input_buffer_seconds, "charge_threshold": charge_threshold_seconds,
		"dodge_attack_window": dodge_attack_window_seconds, "reach_pixels": reach_pixels,
		"silhouette_fill_ratio": silhouette_fill_ratio,
		"contact_bulk_ratio": contact_bulk_ratio,
		"swing_arc_degrees": swing_arc_degrees,
		"hitbox_thickness": hitbox_thickness,
		"control_strength": control_strength,
		"impact_sharpness": impact_sharpness,
		"render_scale": render_scale,
		"grip_topology": grip_topology,
		"rigidity_mode": rigidity_mode,
		"primary_contact_surface": primary_contact_surface,
		"secondary_contact_surface": secondary_contact_surface,
		"secondary_contact_stage": secondary_contact_stage,
		"flex_topology": flex_topology,
		"tether_topology": tether_topology,
		"terminal_load": terminal_load,
		"tether_mode": tether_mode,
		"tether_deployment": tether_deployment,
		"state_topology": state_topology,
		"activation_mode": activation_mode,
		"functional_output": functional_output,
		"handle_leverage_ratio": handle_leverage_ratio,
		"body_coverage_ratio": body_coverage_ratio,
		"mass_inertia_ratio": mass_inertia_ratio,
		"terminal_load_ratio": terminal_load_ratio,
		"tether_origin_ratio": tether_origin_ratio,
		"close_range_deadzone_pixels": close_range_deadzone_pixels,
	}
