class_name FalGeneralObjectVisualProvider
extends "res://scripts/services/forge_visual_provider.gd"

const VISUAL_BRIEF := preload("res://scripts/combat_feel/mechanism_visual_brief.gd")
const ANCHOR_RESOLVER := preload("res://scripts/systems/anchor_resolver.gd")
const BRIDGE_SCRIPT := "res://tools/visual/fal_general_object_pixel_bridge.py"
const REQUEST_SCHEMA := "forge-fal-general-object-visual-request-v1"
const MANIFEST_SCHEMA := "forge-fal-general-object-visual-manifest-v1"
const OUTPUT_ROOT := "user://playlab/fal_general_object_visual/requests"
const CACHE_ROOT := "user://playlab/fal_general_object_visual/cache_v1"
const CACHE_SCHEMA := "forge-fal-general-object-visual-cache-v1"
const PIPELINE_VERSION := "fal-gpt-image-1.5-general-object-image2pixel24-v1"
const PROVIDER_ID := "FAL_GENERAL_OBJECT"
const CANVAS_SIZE := Vector2i(96, 96)
const SUBJECT_SPAN := 82

var python_executable := "python"
var timeout_seconds := 240.0
var process_id := -1
var active_revision := 0
var active_blueprint: WeaponBlueprint
var active_output_directory := ""
var active_request_payload: Dictionary = {}
var active_cache_key := ""
var active_cache_hit := false
var started_msec := 0
var process_exited_msec := 0
var delivered := true
var failure_reason := ""


func configure(next_python_executable: String = "python") -> Dictionary:
	python_executable = next_python_executable.strip_edges()
	if python_executable.is_empty():
		python_executable = "python"
	var bridge_path := ProjectSettings.globalize_path(BRIDGE_SCRIPT)
	if not FileAccess.file_exists(bridge_path):
		return _failure("GENERAL_OBJECT_VISUAL_FAL_BRIDGE_MISSING", false)
	if not OS.has_environment("FAL_KEY") and not OS.has_environment("FAL_API_KEY"):
		return _failure("GENERAL_OBJECT_VISUAL_FAL_KEY_MISSING", false)
	return {"ok": true, "provider": PROVIDER_ID, "bridge_path": bridge_path}


func health_check() -> Dictionary:
	return configure(python_executable)


func request_visual(
	blueprint: WeaponBlueprint,
	_prompt: String,
	_sketch_png: PackedByteArray,
	_control_strength: float = 0.45
) -> int:
	cancel_current()
	request_revision += 1
	active_revision = request_revision
	active_blueprint = blueprint
	delivered = false
	failure_reason = ""
	started_msec = Time.get_ticks_msec()
	process_exited_msec = 0
	active_cache_hit = false
	active_cache_key = ""
	active_request_payload.clear()
	if not _is_supported_blueprint(blueprint):
		failure_reason = "GENERAL_OBJECT_VISUAL_FAL_REQUIRES_MELEE_OBJECT"
		return active_revision
	var brief := VISUAL_BRIEF.compile(blueprint.affordance, blueprint.affordance_source)
	var brief_errors := VISUAL_BRIEF.validation_errors(brief)
	if not brief_errors.is_empty():
		failure_reason = str(brief_errors[0])
		return active_revision
	blueprint.visual_structure_brief = brief.duplicate(true)
	blueprint.visual_structure_brief_source = str(brief.get("source", ""))
	active_request_payload = _build_request_payload(blueprint, brief)
	active_cache_key = _cache_key(active_request_payload)
	var cache_directory := _absolute_path(CACHE_ROOT.path_join(active_cache_key))
	if _cache_entry_valid(cache_directory, active_cache_key):
		active_output_directory = cache_directory
		active_cache_hit = true
		process_id = -1
		return active_revision
	var run_id := "request_%d_r%d" % [roundi(Time.get_unix_time_from_system() * 1000.0), active_revision]
	active_output_directory = ProjectSettings.globalize_path(OUTPUT_ROOT.path_join(run_id))
	if DirAccess.make_dir_recursive_absolute(active_output_directory) != OK:
		failure_reason = "GENERAL_OBJECT_VISUAL_FAL_OUTPUT_DIRECTORY_FAILED"
		return active_revision
	var request_path := active_output_directory.path_join("request.json")
	if _write_json_atomic(request_path, active_request_payload) != OK:
		failure_reason = "GENERAL_OBJECT_VISUAL_FAL_REQUEST_WRITE_FAILED"
		return active_revision
	var arguments: Array[String] = [
		"-E", "-S", "-B",
		ProjectSettings.globalize_path(BRIDGE_SCRIPT),
		"--request", request_path,
		"--output-dir", active_output_directory,
	]
	process_id = OS.create_process(python_executable, arguments)
	if process_id <= 0:
		failure_reason = "GENERAL_OBJECT_VISUAL_FAL_PROCESS_START_FAILED"
	return active_revision


func poll() -> Dictionary:
	if active_revision <= 0 or delivered:
		return {"status": "idle"}
	if not failure_reason.is_empty():
		delivered = true
		return _failure(failure_reason, false)
	if Time.get_ticks_msec() - started_msec > int(timeout_seconds * 1000.0):
		if process_id > 0 and OS.is_process_running(process_id):
			OS.kill(process_id)
		delivered = true
		return _failure("GENERAL_OBJECT_VISUAL_FAL_TIMEOUT", true)
	var manifest_path := active_output_directory.path_join("manifest.json")
	if FileAccess.file_exists(manifest_path):
		return _load_completed_result(manifest_path)
	if process_id > 0 and OS.is_process_running(process_id):
		return {"status": "running", "revision": active_revision, "provider": PROVIDER_ID}
	if process_id > 0:
		if process_exited_msec == 0:
			process_exited_msec = Time.get_ticks_msec()
			return {"status": "running", "revision": active_revision, "provider": PROVIDER_ID}
		if Time.get_ticks_msec() - process_exited_msec < 1200:
			return {"status": "running", "revision": active_revision, "provider": PROVIDER_ID}
		delivered = true
		return _failure("GENERAL_OBJECT_VISUAL_FAL_EXITED_WITHOUT_MANIFEST", true)
	return {"status": "running", "revision": active_revision, "provider": PROVIDER_ID}


func load_atomic_result(directory: String, blueprint: WeaponBlueprint) -> Dictionary:
	active_blueprint = blueprint
	var brief := VISUAL_BRIEF.compile(blueprint.affordance, blueprint.affordance_source)
	active_request_payload = _build_request_payload(blueprint, brief)
	active_cache_key = _cache_key(active_request_payload)
	active_cache_hit = false
	active_output_directory = _absolute_path(directory)
	active_revision = request_revision
	delivered = false
	return _load_completed_result(active_output_directory.path_join("manifest.json"))


func cancel_current() -> void:
	super.cancel_current()
	if process_id > 0 and OS.is_process_running(process_id):
		OS.kill(process_id)
	process_id = -1
	process_exited_msec = 0
	active_revision = 0
	delivered = true
	active_request_payload.clear()
	active_cache_key = ""
	active_cache_hit = false


func _load_completed_result(manifest_path: String) -> Dictionary:
	if not accepts_revision(active_revision):
		delivered = true
		return _failure("STALE_RESULT_IGNORED", false)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary:
		delivered = true
		return _failure("GENERAL_OBJECT_VISUAL_FAL_MANIFEST_INVALID_JSON", false)
	var manifest := parsed as Dictionary
	if str(manifest.get("schema", "")) != MANIFEST_SCHEMA:
		delivered = true
		return _failure("GENERAL_OBJECT_VISUAL_FAL_MANIFEST_SCHEMA_INVALID", false)
	if str(manifest.get("status", "")) != "success":
		delivered = true
		return _failure(str(manifest.get("failure_reason", "GENERAL_OBJECT_VISUAL_FAL_GENERATION_FAILED")), false)
	var normalized: Dictionary
	var candidate_source := "fal_image2pixel"
	if active_cache_hit:
		normalized = _load_normalized_candidate(active_output_directory.path_join("processed_sprite.png"))
	else:
		normalized = _normalize_pixel_candidate(
			active_output_directory.path_join("raw_pixel_art.png"),
			active_output_directory.path_join("processed_sprite.png")
		)
		if not bool(normalized.get("ok", false)):
			normalized = _normalize_pixel_candidate(
				active_output_directory.path_join("ai_raw.png"),
				active_output_directory.path_join("processed_sprite.png")
			)
			candidate_source = "fal_transparent_identity_art_local_pixel_fallback"
	if not bool(normalized.get("ok", false)):
		delivered = true
		return _failure(str(normalized.get("error", "GENERAL_OBJECT_VISUAL_FAL_NORMALIZE_FAILED")), true)
	var image := normalized.get("image") as Image
	var asset: WeaponVisualAsset = ANCHOR_RESOLVER.resolve(image, active_blueprint)
	if asset == null:
		delivered = true
		return _failure("GENERAL_OBJECT_VISUAL_FAL_ALPHA_INVALID", true)
	_apply_mechanism_anchor_intent(asset, active_blueprint)
	asset.tether_origin = asset.tip
	manifest["candidate_source"] = candidate_source
	manifest["cache"] = {
		"schema": CACHE_SCHEMA,
		"hit": active_cache_hit,
		"key": active_cache_key,
		"pipeline_version": PIPELINE_VERSION,
	}
	manifest["local_pixel_normalization"] = {
		"source_size": normalized.get("source_size", []),
		"source_bounds": normalized.get("source_bounds", []),
		"processed_bounds": normalized.get("processed_bounds", []),
		"opaque_colors_before": normalized.get("opaque_colors_before", 0),
		"opaque_colors_after": normalized.get("opaque_colors_after", 0),
	}
	if _write_json_atomic(manifest_path, manifest) != OK:
		delivered = true
		return _failure("GENERAL_OBJECT_VISUAL_FAL_MANIFEST_UPDATE_FAILED", false)
	delivered = true
	if not active_cache_hit:
		_persist_cache(active_output_directory, manifest)
	return {
		"status": "success",
		"revision": active_revision,
		"provider": PROVIDER_ID,
		"asset": asset,
		"manifest": manifest.duplicate(true),
		"output_directory": active_output_directory,
		"ai_affordance": active_blueprint.affordance.duplicate(true),
		"ai_affordance_source": active_blueprint.affordance_source,
		"ai_visual_rig": {},
		"ai_visual_rig_source": "",
	}


func _build_request_payload(blueprint: WeaponBlueprint, brief: Dictionary) -> Dictionary:
	var parts: Array[String] = []
	for feature: String in blueprint.preserved_visual_features:
		if feature.begins_with("required_visible_part="):
			parts.append(feature.trim_prefix("required_visible_part=").left(80))
	var exclusions: Array = []
	var raw_exclusions: Variant = blueprint.modifiers.get("general_object_visual_exclusions", [])
	if raw_exclusions is Array:
		for raw_exclusion: Variant in raw_exclusions:
			exclusions.append(str(raw_exclusion).left(220))
	var axes := {}
	for axis: String in [
		"handle_length", "body_length", "grip_topology", "rigidity", "mass_distribution",
		"contact_surface", "secondary_contact_surface", "flex_topology", "tether_topology",
		"terminal_load", "tether_mode", "tether_deployment",
	]:
		axes[axis] = str(blueprint.affordance.get(axis, ""))
	for flag: String in ["has_point", "has_edge", "has_broad_face", "has_barrel", "has_stock"]:
		axes[flag] = bool(blueprint.affordance.get(flag, false))
	return {
		"schema": REQUEST_SCHEMA,
		"identity": blueprint.player_identity_text.strip_edges(),
		"canonical_name": str(blueprint.modifiers.get("general_object_canonical_name", blueprint.display_name)),
		"visual_description": blueprint.visual_description,
		"required_identity_parts": parts,
		"confusable_exclusions": exclusions,
		"structure_prompt": str(brief.get("prompt_clause", "")),
		"scale_treatment": str(blueprint.modifiers.get("general_object_scale_treatment", "handheld")),
		"axes": axes,
		"seed": randi_range(1, 2147483646),
		"retry_index": clampi(int(blueprint.modifiers.get("mechanism_visual_retry_count", 0)), 0, 2),
		"retry_prompt": str(blueprint.modifiers.get("mechanism_visual_retry_prompt", "")),
	}


func _cache_key(payload: Dictionary) -> String:
	var fingerprint := payload.duplicate(true)
	fingerprint.erase("seed")
	fingerprint.erase("retry_index")
	fingerprint.erase("retry_prompt")
	fingerprint["pipeline_version"] = PIPELINE_VERSION
	return JSON.stringify(fingerprint).sha256_text()


func _cache_entry_valid(directory: String, key: String) -> bool:
	var record_path := directory.path_join("cache_record.json")
	var manifest_path := directory.path_join("manifest.json")
	if not FileAccess.file_exists(record_path) or not FileAccess.file_exists(manifest_path) \
		or not FileAccess.file_exists(directory.path_join("processed_sprite.png")):
		return false
	var record_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(record_path))
	var manifest_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not record_value is Dictionary or not manifest_value is Dictionary:
		return false
	var record := record_value as Dictionary
	var manifest := manifest_value as Dictionary
	var sprite_bytes := FileAccess.get_file_as_bytes(directory.path_join("processed_sprite.png"))
	return str(record.get("schema", "")) == CACHE_SCHEMA \
		and str(record.get("key", "")) == key \
		and str(record.get("pipeline_version", "")) == PIPELINE_VERSION \
		and not sprite_bytes.is_empty() \
		and str(record.get("processed_sprite_sha256", "")) == _bytes_sha256(sprite_bytes) \
		and str(manifest.get("schema", "")) == MANIFEST_SCHEMA \
		and str(manifest.get("status", "")) == "success"


func _persist_cache(source_directory: String, manifest: Dictionary) -> Dictionary:
	if active_cache_key.is_empty():
		return {"ok": false, "error": "GENERAL_OBJECT_VISUAL_CACHE_KEY_MISSING"}
	var sprite_path := source_directory.path_join("processed_sprite.png")
	if not FileAccess.file_exists(sprite_path):
		return {"ok": false, "error": "GENERAL_OBJECT_VISUAL_CACHE_SPRITE_MISSING"}
	var cache_directory := _absolute_path(CACHE_ROOT.path_join(active_cache_key))
	if DirAccess.make_dir_recursive_absolute(cache_directory) != OK:
		return {"ok": false, "error": "GENERAL_OBJECT_VISUAL_CACHE_DIRECTORY_FAILED"}
	var sprite_bytes := FileAccess.get_file_as_bytes(sprite_path)
	if sprite_bytes.is_empty() or _write_bytes_atomic(cache_directory.path_join("processed_sprite.png"), sprite_bytes) != OK:
		return {"ok": false, "error": "GENERAL_OBJECT_VISUAL_CACHE_SPRITE_WRITE_FAILED"}
	var cached_manifest := manifest.duplicate(true)
	if _write_json_atomic(cache_directory.path_join("manifest.json"), cached_manifest) != OK:
		return {"ok": false, "error": "GENERAL_OBJECT_VISUAL_CACHE_MANIFEST_WRITE_FAILED"}
	var record := {
		"schema": CACHE_SCHEMA,
		"key": active_cache_key,
		"pipeline_version": PIPELINE_VERSION,
		"processed_sprite_sha256": _bytes_sha256(sprite_bytes),
		"player_confirmation_required": false,
	}
	if _write_json_atomic(cache_directory.path_join("cache_record.json"), record) != OK:
		return {"ok": false, "error": "GENERAL_OBJECT_VISUAL_CACHE_RECORD_WRITE_FAILED"}
	return {"ok": true, "directory": cache_directory}


func _load_normalized_candidate(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "GENERAL_OBJECT_VISUAL_FAL_CACHE_SPRITE_MISSING"}
	var image := Image.load_from_file(path)
	if image == null or image.is_empty() or image.get_size() != CANVAS_SIZE:
		return {"ok": false, "error": "GENERAL_OBJECT_VISUAL_FAL_CACHE_SPRITE_INVALID"}
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return {
		"ok": true, "image": image,
		"source_size": [CANVAS_SIZE.x, CANVAS_SIZE.y],
		"source_bounds": _rect_array(_alpha_bounds(image)),
		"processed_bounds": _rect_array(_alpha_bounds(image)),
		"opaque_colors_before": _opaque_color_count(image),
		"opaque_colors_after": _opaque_color_count(image),
	}


func _normalize_pixel_candidate(source_path: String, target_path: String) -> Dictionary:
	if not FileAccess.file_exists(source_path):
		return {"ok": false, "error": "GENERAL_OBJECT_VISUAL_FAL_PIXEL_OUTPUT_MISSING"}
	var source := Image.load_from_file(source_path)
	if source == null or source.is_empty() or source.get_width() < 32 or source.get_height() < 32:
		return {"ok": false, "error": "GENERAL_OBJECT_VISUAL_FAL_PIXEL_OUTPUT_INVALID"}
	if source.get_format() != Image.FORMAT_RGBA8:
		source.convert(Image.FORMAT_RGBA8)
	var bounds := _alpha_bounds(source)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return {"ok": false, "error": "GENERAL_OBJECT_VISUAL_FAL_ALPHA_MISSING"}
	var cropped := source.get_region(bounds)
	var scale := minf(float(SUBJECT_SPAN) / float(cropped.get_width()), float(SUBJECT_SPAN) / float(cropped.get_height()))
	var resized_size := Vector2i(
		maxi(1, roundi(float(cropped.get_width()) * scale)),
		maxi(1, roundi(float(cropped.get_height()) * scale))
	)
	cropped.resize(resized_size.x, resized_size.y, Image.INTERPOLATE_NEAREST)
	var canvas := Image.create(CANVAS_SIZE.x, CANVAS_SIZE.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color.TRANSPARENT)
	var destination := Vector2i((CANVAS_SIZE.x - resized_size.x) / 2, (CANVAS_SIZE.y - resized_size.y) / 2)
	canvas.blit_rect(cropped, Rect2i(Vector2i.ZERO, resized_size), destination)
	for y: int in range(CANVAS_SIZE.y):
		for x: int in range(CANVAS_SIZE.x):
			var pixel := canvas.get_pixel(x, y)
			pixel.a = 1.0 if pixel.a > 0.10 else 0.0
			canvas.set_pixel(x, y, pixel)
	var colors_before := _opaque_color_count(canvas)
	if colors_before > 32:
		_quantize_opaque_colors(canvas, 24)
	var colors_after := _opaque_color_count(canvas)
	if _save_png_atomic(canvas, target_path) != OK:
		return {"ok": false, "error": "GENERAL_OBJECT_VISUAL_FAL_PROCESSED_WRITE_FAILED"}
	return {
		"ok": true, "image": canvas,
		"source_size": [source.get_width(), source.get_height()],
		"source_bounds": _rect_array(bounds),
		"processed_bounds": [destination.x, destination.y, resized_size.x, resized_size.y],
		"opaque_colors_before": colors_before,
		"opaque_colors_after": colors_after,
	}


func _alpha_bounds(image: Image) -> Rect2i:
	var minimum := Vector2i(image.get_width(), image.get_height())
	var maximum := Vector2i(-1, -1)
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.10:
				continue
			minimum.x = mini(minimum.x, x)
			minimum.y = mini(minimum.y, y)
			maximum.x = maxi(maximum.x, x)
			maximum.y = maxi(maximum.y, y)
	return Rect2i() if maximum.x < minimum.x else Rect2i(minimum, maximum - minimum + Vector2i.ONE)


func _opaque_color_count(image: Image) -> int:
	var colors := {}
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.10:
				colors[pixel.to_html(false)] = true
	return colors.size()


func _quantize_opaque_colors(image: Image, maximum_colors: int) -> void:
	var bins := {}
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.10:
				continue
			var key := (clampi(int(pixel.r * 255.0) >> 5, 0, 7) * 64
				+ clampi(int(pixel.g * 255.0) >> 5, 0, 7) * 8
				+ clampi(int(pixel.b * 255.0) >> 5, 0, 7))
			var group: Dictionary = bins.get(key, {"count": 0, "sum": Vector3.ZERO})
			group["count"] = int(group["count"]) + 1
			group["sum"] = (group.get("sum", Vector3.ZERO) as Vector3) + Vector3(pixel.r, pixel.g, pixel.b)
			bins[key] = group
	var groups: Array = bins.values()
	groups.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return int(left.get("count", 0)) > int(right.get("count", 0)))
	var palette: Array[Color] = []
	for index: int in range(mini(maximum_colors, groups.size())):
		var group := groups[index] as Dictionary
		var mean := (group.get("sum", Vector3.ZERO) as Vector3) / float(maxi(1, int(group.get("count", 1))))
		palette.append(Color(mean.x, mean.y, mean.z, 1.0))
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.10 or palette.is_empty():
				continue
			var best := palette[0]
			var best_distance := INF
			for candidate: Color in palette:
				var difference := Vector3(pixel.r - candidate.r, pixel.g - candidate.g, pixel.b - candidate.b)
				if difference.length_squared() < best_distance:
					best_distance = difference.length_squared()
					best = candidate
			image.set_pixel(x, y, best)


func _is_supported_blueprint(blueprint: WeaponBlueprint) -> bool:
	return blueprint != null and blueprint.behavior_family == "heavy_melee" \
		and str(blueprint.modifiers.get("general_object_profile_id", "")).begins_with("object_")


func _apply_mechanism_anchor_intent(asset: WeaponVisualAsset, blueprint: WeaponBlueprint) -> void:
	if asset == null or blueprint == null:
		return
	var grip_topology := str(blueprint.affordance.get("grip_topology", ""))
	if grip_topology not in ["body_grip", "clamp_grip"]:
		return
	var target_ratio: float = float({
		"rear": 0.16,
		"balanced": 0.40,
		"front": 0.60,
	}.get(str(blueprint.affordance.get("mass_distribution", "balanced")), 0.40))
	var centroid := ANCHOR_RESOLVER.alpha_centroid(asset.source_image, asset.opaque_bounds)
	var desired := (centroid - float(target_ratio) * asset.tip) / maxf(0.10, 1.0 - float(target_ratio))
	asset.grip_primary = _nearest_opaque(asset.source_image, desired, 20)
	asset.grip_secondary = _nearest_opaque(
		asset.source_image,
		asset.grip_primary.lerp(centroid, 0.42),
		14
	)
	asset.anchor_source = "alpha+ai_grip_topology+mass_distribution"
	asset.anchor_confidence = minf(asset.anchor_confidence, 0.82)


func _nearest_opaque(image: Image, desired: Vector2, radius: int) -> Vector2:
	var best := desired
	var best_distance := INF
	for y: int in range(maxi(0, roundi(desired.y) - radius), mini(image.get_height(), roundi(desired.y) + radius + 1)):
		for x: int in range(maxi(0, roundi(desired.x) - radius), mini(image.get_width(), roundi(desired.x) + radius + 1)):
			if image.get_pixel(x, y).a <= 0.10:
				continue
			var distance := Vector2(x, y).distance_squared_to(desired)
			if distance < best_distance:
				best_distance = distance
				best = Vector2(x, y)
	return best


func _rect_array(rect: Rect2i) -> Array[int]:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _write_json_atomic(target: String, value: Dictionary) -> Error:
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


func _write_bytes_atomic(target: String, value: PackedByteArray) -> Error:
	var temporary := "%s.%s.tmp" % [target, str(Time.get_ticks_usec())]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(value)
	file.close()
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(target)
	var error := DirAccess.rename_absolute(temporary, target)
	if error != OK and FileAccess.file_exists(temporary):
		DirAccess.remove_absolute(temporary)
	return error


func _save_png_atomic(image: Image, target: String) -> Error:
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


func _bytes_sha256(value: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value)
	return context.finish().hex_encode()


func _absolute_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path.simplify_path()


func _failure(error: String, retry_required: bool) -> Dictionary:
	return {
		"ok": false,
		"status": "failed",
		"failure_reason": error,
		"error": error,
		"revision": active_revision,
		"provider": PROVIDER_ID,
		"output_directory": active_output_directory,
		"retry_required": retry_required,
		"player_confirmation_required": false,
	}
