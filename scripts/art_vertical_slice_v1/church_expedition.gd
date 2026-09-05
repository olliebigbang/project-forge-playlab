extends "res://scripts/art_vertical_slice_v1/church_forge.gd"
## Campaign shell. The Church keeps three chapters; themed campaigns may use
## the same save/UI contract for a single continuous level.
const EXP_ARENA := preload("res://scripts/art_vertical_slice_v1/expedition_arena.gd")
const EXP_RULES := preload("res://scripts/art_vertical_slice_v1/expedition_rules.gd")
const EXP_LIBRARY := preload("res://scripts/art_vertical_slice_v1/expedition_library.gd")
const EXP_STORE := preload("res://scripts/art_vertical_slice_v1/expedition_store.gd")
const EXP_METER := preload("res://scripts/art_vertical_slice_v1/expedition_meter.gd")
const WEAPON_STORE := preload("res://scripts/combat_feel/weapon_library_store.gd")
var expedition_rules: Script = EXP_RULES
var campaign_title := "教堂远征"
var campaign_enter_text := "进入教堂"
var campaign_result_text := "三章完成 · 教堂重新亮起"
var campaign_chapter_count := 3
var campaign_scope_text := "带它闯过三章"
var campaign_empty_history_text := "三章：烛光前厅 → 回声长廊 → 最后的圣坛。目标首轮约10–15分钟，因武器与操作而异。"
var flow := "hub"
var shelf: Array[Dictionary] = []
var selected_index := -1
var run_chapter := 0
var run_seed := 0
var run_health := 100.0
var run_supplies := 2
var totals: Dictionary = {}
var run_error := ""
var library_notice := ""
var completed_run := false
var campaign_store: RefCounted = EXP_STORE.new()
var campaign: Dictionary = {}
var include_user_library := true
var shelf_catalog: RefCounted = EXP_LIBRARY.new()
var screen_layer: CanvasLayer
var hub_page: Control
var run_page: Control
var dialog_page: Control
var shelf_box: VBoxContainer
var shelf_scroll: ScrollContainer
var hub_texture: TextureRect
var hub_name: Label
var hub_description: Label
var hub_source: Label
var hub_history: Label
var new_run_button: Button
var resume_run_button: Button
var run_header: Label
var run_hint: Label
var weapon_status: Label
var run_progress: EXP_METER
var health_bar: EXP_METER
var supply_button: Button
var attack_action: Button
var dialog_title: Label
var dialog_body: Label
var dialog_primary: Button
var dialog_secondary: Button
var dialog_tertiary: Button
var forge_home_button: Button
var camp_return := false
var last_hud := ""
var hub_entry_id := 0
var shelf_buttons: Array[Button] = []

func _ready() -> void:
	if not arena_factory.is_valid(): arena_factory = func() -> GameplayArena: return EXP_ARENA.new()
	super._ready()
	get_tree().root.title = "Forge · " + campaign_title
	(arena as Node).chapter_finished.connect(_chapter_finished)
	(arena as Node).expedition_failed.connect(_run_failed)
	campaign = campaign_store.read_state()
	load_shelf()
	_refresh_ui()

func load_shelf() -> void:
	var catalog: RefCounted = shelf_catalog
	shelf = catalog.load_all(include_user_library)
	if not entry.is_empty():
		var found := false
		for candidate: Dictionary in shelf:
			if candidate.get("identity", "") == entry.get("identity", ""): found = true
		if not found:
			entry["shelf_source"] = "本次生成 · 尚未保存" if not saved else "我的已保存武器"
			shelf.push_front(entry)
	_rebuild_shelf()
	if entry.is_empty() and not shelf.is_empty():
		var preferred := 0
		for index: int in range(shelf.size()):
			if shelf[index].get("library_key", "") == campaign.get("selected_key", ""): preferred = index
		select_weapon(preferred, false)
	library_notice = "有 %d 件旧武器未通过当前校验，已跳过；原存档保留。" % catalog.diagnostics.size() if not catalog.diagnostics.is_empty() else ""

func select_weapon(index: int, user_selection: bool = true) -> void:
	if index < 0 or index >= shelf.size() or flow == "combat" or state == "generating": return
	var candidate: Dictionary = shelf[index]
	var checked := validate_entry(candidate, presentation_style_id)
	if not checked.get("ok", false): run_error = str(checked.get("error", "武器校验失败")); return
	entry = candidate.duplicate(true); selected_index = index
	for button_index: int in range(shelf_buttons.size()): shelf_buttons[button_index].set_pressed_no_signal(button_index == index)
	if shelf_scroll != null and index < shelf_buttons.size(): shelf_scroll.call_deferred("ensure_control_visible", shelf_buttons[index])
	if user_selection and not campaign.get("checkpoint", {}).is_empty(): camp_return = true
	saved = not candidate.get("bundled_starter", false) and not str(candidate.get("library_key", "")).is_empty()
	state = "success"; preview_entry_id = 0
	_refresh_ui()

func open_forge() -> void:
	if flow == "combat": return
	flow = "forge"; camp_return = false
	if state != "generating": state = "success" if not entry.is_empty() else "idle"
	_refresh_ui()

func open_hub() -> void:
	if flow == "combat" or state == "generating": return
	flow = "hub"
	state = "success" if not entry.is_empty() else "idle"
	load_shelf(); _refresh_ui()

func accept_generation_result(token: int, response: Dictionary) -> bool:
	var accepted := super.accept_generation_result(token, response)
	if accepted and state == "success":
		entry["shelf_source"] = "本次生成 · 来源见造物页"
		if mechanism_summary != null: mechanism_summary.text = expedition_rules.weapon_help(entry)
	return accepted

func enter_battle() -> Dictionary:
	# Called by the inherited forge button: use exactly this generated weapon.
	flow = "hub"; _refresh_ui()
	return start_new_run()

func _persist_selection() -> Dictionary:
	if entry.is_empty(): return {"ok": false, "error": "请先选择或生成一件武器。"}
	var armory := ARMORY.new()
	var result: Dictionary = armory.save_entry(entry)
	if not result.get("ok", false): return result
	entry["library_key"] = result.library_key
	var equipped: Dictionary = armory.remember_equipped(entry)
	if not equipped.get("ok", false): return equipped
	saved = true
	campaign["selected_key"] = result.library_key
	return {"ok": true}

func start_new_run(seed_value: int = -1) -> Dictionary:
	if flow == "combat" or state == "generating": return {"ok": false, "error": "RUN_BUSY"}
	var selection := _persist_selection()
	if not selection.get("ok", false): run_error = str(selection.get("error", "保存失败")); _refresh_ui(); return selection
	var previous_seed := int(campaign.get("checkpoint", {}).get("seed", run_seed))
	if not campaign.get("history", []).is_empty(): previous_seed = int(campaign.history[0].get("seed", previous_seed))
	run_chapter = 0; run_seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system()) % 10000
	if seed_value < 0 and posmod(run_seed, 4) == posmod(previous_seed, 4): run_seed += 1
	run_health = 100.0; run_supplies = 2; totals = {}; completed_run = false
	var recorded := _checkpoint()
	if not recorded.get("ok", false): run_error = str(recorded.get("error", "保存失败")); return recorded
	flow = "briefing"; _refresh_ui()
	return {"ok": true}

func continue_run() -> Dictionary:
	campaign = campaign_store.read_state()
	var point: Dictionary = campaign.get("checkpoint", {})
	if point.is_empty(): return {"ok": false, "error": "没有可继续的远征。"}
	if int(point.get("chapter", -1)) < 0 or int(point.get("chapter", -1)) >= campaign_chapter_count:
		run_error = "旧版远征进度与当前关卡结构不兼容；武器仍保留，请开始新的远征。"
		_refresh_ui(); return {"ok": false, "error": run_error}
	var loaded: Dictionary = WEAPON_STORE.new().load_entry(str(point.weapon_key))
	if not loaded.get("ok", false) or not validate_entry(loaded, presentation_style_id).get("ok", false):
		run_error = "这次远征的武器未通过存档校验；原文件保留。"
		_refresh_ui(); return {"ok": false, "error": run_error}
	entry = loaded; saved = true; state = "success"; preview_entry_id = 0
	run_chapter = int(point.chapter); run_seed = int(point.seed)
	run_health = float(point.health); run_supplies = int(point.supplies); totals = point.metrics.duplicate(true)
	flow = "briefing"; _refresh_ui(); return {"ok": true}

func begin_chapter() -> Dictionary:
	if flow not in ["briefing", "camp"]: return {"ok": false, "error": "NOT_READY_FOR_CHAPTER"}
	var recorded := _persist_selection()
	if not recorded.get("ok", false): run_error = str(recorded.get("error", "保存失败")); _refresh_ui(); return recorded
	var checkpoint_result := _checkpoint()
	if not checkpoint_result.get("ok", false): run_error = str(checkpoint_result.get("error", "存档失败")); _refresh_ui(); return checkpoint_result
	var result: Dictionary = arena.begin_chapter(run_chapter, run_seed, entry, run_health, run_supplies)
	if result.get("ok", false): flow = "combat"; state = "combat"
	else: run_error = str(result.get("error", "关卡未能开始"))
	_refresh_ui(); return result

func _checkpoint() -> Dictionary:
	var candidate := campaign.duplicate(true)
	candidate["checkpoint"] = {"chapter": run_chapter, "seed": run_seed, "health": run_health, "supplies": run_supplies, "weapon_key": str(entry.get("library_key", "")), "metrics": totals.duplicate(true)}
	var result: Dictionary = campaign_store.write_state(candidate)
	if result.get("ok", false): campaign = candidate; run_error = ""
	return result

func _chapter_finished(metrics: Dictionary) -> void:
	if flow != "combat": return
	for key: String in ["damage_taken", "defeated", "attacks_used", "shots_fired", "dodge_count", "elapsed_seconds", "heals_used", "seal_seconds", "contested_seconds", "interruptions", "melee_hits", "forge_materials_collected", "forge_materials_spent", "structure_cores_collected", "structure_cores_used", "upgrade_rerolls_used"]:
		totals[key] = float(totals.get(key, 0)) + float(metrics.get(key, 0))
	var reactions: Dictionary = totals.get("reactions", {})
	for key: String in metrics.get("reactions", {}): reactions[key] = int(reactions.get(key, 0)) + int(metrics.reactions[key])
	totals["reactions"] = reactions
	# Optional per-run mechanism choices are serializable result evidence. Legacy
	# campaigns omit this field and retain their exact previous save contract.
	if metrics.get("upgrades", null) is Array:
		totals["upgrades"] = (metrics.get("upgrades", []) as Array).duplicate(true)
	if metrics.get("reward_history", null) is Array:
		totals["reward_history"] = (metrics.get("reward_history", []) as Array).duplicate(true)
	if metrics.get("meta_reward", null) is Dictionary:
		totals["meta_reward"] = (metrics.get("meta_reward", {}) as Dictionary).duplicate(true)
	run_health = 100.0
	run_supplies = 2
	run_chapter += 1; state = "success"
	if run_chapter >= campaign_chapter_count:
		completed_run = true; flow = "result"
		var history: Array = campaign.get("history", [])
		history.push_front({"seed": run_seed, "weapon": entry.blueprint.display_name, "metrics": totals.duplicate(true), "health": arena.player_health, "completed": true})
		campaign["history"] = history.slice(0, 10); campaign["checkpoint"] = {}
		var result: Dictionary = campaign_store.write_state(campaign)
		if not result.get("ok", false): run_error = "已通关，但结算未保存。已有武器仍保留。"
	else:
		flow = "camp"
		var result := _checkpoint()
		if not result.get("ok", false): run_error = "休整进度未保存，请重试后再继续。"
	_refresh_ui()

func _run_failed() -> void:
	if flow != "combat": return
	flow = "defeated"; state = "success"; _refresh_ui()

func pause_run() -> void:
	if flow != "combat": return
	arena.set_touch_attack(false); arena.set_touch_vector(Vector2.ZERO)
	flow = "paused"; _refresh_ui()

func resume_combat() -> void:
	if flow != "paused": return
	flow = "combat"; _refresh_ui()

func return_to_forge() -> void:
	if state == "generating": return
	if flow in ["combat", "paused", "defeated"]: arena.stop()
	flow = "hub"; state = "success" if not entry.is_empty() else "idle"
	camp_return = false; load_shelf(); _refresh_ui()

func restart_battle() -> Dictionary:
	if flow not in ["paused", "defeated", "result"]: return {"ok": false, "error": "RETRY_NOT_AVAILABLE"}
	if flow == "result": return start_new_run()
	var restored := continue_run()
	return begin_chapter() if restored.get("ok", false) else restored

func _process(delta: float) -> void:
	if state == "generating":
		elapsed += delta; poll_generation()
	if flow == "combat":
		arena._process(delta)
	_refresh_ui()

func _on_battle_complete(_stage: String, _metrics: Dictionary) -> void:
	pass # expedition owns objective completion; no two-enemy shortcut.

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	var key: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	if key == KEY_ESCAPE:
		if state == "generating": cancel_generation()
		elif flow == "combat": pause_run()
		elif flow == "paused": resume_combat()
		else: return_to_forge()
		get_viewport().set_input_as_handled()
	elif key == KEY_Q and flow == "combat": arena.use_supply(); get_viewport().set_input_as_handled()
	elif key == KEY_R and flow in ["paused", "defeated", "result"]: restart_battle(); get_viewport().set_input_as_handled()

func _build_ui() -> void:
	super._build_ui()
	forge_home_button = _button(forge_page, "武器库 / 远征", Rect2(1020, 38, 215, 46))
	forge_home_button.pressed.connect(open_hub)
	battle_button.text = "保存并开始远征"
	mechanism_summary.text = ""
	screen_layer = CanvasLayer.new(); screen_layer.layer = 2; add_child(screen_layer)
	hub_page = Control.new(); hub_page.size = Vector2(1280, 720); screen_layer.add_child(hub_page)
	_panel(hub_page, Rect2(20, 20, 1240, 90))
	_text(hub_page, campaign_title, Vector2(42, 30), Vector2(530, 40), 30)
	_text(hub_page, "造一件武器，%s。也可以先用已有成品，离线开始。" % campaign_scope_text, Vector2(42, 76), Vector2(960, 24), 17)
	var forge := _button(hub_page, "描述新物品", Rect2(1020, 36, 214, 48)); forge.pressed.connect(open_forge)
	_panel(hub_page, Rect2(20, 126, 595, 532)); _panel(hub_page, Rect2(634, 126, 626, 532))
	_text(hub_page, "我的武器 / 随游戏提供的成品", Vector2(42, 144), Vector2(548, 30), 21)
	var scroll := ScrollContainer.new(); scroll.position = Vector2(38, 189); scroll.size = Vector2(558, 447)
	shelf_scroll = scroll
	hub_page.add_child(scroll); shelf_box = VBoxContainer.new(); shelf_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shelf_box.add_theme_constant_override("separation", 8); scroll.add_child(shelf_box)
	hub_name = _text(hub_page, "选择一件武器", Vector2(658, 146), Vector2(573, 48), 23)
	hub_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hub_name.max_lines_visible = 2
	hub_texture = TextureRect.new(); hub_texture.position = Vector2(786, 205); hub_texture.size = Vector2(300, 170)
	hub_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; hub_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hub_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; hub_page.add_child(hub_texture)
	hub_description = _text(hub_page, "", Vector2(658, 388), Vector2(570, 78), 18); hub_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hub_source = _text(hub_page, "", Vector2(658, 472), Vector2(570, 45), 14); hub_source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	new_run_button = _button(hub_page, "开始新远征", Rect2(658, 540, 277, 52)); new_run_button.pressed.connect(start_new_run)
	resume_run_button = _button(hub_page, "继续上次远征", Rect2(951, 540, 282, 52)); resume_run_button.pressed.connect(continue_run)
	_text(hub_page, "开始会保存当前武器与关卡起点。新远征替换旧进度，不删除武器。", Vector2(658, 606), Vector2(575, 37), 13)
	hub_history = _text(hub_page, "", Vector2(40, 675), Vector2(1195, 27), 15)
	_build_run_ui(); _build_dialog()

func _rebuild_shelf() -> void:
	if shelf_box == null: return
	shelf_buttons.clear()
	var selection_group := ButtonGroup.new()
	for child: Node in shelf_box.get_children(): shelf_box.remove_child(child); child.queue_free()
	for index: int in range(shelf.size()):
		var candidate: Dictionary = shelf[index]
		var row := HBoxContainer.new(); row.custom_minimum_size = Vector2(534, 104); shelf_box.add_child(row)
		var picture := TextureRect.new(); picture.custom_minimum_size = Vector2(96, 96)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; picture.texture = candidate.asset.texture; row.add_child(picture)
		var button := SAMPLE_UI._button(str(candidate.blueprint.display_name), Vector2.ZERO, Vector2(424, 98))
		button.custom_minimum_size = Vector2(424, 98); button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.add_theme_font_size_override("font_size", 17)
		button.toggle_mode = true; button.button_group = selection_group
		button.tooltip_text = str(candidate.blueprint.display_name) + "\n" + str(candidate.get("shelf_source", ""))
		var selected_style := SAMPLE_UI._panel_style(); selected_style.bg_color = Color("40295d"); selected_style.border_color = Color("d0a46d")
		button.add_theme_stylebox_override("pressed", selected_style)
		button.set_pressed_no_signal(not entry.is_empty() and candidate.identity == entry.get("identity", ""))
		shelf_buttons.append(button)
		button.pressed.connect(select_weapon.bind(index)); row.add_child(button)

func _build_run_ui() -> void:
	run_page = Control.new(); run_page.size = Vector2(1280, 720); screen_layer.add_child(run_page)
	_panel(run_page, Rect2(20, 18, 1240, 107))
	run_header = _text(run_page, "", Vector2(40, 27), Vector2(1010, 29), 21)
	run_hint = _text(run_page, "", Vector2(40, 62), Vector2(1000, 27), 17)
	var pause := _button(run_page, "暂停 · Esc", Rect2(1090, 34, 145, 43)); pause.pressed.connect(pause_run)
	_text(run_page, "生命", Vector2(40, 93), Vector2(43, 22), 12)
	_text(run_page, "此阵眼", Vector2(287, 93), Vector2(55, 22), 12)
	health_bar = _progress_bar(Vector2(84, 99), Vector2(176, 8), Color("b15c51")); run_page.add_child(health_bar)
	run_progress = _progress_bar(Vector2(346, 99), Vector2(679, 8), Color("d0a46d")); run_page.add_child(run_progress)
	weapon_status = _text(run_page, "", Vector2(1045, 94), Vector2(189, 25), 13)
	_panel(run_page, Rect2(20, 670, 756, 36)); _text(run_page, "WASD 移动   J / 空格攻击   K / Shift 闪避   Q 补给   Esc 暂停", Vector2(34, 676), Vector2(730, 26), 15)
	supply_button = _button(run_page, "补给 2 · Q", Rect2(797, 652, 143, 54)); supply_button.pressed.connect(func() -> void:
		if flow == "combat": arena.use_supply())
	var dodge := _button(run_page, "闪避", Rect2(954, 652, 133, 54)); dodge.pressed.connect(func() -> void:
		if flow == "combat": arena.request_touch_dodge())
	attack_action = _button(run_page, "攻击 / 长按", Rect2(1101, 652, 157, 54))
	attack_action.button_down.connect(func() -> void:
		if flow == "combat": arena.set_touch_attack(true); arena.request_touch_attack())
	attack_action.button_up.connect(func() -> void: arena.set_touch_attack(false))

func _build_dialog() -> void:
	dialog_page = Control.new(); dialog_page.size = Vector2(1280, 720); screen_layer.add_child(dialog_page)
	var shade := ColorRect.new(); shade.size = Vector2(1280, 720); shade.color = Color(0.03, 0.02, 0.06, 0.72); dialog_page.add_child(shade)
	_panel(dialog_page, Rect2(265, 174, 750, 392))
	dialog_title = _text(dialog_page, "", Vector2(297, 198), Vector2(680, 44), 28)
	dialog_body = _text(dialog_page, "", Vector2(297, 258), Vector2(680, 178), 19); dialog_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog_primary = _button(dialog_page, "继续", Rect2(297, 481, 214, 54)); dialog_primary.pressed.connect(_dialog_primary)
	dialog_secondary = _button(dialog_page, "武器库", Rect2(525, 481, 214, 54)); dialog_secondary.pressed.connect(_dialog_secondary)
	dialog_tertiary = _button(dialog_page, "返回营地", Rect2(753, 481, 229, 54)); dialog_tertiary.pressed.connect(return_to_forge)

func _dialog_primary() -> void:
	match flow:
		"briefing", "camp": begin_chapter()
		"paused": resume_combat()
		"result", "defeated": restart_battle()

func _dialog_secondary() -> void:
	if flow == "paused": restart_battle(); return
	if flow in ["camp", "briefing", "defeated"]: camp_return = true
	flow = "hub"; state = "success"; load_shelf(); _refresh_ui()

func _refresh_ui() -> void:
	if not ui_ready or hub_page == null: return
	if flow == "combat":
		# Simulation still runs every frame. Text, layout and theme setters only
		# run when a visible HUD value changes (or at the 10 Hz clock cadence).
		var hud_signature := str([
			flow, arena.phase, arena.seal_index, roundi(arena.seal_progress * 2.0),
			roundi(arena.player_health * 10.0), arena.supplies,
			int(arena.chapter_clock * 10.0), arena.objective_notice, arena.notice_time > 0,
			arena.ammo_in_magazine, arena.reload_timer > 0, arena.manual_cycle_timer > 0,
			str(arena.melee_runtime.controller.phase), run_error,
		])
		if hud_signature == last_hud: return
		last_hud = hud_signature
	else:
		last_hud = ""
	if flow == "forge":
		super._refresh_ui()
		if not entry.is_empty(): mechanism_summary.text = expedition_rules.weapon_help(entry)
		forge_home_button.disabled = state == "generating"
		battle_button.text = "保存并开始远征"
	else: forge_page.hide(); battle_page.hide()
	hub_page.visible = flow == "hub"
	run_page.visible = flow in ["combat", "paused", "defeated", "camp", "result"]
	dialog_page.visible = flow in ["briefing", "paused", "defeated", "camp", "result"]
	if flow == "hub":
		new_run_button.disabled = entry.is_empty() or state == "generating"
		var checkpoint: Dictionary = campaign.get("checkpoint", {})
		resume_run_button.disabled = checkpoint.is_empty() or int(checkpoint.get("chapter", -1)) < 0 or int(checkpoint.get("chapter", -1)) >= campaign_chapter_count
		resume_run_button.text = "带所选武器继续" if camp_return else "继续上次远征"
		if camp_return:
			# Continue selected camp weapon, not the previously equipped checkpoint.
			if resume_run_button.pressed.is_connected(continue_run): resume_run_button.pressed.disconnect(continue_run)
			if not resume_run_button.pressed.is_connected(_resume_after_selection): resume_run_button.pressed.connect(_resume_after_selection)
		else:
			if resume_run_button.pressed.is_connected(_resume_after_selection): resume_run_button.pressed.disconnect(_resume_after_selection)
			if not resume_run_button.pressed.is_connected(continue_run): resume_run_button.pressed.connect(continue_run)
		if not entry.is_empty():
			hub_name.text = entry.blueprint.display_name
			if hub_entry_id != entry.asset.get_instance_id():
				hub_entry_id = entry.asset.get_instance_id()
				var atlas := AtlasTexture.new(); atlas.atlas = entry.asset.texture; atlas.region = Rect2(entry.asset.opaque_bounds)
				var dimensions := Vector2(entry.asset.opaque_bounds.size)
				var zoom := maxf(1.0, minf(4.0, floorf(minf(560.0 / dimensions.x, 170.0 / dimensions.y))))
				hub_texture.stretch_mode = TextureRect.STRETCH_SCALE; hub_texture.texture = atlas
				hub_texture.size = dimensions * zoom; hub_texture.position = (Vector2(947, 290) - hub_texture.size * 0.5).floor()
			hub_description.text = expedition_rules.weapon_help(entry)
			hub_source.text = str(entry.get("shelf_source", "已校验武器")) + "\n不联网也可战斗；生成新物品才使用 AI。"
		var history: Array = campaign.get("history", [])
		hub_history.text = run_error if not run_error.is_empty() else (library_notice if not library_notice.is_empty() else ("最近记录 %d 次远征 · 上次战斗用时 %s · 换结构或换路线再挑战" % [history.size(), _clock(float(history[0].metrics.get("elapsed_seconds", 0)))] if not history.is_empty() else campaign_empty_history_text))
	if run_page.visible:
		var exp: Node = arena
		var phase_text := "本关完成" if exp.phase == "complete" else ("守门战" if exp.phase == "guardian" else "阵眼 %d/%d · %d%%" % [mini(expedition_rules.SEAL_COUNT, exp.seal_index + 1), expedition_rules.SEAL_COUNT, clampi(roundi(exp.seal_progress / expedition_rules.SEAL_SECONDS * 100.0), 0, 100)])
		var shown_clock: float = float(totals.get("elapsed_seconds", 0)) + (exp.chapter_clock if flow in ["combat", "paused", "defeated"] else 0.0)
		if campaign_chapter_count == 1:
			run_header.text = "%s     生命 %d     %s     %s" % [expedition_rules.CHAPTERS[0], int(arena.player_health), phase_text, _clock(shown_clock)]
		else:
			run_header.text = "第 %d / %d 章 · %s     生命 %d     %s     %s" % [exp.chapter + 1, campaign_chapter_count, expedition_rules.CHAPTERS[exp.chapter], int(arena.player_health), phase_text, _clock(shown_clock)]
		var instruction: String = expedition_rules.LESSONS[clampi(run_chapter, 0, expedition_rules.LESSONS.size() - 1)]
		if exp.phase == "seal": instruction = ("敌人进入阵眼，进度暂停。击退或引开它！" if exp.contested else ("阵眼正在充能，留意红色攻击预警。" if exp.on_seal else "回到金色阵眼内继续充能，离开不会倒退。"))
		if exp.notice_time > 0: instruction = exp.objective_notice
		run_hint.text = instruction
		health_bar.value = arena.player_health
		run_progress.value = 100 if exp.phase in ["guardian", "complete"] else exp.seal_progress / expedition_rules.SEAL_SECONDS * 100
		supply_button.text = "补给 %d · Q" % exp.supplies
		supply_button.disabled = flow != "combat" or exp.supplies <= 0 or arena.player_health >= 100
		attack_action.text = "射击" if arena._uses_firearm_runtime() else "攻击 / 长按"
		if arena._uses_firearm_runtime():
			weapon_status.text = "弹匣 %d/%d%s" % [arena.ammo_in_magazine, int(arena.ranged_runtime_profile.get("magazine_size", 0)), " · 装填中" if arena.reload_timer > 0 else (" · 复位中" if arena.manual_cycle_timer > 0 else "")]
		else:
			weapon_status.text = {"startup": "起手 · 注意预警", "active": "出招", "recovery": "收招", "idle": "就绪"}.get(str(arena.melee_runtime.controller.phase), "就绪")
	if dialog_page.visible: _refresh_dialog()

func _resume_after_selection() -> void:
	var point: Dictionary = campaign_store.read_state().get("checkpoint", {})
	if point.is_empty() or int(point.get("chapter", -1)) < 0 or int(point.get("chapter", -1)) >= campaign_chapter_count: return
	run_chapter = int(point.chapter); run_seed = int(point.seed)
	run_health = float(point.health); run_supplies = int(point.supplies); totals = point.metrics.duplicate(true)
	camp_return = false; flow = "camp"; begin_chapter()

func _refresh_dialog() -> void:
	dialog_secondary.visible = true
	dialog_tertiary.text = "返回营地"
	match flow:
		"briefing":
			dialog_title.text = ("%s · %s" % [campaign_title, expedition_rules.CHAPTERS[0]]) if campaign_chapter_count == 1 else ("第 %d 章 · %s" % [run_chapter + 1, expedition_rules.CHAPTERS[run_chapter]])
			dialog_body.text = "守住 %d 处金色阵眼，再击败守门者。\n站在大圈内充能；敌人靠近中心会阻断进度。\n%s\nQ 使用补给恢复35生命；Esc可随时暂停。\n当前武器：%s" % [expedition_rules.SEAL_COUNT, expedition_rules.LESSONS[clampi(run_chapter, 0, expedition_rules.LESSONS.size() - 1)], entry.blueprint.display_name]
			dialog_primary.text = campaign_enter_text; dialog_secondary.text = "换武器"
		"camp":
			dialog_title.text = "第 %d 章完成 · 休整" % run_chapter
			dialog_body.text = "生命恢复全满，补给补满2份。\n下一章：%s\n%s\n可以保留武器，也可以从武器库换一种结构。\n%s" % [expedition_rules.CHAPTERS[run_chapter], expedition_rules.LESSONS[run_chapter], "进度已保存到下一章起点。" if run_error.is_empty() else ""]
			dialog_primary.text = "继续下一章"; dialog_secondary.text = "换武器"
		"paused":
			dialog_title.text = "已暂停"
			dialog_body.text = "%s\n\n%s\n返回营地后可从本章起点继续；不保存战斗瞬间。" % [entry.blueprint.display_name, expedition_rules.weapon_help(entry)]
			dialog_primary.text = "继续战斗"; dialog_secondary.text = "重试本章"
		"defeated":
			dialog_title.text = "本关未完成" if campaign_chapter_count == 1 else "本章未完成"
			dialog_body.text = "武器没有丢失。\n%s\n可从本关起点重试，也可返回营地选择另一种武器。\n本关受伤 %.0f · 击败 %d 个敌人" % [expedition_rules.LESSONS[clampi(run_chapter, 0, expedition_rules.LESSONS.size() - 1)], float(arena.metrics.get("damage_taken", 0)), int(arena.metrics.get("defeated", 0))]
			dialog_primary.text = "重试本关 · R"; dialog_secondary.text = "查看武器库"
		"result":
			dialog_title.text = campaign_result_text
			dialog_body.text = "战斗用时 %s · 击败 %d 个敌人\n总受伤 %.0f · 闪避 %d 次 · 补给 %d 次\n%s\n终局武器：%s\n再挑战会改变阵眼与增援方向，也可换一种结构。" % [_clock(float(totals.get("elapsed_seconds", 0))), int(totals.get("defeated", 0)), float(totals.get("damage_taken", 0)), int(totals.get("dodge_count", 0)), int(totals.get("heals_used", 0)), _reaction_summary(), entry.blueprint.display_name]
			dialog_primary.text = "新的远征 · R"; dialog_secondary.text = "换武器再来"
	if not run_error.is_empty(): dialog_body.text += "\n" + run_error

static func _clock(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds) / 60, int(seconds) % 60]

func _reaction_summary() -> String:
	var labels := {"entangle": "缠住", "shove": "击退", "pin": "钉住", "cleave": "斩切", "suppress": "压制", "armor_break": "破甲"}
	var reactions: Dictionary = totals.get("reactions", {})
	var ordered: Array = reactions.keys()
	ordered.sort_custom(func(a: String, b: String) -> bool: return int(reactions[a]) > int(reactions[b]))
	var parts: Array[String] = []
	for name: String in ordered:
		if labels.has(name) and parts.size() < 2: parts.append("%s %d次" % [labels[name], int(reactions[name])])
	return "本轮作用：" + " · ".join(parts) if not parts.is_empty() else "本轮作用：命中与位移"

static func _progress_bar(point: Vector2, dimensions: Vector2, color: Color) -> EXP_METER:
	var bar := EXP_METER.new(); bar.position = point; bar.size = dimensions; bar.tint = color
	return bar
