extends SceneTree

const INTERPRETER := preload("res://scripts/services/open_identity_interpreter.gd")
const PROVIDER := preload("res://scripts/services/fal_firearm_visual_provider.gd")

var provider
var finished := false
var blueprint: WeaponBlueprint
var identity := ""
var python_path := "python"
var retry_count := 0
var max_retries := 0


func _initialize() -> void:
	identity = _argument_value("--identity=", "M4A1")
	var interpreted: Dictionary = INTERPRETER.new().interpret(identity, PackedByteArray(), {})
	blueprint = interpreted.get("blueprint") as WeaponBlueprint
	if blueprint == null:
		_finish({"status": "failed", "failure_reason": "LIVE_FIREARM_INTERPRETATION_FAILED"}, 2)
		return
	python_path = _argument_value("--fal-python=", "python")
	max_retries = clampi(int(_argument_value("--max-retries=", "0")), 0, 2)
	retry_count = clampi(int(_argument_value("--initial-retry-index=", "0")), 0, 2)
	if retry_count > 0:
		blueprint.modifiers["mechanism_visual_retry_count"] = retry_count
		blueprint.modifiers["mechanism_visual_retry_prompt"] = (
			_argument_value(
				"--initial-retry-prompt=",
				"The previous candidate confused the declared stock or upper profile with another firearm family; redraw the exact named identity."
			)
		)
	_start_request()


func _start_request() -> void:
	provider = PROVIDER.new()
	var configured: Dictionary = provider.configure(python_path)
	if not bool(configured.get("ok", false)):
		_finish(configured, 2)
		return
	provider.request_visual(blueprint, identity, PackedByteArray(), 0.0)


func _process(_delta: float) -> bool:
	if finished or provider == null:
		return false
	var result: Dictionary = provider.poll()
	if str(result.get("status", "")) in ["success", "failed"]:
		if (
			str(result.get("status", "")) == "failed"
			and bool(result.get("retry_required", false))
			and retry_count < max_retries
		):
			retry_count += 1
			blueprint.modifiers["mechanism_visual_retry_count"] = retry_count
			blueprint.modifiers["mechanism_visual_retry_prompt"] = str(result.get(
				"retry_prompt",
				"Preserve the exact identity and make every declared firearm structure readable."
			))
			print("FAL_FIREARM_LIVE_RETRY=%d:%s" % [retry_count, str(result.get("failure_reason", ""))])
			_start_request()
			return false
		var safe_result := {
			"status": str(result.get("status", "")),
			"failure_reason": str(result.get("failure_reason", "")),
			"provider": str(result.get("provider", "")),
			"output_directory": str(result.get("output_directory", "")),
			"gate_ok": bool((result.get("firearm_visual_identity_gate", {}) as Dictionary).get("ok", false)),
			"visual_mode": str((result.get("manifest", {}) as Dictionary).get("visual_mode", "")),
			"finished_art": bool((result.get("manifest", {}) as Dictionary).get("finished_art", false)),
			"automatic_retries": retry_count,
		}
		_finish(safe_result, 0 if str(result.get("status", "")) == "success" else 1)
	return false


func _finish(result: Dictionary, code: int) -> void:
	if finished:
		return
	finished = true
	print("FAL_FIREARM_LIVE_RESULT=%s" % JSON.stringify(result))
	quit(code)


func _argument_value(prefix: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return fallback
