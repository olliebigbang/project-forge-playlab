class_name ForgeFixtureOverlay
extends Node2D

const GRIP_COLOR := Color("5eead4")
const SECONDARY_COLOR := Color("facc15")
const EFFECT_COLOR := Color("38bdf8")
const STRIKE_COLOR := Color("fb7185")
const SPIN_COLOR := Color("c084fc")

var arena: GameplayArena
var calibration

func configure(target_arena: GameplayArena, value: RefCounted) -> void:
	arena = target_arena
	calibration = value
	set_process(true)
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if arena == null or calibration == null or not arena.visible or calibration.asset == null:
		return
	var primary_world := _anchor_world(calibration.training_anchor_point("GripPrimary"))
	_draw_grip_fixture(primary_world, GRIP_COLOR, 8.0)
	if calibration.required_anchor_types.has("GripSecondary"):
		_draw_grip_fixture(_anchor_world(calibration.training_anchor_point("GripSecondary")), SECONDARY_COLOR, 7.0)
	if calibration.required_anchor_types.has("EffectOrigin"):
		_draw_effect_rune(_anchor_world(calibration.training_anchor_point("EffectOrigin")), EFFECT_COLOR)
	if calibration.required_anchor_types.has("StrikePoint"):
		_draw_effect_rune(_anchor_world(calibration.training_anchor_point("StrikePoint")), STRIKE_COLOR)
	if calibration.required_anchor_types.has("SpinPivot"):
		_draw_spin_rune(_anchor_world(calibration.training_anchor_point("SpinPivot")))

func _anchor_world(point: Vector2) -> Vector2:
	var hand := arena.player_position + Vector2(19.0 * arena.facing, -10.0)
	var relative: Vector2 = (point - calibration.training_anchor_point("GripPrimary")) * 1.15
	return hand + Vector2(relative.x * arena.facing, relative.y)

func _draw_grip_fixture(point: Vector2, color: Color, radius: float) -> void:
	draw_arc(point, radius, -2.45, -0.70, 10, color, 2.5)
	draw_arc(point, radius, 0.70, 2.45, 10, color, 2.5)
	draw_line(point + Vector2(-radius - 3.0, -5.0), point + Vector2(-radius - 3.0, 5.0), color, 3.0)
	draw_line(point + Vector2(radius + 3.0, -5.0), point + Vector2(radius + 3.0, 5.0), color, 3.0)
	draw_circle(point, 2.5, color)

func _draw_effect_rune(point: Vector2, color: Color) -> void:
	draw_arc(point, 10.0, 0.0, TAU, 20, color, 2.5)
	draw_arc(point, 5.0, 0.0, TAU, 16, Color(color, 0.72), 1.5)
	for index: int in range(6):
		var direction := Vector2.RIGHT.rotated(float(index) * TAU / 6.0)
		draw_line(point + direction * 12.0, point + direction * 17.0, color, 2.0)

func _draw_spin_rune(point: Vector2) -> void:
	draw_arc(point, 9.0, 0.4, TAU - 0.3, 18, SPIN_COLOR, 2.0)
	draw_circle(point, 2.5, SPIN_COLOR)
