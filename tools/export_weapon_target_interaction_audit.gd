extends SceneTree

const INTERACTION := preload("res://scripts/combat_feel/weapon_target_interaction_resolver.gd")
const PRIMITIVE := preload("res://scripts/combat_feel/motion_primitive.gd")

const DEFAULT_OUTPUT := "res://output/weapon-target-interaction-v3-audit/finite_difference_audit.json"


func _initialize() -> void:
	var output_path := _argument_value("--output", DEFAULT_OUTPUT)
	var audit: Dictionary = INTERACTION.finite_difference_audit()
	var examples := {
		"point_thrust": _melee_example("point", "thrust"),
		"edge_sweep": _melee_example("edge", "sweep"),
		"broad_bash": _melee_example("broad", "bash"),
		"flexible_wrap": _soft_example("wrap"),
		"flexible_hook": _soft_example("hook"),
		"ranged_light_deliberate": INTERACTION.compile_ranged({
			"impact_force": "light", "penetration": "light", "cadence": "deliberate",
		}),
		"ranged_strong_rapid": INTERACTION.compile_ranged({
			"impact_force": "strong", "penetration": "strong", "cadence": "rapid",
		}),
	}
	var result := {
		"schema": "forge-weapon-target-interaction-v3-audit-bundle-v1",
		"runtime_schema": INTERACTION.RUNTIME_SCHEMA,
		"audit_schema": INTERACTION.AUDIT_SCHEMA,
		"generated_unix_time": int(Time.get_unix_time_from_system()),
		"method": "single-variable exhaustive finite differences across all seven target-reaction axes",
		"effect_axes": Array(INTERACTION.EFFECT_AXES),
		"audited_final_parameters": Array(INTERACTION.AUDITED_PARAMETERS),
		"parameter_bounds": INTERACTION.PARAMETER_BOUNDS.duplicate(true),
		"parameter_owners": INTERACTION.PARAMETER_OWNERS.duplicate(true),
		"finite_difference": audit,
		"compiled_examples": examples,
		"summary": {
			"passed": bool(audit.get("passed", false)),
			"zero_effects": audit.get("zero_effect_axes", []),
			"duplicate_directions": audit.get("duplicate_direction_groups", []),
			"covered_effects": audit.get("covered_effects", []),
			"uncovered_parameters": audit.get("uncovered_parameters", []),
			"owner_mismatches": audit.get("owner_mismatches", []),
		},
	}
	var absolute_path := ProjectSettings.globalize_path(output_path)
	if DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir()) != OK:
		printerr("WEAPON_TARGET_INTERACTION_AUDIT_DIRECTORY_FAILED:%s" % absolute_path)
		quit(1)
		return
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		printerr("WEAPON_TARGET_INTERACTION_AUDIT_WRITE_FAILED:%s" % absolute_path)
		quit(1)
		return
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("WEAPON_TARGET_INTERACTION_AUDIT=%s" % absolute_path)
	print("WEAPON_TARGET_INTERACTION_AUDIT_PASS=%s" % str(bool((result["summary"] as Dictionary)["passed"])))
	quit(0 if bool((result["summary"] as Dictionary)["passed"]) else 1)


func _melee_example(surface: String, family: String) -> Dictionary:
	var primitive: Resource = PRIMITIVE.new()
	primitive.contact_surface = surface
	primitive.motion_family = family
	return INTERACTION.compile_melee({}, primitive)


func _soft_example(tether_mode: String) -> Dictionary:
	var primitive: Resource = PRIMITIVE.new()
	primitive.contact_surface = "whole_body" if tether_mode == "wrap" else "point"
	primitive.motion_family = "spin" if tether_mode == "wrap" else "sweep"
	primitive.flex_topology = "flexible_line"
	primitive.tether_mode = tether_mode
	primitive.tether_strength = 120.0
	return INTERACTION.compile_melee({}, primitive)


func _argument_value(flag: String, fallback: String) -> String:
	var arguments := OS.get_cmdline_user_args()
	for index: int in range(arguments.size()):
		var value := str(arguments[index])
		if value.begins_with(flag + "="):
			return value.substr(flag.length() + 1)
		if value == flag and index + 1 < arguments.size():
			return str(arguments[index + 1])
	return fallback
