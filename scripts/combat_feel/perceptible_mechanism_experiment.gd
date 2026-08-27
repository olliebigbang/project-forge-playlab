extends "res://scripts/combat_feel/combat_feel_slice_0.gd"

const CONTACT_MECHANICS := preload("res://scripts/combat_feel/perceptible_contact_mechanics.gd")
const EXPERIMENT_LOADER := preload("res://scripts/combat_feel/perceptible_experiment_asset_loader.gd")
const CONTACT_SURFACE_ORDER := ["edge", "point", "broad", "whole_body"]

var experiment_loader := EXPERIMENT_LOADER.new()
var experiment_surface := "whole_body"
var experiment_asset_id := ""
var experiment_sample_label := "SAMPLE"


func _ready() -> void:
	super._ready()
	_configure_experiment_ui()
	var capture_directory := _argument_value("--mechanism-capture-dir=", "")
	if not capture_directory.is_empty() and motion_profile != null:
		call_deferred("_capture_mechanism_evidence", capture_directory)


func _configure_experiment_ui() -> void:
	# The base slice reserves two HUD lines. Keep the experiment within that
	# contract so its live verb readout never collides with the shared controls.
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.size = Vector2(930, 44)
	banner_label.position = Vector2(40, 162)
	banner_label.size = Vector2(1200, 56)
	banner_label.add_theme_font_size_override("font_size", 28)


func _mechanism_experiment_enabled() -> bool:
	return true


func _load_requested_weapon() -> bool:
	var requested_surface := _argument_value("--experiment-surface=", "")
	if not requested_surface.is_empty():
		return _assign_experiment_surface(requested_surface)
	var legacy_asset := _argument_value("--experiment-asset=", "")
	if not legacy_asset.is_empty():
		return _assign_experiment_asset(legacy_asset)
	return _assign_experiment_surface(experiment_surface)


func _assign_experiment_surface(surface: String) -> bool:
	return _accept_loaded_result(experiment_loader.load_surface(surface))


func _assign_experiment_asset(asset_id: String) -> bool:
	return _accept_loaded_result(experiment_loader.load_asset(asset_id))


func _accept_loaded_result(result: Dictionary) -> bool:
	if not bool(result.get("ok", false)):
		source_notice = str(result.get("error", "EXPERIMENT_LOAD_FAILED"))
		return false
	blueprint = result.get("blueprint") as WeaponBlueprint
	asset = result.get("asset") as WeaponVisualAsset
	affordance_profile = result.get("affordance_profile") as Resource
	source_notice = "PERCEPTIBLE MECHANISM EXPERIMENT · DEVELOPER ONLY"
	weapon_id = str(result.get("asset_id", ""))
	experiment_asset_id = weapon_id
	experiment_surface = str(result.get("representative_surface", ""))
	experiment_sample_label = str(result.get("sample_label", "SAMPLE"))
	is_developer_fixture = true
	return blueprint != null and asset != null and affordance_profile != null


func _switch_experiment_surface(surface: String) -> bool:
	_cleanup_enemies()
	particles.clear()
	if not _assign_experiment_surface(surface):
		_show_blocked(source_notice)
		return false
	var compiled: Variant = _compile_loaded_weapon()
	if compiled is String:
		_show_blocked(str(compiled))
		return false
	motion_profile = compiled
	_capture_compiled_timing_defaults()
	controller.configure(motion_profile)
	_update_mode_title()
	_start_run()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var requested := ""
		match event.physical_keycode:
			KEY_1: requested = "edge"
			KEY_2: requested = "point"
			KEY_3: requested = "broad"
			KEY_4: requested = "whole_body"
		if not requested.is_empty():
			_switch_experiment_surface(requested)
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)


func _update_mode_title() -> void:
	if title_label != null:
		title_label.text = "CONTACT-SURFACE AXIS — %s / %s" % [
			experiment_surface.replace("_", " ").to_upper(),
			experiment_sample_label,
		]


func _update_hud() -> void:
	if blueprint == null or motion_profile == null or status_label == null:
		return
	var primitive: Variant = controller.current_primitive
	if primitive == null and motion_profile.combo_recipe != null:
		primitive = motion_profile.combo_recipe.hit_1
	var verb: String = CONTACT_MECHANICS.verb_for(primitive)
	var scenario: String = str({
		0: "PREPARE",
		1: "COVERAGE · contact shape decides target count",
		2: "INTERRUPT · stop the telegraphed Ram",
		3: "MIXED PRESSURE · solve by contact result",
	}.get(current_wave, "EXPERIMENT"))
	status_label.text = "%s\n%s   ·   HITS %d   ·   [1] EDGE  [2] POINT  [3] BROAD  [4] BODY" % [
		scenario,
		CONTACT_MECHANICS.legend_for_verb(verb),
		int(mechanism_verb_counts.get(verb, 0)),
	]
	health_label.text = "PLAYER HP %d" % roundi(player_health)
	wave_label.text = "EXPERIMENT %d / 3　TIME %.1fs" % [current_wave, elapsed_seconds]


func _spawn_wave(wave: int) -> void:
	match wave:
		1:
			_spawn_stationary_puppet(Vector2(690, 325))
			_spawn_stationary_puppet(Vector2(725, 420))
			_spawn_stationary_puppet(Vector2(690, 515))
		2:
			var ram: Node2D = _spawn_enemy(ENEMY.RAM, Vector2(850, 420))
			ram.tell_seconds = 1.15
			ram.force_state("tell")
			_spawn_stationary_puppet(Vector2(790, 315))
			_spawn_stationary_puppet(Vector2(790, 525))
		3:
			_spawn_enemy(ENEMY.RAM, Vector2(970, 420))
			_spawn_enemy(ENEMY.PUPPET, Vector2(805, 285))
			_spawn_enemy(ENEMY.PUPPET, Vector2(805, 555))


func _spawn_stationary_puppet(at: Vector2) -> Node2D:
	var enemy: Node2D = _spawn_enemy(ENEMY.PUPPET, at)
	enemy.recovery_seconds = 999.0
	enemy.force_state("recovery")
	return enemy


func _finish_run(victory: bool) -> void:
	super._finish_run(victory)
	questionnaire_panel.visible = false
	if victory:
		banner_label.text = "EXPERIMENT COMPLETE · %s" % str(mechanism_verb_counts)


func _capture_mechanism_evidence(directory: String) -> void:
	var directory_error := DirAccess.make_dir_recursive_absolute(directory)
	if directory_error != OK:
		push_error("MECHANISM_CAPTURE_DIRECTORY_FAILED:%s" % error_string(directory_error))
		get_tree().quit(1)
		return
	for surface: String in CONTACT_SURFACE_ORDER:
		if not _switch_experiment_surface(surface):
			get_tree().quit(1)
			return
		game_active = false
		_cleanup_enemies()
		particles.clear()
		player_position = Vector2(390, 420)
		player_facing = 1.0
		controller.attack_kind = "normal"
		controller.combo_index = 1
		controller.current_primitive = motion_profile.combo_recipe.hit_1
		controller.phase = "active"
		controller.phase_duration = 1.0
		controller.phase_elapsed = 0.55
		controller.hit_targets.clear()
		for target_position: Vector2 in _sample_contact_targets(3):
			_spawn_stationary_puppet(target_position)
		_resolve_melee_hits()
		_update_hud()
		capture_caption = "%s · %s" % [
			CONTACT_MECHANICS.legend_for_verb(CONTACT_MECHANICS.verb_for(controller.current_primitive)),
			experiment_sample_label,
		]
		await _capture_frame(directory.path_join("%s.png" % experiment_asset_id))
	_cleanup_enemies()
	get_tree().quit()


func _sample_contact_targets(limit: int) -> Array[Vector2]:
	var candidates: Array[Vector2] = []
	for y: int in range(250, 591, 10):
		for x: int in range(420, 751, 10):
			var candidate := Vector2(x, y)
			if _attack_contains(candidate):
				candidates.append(candidate)
	if candidates.is_empty():
		return []

	# Farthest-point sampling makes coverage legible in evidence frames instead
	# of choosing three valid points that happen to sit on top of each other.
	var selected: Array[Vector2] = []
	selected.append(candidates[floori(float(candidates.size()) * 0.5)])
	while selected.size() < mini(limit, candidates.size()):
		var best: Vector2 = candidates[0]
		var best_separation := -1.0
		for candidate: Vector2 in candidates:
			var nearest_separation := INF
			for existing: Vector2 in selected:
				nearest_separation = minf(nearest_separation, candidate.distance_squared_to(existing))
			if nearest_separation > best_separation:
				best = candidate
				best_separation = nearest_separation
		selected.append(best)
	return selected
