class_name CombatMotionProfile
extends Resource

const MOTION_FAMILIES: PackedStringArray = ["sweep", "slam", "thrust"]
const WEIGHT_CLASSES: PackedStringArray = ["light", "medium", "heavy"]
const REACH_CLASSES: PackedStringArray = ["short", "medium", "long"]
const TEMPOS: PackedStringArray = ["rapid", "balanced", "committed"]
const CONTACT_MODES: PackedStringArray = ["edge", "point", "whole_body"]
const GRIP_MODES: PackedStringArray = ["one_hand", "two_hand", "center"]

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
@export var silhouette_grip_inertia_proxy_raw := 0.0
@export_enum("arrest", "follow_through", "rebound") var contact_resolution := "arrest"
@export_enum("one_hand_handle", "two_hand_handle", "body_grip", "clamp_grip") var grip_topology := "one_hand_handle"
@export var contact_bulk_ratio := 0.20
@export var swing_arc_degrees := 110.0
@export var hitbox_thickness := 46.0
@export var control_strength := 1.0
@export var impact_sharpness := 1.0
@export var render_scale := 1.18

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
		"silhouette_grip_inertia_proxy_raw": silhouette_grip_inertia_proxy_raw,
		"contact_resolution": contact_resolution,
		"grip_topology": grip_topology,
		"contact_bulk_ratio": contact_bulk_ratio,
		"swing_arc_degrees": swing_arc_degrees,
		"hitbox_thickness": hitbox_thickness,
		"control_strength": control_strength,
		"impact_sharpness": impact_sharpness,
		"render_scale": render_scale,
	}
