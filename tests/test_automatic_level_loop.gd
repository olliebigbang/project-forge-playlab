extends SceneTree

const CATALOG := preload("res://scripts/enemy_attack/offline_enemy_blueprint_catalog.gd")
const DIRECTOR := preload("res://scripts/enemy_attack/automatic_encounter_director.gd")
const ARENA := preload("res://scripts/systems/gameplay_arena.gd")
const LOOP_SCENE := preload("res://scenes/automatic_level_loop.tscn")
const AutomaticLevelLoop := preload("res://scripts/enemy_attack/automatic_level_loop.gd")
const RANGED_AXIS_RESOLVER := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_check("Bundled enemies are offline AI responses revalidated by the mechanism compiler", _test_catalog_validation)
	_check("Automatic level exposes no player enemy-input or mechanic-confirmation path", _test_no_enemy_input)
	_check("Encounter sequence is reproducible across independent directors", _test_reproducible_order)
	_check("Weapon blueprint, visual asset, and final mechanism matrix survive the handoff", _test_weapon_handoff)
	_check("Public ranged handoff enters the level without rebuilding the weapon", _test_public_runtime_handoff)
	_check("Level weapon cards preserve bolt-action mechanism timing", _test_cycle_action_weapon_card)
	_check("A level encounter executes two distinct compiled attack deliveries", _test_two_compiled_deliveries_execute)
	_check("Three encounter completions produce the playable completed state", _test_completed_state)
	_check("Exhausted health produces a failed run state", _test_failed_state)
	print("AUTOMATIC_LEVEL_LOOP_TESTS passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _check(label: String, callable: Callable) -> void:
	var result: Variant = callable.call()
	if result is bool and bool(result):
		passed += 1
		print("PASS | %s" % label)
	else:
		failed += 1
		printerr("FAIL | %s | %s" % [label, str(result)])


func _test_catalog_validation() -> Variant:
	var catalog: Dictionary = CATALOG.load_validated()
	if not bool(catalog.get("ok", false)):
		return catalog
	var profiles := catalog.get("profiles_by_id", {}) as Dictionary
	var deliveries: Dictionary = {}
	for raw_profile: Variant in profiles.values():
		var profile := raw_profile as Dictionary
		if not bool(profile.get("offline_accepted_blueprint", false)):
			return profile
		if bool(profile.get("runtime_identity_inputs_used", true)):
			return profile
		if bool(profile.get("player_confirmation_required", true)):
			return profile
		var declarations := profile.get("attack_declarations", []) as Array
		if declarations.size() != 2:
			return profile
		for declaration: Dictionary in declarations:
			deliveries[str((declaration.get("axes", {}) as Dictionary).get("delivery", ""))] = true
	var ok := profiles.size() == 3 and (catalog.get("encounters", []) as Array).size() == 3
	ok = ok and deliveries.size() == 4
	ok = ok and not bool(catalog.get("online_api_required", true))
	return true if ok else {"profiles": profiles.keys(), "deliveries": deliveries.keys(), "catalog": catalog}


func _test_no_enemy_input() -> Variant:
	var paths: Array[String] = [
		"res://scripts/enemy_attack/automatic_encounter_director.gd",
		"res://scripts/enemy_attack/automatic_level_loop.gd",
	]
	for path: String in paths:
		var source := FileAccess.get_file_as_string(path).to_lower()
		for forbidden: String in [
			"lineedit", "concept_input", "request_blueprint", "enemy_ai_blueprint_provider",
			"ask_player", "confirm_mechanic", "choose_attack", "mechanical_spider",
			"ember_priest", "frost_siege_beast",
		]:
			if source.contains(forbidden):
				return "%s leaked %s" % [path, forbidden]
	var loop_source := FileAccess.get_file_as_string("res://scripts/enemy_attack/automatic_level_loop.gd")
	if not loop_source.contains("armory.load_entries()"):
		return "automatic level did not use the public armory interface"
	for private_cache_detail: String in ["visual_cache_root", "profile_cache_paths", "cache_v1"]:
		if loop_source.contains(private_cache_detail):
			return "automatic level leaked armory cache detail: %s" % private_cache_detail
	var catalog: Dictionary = CATALOG.load_validated()
	return true if (
		bool(catalog.get("ok", false))
		and not bool(catalog.get("player_enemy_input_required", true))
		and not bool(catalog.get("player_confirmation_required", true))
	) else catalog


func _test_reproducible_order() -> Variant:
	var first: RefCounted = DIRECTOR.new()
	var second: RefCounted = DIRECTOR.new()
	var first_config: Dictionary = first.configure()
	var second_config: Dictionary = second.configure()
	if not bool(first_config.get("ok", false)) or not bool(second_config.get("ok", false)):
		return {"first": first_config, "second": second_config}
	var first_ids: Array[String] = []
	var second_ids: Array[String] = []
	for encounter: Dictionary in first.catalog.get("encounters", []):
		first_ids.append(str(encounter.get("encounter_id", "")))
	for encounter: Dictionary in second.catalog.get("encounters", []):
		second_ids.append(str(encounter.get("encounter_id", "")))
	var ok := first_ids == second_ids and first_ids.size() == 3
	ok = ok and str(first_config.get("sequence_signature", "")) == str(second_config.get("sequence_signature", ""))
	return true if ok else {"first": first_ids, "second": second_ids, "first_config": first_config, "second_config": second_config}


func _test_weapon_handoff() -> Variant:
	var director: RefCounted = DIRECTOR.new()
	var configured: Dictionary = director.configure()
	if not bool(configured.get("ok", false)):
		return configured
	var entry: Dictionary = _weapon_entry()
	var started: Dictionary = director.begin_run(entry)
	if not bool(started.get("ok", false)):
		return started
	var handoff: Dictionary = director.weapon_handoff()
	var source_runtime := entry.get("ranged_runtime_profile", {}) as Dictionary
	var handed_runtime := handoff.get("ranged_runtime_profile", {}) as Dictionary
	var ok: bool = handoff.get("blueprint") == entry.get("blueprint")
	ok = ok and handoff.get("asset") == entry.get("asset")
	ok = ok and str(handed_runtime.get("axis_signature", "")) == str(source_runtime.get("axis_signature", ""))
	ok = ok and handed_runtime.get("final_parameters", {}) == source_runtime.get("final_parameters", {})
	return true if ok else {"started": started, "handoff": handoff}


func _test_two_compiled_deliveries_execute() -> Variant:
	var director: RefCounted = DIRECTOR.new()
	director.configure()
	var begun: Dictionary = director.begin_run(_weapon_entry())
	if not bool(begun.get("ok", false)):
		return begun
	var encounter: Dictionary = director.begin_next_encounter()
	if not bool(encounter.get("ok", false)):
		return encounter
	var profile := ((encounter.get("profiles", []) as Array)[0] as Dictionary).duplicate(true)
	var deliveries: Dictionary = {}
	for player_position: Vector2 in [Vector2(860, 350), Vector2(250, 420)]:
		var arena: GameplayArena = ARENA.new() as GameplayArena
		arena.stage_name = "automatic_mechanism_execution_test"
		arena.player_position = player_position
		arena._spawn_enemy_blueprint(profile, Vector2(900, 350))
		var enemy: Dictionary = arena.enemies[0]
		arena._update_enemies(0.01)
		var runtime: Variant = enemy.get("attack_runtime", null)
		if runtime == null or not bool(enemy.get("compiled_attacks_ready", false)) or not runtime.is_running():
			var diagnostics := enemy.duplicate(true)
			arena.free()
			return diagnostics
		deliveries[runtime.current_delivery()] = true
		arena.free()
	var ok := deliveries.has("contact") and deliveries.has("marked_impact")
	return true if ok else {"deliveries": deliveries.keys(), "encounter": encounter}


func _test_public_runtime_handoff() -> Variant:
	var entry: Dictionary = _weapon_entry()
	var handoff: Node = root.get_node_or_null("MechanismHandoff")
	if handoff == null:
		return "MECHANISM_HANDOFF_AUTOLOAD_MISSING"
	handoff.clear()
	var error := str(handoff.store_ranged(
		entry.get("blueprint") as WeaponBlueprint,
		entry.get("asset") as WeaponVisualAsset,
		entry.get("ranged_runtime_profile", {}) as Dictionary
	))
	if not error.is_empty():
		return error
	var loop := LOOP_SCENE.instantiate() as AutomaticLevelLoop
	root.add_child(loop)
	var handed: Dictionary = loop.director.weapon_handoff()
	var original_runtime := entry.get("ranged_runtime_profile", {}) as Dictionary
	var handed_runtime := handed.get("ranged_runtime_profile", {}) as Dictionary
	var ok := loop.state == "between_encounters"
	ok = ok and handed.get("blueprint") == entry.get("blueprint")
	ok = ok and handed.get("asset") == entry.get("asset")
	ok = ok and handed_runtime.get("final_parameters", {}) == original_runtime.get("final_parameters", {})
	var result: Variant = true if ok else {"state": loop.state, "handed": handed}
	loop.queue_free()
	return result


func _test_cycle_action_weapon_card() -> Variant:
	var loop := LOOP_SCENE.instantiate() as AutomaticLevelLoop
	var runtime := (_weapon_entry().get("ranged_runtime_profile", {}) as Dictionary).duplicate(true)
	runtime["cycle_action_code"] = 1
	runtime["cycle_required"] = true
	runtime["cycle_overhead_seconds"] = 0.54
	runtime["shot_interval_seconds"] = 0.28
	var mode := loop._fire_mode_label(runtime)
	var timing := loop._fire_timing_label(runtime)
	var ok := mode == "每发后自动拉栓" and timing == "总动作 0.82 秒"
	loop.free()
	return true if ok else {"mode": mode, "timing": timing}


func _test_completed_state() -> Variant:
	var loop := LOOP_SCENE.instantiate() as AutomaticLevelLoop
	root.add_child(loop)
	loop._begin_run(_weapon_entry())
	for index: int in range(3):
		loop._process(2.0)
		if loop.state != "combat":
			var diagnostics := {"index": index, "state": loop.state, "director": loop.director.snapshot()}
			loop.queue_free()
			return diagnostics
		loop._on_stage_completed(
			str(loop.current_encounter.get("stage_name", "")),
			{"defeated": 1, "elapsed_seconds": 1.0, "damage_taken": 0.0, "shots_fired": 2}
		)
	var final_state: Dictionary = loop.director.snapshot()
	var ok := loop.state == "completed" and str(final_state.get("state", "")) == "completed"
	ok = ok and int(final_state.get("completed_count", 0)) == 3
	var result: Variant = true if ok else {"loop_state": loop.state, "director": final_state}
	loop.queue_free()
	return result


func _test_failed_state() -> Variant:
	var loop := LOOP_SCENE.instantiate() as AutomaticLevelLoop
	root.add_child(loop)
	loop._begin_run(_weapon_entry())
	loop._process(1.0)
	if loop.state != "combat":
		var diagnostics := {"state": loop.state, "director": loop.director.snapshot()}
		loop.queue_free()
		return diagnostics
	loop.arena.player_health = 1.0
	loop.arena.metrics["damage_taken"] = loop.encounter_start_health
	loop._process(0.01)
	var ok := loop.state == "failed" and str((loop.director.snapshot() as Dictionary).get("state", "")) == "failed"
	var result: Variant = true if ok else {"loop_state": loop.state, "director": loop.director.snapshot()}
	loop.queue_free()
	return result


func _weapon_entry() -> Dictionary:
	var blueprint := WeaponBlueprint.fixed_blueprint("gatling")
	blueprint.display_name = "自动关卡测试步枪"
	blueprint.effect_type = "ballistic_projectile"
	blueprint.affordance = {
		"weapon_domain": "handheld_firearm", "firearm_family": "rifle", "layout": "conventional_rifle",
		"stock_structure": "fixed", "feed_position": "ahead_of_grip",
		"magazine_shape": "curved", "barrel_length": "medium", "upper_profile": "top_rail",
		"support_mode": "two_hand_shouldered", "fire_control": "select_fire_auto",
		"action_mechanism": "self_loading", "feed_system": "detachable_box",
		"shot_pattern": "single_projectile", "sustained_climb": "progressive",
		"cadence": "balanced", "recoil": "medium", "recoil_recovery": "balanced",
		"muzzle_climb": "medium", "accuracy": "controlled", "impact_force": "medium",
		"penetration": "medium", "reload": "standard", "effective_range": "long",
		"handling": "balanced", "magazine_capacity": "standard", "confidence": 0.99,
	}
	blueprint.affordance_source = "AUTOMATIC_LEVEL_TEST_AI_FIREARM_AXES"
	var runtime: Dictionary = RANGED_AXIS_RESOLVER.compile(blueprint.affordance, blueprint.affordance_source)
	blueprint.modifiers["ranged_runtime_profile"] = runtime.duplicate(true)
	var image := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color("4b6478"))
	var asset := WeaponVisualAsset.new()
	asset.source_image = image
	asset.texture = ImageTexture.create_from_image(image)
	asset.canvas_size = image.get_size()
	asset.grip_primary = Vector2(4, 5)
	asset.grip_secondary = Vector2(7, 5)
	asset.muzzle = Vector2(15, 3)
	asset.tip = asset.muzzle
	return {
		"blueprint": blueprint,
		"asset": asset,
		"ranged_runtime_profile": runtime,
		"display_name": blueprint.display_name,
	}
