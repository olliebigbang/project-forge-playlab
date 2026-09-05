class_name GameplayArena
extends Node2D

signal stage_completed(stage_name: String, metrics: Dictionary)
signal metrics_changed(metrics: Dictionary)

const RULES := preload("res://scripts/systems/combat_rules.gd")
const RANGED_AXIS_RESOLVER := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")
const FIREARM_ACTION_CHOREOGRAPHY := preload(
	"res://scripts/combat_feel/firearm_action_choreography.gd"
)
const PIXEL_WEAPON_DEFORMER := preload("res://scripts/combat_feel/pixel_weapon_deformer.gd")
const STATEFUL_PIXEL_MORPHER := preload("res://scripts/combat_feel/stateful_pixel_weapon_morpher.gd")
const TARGET_INTERACTION := preload("res://scripts/combat_feel/weapon_target_interaction_resolver.gd")
const WEAPON_PLAYER_FIT := preload("res://scripts/combat_feel/weapon_player_fit_compiler.gd")
const WEAPON_STRATEGY := preload("res://scripts/combat_feel/weapon_strategy_compiler.gd")
const MELEE_RUNTIME := preload("res://scripts/combat_feel/arena_melee_runtime.gd")
const ENEMY_ATTACK_RUNTIME := preload("res://scripts/enemy_attack/enemy_attack_runtime_driver.gd")
const ENEMY_ATTACK_VISUAL := preload("res://scripts/enemy_attack/enemy_attack_visual_language.gd")
const ENEMY_ATTACK_SPRITE := preload("res://scripts/enemy_attack/enemy_attack_sprite_language.gd")
const ENEMY_IDENTITY_VISUAL := preload("res://scripts/enemy_attack/enemy_identity_visual_language.gd")
const ENEMY_VISUAL_ASSET_LIBRARY := preload("res://scripts/enemy_attack/enemy_visual_asset_library.gd")
const PLAYER_BASE_TEXTURE := preload("res://assets/player/forge_wanderer_base_v2.png")
const WORLD_RECT := Rect2(34, 116, 1212, 568)

const TARGET_MECHANICAL_PROFILES := {
	"swarmling": {"mass_class": "light", "armor_integrity": 0.0},
	"rusher": {"mass_class": "medium", "armor_integrity": 0.0},
	"guard": {"mass_class": "heavy", "armor_integrity": 1.0},
	"target": {"mass_class": "medium", "armor_integrity": 0.0},
	"moving_target": {"mass_class": "medium", "armor_integrity": 0.0},
}
const TARGET_ATTACK_DECLARATIONS := {
	"swarmling": [{
		"attack_key": "slot_quick_contact",
		"axes": {
			"delivery": "contact", "target_lock": "live_until_active",
			"hit_shape": "capsule", "depth_path": "same_lane", "tempo": "quick",
			"stability": "fragile", "recovery": "brief",
		},
		"selection": {
			"preferred_range": "close", "depth_fit": "aligned", "base_priority": 65,
			"coordination_cost": 1, "requires_clear_path": false, "selection_rank": 10,
		},
	}],
	"rusher": [{
		"attack_key": "slot_locked_rush",
		"axes": {
			"delivery": "rush", "target_lock": "direction_on_commit",
			"hit_shape": "strip", "depth_path": "cross_depth", "tempo": "committed",
			"stability": "tell_interruptible", "recovery": "extended",
		},
		"selection": {
			"preferred_range": "mid", "depth_fit": "tolerant", "base_priority": 72,
			"coordination_cost": 1, "requires_clear_path": true, "selection_rank": 10,
		},
	}, {
		"attack_key": "slot_marked_crash",
		"axes": {
			"delivery": "marked_impact", "target_lock": "point_on_commit",
			"hit_shape": "circle", "depth_path": "depth_band", "tempo": "committed",
			"stability": "fragile", "recovery": "extended",
		},
		"selection": {
			"preferred_range": "far", "depth_fit": "any", "base_priority": 66,
			"coordination_cost": 1, "requires_clear_path": false, "selection_rank": 20,
		},
	}],
	"guard": [{
		"attack_key": "slot_guard_arc",
		"axes": {
			"delivery": "contact", "target_lock": "direction_on_commit",
			"hit_shape": "arc", "depth_path": "same_lane", "tempo": "standard",
			"stability": "armored_commit", "recovery": "punishable",
		},
		"selection": {
			"preferred_range": "close", "depth_fit": "aligned", "base_priority": 58,
			"coordination_cost": 1, "requires_clear_path": false, "selection_rank": 10,
		},
	}, {
		"attack_key": "slot_guard_projectile",
		"axes": {
			"delivery": "projectile", "target_lock": "direction_on_commit",
			"hit_shape": "capsule", "depth_path": "same_lane", "tempo": "standard",
			"stability": "tell_interruptible", "recovery": "punishable",
		},
		"selection": {
			"preferred_range": "far", "depth_fit": "aligned", "base_priority": 64,
			"coordination_cost": 1, "requires_clear_path": true, "selection_rank": 20,
		},
	}],
}

var stage_name := "training"
var blueprint: WeaponBlueprint
var asset: WeaponVisualAsset
var player_position := Vector2(250, 420)
var player_health := 100.0
var facing := 1.0
var enemies: Array[Dictionary] = []
var custom_enemy_blueprints: Array[Dictionary] = []
var enemy_visual_assets: RefCounted = ENEMY_VISUAL_ASSET_LIBRARY.new()
var arena_background_texture: Texture2D
var projectiles: Array[Dictionary] = []
var enemy_attack_hazards: Array[Dictionary] = []
var boomerang: Dictionary = {}
var active := false
var debug_anchors := false
var touch_vector := Vector2.ZERO
var touch_attack := false
var touch_attack_requested := false
var touch_dodge_requested := false
var attack_was_down := false
var attack_charge := 0.0
var shot_cooldown := 0.0
var burst_shots_remaining := 0
var manual_cycle_timer := 0.0
var active_cycle_action_code := 0
var pending_reload_after_cycle := false
var overheat := 0.0
var overheat_lock := 0.0
var ranged_runtime_profile: Dictionary = {}
var weapon_strategy_profile: Dictionary = {}
var ammo_in_magazine := 0
var reload_timer := 0.0
var weapon_recoil_offset := 0.0
var weapon_muzzle_climb_degrees := 0.0
var sustained_muzzle_climb_degrees := 0.0
var sustained_fire_window_timer := 0.0
var muzzle_flash_timer := 0.0
var muzzle_flash_scale := 1.0
var melee_timer := 0.0 # Status only; never determines hits.
var melee_runtime: RefCounted = MELEE_RUNTIME.new()
var melee_frame: Dictionary = {}
var melee_source_pixels: Array = []
var melee_frame_key := ""
var melee_morph_cache: Dictionary = {}
var melee_connected: Dictionary = {}
var dodge_timer := 0.0
var invulnerable_timer := 0.0
var stage_elapsed := 0.0
var completion_delay := -1.0
var flash_timer := 0.0
var metrics := {"damage_taken": 0.0, "overheat_count": 0, "dodge_count": 0, "defeated": 0, "attacks_used": 0}


func _init() -> void:
	var visual_result: Dictionary = enemy_visual_assets.load_validated()
	if bool(visual_result.get("ok", false)):
		arena_background_texture = enemy_visual_assets.background_texture

func start_stage(
	next_stage: String,
	next_blueprint: WeaponBlueprint,
	next_asset: WeaponVisualAsset,
	next_enemy_blueprints: Array[Dictionary] = []
) -> void:
	stage_name = next_stage
	blueprint = next_blueprint
	asset = next_asset
	custom_enemy_blueprints.clear()
	for profile: Dictionary in next_enemy_blueprints:
		custom_enemy_blueprints.append(profile.duplicate(true))
	player_position = Vector2(250, 420)
	player_health = 100.0
	projectiles.clear()
	enemy_attack_hazards.clear()
	boomerang.clear()
	attack_charge = 0.0
	shot_cooldown = 0.0
	burst_shots_remaining = 0
	manual_cycle_timer = 0.0
	active_cycle_action_code = 0
	pending_reload_after_cycle = false
	overheat = 0.0
	overheat_lock = 0.0
	melee_timer = 0.0
	touch_attack = false
	touch_attack_requested = false
	attack_was_down = false
	dodge_timer = 0.0
	stage_elapsed = 0.0
	completion_delay = -1.0
	ranged_runtime_profile.clear()
	if str(blueprint.affordance.get("weapon_domain", "")) == "handheld_firearm":
		var cached_runtime: Variant = blueprint.modifiers.get("ranged_runtime_profile", {})
		if (
			cached_runtime is Dictionary
			and bool((cached_runtime as Dictionary).get("ok", false))
			and str((cached_runtime as Dictionary).get("schema", "")) == RANGED_AXIS_RESOLVER.RUNTIME_SCHEMA
			and (cached_runtime as Dictionary).has("muzzle_climb_cap_degrees")
		):
			ranged_runtime_profile = (cached_runtime as Dictionary).duplicate(true)
		else:
			ranged_runtime_profile = RANGED_AXIS_RESOLVER.compile(blueprint.affordance, blueprint.affordance_source)
	weapon_strategy_profile = WEAPON_STRATEGY.compile(blueprint, asset, ranged_runtime_profile)
	melee_runtime.configure(blueprint, asset)
	melee_frame.clear()
	melee_frame_key = ""
	melee_morph_cache.clear()
	melee_source_pixels.clear()
	if blueprint.behavior_family == "heavy_melee" and asset.source_image != null:
		melee_source_pixels = STATEFUL_PIXEL_MORPHER.deform_local(asset.source_image, asset.grip_primary, asset.tip, "fixed", 0.0).get("pixels", [])
	ammo_in_magazine = int(ranged_runtime_profile.get("magazine_size", 0))
	reload_timer = 0.0
	weapon_recoil_offset = 0.0
	weapon_muzzle_climb_degrees = 0.0
	sustained_muzzle_climb_degrees = 0.0
	sustained_fire_window_timer = 0.0
	muzzle_flash_timer = 0.0
	muzzle_flash_scale = 1.0
	metrics = {"damage_taken": 0.0, "overheat_count": 0, "dodge_count": 0, "defeated": 0, "attacks_used": 0, "shots_fired": 0, "reload_count": 0, "reload_interrupt_count": 0, "manual_cycle_count": 0}
	_spawn_stage()
	active = true
	set_process(true)
	queue_redraw()

func stop() -> void:
	active = false
	set_process(false)

func set_touch_vector(value: Vector2) -> void:
	touch_vector = value

func set_touch_attack(value: bool) -> void:
	touch_attack = value

func request_touch_attack() -> void:
	# Latch tap-style melee/throw inputs until the next gameplay frame. A fast
	# UI click can otherwise send button_down and button_up between two frames.
	touch_attack_requested = true

func request_touch_dodge() -> void:
	touch_dodge_requested = true

func _process(delta: float) -> void:
	if not active or blueprint == null or asset == null:
		return
	stage_elapsed += delta
	shot_cooldown = maxf(0.0, shot_cooldown - delta)
	overheat_lock = maxf(0.0, overheat_lock - delta)
	_update_firearm_timers(delta)
	invulnerable_timer = maxf(0.0, invulnerable_timer - delta)
	flash_timer = maxf(0.0, flash_timer - delta)
	_update_player(delta)
	_update_attacks(delta)
	_update_projectiles(delta)
	_update_enemies(delta)
	_update_enemy_attack_hazards(delta)
	_check_completion(delta)
	queue_redraw()

func _update_player(delta: float) -> void:
	var keyboard := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var movement := keyboard if keyboard.length() > 0.05 else touch_vector
	if absf(movement.x) > 0.08 and melee_timer <= 0.0:
		facing = signf(movement.x)
	var speed := 220.0
	if blueprint.weight_class == "heavy":
		speed = 158.0
	if _uses_firearm_runtime():
		speed *= float(ranged_runtime_profile.get("movement_multiplier", 1.0))
		if shot_cooldown > 0.0:
			speed *= float(ranged_runtime_profile.get("firing_movement_multiplier", 1.0))
	if melee_runtime.busy():
		speed *= melee_runtime.movement_ratio()
	elif attack_charge > 0.0:
		speed *= 0.62
	if reload_timer > 0.0:
		speed *= 0.82
	if dodge_timer > 0.0:
		dodge_timer -= delta
		speed = 510.0
	var wants_dodge := Input.is_action_just_pressed("dodge") or touch_dodge_requested
	touch_dodge_requested = false
	var can_dodge: bool = not melee_runtime.busy() or melee_runtime.controller.can_dodge_cancel()
	if wants_dodge and dodge_timer <= 0.0 and can_dodge:
		if melee_runtime.profile != null: melee_runtime.controller.press_dodge()
		dodge_timer = 0.20
		invulnerable_timer = 0.26
		metrics["dodge_count"] = int(metrics["dodge_count"]) + 1
		metrics_changed.emit(metrics)
	player_position += movement.limit_length(1.0) * speed * delta
	var bounds := _world_bounds()
	player_position.x = clampf(player_position.x, bounds.position.x + 34.0, bounds.end.x - 34.0)
	player_position.y = clampf(player_position.y, bounds.position.y + 48.0, bounds.end.y - 28.0)


## Campaign arenas may be wider than one viewport. Returning a virtual bounds
## rectangle keeps movement, lunges, projectiles and displacement in the same
## authoritative world instead of faking travel by sliding only the backdrop.
func _world_bounds() -> Rect2:
	return WORLD_RECT

func _update_attacks(delta: float) -> void:
	var attack_down := Input.is_action_pressed("attack") or touch_attack
	var just_pressed := touch_attack_requested or (attack_down and not attack_was_down)
	touch_attack_requested = false
	attack_was_down = attack_down
	if (attack_down or just_pressed) and not melee_runtime.busy():
		_face_nearest_enemy_for_attack()
	if just_pressed:
		metrics["attacks_used"] = int(metrics.get("attacks_used", 0)) + 1
	match blueprint.behavior_family:
		"returning_thrown": _update_returning_attack(just_pressed, delta)
		"heavy_melee": _update_melee_attack(just_pressed, delta, attack_down)
		_: _update_sustained_attack(attack_down, just_pressed, delta)


func _face_nearest_enemy_for_attack() -> void:
	var nearest_x_distance := INF
	var nearest_offset_x := 0.0
	for enemy: Dictionary in enemies:
		if float(enemy.get("hp", 0.0)) <= 0.0:
			continue
		var offset := Vector2(enemy.get("pos", player_position)) - player_position
		if absf(offset.x) <= 4.0:
			continue
		var distance := absf(offset.x) + absf(offset.y) * 0.35
		if distance < nearest_x_distance:
			nearest_x_distance = distance
			nearest_offset_x = offset.x
	if nearest_x_distance < INF:
		facing = signf(nearest_offset_x)

func _update_sustained_attack(attack_down: bool, just_pressed: bool, delta: float) -> void:
	if _uses_firearm_runtime():
		_update_firearm_attack(attack_down, just_pressed)
		return
	var heat_multiplier := float(blueprint.modifiers.get("heat_multiplier", 1.0))
	var rate_multiplier := float(blueprint.modifiers.get("fire_rate_multiplier", 1.0))
	if overheat_lock > 0.0:
		attack_charge = 0.0
		overheat = maxf(0.0, overheat - delta * 0.45)
		return
	if attack_down:
		attack_charge += delta
		if attack_charge >= 0.34 and shot_cooldown <= 0.0:
			_fire_bullet()
			shot_cooldown = 0.11 / maxf(0.2, rate_multiplier)
			overheat += 0.035 * heat_multiplier
			if overheat >= 1.0:
				overheat = 1.0
				overheat_lock = 1.45
				metrics["overheat_count"] = int(metrics["overheat_count"]) + 1
				metrics_changed.emit(metrics)
	else:
		attack_charge = maxf(0.0, attack_charge - delta * 2.0)
		overheat = maxf(0.0, overheat - delta * 0.28)

func _update_firearm_attack(attack_down: bool, just_pressed: bool) -> void:
	attack_charge = 0.0
	overheat = 0.0
	if reload_timer > 0.0:
		if _can_interrupt_incremental_reload(just_pressed):
			reload_timer = 0.0
			metrics["reload_interrupt_count"] = int(metrics.get("reload_interrupt_count", 0)) + 1
			metrics_changed.emit(metrics)
		else:
			return
	if manual_cycle_timer > 0.0:
		return
	var burst_size := int(ranged_runtime_profile.get("burst_size", 0))
	if burst_size > 1 and just_pressed and burst_shots_remaining <= 0:
		burst_shots_remaining = burst_size
	var wants_shot := just_pressed
	if bool(ranged_runtime_profile.get("automatic_fire", false)):
		wants_shot = attack_down
	elif burst_size > 1:
		wants_shot = burst_shots_remaining > 0
	if not wants_shot or shot_cooldown > 0.0:
		return
	if ammo_in_magazine <= 0:
		_begin_firearm_reload()
		return
	_fire_bullet()
	ammo_in_magazine -= 1
	if burst_size > 1:
		burst_shots_remaining = maxi(0, burst_shots_remaining - 1)
	shot_cooldown = float(ranged_runtime_profile.get("shot_interval_seconds", 0.18))
	if _firearm_cycle_required():
		active_cycle_action_code = int(ranged_runtime_profile.get("cycle_action_code", 1))
		manual_cycle_timer = _firearm_cycle_total_seconds()
		metrics["manual_cycle_count"] = int(metrics.get("manual_cycle_count", 0)) + 1
	weapon_recoil_offset = float(ranged_runtime_profile.get("recoil_pixels", 6.0))
	weapon_muzzle_climb_degrees = minf(
		maxf(0.0, float(ranged_runtime_profile.get("muzzle_climb_cap_degrees", 18.0))),
		weapon_muzzle_climb_degrees
			+ float(ranged_runtime_profile.get("muzzle_climb_degrees_per_shot", 4.0))
	)
	var sustained_climb_per_shot := maxf(
		0.0,
		float(ranged_runtime_profile.get("sustained_climb_per_shot_degrees", 0.0))
	)
	var sustained_climb_cap := maxf(
		0.0,
		float(ranged_runtime_profile.get("sustained_climb_cap_degrees", 0.0))
	)
	if sustained_climb_per_shot > 0.0 and sustained_climb_cap > 0.0:
		sustained_muzzle_climb_degrees = minf(
			sustained_climb_cap,
			sustained_muzzle_climb_degrees + sustained_climb_per_shot
		)
		sustained_fire_window_timer = maxf(
			0.0,
			float(ranged_runtime_profile.get("sustained_window_seconds", 0.0))
		)
	muzzle_flash_timer = float(ranged_runtime_profile.get("muzzle_flash_seconds", 0.06))
	muzzle_flash_scale = maxf(0.1, float(ranged_runtime_profile.get("muzzle_flash_scale", 1.0)))
	metrics["shots_fired"] = int(metrics.get("shots_fired", 0)) + 1
	metrics_changed.emit(metrics)
	if ammo_in_magazine <= 0:
		if manual_cycle_timer > 0.0:
			pending_reload_after_cycle = true
		else:
			_begin_firearm_reload()

func _begin_firearm_reload() -> void:
	if not _uses_firearm_runtime() or reload_timer > 0.0:
		return
	burst_shots_remaining = 0
	pending_reload_after_cycle = false
	reload_timer = float(ranged_runtime_profile.get("reload_seconds", 1.2))
	metrics["reload_count"] = int(metrics.get("reload_count", 0)) + 1
	metrics_changed.emit(metrics)

func _update_firearm_timers(delta: float) -> void:
	var recoil_recovery := float(ranged_runtime_profile.get("recoil_recovery_pixels_per_second", 70.0))
	var climb_recovery := float(ranged_runtime_profile.get("muzzle_climb_recovery_degrees_per_second", 24.0))
	weapon_recoil_offset = move_toward(weapon_recoil_offset, 0.0, delta * recoil_recovery)
	weapon_muzzle_climb_degrees = move_toward(weapon_muzzle_climb_degrees, 0.0, delta * climb_recovery)
	var sustained_window_before := sustained_fire_window_timer
	sustained_fire_window_timer = maxf(0.0, sustained_fire_window_timer - delta)
	if sustained_fire_window_timer <= 0.0:
		var sustained_recovery_multiplier := maxf(
			0.0,
			float(ranged_runtime_profile.get("sustained_recovery_multiplier", 1.0))
		)
		var sustained_recovery_delta := delta
		if sustained_window_before > 0.0:
			sustained_recovery_delta = maxf(0.0, delta - sustained_window_before)
		sustained_muzzle_climb_degrees = move_toward(
			sustained_muzzle_climb_degrees,
			0.0,
			sustained_recovery_delta * climb_recovery * sustained_recovery_multiplier
		)
	muzzle_flash_timer = maxf(0.0, muzzle_flash_timer - delta)
	var cycle_timer_before := manual_cycle_timer
	manual_cycle_timer = maxf(0.0, manual_cycle_timer - delta)
	var reload_delta := delta
	if cycle_timer_before > 0.0 and manual_cycle_timer <= 0.0:
		active_cycle_action_code = 0
		if pending_reload_after_cycle:
			_begin_firearm_reload()
			reload_delta = maxf(0.0, delta - cycle_timer_before)
	if reload_timer <= 0.0:
		return
	var remaining_delta := maxf(0.0, reload_delta)
	var completed_steps := 0
	while reload_timer > 0.0 and remaining_delta >= reload_timer and completed_steps < 64:
		remaining_delta -= reload_timer
		reload_timer = 0.0
		_complete_firearm_reload_step()
		completed_steps += 1
	if reload_timer > 0.0:
		reload_timer = maxf(0.0, reload_timer - remaining_delta)


func _complete_firearm_reload_step() -> void:
	var magazine_size := maxi(0, int(ranged_runtime_profile.get("magazine_size", 0)))
	var feed_code := int(ranged_runtime_profile.get("reload_feed_code", 0))
	if feed_code in [1, 2]:
		var rounds_per_step := maxi(1, int(ranged_runtime_profile.get("reload_rounds_per_step", 1)))
		ammo_in_magazine = mini(magazine_size, ammo_in_magazine + rounds_per_step)
		if ammo_in_magazine < magazine_size:
			reload_timer = maxf(0.01, float(ranged_runtime_profile.get("reload_seconds", 1.2)))
	else:
		# Detachable magazines (0) and belt boxes (3) both exchange the whole
		# feed package after their declared duration.
		ammo_in_magazine = magazine_size
	metrics_changed.emit(metrics)


func _can_interrupt_incremental_reload(just_pressed: bool) -> bool:
	return (
		just_pressed
		and ammo_in_magazine > 0
		and int(ranged_runtime_profile.get("reload_feed_code", 0)) == 1
	)


func _firearm_cycle_required() -> bool:
	return bool(ranged_runtime_profile.get(
		"cycle_required",
		ranged_runtime_profile.get("manual_cycle_required", false)
	))


func _firearm_cycle_total_seconds() -> float:
	if not _firearm_cycle_required():
		return 0.0
	var cadence_seconds := maxf(
		0.0,
		float(ranged_runtime_profile.get("shot_interval_seconds", 0.18))
	)
	var cycle_overhead := maxf(
		0.0,
		float(ranged_runtime_profile.get(
			"cycle_overhead_seconds",
			ranged_runtime_profile.get("manual_cycle_overhead_seconds", 0.0)
		))
	)
	return cadence_seconds + cycle_overhead

func _uses_firearm_runtime() -> bool:
	return bool(ranged_runtime_profile.get("ok", false)) and str(ranged_runtime_profile.get("schema", "")) == RANGED_AXIS_RESOLVER.RUNTIME_SCHEMA

func _update_returning_attack(just_pressed: bool, delta: float) -> void:
	if just_pressed and boomerang.is_empty():
		boomerang = {
			"pos": _muzzle_world(), "origin": player_position, "direction": facing,
			"distance": 0.0, "returning": false, "hit_out": {}, "hit_back": {}
		}
	if boomerang.is_empty():
		return
	var position: Vector2 = boomerang["pos"]
	if not bool(boomerang["returning"]):
		position.x += float(boomerang["direction"]) * 430.0 * delta
		boomerang["distance"] = float(boomerang["distance"]) + 430.0 * delta
		if float(boomerang["distance"]) >= 340.0:
			boomerang["returning"] = true
	else:
		position = position.move_toward(player_position, 470.0 * delta)
		if position.distance_to(player_position) < 24.0:
			boomerang.clear()
			return
	boomerang["pos"] = position
	var hit_set: Dictionary = boomerang["hit_back"] if bool(boomerang["returning"]) else boomerang["hit_out"]
	for enemy: Dictionary in enemies:
		var enemy_id := int(enemy["id"])
		if not hit_set.has(enemy_id) and position.distance_to(enemy["pos"]) < 32.0:
			hit_set[enemy_id] = true
			var base_damage := RULES.damage_against(blueprint.behavior_family, enemy["type"], _is_front_hit(enemy), blueprint.modifiers)
			var outcome := _resolve_enemy_defense(enemy, {"ok": true, "health_damage": base_damage, "stagger_seconds": 0.12, "interrupt_strength": 0.45, "knockback": Vector2.ZERO}, position)
			_damage_enemy(enemy, float(outcome.get("health_damage", base_damage)), float(outcome.get("stagger_seconds", 0.12)))
			_apply_target_interaction(enemy, outcome)
			_chain_damage(enemy, 8.0)

func _update_melee_attack(just_pressed: bool, delta: float, held: bool = false) -> void:
	if melee_runtime.profile == null:
		if not melee_runtime.configure(blueprint, asset): return
	melee_runtime.input_attack(just_pressed, held)
	# A delayed frame must not skip a fast active phase.
	var remaining := maxf(0.0, delta)
	var active_sampled := false
	while remaining > 0.00001:
		var step := minf(remaining, 1.0 / 120.0)
		melee_runtime.tick(step)
		var travel := _safe_melee_lunge(melee_runtime.root_step())
		var bounds := _world_bounds()
		player_position.x = clampf(player_position.x + travel * facing, bounds.position.x + 34.0, bounds.end.x - 34.0)
		# Runtime timing remains 120 Hz, but deforming hundreds of source pixels
		# four times inside one visible 30 Hz frame produces identical overdraw.
		# One authoritative active sample per displayed update still catches a
		# phase crossed by a delayed frame and preserves registered-hit semantics.
		if melee_runtime.active() and not active_sampled:
			_build_melee_frame()
			_resolve_compiled_melee_hits()
			active_sampled = true
		remaining -= step
	if not active_sampled: _build_melee_frame()
	melee_timer = 1.0 if melee_runtime.busy() else 0.0


func _resolve_compiled_melee_hits() -> void:
	var primitive: Variant = melee_runtime.primitive()
	var interaction: Dictionary = TARGET_INTERACTION.compile_melee(melee_runtime.affordance, primitive)
	for enemy: Dictionary in enemies:
		if melee_runtime.controller.hit_targets.has(int(enemy["id"])): continue
		if float(enemy.get("hp", 0.0)) <= 0.0 or not _melee_frame_contains(Vector2(enemy["pos"])): continue
		if not melee_runtime.controller.register_hit(int(enemy["id"])): continue
		melee_connected[int(enemy["id"])] = true
		var direction := (Vector2(enemy["pos"]) - player_position).normalized()
		var damage := RULES.damage_against(blueprint.behavior_family, enemy["type"], _is_front_hit(enemy), blueprint.modifiers)
		damage *= float(primitive.damage_multiplier) * _melee_axis_damage_multiplier()
		var reaction := {"knockback": direction * 22.0 * float(primitive.knockback_multiplier), "stagger": 0.18 * float(primitive.stagger_multiplier)}
		var outcome := TARGET_INTERACTION.resolve(interaction, _target_interaction_context(enemy), damage, reaction)
		outcome = _resolve_enemy_defense(enemy, outcome, player_position)
		_damage_enemy(enemy, float(outcome.get("health_damage", damage)), float(outcome.get("stagger_seconds", 0.18)))
		_apply_target_interaction(enemy, outcome)
		_apply_melee_axis_force(enemy, Vector2(enemy["pos"]) - player_position)
		melee_runtime.controller.begin_hitstop(minf(0.055, 0.025 * float(primitive.hitstop_multiplier)))
		if blueprint.effect_type == "lifesteal":
			player_health = minf(100.0, player_health + float(outcome.get("health_damage", damage)) * 0.10)
		metrics["melee_hits"] = int(metrics.get("melee_hits", 0)) + 1
		metrics["last_melee_stage"] = melee_runtime.controller.combo_index
		metrics["last_melee_surface"] = str(primitive.contact_surface)
		metrics["last_melee_verb"] = str(outcome.get("primary_reaction", ""))
		metrics_changed.emit(metrics)


func _safe_melee_lunge(requested: float) -> float:
	var nearest_forward := INF
	for enemy: Dictionary in enemies:
		var relative := Vector2(enemy.get("pos", player_position)) - player_position
		var forward := relative.x * facing
		if forward >= 0.0 and absf(relative.y) <= 64.0:
			nearest_forward = minf(nearest_forward, forward)
	if nearest_forward < INF:
		return minf(requested, maxf(0.0, nearest_forward - 30.0))
	return requested


## Shared presentation/contact root. Native-pose adapters override this once;
## source pixels, soft geometry and all effective contacts use the same result.
func _melee_root_pose() -> Dictionary:
	var pose: Dictionary = melee_runtime.pose(facing)
	pose["hand"] = _firearm_hand_base() + Vector2(pose.get("offset", Vector2.ZERO))
	return pose

func _build_melee_frame() -> void:
	if asset == null or melee_runtime.profile == null: return
	var pose := _melee_root_pose()
	var hand := Vector2(pose.hand)
	var angle := float(pose.angle)
	var longitudinal_scale := float(pose.get("longitudinal_scale", 1.0))
	var trajectory_plane := str(pose.get("trajectory_plane", "screen_arc"))
	var depth_layer := float(pose.get("depth_layer", 0.0))
	var scale := float(_weapon_fit().get("draw_scale", 1.0))
	var p: Variant = melee_runtime.primitive()
	var frame_key := "%s/%0.5f/%0.4f/%0.3f/%s/%s/%0.5f" % [hand, angle, longitudinal_scale, melee_runtime.state_power(), melee_runtime.controller.attack_serial, melee_runtime.controller.phase, melee_runtime.motion_ratio()]
	if frame_key == melee_frame_key: return
	melee_frame_key = frame_key
	var pixels: Array = []
	var contacts := PackedVector2Array()
	var is_soft := _uses_soft_mechanism_visual()
	var geometry: Dictionary = {}
	var power := _melee_state_power()
	if is_soft:
		geometry = _soft_weapon_geometry(hand, angle, longitudinal_scale)
		depth_layer = float(geometry.get("depth_layer", depth_layer))
		# Styled chain sprites already have deliberate dark outlines and holes.
		# The old readability lift bleached those outlines; the solid strand
		# resampler painted over their holes. Deform the actual source pixels.
		geometry.merge({"source_grip": asset.grip_primary, "facing": facing, "scale": scale, "pixel_snap": true})
		geometry.merge(_soft_pixel_render_options())
		# Runtime needs final pixels only. Skip report-only centroids/bounds and
		# collapse exact overdraw created when a flexible strand folds on itself.
		geometry["include_metadata"] = false
		geometry["compact_pixels"] = true
		pixels = PIXEL_WEAPON_DEFORMER.deform(asset.visual_rig, geometry).get("pixels", [])
	else:
		var local_pixels := melee_source_pixels
		if local_pixels.is_empty() and asset.source_image != null:
			local_pixels = STATEFUL_PIXEL_MORPHER.deform_local(asset.source_image, asset.grip_primary, asset.tip, "fixed", 0.0).get("pixels", [])
			melee_source_pixels = local_pixels
		if power > 0.01:
			var morph_key := roundi(power * 24.0)
			if not melee_morph_cache.has(morph_key):
				melee_morph_cache[morph_key] = STATEFUL_PIXEL_MORPHER.deform_local(asset.source_image, asset.grip_primary, asset.tip, str(blueprint.affordance.get("state_topology", "fixed")), float(morph_key) / 24.0, blueprint.affordance).get("pixels", [])
			local_pixels = melee_morph_cache[morph_key]
		for pixel: Dictionary in local_pixels:
			var local := Vector2(pixel.get("position", Vector2.ZERO)) * scale
			local.x *= longitudinal_scale
			var world := hand + Vector2(local.x * facing, local.y).rotated(angle)
			pixels.append({"position": world.round(), "size": maxf(1.0, ceilf(scale)), "color": pixel.get("color", Color.WHITE), "source_position": pixel.get("source_position", asset.grip_primary), "generated": pixel.get("generated", false)})
	if p != null:
		var anchor := asset.muzzle if str(p.contact_anchor) == "muzzle" else asset.tip
		if str(p.contact_anchor) == "rear_contact":
			anchor = asset.rear_contact
			if anchor.distance_to(asset.grip_primary) < 5.0 or anchor == Vector2.ZERO:
				# Farthest opaque pixel opposite the primary strike direction.
				var direction := (asset.tip - asset.grip_primary).normalized()
				var back := 0.0
				for pixel: Dictionary in melee_source_pixels:
					var source := Vector2(pixel.get("source_position", asset.grip_primary))
					var projection := (source - asset.grip_primary).dot(direction)
					if projection < back:
						back = projection
						anchor = source
		var span := maxf(8.0, anchor.distance_to(asset.grip_primary))
		var start_ratio := float({"point": 0.80, "broad": 0.50, "edge": 0.24, "whole_body": 0.0}.get(str(p.contact_surface), 0.24))
		var contact := Vector2(geometry.get("contact", hand))
		for pixel: Dictionary in pixels:
			var world := Vector2(pixel["position"])
			var eligible := false
			if is_soft:
				var role := str(pixel.get("role", ""))
				if str(p.contact_surface) == "point":
					eligible = role == "terminal" or world.distance_to(contact) <= 6.0 + float(p.terminal_load_ratio) * 7.0
				else:
					eligible = role in ["deform_body", "tether", "terminal"] and world.distance_to(hand) >= contact.distance_to(hand) * maxf(start_ratio, float(p.soft_contact_start_ratio))
			else:
				var source := Vector2(pixel.get("source_position", asset.grip_primary))
				var projection := (source - asset.grip_primary).dot((anchor - asset.grip_primary).normalized())
				eligible = projection >= span * start_ratio
				if power > 0.01 and bool(pixel.get("generated", false)): eligible = true
			if eligible and world.distance_to(hand) >= float(p.inner_deadzone_pixels) * scale:
				contacts.append(world)
	var field := PackedVector2Array()
	if p != null and melee_runtime.state_power() > 0.0 and str(p.functional_output) != "contact_only":
		var direction := Vector2(facing, 0.0).rotated(angle).normalized()
		var normal := Vector2(-direction.y, direction.x)
		var reach := _melee_axis_reach()
		if str(p.functional_output) == "radial_field":
			for index: int in range(40): field.append(hand + Vector2.from_angle(TAU * index / 40.0) * reach * 0.82)
		else:
			var nozzle := _soft_source_world(asset.muzzle, hand, angle)
			# Fixed rigid outputs begin at the validated native-function anchor.
			# Only a structure that actually deploys/deforms may replace that closed
			# source anchor with its farthest currently drawn working pixel.
			var deployed_output := str(p.state_topology) != "fixed" or str(p.flex_topology) != "none" or str(p.tether_topology) != "none"
			if deployed_output:
				var forward := -INF
				for point: Vector2 in contacts:
					var projection := (point - hand).dot(direction)
					if projection > forward:
						forward = projection
						nozzle = point
			var finish := nozzle + direction * reach
			var width := float(melee_runtime.profile.hitbox_thickness) * float(p.hitbox_width_multiplier) * 0.65
			field = PackedVector2Array([nozzle - normal * 4.0, finish - normal * width, finish + normal * width, nozzle + normal * 4.0])
	geometry["trajectory_plane"] = trajectory_plane
	geometry["longitudinal_scale"] = longitudinal_scale
	geometry["depth_layer"] = depth_layer
	melee_frame = {
		"pixels": pixels,
		"contacts": contacts,
		"field": field,
		"hand": hand,
		"angle": angle,
		"active": melee_runtime.active(),
		"state_power": power,
		"trajectory_plane": trajectory_plane,
		"longitudinal_scale": longitudinal_scale,
		"depth_layer": depth_layer,
		"geometry": geometry,
	}


func _melee_frame_contains(target: Vector2, target_radius: float = 24.0) -> bool:
	if not melee_runtime.active(): return false
	var field: PackedVector2Array = melee_frame.get("field", PackedVector2Array())
	if not field.is_empty():
		if Geometry2D.is_point_in_polygon(target, field): return true
		for index: int in range(field.size()):
			if Geometry2D.get_closest_point_to_segment(target, field[index], field[(index + 1) % field.size()]).distance_to(target) <= target_radius: return true
	var contacts: PackedVector2Array = melee_frame.get("contacts", PackedVector2Array())
	for point: Vector2 in contacts:
		if point.distance_squared_to(target) <= target_radius * target_radius: return true
	return false


func _melee_axis_reach() -> float:
	return melee_runtime.reach()


func _melee_axis_contains(relative: Vector2, _reach: float) -> bool:
	return _melee_frame_contains(player_position + relative)


func _melee_axis_damage_multiplier() -> float:
	if melee_runtime.state_power() <= 0.0: return 1.0
	var p: Variant = melee_runtime.primitive()
	return float({"contact_only": 1.0, "directed_stream": 0.74, "radial_field": 0.68, "pull_field": 0.62}.get(str(p.functional_output), 1.0))


func _apply_melee_axis_force(enemy: Dictionary, relative: Vector2) -> void:
	if blueprint == null or relative.length_squared() < 1.0 or melee_runtime.state_power() <= 0.0:
		return
	var output := str(blueprint.affordance.get("functional_output", "contact_only"))
	var direction := relative.normalized()
	if output == "pull_field":
		enemy["pos"] = Vector2(enemy["pos"]) - direction * 46.0
	elif output == "radial_field":
		enemy["pos"] = Vector2(enemy["pos"]) + direction * 38.0

func _fire_bullet() -> void:
	var projectile_speed := 610.0
	var spread_velocity := 12.0
	var projectile_life := 1.45
	var projectile_damage := RULES.base_damage("sustained_ranged")
	var pellet_count := 1
	var pellet_spread_degrees := 0.0
	var pellet_damage_multiplier := 1.0
	var damage_falloff_min_multiplier := 0.55
	var hit_stagger := 0.12
	var armor_damage_multiplier := 0.45
	var pierce_budget := 1 if bool(blueprint.modifiers.get("limited_pierce", false)) else 0
	var falloff_start := 480.0
	var falloff_end := 800.0
	var axis_signature := "generic_sustained"
	if _uses_firearm_runtime():
		projectile_speed = float(ranged_runtime_profile.get("projectile_speed", projectile_speed))
		spread_velocity = float(ranged_runtime_profile.get("spread_velocity", spread_velocity))
		projectile_life = float(ranged_runtime_profile.get("projectile_life_seconds", projectile_life))
		projectile_damage = float(ranged_runtime_profile.get("projectile_damage", projectile_damage))
		pellet_count = maxi(1, int(ranged_runtime_profile.get("pellet_count", pellet_count)))
		pellet_spread_degrees = maxf(0.0, float(ranged_runtime_profile.get("pellet_spread_degrees", pellet_spread_degrees)))
		pellet_damage_multiplier = maxf(0.0, float(ranged_runtime_profile.get("pellet_damage_multiplier", pellet_damage_multiplier)))
		damage_falloff_min_multiplier = clampf(
			float(ranged_runtime_profile.get("damage_falloff_min_multiplier", damage_falloff_min_multiplier)),
			0.0,
			1.0
		)
		hit_stagger = float(ranged_runtime_profile.get("hit_stagger_seconds", hit_stagger))
		armor_damage_multiplier = float(ranged_runtime_profile.get("armor_damage_multiplier", armor_damage_multiplier))
		pierce_budget = int(ranged_runtime_profile.get("pierce_budget", pierce_budget))
		falloff_start = float(ranged_runtime_profile.get("damage_falloff_start_pixels", falloff_start))
		falloff_end = float(ranged_runtime_profile.get("damage_falloff_end_pixels", falloff_end))
		axis_signature = str(ranged_runtime_profile.get("axis_signature", ""))
	var origin := _safe_projectile_origin(_muzzle_world())
	var shot_direction := Vector2(facing, 0.0).rotated(_firearm_recoil_rotation())
	var target_interaction_profile := TARGET_INTERACTION.compile_ranged(
		blueprint.affordance,
		ranged_runtime_profile
	)
	for pellet_index: int in range(pellet_count):
		var pellet_angle_degrees := _pellet_angle_degrees(
			pellet_index,
			pellet_count,
			pellet_spread_degrees
		)
		var pellet_direction := shot_direction.rotated(deg_to_rad(pellet_angle_degrees) * facing)
		var legacy_spread := Vector2.ZERO
		if pellet_count == 1:
			# The V4 single-projectile path retains its existing slight random
			# velocity spread. Multi-pellet declarations use exact deterministic
			# angles so the two edge pellets cover the full declared cone.
			legacy_spread = Vector2(0.0, randf_range(-spread_velocity, spread_velocity))
		projectiles.append({
			"pos": origin,
			"origin": origin,
			"distance_travelled": 0.0,
			"vel": pellet_direction * projectile_speed + legacy_spread,
			"life": projectile_life,
			"damage": projectile_damage * pellet_damage_multiplier,
			"pellet_index": pellet_index,
			"pellet_count": pellet_count,
			"pellet_angle_degrees": pellet_angle_degrees,
			"hit_stagger_seconds": hit_stagger,
			"projectile_radius_pixels": float(ranged_runtime_profile.get("projectile_radius_pixels", 4.0)),
			"armor_damage_multiplier": armor_damage_multiplier,
			"tracer_width_pixels": float(ranged_runtime_profile.get("tracer_width_pixels", 3.0)),
			"tracer_length_pixels": float(ranged_runtime_profile.get("tracer_length_pixels", 15.0)),
			"damage_falloff_start_pixels": falloff_start,
			"damage_falloff_end_pixels": falloff_end,
			"damage_falloff_min_multiplier": damage_falloff_min_multiplier,
			"pierces": pierce_budget,
			"hit": {},
			"axis_signature": axis_signature,
			"target_interaction_profile": target_interaction_profile,
		})


func _safe_projectile_origin(requested_origin: Vector2) -> Vector2:
	var forward_distance := (requested_origin.x - player_position.x) * facing
	var safe_forward_distance := maxf(8.0, forward_distance)
	for enemy: Dictionary in enemies:
		if float(enemy.get("hp", 0.0)) <= 0.0:
			continue
		var offset := Vector2(enemy.get("pos", player_position)) - player_position
		var enemy_forward := offset.x * facing
		if enemy_forward > 0.0 and absf(offset.y) <= 28.0:
			safe_forward_distance = minf(safe_forward_distance, maxf(8.0, enemy_forward - 12.0))
	return Vector2(player_position.x + safe_forward_distance * facing, requested_origin.y)


func _pellet_angle_degrees(index: int, count: int, spread_degrees: float) -> float:
	if count <= 1 or spread_degrees <= 0.0:
		return 0.0
	return lerpf(-spread_degrees * 0.5, spread_degrees * 0.5, float(index) / float(count - 1))


func _projectile_damage_against(projectile: Dictionary, enemy: Dictionary) -> float:
	if not projectile.has("damage"):
		return RULES.damage_against(
			blueprint.behavior_family,
			str(enemy.get("type", "target")),
			_is_front_hit(enemy),
			blueprint.modifiers
		)
	var damage := float(projectile.get("damage", RULES.base_damage("sustained_ranged")))
	var falloff_start := float(projectile.get("damage_falloff_start_pixels", INF))
	var falloff_end := maxf(
		falloff_start + 1.0,
		float(projectile.get("damage_falloff_end_pixels", falloff_start + 1.0))
	)
	var travelled := float(projectile.get("distance_travelled", 0.0))
	if travelled > falloff_start:
		var falloff := clampf(inverse_lerp(falloff_start, falloff_end, travelled), 0.0, 1.0)
		var minimum_multiplier := clampf(
			float(projectile.get("damage_falloff_min_multiplier", 0.55)),
			0.0,
			1.0
		)
		damage *= lerpf(1.0, minimum_multiplier, falloff)
	if float(enemy.get("armor_integrity", 0.0)) > 0.0 and _is_front_hit(enemy):
		damage *= float(projectile.get("armor_damage_multiplier", 0.45))
	return maxf(1.0, damage)


func _update_projectiles(delta: float) -> void:
	for projectile: Dictionary in projectiles:
		var previous_position := Vector2(projectile["pos"])
		var travel_step := Vector2(projectile["vel"]) * delta
		projectile["pos"] = Vector2(projectile["pos"]) + travel_step
		projectile["distance_travelled"] = float(projectile.get("distance_travelled", 0.0)) + travel_step.length()
		projectile["life"] = float(projectile["life"]) - delta
		for enemy: Dictionary in enemies:
			var enemy_id := int(enemy["id"])
			var hit: Dictionary = projectile["hit"]
			if not hit.has(enemy_id) and _projectile_contacts_enemy(previous_position, Vector2(projectile["pos"]), projectile, enemy):
				hit[enemy_id] = true
				_resolve_projectile_hit(projectile, enemy)
				enemy["burn"] = 2.2
				if int(projectile["pierces"]) > 0:
					projectile["pierces"] = int(projectile["pierces"]) - 1
				else:
					projectile["life"] = 0.0
					break
	var bounds := _world_bounds()
	projectiles = projectiles.filter(func(projectile: Dictionary) -> bool: return float(projectile["life"]) > 0.0 and bounds.grow(80).has_point(projectile["pos"]))


func _projectile_contacts_enemy(start: Vector2, finish: Vector2, _projectile: Dictionary, enemy: Dictionary) -> bool:
	# Sweep the travelled segment: a frame must not skip a small target.
	return _distance_to_segment(Vector2(enemy.pos), start, finish) < 23.0

func _update_enemies(delta: float) -> void:
	for enemy: Dictionary in enemies:
		_tick_target_interaction(enemy, delta)
		enemy["hurt"] = maxf(0.0, float(enemy.get("hurt", 0.0)) - delta)
		enemy["cooldown"] = maxf(0.0, float(enemy.get("cooldown", 0.0)) - delta)
		if float(enemy.get("burn", 0.0)) > 0.0:
			enemy["burn"] = float(enemy["burn"]) - delta
			enemy["hp"] = float(enemy["hp"]) - 5.0 * delta
		if stage_name == "training":
			if enemy["type"] == "moving_target" and not _target_is_immobilized(enemy):
				var training_speed := 75.0 * _target_suppression_speed(enemy)
				enemy["pos"] = Vector2(enemy["pos"]) + Vector2(float(enemy["patrol"]), 0) * training_speed * delta
				if float(Vector2(enemy["pos"]).x) < 680.0 or float(Vector2(enemy["pos"]).x) > 1120.0:
					enemy["patrol"] = -float(enemy["patrol"])
			if float(enemy["hp"]) <= 0.0:
				enemy["hp"] = float(enemy["max_hp"])
			continue
		var to_player := player_position - Vector2(enemy["pos"])
		enemy["facing"] = signf(to_player.x)
		var attack_runtime: Variant = enemy.get("attack_runtime", null)
		if bool(enemy.get("compiled_attacks_ready", false)) and attack_runtime != null:
			if attack_runtime.is_running():
				_update_compiled_enemy_attack(enemy, attack_runtime, delta)
				continue
			if not _target_is_immobilized(enemy) and float(enemy.get("suppression_seconds", 0.0)) <= 0.0:
				if _begin_compiled_enemy_attack(enemy, attack_runtime, to_player):
					continue
		if _target_is_immobilized(enemy):
			continue
		var speed := float(enemy.get("move_speed", 54.0))
		if enemy["type"] == "rusher":
			enemy["charge"] = float(enemy.get("charge", 0.0)) + delta
			if float(enemy["charge"]) > 1.35:
				speed = 235.0
			if float(enemy["charge"]) > 1.75:
				enemy["charge"] = 0.0
		elif enemy["type"] == "swarmling":
			speed = 82.0
		elif enemy["type"] == "guard":
			speed = 42.0
		speed *= _target_suppression_speed(enemy)
		if float(enemy.get("suppression_seconds", 0.0)) > 0.0:
			enemy["cooldown"] = maxf(float(enemy.get("cooldown", 0.0)), 0.18)
		if to_player.length() > 28.0:
			enemy["pos"] = Vector2(enemy["pos"]) + to_player.normalized() * speed * delta
		elif not bool(enemy.get("compiled_attacks_ready", false)) and float(enemy["cooldown"]) <= 0.0 and invulnerable_timer <= 0.0:
			var damage := (5.0 if enemy["type"] == "swarmling" else 9.0) * float(enemy.get("damage_multiplier", 1.0))
			_take_player_damage(damage)
			enemy["cooldown"] = 0.85
	var before := enemies.size()
	enemies = enemies.filter(func(enemy: Dictionary) -> bool: return float(enemy["hp"]) > 0.0)
	metrics["defeated"] = int(metrics["defeated"]) + before - enemies.size()

func _damage_enemy(enemy: Dictionary, amount: float, hurt_seconds: float = 0.12) -> void:
	enemy["hp"] = float(enemy["hp"]) - amount
	enemy["hurt"] = maxf(float(enemy.get("hurt", 0.0)), hurt_seconds)


func _take_player_damage(amount: float) -> float:
	var applied := maxf(0.0, amount)
	if melee_runtime.active() and melee_runtime.state_power() > 0.0:
		applied *= float(weapon_strategy_profile.get("active_guard_damage_multiplier", 1.0))
	player_health = maxf(1.0, player_health - applied)
	metrics["damage_taken"] = float(metrics["damage_taken"]) + applied
	flash_timer = 0.14
	metrics_changed.emit(metrics)
	return applied


func _begin_compiled_enemy_attack(enemy: Dictionary, attack_runtime: Variant, to_player: Vector2) -> bool:
	var selected: Dictionary = attack_runtime.begin_attack({
		"distance_pixels": to_player.length(),
		"depth_delta_pixels": to_player.y,
		"available_coordination_budget": int(enemy.get("coordination_budget", 1)),
		"clear_path": _enemy_has_clear_path(enemy, player_position),
	}, Vector2(enemy["pos"]), player_position)
	if not bool(selected.get("ok", false)):
		return false
	enemy["attack_phase"] = "telegraph"
	enemy["last_attack_mechanism"] = selected.duplicate(true)
	return true


func _update_compiled_enemy_attack(enemy: Dictionary, attack_runtime: Variant, delta: float) -> void:
	var result: Dictionary = attack_runtime.step(delta, Vector2(enemy["pos"]), player_position)
	enemy["attack_phase"] = str(result.get("phase", "idle"))
	enemy["last_attack_mechanism"] = result.duplicate(true)
	var delivery := str(result.get("delivery", attack_runtime.current_delivery()))
	var activation_event := result.get("activation_event", {}) as Dictionary
	if bool(activation_event.get("ok", false)):
		var danger_zone := activation_event.get("danger_zone", {}) as Dictionary
		# Projectile/impact attacks already detach into world hazards. A residue
		# modifier must also leave the SAME compiled contact/rush region behind;
		# otherwise the family silently has no effect whenever that attack wins
		# selection.
		if delivery in ["projectile", "marked_impact"] or bool(danger_zone.get("persists_after_active", false)):
			_spawn_enemy_attack_hazard(enemy, activation_event)
	for echo_event: Dictionary in result.get("echo_events", []) as Array:
		_spawn_enemy_attack_hazard(enemy, echo_event)
	var active_seconds := float(result.get("active_seconds_this_step", 0.0))
	if active_seconds <= 0.0:
		return
	if delivery == "rush" and not _target_is_immobilized(enemy):
		var motion := result.get("attack_motion", {}) as Dictionary
		var direction: Vector2 = Vector2(result.get("locked_direction", Vector2(float(enemy.get("facing", -1.0)), 0.0)))
		enemy["pos"] = Vector2(enemy["pos"]) + direction * float(motion.get("travel_speed_pixels_per_second", 0.0)) * active_seconds
	if delivery not in ["contact", "rush"] or attack_runtime.active_hit_registered or invulnerable_timer > 0.0:
		return
	if not attack_runtime.current_hit_contains(Vector2(enemy["pos"]), player_position):
		return
	attack_runtime.register_active_hit()
	var damage: float = float({"contact": 6.0, "rush": 12.0, "projectile": 8.0, "marked_impact": 10.0}.get(delivery, 6.0))
	damage *= float(enemy.get("damage_multiplier", 1.0))
	_take_player_damage(damage)


func _spawn_enemy_attack_hazard(enemy: Dictionary, activation_event: Dictionary) -> void:
	var delivery := str(activation_event.get("delivery", ""))
	var event_schema := str(activation_event.get("schema", ""))
	var is_echo := event_schema == "forge-enemy-attack-echo-event-v1"
	var danger_zone := (activation_event.get("danger_zone", {}) as Dictionary).duplicate(true)
	var is_residue := str(danger_zone.get("modifier_source", "")) == "residue"
	if delivery not in ["projectile", "marked_impact"] and not is_echo and not is_residue:
		return
	var origin: Vector2 = Vector2(activation_event.get("origin", enemy.get("pos", Vector2.ZERO)))
	var lifetime := float(activation_event.get("hazard_lifetime_seconds", 0.0))
	var region := (activation_event.get("hit_region", {}) as Dictionary).duplicate(true)
	var region_scale := maxf(0.1, float(activation_event.get("region_scale", 1.0)))
	for key: String in ["radius_pixels", "length_pixels", "width_pixels"]:
		if region.has(key):
			region[key] = float(region[key]) * region_scale
	var contact_mode := str(danger_zone.get("contact_mode", "single"))
	var hazard_mode := str(danger_zone.get("mode", "instant"))
	var damage_multiplier := float(danger_zone.get("damage_multiplier", 1.0))
	damage_multiplier *= float(activation_event.get("damage_multiplier", 1.0))
	var effect_family := "echo" if is_echo else ("residue" if is_residue else "")
	var base_damage := float({"contact": 6.0, "rush": 12.0, "projectile": 8.0, "marked_impact": 10.0}.get(delivery, 6.0))
	enemy_attack_hazards.append({
		"schema": "forge-enemy-attack-hazard-v2",
		"owner_id": int(enemy.get("id", -1)),
		"attack_key": str(activation_event.get("attack_key", "")),
		"mechanism_signature": str(activation_event.get("mechanism_signature", "")),
		"delivery": delivery,
		"effect_family": effect_family,
		"echo_repeat_index": int(activation_event.get("echo_repeat_index", -1)),
		"pos": origin,
		"previous_pos": origin,
		"vel": Vector2(activation_event.get("velocity", Vector2.ZERO)),
		"locked_direction": Vector2(activation_event.get("locked_direction", Vector2.RIGHT)),
		"life": lifetime,
		"maximum_life": lifetime,
		"age": 0.0,
		"repeat_cooldown": 0.0,
		"danger_zone": danger_zone,
		"hazard_mode": hazard_mode,
		"contact_mode": contact_mode,
		"hit_region": region,
		"damage": base_damage * float(enemy.get("damage_multiplier", 1.0)) * damage_multiplier,
		"hit_player": false,
		"damage_event_serial": 0,
		"player_confirmation_required": false,
	})


func _update_enemy_attack_hazards(delta: float) -> void:
	for hazard: Dictionary in enemy_attack_hazards:
		hazard["previous_pos"] = Vector2(hazard.get("pos", Vector2.ZERO))
		if str(hazard.get("delivery", "")) == "projectile":
			hazard["pos"] = Vector2(hazard["pos"]) + Vector2(hazard.get("vel", Vector2.ZERO)) * delta
		hazard["age"] = float(hazard.get("age", 0.0)) + delta
		hazard["repeat_cooldown"] = maxf(0.0, float(hazard.get("repeat_cooldown", 0.0)) - delta)
		hazard["life"] = float(hazard.get("life", 0.0)) - delta
		if bool(hazard.get("hit_player", false)) or invulnerable_timer > 0.0 or not _enemy_hazard_dangerous_now(hazard):
			continue
		if float(hazard.get("repeat_cooldown", 0.0)) > 0.0:
			continue
		if not _enemy_attack_hazard_contains(hazard, player_position):
			continue
		var contact_mode := str(hazard.get("contact_mode", "single"))
		if contact_mode == "single":
			hazard["hit_player"] = true
			hazard["life"] = 0.0
		else:
			var danger_zone := hazard.get("danger_zone", {}) as Dictionary
			if contact_mode == "pulse":
				hazard["repeat_cooldown"] = maxf(0.08, float(danger_zone.get("pulse_interval_seconds", 0.60)))
			else:
				hazard["repeat_cooldown"] = maxf(0.08, float(danger_zone.get("repeat_hit_cooldown_seconds", 0.32)))
		var damage := float(hazard.get("damage", 0.0))
		hazard["damage_event_serial"] = int(hazard.get("damage_event_serial", 0)) + 1
		_take_player_damage(damage)
	var bounds := _world_bounds()
	enemy_attack_hazards = enemy_attack_hazards.filter(func(hazard: Dictionary) -> bool:
		return float(hazard.get("life", 0.0)) > 0.0 and bounds.grow(100.0).has_point(Vector2(hazard.get("pos", Vector2.ZERO)))
	)


func _enemy_hazard_dangerous_now(hazard: Dictionary) -> bool:
	var mode := str(hazard.get("hazard_mode", "instant"))
	if mode != "pulsing":
		return true
	var danger_zone := hazard.get("danger_zone", {}) as Dictionary
	var interval := maxf(0.001, float(danger_zone.get("pulse_interval_seconds", 0.60)))
	var active_seconds := clampf(float(danger_zone.get("pulse_active_seconds", 0.14)), 0.0, interval)
	return fmod(float(hazard.get("age", 0.0)), interval) <= active_seconds


func _enemy_attack_hazard_contains(hazard: Dictionary, point: Vector2) -> bool:
	var region := hazard.get("hit_region", {}) as Dictionary
	var delivery := str(hazard.get("delivery", ""))
	if delivery != "projectile":
		return _enemy_attack_region_contains(
			Vector2(hazard.get("pos", Vector2.ZERO)),
			point,
			Vector2(hazard.get("locked_direction", Vector2.RIGHT)),
			region
		)
	var start: Vector2 = Vector2(hazard.get("previous_pos", hazard.get("pos", Vector2.ZERO)))
	var finish: Vector2 = Vector2(hazard.get("pos", Vector2.ZERO))
	var radius := maxf(4.0, float(region.get("width_pixels", 0.0)) * 0.5)
	return _distance_to_segment(point, start, finish) <= radius


func _enemy_attack_region_contains(origin: Vector2, point: Vector2, direction_value: Vector2, region: Dictionary) -> bool:
	var offset := point - origin
	var depth_tolerance := float(region.get("depth_tolerance_pixels", 100000.0))
	if str(region.get("path_mode", "same_lane")) == "same_lane" and absf(offset.y) > depth_tolerance:
		return false
	match str(region.get("shape", "capsule")):
		"circle":
			return offset.length() <= float(region.get("radius_pixels", 0.0))
		"arc":
			var radius := float(region.get("radius_pixels", 0.0))
			if offset.length() > radius or offset.length() <= 0.001:
				return false
			return absf(direction_value.angle_to(offset.normalized())) <= deg_to_rad(float(region.get("arc_degrees", 0.0)) * 0.5)
		"strip", "capsule":
			var direction := direction_value.normalized()
			if direction.is_zero_approx():
				direction = Vector2.RIGHT
			var forward := offset.dot(direction)
			var sideways := absf(offset.cross(direction))
			return forward >= 0.0 \
				and forward <= float(region.get("length_pixels", 0.0)) \
				and sideways <= float(region.get("width_pixels", 0.0)) * 0.5
	return false


func _distance_to_segment(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment := finish - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return point.distance_to(start)
	var amount := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * amount)


func _resolve_projectile_hit(projectile: Dictionary, enemy: Dictionary) -> Dictionary:
	var interaction_profile: Dictionary = projectile.get("target_interaction_profile", {}) as Dictionary
	if not bool(interaction_profile.get("ok", false)):
		interaction_profile = TARGET_INTERACTION.compile_ranged(
			blueprint.affordance if blueprint != null else {},
			ranged_runtime_profile
		)
	var direction := Vector2(projectile.get("vel", Vector2(facing, 0.0))).normalized()
	if direction.length() < 0.1:
		direction = Vector2(facing, 0.0)
	var base_damage := _projectile_damage_against(projectile, enemy)
	var outcome := TARGET_INTERACTION.resolve(
		interaction_profile,
		_target_interaction_context(enemy),
		base_damage,
		{
			"knockback": direction * 22.0,
			"stagger": float(projectile.get("hit_stagger_seconds", 0.12)),
		}
	)
	outcome = _resolve_enemy_defense(enemy, outcome, Vector2(projectile.get("pos", player_position)))
	_damage_enemy(
		enemy,
		float(outcome.get("health_damage", base_damage)),
		float(outcome.get("stagger_seconds", projectile.get("hit_stagger_seconds", 0.12)))
	)
	_apply_target_interaction(enemy, outcome)
	return outcome


func _resolve_enemy_defense(enemy: Dictionary, outcome: Dictionary, source_position: Vector2) -> Dictionary:
	var resolved := outcome.duplicate(true)
	var attack_runtime: Variant = enemy.get("attack_runtime", null)
	if attack_runtime == null:
		return resolved
	var incoming_from := (source_position - Vector2(enemy.get("pos", Vector2.ZERO))).normalized()
	var defense_result: Dictionary = attack_runtime.resolve_defense(
		incoming_from,
		float(resolved.get("interrupt_strength", resolved.get("stagger_seconds", 0.0))),
		bool(resolved.get("armor_break", false))
	)
	var damage_multiplier := float(defense_result.get("damage_multiplier", 1.0))
	var stagger_multiplier := float(defense_result.get("stagger_multiplier", 1.0))
	resolved["health_damage"] = float(resolved.get("health_damage", 0.0)) * damage_multiplier
	resolved["armor_damage"] = float(resolved.get("armor_damage", 0.0)) * damage_multiplier
	resolved["stagger_seconds"] = float(resolved.get("stagger_seconds", 0.0)) * stagger_multiplier
	resolved["interrupt_strength"] = float(resolved.get("interrupt_strength", 0.0)) * stagger_multiplier
	resolved["knockback"] = Vector2(resolved.get("knockback", Vector2.ZERO)) * stagger_multiplier
	resolved["enemy_defense"] = defense_result.duplicate(true)
	if bool(defense_result.get("guard_broken", false)):
		resolved["status"] = "GUARD BROKEN"
		resolved["status_seconds"] = maxf(0.45, float(resolved.get("status_seconds", 0.0)))
	elif bool(defense_result.get("blocked", false)):
		resolved["status"] = "GUARDED"
		resolved["status_seconds"] = maxf(0.20, float(resolved.get("status_seconds", 0.0)))
	return resolved


func _enemy_has_clear_path(owner: Dictionary, target_position: Vector2) -> bool:
	var start := Vector2(owner.get("pos", Vector2.ZERO))
	var finish := target_position
	for candidate: Dictionary in enemies:
		if int(candidate.get("id", -1)) == int(owner.get("id", -2)) or float(candidate.get("hp", 0.0)) <= 0.0:
			continue
		var point := Vector2(candidate.get("pos", Vector2.ZERO))
		var segment := finish - start
		var length_squared := segment.length_squared()
		if length_squared <= 0.000001:
			return true
		var amount := (point - start).dot(segment) / length_squared
		if amount > 0.08 and amount < 0.92 and _distance_to_segment(point, start, finish) < 30.0:
			return false
	return true


func _target_interaction_context(enemy: Dictionary) -> Dictionary:
	var attack_state := "attack" if float(enemy.get("cooldown", 0.0)) <= 0.0 else "recovery"
	var attack_runtime: Variant = enemy.get("attack_runtime", null)
	if attack_runtime != null and attack_runtime.is_running():
		attack_state = str(attack_runtime.phase)
	return {
		"mass_class": str(enemy.get("mass_class", "medium")),
		"armor_integrity": float(enemy.get("armor_integrity", 0.0)),
		"state": attack_state,
	}


func _apply_target_interaction(enemy: Dictionary, outcome: Dictionary) -> void:
	if not bool(outcome.get("ok", false)):
		return
	var armor_before := float(enemy.get("armor_integrity", 0.0))
	enemy["armor_integrity"] = maxf(0.0, armor_before - float(outcome.get("armor_damage", 0.0)))
	var status := str(outcome.get("status", ""))
	if armor_before > 0.0 and float(enemy["armor_integrity"]) <= 0.0:
		status = "ARMOR BROKEN"
	enemy["interaction_status"] = status
	enemy["interaction_status_time"] = maxf(
		float(enemy.get("interaction_status_time", 0.0)),
		float(outcome.get("status_seconds", 0.0))
	)
	enemy["pin_seconds"] = maxf(float(enemy.get("pin_seconds", 0.0)), float(outcome.get("pin_seconds", 0.0)))
	enemy["entangle_seconds"] = maxf(float(enemy.get("entangle_seconds", 0.0)), float(outcome.get("entangle_seconds", 0.0)))
	enemy["suppression_seconds"] = maxf(float(enemy.get("suppression_seconds", 0.0)), float(outcome.get("suppression_seconds", 0.0)))
	enemy["last_target_interaction"] = outcome.duplicate(true)
	var attack_runtime: Variant = enemy.get("attack_runtime", null)
	if attack_runtime != null and attack_runtime.is_running():
		var interrupt_result: Dictionary = attack_runtime.try_interrupt(outcome)
		if bool(interrupt_result.get("interrupted", false)):
			enemy["attack_phase"] = "recovery"
	var displacement: Vector2 = outcome.get("knockback", Vector2.ZERO)
	match str(outcome.get("displacement_mode", "away")):
		"hold": displacement = Vector2.ZERO
		"toward_source": displacement *= -1.0
	if displacement.length() > 0.0:
		var moved := Vector2(enemy["pos"]) + displacement
		var target_bounds := _world_bounds().grow(-26.0)
		moved.x = clampf(moved.x, target_bounds.position.x, target_bounds.end.x)
		moved.y = clampf(moved.y, target_bounds.position.y, target_bounds.end.y)
		enemy["pos"] = moved
	if bool(outcome.get("interrupts_attack", false)):
		enemy["cooldown"] = maxf(float(enemy.get("cooldown", 0.0)), float(outcome.get("status_seconds", 0.0)))


func _tick_target_interaction(enemy: Dictionary, delta: float) -> void:
	for timer: String in ["pin_seconds", "entangle_seconds", "suppression_seconds", "interaction_status_time"]:
		enemy[timer] = maxf(0.0, float(enemy.get(timer, 0.0)) - delta)
	if float(enemy.get("interaction_status_time", 0.0)) <= 0.0:
		enemy["interaction_status"] = ""


func _target_is_immobilized(enemy: Dictionary) -> bool:
	return float(enemy.get("pin_seconds", 0.0)) > 0.0 or float(enemy.get("entangle_seconds", 0.0)) > 0.0


func _target_suppression_speed(enemy: Dictionary) -> float:
	return 0.55 if float(enemy.get("suppression_seconds", 0.0)) > 0.0 else 1.0

func _chain_damage(source: Dictionary, amount: float) -> void:
	for enemy: Dictionary in enemies:
		if enemy != source and Vector2(enemy["pos"]).distance_to(source["pos"]) < 105.0:
			var outcome := _resolve_enemy_defense(enemy, {"ok": true, "health_damage": amount, "stagger_seconds": 0.08, "interrupt_strength": 0.30, "knockback": Vector2.ZERO}, Vector2(source["pos"]))
			_damage_enemy(enemy, float(outcome.get("health_damage", amount)), float(outcome.get("stagger_seconds", 0.08)))
			_apply_target_interaction(enemy, outcome)

func _is_front_hit(enemy: Dictionary) -> bool:
	var enemy_facing := float(enemy.get("facing", -1.0))
	var incoming_side := signf(player_position.x - Vector2(enemy["pos"]).x)
	return enemy_facing == incoming_side

func _check_completion(delta: float) -> void:
	if stage_name == "training":
		return
	if enemies.is_empty() and completion_delay < 0.0:
		completion_delay = 0.9
	if completion_delay >= 0.0:
		completion_delay -= delta
		if completion_delay <= 0.0:
			active = false
			metrics["elapsed_seconds"] = snappedf(stage_elapsed, 0.1)
			stage_completed.emit(stage_name, metrics.duplicate(true))

func _spawn_stage() -> void:
	enemies.clear()
	if not custom_enemy_blueprints.is_empty():
		var positions: Array[Vector2] = [Vector2(900, 350), Vector2(1040, 520), Vector2(980, 230)]
		for index: int in range(custom_enemy_blueprints.size()):
			var profile := custom_enemy_blueprints[index]
			var spawn_position := positions[index % positions.size()]
			if profile.get("spawn_position", null) is Vector2:
				spawn_position = Vector2(profile["spawn_position"])
			_spawn_enemy_blueprint(profile, spawn_position)
		return
	match stage_name:
		"room_1":
			_spawn_enemy("swarmling", Vector2(800, 250), 24.0)
			_spawn_enemy("swarmling", Vector2(900, 420), 24.0)
			_spawn_enemy("swarmling", Vector2(760, 560), 24.0)
			_spawn_enemy("rusher", Vector2(1090, 360), 58.0)
		"room_2":
			_spawn_enemy("guard", Vector2(850, 350), 120.0)
			_spawn_enemy("rusher", Vector2(1050, 520), 64.0)
			_spawn_enemy("swarmling", Vector2(980, 220), 28.0)
		_:
			_spawn_enemy("target", Vector2(760, 350), 150.0)
			_spawn_enemy("moving_target", Vector2(980, 520), 150.0)

func _spawn_enemy(type_name: String, position: Vector2, health: float) -> void:
	var mechanical: Dictionary = (TARGET_MECHANICAL_PROFILES.get(type_name, TARGET_MECHANICAL_PROFILES["target"]) as Dictionary).duplicate(true)
	_spawn_enemy_blueprint({
		"id": type_name,
		"type_name": type_name,
		"display_name": type_name,
		"mass_class": str(mechanical.get("mass_class", "medium")),
		"armor_integrity": float(mechanical.get("armor_integrity", 0.0)),
		"max_health": health,
		"move_speed": 54.0,
		"attack_declarations": (TARGET_ATTACK_DECLARATIONS.get(type_name, []) as Array).duplicate(true),
		"visual_identity_axes": {},
	}, position)


func _spawn_enemy_blueprint(profile: Dictionary, position: Vector2) -> void:
	var attack_runtime: RefCounted = ENEMY_ATTACK_RUNTIME.new()
	var declarations: Array = (profile.get("attack_declarations", []) as Array).duplicate(true)
	var attack_configuration: Dictionary = attack_runtime.configure(
		declarations,
		float(profile.get("attack_tempo_multiplier", 1.0)),
		(profile.get("enemy_modifier_declarations", []) as Array).duplicate(true)
	) if not declarations.is_empty() else {"ok": false}
	var maximum_health := float(profile.get("max_health", 80.0))
	var type_name := str(profile.get("type_name", "generated_enemy"))
	var blueprint_id := str(profile.get("catalog_id", profile.get("id", type_name)))
	var default_coordination_budget := 3 if type_name == "generated_enemy" else 1
	enemies.append({
		"id": enemies.size() + 1, "type": type_name, "pos": position, "hp": maximum_health,
		"max_hp": maximum_health, "facing": -1.0, "cooldown": 0.0, "hurt": 0.0,
		"burn": 0.0, "charge": 0.0, "patrol": 1.0,
		"display_name": str(profile.get("display_name", type_name)),
		"blueprint_id": blueprint_id,
		"visual_asset": enemy_visual_assets.visual_for(blueprint_id),
		"mass_class": str(profile.get("mass_class", "medium")),
		"armor_integrity": float(profile.get("armor_integrity", 0.0)),
		"move_speed": float(profile.get("move_speed", 54.0)),
		"damage_multiplier": float(profile.get("damage_multiplier", 1.0)),
		"coordination_budget": int(profile.get("coordination_budget", default_coordination_budget)),
		"enemy_modifier_declarations": (profile.get("enemy_modifier_declarations", []) as Array).duplicate(true),
		"visual_identity_axes": (profile.get("visual_identity_axes", {}) as Dictionary).duplicate(true),
		"pin_seconds": 0.0, "entangle_seconds": 0.0, "suppression_seconds": 0.0,
		"interaction_status": "", "interaction_status_time": 0.0,
		"last_target_interaction": {},
		"attack_runtime": attack_runtime,
		"compiled_attacks_ready": bool(attack_configuration.get("ok", false)),
		"attack_phase": "idle", "last_attack_mechanism": {},
	})

func _muzzle_world() -> Vector2:
	if asset == null:
		return player_position
	if _uses_firearm_runtime():
		var action := _firearm_action_sample()
		return FIREARM_ACTION_CHOREOGRAPHY.world_anchor(
			_firearm_hand_base(),
			asset.muzzle,
			asset.grip_primary,
			action.get("root_pose", {}) as Dictionary,
			_firearm_draw_scale()
		)
	var hand := _firearm_hand_base()
	var relative := asset.muzzle - asset.grip_primary
	var scale := float(_weapon_fit().get("draw_scale", 1.0))
	var relative_world := Vector2(relative.x * scale * facing, relative.y * scale)
	return hand + relative_world


func _firearm_recoil_rotation() -> float:
	if not _uses_firearm_runtime():
		return 0.0
	return deg_to_rad(-weapon_muzzle_climb_degrees - sustained_muzzle_climb_degrees) * facing


func _firearm_hand_base() -> Vector2:
	var local := Vector2(_weapon_fit().get("primary_hand_offset", Vector2(18.0, -7.0)))
	return player_position + Vector2(local.x * facing, local.y)


func _firearm_draw_scale() -> float:
	return float(_weapon_fit().get("draw_scale", FIREARM_ACTION_CHOREOGRAPHY.DRAW_SCALE))


func _weapon_fit() -> Dictionary:
	return WEAPON_PLAYER_FIT.compile(blueprint, asset)


func _firearm_action_sample() -> Dictionary:
	if not _uses_firearm_runtime():
		return {}
	return FIREARM_ACTION_CHOREOGRAPHY.sample(
		ranged_runtime_profile,
		{
			"recoil_pixels": weapon_recoil_offset,
			"muzzle_climb_degrees": (
				weapon_muzzle_climb_degrees + sustained_muzzle_climb_degrees
			),
			"cycle_timer": manual_cycle_timer,
			"reload_timer": reload_timer,
			"muzzle_flash_timer": muzzle_flash_timer,
		},
		{
			"ammo_in_magazine": ammo_in_magazine,
			"magazine_size": int(ranged_runtime_profile.get("magazine_size", 1)),
		},
		facing
	)

func _draw() -> void:
	if arena_background_texture != null:
		draw_texture_rect(arena_background_texture, Rect2(0, 0, 1280, 720), false)
	else:
		draw_rect(Rect2(0, 0, 1280, 720), Color("09131f"), true)
	# Keep the authored floor visible. The previous debug grid competed with
	# silhouettes and made the arena look like a test room.
	draw_rect(WORLD_RECT, Color(0.01, 0.03, 0.05, 0.07), true)
	_draw_enemies()
	_draw_player_and_weapon()
	_draw_attacks()

func _draw_player_and_weapon() -> void:
	var pixel_position := Vector2(roundf(player_position.x), roundf(player_position.y))
	_draw_player_pixel_shadow(pixel_position)
	_draw_player_body(pixel_position)
	_draw_player_weapon_and_arms(pixel_position)


## Presentation-only seam: a themed arena can animate a different body without
## duplicating or replacing the production weapon/anchor/hit-geometry renderer.
func _draw_player_body(pixel_position: Vector2) -> void:
	draw_set_transform(pixel_position, 0.0, Vector2(facing, 1.0))
	var player_rect := Rect2(Vector2(-54.0, -53.0), Vector2(108.0, 108.0))
	for outline_offset: Vector2 in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
		draw_texture_rect(
			PLAYER_BASE_TEXTURE,
			Rect2(player_rect.position + outline_offset, player_rect.size),
			false,
			Color(0.32, 0.86, 0.92, 0.34)
		)
	var player_modulate := Color(1.0, 0.58, 0.58) if flash_timer > 0.0 else Color.WHITE
	draw_texture_rect(
		PLAYER_BASE_TEXTURE,
		player_rect,
		false,
		player_modulate
	)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_player_weapon_and_arms(pixel_position: Vector2) -> void:
	var firearm_action := _firearm_action_sample()
	var root_pose := firearm_action.get("root_pose", {}) as Dictionary
	var fit := _weapon_fit()
	var hand_base := _firearm_hand_base()
	var hand_primary := hand_base
	if melee_runtime.busy(): hand_primary += Vector2(melee_runtime.pose(facing).get("offset", Vector2.ZERO))
	var draw_scale := float(fit.get("draw_scale", 1.0))
	var weapon_rotation := _melee_weapon_rotation()
	if _uses_firearm_runtime():
		hand_primary += root_pose.get("offset", Vector2.ZERO) as Vector2
		weapon_rotation = float(root_pose.get("rotation", 0.0))
	var relative_secondary := Vector2(fit.get(
		"secondary_grip_delta",
		(asset.grip_secondary - asset.grip_primary) * draw_scale
	))
	var relative_secondary_world := Vector2(relative_secondary.x * facing, relative_secondary.y).rotated(weapon_rotation)
	var support_required := bool(fit.get("support_required", true))
	var resting_support := Vector2(fit.get("resting_support_offset", Vector2(-12.0, 15.0)))
	var hand_secondary := hand_primary + relative_secondary_world if support_required else player_position + Vector2(resting_support.x * facing, resting_support.y)
	var support_shoulder := pixel_position + Vector2(-7.0 * facing, -14.0)
	var primary_shoulder := pixel_position + Vector2(7.0 * facing, -16.0)
	var support_elbow := (
		pixel_position + Vector2(-16.0 * facing, 0.0)
		if not support_required
		else support_shoulder.lerp(hand_secondary, 0.48) + Vector2(-5.0 * facing, 6.0)
	)
	var primary_elbow := primary_shoulder.lerp(hand_primary, 0.48) + Vector2(-2.0 * facing, 5.0)
	_draw_player_pixel_arm(
		support_shoulder,
		support_elbow,
		hand_secondary,
		Color("294b57")
	)
	_draw_player_pixel_arm(
		primary_shoulder,
		primary_elbow,
		hand_primary,
		Color("3a6872")
	)
	var state_power := _melee_state_power()
	if blueprint.delivery == "whole_object_return" and not boomerang.is_empty():
		pass # The same object is in flight, not duplicated in the hand.
	elif melee_runtime.profile != null:
		if melee_frame.is_empty(): _build_melee_frame()
		for pixel: Dictionary in melee_frame.get("pixels", []):
			var size := float(pixel.get("size", 1.0))
			draw_rect(Rect2(Vector2(pixel["position"]) - Vector2.ONE * size * 0.5, Vector2.ONE * size), Color(pixel["color"]), true)
	elif _uses_stateful_pixel_morph() and state_power > 0.01:
		draw_set_transform(hand_primary, weapon_rotation, Vector2(facing * draw_scale, draw_scale))
		_draw_stateful_pixel_weapon_local(state_power)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	elif _uses_soft_mechanism_visual():
		_draw_soft_mechanism_weapon(_soft_weapon_geometry(hand_primary, weapon_rotation))
	else:
		draw_set_transform(hand_primary, weapon_rotation, Vector2(facing * draw_scale, draw_scale))
		var local_position := -asset.grip_primary
		draw_texture_rect(asset.texture, Rect2(local_position, Vector2(asset.canvas_size)), false)
		if _uses_firearm_runtime():
			_draw_firearm_action_overlays(firearm_action, hand_primary, weapon_rotation)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_melee_state_effect(hand_primary)
	_draw_player_pixel_hand(hand_primary, Color("f2c9a6"))
	_draw_player_pixel_hand(hand_secondary, Color("dcae88"))
	if debug_anchors:
		if _uses_firearm_runtime():
			_draw_firearm_world_anchor(hand_base, asset.grip_primary, root_pose, "GripPrimary", Color("5eead4"))
			_draw_firearm_world_anchor(hand_base, asset.grip_secondary, root_pose, "GripSecondary", Color("facc15"))
			_draw_firearm_world_anchor(hand_base, asset.muzzle, root_pose, "Muzzle", Color("38bdf8"))
			_draw_firearm_world_anchor(hand_base, asset.tip, root_pose, "Tip", Color("fb7185"))
		else:
			_draw_world_anchor(hand_primary, asset.grip_primary, asset.grip_primary, "GripPrimary", Color("5eead4"))
			_draw_world_anchor(hand_primary, asset.grip_secondary, asset.grip_primary, "GripSecondary", Color("facc15"))
			_draw_world_anchor(hand_primary, asset.muzzle, asset.grip_primary, "Muzzle", Color("38bdf8"))
			_draw_world_anchor(hand_primary, asset.tip, asset.grip_primary, "Tip", Color("fb7185"))
			_draw_world_anchor(hand_primary, asset.spin_pivot, asset.grip_primary, "SpinPivot", Color("c084fc"))


func _draw_player_pixel_shadow(position: Vector2) -> void:
	var core := Color(0.005, 0.008, 0.012, 0.48)
	var rim := Color(0.10, 0.13, 0.16, 0.30)
	draw_rect(Rect2(position + Vector2(-16.0, 42.0), Vector2(32.0, 2.0)), rim, true)
	draw_rect(Rect2(position + Vector2(-24.0, 44.0), Vector2(48.0, 4.0)), core, true)
	draw_rect(Rect2(position + Vector2(-18.0, 48.0), Vector2(36.0, 2.0)), rim, true)


func _draw_player_pixel_arm(start: Vector2, elbow: Vector2, finish: Vector2, sleeve: Color) -> void:
	var snapped_start := Vector2(roundf(start.x), roundf(start.y))
	var snapped_elbow := Vector2(roundf(elbow.x), roundf(elbow.y))
	var snapped_finish := Vector2(roundf(finish.x), roundf(finish.y))
	draw_line(snapped_start, snapped_elbow, Color("111827"), 8.0, false)
	draw_line(snapped_elbow, snapped_finish, Color("111827"), 8.0, false)
	draw_line(snapped_start, snapped_elbow, sleeve, 4.0, false)
	draw_line(snapped_elbow, snapped_finish, sleeve.lightened(0.10), 4.0, false)
	draw_rect(Rect2(snapped_elbow - Vector2(3.0, 3.0), Vector2(6.0, 6.0)), Color("111827"), true)
	draw_rect(Rect2(snapped_elbow - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), sleeve, true)


func _draw_player_pixel_hand(position: Vector2, skin: Color) -> void:
	var snapped := Vector2(roundf(position.x), roundf(position.y))
	draw_rect(Rect2(snapped - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), Color("111827"), true)
	draw_rect(Rect2(snapped - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), skin, true)


func _uses_stateful_pixel_morph() -> bool:
	if blueprint == null or asset == null or asset.source_image == null or asset.source_image.is_empty():
		return false
	if blueprint.behavior_family != "heavy_melee":
		return false
	return (
		str(blueprint.affordance.get("activation_mode", "passive")) != "passive"
		and str(blueprint.affordance.get("state_topology", "fixed")) != "fixed"
	)


func _melee_state_power() -> float:
	return melee_runtime.state_power() if _uses_stateful_pixel_morph() else 0.0


func _draw_stateful_pixel_weapon_local(power: float) -> void:
	var deformation: Dictionary = STATEFUL_PIXEL_MORPHER.deform_local(
		asset.source_image,
		asset.grip_primary,
		asset.tip,
		str(blueprint.affordance.get("state_topology", "fixed")),
		power,
		blueprint.affordance
	)
	for pixel: Dictionary in deformation.get("pixels", []):
		var position := Vector2(pixel.get("position", Vector2.ZERO))
		var size := maxf(1.0, float(pixel.get("size", 1.0)))
		draw_rect(Rect2(position - Vector2(size, size) * 0.5, Vector2(size, size)), Color(pixel.get("color", Color.WHITE)), true)


func _draw_melee_state_effect(_hand: Vector2) -> void:
	if not melee_runtime.active(): return
	var polygon: PackedVector2Array = melee_frame.get("field", PackedVector2Array())
	if polygon.size() < 3: return
	var output := str(melee_runtime.primitive().functional_output)
	if output == "directed_stream" and polygon.size() == 4:
		var start := (polygon[0] + polygon[3]) * 0.5
		var finish := (polygon[1] + polygon[2]) * 0.5
		var direction := (finish - start).normalized()
		var normal := Vector2(-direction.y, direction.x)
		var half_width := polygon[1].distance_to(polygon[2]) * 0.5
		for lane: int in range(-2, 3):
			for segment: int in range(6):
				var begin_ratio := 0.03 + float(segment) * 0.17 + float(abs(lane)) * 0.012
				var end_ratio := minf(0.98, begin_ratio + (0.11 if lane == 0 else 0.075))
				var lateral_begin := half_width * float(lane) / 3.2 * pow(begin_ratio, 1.35)
				var lateral_end := half_width * float(lane) / 3.2 * pow(end_ratio, 1.35)
				var line_start := start.lerp(finish, begin_ratio) + normal * lateral_begin
				var line_finish := start.lerp(finish, end_ratio) + normal * lateral_end
				draw_line(line_start.round(), line_finish.round(), Color("edf3e9" if lane == 0 and segment % 2 == 0 else "67e8f9", 0.94 if lane == 0 else 0.74), 2.0 if lane == 0 else 1.0, false)
		for index: int in range(1, 13):
			var ratio := (float(index) + 0.35) / 13.0
			var drift := sin(float(index) * 2.17) * half_width * ratio * 0.48
			var point := start.lerp(finish, ratio) + normal * drift
			var size := Vector2(3, 2) if index % 4 else Vector2(4, 3)
			draw_rect(Rect2((point - size * 0.5).round(), size), Color("edf3e9" if index % 4 == 0 else "67e8f9", 0.92), true)
		return
	var color := Color("67e8f9") if output != "pull_field" else Color("c4b5fd")
	draw_colored_polygon(polygon, Color(color, 0.18))
	var rim := polygon.duplicate()
	rim.append(polygon[0])
	draw_polyline(rim, Color(color, 0.70), 2.0, false)
	# This is emitted energy, not a substitute for the object's source pixels.


func _melee_weapon_rotation() -> float:
	return float(melee_runtime.pose(facing).get("angle", 0.0))


func _uses_soft_mechanism_visual() -> bool:
	if blueprint == null or asset == null or blueprint.behavior_family != "heavy_melee":
		return false
	if not asset.has_pixel_visual_rig():
		return false
	return (
		str(blueprint.affordance.get("flex_topology", "none")) != "none"
		or str(blueprint.affordance.get("tether_topology", "none")) != "none"
	)


func _soft_pixel_render_options() -> Dictionary:
	var legacy_linked := str(blueprint.affordance.get("flex_topology", "none")) == "linked_segments"
	var linked := legacy_linked or str(blueprint.affordance.get("tether_topology", "none")) == "linked_segments"
	var styled_links := linked and str(blueprint.modifiers.get("art_style_id", "")) == "church_v1"
	return {"readable_tether": not styled_links, "readable_links": legacy_linked and not styled_links}


func _draw_soft_mechanism_weapon(geometry: Dictionary) -> void:
	if geometry.is_empty() or asset == null or asset.visual_rig == null:
		return
	var deformation: Dictionary = PIXEL_WEAPON_DEFORMER.deform(asset.visual_rig, {
		"body": geometry.get("body", PackedVector2Array()),
		"tether": geometry.get("tether", PackedVector2Array()),
		"weapon_origin": geometry.get("weapon_origin", Vector2.ZERO),
		"source_grip": asset.grip_primary,
		"contact": geometry.get("contact", Vector2.ZERO),
		"weapon_angle": float(geometry.get("weapon_angle", 0.0)),
		"longitudinal_scale": float(geometry.get("longitudinal_scale", 1.0)),
		"facing": facing,
		"scale": float(_weapon_fit().get("draw_scale", 1.0)),
		"pixel_snap": true,
		"include_metadata": false,
		"compact_pixels": true,
	})
	for pixel: Dictionary in deformation.get("pixels", []):
		var size := float(pixel.get("size", 1.0))
		var position := Vector2(pixel.get("position", Vector2.ZERO))
		draw_rect(
			Rect2(position - Vector2(size, size) * 0.5, Vector2(size, size)),
			Color(pixel.get("color", Color.WHITE)),
			true
		)


func _soft_weapon_geometry(hand: Vector2, weapon_angle: float, longitudinal_scale: float = 1.0) -> Dictionary:
	if not _uses_soft_mechanism_visual():
		return {}
	var flex_topology := str(blueprint.affordance.get("flex_topology", "none"))
	var tether_topology := str(blueprint.affordance.get("tether_topology", "none"))
	var body_source: PackedVector2Array = asset.visual_rig.source_path_for_role("deform_body")
	var tether_source: PackedVector2Array = asset.visual_rig.source_path_for_role("tether")
	var body_start := hand
	var body_finish := _soft_source_world(asset.tip, hand, weapon_angle, longitudinal_scale)
	if not body_source.is_empty():
		body_start = _soft_source_world(body_source[0], hand, weapon_angle, longitudinal_scale)
		body_finish = _soft_source_world(body_source[body_source.size() - 1], hand, weapon_angle, longitudinal_scale)
	var tether_start := body_finish
	var resting_contact := body_finish
	if not tether_source.is_empty():
		tether_start = _soft_source_world(tether_source[0], hand, weapon_angle)
		resting_contact = _soft_source_world(tether_source[tether_source.size() - 1], hand, weapon_angle)
	var contact := resting_contact
	var attack_ratio := _soft_attack_ratio()
	var presentation := str(melee_runtime.primitive().presentation_family) if melee_runtime.primitive() != null else "default"
	var weighted_structure := (
		presentation.begins_with("weighted_")
		and (flex_topology in ["flexible_line", "linked_segments"] or tether_topology in ["flexible_line", "linked_segments"])
	)
	var depth_layer := 0.0
	if weighted_structure:
		# The terminal-loaded body and its attached segment are one continuous
		# mechanism. Drive the terminal around the held end before splitting that
		# same curve back into the rig's body/tether roles for source-pixel binding.
		contact = _weighted_flexible_contact(body_start, resting_contact, attack_ratio, presentation)
		var contact_span := maxf(1.0, body_start.distance_to(contact))
		depth_layer = clampf((contact.y - body_start.y) / contact_span, -1.0, 1.0)
	elif tether_topology != "none":
		contact = _soft_deployment_contact(
			tether_start,
			resting_contact,
			attack_ratio,
			str(melee_runtime.primitive().tether_deployment) if melee_runtime.primitive() != null else "fixed_length"
		)
	elif flex_topology == "flexible_line":
		contact = _soft_deployment_contact(body_start, resting_contact, attack_ratio, "lash")
		body_finish = contact
	var bend_sign := -facing
	var propagation := _soft_topology_propagation(attack_ratio, flex_topology)
	var body_path := PackedVector2Array()
	var tether_path := PackedVector2Array()
	if weighted_structure:
		var weighted_paths := _weighted_flexible_paths(
			body_start,
			contact,
			body_source,
			tether_source,
			presentation,
			bend_sign
		)
		body_path = weighted_paths.get("body", PackedVector2Array())
		tether_path = weighted_paths.get("tether", PackedVector2Array())
		if not body_path.is_empty(): body_finish = body_path[-1]
		if not tether_path.is_empty(): tether_start = tether_path[0]
	elif flex_topology != "none":
		body_path = _soft_curve_points(body_start, body_finish, flex_topology, propagation, bend_sign)
		if flex_topology == "linked_segments":
			body_path = _linked_body_points(body_start, body_finish, body_source, propagation, bend_sign)
			contact = body_path[-1]
			if tether_topology != "none": tether_start = contact
	if tether_topology != "none" and not weighted_structure:
		tether_path = _soft_curve_points(
			tether_start,
			contact,
			tether_topology,
			_soft_topology_propagation(attack_ratio, tether_topology),
			bend_sign
		)
	return {
		"weapon_origin": hand,
		"weapon_angle": weapon_angle,
		"longitudinal_scale": longitudinal_scale,
		"body": body_path,
		"tether": tether_path,
		"contact": contact,
		"attack_ratio": attack_ratio,
		"depth_layer": depth_layer,
	}


func _linked_body_points(start: Vector2, finish: Vector2, source: PackedVector2Array, propagation: float, bend_sign: float) -> PackedVector2Array:
	var joints: PackedFloat32Array = asset.visual_rig.linked_joint_ratios()
	if joints.is_empty(): return PackedVector2Array([start, finish])
	var source_length := 0.0
	for index: int in range(source.size() - 1): source_length += source[index].distance_to(source[index + 1])
	var length := source_length * float(_weapon_fit().get("draw_scale", 1.0))
	var ratios := joints.duplicate()
	ratios.append(1.0)
	var points := PackedVector2Array([start])
	var previous := 0.0
	var base_angle := (finish - start).angle()
	var presentation := str(melee_runtime.primitive().presentation_family) if melee_runtime.primitive() != null else "default"
	if presentation.begins_with("weighted_"):
		# Preserve every source segment length while laying the chain on one
		# readable arc. Alternating per-link lag used to fold adjacent links back
		# over the hand and made a full-length chain look like a short rigid nub.
		var arc_strength := 0.18 + 0.34 * sin(clampf(propagation, 0.0, 1.0) * PI)
		var overarm := presentation in ["weighted_lash_cross", "weighted_retract", "weighted_cast_charge"]
		var arc := arc_strength * (-bend_sign if overarm else bend_sign)
		for index: int in range(ratios.size()):
			var finish_ratio := float(ratios[index])
			var middle_ratio := (previous + finish_ratio) * 0.5
			var tangent_angle := base_angle - arc * 0.5 + arc * middle_ratio
			var segment_length := length * (finish_ratio - previous)
			points.append(points[-1] + Vector2.from_angle(tangent_angle) * segment_length)
			previous = finish_ratio
		return points
	var lag_amplitude := 1.25
	for index: int in range(ratios.size()):
		var lag := 0.0 if index == 0 else sin(propagation * TAU - float(index) * 0.90) * lag_amplitude * bend_sign
		var segment_length := length * (ratios[index] - previous)
		points.append(points[-1] + Vector2.from_angle(base_angle + lag) * segment_length)
		previous = ratios[index]
	return points


func _weighted_flexible_paths(
	start: Vector2,
	finish: Vector2,
	body_source: PackedVector2Array,
	tether_source: PackedVector2Array,
	presentation: String,
	bend_sign: float
) -> Dictionary:
	# Preserve the measured source length of the complete flexible structure.
	# The rig may call its two contiguous sections `deform_body` and `tether`,
	# but they must not animate as a fixed handle plus a tiny line at the tip.
	var scale := float(_weapon_fit().get("draw_scale", 1.0))
	var body_length := _polyline_length(body_source) * scale
	var tether_length := _polyline_length(tether_source) * scale
	var source_length := body_length + tether_length
	if source_length <= 0.5:
		return {"body": PackedVector2Array([start, finish]), "tether": PackedVector2Array()}
	var chord := start.distance_to(finish)
	var route_length := maxf(source_length, chord)
	var body_fraction := clampf(body_length / source_length, 0.0, 1.0)
	var curve_sign := bend_sign
	if presentation in ["weighted_lash_cross", "weighted_retract", "weighted_cast_charge"]:
		curve_sign *= -1.0
	var arc := _fixed_length_arc(start, finish, route_length, curve_sign)
	var ratios: Array[float] = [0.0, 1.0]
	for index: int in range(1, 33):
		ratios.append(float(index) / 33.0)
	if body_length > 0.0 and tether_length > 0.0:
		ratios.append(body_fraction)
	ratios.sort()
	var body := PackedVector2Array()
	var tether := PackedVector2Array()
	for ratio: float in ratios:
		var point := start.lerp(finish, ratio)
		if not bool(arc.get("linear", true)):
			point = Vector2(arc.center) + Vector2(arc.start_vector).rotated(float(arc.delta) * ratio)
		if tether_length <= 0.0 or ratio <= body_fraction + 0.0001:
			body.append(point)
		if tether_length > 0.0 and ratio >= body_fraction - 0.0001:
			tether.append(point)
	if body.is_empty(): body.append(start)
	if tether_length > 0.0 and tether.is_empty(): tether = PackedVector2Array([body[-1], finish])
	return {"body": body, "tether": tether}


func _fixed_length_arc(start: Vector2, finish: Vector2, length: float, bend_sign: float) -> Dictionary:
	var chord := start.distance_to(finish)
	if chord <= 0.5 or length <= chord * 1.001:
		return {"linear": true}
	# Solve chord / arc = 2 sin(theta / 2) / theta. This supports both
	# ordinary swings and a genuinely slack structure whose path exceeds a
	# semicircle; the source length must not disappear merely because the two
	# endpoints happen to be close together.
	var target := clampf(chord / length, 0.000001, 0.999999)
	var low := 0.0001
	var high := TAU - 0.0001
	for _step: int in range(32):
		var theta := (low + high) * 0.5
		var ratio := 2.0 * sin(theta * 0.5) / theta
		if ratio > target: low = theta
		else: high = theta
	var theta := (low + high) * 0.5
	var radius := length / theta
	var direction := (finish - start).normalized()
	var normal := Vector2(-direction.y, direction.x)
	var center_distance := sqrt(maxf(0.0, radius * radius - chord * chord * 0.25))
	var side := -1.0 if bend_sign < 0.0 else 1.0
	var center_side := side if theta <= PI else -side
	var center := (start + finish) * 0.5 + normal * center_distance * center_side
	var start_vector := start - center
	return {"linear": false, "center": center, "start_vector": start_vector, "delta": theta * side}


func _polyline_length(path: PackedVector2Array) -> float:
	var result := 0.0
	for index: int in range(path.size() - 1):
		result += path[index].distance_to(path[index + 1])
	return result


func _soft_source_world(source: Vector2, hand: Vector2, weapon_angle: float, longitudinal_scale: float = 1.0) -> Vector2:
	var local := source - asset.grip_primary
	local = Vector2(local.x * facing, local.y) * float(_weapon_fit().get("draw_scale", 1.0))
	local.x *= longitudinal_scale
	return hand + local.rotated(weapon_angle)


func _soft_attack_ratio() -> float:
	return melee_runtime.motion_ratio()


func _soft_deployment_contact(
	origin: Vector2,
	resting_contact: Vector2,
	ratio: float,
	deployment: String
) -> Vector2:
	if ratio <= 0.0:
		return resting_contact
	if deployment not in ["cast_retract", "launch_tension", "lash"]:
		return resting_contact
	var reach := maxf(origin.distance_to(resting_contact), _melee_axis_reach())
	var target := origin + Vector2(facing * reach, -minf(36.0, reach * 0.16))
	var tucked := origin + Vector2(-facing * 7.0, 18.0)
	if ratio < 0.30:
		return resting_contact.lerp(tucked, smoothstep(0.0, 1.0, ratio / 0.30))
	if ratio < 0.58:
		var outbound := smoothstep(0.0, 1.0, (ratio - 0.30) / 0.28)
		return tucked.lerp(target, outbound) + Vector2.UP * sin(outbound * PI) * 30.0
	if ratio < 0.82:
		return target
	if ratio < 0.94:
		return target.lerp(tucked, smoothstep(0.0, 1.0, (ratio - 0.82) / 0.12))
	return tucked.lerp(resting_contact, smoothstep(0.0, 1.0, (ratio - 0.94) / 0.06))


func _weighted_flexible_contact(
	origin: Vector2,
	resting_contact: Vector2,
	ratio: float,
	presentation: String
) -> Vector2:
	if ratio <= 0.0:
		return resting_contact
	var radius := maxf(24.0, origin.distance_to(resting_contact))
	var rest_local := Vector2(
		(resting_contact.x - origin.x) * facing,
		resting_contact.y - origin.y
	) / radius
	# These points are a projected ground-plane orbit, not a circle painted in
	# the camera plane. X carries the broad left/right travel while the smaller Y
	# excursion supplies depth. A visible terminal may pass behind the body in
	# the active phase because the same pixels, draw layer and collision all use
	# this path; there is no hidden rear damage sector.
	var times := PackedFloat32Array([0.0, 0.08, 0.20, 0.30, 0.46, 0.64, 0.82, 0.93, 1.0])
	var points := PackedVector2Array()
	match presentation:
		"weighted_cast_low", "weighted_dodge_lash":
			points = PackedVector2Array([
				rest_local, Vector2(0.40, 0.18), Vector2(-0.55, 0.22),
				Vector2(-0.92, 0.18), Vector2(-0.06, 0.34), Vector2(1.00, 0.06),
				Vector2(0.84, 0.24), Vector2(0.24, 0.20), rest_local,
			])
		"weighted_lash_cross", "weighted_cast_charge":
			points = PackedVector2Array([
				rest_local, Vector2(0.35, -0.14), Vector2(-0.62, -0.20),
				Vector2(-0.96, -0.16), Vector2(-0.08, -0.34), Vector2(1.00, 0.04),
				Vector2(0.82, 0.26), Vector2(0.18, 0.20), rest_local,
			])
		_:
			# Pull/recovery reverses across the waist before returning to the hand.
			points = PackedVector2Array([
				rest_local, Vector2(0.40, 0.12), Vector2(-0.48, 0.18),
				Vector2(-0.90, 0.12), Vector2(-0.02, -0.30), Vector2(1.00, -0.02),
				Vector2(0.68, 0.22), Vector2(-0.18, 0.16), rest_local,
			])
	var clamped_ratio := clampf(ratio, 0.0, 1.0)
	for index: int in range(times.size() - 1):
		if clamped_ratio <= times[index + 1]:
			var segment_ratio := inverse_lerp(times[index], times[index + 1], clamped_ratio)
			var local := points[index].lerp(points[index + 1], smoothstep(0.0, 1.0, segment_ratio))
			return origin + Vector2(local.x * facing, local.y) * radius
	return resting_contact


func _soft_topology_propagation(ratio: float, topology: String) -> float:
	var lag := float({
		"bending_shaft": 0.08,
		"flexible_line": 0.18,
		"linked_segments": 0.13,
	}.get(topology, 0.0))
	return clampf((ratio - lag) / maxf(0.01, 1.0 - lag), 0.0, 1.0)


func _soft_curve_points(
	start: Vector2,
	finish: Vector2,
	topology: String,
	propagation: float,
	bend_sign: float
) -> PackedVector2Array:
	var span := finish - start
	if span.length_squared() < 1.0:
		return PackedVector2Array([start, finish])
	var normal := Vector2(-span.y, span.x).normalized()
	var bend_scale := float({
		"bending_shaft": 0.10,
		"flexible_line": 0.22,
		"linked_segments": 0.16,
	}.get(topology, 0.0))
	var bend := span.length() * bend_scale * sin((0.18 + propagation * 0.82) * PI)
	var steps := 9 if topology == "linked_segments" else 14
	var points := PackedVector2Array()
	for index: int in range(steps + 1):
		var point_ratio := float(index) / float(steps)
		var envelope := sin(point_ratio * PI)
		if topology == "flexible_line":
			envelope *= 0.45 + point_ratio * 0.85
		points.append(start + span * point_ratio + normal * bend * bend_sign * envelope)
	return points

func _smooth_unit(value: float) -> float:
	var clamped := clampf(value, 0.0, 1.0)
	return clamped * clamped * (3.0 - 2.0 * clamped)

func _draw_world_anchor(hand: Vector2, point: Vector2, grip: Vector2, label: String, color: Color) -> void:
	var relative := (point - grip) * float(_weapon_fit().get("draw_scale", 1.0))
	var world := hand + Vector2(relative.x * facing, relative.y)
	draw_circle(world, 5.0, color)
	draw_string(ThemeDB.fallback_font, world + Vector2(6, -5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)


func _draw_firearm_world_anchor(
	hand_base: Vector2,
	point: Vector2,
	root_pose: Dictionary,
	label: String,
	color: Color
) -> void:
	var world := FIREARM_ACTION_CHOREOGRAPHY.world_anchor(
		hand_base,
		point,
		asset.grip_primary,
		root_pose,
		_firearm_draw_scale()
	)
	draw_circle(world, 5.0, color)
	draw_string(ThemeDB.fallback_font, world + Vector2(6, -5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)


func _draw_firearm_action_overlays(action: Dictionary, hand: Vector2, root_rotation: float) -> void:
	_draw_cycle_overlay(action.get("cycle_overlay_pose", {}) as Dictionary, hand, root_rotation)
	_draw_reload_object(action.get("reload_object_pose", {}) as Dictionary, hand, root_rotation)
	_draw_ejected_case(action.get("ejection_pose", {}) as Dictionary, hand, root_rotation)


func _draw_cycle_overlay(pose: Dictionary, hand: Vector2, root_rotation: float) -> void:
	if not bool(pose.get("visible", false)):
		return
	var local_position := Vector2(7.0, -8.0) + (pose.get("local_position", Vector2.ZERO) as Vector2)
	var position := hand + Vector2(local_position.x * facing, local_position.y).rotated(root_rotation)
	draw_set_transform(position, root_rotation + float(pose.get("rotation", 0.0)) * facing, Vector2(facing, 1.0))
	match str(pose.get("kind", "")):
		"self_loading_bolt":
			draw_rect(Rect2(-5, -2, 10, 4), Color("d7e1e8"), true)
		"bolt_handle":
			draw_line(Vector2(-2, 0), Vector2(6, 6), Color("d7e1e8"), 3.0)
			draw_circle(Vector2(7, 7), 3.0, Color("7d8b96"))
		"pump_fore_end":
			draw_rect(Rect2(16, 8, 22, 9), Color("8b5a36"), true)
			draw_line(Vector2(18, 11), Vector2(36, 11), Color("c58a54"), 2.0)
		"cylinder_index":
			draw_circle(Vector2.ZERO, 8.0, Color("343e47"))
			for angle: float in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
				draw_circle(Vector2.from_angle(angle) * 4.0, 1.5, Color("9eabb4"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_reload_object(pose: Dictionary, hand: Vector2, root_rotation: float) -> void:
	if not bool(pose.get("visible", false)):
		return
	var local_position := pose.get("local_position", Vector2.ZERO) as Vector2
	var position := hand + Vector2(local_position.x * facing, local_position.y).rotated(root_rotation)
	draw_set_transform(position, root_rotation + float(pose.get("rotation", 0.0)) * facing, Vector2(facing, 1.0))
	match str(pose.get("kind", "")):
		"magazine":
			draw_rect(Rect2(-5, -10, 10, 22), Color("252c33"), true)
			draw_line(Vector2(-3, -7), Vector2(3, 8), Color("77838d"), 2.0)
		"single_round":
			draw_rect(Rect2(-6, -2, 10, 4), Color("c7893d"), true)
			draw_circle(Vector2(5, 0), 2.0, Color("e7c15d"))
		"speedloader":
			draw_circle(Vector2.ZERO, 8.0, Color("b5c0c8"), false, 3.0)
			for angle: float in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
				draw_circle(Vector2.from_angle(angle) * 4.0, 2.0, Color("d49a42"))
		"belt_box":
			draw_rect(Rect2(-10, -7, 20, 16), Color("46523d"), true)
			for index: int in range(4):
				draw_circle(Vector2(-8 + index * 5, -10), 2.0, Color("d49a42"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_ejected_case(pose: Dictionary, hand: Vector2, root_rotation: float) -> void:
	if not bool(pose.get("visible", false)):
		return
	var local_position := pose.get("local_position", Vector2.ZERO) as Vector2
	var position := hand + Vector2(local_position.x * facing, local_position.y).rotated(root_rotation)
	draw_set_transform(position, root_rotation + float(pose.get("rotation", 0.0)) * facing, Vector2(facing, 1.0))
	var size := Vector2(8, 4) if str(pose.get("kind", "")) == "spent_shell" else Vector2(6, 3)
	draw_rect(Rect2(-size * 0.5, size), Color("d49a42"), true)
	if str(pose.get("kind", "")) == "spent_casing_cluster":
		draw_rect(Rect2(Vector2(-2, 4), size), Color("d49a42"), true)
		draw_rect(Rect2(Vector2(3, -3), size), Color("d49a42"), true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_firearm_muzzle_flash() -> void:
	if muzzle_flash_timer <= 0.0:
		return
	var flash_muzzle := _muzzle_world()
	var flash_pose := (_firearm_action_sample().get("flash_pose", {}) as Dictionary)
	var flash_scale := flash_pose.get("scale", Vector2.ONE) as Vector2
	draw_colored_polygon(PackedVector2Array([
		flash_muzzle + Vector2(0, -7.0 * flash_scale.y),
		flash_muzzle + Vector2(17.0 * facing * flash_scale.x, 0),
		flash_muzzle + Vector2(0, 7.0 * flash_scale.y),
		flash_muzzle + Vector2(5.0 * facing * flash_scale.x, 0),
	]), Color("fde047"))

func _enemy_ground_draw_offset() -> Vector2:
	return Vector2.ZERO

func _draw_attacks() -> void:
	for projectile: Dictionary in projectiles:
		var position: Vector2 = projectile["pos"]
		var velocity: Vector2 = projectile.get("vel", Vector2(facing, 0.0))
		var direction := velocity.normalized() if velocity.length() > 0.001 else Vector2(facing, 0.0)
		var radius := float(projectile.get("projectile_radius_pixels", 4.0))
		var tracer_width := float(projectile.get("tracer_width_pixels", 3.0))
		var tracer_length := float(projectile.get("tracer_length_pixels", 15.0))
		draw_circle(position, radius * 2.0, Color(0.1, 0.6, 1.0, 0.22))
		draw_line(position - direction * tracer_length, position, Color("2563eb"), tracer_width)
		draw_circle(position, radius, Color("67e8f9"))
	if not boomerang.is_empty():
		var position: Vector2 = boomerang["pos"]
		draw_arc(position, 20.0, 0.0, TAU, 16, Color("5eead4"), 5.0)
		draw_line(position - Vector2(16, 0), position + Vector2(16, 0), Color("a78bfa"), 4.0)
	for hazard: Dictionary in enemy_attack_hazards:
		var hazard_position: Vector2 = Vector2(hazard.get("pos", Vector2.ZERO))
		var effect_family := str(hazard.get("effect_family", ""))
		if str(hazard.get("delivery", "")) == "projectile":
			var velocity: Vector2 = Vector2(hazard.get("vel", Vector2.ZERO))
			var direction := velocity.normalized() if velocity.length() > 0.001 else Vector2.RIGHT
			var projectile_edge := Color("d8b4fe") if effect_family == "echo" else (Color("a3e635") if effect_family == "residue" else Color("fb923c"))
			draw_line(hazard_position - direction * 18.0, hazard_position, projectile_edge.darkened(0.25), 5.0)
			draw_circle(hazard_position, 7.0, projectile_edge)
			draw_circle(hazard_position, 3.0, Color("fff7ed"))
		else:
			var region := hazard.get("hit_region", {}) as Dictionary
			hazard_position += _enemy_ground_draw_offset()
			var life_ratio := clampf(float(hazard.get("life", 0.0)) / maxf(0.001, float(hazard.get("maximum_life", 0.0))), 0.0, 1.0)
			var hazard_mode := str(hazard.get("hazard_mode", "instant"))
			var dangerous_now := _enemy_hazard_dangerous_now(hazard)
			var fill_color := Color(0.38, 0.76, 0.26, 0.22) if hazard_mode == "lingering" else Color(0.95, 0.18, 0.12, 0.18)
			var edge_color := Color("84cc16") if hazard_mode == "lingering" else Color("fb7185")
			if effect_family == "echo":
				fill_color = Color(0.69, 0.42, 0.94, 0.15)
				edge_color = Color("d8b4fe")
			elif effect_family == "residue":
				fill_color = Color(0.51, 0.78, 0.18, 0.22)
				edge_color = Color("a3e635")
			if hazard_mode == "pulsing":
				fill_color = Color(0.45, 0.32, 0.95, 0.30 if dangerous_now else 0.08)
				edge_color = Color("c4b5fd") if dangerous_now else Color(0.55, 0.48, 0.75, 0.62)
			var direction := Vector2(hazard.get("locked_direction", Vector2.RIGHT)).normalized()
			if direction.is_zero_approx(): direction = Vector2.RIGHT
			if str(region.get("shape", "")) in ["strip", "capsule"]:
				var forward_length := float(region.get("length_pixels", 0.0))
				var half_width := float(region.get("width_pixels", 0.0)) * 0.5
				var side := direction.orthogonal() * half_width
				var lane_fill := PackedVector2Array([
					hazard_position + side,
					hazard_position + direction * forward_length + side,
					hazard_position + direction * forward_length - side,
					hazard_position - side,
				])
				draw_colored_polygon(lane_fill, fill_color)
			_draw_attack_hit_region(hazard_position, direction, region, edge_color)
			if str(region.get("shape", "")) == "circle":
				var radius := float(region.get("radius_pixels", 0.0))
				_draw_pixel_disc(hazard_position, radius, fill_color)
				_draw_pixel_arc(hazard_position, radius, 0.0, TAU, edge_color, 5.0, 28)
				_draw_pixel_arc(hazard_position, radius * life_ratio, 0.0, TAU, Color("fde047"), 3.0, 24)
			elif effect_family == "echo":
				# Three square ticks make the delayed repeat legible without a
				# smooth vector clock that would clash with the pixel art.
				for tick: int in range(3):
					draw_rect(Rect2((hazard_position + Vector2(-8 + tick * 8, -20)).round(), Vector2(4, 4)), edge_color)
	# No generic arc: the actual weapon and compiled output are drawn.
	if blueprint != null and blueprint.behavior_family == "sustained_ranged" and attack_charge > 0.0:
		var muzzle := _muzzle_world()
		draw_circle(muzzle, 6.0 + minf(attack_charge, 0.35) * 15.0, Color(0.15, 0.78, 1.0, 0.7), false, 3.0)
	_draw_firearm_muzzle_flash()

func _draw_enemies() -> void:
	for enemy: Dictionary in enemies:
		_draw_enemy(enemy)


## Single-unit rendering lets themed arenas depth-sort without mutating enemies.
func _draw_enemy(enemy: Dictionary) -> void:
	var position: Vector2 = enemy["pos"]
	var shadow_half_width := 38.0 if str(enemy.get("mass_class", "medium")) == "heavy" else 30.0
	_draw_unit_pixel_shadow(position + Vector2(0.0, 45.0), shadow_half_width)
	var sprite_attack := _enemy_sprite_attack(enemy)
	var formal_sprite_drawn := false
	var mechanism_sprite_drawn := false
	if not sprite_attack.is_empty():
		formal_sprite_drawn = _draw_enemy_formal_sprite(enemy, sprite_attack)
		if not formal_sprite_drawn:
			mechanism_sprite_drawn = _draw_enemy_axis_sprite(enemy, sprite_attack)
	if not formal_sprite_drawn and not mechanism_sprite_drawn:
		_draw_noncombat_target(enemy, position)
	if float(enemy.get("burn", 0.0)) > 0.0:
		draw_rect(Rect2(position + Vector2(-6, -74), Vector2(12, 12)), Color("38bdf8"), true)
	_draw_enemy_attack_preview(enemy)
	_draw_target_interaction(enemy)
	var max_hp := float(enemy["max_hp"])
	var ratio := clampf(float(enemy["hp"]) / maxf(1.0, max_hp), 0.0, 1.0)
	var visual_asset := enemy.get("visual_asset", {}) as Dictionary
	var health_y := float(visual_asset.get("health_bar_y", -58.0)) if formal_sprite_drawn else (-58.0 if mechanism_sprite_drawn else -40.0)
	draw_rect(Rect2(position + Vector2(-28, health_y - 3), Vector2(56, 10)), Color("070b0f"), true)
	draw_rect(Rect2(position + Vector2(-26, health_y - 1), Vector2(52, 6)), Color("27303a"), true)
	var filled_segments := ceili(ratio * 10.0)
	for segment: int in range(10):
		if segment >= filled_segments:
			break
		draw_rect(
			Rect2(position + Vector2(-25 + segment * 5, health_y), Vector2(4, 4)),
			Color("eaa35c"),
			true
		)


func _draw_unit_pixel_shadow(position: Vector2, half_width: float) -> void:
	var snapped := _snap_enemy_pixel(position)
	var core := Color(0.005, 0.008, 0.012, 0.48)
	var rim := Color(0.10, 0.13, 0.16, 0.30)
	draw_rect(Rect2(snapped + Vector2(-half_width * 0.64, -4.0), Vector2(half_width * 1.28, 2.0)), rim, true)
	draw_rect(Rect2(snapped + Vector2(-half_width, -2.0), Vector2(half_width * 2.0, 4.0)), core, true)
	draw_rect(Rect2(snapped + Vector2(-half_width * 0.74, 2.0), Vector2(half_width * 1.48, 2.0)), rim, true)


func _enemy_sprite_attack(enemy: Dictionary) -> Dictionary:
	var attack_runtime: Variant = enemy.get("attack_runtime", null)
	if attack_runtime == null:
		return {}
	if not attack_runtime.current_attack.is_empty():
		return attack_runtime.current_attack
	var compiled: Array = attack_runtime.compiled_attacks
	if compiled.is_empty():
		return {}
	return compiled[0] as Dictionary


func _draw_noncombat_target(enemy: Dictionary, position: Vector2) -> void:
	if str(enemy.get("type", "")) == "moving_target":
		draw_circle(position, 25.0, Color("475569"))
		draw_circle(position, 14.0, Color("38bdf8"))
		draw_circle(position, 5.0, Color("f8fafc"))
		return
	draw_rect(Rect2(position - Vector2(8, 34), Vector2(16, 68)), Color("64748b"), true)
	draw_circle(position - Vector2(0, 33), 25.0, Color("ef4444"), false, 7.0)


func _draw_enemy_formal_sprite(enemy: Dictionary, compiled_attack: Dictionary) -> bool:
	var visual_asset := enemy.get("visual_asset", {}) as Dictionary
	var texture := visual_asset.get("texture") as Texture2D
	if texture == null:
		return false
	var sprite: Dictionary = ENEMY_ATTACK_SPRITE.compile(compiled_attack)
	if not bool(sprite.get("ok", false)):
		return false
	var attack_runtime: Variant = enemy.get("attack_runtime", null)
	var phase := "idle"
	var phase_elapsed := 0.0
	var direction := Vector2(float(enemy.get("facing", -1.0)), 0.0)
	if attack_runtime != null and not attack_runtime.current_attack.is_empty():
		phase = str(attack_runtime.phase)
		phase_elapsed = float(attack_runtime.phase_elapsed)
		direction = Vector2(attack_runtime.locked_direction).normalized()
	if direction.is_zero_approx():
		direction = Vector2(float(enemy.get("facing", -1.0)), 0.0)
	var facing_sign := -1.0 if direction.x < 0.0 else 1.0
	var progress := _enemy_sprite_phase_progress(compiled_attack, phase, phase_elapsed)
	var animation_hz := float(sprite.get("animation_hz", 4.0))
	var animation_frame := int(floor(phase_elapsed * animation_hz)) % 2
	var pose_offset := _enemy_sprite_pose_offset(sprite, phase, progress, animation_frame, facing_sign)
	var base := _snap_enemy_pixel(Vector2(enemy["pos"]) + pose_offset)
	var draw_size := visual_asset.get("draw_size", Vector2(160, 128)) as Vector2
	var anchor := visual_asset.get("anchor", Vector2(80, 76)) as Vector2
	var rotation := _enemy_formal_sprite_rotation(sprite, phase, progress, facing_sign)
	var pulse_scale := 1.0
	if phase in ["telegraph", "commit"] and animation_frame == 1:
		pulse_scale = 1.025
	var modulate := Color(1.0, 0.62, 0.62) if float(enemy.get("hurt", 0.0)) > 0.0 else Color.WHITE
	draw_set_transform(base, rotation, Vector2(facing_sign * pulse_scale, pulse_scale))
	draw_texture_rect(texture, Rect2(-anchor, draw_size), false, modulate)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


func _enemy_formal_sprite_rotation(
	sprite: Dictionary,
	phase: String,
	progress: float,
	facing_sign: float
) -> float:
	var family := str(sprite.get("tool_family", "swing_limb"))
	match phase:
		"telegraph":
			return -facing_sign * lerpf(0.0, 0.14 if family == "swing_limb" else 0.06, progress)
		"commit":
			return facing_sign * lerpf(-0.10, 0.08, progress) if family == "swing_limb" else 0.0
		"active":
			if family == "swing_limb":
				return facing_sign * lerpf(0.10, 0.34, progress)
			if family == "barrel":
				return -facing_sign * 0.08
			return facing_sign * 0.04
		"recovery":
			return facing_sign * lerpf(0.08, 0.0, progress)
	return 0.0


func _draw_enemy_axis_sprite(enemy: Dictionary, compiled_attack: Dictionary) -> bool:
	var sprite: Dictionary = ENEMY_ATTACK_SPRITE.compile(compiled_attack)
	if not bool(sprite.get("ok", false)):
		return false
	var identity: Dictionary = ENEMY_IDENTITY_VISUAL.compile(enemy.get("visual_identity_axes", {}) as Dictionary)
	if not bool(identity.get("ok", false)):
		return false
	var attack_runtime: Variant = enemy.get("attack_runtime", null)
	var phase := "idle"
	var phase_elapsed := 0.0
	var direction := Vector2(float(enemy.get("facing", -1.0)), 0.0)
	if attack_runtime != null and not attack_runtime.current_attack.is_empty():
		phase = str(attack_runtime.phase)
		phase_elapsed = float(attack_runtime.phase_elapsed)
		direction = Vector2(attack_runtime.locked_direction).normalized()
	if direction.is_zero_approx():
		direction = Vector2(float(enemy.get("facing", -1.0)), 0.0)
	var facing_sign := -1.0 if direction.x < 0.0 else 1.0
	var progress := _enemy_sprite_phase_progress(compiled_attack, phase, phase_elapsed)
	var animation_hz := float(sprite.get("animation_hz", 4.0))
	var animation_frame := int(floor(phase_elapsed * animation_hz)) % 2
	var scale_multiplier := float(identity.get("scale_multiplier", 1.0))
	var body_width := float(sprite.get("body_width", 28.0)) * scale_multiplier
	var body_height := float(sprite.get("body_height", 32.0)) * scale_multiplier
	var pose_offset := _enemy_sprite_pose_offset(sprite, phase, progress, animation_frame, facing_sign)
	var base := _snap_enemy_pixel(Vector2(enemy["pos"]) + pose_offset)
	var outline := Color("111827")
	var material_color := Color(str(identity.get("material_color", "64748b")))
	var stability_color := Color(str(sprite.get("body_color", "64748b")))
	var body_color := Color("f8fafc") if float(enemy.get("hurt", 0.0)) > 0.0 else material_color.lerp(stability_color, 0.28)
	var accent := Color(str(sprite.get("accent_color", "facc15")))
	var identity_accent := Color(str(identity.get("accent_color", "f59e0b")))
	var body_plan := str(identity.get("body_plan", "biped"))
	_draw_enemy_identity_body(
		base, body_width, body_height, facing_sign, body_plan,
		str(sprite.get("stance_family", "narrow")), int(sprite.get("armor_plate_count", 0)),
		outline, body_color
	)
	_draw_enemy_axis_tool(base, body_width, body_height, facing_sign, direction, phase, progress, sprite, outline, accent)
	_draw_enemy_signature_feature(
		base, body_width, body_height, facing_sign, body_plan,
		str(identity.get("signature_feature", "shoulder_core")), outline, identity_accent
	)
	_draw_enemy_axis_sensor(
		base, body_width, body_height, facing_sign, body_plan,
		str(sprite.get("sensor_family", "tracking_eye")), outline, identity_accent
	)
	return true


func _enemy_sprite_phase_progress(compiled_attack: Dictionary, phase: String, phase_elapsed: float) -> float:
	if phase == "idle":
		return 0.0
	var timeline := compiled_attack.get("timeline", {}) as Dictionary
	var duration := float(timeline.get("%s_seconds" % phase, 0.0))
	if duration <= 0.0001:
		return 1.0
	return clampf(phase_elapsed / duration, 0.0, 1.0)


func _enemy_sprite_pose_offset(
	sprite: Dictionary,
	phase: String,
	progress: float,
	animation_frame: int,
	facing_sign: float
) -> Vector2:
	var family := str(sprite.get("tool_family", "swing_limb"))
	var pixel_pulse := -2.0 if animation_frame == 1 and phase in ["telegraph", "commit"] else 0.0
	match phase:
		"telegraph":
			if family == "ram_prongs":
				return Vector2(-facing_sign * lerpf(0.0, 7.0, progress), lerpf(0.0, 6.0, progress) + pixel_pulse)
			return Vector2(-facing_sign * lerpf(0.0, 3.0, progress), pixel_pulse)
		"commit":
			return Vector2(facing_sign * lerpf(0.0, 3.0, progress), pixel_pulse)
		"active":
			if family == "ram_prongs":
				return Vector2(facing_sign * 9.0, 0.0)
			if family == "barrel":
				return Vector2(-facing_sign * 6.0, 0.0)
			return Vector2(facing_sign * 4.0, -2.0)
		"recovery":
			return Vector2(0.0, lerpf(0.0, float(sprite.get("recovery_drop_pixels", 2.0)), progress))
	return Vector2.ZERO


func _draw_enemy_identity_body(
	base: Vector2,
	body_width: float,
	body_height: float,
	facing_sign: float,
	body_plan: String,
	stance_family: String,
	armor_plate_count: int,
	outline: Color,
	body_color: Color
) -> void:
	match body_plan:
		"arachnid":
			var core_width := body_width * 0.92
			var core_height := body_height * 0.62
			for side_sign: float in [-1.0, 1.0]:
				for leg_index: int in range(4):
					var root := base + Vector2(side_sign * core_width * 0.30, -core_height * 0.22 + float(leg_index) * core_height * 0.15)
					var knee := root + Vector2(side_sign * (10.0 + float(leg_index) * 2.0), -8.0 + float(leg_index) * 5.0)
					var foot := knee + Vector2(side_sign * (10.0 + float(leg_index)), 8.0 + float(leg_index) * 3.0)
					draw_line(root, knee, outline, 6.0)
					draw_line(knee, foot, outline, 5.0)
					draw_line(root, knee, body_color, 3.0)
					draw_line(knee, foot, body_color, 2.0)
			var abdomen := base - Vector2(facing_sign * core_width * 0.42, 0)
			draw_rect(Rect2(abdomen - Vector2(core_width * 0.38 + 3, core_height * 0.42 + 3), Vector2(core_width * 0.76 + 6, core_height * 0.84 + 6)), outline, true)
			draw_rect(Rect2(abdomen - Vector2(core_width * 0.38, core_height * 0.42), Vector2(core_width * 0.76, core_height * 0.84)), body_color.darkened(0.12), true)
			draw_rect(Rect2(base - Vector2(core_width * 0.42 + 3, core_height * 0.50 + 3), Vector2(core_width * 0.84 + 6, core_height + 6)), outline, true)
			draw_rect(Rect2(base - Vector2(core_width * 0.42, core_height * 0.50), Vector2(core_width * 0.84, core_height)), body_color, true)
			_draw_enemy_identity_plates(base, core_width * 0.76, core_height, armor_plate_count, body_color)
		"quadruped":
			var torso_width := body_width * 1.34
			var torso_height := body_height * 0.68
			for leg_x: float in [-0.42, -0.18, 0.18, 0.42]:
				var root := base + Vector2(torso_width * leg_x, torso_height * 0.32)
				var foot := root + Vector2(4.0 * signf(leg_x), body_height * 0.62)
				draw_line(root, foot, outline, 8.0)
				draw_line(root, foot, body_color, 4.0)
			draw_rect(Rect2(base - Vector2(torso_width * 0.5 + 3, torso_height * 0.5 + 3), Vector2(torso_width + 6, torso_height + 6)), outline, true)
			draw_rect(Rect2(base - Vector2(torso_width * 0.5, torso_height * 0.5), Vector2(torso_width, torso_height)), body_color, true)
			_draw_enemy_identity_plates(base, torso_width, torso_height, armor_plate_count, body_color)
		"serpentine":
			for segment_index: int in range(5, 0, -1):
				var segment_size := maxf(8.0, body_height * (0.58 - float(segment_index) * 0.055))
				var segment_center := base - Vector2(facing_sign * float(segment_index) * body_width * 0.34, -sin(float(segment_index) * 1.4) * 5.0)
				draw_rect(Rect2(segment_center - Vector2(segment_size * 0.5 + 2, segment_size * 0.5 + 2), Vector2(segment_size + 4, segment_size + 4)), outline, true)
				draw_rect(Rect2(segment_center - Vector2(segment_size * 0.5, segment_size * 0.5), Vector2(segment_size, segment_size)), body_color.darkened(float(segment_index) * 0.035), true)
			draw_rect(Rect2(base - Vector2(body_width * 0.48 + 3, body_height * 0.42 + 3), Vector2(body_width * 0.96 + 6, body_height * 0.84 + 6)), outline, true)
			draw_rect(Rect2(base - Vector2(body_width * 0.48, body_height * 0.42), Vector2(body_width * 0.96, body_height * 0.84)), body_color, true)
			_draw_enemy_identity_plates(base, body_width * 0.9, body_height * 0.72, armor_plate_count, body_color)
		"floating":
			var radius := maxf(body_width, body_height) * 0.55
			var diamond := PackedVector2Array([
				base + Vector2(0, -radius), base + Vector2(radius, 0),
				base + Vector2(0, radius), base + Vector2(-radius, 0),
			])
			draw_colored_polygon(diamond, outline)
			var inner := PackedVector2Array([
				base + Vector2(0, -radius + 4), base + Vector2(radius - 4, 0),
				base + Vector2(0, radius - 4), base + Vector2(-radius + 4, 0),
			])
			draw_colored_polygon(inner, body_color)
			for offset: Vector2 in [Vector2(-18, radius + 8), Vector2(0, radius + 12), Vector2(18, radius + 8)]:
				draw_rect(Rect2(base + offset - Vector2(3, 3), Vector2(6, 6)), body_color.lightened(0.25), true)
		"tracked":
			var track_width := body_width * 1.32
			var track_height := maxf(14.0, body_height * 0.38)
			var track_center := base + Vector2(0, body_height * 0.33)
			draw_rect(Rect2(track_center - Vector2(track_width * 0.5 + 3, track_height * 0.5 + 3), Vector2(track_width + 6, track_height + 6)), outline, true)
			draw_rect(Rect2(track_center - Vector2(track_width * 0.5, track_height * 0.5), Vector2(track_width, track_height)), body_color.darkened(0.24), true)
			for wheel_x: float in [-0.34, 0.0, 0.34]:
				draw_circle(track_center + Vector2(track_width * wheel_x, 0), track_height * 0.28, body_color.lightened(0.18))
			draw_rect(Rect2(base - Vector2(body_width * 0.5 + 3, body_height * 0.48 + 3), Vector2(body_width + 6, body_height * 0.76 + 6)), outline, true)
			draw_rect(Rect2(base - Vector2(body_width * 0.5, body_height * 0.48), Vector2(body_width, body_height * 0.76)), body_color, true)
			_draw_enemy_identity_plates(base - Vector2(0, body_height * 0.1), body_width, body_height * 0.6, armor_plate_count, body_color)
		_:
			_draw_enemy_axis_stance(base, body_width, body_height, facing_sign, stance_family, outline, body_color)
			_draw_enemy_axis_chassis(base, body_width, body_height, armor_plate_count, outline, body_color)


func _draw_enemy_identity_plates(base: Vector2, width: float, height: float, count: int, body_color: Color) -> void:
	if count <= 0:
		return
	var plate_color := body_color.lightened(0.25)
	var plate_width := maxf(5.0, (width - 6.0) / float(count))
	for index: int in range(count):
		var x := -width * 0.5 + 3.0 + float(index) * plate_width
		draw_rect(Rect2(base + Vector2(x, -height * 0.30), Vector2(plate_width - 2.0, height * 0.60)), plate_color, true)


func _draw_enemy_signature_feature(
	base: Vector2,
	body_width: float,
	body_height: float,
	facing_sign: float,
	body_plan: String,
	feature: String,
	outline: Color,
	accent: Color
) -> void:
	var front := base + Vector2(facing_sign * body_width * (0.66 if body_plan in ["quadruped", "tracked"] else 0.48), -body_height * 0.08)
	match feature:
		"mandibles":
			for y_sign: float in [-1.0, 1.0]:
				var root := front + Vector2(0, y_sign * 5.0)
				var tip := root + Vector2(facing_sign * 16.0, y_sign * 8.0)
				draw_line(root, tip, outline, 6.0)
				draw_line(root, tip, accent, 3.0)
		"horns":
			for x_sign: float in [-1.0, 1.0]:
				var root := base + Vector2(x_sign * body_width * 0.26, -body_height * 0.56)
				var horn := PackedVector2Array([root + Vector2(-5, 0), root + Vector2(5, 0), root + Vector2(x_sign * 5, -15)])
				draw_colored_polygon(horn, outline)
				draw_line(root, root + Vector2(x_sign * 4, -11), accent, 3.0)
		"dorsal_spines":
			for amount: float in [-0.28, 0.0, 0.28]:
				var root := base + Vector2(body_width * amount, -body_height * 0.48)
				var spine := PackedVector2Array([root + Vector2(-5, 0), root + Vector2(5, 0), root + Vector2(0, -14)])
				draw_colored_polygon(spine, accent)
		"halo":
			var center := base + Vector2(0, -body_height * 0.72)
			var halo := PackedVector2Array([
				center + Vector2(-18, -7), center + Vector2(18, -7),
				center + Vector2(18, 7), center + Vector2(-18, 7), center + Vector2(-18, -7),
			])
			draw_polyline(halo, accent, 4.0)
		"tail":
			var root := base - Vector2(facing_sign * body_width * 0.46, -body_height * 0.12)
			var joint := root - Vector2(facing_sign * 18.0, 12.0)
			var tip := joint + Vector2(facing_sign * 8.0, 18.0)
			draw_line(root, joint, outline, 7.0)
			draw_line(joint, tip, accent, 5.0)
		_:
			var core := base + Vector2(-facing_sign * body_width * 0.28, -body_height * 0.20)
			draw_rect(Rect2(core - Vector2(7, 7), Vector2(14, 14)), outline, true)
			draw_rect(Rect2(core - Vector2(4, 4), Vector2(8, 8)), accent, true)


func _draw_enemy_axis_stance(
	base: Vector2,
	body_width: float,
	body_height: float,
	facing_sign: float,
	stance_family: String,
	outline: Color,
	body_color: Color
) -> void:
	var hip_y := body_height * 0.42
	var left_foot := Vector2(-6, hip_y + 14)
	var right_foot := Vector2(6, hip_y + 14)
	match stance_family:
		"staggered":
			left_foot = Vector2(-8 * facing_sign, hip_y + 9)
			right_foot = Vector2(12 * facing_sign, hip_y + 17)
		"wide":
			left_foot = Vector2(-body_width * 0.46, hip_y + 14)
			right_foot = Vector2(body_width * 0.46, hip_y + 14)
	for foot: Vector2 in [left_foot, right_foot]:
		draw_line(base + Vector2(signf(foot.x) * 5.0, hip_y), base + foot, outline, 8.0)
		draw_line(base + Vector2(signf(foot.x) * 5.0, hip_y), base + foot, body_color, 4.0)
		draw_rect(Rect2(base + foot + Vector2(-5, -2), Vector2(10, 5)), outline, true)


func _draw_enemy_axis_chassis(
	base: Vector2,
	body_width: float,
	body_height: float,
	armor_plate_count: int,
	outline: Color,
	body_color: Color
) -> void:
	draw_rect(Rect2(base - Vector2(body_width * 0.5 + 3.0, body_height * 0.5 + 3.0), Vector2(body_width + 6.0, body_height + 6.0)), outline, true)
	draw_rect(Rect2(base - Vector2(body_width * 0.5, body_height * 0.5), Vector2(body_width, body_height)), body_color, true)
	if armor_plate_count <= 0:
		draw_rect(Rect2(base + Vector2(-4, -body_height * 0.35), Vector2(8, body_height * 0.7)), body_color.lightened(0.22), true)
		return
	var plate_color := body_color.lightened(0.24)
	var plate_width := maxf(5.0, (body_width - 8.0) / float(armor_plate_count))
	for index: int in range(armor_plate_count):
		var x := -body_width * 0.5 + 4.0 + float(index) * plate_width
		draw_rect(Rect2(base + Vector2(x, -body_height * 0.33), Vector2(plate_width - 2.0, body_height * 0.66)), plate_color, true)


func _draw_enemy_axis_sensor(
	base: Vector2,
	body_width: float,
	body_height: float,
	facing_sign: float,
	body_plan: String,
	sensor_family: String,
	outline: Color,
	accent: Color
) -> void:
	var head := base + Vector2(0, -body_height * 0.5 - 9.0)
	var head_size := Vector2(18, 14)
	match body_plan:
		"arachnid":
			head = base + Vector2(facing_sign * body_width * 0.38, -body_height * 0.10)
			head_size = Vector2(12, 10)
		"quadruped":
			head = base + Vector2(facing_sign * body_width * 0.68, -body_height * 0.18)
			head_size = Vector2(16, 12)
		"serpentine":
			head = base + Vector2(facing_sign * body_width * 0.28, -body_height * 0.05)
			head_size = Vector2(14, 12)
		"floating":
			head = base
			head_size = Vector2(14, 14)
		"tracked":
			head = base + Vector2(facing_sign * body_width * 0.22, -body_height * 0.44)
			head_size = Vector2(16, 10)
	draw_rect(Rect2(head - head_size * 0.5 - Vector2(2, 2), head_size + Vector2(4, 4)), outline, true)
	draw_rect(Rect2(head - head_size * 0.5, head_size), Color("cbd5e1"), true)
	match sensor_family:
		"direction_slit":
			draw_rect(Rect2(head + Vector2(-1 if facing_sign > 0.0 else -9, -2), Vector2(10, 4)), accent, true)
		"point_diamond":
			var diamond := PackedVector2Array([
				head + Vector2(0, -6), head + Vector2(6, 0),
				head + Vector2(0, 6), head + Vector2(-6, 0),
			])
			draw_colored_polygon(diamond, accent)
		_:
			var eye_x := 2.0 * facing_sign
			draw_rect(Rect2(head + Vector2(eye_x - 3.0, -3), Vector2(6, 6)), accent, true)


func _draw_enemy_axis_tool(
	base: Vector2,
	body_width: float,
	body_height: float,
	facing_sign: float,
	aim_direction: Vector2,
	phase: String,
	progress: float,
	sprite: Dictionary,
	outline: Color,
	accent: Color
) -> void:
	match str(sprite.get("tool_family", "swing_limb")):
		"ram_prongs":
			_draw_enemy_ram_prongs(base, body_width, facing_sign, phase, progress, outline, accent)
		"barrel":
			_draw_enemy_barrel(base, body_width, body_height, facing_sign, aim_direction, phase, progress, outline, accent)
		"focus_orb":
			_draw_enemy_focus_orb(base, body_width, body_height, facing_sign, phase, progress, outline, accent)
		_:
			_draw_enemy_swing_limb(base, body_width, body_height, facing_sign, phase, progress, str(sprite.get("tool_head", "rod")), outline, accent)


func _draw_enemy_swing_limb(
	base: Vector2,
	body_width: float,
	body_height: float,
	facing_sign: float,
	phase: String,
	progress: float,
	head_style: String,
	outline: Color,
	accent: Color
) -> void:
	var shoulder := base + Vector2(facing_sign * body_width * 0.38, -body_height * 0.24)
	var idle_end := base + Vector2(facing_sign * 25.0, 1.0)
	var endpoint := idle_end
	match phase:
		"telegraph": endpoint = idle_end.lerp(base + Vector2(-facing_sign * 18.0, -28.0), progress)
		"commit": endpoint = base + Vector2(-facing_sign * 18.0, -28.0).lerp(Vector2(facing_sign * 5.0, -32.0), progress)
		"active": endpoint = base + Vector2(facing_sign * 5.0, -32.0).lerp(Vector2(facing_sign * 40.0, 5.0), progress)
		"recovery": endpoint = base + Vector2(facing_sign * 40.0, 5.0).lerp(Vector2(facing_sign * 15.0, 23.0), progress)
	var elbow := shoulder.lerp(endpoint, 0.48) + Vector2(0, 5)
	draw_line(shoulder, elbow, outline, 9.0)
	draw_line(shoulder, elbow, Color("94a3b8"), 5.0)
	draw_line(elbow, endpoint, outline, 8.0)
	draw_line(elbow, endpoint, accent, 4.0)
	_draw_enemy_tool_head(endpoint, (endpoint - elbow).normalized(), head_style, outline, accent)


func _draw_enemy_ram_prongs(
	base: Vector2,
	body_width: float,
	facing_sign: float,
	phase: String,
	progress: float,
	outline: Color,
	accent: Color
) -> void:
	var reach := 18.0
	if phase == "telegraph": reach = lerpf(12.0, 20.0, progress)
	elif phase == "commit": reach = lerpf(20.0, 27.0, progress)
	elif phase == "active": reach = 34.0
	elif phase == "recovery": reach = lerpf(28.0, 12.0, progress)
	var front_x := facing_sign * body_width * 0.5
	for y: float in [-10.0, 10.0]:
		var root := base + Vector2(front_x, y)
		var tip := root + Vector2(facing_sign * reach, 0)
		var prong := PackedVector2Array([
			root + Vector2(0, -6), tip, root + Vector2(0, 6),
		])
		draw_colored_polygon(prong, outline)
		var inset := PackedVector2Array([
			root + Vector2(facing_sign * 3.0, -3), tip - Vector2(facing_sign * 4.0, 0),
			root + Vector2(facing_sign * 3.0, 3),
		])
		draw_colored_polygon(inset, accent)
	if phase == "active":
		for offset: float in [8.0, 18.0, 28.0]:
			draw_rect(Rect2(base + Vector2(-facing_sign * (body_width * 0.5 + offset), -8), Vector2(6, 6)), accent, true)


func _draw_enemy_barrel(
	base: Vector2,
	body_width: float,
	body_height: float,
	facing_sign: float,
	aim_direction: Vector2,
	phase: String,
	progress: float,
	outline: Color,
	accent: Color
) -> void:
	var direction := aim_direction.normalized()
	if direction.is_zero_approx():
		direction = Vector2(facing_sign, 0)
	var shoulder := base + Vector2(facing_sign * body_width * 0.34, -body_height * 0.20)
	var recoil := lerpf(8.0, 2.0, progress) if phase == "active" else 0.0
	var center := shoulder + direction * (19.0 - recoil)
	draw_colored_polygon(_oriented_box(center, direction, 23.0, 8.0), outline)
	draw_colored_polygon(_oriented_box(center, direction, 20.0, 5.0), accent)
	var muzzle := center + direction * 24.0
	draw_colored_polygon(_oriented_box(muzzle, direction, 4.0, 10.0), outline)
	var stock := shoulder - direction * 10.0
	draw_colored_polygon(_oriented_box(stock, direction, 9.0, 7.0), Color("475569"))
	if phase == "active":
		var flash := PackedVector2Array([
			muzzle + direction * 18.0,
			muzzle + direction.orthogonal() * 8.0,
			muzzle - direction.orthogonal() * 8.0,
		])
		draw_colored_polygon(flash, Color("fde047"))


func _draw_enemy_focus_orb(
	base: Vector2,
	body_width: float,
	body_height: float,
	facing_sign: float,
	phase: String,
	progress: float,
	outline: Color,
	accent: Color
) -> void:
	var shoulder := base + Vector2(facing_sign * body_width * 0.36, -body_height * 0.18)
	var idle_point := base + Vector2(facing_sign * 22.0, -8.0)
	var raised_point := base + Vector2(facing_sign * 18.0, -35.0)
	var orb := idle_point
	if phase == "telegraph": orb = idle_point.lerp(raised_point, progress)
	elif phase in ["commit", "active"]: orb = raised_point
	elif phase == "recovery": orb = raised_point.lerp(base + Vector2(facing_sign * 14.0, 18.0), progress)
	draw_line(shoulder, orb, outline, 9.0)
	draw_line(shoulder, orb, Color("94a3b8"), 5.0)
	draw_rect(Rect2(orb - Vector2(9, 9), Vector2(18, 18)), outline, true)
	var diamond := PackedVector2Array([
		orb + Vector2(0, -7), orb + Vector2(7, 0),
		orb + Vector2(0, 7), orb + Vector2(-7, 0),
	])
	draw_colored_polygon(diamond, accent)
	if phase in ["commit", "active"]:
		draw_line(orb + Vector2(0, -17), orb + Vector2(0, -10), accent, 4.0)
		draw_line(orb + Vector2(0, 10), orb + Vector2(0, 17), accent, 4.0)
		draw_line(orb + Vector2(-17, 0), orb + Vector2(-10, 0), accent, 4.0)
		draw_line(orb + Vector2(10, 0), orb + Vector2(17, 0), accent, 4.0)


func _draw_enemy_tool_head(point: Vector2, direction: Vector2, style: String, outline: Color, accent: Color) -> void:
	var forward := direction.normalized()
	if forward.is_zero_approx():
		forward = Vector2.RIGHT
	var side := forward.orthogonal()
	match style:
		"blade":
			var blade := PackedVector2Array([
				point + forward * 13.0, point + side * 9.0,
				point - forward * 5.0, point - side * 5.0,
			])
			draw_colored_polygon(blade, outline)
			draw_line(point + side * 5.0, point + forward * 9.0, accent, 4.0)
		"orb":
			draw_rect(Rect2(point - Vector2(8, 8), Vector2(16, 16)), outline, true)
			draw_rect(Rect2(point - Vector2(4, 4), Vector2(8, 8)), accent, true)
		"wedge":
			var wedge := PackedVector2Array([
				point + forward * 12.0, point + side * 10.0,
				point - forward * 7.0 + side * 6.0, point - forward * 7.0 - side * 6.0,
				point - side * 10.0,
			])
			draw_colored_polygon(wedge, outline)
			draw_line(point - side * 6.0, point + side * 6.0, accent, 5.0)
		_:
			draw_colored_polygon(_oriented_box(point, forward, 9.0, 5.0), outline)
			draw_colored_polygon(_oriented_box(point, forward, 6.0, 2.0), accent)


func _oriented_box(center: Vector2, direction: Vector2, half_length: float, half_width: float) -> PackedVector2Array:
	var forward := direction.normalized()
	if forward.is_zero_approx():
		forward = Vector2.RIGHT
	var side := forward.orthogonal()
	return PackedVector2Array([
		center - forward * half_length - side * half_width,
		center + forward * half_length - side * half_width,
		center + forward * half_length + side * half_width,
		center - forward * half_length + side * half_width,
	])


func _snap_enemy_pixel(point: Vector2) -> Vector2:
	return Vector2(snappedf(point.x, 2.0), snappedf(point.y, 2.0))


func _draw_pixel_arc(
	center: Vector2,
	radius: float,
	start_angle: float,
	end_angle: float,
	color: Color,
	width: float,
	segments: int = 24
) -> void:
	var arc_length := absf(end_angle - start_angle) * radius
	var safe_segments := clampi(maxi(segments, ceili(arc_length / 3.0)), 4, 256)
	var block_size := maxf(4.0, snappedf(width, 2.0))
	var previous := Vector2(INF, INF)
	for index: int in range(safe_segments + 1):
		var amount := float(index) / float(safe_segments)
		var angle := lerpf(start_angle, end_angle, amount)
		var point := Vector2(snappedf(center.x + cos(angle) * radius, 4.0), snappedf(center.y + sin(angle) * radius, 4.0))
		if point == previous:
			continue
		previous = point
		draw_rect(Rect2(point - Vector2.ONE * block_size * 0.5, Vector2.ONE * block_size), color, true)


func _draw_pixel_disc(center: Vector2, radius: float, color: Color) -> void:
	var snapped_center := Vector2(snappedf(center.x, 4.0), snappedf(center.y, 4.0))
	var rows := ceili(radius / 4.0)
	for row: int in range(-rows, rows + 1):
		var y := float(row * 4)
		var half_width := sqrt(maxf(0.0, radius * radius - y * y))
		half_width = snappedf(half_width, 4.0)
		draw_rect(Rect2(snapped_center + Vector2(-half_width, y - 2.0), Vector2(half_width * 2.0, 4.0)), color, true)


func _draw_enemy_attack_preview(enemy: Dictionary) -> void:
	var attack_runtime: Variant = enemy.get("attack_runtime", null)
	if attack_runtime == null:
		return
	_draw_enemy_defense_preview(enemy, attack_runtime)
	if attack_runtime.current_attack.is_empty():
		return
	var visual: Dictionary = ENEMY_ATTACK_VISUAL.compile(attack_runtime.current_attack)
	if not bool(visual.get("ok", false)):
		return
	var phase := str(attack_runtime.phase)
	var color := Color(str(visual.get("primary_color", "fb7185")))
	var pulse_hz := float(visual.get("pulse_hz", 3.0))
	var pulse := 0.5 + 0.5 * sin(float(attack_runtime.phase_elapsed) * TAU * pulse_hz)
	color.a = 0.48 + pulse * 0.26
	var origin: Vector2 = Vector2(enemy["pos"])
	if phase == "recovery":
		_draw_enemy_attack_recovery(origin, visual, color)
		return
	if phase not in ["telegraph", "commit", "active"]:
		return
	if phase == "commit":
		color.a = 0.84
	elif phase == "active":
		color.a = 0.96
	var region := attack_runtime.current_attack.get("hit_region", {}) as Dictionary
	var attack_motion := attack_runtime.current_attack.get("attack_motion", {}) as Dictionary
	var direction: Vector2 = Vector2(attack_runtime.locked_direction).normalized()
	if direction.is_zero_approx():
		direction = Vector2(float(enemy.get("facing", -1.0)), 0.0)
	var shape_origin := origin
	if str(region.get("origin_mode", "attacker")) == "locked_point":
		shape_origin = Vector2(attack_runtime.locked_point)
	_draw_attack_hit_region(shape_origin, direction, region, color)
	var marker_origin := shape_origin if str(visual.get("marker_family", "")) == "concentric_target" else origin
	_draw_attack_delivery_marker(marker_origin, direction, region, attack_motion, visual, color)
	_draw_attack_lock_marker(origin, direction, region, attack_runtime, visual, color)
	_draw_attack_stability_marker(origin, phase, visual, color)


func _draw_enemy_defense_preview(enemy: Dictionary, attack_runtime: Variant) -> void:
	var origin := Vector2(enemy.get("pos", Vector2.ZERO))
	if int(attack_runtime.barrier_charges_remaining) > 0:
		_draw_pixel_arc(origin, 48.0, 0.0, TAU, Color("67e8f9"), 5.0, 28)
		_draw_pixel_arc(origin, 40.0, 0.0, TAU, Color(0.40, 0.91, 0.96, 0.48), 3.0, 24)
	var defense := attack_runtime.current_attack.get("defense", {}) as Dictionary
	if str(defense.get("mode", "none")) == "none" or str(attack_runtime.phase) not in defense.get("guarded_phases", []):
		return
	var direction := Vector2(attack_runtime.locked_direction).normalized()
	if direction.is_zero_approx():
		direction = Vector2(float(enemy.get("facing", -1.0)), 0.0)
	var half_arc := deg_to_rad(float(defense.get("guard_arc_degrees", 0.0)) * 0.5)
	var angle := direction.angle()
	_draw_pixel_arc(origin, 44.0, angle - half_arc, angle + half_arc, Color("facc15"), 7.0, 20)


func _draw_attack_hit_region(origin: Vector2, direction: Vector2, region: Dictionary, color: Color) -> void:
	match str(region.get("shape", "capsule")):
		"arc":
			var half_arc := deg_to_rad(float(region.get("arc_degrees", 0.0)) * 0.5)
			var angle := direction.angle()
			_draw_pixel_arc(origin, float(region.get("radius_pixels", 0.0)), angle - half_arc, angle + half_arc, color, 4.0, 20)
		"circle":
			var impact_radius := float(region.get("radius_pixels", 0.0))
			var fill := color
			fill.a *= 0.16
			_draw_pixel_disc(origin, impact_radius, fill)
			_draw_pixel_arc(origin, impact_radius, 0.0, TAU, color, 4.0, 28)
		"strip", "capsule":
			var length := float(region.get("length_pixels", 0.0))
			var side: Vector2 = direction.orthogonal() * float(region.get("width_pixels", 0.0)) * 0.5
			draw_line(origin + side, origin + direction * length + side, color, 3.0)
			draw_line(origin - side, origin + direction * length - side, color, 3.0)
			draw_line(origin + direction * length + side, origin + direction * length - side, color, 3.0)


func _draw_attack_delivery_marker(
	origin: Vector2,
	direction: Vector2,
	region: Dictionary,
	attack_motion: Dictionary,
	visual: Dictionary,
	color: Color
) -> void:
	var side := direction.orthogonal()
	match str(visual.get("marker_family", "body_sweep")):
		"chevron_lane":
			var length := maxf(72.0, float(region.get("length_pixels", 0.0)))
			for amount: float in [0.28, 0.52, 0.76]:
				var center := origin + direction * length * amount
				var tip := center + direction * 10.0
				draw_line(center - direction * 9.0 + side * 9.0, tip, color, 4.0)
				draw_line(center - direction * 9.0 - side * 9.0, tip, color, 4.0)
		"dashed_launch":
			var path_length := minf(
				720.0,
				float(attack_motion.get("travel_speed_pixels_per_second", 0.0))
					* float(attack_motion.get("hazard_lifetime_seconds", 0.0))
			)
			for segment_index: int in range(0, int(path_length), 32):
				var segment_start := origin + direction * float(segment_index)
				var segment_end := origin + direction * minf(path_length, float(segment_index + 18))
				draw_line(segment_start, segment_end, color, 3.0)
			var diamond := PackedVector2Array([
				origin + direction * 11.0,
				origin + side * 9.0,
				origin - direction * 11.0,
				origin - side * 9.0,
				origin + direction * 11.0,
			])
			draw_polyline(diamond, color, 4.0)
		"concentric_target":
			var impact_point := origin
			var radius := float(region.get("radius_pixels", 0.0))
			_draw_pixel_arc(impact_point, radius * 0.58, 0.0, TAU, color, 3.0, 20)
			draw_rect(Rect2(_snap_enemy_pixel(impact_point) - Vector2(5.0, 5.0), Vector2(10.0, 10.0)), color, true)
		_:
			_draw_pixel_arc(origin, 27.0, direction.angle() - 0.8, direction.angle() + 0.8, color, 3.0, 12)


func _draw_attack_lock_marker(
	origin: Vector2,
	direction: Vector2,
	region: Dictionary,
	attack_runtime: Variant,
	visual: Dictionary,
	color: Color
) -> void:
	var side := direction.orthogonal()
	match str(visual.get("lock_marker", "tracking_tether")):
		"direction_gate":
			var gate_distance := maxf(72.0, float(region.get("length_pixels", 0.0)))
			var gate := origin + direction * gate_distance
			draw_line(gate - side * 14.0, gate + side * 14.0, color, 5.0)
			draw_line(gate - side * 14.0, gate - side * 14.0 - direction * 9.0, color, 4.0)
			draw_line(gate + side * 14.0, gate + side * 14.0 - direction * 9.0, color, 4.0)
		"point_brackets":
			var point: Vector2 = Vector2(attack_runtime.locked_point)
			for x_sign: float in [-1.0, 1.0]:
				for y_sign: float in [-1.0, 1.0]:
					var corner := point + Vector2(19.0 * x_sign, 19.0 * y_sign)
					draw_line(corner, corner - Vector2(9.0 * x_sign, 0.0), color, 4.0)
					draw_line(corner, corner - Vector2(0.0, 9.0 * y_sign), color, 4.0)
		_:
			var tracked: Vector2 = Vector2(attack_runtime.tracked_target)
			var tether := color
			tether.a *= 0.48
			draw_dashed_line(origin, tracked, tether, 2.0, 12.0)
			_draw_pixel_arc(tracked, 8.0, 0.0, TAU, color, 3.0, 12)


func _draw_attack_stability_marker(origin: Vector2, phase: String, visual: Dictionary, color: Color) -> void:
	match str(visual.get("stability_marker", "broken_ring")):
		"shield_frame":
			var radius := 34.0
			var frame := PackedVector2Array([
				origin + Vector2(0, -radius),
				origin + Vector2(radius, -radius * 0.45),
				origin + Vector2(radius * 0.78, radius * 0.72),
				origin + Vector2(0, radius),
				origin + Vector2(-radius * 0.78, radius * 0.72),
				origin + Vector2(-radius, -radius * 0.45),
				origin + Vector2(0, -radius),
			])
			draw_polyline(frame, color, 6.0 if phase == "commit" else 3.0)
		"open_ring":
			_draw_pixel_arc(origin, 32.0, -0.15, PI - 0.35, color, 3.0, 14)
			_draw_pixel_arc(origin, 32.0, PI + 0.15, TAU - 0.35, color, 3.0, 14)
		_:
			for start_angle: float in [0.10, 1.70, 3.30, 4.90]:
				_draw_pixel_arc(origin, 31.0, start_angle, start_angle + 0.72, color, 3.0, 6)


func _draw_enemy_attack_recovery(origin: Vector2, visual: Dictionary, color: Color) -> void:
	var count := 1
	match str(visual.get("recovery_marker", "single_bar")):
		"double_bars": count = 2
		"triple_bars": count = 3
	var total_width := float(count - 1) * 12.0
	for index: int in range(count):
		var x := -total_width * 0.5 + float(index) * 12.0
		draw_line(origin + Vector2(x, 30), origin + Vector2(x, 46), color, 5.0)
		draw_rect(Rect2(_snap_enemy_pixel(origin + Vector2(x, 50)) - Vector2(3.0, 3.0), Vector2(6.0, 6.0)), color, true)


func _draw_target_interaction(enemy: Dictionary) -> void:
	var status := str(enemy.get("interaction_status", ""))
	if status.is_empty():
		return
	var position: Vector2 = enemy["pos"]
	var color := Color("facc15")
	if float(enemy.get("pin_seconds", 0.0)) > 0.0:
		color = Color("22d3ee")
		draw_line(position + Vector2(-12, 19), position + Vector2(-12, 37), color, 3.0)
		draw_line(position + Vector2(12, 19), position + Vector2(12, 37), color, 3.0)
	elif float(enemy.get("entangle_seconds", 0.0)) > 0.0:
		color = Color("c084fc")
		_draw_pixel_arc(position, 31.0, 0.0, TAU, color, 3.0, 20)
	elif float(enemy.get("suppression_seconds", 0.0)) > 0.0:
		color = Color("f59e0b")
		for offset: float in [-7.0, 0.0, 7.0]:
			draw_line(position + Vector2(-28, offset), position + Vector2(28, offset), color, 2.0)
	elif status == "ARMOR BROKEN":
		color = Color("fb7185")
	draw_string(ThemeDB.fallback_font, position + Vector2(-48, -48), status, HORIZONTAL_ALIGNMENT_CENTER, 96, 12, color)
