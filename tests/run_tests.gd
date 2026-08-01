extends SceneTree

const BLUEPRINT := preload("res://scripts/data/weapon_blueprint.gd")
const DELTA := preload("res://scripts/data/blueprint_delta.gd")
const RENDERER := preload("res://scripts/systems/procedural_weapon_renderer.gd")
const RESOLVER := preload("res://scripts/systems/anchor_resolver.gd")
const RULES := preload("res://scripts/systems/combat_rules.gd")
const FLOW := preload("res://scripts/systems/flow_policy.gd")
const LOGGER := preload("res://scripts/systems/event_logger.gd")
const INTERPRETER := preload("res://scripts/services/mock_weapon_interpreter.gd")

var passed := 0
var failed := 0

func _initialize() -> void:
	print("Forge Playlab V1 deterministic test suite")
	_run("Blueprint required fields and enums", _test_blueprint_required)
	_run("Unsupported values repair deterministically", _test_blueprint_repair)
	_run("Three fixed blueprints instantiate", _test_fixed_blueprints)
	_run("Alpha bounds extraction", _test_alpha_bounds)
	_run("Default anchors resolve", _test_default_anchors)
	_run("Local grip correction finds opaque pixels", _test_local_grip)
	_run("No alpha fails safely", _test_no_alpha)
	_run("Muzzle and tip stay on forward edge", _test_muzzle_tip)
	_run("Delta cannot remove drawback for free", _test_delta_tradeoff)
	_run("Three weapons damage three enemies", _test_damage_matrix)
	_run("Guard has no hard immunity", _test_guard_no_immunity)
	_run("Forge is locked during combat", _test_combat_forge_lock)
	_run("Intermission change can happen once", _test_one_change)
	_run("Local JSONL logging writes", _test_logger)
	_run("Web export can load main flow", _test_web_startup)
	print("RESULT: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _run(test_name: String, test_callable: Callable) -> void:
	var result: Variant = test_callable.call()
	if result == true:
		passed += 1
		print("PASS | %s" % test_name)
	else:
		failed += 1
		printerr("FAIL | %s | %s" % [test_name, str(result)])

func _test_blueprint_required() -> Variant:
	var blueprint: WeaponBlueprint = BLUEPRINT.fixed_blueprint("gatling")
	if blueprint.id.is_empty() or blueprint.display_name.is_empty() or blueprint.fantasy_summary.is_empty():
		return "missing required text"
	if not blueprint.behavior_family in BLUEPRINT.BEHAVIOR_FAMILIES:
		return "invalid behavior"
	if not blueprint.grip_profile in BLUEPRINT.GRIP_PROFILES:
		return "invalid grip"
	return true

func _test_blueprint_repair() -> Variant:
	var blueprint := BLUEPRINT.new() as WeaponBlueprint
	blueprint.behavior_family = "anything_goes"
	blueprint.grip_profile = "magic_guess"
	blueprint.element = "ice"
	var reasons := blueprint.validate_and_repair()
	return reasons.size() >= 3 and blueprint.behavior_family == "sustained_ranged" and blueprint.element == "normal"

func _test_fixed_blueprints() -> Variant:
	var families: Array[String] = []
	for kind: String in ["gatling", "umbrella", "greatsword"]:
		var blueprint: WeaponBlueprint = BLUEPRINT.fixed_blueprint(kind)
		families.append(blueprint.behavior_family)
	return families == ["sustained_ranged", "returning_thrown", "heavy_melee"]

func _test_alpha_bounds() -> Variant:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y: int in range(7, 19):
		for x: int in range(4, 21):
			image.set_pixel(x, y, Color.WHITE)
	return RESOLVER.alpha_bounds(image) == Rect2i(4, 7, 17, 12)

func _test_default_anchors() -> Variant:
	var blueprint: WeaponBlueprint = BLUEPRINT.fixed_blueprint("gatling")
	var asset: WeaponVisualAsset = RESOLVER.resolve(RENDERER.build_image(blueprint), blueprint)
	return asset != null and asset.grip_primary.x < asset.spin_pivot.x and asset.anchor_confidence >= 0.7

func _test_local_grip() -> Variant:
	var blueprint: WeaponBlueprint = BLUEPRINT.fixed_blueprint("greatsword")
	var image: Image = RENDERER.build_image(blueprint)
	var asset: WeaponVisualAsset = RESOLVER.resolve(image, blueprint)
	var point := Vector2i(roundi(asset.grip_primary.x), roundi(asset.grip_primary.y))
	return image.get_pixelv(point).a > 0.1

func _test_no_alpha() -> Variant:
	var image := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	return RESOLVER.resolve(image, BLUEPRINT.fixed_blueprint("gatling")) == null

func _test_muzzle_tip() -> Variant:
	var blueprint: WeaponBlueprint = BLUEPRINT.fixed_blueprint("gatling")
	var asset: WeaponVisualAsset = RESOLVER.resolve(RENDERER.build_image(blueprint), blueprint)
	return asset.muzzle.x >= asset.opaque_bounds.end.x and asset.tip.x >= asset.opaque_bounds.end.x - 1

func _test_delta_tradeoff() -> Variant:
	var invalid := DELTA.new() as BlueprintDelta
	invalid.accepted_change = "remove_overheat"
	invalid.drawback_delta = "removed"
	invalid.player_summary = "removed"
	if invalid.is_valid():
		return "free removal accepted"
	var interpreter := INTERPRETER.new() as MockWeaponInterpreter
	var result: Dictionary = interpreter.apply_delta(BLUEPRINT.fixed_blueprint("gatling"), "不要过热")
	var applied: BlueprintDelta = result["delta"]
	return applied.is_valid() and not applied.tradeoff.is_empty() and applied.drawback_delta != "removed"

func _test_damage_matrix() -> Variant:
	for family: String in BLUEPRINT.BEHAVIOR_FAMILIES:
		for enemy: String in ["swarmling", "rusher", "guard"]:
			if not RULES.can_damage(family, enemy) or RULES.damage_against(family, enemy, true) <= 0.0:
				return "%s cannot damage %s" % [family, enemy]
	return true

func _test_guard_no_immunity() -> Variant:
	for family: String in BLUEPRINT.BEHAVIOR_FAMILIES:
		if RULES.damage_against(family, "guard", true) < 1.0:
			return false
	return true

func _test_combat_forge_lock() -> Variant:
	var policy := FLOW.new() as FlowPolicy
	policy.in_combat = true
	return not policy.can_open_forge() and not policy.can_apply_intermission_change()

func _test_one_change() -> Variant:
	var policy := FLOW.new() as FlowPolicy
	if not policy.consume_intermission_change():
		return "first change rejected"
	return not policy.consume_intermission_change()

func _test_logger() -> Variant:
	var logger := LOGGER.new() as PlaylabEventLogger
	logger.output_path = "user://playlab/test-events.jsonl"
	var global_path := ProjectSettings.globalize_path(logger.output_path)
	if FileAccess.file_exists(logger.output_path):
		DirAccess.remove_absolute(global_path)
	if not logger.log_event("session_started", {"description": "must not persist", "offline": true}):
		return "write returned false"
	var file := FileAccess.open(logger.output_path, FileAccess.READ)
	if file == null:
		return "file missing"
	var line := file.get_line()
	return line.contains("session_started") and not line.contains("must not persist")

func _test_web_startup() -> Variant:
	if not ResourceLoader.exists("res://scenes/main.tscn"):
		return "main scene missing"
	var scene: Resource = load("res://scenes/main.tscn")
	if scene == null:
		return "main scene failed to load"
	var config := FileAccess.get_file_as_string("res://export_presets.cfg")
	return config.contains("name=\"Web\"") and config.contains("build/web/index.html")

