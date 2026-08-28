extends SceneTree

const CHOREOGRAPHY := preload("res://scripts/combat_feel/firearm_action_choreography.gd")
const SCAFFOLD := preload("res://scripts/combat_feel/firearm_pixel_scaffold.gd")
const BRIEF := preload("res://scripts/combat_feel/firearm_visual_brief.gd")
const GATE := preload("res://scripts/combat_feel/firearm_visual_identity_gate.gd")
const CACHE_POLICY := preload("res://scripts/combat_feel/firearm_visual_cache_policy.gd")
const FAL_PROVIDER := preload("res://scripts/services/fal_firearm_visual_provider.gd")
const PLAYER_ARMORY := preload("res://scripts/combat_feel/player_weapon_armory.gd")
const INTERPRETER := preload("res://scripts/services/open_identity_interpreter.gd")
const RANGED_AXIS_RESOLVER := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")
const GAMEPLAY_ARENA := preload("res://scripts/systems/gameplay_arena.gd")
const TRAINING_ARENA := preload("res://scripts/systems/open_identity_training_arena.gd")

const SPRITE_FIXTURE := "res://tests/fixtures/firearm_visual_v2/m4a1_gpt_image.png"

var passed := 0
var failed := 0


func _initialize() -> void:
	print("Forge firearm V5 visual/action tests")
	_run("Four cycle actions and four reload objects are axis-driven", _test_axis_driven_actions)
	_run("V5 cycle overhead wins and total climb is preserved", _test_v5_timing_and_climb)
	_run("Facing mirrors a shared muzzle anchor without drift", _test_facing_and_muzzle)
	_run("Shotgun revolver and belt-fed structures expose action anchors", _test_new_structures)
	_run("A readable slender pump shotgun is not judged by rifle thickness", _test_slender_shotgun_gate)
	_run("Belt-fed side_feed produces a specific visual brief", _test_side_feed_brief)
	_run("A redraw never excludes the target identity itself", _test_retry_keeps_target_identity)
	_run("Legacy finished art migrates locally and tampered art is rejected", _test_local_cache_migration)
	_run("Armory applies the same local V5 migration policy", _test_armory_migration)
	_run("Training arena consumes the shared choreography", _test_training_uses_shared_choreography)
	_run("Gameplay and training return the same action and muzzle pose", _test_arena_pose_parity)
	print("FIREARM V5 VISUAL RESULT: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _run(test_name: String, callable: Callable) -> void:
	var result: Variant = callable.call()
	if result is bool and bool(result):
		passed += 1
		print("PASS | %s" % test_name)
	else:
		failed += 1
		printerr("FAIL | %s | %s" % [test_name, str(result)])


func _test_axis_driven_actions() -> Variant:
	var timers := {
		"recoil_pixels": 5.0, "muzzle_climb_degrees": 7.0,
		"cycle_timer": 0.30, "reload_timer": 0.60, "muzzle_flash_timer": 0.03,
	}
	var ammo := {"ammo_in_magazine": 0, "magazine_size": 8}
	var cycle_kinds: Array[String] = []
	var reload_kinds: Array[String] = []
	for code: int in range(4):
		var runtime := _runtime(code, code)
		var sample := CHOREOGRAPHY.sample(runtime, timers, ammo, 1.0)
		cycle_kinds.append(str((sample.get("cycle_overlay_pose", {}) as Dictionary).get("kind", "")))
		reload_kinds.append(str((sample.get("reload_object_pose", {}) as Dictionary).get("kind", "")))
	if cycle_kinds != ["self_loading_bolt", "bolt_handle", "pump_fore_end", "cylinder_index"]:
		return cycle_kinds
	if reload_kinds != ["magazine", "single_round", "speedloader", "belt_box"]:
		return reload_kinds
	var wide_runtime := _runtime(2, 1, 9)
	wide_runtime["spread"] = 18.0
	var wide := CHOREOGRAPHY.sample(wide_runtime, timers, ammo, 1.0)
	var narrow := CHOREOGRAPHY.sample(_runtime(2, 1, 1), timers, ammo, 1.0)
	if ((wide.get("flash_pose", {}) as Dictionary).get("scale") as Vector2).x <= ((narrow.get("flash_pose", {}) as Dictionary).get("scale") as Vector2).x:
		return {"wide": wide, "narrow": narrow}
	if ((wide.get("flash_pose", {}) as Dictionary).get("scale") as Vector2).y <= ((narrow.get("flash_pose", {}) as Dictionary).get("scale") as Vector2).y:
		return {"wide_spread": wide, "narrow_spread": narrow}
	var alias_a := _runtime(1, 1)
	var alias_b := alias_a.duplicate(true)
	alias_a["display_name"] = "unrelated identity A"
	alias_b["display_name"] = "unrelated identity B"
	if CHOREOGRAPHY.sample(alias_a, timers, ammo, -1.0) != CHOREOGRAPHY.sample(alias_b, timers, ammo, -1.0):
		return "identity text changed choreography"
	return true


func _test_v5_timing_and_climb() -> Variant:
	var runtime := _runtime(1, 0)
	runtime["shot_interval_seconds"] = 0.18
	runtime["cycle_overhead_seconds"] = 0.54
	runtime["manual_cycle_overhead_seconds"] = 9.0
	var action := CHOREOGRAPHY.sample(runtime, {
		"cycle_timer": 0.36,
		"muzzle_climb_degrees": 13.5,
	}, {"ammo_in_magazine": 4, "magazine_size": 8}, 1.0)
	var cycle := action.get("cycle_overlay_pose", {}) as Dictionary
	var root := action.get("root_pose", {}) as Dictionary
	if not is_equal_approx(float(cycle.get("progress", -1.0)), 0.5):
		return {"cycle_progress": cycle.get("progress"), "expected": 0.5}
	if not is_equal_approx(float(root.get("rotation", 0.0)), deg_to_rad(-13.5)):
		return root
	return true


func _test_facing_and_muzzle() -> Variant:
	var runtime := _runtime(2, 1)
	var timers := {"recoil_pixels": 6.0, "muzzle_climb_degrees": 8.0, "cycle_timer": 0.4}
	var ammo := {"ammo_in_magazine": 2, "magazine_size": 8}
	var right := CHOREOGRAPHY.sample(runtime, timers, ammo, 1.0)
	var left := CHOREOGRAPHY.sample(runtime, timers, ammo, -1.0)
	var center := Vector2(400, 300)
	var grip := Vector2(36, 64)
	var muzzle := Vector2(93, 42)
	var right_world := CHOREOGRAPHY.world_anchor(center, muzzle, grip, right.get("root_pose", {}) as Dictionary)
	var left_world := CHOREOGRAPHY.world_anchor(center, muzzle, grip, left.get("root_pose", {}) as Dictionary)
	if not is_equal_approx(right_world.x - center.x, -(left_world.x - center.x)):
		return {"right": right_world, "left": left_world}
	if not is_equal_approx(right_world.y, left_world.y):
		return {"right": right_world, "left": left_world}
	return true


func _test_new_structures() -> Variant:
	var palette := SCAFFOLD._palette("wood_steel") as Dictionary
	for layout: String in ["conventional_shotgun", "revolver", "belt_fed_support"]:
		var image := Image.create(96, 96, false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		var scaffold_anchors: Dictionary
		match layout:
			"conventional_shotgun": scaffold_anchors = SCAFFOLD._draw_conventional_shotgun(image, {}, palette)
			"revolver": scaffold_anchors = SCAFFOLD._draw_revolver(image, {}, palette)
			_: scaffold_anchors = SCAFFOLD._draw_belt_fed_support(image, {}, palette)
		_add_authored_palette_variation(image)
		var blueprint := WeaponBlueprint.new()
		blueprint.behavior_family = "sustained_ranged"
		blueprint.affordance = {"layout": layout}
		var gate := GATE.evaluate(image, blueprint, {}, {})
		if not bool(gate.get("ok", false)):
			return {"layout": layout, "gate": gate}
		var anchors := gate.get("anchors", {}) as Dictionary
		for anchor: String in ["GripPrimary", "Muzzle", "ActionCycle", "ActionReload"]:
			if not anchors.get(anchor, []) is Array or (anchors.get(anchor, []) as Array).size() < 2:
				return {"layout": layout, "missing": anchor, "scaffold": scaffold_anchors}
	return true


func _test_slender_shotgun_gate() -> Variant:
	var source := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	source.fill(Color.TRANSPARENT)
	SCAFFOLD._draw_conventional_shotgun(source, {}, SCAFFOLD._palette("wood_steel"))
	var source_bounds := _alpha_bounds(source)
	var cropped := source.get_region(source_bounds)
	cropped.resize(82, 14, Image.INTERPOLATE_NEAREST)
	var slender := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	slender.fill(Color.TRANSPARENT)
	slender.blit_rect(cropped, Rect2i(Vector2i.ZERO, cropped.get_size()), Vector2i(7, 41))
	_add_authored_palette_variation(slender)
	var blueprint := WeaponBlueprint.new()
	blueprint.behavior_family = "sustained_ranged"
	blueprint.affordance = {"layout": "conventional_shotgun"}
	var gate := GATE.evaluate(slender, blueprint, {}, {})
	if not bool(gate.get("ok", false)):
		return gate
	var bounds := (gate.get("metrics", {}) as Dictionary).get("bounds", []) as Array
	if bounds.size() < 4 or int(bounds[2]) < 80 or int(bounds[3]) > 16:
		return bounds
	return true


func _test_side_feed_brief() -> Variant:
	var parts := BRIEF._required_visible_parts({"layout": "belt_fed_support", "upper_profile": "top_rail"}) as Array[String]
	var clause := BRIEF._feed_clause("side_feed", "belt_box")
	if "visible_ammunition_belt" not in parts or "belt_box" not in parts:
		return parts
	if not clause.contains("side and underside") or clause.contains("declared feed position"):
		return clause
	return true


func _test_retry_keeps_target_identity() -> Variant:
	var provider = FAL_PROVIDER.new()
	provider.active_request_payload = {
		"identity": "M249",
		"canonical_name": "M249 Light Machine Gun",
	}
	var prompt: String = provider._visual_verification_retry_prompt({
		"verdict": {
			"required_landmarks_missing": ["feed cover hump"],
			"contradictions": [],
			"closest_confusable_identity": "M249",
		},
	})
	if not prompt.contains("feed cover hump") or prompt.contains("do not resemble M249"):
		return prompt
	return true


func _test_local_cache_migration() -> Variant:
	var root := "user://playlab/tests/firearm_v5_provider_%d" % Time.get_ticks_usec()
	var blueprint := _m4_blueprint()
	if blueprint == null:
		return "M4 blueprint unavailable"
	var provider = FAL_PROVIDER.new()
	provider.cache_root = root.path_join("cache")
	provider.output_root = root.path_join("requests")
	provider.bridge_script_path = "res://tests/fixtures/bridge_must_not_exist.py"
	provider.configure_local_first("python-that-must-not-run")
	provider.request_visual(blueprint, "", PackedByteArray(), 0.0)
	var legacy_key: String = provider._cache_key_for_version(
		provider.active_request_payload,
		CACHE_POLICY.LEGACY_PIPELINE_VERSIONS[0]
	)
	var legacy_directory := root.path_join("cache").path_join(legacy_key)
	var sprite_bytes := FileAccess.get_file_as_bytes(SPRITE_FIXTURE)
	_write_legacy_cache(legacy_directory, legacy_key, sprite_bytes)
	provider.request_visual(blueprint, "", PackedByteArray(), 0.0)
	var route := provider.request_route()
	var result: Dictionary = provider.poll()
	var result_cache := (result.get("manifest", {}) as Dictionary).get("cache", {}) as Dictionary
	if route != "local_immediate_hit" or str(result.get("status", "")) != "success" or bool(result.get("external_process_started", true)) or not bool(result_cache.get("locally_revalidated", false)):
		_remove_tree(ProjectSettings.globalize_path(root))
		return {"route": route, "result": result}
	var migrated_record: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		root.path_join("cache").path_join(provider.active_cache_key).path_join("cache_record.json")
	))
	if not migrated_record is Dictionary or str((migrated_record as Dictionary).get("pipeline_version", "")) != CACHE_POLICY.CURRENT_PIPELINE_VERSION:
		_remove_tree(ProjectSettings.globalize_path(root))
		return migrated_record

	var tampered_provider = FAL_PROVIDER.new()
	var tampered_root := root.path_join("tampered")
	tampered_provider.cache_root = tampered_root.path_join("cache")
	tampered_provider.output_root = tampered_root.path_join("requests")
	tampered_provider.bridge_script_path = "res://tests/fixtures/bridge_must_not_exist.py"
	tampered_provider.configure_local_first("python-that-must-not-run")
	tampered_provider.request_visual(blueprint, "", PackedByteArray(), 0.0)
	var tampered_key: String = tampered_provider._cache_key_for_version(
		tampered_provider.active_request_payload,
		CACHE_POLICY.LEGACY_PIPELINE_VERSIONS[0]
	)
	var tampered_bytes := sprite_bytes.duplicate()
	tampered_bytes[tampered_bytes.size() - 8] = tampered_bytes[tampered_bytes.size() - 8] ^ 1
	_write_legacy_cache(tampered_root.path_join("cache").path_join(tampered_key), tampered_key, sprite_bytes)
	_write_bytes(tampered_root.path_join("cache").path_join(tampered_key).path_join("processed_sprite.png"), tampered_bytes)
	tampered_provider.request_visual(blueprint, "", PackedByteArray(), 0.0)
	var tampered_route := tampered_provider.request_route()
	var no_process: bool = tampered_provider.process_id == -1
	_remove_tree(ProjectSettings.globalize_path(root))
	if tampered_route != "remote_generation_unavailable" or not no_process:
		return {"route": tampered_route, "process": tampered_provider.process_id}
	return true


func _test_armory_migration() -> Variant:
	var root := "user://playlab/tests/firearm_v5_armory_%d" % Time.get_ticks_usec()
	var directory := root.path_join("cache/legacy_m4")
	var bytes := FileAccess.get_file_as_bytes(SPRITE_FIXTURE)
	_write_legacy_cache(directory, "legacy_m4_key", bytes)
	var armory = PLAYER_ARMORY.new()
	armory.visual_cache_root = root.path_join("cache")
	armory.profile_cache_paths = []
	var entries: Array[Dictionary] = armory.load_entries()
	var record_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("cache_record.json")))
	_remove_tree(ProjectSettings.globalize_path(root))
	if entries.size() != 1:
		return {"entries": entries.size(), "diagnostics": armory.last_load_diagnostics}
	if not bool(entries[0].get("locally_revalidated", false)):
		return entries[0]
	if not record_value is Dictionary or str((record_value as Dictionary).get("pipeline_version", "")) != CACHE_POLICY.CURRENT_PIPELINE_VERSION:
		return record_value
	return true


func _test_training_uses_shared_choreography() -> Variant:
	var gameplay_source := FileAccess.get_file_as_string("res://scripts/systems/gameplay_arena.gd")
	var training_source := FileAccess.get_file_as_string("res://scripts/systems/open_identity_training_arena.gd")
	if not gameplay_source.contains("FIREARM_ACTION_CHOREOGRAPHY.sample"):
		return "formal gameplay does not consume shared choreography"
	for duplicate_method: String in [
		"func _firearm_action_sample", "func _muzzle_world", "func _draw_firearm_action_overlays",
		"func _draw_cycle_overlay", "func _draw_reload_object", "func _draw_ejected_case",
	]:
		if training_source.contains(duplicate_method):
			return "training duplicates inherited firearm method: %s" % duplicate_method
	for duplicate_curve: String in ["sin(reload_progress", "sin(cycle_progress", "manual_cycle_total_seconds(ranged_runtime_profile)"]:
		if training_source.contains(duplicate_curve):
			return "training still owns curve: %s" % duplicate_curve
	return true


func _test_arena_pose_parity() -> Variant:
	var gameplay = GAMEPLAY_ARENA.new()
	var training = TRAINING_ARENA.new()
	var runtime := _runtime(2, 1, 8)
	runtime["ok"] = true
	runtime["schema"] = RANGED_AXIS_RESOLVER.RUNTIME_SCHEMA
	runtime["magazine_size"] = 8
	var visual_asset := WeaponVisualAsset.new()
	visual_asset.grip_primary = Vector2(36, 64)
	visual_asset.grip_secondary = Vector2(69, 51)
	visual_asset.muzzle = Vector2(93, 42)
	for arena: Node in [gameplay, training]:
		arena.player_position = Vector2(318, 407)
		arena.facing = -1.0
		arena.ranged_runtime_profile = runtime.duplicate(true)
		arena.weapon_recoil_offset = 7.0
		arena.weapon_muzzle_climb_degrees = 12.5
		arena.manual_cycle_timer = 0.31
		arena.reload_timer = 0.0
		arena.muzzle_flash_timer = 0.025
		arena.ammo_in_magazine = 3
		arena.asset = visual_asset
	var gameplay_action: Dictionary = gameplay._firearm_action_sample()
	var training_action: Dictionary = training._firearm_action_sample()
	var gameplay_muzzle: Vector2 = gameplay._muzzle_world()
	var training_muzzle: Vector2 = training._muzzle_world()
	gameplay.free()
	training.free()
	if gameplay_action != training_action:
		return {"gameplay": gameplay_action, "training": training_action}
	if not gameplay_muzzle.is_equal_approx(training_muzzle):
		return {"gameplay_muzzle": gameplay_muzzle, "training_muzzle": training_muzzle}
	return true


func _runtime(cycle_code: int, reload_code: int, pellets: int = 1) -> Dictionary:
	return {
		"cycle_action_code": cycle_code,
		"reload_feed_code": reload_code,
		"pellet_count": pellets,
		"spread": 0.0,
		"muzzle_flash_scale": 1.0,
		"shot_interval_seconds": 0.18,
		"cycle_overhead_seconds": 0.54,
		"reload_seconds": 1.2,
		"muzzle_flash_seconds": 0.065,
	}


func _m4_blueprint() -> WeaponBlueprint:
	var interpreted: Dictionary = INTERPRETER.new().interpret("M4A1", PackedByteArray(), {})
	return interpreted.get("blueprint") as WeaponBlueprint


func _write_legacy_cache(directory: String, key: String, sprite_bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	_write_bytes(directory.path_join("raw_pixel_art.png"), sprite_bytes)
	_write_bytes(directory.path_join("processed_sprite.png"), sprite_bytes)
	_write_json(directory.path_join("manifest.json"), {
		"schema": CACHE_POLICY.MANIFEST_SCHEMA,
		"status": "success",
		"identity": "M4A1",
		"canonical_identity": "M4A1",
		"finished_art": true,
		"presentable_to_player": true,
		"firearm_visual_gate_passed": true,
		"ai_visual_identity_verification": {
			"schema": CACHE_POLICY.VERIFICATION_SCHEMA,
			"ok": true,
			"passed": true,
		},
		"firearm_visual_identity_gate": {"schema": "forge-firearm-visual-identity-gate-v1", "anchors": {}},
	})
	_write_json(directory.path_join("cache_record.json"), {
		"schema": CACHE_POLICY.CACHE_SCHEMA,
		"key": key,
		"pipeline_version": CACHE_POLICY.LEGACY_PIPELINE_VERSIONS[0],
		"identity": "M4A1",
		"canonical_name": "M4A1",
		"processed_sprite_sha256": _sha256(sprite_bytes),
	})


func _add_authored_palette_variation(image: Image) -> void:
	var colors: Array[Color] = [
		Color("26313a"), Color("34434d"), Color("475762"), Color("5b6972"),
		Color("71808a"), Color("89969e"), Color("a4adb3"), Color("c0c7cb"),
	]
	var cursor := 0
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.1:
				image.set_pixel(x, y, colors[cursor])
				cursor += 1
				if cursor >= colors.size():
					return


func _alpha_bounds(image: Image) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.10:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func _write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "  "))
	file.close()


func _write_bytes(path: String, value: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(value)
	file.close()


func _sha256(value: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value)
	return context.finish().hex_encode()


func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var child := directory.get_next()
	while not child.is_empty():
		if child != "." and child != "..":
			var child_path := path.path_join(child)
			if directory.current_is_dir():
				_remove_tree(child_path)
			else:
				DirAccess.remove_absolute(child_path)
		child = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)
