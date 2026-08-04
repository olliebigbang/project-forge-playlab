class_name ForgeVisualProvider
extends RefCounted

const MODE_MOCK := "MOCK"
const MODE_LOCAL_COMFYUI := "LOCAL_COMFYUI"

var request_revision := 0

func health_check() -> Dictionary:
	return {"ok": true}

func request_visual(
	_blueprint: WeaponBlueprint,
	_prompt: String,
	_sketch_png: PackedByteArray,
	_control_strength: float = 0.45
) -> int:
	request_revision += 1
	return request_revision

func poll() -> Dictionary:
	return {"status": "idle"}

func cancel_current() -> void:
	request_revision += 1

func accepts_revision(revision: int) -> bool:
	return revision == request_revision
