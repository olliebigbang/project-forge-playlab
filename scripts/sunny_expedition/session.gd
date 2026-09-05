extends "res://scripts/art_vertical_slice_v1/church_expedition.gd"
const SUNNY_ARENA := preload("res://scripts/sunny_expedition/arena.gd")
const SUNNY_RULES := preload("res://scripts/sunny_expedition/rules.gd")
const SUNNY_STYLE := preload("res://scripts/sunny_expedition/ui_style.gd")
const MECHANISM_UPGRADES := preload("res://scripts/sunny_expedition/mechanism_upgrade_system.gd")
const META_PROGRESSION := preload("res://scripts/sunny_expedition/meta_progression.gd")
const STORY := preload("res://scripts/sunny_expedition/story_content.gd")
var pending_upgrade_choices: Array[Dictionary] = []
var meta_progression: Dictionary = {}
var meta_progress_label: Label
var upgrade_reroll_button: Button
var trial_run_button: Button
var quest_status_label: Label
var build_status_label: Label
var run_mode := STORY.MODE_STORY
var story_route := "brook"
var story_carry: Dictionary = {}

func _init() -> void:
	expedition_rules = SUNNY_RULES
	campaign_title = "晴日远行"
	campaign_enter_text = "出发"
	campaign_result_text = "第一章完成 · 被忘掉的送货单"
	campaign_chapter_count = STORY.STORY_CHAPTER_COUNT
	campaign_scope_text = "把任意物品编译成武器，追查正在抹去物品名字的忘潮"
	campaign_empty_history_text = STORY.QUEST_TITLE + " · 正式远征三段；试铸场可用8只怪快速验武器。"
	presentation_style_id = "sunny_v1"
	forge_title = "晴日造物"
	forge_destination = "晴日关卡"
	shelf_catalog.style_id = presentation_style_id
	campaign_store.directory = WEAPON_STORE.new().root_path.path_join("sunny-expedition-v1")
	arena_factory = func() -> GameplayArena: return SUNNY_ARENA.new()

func _ready() -> void:
	super._ready()
	var checkpoint: Dictionary = campaign.get("checkpoint", {})
	_configure_run_mode(str(checkpoint.get("run_mode", STORY.MODE_TRIAL if not checkpoint.is_empty() else STORY.MODE_STORY)))
	story_route = STORY.normalize_route(checkpoint.get("story_route", "brook"))
	meta_progression = META_PROGRESSION.normalize(campaign.get("meta_progression", {}))
	campaign["meta_progression"] = meta_progression.duplicate(true)
	arena.configure_meta_progression(META_PROGRESSION.runtime_context(meta_progression))
	if not arena.upgrade_requested.is_connected(_on_upgrade_requested):
		arena.upgrade_requested.connect(_on_upgrade_requested)
	# The parent scene wires these buttons while its script is constructing the UI.
	# Give the Sunny flow its own explicit handlers so route-choice clicks cannot
	# fall through to the parent briefing/camp actions.
	_replace_dialog_handler(dialog_primary, Callable(self, "_sunny_dialog_primary"))
	_replace_dialog_handler(dialog_secondary, Callable(self, "_sunny_dialog_secondary"))
	_replace_dialog_handler(dialog_tertiary, Callable(self, "_sunny_dialog_tertiary"))
	var footer := _panel(hub_page, Rect2(20, 666, 1240, 43))
	hub_page.move_child(footer, hub_history.get_index())
	# Meta progression is a primary hub state, not a tiny footer annotation.
	# Keep it beside the title and expose the next unlock as a tooltip.
	_panel(hub_page, Rect2(700, 30, 298, 42))
	meta_progress_label = _text(hub_page, "", Vector2(712, 36), Vector2(274, 30), 16)
	meta_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta_progress_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	quest_status_label = _text(hub_page, "", Vector2(658, 177), Vector2(570, 27), 14)
	quest_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	new_run_button.position = Vector2(658, 540)
	new_run_button.size = Vector2(180, 52)
	new_run_button.text = "故事远征"
	resume_run_button.position = Vector2(1040, 540)
	resume_run_button.size = Vector2(193, 52)
	trial_run_button = _button(hub_page, "试铸场 · 8怪", Rect2(849, 540, 180, 52))
	trial_run_button.pressed.connect(start_trial_run)
	var build_panel := _panel(run_page, Rect2(20, 132, 1240, 34))
	run_page.move_child(build_panel, 0)
	build_status_label = _text(run_page, "", Vector2(39, 137), Vector2(1200, 25), 14)
	upgrade_reroll_button = _button(dialog_page, "重铸候选 · R", Rect2(806, 197, 176, 44))
	upgrade_reroll_button.visible = false
	upgrade_reroll_button.pressed.connect(reroll_upgrade_choices)
	SUNNY_STYLE.apply(self)
	health_bar.tint = Color("bf6547"); health_bar.track_color = Color("b6cad1")
	run_progress.tint = Color("648a63"); run_progress.track_color = Color("d8d281")
	# World and UI remain readable at the supported aspect without clipping.
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	_refresh_ui()


func _replace_dialog_handler(button: Button, handler: Callable) -> void:
	for connection: Dictionary in button.get_signal_connection_list(&"pressed"):
		var connected_callable: Callable = connection.get("callable", Callable())
		if connected_callable.is_valid():
			button.pressed.disconnect(connected_callable)
	for connection: Dictionary in button.get_signal_connection_list(&"button_down"):
		var connected_callable: Callable = connection.get("callable", Callable())
		if connected_callable.is_valid():
			button.button_down.disconnect(connected_callable)
	# Godot can lose the release-side `pressed` notification when this dialog is
	# replaced in the same input cycle. Triggering on button_down keeps all three
	# route cards reliable and still provides the normal hover/pressed feedback.
	button.button_down.connect(handler)


func _configure_run_mode(value: String) -> void:
	run_mode = STORY.normalize_mode(value)
	if run_mode == STORY.MODE_STORY:
		campaign_chapter_count = STORY.STORY_CHAPTER_COUNT
		campaign_result_text = "第一章完成 · 被忘掉的送货单"
	else:
		campaign_chapter_count = STORY.TRIAL_CHAPTER_COUNT
		campaign_result_text = "试铸完成 · 武器机制已记录"


func start_new_run(seed_value: int = -1) -> Dictionary:
	return start_story_run(seed_value)


func start_story_run(seed_value: int = -1) -> Dictionary:
	_configure_run_mode(STORY.MODE_STORY)
	story_route = "brook"
	story_carry = {}
	var result := super.start_new_run(seed_value)
	if result.get("ok", false):
		flow = "route_choice"
		_checkpoint()
		_refresh_ui()
	return result


func start_trial_run(seed_value: int = -1) -> Dictionary:
	_configure_run_mode(STORY.MODE_TRIAL)
	story_route = "brook"
	story_carry = {}
	var result := super.start_new_run(seed_value)
	if result.get("ok", false):
		flow = "briefing"
		_checkpoint()
		_refresh_ui()
	return result


func continue_run() -> Dictionary:
	var saved_campaign: Dictionary = campaign_store.read_state()
	var point: Dictionary = saved_campaign.get("checkpoint", {})
	_configure_run_mode(str(point.get("run_mode", STORY.MODE_TRIAL)))
	story_route = STORY.normalize_route(point.get("story_route", "brook"))
	story_carry = (point.get("story_carry", {}) as Dictionary).duplicate(true)
	return super.continue_run()


func _checkpoint() -> Dictionary:
	var candidate := campaign.duplicate(true)
	candidate["checkpoint"] = {
		"chapter": run_chapter,
		"seed": run_seed,
		"health": run_health,
		"supplies": run_supplies,
		"weapon_key": str(entry.get("library_key", "")),
		"metrics": totals.duplicate(true),
		"run_mode": run_mode,
		"story_route": story_route,
		"story_carry": story_carry.duplicate(true),
	}
	var result: Dictionary = campaign_store.write_state(candidate)
	if result.get("ok", false):
		campaign = candidate
		run_error = ""
	return result


func choose_story_route(route_id: String) -> Dictionary:
	if run_mode != STORY.MODE_STORY or flow not in ["route_choice", "camp"]:
		return {"ok": false, "error": "STORY_ROUTE_CHOICE_NOT_OPEN"}
	story_route = STORY.normalize_route(route_id)
	flow = "briefing"
	var saved := _checkpoint()
	_refresh_ui()
	return saved


func begin_chapter() -> Dictionary:
	meta_progression = META_PROGRESSION.normalize(campaign.get("meta_progression", meta_progression))
	arena.configure_meta_progression(META_PROGRESSION.runtime_context(meta_progression))
	arena.configure_journey(run_mode, story_route, story_carry)
	return super.begin_chapter()


func _chapter_finished(metrics: Dictionary) -> void:
	var enriched := metrics.duplicate(true)
	if run_mode == STORY.MODE_STORY and flow == "combat":
		story_carry = arena.export_journey_carry()
	if flow == "combat" and run_chapter + 1 >= campaign_chapter_count:
		var outcome := META_PROGRESSION.record_completion(meta_progression, entry.get("blueprint") as WeaponBlueprint)
		meta_progression = (outcome.get("progression", {}) as Dictionary).duplicate(true)
		campaign["meta_progression"] = meta_progression.duplicate(true)
		enriched["meta_reward"] = (outcome.get("reward", {}) as Dictionary).duplicate(true)
	super._chapter_finished(enriched)
	if run_mode == STORY.MODE_STORY and flow == "camp":
		flow = "route_choice"
		_refresh_ui()

func _rebuild_shelf() -> void:
	super._rebuild_shelf()
	if shelf_box != null: SUNNY_STYLE.apply(shelf_box)

func _refresh_ui() -> void:
	super._refresh_ui()
	if run_page == null: return
	if flow == "route_choice":
		hub_page.visible = false
		run_page.visible = false
		dialog_page.visible = true
		_refresh_story_route_dialog()
	if meta_progress_label != null:
		meta_progress_label.visible = flow == "hub"
		meta_progress_label.text = META_PROGRESSION.short_summary(meta_progression)
		meta_progress_label.tooltip_text = "完整通关后结算。" + META_PROGRESSION.next_milestone_text(meta_progression)
	if quest_status_label != null:
		quest_status_label.visible = flow == "hub"
		quest_status_label.text = STORY.QUEST_TITLE + " · " + ("当前存档：%s" % ("正式远征" if run_mode == STORY.MODE_STORY else "试铸场") if not campaign.get("checkpoint", {}).is_empty() else "等待出发")
		quest_status_label.tooltip_text = STORY.QUEST_SUMMARY
	if trial_run_button != null:
		trial_run_button.visible = flow == "hub"
		trial_run_button.disabled = entry.is_empty() or state == "generating"
	if flow == "hub":
		new_run_button.text = "故事远征 · 第一章"
		resume_run_button.text = "带所选武器继续" if camp_return else ("继续正式远征" if run_mode == STORY.MODE_STORY and not campaign.get("checkpoint", {}).is_empty() else ("继续试铸" if not campaign.get("checkpoint", {}).is_empty() else "没有中断进度"))
	if build_status_label != null:
		build_status_label.visible = flow in ["combat", "upgrade", "paused", "defeated", "camp", "result", "route_choice"]
		var build_names: Array[String] = []
		for upgrade: Dictionary in arena.upgrade_history:
			build_names.append(str(upgrade.get("title", "强化")))
		var mode_label := "正式远征 · %s" % STORY.route_label(story_route) if run_mode == STORY.MODE_STORY else "试铸场 · 8怪快速验证"
		build_status_label.text = "%s     本段构筑：%s" % [mode_label, " → ".join(build_names) if not build_names.is_empty() else "尚未选择"]
	if upgrade_reroll_button != null:
		upgrade_reroll_button.visible = flow == "upgrade"
		dialog_title.size.x = 495 if flow == "upgrade" else 680
	if flow == "upgrade":
		hub_page.visible = false
		run_page.visible = true
		dialog_page.visible = true
		run_header.text = "%s     生命 %d     路标 %d/%d · 100%%     锻材 %d · 核心 %d     %s" % [expedition_rules.CHAPTERS[clampi(run_chapter, 0, expedition_rules.CHAPTERS.size() - 1)], int(arena.player_health), arena.seal_index + 1, expedition_rules.SEAL_COUNT, arena.forge_materials, arena.structure_cores.size(), _clock(arena.chapter_clock)]
		run_hint.text = "路标已经稳固 · 选择强化后前方道路才会开放"
		run_progress.value = 100
		_refresh_upgrade_dialog()
	run_header.text = run_header.text.replace("阵眼", "路标")
	run_hint.text = run_hint.text.replace("阵眼", "路标")
	dialog_body.text = dialog_body.text.replace("阵眼", "路标")
	if flow in ["combat", "paused", "defeated"]:
		run_header.text += "     锻材 %d · 核心 %d" % [arena.forge_materials, arena.structure_cores.size()]
	if flow == "forge":
		status_title.add_theme_color_override("font_color", Color("943f4b") if state == "failed" else Color("20383b"))
		status_detail.add_theme_color_override("font_color", Color("314b45"))


func _refresh_dialog() -> void:
	if flow == "route_choice":
		_refresh_story_route_dialog()
		return
	if flow == "upgrade":
		_refresh_upgrade_dialog()
		return
	dialog_body.add_theme_font_size_override("font_size", 19)
	dialog_title.size.x = 680
	super._refresh_dialog()
	if flow == "briefing":
		dialog_body.add_theme_font_size_override("font_size", 16)
		var meta_context := META_PROGRESSION.runtime_context(meta_progression)
		var advanced_text := " · 进阶模块已入池" if bool(meta_context.advanced_modules_unlocked) else ""
		var weapon_name := str(entry.blueprint.display_name)
		if weapon_name.length() > 30: weapon_name = weapon_name.left(30) + "…"
		if run_mode == STORY.MODE_STORY:
			dialog_title.text = "第 %d / %d 段 · %s" % [run_chapter + 1, campaign_chapter_count, STORY.CHAPTERS[run_chapter]]
			dialog_body.text = STORY.briefing(run_chapter, story_route, weapon_name) + "\n工坊见闻 %d · 可重铸%d次%s" % [int(meta_progression.insight), int(meta_context.rerolls_per_run), advanced_text]
		else:
			dialog_title.text = "试铸场 · 8只怪"
			dialog_body.text = "一路向右打开 %d 段路障；全程8只怪（含守门者），前三段清场后三选一。\n普通怪回收锻材，金色精英掉结构核心；每次强化消耗3份锻材。\n弹簧菇可推开，毒雾菇可打断，风幽灵逼迫换路，荆棘守望者需破防。\n工坊见闻 %d · 本局可重铸候选 %d 次%s\nQ补给恢复35生命；Esc暂停。 当前武器：%s" % [expedition_rules.SEAL_COUNT, int(meta_progression.insight), int(meta_context.rerolls_per_run), advanced_text, weapon_name]
	elif flow == "result":
		dialog_body.add_theme_font_size_override("font_size", 15)
		dialog_tertiary.text = "返回武器库"
		dialog_primary.text = "再试一次 · R" if run_mode == STORY.MODE_TRIAL else "新的故事远征 · R"
		var result_weapon := str(entry.blueprint.display_name)
		if result_weapon.length() > 34: result_weapon = result_weapon.left(34) + "…"
		var result_lines: Array[String] = [
			"战斗用时 %s · 击败 %d 个敌人" % [_clock(float(totals.get("elapsed_seconds", 0))), int(totals.get("defeated", 0))],
			"受伤 %.0f · 闪避 %d · 补给 %d · 重铸 %d" % [float(totals.get("damage_taken", 0)), int(totals.get("dodge_count", 0)), int(totals.get("heals_used", 0)), int(totals.get("upgrade_rerolls_used", 0))],
			_reaction_summary(),
			"终局武器：" + result_weapon,
		]
		var upgrades: Array = totals.get("upgrades", arena.upgrade_history)
		var upgrade_names: Array[String] = []
		if not upgrades.is_empty():
			for upgrade: Dictionary in upgrades:
				upgrade_names.append(str(upgrade.get("title", "强化")))
			result_lines.append("本局构筑：" + " → ".join(upgrade_names))
		result_lines.append("资源：锻材 %d / 投入 %d · 核心 %d / 灌注 %d" % [int(totals.get("forge_materials_collected", 0)), int(totals.get("forge_materials_spent", 0)), int(totals.get("structure_cores_collected", 0)), int(totals.get("structure_cores_used", 0))])
		var reward: Dictionary = totals.get("meta_reward", {})
		if not reward.is_empty():
			result_lines.append("见闻 +%d · %s%s · 当前 %d" % [int(reward.get("insight_earned", 0)), str(reward.get("family_label", "机制结构")), "（新掌握）" if bool(reward.get("new_family", false)) else "", int(reward.get("total_insight", 0))])
			var unlocked: Array = reward.get("new_unlocks", [])
			if not unlocked.is_empty():
				var labels: Array[String] = []
				for unlock_id: String in unlocked: labels.append(META_PROGRESSION.unlock_label(unlock_id))
				result_lines.append("新解锁：" + "、".join(labels) + " · " + META_PROGRESSION.next_milestone_text(meta_progression))
			else:
				result_lines.append(META_PROGRESSION.next_milestone_text(meta_progression))
		if not run_error.is_empty(): result_lines.append(run_error)
		if run_mode == STORY.MODE_STORY:
			dialog_body.add_theme_font_size_override("font_size", 14)
			var story_result: Array[String] = [
				STORY.ending(result_weapon),
				result_lines[0],
				result_lines[1],
			]
			if not upgrades.is_empty(): story_result.append("本次构筑：" + " → ".join(upgrade_names))
			if not reward.is_empty(): story_result.append("工坊见闻 +%d · 当前 %d" % [int(reward.get("insight_earned", 0)), int(reward.get("total_insight", 0))])
			result_lines = story_result
		dialog_body.text = "\n".join(result_lines)


func _refresh_story_route_dialog() -> void:
	if dialog_page == null: return
	dialog_title.size.x = 680
	dialog_body.add_theme_font_size_override("font_size", 17)
	dialog_title.text = STORY.QUEST_TITLE if run_chapter == 0 else "第 %d 段完成 · 路线抉择" % run_chapter
	dialog_body.text = STORY.prologue() if run_chapter == 0 else STORY.interlude(run_chapter - 1)
	var route_ids := STORY.route_ids()
	var buttons: Array[Button] = [dialog_primary, dialog_secondary, dialog_tertiary]
	for index: int in range(buttons.size()):
		var route_data := STORY.route(route_ids[index])
		buttons[index].visible = true
		buttons[index].text = str(route_data.title)
		buttons[index].tooltip_text = str(route_data.effect)
	if upgrade_reroll_button != null: upgrade_reroll_button.visible = false


func _on_upgrade_requested(choices: Array) -> void:
	pending_upgrade_choices.clear()
	for choice: Dictionary in choices:
		pending_upgrade_choices.append(choice.duplicate(true))
	arena.set_touch_attack(false)
	arena.set_touch_vector(Vector2.ZERO)
	flow = "upgrade"
	state = "combat"
	last_hud = ""
	_refresh_ui()


func choose_upgrade(choice_index: int) -> Dictionary:
	if flow != "upgrade":
		return {"ok": false, "error": "UPGRADE_CHOICE_NOT_OPEN"}
	var result: Dictionary = arena.apply_pending_upgrade(choice_index)
	if not result.get("ok", false):
		run_error = str(result.get("error", "强化未能应用"))
		_refresh_ui()
		return result
	pending_upgrade_choices.clear()
	flow = "combat"
	state = "combat"
	last_hud = ""
	_refresh_ui()
	return result


func reroll_upgrade_choices() -> Dictionary:
	if flow != "upgrade":
		return {"ok": false, "error": "UPGRADE_CHOICE_NOT_OPEN"}
	var result: Dictionary = arena.reroll_pending_upgrade()
	if not result.get("ok", false):
		run_error = "没有可用的重铸次数。" if str(result.get("error", "")) == "NO_UPGRADE_REROLLS_REMAINING" else str(result.get("error", "重铸失败"))
		_refresh_ui()
	else:
		run_error = ""
	return result


func _refresh_upgrade_dialog() -> void:
	if dialog_page == null or pending_upgrade_choices.size() != 3:
		return
	dialog_title.text = "第 %d 个路标稳固 · 选择机制强化" % (arena.seal_index + 1)
	dialog_body.add_theme_font_size_override("font_size", 16)
	var core_text := "无可用核心"
	if not arena.structure_cores.is_empty():
		core_text = "%s可灌注带标记的兼容选项" % MECHANISM_UPGRADES.core_label(arena.structure_cores[0])
	var lines: Array[String] = ["当前锻材 %d · 本次投入 %d · %s" % [arena.forge_materials, int(pending_upgrade_choices[0].get("material_cost", 0)), core_text], "三项由当前武器结构生成，只在本局有效："]
	for index: int in range(3):
		var option: Dictionary = pending_upgrade_choices[index]
		var marker := ("【进阶】" if str(option.get("meta_unlock", "")) == "advanced_modules" else "") + ("【核心灌注】" if bool(option.get("core_infused", false)) else "")
		lines.append("%d. %s%s【%s】— %s" % [index + 1, str(option.title), marker, str(option.category), str(option.detail)])
	dialog_body.text = "\n".join(lines)
	var buttons: Array[Button] = [dialog_primary, dialog_secondary, dialog_tertiary]
	for index: int in range(3):
		var option: Dictionary = pending_upgrade_choices[index]
		buttons[index].visible = true
		buttons[index].text = "%d · %s" % [index + 1, str(option.title)]
		buttons[index].tooltip_text = "%s\n%s\n消耗 %d 锻材" % [str(option.detail), str(option.basis), int(option.get("material_cost", 0))]
	if upgrade_reroll_button != null:
		upgrade_reroll_button.visible = true
		upgrade_reroll_button.text = "重铸候选 · R（%d）" % arena.upgrade_rerolls_remaining
		upgrade_reroll_button.disabled = arena.upgrade_rerolls_remaining <= 0
		upgrade_reroll_button.tooltip_text = "消耗一次本局重铸机会，保留锻材和结构核心。"


func _sunny_dialog_primary() -> void:
	if flow == "route_choice":
		choose_story_route("brook")
		return
	if flow == "result" and run_mode == STORY.MODE_TRIAL:
		start_trial_run()
		return
	if flow == "upgrade":
		choose_upgrade(0)
		return
	super._dialog_primary()


func restart_battle() -> Dictionary:
	if flow == "result" and run_mode == STORY.MODE_TRIAL:
		return start_trial_run()
	return super.restart_battle()


func _sunny_dialog_secondary() -> void:
	if flow == "route_choice":
		choose_story_route("grove")
		return
	if flow == "upgrade":
		choose_upgrade(1)
		return
	super._dialog_secondary()


func _sunny_dialog_tertiary() -> void:
	if flow == "route_choice":
		choose_story_route("ridge")
		return
	if flow == "upgrade":
		choose_upgrade(2)
		return
	return_to_forge()


func _unhandled_key_input(event: InputEvent) -> void:
	if flow == "upgrade" and event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if key in [KEY_1, KEY_2, KEY_3]:
			choose_upgrade(key - KEY_1)
		elif key == KEY_R:
			reroll_upgrade_choices()
		get_viewport().set_input_as_handled()
		return
	super._unhandled_key_input(event)

func _draw() -> void:
	if flow not in ["combat", "upgrade", "paused", "defeated", "camp", "result"]:
		draw_texture_rect(SUNNY_ARENA.SUNNY_BACKGROUNDS[0], Rect2(0, 0, 1280, 720), false, Color(0.7, 0.85, 0.8))

func _smoke_empty_forge() -> void:
	# The campaign starts with a selected shelf item, unlike the old empty
	# Forge scene. Test both real entry pages without invoking AI or saving.
	await RenderingServer.frame_post_draw
	var directory := "res://.tools/sunny-launch/%d-%d" % [int(Time.get_unix_time_from_system()), OS.get_process_id()]
	DirAccess.make_dir_recursive_absolute(directory)
	var ok := flow == "hub" and not entry.is_empty() and service == null
	ok = get_tree().root.get_texture().get_image().save_png(directory.path_join("hub.png")) == OK and ok
	entry.clear(); state = "idle"; input_text = ""; input_field.text = ""; open_forge()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	ok = get_tree().root.get_texture().get_image().save_png(directory.path_join("forge.png")) == OK and ok
	ok = ok and flow == "forge" and state == "idle" and service == null
	print("SUNNY_MAIN_SMOKE ", JSON.stringify({"ok":ok,"online_calls":0,"saved":false,"evidence":ProjectSettings.globalize_path(directory)}))
	get_tree().quit(0 if ok else 2)
