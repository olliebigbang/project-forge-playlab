class_name WeaponInterpreter
extends RefCounted

func interpret(_player_text: String, _sketch_png: PackedByteArray, _geometry: Dictionary, _current: WeaponBlueprint = null, _modification: String = "", _clarification: String = "") -> Dictionary:
	push_error("WeaponInterpreter is an interface and cannot interpret directly.")
	return {"ok": false, "error": "INTERPRETER_NOT_CONFIGURED"}

func apply_delta(_current: WeaponBlueprint, _request: String) -> Dictionary:
	push_error("WeaponInterpreter is an interface and cannot apply changes directly.")
	return {"ok": false, "error": "INTERPRETER_NOT_CONFIGURED"}

