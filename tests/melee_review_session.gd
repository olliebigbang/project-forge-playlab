extends Node2D
## Visible, offline review harness. Uses the production arena and real cached
## art/AI declarations; never writes the player's library or calls providers.
const ARENA := preload("res://scripts/systems/gameplay_arena.gd")
const LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")
const AI := preload("res://scripts/combat_feel/general_object_ai_resolver.gd")
const INTERPRETER := preload("res://scripts/services/open_identity_interpreter.gd")
const VISUAL := preload("res://scripts/services/fal_general_object_visual_provider.gd")
const ANCHORS := preload("res://scripts/systems/anchor_resolver.gd")
const FACTORY := preload("res://scripts/combat_feel/weapon_entry_factory.gd")
const ARMORY := preload("res://scripts/combat_feel/player_weapon_armory.gd")
const DIRECTOR := preload("res://scripts/enemy_attack/automatic_encounter_director.gd")
var arena: GameplayArena
var entries: Array[Dictionary] = []
var label: Label
var selected := 0
var ability_hold := 0.0
var auto_combo := false
var pause_game := false
var frame_count := 0
var max_step_usec := 0
var keys_down: Dictionary = {}
var root: Window
var replay := false
var soft_only := false
var replay_elapsed := 0.0
var replay_taps := 0
var replay_ability := false
var captured: Dictionary = {}
var replay_results: Array = []
var step_samples: Array[int] = []
var review_dir := "res://.tools/melee-axis-review/visual-final"

func _ready() -> void:
	root = get_tree().root
	call_deferred("_setup")

func _setup() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(review_dir))
	root.title = "Forge — Mechanism Runtime Review"
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.show()
	_load_cached_objects()
	var soft: Dictionary = LOADER.new().load_soft_weapon_asset("fishing_rod_builtin")
	if bool(soft.get("ok", false)): entries.append(soft)
	var guns: Array[Dictionary] = ARMORY.new().load_entries()
	if not guns.is_empty(): entries.append(guns[0])
	arena = ARENA.new() as GameplayArena
	root.add_child(arena)
	label = Label.new()
	label.position = Vector2(25, 18)
	label.size = Vector2(1220, 108)
	label.add_theme_font_override("font", load("res://assets/fonts/NotoSansCJKsc-Regular.otf"))
	label.add_theme_font_size_override("font_size", 17)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	layer.add_child(label)
	if entries.is_empty(): push_error("NO_REVIEW_ENTRIES"); get_tree().quit(1); return
	_select(0)
	replay = "--replay" in OS.get_cmdline_user_args()
	soft_only = "--soft-only" in OS.get_cmdline_user_args()
	if soft_only: _select(2)
	print("REVIEW_ENTRIES ", entries.map(func(e: Dictionary) -> String: return e.blueprint.display_name))
	if "--probe" in OS.get_cmdline_user_args():
		for index: int in range(entries.size()):
			_select(index)
			print("REVIEW_ENTRY ", index, " ", entries[index].blueprint.display_name, " ", arena.melee_runtime.error)
			if entries[index].asset.visual_rig != null:
				print("REVIEW_RIG ", index, " grip=", entries[index].asset.grip_primary, " tip=", entries[index].asset.tip, " joints=", entries[index].asset.visual_rig.linked_joint_ratios(), " parts=", entries[index].asset.visual_rig.parts)
		get_tree().quit()

func _load_cached_objects() -> void:
	var cache := "user://playlab/fal_general_object_visual/cache_v1"
	var dir := DirAccess.open(cache)
	if dir == null: return
	var used := {}
	for child: String in dir.get_directories():
		var directory := cache.path_join(child)
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("manifest.json")))
		if not manifest is Dictionary: continue
		var identity := str(manifest.get("identity", ""))
		if identity.is_empty() or used.has(identity): continue
		var semantic: Dictionary = AI.resolve_identity(identity)
		if not bool(semantic.get("ok", false)): continue
		var interpreted: Dictionary = INTERPRETER.new().interpret_with_ai_object_profile(identity, PackedByteArray(), {}, semantic)
		if not bool(interpreted.get("ok", false)): continue
		var bp: WeaponBlueprint = interpreted.blueprint
		var image := Image.load_from_file(ProjectSettings.globalize_path(directory.path_join("processed_sprite.png")))
		if image == null: continue
		var asset: WeaponVisualAsset = ANCHORS.resolve(image, bp)
		VISUAL.new()._apply_mechanism_anchor_intent(asset, bp)
		var result: Dictionary = FACTORY.finish(bp, {"asset": asset, "manifest": manifest})
		if bool(result.get("ok", false)):
			entries.append(result)
			used[identity] = true

func _select(index: int) -> void:
	selected = posmod(index, entries.size())
	ability_hold = 0.0
	auto_combo = false
	replay_elapsed = 0.0
	replay_taps = 0
	replay_ability = false
	max_step_usec = 0
	step_samples.clear()
	var entry := entries[selected]
	var director: RefCounted = DIRECTOR.new()
	director.configure()
	director.begin_run(entry)
	var encounter: Dictionary = director.begin_next_encounter()
	var profiles: Array[Dictionary] = []
	for p: Dictionary in encounter.get("profiles", []): profiles.append(p)
	arena.start_stage("mechanism_review", entry.blueprint, entry.asset, profiles)
	arena.player_position = Vector2(450, 420)
	if not arena.enemies.is_empty(): arena.enemies[0]["pos"] = Vector2(630, 420)
	arena.set_process(false)
	print("REVIEW_SELECT ", selected, " ", entry.blueprint.display_name)

func _process(delta: float) -> void:
	if arena == null: return
	for key: int in [KEY_N, KEY_R, KEY_H, KEY_C, KEY_P, KEY_F8, KEY_ESCAPE]:
		var down := Input.is_physical_key_pressed(key)
		if down and not bool(keys_down.get(key, false)): _review_key(key)
		keys_down[key] = down
	if not pause_game:
		if replay: _drive_replay(delta)
		var started := Time.get_ticks_usec()
		if ability_hold > 0.0:
			ability_hold -= delta
			arena.set_touch_attack(ability_hold > 0.0)
		if auto_combo and not arena.melee_runtime.busy(): arena.request_touch_attack()
		arena._process(delta)
		max_step_usec = maxi(max_step_usec, Time.get_ticks_usec() - started)
		step_samples.append(Time.get_ticks_usec() - started)
		frame_count += 1
	label.text = "机制执行审核 · %d/%d · %s　生命 %.0f　命中 %d\nA/D/W/S 移动　Space 攻击　H 长按能力（2秒）　C 连击开关　P 暂停　N 下一件　R 重开\n%s · %s · %s%s" % [selected + 1, entries.size(), entries[selected].blueprint.display_name, arena.player_health, int(arena.metrics.get("melee_hits", arena.metrics.get("shots_fired", 0))), str(arena.melee_runtime.controller.phase), str(arena.melee_runtime.controller.combo_index), str(arena.metrics.get("last_melee_verb", "")), " · 已暂停" if pause_game else ""]
	if replay:
		label.text = "自动输入回放审核（非桌面手动试玩）\n" + label.text
		var controller: RefCounted = arena.melee_runtime.controller
		if (arena.melee_runtime.active() and controller.phase_ratio() > 0.45) or (arena._uses_firearm_runtime() and replay_elapsed > 1.0):
			_capture_once("%02d-%s-%s" % [selected, controller.attack_kind, controller.combo_index])
		if replay_elapsed > 0.1 and replay_elapsed < 0.2: _capture_once("%02d-idle" % selected)


func _drive_replay(delta: float) -> void:
	replay_elapsed += delta
	if arena._uses_firearm_runtime():
		arena.set_touch_attack(true)
	else:
		if not arena.melee_runtime.busy() and replay_taps < 3:
			arena.request_touch_attack()
			replay_taps += 1
		elif not arena.melee_runtime.busy() and not replay_ability:
			ability_hold = 1.2
			replay_ability = true
	if replay_elapsed < 7.0: return
	step_samples.sort()
	replay_results.append({"identity": entries[selected].blueprint.display_name, "metrics": arena.metrics.duplicate(true), "engine_step_p95_usec": step_samples[int(step_samples.size() * 0.95)] if not step_samples.is_empty() else 0, "engine_step_max_usec": max_step_usec, "runtime_error": arena.melee_runtime.error})
	if selected + 1 < entries.size() and not soft_only:
		_select(selected + 1)
	else:
		var file := FileAccess.open(review_dir.path_join("visible-replay.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"desktop_manual_input": false, "real_godot_render": true, "results": replay_results}, "\t"))
		file.close()
		print("VISIBLE_REPLAY_COMPLETE ", JSON.stringify(replay_results))
		get_tree().quit()


func _capture_once(key: String) -> void:
	if captured.has(key): return
	captured[key] = true
	if soft_only:
		var data := {"geometry": arena.melee_frame.get("geometry", {}), "pixels": arena.melee_frame.get("pixels", [])}
		var trace := FileAccess.open(review_dir.path_join("frame-%s.json" % key), FileAccess.WRITE)
		trace.store_string(JSON.stringify(data, "\t"))
		trace.close()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(review_dir.path_join("replay-%s.png" % key))

func _review_key(key: int) -> void:
	match key:
		KEY_N: _select(selected + 1)
		KEY_R: _select(selected)
		KEY_H: ability_hold = 2.0; arena.set_touch_attack(false); arena.attack_was_down = false
		KEY_C: auto_combo = not auto_combo
		KEY_P: pause_game = not pause_game
		KEY_F8:
			var image := root.get_texture().get_image()
			var path := review_dir.path_join("visible-%02d-%d.png" % [selected, frame_count])
			image.save_png(path)
			print("REVIEW_SCREENSHOT ", path, " ", arena.metrics, " max_step_usec=", max_step_usec)
		KEY_ESCAPE: get_tree().quit()
