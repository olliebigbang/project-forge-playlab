class_name FirearmVisualScaffoldPipeline
extends RefCounted

const PIXEL_SCAFFOLD := preload("res://scripts/combat_feel/firearm_pixel_scaffold.gd")
const VISUAL_BRIEF := preload("res://scripts/combat_feel/firearm_visual_brief.gd")
const AXIS_RESOLVER := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")
const ANCHOR_RESOLVER := preload("res://scripts/systems/anchor_resolver.gd")
const VISUAL_IDENTITY_GATE := preload("res://scripts/combat_feel/firearm_visual_identity_gate.gd")
const VISUAL_IDENTITY_CARD := preload("res://scripts/combat_feel/firearm_visual_identity_card.gd")


static func prepare(blueprint: WeaponBlueprint) -> Dictionary:
	if blueprint == null or blueprint.behavior_family != "sustained_ranged":
		return _failure("FIREARM_SCAFFOLD_BLUEPRINT_UNSUPPORTED")
	var validation := AXIS_RESOLVER.validate_ai_declaration(
		blueprint.affordance,
		blueprint.affordance_source
	)
	if not bool(validation.get("ok", false)):
		return validation
	var identity_card := VISUAL_IDENTITY_CARD.compile(blueprint)
	if not bool(identity_card.get("ok", false)):
		return identity_card
	var brief := VISUAL_BRIEF.compile(
		blueprint.affordance,
		blueprint.affordance_source,
		identity_card
	)
	var brief_errors := VISUAL_BRIEF.validation_errors(brief)
	if not brief_errors.is_empty():
		return _failure(brief_errors[0])
	var built := PIXEL_SCAFFOLD.build(blueprint.affordance, blueprint.affordance_source)
	if not bool(built.get("ok", false)) or not built.get("image") is Image:
		return _failure(str(built.get("error", "FIREARM_PIXEL_SCAFFOLD_BUILD_FAILED")))
	var scaffold := (built.get("image") as Image).duplicate()
	var reference := scaffold.duplicate()
	reference.resize(384, 384, Image.INTERPOLATE_NEAREST)
	return {
		"ok": true,
		"automatic": true,
		"player_mechanism_input_used": false,
		"player_confirmation_required": false,
		"scaffold_image": scaffold,
		"reference_image": reference,
		"contract": (built.get("contract", {}) as Dictionary).duplicate(true),
		"visual_structure_brief": brief,
		"visual_identity_card": identity_card,
		"declaration": validation,
	}


static func persist_request_inputs(
	directory: String,
	run_id: String,
	preparation: Dictionary
) -> Dictionary:
	var absolute_directory := _absolute_path(directory)
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		return _failure("FIREARM_VISUAL_REQUEST_DIRECTORY_FAILED")
	var scaffold := preparation.get("scaffold_image") as Image
	var reference := preparation.get("reference_image") as Image
	if scaffold == null or reference == null:
		return _failure("FIREARM_VISUAL_REQUEST_IMAGE_MISSING")
	var safe_run_id := run_id.validate_filename()
	var scaffold_path := absolute_directory.path_join("%s.firearm_scaffold.png" % safe_run_id)
	var reference_path := absolute_directory.path_join("%s.firearm_reference.png" % safe_run_id)
	var contract_path := absolute_directory.path_join("%s.firearm_scaffold.json" % safe_run_id)
	var brief_path := absolute_directory.path_join("%s.firearm_visual_brief.json" % safe_run_id)
	if _save_png_atomic(scaffold, scaffold_path) != OK:
		return _failure("FIREARM_VISUAL_REQUEST_SCAFFOLD_WRITE_FAILED")
	if _save_png_atomic(reference, reference_path) != OK:
		return _failure("FIREARM_VISUAL_REQUEST_REFERENCE_WRITE_FAILED")
	if _write_json_atomic(contract_path, preparation.get("contract", {}) as Dictionary) != OK:
		return _failure("FIREARM_VISUAL_REQUEST_CONTRACT_WRITE_FAILED")
	if _write_json_atomic(brief_path, preparation.get("visual_structure_brief", {}) as Dictionary) != OK:
		return _failure("FIREARM_VISUAL_REQUEST_BRIEF_WRITE_FAILED")
	return {
		"ok": true,
		"scaffold_path": scaffold_path,
		"reference_path": reference_path,
		"contract_path": contract_path,
		"visual_structure_brief_path": brief_path,
	}


static func resolve_asset(
	image: Image,
	blueprint: WeaponBlueprint,
	preparation: Dictionary
) -> Dictionary:
	var contract := preparation.get("contract", {}) as Dictionary
	var brief := preparation.get("visual_structure_brief", {}) as Dictionary
	var gate := VISUAL_IDENTITY_GATE.evaluate(image, blueprint, contract, brief)
	if not bool(gate.get("ok", false)):
		return gate
	var asset: WeaponVisualAsset = ANCHOR_RESOLVER.resolve(image, blueprint)
	if asset == null:
		return _failure("FIREARM_VISUAL_ALPHA_INVALID")
	var anchors := gate.get("anchors", {}) as Dictionary
	asset.grip_primary = _vector_from_pair(anchors.get("GripPrimary", []))
	asset.grip_secondary = _vector_from_pair(anchors.get("GripSecondary", []))
	asset.muzzle = _vector_from_pair(anchors.get("Muzzle", []))
	asset.tip = _vector_from_pair(anchors.get("Tip", anchors.get("Muzzle", [])))
	asset.tether_origin = asset.muzzle
	asset.rear_contact = _vector_from_pair(anchors.get("RearContact", []))
	asset.anchor_confidence = 0.92
	asset.anchor_source = "firearm_ai_finished_art_gate_v1"
	return {
		"ok": true,
		"automatic": true,
		"finished_art": true,
		"player_confirmation_required": false,
		"asset": asset,
		"visual_identity_gate": gate,
		"contract": contract.duplicate(true),
	}


static func fallback(blueprint: WeaponBlueprint) -> Dictionary:
	var prepared := prepare(blueprint)
	if not bool(prepared.get("ok", false)):
		return prepared
	var image := prepared.get("scaffold_image") as Image
	var contract := prepared.get("contract", {}) as Dictionary
	var asset: WeaponVisualAsset = ANCHOR_RESOLVER.resolve(image, blueprint)
	if asset == null:
		return _failure("FIREARM_SCAFFOLD_ALPHA_INVALID")
	var anchors := contract.get("anchors", {}) as Dictionary
	asset.grip_primary = _vector_from_pair(anchors.get("GripPrimary", []))
	asset.grip_secondary = _vector_from_pair(anchors.get("GripSecondary", []))
	asset.muzzle = _vector_from_pair(anchors.get("Muzzle", []))
	asset.tip = _vector_from_pair(anchors.get("Tip", anchors.get("Muzzle", [])))
	asset.tether_origin = asset.muzzle
	asset.rear_contact = _vector_from_pair(anchors.get("RearContact", []))
	asset.anchor_confidence = 1.0
	asset.anchor_source = "ai_ranged_structure_contract"
	return {
		"ok": true,
		"automatic": true,
		"external_generator_succeeded": false,
		"finished_art": false,
		"scaffold_presentable": false,
		"player_mechanism_input_used": false,
		"player_confirmation_required": false,
		"asset": asset,
		"contract": contract.duplicate(true),
		"visual_structure_brief": (prepared.get("visual_structure_brief", {}) as Dictionary).duplicate(true),
		"scaffold_image": image.duplicate(),
		"reference_image": (prepared.get("reference_image") as Image).duplicate(),
	}


static func persist_generation_handoff(
	directory: String,
	preparation: Dictionary,
	resolution: Dictionary,
	manifest: Dictionary
) -> Dictionary:
	var absolute_directory := _absolute_path(directory)
	if absolute_directory.is_empty() or DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		return _failure("FIREARM_VISUAL_OUTPUT_DIRECTORY_FAILED")
	var scaffold := preparation.get("scaffold_image") as Image
	var reference := preparation.get("reference_image") as Image
	if scaffold == null or reference == null:
		return _failure("FIREARM_VISUAL_PERSIST_IMAGE_MISSING")
	var scaffold_path := absolute_directory.path_join("firearm_scaffold.png")
	var reference_path := absolute_directory.path_join("firearm_scaffold_reference.png")
	if _save_png_atomic(scaffold, scaffold_path) != OK:
		return _failure("FIREARM_VISUAL_PERSIST_SCAFFOLD_FAILED")
	if _save_png_atomic(reference, reference_path) != OK:
		return _failure("FIREARM_VISUAL_PERSIST_REFERENCE_FAILED")
	var contract := preparation.get("contract", {}) as Dictionary
	var brief := preparation.get("visual_structure_brief", {}) as Dictionary
	var gate := resolution.get("visual_identity_gate", {}) as Dictionary
	if _write_json_atomic(absolute_directory.path_join("firearm_scaffold.json"), contract) != OK:
		return _failure("FIREARM_VISUAL_PERSIST_CONTRACT_FAILED")
	if _write_json_atomic(absolute_directory.path_join("firearm_visual_brief.json"), brief) != OK:
		return _failure("FIREARM_VISUAL_PERSIST_BRIEF_FAILED")
	if _write_json_atomic(absolute_directory.path_join("firearm_visual_identity_gate.json"), gate) != OK:
		return _failure("FIREARM_VISUAL_PERSIST_GATE_FAILED")
	var asset := resolution.get("asset") as WeaponVisualAsset
	if asset == null:
		return _failure("FIREARM_VISUAL_PERSIST_ASSET_MISSING")
	var handoff := {
		"schema": "forge-firearm-finished-art-handoff-v1",
		"finished_art": true,
		"presentable_to_player": true,
		"scaffold_presentable": false,
		"structure_authority": "ai_ranged_axes",
		"generator_authority": "finished_identity_rendering_with_locked_roles",
		"external_generator_succeeded": true,
		"firearm_visual_gate_passed": true,
		"player_sketch_reference_used": false,
		"player_mechanism_input_used": false,
		"player_mechanism_confirmation_required": false,
		"visual_identity_confirmation_required": false,
		"anchors": asset.anchors_dict(),
		"visual_identity_gate": gate.duplicate(true),
		"firearm_scaffold_sha256": _sha256_file(scaffold_path),
		"firearm_scaffold_reference_sha256": _sha256_file(reference_path),
	}
	if _write_json_atomic(absolute_directory.path_join("firearm_finished_art_handoff.json"), handoff) != OK:
		return _failure("FIREARM_VISUAL_PERSIST_HANDOFF_FAILED")
	var updated_manifest := manifest.duplicate(true)
	updated_manifest["status"] = "success"
	updated_manifest["visual_mode"] = "firearm_ai_finished_pixel_art"
	updated_manifest["finished_art"] = true
	updated_manifest["presentable_to_player"] = true
	updated_manifest["scaffold_presentable"] = false
	updated_manifest["structure_authority"] = "ai_ranged_axes"
	updated_manifest["generator_authority"] = "finished_identity_rendering_with_locked_roles"
	updated_manifest["external_generator_succeeded"] = true
	updated_manifest["firearm_visual_gate_passed"] = true
	updated_manifest["player_mechanism_input_used"] = false
	updated_manifest["player_mechanism_confirmation_required"] = false
	updated_manifest["visual_identity_confirmation_required"] = false
	updated_manifest["firearm_scaffold_sha256"] = handoff["firearm_scaffold_sha256"]
	updated_manifest["firearm_scaffold_reference_sha256"] = handoff["firearm_scaffold_reference_sha256"]
	updated_manifest["firearm_visual_identity_gate"] = gate.duplicate(true)
	if _write_json_atomic(absolute_directory.path_join("manifest.json"), updated_manifest) != OK:
		return _failure("FIREARM_VISUAL_PERSIST_MANIFEST_FAILED")
	return {
		"ok": true,
		"output_directory": absolute_directory,
		"manifest": updated_manifest,
		"handoff": handoff,
	}


static func persist_generation_rejection(
	directory: String,
	preparation: Dictionary,
	resolution: Dictionary,
	manifest: Dictionary
) -> Dictionary:
	var absolute_directory := _absolute_path(directory)
	if absolute_directory.is_empty() or DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		return _failure("FIREARM_VISUAL_REJECTION_DIRECTORY_FAILED")
	var rejection := {
		"schema": "forge-firearm-finished-art-rejection-v1",
		"error": str(resolution.get("error", "FIREARM_VISUAL_OUTPUT_REJECTED")),
		"retry_required": bool(resolution.get("retry_required", true)),
		"finished_art": false,
		"presentable_to_player": false,
		"scaffold_presentable": false,
		"player_mechanism_confirmation_required": false,
		"metrics": (resolution.get("metrics", {}) as Dictionary).duplicate(true),
	}
	if _write_json_atomic(absolute_directory.path_join("firearm_visual_rejection.json"), rejection) != OK:
		return _failure("FIREARM_VISUAL_REJECTION_WRITE_FAILED")
	var updated_manifest := manifest.duplicate(true)
	updated_manifest["status"] = "failed"
	updated_manifest["failure_reason"] = rejection["error"]
	updated_manifest["visual_mode"] = "firearm_ai_output_rejected"
	updated_manifest["finished_art"] = false
	updated_manifest["presentable_to_player"] = false
	updated_manifest["scaffold_presentable"] = false
	updated_manifest["firearm_visual_gate_passed"] = false
	updated_manifest["firearm_visual_rejection"] = rejection.duplicate(true)
	updated_manifest["player_mechanism_confirmation_required"] = false
	if _write_json_atomic(absolute_directory.path_join("manifest.json"), updated_manifest) != OK:
		return _failure("FIREARM_VISUAL_REJECTION_MANIFEST_FAILED")
	return {"ok": true, "manifest": updated_manifest, "rejection": rejection}


static func persist_fallback(
	directory: String,
	blueprint: WeaponBlueprint,
	fallback_result: Dictionary,
	reason: String
) -> Dictionary:
	var asset := fallback_result.get("asset") as WeaponVisualAsset
	var scaffold := fallback_result.get("scaffold_image") as Image
	if asset == null or scaffold == null:
		return _failure("FIREARM_SCAFFOLD_FALLBACK_RESULT_INVALID")
	var absolute_directory := _absolute_path(directory)
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		return _failure("FIREARM_SCAFFOLD_FALLBACK_DIRECTORY_FAILED")
	var sprite_path := absolute_directory.path_join("processed_sprite.png")
	var save_error := scaffold.save_png(sprite_path)
	if save_error != OK:
		return _failure("FIREARM_SCAFFOLD_FALLBACK_SPRITE_FAILED:%d" % save_error)
	var contract := (fallback_result.get("contract", {}) as Dictionary).duplicate(true)
	var brief := (fallback_result.get("visual_structure_brief", {}) as Dictionary).duplicate(true)
	if _write_json(absolute_directory.path_join("firearm_structure_contract.json"), contract) != OK:
		return _failure("FIREARM_SCAFFOLD_CONTRACT_WRITE_FAILED")
	if _write_json(absolute_directory.path_join("visual_structure_brief.json"), brief) != OK:
		return _failure("FIREARM_SCAFFOLD_BRIEF_WRITE_FAILED")
	var manifest := {
		"status": "diagnostic_only",
		"contract": "forge-firearm-scaffold-diagnostic-v2",
		"visual_mode": "firearm_scaffold_diagnostic",
		"finished_art": false,
		"presentable_to_player": false,
		"fallback_reason": reason,
		"source_identity": blueprint.player_identity_text,
		"canonical_identity": blueprint.display_name,
		"behavior_family": blueprint.behavior_family,
		"ai_ranged_axes_source": blueprint.affordance_source,
		"player_mechanism_input_used": false,
		"player_mechanism_confirmation_required": false,
		"visual_identity_confirmation_required": true,
		"anchors": asset.anchors_dict(),
		"processed_sprite_sha256": _sha256_file(sprite_path),
	}
	if _write_json(absolute_directory.path_join("manifest.json"), manifest) != OK:
		return _failure("FIREARM_SCAFFOLD_MANIFEST_WRITE_FAILED")
	return {
		"ok": true,
		"output_directory": absolute_directory,
		"manifest": manifest,
	}


static func _vector_from_pair(value: Variant) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


static func _write_json(path: String, value: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(value, "  "))
	file.close()
	return OK


static func _save_png_atomic(image: Image, target: String) -> Error:
	var temporary := "%s.%s.tmp.png" % [target.trim_suffix(".png"), str(Time.get_ticks_usec())]
	var error := image.save_png(temporary)
	if error != OK:
		return error
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(target)
	error = DirAccess.rename_absolute(temporary, target)
	if error != OK and FileAccess.file_exists(temporary):
		DirAccess.remove_absolute(temporary)
	return error


static func _write_json_atomic(target: String, value: Dictionary) -> Error:
	var temporary := "%s.%s.tmp" % [target, str(Time.get_ticks_usec())]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(value, "  "))
	file.close()
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(target)
	var error := DirAccess.rename_absolute(temporary, target)
	if error != OK and FileAccess.file_exists(temporary):
		DirAccess.remove_absolute(temporary)
	return error


static func _sha256_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	while file.get_position() < file.get_length():
		context.update(file.get_buffer(mini(65536, file.get_length() - file.get_position())))
	return context.finish().hex_encode()


static func _absolute_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path.simplify_path()


static func _failure(error: String) -> Dictionary:
	return {
		"ok": false,
		"error": error,
		"retry_required": true,
		"player_confirmation_required": false,
	}
