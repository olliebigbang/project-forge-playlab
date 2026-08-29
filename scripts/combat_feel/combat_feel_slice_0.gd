class_name CombatFeelSlice0
extends Node2D

const ARENA := Rect2(38, 145, 1204, 532)
const ASSET_LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")
const MOTION_COMPILER := preload("res://scripts/combat_feel/melee_motion_compiler.gd")
const CONTROLLER := preload("res://scripts/combat_feel/melee_combat_controller.gd")
const ENEMY := preload("res://scripts/combat_feel/combat_feel_enemy.gd")
const FEEDBACK := preload("res://scripts/combat_feel/impact_feedback_profile.gd")
const MOTION_PRIMITIVE := preload("res://scripts/combat_feel/motion_primitive.gd")
const PERCEPTIBLE_CONTACT := preload("res://scripts/combat_feel/perceptible_contact_mechanics.gd")
const TARGET_INTERACTION := preload("res://scripts/combat_feel/weapon_target_interaction_resolver.gd")
const PIXEL_WEAPON_DEFORMER := preload("res://scripts/combat_feel/pixel_weapon_deformer.gd")
const TUNING_SCHEMA := "forge-combat-feel-tuning-v2"
const TIMING_KEYS: PackedStringArray = ["startup", "active", "recovery", "combo_window", "input_buffer"]
const TIMING_CLAMPS := {
	"startup": Vector2(0.06, 0.45),
	"active": Vector2(0.04, 0.22),
	"recovery": Vector2(0.10, 0.60),
	"combo_window": Vector2(0.20, 0.80),
	"input_buffer": Vector2(0.10, 0.18),
}
const TIMING_REFERENCE_BY_TEMPO := {
	"rapid": {"startup": 0.13, "active": 0.08, "recovery": 0.18, "combo_window": 0.46, "input_buffer": 0.16},
	"balanced": {"startup": 0.19, "active": 0.10, "recovery": 0.25, "combo_window": 0.46, "input_buffer": 0.16},
	"committed": {"startup": 0.29, "active": 0.13, "recovery": 0.36, "combo_window": 0.46, "input_buffer": 0.16},
}

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
var attack_root_motion_serial := -1
var attack_root_motion_applied := 0.0
var attack_root_motion_direction := 1.0
var blind_comparison := false
var blind_label := ""
var blind_run_completed := false
var blind_result_path := ""
var blind_suite := "slice_1a"
var capture_pose_only := false
var compiled_timing_defaults: Dictionary = {}
var runtime_mechanism_handoff: Node
var last_contact_verb := "none"
var mechanism_verb_counts: Dictionary = {}

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
	_capture_compiled_timing_defaults()
	_update_mode_title()
	controller.configure(motion_profile)
	_apply_saved_tuning()
	_sync_debug_panel()
	_start_run()
	var smoke_seconds := float(_argument_value("--smoke-seconds=", "0"))
	if smoke_seconds > 0.0: _quit_after(smoke_seconds)
	var capture_dir := _argument_value("--capture-dir=", "")
	var pose_capture_dir := _argument_value("--pose-capture-dir=", "")
	var visual_rig_capture_dir := _argument_value("--visual-rig-capture-dir=", "")
	if not visual_rig_capture_dir.is_empty():
		print("PIXEL_VISUAL_RIG_CAPTURE_REQUESTED:", visual_rig_capture_dir)
		call_deferred("_capture_visual_rig_evidence", visual_rig_capture_dir)
	elif not pose_capture_dir.is_empty(): call_deferred("_capture_pose_visibility", pose_capture_dir)
	elif not capture_dir.is_empty(): call_deferred("_capture_evidence", capture_dir)


func _compile_loaded_weapon() -> Variant:
	if affordance_profile != null:
		return compiler.compile(affordance_profile, asset.anchors_dict(), asset.opaque_bounds)
	return compiler.compile(blueprint, asset)

func _load_requested_weapon() -> bool:
	var runtime_handoff: Node = runtime_mechanism_handoff
	if runtime_handoff == null and is_inside_tree():
		runtime_handoff = get_tree().root.get_node_or_null("MechanismHandoff")
	var sprite_path := _argument_value("--combat-sprite=", "")
	var blueprint_path := _argument_value("--combat-blueprint=", "")
	var anchors_path := _argument_value("--combat-anchors=", "")
	var open_round_path := _argument_value("--open-playtest-round=", "")
	var requested_generalization_id := _argument_value("--generalization-asset=", "")
	var requested_motion_grammar_id := _argument_value("--motion-grammar-asset=", "")
	var requested_soft_weapon_id := _argument_value("--soft-weapon-asset=", "")
	var requested_recipe_id := _argument_value("--recipe-asset=", "")
	var requested_live_id := _argument_value("--live-weapon=", "")
	var requested_fixture := _argument_value("--developer-fixture=", "").to_upper()
	var result: Dictionary
	if runtime_handoff != null and bool(runtime_handoff.call("has_pending")):
		launched_from_open_playtest = true
		result = runtime_handoff.call("take") as Dictionary
	elif not requested_generalization_id.is_empty():
		result = asset_loader.load_generalization_asset(requested_generalization_id)
	elif not requested_motion_grammar_id.is_empty():
		result = asset_loader.load_motion_grammar_asset(requested_motion_grammar_id)
	elif not requested_soft_weapon_id.is_empty():
		result = asset_loader.load_soft_weapon_asset(requested_soft_weapon_id)
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
	blueprint = result.get("blueprint") as WeaponBlueprint
	asset = result.get("asset") as WeaponVisualAsset
	affordance_profile = result.get("affordance_profile") as Resource
	source_notice = str(result.get("notice", ""))
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
	attack_root_motion_serial = -1
	attack_root_motion_applied = 0.0
	attack_root_motion_direction = player_facing
	last_contact_verb = "none"
	mechanism_verb_counts = {}
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
		if controller.phase in ["startup", "active", "recovery"]:
			var primitive: Variant = _current_attack_primitive()
			var allowed: float = float(primitive.movement_allowed_ratio) if primitive != null else float(motion_profile.movement_commitment)
			if controller.phase == "recovery":
				allowed = lerpf(allowed, 1.0, controller.phase_ratio())
			speed *= allowed
		player_position += input_vector * speed * delta
		if absf(input_vector.x) > 0.05: player_facing = signf(input_vector.x)
	_apply_attack_root_motion()
	player_position.x = clampf(player_position.x, ARENA.position.x + 30.0, ARENA.end.x - 30.0)
	player_position.y = clampf(player_position.y, ARENA.position.y + 52.0, ARENA.end.y - 28.0)


func _apply_attack_root_motion() -> void:
	if controller == null or controller.current_primitive == null:
		return
	if attack_root_motion_serial != controller.attack_serial:
		return
	var primitive: Variant = controller.current_primitive
	var target := float(primitive.root_motion_distance) * _root_motion_progress(
		controller.phase,
		controller.phase_ratio(),
		float(primitive.inertia_ratio)
	)
	var distance := maxf(0.0, target - attack_root_motion_applied)
	player_position.x += distance * attack_root_motion_direction
	attack_root_motion_applied = maxf(attack_root_motion_applied, target)


func _root_motion_progress(phase: String, phase_ratio: float, inertia_ratio: float) -> float:
	# Rear-weighted objects deliver almost all travel in the active phase and stop
	# cleanly. Front-weighted objects retain a large, visible recovery carry.
	var active_fraction := lerpf(0.92, 0.60, clampf(inertia_ratio, 0.0, 1.0))
	match phase:
		"startup": return 0.0
		"active": return active_fraction * smoothstep(0.0, 1.0, phase_ratio)
		"recovery": return active_fraction + (1.0 - active_fraction) * smoothstep(0.0, 1.0, phase_ratio)
		"idle": return 1.0
	return 0.0

func _on_attack_started(kind: String, combo_index: int) -> void:
	attack_connected = false
	if kind == "normal" and combo_index in [1, 2, 3]:
		normal_attack_attempts[combo_index] = int(normal_attack_attempts.get(combo_index, 0)) + 1
	attack_root_motion_serial = controller.attack_serial
	attack_root_motion_applied = 0.0
	attack_root_motion_direction = player_facing
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
	var eligible_enemies: Array[Node2D] = enemies
	var active_primitive: Variant = controller.current_primitive
	if _mechanism_experiment_enabled() and PERCEPTIBLE_CONTACT.verb_for(active_primitive) == "pin":
		eligible_enemies = []
		var nearest: Node2D
		var nearest_distance := INF
		for candidate: Node2D in enemies:
			if candidate.state == "dead" or not _attack_contains(candidate.position):
				continue
			var distance := player_position.distance_squared_to(candidate.position)
			if distance < nearest_distance:
				nearest = candidate
				nearest_distance = distance
		if nearest != null:
			eligible_enemies.append(nearest)
	for enemy: Node2D in eligible_enemies:
		if enemy.state == "dead": continue
		if not _attack_contains(enemy.position): continue
		if not controller.register_hit(enemy.enemy_id): continue
		var primitive: Variant = controller.current_primitive
		var feedback: Resource = FEEDBACK.for_attack(motion_profile, controller.attack_kind, controller.combo_index, controller.current_primitive)
		var finisher_scale := 1.45 if controller.combo_index >= 3 or controller.attack_kind == "charge" else 1.0
		if has_meta("debug_hitstop"):
			feedback.hitstop_seconds = float(get_meta("debug_hitstop")) * finisher_scale
		feedback.knockback_strength *= float(get_meta("debug_knockback", 1.0))
		feedback.camera_shake_strength *= float(get_meta("debug_shake", 1.0))
		var damage := _current_damage()
		var reaction := _hit_reaction(enemy.position, feedback, primitive)
		var mechanism: Dictionary = {}
		if _mechanism_experiment_enabled():
			mechanism = PERCEPTIBLE_CONTACT.outcome_for(primitive, reaction, enemy.state)
			reaction["knockback"] = mechanism.get("knockback", reaction["knockback"])
			reaction["stagger"] = mechanism.get("stagger", reaction["stagger"])
			damage *= float(mechanism.get("damage_multiplier", 1.0))
		elif affordance_profile != null:
			var interaction_profile: Dictionary = TARGET_INTERACTION.compile_melee(affordance_profile, primitive)
			var target_context: Dictionary = enemy.target_interaction_context()
			mechanism = TARGET_INTERACTION.resolve(interaction_profile, target_context, damage, reaction)
			reaction["knockback"] = mechanism.get("knockback", reaction["knockback"])
			reaction["stagger"] = mechanism.get("stagger", reaction["stagger"])
			damage = float(mechanism.get("health_damage", damage))
		if not mechanism.is_empty():
			last_contact_verb = str(mechanism.get("verb", "none"))
			mechanism_verb_counts[last_contact_verb] = int(mechanism_verb_counts.get(last_contact_verb, 0)) + 1
		var knockback: Vector2 = reaction["knockback"]
		enemy.apply_hit(damage, knockback, float(reaction["stagger"]), feedback.recoil_degrees, mechanism)
		controller.begin_hitstop(feedback.hitstop_seconds)
		shake_strength = maxf(shake_strength, feedback.camera_shake_strength)
		camera_kick = Vector2(-player_facing * feedback.camera_shake_strength * 0.72, -feedback.camera_shake_strength * 0.18)
		last_hit_target = "%s:%d" % [enemy.enemy_kind, enemy.enemy_id]
		current_knockback = knockback.length()
		if not attack_connected and controller.attack_kind == "normal" and controller.combo_index in [1, 2, 3]:
			normal_attack_hits[controller.combo_index] = int(normal_attack_hits.get(controller.combo_index, 0)) + 1
		attack_connected = true
		_spawn_impact(enemy.position, feedback.particle_scale, feedback.impact_tier, feedback.ring_count)
		if not mechanism.is_empty():
			_spawn_mechanism_feedback(enemy.position, last_contact_verb)
		_play_tone("heavy_hit" if feedback.impact_tier in ["finisher", "charge"] else "hit")


func _mechanism_experiment_enabled() -> bool:
	return false


func _spawn_mechanism_feedback(at: Vector2, verb: String) -> void:
	var color := PERCEPTIBLE_CONTACT.color_for_verb(verb)
	match verb:
		"entangle": color = Color("c084fc")
		"hook_pull": color = Color("22d3ee")
		"suppress": color = Color("f59e0b")
		"armor_break": color = Color("fb7185")
		"stagger": color = Color("facc15")
	particles.append({
		"kind": "ring",
		"pos": at,
		"radius": 10.0,
		"speed": 175.0,
		"life": 0.34,
		"size": 5.5,
		"color": color,
	})


func _hit_reaction(target_position: Vector2, feedback: Resource, primitive: Variant) -> Dictionary:
	var away := (target_position - player_position).normalized()
	if away.length() < 0.1:
		away = Vector2(player_facing, 0.0)
	var knockback := away * float(feedback.knockback_strength) + Vector2(0.0, -float(feedback.launch_strength))
	var stagger := float(feedback.stagger_strength)
	if primitive != null:
		match str(primitive.tether_mode):
			"hook":
				var toward_player := -away
				knockback = toward_player * float(primitive.tether_strength) + Vector2(0.0, -float(feedback.launch_strength) * 0.20)
				stagger *= 1.15
			"wrap":
				knockback *= 0.18
				stagger *= 1.35
		if float(primitive.state_extent_ratio) > 0.0:
			match str(primitive.functional_output):
				"pull_field":
					knockback = -away * maxf(150.0, knockback.length())
					stagger *= 1.28
				"radial_field":
					knockback = away * maxf(180.0, knockback.length())
					stagger *= 1.18
				"directed_stream":
					knockback = away * maxf(135.0, knockback.length())
	return {"knockback": knockback, "stagger": stagger}

func _attack_contains(target: Vector2) -> bool:
	var hand := _hand_world_position() + _run_bob_offset()
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
	var contact_world := _primitive_contact_world(primitive, hand) if primitive != null else hand + Vector2(player_facing * reach * 0.72, 0.0)
	var contact_vector := contact_world - hand
	contact_vector = _categorical_contact_vector(primitive, contact_vector, reach)
	var surface := str(primitive.contact_surface)
	var deadzone := _soft_contact_deadzone(primitive, contact_vector, reach, float(primitive.inner_deadzone_pixels))
	if to_target.length() < deadzone:
		return false
	var stateful_result := _stateful_attack_contains(target, primitive, hand, contact_world, reach, hitbox_thickness, deadzone)
	if bool(stateful_result.get("handled", false)):
		return bool(stateful_result.get("contains", false))
	if _uses_pixel_visual_deformation(primitive):
		return _soft_visual_attack_contains(target, primitive, hitbox_thickness, deadzone)
	match surface:
		"point":
			if _uses_terminal_contact_collision(primitive):
				return target.distance_to(contact_world) <= _contact_radius(hitbox_thickness, primitive)
			if motion_family == "thrust":
				return _point_lane_contains(to_target, contact_vector, reach, hitbox_thickness, primitive)
			return target.distance_to(contact_world) <= _contact_radius(hitbox_thickness, primitive)
		"edge":
			if motion_family == "spin":
				return to_target.length() >= deadzone and to_target.length() <= _spin_contact_reach(primitive, contact_vector, reach)
			return _contact_band_contains(to_target, contact_vector, reach, hitbox_thickness, primitive, deadzone)
		"broad":
			return target.distance_to(contact_world) <= _contact_radius(hitbox_thickness, primitive) \
				+ (16.0 if controller.attack_kind == "charge" else 0.0)
		"whole_body":
			if motion_family == "spin":
				return to_target.length() >= deadzone and to_target.length() <= _spin_contact_reach(primitive, contact_vector, reach)
			return _contact_band_contains(to_target, contact_vector, reach, hitbox_thickness, primitive, deadzone)
	return false


func _stateful_attack_contains(
	target: Vector2,
	primitive: Variant,
	hand: Vector2,
	contact: Vector2,
	reach: float,
	thickness: float,
	deadzone: float
) -> Dictionary:
	if primitive == null or float(primitive.state_extent_ratio) <= 0.0:
		return {"handled": false, "contains": false}
	var output := str(primitive.functional_output)
	var state := str(primitive.state_topology)
	var direction := (contact - hand).normalized()
	if direction.length_squared() < 0.5:
		direction = Vector2(player_facing, 0.0)
	var relative := target - hand
	if output in ["directed_stream", "pull_field"]:
		var projected := relative.dot(direction)
		var perpendicular := absf(relative.cross(direction))
		var cone_width := lerpf(thickness * 0.28, thickness * 1.18, clampf(projected / maxf(1.0, reach), 0.0, 1.0))
		return {"handled": true, "contains": projected >= deadzone and projected <= reach and perpendicular <= cone_width}
	if output == "radial_field":
		return {"handled": true, "contains": relative.length() >= deadzone and relative.length() <= reach * 0.82}
	if state == "radial_expand":
		return {"handled": true, "contains": target.distance_to(contact) <= thickness * 0.92 + 22.0}
	if state == "rotary":
		return {"handled": true, "contains": target.distance_to(contact) <= thickness * 0.72 + 16.0}
	if state == "telescoping":
		var projected := relative.dot(direction)
		return {"handled": true, "contains": projected >= deadzone and projected <= reach and absf(relative.cross(direction)) <= thickness * 0.42}
	return {"handled": false, "contains": false}


func _point_lane_contains(to_target: Vector2, contact_vector: Vector2, reach: float, thickness: float, primitive: Variant) -> bool:
	var direction := _contact_direction(contact_vector)
	var current_reach := _current_contact_reach(contact_vector, reach)
	var rear_tolerance := _thrust_rear_tolerance(primitive, thickness)
	var base_deadzone := float(primitive.inner_deadzone_pixels) if primitive != null else 0.0
	var deadzone := _soft_contact_deadzone(primitive, contact_vector, reach, base_deadzone)
	var projected := to_target.dot(direction)
	var perpendicular := absf(to_target.cross(direction))
	return current_reach > deadzone \
		and projected >= deadzone - rear_tolerance \
		and projected <= current_reach \
		and perpendicular <= thickness * 0.5


func _contact_band_contains(to_target: Vector2, contact_vector: Vector2, reach: float, thickness: float, primitive: Variant, deadzone: float) -> bool:
	var current_reach := _current_contact_reach(contact_vector, reach)
	var distance := to_target.length()
	if current_reach <= deadzone or distance < deadzone or distance > current_reach:
		return false
	var contact_angle := _contact_direction(contact_vector).angle()
	var angular_distance := absf(wrapf(to_target.angle() - contact_angle, -PI, PI))
	return angular_distance <= deg_to_rad(_instantaneous_contact_arc_degrees(primitive, current_reach, thickness) * 0.5)


func _contact_direction(contact_vector: Vector2) -> Vector2:
	if contact_vector.length_squared() > 0.01:
		return contact_vector.normalized()
	return Vector2(player_facing, 0.0)


func _categorical_contact_vector(primitive: Variant, contact_vector: Vector2, reach: float) -> Vector2:
	if _mechanism_experiment_enabled() and primitive != null \
			and str(primitive.contact_surface) == "whole_body":
		# A body-gripped object must own a visibly larger space than a point or
		# edge. Extend the same vector used by collision and rendering so the
		# affordance is a genuine play difference, not a HUD-only promise.
		return _contact_direction(contact_vector) * maxf(contact_vector.length(), reach)
	return contact_vector


func _current_contact_reach(contact_vector: Vector2, reach: float) -> float:
	return minf(reach, contact_vector.length())


func _soft_contact_deadzone(primitive: Variant, contact_vector: Vector2, reach: float, base_deadzone: float) -> float:
	if primitive == null:
		return base_deadzone
	return maxf(base_deadzone, _current_contact_reach(contact_vector, reach) * float(primitive.soft_contact_start_ratio))


func _uses_terminal_contact_collision(primitive: Variant) -> bool:
	if primitive == null:
		return false
	return str(primitive.flex_topology) in ["flexible_line", "linked_segments"] \
		or str(primitive.tether_topology) in ["flexible_line", "linked_segments"] \
		or str(primitive.tether_mode) == "hook"


func _spin_contact_reach(primitive: Variant, contact_vector: Vector2, reach: float) -> float:
	if primitive != null and (str(primitive.flex_topology) != "none" or str(primitive.tether_topology) != "none"):
		return _current_contact_reach(contact_vector, reach)
	return reach


func _instantaneous_contact_arc_degrees(primitive: Variant, current_reach: float, thickness: float) -> float:
	var surface := str(primitive.contact_surface) if primitive != null else "edge"
	var declared_arc := float(primitive.contact_arc_degrees) if primitive != null else 90.0
	var physical_arc := rad_to_deg(2.0 * atan2(thickness * 0.5, maxf(1.0, current_reach)))
	match surface:
		"whole_body":
			if _mechanism_experiment_enabled():
				# In the categorical experiment, whole-body contact owns coverage.
				# The collision and its drawn sector share this value.
				return clampf(maxf(maxf(physical_arc, declared_arc), 120.0), 120.0, 150.0)
			return clampf(maxf(physical_arc, declared_arc * 0.32), 32.0, 132.0)
		"edge": return clampf(maxf(physical_arc, declared_arc * 0.22), 12.0, 54.0)
		_: return clampf(maxf(physical_arc, declared_arc * 0.18), 10.0, 48.0)


func _contact_radius(hitbox_thickness: float, primitive: Variant) -> float:
	var terminal_scale := 1.0 + 0.45 * float(primitive.terminal_load_ratio)
	match str(primitive.contact_surface):
		"point": return hitbox_thickness * 0.30 * terminal_scale
		"broad": return hitbox_thickness * 0.74 * terminal_scale
		"whole_body": return hitbox_thickness * terminal_scale
	return hitbox_thickness * 0.50 * terminal_scale


func _thrust_rear_tolerance(primitive: Variant, hitbox_thickness: float) -> float:
	if primitive == null:
		return 12.0
	if float(primitive.inner_deadzone_pixels) > 0.0:
		return 0.0
	return minf(36.0, float(primitive.root_motion_distance) * 0.60 + hitbox_thickness * 0.25)


func _point_lane_polygon(hand: Vector2, contact_vector: Vector2, reach: float, hitbox_thickness: float, primitive: Variant) -> PackedVector2Array:
	var direction := _contact_direction(contact_vector)
	var normal := Vector2(-direction.y, direction.x) * hitbox_thickness * 0.5
	var rear_tolerance := _thrust_rear_tolerance(primitive, hitbox_thickness)
	var base_deadzone := float(primitive.inner_deadzone_pixels) if primitive != null else 0.0
	var deadzone := _soft_contact_deadzone(primitive, contact_vector, reach, base_deadzone)
	var start := hand + direction * (deadzone - rear_tolerance)
	var finish := hand + direction * _current_contact_reach(contact_vector, reach)
	return PackedVector2Array([start - normal, finish - normal, finish + normal, start + normal])


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
	var primitive: Variant = _current_attack_primitive()
	if primitive != null:
		base *= float(primitive.damage_multiplier)
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
	if compiled_timing_defaults.is_empty():
		_capture_compiled_timing_defaults()
	var data := {
		"schema": TUNING_SCHEMA,
		"timing_multipliers": _current_timing_multipliers(),
		"timing_seconds_at_save": _timing_values(),
		"debug": {
			"hitstop": get_meta("debug_hitstop", 0.060),
			"knockback": get_meta("debug_knockback", 1.0),
			"shake": get_meta("debug_shake", 1.0),
			"tell": get_meta("debug_tell", 0.55),
			"recovery": get_meta("debug_recovery", 0.75),
		},
	}
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
	_apply_tuning_data(data)


func _capture_compiled_timing_defaults() -> void:
	compiled_timing_defaults = _timing_values()


func _timing_values() -> Dictionary:
	if motion_profile == null:
		return {}
	return {
		"startup": motion_profile.startup_seconds,
		"active": motion_profile.active_seconds,
		"recovery": motion_profile.recovery_seconds,
		"combo_window": motion_profile.combo_window_seconds,
		"input_buffer": motion_profile.input_buffer_seconds,
	}


func _current_timing_multipliers() -> Dictionary:
	var result := {}
	var current := _timing_values()
	for key: String in TIMING_KEYS:
		var compiled_value := maxf(0.0001, float(compiled_timing_defaults.get(key, current.get(key, 1.0))))
		result[key] = float(current.get(key, compiled_value)) / compiled_value
	return result


func _apply_tuning_data(data: Dictionary) -> void:
	if motion_profile == null:
		return
	if compiled_timing_defaults.is_empty():
		_capture_compiled_timing_defaults()
	var multipliers: Dictionary = data.get("timing_multipliers", {}) if data.get("timing_multipliers", {}) is Dictionary else {}
	if multipliers.is_empty():
		multipliers = _legacy_timing_multipliers(data)
	for key: String in TIMING_KEYS:
		var multiplier := float(multipliers.get(key, 1.0))
		if not is_finite(multiplier):
			multiplier = 1.0
		multiplier = clampf(multiplier, 0.25, 4.0)
		var limits: Vector2 = TIMING_CLAMPS[key]
		var compiled_value := float(compiled_timing_defaults.get(key, _timing_value(key)))
		_set_timing_value(key, clampf(compiled_value * multiplier, limits.x, limits.y))
	_apply_debug_tuning(data)


func _legacy_timing_multipliers(data: Dictionary) -> Dictionary:
	# V1 saved absolute seconds together with the source profile's tempo. Treat
	# those seconds as a style scale against that tempo instead of forcing every
	# subsequently loaded object to inherit the same absolute timings.
	var source_tempo := str(data.get("tempo", "balanced"))
	var reference: Dictionary = TIMING_REFERENCE_BY_TEMPO.get(source_tempo, TIMING_REFERENCE_BY_TEMPO["balanced"])
	var result := {}
	for key: String in TIMING_KEYS:
		if data.has(key):
			result[key] = float(data[key]) / maxf(0.0001, float(reference[key]))
		else:
			result[key] = 1.0
	return result


func _apply_debug_tuning(data: Dictionary) -> void:
	var debug: Dictionary = data.get("debug", {}) if data.get("debug", {}) is Dictionary else {}
	set_meta("debug_hitstop", clampf(float(debug.get("hitstop", data.get("debug_hitstop", 0.060))), 0.035, 0.115))
	set_meta("debug_knockback", clampf(float(debug.get("knockback", data.get("debug_knockback", 1.0))), 0.60, 1.80))
	set_meta("debug_shake", clampf(float(debug.get("shake", data.get("debug_shake", 1.0))), 0.0, 2.0))
	set_meta("debug_tell", clampf(float(debug.get("tell", data.get("debug_tell", 0.55))), 0.30, 1.10))
	set_meta("debug_recovery", clampf(float(debug.get("recovery", data.get("debug_recovery", 0.75))), 0.40, 1.50))


func _timing_value(key: String) -> float:
	match key:
		"startup": return motion_profile.startup_seconds
		"active": return motion_profile.active_seconds
		"recovery": return motion_profile.recovery_seconds
		"combo_window": return motion_profile.combo_window_seconds
		"input_buffer": return motion_profile.input_buffer_seconds
	return 0.0


func _set_timing_value(key: String, value: float) -> void:
	match key:
		"startup": motion_profile.startup_seconds = value
		"active": motion_profile.active_seconds = value
		"recovery": motion_profile.recovery_seconds = value
		"combo_window": motion_profile.combo_window_seconds = value
		"input_buffer": motion_profile.input_buffer_seconds = value

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
	if _mechanism_experiment_enabled():
		debug_label.text += "\ncontact verb: %s\nverb hit counts: %s" % [last_contact_verb, mechanism_verb_counts]

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
	var frequency: float = float({"swing_light": 245.0, "swing_heavy": 150.0, "whiff": 360.0, "hit": 118.0, "heavy_hit": 64.0, "dodge": 310.0, "hurt": 92.0}.get(kind, 140.0))
	var duration: float = float({"swing_light": 0.045, "swing_heavy": 0.072, "whiff": 0.065, "hit": 0.085, "heavy_hit": 0.16, "dodge": 0.055, "hurt": 0.10}.get(kind, 0.07))
	var stream := AudioStreamWAV.new(); stream.format = AudioStreamWAV.FORMAT_16_BITS; stream.mix_rate = 22050; stream.stereo = false
	var sample_count := int(stream.mix_rate * duration)
	var data := PackedByteArray(); data.resize(sample_count * 2)
	for index: int in range(sample_count):
		var envelope := 1.0 - float(index) / float(sample_count)
		var phase := TAU * frequency * float(index) / float(stream.mix_rate)
		var wave := sin(phase)
		if kind == "heavy_hit": wave = sin(phase) * 0.70 + sin(phase * 0.51) * 0.45
		if kind == "whiff": wave = sin(phase * (1.0 + float(index) / float(sample_count) * 1.6)) * 0.55
		var noise := randf_range(-0.18, 0.18) if kind in ["hit", "heavy_hit"] else (randf_range(-0.08, 0.08) if kind == "whiff" else 0.0)
		var gain := 0.55 if kind == "heavy_hit" else 0.38
		data.encode_s16(index * 2, roundi(clampf((wave + noise) * envelope * gain, -1.0, 1.0) * 32767.0))
	stream.data = data; audio_player.stream = stream; audio_player.play()

func _attack_motion_ratio() -> float:
	if controller == null or controller.phase == "idle":
		return 0.0
	var ratio: float = controller.phase_ratio()
	match controller.phase:
		"startup": return ratio * 0.30
		"active": return 0.30 + ratio * 0.52
		"recovery": return 0.82 + ratio * 0.18
	return 0.0


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
	result = _apply_grip_topology_pose(result, contact)
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


func _apply_grip_topology_pose(pose: Dictionary, contact: float) -> Dictionary:
	if motion_profile == null:
		return pose
	match str(motion_profile.grip_topology):
		"two_hand_handle":
			pose["crouch"] = float(pose["crouch"]) + 2.0 * contact
			pose["torso_rotation"] = float(pose["torso_rotation"]) * 1.08
			pose["back_foot_local"] = Vector2(pose["back_foot_local"]) + Vector2(-4.0, 0.0)
			pose["front_foot_local"] = Vector2(pose["front_foot_local"]) + Vector2(4.0, 0.0)
		"body_grip":
			pose["body_offset"] = Vector2(pose["body_offset"]) * 0.72
			pose["hand_local"] = Vector2(pose["hand_local"]).lerp(Vector2(24.0, -5.0), 0.28)
			pose["crouch"] = float(pose["crouch"]) + 6.0 * contact
			pose["torso_rotation"] = float(pose["torso_rotation"]) * 1.18
			pose["back_foot_local"] = Vector2(-23.0, 43.0)
			pose["front_foot_local"] = Vector2(23.0, 43.0)
		"clamp_grip":
			pose["body_offset"] = Vector2(pose["body_offset"]) * 0.45
			pose["hand_local"] = Vector2(pose["hand_local"]).lerp(Vector2(23.0, -9.0), 0.48)
			pose["torso_rotation"] = float(pose["torso_rotation"]) * 0.58
			pose["main_elbow_local"] = Vector2(pose["main_elbow_local"]).lerp(Vector2(15.0, -4.0), 0.42)
			pose["back_foot_local"] = Vector2(-10.0, 45.0)
			pose["front_foot_local"] = Vector2(12.0, 45.0)
		_:
			pose["front_foot_local"] = Vector2(pose["front_foot_local"]) + Vector2(2.0 * contact, 0.0)
	return pose


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
		var trajectory_ratio := _trajectory_motion_ratio(primitive, motion_ratio)
		var direction := signf(float(primitive.end_angle) - float(primitive.start_angle))
		if is_zero_approx(direction): direction = 1.0
		var follow_phase := clampf((motion_ratio - 0.76) / 0.24, 0.0, 1.0)
		var follow_through := sin(follow_phase * PI) * float(primitive.follow_through_radians) * direction
		angle = (lerpf(primitive.start_angle, primitive.end_angle, trajectory_ratio) + follow_through) * player_facing
		extension = sin(trajectory_ratio * PI) * primitive.extension_pixels
		local_offset = primitive.local_start_offset.lerp(primitive.local_end_offset, trajectory_ratio)
	return {"angle": angle, "extension": extension, "local_offset": local_offset}


func _trajectory_motion_ratio(primitive: Variant, motion_ratio: float) -> float:
	var delay := clampf(float(primitive.trajectory_lag_ratio) * 0.22, 0.0, 0.30)
	var propagated := clampf((motion_ratio - delay) / maxf(0.01, 1.0 - delay), 0.0, 1.0)
	# Main body and attached tether are independent propagation stages. Composite
	# mechanisms transfer motion through the body first and the tether second.
	propagated = _propagate_by_topology(str(primitive.flex_topology), propagated)
	return _propagate_by_topology(str(primitive.tether_topology), propagated)


func _propagate_by_topology(topology: String, ratio: float) -> float:
	match topology:
		"bending_shaft": return smoothstep(0.0, 1.0, ratio)
		"flexible_line": return pow(ratio, 1.60)
		"linked_segments": return pow(ratio, 1.34)
	return ratio


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
	var run_bob := _run_bob_offset().y
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
	if motion_profile.grip_topology == "body_grip" and secondary_delta.length() < 2.0:
		second_hand = weapon_origin + Vector2(-10.0 * player_facing, 5.0)
	var main_shoulder := _pose_local_point(base, Vector2(character_pose["main_shoulder_local"]) + Vector2(0.0, crouch * 0.28), torso_rotation)
	var main_elbow := _pose_local_point(base, Vector2(character_pose["main_elbow_local"]) + Vector2(0.0, crouch * 0.24), torso_rotation * 0.55)
	var support_shoulder := _pose_local_point(base, Vector2(character_pose["support_shoulder_local"]) + Vector2(0.0, crouch * 0.28), torso_rotation)
	var support_elbow := _pose_local_point(base, Vector2(character_pose["support_elbow_local"]) + Vector2(0.0, crouch * 0.24), torso_rotation * 0.45)
	if motion_profile.grip_mode == "two_hand" or motion_profile.grip_topology == "body_grip":
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
	var primitive: Variant = _current_attack_primitive()
	if _uses_pixel_visual_deformation(primitive):
		var soft_geometry := _soft_visual_geometry(primitive, Vector2(0.0, run_bob))
		_draw_deformed_pixel_weapon(soft_geometry)
		if debug_visible:
			_draw_soft_mechanism_overlay(soft_geometry)
	else:
		draw_set_transform(weapon_origin, float(pose["angle"]), Vector2(player_facing * motion_profile.render_scale, motion_profile.render_scale))
		draw_texture_rect(asset.texture, Rect2(-asset.grip_primary, Vector2(asset.canvas_size)), false)
		draw_set_transform(Vector2.ZERO)
	_draw_stateful_mechanism(primitive, hand)
	draw_circle(weapon_origin, 4.0, Color("f6d1ac"))


func _draw_stateful_mechanism(primitive: Variant, hand: Vector2) -> void:
	if primitive == null or float(primitive.state_extent_ratio) <= 0.0 or controller.phase == "idle":
		return
	var phase_power := 1.0
	if controller.phase == "startup":
		phase_power = smoothstep(0.0, 1.0, controller.phase_ratio())
	elif controller.phase == "recovery" and str(primitive.activation_mode) != "toggle":
		phase_power = 1.0 - smoothstep(0.0, 1.0, controller.phase_ratio())
	var power := clampf(float(primitive.state_extent_ratio) * phase_power, 0.0, 1.0)
	if power <= 0.02:
		return
	var contact := _primitive_contact_world(primitive, hand)
	var direction := (contact - hand).normalized()
	if direction.length_squared() < 0.5:
		direction = Vector2(player_facing, 0.0)
	var normal := Vector2(-direction.y, direction.x)
	var cyan := Color(0.22, 0.90, 1.0, 0.34 + power * 0.34)
	var gold := Color(1.0, 0.70, 0.18, 0.34 + power * 0.38)
	match str(primitive.state_topology):
		"hinged":
			draw_line(contact, contact + direction.rotated(0.86) * 34.0 * power, gold, 5.0)
			draw_circle(contact, 6.0, cyan)
		"folding":
			var p1 := contact + direction.rotated(0.52) * 22.0 * power
			var p2 := p1 + direction.rotated(-0.48) * 25.0 * power
			draw_polyline(PackedVector2Array([contact, p1, p2]), gold, 5.0, false)
			draw_circle(p1, 5.0, cyan)
		"telescoping":
			for offset: float in [10.0, 22.0, 34.0]:
				var center := contact + direction * offset * power
				draw_line(center - normal * 7.0, center + normal * 7.0, gold, 3.0)
		"radial_expand":
			var radius := 12.0 + 27.0 * power
			for angle: float in [-1.2, -0.6, 0.0, 0.6, 1.2]:
				draw_line(contact, contact + direction.rotated(angle) * radius, gold, 3.0)
			draw_arc(contact, radius, direction.angle() - 1.25, direction.angle() + 1.25, 22, cyan, 4.0)
		"rotary":
			var radius := 16.0 + 12.0 * power
			draw_arc(contact, radius, 0.0, TAU, 28, cyan, 4.0)
			for angle: float in [0.0, PI * 0.5, PI, PI * 1.5]:
				var spun := angle + elapsed_seconds * 12.0
				draw_line(contact + Vector2.from_angle(spun) * 5.0, contact + Vector2.from_angle(spun) * radius, gold, 3.0)
	match str(primitive.functional_output):
		"directed_stream":
			var finish: Vector2 = hand + direction * float(motion_profile.reach_pixels) * float(primitive.reach_multiplier)
			draw_colored_polygon(PackedVector2Array([contact, finish + normal * 24.0 * power, finish - normal * 24.0 * power]), Color(cyan, 0.18 + power * 0.18))
			for offset: float in [-0.55, 0.0, 0.55]:
				draw_line(contact, finish + normal * 22.0 * offset, cyan, 2.0)
		"radial_field":
			var radius: float = float(motion_profile.reach_pixels) * float(primitive.reach_multiplier) * 0.64 * power
			draw_arc(hand, radius, 0.0, TAU, 40, cyan, 5.0)
		"pull_field":
			var finish: Vector2 = hand + direction * float(motion_profile.reach_pixels) * float(primitive.reach_multiplier)
			for ratio: float in [0.45, 0.70, 0.94]:
				var center: Vector2 = hand.lerp(finish, ratio)
				draw_polyline(PackedVector2Array([center + direction * 10.0 + normal * 10.0, center, center + direction * 10.0 - normal * 10.0]), cyan, 3.0, false)


func _draw_deformed_pixel_weapon(soft_geometry: Dictionary) -> void:
	if asset == null or asset.visual_rig == null:
		return
	var deformation := _pixel_weapon_deformation(soft_geometry)
	for pixel: Dictionary in deformation.get("pixels", []):
		var size := float(pixel.get("size", 1.0))
		var position := Vector2(pixel.get("position", Vector2.ZERO))
		draw_rect(
			Rect2(position - Vector2(size, size) * 0.5, Vector2(size, size)),
			Color(pixel.get("color", Color.WHITE)),
			true
		)


func _pixel_weapon_deformation(soft_geometry: Dictionary) -> Dictionary:
	if asset == null or asset.visual_rig == null:
		return {"pixels": [], "errors": ["PIXEL_VISUAL_RIG_MISSING"]}
	var pose: Dictionary = soft_geometry.get("pose", {})
	return PIXEL_WEAPON_DEFORMER.deform(asset.visual_rig, {
		"body": soft_geometry.get("body", PackedVector2Array()),
		"tether": soft_geometry.get("tether", PackedVector2Array()),
		"weapon_origin": soft_geometry.get("weapon_origin", Vector2.ZERO),
		"source_grip": asset.grip_primary,
		"contact": soft_geometry.get("contact", Vector2.ZERO),
		"weapon_angle": float(pose.get("angle", 0.0)),
		"facing": player_facing,
		"scale": motion_profile.render_scale,
		"pixel_snap": true,
	})


func _draw_soft_mechanism_overlay(soft_geometry: Dictionary) -> void:
	var primitive: Variant = soft_geometry.get("primitive")
	if primitive == null:
		return
	var contact := Vector2(soft_geometry.get("contact", Vector2.ZERO))
	var paths := {
		"body": soft_geometry.get("body", PackedVector2Array()),
		"tether": soft_geometry.get("tether", PackedVector2Array()),
	}
	var body_points: PackedVector2Array = paths.get("body", PackedVector2Array())
	var tether_points: PackedVector2Array = paths.get("tether", PackedVector2Array())
	if body_points.size() >= 2:
		draw_polyline(body_points, Color(0.40, 0.91, 0.98, 0.46), 2.0, false)
		_draw_link_nodes(body_points, str(primitive.flex_topology))
	if tether_points.size() >= 2:
		draw_polyline(tether_points, Color(0.98, 0.80, 0.08, 0.46), 1.0, false)
		_draw_link_nodes(tether_points, str(primitive.tether_topology))
	draw_circle(contact, 2.0, Color(1.0, 0.55, 0.23, 0.58))


func _uses_pixel_visual_deformation(primitive: Variant) -> bool:
	return primitive != null \
		and asset != null \
		and asset.has_pixel_visual_rig() \
		and (str(primitive.flex_topology) != "none" or str(primitive.tether_topology) != "none")


func _soft_visual_geometry(primitive: Variant, bob_offset: Vector2 = Vector2.ZERO) -> Dictionary:
	if primitive == null or asset == null:
		return {}
	var pose := _weapon_pose()
	var raw_hand := _hand_world_position() + bob_offset
	var weapon_origin := _weapon_origin_world(raw_hand, pose)
	var body_origin := _visual_rig_body_origin_world(weapon_origin, pose)
	var resting_contact := _primitive_contact_world(primitive, raw_hand)
	var tether_origin := _primitive_tether_origin_world(primitive, raw_hand, weapon_origin, resting_contact, pose)
	var deployment_target := _tether_delivery_target(primitive, raw_hand, resting_contact)
	var deployment := _tether_deployment_state(
		primitive,
		tether_origin,
		deployment_target,
		resting_contact,
		_attack_motion_ratio()
	)
	var contact := Vector2(deployment.get("contact", resting_contact))
	var paths := _soft_mechanism_paths(body_origin, contact, primitive, tether_origin)
	return {
		"primitive": primitive,
		"pose": pose,
		"hand": raw_hand,
		"weapon_origin": weapon_origin,
		"body_origin": body_origin,
		"contact": contact,
		"resting_contact": resting_contact,
		"deployment_target": deployment_target,
		"deployment_phase": str(deployment.get("phase", "fixed")),
		"deployed_ratio": float(deployment.get("deployed_ratio", 1.0)),
		"tether_origin": tether_origin,
		"body": paths.get("body", PackedVector2Array()),
		"tether": paths.get("tether", PackedVector2Array()),
	}


func _tether_delivery_target(primitive: Variant, hand: Vector2, resting_contact: Vector2) -> Vector2:
	if primitive == null or str(primitive.tether_deployment) not in ["cast_retract", "launch_tension"]:
		return resting_contact
	var contact_vector := resting_contact - hand
	var direction := contact_vector.normalized() if contact_vector.length_squared() > 0.01 else Vector2(player_facing, 0.0)
	var delivery_reach := contact_vector.length()
	if motion_profile != null:
		var timing: Dictionary = controller.current_timing() if controller != null else {}
		delivery_reach = maxf(
			delivery_reach,
			float(motion_profile.reach_pixels)
				* float(timing.get("reach_scale", primitive.reach_multiplier))
				* float(primitive.hitbox_length_multiplier)
		)
	return hand + direction * delivery_reach


func _tether_deployment_state(
	primitive: Variant,
	tether_origin: Vector2,
	deployed_target: Vector2,
	resting_contact: Vector2,
	motion_ratio: float
) -> Dictionary:
	var mode := str(primitive.tether_deployment) if primitive != null else "none"
	if mode not in ["cast_retract", "launch_tension"]:
		return {
			"contact": resting_contact,
			"phase": "fixed",
			"deployed_ratio": 1.0,
		}
	var ratio := clampf(motion_ratio, 0.0, 1.0)
	var full_span := maxf(1.0, tether_origin.distance_to(deployed_target))
	var tuck_distance := clampf(full_span * 0.16, 10.0, 18.0)
	var tuck_direction := Vector2(-player_facing * 0.28, 1.0).normalized()
	var tucked_contact := tether_origin + tuck_direction * tuck_distance
	var contact := resting_contact
	var phase := "load"

	if ratio < 0.22:
		var load_ratio := smoothstep(0.0, 1.0, ratio / 0.22)
		contact = resting_contact.lerp(tucked_contact, load_ratio)
	elif ratio < 0.30:
		contact = tucked_contact
		phase = "loaded"
	else:
		var outbound_end := 0.62 if mode == "cast_retract" else 0.56
		if ratio < outbound_end:
			var outbound_ratio := smoothstep(0.0, 1.0, (ratio - 0.30) / (outbound_end - 0.30))
			var travel := deployed_target - tucked_contact
			var arc_height := minf(34.0, travel.length() * (0.20 if mode == "cast_retract" else 0.13))
			contact = tucked_contact.lerp(deployed_target, outbound_ratio) \
				+ Vector2.UP * sin(outbound_ratio * PI) * arc_height
			phase = "outbound"
		elif mode == "launch_tension" or ratio < 0.84:
			contact = deployed_target
			phase = "tensioned"
		elif ratio < 0.96:
			var retract_ratio := smoothstep(0.0, 1.0, (ratio - 0.84) / 0.12)
			contact = deployed_target.lerp(tucked_contact, retract_ratio)
			phase = "retract"
		else:
			var settle_ratio := smoothstep(0.0, 1.0, (ratio - 0.96) / 0.04)
			contact = tucked_contact.lerp(resting_contact, settle_ratio)
			phase = "settle"
	return {
		"contact": contact,
		"phase": phase,
		"deployed_ratio": clampf(tether_origin.distance_to(contact) / full_span, 0.0, 1.25),
	}


func _weapon_origin_world(raw_hand: Vector2, pose: Dictionary) -> Vector2:
	var local_offset: Vector2 = pose.get("local_offset", Vector2.ZERO)
	return raw_hand + Vector2(
		float(pose.get("extension", 0.0)) * player_facing + local_offset.x * player_facing,
		local_offset.y
	)


func _visual_rig_body_origin_world(weapon_origin: Vector2, pose: Dictionary) -> Vector2:
	if asset == null or asset.visual_rig == null:
		return weapon_origin
	var source_path := asset.visual_rig.source_path_for_role("deform_body")
	if source_path.is_empty():
		return weapon_origin
	var local_origin := source_path[0] - asset.grip_primary
	local_origin = Vector2(local_origin.x * player_facing, local_origin.y) * motion_profile.render_scale
	return weapon_origin + local_origin.rotated(float(pose.get("angle", 0.0)))


func _run_bob_offset() -> Vector2:
	if Input.get_vector("move_left", "move_right", "move_up", "move_down").length() <= 0.1:
		return Vector2.ZERO
	return Vector2(0.0, sin(elapsed_seconds * 12.0) * 2.0)


func _soft_mechanism_paths(
	hand: Vector2,
	contact: Vector2,
	primitive: Variant,
	tether_origin: Vector2 = Vector2(INF, INF)
) -> Dictionary:
	var body_topology := str(primitive.flex_topology)
	var tether_topology := str(primitive.tether_topology)
	var split := contact
	if tether_topology != "none":
		if is_finite(tether_origin.x) and is_finite(tether_origin.y):
			split = tether_origin
		else:
			split = hand.lerp(contact, clampf(float(primitive.tether_origin_ratio), 0.0, 1.0))
	var motion_ratio := 0.55 if controller == null else _attack_motion_ratio()
	var combo_index := 1 if controller == null else maxi(1, int(controller.combo_index))
	var bend_sign := -player_facing if combo_index % 2 == 1 else player_facing
	var body_points := PackedVector2Array()
	var tether_points := PackedVector2Array()
	if body_topology != "none":
		body_points = _soft_curve_points(
			hand,
			split if tether_topology != "none" else contact,
			body_topology,
			_propagate_by_topology(body_topology, motion_ratio),
			bend_sign
		)
	if tether_topology != "none":
		tether_points = _soft_curve_points(
			split,
			contact,
			tether_topology,
			_propagate_by_topology(tether_topology, motion_ratio),
			bend_sign
		)
	return {"body": body_points, "tether": tether_points, "split": split}


func _soft_curve_points(
	start: Vector2,
	finish: Vector2,
	topology: String,
	propagation: float,
	bend_sign: float
) -> PackedVector2Array:
	var span := finish - start
	var points := PackedVector2Array()
	if span.length_squared() < 1.0:
		points.append(start)
		points.append(finish)
		return points
	var normal := Vector2(-span.y, span.x).normalized()
	var bend_scale: float = float({
		"bending_shaft": 0.10,
		"flexible_line": 0.22,
		"linked_segments": 0.16,
	}.get(topology, 0.0))
	var bend := span.length() * bend_scale * sin((0.18 + propagation * 0.82) * PI)
	var steps := 9 if topology == "linked_segments" else 14
	for index: int in range(steps + 1):
		var ratio := float(index) / float(steps)
		var envelope := sin(ratio * PI)
		if topology == "flexible_line":
			envelope *= 0.45 + ratio * 0.85
		points.append(start + span * ratio + normal * bend * bend_sign * envelope)
	return points


func _primitive_tether_origin_world(
	primitive: Variant,
	raw_hand: Vector2,
	weapon_origin: Vector2,
	contact: Vector2,
	pose: Dictionary = {}
) -> Vector2:
	if asset == null or asset.tether_origin == Vector2.ZERO or asset.tether_origin == asset.tip:
		return weapon_origin.lerp(contact, clampf(float(primitive.tether_origin_ratio), 0.0, 1.0))
	if pose.is_empty():
		pose = _weapon_pose()
	var offset := Vector2(float(pose["extension"]) * player_facing, 0.0)
	var local_offset: Vector2 = pose.get("local_offset", Vector2.ZERO)
	offset += Vector2(local_offset.x * player_facing, local_offset.y)
	var local_anchor := asset.tether_origin - asset.grip_primary
	local_anchor = Vector2(local_anchor.x * player_facing, local_anchor.y) * motion_profile.render_scale
	return raw_hand + offset + local_anchor.rotated(float(pose["angle"]))


func _draw_link_nodes(points: PackedVector2Array, topology: String) -> void:
	if topology != "linked_segments":
		return
	for index: int in range(1, points.size() - 1):
		draw_circle(points[index], 2.8, Color("d6d3d1"))


func _soft_visual_attack_contains(target: Vector2, primitive: Variant, hitbox_thickness: float, deadzone: float) -> bool:
	var geometry := _soft_visual_geometry(primitive, _run_bob_offset())
	if geometry.is_empty():
		return false
	var contact := Vector2(geometry.get("contact", Vector2.ZERO))
	match str(primitive.contact_surface):
		"point":
			return target.distance_to(contact) <= _contact_radius(hitbox_thickness, primitive)
		"broad":
			return target.distance_to(contact) <= _contact_radius(hitbox_thickness, primitive) \
				+ (16.0 if controller.attack_kind == "charge" else 0.0)
		_:
			var path := PIXEL_WEAPON_DEFORMER.joined_paths(
				geometry.get("body", PackedVector2Array()),
				geometry.get("tether", PackedVector2Array())
			)
			if path.size() < 2:
				return false
			var full_length := float(PIXEL_WEAPON_DEFORMER.path_signature(path).get("length", 0.0))
			var deadzone_ratio := deadzone / maxf(1.0, full_length)
			var active_start := maxf(deadzone_ratio, float(primitive.soft_contact_start_ratio))
			return PIXEL_WEAPON_DEFORMER.distance_to_polyline(target, path, active_start) <= hitbox_thickness * 0.5


func _draw_soft_visual_hitbox(primitive: Variant, hitbox_thickness: float, deadzone: float, color: Color) -> void:
	var geometry := _soft_visual_geometry(primitive, _run_bob_offset())
	if geometry.is_empty():
		return
	var contact := Vector2(geometry.get("contact", Vector2.ZERO))
	match str(primitive.contact_surface):
		"point":
			draw_circle(contact, _contact_radius(hitbox_thickness, primitive), color)
		"broad":
			draw_circle(contact, _contact_radius(hitbox_thickness, primitive) + (16.0 if controller.attack_kind == "charge" else 0.0), color)
		_:
			var path := PIXEL_WEAPON_DEFORMER.joined_paths(
				geometry.get("body", PackedVector2Array()),
				geometry.get("tether", PackedVector2Array())
			)
			var full_length := float(PIXEL_WEAPON_DEFORMER.path_signature(path).get("length", 0.0))
			var deadzone_ratio := deadzone / maxf(1.0, full_length)
			var active_start := maxf(deadzone_ratio, float(primitive.soft_contact_start_ratio))
			var active_path := PIXEL_WEAPON_DEFORMER.trim_polyline(path, active_start)
			if active_path.size() >= 2:
				draw_polyline(active_path, color, hitbox_thickness, false)
			elif active_path.size() == 1:
				draw_circle(active_path[0], hitbox_thickness * 0.5, color)

func _draw_active_hitbox() -> void:
	var hand := _hand_world_position() + _run_bob_offset()
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
	if _mechanism_experiment_enabled():
		color = PERCEPTIBLE_CONTACT.color_for_verb(
			PERCEPTIBLE_CONTACT.verb_for(primitive),
			0.48 if is_finisher else 0.34
		)
	var contact_world := _primitive_contact_world(primitive, hand) if primitive != null else hand + Vector2(player_facing * reach * 0.72, 0.0)
	var contact_vector := contact_world - hand
	contact_vector = _categorical_contact_vector(primitive, contact_vector, reach)
	var surface := str(primitive.contact_surface)
	var deadzone := _soft_contact_deadzone(primitive, contact_vector, reach, float(primitive.inner_deadzone_pixels))
	if _draw_stateful_hitbox(primitive, hand, contact_world, reach, hitbox_thickness, deadzone, color):
		return
	if _uses_pixel_visual_deformation(primitive):
		_draw_soft_visual_hitbox(primitive, hitbox_thickness, deadzone, color)
		if deadzone > 0.0:
			draw_arc(hand, deadzone, 0.0, TAU, 24, Color(0.2, 0.9, 1.0, 0.65), 2.0)
		return
	match surface:
		"point":
			if _uses_terminal_contact_collision(primitive): draw_circle(contact_world, _contact_radius(hitbox_thickness, primitive), color)
			elif motion_family == "thrust": draw_colored_polygon(_point_lane_polygon(hand, contact_vector, reach, hitbox_thickness, primitive), color)
			else: draw_circle(contact_world, _contact_radius(hitbox_thickness, primitive), color)
		"edge":
			if motion_family == "spin": _draw_spin_contact(hand, _spin_contact_reach(primitive, contact_vector, reach), deadzone, color)
			else: _draw_contact_band(hand, contact_vector, reach, hitbox_thickness, primitive, deadzone, color)
		"broad":
			draw_circle(contact_world, _contact_radius(hitbox_thickness, primitive) + (16.0 if controller.attack_kind == "charge" else 0.0), color)
		"whole_body":
			if motion_family == "spin": _draw_spin_contact(hand, _spin_contact_reach(primitive, contact_vector, reach), deadzone, color)
			else: _draw_contact_band(hand, contact_vector, reach, hitbox_thickness, primitive, deadzone, color)
		_:
			_draw_contact_band(hand, contact_vector, reach, hitbox_thickness, primitive, deadzone, color)
	if deadzone > 0.0:
		draw_arc(hand, deadzone, 0.0, TAU, 24, Color(0.2, 0.9, 1.0, 0.65), 2.0)


func _draw_stateful_hitbox(primitive: Variant, hand: Vector2, contact: Vector2, reach: float, thickness: float, deadzone: float, color: Color) -> bool:
	if primitive == null or float(primitive.state_extent_ratio) <= 0.0:
		return false
	var direction := (contact - hand).normalized()
	if direction.length_squared() < 0.5:
		direction = Vector2(player_facing, 0.0)
	var normal := Vector2(-direction.y, direction.x)
	var output := str(primitive.functional_output)
	var state := str(primitive.state_topology)
	if output in ["directed_stream", "pull_field"]:
		var start := hand + direction * deadzone
		var finish := hand + direction * reach
		draw_colored_polygon(PackedVector2Array([start - normal * thickness * 0.14, finish - normal * thickness * 1.18, finish + normal * thickness * 1.18, start + normal * thickness * 0.14]), color)
		return true
	if output == "radial_field":
		draw_circle(hand, reach * 0.82, color)
		return true
	if state == "radial_expand":
		draw_circle(contact, thickness * 0.92 + 22.0, color)
		return true
	if state == "rotary":
		draw_circle(contact, thickness * 0.72 + 16.0, color)
		return true
	if state == "telescoping":
		draw_colored_polygon(_point_lane_polygon(hand, contact - hand, reach, thickness * 0.84, primitive), color)
		return true
	return false


func _draw_contact_band(hand: Vector2, contact_vector: Vector2, reach: float, thickness: float, primitive: Variant, deadzone: float, color: Color) -> void:
	var current_reach := _current_contact_reach(contact_vector, reach)
	if current_reach <= deadzone:
		return
	var arc_degrees := _instantaneous_contact_arc_degrees(primitive, current_reach, thickness)
	var half_arc := deg_to_rad(arc_degrees * 0.5)
	var center_angle := _contact_direction(contact_vector).angle()
	var steps := maxi(4, ceili(arc_degrees / 8.0))
	var points := PackedVector2Array()
	for index: int in range(steps + 1):
		var angle := lerpf(center_angle - half_arc, center_angle + half_arc, float(index) / float(steps))
		points.append(hand + Vector2.from_angle(angle) * current_reach)
	if deadzone > 0.0:
		for index: int in range(steps, -1, -1):
			var angle := lerpf(center_angle - half_arc, center_angle + half_arc, float(index) / float(steps))
			points.append(hand + Vector2.from_angle(angle) * deadzone)
	else:
		points.append(hand)
	draw_colored_polygon(points, color)


func _draw_spin_contact(hand: Vector2, outer_radius: float, inner_radius: float, color: Color) -> void:
	if outer_radius <= inner_radius:
		return
	if inner_radius > 0.0:
		var center_radius := (outer_radius + inner_radius) * 0.5
		draw_arc(hand, center_radius, 0.0, TAU, 48, color, outer_radius - inner_radius, true)
	else:
		draw_circle(hand, outer_radius, color)

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


func _capture_visual_rig_evidence(directory: String) -> void:
	game_active = false
	capture_pose_only = true
	debug_visible = false
	var capture_directory := ProjectSettings.globalize_path(directory) if directory.begins_with("res://") or directory.begins_with("user://") else directory
	print("PIXEL_VISUAL_RIG_CAPTURE_STARTED:", capture_directory)
	var directory_error := DirAccess.make_dir_recursive_absolute(capture_directory)
	if directory_error != OK:
		push_error("PIXEL_VISUAL_RIG_CAPTURE_DIRECTORY_FAILED:%s:%s" % [capture_directory, error_string(directory_error)])
		get_tree().quit(1)
		return
	_cleanup_enemies()
	particles.clear()
	player_position = Vector2(590.0, 410.0)
	player_facing = 1.0
	controller.phase = "idle"
	controller.current_primitive = null
	var original := Image.new()
	original.copy_from(asset.source_image)
	original.resize(original.get_width() * 3, original.get_height() * 3, Image.INTERPOLATE_NEAREST)
	var original_error := original.save_png(capture_directory.path_join("00_original_silhouette.png"))
	if original_error != OK:
		push_error("PIXEL_VISUAL_RIG_CAPTURE_SAVE_FAILED:00:%s" % error_string(original_error))
	for hit_index: int in [1, 2, 3]:
		controller.attack_kind = "normal"
		controller.combo_index = hit_index
		controller.current_primitive = motion_profile.combo_recipe.primitive_for(hit_index)
		controller.phase = "active"
		controller.phase_duration = 1.0
		controller.phase_elapsed = 0.52
		var soft_geometry := _soft_visual_geometry(controller.current_primitive)
		var deformation := _pixel_weapon_deformation(soft_geometry)
		var raster: Dictionary = PIXEL_WEAPON_DEFORMER.rasterize(deformation, 10, 3)
		var image := raster.get("image") as Image
		if image == null:
			push_error("PIXEL_VISUAL_RIG_CAPTURE_EMPTY:%02d" % hit_index)
			continue
		var save_error := image.save_png(capture_directory.path_join("%02d_mechanism_pixels.png" % hit_index))
		if save_error != OK:
			push_error("PIXEL_VISUAL_RIG_CAPTURE_SAVE_FAILED:%02d:%s" % [hit_index, error_string(save_error)])
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
		get_tree().change_scene_to_file("res://scenes/open_identity_spike.tscn")
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
