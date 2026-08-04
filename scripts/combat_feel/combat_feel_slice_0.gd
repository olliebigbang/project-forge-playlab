class_name CombatFeelSlice0
extends Node2D

const ARENA := Rect2(38, 145, 1204, 532)
const ASSET_LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")
const MOTION_COMPILER := preload("res://scripts/combat_feel/melee_motion_compiler.gd")
const CONTROLLER := preload("res://scripts/combat_feel/melee_combat_controller.gd")
const ENEMY := preload("res://scripts/combat_feel/combat_feel_enemy.gd")
const FEEDBACK := preload("res://scripts/combat_feel/impact_feedback_profile.gd")

var asset_loader: Variant
var compiler: Variant
var controller: Variant
var blueprint: WeaponBlueprint
var asset: WeaponVisualAsset
var motion_profile: Variant
var source_notice := ""
var fixture_id := "M01"

var player_position := Vector2(285, 420)
var player_facing := 1.0
var player_health := 100.0
var player_invulnerable := 0.0
var player_hurt := 0.0
var dodge_direction := Vector2.RIGHT
var game_active := false
var result_state := "playing"
var current_wave := 0
var next_enemy_id := 1
var wave_delay := 0.0
var elapsed_seconds := 0.0
var enemies: Array[Node2D] = []
var particles: Array[Dictionary] = []
var comparison_assets: Array[WeaponVisualAsset] = []
var comparison_profiles: Array[Resource] = []
var shake_strength := 0.0
var last_hit_target := "none"
var current_knockback := 0.0
var capture_comparison := false
var capture_caption := ""

var ui_layer: CanvasLayer
var status_label: Label
var help_label: Label
var health_label: Label
var wave_label: Label
var banner_label: Label
var debug_label: Label
var debug_panel: PanelContainer
var debug_slider_bindings: Dictionary = {}
var retry_button: Button
var return_button: Button
var questionnaire_panel: PanelContainer
var questionnaire_error: Label
var rating_inputs: Array[OptionButton] = []
var note_inputs: Array[LineEdit] = []
var debug_visible := false
var audio_player: AudioStreamPlayer

func _ready() -> void:
	asset_loader = ASSET_LOADER.new()
	compiler = MOTION_COMPILER.new()
	controller = CONTROLLER.new()
	controller.attack_started.connect(_on_attack_started)
	_build_ui()
	_build_audio()
	if not _load_requested_weapon():
		_show_blocked("无法进入：%s" % source_notice)
		return
	motion_profile = compiler.compile(blueprint, asset)
	controller.configure(motion_profile)
	_apply_saved_tuning()
	_sync_debug_panel()
	_start_run()
	var smoke_seconds := float(_argument_value("--smoke-seconds=", "0"))
	if smoke_seconds > 0.0: _quit_after(smoke_seconds)
	var capture_dir := _argument_value("--capture-dir=", "")
	if not capture_dir.is_empty(): call_deferred("_capture_evidence", capture_dir)

func _load_requested_weapon() -> bool:
	fixture_id = _argument_value("--fixture=", "M01").to_upper()
	var sprite_path := _argument_value("--combat-sprite=", "")
	var blueprint_path := _argument_value("--combat-blueprint=", "")
	var anchors_path := _argument_value("--combat-anchors=", "")
	var result: Dictionary
	if not sprite_path.is_empty() or not blueprint_path.is_empty() or not anchors_path.is_empty():
		result = asset_loader.load_live(sprite_path, blueprint_path, anchors_path)
	else:
		result = asset_loader.load_fixture(fixture_id)
	if not bool(result.get("ok", false)):
		source_notice = str(result.get("error", "LOAD_FAILED"))
		return false
	blueprint = result.get("blueprint") as WeaponBlueprint
	asset = result.get("asset") as WeaponVisualAsset
	source_notice = str(result.get("notice", ""))
	fixture_id = str(result.get("fixture_id", fixture_id))
	if blueprint == null or asset == null:
		source_notice = "WEAPON_HANDOFF_INCOMPLETE"
		return false
	if blueprint.behavior_family != "heavy_melee":
		source_notice = "当前切片只验证近战物件。持续远程与投掷返回尚未接入。"
		return false
	return true

func _start_run() -> void:
	_cleanup_enemies()
	player_position = Vector2(285, 420)
	player_health = 100.0
	player_invulnerable = 0.0
	player_hurt = 0.0
	current_wave = 0
	next_enemy_id = 1
	wave_delay = 0.35
	elapsed_seconds = 0.0
	result_state = "playing"
	game_active = true
	controller.reset()
	controller.configure(motion_profile)
	questionnaire_panel.visible = false
	retry_button.visible = false
	return_button.visible = true
	banner_label.text = ""
	_update_hud()
	queue_redraw()

func _process(delta: float) -> void:
	_update_particles(delta)
	shake_strength = move_toward(shake_strength, 0.0, 22.0 * delta)
	position = Vector2(randf_range(-shake_strength, shake_strength), randf_range(-shake_strength, shake_strength)) if shake_strength > 0.05 else Vector2.ZERO
	if not game_active:
		_update_debug()
		queue_redraw()
		return
	elapsed_seconds += delta
	player_invulnerable = maxf(0.0, player_invulnerable - delta)
	player_hurt = maxf(0.0, player_hurt - delta)
	controller.tick(delta)
	_update_player_movement(delta)
	if controller.phase == "active": _resolve_melee_hits()
	var frozen: bool = controller.hitstop_remaining > 0.0
	for enemy: Node2D in enemies:
		enemy.simulate(delta, player_position, frozen)
	_remove_finished_dead()
	_update_waves(delta)
	_update_hud()
	_update_debug()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		debug_visible = not debug_visible
		debug_label.visible = debug_visible
		debug_panel.visible = debug_visible
		get_viewport().set_input_as_handled()
		return
	if not game_active: return
	if event.is_action_pressed("attack"):
		controller.press_attack()
		get_viewport().set_input_as_handled()
	elif event.is_action_released("attack"):
		controller.release_attack()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("dodge"):
		var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if input_vector.length() > 0.1: dodge_direction = input_vector.normalized()
		else: dodge_direction = Vector2(player_facing, 0)
		if controller.press_dodge():
			player_invulnerable = 0.24
			_play_tone("dodge")
		get_viewport().set_input_as_handled()

func _update_player_movement(delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if controller.dodge_motion_seconds > 0.0:
		player_position += dodge_direction * 510.0 * delta
	elif player_hurt <= 0.0:
		var speed := 205.0
		if controller.phase in ["startup", "active"]: speed *= motion_profile.movement_commitment
		player_position += input_vector * speed * delta
		if absf(input_vector.x) > 0.05: player_facing = signf(input_vector.x)
	player_position.x = clampf(player_position.x, ARENA.position.x + 30.0, ARENA.end.x - 30.0)
	player_position.y = clampf(player_position.y, ARENA.position.y + 52.0, ARENA.end.y - 28.0)

func _on_attack_started(kind: String, combo_index: int) -> void:
	var timing: Dictionary = motion_profile.timing_for(kind, combo_index)
	var advance: float = 17.0 * float(timing.get("movement_scale", 1.0))
	if kind == "dodge": advance = 38.0
	if kind == "charge" and motion_profile.motion_family == "thrust": advance = 58.0
	player_position.x += advance * player_facing
	_play_tone("windup")

func _resolve_melee_hits() -> void:
	for enemy: Node2D in enemies:
		if enemy.state == "dead": continue
		if not _attack_contains(enemy.position): continue
		if not controller.register_hit(enemy.enemy_id): continue
		var feedback: Resource = FEEDBACK.for_attack(motion_profile, controller.attack_kind, controller.combo_index)
		var finisher_scale := 1.45 if controller.combo_index >= 3 or controller.attack_kind == "charge" else 1.0
		if has_meta("debug_hitstop"):
			feedback.hitstop_seconds = float(get_meta("debug_hitstop")) * finisher_scale
		feedback.knockback_strength *= float(get_meta("debug_knockback", 1.0))
		feedback.camera_shake_strength *= float(get_meta("debug_shake", 1.0))
		var damage := _current_damage()
		var direction: Vector2 = (enemy.position - player_position).normalized()
		if direction.length() < 0.1: direction = Vector2(player_facing, 0)
		enemy.apply_hit(damage, direction * feedback.knockback_strength, feedback.stagger_strength)
		controller.begin_hitstop(feedback.hitstop_seconds)
		shake_strength = maxf(shake_strength, feedback.camera_shake_strength)
		last_hit_target = "%s:%d" % [enemy.enemy_kind, enemy.enemy_id]
		current_knockback = feedback.knockback_strength
		_spawn_impact(enemy.position, feedback.particle_scale)
		_play_tone("finisher" if controller.combo_index >= 3 or controller.attack_kind == "charge" else "hit")

func _attack_contains(target: Vector2) -> bool:
	var hand := _hand_world_position()
	var to_target := target - hand
	var timing: Dictionary = motion_profile.timing_for(controller.attack_kind, controller.combo_index)
	var reach: float = motion_profile.reach_pixels * float(timing.get("reach_scale", 1.0))
	var forward := to_target.x * player_facing
	match motion_profile.motion_family:
		"thrust":
			return forward >= -12.0 and forward <= reach and absf(to_target.y) <= 30.0
		"slam":
			var impact_center := hand + Vector2(player_facing * reach * 0.68, 28.0)
			return target.distance_to(impact_center) <= 48.0 + (16.0 if controller.attack_kind == "charge" else 0.0)
		_:
			return forward >= -22.0 and to_target.length() <= reach and absf(to_target.y) <= reach * 0.72

func _current_damage() -> float:
	var base: float = float({"rapid": 22.0, "balanced": 27.0, "committed": 34.0}.get(motion_profile.tempo, 27.0))
	if controller.combo_index == 2: base *= 1.12
	if controller.combo_index >= 3: base *= 1.58
	if controller.attack_kind == "charge": base *= 1.88
	if controller.attack_kind == "dodge": base *= 1.24
	return base

func _on_enemy_struck(damage: float, direction: Vector2, enemy: Node2D) -> void:
	if not game_active or player_invulnerable > 0.0: return
	player_health = maxf(0.0, player_health - damage)
	player_hurt = 0.26
	player_invulnerable = 0.55
	player_position += direction * 18.0
	shake_strength = 3.0
	_play_tone("hurt")
	if player_health <= 0.0: _finish_run(false)
	if enemy.enemy_kind == ENEMY.RAM and enemy.state == "charge": enemy.force_state("recovery")

func _on_enemy_defeated(_enemy: Node2D) -> void:
	pass

func _update_waves(delta: float) -> void:
	var alive := 0
	for enemy: Node2D in enemies:
		if enemy.state != "dead": alive += 1
	if alive > 0: return
	wave_delay -= delta
	if wave_delay > 0.0: return
	if current_wave >= 3:
		_finish_run(true)
		return
	current_wave += 1
	_spawn_wave(current_wave)
	wave_delay = 0.85
	banner_label.text = "WAVE %d" % current_wave
	var tween := create_tween()
	tween.tween_interval(0.7)
	tween.tween_callback(func() -> void: if game_active: banner_label.text = "")

func _spawn_wave(wave: int) -> void:
	match wave:
		1:
			_spawn_enemy(ENEMY.PUPPET, Vector2(820, 320))
			_spawn_enemy(ENEMY.PUPPET, Vector2(950, 520))
		2:
			_spawn_enemy(ENEMY.PUPPET, Vector2(780, 250))
			_spawn_enemy(ENEMY.PUPPET, Vector2(930, 430))
			_spawn_enemy(ENEMY.PUPPET, Vector2(1080, 570))
		3:
			_spawn_enemy(ENEMY.RAM, Vector2(1010, 390))
			_spawn_enemy(ENEMY.PUPPET, Vector2(810, 260))
			_spawn_enemy(ENEMY.PUPPET, Vector2(850, 560))

func _spawn_enemy(kind: String, spawn_position: Vector2) -> Node2D:
	var enemy: Node2D = ENEMY.new()
	add_child(enemy)
	enemy.setup(kind, next_enemy_id, spawn_position)
	enemy.tell_seconds = float(get_meta("debug_tell", enemy.tell_seconds))
	enemy.recovery_seconds = float(get_meta("debug_recovery", enemy.recovery_seconds))
	next_enemy_id += 1
	enemy.player_struck.connect(_on_enemy_struck.bind(enemy))
	enemy.defeated.connect(_on_enemy_defeated)
	enemies.append(enemy)
	return enemy

func _remove_finished_dead() -> void:
	for enemy: Node2D in enemies.duplicate():
		if enemy.state == "dead" and enemy.dead_time >= 1.05:
			enemies.erase(enemy)
			enemy.queue_free()

func _cleanup_enemies() -> void:
	for enemy: Node2D in enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	enemies.clear()

func _finish_run(victory: bool) -> void:
	game_active = false
	result_state = "victory" if victory else "defeat"
	banner_label.text = "VICTORY — 请完成手感评分" if victory else "DEFEAT"
	retry_button.visible = true
	return_button.visible = true
	if victory: questionnaire_panel.visible = true

func _show_blocked(message: String) -> void:
	game_active = false
	result_state = "blocked"
	banner_label.text = message
	retry_button.visible = false
	return_button.visible = true

func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 20
	add_child(ui_layer)
	var top := ColorRect.new()
	top.position = Vector2(0, 0); top.size = Vector2(1280, 138); top.color = Color("111a24")
	ui_layer.add_child(top)
	var title := _label("FORGE COMBAT FEEL SLICE 0 — HEAVY MELEE", 24, Color("72e4e0"))
	title.position = Vector2(28, 14); top.add_child(title)
	status_label = _label("", 17, Color("d8e5ec")); status_label.position = Vector2(28, 50); status_label.size = Vector2(900, 28); status_label.clip_text = true; top.add_child(status_label)
	help_label = _label("WASD/方向键 移动　Space/J 攻击（按住蓄力）　Shift/K 闪避　F3 调试", 16, Color("b7c7d2")); help_label.position = Vector2(28, 82); top.add_child(help_label)
	var boundary := _label("当前切片只验证近战物件；持续远程与投掷返回尚未接入。", 15, Color("f5c86b")); boundary.position = Vector2(28, 110); top.add_child(boundary)
	health_label = _label("", 18, Color("ffcf70")); health_label.position = Vector2(980, 20); top.add_child(health_label)
	wave_label = _label("", 18, Color("91e0b1")); wave_label.position = Vector2(980, 50); top.add_child(wave_label)
	return_button = _button("RETURN TO FORGE", _return_to_forge); return_button.position = Vector2(1080, 88); return_button.size = Vector2(170, 38); top.add_child(return_button)
	retry_button = _button("RETRY", _start_run); retry_button.position = Vector2(965, 88); retry_button.size = Vector2(105, 38); retry_button.visible = false; top.add_child(retry_button)
	banner_label = _label("", 34, Color("ffe596")); banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; banner_label.position = Vector2(300, 160); banner_label.size = Vector2(680, 60); ui_layer.add_child(banner_label)
	debug_label = _label("", 14, Color("d9f99d")); debug_label.position = Vector2(14, 475); debug_label.size = Vector2(420, 230); debug_label.visible = false; ui_layer.add_child(debug_label)
	debug_panel = _build_debug_panel(); ui_layer.add_child(debug_panel)
	questionnaire_panel = _build_questionnaire(); ui_layer.add_child(questionnaire_panel)

func _build_debug_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = Vector2(900, 145); panel.size = Vector2(370, 550); panel.visible = false
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 3); panel.add_child(box)
	box.add_child(_label("F3 COMBAT DEBUG / TUNING", 17, Color("76e6dd")))
	_add_tuning_slider(box, "startup", 0.06, 0.45, func(value: float) -> void: motion_profile.startup_seconds = value)
	_add_tuning_slider(box, "active", 0.04, 0.22, func(value: float) -> void: motion_profile.active_seconds = value)
	_add_tuning_slider(box, "recovery", 0.10, 0.60, func(value: float) -> void: motion_profile.recovery_seconds = value)
	_add_tuning_slider(box, "combo window", 0.20, 0.80, func(value: float) -> void: motion_profile.combo_window_seconds = value)
	_add_tuning_slider(box, "input buffer", 0.10, 0.18, func(value: float) -> void: motion_profile.input_buffer_seconds = value)
	_add_tuning_slider(box, "hitstop base", 0.035, 0.115, func(value: float) -> void: set_meta("debug_hitstop", value))
	_add_tuning_slider(box, "knockback scale", 0.60, 1.80, func(value: float) -> void: set_meta("debug_knockback", value))
	_add_tuning_slider(box, "camera shake", 0.0, 2.0, func(value: float) -> void: set_meta("debug_shake", value))
	_add_tuning_slider(box, "enemy tell", 0.30, 1.10, func(value: float) -> void: set_meta("debug_tell", value))
	_add_tuning_slider(box, "enemy recovery", 0.40, 1.50, func(value: float) -> void: set_meta("debug_recovery", value))
	var save := _button("SAVE USER PRESET", _save_tuning_preset); box.add_child(save)
	return panel

func _add_tuning_slider(parent: VBoxContainer, title: String, minimum: float, maximum: float, callback: Callable) -> void:
	var row := HBoxContainer.new(); parent.add_child(row)
	var label := _label(title, 13, Color("d4e1e8")); label.custom_minimum_size = Vector2(120, 22); row.add_child(label)
	var slider := HSlider.new(); slider.min_value = minimum; slider.max_value = maximum; slider.step = 0.005; slider.value = (minimum + maximum) * 0.5; slider.custom_minimum_size = Vector2(155, 22); row.add_child(slider)
	var value_label := _label("%.3f" % slider.value, 12, Color("f0c66e")); value_label.custom_minimum_size = Vector2(55, 22); row.add_child(value_label)
	debug_slider_bindings[title] = {"slider": slider, "label": value_label}
	slider.value_changed.connect(func(value: float) -> void: value_label.text = "%.3f" % value; callback.call(value))

func _sync_debug_panel() -> void:
	var values := {
		"startup": motion_profile.startup_seconds, "active": motion_profile.active_seconds,
		"recovery": motion_profile.recovery_seconds, "combo window": motion_profile.combo_window_seconds,
		"input buffer": motion_profile.input_buffer_seconds, "hitstop base": 0.060,
		"knockback scale": 1.0, "camera shake": 1.0,
		"enemy tell": 0.55, "enemy recovery": 0.75,
	}
	for key: String in values:
		if not debug_slider_bindings.has(key): continue
		var binding: Dictionary = debug_slider_bindings[key]
		var slider := binding["slider"] as HSlider
		var label := binding["label"] as Label
		slider.set_value_no_signal(float(values[key]))
		label.text = "%.3f" % float(values[key])

func _build_questionnaire() -> PanelContainer:
	var panel := PanelContainer.new(); panel.position = Vector2(200, 150); panel.size = Vector2(880, 555); panel.visible = false
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 5); panel.add_child(box)
	box.add_child(_label("本地战斗手感问卷（1–5分）", 23, Color("71e3dc")))
	var questions: Array[String] = [
		"攻击响应：按下攻击后，角色反应及时。", "命中满足感：打中时有明显重量和反馈。",
		"连击节奏：三段攻击衔接自然。", "敌人读招：我能看懂敌人何时要攻击。",
		"物件匹配：动作符合物件外形和描述。", "区分度：它与另外两件近战物件明显不同。",
		"重玩欲望：我愿意再打一局或再造一件近战物件。"
	]
	for question: String in questions:
		var row := HBoxContainer.new(); box.add_child(row)
		var label := _label(question, 14, Color("d7e2e8")); label.custom_minimum_size = Vector2(680, 28); row.add_child(label)
		var choice := OptionButton.new(); choice.custom_minimum_size = Vector2(130, 28); choice.add_item("未选择", 0)
		for score: int in range(1, 6): choice.add_item(str(score), score)
		row.add_child(choice); rating_inputs.append(choice)
	for prompt: String in ["哪一击最爽？", "哪一击最卡？", "哪一部分最像假的？"]:
		var field := LineEdit.new(); field.placeholder_text = prompt; box.add_child(field); note_inputs.append(field)
	questionnaire_error = _label("", 13, Color("ff8b84")); box.add_child(questionnaire_error)
	box.add_child(_button("保存本地评分", _save_questionnaire))
	return panel

func _save_questionnaire() -> void:
	var scores: Array[int] = []
	for choice: OptionButton in rating_inputs:
		if choice.get_selected_id() < 1:
			questionnaire_error.text = "请完成全部七项评分。"
			return
		scores.append(choice.get_selected_id())
	var record := {
		"schema": "forge-combat-feel-slice-0-playtest-v1",
		"timestamp": Time.get_datetime_string_from_system(true),
		"fixture_or_live": fixture_id, "source_notice": source_notice,
		"identity": blueprint.source_identity, "motion_profile": motion_profile.to_dict(),
		"elapsed_seconds": snappedf(elapsed_seconds, 0.01), "scores": scores,
		"best_hit": note_inputs[0].text, "most_stuck_hit": note_inputs[1].text,
		"fake_part": note_inputs[2].text,
	}
	var path := "user://playlab/combat_feel_slice_0_events.jsonl"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null: file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		questionnaire_error.text = "保存失败：%s" % error_string(FileAccess.get_open_error())
		return
	file.seek_end(); file.store_line(JSON.stringify(record)); file.close()
	questionnaire_error.text = "已保存到本机 user://playlab/combat_feel_slice_0_events.jsonl"

func _save_tuning_preset() -> void:
	var path := "user://playlab/combat_feel_slice_0_tuning.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return
	var data: Dictionary = motion_profile.to_dict()
	data["debug_hitstop"] = get_meta("debug_hitstop", 0.060)
	data["debug_knockback"] = get_meta("debug_knockback", 1.0)
	data["debug_shake"] = get_meta("debug_shake", 1.0)
	data["debug_tell"] = get_meta("debug_tell", 0.55)
	data["debug_recovery"] = get_meta("debug_recovery", 0.75)
	file.store_string(JSON.stringify(data, "  ") + "\n"); file.close()
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(absolute): DirAccess.remove_absolute(absolute)
	DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), absolute)

func _apply_saved_tuning() -> void:
	var path := "user://playlab/combat_feel_slice_0_tuning.json"
	if not FileAccess.file_exists(path): return
	var file := FileAccess.open(path, FileAccess.READ)
	var data: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if not data is Dictionary: return
	motion_profile.startup_seconds = clampf(float(data.get("startup", motion_profile.startup_seconds)), 0.06, 0.45)
	motion_profile.active_seconds = clampf(float(data.get("active", motion_profile.active_seconds)), 0.04, 0.22)
	motion_profile.recovery_seconds = clampf(float(data.get("recovery", motion_profile.recovery_seconds)), 0.10, 0.60)
	motion_profile.combo_window_seconds = clampf(float(data.get("combo_window", motion_profile.combo_window_seconds)), 0.20, 0.80)
	motion_profile.input_buffer_seconds = clampf(float(data.get("input_buffer", motion_profile.input_buffer_seconds)), 0.10, 0.18)

func _update_hud() -> void:
	if blueprint == null or motion_profile == null: return
	status_label.text = "%s　%s　|　%s / %s / %s　|　%s" % [fixture_id, blueprint.display_name, motion_profile.motion_family, motion_profile.tempo, motion_profile.reach_class, source_notice]
	health_label.text = "PLAYER HP %d" % roundi(player_health)
	wave_label.text = "WAVE %d / 3　TIME %.1fs" % [current_wave, elapsed_seconds]

func _update_debug() -> void:
	if not debug_visible or motion_profile == null: return
	var enemy_state := "none"
	var telegraph := false
	if not enemies.is_empty():
		enemy_state = enemies[0].state
		telegraph = enemies[0].is_telegraphing()
	debug_label.text = "motion_family: %s\ncombo_index: %d\nattack_phase: %s %.0f%%\nstartup/active/recovery: %.3f / %.3f / %.3f\nbuffered_input: %s\ncharge_state: %s %.3fs\ndodge_attack_window: %.3f\nhitbox: %s %s\nweapon pivot: %s\nenemy state: %s telegraph=%s\nhitstop active: %s %.3f\nlast hit target: %s\ncurrent knockback: %.1f" % [motion_profile.motion_family, controller.combo_index, controller.phase, controller.phase_ratio() * 100.0, motion_profile.startup_seconds, motion_profile.active_seconds, motion_profile.recovery_seconds, controller.buffered_input, controller.charge_state, controller.held_seconds, controller.dodge_attack_window, motion_profile.contact_mode, motion_profile.reach_class, asset.grip_primary, enemy_state, telegraph, controller.hitstop_remaining > 0.0, controller.hitstop_remaining, last_hit_target, current_knockback]

func _update_particles(delta: float) -> void:
	for particle: Dictionary in particles:
		particle["life"] = float(particle["life"]) - delta
		particle["pos"] = Vector2(particle["pos"]) + Vector2(particle["vel"]) * delta
		particle["vel"] = Vector2(particle["vel"]) * 0.90
	particles = particles.filter(func(value: Dictionary) -> bool: return float(value["life"]) > 0.0)

func _spawn_impact(at: Vector2, scale: float) -> void:
	for index: int in range(roundi(8.0 * scale)):
		var angle := TAU * float(index) / maxf(1.0, 8.0 * scale) + randf_range(-0.18, 0.18)
		particles.append({"pos": at, "vel": Vector2.from_angle(angle) * randf_range(70.0, 170.0) * scale, "life": randf_range(0.18, 0.38), "size": randf_range(2.0, 5.0) * scale, "color": Color("ffd164") if index % 2 == 0 else Color("79e1da")})

func _build_audio() -> void:
	audio_player = AudioStreamPlayer.new(); add_child(audio_player)

func _play_tone(kind: String) -> void:
	var frequency: float = float({"windup": 180.0, "hit": 115.0, "finisher": 72.0, "dodge": 310.0, "hurt": 92.0}.get(kind, 140.0))
	var duration: float = float({"windup": 0.045, "hit": 0.08, "finisher": 0.13, "dodge": 0.055, "hurt": 0.10}.get(kind, 0.07))
	var stream := AudioStreamWAV.new(); stream.format = AudioStreamWAV.FORMAT_16_BITS; stream.mix_rate = 22050; stream.stereo = false
	var sample_count := int(stream.mix_rate * duration)
	var data := PackedByteArray(); data.resize(sample_count * 2)
	for index: int in range(sample_count):
		var envelope := 1.0 - float(index) / float(sample_count)
		var wave := sin(TAU * frequency * float(index) / float(stream.mix_rate))
		var noise := randf_range(-0.12, 0.12) if kind in ["hit", "finisher"] else 0.0
		data.encode_s16(index * 2, roundi(clampf((wave + noise) * envelope * 0.42, -1.0, 1.0) * 32767.0))
	stream.data = data; audio_player.stream = stream; audio_player.play()

func _hand_world_position() -> Vector2:
	return player_position + Vector2(20.0 * player_facing, -12.0)

func _weapon_pose() -> Dictionary:
	var angle := -0.18 * player_facing
	var extension := 0.0
	if controller.phase != "idle" or controller.holding_attack:
		var ratio: float = controller.phase_ratio()
		match motion_profile.motion_family:
			"sweep":
				var start := -1.15 if controller.combo_index != 2 else 0.95
				var finish := 0.95 if controller.combo_index != 2 else -1.05
				angle = lerpf(start, finish, ratio) * player_facing
			"slam": angle = lerpf(-1.28, 0.72, ratio) * player_facing
			"thrust":
				angle = -0.08 * player_facing
				extension = sin(ratio * PI) * 32.0
	return {"angle": angle, "extension": extension}

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color("071018"), true)
	draw_rect(ARENA, Color("172734"), true)
	draw_rect(ARENA, Color("405864"), false, 3.0)
	for x: int in range(60, 1240, 80): draw_line(Vector2(x, ARENA.position.y), Vector2(x, ARENA.end.y), Color(0.28, 0.42, 0.47, 0.18), 1.0)
	for y: int in range(170, 680, 64): draw_line(Vector2(ARENA.position.x, y), Vector2(ARENA.end.x, y), Color(0.28, 0.42, 0.47, 0.14), 1.0)
	draw_line(Vector2(50, 655), Vector2(1230, 655), Color("896b3a"), 5.0)
	if capture_comparison: _draw_fixture_comparison()
	else: _draw_player()
	for particle: Dictionary in particles: draw_circle(Vector2(particle["pos"]), float(particle["size"]), Color(particle["color"]))
	if motion_profile != null and controller.phase == "active": _draw_active_hitbox()

func _draw_player() -> void:
	if asset == null: return
	var hurt_color := Color("ff8d84") if player_hurt > 0.0 else Color("58cbd2")
	var run_bob := sin(elapsed_seconds * 12.0) * 2.0 if Input.get_vector("move_left", "move_right", "move_up", "move_down").length() > 0.1 else 0.0
	var base := player_position + Vector2(0, run_bob)
	draw_circle(base + Vector2(0, -29), 13.0, Color("e4c8a8"))
	draw_colored_polygon(PackedVector2Array([base + Vector2(-16, -15), base + Vector2(14, -15), base + Vector2(20, 25), base + Vector2(-18, 25)]), hurt_color)
	draw_colored_polygon(PackedVector2Array([base + Vector2(-16, -20), base + Vector2(4, -45), base + Vector2(16, -22)]), Color("d3843e"))
	draw_circle(base + Vector2(7 * player_facing, -31), 4.0, Color("b8f4ee"))
	var leg_spread := 7.0 if controller.dodge_motion_seconds <= 0.0 else 14.0
	draw_line(base + Vector2(-7, 22), base + Vector2(-leg_spread, 45), Color("7f93a2"), 8.0)
	draw_line(base + Vector2(7, 22), base + Vector2(leg_spread, 45), Color("7f93a2"), 8.0)
	var hand := _hand_world_position()
	var secondary_delta := (asset.grip_secondary - asset.grip_primary) * 1.10
	var second_hand := hand + Vector2(secondary_delta.x * player_facing, secondary_delta.y)
	draw_line(base + Vector2(8 * player_facing, -8), hand, Color("e4c8a8"), 7.0)
	if motion_profile.grip_mode == "two_hand": draw_line(base + Vector2(-5 * player_facing, -6), second_hand, Color("e4c8a8"), 7.0)
	var pose := _weapon_pose()
	var weapon_origin := hand + Vector2(float(pose["extension"]) * player_facing, 0)
	draw_set_transform(weapon_origin, float(pose["angle"]), Vector2(player_facing * 1.18, 1.18))
	draw_texture_rect(asset.texture, Rect2(-asset.grip_primary, Vector2(asset.canvas_size)), false)
	draw_set_transform(Vector2.ZERO)
	draw_circle(hand, 4.0, Color("f6d1ac"))

func _draw_active_hitbox() -> void:
	var hand := _hand_world_position()
	var timing: Dictionary = motion_profile.timing_for(controller.attack_kind, controller.combo_index)
	var reach: float = motion_profile.reach_pixels * float(timing.get("reach_scale", 1.0))
	var color := Color(1.0, 0.38, 0.22, 0.34)
	match motion_profile.motion_family:
		"thrust": draw_rect(Rect2(hand + Vector2(0 if player_facing > 0 else -reach, -25), Vector2(reach, 50)), color, true)
		"slam": draw_circle(hand + Vector2(player_facing * reach * 0.68, 28), 50.0, color)
		_: draw_arc(hand, reach, -0.75 if player_facing > 0 else PI - 0.75, 0.75 if player_facing > 0 else PI + 0.75, 30, color, 18.0)

func _draw_fixture_comparison() -> void:
	var ids: Array[String] = ["M01", "M02", "M03"]
	if comparison_assets.is_empty():
		for id: String in ids:
			var retained: Dictionary = asset_loader.load_fixture(id)
			var retained_asset := retained.get("asset") as WeaponVisualAsset
			comparison_assets.append(retained_asset)
			comparison_profiles.append(compiler.compile(retained.get("blueprint") as WeaponBlueprint, retained_asset))
	for index: int in range(ids.size()):
		var fixture_asset: WeaponVisualAsset = comparison_assets[index]
		var profile: Resource = comparison_profiles[index]
		var player_at := Vector2(135 + index * 390, 435)
		var hand := player_at + Vector2(23, -12)
		draw_circle(player_at + Vector2(0, -28), 12, Color("e4c8a8"))
		draw_colored_polygon(PackedVector2Array([player_at + Vector2(-14, -14), player_at + Vector2(14, -14), player_at + Vector2(18, 24), player_at + Vector2(-17, 24)]), Color("58cbd2"))
		draw_line(player_at + Vector2(-7, 23), player_at + Vector2(-11, 44), Color("7f93a2"), 7)
		draw_line(player_at + Vector2(7, 23), player_at + Vector2(11, 44), Color("7f93a2"), 7)
		draw_line(player_at + Vector2(5, -6), hand, Color("e4c8a8"), 6)
		draw_set_transform(hand, -0.18 + index * 0.18, Vector2(1.5, 1.5))
		draw_texture_rect(fixture_asset.texture, Rect2(-fixture_asset.grip_primary, Vector2(fixture_asset.canvas_size)), false)
		draw_set_transform(Vector2.ZERO)
		if profile.motion_family == "slam":
			draw_circle(hand + Vector2(135, 45), 34, Color(1.0, 0.35, 0.2, 0.18))
		else:
			draw_arc(hand, 135, -0.72, 0.72, 24, Color(1.0, 0.35, 0.2, 0.32), 10)
		draw_string(ThemeDB.fallback_font, player_at + Vector2(-35, 100), "%s  %s" % [ids[index], profile.motion_family], HORIZONTAL_ALIGNMENT_CENTER, 210, 22, Color("f5dc8c"))

func _capture_evidence(directory: String) -> void:
	game_active = false
	DirAccess.make_dir_recursive_absolute(directory)
	_cleanup_enemies()
	var puppet: Node2D = _spawn_enemy(ENEMY.PUPPET, Vector2(760, 410)); puppet.force_state("tell")
	capture_caption = "Slag Puppet telegraph"; await _capture_frame(directory.path_join("slag_puppet_telegraph.png"))
	_cleanup_enemies()
	var ram: Node2D = _spawn_enemy(ENEMY.RAM, Vector2(790, 410)); ram.force_state("tell")
	capture_caption = "Forge Ram charge telegraph"; await _capture_frame(directory.path_join("forge_ram_telegraph.png"))
	_cleanup_enemies()
	var hit_enemy: Node2D = _spawn_enemy(ENEMY.PUPPET, Vector2(520, 410)); hit_enemy.flash_time = 0.4; _spawn_impact(hit_enemy.position, 1.0)
	controller.attack_kind = "normal"; controller.combo_index = 1; controller.phase = "active"; controller.phase_duration = 0.1
	capture_caption = "Normal hit"; await _capture_frame(directory.path_join("normal_hit_feedback.png"))
	hit_enemy.flash_time = 0.4; _spawn_impact(hit_enemy.position, 1.65); controller.combo_index = 3; shake_strength = 0.0
	capture_caption = "Third-hit finisher"; await _capture_frame(directory.path_join("third_hit_feedback.png"))
	_cleanup_enemies(); particles.clear(); controller.phase = "idle"; capture_comparison = true; capture_caption = "Three fixture holding/attack comparison"
	await _capture_frame(directory.path_join("three_weapon_comparison.png"))
	get_tree().quit()

func _capture_frame(path: String) -> void:
	banner_label.text = capture_caption
	queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)

func _quit_after(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	get_tree().quit()

func _return_to_forge() -> void:
	get_tree().change_scene_to_file("res://scenes/open_identity_spike.tscn")

func _label(text_value: String, size_value: int, color: Color) -> Label:
	var label := Label.new(); label.text = text_value; label.add_theme_font_size_override("font_size", size_value); label.modulate = color
	return label

func _button(text_value: String, callback: Callable) -> Button:
	var button := Button.new(); button.text = text_value; button.pressed.connect(callback); return button

func _argument_value(prefix: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix): return argument.trim_prefix(prefix)
	return fallback
