extends Node2D
const ARENA := preload("res://scripts/sunny_player_preview/authored_arena.gd")
const LIBRARY := preload("res://scripts/art_vertical_slice_v1/expedition_library.gd")
const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
var arena: GameplayArena
var entries: Array[Dictionary] = []
var selected := 0
var clean := false

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	get_tree().root.title = "Forge — 原包动作 × AI 武器（离线）"
	get_tree().root.content_scale_size = Vector2i(1280, 720)
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	get_tree().root.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER
	get_tree().root.size = Vector2i(1280, 720)
	arena = ARENA.new(); add_child(arena)
	entries = LIBRARY.new().load_all(false)
	if entries.is_empty(): push_error("Bundled AI weapon library unavailable"); return
	_select(0)

func _select(index: int) -> void:
	selected = posmod(index, entries.size())
	arena.start_stage("training", entries[selected].blueprint, entries[selected].asset)
	arena.set_process(false)

func _physics_process(delta: float) -> void:
	if arena == null or entries.is_empty(): return
	arena._process(delta)
	queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_ESCAPE: get_tree().quit()
		KEY_TAB: clean = not clean
		KEY_R: _select(selected)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5: _select(event.keycode - KEY_1)
		KEY_G: arena.auto_crouch = not arena.auto_crouch
	get_viewport().set_input_as_handled()

func _draw() -> void:
	if clean or entries.is_empty(): return
	draw_rect(Rect2(16, 16, 1248, 102), Color("203e43"))
	draw_string(FONT, Vector2(32, 46), "原包动作 × AI 武器 · " + str(entries[selected].blueprint.display_name), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("fff0c7"))
	var state := "蹲射" if arena.authored_crouched else "站姿 / 移动"
	state += " · 弹匣 %d" % arena.ammo_in_magazine if arena._uses_firearm_runtime() else " · " + str(arena.melee_runtime.controller.phase)
	draw_string(FONT, Vector2(32, 74), state + " · 累计伤害 %.0f" % arena.damage_delivered, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("d5e6c7"))
	draw_string(FONT, Vector2(32, 102), "WASD 移动 · J/空格攻击/蓄力 · K/Shift 翻滚 · C 蹲射 · G 自动蹲射 · 1–5 武器 · R 重置 · Esc 退出", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("fff0c7"))
