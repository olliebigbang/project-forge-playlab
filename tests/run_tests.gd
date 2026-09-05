extends SceneTree

const BLUEPRINT := preload("res://scripts/data/weapon_blueprint.gd")
const DELTA := preload("res://scripts/data/blueprint_delta.gd")
const RENDERER := preload("res://scripts/systems/procedural_weapon_renderer.gd")
const RESOLVER := preload("res://scripts/systems/anchor_resolver.gd")
const SEMANTIC_RESOLVER := preload("res://scripts/systems/semantic_anchor_resolver.gd")
const SEMANTIC_CALIBRATOR := preload("res://scripts/ui/semantic_anchor_calibrator.gd")
const RULES := preload("res://scripts/systems/combat_rules.gd")
const FLOW := preload("res://scripts/systems/flow_policy.gd")
const LOGGER := preload("res://scripts/systems/event_logger.gd")
const INTERPRETER := preload("res://scripts/services/mock_weapon_interpreter.gd")
const VISUAL_PROVIDER := preload("res://scripts/services/forge_visual_provider.gd")
const MOCK_VISUAL_PROVIDER := preload("res://scripts/services/mock_forge_visual_provider.gd")
const OPEN_VISUAL_PROMPT := preload("res://scripts/services/open_identity_visual_prompt.gd")
const OPEN_IDENTITY_TRAINING_ARENA := preload("res://scripts/systems/open_identity_training_arena.gd")
const OPEN_IDENTITY_FLOW := preload("res://scripts/open_identity_spike.gd")
const MECHANISM_HANDOFF := preload("res://scripts/combat_feel/runtime_mechanism_handoff.gd")
const MELEE_MOTION_COMPILER := preload("res://scripts/combat_feel/melee_motion_compiler.gd")
const COMBAT_FEEL_SLICE := preload("res://scripts/combat_feel/combat_feel_slice_0.gd")
const COMBAT_FEEL_ASSET_LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")
const SKETCH_CANVAS := preload("res://scripts/ui/sketch_canvas.gd")

var passed := 0
var failed := 0

func _initialize() -> void:
	print("Forge Playlab V1 deterministic test suite")
	_run("Blueprint required fields and enums", _test_blueprint_required)
	_run("Blueprint preserves isolated AI affordance provenance", _test_blueprint_ai_affordance_roundtrip)
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
	_run("Visual provider ignores stale revisions", _test_visual_provider_revision)
	_run("Mock visual provider remains operational", _test_mock_visual_provider)
	_run("Open identity scene is the active training-only entry", _test_open_identity_entry)
	_run("Open identity prompt preserves player identity", _test_open_identity_prompt)
	_run("Text-only identity input excludes a retained sketch", _test_open_identity_text_only_isolation)
	_run("One clarification survives cancel and retry for unchanged input", _test_open_identity_clarification_persistence)
	_run("Generated identity requires explicit player confirmation", _test_open_identity_confirmation_gate)
	_run("Heavy melee stops before image generation without AI axes", _test_heavy_melee_semantic_preflight)
	_run("Heavy melee without AI affordance fails closed", _test_heavy_melee_mechanism_gate)
	_run("Automatic AI mechanism card has no player mechanism controls", _test_automatic_mechanism_ui)
	_run("Mechanism scaffold fallback works without a visual provider", _test_mechanism_scaffold_fallback)
	_run("AI-resolved mechanism card compiles and hands off exactly once", _test_mechanism_compile_and_handoff)
	_run("Open identity training arena remains identity-agnostic", _test_open_identity_arena_contract)
	_run("Open identity effects are gated by effect type", _test_open_identity_effect_gates)
	_run("Semantic anchors are behavior-declared", _test_semantic_required_types)
	_run("Two-hand secondary grip derives from Alpha", _test_semantic_secondary_grip)
	_run("Returning pivot uses Alpha centroid", _test_semantic_spin_pivot)
	_run("Semantic calibration saves complete final anchors", _test_semantic_calibration_shape)
	_run("Calibrated training asset normalizes orientation without source mutation", _test_semantic_asset_copy)
	_run("Spike 1 corpus contains exactly 11 existing sprites", _test_semantic_corpus)
	_run("Semantic calibrator completes the two-step pointer flow", _test_semantic_two_step_pointer_flow)
	_run("Retaining auto suggestion restores original confidence", _test_semantic_auto_restore)
	print("RESULT: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _run(test_name: String, test_callable: Callable) -> void:
	var result: Variant = test_callable.call()
	if result is bool and result:
		passed += 1
		print("PASS | %s" % test_name)
	else:
		failed += 1
		printerr("FAIL | %s | %s" % [test_name, str(result)])

func _test_blueprint_required() -> Variant:
	var blueprint: WeaponBlueprint = BLUEPRINT.fixed_blueprint("gatling")
	if blueprint.id.is_empty() or blueprint.display_name.is_empty() or blueprint.fantasy_summary.is_empty():
		return "missing required text"
	if blueprint.source_identity.is_empty() or blueprint.player_identity_text.is_empty() or blueprint.visual_description.is_empty():
		return "missing identity/visual boundary"
	if not blueprint.behavior_family in BLUEPRINT.BEHAVIOR_FAMILIES:
		return "invalid behavior"
	if not blueprint.grip_profile in BLUEPRINT.GRIP_PROFILES:
		return "invalid grip"
	return true

func _test_blueprint_ai_affordance_roundtrip() -> Variant:
	var blueprint: WeaponBlueprint = BLUEPRINT.fixed_blueprint("greatsword")
	blueprint.affordance = {
		"handle_length": "long", "body_length": "long", "grip_topology": "two_hand_handle",
		"rigidity": "rigid", "mass_distribution": "front", "contact_surface": "edge",
		"secondary_contact_surface": "none", "has_point": false, "has_edge": true,
		"has_broad_face": false, "has_barrel": false, "has_stock": false,
		"confidence": 0.91, "evidence_parts": ["long blade", "two-hand hilt"],
	}
	blueprint.affordance_source = "anthropic:claude-sonnet-5"
	var serialized := blueprint.to_dict()
	var restored := BLUEPRINT.from_dict(serialized) as WeaponBlueprint
	(serialized["affordance"] as Dictionary)["rigidity"] = "flexible"
	if restored.affordance_source != blueprint.affordance_source:
		return "AI provenance was lost"
	if str(restored.affordance.get("rigidity", "")) != "rigid":
		return "restored affordance aliases the serialized dictionary"
	return restored.affordance == blueprint.affordance

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
	if not ResourceLoader.exists("res://scenes/open_identity_spike.tscn"):
		return "open identity scene missing"
	var scene: Resource = load("res://scenes/open_identity_spike.tscn")
	if scene == null:
		return "open identity scene failed to load"
	var project_config := FileAccess.get_file_as_string("res://project.godot")
	if not project_config.contains('run/main_scene="res://scenes/open_identity_spike.tscn"'):
		return "open identity scene is not active"
	var config := FileAccess.get_file_as_string("res://export_presets.cfg")
	return config.contains("name=\"Web\"") and config.contains("build/web/index.html") and config.contains("tools/comfyui/*") and config.contains("scenes/semantic_anchor_spike.tscn")

func _test_visual_provider_revision() -> Variant:
	var provider := VISUAL_PROVIDER.new() as ForgeVisualProvider
	provider.request_revision = 4
	return provider.accepts_revision(4) and not provider.accepts_revision(3) and not provider.accepts_revision(5)

func _test_mock_visual_provider() -> Variant:
	var provider := MOCK_VISUAL_PROVIDER.new() as MockForgeVisualProvider
	provider.request_visual(BLUEPRINT.fixed_blueprint("gatling"), "", PackedByteArray())
	var result: Dictionary = provider.poll()
	return str(result.get("status", "")) == "success" and result.get("asset") is WeaponVisualAsset

func _test_open_identity_entry() -> Variant:
	var source := FileAccess.get_file_as_string("res://scripts/open_identity_spike.gd")
	if not source.contains('preload("res://scripts/systems/open_identity_training_arena.gd")'):
		return "active scene does not instantiate OpenIdentityTrainingArena"
	if not source.contains('arena.start_stage("training", current_blueprint, current_asset)'):
		return "training handoff missing"
	for forbidden: String in ['"room_1"', '"room_2"', "_finish_training"]:
		if source.contains(forbidden):
			return "combat-room transition leaked into Spike 2: %s" % forbidden
	if source.contains("MOCK_CANNOT_RENDER_ARBITRARY_PLAYER_IDENTITY") == false:
		return "Mock boundary is not explicit"
	if source.count("WeaponBlueprint.fixed_blueprint(") != 1 or not source.contains("local_sample_only"):
		return "fixed visual fixture escaped the single labelled LOCAL SAMPLE boundary"
	if source.contains("ProceduralWeaponRenderer"):
		return "procedural fixed renderer leaked into the normal identity flow"
	if source.contains("local_provider.health_check()"):
		return "synchronous ComfyUI health check can freeze the active Godot UI"
	return true

func _test_open_identity_prompt() -> Variant:
	var blueprint := BLUEPRINT.new() as WeaponBlueprint
	blueprint.player_identity_text = "会连续发射螺丝的木椅"
	blueprint.source_identity = blueprint.player_identity_text
	blueprint.visual_description = blueprint.player_identity_text
	blueprint.preserved_visual_features = ["rough_player_sketch_present", "sketch_aspect_ratio=1.400"]
	var prompt: String = OPEN_VISUAL_PROMPT.build(blueprint)
	if not prompt.contains(blueprint.player_identity_text):
		return "identity omitted from generation prompt"
	if not prompt.contains("Behavior contract") or not prompt.contains("forge-open-identity-v3"):
		return "versioned action-only visual contract missing"
	for fixed_identity: String in ["gatling", "mechanical umbrella", "chainsaw greatsword"]:
		if prompt.to_lower().contains(fixed_identity):
			return "fixed visual identity leaked: %s" % fixed_identity
	return prompt.length() < 1400

func _test_open_identity_text_only_isolation() -> Variant:
	var flow = OPEN_IDENTITY_FLOW.new()
	var edit := TextEdit.new()
	edit.text = "喷射高温蒸汽的旧茶壶"
	var canvas := SKETCH_CANVAS.new() as SketchCanvas
	canvas.size = Vector2(512, 512)
	canvas.strokes = [PackedVector2Array([Vector2(80, 90), Vector2(410, 360)])]
	flow.description_edit = edit
	flow.sketch_canvas = canvas
	flow.input_mode = "description"
	flow._capture_forge_input()
	var result: Variant = true
	if not flow.saved_geometry.is_empty() or not flow.saved_sketch_png.is_empty():
		result = "text-only mode submitted stale sketch evidence"
	elif int(flow.saved_canvas_geometry.get("stroke_count", 0)) != 1:
		result = "player sketch was not retained for later use"
	edit.free()
	canvas.free()
	flow.free()
	return result

func _test_open_identity_clarification_persistence() -> Variant:
	var flow = OPEN_IDENTITY_FLOW.new()
	var geometry := {"raw_strokes": [[[0.1, 0.2], [0.8, 0.7]]]}
	var signature: String = flow._input_signature("sketch", "", geometry)
	flow.current_input_signature = signature
	flow.clarified_input_signature = signature
	flow.clarified_identity = "旧木桌"
	var result: Variant = true
	if flow._stored_clarification() != "IDENTITY::旧木桌":
		result = "unchanged input lost its one-time clarification"
	else:
		flow.current_input_signature = flow._input_signature("sketch", "", {"raw_strokes": [[[0.2, 0.2]]]})
		if not flow._stored_clarification().is_empty():
			result = "changed input reused a stale clarification"
	flow.free()
	return result

func _test_open_identity_confirmation_gate() -> Variant:
	var flow = OPEN_IDENTITY_FLOW.new()
	flow.current_blueprint = BLUEPRINT.new() as WeaponBlueprint
	var result: Variant = true
	if flow._training_identity_is_confirmed():
		result = "unconfirmed generated identity can enter training"
	else:
		flow.visual_identity_confirmed = true
		if not flow._training_identity_is_confirmed():
			result = "explicit player confirmation did not unlock training"
		else:
			flow.visual_identity_confirmed = false
			flow.current_blueprint.modifiers["local_sample_only"] = true
			if flow._training_identity_is_confirmed():
				result = "mutable blueprint modifier bypassed player confirmation"
	flow.free()
	return result

func _test_heavy_melee_semantic_preflight() -> Variant:
	var flow = OPEN_IDENTITY_FLOW.new()
	flow._build_theme()
	flow.arena = OPEN_IDENTITY_TRAINING_ARENA.new()
	flow.add_child(flow.arena)
	flow.ui_layer = CanvasLayer.new()
	flow.add_child(flow.ui_layer)
	flow.provider_mode = "LOCAL_COMFYUI"
	var interpretation: Dictionary = flow.interpreter.interpret("会用边缘重击的巨大鸡腿", PackedByteArray(), {})
	flow._handle_interpretation_result(interpretation)
	var option_controls: Array[Node] = flow.find_children("*", "OptionButton", true, false)
	var ok: bool = flow.state == "ai_semantic_failed" and flow.provider == null and flow.current_asset == null
	ok = ok and option_controls.is_empty()
	flow.free()
	return true if ok else "heavy melee reached image generation or player mechanism controls without AI axes"

func _test_heavy_melee_mechanism_gate() -> Variant:
	var flow = OPEN_IDENTITY_FLOW.new()
	flow.current_blueprint = BLUEPRINT.fixed_blueprint("greatsword")
	flow.current_asset = RESOLVER.resolve(RENDERER.build_image(flow.current_blueprint), flow.current_blueprint)
	if not flow._requires_mechanism_profile():
		flow.free()
		return "heavy melee skipped automatic mechanism resolution"
	if flow._mechanism_profile_is_ready():
		flow.free()
		return "empty mechanism state passed its gate"
	var incomplete: Dictionary = flow._resolve_ai_mechanism()
	if bool(incomplete.get("ok", false)) or str(incomplete.get("error", "")) != "AI_AFFORDANCE_SOURCE_MISSING":
		flow.free()
		return "missing AI affordance did not fail closed: %s" % str(incomplete)
	if bool(incomplete.get("player_confirmation_required", true)) or incomplete.has("questions"):
		flow.free()
		return "missing AI affordance was routed back to the player"
	flow.current_blueprint = BLUEPRINT.fixed_blueprint("gatling")
	if flow._requires_mechanism_profile():
		flow.free()
		return "non-melee behavior was forced through the melee mechanism card"
	flow.free()
	return true

func _test_mechanism_compile_and_handoff() -> Variant:
	var flow = OPEN_IDENTITY_FLOW.new()
	var loaded: Dictionary = COMBAT_FEEL_ASSET_LOADER.new().load_motion_grammar_asset("frying_pan")
	flow.current_blueprint = loaded.get("blueprint") as WeaponBlueprint
	flow.current_asset = loaded.get("asset") as WeaponVisualAsset
	var frozen_affordance := loaded.get("affordance_profile") as Resource
	flow.current_blueprint.affordance = frozen_affordance.to_dict()
	flow.current_blueprint.affordance_source = "ai_semantic_v1_2"
	var resolved: Dictionary = flow._resolve_ai_mechanism()
	if not bool(resolved.get("ok", false)):
		flow.free()
		return "AI axes did not compile: %s" % str(resolved.get("error", ""))
	var affordance := resolved.get("affordance_profile") as Resource
	var motion := resolved.get("motion_profile") as Resource
	flow._apply_ai_mechanism_resolution(resolved)
	if not flow._mechanism_profile_is_ready() or motion.combo_recipe == null:
		flow.free()
		return "compiled mechanism profile did not unlock its dedicated gate"
	var handoff: Node = get_root().get_node_or_null("MechanismHandoff")
	if handoff == null:
		flow.free()
		return "autoloaded mechanism handoff is missing"
	handoff.call("clear")
	var bypass_error := str(handoff.call("store", flow.current_blueprint, flow.current_asset, frozen_affordance))
	if bypass_error != "MECHANISM_HANDOFF_PROFILE_NOT_AI_RESOLVED" or bool(handoff.call("has_pending")):
		flow.free()
		return "manual sidecar bypassed the AI-resolved handoff boundary: %s" % bypass_error
	var error := str(handoff.call("store", flow.current_blueprint, flow.current_asset, affordance))
	if not error.is_empty() or not bool(handoff.call("has_pending")):
		flow.free()
		return "valid mechanism handoff rejected: %s" % error
	var combat = COMBAT_FEEL_SLICE.new()
	combat.compiler = MELEE_MOTION_COMPILER.new()
	combat.runtime_mechanism_handoff = handoff
	var accepted: bool = combat._load_requested_weapon()
	var runtime_compiled: Variant = combat._compile_loaded_weapon() if accepted else null
	var consumed_once := not bool(handoff.call("has_pending")) and (handoff.call("take") as Dictionary).is_empty()
	var ok: bool = accepted and combat.affordance_profile == affordance
	ok = ok and bool(combat.launched_from_open_playtest) and runtime_compiled is Resource and consumed_once
	combat.free()
	flow.free()
	return true if ok else "mechanism handoff was not consumed once by the combat compiler"

func _test_automatic_mechanism_ui() -> Variant:
	var flow = OPEN_IDENTITY_FLOW.new()
	flow._build_theme()
	flow.arena = OPEN_IDENTITY_TRAINING_ARENA.new()
	flow.add_child(flow.arena)
	flow.ui_layer = CanvasLayer.new()
	flow.add_child(flow.ui_layer)
	var loaded: Dictionary = COMBAT_FEEL_ASSET_LOADER.new().load_motion_grammar_asset("frying_pan")
	flow.current_blueprint = loaded.get("blueprint") as WeaponBlueprint
	flow.current_asset = loaded.get("asset") as WeaponVisualAsset
	var frozen_affordance := loaded.get("affordance_profile") as Resource
	flow.current_blueprint.affordance = frozen_affordance.to_dict()
	flow.current_blueprint.affordance_source = "ai_semantic_v1_2"
	flow.visual_identity_confirmed = true
	flow._accept_visual_identity()
	var option_controls: Array[Node] = flow.find_children("*", "OptionButton", true, false)
	var ok: bool = flow.state == "mechanism_summary" and option_controls.is_empty()
	ok = ok and flow._mechanism_profile_is_ready()
	ok = ok and bool(flow.current_mechanism_resolution.get("automatic", false))
	ok = ok and not bool(flow.current_mechanism_resolution.get("player_mechanism_input_used", true))
	var source := FileAccess.get_file_as_string("res://scripts/open_identity_spike.gd")
	ok = ok and not source.contains("OptionButton.new()")
	ok = ok and not source.contains("_answer_clarification(\"heavy_melee\")")
	flow.free()
	return true if ok else "automatic mechanism card still exposes player mechanism choices"

func _test_mechanism_scaffold_fallback() -> Variant:
	var flow = OPEN_IDENTITY_FLOW.new()
	flow._build_theme()
	flow.arena = OPEN_IDENTITY_TRAINING_ARENA.new()
	flow.add_child(flow.arena)
	flow.ui_layer = CanvasLayer.new()
	flow.add_child(flow.ui_layer)
	var loaded: Dictionary = COMBAT_FEEL_ASSET_LOADER.new().load_motion_grammar_asset("frying_pan")
	flow.current_blueprint = loaded.get("blueprint") as WeaponBlueprint
	var frozen_affordance := loaded.get("affordance_profile") as Resource
	flow.current_blueprint.affordance = frozen_affordance.to_dict()
	flow.current_blueprint.affordance_source = "ai_semantic_v1_2"
	flow.current_blueprint.visual_structure_brief.clear()
	flow.current_interpretation_source = "AI TEST"
	flow.current_explanation = "identity remains pending"
	flow.provider_mode = "MOCK"
	var activated: bool = flow._activate_mechanism_scaffold_fallback("TEST_PROVIDER_NOT_CONFIGURED")
	var ok: bool = activated and flow.state == "review" and flow.current_asset != null
	ok = ok and flow.current_asset.source_image.get_size() == Vector2i(96, 96)
	ok = ok and str(flow.current_manifest.get("visual_mode", "")) == "mechanism_scaffold_fallback"
	ok = ok and not bool(flow.current_manifest.get("external_generator_succeeded", true))
	ok = ok and str(flow.current_manifest.get("structure_authority", "")) == "mechanism_axes"
	ok = ok and not bool(flow.current_manifest.get("player_mechanism_confirmation_required", true))
	ok = ok and not flow.visual_identity_confirmed
	ok = ok and bool(flow.current_mechanism_visual_gate.get("ok", false))
	ok = ok and FileAccess.file_exists(flow.current_output_directory.path_join("processed_sprite.png"))
	var option_controls: Array[Node] = flow.find_children("*", "OptionButton", true, false)
	ok = ok and option_controls.is_empty()
	flow.free()
	return true if ok else "mechanism scaffold fallback did not reach identity-only review honestly"


func _test_open_identity_arena_contract() -> Variant:
	if Array(BLUEPRINT.BEHAVIOR_FAMILIES) != ["sustained_ranged", "returning_thrown", "heavy_melee"]:
		return "behavior-family boundary changed: %s" % str(BLUEPRINT.BEHAVIOR_FAMILIES)
	var source := FileAccess.get_file_as_string("res://scripts/systems/open_identity_training_arena.gd")
	for identity_mapping: String in ["gatling", "umbrella", "greatsword", "teapot", "chair", "table", "chicken"]:
		if source.to_lower().contains(identity_mapping):
			return "object-specific runtime mapping leaked: %s" % identity_mapping
	for required_contract: String in [
		'super._update_melee_attack',
		'super._draw_player_and_weapon',
		'match blueprint.effect_type',
		'draw_texture_rect(asset.texture'
	]:
		if not source.contains(required_contract):
			return "training runtime does not consume contract: %s" % required_contract
	var parent_source := FileAccess.get_file_as_string("res://scripts/systems/gameplay_arena.gd")
	if not parent_source.contains('blueprint.delivery == "whole_object_return"') or not parent_source.contains("draw_texture_rect(asset.texture") or not parent_source.contains("_build_melee_frame"):
		return "shared held/returning renderer is missing the delivered source pixels"
	if source.contains("fixed_blueprint(") or source.contains("ProceduralWeaponRenderer"):
		return "training runtime substitutes a fixed/procedural identity"
	var arena := OPEN_IDENTITY_TRAINING_ARENA.new() as OpenIdentityTrainingArena
	if arena == null or not arena is GameplayArena:
		return "specialized training arena failed to instantiate"
	arena.free()
	return true

func _test_open_identity_effect_gates() -> Variant:
	var plain_return_neighbor_hp := _returning_neighbor_hp("player_described_effect")
	var electric_return_neighbor_hp := _returning_neighbor_hp("electric_current")
	if not is_equal_approx(plain_return_neighbor_hp, 100.0):
		return "generic returning identity received an implicit chain effect"
	if not electric_return_neighbor_hp < plain_return_neighbor_hp:
		return "electric_current did not drive returning chain damage"
	var plain_melee_health := _melee_health_after_hit("player_described_effect")
	var lifesteal_melee_health := _melee_health_after_hit("lifesteal")
	if not is_equal_approx(plain_melee_health, 50.0):
		return "generic heavy identity received implicit lifesteal"
	if not lifesteal_melee_health > plain_melee_health:
		return "lifesteal did not drive melee healing"
	var plain_burn := _projectile_burn_after_hit("player_described_effect")
	var thermal_burn := _projectile_burn_after_hit("thermal_emission")
	if not is_equal_approx(plain_burn, 0.0):
		return "generic ranged identity received implicit burn"
	if not thermal_burn > plain_burn:
		return "thermal_emission did not drive projectile burn"
	return true

func _returning_neighbor_hp(effect_type: String) -> float:
	var arena := OPEN_IDENTITY_TRAINING_ARENA.new() as OpenIdentityTrainingArena
	var blueprint := BLUEPRINT.new() as WeaponBlueprint
	blueprint.behavior_family = "returning_thrown"
	blueprint.delivery = "whole_object_return"
	blueprint.effect_type = effect_type
	arena.blueprint = blueprint
	arena.asset = _minimal_visual_asset()
	arena.player_position = Vector2(100, 100)
	arena.facing = 1.0
	var hit_position: Vector2 = arena._muzzle_world()
	arena.enemies = [
		_test_enemy(1, hit_position, 100.0),
		_test_enemy(2, hit_position + Vector2(50, 0), 100.0)
	]
	arena._update_returning_attack(true, 0.0)
	var neighbor_hp := float(arena.enemies[1]["hp"])
	arena.free()
	return neighbor_hp

func _melee_health_after_hit(effect_type: String) -> float:
	var arena := OPEN_IDENTITY_TRAINING_ARENA.new() as OpenIdentityTrainingArena
	var blueprint := BLUEPRINT.new() as WeaponBlueprint
	blueprint.behavior_family = "heavy_melee"
	blueprint.delivery = "whole_object_strike"
	blueprint.effect_type = effect_type
	var axes := preload("res://scripts/combat_feel/object_affordance_profile.gd").new()
	axes.evidence_parts = PackedStringArray(["controlled legacy effect test"])
	blueprint.affordance = axes.to_dict()
	arena.blueprint = blueprint
	arena.asset = _minimal_visual_asset()
	arena.player_position = Vector2(100, 100)
	arena.player_health = 50.0
	arena.facing = 1.0
	arena.enemies = [_test_enemy(1, Vector2(150, 100), 100.0)]
	arena._update_melee_attack(true, 0.0)
	while not arena.melee_runtime.active(): arena._update_melee_attack(false, 1.0 / 120.0)
	var points: PackedVector2Array = arena.melee_frame.get("contacts", PackedVector2Array())
	if not points.is_empty(): arena.enemies[0]["pos"] = points[-1]
	arena._resolve_compiled_melee_hits()
	var health := arena.player_health
	arena.free()
	return health

func _projectile_burn_after_hit(effect_type: String) -> float:
	var arena := OPEN_IDENTITY_TRAINING_ARENA.new() as OpenIdentityTrainingArena
	var blueprint := BLUEPRINT.new() as WeaponBlueprint
	blueprint.behavior_family = "sustained_ranged"
	blueprint.delivery = "continuous_emission"
	blueprint.effect_type = effect_type
	arena.blueprint = blueprint
	arena.asset = _minimal_visual_asset()
	arena.player_position = Vector2(100, 100)
	arena.enemies = [_test_enemy(1, Vector2(150, 100), 100.0)]
	arena.projectiles = [{
		"pos": Vector2(150, 100), "vel": Vector2.ZERO, "life": 1.0,
		"pierces": 0, "hit": {}
	}]
	arena._update_projectiles(0.0)
	var burn := float(arena.enemies[0]["burn"])
	arena.free()
	return burn

func _minimal_visual_asset() -> WeaponVisualAsset:
	var asset := WeaponVisualAsset.new()
	asset.canvas_size = Vector2i(96, 96)
	asset.source_image = Image.create(96, 96, false, Image.FORMAT_RGBA8)
	asset.source_image.fill(Color.TRANSPARENT)
	asset.source_image.fill_rect(Rect2i(16, 44, 66, 8), Color.WHITE)
	asset.texture = ImageTexture.create_from_image(asset.source_image)
	asset.opaque_bounds = asset.source_image.get_used_rect()
	asset.grip_primary = Vector2(20, 48)
	asset.grip_secondary = Vector2(32, 48)
	asset.muzzle = Vector2(70, 48)
	asset.tip = Vector2(80, 48)
	asset.spin_pivot = Vector2(48, 48)
	return asset

func _test_enemy(enemy_id: int, position: Vector2, health: float) -> Dictionary:
	return {
		"id": enemy_id, "type": "target", "pos": position, "hp": health,
		"max_hp": health, "facing": -1.0, "hurt": 0.0, "burn": 0.0
	}

func _test_semantic_required_types() -> Variant:
	var ranged := BLUEPRINT.new() as WeaponBlueprint
	ranged.behavior_family = "sustained_ranged"
	ranged.grip_profile = "bottom_handle"
	var ranged_required: Array[String] = SEMANTIC_RESOLVER.required_anchor_types(ranged)
	if ranged_required != ["GripPrimary", "EffectOrigin"]:
		return "one-hand ranged declaration was %s" % str(ranged_required)
	var returning := BLUEPRINT.new() as WeaponBlueprint
	returning.behavior_family = "returning_thrown"
	returning.grip_profile = "center_shaft"
	var returning_required: Array[String] = SEMANTIC_RESOLVER.required_anchor_types(returning)
	if not returning_required.has("GripPrimary") or not returning_required.has("StrikePoint") or not returning_required.has("SpinPivot"):
		return "returning declaration incomplete"
	for forbidden: String in ["Muzzle", "Tip", "GripSecondary"]:
		if returning_required.has(forbidden):
			return "returning declaration unexpectedly requires %s" % forbidden
	return true

func _test_semantic_secondary_grip() -> Variant:
	var blueprint: WeaponBlueprint = BLUEPRINT.fixed_blueprint("greatsword")
	var image: Image = RENDERER.build_image(blueprint)
	var calibration = SEMANTIC_RESOLVER.resolve(image, blueprint)
	if calibration == null or not calibration.required_anchor_types.has("GripSecondary"):
		return "two-hand behavior did not require secondary grip"
	calibration.set_manual_anchor("GripPrimary", calibration.anchor_point("GripPrimary") + Vector2(2, -1))
	SEMANTIC_RESOLVER.recompute_derived(calibration, image)
	var primary: Vector2 = calibration.anchor_point("GripPrimary")
	var secondary: Vector2 = calibration.anchor_point("GripSecondary")
	return primary.distance_to(secondary) >= 6.0 and SEMANTIC_RESOLVER.is_on_or_near_alpha(image, secondary, 2)

func _test_semantic_spin_pivot() -> Variant:
	var blueprint: WeaponBlueprint = BLUEPRINT.fixed_blueprint("umbrella")
	var image: Image = RENDERER.build_image(blueprint)
	var calibration = SEMANTIC_RESOLVER.resolve(image, blueprint)
	if calibration == null or not calibration.required_anchor_types.has("SpinPivot"):
		return "returning behavior did not require spin pivot"
	SEMANTIC_RESOLVER.recompute_derived(calibration, image)
	return calibration.anchor_point("SpinPivot").distance_to(SEMANTIC_RESOLVER.alpha_centroid(image)) < 0.01

func _test_semantic_calibration_shape() -> Variant:
	var blueprint: WeaponBlueprint = BLUEPRINT.fixed_blueprint("gatling")
	var image: Image = RENDERER.build_image(blueprint)
	var calibration = SEMANTIC_RESOLVER.resolve(image, blueprint)
	calibration.case_id = "test_case"
	calibration.run_id = "test_run"
	calibration.set_manual_anchor("GripPrimary", calibration.anchor_point("GripPrimary"))
	calibration.set_manual_anchor("EffectOrigin", calibration.anchor_point("EffectOrigin"))
	SEMANTIC_RESOLVER.recompute_derived(calibration, image)
	var saved: Dictionary = calibration.to_dict()
	for field: String in ["auto_anchors", "corrected_anchors", "anchor_source", "confidence", "required_anchor_types"]:
		if not saved.has(field):
			return "missing %s" % field
	var corrected: Dictionary = saved.get("corrected_anchors", {})
	for anchor_type: String in calibration.required_anchor_types:
		if not corrected.has(anchor_type):
			return "final anchors omitted %s" % anchor_type
	return true

func _test_semantic_asset_copy() -> Variant:
	var blueprint := BLUEPRINT.new() as WeaponBlueprint
	blueprint.behavior_family = "sustained_ranged"
	blueprint.grip_profile = "bottom_handle"
	var image: Image = RENDERER.build_image(blueprint)
	var original_pixels := image.get_data()
	var calibration = SEMANTIC_RESOLVER.resolve(image, blueprint)
	calibration.set_manual_anchor("GripPrimary", Vector2(80, 50))
	calibration.set_manual_anchor("EffectOrigin", Vector2(10, 48))
	var copy: WeaponVisualAsset = calibration.build_asset_copy()
	if copy == null:
		return "asset copy failed"
	if not bool(calibration.training_transform.get("flip_x", false)):
		return "left-facing action was not normalized"
	if copy.source_image == image or image.get_data() != original_pixels:
		return "source image was mutated"
	return copy.muzzle.x > copy.grip_primary.x and copy.canvas_size == Vector2i(96, 96)

func _test_semantic_corpus() -> Variant:
	var path := "res://tools/comfyui/anchor_calibration/test_cases/corpus.json"
	if not FileAccess.file_exists(path):
		return "corpus missing"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return "corpus invalid JSON"
	var runs: Array = (parsed as Dictionary).get("runs", [])
	if runs.size() != 11:
		return "expected 11, got %d" % runs.size()
	var seen: Dictionary = {}
	for value: Variant in runs:
		var entry := value as Dictionary
		var key := "%s/%s" % [entry.get("case_id", ""), entry.get("run_id", "")]
		var sprite_path := str(entry.get("sprite_path", ""))
		if seen.has(key) or not FileAccess.file_exists(sprite_path):
			return "duplicate or missing sprite: %s" % key
		seen[key] = true
		var image := Image.load_from_file(ProjectSettings.globalize_path(sprite_path))
		if image == null or image.get_size() != Vector2i(96, 96):
			return "invalid corpus image: %s" % key
	return true

func _test_semantic_two_step_pointer_flow() -> Variant:
	var blueprint: WeaponBlueprint = BLUEPRINT.fixed_blueprint("gatling")
	var image: Image = RENDERER.build_image(blueprint)
	var calibration = SEMANTIC_RESOLVER.resolve(image, blueprint)
	var calibrator = SEMANTIC_CALIBRATOR.new()
	root.add_child(calibrator)
	calibrator.size = Vector2(760, 520)
	calibrator.configure(calibration, image, "pointer-test")
	var sprite_scale := 400.0 / 96.0
	var sprite_origin := Vector2(180, 48)
	var initial_grip: Vector2 = calibration.anchor_point("GripPrimary")

	var outside_press := InputEventMouseButton.new()
	outside_press.button_index = MOUSE_BUTTON_LEFT
	outside_press.pressed = true
	outside_press.position = Vector2(12, 100)
	calibrator._gui_input(outside_press)
	var outside_motion := InputEventMouseMotion.new()
	outside_motion.position = sprite_origin + Vector2(24, 50) * sprite_scale
	calibrator._gui_input(outside_motion)
	if calibration.anchor_point("GripPrimary") != initial_grip:
		calibrator.free()
		return "drag beginning outside sprite changed the grip"

	var grip_press := InputEventMouseButton.new()
	grip_press.button_index = MOUSE_BUTTON_LEFT
	grip_press.pressed = true
	grip_press.position = sprite_origin + Vector2(20, 52) * sprite_scale
	calibrator._gui_input(grip_press)
	var grip_drag := InputEventMouseMotion.new()
	grip_drag.position = sprite_origin + Vector2(24, 50) * sprite_scale
	calibrator._gui_input(grip_drag)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = grip_drag.position
	calibrator._gui_input(release)
	if calibration.anchor_point("GripPrimary").distance_to(Vector2(24, 50)) > 0.05:
		calibrator.free()
		return "grip click-drag did not set expected point"
	calibrator.confirm_current_step()
	if calibrator.current_step != 1 or calibrator.current_anchor_type() != "EffectOrigin":
		calibrator.free()
		return "first confirmation did not advance to action step"

	var completed := [false]
	calibrator.calibration_completed.connect(func() -> void: completed[0] = true)
	var action_press := InputEventMouseButton.new()
	action_press.button_index = MOUSE_BUTTON_LEFT
	action_press.pressed = true
	action_press.position = sprite_origin + Vector2(90, 48) * sprite_scale
	calibrator._gui_input(action_press)
	release.position = action_press.position
	calibrator._gui_input(release)
	calibrator.confirm_current_step()
	var passed_flow: bool = bool(completed[0]) and calibration.anchor_point("EffectOrigin").distance_to(Vector2(90, 48)) <= 0.05
	passed_flow = passed_flow and str(calibration.anchor_source.get("GripPrimary", "")) == "manual_player_calibration"
	passed_flow = passed_flow and str(calibration.anchor_source.get("EffectOrigin", "")) == "manual_player_calibration"
	calibrator.free()
	return passed_flow

func _test_semantic_auto_restore() -> Variant:
	var blueprint: WeaponBlueprint = BLUEPRINT.fixed_blueprint("gatling")
	var image: Image = RENDERER.build_image(blueprint)
	var calibration = SEMANTIC_RESOLVER.resolve(image, blueprint)
	var expected_confidence := float(calibration.auto_confidence.get("GripPrimary", -1.0))
	var expected_source := str(calibration.auto_anchor_source.get("GripPrimary", ""))
	calibration.set_manual_anchor("GripPrimary", Vector2(30, 40), 0.21)
	calibration.retain_auto_anchor("GripPrimary")
	return not calibration.corrected_anchors.has("GripPrimary") and is_equal_approx(float(calibration.confidence.get("GripPrimary", -2.0)), expected_confidence) and str(calibration.anchor_source.get("GripPrimary", "")) == expected_source
