extends SceneTree
const UI := preload("res://scripts/art_vertical_slice_v1/church_expedition.gd")
const SHELF := preload("res://scripts/art_vertical_slice_v1/expedition_library.gd")
const SAVE := preload("res://scripts/art_vertical_slice_v1/expedition_store.gd")
const RULES := preload("res://scripts/art_vertical_slice_v1/expedition_rules.gd")
var passed := 0
var failed := 0
class DeniedService extends RefCounted:
	var art_style_id := ""
	var use_semantic_cache := true
	func start(_description: String, _python: String) -> Dictionary:
		return {"status":"failed", "error":"OFFLINE_GENERATION_FAILURE"}
	func cancel_current() -> void:
		pass
func _initialize() -> void:
	for key: String in ["ANTHROPIC_API_KEY", "FAL_KEY", "FAL_API_KEY"]: OS.unset_environment(key)
	if not OS.has_environment("FORGE_WEAPON_LIBRARY_ROOT"):
		OS.set_environment("FORGE_WEAPON_LIBRARY_ROOT", "res://.tools/expedition-tests/%d" % Time.get_ticks_usec())
	call_deferred("run")
func check(label: String, condition: bool) -> void:
	if condition: passed += 1; print("PASS | ", label)
	else: failed += 1; printerr("FAIL | ", label)
func run() -> void:
	var duplicate_samples: Array[Dictionary] = [
		{"identity":"saved-chain-v2", "display_name":"一条末端挂着黄铜挂锁的铁链"},
		{"identity":"legacy-chain-cache", "display_name":"一条末端挂着黄铜挂锁的铁链"},
		{"identity":"fork", "display_name":"一把绿色塑料柄的长柄园艺叉"},
	]
	var unique_samples := SHELF.deduplicate_shelf(duplicate_samples)
	check("Shelf collapses duplicate archive keys by player-facing weapon identity", unique_samples.size() == 2 and unique_samples[0] == duplicate_samples[0])
	var shelf := SHELF.new().load_all(false)
	check("Five labelled existing AI starter packages, no generation", shelf.size() == 5)
	for weapon: Dictionary in shelf:
		check("Starter strictly validates pixels/anchors/compiled axes", UI.validate_entry(weapon).get("ok", false))
		check("Starter has explicit origin", weapon.get("bundled_starter", false))
	var root_path := SAVE.new().directory
	var ui := UI.new(); ui.include_user_library = false
	root.add_child(ui); await process_frame
	ui.set_process(false); ui.arena.audio_enabled = false
	check("Hub opens with forge, library and run actions", ui.flow == "hub" and ui.shelf.size() == 5 and ui.hub_page.visible)
	check("Opening hub does not write user storage", not DirAccess.dir_exists_absolute(root_path))
	check("HUD bars stay thin, theme cannot expand them", ui.health_bar.size.y <= 10 and ui.run_progress.size.y <= 10)
	check("A new run saves selected weapon and chapter checkpoint", ui.start_new_run(13).get("ok", false) and ui.flow == "briefing" and SAVE.new().read_state().checkpoint.chapter == 0)
	check("Begin chapter uses same actual sprite", ui.begin_chapter().ok and ui.arena.asset == ui.entry.asset)
	check("No instant win on empty enemy list", ui.arena.phase == "seal" and ui.flow == "combat")
	ui.arena.player_position = Vector2(1100, 360)
	ui.arena._process(0.1)
	check("Leaving objective does not charge it", ui.arena.seal_progress == 0)
	ui.arena.player_position = ui.arena.seal_position
	ui.arena._process(0.1)
	check("Standing in safe objective earns progress", ui.arena.seal_progress > 0)
	check("Ground ellipse uses visible depth, not a hidden large circle", ui.arena.objective_contains(ui.arena.seal_position + Vector2(90, 20), RULES.SEAL_RADIUS) and not ui.arena.objective_contains(ui.arena.seal_position + Vector2(0, 60), RULES.SEAL_RADIUS))
	var profile := RULES.make_profile(0, 0, 13)
	ui.arena._spawn_enemy_blueprint(profile, ui.arena.seal_position)
	var previous: float = ui.arena.seal_progress
	ui.arena._process(0.01)
	check("Enemy contest pauses charging", ui.arena.contested and ui.arena.seal_progress == previous)
	ui.pause_run(); var clock: float = ui.arena.chapter_clock
	ui._process(2.0)
	check("Pause freezes gameplay and objective time", ui.arena.chapter_clock == clock and ui.flow == "paused")
	ui.resume_combat()
	ui.arena.player_health = 40; ui.arena.supplies = 2
	check("Supply heals 35 and consumes exactly one", ui.arena.use_supply() and ui.arena.player_health == 75 and ui.arena.supplies == 1)
	ui.arena.player_health = 100
	check("Full health cannot consume supply", not ui.arena.use_supply() and ui.arena.supplies == 1)
	check("Finite objective budget, no zero/negative duration", RULES.SEAL_SECONDS == 85.0)
	check("Same seed gives same objective layout", RULES.seal_position(1, 0, 13) == RULES.seal_position(1, 0, 13))
	check("Next seal requires a position change", RULES.seal_position(1, 0, 13) != RULES.seal_position(1, 1, 13))
	check("Final guardian has valid real attack profile", not RULES.make_profile(2, 0, 13, true).is_empty())
	# State-machine checks below deliberately inject completion, NOT playthrough.
	ui.arena.player_health = 65; ui.arena.supplies = 0
	ui._chapter_finished({"elapsed_seconds": 200, "defeated": 7, "damage_taken": 35})
	check("Chapter ends at camp with full rest and supplies", ui.flow == "camp" and ui.run_chapter == 1 and ui.run_health == 100 and ui.run_supplies == 2)
	check("Next chapter checkpoint persists", SAVE.new().read_state().checkpoint.chapter == 1)
	var resumed := UI.new(); resumed.include_user_library = false
	root.add_child(resumed); await process_frame; resumed.set_process(false); resumed.arena.audio_enabled = false
	check("Reopening hub does not implicitly replace checkpoint weapon", not resumed.camp_return)
	check("Continue restores exact saved chapter and weapon", resumed.continue_run().get("ok", false) and resumed.run_chapter == 1 and resumed.entry.library_key == SAVE.new().read_state().checkpoint.weapon_key)
	resumed.queue_free(); await process_frame
	ui._dialog_secondary(); ui.select_weapon(1); ui._resume_after_selection()
	check("Camp equipment change starts next chapter", ui.flow == "combat" and ui.arena.chapter == 1 and ui.arena.asset == ui.entry.asset)
	ui.arena.invulnerable_timer = 0; ui.arena.player_health = 1; ui.arena._take_player_damage(50); ui.arena._process(0.01)
	check("Real health can reach zero and lose", ui.flow == "defeated" and ui.arena.player_health == 0)
	check("Death does not erase checkpoint", SAVE.new().read_state().checkpoint.chapter == 1)
	check("Retry returns to chapter start, not free refill in place", ui.restart_battle().ok and ui.flow == "combat" and ui.arena.chapter == 1 and ui.arena.player_health == 100)
	ui._chapter_finished({"elapsed_seconds": 200}); ui.begin_chapter(); ui._chapter_finished({"elapsed_seconds": 200})
	check("Three chapters reach one result screen", ui.flow == "result" and ui.completed_run)
	check("Completion clears checkpoint and records history", SAVE.new().read_state().checkpoint.is_empty() and SAVE.new().read_state().history.size() == 1)
	var invalid := SAVE.new().read_state(); invalid.checkpoint = {"chapter": 99}
	check("Malformed checkpoint rejected", not SAVE.valid(invalid))
	var invalid_history := SAVE._empty(); invalid_history.history = ["not a result"]
	check("Malformed history cannot crash the hub", not SAVE.valid(invalid_history))
	var bad_metric := SAVE._empty(); bad_metric.history = [{"weapon":"test","metrics":{"elapsed_seconds":"bad"}}]
	check("Non-numeric recorded metrics are rejected", not SAVE.valid(bad_metric))
	var broken_save := SAVE.new(); broken_save.directory = "res://project.godot/forbidden-child"
	check("Unwritable save fails explicitly", not broken_save.write_state(SAVE._empty()).get("ok", false))
	var before_checkpoint: Dictionary = ui.campaign.checkpoint.duplicate(true)
	var good_store: RefCounted = ui.campaign_store; ui.campaign_store = broken_save
	check("Failed checkpoint does not publish false in-memory progress", not ui._checkpoint().get("ok", false) and ui.campaign.checkpoint == before_checkpoint)
	ui.campaign_store = good_store
	# Real saved gun, actual muzzle and ordinary projectile integration. Position
	# setup isolates the old edge-of-floor miss; no hit/damage parameter override.
	var gun := {}
	for candidate: Dictionary in shelf:
		if candidate.blueprint.affordance.get("support_mode", "") == "one_hand" and candidate.blueprint.affordance.get("weapon_domain", "") == "handheld_firearm": gun = candidate; break
	check("Catalogue includes a genuinely compiled one-hand firearm", not gun.is_empty())
	if not gun.is_empty():
		ui.arena.begin_chapter(0, 0, gun, 100, 2)
		ui.arena.player_position = Vector2(100, 600); ui.arena.facing = 1
		# Native full-body holding has a different hand/muzzle position. Put the
		# target in FRONT of the actual fire-pose barrel, not behind its tip.
		ui.arena.shot_age = 0.0
		var muzzle_before: Vector2 = ui.arena._muzzle_world()
		ui.arena._spawn_enemy_blueprint(RULES.make_profile(0, 0, 0), Vector2(muzzle_before.x + 24, 599))
		var victim: Dictionary = ui.arena.enemies[0]; var hp: float = victim.hp
		ui.arena._fire_bullet(); ui.arena._update_projectiles(0.1)
		check("Floor-edge handgun shot crossing visible torso hits", victim.hp < hp)
		check("Torso capsule does not accept shots well above silhouette", not ui.arena._projectile_contacts_enemy(Vector2(100, 490), Vector2(200, 490), {"projectile_radius_pixels": 5}, victim))
		var base := GameplayArena.new()
		check("Fast projectile sweep cannot tunnel through old targets", base._projectile_contacts_enemy(Vector2(0,0), Vector2(100,0), {}, {"pos":Vector2(50,0)}))
		base.free()
	ui.arena.stop(); ui.state = "success"; ui.flow = "hub"
	ui.configure_dependencies(func() -> RefCounted: return DeniedService.new())
	ui.open_forge(); ui.begin_generation("a new unrecognized object")
	check("Unified forge failure never auto-equips a bundled sample", ui.state == "failed" and ui.flow == "forge" and ui.entry.is_empty())
	for page: Control in [ui.hub_page, ui.run_page, ui.dialog_page]: check("Full page fits logical 1280x720", page.size == Vector2(1280,720))
	ui.queue_free(); await process_frame
	print("CHURCH_EXPEDITION_TESTS passed=%d failed=%d" % [passed, failed]); quit(0 if failed == 0 else 1)
