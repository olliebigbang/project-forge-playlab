extends RefCounted
const LIBRARY := preload("res://scripts/original_sword_preview/sword_library.gd")
var library: RefCounted
var clip := "SwordIdle"
var frame_index := 0
var elapsed_ms := 0.0
var sequence: Array = []
var sequence_index := 0
var attacking := false
var facing := 1.0
var completed_actions := 0

func _init(source: RefCounted) -> void:
	library = source

func current_frame() -> Dictionary:
	return library.clips[clip][frame_index]

func start_action(action_index: int) -> bool:
	if attacking or action_index < 0 or action_index >= LIBRARY.ACTIONS.size(): return false
	sequence = LIBRARY.ACTIONS[action_index].duplicate()
	sequence_index = 0
	attacking = true
	_set_clip(str(sequence[0]))
	return true

func locomotion(moving: bool, running: bool, direction: float) -> void:
	if attacking: return
	if not is_zero_approx(direction): facing = signf(direction)
	var next := "SwordRun" if moving and running else ("SwordWalk" if moving else "SwordIdle")
	if next != clip: _set_clip(next)

func tick(delta_seconds: float) -> void:
	elapsed_ms += maxf(0, delta_seconds) * 1000.0
	while elapsed_ms + 0.000001 >= float(current_frame().duration_ms):
		elapsed_ms -= float(current_frame().duration_ms)
		frame_index += 1
		if frame_index < library.clips[clip].size(): continue
		frame_index = 0
		if attacking:
			sequence_index += 1
			if sequence_index < sequence.size(): clip = str(sequence[sequence_index])
			else:
				attacking = false
				completed_actions += 1
				clip = "SwordIdle"

func inspect_step(direction: int) -> void:
	# Inspection stays inside this source clip; it does not invent in-between frames.
	frame_index = posmod(frame_index + direction, library.clips[clip].size())
	elapsed_ms = 0.0

func inspect_clip(name: String, index: int, face: float) -> void:
	clip = name
	frame_index = clampi(index, 0, library.clips[clip].size() - 1)
	elapsed_ms = 0
	facing = face
	attacking = false
	sequence.clear()

func _set_clip(name: String) -> void:
	clip = name
	frame_index = 0
	elapsed_ms = 0
