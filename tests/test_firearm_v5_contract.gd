extends SceneTree

const AXES := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")
const AI_RESOLVER := preload("res://scripts/combat_feel/firearm_identity_ai_resolver.gd")
const CATALOG := preload("res://scripts/combat_feel/firearm_identity_catalog.gd")

const SOURCE := "AI_TEST_FIXTURE_FIREARM_IDENTITY_V4"
const V3_CACHE := "user://playlab/test_firearm_v3_fail_closed.json"
const FIXTURES := [
	{"identity": "Mossberg 500", "path": "res://tests/fixtures/firearm_ai_mossberg_500_response_v4.json", "family": "shotgun", "layout": "conventional_shotgun", "cycle": 2, "feed": 1, "pellets": 8, "capacity": 6},
	{"identity": "S&W 686", "path": "res://tests/fixtures/firearm_ai_sw_686_response_v4.json", "family": "revolver", "layout": "revolver", "cycle": 3, "feed": 2, "pellets": 1, "capacity": 6},
	{"identity": "M249", "path": "res://tests/fixtures/firearm_ai_m249_response_v4.json", "family": "light_machine_gun", "layout": "belt_fed_support", "cycle": 0, "feed": 3, "pellets": 1, "capacity": 80},
]
const FROZEN_PARAMETERS := [
	"cycle_action_code", "cycle_required", "cycle_overhead_seconds",
	"reload_feed_code", "reload_rounds_per_step", "pellet_count",
	"pellet_spread_degrees", "pellet_damage_multiplier",
	"damage_falloff_min_multiplier", "muzzle_flash_seconds", "muzzle_flash_scale",
	"sustained_climb_per_shot_degrees", "sustained_climb_cap_degrees",
	"sustained_recovery_multiplier", "sustained_window_seconds",
	"muzzle_climb_cap_degrees",
]

var passed := 0
var failed := 0


func _initialize() -> void:
	print("Forge firearm V5 contract tests")
	_run("Seven curated firearms declare complete V5 axes", _test_curated_profiles)
	_run("Shotgun, revolver, and belt-fed fixtures parse and compile", _test_family_fixtures)
	_run("Feed systems reject impossible capacity classes", _test_feed_capacity_invariants)
	_run("Every frozen V5 output is clamped, owned, and finite-difference covered", _test_frozen_parameter_audit)
	_run("Revolver cylinder creates a real post-shot cycle lock", _test_revolver_cycle_causality)
	_run("Legacy V3 response and cache fail closed", _test_v3_fail_closed)
	_run("Break-action shotgun remains unsupported", _test_break_action_boundary)
	print("FIREARM V5 CONTRACT RESULT: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _run(test_name: String, callable: Callable) -> void:
	var result: Variant = callable.call()
	if result is bool and bool(result):
		passed += 1
		print("PASS | %s" % test_name)
	else:
		failed += 1
		printerr("FAIL | %s | %s" % [test_name, str(result)])


func _test_curated_profiles() -> Variant:
	var profiles := CATALOG.all_profiles()
	if profiles.size() != 7:
		return "expected seven curated profiles, got %d" % profiles.size()
	for profile: Dictionary in profiles:
		var declaration := profile.get("declaration", {}) as Dictionary
		for axis: String in ["firearm_family", "action_mechanism", "feed_system", "shot_pattern", "sustained_climb"]:
			if not declaration.has(axis):
				return "%s missing %s" % [profile.get("id", "unknown"), axis]
		var runtime := AXES.compile(declaration, str(declaration.get("source", "")))
		if not bool(runtime.get("ok", false)) or str(runtime.get("schema", "")) != AXES.RUNTIME_SCHEMA:
			return {"id": profile.get("id", ""), "runtime": runtime}
	var m24 := CATALOG.resolve_identity("M24A2")
	var m24_declaration := m24.get("declaration", {}) as Dictionary
	if str(m24_declaration.get("fire_control", "")) != "semi_auto" or str(m24_declaration.get("action_mechanism", "")) != "bolt_action":
		return "M24A2 did not migrate to semi_auto + bolt_action"
	return true


func _test_family_fixtures() -> Variant:
	var fixture_runtimes := {}
	for fixture: Dictionary in FIXTURES:
		var payload: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(fixture["path"])))
		if not payload is Dictionary:
			return "invalid fixture JSON: %s" % fixture["path"]
		var accepted := AI_RESOLVER.accept_ai_response(str(fixture["identity"]), payload, SOURCE, false)
		if not bool(accepted.get("ok", false)):
			return {"fixture": fixture["identity"], "accepted": accepted}
		var declaration := accepted.get("declaration", {}) as Dictionary
		var runtime := AXES.compile(declaration, SOURCE)
		if (
			not bool(runtime.get("ok", false))
			or str(declaration.get("firearm_family", "")) != str(fixture["family"])
			or str(declaration.get("layout", "")) != str(fixture["layout"])
			or int(runtime.get("cycle_action_code", -1)) != int(fixture["cycle"])
			or int(runtime.get("reload_feed_code", -1)) != int(fixture["feed"])
			or int(runtime.get("pellet_count", -1)) != int(fixture["pellets"])
			or int(runtime.get("magazine_size", -1)) != int(fixture["capacity"])
		):
			return {"fixture": fixture["identity"], "runtime": runtime}
		fixture_runtimes[str(fixture.identity)] = runtime
	var m4_declaration := (CATALOG.resolve_identity("M4A1").get("declaration", {}) as Dictionary).duplicate(true)
	var m4_runtime := AXES.compile(m4_declaration, str(m4_declaration.get("source", "")))
	var support_runtime := fixture_runtimes.get("M249", {}) as Dictionary
	if float(support_runtime.get("muzzle_climb_cap_degrees", 0.0)) <= float(m4_runtime.get("muzzle_climb_cap_degrees", INF)):
		return {"carbine": m4_runtime, "support": support_runtime, "error": "weapon-axis climb caps collapsed"}
	return true


func _test_feed_capacity_invariants() -> Variant:
	var cases := [
		{"path": FIXTURES[0]["path"], "capacity": "standard", "error": "INTERNAL_TUBE_CAPACITY"},
		{"path": FIXTURES[1]["path"], "capacity": "compact", "error": "REVOLVER_CAPACITY"},
		{"path": FIXTURES[2]["path"], "capacity": "extended", "error": "BELT_CAPACITY"},
	]
	for test_case: Dictionary in cases:
		var payload := JSON.parse_string(FileAccess.get_file_as_string(str(test_case["path"]))) as Dictionary
		var declaration := (payload.get("declaration", {}) as Dictionary).duplicate(true)
		declaration["magazine_capacity"] = str(test_case["capacity"])
		payload["declaration"] = declaration
		var validation := AI_RESOLVER.accept_ai_response(
			str(payload.get("requested_identity", "")), payload, SOURCE, false
		)
		if bool(validation.get("ok", false)) or not str(validation.get("error", "")).contains(str(test_case["error"])):
			return validation
	return true


func _test_frozen_parameter_audit() -> Variant:
	var payload := (CATALOG.resolve_identity("M4A1").get("declaration", {}) as Dictionary).duplicate(true)
	var audit := AXES.finite_difference_audit(payload, str(payload.get("source", "")))
	if not bool(audit.get("ok", false)):
		return audit
	if (
		not (audit.get("zero_effect_axes", []) as Array).is_empty()
		or not (audit.get("duplicate_direction_groups", []) as Array).is_empty()
		or not (audit.get("covered_effects", []) as Array).is_empty()
		or not (audit.get("owner_mismatches", []) as Array).is_empty()
		or not bool(audit.get("passed", false))
	):
		return {
			"zero": audit.get("zero_effect_axes", []),
			"duplicate": audit.get("duplicate_direction_groups", []),
			"clamp_covered": audit.get("covered_effects", []),
			"owner": audit.get("owner_mismatches", []),
		}
	var baseline := audit.get("baseline_final_parameters", {}) as Dictionary
	var coverage := audit.get("parameter_coverage", {}) as Dictionary
	for parameter: String in FROZEN_PARAMETERS:
		if not baseline.has(parameter):
			return "final_parameters missing %s" % parameter
		if not AXES.PARAMETER_BOUNDS.has(parameter):
			return "bounds missing %s" % parameter
		if not AXES.PARAMETER_OWNERS.has(parameter):
			return "owner missing %s" % parameter
		if not bool((coverage.get(parameter, {}) as Dictionary).get("covered", false)):
			return "finite difference missing %s" % parameter
	return true


func _test_revolver_cycle_causality() -> Variant:
	var payload := JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/firearm_ai_sw_686_response_v4.json")) as Dictionary
	var declaration := payload.get("declaration", {}) as Dictionary
	declaration["source"] = SOURCE
	declaration["confidence"] = 0.96
	var runtime := AXES.compile(declaration, SOURCE)
	if not bool(runtime.get("cycle_required", false)) or float(runtime.get("cycle_overhead_seconds", 0.0)) < 0.10:
		return runtime
	var precise := AXES.cycle_lock_total_seconds(runtime)
	var compatibility := AXES.manual_cycle_total_seconds(runtime)
	return true if precise > float(runtime.get("shot_interval_seconds", 0.0)) and is_equal_approx(precise, compatibility) else runtime


func _test_v3_fail_closed() -> Variant:
	var payload := JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/firearm_ai_m249_response_v4.json")) as Dictionary
	payload["schema"] = "forge-firearm-identity-ai-response-v3"
	var rejected := AI_RESOLVER.accept_ai_response("M249", payload, SOURCE, false)
	if str(rejected.get("error", "")) != "AI_FIREARM_RESPONSE_SCHEMA_INVALID":
		return rejected
	var absolute := ProjectSettings.globalize_path(V3_CACHE)
	var directory := absolute.get_base_dir()
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema": "forge-firearm-identity-ai-cache-v3", "entries": []}))
	file.close()
	var cached := AI_RESOLVER.resolve_identity("definitely-not-curated", V3_CACHE)
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)
	return true if str(cached.get("error", "")) == "AI_FIREARM_IDENTITY_NOT_CACHED" else cached


func _test_break_action_boundary() -> Variant:
	var payload := _unsupported_payload("Beretta 686")
	var rejected := AI_RESOLVER.accept_ai_response("Beretta 686", payload, SOURCE, false)
	return true if str(rejected.get("error", "")) == "AI_FIREARM_STRUCTURE_FAMILY_UNSUPPORTED" else rejected


func _unsupported_payload(identity: String) -> Dictionary:
	var declaration := {}
	for key: String in [
		"weapon_domain", "firearm_family", "layout", "stock_structure", "feed_position",
		"magazine_shape", "barrel_length", "upper_profile", "support_mode", "fire_control",
		"action_mechanism", "feed_system", "shot_pattern", "sustained_climb", "cadence",
		"recoil", "recoil_recovery", "muzzle_climb", "accuracy", "impact_force",
		"penetration", "reload", "effective_range", "handling", "magazine_capacity", "finish_palette",
	]:
		declaration[key] = "not_applicable"
	return {
		"schema": AI_RESOLVER.RESPONSE_SCHEMA,
		"requested_identity": identity,
		"classification": "handheld_firearm_unsupported",
		"canonical_name": identity,
		"confidence": 0.96,
		"identity_evidence": ["break-action shotgun outside the supported action family"],
		"visual_description_en": "",
		"required_identity_parts_zh": [],
		"visual_identity_axes": {"stock_profile": "not_applicable", "upper_landmark": "not_applicable", "magazine_profile": "not_applicable", "fore_end_profile": "not_applicable", "receiver_profile": "not_applicable"},
		"required_landmarks_en": [],
		"confusable_exclusions_en": [],
		"declaration": declaration,
	}
