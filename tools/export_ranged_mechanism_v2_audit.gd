extends SceneTree

const CATALOG := preload("res://scripts/combat_feel/firearm_identity_catalog.gd")
const AXES := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")

const DEFAULT_OUTPUT := "res://output/ranged-mechanism-v2-audit-20260827/firearm_mechanism_v2_audit.json"


func _initialize() -> void:
	var output_path := _argument_value("--output", DEFAULT_OUTPUT)
	var records := {}
	var failed_profiles: Array[String] = []
	var aggregate_zero_effects: Array[Dictionary] = []
	var aggregate_duplicate_directions: Array[Dictionary] = []
	var aggregate_covered_effects: Array[Dictionary] = []
	var aggregate_uncovered_parameters: Array[Dictionary] = []
	for profile: Dictionary in CATALOG.all_profiles():
		var profile_id := str(profile.get("id", ""))
		var declaration := profile.get("declaration", {}) as Dictionary
		var source := str(declaration.get("source", ""))
		var runtime: Dictionary = AXES.compile(declaration, source)
		var audit: Dictionary = AXES.finite_difference_audit(declaration, source)
		if not bool(runtime.get("ok", false)) or not bool(audit.get("ok", false)):
			failed_profiles.append(profile_id)
		var zero_effects := audit.get("zero_effect_axes", []) as Array
		var duplicate_directions := audit.get("duplicate_direction_groups", []) as Array
		var covered_effects := audit.get("covered_effects", []) as Array
		var uncovered := audit.get("uncovered_parameters", []) as Array
		for axis: Variant in zero_effects:
			aggregate_zero_effects.append({"profile": profile_id, "axis": str(axis)})
		for group: Variant in duplicate_directions:
			aggregate_duplicate_directions.append({"profile": profile_id, "axes": group})
		for effect: Variant in covered_effects:
			aggregate_covered_effects.append({"profile": profile_id, "effect": effect})
		for parameter: Variant in uncovered:
			aggregate_uncovered_parameters.append({"profile": profile_id, "parameter": str(parameter)})
		records[profile_id] = {
			"canonical_name_zh": str(profile.get("canonical_name_zh", profile_id)),
			"source": source,
			"declared_axes": runtime.get("axes", {}),
			"raw_parameter_matrix": runtime.get("raw_parameters", {}),
			"final_clamped_parameter_matrix": runtime.get("final_parameters", {}),
			"clamp_events": runtime.get("clamp_events", []),
			"finite_difference": audit,
		}
	var result := {
		"schema": "forge-ranged-mechanism-v2-audit-bundle-v1",
		"runtime_schema": AXES.RUNTIME_SCHEMA,
		"audit_schema": AXES.AUDIT_SCHEMA,
		"generated_unix_time": int(Time.get_unix_time_from_system()),
		"method": "single-variable exhaustive finite differences across every legal V2 mechanism-axis value",
		"profile_count": records.size(),
		"mechanism_axes": Array(AXES.MECHANISM_AXES),
		"audited_final_parameters": Array(AXES.AUDITED_PARAMETERS),
		"parameter_bounds": AXES.PARAMETER_BOUNDS.duplicate(true),
		"parameter_owners": AXES.PARAMETER_OWNERS.duplicate(true),
		"summary": {
			"passed": (
				failed_profiles.is_empty()
				and aggregate_zero_effects.is_empty()
				and aggregate_duplicate_directions.is_empty()
				and aggregate_covered_effects.is_empty()
				and aggregate_uncovered_parameters.is_empty()
			),
			"failed_profiles": failed_profiles,
			"zero_effects": aggregate_zero_effects,
			"duplicate_directions": aggregate_duplicate_directions,
			"covered_effects": aggregate_covered_effects,
			"uncovered_parameters": aggregate_uncovered_parameters,
		},
		"profiles": records,
	}
	var absolute_path := ProjectSettings.globalize_path(output_path)
	if DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir()) != OK:
		printerr("RANGED_MECHANISM_V2_AUDIT_DIRECTORY_FAILED:%s" % absolute_path)
		quit(1)
		return
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		printerr("RANGED_MECHANISM_V2_AUDIT_WRITE_FAILED:%s" % absolute_path)
		quit(1)
		return
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("RANGED_MECHANISM_V2_AUDIT=%s" % absolute_path)
	print("RANGED_MECHANISM_V2_AUDIT_PASS=%s" % str((result.get("summary", {}) as Dictionary).get("passed", false)))
	quit(0 if bool((result.get("summary", {}) as Dictionary).get("passed", false)) else 1)


func _argument_value(flag: String, fallback: String) -> String:
	var arguments := OS.get_cmdline_user_args()
	for index: int in range(arguments.size()):
		var value := str(arguments[index])
		if value.begins_with(flag + "="):
			return value.substr(flag.length() + 1)
		if value == flag and index + 1 < arguments.size():
			return str(arguments[index + 1])
	return fallback
