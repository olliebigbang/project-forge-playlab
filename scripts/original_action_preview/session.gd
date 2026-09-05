extends Node2D
const LIBRARY := preload("res://scripts/original_action_preview/action_library.gd")
const CONTROLLER := preload("res://scripts/original_action_preview/controller.gd")
const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
const BACKGROUND := preload("res://assets/sunny_arena_preview_v1/clearing_generated_v3.png")
const FROG := preload("res://assets/sunny_arena_preview_v1/frog_idle.png")
const EQUIPMENT := ["sword", "gun", "bow", "fishing", "unarmed"]
const SCALE := 4.0
var library := LIBRARY.new()
var actor: RefCounted
var paused := false
var slow := false
var inspect_mode := false
var auto_crouch := true
var auto_lowered := false
var target_feet := Vector2(864, 580)
var target_image: Image
var target_damage := 0
var hits := 0
var projectiles: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var effects: Array[Dictionary] = []
var last_melee_revision := -1
var catalog_picker: OptionButton
var equipment_buttons: Array[Button] = []
var note := "原包完整人物与动作；枪是原包占位枪。不是三章关卡，也未替换 AI 武器。"
var evidence := ""
var time := 0.0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var window := get_tree().root
	window.title = "Forge — 原包动作训练场：近战 / 蹲射 / 移动 / 钓鱼"
	window.content_scale_size = Vector2i(1280, 720)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.size = Vector2i(1280, 720)
	window.min_size = Vector2i(960, 540)
	Engine.max_fps = 60
	if not library.errors.is_empty():
		push_error(str(library.errors)); get_tree().quit(1); return
	actor = CONTROLLER.new(library)
	target_image = FROG.get_image()
	var names := ["剑 · 1", "枪 · 2", "弓 · 3", "钓竿 · 4", "徒手 · 5"]
	for i: int in range(names.size()):
		var b := Button.new()
		b.position = Vector2(26 + i * 141, 626)
		b.size = Vector2(130, 39)
		b.text = names[i]
		style_control(b)
		b.pressed.connect(equip.bind(i))
		add_child(b)
		equipment_buttons.append(b)
	catalog_picker = OptionButton.new()
	catalog_picker.position = Vector2(744, 626)
	catalog_picker.size = Vector2(506, 39)
	style_control(catalog_picker)
	catalog_picker.add_item("全部动作 / 配套特效检查（点击选择）")
	for item: Dictionary in library.catalog:
		if item.excluded: continue
		catalog_picker.add_item(library.label(item.key) + " · " + str(item.key))
		catalog_picker.set_item_metadata(catalog_picker.item_count - 1, item.key)
	catalog_picker.get_popup().max_size = Vector2i(610, 470)
	catalog_picker.item_selected.connect(_inspect_selected)
	add_child(catalog_picker)
	queue_redraw()

func style_control(control: Control) -> void:
	control.focus_mode = Control.FOCUS_NONE
	control.add_theme_font_override("font", FONT)
	control.add_theme_font_size_override("font_size", 17)
	control.add_theme_stylebox_override("normal", panel(Color("244a4e")))
	control.add_theme_stylebox_override("hover", panel(Color("37676b")))
	control.add_theme_stylebox_override("pressed", panel(Color("477b70")))

func equip(index: int) -> void:
	actor.equip(EQUIPMENT[index])
	inspect_mode = false
	paused = false
	projectiles.clear()
	effects.clear()
	catalog_picker.select(0)
	note = "J 按住蓄力，松开抛竿；再按 J 收回。原包无持竿行走帧，此模式原地演示，不是钓鱼小游戏。" if index == 3 else "低靶会记录真实命中；按 G 比较自动蹲射开关，C 可手动蹲下。O 快斩 / B 切换持剑跑姿。"
	queue_redraw()

func _inspect_selected(index: int) -> void:
	if index == 0: equip(EQUIPMENT.find(actor.equipment)); return
	inspect_mode = true
	paused = false
	actor.inspect(str(catalog_picker.get_item_metadata(index)))
	actor.feet = Vector2(624, 580)
	projectiles.clear()
	effects.clear()
	for item: Dictionary in library.catalog:
		if item.key == actor.animation.clip: note = item.status + "；单项演示不产生伤害，按 1～5 返回操作。"
	queue_redraw()

func _physics_process(delta: float) -> void:
	if actor == null: return
	var movement := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var input := {"move": movement, "run": Input.is_physical_key_pressed(KEY_SHIFT), "sprint": Input.is_physical_key_pressed(KEY_CTRL), "crouch": Input.is_physical_key_pressed(KEY_C), "attack": Input.is_physical_key_pressed(KEY_J) or Input.is_physical_key_pressed(KEY_SPACE), "secondary": Input.is_physical_key_pressed(KEY_L), "guard": Input.is_physical_key_pressed(KEY_V), "dodge": Input.is_physical_key_pressed(KEY_K), "dash": Input.is_physical_key_pressed(KEY_Z), "slide": Input.is_physical_key_pressed(KEY_X), "reload": Input.is_physical_key_pressed(KEY_R), "hit": Input.is_physical_key_pressed(KEY_H), "stun": Input.is_physical_key_pressed(KEY_U)}
	input.quick = Input.is_physical_key_pressed(KEY_O)
	advance(delta, input)

func advance(delta: float, input: Dictionary = {}) -> void:
	if paused or actor == null: return
	var dt := delta * (0.25 if slow else 1.0)
	time += dt
	if inspect_mode:
		actor.animation.tick(dt)
		actor.animation.entries.clear()
		queue_redraw()
		return
	var controls := input.duplicate()
	var movement: Vector2 = controls.get("move", Vector2.ZERO)
	auto_lowered = false
	# Automatic posture, not diagonal correction: use the two authored muzzle heights.
	if actor.equipment == "gun" and auto_crouch and movement.is_zero_approx():
		if not ray_hits_target("combat/GunFire") and ray_hits_target("combat/GunCrouchFire"):
			auto_lowered = true
			controls.crouch = true
	actor.step(dt, controls)
	_clamp_actor_canvas()
	for event: Dictionary in actor.events:
		if event.type == "shot": _shoot(event)
		elif event.type == "arrow": _arrow(event)
		elif event.type == "fx": effects.append({"key": event.key, "feet": event.feet, "facing": event.facing, "age": 0.0})
	actor.events.clear()
	for i: int in range(projectiles.size() - 1, -1, -1):
		var p: Dictionary = projectiles[i]
		var before: Vector2 = p.position
		p.position += p.velocity * dt
		if segment_hits_target(before, p.position, p.key, p.facing):
			hits += 1
			target_damage += 14
			shots[p.record].hit = true
			projectiles.remove_at(i)
		elif p.position.x < -100 or p.position.x > 1380: projectiles.remove_at(i)
	_update_melee()
	for i: int in range(effects.size() - 1, -1, -1):
		effects[i].age += dt
		if effects[i].age * 1000 >= library.total_ms(effects[i].key): effects.remove_at(i)
	queue_redraw()

func _clamp_actor_canvas() -> void:
	var body: Dictionary = actor.animation.current()
	var canvas: Vector2 = body.texture.get_size()
	var left: float = body.pivot.x if actor.facing > 0 else canvas.x - body.pivot.x
	var right := canvas.x - left
	# Fishing's asymmetric wide canvas must mirror with the actor, including bounds.
	actor.feet.x = clampf(actor.feet.x, maxf(220, left * SCALE), minf(1060, 1280 - right * SCALE))
	actor.feet.y = clampf(actor.feet.y, ceilf(maxf(488, 156 + body.pivot.y * SCALE) / SCALE) * SCALE, 604)

func muzzle(key: String, frame_index: int = 0, feet_override: Vector2 = Vector2.INF, face_override: float = 0) -> Vector2:
	var frame: Dictionary = library.frame(key, frame_index)
	if not frame.has("muzzle"): return Vector2.INF
	var origin: Vector2 = actor.feet.snapped(Vector2(4, 4)) if feet_override == Vector2.INF else feet_override
	var face: float = actor.facing if face_override == 0 else face_override
	return origin + (frame.muzzle - frame.pivot) * Vector2(face, 1) * SCALE

func _shoot(event: Dictionary) -> void:
	var origin := muzzle(event.clip, event.frame, event.feet, event.facing)
	if not origin.is_finite(): push_error("Source gun layer has no muzzle: " + str(event.clip)); return
	_spawn_projectile(origin, event.facing, "weapon/Bullet", event.clip)

func _arrow(event: Dictionary) -> void:
	# Bow is baked into the body PNG. Its green forward edge is the release anchor.
	var frame: Dictionary = library.frame(event.clip, event.frame)
	var edge := Vector2.ZERO
	for y: int in range(frame.image.get_height()):
		for x: int in range(frame.image.get_width()):
			var color: Color = frame.image.get_pixel(x, y)
			if color.a > 0.5 and color.g > color.r * 1.2 and color.g > color.b * 1.1 and x > edge.x: edge = Vector2(x + 1, y + 0.5)
	if edge == Vector2.ZERO: return
	_spawn_projectile(event.feet + (edge - frame.pivot) * Vector2(event.facing, 1) * SCALE, event.facing, "weapon/Arrow", event.clip)

func _spawn_projectile(origin: Vector2, face: float, key: String, source_clip: String) -> void:
	shots.append({"origin": origin, "velocity": Vector2(face * 720, 0), "clip": source_clip, "hit": false})
	projectiles.append({"position": origin, "velocity": Vector2(face * 720, 0), "key": key, "record": shots.size() - 1, "facing": face})

func target_pixel(point: Vector2) -> bool:
	var local := (point - target_feet) / SCALE + Vector2(16, 27)
	var x := floori(local.x)
	var y := floori(local.y)
	return x >= 0 and x < 32 and y >= 0 and y < 32 and target_image.get_pixel(64 + x, y).a > 0.5

func segment_hits_target(from: Vector2, to: Vector2, key: String = "weapon/Bullet", face: float = 1) -> bool:
	var img: Image = library.frame(key).image
	var bounds := img.get_used_rect()
	var center := Vector2(bounds.get_center())
	var steps := maxi(1, ceili(from.distance_to(to) / 2))
	# Test actual opaque projectile blocks along the travelled segment. No giant capsule.
	for step: int in range(steps + 1):
		var pos := from.lerp(to, float(step) / steps).snapped(Vector2.ONE)
		if absf(pos.x - target_feet.x) > 110: continue
		for y: int in range(bounds.position.y, bounds.end.y):
			for x: int in range(bounds.position.x, bounds.end.x):
				if img.get_pixel(x, y).a < 0.5: continue
				var pixel := pos + (Vector2(x, y) - center) * Vector2(face, 1) * SCALE
				if face < 0: pixel.x -= SCALE
				for offset: Vector2 in [Vector2.ZERO, Vector2(3, 0), Vector2(0, 3), Vector2(3, 3)]:
					if target_pixel(pixel + offset): return true
	return false

func ray_hits_target(key: String) -> bool:
	var origin := muzzle(key)
	if not origin.is_finite() or (target_feet.x - origin.x) * actor.facing <= 0: return false
	# A horizontal bullet sweeps its two actual opaque rows through the target.
	# This is the same source-alpha test without resampling a long empty ray.
	var bullet: Image = library.frame("weapon/Bullet").image
	var bounds := bullet.get_used_rect()
	var center := Vector2(bounds.get_center())
	for py: int in range(bounds.position.y, bounds.end.y):
		var occupied := false
		for px: int in range(bounds.position.x, bounds.end.x):
			if bullet.get_pixel(px, py).a > 0.5: occupied = true; break
		if not occupied: continue
		var top := origin.y + (py - center.y) * SCALE
		for y: int in range(32):
			var target_top := target_feet.y + (y - 27) * SCALE
			if top >= target_top + SCALE or top + SCALE <= target_top: continue
			for x: int in range(32):
				if target_image.get_pixel(64 + x, y).a > 0.5: return true
	return false

func _update_melee() -> void:
	if actor.equipment != "sword" or not actor.animation.busy() or last_melee_revision == actor.animation.revision: return
	var frame: Dictionary = actor.animation.current()
	var img: Image = frame.image
	for y: int in range(img.get_height()):
		for x: int in range(img.get_width()):
			var c := img.get_pixel(x, y)
			if c.a < 0.5 or c.g < c.r * 1.2 or c.g < c.b * 1.1: continue
			var point: Vector2 = actor_origin() + (Vector2(x, y) + Vector2(0.5, 0.5) - frame.pivot) * Vector2(actor.facing, 1) * SCALE
			if target_pixel(point):
				last_melee_revision = actor.animation.revision
				hits += 1
				target_damage += 20
				return

func actor_origin() -> Vector2: return actor.feet.snapped(Vector2(4, 4))

func _draw() -> void:
	draw_texture_rect(BACKGROUND, Rect2(0, 0, 1280, 720), false)
	if actor == null: return
	if not inspect_mode:
		draw_texture_rect_region(FROG, Rect2(target_feet - Vector2(64, 108), Vector2(128, 128)), Rect2(64, 0, 32, 32))
		draw_string(FONT, target_feet + Vector2(-63, -119), "低靶 · 命中 %d" % hits, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("173e3b"))
	var frame: Dictionary = actor.animation.current()
	draw_rect(Rect2(actor_origin() + Vector2(-32, 0), Vector2(64, 4)), Color("a67d42"))
	draw_set_transform(actor_origin(), 0, Vector2(actor.facing, 1) * SCALE)
	draw_texture(frame.texture, -frame.pivot)
	draw_set_transform(Vector2.ZERO)
	for p: Dictionary in projectiles:
		var projectile: Dictionary = library.frame(p.key)
		var center := Vector2((projectile.image as Image).get_used_rect().get_center())
		draw_set_transform((p.position as Vector2).snapped(Vector2.ONE), 0, Vector2(p.facing, 1) * SCALE)
		draw_texture(projectile.texture, -center)
		draw_set_transform(Vector2.ZERO)
	for effect: Dictionary in effects:
		var elapsed: float = effect.age * 1000
		for fx_frame: Dictionary in library.clips[effect.key]:
			if elapsed < float(fx_frame.duration_ms):
				draw_set_transform((effect.feet as Vector2).snapped(Vector2(4, 4)), 0, Vector2(effect.facing, 1) * SCALE)
				draw_texture(fx_frame.texture, -fx_frame.pivot)
				draw_set_transform(Vector2.ZERO)
				break
			elapsed -= float(fx_frame.duration_ms)
	_draw_hud()

func _draw_hud() -> void:
	draw_style_box(panel(Color("18383e", 0.96)), Rect2(16, 16, 1248, 139))
	draw_string(FONT, Vector2(32, 48), "原包动作训练场", HORIZONTAL_ALIGNMENT_LEFT, -1, 27, Color("fff0cd"))
	var frame: Dictionary = actor.animation.current()
	var state := "单项动作演示" if inspect_mode else "可操作 · 原包全身动作"
	draw_string(FONT, Vector2(280, 46), "%s  ·  %s  ·  %d/%d 帧" % [state, library.label(actor.animation.clip), actor.animation.index + 1, library.clips[actor.animation.clip].size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("dcebdc"))
	var stance := "蹲射" if actor.animation.clip.contains("Crouch") else "站姿 / 移动"
	draw_string(FONT, Vector2(32, 79), "%s  |  %s %dms  |  弹匣 %d/6  生命 %d  |  低靶自动蹲下：%s" % [actor.animation.clip, "暂停 " if paused else ("慢放 " if slow else "原速 "), frame.duration_ms, actor.ammo, actor.health, "开（" + stance + "）" if auto_crouch else "关"], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("fff0cd"))
	draw_string(FONT, Vector2(32, 110), "WASD 移动  Shift 跑 / Ctrl 冲刺  J 攻击 / 蓄力松开  L 连击 / 双手射击  C 蹲下  K 翻滚", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("dcebdc"))
	draw_string(FONT, Vector2(32, 139), "R 换弹  V 格挡  Z 闪身 / X 滑步  G 自动蹲射  F 转向  H 受击 / U 眩晕  P 暂停  T 慢放  Esc 退出", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("dcebdc"))
	draw_style_box(panel(Color("18383e", 0.96)), Rect2(16, 614, 1248, 90))
	draw_string(FONT, Vector2(30, 693), note, HORIZONTAL_ALIGNMENT_LEFT, 1220, 15, Color("dcebdc"))

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or actor == null: return
	match event.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5: equip(event.keycode - KEY_1)
		KEY_G: auto_crouch = not auto_crouch
		KEY_T: slow = not slow
		KEY_P: paused = not paused
		KEY_B: actor.alternate_run = not actor.alternate_run
		KEY_F:
			if not actor.animation.busy(): actor.facing *= -1
		KEY_LEFT, KEY_RIGHT:
			if paused:
				actor.animation.index = posmod(actor.animation.index + (-1 if event.keycode == KEY_LEFT else 1), library.clips[actor.animation.clip].size())
		KEY_F8: _capture()
		KEY_ESCAPE: get_tree().quit()
	queue_redraw()

func _capture() -> void:
	if evidence.is_empty():
		evidence = "res://.tools/original-actions/manual-%d-%d" % [Time.get_unix_time_from_system(), OS.get_process_id()]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(evidence.path_join("frame-%d.png" % Time.get_ticks_msec()))

static func panel(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = 8
	box.corner_radius_top_right = 8
	box.corner_radius_bottom_left = 8
	box.corner_radius_bottom_right = 8
	return box
