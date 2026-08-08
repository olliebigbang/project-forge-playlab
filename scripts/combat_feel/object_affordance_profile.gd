class_name ObjectAffordanceProfile
extends Resource

const HANDLE_LENGTHS: PackedStringArray = ["none", "short", "medium", "long"]
const BODY_LENGTHS: PackedStringArray = ["short", "medium", "long"]
const GRIP_TOPOLOGIES: PackedStringArray = ["one_hand_handle", "two_hand_handle", "body_grip", "clamp_grip"]
const MASS_DISTRIBUTIONS: PackedStringArray = ["rear", "balanced", "front"]
const CONTACT_SURFACES: PackedStringArray = ["point", "edge", "broad", "whole_body"]
const SECONDARY_CONTACT_SURFACES: PackedStringArray = ["none", "point", "edge", "broad", "whole_body"]
const RIGIDITIES: PackedStringArray = ["rigid", "semi_rigid", "flexible"]

@export_enum("none", "short", "medium", "long") var handle_length := "medium"
@export_enum("short", "medium", "long") var body_length := "medium"
@export_enum("one_hand_handle", "two_hand_handle", "body_grip", "clamp_grip") var grip_topology := "one_hand_handle"
@export_enum("rear", "balanced", "front") var mass_distribution := "balanced"
@export_enum("point", "edge", "broad", "whole_body") var contact_surface := "point"
@export_enum("none", "point", "edge", "broad", "whole_body") var secondary_contact_surface := "none"
@export_enum("rigid", "semi_rigid", "flexible") var rigidity := "rigid"
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
