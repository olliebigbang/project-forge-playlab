extends "res://scripts/art_vertical_slice_v1/church_arena.gd"
## Opt-in campaign adapter: original test arenas and their rules stay intact.
const RUN_RULES := preload("res://scripts/art_vertical_slice_v1/expedition_rules.gd")
var campaign_rules: Script = RUN_RULES
signal chapter_finished(summary: Dictionary)
signal expedition_failed
var chapter := 0
var run_seed := 0
var seal_index := 0
var seal_progress := 0.0
var seal_position := Vector2(410, 465)
var phase := "seal"
var contested := false
var on_seal := false
var spawn_clock := 0.0
var spawn_ordinal := 0
var enemy_serial := 0
var chapter_clock := 0.0
var supplies := 2
var objective_notice := ""
var notice_time := 0.0
var spawn_tells: Array[Dictionary] = []
var sparks: Array[Dictionary] = []
var audio_enabled := true
var audio_pool: Array[AudioStreamPlayer] = []
var audio_cursor := 0
var last_sound_at := -5.0
var sound_bank: Dictionary = {}
var seals_defended := 0
var damage_start := 0.0

func begin_chapter(index: int, seed_value: int, weapon: Dictionary, health: float, remaining_supplies: int) -> Dictionary:
	var probe: Dictionary = campaign_rules.make_profile(index, 0, seed_value, index == 2)
	if probe.is_empty(): return {"ok": false, "error": "EXPEDITION_ENEMY_PROFILE_MISSING"}
	chapter = index; run_seed = seed_value; seal_index = 0; seal_progress = 0.0
	phase = "seal"; spawn_clock = 0.5; spawn_ordinal = 0; enemy_serial = 0
	chapter_clock = 0.0; supplies = remaining_supplies; seals_defended = 0
	spawn_tells.clear(); sparks.clear()
	# Supplying a profile avoids spawning training targets; then use announced
	# reinforcements. Neither enemy HP nor damage is modified by the QA driver.
	var initial: Array[Dictionary] = [probe]
	start_stage("church_expedition", weapon.blueprint, weapon.asset, initial)
	enemies.clear()
	player_position = Vector2(580, 505); player_health = clampf(health, 1, 100)
	invulnerable_timer = 0.0; flash_timer = 0.0; facing = 1.0
	seal_position = campaign_rules.seal_position(chapter, seal_index, run_seed)
	var opening_count: int = campaign_rules.initial_spawns(chapter)
	for opening_index: int in range(opening_count):
		announce_spawn(false)
		# Readable stagger: all configured roles arrive within the opening seconds
		# instead of overlapping into an unreadable single silhouette.
		spawn_tells.back().remaining += opening_index * 0.55
	if opening_count > 0: spawn_clock = campaign_rules.spawn_interval(chapter)
	metrics["seal_seconds"] = 0.0; metrics["contested_seconds"] = 0.0
	metrics["heals_used"] = 0; metrics["interruptions"] = 0
	set_process(false)
	objective_notice = "站进金色阵眼，击退靠近的敌人"; notice_time = 4.0
	return {"ok": melee_runtime.error.is_empty(), "error": melee_runtime.error}

func _process(delta: float) -> void:
	if not active: return
	chapter_clock += delta
	notice_time = maxf(0, notice_time - delta)
	for spark: Dictionary in sparks: spark.life -= delta
	sparks = sparks.filter(func(s: Dictionary) -> bool: return s.life > 0)
	_tick_spawns(delta)
	super._process(delta)
	if player_health <= 0:
		stop(); expedition_failed.emit(); return
	if phase == "seal":
		on_seal = objective_contains(player_position, campaign_rules.SEAL_RADIUS)
		contested = false
		for enemy: Dictionary in enemies:
			if float(enemy.hp) > 0 and objective_contains(Vector2(enemy.pos), campaign_rules.CONTEST_RADIUS): contested = true
		if on_seal and not contested:
			seal_progress = minf(campaign_rules.SEAL_SECONDS, seal_progress + delta)
			metrics.seal_seconds = float(metrics.seal_seconds) + delta
		elif contested: metrics.contested_seconds = float(metrics.contested_seconds) + delta
		if seal_progress >= campaign_rules.SEAL_SECONDS and _objective_completion_allowed():
			seal_index += 1; seals_defended += 1; seal_progress = 0.0
			var health_reward: float = campaign_rules.seal_health_reward(chapter)
			var supply_reward: int = campaign_rules.seal_supply_reward(chapter)
			player_health = minf(100.0, player_health + health_reward)
			var supplies_before := supplies
			supplies = mini(2, supplies + supply_reward)
			var supplies_gained := supplies - supplies_before
			play_cue("seal")
			if seal_index < campaign_rules.SEAL_COUNT:
				seal_position = campaign_rules.seal_position(chapter, seal_index, run_seed)
				objective_notice = "阵眼已稳固 · 恢复%d生命%s · 转移到第 %d 处" % [int(health_reward), " · 补给+%d" % supplies_gained if supplies_gained > 0 else "", seal_index + 1]; notice_time = 4.5
			else:
				phase = "guardian"; spawn_tells.clear()
				announce_spawn(true)
				objective_notice = "阵眼已稳固 · 击败守门者与剩余敌人"; notice_time = 4.5
	queue_redraw()

func _check_completion(_delta: float) -> void:
	if phase == "guardian" and enemies.is_empty() and spawn_tells.is_empty() and player_health > 0:
		phase = "complete"; stop()
		metrics["elapsed_seconds"] = snappedf(chapter_clock, 0.1)
		chapter_finished.emit(metrics.duplicate(true))

func objective_contains(point: Vector2, radius: float) -> bool:
	# Ground ellipse and occupancy use the SAME projection. Feet offset cancels
	# because the centre and actors are both rendered 42px below world origin.
	var difference := point - seal_position
	return Vector2(difference.x, difference.y / 0.36).length() <= radius

func _tick_spawns(delta: float) -> void:
	for tell: Dictionary in spawn_tells: tell.remaining -= delta
	for tell: Dictionary in spawn_tells:
		if tell.remaining > 0: continue
		var profile: Dictionary = tell.profile
		_spawn_enemy_blueprint(profile, tell.position)
		enemy_serial += 1
		var enemy: Dictionary = enemies.back()
		enemy.id = enemy_serial
		enemy["expedition_elite"] = profile.get("expedition_elite", false)
		enemy.cooldown = 0.6
	spawn_tells = spawn_tells.filter(func(t: Dictionary) -> bool: return t.remaining > 0)
	if phase != "seal": return
	if not _reinforcements_allowed(): return
	spawn_clock -= delta
	if spawn_clock <= 0 and enemies.size() + spawn_tells.size() < campaign_rules.max_active_enemies(chapter):
		announce_spawn(false)
		# Short relief between reinforcements lets slow/recovering weapons hold
		# the same objective. Pressure rises by chapter, not by endless HP growth.
		spawn_clock = campaign_rules.spawn_interval(chapter)


## Theme-specific routes can hold a completed objective until its local wave
## is cleared, while the legacy Church campaign keeps its original behaviour.
func _objective_completion_allowed() -> bool:
	return true


## Long routes can delay off-screen reinforcements until the player reaches
## the next encounter segment. Static arenas continue spawning as before.
func _reinforcements_allowed() -> bool:
	return true

func announce_spawn(elite: bool) -> void:
	var profile: Dictionary = campaign_rules.make_profile(chapter, spawn_ordinal, run_seed, elite)
	if profile.is_empty(): stop(); expedition_failed.emit(); return
	var positions := [Vector2(130, 430), Vector2(1150, 555), Vector2(1120, 390), Vector2(150, 580)]
	var point: Vector2 = positions[posmod(spawn_ordinal + run_seed, positions.size())]
	if point.distance_to(player_position) < 190: point.x = 1280 - point.x
	spawn_tells.append({"profile": profile, "position": point, "remaining": 1.8})
	spawn_ordinal += 1

func _begin_compiled_enemy_attack(enemy: Dictionary, runtime: Variant, offset: Vector2) -> bool:
	if float(enemy.get("cooldown", 0)) > 0: return false
	var attackers := 0
	for other: Dictionary in enemies:
		if other.id != enemy.id and str(other.get("attack_phase", "idle")) in ["telegraph", "commit", "active"]: attackers += 1
	if attackers >= campaign_rules.max_active_attackers(chapter): return false
	return super._begin_compiled_enemy_attack(enemy, runtime, offset)

func _update_compiled_enemy_attack(enemy: Dictionary, runtime: Variant, delta: float) -> void:
	var before := str(runtime.phase)
	super._update_compiled_enemy_attack(enemy, runtime, delta)
	if before != "idle" and str(runtime.phase) == "idle": enemy.cooldown = 1.0 + (int(enemy.id) % 3) * 0.22

func _update_enemies(delta: float) -> void:
	super._update_enemies(delta)
	# Idle/recovery separation keeps silhouettes readable; committed attack
	# paths are never displaced after their authoritative warning is locked.
	for enemy: Dictionary in enemies:
		if str(enemy.get("attack_phase", "idle")) not in ["idle", "recovery"]: continue
		var diff := Vector2(enemy.pos) - player_position
		if diff.length() < 43 and diff.length() > 0.1:
			enemy.pos = _clamp_to_floor(Vector2(enemy.pos) + diff.normalized() * minf(43 - diff.length(), delta * 75))

func _take_player_damage(amount: float) -> float:
	if player_health <= 0 or invulnerable_timer > 0: return 0.0
	var actual := maxf(0.0, amount)
	if melee_runtime.active() and melee_runtime.state_power() > 0:
		actual *= float(weapon_strategy_profile.get("active_guard_damage_multiplier", 1.0))
	player_health = maxf(0.0, player_health - actual)
	metrics.damage_taken = float(metrics.damage_taken) + actual
	invulnerable_timer = 0.55; flash_timer = 0.16
	play_cue("hurt")
	metrics_changed.emit(metrics)
	return actual

func _damage_enemy(enemy: Dictionary, amount: float, hurt_seconds: float = 0.12) -> void:
	super._damage_enemy(enemy, amount, hurt_seconds)
	sparks.append({"position": Vector2(enemy.pos) + Vector2(0, -22), "life": 0.15, "color": Color("eee0c0")})
	play_cue("shot" if _uses_firearm_runtime() else "hit")

func use_supply() -> bool:
	if not active or player_health <= 0 or player_health >= 100 or supplies <= 0: return false
	supplies -= 1; player_health = minf(100, player_health + 35)
	metrics.heals_used = int(metrics.heals_used) + 1
	play_cue("seal"); return true

func _draw_stone_floor() -> void:
	super._draw_stone_floor()
	# Narrow inlaid masonry border, no competing high-frequency floor noise.
	for y: int in [408, 628]:
		draw_line(Vector2(65, y), Vector2(1214, y), Color("494054"), 2, false)
	if phase == "seal":
		var center := seal_position + Vector2(0, 42)
		var col := Color("d0a46d") if not contested else Color("b15c51")
		draw_texture_rect_region(TILES, Rect2(center + Vector2(-16, -98), Vector2(32, 88)), Rect2(256, 96, 16, 44))
		for i: int in range(48):
			var a := TAU * i / 48.0
			var b := TAU * (i + 0.75) / 48.0
			var p := center + Vector2(cos(a) * campaign_rules.SEAL_RADIUS, sin(a) * campaign_rules.SEAL_RADIUS * 0.36)
			var q := center + Vector2(cos(b) * campaign_rules.SEAL_RADIUS, sin(b) * campaign_rules.SEAL_RADIUS * 0.36)
			draw_line(p.round(), q.round(), col, 2, false)
			var inner_p := center + Vector2(cos(a) * campaign_rules.CONTEST_RADIUS, sin(a) * campaign_rules.CONTEST_RADIUS * 0.36)
			var inner_q := center + Vector2(cos(b) * campaign_rules.CONTEST_RADIUS, sin(b) * campaign_rules.CONTEST_RADIUS * 0.36)
			draw_line(inner_p.round(), inner_q.round(), Color("793d4e") if contested else Color("888c78"), 2, false)
		# Charging meter drawn on the ground, not an unexplained HUD-only timer.
		draw_rect(Rect2(center + Vector2(-42, -5), Vector2(84, 10)), Color("161633"))
		draw_rect(Rect2(center + Vector2(-40, -3), Vector2(80 * clampf(seal_progress / campaign_rules.SEAL_SECONDS, 0, 1), 6)), col)
	for tell: Dictionary in spawn_tells:
		var p: Vector2 = tell.position + Vector2(0, 40)
		var is_wizard: bool = tell.profile.get("catalog_id", "") == "ember_priest"
		var size := Vector2(81, 66) if is_wizard else Vector2(57, 60)
		var texture: Texture2D = WIZARD_IDLE if is_wizard else GHOUL_RUN
		draw_texture_rect_region(texture, Rect2(p - Vector2(size.x, size.y * 2 - 6), size * 2), Rect2(Vector2.ZERO, size), Color(0.9, 0.5, 0.4, 0.5))
		var diamond := PackedVector2Array([p + Vector2(-28, 0), p + Vector2(0, -12), p + Vector2(28, 0), p + Vector2(0, 12), p + Vector2(-28, 0)])
		draw_polyline(diamond, Color("e1924d"), 3, false)

func _draw() -> void:
	super._draw()
	# Label after architecture/borders, so the rear-floor seam cannot erase it.
	for tell: Dictionary in spawn_tells:
		var point := Vector2(tell.position) + Vector2(-40, -45)
		draw_string(preload("res://assets/fonts/NotoSansCJKsc-Regular.otf"), point, "增援 · %d" % ceili(tell.remaining), HORIZONTAL_ALIGNMENT_CENTER, 80, 15, Color("eee0c0"))
	for spark: Dictionary in sparks:
		var p: Vector2 = spark.position
		for offset: Vector2 in [Vector2(-9, -4), Vector2(7, -9), Vector2(11, 3)]:
			draw_rect(Rect2((p + offset).round(), Vector2(4, 4)), spark.color)

func enemy_frame_sample(enemy: Dictionary, attack: Dictionary) -> Dictionary:
	if str(enemy.get("blueprint_id", "")) != "frost_siege_beast": return super.enemy_frame_sample(enemy, attack)
	# Presentation only: same licensed ghoul sheet, real heavy-enemy mechanism.
	var proxy := enemy.duplicate()
	proxy.blueprint_id = "mechanical_spider"
	return super.enemy_frame_sample(proxy, attack)

func _apply_target_interaction(enemy: Dictionary, outcome: Dictionary) -> void:
	var before: String = str(enemy.get("attack_phase", "idle"))
	super._apply_target_interaction(enemy, outcome)
	if before in ["telegraph", "commit", "active"] and enemy.get("attack_phase", "idle") == "recovery":
		metrics.interruptions = int(metrics.get("interruptions", 0)) + 1
	var reaction := str(outcome.get("primary_reaction", "none"))
	var counts: Dictionary = metrics.get("reactions", {})
	counts[reaction] = int(counts.get(reaction, 0)) + 1
	metrics["reactions"] = counts

func _draw_target_interaction(enemy: Dictionary) -> void:
	if float(enemy.get("interaction_status_time", 0.0)) <= 0: return
	var word := ""
	if float(enemy.get("pin_seconds", 0)) > 0: word = "钉住"
	elif float(enemy.get("entangle_seconds", 0)) > 0: word = "缠住"
	elif float(enemy.get("suppression_seconds", 0)) > 0: word = "压制"
	elif str(enemy.get("interaction_status", "")) == "ARMOR BROKEN": word = "破甲"
	if not word.is_empty(): draw_string(preload("res://assets/fonts/NotoSansCJKsc-Regular.otf"), Vector2(enemy.pos) + Vector2(-35, -64), word, HORIZONTAL_ALIGNMENT_CENTER, 70, 14, Color("eee0c0"))

func play_cue(kind: String) -> void:
	if not audio_enabled or not is_inside_tree() or chapter_clock - last_sound_at < 0.075: return
	if audio_pool.is_empty():
		for index: int in range(4):
			var player := AudioStreamPlayer.new(); player.volume_db = -18
			add_child(player); audio_pool.append(player)
	if not sound_bank.has(kind):
		var data := PackedByteArray()
		var count := 3000 if kind == "seal" else 1300
		data.resize(count * 2)
		var frequency: float = {"hit": 130.0, "shot": 80.0, "hurt": 65.0, "seal": 440.0}.get(kind, 130.0)
		for i: int in range(count):
			var envelope := pow(1.0 - float(i) / count, 2)
			var wave := sin(TAU * frequency * i / 22050.0)
			data.encode_s16(i * 2, int(wave * envelope * 9500))
		var sound := AudioStreamWAV.new(); sound.format = AudioStreamWAV.FORMAT_16_BITS
		sound.mix_rate = 22050; sound.data = data; sound_bank[kind] = sound
	var player: AudioStreamPlayer = audio_pool[audio_cursor % audio_pool.size()]
	player.stream = sound_bank[kind]; player.play(); audio_cursor += 1; last_sound_at = chapter_clock
