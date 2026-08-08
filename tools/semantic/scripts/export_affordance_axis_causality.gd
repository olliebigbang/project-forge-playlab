extends SceneTree

const AFFORDANCE := preload("res://scripts/combat_feel/object_affordance_profile.gd")
const COMPILER := preload("res://scripts/combat_feel/melee_motion_compiler.gd")

const ANCHORS := {
	"GripPrimary": [24.0, 48.0],
	"GripSecondary": [38.0, 48.0],
	"StrikePoint": [78.0, 48.0],
	"Muzzle": [82.0, 48.0],
	"rear_contact": [10.0, 48.0],
}
const ALPHA_BOUNDS := Rect2i(8, 8, 80, 80)


func _init() -> void:
	call_deferred("_export")


func _export() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1 or not arguments[0].begins_with("--output="):
		_fail("AFFORDANCE_AXIS_AUDIT_ARGUMENT_INVALID")
		return
	var output_path := arguments[0].trim_prefix("--output=")
	var baseline := _baseline_payload()
	var baseline_result := _compile_payload(baseline)
	if not bool(baseline_result.get("ok", false)):
		_fail("AFFORDANCE_AXIS_AUDIT_BASELINE_FAILED")
		return
	var records: Array[Dictionary] = []
	for scenario: Dictionary in _scenarios():
		var payload: Dictionary = baseline.duplicate(true)
		var changes: Dictionary = scenario["changes"]
		for field: String in changes:
			payload[field] = changes[field]
		var compiled := _compile_payload(payload)
		if not bool(compiled.get("ok", false)):
			_fail("AFFORDANCE_AXIS_AUDIT_SCENARIO_FAILED:%s" % str(scenario["id"]))
			return
		compiled["id"] = scenario["id"]
		compiled["axis"] = scenario["axis"]
		compiled["changes"] = changes.duplicate(true)
		compiled["expected"] = scenario["expected"]
		records.append(compiled)
	var output := {
		"schema": "forge-affordance-axis-causality-raw-v1",
		"compiler": "MeleeMotionCompiler",
		"compiler_resource": "res://scripts/combat_feel/melee_motion_compiler.gd",
		"identity_inputs_used": false,
		"anchors": ANCHORS.duplicate(true),
		"alpha_bounds": [ALPHA_BOUNDS.position.x, ALPHA_BOUNDS.position.y, ALPHA_BOUNDS.size.x, ALPHA_BOUNDS.size.y],
		"baseline": baseline_result,
		"scenarios": records,
	}
	var temporary := "%s.%s.tmp" % [output_path, str(Time.get_ticks_usec())]
	var stream := FileAccess.open(temporary, FileAccess.WRITE)
	if stream == null:
		_fail("AFFORDANCE_AXIS_AUDIT_WRITE_FAILED")
		return
	stream.store_string(JSON.stringify(output, "  ") + "\n")
	stream.flush()
	stream.close()
	if DirAccess.rename_absolute(temporary, output_path) != OK:
		_fail("AFFORDANCE_AXIS_AUDIT_ATOMIC_RENAME_FAILED")
		return
	print("AFFORDANCE_AXIS_CAUSALITY_EXPORT=PASS scenarios=%d" % records.size())
	quit(0)


func _baseline_payload() -> Dictionary:
	return {
		"handle_length": "medium",
		"body_length": "medium",
		"grip_topology": "one_hand_handle",
		"rigidity": "rigid",
		"mass_distribution": "balanced",
		"contact_surface": "broad",
		"secondary_contact_surface": "none",
		"has_point": false,
		"has_edge": false,
		"has_broad_face": false,
		"has_barrel": false,
		"has_stock": false,
		"confidence": 0.80,
		"evidence_parts": ["anonymous structural baseline"],
	}


func _scenarios() -> Array[Dictionary]:
	return [
		{"id": "handle_short", "axis": "handle_length", "changes": {"handle_length": "short"}, "expected": "runtime_effect"},
		{"id": "handle_long", "axis": "handle_length", "changes": {"handle_length": "long"}, "expected": "runtime_effect"},
		{"id": "body_short", "axis": "body_length", "changes": {"body_length": "short"}, "expected": "runtime_effect"},
		{"id": "body_long", "axis": "body_length", "changes": {"body_length": "long"}, "expected": "runtime_effect"},
		{"id": "grip_two_hand", "axis": "grip_topology", "changes": {"grip_topology": "two_hand_handle"}, "expected": "runtime_effect"},
		{"id": "grip_clamp", "axis": "grip_topology", "changes": {"grip_topology": "clamp_grip"}, "expected": "runtime_effect"},
		{"id": "grip_handleless_body", "axis": "grip_mode", "changes": {"handle_length": "none", "grip_topology": "body_grip"}, "expected": "runtime_effect"},
		{"id": "rigidity_semi", "axis": "rigidity", "changes": {"rigidity": "semi_rigid"}, "expected": "runtime_effect"},
		{"id": "rigidity_flexible", "axis": "rigidity", "changes": {"rigidity": "flexible"}, "expected": "runtime_effect"},
		{"id": "mass_rear", "axis": "mass_distribution", "changes": {"mass_distribution": "rear"}, "expected": "runtime_effect"},
		{"id": "mass_front", "axis": "mass_distribution", "changes": {"mass_distribution": "front"}, "expected": "runtime_effect"},
		{"id": "primary_point", "axis": "contact_surface", "changes": {"contact_surface": "point"}, "expected": "runtime_effect"},
		{"id": "primary_edge", "axis": "contact_surface", "changes": {"contact_surface": "edge"}, "expected": "runtime_effect"},
		{"id": "primary_whole_body", "axis": "contact_surface", "changes": {"contact_surface": "whole_body"}, "expected": "runtime_effect"},
		{"id": "secondary_point", "axis": "secondary_contact_surface", "changes": {"secondary_contact_surface": "point"}, "expected": "runtime_effect"},
		{"id": "secondary_edge", "axis": "secondary_contact_surface", "changes": {"secondary_contact_surface": "edge"}, "expected": "runtime_effect"},
		{"id": "secondary_broad", "axis": "secondary_contact_surface", "changes": {"secondary_contact_surface": "broad"}, "expected": "runtime_effect"},
		{"id": "secondary_whole_body", "axis": "secondary_contact_surface", "changes": {"secondary_contact_surface": "whole_body"}, "expected": "runtime_effect"},
		{"id": "feature_point", "axis": "has_point", "changes": {"has_point": true}, "expected": "runtime_effect"},
		{"id": "feature_edge", "axis": "has_edge", "changes": {"has_edge": true}, "expected": "runtime_effect"},
		{"id": "feature_broad_face", "axis": "has_broad_face", "changes": {"has_broad_face": true}, "expected": "runtime_effect"},
		{"id": "feature_barrel", "axis": "has_barrel", "changes": {"has_barrel": true}, "expected": "runtime_effect"},
		{"id": "feature_stock", "axis": "has_stock", "changes": {"has_stock": true}, "expected": "runtime_effect"},
		{"id": "confidence_high", "axis": "confidence", "changes": {"confidence": 0.95}, "expected": "invariant"},
		{"id": "evidence_changed", "axis": "evidence_parts", "changes": {"evidence_parts": ["different anonymous evidence wording"]}, "expected": "invariant"},
	]


func _compile_payload(payload: Dictionary) -> Dictionary:
	var affordance: Resource = AFFORDANCE.new()
	for field: String in [
		"handle_length", "body_length", "grip_topology", "rigidity",
		"mass_distribution", "contact_surface", "secondary_contact_surface",
		"has_point", "has_edge", "has_broad_face", "has_barrel", "has_stock",
		"confidence",
	]:
		affordance.set(field, payload[field])
	affordance.evidence_parts = PackedStringArray(payload["evidence_parts"])
	if not affordance.validation_errors().is_empty():
		return {"ok": false, "errors": affordance.validation_errors()}
	var result: Variant = COMPILER.new().compile(affordance, ANCHORS, ALPHA_BOUNDS)
	if not result is Resource or result.combo_recipe == null:
		return {"ok": false, "errors": [str(result)]}
	return {
		"ok": true,
		"affordance": affordance.to_dict(),
		"profile": result.to_dict(),
	}


func _fail(code: String) -> void:
	push_error(code)
	quit(1)
