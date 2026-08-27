extends SceneTree

const LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")
const COMPILER := preload("res://scripts/combat_feel/melee_motion_compiler.gd")
const SLICE := preload("res://scripts/combat_feel/combat_feel_slice_0.gd")
const INDEX_PATH := "res://data/combat_feel/live_assets/motion_grammar_generalization_v1/index.json"
const RUNNER_PATH := "res://scripts/run_motion_grammar_generalization_blind.ps1"

var passed := 0
var failed := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_new_real_asset_set()
	_test_existing_orthogonal_chain_compiles_all_assets()
	_test_no_normal_player_or_named_recipe_path()
	_test_blind_runner_uses_runtime_metrics()
	_test_blind_metrics_have_unique_extrema()
	print("MOTION_GRAMMAR_GENERALIZATION_TESTS passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _test_new_real_asset_set() -> void:
	var loader: Variant = LOADER.new()
	var ids: Array[String] = loader.generalization_asset_ids()
	var expected := PackedStringArray([
		"longsword_generalization",
		"spear_generalization",
		"wooden_chair_generalization",
	])
	var ok := ids.size() == 3
	for id: String in expected:
		ok = ok and ids.has(id)
	for old_id: String in ["frying_pan", "old_mop", "shotgun_melee"]:
		ok = ok and not ids.has(old_id)
	_check(ok, "01 generalization blind set contains three new identities and none of the old trio")


func _test_existing_orthogonal_chain_compiles_all_assets() -> void:
	var loader: Variant = LOADER.new()
	var compiler: Variant = COMPILER.new()
	var signatures := {}
	var sequences := {}
	var ok := true
	for asset_id: String in loader.generalization_asset_ids():
		var loaded: Dictionary = loader.load_generalization_asset(asset_id)
		var entry_ok := bool(loaded.get("ok", false)) and not bool(loaded.get("fixture", true))
		if not entry_ok:
			push_error("GENERALIZATION_LOAD_FAILED:%s:%s" % [asset_id, str(loaded.get("error", "unknown"))])
		ok = ok and entry_ok
		if not entry_ok:
			continue
		var asset: WeaponVisualAsset = loaded.get("asset") as WeaponVisualAsset
		var affordance: Resource = loaded.get("affordance_profile") as Resource
		var compiled: Variant = compiler.compile(affordance, asset.anchors_dict(), asset.opaque_bounds)
		ok = ok and compiled is Resource and compiled.combo_recipe.validation_errors().is_empty()
		if not compiled is Resource:
			continue
		signatures[compiled.combo_recipe.signature()] = true
		sequences["|".join(compiled.combo_recipe.primitive_sequence())] = true
		ok = ok and str(compiled.compile_trace.get("composer", "")) == "orthogonal_affordance_v4"
		ok = ok and not bool(compiled.compile_trace.get("identity_inputs_used", true))
	_check(ok and signatures.size() == 3 and sequences.size() == 3, "02 new assets compile through the existing orthogonal chain into distinct runtime recipes")


func _test_no_normal_player_or_named_recipe_path() -> void:
	var index: Dictionary = _read_json(INDEX_PATH)
	var compiler_source := FileAccess.get_file_as_string("res://scripts/combat_feel/melee_motion_compiler.gd").to_lower()
	var ok := not bool(index.get("normal_player_flow", true))
	for value: Variant in index.get("assets", []):
		var entry: Dictionary = value
		ok = ok and bool(entry.get("developer_only", false)) and not bool(entry.get("normal_player_flow", true))
		ok = ok and not entry.has("recipe")
	for forbidden: String in ["longsword_generalization", "spear_generalization", "wooden_chair_generalization"]:
		ok = ok and not compiler_source.contains(forbidden)
	_check(ok, "03 frozen selection stays developer-only and the compiler has no identity-specific recipe branch")


func _test_blind_runner_uses_runtime_metrics() -> void:
	var runner := FileAccess.get_file_as_string(RUNNER_PATH)
	var ok := runner.contains("--generalization-asset=")
	ok = ok and runner.contains("Get-ExpectedLabel") and runner.contains("compiled_metrics")
	ok = ok and runner.contains("GENERALIZATION_RECIPES_NOT_DISTINCT")
	ok = ok and not runner.contains("--motion-grammar-asset=")
	_check(ok, "04 blind expected answers are derived from frozen runtime metrics rather than the old identity mapping")


func _test_blind_metrics_have_unique_extrema() -> void:
	var loader: Variant = LOADER.new()
	var compiler: Variant = COMPILER.new()
	var metric_values := {
		"reach_pixels": {},
		"maximum_coverage_score": {},
		"third_hit_weight_score": {},
		"control_score": {},
		"combo_root_motion_total": {},
	}
	var ok := true
	for asset_id: String in loader.generalization_asset_ids():
		var loaded: Dictionary = loader.load_generalization_asset(asset_id)
		if not bool(loaded.get("ok", false)):
			push_error("GENERALIZATION_METRIC_LOAD_FAILED:%s:%s" % [asset_id, str(loaded.get("error", "unknown"))])
			ok = false
			continue
		var asset: WeaponVisualAsset = loaded.get("asset") as WeaponVisualAsset
		var compiled: Resource = compiler.compile(
			loaded.get("affordance_profile") as Resource,
			asset.anchors_dict(),
			asset.opaque_bounds
		) as Resource
		var slice: Node = SLICE.new()
		slice.motion_profile = compiled
		var metrics: Dictionary = slice._blind_compiled_metrics()
		slice.free()
		for metric: String in metric_values:
			metric_values[metric][snappedf(float(metrics.get(metric, 0.0)), 0.000001)] = true
	for metric: String in metric_values:
		ok = ok and (metric_values[metric] as Dictionary).size() == 3
	_check(ok, "05 each blind comparison metric has a unique runtime extremum")


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: %s" % label)
	else:
		failed += 1
		push_error("FAIL: %s" % label)
