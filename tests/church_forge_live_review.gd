extends SceneTree
## Explicit developer live QA only. Never included in offline test discovery.
const FORGE := preload("res://scripts/art_vertical_slice_v1/church_forge.gd")
const LIBRARY := preload("res://scripts/combat_feel/weapon_library_store.gd")
const SAMPLE := preload("res://scripts/art_vertical_slice_v1/art_slice_session.gd")
const INPUTS := ["一把绿色塑料柄的长柄园艺叉", "一个红色金属咖啡壶，带壶嘴和侧把手", "一条末端挂着黄铜挂锁的铁链"]
var evidence_dir := ""
var records: Array[Dictionary] = []
var ui: Node2D

func _initialize() -> void:
	if "--allow-live-ai-review" not in OS.get_cmdline_user_args() or not OS.has_environment("FORGE_WEAPON_LIBRARY_ROOT"):
		printerr("LIVE_REVIEW_EXPLICIT_FLAG_AND_ISOLATED_LIBRARY_REQUIRED")
		quit(2)
		return
	evidence_dir = ProjectSettings.globalize_path("res://.tools/church-ai-forge/live-%d-%d" % [int(Time.get_unix_time_from_system()), OS.get_process_id()])
	DirAccess.make_dir_recursive_absolute(evidence_dir)
	call_deferred("_run")

func _run() -> void:
	ui = FORGE.new()
	ui.use_semantic_cache = false
	root.add_child(ui)
	await process_frame
	await _capture("00-empty-forge")
	for index: int in range(INPUTS.size()):
		var identity: String = INPUTS[index]
		var prefix := "%02d" % (index + 1)
		var started := Time.get_ticks_msec()
		print("LIVE_REVIEW_BEGIN ", index + 1, " ", identity)
		ui.begin_generation(identity)
		var last_stage := ""
		while ui.state == "generating" and Time.get_ticks_msec() - started < 650000:
			if ui.generation_stage != last_stage:
				last_stage = ui.generation_stage
				print("LIVE_REVIEW_STAGE ", index + 1, " ", last_stage)
			await create_timer(0.10).timeout
		if ui.state == "generating": ui.cancel_generation()
		var record := {"identity": identity, "state": ui.state, "error": ui.error_code, "seconds": snappedf((Time.get_ticks_msec() - started) / 1000.0, 0.1), "generation_evidence": ui.generation_evidence.duplicate(true), "api_request_limit": 2, "input_method": "automated_UI_controller_and_touch_actions_not_manual_desktop"}
		if ui.service != null:
			if ui.service.semantic_provider != null: record["semantic_output"] = ui.service.semantic_provider.active_output_directory
			if ui.service.visual_provider != null: record["visual_output"] = ui.service.visual_provider.active_output_directory
		if ui.state != "success":
			await _capture(prefix + "-generation-failed")
			records.append(record)
			_write_report()
			print("LIVE_REVIEW_REJECTED ", index + 1, " ", ui.error_code)
			continue
		await _capture(prefix + "-preview")
		var asset: WeaponVisualAsset = ui.entry.asset
		asset.source_image.save_png(evidence_dir.path_join(prefix + "-sprite.png"))
		record["blueprint"] = ui.entry.blueprint.to_dict()
		record["anchors"] = asset.anchors_dict()
		record["visual_evidence"] = ui.entry.visual_evidence.duplicate(true)
		var started_battle: Dictionary = ui.enter_battle()
		record["battle_start"] = started_battle
		if bool(started_battle.get("ok", false)):
			record["same_generated_asset_in_arena"] = ui.arena.asset == asset
			record["battle"] = await _battle(prefix)
		ui.return_to_forge()
		record["returned_with_same_weapon"] = ui.state == "success" and ui.entry.asset == asset and ui.input_text == identity
		var saved: Dictionary = ui.save_current_entry()
		var restored: Dictionary = LIBRARY.new().load_entry(str(saved.get("library_key", ""))) if bool(saved.get("ok", false)) else {}
		record["isolated_save"] = {"ok": saved.get("ok", false), "error": saved.get("error", ""), "library_key": saved.get("library_key", ""), "restored": restored.get("ok", false), "pixels_identical": bool(restored.get("ok", false)) and restored.asset.source_image.get_data() == asset.source_image.get_data()}
		await _capture(prefix + "-returned-saved")
		records.append(record)
		_write_report()
		print("LIVE_REVIEW_COMPLETE ", index + 1, " ", JSON.stringify(record.get("battle", {})))
	var successes := 0
	var playable := 0
	for record: Dictionary in records:
		if record.state == "success": successes += 1
		var battle: Dictionary = record.get("battle", {})
		var metrics: Dictionary = battle.get("metrics", {})
		if record.get("same_generated_asset_in_arena", false) and record.get("returned_with_same_weapon", false) and (record.get("isolated_save", {}) as Dictionary).get("pixels_identical", false) and battle.get("runtime_error", "missing") == "" and int(metrics.get("melee_hits", 0)) + int(metrics.get("shots_fired", 0)) > 0:
			playable += 1
	print("LIVE_REVIEW_RESULT generated=%d/%d playable_and_saved=%d evidence=%s" % [successes, INPUTS.size(), playable, evidence_dir])
	ui.queue_free()
	await process_frame
	quit(0 if successes == INPUTS.size() and playable == INPUTS.size() else 1)

func _battle(prefix: String) -> Dictionary:
	var elapsed := 0.0
	var last_dodge := -10.0
	var captured := {}
	var arena: GameplayArena = ui.arena
	while elapsed < 24.0 and ui.state == "combat":
		await process_frame
		elapsed += root.get_process_delta_time()
		if elapsed > 0.15 and not captured.has("idle"):
			captured.idle = true
			await _capture(prefix + "-idle")
		if elapsed < 0.5:
			arena.set_touch_vector(Vector2.LEFT if elapsed > 0.30 else Vector2.ZERO)
			continue
		if elapsed > 0.50 and not captured.has("left"):
			captured.left = true
			await _capture(prefix + "-left")
		if not arena.enemies.is_empty():
			var target: Dictionary = arena.enemies[0]
			for enemy: Dictionary in arena.enemies:
				if arena.player_position.distance_squared_to(enemy.pos) < arena.player_position.distance_squared_to(target.pos): target = enemy
			var offset := Vector2(target.pos) - arena.player_position
			var firearm := arena._uses_firearm_runtime()
			var reach := 260.0 if firearm else 65.0
			var move := Vector2.ZERO
			if absf(offset.y) > 10.0: move.y = signf(offset.y)
			if absf(offset.x) > reach: move.x = signf(offset.x)
			elif firearm and absf(offset.x) < 160.0: move.x = -signf(offset.x)
			elif arena.facing != signf(offset.x): move.x = signf(offset.x) * 0.15
			if str(target.get("attack_phase", "")) in ["telegraph", "active"] and offset.length() < 180 and elapsed - last_dodge > 1.6:
				move.y = 1 if arena.player_position.y < 480 else -1
				arena.request_touch_dodge()
				last_dodge = elapsed
			arena.set_touch_vector(move)
			if firearm: arena.set_touch_attack(SAMPLE.replay_trigger_down(arena.ranged_runtime_profile, elapsed, absf(offset.y) < 30))
			else:
				arena.set_touch_attack(elapsed > 3.0 and elapsed < 5.5)
				if elapsed >= 5.5 and not arena.melee_runtime.busy() and offset.length() < 150: arena.request_touch_attack()
		if arena.melee_runtime.active():
			var key := "attack-" + str(arena.melee_runtime.controller.attack_kind)
			if not captured.has(key):
				captured[key] = true
				await _capture(prefix + "-" + key)
		for enemy: Dictionary in arena.enemies:
			var phase := str(enemy.get("attack_phase", ""))
			if phase in ["telegraph", "active"]:
				var key := str(enemy.blueprint_id) + "-" + phase
				if not captured.has(key):
					captured[key] = true
					await _capture(prefix + "-enemy-" + key)
	arena.set_touch_vector(Vector2.ZERO)
	arena.set_touch_attack(false)
	await _capture(prefix + "-battle-end")
	return {"seconds": snappedf(elapsed, 0.1), "state": ui.state, "metrics": arena.metrics.duplicate(true), "runtime_error": arena.melee_runtime.error, "captured": captured.keys()}

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(evidence_dir.path_join(label + ".png"))

func _write_report() -> void:
	var file := FileAccess.open(evidence_dir.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"records": records, "library_root": OS.get_environment("FORGE_WEAPON_LIBRARY_ROOT"), "no_user_library_writes": true, "live_inputs_maximum": 3, "visual_requests_per_input_maximum": 2, "not_manual_desktop": true}, "  "))
	file.close()
