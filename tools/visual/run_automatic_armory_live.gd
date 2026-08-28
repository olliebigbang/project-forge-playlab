extends SceneTree

const ARMORY := preload("res://scripts/combat_feel/player_weapon_armory.gd")
const AUTOMATIC_ARMORY := preload("res://scripts/combat_feel/automatic_armory_director.gd")

var armory: RefCounted = ARMORY.new()
var automatic_armory: RefCounted = AUTOMATIC_ARMORY.new()
var finished := false


func _initialize() -> void:
	var entries: Array[Dictionary] = armory.load_entries()
	var excluded: Array[String] = []
	var excluded_argument := _argument_value("--exclude=", "").replace("_", " ")
	if not excluded_argument.strip_edges().is_empty():
		excluded.append(excluded_argument.strip_edges())
	var started: Dictionary = automatic_armory.start(
		entries, _argument_value("--python=", "python"), excluded
	)
	if not bool(started.get("ok", false)):
		_finish(started, 1)
		return
	if str(started.get("status", "")) == "complete":
		_finish(started, 0)
		return
	print("AUTOMATIC_ARMORY_LIVE_STARTED=%s" % JSON.stringify({
		"existing_entry_count": entries.size(),
		"target_role": str(started.get("target_role", "")),
		"target_role_label_zh": str(started.get("target_role_label_zh", "")),
		"player_confirmation_required": false,
	}))


func _process(_delta: float) -> bool:
	if finished:
		return false
	var result: Dictionary = automatic_armory.poll()
	var status := str(result.get("status", ""))
	if status in ["idle", "running"]:
		return false
	_finish(result, 0 if status == "success" or status == "complete" else 1)
	return false


func _finish(result: Dictionary, code: int) -> void:
	if finished:
		return
	finished = true
	var entry := result.get("entry", {}) as Dictionary
	var blueprint := entry.get("blueprint") as WeaponBlueprint
	var runtime := entry.get("ranged_runtime_profile", {}) as Dictionary
	print("AUTOMATIC_ARMORY_LIVE_RESULT=%s" % JSON.stringify({
		"status": str(result.get("status", "")),
		"failure_reason": str(result.get("failure_reason", "")),
		"generated": bool(result.get("generated", false)),
		"target_role": str(result.get("target_role", "")),
		"candidate_identity": str(result.get("candidate_identity", "")),
		"display_name": blueprint.display_name if blueprint != null else "",
		"firearm_family": str(blueprint.affordance.get("firearm_family", "")) if blueprint != null else "",
		"axis_signature": str(runtime.get("axis_signature", "")),
		"cache_status": str(entry.get("cache_status", "")),
		"sprite_path": str(entry.get("sprite_path", "")),
		"automatic_retries": int(result.get("automatic_retries", 0)),
		"candidate_attempts": int(result.get("candidate_attempts", 0)),
		"total_visual_requests": int(result.get("total_visual_requests", 0)),
		"player_confirmation_required": false,
	}))
	quit(code)


func _argument_value(prefix: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return fallback
