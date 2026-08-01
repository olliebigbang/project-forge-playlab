class_name PlaylabEventLogger
extends RefCounted

const EVENT_NAMES: PackedStringArray = [
	"session_started", "input_mode_selected", "description_submitted", "sketch_completed",
	"clarification_shown", "clarification_answered", "blueprint_created", "visual_created",
	"anchors_resolved", "weapon_confirmed", "training_completed", "room_1_started",
	"room_1_completed", "modification_requested", "blueprint_delta_applied", "room_2_started",
	"room_2_completed", "session_completed", "survey_submitted"
]

var session_id: String
var started_msec: int
var output_path: String = "user://playlab/events.jsonl"

func _init() -> void:
	started_msec = Time.get_ticks_msec()
	session_id = "%s-%s" % [Time.get_unix_time_from_system(), randi_range(100000, 999999)]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://playlab"))

func log_event(event_name: String, payload: Dictionary = {}) -> bool:
	if not event_name in EVENT_NAMES:
		push_warning("Unexpected playlab event: %s" % event_name)
	var safe_payload := _sanitize(payload)
	var record := {
		"event": event_name,
		"session_id": session_id,
		"elapsed_ms": Time.get_ticks_msec() - started_msec,
		"unix_time": Time.get_unix_time_from_system(),
		"data": safe_payload
	}
	var file := FileAccess.open(output_path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		return false
	file.seek_end()
	file.store_line(JSON.stringify(record))
	return true

func _sanitize(payload: Dictionary) -> Dictionary:
	var safe := payload.duplicate(true)
	for forbidden: String in ["description", "raw_text", "raw_strokes", "preview_png", "sketch_png", "free_text"]:
		safe.erase(forbidden)
	return safe

