extends SceneTree

const PROVIDER_SCRIPT := preload("res://scripts/services/local_comfy_forge_visual_provider.gd")
const BLUEPRINT_SCRIPT := preload("res://scripts/data/weapon_blueprint.gd")
const OPEN_IDENTITY_SCENE := preload("res://scenes/open_identity_spike.tscn")
const OPEN_INTERPRETER := preload("res://scripts/services/open_identity_interpreter.gd")
const GENERAL_OBJECT_RESOLVER := preload("res://scripts/combat_feel/general_object_ai_resolver.gd")
const MECHANISM_SCAFFOLD := preload("res://scripts/combat_feel/mechanism_visual_scaffold_pipeline.gd")
const MECHANISM_AXES := preload("res://scripts/combat_feel/mechanism_axis_resolver.gd")
const MELEE_COMPILER := preload("res://scripts/combat_feel/melee_motion_compiler.gd")
const FIREARM_SCAFFOLD := preload("res://scripts/combat_feel/firearm_visual_scaffold_pipeline.gd")
const RANGED_AXES := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")

var passed := 0
var failed := 0

func _initialize() -> void:
	print("Forge Open Identity local provider boundary tests")
	_run("Strict loopback URL accepts only an exact local endpoint", _test_strict_loopback_url)
	_run("Atomic result loading leaves delivered anchors untouched", _test_atomic_result_is_read_only)
	_run("Forge home layout stays inside the 1280 viewport", _test_forge_layout_width)
	_run("Formal encounters are the primary play path", _test_formal_encounter_primary_path)
	_run("Generated weapon review keeps its actions inside the viewport", _test_generated_review_layout)
	_run("Melee mechanism card keeps its actions inside the viewport", _test_melee_summary_layout)
	_run("Ranged mechanism card keeps its actions inside the viewport", _test_ranged_summary_layout)
	print("OPEN IDENTITY PROVIDER RESULT: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _run(test_name: String, callable: Callable) -> void:
	var result: Variant = callable.call()
	if result is bool and bool(result):
		passed += 1
		print("PASS | %s" % test_name)
	else:
		failed += 1
		printerr("FAIL | %s | %s" % [test_name, str(result)])

func _test_strict_loopback_url() -> Variant:
	var valid_path := "user://playlab/tests/provider-valid.json"
	var malicious_path := "user://playlab/tests/provider-malicious.json"
	var invalid_port_path := "user://playlab/tests/provider-invalid-port.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(valid_path).get_base_dir())
	_write_json(valid_path, {"api_base": "http://127.0.0.1:8188"})
	_write_json(malicious_path, {"api_base": "http://127.0.0.1:8188@evil.example"})
	_write_json(invalid_port_path, {"api_base": "http://127.0.0.1:65536"})
	var provider = PROVIDER_SCRIPT.new()
	if not bool(provider.configure(valid_path).get("ok", false)):
		return "exact loopback endpoint was rejected"
	var malicious: Dictionary = provider.configure(malicious_path)
	if bool(malicious.get("ok", true)) or str(malicious.get("error", "")) != "COMFYUI_API_MUST_USE_LOOPBACK":
		return "userinfo URL bypassed loopback validation"
	var invalid_port: Dictionary = provider.configure(invalid_port_path)
	if bool(invalid_port.get("ok", true)) or str(invalid_port.get("error", "")) != "COMFYUI_API_MUST_USE_LOOPBACK":
		return "out-of-range port bypassed loopback validation"
	return true

func _test_atomic_result_is_read_only() -> Variant:
	var directory := "user://playlab/tests/provider-atomic-result"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	_write_json(directory.path_join("manifest.json"), {"status": "success"})
	var sentinel := "{\"producer\":\"bridge\",\"sentinel\":true}"
	var anchor_file := FileAccess.open(directory.path_join("anchors.json"), FileAccess.WRITE)
	if anchor_file == null:
		return "could not create anchor sentinel"
	anchor_file.store_string(sentinel)
	anchor_file.close()
	var image := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y: int in range(24, 72):
		for x: int in range(18, 80):
			image.set_pixel(x, y, Color.WHITE)
	if image.save_png(ProjectSettings.globalize_path(directory.path_join("processed_sprite.png"))) != OK:
		return "could not create processed sprite"
	var blueprint := BLUEPRINT_SCRIPT.new() as WeaponBlueprint
	blueprint.player_identity_text = "测试物件"
	blueprint.source_identity = blueprint.player_identity_text
	blueprint.visual_description = blueprint.player_identity_text
	blueprint.behavior_family = "sustained_ranged"
	blueprint.grip_profile = "rear_grip"
	var provider = PROVIDER_SCRIPT.new()
	var loaded: Dictionary = provider.load_atomic_result(directory, blueprint)
	if str(loaded.get("status", "")) != "success":
		return "valid atomic result was rejected: %s" % str(loaded)
	return FileAccess.get_file_as_string(directory.path_join("anchors.json")) == sentinel

func _test_forge_layout_width() -> Variant:
	var forge = OPEN_IDENTITY_SCENE.instantiate()
	root.add_child(forge)
	forge._ready()
	var forge_page := forge.page as Control
	if forge_page == null:
		forge.free()
		return "Forge page was not created"
	var minimum_width := forge_page.get_combined_minimum_size().x
	var viewport_width := forge_page.size.x
	forge.free()
	if minimum_width > viewport_width:
		return "Forge needs %.1f px but viewport is only %.1f px" % [minimum_width, viewport_width]
	return true

func _test_formal_encounter_primary_path() -> Variant:
	var source := FileAccess.get_file_as_string("res://scripts/open_identity_spike.gd")
	if source.count("进入三战正式关卡") < 2:
		return "melee and ranged summaries do not both lead with the formal level"
	if not source.contains("画面中是测试靶，不是敌人"):
		return "training targets are not identified clearly"
	if not source.contains("_button(\"进入正式三战\", _start_automatic_level, true)"):
		return "target training has no direct route into the formal level"
	return true

func _test_generated_review_layout() -> Variant:
	var interpretation: Dictionary = OPEN_INTERPRETER.new().interpret(
		"M4A1", PackedByteArray(), {}
	)
	var blueprint := interpretation.get("blueprint") as WeaponBlueprint
	var scaffold: Dictionary = FIREARM_SCAFFOLD.fallback(blueprint)
	var asset := scaffold.get("asset") as WeaponVisualAsset
	if blueprint == null or asset == null:
		return "could not assemble the generated review fixture"
	var forge = OPEN_IDENTITY_SCENE.instantiate()
	root.add_child(forge)
	forge._ready()
	forge.current_blueprint = blueprint
	forge.current_asset = asset
	forge.current_explanation = "Long generated identity explanation used for layout coverage."
	forge.current_interpretation_source = "CURATED_AI_FIREARM_IDENTITY_V5"
	forge.current_visual_source = "FAL_FIREARM"
	forge.current_output_directory = "C:/very/long/generated/output/path/that/must/wrap/without/pushing/actions/outside/the/window"
	forge.current_manifest = {
		"firearm_visual_gate_passed": true,
		"firearm_visual_identity_gate": {"ok": true},
	}
	forge._show_review()
	var result: Variant = _summary_page_result(forge.page as Control)
	forge.free()
	return result

func _test_melee_summary_layout() -> Variant:
	var payload_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://tests/fixtures/general_object_ai_fridge_response.json"
	))
	if not payload_value is Dictionary:
		return "general-object fixture is missing"
	var accepted: Dictionary = GENERAL_OBJECT_RESOLVER.accept_ai_response(
		"冰箱", payload_value as Dictionary, "AI_TEST_LAYOUT", false
	)
	var interpretation: Dictionary = OPEN_INTERPRETER.new().interpret_with_ai_object_profile(
		"冰箱", PackedByteArray(), {}, accepted
	)
	var blueprint := interpretation.get("blueprint") as WeaponBlueprint
	var scaffold: Dictionary = MECHANISM_SCAFFOLD.fallback(blueprint)
	var asset := scaffold.get("asset") as WeaponVisualAsset
	var resolution: Dictionary = MECHANISM_AXES.resolve_ai(
		asset, blueprint.affordance, blueprint.affordance_source
	)
	var profile := resolution.get("profile") as Resource
	var motion := MELEE_COMPILER.new().compile(profile, asset.anchors_dict(), asset.opaque_bounds) as Resource
	if blueprint == null or asset == null or profile == null or motion == null:
		return "could not assemble the melee layout fixture"
	var forge = OPEN_IDENTITY_SCENE.instantiate()
	root.add_child(forge)
	forge._ready()
	forge.current_blueprint = blueprint
	forge.current_asset = asset
	forge.current_mechanism_resolution = resolution
	forge.current_affordance_profile = profile
	forge.current_melee_motion_profile = motion
	forge._show_mechanism_summary()
	var result: Variant = _summary_page_result(forge.page as Control)
	forge.free()
	return result

func _test_ranged_summary_layout() -> Variant:
	var interpretation: Dictionary = OPEN_INTERPRETER.new().interpret(
		"M4A1", PackedByteArray(), {}
	)
	var blueprint := interpretation.get("blueprint") as WeaponBlueprint
	var scaffold: Dictionary = FIREARM_SCAFFOLD.fallback(blueprint)
	var asset := scaffold.get("asset") as WeaponVisualAsset
	var runtime: Dictionary = RANGED_AXES.compile(
		blueprint.affordance, blueprint.affordance_source
	)
	if blueprint == null or asset == null or not bool(runtime.get("ok", false)):
		return "could not assemble the ranged layout fixture"
	var forge = OPEN_IDENTITY_SCENE.instantiate()
	root.add_child(forge)
	forge._ready()
	forge.current_blueprint = blueprint
	forge.current_asset = asset
	forge.current_ranged_mechanism = runtime
	forge._show_ranged_mechanism_summary()
	var result: Variant = _summary_page_result(forge.page as Control)
	forge.free()
	return result

func _summary_page_result(summary_page: Control) -> Variant:
	if summary_page == null:
		return "summary page was not created"
	var minimum := summary_page.get_combined_minimum_size()
	if minimum.x > summary_page.size.x or minimum.y > summary_page.size.y:
		return "summary needs %s but viewport is %s" % [str(minimum), str(summary_page.size)]
	if not _contains_scroll_container(summary_page):
		return "long mechanism details are not scrollable"
	return true

func _contains_scroll_container(node: Node) -> bool:
	for child: Node in node.get_children():
		if child is ScrollContainer or _contains_scroll_container(child):
			return true
	return false

func _write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value))
