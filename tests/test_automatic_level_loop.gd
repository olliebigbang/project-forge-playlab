extends SceneTree

const CATALOG := preload("res://scripts/enemy_attack/offline_enemy_blueprint_catalog.gd")
const DIRECTOR := preload("res://scripts/enemy_attack/automatic_encounter_director.gd")
const ARENA := preload("res://scripts/systems/gameplay_arena.gd")
const LOOP_SCENE := preload("res://scenes/automatic_level_loop.tscn")
const AutomaticLevelLoop := preload("res://scripts/enemy_attack/automatic_level_loop.gd")
const AUTOMATIC_ARMORY := preload("res://scripts/combat_feel/automatic_armory_director.gd")
const RANGED_AXIS_RESOLVER := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")
const ASSET_LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")
const ENEMY_VISUAL_ASSETS := preload("res://scripts/enemy_attack/enemy_visual_asset_library.gd")
const WEAPON_PLAYER_FIT := preload("res://scripts/combat_feel/weapon_player_fit_compiler.gd")
const WEAPON_STRATEGY := preload("res://scripts/combat_feel/weapon_strategy_compiler.gd")

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
	_check("A general soft object enters the same level with its AI mechanism profile intact", _test_general_mechanism_handoff)
	_check("Every accepted enemy blueprint resolves a formal sprite and the arena background", _test_formal_enemy_visual_assets)
	_check("Formal combat art obeys the hard-alpha and pixel-density contract", _test_pixel_art_render_contract)
	_check("Firearm render scale stays proportional to the formal player sprite", _test_player_firearm_render_proportions)
	_check("Every weapon is fitted to the player from structure rather than its name", _test_identity_free_player_fit)
	_check("Weapon capability profiles produce different three-battle tactics", _test_capability_driven_strategy)
	_check("Attacking keeps aim on the target while the player retreats", _test_retreating_attack_aim)
	_check("A close melee sweep still connects when an enemy crosses the facing axis", _test_close_melee_sweep)
	_check("Enemy pressure rises across the three battles without removing telegraphs", _test_enemy_pressure_curve)
	_check("General melee attacks apply their compiled control and armor interactions", _test_general_melee_target_interaction)
	_check("Level weapon cards preserve bolt-action mechanism timing", _test_cycle_action_weapon_card)
	_check("Mechanism coverage chooses one missing firearm role without player input", _test_automatic_armory_gap_plan)
	_check("A level encounter executes two distinct compiled attack deliveries", _test_two_compiled_deliveries_execute)
	_check("Three encounter completions produce the playable completed state", _test_completed_state)
	_check("A generated firearm is offered as an optional post-run reward", _test_generated_armory_reward)
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
		"res://scripts/combat_feel/automatic_armory_director.gd",
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
	if not loop_source.contains("automatic_armory.start(armory_entries"):
		return "automatic level did not start the mechanism-gap armory director"
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
	runtime["automatic_fire"] = false
	runtime["burst_size"] = 0
	runtime["cycle_action_code"] = 1
	runtime["cycle_required"] = true
	runtime["cycle_overhead_seconds"] = 0.54
	runtime["shot_interval_seconds"] = 0.28
	var mode := loop._fire_mode_label(runtime)
	var timing := loop._fire_timing_label(runtime)
	var ok := mode == "按一下单发" and timing == "每发后拉栓，总锁定 0.82 秒"
	loop.free()
	return true if ok else {"mode": mode, "timing": timing}


func _test_automatic_armory_gap_plan() -> Variant:
	var automatic_armory: RefCounted = AUTOMATIC_ARMORY.new()
	var service_only: Array[Dictionary] = [_weapon_entry()]
	var missing_close_quarters: Dictionary = automatic_armory.plan(service_only)
	if (
		not bool(missing_close_quarters.get("needs_generation", false))
		or str(missing_close_quarters.get("target_role", "")) != "close_quarters"
		or bool(missing_close_quarters.get("player_confirmation_required", true))
	):
		return missing_close_quarters
	var covered: Array[Dictionary] = [
		_role_entry("submachine_gun", "self_loading", "close"),
		_role_entry("precision_rifle", "bolt_action", "precision"),
		_role_entry("semi_auto_pistol", "self_loading", "sidearm"),
		_role_entry("shotgun", "pump_action", "scatter"),
		_role_entry("light_machine_gun", "self_loading", "support"),
		_role_entry("rifle", "self_loading", "service"),
	]
	var complete: Dictionary = automatic_armory.plan(covered)
	return true if (
		not bool(complete.get("needs_generation", true))
		and (complete.get("occupied_roles", {}) as Dictionary).size() == 6
	) else complete


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


func _test_general_mechanism_handoff() -> Variant:
	var entry := _mechanism_weapon_entry()
	if not bool(entry.get("ok", false)):
		return entry
	var handoff: Node = root.get_node_or_null("MechanismHandoff")
	if handoff == null:
		return "MECHANISM_HANDOFF_AUTOLOAD_MISSING"
	handoff.clear()
	var error := str(handoff.store(
		entry.get("blueprint") as WeaponBlueprint,
		entry.get("asset") as WeaponVisualAsset,
		entry.get("affordance_profile") as Resource
	))
	if not error.is_empty():
		return error
	var loop := LOOP_SCENE.instantiate() as AutomaticLevelLoop
	root.add_child(loop)
	var handed: Dictionary = loop.director.weapon_handoff()
	var source_profile := entry.get("affordance_profile") as Resource
	var handed_profile := handed.get("affordance_profile") as Resource
	var ok := loop.state == "between_encounters"
	ok = ok and str(handed.get("kind", "")) == "mechanism_weapon"
	ok = ok and handed.get("blueprint") == entry.get("blueprint")
	ok = ok and handed.get("asset") == entry.get("asset")
	ok = ok and handed_profile != null and handed_profile.to_dict() == source_profile.to_dict()
	ok = ok and (handed.get("ranged_runtime_profile", {}) as Dictionary).is_empty()
	ok = ok and not loop.automatic_armory_attempted
	ok = ok and loop.attack_button.text == "攻击"
	var arena: GameplayArena = ARENA.new() as GameplayArena
	arena.blueprint = entry.get("blueprint") as WeaponBlueprint
	arena.asset = entry.get("asset") as WeaponVisualAsset
	arena.facing = 1.0
	arena.melee_timer = 0.0
	var idle_geometry := arena._soft_weapon_geometry(Vector2(250, 410), 0.0)
	arena.melee_timer = 0.31
	var cast_geometry := arena._soft_weapon_geometry(Vector2(250, 410), 0.0)
	var idle_contact := Vector2(idle_geometry.get("contact", Vector2.ZERO))
	var cast_contact := Vector2(cast_geometry.get("contact", Vector2.ZERO))
	ok = ok and (cast_geometry.get("tether", PackedVector2Array()) as PackedVector2Array).size() >= 2
	ok = ok and cast_contact.distance_to(Vector2(250, 410)) > idle_contact.distance_to(Vector2(250, 410)) + 70.0
	arena.free()
	var result: Variant = true if ok else {
		"state": loop.state,
		"handed": handed,
		"automatic_armory_attempted": loop.automatic_armory_attempted,
		"attack_button": loop.attack_button.text,
		"idle_contact": idle_contact,
		"cast_contact": cast_contact,
	}
	loop.queue_free()
	return result


func _test_formal_enemy_visual_assets() -> Variant:
	var library: RefCounted = ENEMY_VISUAL_ASSETS.new()
	var loaded: Dictionary = library.load_validated()
	if not bool(loaded.get("ok", false)):
		return loaded
	var catalog: Dictionary = CATALOG.load_validated()
	if not bool(catalog.get("ok", false)):
		return catalog
	if library.background_texture == null:
		return "ARENA_BACKGROUND_TEXTURE_MISSING"
	var arena: GameplayArena = ARENA.new() as GameplayArena
	for raw_profile: Variant in (catalog.get("profiles_by_id", {}) as Dictionary).values():
		var profile := raw_profile as Dictionary
		var visual: Dictionary = library.visual_for(str(profile.get("catalog_id", profile.get("id", ""))))
		if visual.get("texture") == null:
			arena.free()
			return {"missing_visual": profile.get("id", "")}
		arena._spawn_enemy_blueprint(profile, Vector2(900, 350))
		var enemy := arena.enemies[-1]
		if (enemy.get("visual_asset", {}) as Dictionary).get("texture") == null:
			arena.free()
			return {"spawn_dropped_visual": profile.get("id", "")}
		if not bool(enemy.get("compiled_attacks_ready", false)):
			arena.free()
			return {"attack_axes_lost": profile.get("id", "")}
	var ok := int(loaded.get("enemy_count", 0)) == 3 and arena.enemies.size() == 3
	var result: Variant = true if ok else {"loaded": loaded, "enemy_count": arena.enemies.size()}
	arena.free()
	return result


func _test_pixel_art_render_contract() -> Variant:
	var declarations: Array[Dictionary] = [
		{
			"path": "res://assets/backgrounds/ruined_ember_forge_courtyard_v2.png",
			"size": Vector2i(1280, 720), "maximum_colors": 128, "requires_2x_blocks": true,
		},
		{
			"path": "res://assets/player/forge_wanderer_base_v2.png",
			"size": Vector2i(108, 108), "maximum_colors": 32, "requires_2x_blocks": false,
		},
		{
			"path": "res://assets/enemies/ember_priest_v4.png",
			"size": Vector2i(160, 128), "maximum_colors": 32, "requires_2x_blocks": true,
		},
		{
			"path": "res://assets/enemies/mechanical_spider_v3.png",
			"size": Vector2i(160, 128), "maximum_colors": 32, "requires_2x_blocks": true,
		},
		{
			"path": "res://assets/enemies/frost_siege_beast_v3.png",
			"size": Vector2i(160, 128), "maximum_colors": 32, "requires_2x_blocks": true,
		},
	]
	for declaration: Dictionary in declarations:
		var path := str(declaration["path"])
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		if image == null or image.is_empty():
			return {"path": path, "error": "IMAGE_MISSING"}
		if image.get_size() != declaration["size"]:
			return {"path": path, "size": image.get_size(), "expected": declaration["size"]}
		var colors: Dictionary = {}
		for y: int in range(image.get_height()):
			for x: int in range(image.get_width()):
				var pixel := image.get_pixel(x, y)
				var alpha_byte := roundi(pixel.a * 255.0)
				if alpha_byte not in [0, 255]:
					return {"path": path, "soft_alpha": alpha_byte, "position": Vector2i(x, y)}
				colors[pixel.to_html(true)] = true
		if colors.size() > int(declaration["maximum_colors"]):
			return {"path": path, "colors": colors.size(), "maximum": declaration["maximum_colors"]}
		if bool(declaration["requires_2x_blocks"]):
			for y: int in range(0, image.get_height(), 2):
				for x: int in range(0, image.get_width(), 2):
					var reference := image.get_pixel(x, y)
					for offset: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
						if image.get_pixel(x + offset.x, y + offset.y) != reference:
							return {"path": path, "non_integer_cluster": Vector2i(x, y)}
	return true


func _test_player_firearm_render_proportions() -> Variant:
	var entry := _weapon_entry()
	var arena := ARENA.new() as GameplayArena
	arena.blueprint = entry.get("blueprint") as WeaponBlueprint
	arena.asset = entry.get("asset") as WeaponVisualAsset
	arena.ranged_runtime_profile = (entry.get("ranged_runtime_profile", {}) as Dictionary).duplicate(true)
	arena.blueprint.affordance["support_mode"] = "one_hand"
	var sidearm_matrix: Array[Dictionary] = []
	var sidearms_ok := true
	for source_width: int in [40, 64, 80, 96]:
		arena.asset.opaque_bounds = Rect2i(0, 0, source_width, 28)
		var scale := arena._firearm_draw_scale()
		var span := float(source_width) * scale
		sidearm_matrix.append({"source_width": source_width, "scale": scale, "span": span})
		sidearms_ok = sidearms_ok and span <= 34.5
	arena.asset.opaque_bounds = Rect2i(0, 0, 88, 32)
	arena.blueprint.affordance["support_mode"] = "two_hand_shouldered"
	var shouldered_scale := arena._firearm_draw_scale()
	var shouldered_span := float(arena.asset.opaque_bounds.size.x) * shouldered_scale
	var ok := sidearms_ok and shouldered_span <= 70.5
	ok = ok and float((sidearm_matrix[1] as Dictionary)["scale"]) < shouldered_scale
	ok = ok and arena._firearm_hand_base().distance_to(arena.player_position) < 22.0
	var result: Variant = true if ok else {
		"sidearm_matrix": sidearm_matrix,
		"shouldered_scale": shouldered_scale,
		"shouldered_span": shouldered_span,
		"hand_offset": arena._firearm_hand_base() - arena.player_position,
	}
	arena.free()
	return result


func _test_identity_free_player_fit() -> Variant:
	var firearm := _weapon_entry()
	var firearm_blueprint := firearm.get("blueprint") as WeaponBlueprint
	var firearm_asset := firearm.get("asset") as WeaponVisualAsset
	firearm_asset.opaque_bounds = Rect2i(0, 0, 96, 28)
	firearm_blueprint.affordance["support_mode"] = "one_hand"
	var sidearm := WEAPON_PLAYER_FIT.compile(firearm_blueprint, firearm_asset)
	firearm_blueprint.affordance["support_mode"] = "two_hand_shouldered"
	var shouldered := WEAPON_PLAYER_FIT.compile(firearm_blueprint, firearm_asset)
	var mechanism := _mechanism_weapon_entry()
	if not bool(mechanism.get("ok", false)):
		return mechanism
	var general := WEAPON_PLAYER_FIT.compile(
		mechanism.get("blueprint") as WeaponBlueprint,
		mechanism.get("asset") as WeaponVisualAsset
	)
	var source := FileAccess.get_file_as_string("res://scripts/combat_feel/weapon_player_fit_compiler.gd").to_lower()
	for forbidden: String in ["akm", "pistol", "rifle", "umbrella", "fishing_rod", "whip", "sword"]:
		if source.contains(forbidden):
			return "fit compiler leaked identity branch: %s" % forbidden
	var ok := bool(sidearm.get("ok", false)) and bool(shouldered.get("ok", false)) and bool(general.get("ok", false))
	ok = ok and float(sidearm.get("rendered_span_pixels", 999.0)) <= 34.5
	ok = ok and float(shouldered.get("rendered_span_pixels", 999.0)) <= 70.5
	ok = ok and not bool(sidearm.get("support_required", true)) and bool(shouldered.get("support_required", false))
	ok = ok and not bool(general.get("identity_inputs_used", true))
	return true if ok else {"sidearm": sidearm, "shouldered": shouldered, "general": general}


func _test_capability_driven_strategy() -> Variant:
	var firearm := _weapon_entry()
	var ranged := WEAPON_STRATEGY.compile(
		firearm.get("blueprint") as WeaponBlueprint,
		firearm.get("asset") as WeaponVisualAsset,
		firearm.get("ranged_runtime_profile", {}) as Dictionary
	)
	var mechanism := _mechanism_weapon_entry()
	if not bool(mechanism.get("ok", false)):
		return mechanism
	var control := WEAPON_STRATEGY.compile(
		mechanism.get("blueprint") as WeaponBlueprint,
		mechanism.get("asset") as WeaponVisualAsset
	)
	var defensive_blueprint := WeaponBlueprint.from_dict((mechanism.get("blueprint") as WeaponBlueprint).to_dict())
	defensive_blueprint.affordance = (mechanism.get("blueprint") as WeaponBlueprint).affordance.duplicate(true)
	defensive_blueprint.affordance["has_broad_face"] = true
	defensive_blueprint.affordance["state_topology"] = "radial_expand"
	defensive_blueprint.affordance["activation_mode"] = "momentary"
	defensive_blueprint.affordance["functional_output"] = "radial_field"
	var defensive := WEAPON_STRATEGY.compile(
		defensive_blueprint,
		mechanism.get("asset") as WeaponVisualAsset
	)
	var tips := ranged.get("battle_tips_zh", []) as Array
	var source := FileAccess.get_file_as_string("res://scripts/combat_feel/weapon_strategy_compiler.gd").to_lower()
	for forbidden: String in ["akm", "m4a1", "fishing_rod", "umbrella", "whip", "sword"]:
		if source.contains(forbidden):
			return "strategy compiler leaked identity branch: %s" % forbidden
	var ok := bool(ranged.get("firearm", false)) and not bool(control.get("firearm", true))
	ok = ok and tips.size() == 3 and float(ranged.get("reach", 0.0)) > 0.8
	ok = ok and float(control.get("control", 0.0)) > float(ranged.get("control", 0.0))
	ok = ok and float(defensive.get("defense", 0.0)) >= 0.9
	ok = ok and float(defensive.get("active_guard_damage_multiplier", 1.0)) < 0.55
	return true if ok else {"ranged": ranged, "control": control, "defensive": defensive}


func _test_retreating_attack_aim() -> Variant:
	var entry := _weapon_entry()
	var arena := ARENA.new() as GameplayArena
	arena.start_stage(
		"training",
		entry.get("blueprint") as WeaponBlueprint,
		entry.get("asset") as WeaponVisualAsset
	)
	var enemy := arena.enemies[0]
	enemy["pos"] = arena.player_position + Vector2(26.0, 0.0)
	var hp_before := float(enemy["hp"])
	arena.set_touch_vector(Vector2.LEFT)
	arena.set_touch_attack(true)
	arena._process(1.0 / 60.0)
	var ok := arena.facing > 0.0 and float(enemy["hp"]) < hp_before
	var result: Variant = true if ok else {
		"facing": arena.facing,
		"hp_before": hp_before,
		"hp_after": enemy["hp"],
		"projectiles": arena.projectiles,
	}
	arena.free()
	return result


func _test_close_melee_sweep() -> Variant:
	var entry := _mechanism_weapon_entry()
	if not bool(entry.get("ok", false)):
		return entry
	var arena := ARENA.new() as GameplayArena
	arena.blueprint = entry.get("blueprint") as WeaponBlueprint
	var crossed_axis := arena._melee_axis_contains(Vector2(-3.0, 18.0), arena._melee_axis_reach())
	arena.free()
	return true if crossed_axis else "CLOSE_MELEE_SWEEP_MISSED_CROSSED_AXIS"


func _test_enemy_pressure_curve() -> Variant:
	var director: RefCounted = DIRECTOR.new()
	var configured: Dictionary = director.configure()
	if not bool(configured.get("ok", false)):
		return configured
	var begun: Dictionary = director.begin_run(_weapon_entry())
	if not bool(begun.get("ok", false)):
		return begun
	var encounters: Array[Dictionary] = []
	for index: int in range(3):
		var encounter: Dictionary = director.begin_next_encounter()
		encounters.append(encounter)
		if index < 2:
			director.complete_active_encounter({})
	var first_profiles := encounters[0].get("profiles", []) as Array
	var second_profiles := encounters[1].get("profiles", []) as Array
	var final_profiles := encounters[2].get("profiles", []) as Array
	var first := first_profiles[0] as Dictionary
	var final := final_profiles[0] as Dictionary
	var runtime: RefCounted = preload("res://scripts/enemy_attack/enemy_attack_runtime_driver.gd").new()
	var runtime_result: Dictionary = runtime.configure(
		final.get("attack_declarations", []) as Array,
		float(final.get("attack_tempo_multiplier", 1.0))
	)
	var telegraph := float(((runtime.compiled_attacks[0] as Dictionary).get("timeline", {}) as Dictionary).get("telegraph_seconds", 0.0))
	var ok := first_profiles.size() == 1 and second_profiles.size() == 2 and final_profiles.size() == 1
	ok = ok and float(first.get("damage_multiplier", 1.0)) > 1.0
	ok = ok and float(final.get("max_health", 0.0)) > float(first.get("max_health", 0.0)) * 2.0
	ok = ok and float(final.get("attack_tempo_multiplier", 1.0)) < float(first.get("attack_tempo_multiplier", 1.0))
	ok = ok and bool(runtime_result.get("ok", false)) and telegraph >= 0.24
	return true if ok else {"encounters": encounters, "runtime": runtime_result, "telegraph": telegraph}


func _test_general_melee_target_interaction() -> Variant:
	var entry := _mechanism_weapon_entry()
	if not bool(entry.get("ok", false)):
		return entry
	var arena := ARENA.new() as GameplayArena
	arena.start_stage(
		"training",
		entry.get("blueprint") as WeaponBlueprint,
		entry.get("asset") as WeaponVisualAsset
	)
	var enemy := arena.enemies[0]
	enemy["pos"] = arena.player_position + Vector2(72.0, 0.0)
	var before := Vector2(enemy["pos"])
	arena._update_melee_attack(true, 0.0)
	arena._update_melee_attack(false, 0.45)
	var outcome := enemy.get("last_target_interaction", {}) as Dictionary
	var moved := Vector2(enemy["pos"])
	var ok := bool(outcome.get("ok", false)) and str(outcome.get("primary_reaction", "")) in ["hook_pull", "entangle", "stagger"]
	ok = ok and moved.x < before.x and float(enemy.get("interaction_status_time", 0.0)) > 0.0
	var result: Variant = true if ok else {"outcome": outcome, "before": before, "after": moved, "strategy": arena.weapon_strategy_profile}
	arena.free()
	return result


func _test_generated_armory_reward() -> Variant:
	var loop := LOOP_SCENE.instantiate() as AutomaticLevelLoop
	root.add_child(loop)
	var reward := _weapon_entry()
	var reward_blueprint := reward.get("blueprint") as WeaponBlueprint
	reward_blueprint.display_name = "AI 自动奖励冲锋枪"
	reward["display_name"] = reward_blueprint.display_name
	loop.pending_armory_reward = reward
	loop._begin_run(_weapon_entry())
	for index: int in range(3):
		loop._process(2.0)
		loop._on_stage_completed(
			str(loop.current_encounter.get("stage_name", "")),
			{"defeated": 1, "elapsed_seconds": 1.0, "damage_taken": 0.0, "shots_fired": 2}
		)
	var offered := (
		loop.state == "completed"
		and loop.primary_button.text == "装备新枪再战"
		and loop.message_body.text.contains("AI 自动奖励冲锋枪")
	)
	if not offered:
		var diagnostics := {
			"state": loop.state,
			"button": loop.primary_button.text,
			"message": loop.message_body.text,
		}
		loop.queue_free()
		return diagnostics
	loop._on_primary_result_pressed()
	var claimed := (
		loop.state == "between_encounters"
		and loop.pending_armory_reward.is_empty()
		and loop._weapon_display_name() == "AI 自动奖励冲锋枪"
	)
	var result: Variant = true if claimed else {
		"state": loop.state,
		"pending": loop.pending_armory_reward,
		"equipped": loop._weapon_display_name(),
	}
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


func _mechanism_weapon_entry() -> Dictionary:
	var loaded: Dictionary = ASSET_LOADER.new().load_soft_weapon_asset("fishing_rod_builtin")
	if not bool(loaded.get("ok", false)):
		return loaded
	return {
		"ok": true,
		"blueprint": loaded.get("blueprint"),
		"asset": loaded.get("asset"),
		"affordance_profile": loaded.get("affordance_profile"),
		"display_name": (loaded.get("blueprint") as WeaponBlueprint).display_name,
	}


func _role_entry(family: String, action: String, identity: String) -> Dictionary:
	var entry := _weapon_entry()
	var blueprint := entry.get("blueprint") as WeaponBlueprint
	blueprint.affordance["firearm_family"] = family
	blueprint.affordance["action_mechanism"] = action
	entry["identity"] = identity
	return entry
