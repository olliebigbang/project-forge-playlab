extends RefCounted
## One source timeline for body, hands and authored weapon. No IK overlay.
var library: RefCounted
var clip := "combat/SwordIdle"
var index := 0
var elapsed_ms := 0.0
var sequence: Array[String] = []
var next_loop := "combat/SwordIdle"
var entries: Array[Dictionary] = []
var revision := 0
var completed := 0
var freeze_last := false

func _init(source: RefCounted) -> void: library = source

func current() -> Dictionary: return library.frame(clip, index)
func busy() -> bool: return not sequence.is_empty()

func play(names: Array[String], afterwards: String, hold_last: bool = false) -> void:
	sequence = names.duplicate()
	next_loop = afterwards
	freeze_last = hold_last
	_set_clip(sequence.pop_front())
	sequence.push_front(clip)

func loop(name: String) -> void:
	if busy() or clip == name: return
	freeze_last = false
	_set_clip(name)

func inspect(name: String, frame_index: int = 0) -> void:
	sequence.clear()
	_set_clip(name)
	index = clampi(frame_index, 0, library.clips[name].size() - 1)
	entries.clear()

func _set_clip(name: String) -> void:
	clip = name
	index = 0
	elapsed_ms = 0
	revision += 1
	entries.append({"clip": clip, "index": index, "revision": revision})

func tick(seconds: float) -> void:
	elapsed_ms += maxf(0, seconds) * 1000
	while elapsed_ms + 0.000001 >= float(current().duration_ms):
		elapsed_ms -= float(current().duration_ms)
		index += 1
		if index >= library.clips[clip].size():
			if freeze_last and sequence.size() == 1:
				index -= 1
				elapsed_ms = 0
				return
			index = 0
			if busy():
				sequence.pop_front()
				if sequence.is_empty():
					completed += 1
					clip = next_loop
				else: clip = sequence[0]
			revision += 1
		entries.append({"clip": clip, "index": index, "revision": revision})
