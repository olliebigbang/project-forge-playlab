extends SceneTree

const INTERPRETER := preload("res://scripts/services/open_identity_interpreter.gd")
const CATALOG := preload("res://scripts/combat_feel/firearm_identity_catalog.gd")
const AXES := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")
const PIXEL_SCAFFOLD := preload("res://scripts/combat_feel/firearm_pixel_scaffold.gd")
const SCAFFOLD_PIPELINE := preload("res://scripts/combat_feel/firearm_visual_scaffold_pipeline.gd")
const VISUAL_IDENTITY_GATE := preload("res://scripts/combat_feel/firearm_visual_identity_gate.gd")
const VISUAL_IDENTITY_CARD := preload("res://scripts/combat_feel/firearm_visual_identity_card.gd")
const LOCAL_VISUAL_PROVIDER := preload("res://scripts/services/local_comfy_forge_visual_provider.gd")
const FAL_VISUAL_PROVIDER := preload("res://scripts/services/fal_firearm_visual_provider.gd")
const ARENA := preload("res://scripts/systems/open_identity_training_arena.gd")
const OPEN_FLOW := preload("res://scripts/open_identity_spike.gd")

const REQUIRED_CASES: Array[Dictionary] = [
	{"input": "中国95式步枪", "id": "qbz_95", "layout": "bullpup", "feed": "behind_grip", "automatic": true},
	{"input": "M4A1", "id": "m4a1", "layout": "conventional_rifle", "feed": "ahead_of_grip", "automatic": true},
	{"input": "M16A2", "id": "m16a2", "layout": "conventional_rifle", "feed": "ahead_of_grip", "automatic": false, "burst": 3},
	{"input": "81杠", "id": "type_81", "layout": "conventional_rifle", "feed": "ahead_of_grip", "automatic": true},
	{"input": "92式手枪", "id": "qsz_92", "layout": "pistol", "feed": "in_grip", "automatic": false},
]

var passed := 0
var failed := 0


func _initialize() -> void:
	print("Forge ranged identity and mechanism tests")
	_run("Five firearm names and common aliases resolve without a player behavior question", _test_alias_resolution)
	_run("Model-only input receives an AI-owned ranged declaration", _test_model_only_interpretation)
	_run("All ranged axes validate and compile to distinct runtime matrices", _test_axis_compilation)
	_run("V3 single-variable finite differences expose every mechanism axis", _test_v3_finite_difference_audit)
	_run("Five 96px silhouettes remain structurally distinct", _test_distinct_pixel_silhouettes)
	_run("Independent structural axes own visible pixels", _test_structural_axis_pixel_differences)
	_run("Scaffold anchors come from the declared firearm structure", _test_scaffold_anchor_contract)
	_run("Five exact-model visual identity cards are automatic and cannot own mechanics", _test_visual_identity_cards)
	_run("Finished AI pixel sprites pass while Godot scaffolds cannot masquerade as art", _test_finished_pixel_identity_gate)
	_run("Provider promotes only gated firearm pixels to finished player-facing art", _test_finished_pixel_provider_handoff)
	_run("FAL candidate is normalized then promoted only after the same automatic firearm gate", _test_fal_finished_pixel_provider_handoff)
	_run("FAL candidate is rejected when AI sees a confusable firearm identity", _test_fal_ai_visual_rejection)
	_run("Empty pixelizer output falls back to AI identity art and still must pass the firearm gate", _test_fal_pixelizer_fallback)
	_run("Versioned visual cache normalizes aliases and changes with the identity card", _test_visual_cache_key)
	_run("Default Forge flow refuses to present a Godot firearm scaffold as finished art", _test_mock_flow_integration)
	_run("Semi-auto, three-round burst, automatic fire, recoil and reload follow compiled axes", _test_runtime_mechanisms)
	_run("V3 impact, penetration, recovery and muzzle climb reach runtime", _test_v3_runtime_causality)
	_run("Runtime contains no firearm-model name branches", _test_no_model_name_runtime_branches)
	print("RANGED WEAPON RESULT: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _run(test_name: String, callable: Callable) -> void:
	var result: Variant = callable.call()
	if result is bool and bool(result):
		passed += 1
		print("PASS | %s" % test_name)
	else:
		failed += 1
		printerr("FAIL | %s | %s" % [test_name, str(result)])


func _test_alias_resolution() -> Variant:
	var aliases := {
		"QBZ95": "qbz_95",
		"M4-A1": "m4a1",
		"M16-A2": "m16a2",
		"81式自动步枪": "type_81",
		"QSZ-92": "qsz_92",
	}
	for alias: String in aliases:
		var resolved: Dictionary = CATALOG.resolve_identity(alias)
		if not bool(resolved.get("ok", false)) or str(resolved.get("id", "")) != str(aliases[alias]):
			return "alias failed: %s -> %s" % [alias, str(resolved)]
		if bool(resolved.get("player_confirmation_required", false)):
			return "alias routed mechanism choice to player: %s" % alias
	return true


func _test_model_only_interpretation() -> Variant:
	var interpreter: WeaponInterpreter = INTERPRETER.new()
	for test_case: Dictionary in REQUIRED_CASES:
		var input_text := str(test_case["input"])
		var result: Dictionary = interpreter.interpret(input_text, PackedByteArray(), {})
		if not bool(result.get("ok", false)) or bool(result.get("needs_clarification", true)):
			return "model-only input did not compile: %s" % input_text
		if not bool(result.get("ai_interpretation_used", false)) or not bool(result.get("identity_semantics_understood", false)):
			return "AI identity ownership missing: %s" % input_text
		if bool(result.get("player_confirmation_required", false)) or result.has("question"):
			return "mechanism question leaked to player: %s" % input_text
		var blueprint := result.get("blueprint") as WeaponBlueprint
		if blueprint == null or blueprint.player_identity_text != input_text or blueprint.source_identity != input_text:
			return "player identity was not preserved: %s" % input_text
		if blueprint.behavior_family != "sustained_ranged" or str(blueprint.affordance.get("weapon_domain", "")) != "handheld_firearm":
			return "wrong ranged family: %s" % input_text
		if str(blueprint.modifiers.get("firearm_identity_id", "")) != str(test_case["id"]):
			return "wrong canonical profile: %s" % input_text
		if str(blueprint.affordance.get("layout", "")) != str(test_case["layout"]):
			return "wrong structure layout: %s" % input_text
		if not blueprint.visual_prompt.contains("do not collapse the firearm into one long bar"):
			return "firearm structure brief missing from prompt: %s" % input_text
	return true


func _test_axis_compilation() -> Variant:
	var signatures := {}
	var runtime_matrices := {}
	for profile: Dictionary in CATALOG.all_profiles():
		var declaration := profile.get("declaration", {}) as Dictionary
		var source := str(declaration.get("source", ""))
		var validation: Dictionary = AXES.validate_ai_declaration(declaration, source)
		if not bool(validation.get("ok", false)):
			return "axis declaration invalid: %s" % str(validation)
		var runtime: Dictionary = AXES.compile(declaration, source)
		if not bool(runtime.get("ok", false)):
			return "axis compile failed: %s" % str(runtime)
		if str(runtime.get("schema", "")) != AXES.RUNTIME_SCHEMA:
			return "runtime did not upgrade to V3: %s" % str(runtime.get("schema", ""))
		var final_parameters := runtime.get("final_parameters", {}) as Dictionary
		if final_parameters.size() != AXES.AUDITED_PARAMETERS.size():
			return "final clamped matrix is incomplete: %s" % str(final_parameters)
		var signature := str(runtime.get("axis_signature", ""))
		if signature.is_empty() or signatures.has(signature):
			return "runtime signature missing or duplicated: %s" % str(profile.get("id", ""))
		signatures[signature] = true
		runtime_matrices[str(profile.get("id", ""))] = [
			bool(runtime.get("automatic_fire", false)),
			int(runtime.get("burst_size", 0)),
			float(runtime.get("shot_interval_seconds", 0.0)),
			float(runtime.get("recoil_pixels", 0.0)),
			float(runtime.get("spread_velocity", 0.0)),
			int(runtime.get("magazine_size", 0)),
			float(runtime.get("reload_seconds", 0.0)),
		]
	if runtime_matrices.size() != REQUIRED_CASES.size():
		return "not every acceptance model compiled"
	if not bool((runtime_matrices["m4a1"] as Array)[0]) or bool((runtime_matrices["qsz_92"] as Array)[0]):
		return "fire-control axis did not own automatic/semi behavior"
	if int((runtime_matrices["m16a2"] as Array)[1]) != 3 or bool((runtime_matrices["m16a2"] as Array)[0]):
		return "three-round burst collapsed into semi-auto or unrestricted automatic fire"
	if float((runtime_matrices["type_81"] as Array)[3]) <= float((runtime_matrices["m4a1"] as Array)[3]):
		return "recoil axis direction collapsed"
	return true


func _test_v3_finite_difference_audit() -> Variant:
	for profile: Dictionary in CATALOG.all_profiles():
		var declaration := profile.get("declaration", {}) as Dictionary
		var audit: Dictionary = AXES.finite_difference_audit(
			declaration,
			str(declaration.get("source", ""))
		)
		if not bool(audit.get("ok", false)) or not bool(audit.get("passed", false)):
			return "finite-difference audit failed for %s: %s" % [
				str(profile.get("id", "")),
				str(audit),
			]
		if (audit.get("axis_cases", {}) as Dictionary).size() != AXES.MECHANISM_AXES.size():
			return "not every V3 mechanism axis was varied: %s" % str(profile.get("id", ""))
		if (audit.get("baseline_final_parameters", {}) as Dictionary).size() != AXES.AUDITED_PARAMETERS.size():
			return "audit omitted final clamp parameters: %s" % str(profile.get("id", ""))
		for issue_key: String in [
			"zero_effect_axes", "duplicate_direction_groups", "covered_effects",
			"uncovered_parameters", "owner_mismatches",
		]:
			if not (audit.get(issue_key, []) as Array).is_empty():
				return "%s reported %s: %s" % [str(profile.get("id", "")), issue_key, str(audit.get(issue_key))]
	return true


func _test_distinct_pixel_silhouettes() -> Variant:
	var images := {}
	var contracts := {}
	for profile: Dictionary in CATALOG.all_profiles():
		var declaration := profile.get("declaration", {}) as Dictionary
		var built: Dictionary = PIXEL_SCAFFOLD.build(declaration, str(declaration.get("source", "")))
		var image := built.get("image") as Image
		if not bool(built.get("ok", false)) or image == null or image.get_size() != Vector2i(96, 96):
			return "pixel build failed: %s" % str(profile.get("id", ""))
		var profile_id := str(profile.get("id", ""))
		images[profile_id] = image
		contracts[profile_id] = built.get("contract", {})
	var ids: Array = images.keys()
	for left_index: int in range(ids.size()):
		for right_index: int in range(left_index + 1, ids.size()):
			var difference := _alpha_difference(images[ids[left_index]] as Image, images[ids[right_index]] as Image)
			if difference < 45:
				return "silhouettes collapsed: %s/%s diff=%d" % [ids[left_index], ids[right_index], difference]
	var qbz_anchors := (contracts["qbz_95"] as Dictionary).get("anchors", {}) as Dictionary
	var m4_anchors := (contracts["m4a1"] as Dictionary).get("anchors", {}) as Dictionary
	var pistol_anchors := (contracts["qsz_92"] as Dictionary).get("anchors", {}) as Dictionary
	if float((qbz_anchors["FeedCenter"] as Array)[0]) >= float((qbz_anchors["GripPrimary"] as Array)[0]):
		return "bullpup feed is not visibly behind grip"
	if float((m4_anchors["FeedCenter"] as Array)[0]) <= float((m4_anchors["GripPrimary"] as Array)[0]):
		return "conventional feed is not visibly ahead of grip"
	if absf(float((pistol_anchors["FeedCenter"] as Array)[0]) - float((pistol_anchors["GripPrimary"] as Array)[0])) > 1.0:
		return "pistol feed is not housed in grip"
	return true


func _test_structural_axis_pixel_differences() -> Variant:
	var profile: Dictionary = CATALOG.resolve_identity("M4A1")
	var baseline := (profile.get("declaration", {}) as Dictionary).duplicate(true)
	var baseline_result: Dictionary = PIXEL_SCAFFOLD.build(baseline, str(baseline.get("source", "")))
	var baseline_image := baseline_result.get("image") as Image
	if baseline_image == null:
		return "baseline image missing"
	var alternatives := {
		"stock_structure": "fixed",
		"magazine_shape": "curved",
		"barrel_length": "long",
		"upper_profile": "raised_gas_tube",
	}
	for axis: String in alternatives:
		var changed := baseline.duplicate(true)
		changed[axis] = alternatives[axis]
		var changed_result: Dictionary = PIXEL_SCAFFOLD.build(changed, str(changed.get("source", "")))
		var changed_image := changed_result.get("image") as Image
		if not bool(changed_result.get("ok", false)) or changed_image == null:
			return "single-axis build failed: %s" % axis
		var difference := _rgba_difference(baseline_image, changed_image)
		if difference < 12:
			return "structural axis has weak/zero visible effect: %s diff=%d" % [axis, difference]
	return true


func _test_scaffold_anchor_contract() -> Variant:
	var interpreter: WeaponInterpreter = INTERPRETER.new()
	for test_case: Dictionary in REQUIRED_CASES:
		var result: Dictionary = interpreter.interpret(str(test_case["input"]), PackedByteArray(), {})
		var blueprint := result.get("blueprint") as WeaponBlueprint
		var fallback: Dictionary = SCAFFOLD_PIPELINE.fallback(blueprint)
		var asset := fallback.get("asset") as WeaponVisualAsset
		if not bool(fallback.get("ok", false)) or asset == null:
			return "fallback failed: %s" % str(test_case["input"])
		if asset.anchor_source != "ai_ranged_structure_contract" or asset.anchor_confidence != 1.0:
			return "declared anchors lost authority: %s" % str(test_case["input"])
		if asset.muzzle.x <= asset.grip_primary.x or asset.source_image.get_pixelv(Vector2i(asset.grip_primary.round())).a <= 0.1:
			return "grip/muzzle geometry invalid: %s" % str(test_case["input"])
	return true


func _test_finished_pixel_identity_gate() -> Variant:
	var interpreter: WeaponInterpreter = INTERPRETER.new()
	var cases := [
		{"identity": "92式手枪", "sprite": "res://tests/fixtures/firearm_visual_v2/glock17.png"},
		{"identity": "M4A1", "sprite": "res://tests/fixtures/firearm_visual_v2/m4a1_gpt_image.png"},
	]
	for test_case: Dictionary in cases:
		var interpretation: Dictionary = interpreter.interpret(str(test_case["identity"]), PackedByteArray(), {})
		var blueprint := interpretation.get("blueprint") as WeaponBlueprint
		var prepared: Dictionary = SCAFFOLD_PIPELINE.prepare(blueprint)
		var sprite := Image.load_from_file(str(test_case["sprite"]))
		var accepted: Dictionary = VISUAL_IDENTITY_GATE.evaluate(
			sprite,
			blueprint,
			prepared.get("contract", {}) as Dictionary,
			prepared.get("visual_structure_brief", {}) as Dictionary
		)
		if not bool(accepted.get("ok", false)) or bool(accepted.get("player_confirmation_required", true)):
			return "finished sprite rejected: %s -> %s" % [str(test_case["identity"]), str(accepted)]
		var scaffold := prepared.get("scaffold_image") as Image
		var rejected: Dictionary = VISUAL_IDENTITY_GATE.evaluate(
			scaffold,
			blueprint,
			prepared.get("contract", {}) as Dictionary,
			prepared.get("visual_structure_brief", {}) as Dictionary
		)
		if bool(rejected.get("ok", false)) or str(rejected.get("error", "")) != "FIREARM_VISUAL_SCAFFOLD_IS_NOT_FINISHED_ART":
			return "scaffold was allowed to masquerade as finished art: %s" % str(rejected)
	var m4_interpretation: Dictionary = interpreter.interpret("M4A1", PackedByteArray(), {})
	var m4_blueprint := m4_interpretation.get("blueprint") as WeaponBlueprint
	var m4_prepared: Dictionary = SCAFFOLD_PIPELINE.prepare(m4_blueprint)
	var confused_m16 := Image.load_from_file(
		"res://tests/fixtures/firearm_visual_v2/m4a1_wrong_fixed_carry_handle.png"
	)
	var identity_conflict: Dictionary = VISUAL_IDENTITY_GATE.evaluate(
		confused_m16,
		m4_blueprint,
		m4_prepared.get("contract", {}) as Dictionary,
		m4_prepared.get("visual_structure_brief", {}) as Dictionary
	)
	if (
		bool(identity_conflict.get("ok", false))
		or str(identity_conflict.get("error", "")) != "FIREARM_VISUAL_TOP_RAIL_HAS_CARRY_HANDLE_LOOP"
	):
		return "M16-style fixed-stock/carry-handle confusion was not rejected: %s" % str(identity_conflict)
	return true


func _test_visual_identity_cards() -> Variant:
	var interpreter: WeaponInterpreter = INTERPRETER.new()
	var signatures := {}
	for test_case: Dictionary in REQUIRED_CASES:
		var blueprint := (
			interpreter.interpret(str(test_case["input"]), PackedByteArray(), {}).get("blueprint")
			as WeaponBlueprint
		)
		var card: Dictionary = VISUAL_IDENTITY_CARD.compile(blueprint)
		if not bool(card.get("ok", false)) or bool(card.get("mechanics_authority", true)):
			return "visual identity card invalid or owns mechanics: %s" % str(card)
		if bool(card.get("player_confirmation_required", true)):
			return "visual identity card asked the player: %s" % str(test_case["input"])
		if (card.get("required_landmarks", []) as Array).size() < 4:
			return "exact-model landmarks missing: %s" % str(test_case["input"])
		var signature := JSON.stringify(card.get("visual_axes", {}))
		if signatures.has(signature):
			return "visual-only axes collapsed: %s" % str(test_case["input"])
		signatures[signature] = true
	return true


func _test_finished_pixel_provider_handoff() -> Variant:
	var interpreter: WeaponInterpreter = INTERPRETER.new()
	var interpretation: Dictionary = interpreter.interpret("M4A1", PackedByteArray(), {})
	var blueprint := interpretation.get("blueprint") as WeaponBlueprint
	var directory := "user://playlab/tests/firearm_finished_art_%d" % Time.get_ticks_usec()
	var absolute_directory := ProjectSettings.globalize_path(directory)
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		return "test output directory failed"
	var source := FileAccess.open("res://tests/fixtures/firearm_visual_v2/m4a1_gpt_image.png", FileAccess.READ)
	var target := FileAccess.open(directory.path_join("processed_sprite.png"), FileAccess.WRITE)
	if source == null or target == null:
		return "fixture copy failed"
	target.store_buffer(source.get_buffer(source.get_length()))
	source.close()
	target.close()
	var manifest_file := FileAccess.open(directory.path_join("manifest.json"), FileAccess.WRITE)
	if manifest_file == null:
		return "manifest write failed"
	manifest_file.store_string(JSON.stringify({
		"status": "success",
		"generation_prompt": blueprint.visual_prompt,
		"positive_prompt": blueprint.visual_prompt,
	}, "  "))
	manifest_file.close()
	var provider = LOCAL_VISUAL_PROVIDER.new()
	var loaded: Dictionary = provider.load_atomic_result(directory, blueprint)
	var asset := loaded.get("asset") as WeaponVisualAsset
	if (
		str(loaded.get("status", "")) != "success"
		or asset == null
		or asset.anchor_source != "firearm_ai_finished_art_gate_v1"
		or str((loaded.get("manifest", {}) as Dictionary).get("visual_mode", "")) != "firearm_ai_finished_pixel_art"
		or not bool((loaded.get("manifest", {}) as Dictionary).get("firearm_visual_gate_passed", false))
	):
		return "provider did not promote gated finished art: %s" % str(loaded)
	return true


func _test_fal_finished_pixel_provider_handoff() -> Variant:
	var interpreter: WeaponInterpreter = INTERPRETER.new()
	var interpretation: Dictionary = interpreter.interpret("M4A1", PackedByteArray(), {})
	var blueprint := interpretation.get("blueprint") as WeaponBlueprint
	var directory := "user://playlab/tests/fal_firearm_finished_art_%d" % Time.get_ticks_usec()
	var absolute_directory := ProjectSettings.globalize_path(directory)
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		return "FAL test output directory failed"
	var source := FileAccess.open("res://tests/fixtures/firearm_visual_v2/m4a1_gpt_image.png", FileAccess.READ)
	var target := FileAccess.open(directory.path_join("raw_pixel_art.png"), FileAccess.WRITE)
	if source == null or target == null:
		return "FAL fixture copy failed"
	target.store_buffer(source.get_buffer(source.get_length()))
	source.close()
	target.close()
	var manifest_file := FileAccess.open(directory.path_join("manifest.json"), FileAccess.WRITE)
	if manifest_file == null:
		return "FAL manifest write failed"
	manifest_file.store_string(JSON.stringify({
		"schema": "forge-fal-firearm-visual-manifest-v1",
		"status": "success",
		"provider": "FAL_FIREARM",
		"visual_mode": "fal_ai_pixel_candidate",
		"finished_art": false,
		"presentable_to_player": false,
		"generation_prompt": "exact M4A1 finished side profile pixel sprite",
		"positive_prompt": "exact M4A1 finished side profile pixel sprite",
		"models": {
			"identity_renderer": "fal-ai/gpt-image-1.5",
			"pixelizer": "fal-ai/image2pixel",
		},
		"ai_visual_identity_verification": _accepted_visual_verification("M4A1"),
	}, "  "))
	manifest_file.close()
	var provider = FAL_VISUAL_PROVIDER.new()
	var loaded: Dictionary = provider.load_atomic_result(directory, blueprint)
	var asset := loaded.get("asset") as WeaponVisualAsset
	var manifest := loaded.get("manifest", {}) as Dictionary
	if (
		str(loaded.get("status", "")) != "success"
		or str(loaded.get("provider", "")) != "FAL_FIREARM"
		or asset == null
		or asset.anchor_source != "firearm_ai_finished_art_gate_v1"
		or str(manifest.get("visual_mode", "")) != "firearm_ai_finished_pixel_art"
		or not bool(manifest.get("finished_art", false))
		or not bool(manifest.get("presentable_to_player", false))
		or not bool(manifest.get("firearm_visual_gate_passed", false))
	):
		return "FAL provider did not gate and promote candidate: %s" % str(loaded)
	return true


func _test_fal_ai_visual_rejection() -> Variant:
	var interpreter: WeaponInterpreter = INTERPRETER.new()
	var blueprint := (
		interpreter.interpret("M4A1", PackedByteArray(), {}).get("blueprint") as WeaponBlueprint
	)
	var directory := "user://playlab/tests/fal_firearm_ai_rejection_%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) != OK:
		return "FAL AI rejection directory failed"
	var source := FileAccess.open("res://tests/fixtures/firearm_visual_v2/m4a1_gpt_image.png", FileAccess.READ)
	var target := FileAccess.open(directory.path_join("raw_pixel_art.png"), FileAccess.WRITE)
	if source == null or target == null:
		return "FAL AI rejection fixture copy failed"
	target.store_buffer(source.get_buffer(source.get_length()))
	source.close()
	target.close()
	var rejected_verification := _accepted_visual_verification("M4A1")
	rejected_verification["passed"] = false
	rejected_verification["failure_reasons"] = ["confusable_identity_contradiction"]
	rejected_verification["verdict"] = {
		"required_landmarks_missing": ["compact collapsible polymer stock"],
		"contradictions": ["full fixed M16 stock"],
		"closest_confusable_identity": "M16A2",
	}
	var manifest_file := FileAccess.open(directory.path_join("manifest.json"), FileAccess.WRITE)
	if manifest_file == null:
		return "FAL AI rejection manifest failed"
	manifest_file.store_string(JSON.stringify({
		"schema": "forge-fal-firearm-visual-manifest-v1",
		"status": "success",
		"provider": "FAL_FIREARM",
		"ai_visual_identity_verification": rejected_verification,
	}, "  "))
	manifest_file.close()
	var loaded: Dictionary = FAL_VISUAL_PROVIDER.new().load_atomic_result(directory, blueprint)
	if (
		str(loaded.get("status", "")) != "failed"
		or str(loaded.get("failure_reason", "")) != "FIREARM_VISUAL_AI_IDENTITY_REJECTED"
		or not str(loaded.get("retry_prompt", "")).contains("M16A2")
	):
		return "AI confusable-identity verdict did not stop promotion: %s" % str(loaded)
	return true


func _test_fal_pixelizer_fallback() -> Variant:
	var interpreter: WeaponInterpreter = INTERPRETER.new()
	var blueprint := (interpreter.interpret("M4A1", PackedByteArray(), {}).get("blueprint") as WeaponBlueprint)
	var directory := "user://playlab/tests/fal_firearm_pixelizer_fallback_%d" % Time.get_ticks_usec()
	var absolute_directory := ProjectSettings.globalize_path(directory)
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		return "FAL fallback directory failed"
	var source := FileAccess.open("res://tests/fixtures/firearm_visual_v2/m4a1_gpt_image.png", FileAccess.READ)
	var raw_target := FileAccess.open(directory.path_join("ai_raw.png"), FileAccess.WRITE)
	if source == null or raw_target == null:
		return "FAL fallback identity-art fixture copy failed"
	raw_target.store_buffer(source.get_buffer(source.get_length()))
	source.close()
	raw_target.close()
	var blank := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	blank.fill(Color(0.0, 0.0, 0.0, 0.0))
	if blank.save_png(directory.path_join("raw_pixel_art.png")) != OK:
		return "FAL blank pixelizer fixture write failed"
	var manifest_file := FileAccess.open(directory.path_join("manifest.json"), FileAccess.WRITE)
	if manifest_file == null:
		return "FAL fallback manifest write failed"
	manifest_file.store_string(JSON.stringify({
		"schema": "forge-fal-firearm-visual-manifest-v1",
		"status": "success",
		"provider": "FAL_FIREARM",
		"visual_mode": "fal_ai_pixel_candidate",
		"finished_art": false,
		"presentable_to_player": false,
		"generation_prompt": "exact M4A1 finished side profile pixel sprite",
		"positive_prompt": "exact M4A1 finished side profile pixel sprite",
		"ai_visual_identity_verification": _accepted_visual_verification("M4A1"),
	}, "  "))
	manifest_file.close()
	var loaded: Dictionary = FAL_VISUAL_PROVIDER.new().load_atomic_result(directory, blueprint)
	var manifest := loaded.get("manifest", {}) as Dictionary
	if (
		str(loaded.get("status", "")) != "success"
		or str(manifest.get("candidate_source", "")) != "fal_transparent_identity_art_local_pixel_fallback"
		or not bool(manifest.get("firearm_visual_gate_passed", false))
	):
		return "FAL identity-art fallback did not remain fail-closed: %s" % str(loaded)
	return true


func _test_visual_cache_key() -> Variant:
	var interpreter: WeaponInterpreter = INTERPRETER.new()
	var first := interpreter.interpret("M4A1", PackedByteArray(), {}).get("blueprint") as WeaponBlueprint
	var alias := interpreter.interpret("M4-A1", PackedByteArray(), {}).get("blueprint") as WeaponBlueprint
	var provider = FAL_VISUAL_PROVIDER.new()
	var first_preparation: Dictionary = SCAFFOLD_PIPELINE.prepare(first)
	var alias_preparation: Dictionary = SCAFFOLD_PIPELINE.prepare(alias)
	var first_payload: Dictionary = provider._build_request_payload(first, first_preparation)
	var alias_payload: Dictionary = provider._build_request_payload(alias, alias_preparation)
	var first_key: String = provider._cache_key(first_payload)
	var alias_key: String = provider._cache_key(alias_payload)
	if first_key.is_empty() or first_key != alias_key:
		return "normalized aliases did not share a visual cache key"
	if not str(first_payload.get("identity_reference_id", "")).is_empty():
		return "M4A1 unexpectedly received a curated Type 81 reference"
	var changed := first_payload.duplicate(true)
	var changed_card := changed.get("identity_card", {}) as Dictionary
	var changed_axes := changed_card.get("visual_axes", {}) as Dictionary
	changed_axes["stock_profile"] = "fixed_solid_stock"
	changed_card["visual_axes"] = changed_axes
	changed["identity_card"] = changed_card
	if provider._cache_key(changed) == first_key:
		return "identity-card change did not invalidate visual cache key"
	var type_81 := interpreter.interpret("81杠", PackedByteArray(), {}).get("blueprint") as WeaponBlueprint
	var type_81_payload: Dictionary = provider._build_request_payload(
		type_81,
		SCAFFOLD_PIPELINE.prepare(type_81)
	)
	if str(type_81_payload.get("identity_reference_id", "")) != "type_81_museum_cc_by_sa_v1":
		return "Type 81 did not receive its system-curated identity reference"
	var without_reference := type_81_payload.duplicate(true)
	without_reference["identity_reference_id"] = ""
	if provider._cache_key(without_reference) == provider._cache_key(type_81_payload):
		return "identity-reference change did not invalidate the Type 81 cache key"
	return true


func _test_mock_flow_integration() -> Variant:
	var interpreter: WeaponInterpreter = INTERPRETER.new()
	var result: Dictionary = interpreter.interpret("M4A1", PackedByteArray(), {})
	var flow := OPEN_FLOW.new()
	flow._ready()
	flow._handle_interpretation_result(result)
	var ok := (
		flow.state == "error"
		and flow.current_asset == null
		and str(flow.current_manifest.get("visual_mode", "")) == "firearm_scaffold_diagnostic"
		and not bool(flow.current_manifest.get("presentable_to_player", true))
		and flow._requires_ranged_mechanism_profile()
		and not flow._ranged_mechanism_is_ready()
	)
	var failure := "" if ok else "state=%s asset=%s manifest=%s ranged_ready=%s" % [
		flow.state,
		str(flow.current_asset != null),
		str(flow.current_manifest),
		str(flow._ranged_mechanism_is_ready()),
	]
	flow.free()
	return true if ok else failure


func _test_runtime_mechanisms() -> Variant:
	var pistol_bundle: Dictionary = _runtime_bundle("92式手枪")
	var pistol := pistol_bundle.get("arena") as GameplayArena
	if pistol == null:
		return "pistol arena missing"
	pistol._update_sustained_attack(true, true, 0.016)
	if pistol.projectiles.size() != 1:
		return "semi-auto did not fire exactly once on press"
	pistol.shot_cooldown = 0.0
	pistol._update_sustained_attack(true, false, 0.016)
	if pistol.projectiles.size() != 1:
		return "semi-auto repeated while held"
	var rifle_bundle: Dictionary = _runtime_bundle("M4A1")
	var rifle := rifle_bundle.get("arena") as GameplayArena
	if rifle == null:
		return "rifle arena missing"
	rifle._update_sustained_attack(true, true, 0.016)
	rifle.shot_cooldown = 0.0
	rifle._update_sustained_attack(true, false, 0.016)
	if rifle.projectiles.size() != 2:
		return "automatic fire did not repeat while held"
	var burst_bundle: Dictionary = _runtime_bundle("M16A2")
	var burst := burst_bundle.get("arena") as GameplayArena
	if burst == null:
		return "three-round-burst arena missing"
	burst._update_sustained_attack(true, true, 0.016)
	burst.shot_cooldown = 0.0
	burst._update_sustained_attack(false, false, 0.016)
	burst.shot_cooldown = 0.0
	burst._update_sustained_attack(false, false, 0.016)
	if burst.projectiles.size() != 3 or burst.burst_shots_remaining != 0:
		return "one trigger press did not complete exactly three shots after release"
	burst.shot_cooldown = 0.0
	burst._update_sustained_attack(false, false, 0.016)
	if burst.projectiles.size() != 3:
		return "three-round burst continued into unrestricted automatic fire"
	var m4_recoil := rifle.weapon_recoil_offset
	var heavy_bundle: Dictionary = _runtime_bundle("81杠")
	var heavy := heavy_bundle.get("arena") as GameplayArena
	heavy._update_sustained_attack(true, true, 0.016)
	if heavy.weapon_recoil_offset <= m4_recoil:
		return "strong recoil axis did not move the weapon farther"
	heavy.ammo_in_magazine = 1
	heavy.shot_cooldown = 0.0
	heavy._update_sustained_attack(true, true, 0.016)
	if heavy.reload_timer <= 0.0 or heavy.ammo_in_magazine != 0:
		return "empty magazine did not start reload"
	heavy._update_firearm_timers(heavy.reload_timer + 0.01)
	if heavy.ammo_in_magazine != int(heavy.ranged_runtime_profile.get("magazine_size", 0)):
		return "reload did not refill compiled magazine"
	pistol.free()
	rifle.free()
	burst.free()
	heavy.free()
	return true


func _test_v3_runtime_causality() -> Variant:
	var pistol_bundle: Dictionary = _runtime_bundle("92式手枪")
	var pistol := pistol_bundle.get("arena") as GameplayArena
	var m4_bundle: Dictionary = _runtime_bundle("M4A1")
	var m4 := m4_bundle.get("arena") as GameplayArena
	var type81_bundle: Dictionary = _runtime_bundle("81杠")
	var type81 := type81_bundle.get("arena") as GameplayArena
	if pistol == null or m4 == null or type81 == null:
		return "V3 runtime arenas are incomplete"
	for arena: GameplayArena in [pistol, m4, type81]:
		arena._update_sustained_attack(true, true, 0.016)
		if arena.projectiles.size() != 1 or arena.weapon_muzzle_climb_degrees <= 0.0:
			return "V3 shot did not create a projectile and muzzle climb"
		var projectile := arena.projectiles[0] as Dictionary
		if not projectile.has("damage") or not projectile.has("armor_damage_multiplier"):
			return "V3 impact or penetration payload did not reach the projectile"
	var m4_kick_before := m4.weapon_recoil_offset
	var m4_climb_before := m4.weapon_muzzle_climb_degrees
	m4._update_firearm_timers(0.05)
	if m4.weapon_recoil_offset >= m4_kick_before or m4.weapon_muzzle_climb_degrees >= m4_climb_before:
		return "recoil recovery axis did not return weapon translation and rotation"
	var pistol_projectile := pistol.projectiles[0] as Dictionary
	var type81_projectile := type81.projectiles[0] as Dictionary
	if int(pistol_projectile.get("pierces", -1)) >= int(type81_projectile.get("pierces", -1)):
		return "penetration axis did not change target pierce budget"
	var guard := {
		"id": 99, "type": "guard", "pos": Vector2(320, 420), "hp": 100.0,
		"max_hp": 100.0, "facing": -1.0, "hurt": 0.0,
	}
	var pistol_guard_damage := pistol._projectile_damage_against(pistol_projectile, guard)
	var type81_guard_damage := type81._projectile_damage_against(type81_projectile, guard)
	if type81_guard_damage <= pistol_guard_damage:
		return "impact and penetration axes collapsed against front armor"
	pistol_projectile["distance_travelled"] = 700.0
	var pistol_near_damage := float(pistol.ranged_runtime_profile.get("projectile_damage", 0.0))
	var pistol_far_damage := pistol._projectile_damage_against(
		pistol_projectile,
		{"id": 100, "type": "target", "pos": Vector2(950, 420), "hp": 100.0, "facing": -1.0}
	)
	if pistol_far_damage >= pistol_near_damage:
		return "effective-range falloff did not reduce distant damage"
	pistol.free()
	m4.free()
	type81.free()
	return true


func _test_no_model_name_runtime_branches() -> Variant:
	var runtime_sources := "\n".join([
		FileAccess.get_file_as_string("res://scripts/systems/gameplay_arena.gd"),
		FileAccess.get_file_as_string("res://scripts/systems/open_identity_training_arena.gd"),
		FileAccess.get_file_as_string("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd"),
		FileAccess.get_file_as_string("res://scripts/combat_feel/firearm_pixel_scaffold.gd"),
	])
	for forbidden: String in ["qbz_95", "m4a1", "m16a2", "type_81", "qsz_92", "95式", "M16A2", "81杠", "92式"]:
		if runtime_sources.to_lower().contains(forbidden.to_lower()):
			return "model-name branch leaked into generic runtime: %s" % forbidden
	return true


func _runtime_bundle(identity: String) -> Dictionary:
	var interpreter: WeaponInterpreter = INTERPRETER.new()
	var result: Dictionary = interpreter.interpret(identity, PackedByteArray(), {})
	var blueprint := result.get("blueprint") as WeaponBlueprint
	var fallback: Dictionary = SCAFFOLD_PIPELINE.fallback(blueprint)
	var asset := fallback.get("asset") as WeaponVisualAsset
	if blueprint == null or asset == null:
		return {}
	var arena: GameplayArena = ARENA.new()
	arena.start_stage("training", blueprint, asset)
	return {"arena": arena, "blueprint": blueprint, "asset": asset}


func _alpha_difference(left: Image, right: Image) -> int:
	var difference := 0
	for y: int in range(left.get_height()):
		for x: int in range(left.get_width()):
			if (left.get_pixel(x, y).a > 0.1) != (right.get_pixel(x, y).a > 0.1):
				difference += 1
	return difference


func _rgba_difference(left: Image, right: Image) -> int:
	var difference := 0
	for y: int in range(left.get_height()):
		for x: int in range(left.get_width()):
			if left.get_pixel(x, y) != right.get_pixel(x, y):
				difference += 1
	return difference


func _accepted_visual_verification(identity: String) -> Dictionary:
	return {
		"schema": "forge-firearm-ai-visual-verification-v1",
		"ok": true,
		"passed": true,
		"automatic": true,
		"provider": "offline-test-fixture",
		"model_id": "offline-test-fixture",
		"failure_reasons": [],
		"verdict": {
			"exact_identity_match": true,
			"identity_readable_at_96px": true,
			"required_landmarks_present": [identity],
			"required_landmarks_missing": [],
			"contradictions": [],
			"closest_confusable_identity": "none",
			"confidence": 1.0,
			"summary": "Offline fixture accepted for provider handoff testing.",
		},
		"mechanics_authority": false,
		"player_confirmation_required": false,
	}
