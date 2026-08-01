class_name WeaponImageGenerator
extends RefCounted

func generate(_blueprint: WeaponBlueprint, _sketch_image: Image = null, _geometry: Dictionary = {}) -> Dictionary:
	push_error("WeaponImageGenerator is an interface and cannot generate directly.")
	return {"ok": false, "error": "IMAGE_GENERATOR_NOT_CONFIGURED"}

