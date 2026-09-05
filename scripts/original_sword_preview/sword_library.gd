extends RefCounted
## Only reads authored timing metadata and the matching untouched full PNGs.
## Format reference: https://github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md
const SOURCE := "res://assets/dead_revolver_player_v1/Aseprite/PlayerCombat.aseprite"
const ROOT := "res://assets/dead_revolver_player_v1/Sprites/Combat/"
const CLIPS := ["SwordIdle", "SwordWalk", "SwordRun", "SwordSlash01", "StandingSlash", "SwordCombo01", "SwordCombo02", "SwordCombo03", "SwordCombo04"]
const ACTIONS := [["SwordSlash01"], ["SwordCombo01", "SwordCombo02", "SwordCombo03", "SwordCombo04"], ["StandingSlash"]]
var clips: Dictionary = {}
var errors: Array[String] = []
var source_hash := ""

func _init() -> void:
	var data := FileAccess.get_file_as_bytes(SOURCE)
	var metadata := read_metadata(data)
	if metadata.is_empty():
		errors.append("Invalid Aseprite frame/tag metadata; no fallback timing.")
		return
	source_hash = FileAccess.get_sha256(SOURCE)
	for clip: String in CLIPS:
		if not metadata.tags.has(clip):
			errors.append("Missing authored tag: " + clip)
			continue
		var tag: Dictionary = metadata.tags[clip]
		if int(tag.direction) != 0:
			errors.append("Unsupported non-forward source tag: " + clip)
			continue
		var frames: Array[Dictionary] = []
		for index: int in range(int(tag.first), int(tag.last) + 1):
			var path := ROOT + clip + "/%s%02d.png" % [clip, index - int(tag.first) + 1]
			if not ResourceLoader.exists(path):
				errors.append("Missing original frame: " + path)
				continue
			var texture := load(path) as Texture2D
			if texture == null or texture.get_size() != Vector2(96, 84):
				errors.append("Invalid original canvas: " + path)
				continue
			frames.append({"texture": texture, "duration_ms": int(metadata.durations[index]), "source_frame": index, "path": path})
		clips[clip] = frames

static func read_metadata(data: PackedByteArray, expected_canvas: Vector2i = Vector2i(96, 84)) -> Dictionary:
	# Bound every read. Cel pixels and optional chunks are not decoded/executed.
	if data.size() < 128 or data.decode_u32(0) != data.size() or data.decode_u16(4) != 0xA5E0: return {}
	var canvas := Vector2i(data.decode_u16(8), data.decode_u16(10))
	if canvas.x <= 0 or canvas.y <= 0: return {}
	if expected_canvas != Vector2i.ZERO and canvas != expected_canvas: return {}
	var durations: Array[int] = []
	var tags: Dictionary = {}
	var position := 128
	for _frame: int in range(data.decode_u16(6)):
		if position + 16 > data.size(): return {}
		var end := position + int(data.decode_u32(position))
		if end > data.size() or end < position + 16 or data.decode_u16(position + 4) != 0xF1FA: return {}
		var duration := int(data.decode_u16(position + 8))
		if duration <= 0: return {}
		durations.append(duration)
		var count := int(data.decode_u32(position + 12))
		if count == 0: count = int(data.decode_u16(position + 6))
		var cursor := position + 16
		for _chunk: int in range(count):
			if cursor + 6 > end: return {}
			var chunk_end := cursor + int(data.decode_u32(cursor))
			if chunk_end > end or chunk_end < cursor + 6: return {}
			if data.decode_u16(cursor + 4) == 0x2018:
				if cursor + 16 > chunk_end: return {}
				var tag_count := int(data.decode_u16(cursor + 6))
				var tag_cursor := cursor + 16
				for _tag: int in range(tag_count):
					if tag_cursor + 19 > chunk_end: return {}
					var name_end := tag_cursor + 19 + int(data.decode_u16(tag_cursor + 17))
					if name_end > chunk_end: return {}
					var name := data.slice(tag_cursor + 19, name_end).get_string_from_utf8()
					tags[name] = {"first": data.decode_u16(tag_cursor), "last": data.decode_u16(tag_cursor + 2), "direction": data[tag_cursor + 4]}
					tag_cursor = name_end
			cursor = chunk_end
		position = end
	if position != data.size(): return {}
	for tag: Dictionary in tags.values():
		if int(tag.first) > int(tag.last) or int(tag.last) >= durations.size(): return {}
	return {"durations": durations, "tags": tags, "canvas": canvas}

func total_ms(clip: String) -> int:
	var total := 0
	for frame: Dictionary in clips.get(clip, []): total += int(frame.duration_ms)
	return total
