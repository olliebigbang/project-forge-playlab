extends SceneTree

const AFFORDANCE := preload("res://scripts/combat_feel/object_affordance_profile.gd")
const COMPILER := preload("res://scripts/combat_feel/melee_motion_compiler.gd")


func _init() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1 or not arguments[0].begins_with("--run-directory="):
		_fail("AFFORDANCE_RETEST_EXPORT_ARGUMENT_INVALID")
		return
	var run_directory := arguments[0].trim_prefix("--run-directory=")
	var root := DirAccess.open(run_directory)
	if root == null:
		_fail("AFFORDANCE_RETEST_RUN_DIRECTORY_MISSING")
		return
	var cases_path := run_directory.path_join("case_order.json")
	var cases_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(cases_path))
	if not cases_value is Array or cases_value.size() != 12:
		_fail("AFFORDANCE_RETEST_CASE_ORDER_INVALID")
		return
	var records: Array[Dictionary] = []
	for case_value: Variant in cases_value:
		var case_id := str(case_value)
		var profile_path := run_directory.path_join("affordance_profiles").path_join("%s.json" % case_id)
		var payload: Variant = JSON.parse_string(FileAccess.get_file_as_string(profile_path))
		if not payload is Dictionary:
			records.append({"case_id": case_id, "status": "NO_VALID_AFFORDANCE", "failure_reason": "profile unavailable"})
			continue
		var affordance: Resource = AFFORDANCE.new()
		for field: String in [
			"handle_length", "body_length", "grip_topology", "rigidity",
			"mass_distribution", "contact_surface", "secondary_contact_surface",
			"has_point", "has_edge", "has_broad_face", "has_barrel", "has_stock",
			"confidence"
		]:
			affordance.set(field, payload[field])
		affordance.evidence_parts = PackedStringArray(payload["evidence_parts"])
		var anchors := {
			"GripPrimary": [24.0, 48.0], "GripSecondary": [38.0, 48.0],
			"StrikePoint": [78.0, 48.0], "Muzzle": [82.0, 48.0],
			"rear_contact": [10.0, 48.0],
		}
		var compiled: Variant = COMPILER.new().compile(affordance, anchors, Rect2i(8, 8, 80, 80))
		if not compiled is Resource or compiled.combo_recipe == null:
			records.append({"case_id": case_id, "status": "COMPILE_REJECTED", "failure_reason": str(compiled)})
			continue
		records.append({
			"case_id": case_id,
			"status": "COMPILED",
			"mechanism_axes": compiled.mechanism_axes.duplicate(true),
			"primitive_scores": compiled.primitive_scores.duplicate(true),
			"primitive_sequence": Array(compiled.combo_recipe.primitive_sequence()),
			"recipe_signature": compiled.combo_recipe.signature(),
			"recipe": compiled.combo_recipe.to_dict(),
		})
	var output := {
		"compiler": "MeleeMotionCompiler",
		"compiler_resource": "res://scripts/combat_feel/melee_motion_compiler.gd",
		"identity_inputs_used": false,
		"anchor_basis": "one frozen neutral anchor/bounds basis for all 12 cases",
		"records": records,
	}
	var target := run_directory.path_join("compiled_recipes.json")
	var temporary := "%s.tmp" % target
	var stream := FileAccess.open(temporary, FileAccess.WRITE)
	if stream == null:
		_fail("AFFORDANCE_RETEST_EXPORT_WRITE_FAILED")
		return
	stream.store_string(JSON.stringify(output, "  ") + "\n")
	stream.flush()
	stream.close()
	if DirAccess.rename_absolute(temporary, target) != OK:
		_fail("AFFORDANCE_RETEST_EXPORT_ATOMIC_RENAME_FAILED")
		return
	print("AFFORDANCE_RETEST_RECIPE_EXPORT=PASS records=%d" % records.size())
	quit(0)


func _fail(code: String) -> void:
	push_error(code)
	quit(1)
