extends SceneTree

const PROVIDER := preload("res://scripts/enemy_attack/enemy_ai_blueprint_provider.gd")
const RESOLVER := preload("res://scripts/enemy_attack/enemy_ai_blueprint_resolver.gd")
const IDENTITY_VISUAL := preload("res://scripts/enemy_attack/enemy_identity_visual_language.gd")
const ATTACK_SPRITE := preload("res://scripts/enemy_attack/enemy_attack_sprite_language.gd")
const ARENA := preload("res://scripts/systems/gameplay_arena.gd")
const PLAYTEST_SCENE := preload("res://scenes/ai_enemy_playtest.tscn")
const PLAYER_ARMORY := preload("res://scripts/combat_feel/player_weapon_armory.gd")
const RUNTIME_HANDOFF := preload("res://scripts/combat_feel/runtime_mechanism_handoff.gd")
const RANGED_AXIS_RESOLVER := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")
const FIXTURE_PATH := "res://tests/fixtures/enemy_ai_mechanical_spider_response.json"
const FIREARM_SPRITE_FIXTURE := "res://tests/fixtures/firearm_visual_v2/m4a1_gpt_image.png"

var passed := 0
var failed := 0


func _initialize() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_check("AI enemy fixture compiles into one complete combat blueprint", _test_fixture_compiles)
	_check("Illegal AI attack coverage fails closed", _test_illegal_coverage_rejected)
	_check("Enemy identity visual axes produce a readable arachnid body contract", _test_identity_visual)
	_check("Combat arena spawns anonymous generated enemies from blueprint data", _test_blueprint_arena_spawn)
	_check("Solo AI enemies can execute higher-cost pressure attacks", _test_solo_enemy_coordination_budget)
	_check("Cached AI enemies preserve integer attack selection fields", _test_cache_round_trip)
	_check("AI enemy playtest accepts a compiled blueprint without player mechanics", _test_playtest_handoff)
	_check("Player armory reconstructs a cached firearm without an API call", _test_player_armory_cache)
	_check("Cached M16A2 uses the current three-round-burst catalog mechanism", _test_m16a2_armory_mechanism)
	_check("Cached M24A2 preserves manual cycling through the armory handoff", _test_m24a2_armory_handoff)
	_check("Ranged handoff preserves the AI-compiled firearm profile", _test_ranged_handoff)
	var provider_result: Variant = await _test_offline_provider_handoff()
	_check("Offline AI bridge hands one strict response back to Godot", func() -> Variant: return provider_result)
	_check("AI generation boundary never requests player confirmation", _test_no_player_confirmation)
	print("ENEMY_AI_GENERATION_TESTS passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _check(label: String, callable: Callable) -> void:
	var result: Variant = callable.call()
	if result is bool and bool(result):
		passed += 1
		print("PASS | %s" % label)
	else:
		failed += 1
		printerr("FAIL | %s | %s" % [label, str(result)])


func _test_fixture_compiles() -> Variant:
	var payload := _fixture()
	var result: Dictionary = RESOLVER.accept_ai_response("机械蜘蛛", payload, "AI_TEST", false)
	if not bool(result.get("ok", false)):
		return result
	var declarations := result.get("attack_declarations", []) as Array
	var labels := result.get("attack_labels_zh", []) as Array
	var visual := result.get("visual_identity_axes", {}) as Dictionary
	var ok := str(result.get("schema", "")) == RESOLVER.PROFILE_SCHEMA
	ok = ok and str(result.get("display_name", "")) == "织网猎蛛"
	ok = ok and declarations.size() == 2 and labels == ["锁向飞扑", "电网喷射"]
	ok = ok and str(visual.get("body_plan", "")) == "arachnid"
	ok = ok and is_equal_approx(float(result.get("armor_integrity", 0.0)), 0.45)
	ok = ok and is_equal_approx(float(result.get("max_health", 0.0)), 78.0)
	ok = ok and is_equal_approx(float(result.get("move_speed", 0.0)), 78.0)
	ok = ok and not bool(result.get("runtime_identity_inputs_used", true))
	ok = ok and not bool(result.get("player_confirmation_required", true))
	return true if ok else result


func _test_illegal_coverage_rejected() -> Variant:
	var payload := _fixture()
	var attacks := payload.get("attacks", []) as Array
	var pressure := attacks[1] as Dictionary
	var selection := pressure.get("selection", {}) as Dictionary
	selection["preferred_range"] = "mid"
	var result: Dictionary = RESOLVER.accept_ai_response("机械蜘蛛", payload, "AI_TEST", false)
	return true if not bool(result.get("ok", false)) and str(result.get("error", "")).contains("RANGE_COVERAGE") else result


func _test_identity_visual() -> Variant:
	var payload := _fixture()
	var visual: Dictionary = IDENTITY_VISUAL.compile(payload.get("visual_axes", {}) as Dictionary)
	var ok := bool(visual.get("ok", false))
	ok = ok and str(visual.get("body_plan", "")) == "arachnid"
	ok = ok and str(visual.get("material_color", "")) == "64748b"
	ok = ok and str(visual.get("accent_color", "")) == "fde047"
	ok = ok and str(visual.get("signature_feature", "")) == "mandibles"
	return true if ok else visual


func _test_blueprint_arena_spawn() -> Variant:
	var profile: Dictionary = RESOLVER.accept_ai_response("机械蜘蛛", _fixture(), "AI_TEST", false)
	if not bool(profile.get("ok", false)):
		return profile
	var arena: Node2D = ARENA.new()
	arena.stage_name = "ai_enemy"
	arena.player_position = Vector2(500, 400)
	arena._spawn_enemy_blueprint(profile, Vector2(780, 400))
	if arena.enemies.size() != 1:
		arena.free()
		return {"enemy_count": arena.enemies.size()}
	var enemy: Dictionary = arena.enemies[0]
	var runtime: Variant = enemy.get("attack_runtime", null)
	var visual_axes := enemy.get("visual_identity_axes", {}) as Dictionary
	var ok := str(enemy.get("type", "")) == "generated_enemy"
	ok = ok and str(enemy.get("display_name", "")) == "织网猎蛛"
	ok = ok and str(visual_axes.get("body_plan", "")) == "arachnid"
	ok = ok and runtime != null and runtime.compiled_attacks.size() == 2
	arena._update_enemies(0.01)
	ok = ok and runtime.is_running()
	var sprite: Dictionary = ATTACK_SPRITE.compile(runtime.current_attack)
	ok = ok and bool(sprite.get("ok", false))
	var diagnostics := {"enemy": enemy, "runtime": runtime.snapshot() if runtime != null else {}}
	arena.free()
	return true if ok else diagnostics


func _test_playtest_handoff() -> Variant:
	var profile: Dictionary = RESOLVER.accept_ai_response("机械蜘蛛", _fixture(), "AI_TEST", false)
	if not bool(profile.get("ok", false)):
		return profile
	var playtest: Node2D = PLAYTEST_SCENE.instantiate()
	root.add_child(playtest)
	playtest._build_weapon_fixture()
	playtest._start_combat(profile)
	var ok: bool = playtest.state == "combat"
	ok = ok and playtest.arena.enemies.size() == 1
	ok = ok and str(playtest.arena.enemies[0].get("display_name", "")) == "织网猎蛛"
	var diagnostics := {"state": playtest.state, "enemy_count": playtest.arena.enemies.size()}
	playtest.queue_free()
	return true if ok else diagnostics


func _test_player_armory_cache() -> Variant:
	var root_path := "user://playlab/tests/player_armory_%d" % Time.get_ticks_usec()
	var cache_directory := root_path.path_join("visual/cache_v1/m4a1")
	var absolute_directory := ProjectSettings.globalize_path(cache_directory)
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		return "ARMORY_TEST_DIRECTORY_FAILED"
	var sprite_bytes := FileAccess.get_file_as_bytes(FIREARM_SPRITE_FIXTURE)
	var sprite := FileAccess.open(cache_directory.path_join("processed_sprite.png"), FileAccess.WRITE)
	if sprite == null:
		_remove_tree(ProjectSettings.globalize_path(root_path))
		return "ARMORY_TEST_SPRITE_WRITE_FAILED"
	sprite.store_buffer(sprite_bytes)
	sprite.close()
	_write_json(cache_directory.path_join("cache_record.json"), {
		"identity": "M4A1",
		"canonical_name": "M4A1",
		"processed_sprite_sha256": _sha256(sprite_bytes),
	})
	_write_json(cache_directory.path_join("manifest.json"), {
		"status": "success",
		"finished_art": true,
		"presentable_to_player": true,
		"firearm_visual_gate_passed": true,
	})
	var armory: RefCounted = PLAYER_ARMORY.new()
	armory.visual_cache_root = root_path.path_join("visual/cache_v1")
	armory.profile_cache_paths = []
	var entries: Array[Dictionary] = armory.load_entries()
	_remove_tree(ProjectSettings.globalize_path(root_path))
	if entries.size() != 1:
		return {"entry_count": entries.size()}
	var entry := entries[0]
	var blueprint := entry.get("blueprint") as WeaponBlueprint
	var asset := entry.get("asset") as WeaponVisualAsset
	var runtime := entry.get("ranged_runtime_profile", {}) as Dictionary
	var ok := blueprint != null and asset != null and str(entry.get("display_name", "")) == "M4A1"
	ok = ok and bool(runtime.get("ok", false)) and int(runtime.get("magazine_size", 0)) > 0
	ok = ok and not bool(entry.get("paid_api_call_used_for_selection", true))
	return true if ok else entry


func _test_m16a2_armory_mechanism() -> Variant:
	var root_path := "user://playlab/tests/player_armory_m16a2_%d" % Time.get_ticks_usec()
	var cache_directory := root_path.path_join("visual/cache_v1/m16a2")
	var absolute_directory := ProjectSettings.globalize_path(cache_directory)
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		return "M16A2_ARMORY_TEST_DIRECTORY_FAILED"
	var sprite_bytes := FileAccess.get_file_as_bytes(FIREARM_SPRITE_FIXTURE)
	var sprite := FileAccess.open(cache_directory.path_join("processed_sprite.png"), FileAccess.WRITE)
	if sprite == null:
		_remove_tree(ProjectSettings.globalize_path(root_path))
		return "M16A2_ARMORY_TEST_SPRITE_WRITE_FAILED"
	sprite.store_buffer(sprite_bytes)
	sprite.close()
	_write_json(cache_directory.path_join("cache_record.json"), {
		"identity": "M16A2",
		"canonical_name": "M16A2",
		"processed_sprite_sha256": _sha256(sprite_bytes),
	})
	_write_json(cache_directory.path_join("manifest.json"), {
		"status": "success",
		"finished_art": true,
		"presentable_to_player": true,
		"firearm_visual_gate_passed": true,
	})
	var armory: RefCounted = PLAYER_ARMORY.new()
	armory.visual_cache_root = root_path.path_join("visual/cache_v1")
	armory.profile_cache_paths = []
	var entries: Array[Dictionary] = armory.load_entries()
	_remove_tree(ProjectSettings.globalize_path(root_path))
	if entries.size() != 1:
		return {"entry_count": entries.size()}
	var entry := entries[0]
	var blueprint := entry.get("blueprint") as WeaponBlueprint
	var runtime := entry.get("ranged_runtime_profile", {}) as Dictionary
	var ok := blueprint != null and str(entry.get("display_name", "")) == "M16A2"
	ok = ok and str(blueprint.affordance.get("fire_control", "")) == "three_round_burst"
	ok = ok and not bool(runtime.get("automatic_fire", true)) and int(runtime.get("burst_size", 0)) == 3
	ok = ok and not bool(entry.get("legacy_axis_migration", true))
	ok = ok and not bool(entry.get("paid_api_call_used_for_selection", true))
	return true if ok else entry


func _test_m24a2_armory_handoff() -> Variant:
	var root_path := "user://playlab/tests/player_armory_m24a2_%d" % Time.get_ticks_usec()
	var cache_directory := root_path.path_join("visual/cache_v1/m24a2")
	var absolute_directory := ProjectSettings.globalize_path(cache_directory)
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		return "M24A2_ARMORY_TEST_DIRECTORY_FAILED"
	var sprite_bytes := FileAccess.get_file_as_bytes(FIREARM_SPRITE_FIXTURE)
	var sprite := FileAccess.open(cache_directory.path_join("processed_sprite.png"), FileAccess.WRITE)
	if sprite == null:
		_remove_tree(ProjectSettings.globalize_path(root_path))
		return "M24A2_ARMORY_TEST_SPRITE_WRITE_FAILED"
	sprite.store_buffer(sprite_bytes)
	sprite.close()
	_write_json(cache_directory.path_join("cache_record.json"), {
		"identity": "M24A2",
		"canonical_name": "M24A2狙击步枪",
		"processed_sprite_sha256": _sha256(sprite_bytes),
	})
	_write_json(cache_directory.path_join("manifest.json"), {
		"status": "success",
		"finished_art": true,
		"presentable_to_player": true,
		"firearm_visual_gate_passed": true,
	})
	var armory: RefCounted = PLAYER_ARMORY.new()
	armory.visual_cache_root = root_path.path_join("visual/cache_v1")
	armory.profile_cache_paths = []
	var entries: Array[Dictionary] = armory.load_entries()
	_remove_tree(ProjectSettings.globalize_path(root_path))
	if entries.size() != 1:
		return {"entry_count": entries.size()}
	var entry := entries[0]
	var blueprint := entry.get("blueprint") as WeaponBlueprint
	var asset := entry.get("asset") as WeaponVisualAsset
	var runtime := entry.get("ranged_runtime_profile", {}) as Dictionary
	if (
		blueprint == null
		or asset == null
		or str(entry.get("display_name", "")) != "M24A2狙击步枪"
		or str(blueprint.affordance.get("fire_control", "")) != "manual_cycle"
		or not bool(runtime.get("manual_cycle_required", false))
		or float(runtime.get("manual_cycle_overhead_seconds", 0.0)) <= 0.0
		or bool(entry.get("paid_api_call_used_for_selection", true))
	):
		return entry
	var handoff: Node = RUNTIME_HANDOFF.new()
	var error := str(handoff.store_ranged(blueprint, asset, runtime))
	var payload: Dictionary = handoff.take_ranged()
	var stored_runtime := payload.get("ranged_runtime_profile", {}) as Dictionary
	var ok := error.is_empty() and str(payload.get("kind", "")) == "ranged_firearm"
	ok = ok and bool(stored_runtime.get("manual_cycle_required", false))
	ok = ok and is_equal_approx(
		float(stored_runtime.get("manual_cycle_overhead_seconds", 0.0)),
		float(runtime.get("manual_cycle_overhead_seconds", -1.0))
	)
	ok = ok and not handoff.has_pending()
	handoff.free()
	return true if ok else {"error": error, "payload": payload}


func _test_ranged_handoff() -> Variant:
	var playtest: Node2D = PLAYTEST_SCENE.instantiate()
	playtest._build_weapon_fixture()
	var runtime: Dictionary = RANGED_AXIS_RESOLVER.compile(
		playtest.weapon_blueprint.affordance,
		playtest.weapon_blueprint.affordance_source
	)
	var handoff: Node = RUNTIME_HANDOFF.new()
	var error := str(handoff.store_ranged(playtest.weapon_blueprint, playtest.weapon_asset, runtime))
	var payload: Dictionary = handoff.take_ranged()
	var stored_runtime := payload.get("ranged_runtime_profile", {}) as Dictionary
	var ok := error.is_empty() and str(payload.get("kind", "")) == "ranged_firearm"
	ok = ok and str(stored_runtime.get("axis_signature", "")) == str(runtime.get("axis_signature", ""))
	ok = ok and not handoff.has_pending()
	playtest.free()
	handoff.free()
	return true if ok else {"error": error, "payload": payload}


func _test_solo_enemy_coordination_budget() -> Variant:
	var profile: Dictionary = RESOLVER.accept_ai_response("机械蜘蛛", _fixture(), "AI_TEST", false)
	if not bool(profile.get("ok", false)):
		return profile
	var declarations := profile.get("attack_declarations", []) as Array
	var pressure := declarations[1] as Dictionary
	var selection := pressure.get("selection", {}) as Dictionary
	selection["coordination_cost"] = 2
	var arena: Node2D = ARENA.new()
	arena.stage_name = "ai_enemy"
	arena.player_position = Vector2(500, 400)
	arena._spawn_enemy_blueprint(profile, Vector2(1000, 400))
	var enemy: Dictionary = arena.enemies[0]
	var runtime: Variant = enemy.get("attack_runtime", null)
	arena._update_enemies(0.01)
	var ok := int(enemy.get("coordination_budget", 0)) == 3
	ok = ok and runtime != null and runtime.is_running()
	ok = ok and runtime.current_delivery() == "projectile"
	var diagnostics := {"enemy": enemy, "runtime": runtime.snapshot() if runtime != null else {}}
	arena.free()
	return true if ok else diagnostics


func _test_offline_provider_handoff() -> Variant:
	var provider: RefCounted = PROVIDER.new()
	provider.offline_fixture_path = FIXTURE_PATH
	var configured: Dictionary = provider.configure("python")
	if not bool(configured.get("ok", false)):
		return configured
	provider.request_blueprint("机械蜘蛛")
	var deadline := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline:
		var result: Dictionary = provider.poll()
		if str(result.get("status", "")) == "success":
			var response := result.get("response", {}) as Dictionary
			return true if str(response.get("canonical_name_zh", "")) == "织网猎蛛" and not bool(result.get("player_confirmation_required", true)) else result
		if str(result.get("status", "")) == "failed":
			return result
		await create_timer(0.02).timeout
	provider.cancel_current()
	return "OFFLINE_PROVIDER_TIMEOUT"


func _test_cache_round_trip() -> Variant:
	var cache_path := "user://playlab/tests/enemy_ai_cache_round_trip.json"
	var absolute_path := ProjectSettings.globalize_path(cache_path)
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)
	var stored: Dictionary = RESOLVER.accept_ai_response("机械蜘蛛", _fixture(), "AI_TEST", true, cache_path)
	if not bool(stored.get("ok", false)):
		return stored
	var cached: Dictionary = RESOLVER.resolve_cached("机械蜘蛛", cache_path)
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)
	if not bool(cached.get("ok", false)):
		return cached
	var declarations := cached.get("attack_declarations", []) as Array
	var selection := (declarations[0] as Dictionary).get("selection", {}) as Dictionary
	var ok := typeof(selection.get("base_priority")) == TYPE_INT
	ok = ok and typeof(selection.get("coordination_cost")) == TYPE_INT
	ok = ok and typeof(selection.get("selection_rank")) == TYPE_INT
	return true if ok else selection


func _test_no_player_confirmation() -> Variant:
	var paths: Array[String] = [
		"res://scripts/enemy_attack/enemy_ai_blueprint_provider.gd",
		"res://scripts/enemy_attack/enemy_ai_blueprint_resolver.gd",
		"res://scripts/enemy_attack/ai_enemy_playtest.gd",
	]
	for path: String in paths:
		var source := FileAccess.get_file_as_string(path).to_lower()
		for forbidden: String in ["ask_player", "player_choice", "confirm_mechanic", "choose_attack"]:
			if source.contains(forbidden):
				return "%s leaked %s" % [path, forbidden]
	var profile: Dictionary = RESOLVER.accept_ai_response("机械蜘蛛", _fixture(), "AI_TEST", false)
	return true if not bool(profile.get("player_confirmation_required", true)) else profile


func _fixture() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}


func _write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value))
		file.close()


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _remove_tree(absolute_path: String) -> void:
	var directory := DirAccess.open(absolute_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var child := directory.get_next()
	while not child.is_empty():
		var child_path := absolute_path.path_join(child)
		if directory.current_is_dir():
			_remove_tree(child_path)
		else:
			DirAccess.remove_absolute(child_path)
		child = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(absolute_path)
