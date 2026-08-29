extends SceneTree

const DIRECTOR := preload("res://scripts/enemy_attack/automatic_encounter_director.gd")
const ARENA := preload("res://scripts/systems/gameplay_arena.gd")
const RANGED_AXIS_RESOLVER := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")
const ASSET_LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check("A ranged capability profile clears all three pressure encounters by spacing", _simulate_run(_ranged_entry()))
	_check("A flexible hook capability profile clears the same encounters by closing and controlling", _simulate_run(_control_entry()))
	print("THREE_BATTLE_STRATEGY_PLAYTEST passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _check(label: String, result: Dictionary) -> void:
	if bool(result.get("ok", false)):
		passed += 1
		print("PASS | %s | %s" % [label, JSON.stringify(result.get("summary", {}))])
	else:
		failed += 1
		printerr("FAIL | %s | %s" % [label, JSON.stringify(result)])


func _simulate_run(entry: Dictionary) -> Dictionary:
	if not bool(entry.get("ok", false)):
		return entry
	var director: RefCounted = DIRECTOR.new()
	var configured: Dictionary = director.configure()
	if not bool(configured.get("ok", false)):
		return configured
	var begun: Dictionary = director.begin_run(entry)
	if not bool(begun.get("ok", false)):
		return begun
	var health := 100.0
	var encounter_summaries: Array[Dictionary] = []
	for encounter_number: int in range(1, 4):
		var encounter: Dictionary = director.begin_next_encounter()
		if not bool(encounter.get("ok", false)):
			return encounter
		var profiles: Array[Dictionary] = []
		for raw_profile: Variant in encounter.get("profiles", []):
			profiles.append((raw_profile as Dictionary).duplicate(true))
		var arena := ARENA.new() as GameplayArena
		arena.start_stage(
			str(encounter.get("stage_name", "automatic_playtest")),
			entry.get("blueprint") as WeaponBlueprint,
			entry.get("asset") as WeaponVisualAsset,
			profiles
		)
		arena.player_health = health
		var elapsed := 0.0
		var attack_pulse := 0.0
		while not arena.enemies.is_empty() and elapsed < 38.0 and arena.player_health > 1.0:
			var nearest := _nearest_enemy(arena)
			var movement := _movement_for(arena, nearest)
			arena.set_touch_vector(movement)
			if bool(arena.weapon_strategy_profile.get("firearm", false)):
				arena.set_touch_attack(true)
			else:
				arena.set_touch_attack(false)
				attack_pulse -= 1.0 / 60.0
				if attack_pulse <= 0.0 and _any_melee_target_is_aligned(arena):
					arena.request_touch_attack()
					attack_pulse = 0.78
			if _danger_is_committed(arena) and arena.dodge_timer <= 0.0:
				arena.request_touch_dodge()
			arena._process(1.0 / 60.0)
			elapsed += 1.0 / 60.0
		arena.set_touch_attack(false)
		arena.set_touch_vector(Vector2.ZERO)
		var cleared := arena.enemies.is_empty()
		encounter_summaries.append({
			"encounter": encounter_number,
			"cleared": cleared,
			"seconds": snappedf(elapsed, 0.1),
			"health": snappedf(arena.player_health, 0.1),
			"damage_taken": snappedf(float(arena.metrics.get("damage_taken", 0.0)), 0.1),
			"defeated": int(arena.metrics.get("defeated", 0)),
		})
		if not cleared:
			var remaining: Array[Dictionary] = []
			for enemy: Dictionary in arena.enemies:
				remaining.append({"hp": enemy.get("hp", 0.0), "pos": enemy.get("pos", Vector2.ZERO)})
			var failure := {
				"ok": false,
				"reason": "ENCOUNTER_NOT_CLEARED",
				"summary": encounter_summaries,
				"player_pos": arena.player_position,
				"attacks_used": arena.metrics.get("attacks_used", 0),
				"melee_timer": arena.melee_timer,
				"remaining": remaining,
				"strategy": arena.weapon_strategy_profile,
			}
			arena.free()
			return failure
		health = arena.player_health
		director.complete_active_encounter(arena.metrics)
		arena.free()
	return {
		"ok": health > 1.0 and str(director.snapshot().get("state", "")) == "completed",
		"summary": {"remaining_health": snappedf(health, 0.1), "encounters": encounter_summaries},
	}


func _nearest_enemy(arena: GameplayArena) -> Dictionary:
	var nearest: Dictionary = {}
	var distance := INF
	for enemy: Dictionary in arena.enemies:
		var candidate := arena.player_position.distance_to(Vector2(enemy["pos"]))
		if candidate < distance:
			distance = candidate
			nearest = enemy
	return nearest


func _movement_for(arena: GameplayArena, enemy: Dictionary) -> Vector2:
	if enemy.is_empty():
		return Vector2.ZERO
	var offset := Vector2(enemy["pos"]) - arena.player_position
	if bool(arena.weapon_strategy_profile.get("firearm", false)):
		var vertical := clampf(offset.y / 90.0, -1.0, 1.0)
		var horizontal := 0.0
		if absf(offset.x) < 270.0:
			horizontal = -signf(offset.x)
		elif absf(offset.x) > 410.0:
			horizontal = signf(offset.x)
		return Vector2(horizontal, vertical).limit_length(1.0)
	if absf(offset.y) > 14.0:
		return Vector2(0.0, signf(offset.y))
	if absf(offset.x) <= 4.0:
		return Vector2(-1.0 if arena.player_position.x > 640.0 else 1.0, 0.0)
	if absf(offset.x) > 82.0:
		return Vector2(signf(offset.x), 0.0)
	return Vector2.ZERO


func _any_melee_target_is_aligned(arena: GameplayArena) -> bool:
	for enemy: Dictionary in arena.enemies:
		var offset := Vector2(enemy["pos"]) - arena.player_position
		if absf(offset.y) <= 22.0 and absf(offset.x) > 4.0 and absf(offset.x) <= 112.0:
			return true
	return false


func _danger_is_committed(arena: GameplayArena) -> bool:
	for enemy: Dictionary in arena.enemies:
		var runtime: Variant = enemy.get("attack_runtime", null)
		if runtime != null and str(runtime.phase) == "commit":
			return true
	return false


func _ranged_entry() -> Dictionary:
	var blueprint := WeaponBlueprint.fixed_blueprint("gatling")
	blueprint.affordance = {
		"weapon_domain": "handheld_firearm", "firearm_family": "rifle", "layout": "conventional_rifle",
		"stock_structure": "fixed", "feed_position": "ahead_of_grip", "magazine_shape": "curved",
		"barrel_length": "medium", "upper_profile": "top_rail", "support_mode": "two_hand_shouldered",
		"fire_control": "select_fire_auto", "action_mechanism": "self_loading", "feed_system": "detachable_box",
		"shot_pattern": "single_projectile", "sustained_climb": "controlled", "cadence": "balanced",
		"recoil": "medium", "recoil_recovery": "balanced", "muzzle_climb": "medium", "accuracy": "controlled",
		"impact_force": "medium", "penetration": "strong", "reload": "standard", "effective_range": "long",
		"handling": "balanced", "magazine_capacity": "standard", "confidence": 0.99,
	}
	blueprint.affordance_source = "AUTOMATIC_LEVEL_TEST_AI_FIREARM_AXES"
	var runtime := RANGED_AXIS_RESOLVER.compile(blueprint.affordance, blueprint.affordance_source)
	blueprint.modifiers["ranged_runtime_profile"] = runtime.duplicate(true)
	var image := Image.create(72, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color("4b6478"))
	var asset := WeaponVisualAsset.new()
	asset.source_image = image
	asset.texture = ImageTexture.create_from_image(image)
	asset.canvas_size = image.get_size()
	asset.opaque_bounds = Rect2i(Vector2i.ZERO, image.get_size())
	asset.grip_primary = Vector2(14, 16)
	asset.grip_secondary = Vector2(35, 15)
	asset.muzzle = Vector2(70, 10)
	asset.tip = asset.muzzle
	return {"ok": true, "blueprint": blueprint, "asset": asset, "ranged_runtime_profile": runtime}


func _control_entry() -> Dictionary:
	var loaded: Dictionary = ASSET_LOADER.new().load_soft_weapon_asset("fishing_rod_builtin")
	if not bool(loaded.get("ok", false)):
		return loaded
	return {
		"ok": true,
		"blueprint": loaded.get("blueprint"),
		"asset": loaded.get("asset"),
		"affordance_profile": loaded.get("affordance_profile"),
		"ranged_runtime_profile": {},
	}
