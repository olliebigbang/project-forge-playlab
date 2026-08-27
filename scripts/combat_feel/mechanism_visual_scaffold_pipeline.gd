class_name MechanismVisualScaffoldPipeline
extends RefCounted

const PIXEL_SCAFFOLD := preload("res://scripts/combat_feel/mechanism_pixel_scaffold.gd")
const VISUAL_BRIEF := preload("res://scripts/combat_feel/mechanism_visual_brief.gd")
const AXIS_RESOLVER := preload("res://scripts/combat_feel/mechanism_axis_resolver.gd")
const ANCHOR_RESOLVER := preload("res://scripts/systems/anchor_resolver.gd")

const CANVAS_SIZE := Vector2i(96, 96)
const REFERENCE_SIZE := Vector2i(512, 512)
const CHROMA_BACKGROUND := Color("ff26ff")
const ALPHA_THRESHOLD := 0.10
const MIN_OPAQUE_RATIO := 0.01
const MAX_OPAQUE_RATIO := 0.48
const MIN_SCAFFOLD_ALPHA_IOU := 0.18
const MAX_ANCHOR_SEARCH_PIXELS := 12


static func prepare(blueprint: WeaponBlueprint) -> Dictionary:
	if blueprint == null or blueprint.behavior_family != "heavy_melee":
		return _failure("MECHANISM_SCAFFOLD_BLUEPRINT_UNSUPPORTED")
	var declaration := AXIS_RESOLVER.validate_ai_declaration(
		blueprint.affordance,
		blueprint.affordance_source
	)
	if not bool(declaration.get("ok", false)):
		return declaration
	var brief := VISUAL_BRIEF.compile(blueprint.affordance, blueprint.affordance_source)
	var brief_errors := VISUAL_BRIEF.validation_errors(brief)
	if not brief_errors.is_empty():
		return _failure(str(brief_errors[0]))
	var built := PIXEL_SCAFFOLD.build(blueprint.affordance)
	if not bool(built.get("ok", false)) or not built.get("image") is Image:
		return _failure(str(built.get("error", "MECHANISM_PIXEL_SCAFFOLD_BUILD_FAILED")))
	var scaffold := (built.get("image") as Image).duplicate()
	var contract: Dictionary = (built.get("contract", {}) as Dictionary).duplicate(true)
	contract["scaffold_rgba_sha256"] = _bytes_sha256(scaffold.get_data())
	contract["reference_background"] = CHROMA_BACKGROUND.to_html(false)
	contract["reference_size"] = [REFERENCE_SIZE.x, REFERENCE_SIZE.y]
	contract["structure_authority"] = "mechanism_axes"
	contract["generator_authority"] = "style_and_color_only"
	return {
		"ok": true,
		"automatic": true,
		"player_mechanism_input_used": false,
		"player_confirmation_required": false,
		"structure_authority": "mechanism_axes",
		"generator_authority": "style_and_color_only",
		"scaffold_image": scaffold,
		"reference_image": _build_reference_image(scaffold),
		"palette_image": PIXEL_SCAFFOLD.palette_image(),
		"contract": contract,
		"visual_structure_brief": brief,
		"declaration": declaration,
	}


static func resolve_asset(
	image: Image,
	blueprint: WeaponBlueprint,
	contract_override: Dictionary = {}
) -> Dictionary:
	var prepared := prepare(blueprint)
	if not bool(prepared.get("ok", false)):
		return prepared
	var expected := prepared.get("scaffold_image") as Image
	var contract: Dictionary = contract_override.duplicate(true)
	if contract.is_empty():
		contract = (prepared.get("contract", {}) as Dictionary).duplicate(true)
	var preflight := _preflight(image, expected)
	if not bool(preflight.get("ok", false)):
		return {
			"ok": false,
			"error": str(preflight.get("error", "MECHANISM_SCAFFOLD_PREFLIGHT_FAILED")),
			"retry_required": true,
			"player_confirmation_required": false,
			"preflight": preflight,
		}
	var asset: WeaponVisualAsset = ANCHOR_RESOLVER.resolve(image, blueprint)
	if asset == null:
		return _failure("MECHANISM_SCAFFOLD_ALPHA_INVALID")
	var anchors: Dictionary = contract.get("anchors", {})
	var grip_expected := _vector_from_pair(anchors.get("GripPrimary", []))
	var strike_expected := _vector_from_pair(anchors.get("StrikePoint", []))
	var tether_expected := _vector_from_pair(anchors.get("TetherOrigin", []))
	var grip := _nearest_opaque(image, grip_expected, MAX_ANCHOR_SEARCH_PIXELS)
	var strike := _nearest_opaque(image, strike_expected, MAX_ANCHOR_SEARCH_PIXELS)
	var tether_origin := _nearest_opaque(image, tether_expected, MAX_ANCHOR_SEARCH_PIXELS)
	if grip.x < 0.0:
		return _anchor_failure("GripPrimary", grip_expected, preflight)
	if strike.x < 0.0:
		return _anchor_failure("StrikePoint", strike_expected, preflight)
	if tether_origin.x < 0.0:
		return _anchor_failure("TetherOrigin", tether_expected, preflight)
	asset.grip_primary = grip
	asset.tip = strike
	asset.tether_origin = tether_origin
	var secondary_expected := grip.lerp(tether_origin, 0.18)
	var secondary := _nearest_opaque(image, secondary_expected, MAX_ANCHOR_SEARCH_PIXELS)
	asset.grip_secondary = grip if secondary.x < 0.0 else secondary
	asset.spin_pivot = ANCHOR_RESOLVER.alpha_centroid(image, asset.opaque_bounds)
	var maximum_anchor_drift := maxf(
		grip.distance_to(grip_expected),
		maxf(strike.distance_to(strike_expected), tether_origin.distance_to(tether_expected))
	)
	asset.anchor_confidence = clampf(1.0 - maximum_anchor_drift / float(MAX_ANCHOR_SEARCH_PIXELS * 2), 0.50, 1.0)
	asset.anchor_source = "mechanism_scaffold_contract+nearest_real_alpha"
	return {
		"ok": true,
		"automatic": true,
		"player_confirmation_required": false,
		"asset": asset,
		"preflight": preflight,
		"contract": contract,
		"anchor_drift_pixels": {
			"GripPrimary": grip.distance_to(grip_expected),
			"StrikePoint": strike.distance_to(strike_expected),
			"TetherOrigin": tether_origin.distance_to(tether_expected),
		},
	}


static func fallback(blueprint: WeaponBlueprint) -> Dictionary:
	var prepared := prepare(blueprint)
	if not bool(prepared.get("ok", false)):
		return prepared
	var resolved := resolve_asset(
		prepared.get("scaffold_image") as Image,
		blueprint,
		prepared.get("contract", {}) as Dictionary
	)
	if not bool(resolved.get("ok", false)):
		return resolved
	return {
		"ok": true,
		"automatic": true,
		"external_generator_succeeded": false,
		"player_mechanism_input_used": false,
		"player_confirmation_required": false,
		"asset": resolved.get("asset") as WeaponVisualAsset,
		"preflight": (resolved.get("preflight", {}) as Dictionary).duplicate(true),
		"anchor_drift_pixels": (resolved.get("anchor_drift_pixels", {}) as Dictionary).duplicate(true),
		"contract": (prepared.get("contract", {}) as Dictionary).duplicate(true),
		"visual_structure_brief": (prepared.get("visual_structure_brief", {}) as Dictionary).duplicate(true),
		"scaffold_image": (prepared.get("scaffold_image") as Image).duplicate(),
		"reference_image": (prepared.get("reference_image") as Image).duplicate(),
	}


static func persist_request_inputs(
	directory: String,
	run_id: String,
	preparation: Dictionary
) -> Dictionary:
	var absolute_directory := _absolute_path(directory)
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		return _failure("MECHANISM_SCAFFOLD_REQUEST_DIRECTORY_FAILED")
	var scaffold := preparation.get("scaffold_image") as Image
	var reference := preparation.get("reference_image") as Image
	var palette := preparation.get("palette_image") as Image
	if scaffold == null or reference == null or palette == null:
		return _failure("MECHANISM_SCAFFOLD_REQUEST_IMAGE_MISSING")
	var safe_run_id := run_id.validate_filename()
	var scaffold_path := absolute_directory.path_join("%s.mechanism_scaffold.png" % safe_run_id)
	var reference_path := absolute_directory.path_join("%s.mechanism_reference.png" % safe_run_id)
	var palette_path := absolute_directory.path_join("%s.mechanism_palette.png" % safe_run_id)
	var contract_path := absolute_directory.path_join("%s.mechanism_scaffold.json" % safe_run_id)
	var brief_path := absolute_directory.path_join("%s.visual_structure_brief.json" % safe_run_id)
	for item: Array in [
		[scaffold, scaffold_path],
		[reference, reference_path],
		[palette, palette_path],
	]:
		var save_error := _save_png_atomic(item[0] as Image, str(item[1]))
		if save_error != OK:
			return _failure("MECHANISM_SCAFFOLD_REQUEST_PNG_FAILED:%d" % save_error)
	if _write_json_atomic(contract_path, preparation.get("contract", {}) as Dictionary) != OK:
		return _failure("MECHANISM_SCAFFOLD_REQUEST_CONTRACT_FAILED")
	if _write_json_atomic(brief_path, preparation.get("visual_structure_brief", {}) as Dictionary) != OK:
		return _failure("MECHANISM_SCAFFOLD_REQUEST_BRIEF_FAILED")
	return {
		"ok": true,
		"scaffold_path": scaffold_path,
		"reference_path": reference_path,
		"palette_path": palette_path,
		"contract_path": contract_path,
		"visual_structure_brief_path": brief_path,
	}


static func persist_generation_handoff(
	directory: String,
	preparation: Dictionary,
	resolution: Dictionary,
	manifest: Dictionary,
	external_generator_succeeded: bool
) -> Dictionary:
	var absolute_directory := _absolute_path(directory)
	if absolute_directory.is_empty():
		return _failure("MECHANISM_SCAFFOLD_OUTPUT_DIRECTORY_MISSING")
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		return _failure("MECHANISM_SCAFFOLD_OUTPUT_DIRECTORY_FAILED")
	var scaffold := preparation.get("scaffold_image") as Image
	var reference := preparation.get("reference_image") as Image
	if scaffold == null or reference == null:
		return _failure("MECHANISM_SCAFFOLD_PERSIST_IMAGE_MISSING")
	var scaffold_path := absolute_directory.path_join("mechanism_scaffold.png")
	var reference_path := absolute_directory.path_join("mechanism_scaffold_reference.png")
	var save_error := _save_png_atomic(scaffold, scaffold_path)
	if save_error != OK:
		return _failure("MECHANISM_SCAFFOLD_PERSIST_PNG_FAILED:%d" % save_error)
	save_error = _save_png_atomic(reference, reference_path)
	if save_error != OK:
		return _failure("MECHANISM_SCAFFOLD_REFERENCE_PERSIST_PNG_FAILED:%d" % save_error)
	var contract: Dictionary = (preparation.get("contract", {}) as Dictionary).duplicate(true)
	var brief: Dictionary = (preparation.get("visual_structure_brief", {}) as Dictionary).duplicate(true)
	if _write_json_atomic(absolute_directory.path_join("mechanism_scaffold.json"), contract) != OK:
		return _failure("MECHANISM_SCAFFOLD_CONTRACT_PERSIST_FAILED")
	if _write_json_atomic(absolute_directory.path_join("visual_structure_brief.json"), brief) != OK:
		return _failure("MECHANISM_SCAFFOLD_BRIEF_PERSIST_FAILED")
	var asset := resolution.get("asset") as WeaponVisualAsset
	if asset == null:
		return _failure("MECHANISM_SCAFFOLD_PERSIST_ASSET_MISSING")
	var handoff := {
		"schema": "forge-mechanism-scaffold-handoff-v1",
		"structure_authority": "mechanism_axes",
		"generator_authority": "style_and_color_only" if external_generator_succeeded else "none",
		"external_generator_succeeded": external_generator_succeeded,
		"mechanism_scaffold_reference_used": external_generator_succeeded,
		"player_sketch_reference_used": false,
		"player_mechanism_input_used": false,
		"player_mechanism_confirmation_required": false,
		"visual_identity_confirmation_required": true,
		"preflight": (resolution.get("preflight", {}) as Dictionary).duplicate(true),
		"anchor_drift_pixels": (resolution.get("anchor_drift_pixels", {}) as Dictionary).duplicate(true),
		"anchors": asset.anchors_dict(),
		"mechanism_scaffold_sha256": _sha256_file(scaffold_path),
		"mechanism_scaffold_reference_sha256": _sha256_file(reference_path),
	}
	if _write_json_atomic(absolute_directory.path_join("mechanism_scaffold_handoff.json"), handoff) != OK:
		return _failure("MECHANISM_SCAFFOLD_HANDOFF_PERSIST_FAILED")
	var updated_manifest := manifest.duplicate(true)
	updated_manifest["mechanism_scaffold_reference_used"] = external_generator_succeeded
	updated_manifest["structure_authority"] = "mechanism_axes"
	updated_manifest["generator_authority"] = "style_and_color_only" if external_generator_succeeded else "none"
	updated_manifest["external_generator_succeeded"] = external_generator_succeeded
	updated_manifest["player_sketch_reference_used"] = false
	updated_manifest["player_mechanism_input_used"] = false
	updated_manifest["player_mechanism_confirmation_required"] = false
	updated_manifest["visual_identity_confirmation_required"] = true
	updated_manifest["mechanism_scaffold_sha256"] = handoff["mechanism_scaffold_sha256"]
	updated_manifest["mechanism_scaffold_reference_sha256"] = handoff["mechanism_scaffold_reference_sha256"]
	updated_manifest["mechanism_scaffold_preflight"] = handoff["preflight"]
	if _write_json_atomic(absolute_directory.path_join("manifest.json"), updated_manifest) != OK:
		return _failure("MECHANISM_SCAFFOLD_MANIFEST_PERSIST_FAILED")
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
		return _failure("MECHANISM_SCAFFOLD_REJECTION_DIRECTORY_FAILED")
	var scaffold := preparation.get("scaffold_image") as Image
	var reference := preparation.get("reference_image") as Image
	if scaffold == null or reference == null:
		return _failure("MECHANISM_SCAFFOLD_REJECTION_IMAGE_MISSING")
	var scaffold_path := absolute_directory.path_join("mechanism_scaffold.png")
	var reference_path := absolute_directory.path_join("mechanism_scaffold_reference.png")
	if _save_png_atomic(scaffold, scaffold_path) != OK:
		return _failure("MECHANISM_SCAFFOLD_REJECTION_SCAFFOLD_PERSIST_FAILED")
	if _save_png_atomic(reference, reference_path) != OK:
		return _failure("MECHANISM_SCAFFOLD_REJECTION_REFERENCE_PERSIST_FAILED")
	if _write_json_atomic(
		absolute_directory.path_join("mechanism_scaffold.json"),
		preparation.get("contract", {}) as Dictionary
	) != OK:
		return _failure("MECHANISM_SCAFFOLD_REJECTION_CONTRACT_PERSIST_FAILED")
	if _write_json_atomic(
		absolute_directory.path_join("visual_structure_brief.json"),
		preparation.get("visual_structure_brief", {}) as Dictionary
	) != OK:
		return _failure("MECHANISM_SCAFFOLD_REJECTION_BRIEF_PERSIST_FAILED")
	var rejection := {
		"schema": "forge-mechanism-scaffold-rejection-v1",
		"error": str(resolution.get("error", "MECHANISM_SCAFFOLD_OUTPUT_REJECTED")),
		"retry_required": bool(resolution.get("retry_required", true)),
		"structure_authority": "mechanism_axes",
		"generator_authority": "style_and_color_only",
		"external_generator_completed": true,
		"mechanism_output_accepted": false,
		"mechanism_scaffold_reference_used": true,
		"player_sketch_reference_used": false,
		"player_mechanism_confirmation_required": false,
		"preflight": (resolution.get("preflight", {}) as Dictionary).duplicate(true),
		"mechanism_scaffold_sha256": _sha256_file(scaffold_path),
		"mechanism_scaffold_reference_sha256": _sha256_file(reference_path),
	}
	if _write_json_atomic(absolute_directory.path_join("mechanism_scaffold_rejection.json"), rejection) != OK:
		return _failure("MECHANISM_SCAFFOLD_REJECTION_EVIDENCE_PERSIST_FAILED")
	var updated_manifest := manifest.duplicate(true)
	updated_manifest["mechanism_acceptance_status"] = "rejected"
	updated_manifest["mechanism_output_accepted"] = false
	updated_manifest["mechanism_rejection_error"] = rejection["error"]
	updated_manifest["mechanism_scaffold_preflight"] = rejection["preflight"]
	updated_manifest["mechanism_scaffold_reference_used"] = true
	updated_manifest["structure_authority"] = "mechanism_axes"
	updated_manifest["generator_authority"] = "style_and_color_only"
	updated_manifest["external_generator_completed"] = true
	updated_manifest["external_generator_succeeded"] = false
	updated_manifest["player_sketch_reference_used"] = false
	updated_manifest["player_mechanism_confirmation_required"] = false
	if _write_json_atomic(absolute_directory.path_join("manifest.json"), updated_manifest) != OK:
		return _failure("MECHANISM_SCAFFOLD_REJECTION_MANIFEST_PERSIST_FAILED")
	return {
		"ok": true,
		"manifest": updated_manifest,
		"rejection": rejection,
	}


static func persist_fallback(
	directory: String,
	blueprint: WeaponBlueprint,
	fallback_result: Dictionary,
	reason: String
) -> Dictionary:
	var asset := fallback_result.get("asset") as WeaponVisualAsset
	var scaffold := fallback_result.get("scaffold_image") as Image
	if asset == null or scaffold == null:
		return _failure("MECHANISM_SCAFFOLD_FALLBACK_RESULT_INVALID")
	var absolute_directory := _absolute_path(directory)
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		return _failure("MECHANISM_SCAFFOLD_FALLBACK_DIRECTORY_FAILED")
	var sprite_path := absolute_directory.path_join("processed_sprite.png")
	var sprite_error := _save_png_atomic(scaffold, sprite_path)
	if sprite_error != OK:
		return _failure("MECHANISM_SCAFFOLD_FALLBACK_SPRITE_PERSIST_FAILED:%d" % sprite_error)
	var prompt := blueprint.visual_prompt.strip_edges()
	if prompt.is_empty():
		prompt = blueprint.player_identity_text.strip_edges()
	var manifest := {
		"status": "success",
		"contract": "forge-mechanism-scaffold-fallback-v1",
		"visual_mode": "mechanism_scaffold_fallback",
		"fallback_reason": reason,
		"generation_prompt": prompt,
		"positive_prompt": prompt,
		"source_identity": blueprint.player_identity_text,
		"processed_sprite_sha256": _sha256_file(sprite_path),
	}
	var preparation := {
		"scaffold_image": scaffold,
		"reference_image": fallback_result.get("reference_image") as Image,
		"contract": (fallback_result.get("contract", {}) as Dictionary).duplicate(true),
		"visual_structure_brief": (fallback_result.get("visual_structure_brief", {}) as Dictionary).duplicate(true),
	}
	return persist_generation_handoff(
		absolute_directory,
		preparation,
		fallback_result,
		manifest,
		false
	)


static func _preflight(image: Image, expected: Image) -> Dictionary:
	if image == null or image.is_empty():
		return {"ok": false, "error": "MECHANISM_SCAFFOLD_IMAGE_MISSING"}
	if image.get_size() != CANVAS_SIZE:
		return {
			"ok": false,
			"error": "MECHANISM_SCAFFOLD_IMAGE_MUST_BE_96X96",
			"actual_size": [image.get_width(), image.get_height()],
		}
	var opaque_pixels := 0
	var transparent_pixels := 0
	var semitransparent_pixels := 0
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var alpha := image.get_pixel(x, y).a
			if alpha > ALPHA_THRESHOLD:
				opaque_pixels += 1
			else:
				transparent_pixels += 1
			if alpha > 0.01 and alpha < 0.99:
				semitransparent_pixels += 1
	var pixel_count := image.get_width() * image.get_height()
	var opaque_ratio := float(opaque_pixels) / float(maxi(1, pixel_count))
	var alpha_iou := _alpha_iou(image, expected)
	var result := {
		"ok": true,
		"canvas": [image.get_width(), image.get_height()],
		"opaque_pixels": opaque_pixels,
		"transparent_pixels": transparent_pixels,
		"semitransparent_pixels": semitransparent_pixels,
		"opaque_ratio": opaque_ratio,
		"scaffold_alpha_iou": alpha_iou,
		"minimum_scaffold_alpha_iou": MIN_SCAFFOLD_ALPHA_IOU,
		"maximum_opaque_ratio": MAX_OPAQUE_RATIO,
	}
	if transparent_pixels == 0:
		result["ok"] = false
		result["error"] = "MECHANISM_SCAFFOLD_TRANSPARENCY_MISSING"
	elif semitransparent_pixels > 0:
		result["ok"] = false
		result["error"] = "MECHANISM_SCAFFOLD_ALPHA_MUST_BE_BINARY"
	elif opaque_ratio < MIN_OPAQUE_RATIO:
		result["ok"] = false
		result["error"] = "MECHANISM_SCAFFOLD_TOO_FEW_OPAQUE_PIXELS"
	elif opaque_ratio > MAX_OPAQUE_RATIO:
		result["ok"] = false
		result["error"] = "MECHANISM_SCAFFOLD_TOO_MANY_OPAQUE_PIXELS"
	elif alpha_iou < MIN_SCAFFOLD_ALPHA_IOU:
		result["ok"] = false
		result["error"] = "MECHANISM_SCAFFOLD_ALPHA_IOU_TOO_LOW"
	return result


static func _alpha_iou(left: Image, right: Image) -> float:
	if left == null or right == null or left.get_size() != right.get_size():
		return 0.0
	var intersection := 0
	var union := 0
	for y: int in range(left.get_height()):
		for x: int in range(left.get_width()):
			var left_opaque := left.get_pixel(x, y).a > ALPHA_THRESHOLD
			var right_opaque := right.get_pixel(x, y).a > ALPHA_THRESHOLD
			if left_opaque and right_opaque:
				intersection += 1
			if left_opaque or right_opaque:
				union += 1
	return float(intersection) / float(maxi(1, union))


static func _build_reference_image(scaffold: Image) -> Image:
	var reference := Image.create(CANVAS_SIZE.x, CANVAS_SIZE.y, false, Image.FORMAT_RGBA8)
	reference.fill(CHROMA_BACKGROUND)
	for y: int in range(scaffold.get_height()):
		for x: int in range(scaffold.get_width()):
			var pixel := scaffold.get_pixel(x, y)
			if pixel.a > ALPHA_THRESHOLD:
				reference.set_pixel(x, y, Color(pixel.r, pixel.g, pixel.b, 1.0))
	reference.resize(REFERENCE_SIZE.x, REFERENCE_SIZE.y, Image.INTERPOLATE_NEAREST)
	return reference


static func _nearest_opaque(image: Image, desired: Vector2, radius: int) -> Vector2:
	var best := Vector2(-1.0, -1.0)
	var best_distance := INF
	var center := Vector2i(desired.round())
	for y: int in range(maxi(0, center.y - radius), mini(image.get_height(), center.y + radius + 1)):
		for x: int in range(maxi(0, center.x - radius), mini(image.get_width(), center.x + radius + 1)):
			if image.get_pixel(x, y).a <= ALPHA_THRESHOLD:
				continue
			var distance := Vector2(x, y).distance_squared_to(desired)
			if distance < best_distance:
				best_distance = distance
				best = Vector2(x, y)
	return best


static func _vector_from_pair(value: Variant) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


static func _anchor_failure(anchor: String, expected: Vector2, preflight: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"error": "MECHANISM_SCAFFOLD_ANCHOR_ALPHA_MISSING:%s" % anchor,
		"anchor": anchor,
		"expected": [expected.x, expected.y],
		"retry_required": true,
		"player_confirmation_required": false,
		"preflight": preflight,
	}


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


static func _bytes_sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
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
