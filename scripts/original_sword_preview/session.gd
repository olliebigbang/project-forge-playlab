extends Node2D
## Authored animation baseline only: no AI, character reskin, IK or damage.
const LIBRARY := preload("res://scripts/original_sword_preview/sword_library.gd")
const PLAYER := preload("res://scripts/original_sword_preview/clip_player.gd")
const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
const BACKGROUND := preload("res://assets/sunny_arena_preview_v1/clearing_generated_v3.png")
const PIVOT := Vector2(48, 84)
const PIXEL_SCALE := 4.0
const ACTION_NAMES := ["全身挥剑", "四段连击", "站立快斩"]
var library := LIBRARY.new()
var player: RefCounted
var feet := Vector2(624, 566)
var paused := false
var slow := false
var autoplay := true
var demo_wait := 0.55
var demo_action := 0
var last_action := "原包持剑待机"
var buttons: Array[Button] = []
var evidence := ""

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var window := get_tree().root
	window.title = "Forge — 原包剑招还原（独立离线小样）"
	window.content_scale_size = Vector2i(1280, 720)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.size = Vector2i(1280, 720)
	window.min_size = Vector2i(960, 540)
	Engine.max_fps = 60
	if not library.errors.is_empty():
		push_error(str(library.errors))
		get_tree().quit(1)
		return
	player = PLAYER.new(library)
	var labels := ["挥剑 · J", "四段连击 · K", "快斩 · L", "自动演示 · Q", "慢放 · T", "暂停 · P"]
	for index: int in range(labels.size()):
		var button := Button.new()
		button.position = Vector2(32 + index * 202, 624)
		button.size = Vector2(186, 42)
		button.text = labels[index]
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_override("font", FONT)
		button.add_theme_font_size_override("font_size", 18)
		button.add_theme_stylebox_override("normal", panel(Color("244a4e")))
		button.add_theme_stylebox_override("hover", panel(Color("37676b")))
		button.add_theme_stylebox_override("pressed", panel(Color("477b70")))
		button.pressed.connect(_button_pressed.bind(index))
		add_child(button)
		buttons.append(button)
	queue_redraw()

func _physics_process(delta: float) -> void:
	if player == null: return
	var movement := float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
	var running := Input.is_physical_key_pressed(KEY_SHIFT)
	advance(delta, movement, running)

func advance(delta: float, movement: float = 0, running: bool = false) -> void:
	if paused: return
	var dt := delta * (0.25 if slow else 1.0)
	if not is_zero_approx(movement): autoplay = false
	player.locomotion(not is_zero_approx(movement), running, movement)
	if not player.attacking:
		feet.x = clampf(feet.x + movement * (260.0 if running else 150.0) * dt, 224.0, 1056.0)
		if autoplay:
			demo_wait -= dt
			if demo_wait <= 0:
				last_action = ACTION_NAMES[demo_action]
				player.start_action(demo_action)
				demo_action = (demo_action + 1) % ACTION_NAMES.size()
				demo_wait = 0.65
	var completed: int = player.completed_actions
	player.tick(dt)
	if autoplay and player.completed_actions != completed and demo_action == 0: player.facing *= -1
	queue_redraw()

func trigger_action(index: int) -> void:
	autoplay = false
	# A press while paused explicitly starts the whole authored move again.
	if paused:
		paused = false
		player.attacking = false
	if player.start_action(index): last_action = ACTION_NAMES[index]
	queue_redraw()

func _button_pressed(index: int) -> void:
	match index:
		0, 1, 2: trigger_action(index)
		3: autoplay = not autoplay; demo_wait = 0.2
		4: slow = not slow
		5: paused = not paused
	queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or player == null: return
	match event.keycode:
		KEY_J, KEY_SPACE: trigger_action(0)
		KEY_K: trigger_action(1)
		KEY_L: trigger_action(2)
		KEY_Q: _button_pressed(3)
		KEY_T: _button_pressed(4)
		KEY_P: _button_pressed(5)
		KEY_LEFT, KEY_RIGHT:
			if paused: player.inspect_step(-1 if event.keycode == KEY_LEFT else 1)
		KEY_F:
			if paused or not player.attacking: player.facing *= -1
		KEY_R:
			player = PLAYER.new(library)
			feet = Vector2(624, 566)
			paused = false
			slow = false
			autoplay = true
			demo_action = 0
			demo_wait = 0.55
		KEY_F8: _capture()
		KEY_ESCAPE: get_tree().quit()
	queue_redraw()
	get_viewport().set_input_as_handled()

func actor_origin() -> Vector2:
	return feet.snapped(Vector2.ONE * PIXEL_SCALE)

func _draw() -> void:
	draw_texture_rect(BACKGROUND, Rect2(0, 0, 1280, 720), false)
	if player == null: return
	var origin := actor_origin()
	draw_rect(Rect2(origin + Vector2(-38, 0), Vector2(76, 4)), Color("a67d42"))
	draw_set_transform(origin, 0, Vector2(player.facing, 1) * PIXEL_SCALE)
	# One untouched full source canvas: never recenter each frame's opaque box.
	draw_texture(player.current_frame().texture, -PIVOT)
	draw_set_transform(Vector2.ZERO)
	draw_style_box(panel(Color("18383e", 0.96)), Rect2(16, 16, 1248, 120))
	draw_string(FONT, Vector2(32, 51), "原包剑招还原", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color("fff0cd"))
	draw_string(FONT, Vector2(286, 49), "完整人物 + 原始剑与斩光 · 不换皮、不拼手臂", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("cbe0d5"))
	var mode := "暂停逐帧" if paused else ("自动演示（可直接按键接管）" if autoplay else "手动操作")
	draw_string(FONT, Vector2(32, 83), "%s  ·  %s  ·  %s" % [mode, "四分之一慢放" if slow else "原始速度", last_action], HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("fff0cd"))
	draw_string(FONT, Vector2(32, 113), "A / D 移动   Shift 跑步   J / 空格 挥剑   K 四段连击   L 快斩   F 转向   Esc 退出", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("dcebdc"))
	draw_style_box(panel(Color("18383e", 0.94)), Rect2(16, 148, 1248, 63))
	var count: int = library.clips[player.clip].size()
	draw_string(FONT, Vector2(32, 173), "%s · 第 %d / %d 帧 · 原始每帧 %d 毫秒" % [player.clip, player.frame_index + 1, count, player.current_frame().duration_ms], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("dcebdc"))
	var x := 32.0
	var total := float(library.total_ms(player.clip))
	for index: int in range(count):
		var width := 1208.0 * float(library.clips[player.clip][index].duration_ms) / total
		draw_rect(Rect2(x, 187, width - 3, 8), Color("f2c76d") if index == player.frame_index else Color("4c7774"))
		x += width
	draw_style_box(panel(Color("18383e", 0.96)), Rect2(16, 608, 1248, 96))
	draw_string(FONT, Vector2(32, 692), "P 暂停后用 ← / → 逐帧看动作  ·  R 重置  ·  本小样只还原动画，未接伤害、敌人或通用机制轴", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("dcebdc"))

static func panel(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = 8
	box.corner_radius_top_right = 8
	box.corner_radius_bottom_left = 8
	box.corner_radius_bottom_right = 8
	return box

func _capture() -> void:
	if evidence.is_empty():
		evidence = "res://.tools/original-sword/manual-%d-%d" % [Time.get_unix_time_from_system(), OS.get_process_id()]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(evidence.path_join("frame-%d.png" % Time.get_ticks_msec()))
