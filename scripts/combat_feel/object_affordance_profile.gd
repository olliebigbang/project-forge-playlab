class_name ObjectAffordanceProfile
extends Resource

@export_enum("short", "medium", "long") var handle_length := "medium"
@export_enum("short", "medium", "long") var body_length := "medium"
@export_enum("rear", "balanced", "front") var mass_distribution := "balanced"
@export_enum("point", "edge", "broad", "whole_body") var contact_surface := "point"
@export_enum("rigid", "semi_rigid", "flexible") var rigidity := "rigid"
