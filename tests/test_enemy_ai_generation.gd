extends SceneTree

const PROVIDER := preload("res://scripts/enemy_attack/enemy_ai_blueprint_provider.gd")
const RESOLVER := preload("res://scripts/enemy_attack/enemy_ai_blueprint_resolver.gd")
const IDENTITY_VISUAL := preload("res://scripts/enemy_attack/enemy_identity_visual_language.gd")
const ATTACK_SPRITE := preload("res://scripts/enemy_attack/enemy_attack_sprite_language.gd")
const ARENA := preload("res://scripts/systems/gameplay_arena.gd")
const PLAYTEST_SCENE := preload("res://scenes/ai_enemy_playtest.tscn")
const FIXTURE_PATH := "res://tests/fixtures/enemy_ai_mechanical_spider_response.json"

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
	playtest._start_combat(profile)
	var ok: bool = playtest.state == "combat"
	ok = ok and playtest.arena.enemies.size() == 1
	ok = ok and str(playtest.arena.enemies[0].get("display_name", "")) == "织网猎蛛"
	var diagnostics := {"state": playtest.state, "enemy_count": playtest.arena.enemies.size()}
	playtest.queue_free()
	return true if ok else diagnostics


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
