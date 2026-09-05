class_name AutomaticLevelLoop
extends Node2D

const ARENA := preload("res://scripts/systems/gameplay_arena.gd")
const ARMORY := preload("res://scripts/combat_feel/player_weapon_armory.gd")
const AUTOMATIC_ARMORY := preload("res://scripts/combat_feel/automatic_armory_director.gd")
const DIRECTOR := preload("res://scripts/enemy_attack/automatic_encounter_director.gd")
const RANGED_AXIS_RESOLVER := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")
const WEAPON_STRATEGY := preload("res://scripts/combat_feel/weapon_strategy_compiler.gd")
const CAPABILITIES := preload("res://scripts/combat_feel/weapon_capability_catalog.gd")

var arena: GameplayArena
var armory: RefCounted = ARMORY.new()
var automatic_armory: RefCounted = AUTOMATIC_ARMORY.new()
var director: RefCounted = DIRECTOR.new()
var armory_entries: Array[Dictionary] = []
var equipped_entry: Dictionary = {}
var current_encounter: Dictionary = {}
var state := "boot"
var intermission_seconds := 0.0
var automatic_armory_attempted := false
var automatic_armory_message := ""
var pending_armory_reward: Dictionary = {}
var reward_claim_ready := false
var run_health := 100.0
var encounter_start_health := 100.0
var run_metrics := {
	"damage_taken": 0.0,
	"defeated": 0,
	"shots_fired": 0,
	"reload_count": 0,
	"elapsed_seconds": 0.0,
}

var status_label: Label
var weapon_panel: Control
var weapon_list: HBoxContainer
var armory_message: Label
var combat_controls: Control
var message_panel: Control
var message_title: Label
var message_body: Label
var primary_button: Button
var secondary_button: Button
var control_help_label: Label
var attack_button: Button


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("07111b"))
	arena = ARENA.new() as GameplayArena
	arena.visible = false
	arena.stage_completed.connect(_on_stage_completed)
	add_child(arena)
	_build_ui()
	var configured: Dictionary = director.configure()
	if not bool(configured.get("ok", false)):
		_show_fatal_error("离线敌人蓝图没有通过机制检查：%s" % str(configured.get("error", "未知错误")))
		return
	armory_entries = armory.load_entries()
	pending_armory_reward = armory.pending_reward()
	if _take_mechanism_handoff():
		_begin_run(equipped_entry)
		return
	_show_weapon_picker()


func _exit_tree() -> void:
	automatic_armory.reset()


func _process(delta: float) -> void:
	_poll_automatic_armory()
	if state == "between_encounters":
		intermission_seconds = maxf(0.0, intermission_seconds - delta)
		if intermission_seconds <= 0.0:
			_start_next_encounter()
	elif state == "combat":
		_update_combat_status()
		var encounter_damage := float(arena.metrics.get("damage_taken", 0.0))
		if arena.player_health <= 1.0 and encounter_damage >= encounter_start_health:
			_finish_failure("生命耗尽")


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_ESCAPE:
		get_tree().change_scene_to_file("res://scenes/open_identity_spike.tscn")
	elif event.physical_keycode == KEY_R and state in ["completed", "failed"]:
		_begin_run(equipped_entry)
	elif event.physical_keycode == KEY_B and state in ["completed", "failed", "weapon_select"]:
		_show_weapon_picker()


func _take_mechanism_handoff() -> bool:
	var handoff: Node = get_node_or_null("/root/MechanismHandoff")
	if handoff == null or not handoff.has_method("take"):
		return false
	var payload: Dictionary = handoff.call("take") as Dictionary
	if payload.is_empty():
		return false
	var blueprint := payload.get("blueprint") as WeaponBlueprint
	equipped_entry = payload.duplicate(true)
	equipped_entry["display_name"] = blueprint.display_name if blueprint != null else ""
	return true


func _show_weapon_picker() -> void:
	arena.stop()
	arena.visible = false
	state = "weapon_select"
	weapon_panel.visible = true
	combat_controls.visible = false
	message_panel.visible = false
	armory_entries = armory.load_entries()
	_rebuild_weapon_cards()
	_refresh_armory_message()
	status_label.text = "三战短关卡 · 选择武器\n不会要求你输入敌人，也不会在线等待 AI。"


func _start_automatic_armory_expansion() -> void:
	if automatic_armory_attempted or not pending_armory_reward.is_empty():
		return
	automatic_armory_attempted = true
	var python_path := _argument_value(
		"--firearm-ai-python=", _argument_value("--fal-python=", "python")
	)
	var started: Dictionary = automatic_armory.start(armory_entries, python_path)
	if bool(started.get("ok", false)) and str(started.get("status", "")) == "running":
		automatic_armory_message = "AI 正在后台补充“%s”能力的物品；战斗不会等它。" % str(
			started.get("target_role_label_zh", "新机制武器")
		)
	elif bool(started.get("ok", false)):
		automatic_armory_message = "当前武器库已覆盖六种主要能力，本次不额外调用 AI。"
	else:
		automatic_armory_message = "后台造物本次未启动；现有武器和关卡仍可正常使用。"


func _poll_automatic_armory() -> void:
	if not automatic_armory_attempted:
		return
	var result: Dictionary = automatic_armory.poll()
	var result_status := str(result.get("status", ""))
	if result_status in ["idle", "running"]:
		return
	if result_status == "success" and result.get("entry", {}) is Dictionary:
		var stored: Dictionary = armory.stage_reward(result.get("entry", {}) as Dictionary)
		if not bool(stored.get("ok", false)):
			automatic_armory_message = "新物品未能完整保存，本轮不发放；现有武器不受影响。"
			_refresh_armory_message()
			return
		pending_armory_reward = (stored.get("entry", {}) as Dictionary).duplicate(true)
		automatic_armory_message = "新物品“%s”已经通过结构与机制检查并保存，完成三战即可领取。" % str(
			result.get("candidate_identity", "新武器")
		)
		armory.invalidate_cache()
		if state == "completed":
			var unlocked: Dictionary = armory.record_run(equipped_entry, true, run_metrics)
			reward_claim_ready = bool(unlocked.get("ok", false))
			if reward_claim_ready:
				_show_completion_reward()
	elif result_status == "failed":
		automatic_armory_message = "后台物品没有通过自动检查，本轮已停止尝试；不会影响当前关卡。"
	_refresh_armory_message()


func _refresh_armory_message() -> void:
	if armory_message == null:
		return
	var base := ""
	if armory_entries.is_empty():
		base = "武器库还是空的。点“描述新物品”，输入任何想尝试的东西；AI 会判断结构和攻击方式。"
	else:
		base = "只选你的武器。敌人、出现顺序和攻击方式全部由系统用离线验收蓝图安排。"
	armory_message.text = base
	if not (armory.last_load_diagnostics.get("library_rejections", []) as Array).is_empty():
		armory_message.text += "\n部分存档检查未通过，已单独跳过；没有替换成默认武器。"
	if not automatic_armory_message.is_empty():
		armory_message.text += "\n" + automatic_armory_message


func _begin_run(entry: Dictionary) -> void:
	var started: Dictionary = director.begin_run(entry)
	if not bool(started.get("ok", false)):
		_show_fatal_error("这件武器的机制交接不完整：%s" % str(started.get("error", "未知错误")))
		return
	equipped_entry = entry.duplicate(true)
	reward_claim_ready = false
	if bool(equipped_entry.get("accepted_visual", false)):
		var saved: Dictionary = armory.remember_equipped(equipped_entry)
		if not bool(saved.get("ok", false)):
			_show_fatal_error("武器未能完整保存，尚未开始本局：%s" % str(saved.get("error", "保存失败")))
			return
		pending_armory_reward = armory.pending_reward()
	if pending_armory_reward.is_empty() and automatic_armory.state not in ["candidate", "generating"]:
		automatic_armory_attempted = false
	_start_automatic_armory_expansion()
	run_health = 100.0
	run_metrics = {
		"damage_taken": 0.0,
		"defeated": 0,
		"shots_fired": 0,
		"attacks_used": 0,
		"reload_count": 0,
		"elapsed_seconds": 0.0,
	}
	weapon_panel.visible = false
	combat_controls.visible = false
	_refresh_control_labels()
	_schedule_next_encounter(0.85)


func _schedule_next_encounter(delay_seconds: float) -> void:
	state = "between_encounters"
	intermission_seconds = delay_seconds
	message_panel.visible = true
	primary_button.visible = false
	secondary_button.visible = false
	var next_number := int((director.snapshot() as Dictionary).get("completed_count", 0)) + 1
	message_title.text = "准备第 %d 战" % next_number
	message_body.text = "系统正在从已验收的敌人机制蓝图安排下一场战斗。\n你不需要选择敌人或确认它怎么攻击。"
	status_label.text = "已装备：%s　生命：%d\n下一场战斗会自动开始。" % [
		_weapon_display_name(),
		roundi(run_health),
	]


func _start_next_encounter() -> void:
	var encounter: Dictionary = director.begin_next_encounter()
	if str(encounter.get("state", "")) == "completed":
		_finish_success()
		return
	if not bool(encounter.get("ok", false)):
		_show_fatal_error("关卡无法继续：%s" % str(encounter.get("error", "未知错误")))
		return
	current_encounter = encounter.duplicate(true)
	var weapon: Dictionary = director.weapon_handoff()
	var blueprint := weapon.get("blueprint") as WeaponBlueprint
	var asset := weapon.get("asset") as WeaponVisualAsset
	var runtime := weapon.get("ranged_runtime_profile", {}) as Dictionary
	if bool(runtime.get("ok", false)):
		blueprint.modifiers["ranged_runtime_profile"] = runtime.duplicate(true)
	var profiles: Array[Dictionary] = []
	for raw_profile: Variant in encounter.get("profiles", []):
		profiles.append((raw_profile as Dictionary).duplicate(true))
	arena.start_stage(str(encounter.get("stage_name", "automatic_encounter")), blueprint, asset, profiles)
	encounter_start_health = run_health
	arena.player_health = run_health
	arena.visible = true
	combat_controls.visible = true
	message_panel.visible = false
	state = "combat"
	_update_combat_status()


func _on_stage_completed(_stage_name: String, metrics: Dictionary) -> void:
	if state != "combat":
		return
	run_health = maxf(1.0, arena.player_health)
	_accumulate_metrics(metrics)
	var progressed: Dictionary = director.complete_active_encounter(metrics)
	arena.visible = false
	combat_controls.visible = false
	if str(progressed.get("state", "")) == "completed":
		_finish_success()
	else:
		_schedule_next_encounter(1.25)


func _finish_success() -> void:
	state = "completed"
	arena.stop()
	arena.visible = false
	combat_controls.visible = false
	message_panel.visible = true
	message_title.text = "三战完成"
	var saved: Dictionary = armory.record_run(equipped_entry, true, run_metrics)
	message_body.text = "你带着 %s 击败了 %d 个敌人，剩余生命 %d。\n敌人的身份和攻击方式全程由离线机制蓝图自动安排。" % [
		_weapon_display_name(),
		int(run_metrics.get("defeated", 0)),
		roundi(run_health),
	]
	reward_claim_ready = bool(saved.get("ok", false)) and not pending_armory_reward.is_empty()
	if reward_claim_ready:
		_show_completion_reward()
	if not bool(saved.get("ok", false)):
		message_body.text += "\n结算暂未保存；已有武器存档没有被覆盖。"
	_configure_result_buttons()
	var action_total := int(run_metrics.get("shots_fired", 0)) if _is_firearm_equipped() else int(run_metrics.get("attacks_used", 0))
	var action_label := "总射击" if _is_firearm_equipped() else "总攻击"
	status_label.text = "关卡完成　总受伤 %.0f　%s %d\nR 再来一次　B 换武器　Esc 返回 Forge" % [
		float(run_metrics.get("damage_taken", 0.0)), action_label, action_total,
	]


func _show_completion_reward() -> void:
	if pending_armory_reward.is_empty() or state != "completed" or not reward_claim_ready:
		return
	var reward_blueprint := pending_armory_reward.get("blueprint") as WeaponBlueprint
	var reward_name := reward_blueprint.display_name if reward_blueprint != null else str(
		pending_armory_reward.get("display_name", "AI 新物品")
	)
	message_body.text = "三战奖励已保存并解锁：%s。\n%s。\n可以装备它再战，也可以在武器库继续使用原来的物品。" % [reward_name, CAPABILITIES.summary(pending_armory_reward)]
	_configure_result_buttons()


func _finish_failure(reason: String) -> void:
	if state != "combat":
		return
	_accumulate_metrics(arena.metrics)
	director.fail_run(reason, arena.metrics)
	run_health = 0.0
	state = "failed"
	arena.stop()
	arena.visible = false
	combat_controls.visible = false
	message_panel.visible = true
	message_title.text = "本次挑战失败"
	var saved: Dictionary = armory.record_run(equipped_entry, false, run_metrics)
	message_body.text = "%s。已经完成 %d / %d 场。\n武器和敌人编排不变，可以直接重试。" % [
		reason,
		int((director.snapshot() as Dictionary).get("completed_count", 0)),
		int((director.snapshot() as Dictionary).get("encounter_count", 0)),
	]
	if not bool(saved.get("ok", false)):
		message_body.text += "\n本次结算未能保存，原有武器存档仍保留。"
	_configure_result_buttons()
	status_label.text = "挑战结束\nR 重新开始　B 换武器　Esc 返回 Forge"


func _show_fatal_error(message: String) -> void:
	state = "error"
	if arena != null:
		arena.stop()
		arena.visible = false
	weapon_panel.visible = false
	combat_controls.visible = false
	message_panel.visible = true
	message_title.text = "关卡没有启动"
	message_body.text = message
	primary_button.visible = false
	secondary_button.visible = true
	secondary_button.text = "返回 Forge"
	status_label.text = "本地检查未通过，没有调用在线服务。"


func _configure_result_buttons() -> void:
	primary_button.visible = true
	primary_button.text = "装备奖励物品再战" if reward_claim_ready else "再来一次"
	secondary_button.visible = true
	secondary_button.text = "查看全部武器" if reward_claim_ready else "更换武器"


func _on_primary_result_pressed() -> void:
	if state not in ["completed", "failed"]:
		return
	if state == "completed" and reward_claim_ready:
		var reward := pending_armory_reward.duplicate(true)
		_begin_run(reward)
		if state == "between_encounters":
			pending_armory_reward.clear()
		return
	_begin_run(equipped_entry)


func _accumulate_metrics(metrics: Dictionary) -> void:
	for key: String in ["damage_taken", "elapsed_seconds"]:
		run_metrics[key] = float(run_metrics.get(key, 0.0)) + float(metrics.get(key, 0.0))
	for key: String in ["defeated", "shots_fired", "attacks_used", "reload_count"]:
		run_metrics[key] = int(run_metrics.get(key, 0)) + int(metrics.get(key, 0))


func _update_combat_status() -> void:
	var enemy_names: Array[String] = []
	var attack_names: Array[String] = []
	for raw_profile: Variant in current_encounter.get("profiles", []):
		var profile := raw_profile as Dictionary
		enemy_names.append(str(profile.get("display_name", "敌人")))
		for raw_label: Variant in profile.get("attack_labels_zh", []):
			attack_names.append(str(raw_label))
	var runtime_states: Array[String] = []
	for enemy: Dictionary in arena.enemies:
		var runtime: Variant = enemy.get("attack_runtime", null)
		if runtime != null and runtime.is_running():
			runtime_states.append("%s·%s" % [
				_enemy_phase_label(str(runtime.phase)),
				_enemy_delivery_label(str(runtime.current_delivery())),
			])
	var weapon_state := _weapon_runtime_status()
	var strategy_tip := WEAPON_STRATEGY.battle_tip(
		arena.weapon_strategy_profile,
		int(current_encounter.get("encounter_number", 1))
	)
	status_label.text = (
		"%s　%d / %d　|　%s　|　生命 %d　%s\n" % [
			str(current_encounter.get("title_zh", "战斗")),
			int(current_encounter.get("encounter_number", 1)),
			int(current_encounter.get("encounter_total", 1)),
			"、".join(enemy_names),
			roundi(arena.player_health),
			weapon_state,
		]
		+ "%s　武器策略：%s\n" % [str(current_encounter.get("brief_zh", "")), strategy_tip]
		+ "敌人招式：%s　状态：%s" % ["、".join(attack_names), "　".join(runtime_states)]
	)


func _enemy_phase_label(phase: String) -> String:
	return str({
		"telegraph": "预警",
		"commit": "蓄势",
		"active": "出招",
		"recovery": "收招",
	}.get(phase, "观察中"))


func _enemy_delivery_label(delivery: String) -> String:
	return str({
		"contact": "近身攻击",
		"rush": "冲撞",
		"projectile": "飞行弹",
		"marked_impact": "落点攻击",
	}.get(delivery, "待机"))


func _rebuild_weapon_cards() -> void:
	for child: Node in weapon_list.get_children():
		weapon_list.remove_child(child)
		child.queue_free()
	for index: int in range(armory_entries.size()):
		var entry := armory_entries[index]
		var blueprint := entry.get("blueprint") as WeaponBlueprint
		var asset := entry.get("asset") as WeaponVisualAsset
		var runtime := entry.get("ranged_runtime_profile", {}) as Dictionary
		if blueprint == null or asset == null:
			continue
		var card := VBoxContainer.new()
		card.custom_minimum_size = Vector2(220, 300)
		card.add_theme_constant_override("separation", 8)
		weapon_list.add_child(card)
		var preview := TextureRect.new()
		preview.custom_minimum_size = Vector2(210, 122)
		preview.texture = asset.texture
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		card.add_child(preview)
		var name_label := Label.new()
		name_label.text = blueprint.display_name + (" · 上次使用" if bool(entry.get("last_equipped", false)) else "")
		name_label.custom_minimum_size = Vector2(210, 42)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 19)
		card.add_child(name_label)
		var mechanism := Label.new()
		mechanism.text = ("%s　%s\n%s　%s\n伤害 %.0f　后坐 %.0f　容量 %d" % [
			_fire_mode_label(runtime),
			_fire_timing_label(runtime),
			_shot_pattern_label(runtime),
			_reload_feed_label(runtime),
			float(runtime.get("projectile_damage", 0.0)),
			float(runtime.get("recoil_pixels", 0.0)),
			int(runtime.get("magazine_size", 0)),
		]) if bool(runtime.get("ok", false)) else _general_weapon_card_text(entry)
		mechanism.custom_minimum_size = Vector2(210, 84)
		mechanism.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mechanism.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mechanism.add_theme_font_size_override("font_size", 14)
		mechanism.modulate = Color("bae6fd")
		card.add_child(mechanism)
		var select := Button.new()
		select.text = "带它进入三战"
		select.custom_minimum_size = Vector2(200, 48)
		_style_pixel_button(select)
		var selected_index := index
		select.pressed.connect(func() -> void: _select_armory_weapon(selected_index))
		card.add_child(select)


func _general_weapon_card_text(entry: Dictionary) -> String:
	var blueprint := entry.get("blueprint") as WeaponBlueprint
	var axes := blueprint.affordance
	var mechanism_axes := preload("res://scripts/combat_feel/mechanism_axis_resolver.gd")
	var state_label := str(mechanism_axes.OPTION_LABELS_ZH["state_topology"].get(str(axes.get("state_topology", "fixed")), "结构固定"))
	var output_label := str(mechanism_axes.OPTION_LABELS_ZH["functional_output"].get(str(axes.get("functional_output", "contact_only")), "接触打击"))
	return "%s\n%s\n%s" % [CAPABILITIES.summary(entry), state_label, output_label]


func _select_armory_weapon(index: int) -> void:
	if index < 0 or index >= armory_entries.size():
		return
	_begin_run(armory_entries[index])


func _weapon_display_name() -> String:
	var blueprint := equipped_entry.get("blueprint") as WeaponBlueprint
	return blueprint.display_name if blueprint != null else str(equipped_entry.get("display_name", "武器"))


func _is_firearm_equipped() -> bool:
	var blueprint := equipped_entry.get("blueprint") as WeaponBlueprint
	return blueprint != null and str(blueprint.affordance.get("weapon_domain", "")) == "handheld_firearm"


func _weapon_runtime_status() -> String:
	if _is_firearm_equipped():
		return "弹匣 %d/%d" % [
			arena.ammo_in_magazine,
			int(arena.ranged_runtime_profile.get("magazine_size", 0)),
		]
	if arena.melee_runtime.profile != null:
		var runtime: RefCounted = arena.melee_runtime
		if not runtime.busy(): return "点按连击 · 长按能力"
		var phase := str({"startup": "蓄势", "active": "出招", "recovery": "收招"}.get(str(runtime.controller.phase), "待机"))
		return "%s · %s" % ["能力" if str(runtime.controller.attack_kind) == "charge" else "连击 %d/3" % int(runtime.controller.combo_index), phase]
	var profile: Variant = equipped_entry.get("affordance_profile")
	if profile == null:
		return "机制轴已接管"
	var soft := str(profile.get("flex_topology")) != "none" or str(profile.get("tether_topology")) != "none"
	var strategy := arena.weapon_strategy_profile
	if soft:
		return "柔性控制 %.0f%%" % (float(strategy.get("control", 0.0)) * 100.0)
	if float(strategy.get("defense", 0.0)) >= 0.55:
		return "攻防展开 %.0f%%" % (float(strategy.get("defense", 0.0)) * 100.0)
	return "实体打击 · 突进 %.0f" % float(strategy.get("melee_lunge_pixels", 0.0))


func _refresh_control_labels() -> void:
	if control_help_label != null:
		control_help_label.text = "WASD 移动　空格/J %s　Shift/K 闪避　Esc 返回 Forge" % (
			"射击" if _is_firearm_equipped() else "攻击"
		)
	if attack_button != null:
		attack_button.text = "射击" if _is_firearm_equipped() else "攻击"


func _fire_mode_label(runtime: Dictionary) -> String:
	if bool(runtime.get("automatic_fire", false)):
		return "按住连射"
	var burst_size := int(runtime.get("burst_size", 0))
	return "按一下 %d 连发" % burst_size if burst_size > 1 else "按一下单发"


func _fire_timing_label(runtime: Dictionary) -> String:
	if bool(runtime.get("cycle_required", false)):
		return "%s，总锁定 %.2f 秒" % [
			_cycle_action_label(int(runtime.get("cycle_action_code", 0))),
			RANGED_AXIS_RESOLVER.cycle_lock_total_seconds(runtime),
		]
	return "%.2f 秒/发" % float(runtime.get("shot_interval_seconds", 0.0))


func _cycle_action_label(action_code: int) -> String:
	return str({1: "每发后拉栓", 2: "每发后泵动", 3: "扳机带动转轮"}.get(action_code, "自动完成循环"))


func _shot_pattern_label(runtime: Dictionary) -> String:
	var pellet_count := maxi(1, int(runtime.get("pellet_count", 1)))
	if pellet_count > 1:
		return "每枪 %d 颗霰弹，覆盖 %.0f°" % [
			pellet_count,
			float(runtime.get("pellet_spread_degrees", 0.0)),
		]
	return "每枪 1 颗弹丸"


func _reload_feed_label(runtime: Dictionary) -> String:
	var step_seconds := float(runtime.get("reload_seconds", 0.0))
	var rounds_per_step := maxi(1, int(runtime.get("reload_rounds_per_step", 1)))
	match int(runtime.get("reload_feed_code", 0)):
		1:
			return "逐发装填 %.2f 秒/次，可开枪打断" % step_seconds
		2:
			return "转轮每次装 %d 发，%.2f 秒/次" % [rounds_per_step, step_seconds]
		3:
			return "整箱更换弹链 %.2f 秒" % step_seconds
		_:
			return "整匣更换 %.2f 秒" % step_seconds


func _build_ui() -> void:
	var font := load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font
	if font is FontFile:
		var pixel_font := font as FontFile
		pixel_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		pixel_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var top := _add_pixel_panel(layer, Vector2(18, 12), Vector2(1244, 116), Color(0.02, 0.05, 0.09, 0.96), Color("6f442a"), 4.0)
	var top_accent := ColorRect.new()
	top_accent.position = Vector2(18, 124)
	top_accent.size = Vector2(1244, 4)
	top_accent.color = Color("9a5a2f")
	layer.add_child(top_accent)
	status_label = Label.new()
	status_label.position = Vector2(32, 20)
	status_label.size = Vector2(1214, 100)
	status_label.add_theme_font_override("font", font)
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.add_theme_color_override("font_color", Color("e2e8f0"))
	layer.add_child(status_label)

	weapon_panel = Control.new()
	layer.add_child(weapon_panel)
	var armory_card := _add_pixel_panel(weapon_panel, Vector2(70, 150), Vector2(1140, 516), Color("111c27"), Color("6f442a"), 4.0)
	var title := Label.new()
	title.text = "选择你的武器"
	title.position = Vector2(108, 174)
	title.size = Vector2(620, 46)
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 28)
	weapon_panel.add_child(title)
	armory_message = Label.new()
	armory_message.position = Vector2(108, 220)
	armory_message.size = Vector2(900, 52)
	armory_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	armory_message.add_theme_font_override("font", font)
	armory_message.add_theme_font_size_override("font_size", 15)
	weapon_panel.add_child(armory_message)
	var refresh := Button.new()
	refresh.text = "重新读取武器库"
	refresh.position = Vector2(960, 174)
	refresh.size = Vector2(208, 46)
	refresh.add_theme_font_override("font", font)
	_style_pixel_button(refresh)
	refresh.pressed.connect(_show_weapon_picker)
	weapon_panel.add_child(refresh)
	var create := Button.new()
	create.text = "描述新物品"
	create.position = Vector2(750, 174)
	create.size = Vector2(194, 46)
	create.add_theme_font_override("font", font)
	_style_pixel_button(create)
	create.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/open_identity_spike.tscn"))
	weapon_panel.add_child(create)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(104, 286)
	scroll.size = Vector2(1070, 338)
	weapon_panel.add_child(scroll)
	weapon_list = HBoxContainer.new()
	weapon_list.add_theme_constant_override("separation", 18)
	scroll.add_child(weapon_list)

	combat_controls = Control.new()
	layer.add_child(combat_controls)
	control_help_label = Label.new()
	control_help_label.text = "WASD 移动　空格/J 攻击　Shift/K 闪避　Esc 返回 Forge"
	control_help_label.position = Vector2(38, 680)
	control_help_label.size = Vector2(760, 30)
	control_help_label.add_theme_font_override("font", font)
	control_help_label.add_theme_font_size_override("font_size", 15)
	combat_controls.add_child(control_help_label)
	attack_button = Button.new()
	attack_button.text = "攻击"
	attack_button.position = Vector2(1090, 638)
	attack_button.size = Vector2(126, 62)
	attack_button.add_theme_font_override("font", font)
	_style_pixel_button(attack_button)
	attack_button.button_down.connect(func() -> void: arena.set_touch_attack(true))
	attack_button.button_up.connect(func() -> void: arena.set_touch_attack(false))
	combat_controls.add_child(attack_button)
	var dodge := Button.new()
	dodge.text = "闪避"
	dodge.position = Vector2(940, 650)
	dodge.size = Vector2(122, 50)
	dodge.add_theme_font_override("font", font)
	_style_pixel_button(dodge)
	dodge.pressed.connect(func() -> void: arena.request_touch_dodge())
	combat_controls.add_child(dodge)
	combat_controls.visible = false

	message_panel = Control.new()
	layer.add_child(message_panel)
	var message_card := _add_pixel_panel(message_panel, Vector2(274, 222), Vector2(732, 300), Color("111c27"), Color("6f442a"), 4.0)
	message_title = Label.new()
	message_title.position = Vector2(316, 258)
	message_title.size = Vector2(648, 48)
	message_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_title.add_theme_font_override("font", font)
	message_title.add_theme_font_size_override("font_size", 30)
	message_panel.add_child(message_title)
	message_body = Label.new()
	message_body.position = Vector2(320, 328)
	message_body.size = Vector2(640, 92)
	message_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_body.add_theme_font_override("font", font)
	message_body.add_theme_font_size_override("font_size", 17)
	message_panel.add_child(message_body)
	primary_button = Button.new()
	primary_button.position = Vector2(380, 442)
	primary_button.size = Vector2(240, 54)
	primary_button.add_theme_font_override("font", font)
	primary_button.add_theme_font_size_override("font_size", 18)
	_style_pixel_button(primary_button)
	primary_button.pressed.connect(_on_primary_result_pressed)
	message_panel.add_child(primary_button)
	secondary_button = Button.new()
	secondary_button.position = Vector2(658, 442)
	secondary_button.size = Vector2(240, 54)
	secondary_button.add_theme_font_override("font", font)
	secondary_button.add_theme_font_size_override("font_size", 18)
	_style_pixel_button(secondary_button)
	secondary_button.pressed.connect(func() -> void:
		if state == "error":
			get_tree().change_scene_to_file("res://scenes/open_identity_spike.tscn")
		else:
			_show_weapon_picker()
	)
	message_panel.add_child(secondary_button)
	message_panel.visible = false


func _style_pixel_button(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("151e26")
	normal.border_color = Color("8e5832")
	normal.set_border_width_all(4)
	normal.corner_radius_top_left = 0
	normal.corner_radius_top_right = 0
	normal.corner_radius_bottom_left = 0
	normal.corner_radius_bottom_right = 0
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("263443")
	hover.border_color = Color("d28a4a")
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("0b1117")
	pressed.border_color = Color("f0b565")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_color_override("font_color", Color("f1d5a8"))
	button.add_theme_color_override("font_hover_color", Color("ffffff"))
	button.add_theme_color_override("font_pressed_color", Color("ffd39a"))


func _add_pixel_panel(
	parent: Node,
	panel_position: Vector2,
	panel_size: Vector2,
	fill: Color,
	border: Color,
	border_width: float
) -> ColorRect:
	var panel := ColorRect.new()
	panel.position = panel_position
	panel.size = panel_size
	panel.color = fill
	parent.add_child(panel)
	for edge: Rect2 in [
		Rect2(Vector2.ZERO, Vector2(panel_size.x, border_width)),
		Rect2(Vector2(0.0, panel_size.y - border_width), Vector2(panel_size.x, border_width)),
		Rect2(Vector2.ZERO, Vector2(border_width, panel_size.y)),
		Rect2(Vector2(panel_size.x - border_width, 0.0), Vector2(border_width, panel_size.y)),
	]:
		var strip := ColorRect.new()
		strip.position = edge.position
		strip.size = edge.size
		strip.color = border
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(strip)
	return panel


func _argument_value(prefix: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return fallback
