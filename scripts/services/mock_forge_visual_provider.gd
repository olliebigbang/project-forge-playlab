class_name MockForgeVisualProvider
extends "res://scripts/services/forge_visual_provider.gd"

const MOCK_GENERATOR := preload("res://scripts/services/mock_weapon_image_generator.gd")

var pending_result: Dictionary = {}

func request_visual(
	blueprint: WeaponBlueprint,
	_prompt: String,
	_sketch_png: PackedByteArray,
	_control_strength: float = 0.45
) -> int:
	request_revision += 1
	var generator := MOCK_GENERATOR.new() as MockWeaponImageGenerator
	var generated: Dictionary = generator.generate(blueprint)
	pending_result = {
		"status": "success" if bool(generated.get("ok", false)) else "failed",
		"asset": generated.get("asset"),
		"revision": request_revision,
		"provider": MODE_MOCK,
		"failure_reason": str(generated.get("error", ""))
	}
	return request_revision

func poll() -> Dictionary:
	if pending_result.is_empty():
		return {"status": "idle"}
	var result := pending_result.duplicate()
	pending_result.clear()
	return result
