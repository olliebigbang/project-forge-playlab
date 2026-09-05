extends "res://scripts/art_vertical_slice_v1/expedition_arena.gd"
## Complete campaign, with a separate Sunny presentation. No Church draw pass.
const SUNNY_RULES := preload("res://scripts/sunny_expedition/rules.gd")
const STORY := preload("res://scripts/sunny_expedition/story_content.gd")
const MECHANISM_UPGRADES := preload("res://scripts/sunny_expedition/mechanism_upgrade_system.gd")
const ENEMY_VISUAL := preload("res://scripts/sunny_expedition/enemy_visual_adapter.gd")
const SUNNY_BACKGROUNDS := [preload("res://assets/sunny_arena_preview_v1/clearing_generated_v3.png"), preload("res://assets/sunny_expedition_v1/forest_v1.png"), preload("res://assets/sunny_expedition_v1/creek_v1.png")]
const SPRING_MUSHROOM := preload("res://assets/sunny_fantasy_enemies_v1/spring_mushroom.png")
const SPORE_MUSHROOM_WALK := preload("res://assets/sunny_fantasy_enemies_v1/spore_mushroom_walk.png")
const SPORE_MUSHROOM_BREATH := preload("res://assets/sunny_fantasy_enemies_v1/spore_mushroom_breath.png")
const WIND_WISP := preload("res://assets/sunny_fantasy_enemies_v1/wind_wisp.png")
const THORN_GUARDIAN_SHOOT := preload("res://assets/sunny_fantasy_enemies_v1/thorn_guardian_shoot.png")
const THORN_GUARDIAN_HURT := preload("res://assets/sunny_fantasy_enemies_v1/thorn_guardian_hurt.png")
const VIEWPORT_WIDTH := 1280.0
const CAMERA_ANCHOR_X := 470.0
const ROUTE_GATE_MARGIN := 238.0
const UPGRADE_MATERIAL_COST := 3
const SUNNY_FLOOR := Rect2(100, 390, SUNNY_RULES.ROUTE_WORLD_LENGTH - 200.0, 214)
var sprite_images: Dictionary = {}
var sprite_frame_data: Dictionary = {}
var enemy_visual_specs: Dictionary = {}
var collision_sample_cache: Dictionary = {}
var collision_cache_open := false
var background_textures: Array[Texture2D] = []
var mirrored_background_textures: Array[Texture2D] = []
var route_camera_x := 0.0
signal upgrade_requested(choices: Array)
var pending_upgrade_choices: Array[Dictionary] = []
var pending_upgrade_roadpost := -1
var upgrade_history: Array[Dictionary] = []
var taken_upgrade_ids: Array[String] = []
var upgraded_roadposts: Dictionary = {}
var last_upgrade_application: Dictionary = {}
var upgrade_melee_armor_multiplier := 1.0
var upgrade_melee_status_multiplier := 1.0
var upgrade_ranged_knockback_multiplier := 1.0
var upgrade_ranged_status_multiplier := 1.0
var upgrade_state_damage_multiplier := 1.0
var upgrade_state_force_multiplier := 1.0
var upgrade_resolution_channel := ""
var forge_materials := 0
var forge_materials_collected := 0
var forge_materials_spent := 0
var structure_cores: Array[String] = []
var structure_cores_collected := 0
var structure_cores_used := 0
var reward_history: Array[Dictionary] = []
var meta_context: Dictionary = {"rerolls_per_run": 0, "advanced_modules_unlocked": false, "insight": 0}
var upgrade_rerolls_remaining := 0
var upgrade_offer_revision := 0
var upgrade_rerolls_used := 0
var spawned_segment_waves: Dictionary = {}
var journey_mode := STORY.MODE_TRIAL
var story_route := "brook"
var story_route_effects: Dictionary = {}
var journey_carry: Dictionary = {}

func _init() -> void:
	campaign_rules = SUNNY_RULES


func configure_meta_progression(context: Dictionary) -> void:
	meta_context = {
		"rerolls_per_run": clampi(int(context.get("rerolls_per_run", 0)), 0, 2),
		"advanced_modules_unlocked": bool(context.get("advanced_modules_unlocked", false)),
		"insight": maxi(0, int(context.get("insight", 0))),
	}


func configure_journey(mode: String, route_id: String, carry: Dictionary = {}) -> void:
	journey_mode = STORY.normalize_mode(mode)
	story_route = STORY.normalize_route(route_id)
	story_route_effects = STORY.route_combat(story_route) if journey_mode == STORY.MODE_STORY else {}
	journey_carry = carry.duplicate(true) if journey_mode == STORY.MODE_STORY else {}

func _ready() -> void:
	super._ready()
	enemy_visual_specs = _build_enemy_visual_specs()
	for texture: Texture2D in SUNNY_BACKGROUNDS:
		var img := texture.get_image()
		# Fixed 2x world grid for backgrounds, nearest only; originals untouched.
		img.resize(640, 360, Image.INTERPOLATE_NEAREST)
		background_textures.append(ImageTexture.create_from_image(img))
		var mirrored := img.duplicate(); mirrored.flip_x()
		mirrored_background_textures.append(ImageTexture.create_from_image(mirrored))
	for sheet: Dictionary in [
		{"texture": SPRING_MUSHROOM, "size": Vector2i(32, 39), "frames": 7},
		{"texture": SPORE_MUSHROOM_WALK, "size": Vector2i(41, 30), "frames": 10},
		{"texture": SPORE_MUSHROOM_BREATH, "size": Vector2i(63, 37), "frames": 10},
		{"texture": WIND_WISP, "size": Vector2i(64, 64), "frames": 6},
		{"texture": THORN_GUARDIAN_SHOOT, "size": Vector2i(61, 45), "frames": 12},
		{"texture": THORN_GUARDIAN_HURT, "size": Vector2i(61, 45), "frames": 8},
	]:
		var texture: Texture2D = sheet.texture
		sprite_images[texture.get_instance_id()] = texture.get_image()
		for frame_index: int in range(int(sheet.frames)):
			_sprite_frame(texture, Rect2i(Vector2i(frame_index * int(sheet.size.x), 0), Vector2i(sheet.size)))


func _build_enemy_visual_specs() -> Dictionary:
	var all_alpha := {"mode": "all_alpha"}
	return {
		"spring_hopper": {
			"kind": "spring", "zoom": 3.0, "art_forward": 1.0,
			"idle_texture": SPRING_MUSHROOM, "action_texture": SPRING_MUSHROOM,
			"idle_frame_size": Vector2i(32, 39), "action_frame_size": Vector2i(32, 39), "idle_frames": 1, "action_frames": 7,
			"routes": {
				"idle": {"texture": SPRING_MUSHROOM, "frame_size": Vector2i(32, 39), "frame_count": 7, "idle_frames": [0], "speed": 6.0, "collision": all_alpha, "anchors": {"cast": Vector2(16, 18)}},
				"move": {"texture": SPRING_MUSHROOM, "frame_size": Vector2i(32, 39), "frame_count": 7, "idle_frames": [0, 1, 2, 3, 4, 5, 6], "speed": 10.0, "collision": all_alpha, "anchors": {"cast": Vector2(16, 18)}},
				"contact": {"texture": SPRING_MUSHROOM, "frame_size": Vector2i(32, 39), "frame_count": 7, "telegraph_frames": [0], "commit_frames": [0, 1, 2, 3], "active_frames": [3, 4, 5, 6], "recovery_frames": [6, 5, 1, 0], "collision": all_alpha, "anchors": {"cast": Vector2(16, 18)}, "spark_anchor": "cast"},
				"marked_impact": {"texture": SPRING_MUSHROOM, "frame_size": Vector2i(32, 39), "frame_count": 7, "telegraph_frames": [0], "commit_frames": [0, 1, 2, 3], "active_frames": [3, 4, 5, 6], "recovery_frames": [6, 5, 1, 0], "collision": all_alpha, "anchors": {"cast": Vector2(16, 18)}, "spark_anchor": "cast"},
			},
		},
		"spore_raider": {
			"kind": "spore", "zoom": 3.0, "art_forward": 1.0,
			"idle_texture": SPORE_MUSHROOM_WALK, "action_texture": SPORE_MUSHROOM_WALK, "secondary_action_texture": SPORE_MUSHROOM_BREATH,
			"idle_frame_size": Vector2i(41, 30), "action_frame_size": Vector2i(41, 30), "secondary_action_frame_size": Vector2i(63, 37), "idle_frames": 10, "action_frames": 10, "secondary_action_frames": 10,
			"routes": {
				"idle": {"texture": SPORE_MUSHROOM_WALK, "frame_size": Vector2i(41, 30), "frame_count": 10, "idle_frames": [0], "speed": 6.0, "collision": all_alpha, "anchors": {"mouth": Vector2(29, 18)}},
				"move": {"texture": SPORE_MUSHROOM_WALK, "frame_size": Vector2i(41, 30), "frame_count": 10, "idle_frames": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], "speed": 12.0, "collision": all_alpha, "anchors": {"mouth": Vector2(29, 18)}},
				"rush": {"texture": SPORE_MUSHROOM_WALK, "frame_size": Vector2i(41, 30), "frame_count": 10, "telegraph_frames": [0], "commit_frames": [0, 1, 2, 3, 4], "active_frames": [4, 5, 6, 7, 8, 9], "recovery_frames": [9, 7, 3, 0], "collision": all_alpha, "anchors": {"mouth": Vector2(29, 18)}, "spark_anchor": "mouth"},
				"projectile": {"texture": SPORE_MUSHROOM_BREATH, "frame_size": Vector2i(63, 37), "frame_count": 10, "telegraph_frames": [0], "commit_frames": [0, 1, 2, 3, 4, 5], "active_frames": [5, 6, 7, 8, 9], "recovery_frames": [9, 8, 1, 0], "collision": {"mode": "clip_rect", "rect": Rect2i(0, 0, 33, 37)}, "anchors": {"mouth": Vector2(29, 21), "launch": Vector2(31, 21)}, "spark_anchor": "mouth"},
			},
		},
		"wind_wisp": {
			"kind": "wisp", "zoom": 3.0, "art_forward": 1.0,
			"idle_texture": WIND_WISP, "action_texture": WIND_WISP,
			"idle_frame_size": Vector2i(64, 64), "action_frame_size": Vector2i(64, 64), "idle_frames": 6, "action_frames": 6,
			"routes": {
				"idle": {"texture": WIND_WISP, "frame_size": Vector2i(64, 64), "frame_count": 6, "idle_frames": [0, 1, 2, 3, 4, 5], "speed": 6.0, "collision": all_alpha, "anchors": {"cast": Vector2(32, 28)}},
				"move": {"texture": WIND_WISP, "frame_size": Vector2i(64, 64), "frame_count": 6, "idle_frames": [0, 1, 2, 3, 4, 5], "speed": 8.0, "collision": all_alpha, "anchors": {"cast": Vector2(32, 28)}},
				"contact": {"texture": WIND_WISP, "frame_size": Vector2i(64, 64), "frame_count": 6, "telegraph_frames": [0], "commit_frames": [0, 1, 2], "active_frames": [2, 3, 4, 5], "recovery_frames": [5, 4, 2, 0], "collision": all_alpha, "anchors": {"cast": Vector2(32, 26)}, "spark_anchor": "cast", "close_lunge": true},
				"marked_impact": {"texture": WIND_WISP, "frame_size": Vector2i(64, 64), "frame_count": 6, "telegraph_frames": [0], "commit_frames": [0, 1, 2, 3], "active_frames": [3, 4, 5], "recovery_frames": [5, 4, 2, 0], "collision": all_alpha, "anchors": {"cast": Vector2(32, 24)}, "spark_anchor": "cast", "readable_cast": true},
			},
		},
		"thorn_guardian": {
			"kind": "thorn", "zoom": 3.0, "art_forward": -1.0,
			"idle_texture": THORN_GUARDIAN_SHOOT, "action_texture": THORN_GUARDIAN_SHOOT, "hurt_texture": THORN_GUARDIAN_HURT,
			"idle_frame_size": Vector2i(61, 45), "action_frame_size": Vector2i(61, 45), "hurt_frame_size": Vector2i(61, 45), "idle_frames": 1, "action_frames": 12, "hurt_frames": 8,
			"routes": {
				"idle": {"texture": THORN_GUARDIAN_SHOOT, "frame_size": Vector2i(61, 45), "frame_count": 12, "idle_frames": [0], "speed": 6.0, "collision": {"mode": "largest_component"}, "anchors": {"mouth": Vector2(18, 25)}},
				"move": {"texture": THORN_GUARDIAN_SHOOT, "frame_size": Vector2i(61, 45), "frame_count": 12, "idle_frames": [0, 1, 2, 3], "speed": 7.0, "collision": {"mode": "largest_component"}, "anchors": {"mouth": Vector2(18, 25)}},
				"contact": {"texture": THORN_GUARDIAN_HURT, "frame_size": Vector2i(61, 45), "frame_count": 8, "telegraph_frames": [0], "commit_frames": [0, 1, 2, 3], "active_frames": [3, 4, 5, 6, 7], "recovery_frames": [7, 6, 2, 0], "collision": all_alpha, "anchors": {"mouth": Vector2(18, 24)}, "spark_anchor": "mouth", "close_lunge": true},
				"projectile": {"texture": THORN_GUARDIAN_SHOOT, "frame_size": Vector2i(61, 45), "frame_count": 12, "telegraph_frames": [0], "commit_frames": [0, 1, 2, 3, 4, 5], "active_frames": [5, 6, 7, 8, 9, 10, 11], "recovery_frames": [11, 8, 3, 0], "collision": {"mode": "largest_component"}, "anchors": {"mouth": Vector2(18, 25), "launch": Vector2(15, 25)}, "spark_anchor": "mouth"},
				"hurt": {"texture": THORN_GUARDIAN_HURT, "frame_size": Vector2i(61, 45), "frame_count": 8, "idle_frames": [0, 1, 2, 3, 4, 5, 6, 7], "speed": 12.0, "collision": all_alpha, "anchors": {"mouth": Vector2(18, 24)}},
			},
		},
	}

func _clamp_to_floor(point: Vector2) -> Vector2:
	return point.clamp(SUNNY_FLOOR.position, SUNNY_FLOOR.end)


func _world_bounds() -> Rect2:
	# Keep the original vertical rules while expanding only the route width.
	return Rect2(34, 116, SUNNY_RULES.ROUTE_WORLD_LENGTH - 68.0, 568)

func _enemy_ground_draw_offset() -> Vector2:
	return FEET_OFFSET

func _draw_enemy_attack_preview(enemy: Dictionary) -> void:
	var runtime: Variant = enemy.get("attack_runtime")
	# Ground danger is measured against ground roots, so draw it at the feet.
	# Launched projectiles stay at body height and retain their actual flight line.
	var ground: bool = runtime != null and runtime.current_delivery() != "projectile" and runtime.phase != "recovery"
	if ground: draw_set_transform(FEET_OFFSET)
	super._draw_enemy_attack_preview(enemy)
	if ground: draw_set_transform(Vector2.ZERO)
	_draw_enemy_modifier_attack_preview(enemy, runtime)


func _draw_enemy_modifier_attack_preview(enemy: Dictionary, runtime: Variant) -> void:
	if runtime == null:
		return
	var family := ENEMY_VISUAL.modifier_family({"modifier_contract": runtime.compiled_modifiers})
	var skin := ENEMY_VISUAL.modifier_skin(family)
	if skin.is_empty():
		return
	var accent := Color(skin.get("accent", Color.WHITE))
	# Residue champions announce that the SAME red attack outline will remain
	# dangerous. The green broken pips are an annotation of the compiled region,
	# not a second, larger hidden hitbox.
	if family == "residue" and str(runtime.phase) in ["telegraph", "commit"]:
		var region := runtime.current_attack.get("hit_region", {}) as Dictionary
		var delivery: String = str(runtime.current_delivery())
		var origin := Vector2(enemy.get("pos", Vector2.ZERO))
		if str(region.get("origin_mode", "attacker")) == "locked_point":
			origin = Vector2(runtime.locked_point)
		if delivery != "projectile": origin += FEET_OFFSET
		var direction := Vector2(runtime.locked_direction).normalized()
		if direction.is_zero_approx(): direction = Vector2(float(enemy.get("facing", -1.0)), 0.0)
		accent.a = 0.72
		_draw_attack_hit_region(origin, direction, region, accent)
		for pip: int in range(3):
			draw_rect(Rect2((origin + Vector2(-10 + pip * 10, 10)).round(), Vector2(4, 4)), accent)
	# Echoes are scheduled from the authoritative activation event. Keep the
	# exact frozen origin/direction/region visible for the whole delay so the
	# repeat is a dodge test, not an invisible second hit.
	if family == "echo":
		for scheduled: Dictionary in runtime.scheduled_echoes:
			var event := scheduled.get("activation_event", {}) as Dictionary
			var delivery := str(event.get("delivery", ""))
			var origin := Vector2(event.get("origin", enemy.get("pos", Vector2.ZERO))) - Vector2(route_camera_x, 0.0)
			var direction := Vector2(event.get("locked_direction", Vector2.RIGHT)).normalized()
			if direction.is_zero_approx(): direction = Vector2.RIGHT
			accent.a = 0.58 + 0.20 * (0.5 + 0.5 * sin(stage_elapsed * TAU * 5.0))
			if delivery == "projectile":
				var length := minf(720.0, Vector2(event.get("velocity", Vector2.ZERO)).length() * float(event.get("hazard_lifetime_seconds", 0.0)))
				for segment: int in range(0, int(length), 28):
					draw_line(origin + direction * segment, origin + direction * minf(length, segment + 14), accent, 3.0)
			else:
				origin += FEET_OFFSET
				_draw_attack_hit_region(origin, direction, event.get("hit_region", {}) as Dictionary, accent)
			for pip: int in range(3):
				draw_rect(Rect2((origin + Vector2(-10 + pip * 10, -20)).round(), Vector2(4, 4)), accent)

func begin_chapter(index: int, seed_value: int, weapon: Dictionary, health: float, remaining_supplies: int) -> Dictionary:
	route_camera_x = 0.0
	spawned_segment_waves.clear()
	pending_upgrade_choices.clear()
	pending_upgrade_roadpost = -1
	upgrade_history.clear()
	taken_upgrade_ids.clear()
	upgraded_roadposts.clear()
	last_upgrade_application.clear()
	upgrade_melee_armor_multiplier = 1.0
	upgrade_melee_status_multiplier = 1.0
	upgrade_ranged_knockback_multiplier = 1.0
	upgrade_ranged_status_multiplier = 1.0
	upgrade_state_damage_multiplier = 1.0
	upgrade_state_force_multiplier = 1.0
	upgrade_resolution_channel = ""
	forge_materials = 0
	forge_materials_collected = 0
	forge_materials_spent = 0
	structure_cores.clear()
	structure_cores_collected = 0
	structure_cores_used = 0
	reward_history.clear()
	upgrade_rerolls_remaining = int(meta_context.get("rerolls_per_run", 0))
	upgrade_offer_revision = 0
	upgrade_rerolls_used = 0
	var result := super.begin_chapter(index, seed_value, weapon, health, remaining_supplies)
	if not result.get("ok", false):
		return result
	if journey_mode == STORY.MODE_STORY:
		# The base adapter schedules the two-enemy trial opening. A story leg owns
		# a larger finite budget, so replace only the pending warnings before any
		# enemy has entered the world.
		spawn_tells.clear()
		spawn_ordinal = 0
		for opening_index: int in range(SUNNY_RULES.story_segment_spawns(chapter, 0)):
			announce_spawn(false)
			spawn_tells.back().remaining += opening_index * 0.55
	# The parent schedules the first segment through initial_spawns(). Later
	# segments are armed only when the player approaches their roadpost.
	spawned_segment_waves[0] = true
	metrics["upgrades"] = []
	metrics["forge_materials_collected"] = 0
	metrics["forge_materials_spent"] = 0
	metrics["structure_cores_collected"] = 0
	metrics["structure_cores_used"] = 0
	metrics["upgrade_rerolls_used"] = 0
	metrics["reward_history"] = []
	stage_name = "sunny_story_expedition" if journey_mode == STORY.MODE_STORY else "sunny_trial_route"
	if journey_mode == STORY.MODE_STORY:
		_restore_journey_carry()
		var starting_materials := maxi(0, int(story_route_effects.get("starting_materials", 0)))
		if starting_materials > 0:
			_grant_materials(starting_materials, "route_supply", {})
		var starting_core := str(story_route_effects.get("starting_core", ""))
		if not starting_core.is_empty():
			structure_cores.append(starting_core)
			structure_cores_collected += 1
			reward_history.append({"kind": "structure_core", "family": starting_core, "source": "route_supply", "enemy_id": -1, "roadpost": 1})
			_sync_reward_metrics()
	objective_notice = "%s · 沿道路向右推进" % STORY.route_label(story_route) if journey_mode == STORY.MODE_STORY else "沿道路向右推进，到达金色路标后守住这一段"
	return result


func _restore_journey_carry() -> void:
	forge_materials = clampi(int(journey_carry.get("forge_materials", 0)), 0, 99)
	structure_cores.clear()
	for core: Variant in journey_carry.get("structure_cores", []) as Array:
		if str(core) in ["impact", "control", "tempo", "stability"] and structure_cores.size() < 8:
			structure_cores.append(str(core))
	upgrade_history.clear()
	taken_upgrade_ids.clear()
	for stored: Variant in journey_carry.get("upgrades", []) as Array:
		if not stored is Dictionary or upgrade_history.size() >= 9:
			continue
		var record := (stored as Dictionary).duplicate(true)
		var effects: Dictionary = record.get("effects", {})
		if effects.is_empty():
			continue
		_apply_upgrade_effects(effects)
		upgrade_history.append(record)
		var upgrade_id := str(record.get("id", ""))
		if not upgrade_id.is_empty() and upgrade_id not in taken_upgrade_ids:
			taken_upgrade_ids.append(upgrade_id)
	metrics["upgrades"] = upgrade_history.duplicate(true)
	_sync_reward_metrics()


func export_journey_carry() -> Dictionary:
	return {
		"forge_materials": clampi(forge_materials, 0, 99),
		"structure_cores": structure_cores.slice(0, 8),
		"upgrades": upgrade_history.slice(0, 9).duplicate(true),
	}

func _process(delta: float) -> void:
	collision_sample_cache.clear()
	collision_cache_open = true
	_ensure_current_segment_wave()
	var arrivals_pending := phase == "seal" and not spawn_tells.is_empty()
	var progress_before_arrivals := seal_progress
	super._process(delta)
	# Spawn warnings are part of the encounter, not free capture time. Let the
	# silhouettes arrive before the short eight-second roadpost hold begins.
	if arrivals_pending and phase == "seal":
		seal_progress = progress_before_arrivals
	collision_cache_open = false
	_apply_forward_gate()
	_update_route_camera(delta)
	_update_route_notice()
	if objective_notice.contains("阵眼"): objective_notice = objective_notice.replace("阵眼", "路标")


func _ensure_current_segment_wave() -> void:
	if phase != "seal" or spawned_segment_waves.has(seal_index):
		return
	# Wake a segment shortly before it enters view. This keeps the route moving
	# while preventing enemies from fighting across multiple screens.
	if absf(player_position.x - seal_position.x) > 700.0:
		return
	spawned_segment_waves[seal_index] = true
	var count := SUNNY_RULES.story_segment_spawns(chapter, seal_index) if journey_mode == STORY.MODE_STORY else SUNNY_RULES.segment_spawns(seal_index)
	for local_index: int in range(count):
		announce_spawn(false)
		spawn_tells.back().remaining += local_index * 0.55


func _apply_forward_gate() -> void:
	if phase != "seal": return
	# A locked road segment has a real world-space boundary. Lunges and dodges
	# cannot skip the encounter while enemies or roadpost work remain.
	player_position.x = minf(player_position.x, seal_position.x + ROUTE_GATE_MARGIN)


func _update_route_camera(delta: float) -> void:
	var maximum := maxf(0.0, SUNNY_RULES.ROUTE_WORLD_LENGTH - VIEWPORT_WIDTH)
	var target := clampf(player_position.x - CAMERA_ANCHOR_X, 0.0, maximum)
	route_camera_x = move_toward(route_camera_x, target, 560.0 * delta)
	# Teleports used by save recovery and test playback must still appear in the
	# same frame instead of leaving the player outside the visible viewport.
	if player_position.x - route_camera_x > 1080.0:
		route_camera_x = minf(maximum, player_position.x - 1080.0)
	elif player_position.x - route_camera_x < 180.0:
		route_camera_x = maxf(0.0, player_position.x - 180.0)


func _update_route_notice() -> void:
	if phase != "seal": return
	# Preserve the only immediate confirmation that a build choice took effect.
	# Navigation copy resumes when the short feedback window expires.
	if notice_time > 0.0 and (objective_notice.begins_with("获得「") or objective_notice.begins_with("候选已重铸")):
		return
	if seal_progress >= SUNNY_RULES.SEAL_SECONDS and not _objective_completion_allowed():
		objective_notice = "路标已经稳固 · 清除这一段剩余怪物，路障才会打开"
		notice_time = maxf(notice_time, 0.25)
	elif player_position.x < seal_position.x - SUNNY_RULES.SEAL_RADIUS:
		objective_notice = "继续向右推进 · 前方路标还有 %d 米" % maxi(0, roundi((seal_position.x - player_position.x) / 10.0))
		notice_time = maxf(notice_time, 0.25)


func _objective_completion_allowed() -> bool:
	if not enemies.is_empty() or not spawn_tells.is_empty():
		return false
	# The fourth roadpost leads straight into the guardian. The first three
	# pause here so the next segment genuinely uses the player's chosen build.
	if seal_index >= SUNNY_RULES.SEAL_COUNT - 1:
		return true
	if upgraded_roadposts.has(seal_index):
		return true
	if pending_upgrade_roadpost != seal_index:
		_ensure_upgrade_material_budget()
		upgrade_offer_revision = 0
		pending_upgrade_choices = _build_pending_upgrade_choices()
		if pending_upgrade_choices.size() != MECHANISM_UPGRADES.CHOICE_COUNT:
			return false
		pending_upgrade_roadpost = seal_index
		objective_notice = "路标已经稳固 · 选择一项机制强化后继续前进"
		notice_time = 999.0
		upgrade_requested.emit(pending_upgrade_choices.duplicate(true))
	return false


func _build_pending_upgrade_choices() -> Array[Dictionary]:
	# Revision changes the deterministic offer without touching the run/map seed.
	# This keeps replays stable and makes a reroll a real, auditable resource.
	return MECHANISM_UPGRADES.build_choices(
		blueprint,
		ranged_runtime_profile,
		seal_index,
		run_seed + upgrade_offer_revision * 7919,
		taken_upgrade_ids,
		_reward_context(),
		meta_context
	)


func reroll_pending_upgrade() -> Dictionary:
	if pending_upgrade_roadpost != seal_index or pending_upgrade_choices.size() != MECHANISM_UPGRADES.CHOICE_COUNT:
		return {"ok": false, "error": "NO_PENDING_MECHANISM_UPGRADE"}
	if upgrade_rerolls_remaining <= 0:
		return {"ok": false, "error": "NO_UPGRADE_REROLLS_REMAINING"}
	var previous_ids: Array[String] = []
	for option: Dictionary in pending_upgrade_choices:
		previous_ids.append(str(option.get("id", "")))
	var replacement: Array[Dictionary] = []
	for _attempt: int in range(8):
		upgrade_offer_revision += 1
		replacement = _build_pending_upgrade_choices()
		var replacement_ids: Array[String] = []
		for option: Dictionary in replacement:
			replacement_ids.append(str(option.get("id", "")))
		if replacement_ids != previous_ids:
			break
	if replacement.size() != MECHANISM_UPGRADES.CHOICE_COUNT:
		return {"ok": false, "error": "UPGRADE_REROLL_BUILD_FAILED"}
	var final_ids: Array[String] = []
	for option: Dictionary in replacement:
		final_ids.append(str(option.get("id", "")))
	if final_ids == previous_ids:
		return {"ok": false, "error": "UPGRADE_REROLL_NO_ALTERNATIVE"}
	pending_upgrade_choices = replacement
	upgrade_rerolls_remaining -= 1
	upgrade_rerolls_used += 1
	_sync_reward_metrics()
	objective_notice = "候选已重铸 · 剩余%d次" % upgrade_rerolls_remaining
	upgrade_requested.emit(pending_upgrade_choices.duplicate(true))
	return {"ok": true, "choices": pending_upgrade_choices.duplicate(true), "remaining": upgrade_rerolls_remaining}


func apply_pending_upgrade(choice_index: int) -> Dictionary:
	if pending_upgrade_roadpost != seal_index or choice_index < 0 or choice_index >= pending_upgrade_choices.size():
		return {"ok": false, "error": "NO_PENDING_MECHANISM_UPGRADE"}
	var option: Dictionary = pending_upgrade_choices[choice_index].duplicate(true)
	var effects: Dictionary = option.get("effects", {})
	if effects.is_empty():
		return {"ok": false, "error": "EMPTY_MECHANISM_UPGRADE"}
	var material_cost := maxi(0, int(option.get("material_cost", UPGRADE_MATERIAL_COST)))
	if forge_materials < material_cost:
		return {"ok": false, "error": "锻材不足：需要%d，当前%d" % [material_cost, forge_materials]}
	var infused_core := str(option.get("core_family", "")) if bool(option.get("core_infused", false)) else ""
	if not infused_core.is_empty() and infused_core not in structure_cores:
		return {"ok": false, "error": "对应结构核心已经不存在"}
	var before := combat_upgrade_snapshot()
	_apply_upgrade_effects(effects)
	var after := combat_upgrade_snapshot()
	if before == after:
		return {"ok": false, "error": "MECHANISM_UPGRADE_ZERO_EFFECT"}
	var materials_before := forge_materials
	forge_materials -= material_cost
	forge_materials_spent += material_cost
	if not infused_core.is_empty():
		structure_cores.erase(infused_core)
		structure_cores_used += 1
	var record := {
		"chapter": chapter + 1,
		"roadpost": seal_index + 1,
		"id": str(option.get("id", "")),
		"title": str(option.get("title", "强化")),
		"category": str(option.get("category", "")),
		"detail": str(option.get("detail", "")),
		"basis": str(option.get("basis", "")),
		"module_family": str(option.get("module_family", "")),
		"material_cost": material_cost,
		"materials_before": materials_before,
		"materials_after": forge_materials,
		"core_consumed": infused_core,
		"meta_unlock": str(option.get("meta_unlock", "")),
		"offer_revision": upgrade_offer_revision,
		"effects": effects.duplicate(true),
	}
	upgrade_history.append(record)
	taken_upgrade_ids.append(str(record.id))
	upgraded_roadposts[seal_index] = true
	metrics["upgrades"] = upgrade_history.duplicate(true)
	_sync_reward_metrics()
	last_upgrade_application = {"before": before, "after": after, "record": record.duplicate(true)}
	pending_upgrade_choices.clear()
	pending_upgrade_roadpost = -1
	objective_notice = "获得「%s」· 剩余锻材%d · 前方路障正在打开" % [str(record.title), forge_materials]
	notice_time = 4.5
	return {"ok": true, "record": record, "before": before, "after": after}


func _reward_context() -> Dictionary:
	return {
		"material_count": forge_materials,
		"material_cost": UPGRADE_MATERIAL_COST,
		"core_family": structure_cores[0] if not structure_cores.is_empty() else "",
		"core_count": structure_cores.size(),
	}


func _ensure_upgrade_material_budget() -> void:
	# Normal play earns more than this from the cleared wave. The recovery floor
	# prevents a route soft-lock if a future hazard or scripted despawn removes an
	# enemy without going through player damage.
	if forge_materials < UPGRADE_MATERIAL_COST:
		_grant_materials(UPGRADE_MATERIAL_COST - forge_materials, "roadpost_salvage", {})


func _grant_materials(amount: int, source: String, enemy: Dictionary) -> void:
	if amount <= 0:
		return
	forge_materials += amount
	forge_materials_collected += amount
	reward_history.append({
		"kind": "forge_material",
		"amount": amount,
		"source": source,
		"enemy_id": int(enemy.get("id", -1)),
		"roadpost": mini(SUNNY_RULES.SEAL_COUNT, seal_index + 1),
	})
	_sync_reward_metrics()


func _register_enemy_reward(enemy: Dictionary) -> void:
	if bool(enemy.get("reward_drop_registered", false)):
		return
	enemy["reward_drop_registered"] = true
	var champion := bool(enemy.get("expedition_champion", false))
	var elite := bool(enemy.get("expedition_elite", false))
	_grant_materials(2 if champion or elite else 1, "elite_enemy" if champion or elite else "ordinary_enemy", enemy)
	var core_family := str(enemy.get("reward_core_family", ""))
	if (champion or elite) and not core_family.is_empty():
		structure_cores.append(core_family)
		structure_cores_collected += 1
		reward_history.append({
			"kind": "structure_core",
			"family": core_family,
			"source": "guardian" if elite else "champion",
			"enemy_id": int(enemy.get("id", -1)),
			"roadpost": mini(SUNNY_RULES.SEAL_COUNT, seal_index + 1),
		})
		objective_notice = "击败精英 · 获得%s · 当前锻材%d" % [MECHANISM_UPGRADES.core_label(core_family), forge_materials]
		notice_time = 4.0
	_sync_reward_metrics()
	metrics_changed.emit(metrics)


func _sync_reward_metrics() -> void:
	metrics["forge_materials_collected"] = forge_materials_collected
	metrics["forge_materials_spent"] = forge_materials_spent
	metrics["structure_cores_collected"] = structure_cores_collected
	metrics["structure_cores_used"] = structure_cores_used
	metrics["upgrade_rerolls_used"] = upgrade_rerolls_used
	metrics["reward_history"] = reward_history.duplicate(true)


func _damage_enemy(enemy: Dictionary, amount: float, hurt_seconds: float = 0.12) -> void:
	var was_alive := float(enemy.get("hp", 0.0)) > 0.0
	super._damage_enemy(enemy, amount, hurt_seconds)
	if was_alive and float(enemy.get("hp", 0.0)) <= 0.0:
		_register_enemy_reward(enemy)


func _update_enemies(delta: float) -> void:
	# Damage-over-time is advanced inside the shared enemy tick and can cross
	# zero without calling _damage_enemy. Retain the dictionary references for
	# one tick so every genuine death still enters the same reward ledger.
	var before_filter: Array = enemies.duplicate()
	super._update_enemies(delta)
	for enemy: Dictionary in before_filter:
		if float(enemy.get("hp", 0.0)) <= 0.0:
			_register_enemy_reward(enemy)


func combat_upgrade_snapshot() -> Dictionary:
	if _uses_firearm_runtime():
		return {
			"damage": snappedf(float(ranged_runtime_profile.get("projectile_damage", 0.0)), 0.001),
			"interval": snappedf(float(ranged_runtime_profile.get("shot_interval_seconds", 0.0)), 0.001),
			"reload": snappedf(float(ranged_runtime_profile.get("reload_seconds", 0.0)), 0.001),
			"magazine": int(ranged_runtime_profile.get("magazine_size", 0)),
			"pierce": int(ranged_runtime_profile.get("pierce_budget", 0)),
			"armor": snappedf(float(ranged_runtime_profile.get("armor_damage_multiplier", 0.0)), 0.001),
			"spread": snappedf(float(ranged_runtime_profile.get("spread_velocity", 0.0)), 0.001),
			"recoil_per_shot": snappedf(float(ranged_runtime_profile.get("muzzle_climb_degrees_per_shot", 0.0)), 0.001),
			"recoil_cap": snappedf(float(ranged_runtime_profile.get("muzzle_climb_cap_degrees", 0.0)), 0.001),
			"firing_move": snappedf(float(ranged_runtime_profile.get("firing_movement_multiplier", 0.0)), 0.001),
			"knockback": snappedf(upgrade_ranged_knockback_multiplier, 0.001),
			"status": snappedf(upgrade_ranged_status_multiplier, 0.001),
		}
	if melee_runtime.profile == null:
		return {}
	var profile: Resource = melee_runtime.profile
	var primitives: Array = profile.combo_recipe.all_primitives()
	return {
		"startup": snappedf(float(profile.startup_seconds), 0.001),
		"active": snappedf(float(profile.active_seconds), 0.001),
		"recovery": snappedf(float(profile.recovery_seconds), 0.001),
		"damage": snappedf(float(primitives[0].damage_multiplier), 0.001),
		"knockback": snappedf(float(primitives[0].knockback_multiplier), 0.001),
		"stagger": snappedf(float(primitives[0].stagger_multiplier), 0.001),
		"root_motion": snappedf(float(primitives[0].root_motion_distance), 0.001),
		"armor": snappedf(upgrade_melee_armor_multiplier, 0.001),
		"status": snappedf(upgrade_melee_status_multiplier, 0.001),
		"state_damage": snappedf(upgrade_state_damage_multiplier, 0.001),
		"state_force": snappedf(upgrade_state_force_multiplier, 0.001),
	}


func _apply_upgrade_effects(effects: Dictionary) -> void:
	if _uses_firearm_runtime():
		_apply_ranged_upgrade(effects)
	else:
		_apply_melee_upgrade(effects)


func _apply_ranged_upgrade(effects: Dictionary) -> void:
	_multiply_runtime_value("projectile_damage", effects.get("ranged_damage_mul", 1.0), 1.0, 250.0)
	_multiply_runtime_value("shot_interval_seconds", effects.get("shot_interval_mul", 1.0), 0.045, 2.0)
	_multiply_runtime_value("reload_seconds", effects.get("reload_mul", 1.0), 0.15, 6.0)
	_multiply_runtime_value("projectile_speed", effects.get("projectile_speed_mul", 1.0), 120.0, 1800.0)
	_multiply_runtime_value("projectile_life_seconds", effects.get("projectile_life_mul", 1.0), 0.3, 5.0)
	_multiply_runtime_value("spread_velocity", effects.get("spread_mul", 1.0), 0.0, 100.0)
	_multiply_runtime_value("pellet_spread_degrees", effects.get("pellet_spread_mul", 1.0), 0.0, 90.0)
	_multiply_runtime_value("pellet_damage_multiplier", effects.get("pellet_damage_mul", 1.0), 0.1, 2.0)
	_multiply_runtime_value("recoil_pixels", effects.get("recoil_mul", 1.0), 0.0, 40.0)
	_multiply_runtime_value("muzzle_climb_degrees_per_shot", effects.get("recoil_mul", 1.0), 0.0, 30.0)
	_multiply_runtime_value("muzzle_climb_cap_degrees", effects.get("recoil_mul", 1.0), 0.0, 30.0)
	_multiply_runtime_value("firing_movement_multiplier", effects.get("firing_move_mul", 1.0), 0.25, 1.35)
	_multiply_runtime_value("armor_damage_multiplier", effects.get("ranged_armor_mul", 1.0), 0.2, 2.5)
	_multiply_runtime_value("hit_stagger_seconds", effects.get("ranged_status_mul", 1.0), 0.04, 1.5)
	var range_multiplier := float(effects.get("falloff_range_mul", 1.0))
	_multiply_runtime_value("damage_falloff_start_pixels", range_multiplier, 80.0, 2400.0)
	_multiply_runtime_value("damage_falloff_end_pixels", range_multiplier, 120.0, 3200.0)
	ranged_runtime_profile["pierce_budget"] = maxi(0, int(ranged_runtime_profile.get("pierce_budget", 0)) + int(effects.get("pierce_add", 0)))
	upgrade_ranged_knockback_multiplier *= float(effects.get("ranged_knockback_mul", 1.0))
	upgrade_ranged_status_multiplier *= float(effects.get("ranged_status_mul", 1.0))
	if effects.has("magazine_mul"):
		var previous := maxi(1, int(ranged_runtime_profile.get("magazine_size", 1)))
		var expanded := maxi(previous + 1, roundi(previous * float(effects.magazine_mul)))
		ranged_runtime_profile["magazine_size"] = expanded
		ammo_in_magazine = mini(expanded, ammo_in_magazine + expanded - previous)


func _multiply_runtime_value(key: String, multiplier_value: Variant, minimum: float, maximum: float) -> void:
	var multiplier := float(multiplier_value)
	if is_equal_approx(multiplier, 1.0) or not ranged_runtime_profile.has(key):
		return
	ranged_runtime_profile[key] = clampf(float(ranged_runtime_profile[key]) * multiplier, minimum, maximum)


func _apply_melee_upgrade(effects: Dictionary) -> void:
	if melee_runtime.profile == null:
		return
	var profile: Resource = melee_runtime.profile
	profile.startup_seconds = clampf(float(profile.startup_seconds) * float(effects.get("startup_mul", 1.0)), 0.045, 0.8)
	profile.active_seconds = clampf(float(profile.active_seconds) * float(effects.get("active_mul", 1.0)), 0.04, 0.5)
	profile.recovery_seconds = clampf(float(profile.recovery_seconds) * float(effects.get("recovery_mul", 1.0)), 0.07, 1.2)
	for primitive: Resource in profile.combo_recipe.all_primitives():
		primitive.damage_multiplier = clampf(float(primitive.damage_multiplier) * float(effects.get("melee_damage_mul", 1.0)), 0.2, 5.0)
		primitive.knockback_multiplier = clampf(float(primitive.knockback_multiplier) * float(effects.get("melee_knockback_mul", 1.0)), 0.2, 5.0)
		primitive.stagger_multiplier = clampf(float(primitive.stagger_multiplier) * float(effects.get("melee_stagger_mul", 1.0)), 0.2, 5.0)
		primitive.root_motion_distance = clampf(float(primitive.root_motion_distance) * float(effects.get("root_motion_mul", 1.0)), 0.0, 60.0)
		primitive.movement_allowed_ratio = clampf(float(primitive.movement_allowed_ratio) * float(effects.get("attack_move_mul", 1.0)), 0.0, 1.0)
	upgrade_melee_armor_multiplier *= float(effects.get("melee_armor_mul", 1.0))
	upgrade_melee_status_multiplier *= float(effects.get("melee_status_mul", 1.0))
	upgrade_state_damage_multiplier *= float(effects.get("state_damage_mul", 1.0))
	upgrade_state_force_multiplier *= float(effects.get("state_force_mul", 1.0))
	if effects.has("active_guard_mul"):
		weapon_strategy_profile["active_guard_damage_multiplier"] = clampf(
			float(weapon_strategy_profile.get("active_guard_damage_multiplier", 1.0)) * float(effects.active_guard_mul),
			0.25,
			1.0
		)


func _resolve_compiled_melee_hits() -> void:
	upgrade_resolution_channel = "melee"
	super._resolve_compiled_melee_hits()
	upgrade_resolution_channel = ""


func _resolve_projectile_hit(projectile: Dictionary, enemy: Dictionary) -> Dictionary:
	upgrade_resolution_channel = "ranged"
	var result := super._resolve_projectile_hit(projectile, enemy)
	upgrade_resolution_channel = ""
	return result


func _apply_target_interaction(enemy: Dictionary, outcome: Dictionary) -> void:
	var modified := outcome.duplicate(true)
	var status_multiplier := upgrade_melee_status_multiplier if upgrade_resolution_channel == "melee" else upgrade_ranged_status_multiplier
	var knockback_multiplier := 1.0 if upgrade_resolution_channel == "melee" else upgrade_ranged_knockback_multiplier
	var armor_multiplier := upgrade_melee_armor_multiplier if upgrade_resolution_channel == "melee" else 1.0
	if modified.get("knockback", Vector2.ZERO) is Vector2:
		modified["knockback"] = Vector2(modified.get("knockback", Vector2.ZERO)) * knockback_multiplier
	for key: String in ["stagger_seconds", "status_seconds", "pin_seconds", "entangle_seconds", "suppression_seconds"]:
		if modified.has(key):
			modified[key] = float(modified[key]) * status_multiplier
	if modified.has("armor_damage"):
		modified["armor_damage"] = float(modified.armor_damage) * armor_multiplier
	super._apply_target_interaction(enemy, modified)


func _melee_axis_damage_multiplier() -> float:
	var result := super._melee_axis_damage_multiplier()
	if melee_runtime.state_power() > 0.0:
		result *= upgrade_state_damage_multiplier
	return result


func _apply_melee_axis_force(enemy: Dictionary, relative: Vector2) -> void:
	var before := Vector2(enemy.get("pos", Vector2.ZERO))
	super._apply_melee_axis_force(enemy, relative)
	var displacement := Vector2(enemy.get("pos", before)) - before
	if displacement.length_squared() > 0.0 and not is_equal_approx(upgrade_state_force_multiplier, 1.0):
		var moved := before + displacement * upgrade_state_force_multiplier
		var target_bounds := _world_bounds().grow(-26.0)
		moved.x = clampf(moved.x, target_bounds.position.x, target_bounds.end.x)
		moved.y = clampf(moved.y, target_bounds.position.y, target_bounds.end.y)
		enemy["pos"] = moved


func _reinforcements_allowed() -> bool:
	# Sunny uses a finite per-segment budget. The base arena's endless timed
	# reinforcement loop is deliberately disabled for the quick-play route.
	return false


func _spawn_enemy_blueprint(profile: Dictionary, position: Vector2) -> void:
	super._spawn_enemy_blueprint(profile, position)
	if enemies.is_empty():
		return
	var enemy: Dictionary = enemies.back()
	enemy["expedition_elite"] = bool(profile.get("expedition_elite", false))
	enemy["expedition_champion"] = bool(profile.get("expedition_champion", false))
	enemy["reward_core_family"] = str(profile.get("reward_core_family", ""))
	enemy["reward_drop_registered"] = false


func announce_spawn(elite: bool) -> void:
	var roster_offset := int(story_route_effects.get("roster_offset", 0)) if journey_mode == STORY.MODE_STORY else 0
	var profile: Dictionary = campaign_rules.make_profile(chapter, spawn_ordinal + roster_offset, run_seed, elite)
	if profile.is_empty(): stop(); expedition_failed.emit(); return
	if journey_mode == STORY.MODE_STORY:
		profile["move_speed"] = float(profile.get("move_speed", 60.0)) * float(story_route_effects.get("enemy_move_mul", 1.0))
		profile["max_health"] = float(profile.get("max_health", 65.0)) * float(story_route_effects.get("enemy_health_mul", 1.0))
		profile["damage_multiplier"] = float(profile.get("damage_multiplier", 1.0)) * float(story_route_effects.get("enemy_damage_mul", 1.0))
	# Reinforcements enter from different horizontal sides but stay in the
	# objective's real contest lane. This makes occupying monsters visibly stop
	# progress and gives both ranged and melee players a reason to clear them.
	var offsets := [Vector2(-245, -14), Vector2(205, 18), Vector2(255, -18), Vector2(-190, 12)]
	var point: Vector2 = _clamp_to_floor(seal_position + offsets[posmod(spawn_ordinal + run_seed, offsets.size())])
	if point.distance_to(player_position) < 190.0:
		point.x = clampf(seal_position.x + (245.0 if point.x <= player_position.x else -245.0), SUNNY_FLOOR.position.x, SUNNY_FLOOR.end.x)
	spawn_tells.append({"profile": profile, "position": point, "remaining": 1.8})
	spawn_ordinal += 1

func enemy_frame_sample(enemy: Dictionary, _attack: Dictionary) -> Dictionary:
	var runtime: Variant = enemy.get("attack_runtime")
	var state := str(runtime.phase) if runtime != null else "idle"
	var ratio := 0.0
	if runtime != null: ratio = _enemy_sprite_phase_progress(runtime.current_attack, state, float(runtime.phase_elapsed))
	var spec := _enemy_visual_spec(str(enemy.get("blueprint_id", "")))
	var kind := str(spec.kind)
	var elite := bool(enemy.get("expedition_elite", false))
	var champion := bool(enemy.get("expedition_champion", false))
	var direction := float(enemy.get("facing", -1.0))
	var delivery := str(runtime.current_delivery()) if runtime != null else ""
	if runtime != null and state != "idle" and absf(Vector2(runtime.locked_direction).x) > 0.01: direction = signf(Vector2(runtime.locked_direction).x)
	var moving := bool(enemy_is_moving.get(enemy.get("id", -1), false))
	var hurt := float(enemy.get("hurt", 0)) > 0 and state not in ["commit", "active"]
	var route := ENEMY_VISUAL.route_for(spec, delivery, moving, hurt)
	var texture: Texture2D = route.get("texture") as Texture2D
	var frame_size: Vector2i = route.get("frame_size", Vector2i(32, 32))
	var frame := ENEMY_VISUAL.phase_frame(route, state, ratio, stage_elapsed)
	var zoom := float(spec.zoom) + (1.0 if elite else (0.45 if champion else 0.0))
	var source := Rect2i(Vector2i(frame * frame_size.x, 0), frame_size)
	var frame_data := _sprite_frame(texture, source, route.get("collision", {}) as Dictionary)
	var img: Image = frame_data.image
	var used: Rect2i = frame_data.used
	var pivot := Vector2(used.position.x + used.size.x * 0.5, used.end.y)
	var offset := Vector2.ZERO
	if state in ["telegraph", "commit"]:
		var cast_lift := 10.0 if bool(route.get("readable_cast", false)) else 0.0
		offset = Vector2(-direction * (6 + roundf(ratio * 6)), -roundf(sin(ratio * PI * 0.5) * cast_lift))
	elif state == "active" and kind == "wisp": offset = Vector2(direction * 13, -18 - roundf(sin(ratio * PI) * 12))
	elif state == "active" and kind == "spring": offset = Vector2(direction * 9, -roundf(sin(ratio * PI) * 18))
	elif state == "active" and bool(route.get("close_lunge", false)): offset = Vector2(direction * (12 + roundf(sin(ratio * PI) * 12)), -roundf(sin(ratio * PI) * 4))
	elif state == "active": offset = Vector2(direction * 10, -roundf(sin(ratio * PI) * 8))
	elif state == "recovery": offset = Vector2(direction * roundf(9 * (1 - ratio)), 0)
	return {"texture": texture, "image": img, "region": source, "pivot": pivot, "zoom": zoom, "frame": frame, "phase": state, "facing": direction, "draw_facing": direction * float(spec.art_forward), "offset": offset, "used": used, "alpha_mask": frame_data.body_alpha, "visual_alpha": frame_data.visual_alpha, "opaque_points": frame_data.body_points, "effect_points": frame_data.effect_points, "elite": elite, "champion": champion, "visual_kind": kind, "delivery": delivery, "anchors": route.get("anchors", {}), "spark_anchor": str(route.get("spark_anchor", "")), "continuous_action_progress": ENEMY_VISUAL.commit_active_progress(runtime.current_attack, state, float(runtime.phase_elapsed)) if runtime != null else 0.0}

func _enemy_visual_spec(blueprint_id: String) -> Dictionary:
	return enemy_visual_specs.get(blueprint_id, enemy_visual_specs.get("spring_hopper", {}))


func _sprite_frame(texture: Texture2D, source: Rect2i, collision_policy: Dictionary = {}) -> Dictionary:
	var key := str([texture.get_instance_id(), source.position, source.size, collision_policy])
	if sprite_frame_data.has(key): return sprite_frame_data[key]
	var img: Image = sprite_images.get(texture.get_instance_id())
	if img == null:
		img = texture.get_image()
		sprite_images[texture.get_instance_id()] = img
	var layers := ENEMY_VISUAL.alpha_layers(img, source, collision_policy)
	var minimum := Vector2i(source.size.x, source.size.y)
	var maximum := Vector2i(-1, -1)
	for point: Vector2 in layers.body_points:
		var pixel := Vector2i(floori(point.x), floori(point.y))
		minimum.x = mini(minimum.x, pixel.x); minimum.y = mini(minimum.y, pixel.y)
		maximum.x = maxi(maximum.x, pixel.x); maximum.y = maxi(maximum.y, pixel.y)
	var used := Rect2i()
	if maximum.x >= minimum.x: used = Rect2i(minimum, maximum - minimum + Vector2i.ONE)
	var result := {"image": img, "used": used, "body_alpha": layers.body_alpha, "visual_alpha": layers.visual_alpha, "body_points": layers.body_points, "effect_points": layers.effect_points}
	sprite_frame_data[key] = result
	return result

func _collision_sample(enemy: Dictionary) -> Dictionary:
	var cache_key := int(enemy.get("id", -1))
	if collision_cache_open and collision_sample_cache.has(cache_key): return collision_sample_cache[cache_key]
	var sample := enemy_frame_sample(enemy, {})
	sample["root"] = (Vector2(enemy.pos) + FEET_OFFSET).round() + Vector2(sample.offset)
	var half_width := float(sample.used.size.x) * float(sample.zoom) * 0.5
	sample["bounds"] = Rect2(Vector2(sample.root) - Vector2(half_width, float(sample.used.size.y) * float(sample.zoom)), Vector2(half_width * 2, float(sample.used.size.y) * float(sample.zoom)))
	if collision_cache_open: collision_sample_cache[cache_key] = sample
	return sample

func _alpha_contact(point: Vector2, radius: float, sample: Dictionary) -> bool:
	if not Rect2(sample.bounds).grow(radius + 2).has_point(point): return false
	for offset: Vector2 in [Vector2.ZERO, Vector2(0, radius), Vector2(0, -radius), Vector2(radius, 0), Vector2(-radius, 0)]:
		var local := (point + offset - Vector2(sample.root)) / float(sample.zoom)
		local.x *= float(sample.draw_facing)
		var pixel := Vector2i((local + Vector2(sample.pivot)).floor())
		var size := Vector2i(sample.region.size)
		if Rect2i(Vector2i.ZERO, size).has_point(pixel) and sample.alpha_mask[pixel.y * size.x + pixel.x] != 0: return true
	return false

func _fire_bullet() -> void:
	var previous_count := projectiles.size()
	super._fire_bullet()
	for index: int in range(previous_count, projectiles.size()):
		var projectile: Dictionary = projectiles[index]
		var velocity := Vector2(projectile.get("vel", Vector2.ZERO))
		if velocity.length_squared() <= 0.001: continue
		# Recoil remains a real trajectory. Preserve the declared horizontal
		# effective range for steep rays: a high-climb support weapon travels the
		# longer diagonal path instead of expiring early only because it entered
		# another lane.
		var horizontal_factor := clampf(absf(velocity.normalized().x), 0.55, 1.0)
		projectile["ballistic_horizontal_factor"] = horizontal_factor
		projectile["recoil_launch_degrees"] = rad_to_deg(velocity.angle())
		if horizontal_factor < 0.999:
			projectile["life"] = float(projectile.get("life", 0.0)) / horizontal_factor
			projectile["damage_falloff_start_pixels"] = float(projectile.get("damage_falloff_start_pixels", 0.0)) / horizontal_factor
			projectile["damage_falloff_end_pixels"] = float(projectile.get("damage_falloff_end_pixels", 0.0)) / horizontal_factor


func _projectile_contacts_enemy(start: Vector2, finish: Vector2, projectile: Dictionary, enemy: Dictionary) -> bool:
	if projectile.has("ground_lane_y"):
		var origin_lane := float(projectile.get("ground_lane_origin_y", projectile.ground_lane_y))
		var current_lane := float(projectile.ground_lane_y)
		if projectile.has("origin"):
			# A flat shot remains in its original beat-em-up lane. A visibly diagonal
			# recoil ray transfers by the same screen-space delta and can hit an enemy
			# standing higher/lower in the field. The original lane remains accepted
			# for a ray crossing the real Alpha of a tall same-lane monster.
			var contact_midpoint := (start + finish) * 0.5
			current_lane = origin_lane + contact_midpoint.y - Vector2(projectile.origin).y
		var enemy_lane := Vector2(enemy.pos).y
		if minf(absf(origin_lane - enemy_lane), absf(current_lane - enemy_lane)) > 30.0: return false
	var sample := _collision_sample(enemy)
	var radius := clampf(float(projectile.get("projectile_radius_pixels", 1)), 1, 8)
	if not Rect2(sample.bounds).grow(radius + 2).intersects(Rect2(start, Vector2.ZERO).expand(finish).grow(0.1)): return false
	var steps := maxi(1, ceili(start.distance_to(finish) / 2))
	for index: int in range(steps + 1):
		if _alpha_contact(start.lerp(finish, float(index) / steps), radius, sample): return true
	return false

func _melee_frame_contains(target: Vector2, target_radius: float = 24.0) -> bool:
	if not melee_runtime.active(): return false
	for enemy: Dictionary in enemies:
		if Vector2(enemy.pos).distance_squared_to(target) > 0.01: continue
		# Sample the current visible body ONCE, not once per chain/contact pixel.
		var sample := _collision_sample(enemy)
		if not melee_frame.has("contact_bounds"):
			var bounds := Rect2()
			var first := true
			for point: Vector2 in melee_frame.get("contacts", PackedVector2Array()):
				if first: bounds = Rect2(point, Vector2.ZERO); first = false
				else: bounds = bounds.expand(point)
			for point: Vector2 in melee_frame.get("field", PackedVector2Array()):
				if first: bounds = Rect2(point, Vector2.ZERO); first = false
				else: bounds = bounds.expand(point)
			melee_frame["contact_bounds"] = bounds.grow(3)
		if not Rect2(melee_frame.contact_bounds).intersects(sample.bounds): return false
		for point: Vector2 in melee_frame.get("contacts", PackedVector2Array()):
			if _alpha_contact(point, 1, sample): return true
		var field: PackedVector2Array = melee_frame.get("field", PackedVector2Array())
		if not field.is_empty():
			for field_point: Vector2 in field:
				if _alpha_contact(field_point, 1.0, sample): return true
			var field_bounds := Rect2(field[0], Vector2.ZERO)
			for field_point: Vector2 in field: field_bounds = field_bounds.expand(field_point)
			for opaque: Vector2 in sample.opaque_points:
				var local := (opaque - Vector2(sample.pivot)) * float(sample.zoom)
				local.x *= float(sample.draw_facing)
				var world := Vector2(sample.root) + local
				if field_bounds.has_point(world) and Geometry2D.is_point_in_polygon(world, field): return true
		return false
	return super._melee_frame_contains(target, target_radius)
func _draw_enemy(enemy: Dictionary) -> void:
	var sample := enemy_frame_sample(enemy, _enemy_sprite_attack(enemy))
	var feet := (Vector2(enemy.pos) + FEET_OFFSET).round()
	var runtime: Variant = enemy.get("attack_runtime")
	# The draw pass needs only two tiny modifier fields. Avoid snapshot(), which
	# deep-copies the complete attack card for every enemy every frame.
	var modifier_snapshot: Dictionary = {
		"modifier_contract": runtime.compiled_modifiers,
		"barrier_charges_remaining": runtime.barrier_charges_remaining,
	} if runtime != null else {}
	var modifier_family := ENEMY_VISUAL.modifier_family(modifier_snapshot)
	var modifier_skin := ENEMY_VISUAL.modifier_skin(modifier_family)
	_draw_unit_pixel_shadow(feet, 36 if sample.elite else (31 if sample.champion else 26))
	_draw_modifier_skin_back(feet, sample, modifier_family, modifier_skin)
	var tint := Color("ffaf87") if float(enemy.get("hurt", 0)) > 0 else Color.WHITE
	if sample.elite: tint *= Color("bbdadd")
	elif sample.champion: tint *= Color(modifier_skin.get("tint", Color("fff0bd")))
	draw_set_transform(feet + Vector2(sample.offset), 0, Vector2(float(sample.draw_facing), 1) * float(sample.zoom))
	draw_texture_rect_region(sample.texture, Rect2(-Vector2(sample.pivot), Vector2(sample.region.size)), Rect2(sample.region), tint)
	draw_set_transform(Vector2.ZERO)
	_draw_modifier_skin_front(feet, sample, modifier_family, modifier_skin, modifier_snapshot)
	var top := feet.y - float(sample.used.size.y) * float(sample.zoom) - 12
	draw_rect(Rect2(Vector2(feet.x - 31, top), Vector2(62, 7)), Color("314b45"))
	draw_rect(Rect2(Vector2(feet.x - 29, top + 2), Vector2(58 * clampf(float(enemy.hp) / float(enemy.max_hp), 0, 1), 3)), Color("f2bc76") if sample.elite or sample.champion else Color("b3d785"))
	if sample.champion or sample.elite:
		var modifier_label := str(modifier_skin.get("label", "机制精英"))
		if modifier_family == "barrier" and int(modifier_snapshot.get("barrier_charges_remaining", 0)) <= 0:
			modifier_label = str(modifier_skin.get("broken_label", "护盾已破"))
		draw_string(preload("res://assets/fonts/NotoSansCJKsc-Regular.otf"), Vector2(feet.x - 42, top - 7), modifier_label, HORIZONTAL_ALIGNMENT_CENTER, 84, 12, Color(modifier_skin.get("dark", Color("8d573c"))))
	if float(enemy.get("interaction_status_time", 0)) > 0:
		var word: String = {"PINNED": "钉住", "ENTANGLED": "缠住", "SUPPRESSED": "压制", "ARMOR BROKEN": "破甲", "GUARD BROKEN": "破盾", "GUARDED": "格挡"}.get(str(enemy.get("interaction_status", "")), "")
		if not str(word).is_empty(): draw_string(preload("res://assets/fonts/NotoSansCJKsc-Regular.otf"), Vector2(feet.x - 30, top - (22 if sample.champion or sample.elite else 8)), word, HORIZONTAL_ALIGNMENT_CENTER, 60, 14, Color("20383b"))
	if sample.phase in ["telegraph", "commit", "active"]:
		# Readable casting/charging sparkle; authoritative warnings still drawn below.
		var anchor_sample := sample.duplicate()
		anchor_sample["root"] = feet + Vector2(sample.offset)
		var anchor_name := str(sample.get("spark_anchor", ""))
		var point := ENEMY_VISUAL.world_anchor(anchor_sample, anchor_name) if not anchor_name.is_empty() else feet + Vector2(float(sample.facing) * 24, -36) + Vector2(sample.offset)
		var color := Color("d26365") if sample.phase != "active" else Color("edf3e9")
		for d: Vector2 in [Vector2(-10, 0), Vector2(0, -12), Vector2(10, 0)]: draw_rect(Rect2((point + d).round(), Vector2(4, 4)), color)


func _draw_modifier_skin_back(feet: Vector2, sample: Dictionary, family: String, skin: Dictionary) -> void:
	if family.is_empty() or skin.is_empty():
		return
	var accent := Color(skin.get("accent", Color.WHITE))
	var dark := Color(skin.get("dark", accent.darkened(0.45)))
	var body_height := clampf(float(sample.used.size.y) * float(sample.zoom), 56.0, 176.0)
	var half_width := clampf(float(sample.used.size.x) * float(sample.zoom) * 0.5, 26.0, 96.0)
	if family == "echo":
		var ghost := accent
		ghost.a = 0.24
		draw_set_transform(feet + Vector2(sample.offset) - Vector2(float(sample.facing) * 10.0, 0.0), 0, Vector2(float(sample.draw_facing), 1) * float(sample.zoom))
		draw_texture_rect_region(sample.texture, Rect2(-Vector2(sample.pivot), Vector2(sample.region.size)), Rect2(sample.region), ghost)
		draw_set_transform(Vector2.ZERO)
	elif family == "residue":
		for side: float in [-1.0, 1.0]:
			var pod := (feet + Vector2(side * half_width * 0.78, -body_height * 0.28)).round()
			draw_rect(Rect2(pod - Vector2(5, 7), Vector2(10, 14)), dark)
			draw_rect(Rect2(pod - Vector2(2, 4), Vector2(5, 8)), accent)
	elif family == "barrier":
		for side: float in [-1.0, 1.0]:
			var plate := (feet + Vector2(side * (half_width + 2.0), -body_height * 0.48)).round()
			draw_rect(Rect2(plate - Vector2(5, 9), Vector2(10, 18)), dark)
			draw_rect(Rect2(plate - Vector2(2, 6), Vector2(5, 12)), accent)


func _draw_modifier_skin_front(feet: Vector2, sample: Dictionary, family: String, skin: Dictionary, snapshot: Dictionary) -> void:
	if family.is_empty() or skin.is_empty():
		return
	var accent := Color(skin.get("accent", Color.WHITE))
	var dark := Color(skin.get("dark", accent.darkened(0.45)))
	var body_height := clampf(float(sample.used.size.y) * float(sample.zoom), 56.0, 176.0)
	var half_width := clampf(float(sample.used.size.x) * float(sample.zoom) * 0.5, 26.0, 96.0)
	match family:
		"echo":
			for offset: Vector2 in [Vector2(-half_width * 0.72, -body_height * 0.72), Vector2(half_width * 0.82, -body_height * 0.46), Vector2(0, -body_height - 8)]:
				var mote := (feet + offset).round()
				draw_rect(Rect2(mote - Vector2(4, 4), Vector2(8, 8)), dark)
				draw_rect(Rect2(mote - Vector2(2, 2), Vector2(4, 4)), accent)
		"residue":
			for offset: Vector2 in [Vector2(-12, -4), Vector2(2, -8), Vector2(16, -3)]:
				var drop := (feet + offset).round()
				draw_rect(Rect2(drop - Vector2(3, 5), Vector2(6, 8)), dark)
				draw_rect(Rect2(drop - Vector2(1, 3), Vector2(3, 4)), accent)
		"barrier":
			if int(snapshot.get("barrier_charges_remaining", 0)) > 0:
				var crown := (feet + Vector2(0, -body_height - 5)).round()
				draw_colored_polygon(PackedVector2Array([crown + Vector2(0, -8), crown + Vector2(7, 0), crown, crown + Vector2(-7, 0)]), dark)
				draw_rect(Rect2(crown - Vector2(2, 5), Vector2(4, 6)), accent)

func _draw() -> void:
	if background_textures.is_empty(): return
	_draw_scrolling_background()
	if blueprint == null or asset == null: return
	var saved_frame := melee_frame
	var saved_frame_key := melee_frame_key
	melee_frame = {}; melee_frame_key = ""
	var screen_offset := Vector2(-route_camera_x, 0)
	_shift_draw_state(screen_offset)
	_draw_sunny_objective()
	var units: Array[Dictionary] = [{"player": true, "y": player_position.y}]
	for enemy: Dictionary in enemies: units.append({"player": false, "y": Vector2(enemy.pos).y, "enemy": enemy})
	units.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.y) < float(b.y))
	for unit: Dictionary in units:
		if unit.player: _draw_player_and_weapon()
		else: _draw_enemy(unit.enemy)
	for enemy: Dictionary in enemies: _draw_enemy_attack_preview(enemy)
	_draw_attacks()
	for spark: Dictionary in sparks:
		for offset: Vector2 in [Vector2(-9, -4), Vector2(7, -9), Vector2(11, 3)]: draw_rect(Rect2((Vector2(spark.position) + offset).round(), Vector2(4, 4)), Color("edf3e9"))
	_shift_draw_state(-screen_offset)
	melee_frame = saved_frame; melee_frame_key = saved_frame_key
	_draw_route_barrier_and_direction()


func _draw_scrolling_background() -> void:
	# One coherent forest panorama alternates with its exact mirror. The touching
	# edge columns are therefore identical: movement stays crisp and continuous
	# without a translucent cross-fade or a generated-image vertical seam.
	var texture_index := clampi(chapter, 0, background_textures.size() - 1) if journey_mode == STORY.MODE_STORY else (1 if background_textures.size() > 1 else 0)
	var panel_count := ceili(SUNNY_RULES.ROUTE_WORLD_LENGTH / VIEWPORT_WIDTH)
	var first_panel := maxi(0, floori(route_camera_x / VIEWPORT_WIDTH) - 1)
	var last_panel := mini(panel_count - 1, first_panel + 2)
	for panel_index: int in range(first_panel, last_panel + 1):
		var texture: Texture2D = mirrored_background_textures[texture_index] if panel_index % 2 == 1 else background_textures[texture_index]
		var screen_x := roundf(float(panel_index) * VIEWPORT_WIDTH - route_camera_x)
		draw_texture_rect(texture, Rect2(screen_x, 0, VIEWPORT_WIDTH, 720), false)


func _shift_draw_state(offset: Vector2) -> void:
	player_position += offset
	seal_position += offset
	for enemy: Dictionary in enemies:
		enemy.pos = Vector2(enemy.pos) + offset
		var runtime: Variant = enemy.get("attack_runtime")
		if runtime != null: runtime.locked_point = Vector2(runtime.locked_point) + offset
	for tell: Dictionary in spawn_tells: tell.position = Vector2(tell.position) + offset
	for projectile: Dictionary in projectiles:
		for key: String in ["pos", "origin"]:
			if projectile.get(key) is Vector2: projectile[key] = Vector2(projectile[key]) + offset
	for hazard: Dictionary in enemy_attack_hazards:
		if hazard.get("pos") is Vector2: hazard.pos = Vector2(hazard.pos) + offset
	if not boomerang.is_empty():
		for key: String in ["pos", "origin"]:
			if boomerang.get(key) is Vector2: boomerang[key] = Vector2(boomerang[key]) + offset
	for spark: Dictionary in sparks: spark.position = Vector2(spark.position) + offset


func _draw_route_barrier_and_direction() -> void:
	if phase == "seal":
		var gate_x := roundf(seal_position.x + ROUTE_GATE_MARGIN - route_camera_x)
		if gate_x > 70 and gate_x < 1230:
			var locked := seal_progress < SUNNY_RULES.SEAL_SECONDS or not _objective_completion_allowed()
			if locked:
				for y: int in range(414, 625, 30): draw_rect(Rect2(gate_x - 3, y, 6, 17), Color("943f4b", 0.82))
				draw_rect(Rect2(gate_x - 34, 394, 68, 23), Color("f9e5b1"))
				draw_rect(Rect2(gate_x - 34, 394, 68, 23), Color("8d573c"), false, 2)
				draw_string(preload("res://assets/fonts/NotoSansCJKsc-Regular.otf"), Vector2(gate_x - 30, 411), "清敌放行", HORIZONTAL_ALIGNMENT_CENTER, 60, 13, Color("59362e"))
	var objective_x := seal_position.x - route_camera_x
	if phase == "seal" and objective_x > 1160.0:
		var arrow := PackedVector2Array([Vector2(1194, 350), Vector2(1232, 370), Vector2(1194, 390), Vector2(1204, 370)])
		draw_colored_polygon(arrow, Color("943f4b"))
		draw_string(preload("res://assets/fonts/NotoSansCJKsc-Regular.otf"), Vector2(1050, 345), "下一路标 · %d米" % maxi(0, roundi((seal_position.x - player_position.x) / 10.0)), HORIZONTAL_ALIGNMENT_RIGHT, 132, 15, Color("59362e"))
	elif phase == "seal" and objective_x < 120.0:
		var arrow := PackedVector2Array([Vector2(86, 350), Vector2(48, 370), Vector2(86, 390), Vector2(76, 370)])
		draw_colored_polygon(arrow, Color("943f4b"))
		draw_string(preload("res://assets/fonts/NotoSansCJKsc-Regular.otf"), Vector2(98, 345), "路标在后方", HORIZONTAL_ALIGNMENT_LEFT, 120, 15, Color("59362e"))

func _draw_sunny_objective() -> void:
	if phase == "seal":
		var center := seal_position + Vector2(0, 42)
		var color := Color("943f4b") if contested else Color("8d573c")
		# The route marker is deliberately small. Both ellipse boundaries exactly
		# match occupancy; no decorative pillar hiding the combatants.
		draw_rect(Rect2(center + Vector2(-3, -55), Vector2(6, 45)), Color("8d573c"))
		draw_rect(Rect2(center + Vector2(-19, -58), Vector2(42, 18)), Color("f9e5b1"))
		draw_rect(Rect2(center + Vector2(-19, -58), Vector2(42, 18)), Color("8d573c"), false, 2)
		for radius: float in [SUNNY_RULES.SEAL_RADIUS, SUNNY_RULES.CONTEST_RADIUS]:
			for i: int in range(64):
				var a := TAU * i / 64.0; var b := TAU * (i + 0.75) / 64.0
				draw_line((center + Vector2(cos(a), sin(a) * 0.36) * radius).round(), (center + Vector2(cos(b), sin(b) * 0.36) * radius).round(), color if radius == SUNNY_RULES.SEAL_RADIUS else Color("bf8c4c"), 2, false)
		draw_rect(Rect2(center + Vector2(-40, -7), Vector2(80, 8)), Color("8d573c"))
		draw_rect(Rect2(center + Vector2(-38, -5), Vector2(76 * seal_progress / SUNNY_RULES.SEAL_SECONDS, 4)), Color("b3d785"))
	for tell: Dictionary in spawn_tells:
		var point := Vector2(tell.position) + FEET_OFFSET
		var diamond := PackedVector2Array([point + Vector2(-24, 0), point + Vector2(0, -10), point + Vector2(24, 0), point + Vector2(0, 10), point + Vector2(-24, 0)])
		draw_polyline(diamond, Color("943f4b"), 3, false)
		draw_string(preload("res://assets/fonts/NotoSansCJKsc-Regular.otf"), point + Vector2(-45, -22), "增援 · %d" % ceili(tell.remaining), HORIZONTAL_ALIGNMENT_CENTER, 90, 15, Color("59362e"))
