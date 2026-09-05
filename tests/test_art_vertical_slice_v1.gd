extends SceneTree

const SESSION := preload("res://scripts/art_vertical_slice_v1/art_slice_session.gd")
const CATALOG := preload("res://scripts/enemy_attack/offline_enemy_blueprint_catalog.gd")
var passed := 0
var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(label: String, condition: bool) -> void:
	if condition: passed += 1; print("PASS | ", label)
	else: failed += 1; printerr("FAIL | ", label)


func _run() -> void:
	var profiles: Array[Dictionary] = SESSION.encounter_profiles()
	var catalog: Dictionary = CATALOG.load_validated()
	_check("Church sample has two validated enemy mechanisms", profiles.size() == 2)
	if profiles.size() == 2:
		for profile: Dictionary in profiles:
			var original: Dictionary = catalog.profiles_by_id[profile.catalog_id]
			_check("Visual identity does not alter attacks: " + str(profile.catalog_id), profile.attack_declarations == original.attack_declarations)
			var position: Vector2 = profile.spawn_position
			_check("Enemy spawn stays inside Church walk plane: " + str(profile.catalog_id), position.x >= 100 and position.x <= 1180 and position.y >= 335 and position.y <= 600)
	var source := FileAccess.get_file_as_string("res://scripts/art_vertical_slice_v1/art_slice_session.gd")
	var no_writes := true
	for forbidden: String in ["remember_equipped(", ".save_entry(", ".record_run(", "accept_ai_response(", "HTTPRequest.new("]:
		no_writes = no_writes and forbidden not in source
	_check("Independent scene has no generation/library mutation entrypoint", no_writes)
	var launcher := FileAccess.get_file_as_string("res://scripts/run_art_vertical_slice_v1.ps1")
	_check("Launcher targets independent scene and skips environment file loading", "res://scenes/art_vertical_slice_v1.tscn" in launcher and "EnvFile" not in launcher and "Read-Host" not in launcher)
	_check("Replay evidence distinguishes rendered bot inputs from manual play", '"desktop_manual_input": false' in source and '"real_godot_render"' in source)
	_check("Completion guard requires real empty encounter", 'not arena.enemies.is_empty(): return' in source)
	var semi := {"automatic_fire": false, "shot_interval_seconds": 0.2}
	_check("Semi-auto replay releases trigger between legal shots", SESSION.replay_trigger_down(semi, 0.03, true) and not SESSION.replay_trigger_down(semi, 0.15, true) and SESSION.replay_trigger_down(semi, 0.33, true))
	_check("Automatic replay holds trigger only when aligned", SESSION.replay_trigger_down({"automatic_fire": true}, 0.15, true) and not SESSION.replay_trigger_down({"automatic_fire": true}, 0.15, false))
	var short_press := InputEventKey.new()
	short_press.keycode = KEY_F8
	short_press.pressed = true
	_check("Short logical-key press is handled without polling", SESSION.hotkey_from_event(short_press) == KEY_F8)
	short_press.echo = true
	_check("Held-key repeats do not double-trigger hotkeys", SESSION.hotkey_from_event(short_press) == KEY_NONE)
	short_press.echo = false
	short_press.pressed = false
	_check("Release does not double-trigger hotkeys", SESSION.hotkey_from_event(short_press) == KEY_NONE)
	short_press.pressed = true
	short_press.physical_keycode = KEY_N
	_check("Physical hotkeys remain supported", SESSION.hotkey_from_event(short_press) == KEY_N)
	var button: Button = SESSION._button("test", Vector2.ZERO, Vector2(100, 40))
	var disabled: StyleBoxFlat = button.get_theme_stylebox("disabled")
	_check("Disabled controls keep an opaque readable backdrop", disabled != null and disabled.bg_color.a == 1.0 and button.get_theme_color("font_disabled_color").a == 1.0)
	button.free()
	var session := SESSION.new()
	session._build_ui()
	session.arena = GameplayArena.new()
	session.state = "combat"
	session.arena.enemies = [{"hp": 10.0}]
	session._on_stage_completed("unit_fixture", {})
	_check("Premature completion cannot award victory", session.state == "combat")
	session.arena.enemies.clear()
	session.arena.metrics = {"damage_taken": 100.0}
	session._on_stage_completed("unit_fixture", {})
	_check("Lethal same-frame completion cannot award victory", session.state == "combat")
	session._process(0.0)
	_check("Accumulated real damage closes the loss loop", session.state == "defeated" and not session.arena.active)
	session.state = "combat"
	session.arena.metrics = {"damage_taken": 20.0}
	session._on_stage_completed("unit_fixture", {})
	_check("Genuine completion signal with surviving player awards victory", session.state == "victory")
	session.arena.blueprint = WeaponBlueprint.fixed_blueprint("hammer")
	var coverage: Dictionary = session._entry_coverage("unit")
	_check("Unobserved replay actions stay explicitly uncovered", not coverage.complete and "normal_melee_active" in coverage.missing and "mechanical_spider-active" in coverage.missing)
	session.arena.free()
	session.free()
	print("ART_VERTICAL_SLICE_TESTS passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)
