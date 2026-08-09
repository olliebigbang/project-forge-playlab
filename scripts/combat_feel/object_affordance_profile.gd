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

# Longest real-world dimension in centimetres (affordance contract v1.3). 0.0 means the
# profile predates v1.3 and carries no length, so consumers must fall back rather than
# treat it as a zero-length object. body_length cannot substitute: it is a three-value
# ordinal and old_mop, giant_wooden_spoon and shotgun_melee are all "long" while
# measuring 140, 120 and 100cm.
@export var real_length_cm := 0.0

# Mass of the real object in kilograms (affordance contract v1.4). 0.0 means the profile
# predates v1.4 and carries no mass, so consumers must fall back rather than treat it as
# a weightless object. mass_distribution cannot substitute: it says where the weight sits,
# not how much there is, and all four shipped objects answer it the same way.
@export var real_mass_kg := 0.0


func has_real_length() -> bool:
	return is_finite(real_length_cm) and real_length_cm > 0.0


func has_real_mass() -> bool:
	return is_finite(real_mass_kg) and real_mass_kg > 0.0


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
	# 0.0 is the legitimate "absent" value for pre-v1.3 profiles; only a present-but-
	# nonsensical length is an error.
	if not is_finite(real_length_cm) or real_length_cm < 0.0:
		errors.append("INVALID_REAL_LENGTH_CM")
	if not is_finite(real_mass_kg) or real_mass_kg < 0.0:
		errors.append("INVALID_REAL_MASS_KG")
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
		"real_length_cm": real_length_cm,
		"real_mass_kg": real_mass_kg,
	}
