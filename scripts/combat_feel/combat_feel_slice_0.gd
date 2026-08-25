class_name CombatFeelSlice0
extends Node2D

const ARENA := Rect2(38, 145, 1204, 532)
const ASSET_LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")
const MOTION_COMPILER := preload("res://scripts/combat_feel/melee_motion_compiler.gd")
const CONTROLLER := preload("res://scripts/combat_feel/melee_combat_controller.gd")
const ENEMY := preload("res://scripts/combat_feel/combat_feel_enemy.gd")
const FEEDBACK := preload("res://scripts/combat_feel/impact_feedback_profile.gd")
const AB_COMPARE := preload("res://scripts/combat_feel/ab_comparison.gd")
const MOTION_PRIMITIVE := preload("res://scripts/combat_feel/motion_primitive.gd")

var asset_loader: Variant
var compiler: Variant
var controller: Variant
var blueprint: WeaponBlueprint
var asset: WeaponVisualAsset
var affordance_profile: Resource
var motion_profile: Variant
var source_notice := ""
var weapon_id := "giant_wooden_spoon"
var is_developer_fixture := false
var launched_from_open_playtest := false

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
var camera_kick := Vector2.ZERO
var last_hit_target := "none"
var current_knockback := 0.0
var attack_connected := false
var capture_comparison := false
var capture_caption := ""
var pending_attack_input_msec := -1
var input_to_visual_ms := -1
var input_to_active_ms := -1
var normal_attack_attempts: Dictionary = {1: 0, 2: 0, 3: 0}
var normal_attack_hits: Dictionary = {1: 0, 2: 0, 3: 0}
var normal_attack_whiffs: Dictionary = {1: 0, 2: 0, 3: 0}
var blind_comparison := false
var blind_label := ""
var blind_run_completed := false
var blind_result_path := ""
var blind_suite := "slice_1a"
var capture_pose_only := false
var compare_profiles: Array = []
var compare_labels: PackedStringArray = []
var compare_index := 0
var compare_rows: Array = []
var compare_label: Label

var ui_layer: CanvasLayer
var title_label: Label
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
	blind_comparison = _argument_value("--blind-comparison=", "false").to_lower() in ["1", "true", "yes"]
	blind_label = _argument_value("--blind-label=", "").to_upper()
	blind_result_path = _argument_value("--blind-result-path=", "")
	blind_suite = _argument_value("--blind-suite=", "slice_1a")
	asset_loader = ASSET_LOADER.new()
	compiler = MOTION_COMPILER.new()
	controller = CONTROLLER.new()
	controller.attack_started.connect(_on_attack_started)
	controller.phase_changed.connect(_on_attack_phase_changed)
	_build_ui()
	_build_audio()
	if not _load_requested_weapon():
		_show_blocked("无法进入：%s" % source_notice)
		return
	var compiled: Variant = _compile_loaded_weapon()
	if compiled is String and str(compiled) == MOTION_COMPILER.UNSUPPORTED:
		_show_blocked(MOTION_COMPILER.UNSUPPORTED)
		return
	motion_profile = compiled
	_setup_comparison()
	_update_mode_title()
	controller.configure(motion_profile)
	_apply_saved_tuning()
	_sync_debug_panel()
	_start_run()
	var smoke_seconds := float(_argument_value("--smoke-seconds=", "0"))
	if smoke_seconds > 0.0: _quit_after(smoke_seconds)
	var capture_dir := _argument_value("--capture-dir=", "")
	var pose_capture_dir := _argument_value("--pose-capture-dir=", "")
	if not pose_capture_dir.is_empty(): call_deferred("_capture_pose_visibility", pose_capture_dir)
	elif not capture_dir.is_empty(): call_deferred("_capture_evidence", capture_dir)


## Two profiles in one session, swapped instantly, so a judgement is made against the other
## side rather than against a memory from before a relaunch. Three rounds of comparing
## across relaunches could not tell a sweep from a bash, which says more about the protocol
## than about anything being compared.
func _setup_comparison() -> void:
	var against := _argument_value("--compare-with=", "")
	var calibration := _has_argument("--compare-calibration")
	if against.is_empty() and not calibration:
		return
	var other: Variant = _calibration_profile() if calibration else _compare_asset_profile(against)
	if other == null:
		source_notice = "COMPARE_TARGET_UNAVAILABLE"
		return
	compare_profiles = [motion_profile, other]
	compare_labels = PackedStringArray(["A  %s" % weapon_id, "B  %s" % ("calibration" if calibration else against)])
	compare_rows = AB_COMPARE.differences(compare_profiles[0], compare_profiles[1])
	_refresh_compare_label()


## A second real asset, compiled against this one's anchors so only the affordance differs.
func _compare_asset_profile(asset_id: String) -> Variant:
	var loaded: Dictionary = asset_loader.load_motion_grammar_asset(asset_id)
	if not bool(loaded.get("ok", false)):
		loaded = asset_loader.load_recipe_asset(asset_id)
	if not bool(loaded.get("ok", false)):
		return null
	var affordance: Variant = loaded.get("affordance_profile")
	if affordance == null:
		return null
	var compiled: Variant = compiler.compile(affordance, asset.anchors_dict(), asset.opaque_bounds)
	return null if compiled is String else compiled


## A deliberately absurd counterpart, for finding out whether the protocol can detect
## anything at all before it is trusted to detect something subtle. If this pair is
## indistinguishable the problem is the setup, not the design.
func _calibration_profile() -> Variant:
	if affordance_profile == null:
		return null
	var extreme: Variant = affordance_profile.duplicate()
	extreme.contact_surface = "point" if str(affordance_profile.contact_surface) != "point" else "whole_body"
	extreme.secondary_contact_surface = "none"
	extreme.rigidity = "flexible" if str(affordance_profile.rigidity) != "flexible" else "rigid"
	extreme.grip_topology = "body_grip" if str(affordance_profile.grip_topology) != "body_grip" else "two_hand_handle"
	extreme.handle_length = "none" if extreme.grip_topology == "body_grip" else affordance_profile.handle_length
	extreme.has_point = true
	extreme.real_mass_kg = maxf(0.15, float(affordance_profile.real_mass_kg) * 0.2)
	var compiled: Variant = compiler.compile(extreme, asset.anchors_dict(), asset.opaque_bounds)
	return null if compiled is String else compiled


func _swap_comparison() -> void:
	if compare_profiles.size() < 2:
		return
	compare_index = 1 - compare_index
	motion_profile = compare_profiles[compare_index]
	controller.configure(motion_profile)
	_update_mode_title()
	_refresh_compare_label()


func _refresh_compare_label() -> void:
	if compare_label == null or compare_profiles.size() < 2:
		return
	var text := "%s          [Q] 切换
" % compare_labels[compare_index]
	if compare_rows.is_empty():
		text += "两侧编译结果完全相同 —— 这一对测不出任何东西"
	else:
		for row: Dictionary in compare_rows:
			text += "%s  %s
" % [str(row["channel"]).rpad(20), row["detail"]]
	compare_label.text = text


func _compile_loaded_weapon() -> Variant:
	if affordance_profile != null:
		return compiler.compile(affordance_profile, asset.anchors_dict(), asset.opaque_bounds)
	return compiler.compile(blueprint, asset)

func _load_requested_weapon() -> bool:
	var sprite_path := _argument_value("--combat-sprite=", "")
	var blueprint_path := _argument_value("--combat-blueprint=", "")
	var anchors_path := _argument_value("--combat-anchors=", "")
	var open_round_path := _argument_value("--open-playtest-round=", "")
	var requested_generalization_id := _argument_value("--generalization-asset=", "")
	var requested_motion_grammar_id := _argument_value("--motion-grammar-asset=", "")
	var requested_recipe_id := _argument_value("--recipe-asset=", "")
	var requested_live_id := _argument_value("--live-weapon=", "")
	var requested_fixture := _argument_value("--developer-fixture=", "").to_upper()
	var result: Dictionary
	if not requested_generalization_id.is_empty():
		result = asset_loader.load_generalization_asset(requested_generalization_id)
	elif not requested_motion_grammar_id.is_empty():
		result = asset_loader.load_motion_grammar_asset(requested_motion_grammar_id)
	elif not requested_recipe_id.is_empty():
		result = asset_loader.load_recipe_asset(requested_recipe_id)
	elif not sprite_path.is_empty() or not blueprint_path.is_empty() or not anchors_path.is_empty():
		result = asset_loader.load_live(sprite_path, blueprint_path, anchors_path)
	elif not open_round_path.is_empty():
		launched_from_open_playtest = true
		result = asset_loader.load_open_playtest_round(open_round_path, _has_argument("--require-affordance-grammar"))
	elif not requested_fixture.is_empty():
		result = asset_loader.load_fixture(requested_fixture)
	elif requested_live_id.is_empty():
		result = asset_loader.load_default_live()
	else:
		result = asset_loader.load_frozen_live(requested_live_id)
	if not bool(result.get("ok", false)):
		source_notice = str(result.get("error", "LOAD_FAILED"))
		return false
	# Playtest hook: swap in a profile that carries real_length_cm without touching the
	# frozen, hash-pinned one. Resolved before blueprint/asset are assigned so a bad path
	# leaves exactly the same state as any other failed load -- assigning them first and
	# then returning false leaves the scene half-built, and _draw_player spams
	# "render_scale on Nil" every frame instead of failing once.
	var affordance_override_path := _argument_value("--combat-affordance=", "")
	var override_profile: Resource = null
	if not affordance_override_path.is_empty():
		override_profile = asset_loader.load_affordance_override(affordance_override_path)
		if override_profile == null:
			source_notice = "AFFORDANCE_OVERRIDE_INVALID:%s" % affordance_override_path
			return false
	blueprint = result.get("blueprint") as WeaponBlueprint
	asset = result.get("asset") as WeaponVisualAsset
	affordance_profile = result.get("affordance_profile") as Resource
	source_notice = str(result.get("notice", ""))
	if override_profile != null:
		# Marked unverified: this bypasses the index hash checks by design.
		affordance_profile = override_profile
		source_notice = "DEV AFFORDANCE OVERRIDE (unverified): %s" % affordance_override_path
	weapon_id = str(result.get("asset_id", result.get("fixture_id", weapon_id)))
	is_developer_fixture = bool(result.get("fixture", false))
	if blueprint == null or asset == null:
		source_notice = "WEAPON_HANDOFF_INCOMPLETE"
		return false
	if blueprint.behavior_family != "heavy_melee":
		source_notice = "当前切片只验证近战物件。持续远程与投掷返回尚未接入。"
		return false
	if launched_from_open_playtest and return_button != null:
		return_button.text = "CLOSE / RETURN TO OPEN PLAYTEST"
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
	pending_attack_input_msec = -1
	input_to_visual_ms = -1
	input_to_active_ms = -1
	_reset_normal_attack_stats()
	blind_run_completed = false
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
	camera_kick = camera_kick.move_toward(Vector2.ZERO, 34.0 * delta)
	var shake_offset := Vector2(randf_range(-shake_strength, shake_strength), randf_range(-shake_strength, shake_strength)) if shake_strength > 0.05 else Vector2.ZERO
	position = shake_offset + camera_kick
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

## Q rather than TAB, and _input rather than _unhandled_input. TAB is bound to
## ui_focus_next by default, so the focus system eats it before gameplay ever sees it --
## which a headless smoke test cannot show, because it only proves the script parses.
func _input(event: InputEvent) -> void:
	if compare_profiles.size() < 2:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Q:
		_swap_comparison()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug") and not blind_comparison:
		debug_visible = not debug_visible
		debug_label.visible = debug_visible
		debug_panel.visible = debug_visible
		get_viewport().set_input_as_handled()
		return
	if not game_active: return
	if event.is_action_pressed("attack"):
		pending_attack_input_msec = Time.get_ticks_msec()
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
		if controller.phase in ["startup", "active"]:
			var primitive: Variant = _current_attack_primitive()
			speed *= float(primitive.movement_allowed_ratio) if primitive != null else motion_profile.movement_commitment
		player_position += input_vector * speed * delta
		if absf(input_vector.x) > 0.05: player_facing = signf(input_vector.x)
	player_position.x = clampf(player_position.x, ARENA.position.x + 30.0, ARENA.end.x - 30.0)
	player_position.y = clampf(player_position.y, ARENA.position.y + 52.0, ARENA.end.y - 28.0)

func _on_attack_started(kind: String, combo_index: int) -> void:
	attack_connected = false
	if kind == "normal" and combo_index in [1, 2, 3]:
		normal_attack_attempts[combo_index] = int(normal_attack_attempts.get(combo_index, 0)) + 1
	var timing: Dictionary = controller.current_timing()
	var primitive: Variant = controller.current_primitive
	var advance: float = float(primitive.root_motion_distance) if primitive != null else 17.0 * float(timing.get("movement_scale", 1.0))
	player_position.x += advance * player_facing
	_play_tone("swing_heavy" if kind == "charge" or combo_index >= 3 or motion_profile.tempo == "committed" else "swing_light")

func _on_attack_phase_changed(next_phase: String) -> void:
	if next_phase == "startup" and pending_attack_input_msec >= 0:
		input_to_visual_ms = maxi(0, Time.get_ticks_msec() - pending_attack_input_msec)
	if next_phase == "active" and pending_attack_input_msec >= 0:
		input_to_active_ms = maxi(0, Time.get_ticks_msec() - pending_attack_input_msec)
		pending_attack_input_msec = -1
	if next_phase == "recovery" and not attack_connected:
		if controller.attack_kind == "normal" and controller.combo_index in [1, 2, 3]:
			normal_attack_whiffs[controller.combo_index] = int(normal_attack_whiffs.get(controller.combo_index, 0)) + 1
		_play_tone("whiff")

func _resolve_melee_hits() -> void:
	for enemy: Node2D in enemies:
		if enemy.state == "dead": continue
		if not _attack_contains(enemy.position): continue
		if not controller.register_hit(enemy.enemy_id): continue
		if not attack_connected:
			# Once per swing, on the first thing it touches.
			player_position.x += float(controller.contact_displacement_pixels) * player_facing
		var feedback: Resource = FEEDBACK.for_attack(motion_profile, controller.attack_kind, controller.combo_index, controller.current_primitive)
		var finisher_scale := 1.45 if controller.combo_index >= 3 or controller.attack_kind == "charge" else 1.0
		if has_meta("debug_hitstop"):
			feedback.hitstop_seconds = float(get_meta("debug_hitstop")) * finisher_scale
		feedback.knockback_strength *= float(get_meta("debug_knockback", 1.0))
		feedback.camera_shake_strength *= float(get_meta("debug_shake", 1.0))
		var damage := _current_damage()
		var direction: Vector2 = (enemy.position - player_position).normalized()
		if direction.length() < 0.1: direction = Vector2(player_facing, 0)
		var knockback: Vector2 = direction * float(feedback.knockback_strength) + Vector2(0, -float(feedback.launch_strength))
		enemy.apply_hit(damage, knockback, feedback.stagger_strength, feedback.recoil_degrees)
		controller.begin_hitstop(feedback.hitstop_seconds)
		shake_strength = maxf(shake_strength, feedback.camera_shake_strength)
		camera_kick = Vector2(-player_facing * feedback.camera_shake_strength * 0.72, -feedback.camera_shake_strength * 0.18)
		last_hit_target = "%s:%d" % [enemy.enemy_kind, enemy.enemy_id]
		current_knockback = feedback.knockback_strength
		if not attack_connected and controller.attack_kind == "normal" and controller.combo_index in [1, 2, 3]:
			normal_attack_hits[controller.combo_index] = int(normal_attack_hits.get(controller.combo_index, 0)) + 1
		attack_connected = true
		_spawn_impact(enemy.position, feedback.particle_scale, feedback.impact_tier, feedback.ring_count)
		_play_tone(str(feedback.sound_profile))

func _attack_contains(target: Vector2) -> bool:
	var hand := _hand_world_position()
	var to_target := target - hand
	var primitive: Variant = _current_attack_primitive()
	if primitive == null:
		return false
	var timing: Dictionary = controller.current_timing()
	var hitbox_length_scale: float = float(primitive.hitbox_length_multiplier) if primitive != null else 1.0
	var reach: float = motion_profile.reach_pixels * float(timing.get("reach_scale", 1.0)) * hitbox_length_scale
	var hitbox_scale: float = float(primitive.hitbox_multiplier) * float(primitive.hitbox_width_multiplier) if primitive != null else 1.0
	var hitbox_thickness: float = motion_profile.hitbox_thickness * hitbox_scale
	var motion_family: String = str(primitive.motion_family)
	var forward := to_target.x * player_facing
	var contact_world := _primitive_contact_world(primitive, hand) if primitive != null else hand + Vector2(player_facing * reach * 0.72, 0.0)
	match motion_family:
		"bash":
			return target.distance_to(contact_world) <= hitbox_thickness * 0.58
		"thrust":
			return _thrust_hitbox_rect(hand, reach, hitbox_thickness, primitive).has_point(target)
		"slam":
			return target.distance_to(contact_world) <= hitbox_thickness + (16.0 if controller.attack_kind == "charge" else 0.0)
		"spin":
			return to_target.length() <= reach
		_:
			var half_arc := deg_to_rad(motion_profile.swing_arc_degrees * 0.5)
			var angle := absf(wrapf(to_target.angle() - (0.0 if player_facing > 0 else PI), -PI, PI))
			return forward >= -hitbox_thickness * 0.45 and to_target.length() <= reach and angle <= half_arc


func _thrust_rear_tolerance(primitive: Variant, hitbox_thickness: float) -> float:
	if primitive == null:
		return 12.0
	return minf(36.0, float(primitive.root_motion_distance) * 0.60 + hitbox_thickness * 0.25)


func _thrust_hitbox_rect(hand: Vector2, reach: float, hitbox_thickness: float, primitive: Variant) -> Rect2:
	var rear_tolerance := _thrust_rear_tolerance(primitive, hitbox_thickness)
	var left := hand.x - rear_tolerance if player_facing > 0.0 else hand.x - reach
	return Rect2(Vector2(left, hand.y - hitbox_thickness * 0.5), Vector2(reach + rear_tolerance, hitbox_thickness))


func _reset_normal_attack_stats() -> void:
	normal_attack_attempts = {1: 0, 2: 0, 3: 0}
	normal_attack_hits = {1: 0, 2: 0, 3: 0}
	normal_attack_whiffs = {1: 0, 2: 0, 3: 0}


func _normal_attack_stats() -> Dictionary:
	return {
		"attempts": normal_attack_attempts.duplicate(true),
		"hits": normal_attack_hits.duplicate(true),
		"whiffs": normal_attack_whiffs.duplicate(true),
	}

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
	blind_run_completed = blind_comparison and victory
	if blind_comparison:
		banner_label.text = "BLIND %s COMPLETE" % blind_label if victory else "BLIND %s DEFEAT — RETRY OR ABORT" % blind_label
		questionnaire_panel.visible = false
		return_button.text = "COMPLETE BLIND %s" % blind_label if victory else "ABORT BLIND %s" % blind_label
		if victory:
			_write_blind_run_result()
	else:
		banner_label.text = "VICTORY — 请完成手感评分" if victory else "DEFEAT"
	retry_button.visible = true
	return_button.visible = true
	if victory and not blind_comparison: questionnaire_panel.visible = true

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
	title_label = _label("COMBAT FEEL SLICE 0 — HEAVY MELEE", 24, Color("72e4e0"))
	title_label.position = Vector2(28, 14); top.add_child(title_label)
	compare_label = _label("", 15, Color("f0c674"))
	compare_label.position = Vector2(28, 52); top.add_child(compare_label)
	status_label = _label("", 15, Color("d8e5ec")); status_label.position = Vector2(28, 46); status_label.size = Vector2(930, 48); top.add_child(status_label)
	help_label = _label("WASD/方向键 移动　Space/J 攻击（按住蓄力）　Shift/K 闪避　F3 调试", 15, Color("b7c7d2")); help_label.position = Vector2(28, 94); top.add_child(help_label)
	var boundary := _label("当前切片只验证近战物件；持续远程与投掷返回尚未接入。", 14, Color("f5c86b")); boundary.position = Vector2(28, 116); top.add_child(boundary)
	health_label = _label("", 18, Color("ffcf70")); health_label.position = Vector2(980, 20); top.add_child(health_label)
	wave_label = _label("", 18, Color("91e0b1")); wave_label.position = Vector2(980, 50); top.add_child(wave_label)
	return_button = _button("RETURN TO FORGE", _return_to_forge); return_button.position = Vector2(1080, 88); return_button.size = Vector2(170, 38); top.add_child(return_button)
	retry_button = _button("RETRY", _start_run); retry_button.position = Vector2(965, 88); retry_button.size = Vector2(105, 38); retry_button.visible = false; top.add_child(retry_button)
	banner_label = _label("", 34, Color("ffe596")); banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; banner_label.position = Vector2(300, 160); banner_label.size = Vector2(680, 60); ui_layer.add_child(banner_label)
	debug_label = _label("", 14, Color("d9f99d")); debug_label.position = Vector2(14, 475); debug_label.size = Vector2(420, 230); debug_label.visible = false; ui_layer.add_child(debug_label)
	debug_panel = _build_debug_panel(); ui_layer.add_child(debug_panel)
	questionnaire_panel = _build_questionnaire(); ui_layer.add_child(questionnaire_panel)


func _update_mode_title() -> void:
	if title_label == null:
		return
	if blind_comparison:
		title_label.text = "MOTION GRAMMAR GENERALIZATION — BLIND %s" % blind_label \
			if blind_suite == "generalization_v1" else "MOTION GRAMMAR SLICE 1A — BLIND %s" % blind_label
		return
	var labels := {
		"frying_pan": "PAN",
		"old_mop": "BROOM / MOP",
		"shotgun_melee": "SHOTGUN STOCK MELEE — DEV OVERRIDE",
		"giant_wooden_spoon": "GIANT WOODEN SPOON",
		"LIVE": "LIVE OPEN PLAYTEST WEAPON",
	}
	title_label.text = "MOTION GRAMMAR SLICE 1A — %s" % str(labels.get(weapon_id, weapon_id.to_upper()))

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
		"weapon_asset_id": weapon_id, "source_notice": source_notice,
		"developer_fixture": is_developer_fixture,
		"identity": blueprint.source_identity, "motion_profile": motion_profile.to_dict(),
		"elapsed_seconds": snappedf(elapsed_seconds, 0.01), "scores": scores,
		"input_to_visual_ms": input_to_visual_ms, "input_to_active_ms": input_to_active_ms,
		"normal_attack_stats": _normal_attack_stats(),
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
	if blind_comparison:
		status_label.text = "BLIND %s  |  REAL GENERATED SPRITE  |  identity, Recipe and Affordance hidden\nComplete all three waves, then answer the five comparison questions in PowerShell." % blind_label
		health_label.text = "PLAYER HP %d" % roundi(player_health)
		wave_label.text = "WAVE %d / 3  TIME %.1fs" % [current_wave, elapsed_seconds]
		return
	var recipe: Variant = motion_profile.combo_recipe
	var sequence: PackedStringArray = recipe.primitive_sequence() if recipe != null else PackedStringArray(["missing", "missing", "missing"])
	status_label.text = "ASSET %s  |  ACTUAL RECIPE  %s → %s → %s  |  reach %.0f px  |  tempo %s\nHit 1 %s  |  Hit 2 %s  |  Hit 3 %s" % [weapon_id, sequence[0], sequence[1], sequence[2], motion_profile.reach_pixels, motion_profile.tempo, sequence[0], sequence[1], sequence[2]]
	health_label.text = "PLAYER HP %d" % roundi(player_health)
	wave_label.text = "WAVE %d / 3　TIME %.1fs" % [current_wave, elapsed_seconds]

func _update_debug() -> void:
	if not debug_visible or motion_profile == null: return
	var enemy_state := "none"
	var telegraph := false
	if not enemies.is_empty():
		enemy_state = enemies[0].state
		telegraph = enemies[0].is_telegraphing()
	var primitive: Variant = _current_attack_primitive()
	var current_family := str(primitive.motion_family) if primitive != null else "idle"
	debug_label.text = "current_primitive: %s\ncombo_index: %d\nattack_phase: %s %.0f%%\nstartup/active/recovery: %.3f / %.3f / %.3f\nbuffered_input: %s\ncharge_state: %s %.3fs\ndodge_attack_window: %.3f\ninput visual/active: %d / %d ms\nnormal attempts/hits/whiffs: %s / %s / %s\nhitbox: %s %s\nweapon pivot: %s\nenemy state: %s telegraph=%s\nhitstop active: %s %.3f\nlast hit target: %s\ncurrent knockback: %.1f" % [current_family, controller.combo_index, controller.phase, controller.phase_ratio() * 100.0, motion_profile.startup_seconds, motion_profile.active_seconds, motion_profile.recovery_seconds, controller.buffered_input, controller.charge_state, controller.held_seconds, controller.dodge_attack_window, input_to_visual_ms, input_to_active_ms, normal_attack_attempts, normal_attack_hits, normal_attack_whiffs, motion_profile.contact_mode, motion_profile.reach_class, asset.grip_primary, enemy_state, telegraph, controller.hitstop_remaining > 0.0, controller.hitstop_remaining, last_hit_target, current_knockback]

func _update_particles(delta: float) -> void:
	for particle: Dictionary in particles:
		particle["life"] = float(particle["life"]) - delta
		if str(particle.get("kind", "spark")) == "ring":
			particle["radius"] = float(particle.get("radius", 4.0)) + float(particle.get("speed", 90.0)) * delta
		else:
			particle["pos"] = Vector2(particle["pos"]) + Vector2(particle["vel"]) * delta
			particle["vel"] = Vector2(particle["vel"]) * 0.90
	particles = particles.filter(func(value: Dictionary) -> bool: return float(value["life"]) > 0.0)

func _spawn_impact(at: Vector2, scale: float, tier: String = "light", ring_count: int = 0) -> void:
	var count := roundi((7.0 if tier == "light" else 10.0) * scale)
	var speed_min := 85.0 if tier == "light" else 125.0
	var speed_max := 175.0 if tier == "light" else 255.0
	for index: int in range(count):
		var angle := TAU * float(index) / maxf(1.0, float(count)) + randf_range(-0.18, 0.18)
		var color := Color("fff0a8") if tier == "light" else (Color("ff9f43") if index % 2 == 0 else Color("7cf4e8"))
		particles.append({"kind": "spark", "pos": at, "vel": Vector2.from_angle(angle) * randf_range(speed_min, speed_max) * scale, "life": randf_range(0.16, 0.34) * minf(scale, 1.7), "size": randf_range(1.7, 4.2) * scale, "color": color})
	for ring_index: int in range(ring_count):
		particles.append({"kind": "ring", "pos": at, "radius": 7.0 + ring_index * 9.0, "speed": 135.0 + ring_index * 35.0, "life": 0.24 + ring_index * 0.05, "size": 4.5 - ring_index, "color": Color("ffe08a") if ring_index == 0 else Color("66e9e1")})

func _build_audio() -> void:
	audio_player = AudioStreamPlayer.new(); add_child(audio_player)

func _play_tone(kind: String) -> void:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	stream.data = FEEDBACK.synthesise(kind, stream.mix_rate)
	audio_player.stream = stream
	audio_player.play()


func _attack_motion_ratio() -> float:
	# The controller owns this now, because after a hit the path depends on what the
	# object is made of and only the controller knows a hit has landed.
	return 0.0 if controller == null else float(controller.swing_progress())


func _character_pose() -> Dictionary:
	var result := {
		"body_offset": Vector2.ZERO,
		"hand_local": Vector2(20.0, -12.0),
		"torso_rotation": 0.0,
		"crouch": 0.0,
		"head_tilt": 0.0,
		"main_shoulder_local": Vector2(9.0, -8.0),
		"main_elbow_local": Vector2(16.0, -5.0),
		"support_shoulder_local": Vector2(-6.0, -6.0),
		"support_elbow_local": Vector2(7.0, -1.0),
		"back_foot_local": Vector2(-9.0, 45.0),
		"front_foot_local": Vector2(10.0, 45.0),
	}
	var primitive: Variant = _current_attack_primitive()
	if primitive == null:
		return result
	var motion_ratio := _attack_motion_ratio()
	var contact := smoothstep(0.22, 0.62, motion_ratio)
	var recovery := smoothstep(0.82, 1.0, motion_ratio)
	var pose_weight := 1.0 - recovery
	match str(primitive.motion_family):
		"sweep":
			result.body_offset = Vector2(lerpf(-5.0, 8.0, contact) * player_facing, 0.0)
			result.hand_local = Vector2(-6.0, -23.0).lerp(Vector2(34.0, -3.0), contact)
			result.torso_rotation = lerpf(-0.30, 0.42, contact) * player_facing
			result.head_tilt = result.torso_rotation * 0.45
			result.main_elbow_local = Vector2(-2.0, -16.0).lerp(Vector2(23.0, 3.0), contact)
			result.support_elbow_local = Vector2(-9.0, -7.0).lerp(Vector2(15.0, 6.0), contact)
			result.back_foot_local = Vector2(-17.0, 45.0)
			result.front_foot_local = Vector2(17.0, 45.0)
		"bash":
			result.body_offset = Vector2(lerpf(2.0, 15.0, contact) * player_facing, lerpf(0.0, 3.0, contact))
			result.hand_local = Vector2(10.0, -15.0).lerp(Vector2(34.0, -6.0), contact)
			result.torso_rotation = lerpf(-0.10, 0.24, contact) * player_facing
			result.head_tilt = result.torso_rotation * 0.55
			result.main_elbow_local = Vector2(8.0, -7.0).lerp(Vector2(23.0, -4.0), contact)
			result.support_elbow_local = Vector2(2.0, -2.0).lerp(Vector2(17.0, 2.0), contact)
			result.crouch = 3.0 * contact
			result.back_foot_local = Vector2(-13.0, 45.0)
			result.front_foot_local = Vector2(15.0, 44.0)
		"thrust":
			result.body_offset = Vector2(lerpf(-2.0, 18.0, contact) * player_facing, 2.0 * contact)
			result.hand_local = Vector2(8.0, -14.0).lerp(Vector2(43.0, -10.0), contact)
			result.torso_rotation = lerpf(-0.12, 0.22, contact) * player_facing
			result.head_tilt = result.torso_rotation * 0.50
			result.main_elbow_local = Vector2(5.0, -7.0).lerp(Vector2(29.0, -9.0), contact)
			result.support_elbow_local = Vector2(0.0, -2.0).lerp(Vector2(22.0, -4.0), contact)
			result.crouch = 3.0 * contact
			result.back_foot_local = Vector2(-15.0, 45.0)
			result.front_foot_local = Vector2(24.0, 43.0)
		"slam":
			result.body_offset = Vector2(lerpf(-3.0, 7.0, contact) * player_facing, lerpf(-7.0, 11.0, contact))
			result.hand_local = Vector2(1.0, -43.0).lerp(Vector2(25.0, 8.0), contact)
			result.torso_rotation = lerpf(-0.34, 0.38, contact) * player_facing
			result.head_tilt = result.torso_rotation * 0.60
			result.main_elbow_local = Vector2(-7.0, -27.0).lerp(Vector2(18.0, -1.0), contact)
			result.support_elbow_local = Vector2(-13.0, -20.0).lerp(Vector2(10.0, 4.0), contact)
			result.crouch = 12.0 * contact
			result.back_foot_local = Vector2(-18.0, 44.0)
			result.front_foot_local = Vector2(18.0, 44.0)
		"spin":
			result.body_offset = Vector2(0.0, lerpf(2.0, 9.0, contact))
			result.hand_local = Vector2(-25.0, -5.0).lerp(Vector2(31.0, 1.0), contact)
			result.torso_rotation = lerpf(-0.56, 0.66, contact) * player_facing
			result.head_tilt = result.torso_rotation * 0.72
			result.main_elbow_local = Vector2(-17.0, -9.0).lerp(Vector2(22.0, 5.0), contact)
			result.support_elbow_local = Vector2(-20.0, 2.0).lerp(Vector2(13.0, -8.0), contact)
			result.crouch = 10.0 * contact
			result.back_foot_local = Vector2(-21.0, 43.0)
			result.front_foot_local = Vector2(21.0, 43.0)
	if pose_weight < 1.0:
		result.body_offset = Vector2(result.body_offset) * pose_weight
		result.hand_local = Vector2(20.0, -12.0).lerp(Vector2(result.hand_local), pose_weight)
		result.torso_rotation = float(result.torso_rotation) * pose_weight
		result.crouch = float(result.crouch) * pose_weight
		result.head_tilt = float(result.head_tilt) * pose_weight
		result.main_elbow_local = Vector2(16.0, -5.0).lerp(Vector2(result.main_elbow_local), pose_weight)
		result.support_elbow_local = Vector2(7.0, -1.0).lerp(Vector2(result.support_elbow_local), pose_weight)
		result.back_foot_local = Vector2(-9.0, 45.0).lerp(Vector2(result.back_foot_local), pose_weight)
		result.front_foot_local = Vector2(10.0, 45.0).lerp(Vector2(result.front_foot_local), pose_weight)
	return result


func _hand_world_position() -> Vector2:
	var character_pose := _character_pose()
	var base := player_position + Vector2(character_pose["body_offset"])
	return _pose_local_point(base, Vector2(character_pose["hand_local"]), float(character_pose["torso_rotation"]) * 0.35)


func _pose_local_point(base: Vector2, local_point: Vector2, rotation: float = 0.0) -> Vector2:
	return base + Vector2(local_point.x * player_facing, local_point.y).rotated(rotation)


func _weapon_pose() -> Dictionary:
	var angle := -0.18 * player_facing
	var extension := 0.0
	var local_offset := Vector2.ZERO
	var primitive: Variant = _current_attack_primitive()
	if primitive != null:
		var motion_ratio := _attack_motion_ratio()
		angle = lerpf(primitive.start_angle, primitive.end_angle, motion_ratio) * player_facing
		# Knocked off line by however it was being held. Zero until something is hit.
		angle += float(controller.contact_deflect_radians) * player_facing
		extension = sin(motion_ratio * PI) * primitive.extension_pixels
		local_offset = primitive.local_start_offset.lerp(primitive.local_end_offset, motion_ratio)
	return {"angle": angle, "extension": extension, "local_offset": local_offset}


func _current_attack_primitive() -> Variant:
	if controller == null or controller.phase == "idle":
		return null
	return controller.current_primitive


func _primitive_contact_world(primitive: Variant, hand: Vector2) -> Vector2:
	if primitive == null or asset == null:
		return hand
	var anchor: Vector2
	match str(primitive.contact_anchor):
		"muzzle": anchor = asset.muzzle
		"rear_contact": anchor = _resolved_rear_contact()
		"whole_body": anchor = Vector2(asset.opaque_bounds.get_center())
		_: anchor = asset.tip
	var pose: Dictionary = _weapon_pose()
	var offset := Vector2(float(pose["extension"]) * player_facing, 0.0)
	var local_offset: Vector2 = pose.get("local_offset", Vector2.ZERO)
	offset += Vector2(local_offset.x * player_facing, local_offset.y)
	var local_anchor := anchor - asset.grip_primary
	local_anchor = Vector2(local_anchor.x * player_facing, local_anchor.y) * motion_profile.render_scale
	return hand + offset + local_anchor.rotated(float(pose["angle"]))


func _resolved_rear_contact() -> Vector2:
	if asset == null:
		return Vector2.ZERO
	if asset.rear_contact != asset.grip_primary and asset.rear_contact != Vector2.ZERO:
		return asset.rear_contact
	var function_anchor := asset.muzzle if asset.muzzle != asset.grip_primary else asset.tip
	var forward_axis: Vector2 = function_anchor - asset.grip_primary
	if forward_axis.length() < 0.5:
		forward_axis = Vector2.RIGHT
	var rear_axis := -forward_axis.normalized()
	var diagonal := Vector2(asset.opaque_bounds.size).length() + 4.0
	var farthest_opaque := asset.grip_primary
	if asset.source_image != null and not asset.source_image.is_empty():
		for step: int in range(1, ceili(diagonal) + 1):
			var sample := asset.grip_primary + rear_axis * float(step)
			var pixel := Vector2i(roundi(sample.x), roundi(sample.y))
			if pixel.x < 0 or pixel.y < 0 or pixel.x >= asset.source_image.get_width() or pixel.y >= asset.source_image.get_height():
				break
			if asset.source_image.get_pixelv(pixel).a >= 0.12:
				farthest_opaque = Vector2(pixel)
	if farthest_opaque != asset.grip_primary:
		return farthest_opaque
	var bounds := Rect2(asset.opaque_bounds)
	var distances: Array[float] = []
	if absf(rear_axis.x) > 0.0001:
		var x_edge := bounds.end.x if rear_axis.x > 0.0 else bounds.position.x
		var x_distance := (x_edge - asset.grip_primary.x) / rear_axis.x
		if x_distance >= 0.0:
			distances.append(x_distance)
	if absf(rear_axis.y) > 0.0001:
		var y_edge := bounds.end.y if rear_axis.y > 0.0 else bounds.position.y
		var y_distance := (y_edge - asset.grip_primary.y) / rear_axis.y
		if y_distance >= 0.0:
			distances.append(y_distance)
	if distances.is_empty():
		return asset.grip_primary
	var rear_distance: float = distances.min()
	return asset.grip_primary + rear_axis * minf(rear_distance, diagonal)

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color("071018"), true)
	draw_rect(ARENA, Color("172734"), true)
	draw_rect(ARENA, Color("405864"), false, 3.0)
	for x: int in range(60, 1240, 80): draw_line(Vector2(x, ARENA.position.y), Vector2(x, ARENA.end.y), Color(0.28, 0.42, 0.47, 0.18), 1.0)
	for y: int in range(170, 680, 64): draw_line(Vector2(ARENA.position.x, y), Vector2(ARENA.end.x, y), Color(0.28, 0.42, 0.47, 0.14), 1.0)
	draw_line(Vector2(50, 655), Vector2(1230, 655), Color("896b3a"), 5.0)
	if capture_comparison: _draw_real_weapon_comparison()
	else: _draw_player()
	for particle: Dictionary in particles:
		if str(particle.get("kind", "spark")) == "ring":
			draw_arc(Vector2(particle["pos"]), float(particle["radius"]), 0.0, TAU, 28, Color(particle["color"], clampf(float(particle["life"]) * 4.0, 0.0, 1.0)), float(particle["size"]))
		else:
			var spark_pos := Vector2(particle["pos"])
			var velocity := Vector2(particle["vel"])
			draw_line(spark_pos, spark_pos - velocity.normalized() * float(particle["size"]) * 2.4, Color(particle["color"]), float(particle["size"]))
	if motion_profile != null and controller.phase == "active" and not capture_pose_only: _draw_active_hitbox()

func _draw_player() -> void:
	if asset == null: return
	var hurt_color := Color("ff8d84") if player_hurt > 0.0 else Color("58cbd2")
	var run_bob := sin(elapsed_seconds * 12.0) * 2.0 if Input.get_vector("move_left", "move_right", "move_up", "move_down").length() > 0.1 else 0.0
	var character_pose := _character_pose()
	var body_offset: Vector2 = character_pose["body_offset"]
	var torso_rotation: float = float(character_pose["torso_rotation"])
	var crouch: float = float(character_pose["crouch"])
	var base := player_position + Vector2(0, run_bob) + body_offset
	var back_foot_local: Vector2 = character_pose["back_foot_local"]
	var front_foot_local: Vector2 = character_pose["front_foot_local"]
	if controller.dodge_motion_seconds > 0.0:
		back_foot_local.x -= 7.0
		front_foot_local.x += 7.0
	var back_hip := _pose_local_point(base, Vector2(-7.0, 21.0 + crouch * 0.45), torso_rotation * 0.30)
	var front_hip := _pose_local_point(base, Vector2(7.0, 21.0 + crouch * 0.45), torso_rotation * 0.30)
	var back_foot := _pose_local_point(base, back_foot_local)
	var front_foot := _pose_local_point(base, front_foot_local)
	draw_line(back_hip, back_foot, Color("7f93a2"), 8.0)
	draw_line(front_hip, front_foot, Color("7f93a2"), 8.0)

	var hand := _hand_world_position() + Vector2(0.0, run_bob)
	var pose := _weapon_pose()
	var local_offset: Vector2 = pose.get("local_offset", Vector2.ZERO)
	var weapon_origin := hand + Vector2(float(pose["extension"]) * player_facing + local_offset.x * player_facing, local_offset.y)
	var secondary_delta: Vector2 = Vector2((asset.grip_secondary.x - asset.grip_primary.x) * player_facing, asset.grip_secondary.y - asset.grip_primary.y) * motion_profile.render_scale
	var second_hand: Vector2 = weapon_origin + secondary_delta.rotated(float(pose["angle"]))
	var main_shoulder := _pose_local_point(base, Vector2(character_pose["main_shoulder_local"]) + Vector2(0.0, crouch * 0.28), torso_rotation)
	var main_elbow := _pose_local_point(base, Vector2(character_pose["main_elbow_local"]) + Vector2(0.0, crouch * 0.24), torso_rotation * 0.55)
	var support_shoulder := _pose_local_point(base, Vector2(character_pose["support_shoulder_local"]) + Vector2(0.0, crouch * 0.28), torso_rotation)
	var support_elbow := _pose_local_point(base, Vector2(character_pose["support_elbow_local"]) + Vector2(0.0, crouch * 0.24), torso_rotation * 0.45)
	if motion_profile.grip_mode == "two_hand":
		draw_line(support_shoulder, support_elbow, Color("d7b994"), 7.0)
		draw_line(support_elbow, second_hand, Color("e4c8a8"), 7.0)
		draw_circle(support_elbow, 4.0, Color("e4c8a8"))

	var torso_points := PackedVector2Array([
		_pose_local_point(base, Vector2(-16.0, -15.0 + crouch * 0.24), torso_rotation),
		_pose_local_point(base, Vector2(14.0, -15.0 + crouch * 0.24), torso_rotation),
		_pose_local_point(base, Vector2(19.0, 25.0 + crouch), torso_rotation * 0.35),
		_pose_local_point(base, Vector2(-18.0, 25.0 + crouch), torso_rotation * 0.35),
	])
	draw_colored_polygon(torso_points, hurt_color)

	var head_tilt: float = float(character_pose["head_tilt"])
	var head_center := _pose_local_point(base, Vector2(0.0, -30.0 + crouch * 0.16), torso_rotation * 0.42)
	draw_circle(head_center, 13.0, Color("e4c8a8"))
	draw_colored_polygon(PackedVector2Array([
		head_center + Vector2(-16.0, 9.0).rotated(head_tilt),
		head_center + Vector2(4.0, -16.0).rotated(head_tilt),
		head_center + Vector2(16.0, 7.0).rotated(head_tilt),
	]), Color("d3843e"))
	draw_circle(head_center + Vector2(7.0 * player_facing, -2.0).rotated(head_tilt), 4.0, Color("b8f4ee"))

	draw_line(main_shoulder, main_elbow, Color("d7b994"), 7.0)
	draw_line(main_elbow, weapon_origin, Color("e4c8a8"), 7.0)
	draw_circle(main_shoulder, 4.0, Color("d7b994"))
	draw_circle(main_elbow, 4.5, Color("e4c8a8"))
	draw_set_transform(weapon_origin, float(pose["angle"]), Vector2(player_facing * motion_profile.render_scale, motion_profile.render_scale))
	draw_texture_rect(asset.texture, Rect2(-asset.grip_primary, Vector2(asset.canvas_size)), false)
	draw_set_transform(Vector2.ZERO)
	draw_circle(weapon_origin, 4.0, Color("f6d1ac"))

func _draw_active_hitbox() -> void:
	var hand := _hand_world_position()
	var primitive: Variant = _current_attack_primitive()
	if primitive == null:
		return
	var timing: Dictionary = controller.current_timing()
	var hitbox_length_scale: float = float(primitive.hitbox_length_multiplier) if primitive != null else 1.0
	var reach: float = motion_profile.reach_pixels * float(timing.get("reach_scale", 1.0)) * hitbox_length_scale
	var hitbox_scale: float = float(primitive.hitbox_multiplier) * float(primitive.hitbox_width_multiplier) if primitive != null else 1.0
	var hitbox_thickness: float = motion_profile.hitbox_thickness * hitbox_scale
	var motion_family: String = str(primitive.motion_family)
	var is_finisher: bool = controller.combo_index >= 3 or controller.attack_kind == "charge"
	var color := Color(1.0, 0.72, 0.22, 0.42) if is_finisher else Color(1.0, 0.38, 0.22, 0.28)
	var contact_world := _primitive_contact_world(primitive, hand) if primitive != null else hand + Vector2(player_facing * reach * 0.72, 0.0)
	match motion_family:
		"bash": draw_circle(contact_world, hitbox_thickness * 0.58, color)
		"thrust": draw_rect(_thrust_hitbox_rect(hand, reach, hitbox_thickness, primitive), color, true)
		"slam": draw_circle(contact_world, hitbox_thickness + (10.0 if is_finisher else 0.0), color)
		"spin": draw_arc(hand, reach, 0.0, TAU, 48, color, 28.0)
		_:
			var half_arc := deg_to_rad(motion_profile.swing_arc_degrees * 0.5)
			var facing_angle := 0.0 if player_facing > 0 else PI
			draw_arc(hand, reach, facing_angle - half_arc, facing_angle + half_arc, 36, color, 24.0 if is_finisher else 16.0)

func _draw_real_weapon_comparison() -> void:
	var ids: Array[String] = asset_loader.recipe_asset_ids()
	if comparison_assets.is_empty():
		for id: String in ids:
			var retained: Dictionary = asset_loader.load_recipe_asset(id)
			if not bool(retained.get("ok", false)): continue
			var retained_asset := retained.get("asset") as WeaponVisualAsset
			var retained_affordance := retained.get("affordance_profile") as Resource
			var retained_compiled: Variant = compiler.compile(retained_affordance, retained_asset.anchors_dict(), retained_asset.opaque_bounds)
			if retained_compiled is String: continue
			comparison_assets.append(retained_asset)
			comparison_profiles.append(retained_compiled)
	if comparison_assets.is_empty(): return
	var spacing := 1080.0 / float(comparison_assets.size())
	for index: int in range(comparison_assets.size()):
		var live_asset: WeaponVisualAsset = comparison_assets[index]
		var profile: Resource = comparison_profiles[index]
		var player_at := Vector2(100.0 + spacing * (float(index) + 0.5), 435)
		var hand := player_at + Vector2(23, -12)
		draw_circle(player_at + Vector2(0, -28), 12, Color("e4c8a8"))
		draw_colored_polygon(PackedVector2Array([player_at + Vector2(-14, -14), player_at + Vector2(14, -14), player_at + Vector2(18, 24), player_at + Vector2(-17, 24)]), Color("58cbd2"))
		draw_line(player_at + Vector2(-7, 23), player_at + Vector2(-11, 44), Color("7f93a2"), 7)
		draw_line(player_at + Vector2(7, 23), player_at + Vector2(11, 44), Color("7f93a2"), 7)
		draw_line(player_at + Vector2(5, -6), hand, Color("e4c8a8"), 6)
		draw_set_transform(hand, -0.18 + index * 0.18, Vector2(1.5, 1.5))
		draw_texture_rect(live_asset.texture, Rect2(-live_asset.grip_primary, Vector2(live_asset.canvas_size)), false)
		draw_set_transform(Vector2.ZERO)
		if profile.motion_family == "slam":
			draw_circle(hand + Vector2(135, 45), 34, Color(1.0, 0.35, 0.2, 0.18))
		else:
			draw_arc(hand, 135, -0.72, 0.72, 24, Color(1.0, 0.35, 0.2, 0.32), 10)
		draw_string(ThemeDB.fallback_font, player_at + Vector2(-220, 100), "%s  %s/%s/%s" % [ids[index], profile.motion_family, profile.tempo, profile.reach_class], HORIZONTAL_ALIGNMENT_CENTER, 440, 22, Color("f5dc8c"))

func _capture_evidence(directory: String) -> void:
	game_active = false
	var directory_error := DirAccess.make_dir_recursive_absolute(directory)
	if directory_error != OK:
		push_error("COMBAT_FEEL_CAPTURE_DIRECTORY_FAILED:%s:%s" % [directory, error_string(directory_error)])
		get_tree().quit(1)
		return
	_cleanup_enemies()
	var puppet: Node2D = _spawn_enemy(ENEMY.PUPPET, Vector2(760, 410)); puppet.force_state("tell")
	capture_caption = "Slag Puppet telegraph"; await _capture_frame(directory.path_join("slag_puppet_telegraph.png"))
	_cleanup_enemies()
	var ram: Node2D = _spawn_enemy(ENEMY.RAM, Vector2(790, 410)); ram.force_state("tell")
	capture_caption = "Forge Ram charge telegraph"; await _capture_frame(directory.path_join("forge_ram_telegraph.png"))
	_cleanup_enemies()
	var hit_enemy: Node2D = _spawn_enemy(ENEMY.PUPPET, Vector2(520, 410))
	controller.attack_kind = "normal"; controller.combo_index = 1; controller.current_primitive = motion_profile.combo_recipe.primitive_for(1); controller.phase = "active"; controller.phase_duration = 0.1
	var normal_feedback: Resource = FEEDBACK.for_attack(motion_profile, "normal", 1, controller.current_primitive)
	hit_enemy.apply_hit(10.0, Vector2(normal_feedback.knockback_strength, 0), normal_feedback.stagger_strength, normal_feedback.recoil_degrees)
	_spawn_impact(hit_enemy.position, normal_feedback.particle_scale, normal_feedback.impact_tier, normal_feedback.ring_count)
	hit_enemy.simulate(0.035, player_position); _update_particles(0.035)
	capture_caption = "Normal hit"; await _capture_frame(directory.path_join("normal_hit_feedback.png"))
	_cleanup_enemies(); particles.clear()
	hit_enemy = _spawn_enemy(ENEMY.PUPPET, Vector2(520, 410)); controller.combo_index = 3; controller.current_primitive = motion_profile.combo_recipe.primitive_for(3); shake_strength = 0.0
	var finisher_feedback: Resource = FEEDBACK.for_attack(motion_profile, "normal", 3, controller.current_primitive)
	hit_enemy.apply_hit(10.0, Vector2(finisher_feedback.knockback_strength, -finisher_feedback.launch_strength), finisher_feedback.stagger_strength, finisher_feedback.recoil_degrees)
	_spawn_impact(hit_enemy.position, finisher_feedback.particle_scale, finisher_feedback.impact_tier, finisher_feedback.ring_count)
	hit_enemy.simulate(0.055, player_position); _update_particles(0.055)
	capture_caption = "Third-hit finisher"; await _capture_frame(directory.path_join("third_hit_feedback.png"))
	_cleanup_enemies(); particles.clear(); controller.phase = "idle"; capture_comparison = true; capture_caption = "Frozen real Live Forge weapon handoff"
	await _capture_frame(directory.path_join("real_weapon_comparison.png"))
	get_tree().quit()


func _capture_pose_visibility(directory: String) -> void:
	game_active = false
	capture_pose_only = true
	var directory_error := DirAccess.make_dir_recursive_absolute(directory)
	if directory_error != OK:
		push_error("COMBAT_FEEL_POSE_CAPTURE_DIRECTORY_FAILED:%s:%s" % [directory, error_string(directory_error)])
		get_tree().quit(1)
		return
	_cleanup_enemies()
	player_position = Vector2(640.0, 410.0)
	player_facing = 1.0
	var pose_specs := {
		"sweep": Vector3(-1.35, 1.15, 12.0),
		"bash": Vector3(-0.74, 0.32, 18.0),
		"thrust": Vector3(-0.06, -0.06, 36.0),
		"slam": Vector3(-1.78, 1.05, 16.0),
		"spin": Vector3(-2.85, 3.25, 20.0),
	}
	for family: String in ["sweep", "bash", "thrust", "slam", "spin"]:
		var primitive: Variant = MOTION_PRIMITIVE.new()
		var spec: Vector3 = pose_specs[family]
		primitive.motion_family = family
		primitive.start_angle = spec.x
		primitive.end_angle = spec.y
		primitive.extension_pixels = spec.z
		controller.attack_kind = "normal"
		controller.combo_index = 1
		controller.current_primitive = primitive
		controller.phase = "startup"
		controller.phase_duration = 1.0
		controller.phase_elapsed = 0.70
		capture_caption = "%s — visible windup pose" % family.to_upper()
		await _capture_frame(directory.path_join("%s_windup.png" % family))
		controller.phase = "active"
		controller.phase_duration = 1.0
		controller.phase_elapsed = 0.55
		capture_caption = "%s — visible contact pose" % family.to_upper()
		await _capture_frame(directory.path_join("%s_contact.png" % family))
	controller.phase = "idle"
	controller.current_primitive = null
	get_tree().quit()

func _capture_frame(path: String) -> void:
	banner_label.text = capture_caption
	queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var save_error := image.save_png(path)
	if save_error != OK:
		push_error("COMBAT_FEEL_CAPTURE_SAVE_FAILED:%s:%s" % [path, error_string(save_error)])

func _quit_after(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	get_tree().quit()

func _return_to_forge() -> void:
	if blind_comparison:
		get_tree().quit(0 if blind_run_completed else 2)
		return
	if launched_from_open_playtest:
		get_tree().quit()
		return
	get_tree().change_scene_to_file("res://scenes/open_identity_spike.tscn")


func _write_blind_run_result() -> void:
	if blind_result_path.is_empty():
		return
	var absolute_path := ProjectSettings.globalize_path(blind_result_path)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if directory_error != OK:
		push_error("BLIND_RESULT_DIRECTORY_FAILED:%s" % error_string(directory_error))
		return
	var temporary_path := absolute_path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		push_error("BLIND_RESULT_WRITE_FAILED:%s" % error_string(FileAccess.get_open_error()))
		return
	var record := {
		"schema": "forge-motion-grammar-slice-1a-blind-run-v1",
		"timestamp": Time.get_datetime_string_from_system(true),
		"blind_label": blind_label,
		"completed": true,
		"elapsed_seconds": snappedf(elapsed_seconds, 0.01),
		"input_to_visual_ms": input_to_visual_ms,
		"input_to_active_ms": input_to_active_ms,
		"normal_attack_stats": _normal_attack_stats(),
	}
	if blind_suite == "generalization_v1":
		record["schema"] = "forge-motion-grammar-blind-run-v2"
		record["blind_suite"] = blind_suite
		record["compiled_metrics"] = _blind_compiled_metrics()
	file.store_string(JSON.stringify(record, "  ") + "\n")
	file.close()
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)
	var rename_error := DirAccess.rename_absolute(temporary_path, absolute_path)
	if rename_error != OK:
		push_error("BLIND_RESULT_DELIVERY_FAILED:%s" % error_string(rename_error))


func _blind_compiled_metrics() -> Dictionary:
	var recipe: Resource = motion_profile.combo_recipe
	if recipe == null:
		return {}
	var max_coverage := 0.0
	var max_control := 0.0
	var total_root_motion := 0.0
	for primitive: Resource in recipe.primitives():
		var arc_degrees := absf(rad_to_deg(primitive.end_angle - primitive.start_angle))
		var effective_width: float = motion_profile.hitbox_thickness * primitive.hitbox_width_multiplier
		var coverage: float = effective_width * maxf(8.0, arc_degrees) * primitive.hitbox_length_multiplier
		max_coverage = maxf(max_coverage, coverage)
		max_control = maxf(
			max_control,
			motion_profile.control_strength * primitive.knockback_multiplier * primitive.hitbox_width_multiplier
		)
		total_root_motion += primitive.root_motion_distance
	var third: Resource = recipe.hit_3
	var third_weight: float = third.hitstop_multiplier * third.stagger_multiplier \
		* third.camera_kick_multiplier * motion_profile.impact_sharpness
	return {
		"reach_pixels": motion_profile.reach_pixels,
		"maximum_coverage_score": max_coverage,
		"third_hit_weight_score": third_weight,
		"control_score": max_control,
		"combo_root_motion_total": total_root_motion,
		"recipe_signature": recipe.signature(),
		"primitive_sequence": Array(recipe.primitive_sequence()),
	}

func _label(text_value: String, size_value: int, color: Color) -> Label:
	var label := Label.new(); label.text = text_value; label.add_theme_font_size_override("font_size", size_value); label.modulate = color
	return label

func _button(text_value: String, callback: Callable) -> Button:
	var button := Button.new(); button.text = text_value; button.pressed.connect(callback); return button

func _argument_value(prefix: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix): return argument.trim_prefix(prefix)
	return fallback


func _has_argument(expected: String) -> bool:
	return expected in OS.get_cmdline_user_args()
