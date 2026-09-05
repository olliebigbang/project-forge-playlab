extends Node2D
## Independent offline art sample. Existing mechanism declarations and source
## weapon pixels are reused; this scene never generates or saves a weapon.
const ARENA_PATH := "res://scripts/art_vertical_slice_v1/church_arena.gd"
const ARMORY := preload("res://scripts/combat_feel/player_weapon_armory.gd")
const LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")
const AI := preload("res://scripts/combat_feel/general_object_ai_resolver.gd")
const INTERPRETER := preload("res://scripts/services/open_identity_interpreter.gd")
const VISUAL := preload("res://scripts/services/fal_general_object_visual_provider.gd")
const ANCHORS := preload("res://scripts/systems/anchor_resolver.gd")
const FACTORY := preload("res://scripts/combat_feel/weapon_entry_factory.gd")
const CATALOG := preload("res://scripts/enemy_attack/offline_enemy_blueprint_catalog.gd")
const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
const OBJECT_CACHE := "user://playlab/fal_general_object_visual/cache_v1"
const OBJECT_IDENTITIES: Array[String] = ["一把普通的短柄铁锤", "一把带弯柄、可以开合的长雨伞"]
const EVIDENCE_ROOT := "res://.tools/art-vertical-slice-v1/evidence"
const REPLAY_SECONDS := 20.0

var arena: GameplayArena
var entries: Array[Dictionary] = []
var diagnostics: Array[String] = []
var selected := 0
var state := "loading"
var replay := false
var smoke := false
var smoke_started := false
var smoke_elapsed := 0.0
var key_events_received := 0
var hotkey_presses_received := 0
var replay_elapsed := 0.0
var replay_results: Array[Dictionary] = []
var phase_observations: Dictionary = {}
var action_observations: Dictionary = {}
var captured: Dictionary = {}
var evidence_dir := ""
var capture_pending := 0
var step_samples: Array[int] = []
var header: Label
var detail: Label
var right_header: Label
var outcome_panel: PanelContainer
var outcome_title: Label
var outcome_detail: Label
var weapon_buttons: Array[Button] = []
var attack_button: Button
var dodge_button: Button
var replay_dodge_at := -100.0
var frame_count := 0
var runtime_stepped := false


func _ready() -> void:
	call_deferred("_setup")


func _setup() -> void:
	var args := OS.get_cmdline_user_args()
	replay = "--replay" in args
	smoke = "--smoke" in args
	var root := get_tree().root
	root.title = "Forge — Church Art Sample (offline)"
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(1280, 720)
	root.min_size = Vector2i(960, 540)
	Engine.max_fps = 60
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var loaded := load_offline_entries()
	entries.assign(loaded.get("entries", []))
	diagnostics.assign(loaded.get("diagnostics", []))
	_build_ui()
	if entries.is_empty():
		_show_failure("没有可用的离线武器", "本样板没有在线生成或使用假枪。请先在工坊生成并保存武器，再启动本场景。")
		if "--probe" in args or replay: get_tree().quit(1)
		return
	var arena_script: Script = load(ARENA_PATH)
	if arena_script == null:
		_show_failure("教堂场景未能加载", "请检查本地文件是否完整。")
		if "--probe" in args or replay: get_tree().quit(1)
		return
	arena = arena_script.new() as GameplayArena
	add_child(arena)
	arena.stage_completed.connect(_on_stage_completed)
	_select(0)
	if "--probe" in args:
		var failures := 0
		for index: int in range(entries.size()):
			_select(index)
			var valid: bool = state == "combat" and arena.enemies.size() == 2 and arena.melee_runtime.error.is_empty()
			if not valid: failures += 1
			print("ART_SLICE_ENTRY ", JSON.stringify({"index": index + 1, "identity": entries[index].blueprint.display_name, "source": entries[index].get("art_sample_source", ""), "weapon_domain": entries[index].blueprint.affordance.get("weapon_domain", ""), "runtime_error": arena.melee_runtime.error, "enemy_count": arena.enemies.size(), "ok": valid}))
		print("ART_SLICE_PROBE ", JSON.stringify({"entries": entries.size(), "failed": failures, "diagnostics": diagnostics, "online_calls": false, "saved_library_written": false}))
		get_tree().quit(0 if failures == 0 else 1)
	elif replay:
		_create_evidence_dir()
		print("ART_SLICE_REPLAY_START ", ProjectSettings.globalize_path(evidence_dir))
	elif smoke:
		_create_evidence_dir()
		print("ART_SLICE_NORMAL_SMOKE_START ", ProjectSettings.globalize_path(evidence_dir))


static func load_offline_entries() -> Dictionary:
	var output: Array[Dictionary] = []
	var problems: Array[String] = []
	var firearm_candidates: Array[Dictionary] = []
	for entry: Dictionary in ARMORY.new().load_entries():
		var blueprint := entry.get("blueprint") as WeaponBlueprint
		if blueprint != null and str(blueprint.affordance.get("weapon_domain", "")) == "handheld_firearm":
			firearm_candidates.append(entry)
	firearm_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.blueprint.display_name) < str(b.blueprint.display_name))
	# Classify the presentation sample by validated structure, never by gun name.
	# This selects visuals only and does not choose or replace combat recipes.
	for one_hand: bool in [true, false]:
		var found := false
		for entry: Dictionary in firearm_candidates:
			var axes: Dictionary = entry.blueprint.affordance
			var is_one_hand := str(axes.get("support_mode", "")) == "one_hand"
			if is_one_hand != one_hand: continue
			var sample := entry.duplicate(true)
			sample["art_sample_source"] = "validated_local_firearm_cache"
			output.append(sample)
			found = true
			break
		if not found: problems.append("本地没有合格的%s缓存；没有替换成默认武器。" % ("手枪" if one_hand else "双手枪械"))
	for identity: String in OBJECT_IDENTITIES:
		var object_entry := _load_cached_object(identity)
		if bool(object_entry.get("ok", false)):
			object_entry["art_sample_source"] = "validated_local_object_cache"
			output.append(object_entry)
		else:
			problems.append("%s：%s" % [identity, object_entry.get("error", "缓存不可用")])
	var soft: Dictionary = LOADER.new().load_soft_weapon_asset("fishing_rod_builtin")
	if bool(soft.get("ok", false)):
		soft["art_sample_source"] = "explicit_builtin_development_fishing_rod"
		output.append(soft)
	else:
		problems.append("开发鱼竿样本不可用：%s" % str(soft.get("error", "unknown")))
	return {"entries": output, "diagnostics": problems}


static func _load_cached_object(identity: String) -> Dictionary:
	var semantic: Dictionary = AI.resolve_identity(identity)
	if not bool(semantic.get("ok", false)): return semantic
	var interpreted: Dictionary = INTERPRETER.new().interpret_with_ai_object_profile(identity, PackedByteArray(), {}, semantic)
	if not bool(interpreted.get("ok", false)): return interpreted
	var directory := DirAccess.open(OBJECT_CACHE)
	if directory == null: return {"ok": false, "error": "OBJECT_VISUAL_CACHE_MISSING"}
	var children := directory.get_directories()
	children.sort()
	for child: String in children:
		var path := OBJECT_CACHE.path_join(child)
		if not FileAccess.file_exists(path.path_join("manifest.json")): continue
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(path.path_join("manifest.json")))
		if not manifest is Dictionary or str(manifest.get("identity", "")) != identity: continue
		var sprite_path := path.path_join("processed_sprite.png")
		if not FileAccess.file_exists(sprite_path): continue
		var image := Image.load_from_file(ProjectSettings.globalize_path(sprite_path))
		if image == null or image.is_empty(): continue
		var bp := interpreted.get("blueprint") as WeaponBlueprint
		var asset: WeaponVisualAsset = ANCHORS.resolve(image, bp)
		VISUAL.new()._apply_mechanism_anchor_intent(asset, bp)
		var result: Dictionary = FACTORY.finish(bp, {"asset": asset, "manifest": manifest})
		if bool(result.get("ok", false)): return result
	return {"ok": false, "error": "OBJECT_VISUAL_CACHE_NOT_VALIDATED"}


static func encounter_profiles() -> Array[Dictionary]:
	var catalog: Dictionary = CATALOG.load_validated()
	var profiles: Array[Dictionary] = []
	if not bool(catalog.get("ok", false)): return profiles
	var ids := ["ember_priest", "mechanical_spider"]
	var names := ["教堂术士", "焚行者"]
	var positions := [Vector2(710, 460), Vector2(990, 545)]
	for index: int in range(ids.size()):
		var profile: Dictionary = catalog.profiles_by_id.get(ids[index], {}).duplicate(true)
		if profile.is_empty(): return []
		profile["display_name"] = names[index]
		profile["spawn_position"] = positions[index]
		profiles.append(profile)
	return profiles


func _select(index: int) -> void:
	if entries.is_empty() or arena == null: return
	selected = posmod(index, entries.size())
	var profiles := encounter_profiles()
	if profiles.size() != 2:
		_show_failure("敌人蓝图不可用", "未改用无攻击机制的占位敌人。")
		return
	var entry := entries[selected]
	arena.start_stage("church_art_sample", entry.blueprint, entry.asset, profiles)
	arena.player_position = Vector2(350, 475)
	arena.facing = 1.0
	arena.invulnerable_timer = 0.0
	arena.flash_timer = 0.0
	arena.set_touch_vector(Vector2.ZERO)
	arena.set_touch_attack(false)
	arena.set_process(false)
	state = "combat"
	outcome_panel.hide()
	replay_elapsed = 0.0
	replay_dodge_at = -100.0
	phase_observations.clear()
	action_observations.clear()
	step_samples.clear()
	for button_index: int in range(weapon_buttons.size()):
		weapon_buttons[button_index].button_pressed = button_index == selected
	_refresh_ui()
	print("ART_SLICE_SELECT ", selected + 1, " ", entry.blueprint.display_name)


func _process(delta: float) -> void:
	if arena == null: return
	if replay:
		replay_elapsed += delta
		_drive_replay()
	runtime_stepped = false
	if state == "combat":
		var begin := Time.get_ticks_usec()
		arena._process(delta)
		runtime_stepped = true
		step_samples.append(Time.get_ticks_usec() - begin)
		# The inherited training-oriented arena clamps displayed health to 1.
		# Count its real damage instead; loss is checked before UI completion and
		# _on_stage_completed rejects the same lethal frame as well.
		if float(arena.metrics.get("damage_taken", 0.0)) >= 100.0:
			state = "defeated"
			arena.stop()
			_show_outcome("试炼未完成", "看清预告，离开危险区，再抓住收招空隙。")
	frame_count += 1
	_refresh_ui()
	if replay: _observe_replay()
	if smoke and not smoke_started:
		smoke_elapsed += delta
		if smoke_elapsed >= 0.6:
			smoke_started = true
			_capture_normal_smoke()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey: return
	key_events_received += 1
	var key := hotkey_from_event(event as InputEventKey)
	if key == KEY_NONE or arena == null: return
	hotkey_presses_received += 1
	print("ART_SLICE_HOTKEY ", key, " frame=", frame_count)
	_handle_key(key)
	get_viewport().set_input_as_handled()


static func hotkey_from_event(event: InputEventKey) -> int:
	if not event.pressed or event.echo: return KEY_NONE
	var key := event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	if key in [KEY_N, KEY_R, KEY_ESCAPE, KEY_F8, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5]: return key
	return KEY_NONE


func _capture_normal_smoke() -> void:
	# No bot inputs: exercise the normal interactive scene and capture its own
	# rendered viewport. This does not certify Windows screen-capture output or
	# desktop keyboard/mouse delivery.
	await RenderingServer.frame_post_draw
	var root := get_tree().root
	var image := root.get_texture().get_image()
	var path := evidence_dir.path_join("normal-first-frame.png")
	var saved := image.save_png(ProjectSettings.globalize_path(path)) == OK
	var sampled_colors := {}
	for y: int in range(0, image.get_height(), 24):
		for x: int in range(0, image.get_width(), 24):
			sampled_colors[image.get_pixel(x, y).to_html()] = true
	var report := {
		"mode": "normal_scene_first_frame_smoke", "automated_gameplay_inputs": false,
		"desktop_manual_input_verified": false, "windows_capture_verified": false,
		"replay": replay, "scene_state": state, "session_frames": frame_count,
		"arena_elapsed": arena.stage_elapsed, "window_visible": root.visible,
		"window_has_focus": root.has_focus(), "window_mode": root.mode,
		"render_display_server": DisplayServer.get_name(), "viewport_size": image.get_size(),
		"sampled_color_count": sampled_colors.size(), "saved": saved,
		"key_events_received": key_events_received, "hotkey_presses_received": hotkey_presses_received,
		"screenshot": ProjectSettings.globalize_path(path),
	}
	var file := FileAccess.open(evidence_dir.path_join("normal-smoke.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("ART_SLICE_NORMAL_SMOKE_COMPLETE ", JSON.stringify(report))
	get_tree().quit(0 if saved and sampled_colors.size() > 10 else 2)


func _handle_key(key: int) -> void:
	match key:
		KEY_ESCAPE: get_tree().quit()
		KEY_N:
			if not replay: _select(selected + 1)
		KEY_R:
			if not replay: _select(selected)
		KEY_F8:
			if evidence_dir.is_empty(): _create_evidence_dir()
			_capture_once("manual-frame-%06d" % frame_count)
		_:
			if not replay and key >= KEY_1 and key <= KEY_5 and key - KEY_1 < entries.size(): _select(key - KEY_1)


func _on_stage_completed(_stage: String, _metrics: Dictionary) -> void:
	# The production completion signal is the only success route. No countdown,
	# UI selection or replay timer can award a victory.
	if state != "combat" or not arena.enemies.is_empty(): return
	if float(arena.metrics.get("damage_taken", 0.0)) >= 100.0: return
	state = "victory"
	arena.stop()
	_show_outcome("教堂试炼完成", "两名敌人已击败。换件武器，体验不同结构的打法。")


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := Panel.new()
	panel.position = Vector2(20, 18)
	panel.size = Vector2(1240, 82)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style())
	layer.add_child(panel)
	header = _label(Vector2(38, 26), Vector2(770, 32), 22)
	detail = _label(Vector2(38, 62), Vector2(900, 27), 15)
	detail.modulate = Color("b9b4c5")
	right_header = _label(Vector2(895, 28), Vector2(345, 52), 17)
	right_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for item: Label in [header, detail, right_header]: layer.add_child(item)
	for index: int in range(entries.size()):
		var title := str(entries[index].blueprint.display_name)
		if title.length() > 11: title = title.left(10) + "…"
		var button := _button("%d  %s" % [index + 1, title], Vector2(20 + index * 244, 112), Vector2(234, 38))
		button.toggle_mode = true
		button.pressed.connect(func() -> void:
			if not replay: _select(index)
		)
		button.tooltip_text = "%s\n换武器会重开本场；不写入武器库。" % entries[index].blueprint.display_name
		weapon_buttons.append(button)
		layer.add_child(button)
	var enemies_hint := _label(Vector2(34, 162), Vector2(1120, 24), 14)
	enemies_hint.text = "教堂术士：近身横扫 / 落点预告     焚行者：锁向突进 / 远程喷射"
	enemies_hint.modulate = Color("c8b69d")
	layer.add_child(enemies_hint)
	var footer := Panel.new()
	footer.position = Vector2(20, 672)
	footer.size = Vector2(930, 34)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_theme_stylebox_override("panel", _panel_style())
	layer.add_child(footer)
	var instructions := _label(Vector2(34, 677), Vector2(907, 26), 14)
	instructions.text = "WASD / 方向键移动   Space / J 攻击   Shift / K 闪避   N 换武器并重开   R 重开   Esc 退出"
	layer.add_child(instructions)
	attack_button = _button("攻击", Vector2(1112, 652), Vector2(148, 54))
	attack_button.button_down.connect(func() -> void:
		if arena != null and state == "combat" and not replay:
			arena.set_touch_attack(true)
			arena.request_touch_attack()
	)
	attack_button.button_up.connect(func() -> void:
		if arena != null: arena.set_touch_attack(false)
	)
	layer.add_child(attack_button)
	dodge_button = _button("闪避", Vector2(964, 652), Vector2(132, 54))
	dodge_button.pressed.connect(func() -> void:
		if arena != null and state == "combat" and not replay: arena.request_touch_dodge()
	)
	layer.add_child(dodge_button)
	outcome_panel = PanelContainer.new()
	outcome_panel.position = Vector2(320, 232)
	outcome_panel.size = Vector2(640, 238)
	outcome_panel.add_theme_stylebox_override("panel", _panel_style())
	layer.add_child(outcome_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	outcome_panel.add_child(box)
	outcome_title = _label(Vector2.ZERO, Vector2.ZERO, 28)
	outcome_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(outcome_title)
	outcome_detail = _label(Vector2.ZERO, Vector2.ZERO, 16)
	outcome_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outcome_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outcome_detail.custom_minimum_size = Vector2(580, 52)
	box.add_child(outcome_detail)
	var restart := _button("再试一次  ·  R", Vector2.ZERO, Vector2(260, 46))
	restart.custom_minimum_size = Vector2(260, 46)
	restart.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	restart.pressed.connect(func() -> void:
		if not replay: _select(selected)
	)
	box.add_child(restart)
	outcome_panel.hide()


static func _label(position_value: Vector2, size_value: Vector2, font_size: int) -> Label:
	var item := Label.new()
	item.position = position_value
	item.size = size_value
	item.add_theme_font_override("font", FONT)
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", Color("eee6d3"))
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return item


static func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.075, 0.063, 0.11, 0.94)
	style.border_color = Color("78624c")
	style.set_border_width_all(2)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	return style


static func _button(text_value: String, position_value: Vector2, size_value: Vector2) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = position_value
	button.size = size_value
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", Color("eee6d3"))
	var normal := _panel_style()
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	normal.content_margin_left = 9
	normal.content_margin_right = 9
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("342c3e")
	hover.border_color = Color("c39c6a")
	button.add_theme_stylebox_override("hover", hover)
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("47374e")
	pressed.border_color = Color("e2ba79")
	button.add_theme_stylebox_override("pressed", pressed)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color("181420")
	disabled.border_color = Color("514650")
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_disabled_color", Color("aaa0ac"))
	return button


func _refresh_ui() -> void:
	if arena == null or entries.is_empty(): return
	var hp := maxf(0.0, 100.0 - float(arena.metrics.get("damage_taken", 0.0)))
	var name_text := str(entries[selected].blueprint.display_name)
	header.text = "生命 %03d   ·   %s" % [ceili(hp), name_text]
	var ammo := "弹匣 %d/%d" % [arena.ammo_in_magazine, int(arena.ranged_runtime_profile.get("magazine_size", 0))] if arena._uses_firearm_runtime() else "点按三段动作 · 长按结构能力"
	var source := "开发鱼竿样本" if str(entries[selected].get("art_sample_source", "")).begins_with("explicit_builtin") else "已验收的本地缓存武器"
	detail.text = "%s   |   %s" % [ammo, source]
	right_header.text = "%s\n敌人 %d / 2" % ["自动输入回放 · 非手动试玩" if replay else "教堂试炼 · 离线同屏样板", arena.enemies.size()]
	attack_button.text = "射击" if arena._uses_firearm_runtime() else "攻击 / 长按"
	attack_button.disabled = state != "combat" or replay
	dodge_button.disabled = state != "combat" or replay


func _show_outcome(title: String, body: String) -> void:
	outcome_title.text = title
	outcome_detail.text = body + "\nR 重开本场 · N 换武器并重开"
	outcome_panel.show()


func _show_failure(title: String, body: String) -> void:
	state = "error"
	_show_outcome(title, body)
	printerr("ART_SLICE_ERROR ", title, " ", diagnostics)


func _drive_replay() -> void:
	if state != "combat":
		arena.set_touch_vector(Vector2.ZERO)
		arena.set_touch_attack(false)
		return
	# Initial left/right and walking samples are produced by movement inputs,
	# not by forcing a pose or skipping an enemy state.
	if replay_elapsed < 0.28:
		arena.set_touch_vector(Vector2.ZERO)
		return
	if replay_elapsed < 0.48:
		arena.set_touch_vector(Vector2.LEFT)
		return
	if replay_elapsed < 0.75:
		arena.set_touch_vector(Vector2.ZERO)
		return
	if replay_elapsed < 1.35:
		arena.set_touch_vector(Vector2.RIGHT)
		return
	if replay_elapsed < 3.2:
		arena.set_touch_vector(Vector2.ZERO)
		return
	if arena.enemies.is_empty(): return
	var nearest: Dictionary = arena.enemies[0]
	for enemy: Dictionary in arena.enemies:
		if arena.player_position.distance_squared_to(enemy.pos) < arena.player_position.distance_squared_to(nearest.pos): nearest = enemy
	var offset := Vector2(nearest.pos) - arena.player_position
	var firearm := arena._uses_firearm_runtime()
	var reach := 260.0 if firearm else 76.0
	var movement := Vector2.ZERO
	if absf(offset.y) > 12.0: movement.y = signf(offset.y)
	if absf(offset.x) > reach: movement.x = signf(offset.x)
	elif absf(offset.x) < reach * 0.62 and firearm: movement.x = -signf(offset.x)
	elif arena.facing != signf(offset.x): movement.x = signf(offset.x) * 0.12
	var danger := str(nearest.get("attack_phase", "")) in ["telegraph", "active"] and offset.length() < 200.0
	if danger and replay_elapsed - replay_dodge_at > 1.4:
		movement.y = 1.0 if arena.player_position.y < 480.0 else -1.0
		arena.request_touch_dodge()
		replay_dodge_at = replay_elapsed
	arena.set_touch_vector(movement)
	if firearm:
		var aligned := absf(offset.y) < 30.0 and absf(offset.x) < 560.0
		arena.set_touch_attack(replay_trigger_down(arena.ranged_runtime_profile, replay_elapsed, aligned))
	else:
		# Show the declared structure ability before normal strikes can defeat
		# the encounter; this still uses the ordinary held attack input.
		var ability_window := replay_elapsed > 3.2 and replay_elapsed < 5.5
		arena.set_touch_attack(ability_window)
		if not ability_window and not arena.melee_runtime.busy() and offset.length() < 155.0:
			arena.request_touch_attack()


static func replay_trigger_down(profile: Dictionary, elapsed: float, aligned: bool) -> bool:
	if not aligned: return false
	if bool(profile.get("automatic_fire", false)): return true
	# Semi-auto and burst mechanisms require distinct press/release edges.
	# This is a bot input schedule, not a direct call to the firing implementation.
	var interval := maxf(0.16, float(profile.get("shot_interval_seconds", 0.18)) + 0.10)
	return fmod(elapsed, interval) < 0.09


func _observe_replay() -> void:
	var prefix := "%02d" % (selected + 1)
	if replay_elapsed > 0.12 and replay_elapsed < 0.28: _capture_once(prefix + "-idle-right")
	if replay_elapsed > 0.55 and replay_elapsed < 0.75: _capture_once(prefix + "-idle-left")
	if replay_elapsed > 0.95 and replay_elapsed < 1.30: _capture_once(prefix + "-walking")
	if arena.muzzle_flash_timer > 0.0:
		action_observations["gun_firing"] = true
		_capture_once(prefix + "-gun-firing")
	if arena.melee_runtime.active():
		action_observations["melee_" + str(arena.melee_runtime.controller.attack_kind)] = true
		_capture_once(prefix + "-melee-" + str(arena.melee_runtime.controller.attack_kind))
	for enemy: Dictionary in arena.enemies:
		if not runtime_stepped: continue
		var phase := str(enemy.get("attack_phase", "idle"))
		var key := str(enemy.get("blueprint_id", "unknown")) + "-" + phase
		phase_observations[key] = int(phase_observations.get(key, 0)) + 1
		if phase in ["telegraph", "active"]: _capture_once(prefix + "-enemy-" + key)
	if state in ["victory", "defeated"]: _capture_once(prefix + "-" + state)
	if replay_elapsed < REPLAY_SECONDS or capture_pending > 0: return
	# Let the real 0.9-second completion delay finish if the last enemy was
	# defeated right at the capture deadline; never force a completed state.
	if state == "combat" and arena.enemies.is_empty() and replay_elapsed < REPLAY_SECONDS + 1.2: return
	step_samples.sort()
	var coverage := _entry_coverage(prefix)
	replay_results.append({
		"identity": entries[selected].blueprint.display_name,
		"weapon_source": entries[selected].get("art_sample_source", ""),
		"result": state,
		"elapsed_seconds": replay_elapsed,
		"metrics": arena.metrics.duplicate(true),
		"enemy_phase_observations": phase_observations.duplicate(true),
		"action_observations": action_observations.duplicate(true),
		"coverage": coverage,
		"runtime_error": arena.melee_runtime.error,
		"remaining_enemies": arena.enemies.map(func(enemy: Dictionary) -> Dictionary: return {"id": enemy.get("blueprint_id", ""), "hp": enemy.get("hp", 0), "phase": enemy.get("attack_phase", ""), "position": enemy.get("pos", Vector2.ZERO)}),
		"arena_step_p95_usec": step_samples[int(step_samples.size() * 0.95)] if not step_samples.is_empty() else 0,
		"arena_step_max_usec": step_samples.back() if not step_samples.is_empty() else 0,
	})
	if selected + 1 < entries.size():
		_select(selected + 1)
	else:
		var complete := true
		for result: Dictionary in replay_results:
			complete = complete and bool(result.coverage.complete) and str(result.runtime_error).is_empty()
		var report := {"schema": "forge-church-art-replay-v1", "real_godot_render": DisplayServer.get_name() != "headless", "desktop_manual_input": false, "online_calls": false, "saved_library_written": false, "required_render_coverage_complete": complete, "results": replay_results, "screenshots": captured, "diagnostics": diagnostics}
		var file := FileAccess.open(evidence_dir.path_join("replay.json"), FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify(report, "\t")); file.close()
		print("ART_SLICE_REPLAY_COMPLETE ", ProjectSettings.globalize_path(evidence_dir.path_join("replay.json")))
		print("ART_SLICE_RENDER_COVERAGE ", "COMPLETE" if complete else "INCOMPLETE: inspect replay.json; process exit does not certify coverage or victories")
		get_tree().quit(0 if complete else 2)


func _entry_coverage(prefix: String) -> Dictionary:
	var missing: Array[String] = []
	for suffix: String in ["idle-right", "idle-left", "walking"]:
		if not bool((captured.get(prefix + "-" + suffix, {}) as Dictionary).get("saved", false)): missing.append(suffix)
	if arena._uses_firearm_runtime():
		if not bool(action_observations.get("gun_firing", false)): missing.append("gun_firing")
	else:
		if not bool(action_observations.get("melee_normal", false)): missing.append("normal_melee_active")
	for enemy_id: String in ["ember_priest", "mechanical_spider"]:
		for phase: String in ["telegraph", "active"]:
			if int(phase_observations.get(enemy_id + "-" + phase, 0)) == 0: missing.append(enemy_id + "-" + phase)
	return {"complete": missing.is_empty(), "missing": missing, "not_a_victory_or_manual_play_certification": true}


func _create_evidence_dir() -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "")
	evidence_dir = EVIDENCE_ROOT.path_join("%s-%d-%d" % [stamp, OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_dir))


func _capture_once(key: String) -> void:
	if captured.has(key) or DisplayServer.get_name() == "headless": return
	captured[key] = {"requested_at_frame": frame_count, "elapsed_seconds": replay_elapsed, "saved": false}
	capture_pending += 1
	await RenderingServer.frame_post_draw
	var path := evidence_dir.path_join(key + ".png")
	var code := get_tree().root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	captured[key]["saved"] = code == OK
	captured[key]["path"] = ProjectSettings.globalize_path(path)
	capture_pending -= 1
	if code != OK: printerr("ART_SLICE_CAPTURE_FAILED ", code, " ", path)
