extends SceneTree

const CONTACT_MECHANICS := preload("res://scripts/combat_feel/perceptible_contact_mechanics.gd")
const PRIMITIVE := preload("res://scripts/combat_feel/motion_primitive.gd")
const ENEMY := preload("res://scripts/combat_feel/combat_feel_enemy.gd")
const EXPERIMENT_LOADER := preload("res://scripts/combat_feel/perceptible_experiment_asset_loader.gd")
const COMPILER := preload("res://scripts/combat_feel/melee_motion_compiler.gd")

var passed := 0
var failed := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_surface_to_verb_contract()
	_test_outcomes_are_categorical()
	_test_enemy_statuses_are_visible_runtime_state()
	_test_four_surface_samples_reach_distinct_verbs()
	_test_surface_samples_are_data_driven()
	_test_experiment_boundary_and_entrypoints()
	if passed + failed != 6:
		failed += 1
		printerr("FAIL | expected 6 completed checks, got %d" % (passed + failed - 1))
	print("PERCEPTIBLE_MECHANISM_TESTS passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _test_surface_to_verb_contract() -> void:
	var actual := PackedStringArray()
	for surface: String in ["point", "edge", "broad", "whole_body"]:
		actual.append(CONTACT_MECHANICS.verb_for(_primitive(surface)))
	_check(
		actual == PackedStringArray(["pin", "cleave", "shove", "sweep_control"]),
		"01 every contact surface owns one player-facing verb"
	)


func _test_outcomes_are_categorical() -> void:
	var base := {"knockback": Vector2(100, 0), "stagger": 0.40}
	var pin: Dictionary = CONTACT_MECHANICS.outcome_for(_primitive("point"), base, "charge")
	var cleave: Dictionary = CONTACT_MECHANICS.outcome_for(_primitive("edge"), base, "approach")
	var shove: Dictionary = CONTACT_MECHANICS.outcome_for(_primitive("broad"), base, "tell")
	var control: Dictionary = CONTACT_MECHANICS.outcome_for(_primitive("whole_body"), base, "attack")
	var ok := bool(pin["immobilize"]) and bool(pin["interrupts_attack"])
	ok = ok and float(cleave["damage_multiplier"]) > 1.0 and not bool(cleave["interrupts_attack"])
	ok = ok and Vector2(shove["knockback"]).length() > Vector2(base["knockback"]).length() and bool(shove["interrupts_attack"])
	ok = ok and bool(control["control_lock"]) and float(control["status_seconds"]) > float(shove["status_seconds"])
	_check(ok, "02 verbs change target state and decision utility, not only feedback multipliers")


func _test_enemy_statuses_are_visible_runtime_state() -> void:
	var ram: Node2D = ENEMY.new()
	ram.setup(ENEMY.RAM, 1, Vector2.ZERO)
	ram.force_state("charge")
	var shove := CONTACT_MECHANICS.outcome_for(
		_primitive("broad"),
		{"knockback": Vector2(100, 0), "stagger": 0.40},
		ram.state
	)
	ram.apply_hit(1.0, Vector2(shove["knockback"]), float(shove["stagger"]), 7.0, shove)
	var shove_ok: bool = ram.state == "recovery" and ram.mechanism_status == "SHOVED" and ram.velocity.x > 150.0
	ram.free()

	var puppet: Node2D = ENEMY.new()
	puppet.setup(ENEMY.PUPPET, 2, Vector2.ZERO)
	var pin := CONTACT_MECHANICS.outcome_for(
		_primitive("point"),
		{"knockback": Vector2(100, 0), "stagger": 0.40},
		puppet.state
	)
	puppet.apply_hit(1.0, Vector2(pin["knockback"]), float(pin["stagger"]), 7.0, pin)
	var pin_ok: bool = puppet.mechanism_status == "PINNED" and puppet.velocity == Vector2.ZERO and puppet.stagger_time >= 0.82
	puppet.free()
	_check(shove_ok and pin_ok, "03 enemy runtime exposes interrupt, displacement and immobilization states")


func _test_four_surface_samples_reach_distinct_verbs() -> void:
	var loader := EXPERIMENT_LOADER.new()
	var compiler := COMPILER.new()
	var expected := {
		"longsword_generalization": "cleave",
		"spear_generalization": "pin",
		"frying_pan": "shove",
		"wooden_chair_generalization": "sweep_control",
	}
	var actual := {}
	for asset_id: String in expected:
		var loaded: Dictionary = loader.load_asset(asset_id)
		if not bool(loaded.get("ok", false)):
			continue
		var asset: WeaponVisualAsset = loaded.get("asset") as WeaponVisualAsset
		var profile: Resource = compiler.compile(
			loaded.get("affordance_profile") as Resource,
			asset.anchors_dict(),
			asset.opaque_bounds
		)
		if profile != null and profile.combo_recipe != null:
			actual[asset_id] = CONTACT_MECHANICS.verb_for(profile.combo_recipe.hit_1)
	_check(actual == expected, "04 four replaceable samples compile into cleave, pin, shove and control without identity branches")


func _test_surface_samples_are_data_driven() -> void:
	var loader := EXPERIMENT_LOADER.new()
	var ids := {}
	var ok := true
	for surface: String in ["point", "edge", "broad", "whole_body"]:
		var descriptor: Dictionary = loader.sample_for_surface(surface)
		var loaded: Dictionary = loader.load_surface(surface)
		ok = ok and bool(descriptor.get("ok", false)) and bool(loaded.get("ok", false))
		ok = ok and str(descriptor.get("surface", "")) == surface
		ok = ok and str(loaded.get("representative_surface", "")) == surface
		var profile: Resource = loaded.get("affordance_profile") as Resource
		ok = ok and profile != null and str(profile.contact_surface) == surface
		ids[str(descriptor.get("asset_id", ""))] = true
	_check(ok and ids.size() == 4, "05 each factor level has exactly one data-selected representative that may be replaced in the index")


func _test_experiment_boundary_and_entrypoints() -> void:
	var resolver_source := FileAccess.get_file_as_string("res://scripts/combat_feel/perceptible_contact_mechanics.gd").to_lower()
	var index_source := FileAccess.get_file_as_string("res://data/combat_feel/perceptible_mechanism_experiment_assets.json")
	var slice_source := FileAccess.get_file_as_string("res://scripts/combat_feel/combat_feel_slice_0.gd")
	var experiment_source := FileAccess.get_file_as_string("res://scripts/combat_feel/perceptible_mechanism_experiment.gd")
	var ok := not resolver_source.contains("longsword") and not resolver_source.contains("spear") and not resolver_source.contains("chair")
	ok = ok and index_source.contains('"developer_experiment_only": true') and index_source.contains('"frozen_evidence_claim": false')
	ok = ok and slice_source.contains("func _mechanism_experiment_enabled() -> bool:\n\treturn false")
	ok = ok and experiment_source.contains("func _mechanism_experiment_enabled() -> bool:\n\treturn true")
	ok = ok and experiment_source.contains("load_surface")
	ok = ok and not experiment_source.contains("longsword_generalization") and not experiment_source.contains("spear_generalization")
	ok = ok and not experiment_source.contains("frying_pan") and not experiment_source.contains("wooden_chair_generalization")
	ok = ok and ResourceLoader.exists("res://scenes/perceptible_mechanism_experiment.tscn")
	ok = ok and FileAccess.file_exists("res://scripts/run_perceptible_mechanism_experiment.ps1")
	_check(ok, "06 experiment is explicit, identity-free and isolated from the default scene")


func _primitive(surface: String) -> Resource:
	var primitive: Resource = PRIMITIVE.new()
	primitive.contact_surface = surface
	return primitive


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS | %s" % label)
	else:
		failed += 1
		printerr("FAIL | %s" % label)
