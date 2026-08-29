class_name ObjectAffordanceProfile
extends Resource

const HANDLE_LENGTHS: PackedStringArray = ["none", "short", "medium", "long"]
const BODY_LENGTHS: PackedStringArray = ["short", "medium", "long"]
const GRIP_TOPOLOGIES: PackedStringArray = ["one_hand_handle", "two_hand_handle", "body_grip", "clamp_grip"]
const MASS_DISTRIBUTIONS: PackedStringArray = ["rear", "balanced", "front"]
const CONTACT_SURFACES: PackedStringArray = ["point", "edge", "broad", "whole_body"]
const SECONDARY_CONTACT_SURFACES: PackedStringArray = ["none", "point", "edge", "broad", "whole_body"]
const RIGIDITIES: PackedStringArray = ["rigid", "semi_rigid", "flexible"]
const FLEX_TOPOLOGIES: PackedStringArray = ["none", "bending_shaft", "flexible_line", "linked_segments"]
const TETHER_TOPOLOGIES: PackedStringArray = ["none", "flexible_line", "linked_segments"]
const TERMINAL_LOADS: PackedStringArray = ["none", "light", "heavy"]
const TETHER_MODES: PackedStringArray = ["none", "wrap", "hook"]
const TETHER_DEPLOYMENTS: PackedStringArray = ["none", "fixed_length", "cast_retract", "launch_tension"]
const STATE_TOPOLOGIES: PackedStringArray = ["fixed", "hinged", "folding", "telescoping", "radial_expand", "rotary"]
const ACTIVATION_MODES: PackedStringArray = ["passive", "momentary", "toggle", "charge_release", "continuous_hold"]
const FUNCTIONAL_OUTPUTS: PackedStringArray = ["contact_only", "directed_stream", "radial_field", "pull_field"]

@export_enum("none", "short", "medium", "long") var handle_length := "medium"
@export_enum("short", "medium", "long") var body_length := "medium"
@export_enum("one_hand_handle", "two_hand_handle", "body_grip", "clamp_grip") var grip_topology := "one_hand_handle"
@export_enum("rear", "balanced", "front") var mass_distribution := "balanced"
@export_enum("point", "edge", "broad", "whole_body") var contact_surface := "point"
@export_enum("none", "point", "edge", "broad", "whole_body") var secondary_contact_surface := "none"
@export_enum("rigid", "semi_rigid", "flexible") var rigidity := "rigid"
@export_enum("none", "bending_shaft", "flexible_line", "linked_segments") var flex_topology := "none"
@export_enum("none", "flexible_line", "linked_segments") var tether_topology := "none"
@export_enum("none", "light", "heavy") var terminal_load := "none"
@export_enum("none", "wrap", "hook") var tether_mode := "none"
@export_enum("none", "fixed_length", "cast_retract", "launch_tension") var tether_deployment := "none"
@export_enum("fixed", "hinged", "folding", "telescoping", "radial_expand", "rotary") var state_topology := "fixed"
@export_enum("passive", "momentary", "toggle", "charge_release", "continuous_hold") var activation_mode := "passive"
@export_enum("contact_only", "directed_stream", "radial_field", "pull_field") var functional_output := "contact_only"
@export var has_point := false
@export var has_edge := false
@export var has_broad_face := false
@export var has_barrel := false
@export var has_stock := false
@export_range(0.65, 1.0) var confidence := 1.0
@export var evidence_parts := PackedStringArray()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if handle_length not in HANDLE_LENGTHS:
		errors.append("INVALID_HANDLE_LENGTH")
	if body_length not in BODY_LENGTHS:
		errors.append("INVALID_BODY_LENGTH")
	if grip_topology not in GRIP_TOPOLOGIES:
		errors.append("INVALID_GRIP_TOPOLOGY")
	if rigidity not in RIGIDITIES:
		errors.append("INVALID_RIGIDITY")
	if flex_topology not in FLEX_TOPOLOGIES:
		errors.append("INVALID_FLEX_TOPOLOGY")
	if tether_topology not in TETHER_TOPOLOGIES:
		errors.append("INVALID_TETHER_TOPOLOGY")
	if terminal_load not in TERMINAL_LOADS:
		errors.append("INVALID_TERMINAL_LOAD")
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
	if mass_distribution not in MASS_DISTRIBUTIONS:
		errors.append("INVALID_MASS_DISTRIBUTION")
	if contact_surface not in CONTACT_SURFACES:
		errors.append("INVALID_CONTACT_SURFACE")
	if secondary_contact_surface not in SECONDARY_CONTACT_SURFACES:
		errors.append("INVALID_SECONDARY_CONTACT_SURFACE")
	if handle_length == "none" and grip_topology in ["one_hand_handle", "two_hand_handle"]:
		errors.append("HANDLELESS_OBJECT_REQUIRES_BODY_OR_CLAMP_GRIP")
	if handle_length != "none" and grip_topology == "body_grip":
		errors.append("BODY_GRIP_REQUIRES_HANDLE_LENGTH_NONE")
	if rigidity == "flexible" and flex_topology == "none":
		errors.append("FLEXIBLE_OBJECT_REQUIRES_FLEX_TOPOLOGY")
	if rigidity != "flexible" and flex_topology != "none":
		errors.append("FLEX_TOPOLOGY_REQUIRES_FLEXIBLE_OBJECT")
	var has_soft_path := flex_topology != "none" or tether_topology != "none"
	if not has_soft_path and (terminal_load != "none" or tether_mode != "none"):
		errors.append("SOFT_FACTORS_REQUIRE_SOFT_PATH")
	if tether_mode != "none" \
		and flex_topology not in ["flexible_line", "linked_segments"] \
		and tether_topology == "none":
		errors.append("TETHER_MODE_REQUIRES_LINE_OR_LINKS")
	if tether_mode == "hook" and not (has_point or contact_surface == "point" or secondary_contact_surface == "point"):
		errors.append("HOOK_TETHER_REQUIRES_POINT_CONTACT")
	if tether_topology == "none" and tether_deployment != "none":
		errors.append("TETHER_DEPLOYMENT_REQUIRES_ATTACHED_TETHER")
	if tether_topology != "none" and tether_deployment == "none":
		errors.append("ATTACHED_TETHER_REQUIRES_DEPLOYMENT")
	if activation_mode == "passive" and (state_topology != "fixed" or functional_output != "contact_only"):
		errors.append("ACTIVE_STATE_OR_OUTPUT_REQUIRES_ACTIVATION")
	if not is_finite(confidence) or confidence < 0.65 or confidence > 1.0:
		errors.append("INVALID_AFFORDANCE_CONFIDENCE")
	if evidence_parts.is_empty():
		errors.append("MISSING_AFFORDANCE_EVIDENCE")
	return errors


func to_dict() -> Dictionary:
	return {
		"handle_length": handle_length,
		"body_length": body_length,
		"grip_topology": grip_topology,
		"rigidity": rigidity,
		"flex_topology": flex_topology,
		"tether_topology": tether_topology,
		"terminal_load": terminal_load,
		"tether_mode": tether_mode,
		"tether_deployment": tether_deployment,
		"state_topology": state_topology,
		"activation_mode": activation_mode,
		"functional_output": functional_output,
		"mass_distribution": mass_distribution,
		"contact_surface": contact_surface,
		"secondary_contact_surface": secondary_contact_surface,
		"has_point": has_point,
		"has_edge": has_edge,
		"has_broad_face": has_broad_face,
		"has_barrel": has_barrel,
		"has_stock": has_stock,
		"confidence": confidence,
		"evidence_parts": Array(evidence_parts),
	}
