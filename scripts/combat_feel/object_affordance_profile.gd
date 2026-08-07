class_name ObjectAffordanceProfile
extends Resource

@export_enum("short", "medium", "long") var handle_length := "medium"
@export_enum("short", "medium", "long") var body_length := "medium"
@export_enum("rear", "balanced", "front") var mass_distribution := "balanced"
@export_enum("point", "edge", "broad", "whole_body") var contact_surface := "point"
@export_enum("rigid", "semi_rigid", "flexible") var rigidity := "rigid"
@export var has_point := false
@export var has_edge := false
@export var has_broad_face := false
@export var has_barrel := false
@export var has_stock := false


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if handle_length not in ["short", "medium", "long"]:
		errors.append("INVALID_HANDLE_LENGTH")
	if body_length not in ["short", "medium", "long"]:
		errors.append("INVALID_BODY_LENGTH")
	if rigidity not in ["rigid", "semi_rigid", "flexible"]:
		errors.append("INVALID_RIGIDITY")
	if mass_distribution not in ["rear", "balanced", "front"]:
		errors.append("INVALID_MASS_DISTRIBUTION")
	if contact_surface not in ["point", "edge", "broad", "whole_body"]:
		errors.append("INVALID_CONTACT_SURFACE")
	return errors


func to_dict() -> Dictionary:
	return {
		"handle_length": handle_length,
		"body_length": body_length,
		"rigidity": rigidity,
		"mass_distribution": mass_distribution,
		"contact_surface": contact_surface,
		"has_point": has_point,
		"has_edge": has_edge,
		"has_broad_face": has_broad_face,
		"has_barrel": has_barrel,
		"has_stock": has_stock,
	}
