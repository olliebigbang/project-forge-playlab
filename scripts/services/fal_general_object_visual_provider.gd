class_name FalGeneralObjectVisualProvider
extends "res://scripts/services/forge_visual_provider.gd"

const VISUAL_BRIEF := preload("res://scripts/combat_feel/mechanism_visual_brief.gd")
const ANCHOR_RESOLVER := preload("res://scripts/systems/anchor_resolver.gd")
const CHURCH_PIXEL_STYLE := preload("res://scripts/art_vertical_slice_v1/church_pixel_style.gd")
const SIDE_LOOP_GRIP := preload("res://scripts/combat_feel/side_loop_grip_resolver.gd")
const BRIDGE_SCRIPT := "res://tools/visual/fal_general_object_pixel_bridge.py"
const REQUEST_SCHEMA := "forge-fal-general-object-visual-request-v2"
const MANIFEST_SCHEMA := "forge-fal-general-object-visual-manifest-v1"
const OUTPUT_ROOT := "user://playlab/fal_general_object_visual/requests"
const CACHE_ROOT := "user://playlab/fal_general_object_visual/cache_v2"
const CACHE_SCHEMA := "forge-fal-general-object-visual-cache-v2"
const PIPELINE_VERSION := "fal-gpt-image-1.5-general-object-image2pixel24-v3-grip-left-role-bound"
const PROVIDER_ID := "FAL_GENERAL_OBJECT"
const CANVAS_SIZE := Vector2i(96, 96)
const SUBJECT_SPAN := 82

var python_executable := "python"
var cache_root := CACHE_ROOT
var output_root := OUTPUT_ROOT
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
	if not _art_style_id(blueprint).is_empty() and _art_style_contract(blueprint).is_empty():
		failure_reason = "GENERAL_OBJECT_VISUAL_ART_STYLE_UNSUPPORTED"
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
	var cache_directory := _absolute_path(cache_root.path_join(active_cache_key))
	if _can_reuse_visual_cache() and _cache_entry_valid(cache_directory, active_cache_key):
		active_output_directory = cache_directory
		active_cache_hit = true
		process_id = -1
		return active_revision
	var run_id := "request_%d_r%d" % [roundi(Time.get_unix_time_from_system() * 1000.0), active_revision]
	active_output_directory = ProjectSettings.globalize_path(output_root.path_join(run_id))
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
	if not _art_style_id(blueprint).is_empty() and _art_style_contract(blueprint).is_empty():
		return _failure("GENERAL_OBJECT_VISUAL_ART_STYLE_UNSUPPORTED", false)
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
	var recover_from_identity_art := false
	if str(manifest.get("status", "")) != "success":
		var upstream_failure := str(manifest.get("failure_reason", "GENERAL_OBJECT_VISUAL_FAL_GENERATION_FAILED"))
		recover_from_identity_art = upstream_failure.begins_with("GENERAL_OBJECT_VISUAL_FAL_PIXELIZER_") \
			and FileAccess.file_exists(active_output_directory.path_join("ai_raw.png"))
		if not recover_from_identity_art:
			delivered = true
			return _failure(upstream_failure, false)
		# The paid identity renderer already returned a validated transparent PNG.
		# If only the optional remote pixelizer fails, use the same local 96px,
		# palette and Alpha normalizer that already backs successful manifests.
		# Identity-renderer failures and missing raw images never enter this path.
		manifest["upstream_status"] = "failed"
		manifest["pixelizer_failure_reason"] = upstream_failure
		manifest["status"] = "success"
		manifest["recovery"] = {
			"method": "validated_transparent_identity_art_local_pixel_fallback",
			"new_network_requests": 0,
			"source": "ai_raw.png",
		}
		if active_request_payload.has("art_style"):
			manifest["art_style"] = (active_request_payload.art_style as Dictionary).duplicate(true)
	if not _art_style_matches(manifest):
		delivered = true
		return _failure("GENERAL_OBJECT_VISUAL_ART_STYLE_MANIFEST_MISMATCH", false)
	var normalized: Dictionary
	var candidate_source := "fal_image2pixel"
	if recover_from_identity_art:
		normalized = _normalize_pixel_candidate(
			active_output_directory.path_join("ai_raw.png"),
			active_output_directory.path_join("processed_sprite.png")
		)
		candidate_source = "fal_transparent_identity_art_local_pixel_fallback"
	elif active_cache_hit:
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
	var styled := _apply_art_style(normalized, manifest, active_cache_hit)
	if not bool(styled.get("ok", false)):
		delivered = true
		return _failure(str(styled.get("error", "GENERAL_OBJECT_VISUAL_ART_STYLE_FAILED")), false)
	var image := normalized.get("image") as Image
	var asset: WeaponVisualAsset = ANCHOR_RESOLVER.resolve(image, active_blueprint)
	if asset == null:
		delivered = true
		return _failure("GENERAL_OBJECT_VISUAL_FAL_ALPHA_INVALID", true)
	_apply_mechanism_anchor_intent(asset, active_blueprint)
	if str(active_blueprint.affordance.get("functional_output", "contact_only")) != "contact_only" \
			and not bool((active_blueprint.modifiers.get("native_function_origin_evidence", {}) as Dictionary).get("resolved", false)):
		delivered = true
		return _failure("GENERAL_OBJECT_VISUAL_NATIVE_FUNCTION_ORIGIN_UNRESOLVED", true)
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
	var legacy_axis_defaults := {
		"state_topology": "fixed",
		"activation_mode": "passive",
		"functional_output": "contact_only",
	}
	for axis: String in [
		"handle_length", "body_length", "grip_topology", "rigidity", "mass_distribution",
		"contact_surface", "secondary_contact_surface", "flex_topology", "tether_topology",
		"terminal_load", "tether_mode", "tether_deployment",
		"state_topology", "activation_mode", "functional_output",
	]:
		axes[axis] = str(blueprint.affordance.get(axis, legacy_axis_defaults.get(axis, "")))
	for flag: String in ["has_point", "has_edge", "has_broad_face", "has_barrel", "has_stock"]:
		axes[flag] = bool(blueprint.affordance.get(flag, false))
	var payload := {
		"schema": REQUEST_SCHEMA,
		"identity": blueprint.player_identity_text.strip_edges(),
		"canonical_name": str(blueprint.modifiers.get("general_object_canonical_name", blueprint.display_name)),
		"visual_description": blueprint.visual_description,
		"required_identity_parts": parts,
		"confusable_exclusions": exclusions,
		"mechanism_roles": (blueprint.modifiers.get("general_object_mechanism_roles", {}) as Dictionary).duplicate(true),
		"structure_prompt": str(brief.get("prompt_clause", "")),
		"scale_treatment": str(blueprint.modifiers.get("general_object_scale_treatment", "handheld")),
		"axes": axes,
		"seed": randi_range(1, 2147483646),
		"retry_index": clampi(int(blueprint.modifiers.get("mechanism_visual_retry_count", 0)), 0, 2),
		"retry_prompt": str(blueprint.modifiers.get("mechanism_visual_retry_prompt", "")),
	}
	var style := _art_style_contract(blueprint)
	if not style.is_empty():
		payload["art_style"] = style
	return payload


func _art_style_id(blueprint: WeaponBlueprint) -> String:
	return "" if blueprint == null else str(blueprint.modifiers.get("art_style_id", "")).strip_edges()


func _art_style_contract(blueprint: WeaponBlueprint) -> Dictionary:
	var id := _art_style_id(blueprint)
	if id.is_empty():
		return {}
	var style: Dictionary = CHURCH_PIXEL_STYLE.contract(id)
	if str(style.get("id", "")) != id or str(style.get("version", "")).is_empty() or str(style.get("prompt", "")).is_empty():
		return {}
	return {"id": id, "version": str(style.version), "prompt": str(style.prompt)}


func _art_style_matches(evidence: Dictionary) -> bool:
	var expected: Dictionary = active_request_payload.get("art_style", {})
	if expected.is_empty():
		return not evidence.has("art_style")
	return evidence.get("art_style") is Dictionary and evidence.art_style == expected


func _apply_art_style(normalized: Dictionary, manifest: Dictionary, from_cache: bool) -> Dictionary:
	var style: Dictionary = active_request_payload.get("art_style", {})
	if style.is_empty():
		return {"ok": true}
	if not _art_style_matches(manifest):
		return {"ok": false, "error": "GENERAL_OBJECT_VISUAL_ART_STYLE_MANIFEST_MISMATCH"}
	var image := normalized.get("image") as Image
	var original_bytes := image.get_data()
	var applied: Dictionary = CHURCH_PIXEL_STYLE.normalize(image, str(style.id))
	if not bool(applied.get("ok", false)) or not applied.get("image") is Image:
		return {"ok": false, "error": str(applied.get("error", "GENERAL_OBJECT_VISUAL_ART_STYLE_FAILED"))}
	var styled_image := applied.get("image") as Image
	if from_cache:
		var report: Dictionary = manifest.get("art_style_report", {}) if manifest.get("art_style_report") is Dictionary else {}
		if not bool(report.get("ok", false)) or report.get("id") != style.id or report.get("version") != style.version or styled_image.get_data() != original_bytes:
			return {"ok": false, "error": "GENERAL_OBJECT_VISUAL_ART_STYLE_CACHE_NOT_CANONICAL"}
	if not from_cache:
		if _save_png_atomic(styled_image, active_output_directory.path_join("processed_sprite.png")) != OK:
			return {"ok": false, "error": "GENERAL_OBJECT_VISUAL_ART_STYLE_WRITE_FAILED"}
		manifest["art_style_report"] = (applied.get("report", {}) as Dictionary).duplicate(true)
	normalized["image"] = styled_image
	normalized["opaque_colors_after"] = _opaque_color_count(styled_image)
	return {"ok": true}


func _cache_key(payload: Dictionary) -> String:
	var fingerprint := payload.duplicate(true)
	fingerprint.erase("seed")
	fingerprint.erase("retry_index")
	fingerprint.erase("retry_prompt")
	fingerprint["pipeline_version"] = PIPELINE_VERSION
	return JSON.stringify(fingerprint).sha256_text()


func _can_reuse_visual_cache() -> bool:
	# A downstream structural rejection requests a redraw, not the same cached pixels.
	return int(active_request_payload.get("retry_index", 0)) == 0


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
	if not _art_style_matches(manifest) or not _art_style_matches(record):
		return false
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
	var cache_directory := _absolute_path(cache_root.path_join(active_cache_key))
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
	if active_request_payload.has("art_style"):
		record["art_style"] = (active_request_payload.art_style as Dictionary).duplicate(true)
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
	if grip_topology == "one_hand_handle":
		var loop := SIDE_LOOP_GRIP.resolve(asset.source_image, blueprint.affordance)
		blueprint.modifiers["side_loop_grip_evidence"] = (loop.get("evidence", {}) as Dictionary).duplicate(true)
		if bool(loop.get("resolved", false)):
			asset.grip_primary = loop.grip_primary
			asset.grip_secondary = loop.grip_secondary
			asset.tip = loop.strike_point
			asset.muzzle = asset.tip
			asset.rear_contact = asset.grip_primary
			asset.anchor_source = "alpha_side_loop+ai_rigid_broad_contact"
			asset.anchor_confidence = minf(asset.anchor_confidence, 0.82)
			_normalize_asset_forward(asset)
			blueprint.modifiers.side_loop_grip_evidence["orientation_flipped"] = asset.orientation_flipped
			blueprint.modifiers.side_loop_grip_evidence["normalized_grip_primary"] = [asset.grip_primary.x, asset.grip_primary.y]
			blueprint.modifiers.side_loop_grip_evidence["normalized_strike_point"] = [asset.tip.x, asset.tip.y]
			_apply_native_function_origin(asset, blueprint)
			return
		if _apply_one_hand_endpoint_roles(asset, blueprint):
			_normalize_asset_forward(asset)
			_apply_native_function_origin(asset, blueprint)
			return
	if grip_topology not in ["body_grip", "clamp_grip"]:
		_apply_native_function_origin(asset, blueprint)
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
	_apply_native_function_origin(asset, blueprint)


func refresh_automatic_handle_binding(asset: WeaponVisualAsset, blueprint: WeaponBlueprint) -> bool:
	# Runtime-only migration for older generated entries whose Alpha already has
	# an unambiguous closed/open side handle or a structurally distinct long-blade
	# terminal. Never write the source package.
	if asset == null or blueprint == null or str(blueprint.affordance.get("grip_topology", "")) != "one_hand_handle": return false
	if asset.anchor_source not in ["alpha_local_search+profile", "alpha_principal_terminals+ai_contact_surface", "alpha_side_loop+ai_rigid_broad_contact"]: return false
	var before_pixels := asset.source_image.get_data()
	var loop := SIDE_LOOP_GRIP.resolve(asset.source_image, blueprint.affordance)
	if bool(loop.get("resolved", false)):
		asset.grip_primary = loop.grip_primary
		asset.grip_secondary = loop.grip_secondary
		asset.tip = loop.strike_point
		asset.muzzle = asset.tip
		asset.rear_contact = asset.grip_primary
		asset.anchor_source = "alpha_side_loop+ai_rigid_broad_contact"
		asset.anchor_confidence = minf(asset.anchor_confidence, 0.82)
	elif not _apply_one_hand_endpoint_roles(asset, blueprint):
		return false
	_normalize_asset_forward(asset)
	# Stage loading may migrate an old asset in memory, but the immutable
	# blueprint/card remains byte-for-byte unchanged.
	_apply_native_function_origin(asset, blueprint, false)
	return asset.source_image.get_data() == before_pixels or asset.orientation_flipped


func _apply_native_function_origin(asset: WeaponVisualAsset, blueprint: WeaponBlueprint, write_evidence: bool = true) -> void:
	var output := str(blueprint.affordance.get("functional_output", "contact_only"))
	var roles: Dictionary = blueprint.modifiers.get("general_object_mechanism_roles", {})
	var evidence := {"resolved": true, "output": output, "role": str(roles.get("effect_origin_part_zh", "")), "method": "contact_anchor", "alpha_changed": false}
	if output == "contact_only":
		asset.muzzle = asset.tip
		if write_evidence: blueprint.modifiers["native_function_origin_evidence"] = evidence
		return
	if output == "radial_field":
		asset.muzzle = _nearest_opaque(asset.source_image, asset.spin_pivot, 18)
		evidence.method = "nearest_alpha_to_mass_pivot"
		evidence.origin = [asset.muzzle.x, asset.muzzle.y]
		if write_evidence: blueprint.modifiers["native_function_origin_evidence"] = evidence
		return
	var forward_delta := asset.tip - asset.grip_primary
	if forward_delta.length() < 8.0:
		evidence.resolved = false; evidence.method = "forward_axis_unresolved"
		if write_evidence: blueprint.modifiers["native_function_origin_evidence"] = evidence
		return
	var forward := forward_delta.normalized()
	var origin := Vector2.ZERO
	var maximum_projection := -INF
	var nearest_to_axis := INF
	for y: int in range(asset.opaque_bounds.position.y, asset.opaque_bounds.end.y):
		for x: int in range(asset.opaque_bounds.position.x, asset.opaque_bounds.end.x):
			if asset.source_image.get_pixel(x, y).a <= 0.10: continue
			var point := Vector2(float(x), float(y))
			var relative := point - asset.grip_primary
			var projection := relative.dot(forward)
			var perpendicular := absf(relative.cross(forward))
			if projection > maximum_projection + 0.001 or (is_equal_approx(projection, maximum_projection) and perpendicular < nearest_to_axis):
				origin = point; maximum_projection = projection; nearest_to_axis = perpendicular
	var minimum_span := maxf(14.0, forward_delta.length() * 1.08)
	if maximum_projection < minimum_span or asset.source_image.get_pixelv(Vector2i(origin)).a <= 0.10:
		evidence.resolved = false; evidence.method = "effect_origin_not_separated_from_grip"
	else:
		asset.muzzle = origin
		evidence.method = "farthest_forward_alpha_terminal_from_grip"
		evidence.origin = [origin.x, origin.y]
		evidence.grip_to_origin_pixels = origin.distance_to(asset.grip_primary)
		evidence.forward_projection_pixels = maximum_projection
		evidence.forward_vector = [forward.x, forward.y]
	if write_evidence: blueprint.modifiers["native_function_origin_evidence"] = evidence


func _apply_one_hand_endpoint_roles(asset: WeaponVisualAsset, blueprint: WeaponBlueprint) -> bool:
	var terminals := _principal_terminal_analysis(asset.source_image, asset.opaque_bounds)
	if not bool(terminals.get("ok", false)):
		return false
	var contact_surface := str(blueprint.affordance.get("contact_surface", ""))
	var long_blade_edge := (
		contact_surface == "edge"
		and str(blueprint.affordance.get("secondary_contact_surface", "")) == "point"
		and str(blueprint.affordance.get("body_length", "")) == "long"
		and bool(blueprint.affordance.get("has_edge", false))
		and bool(blueprint.affordance.get("has_point", false))
	)
	if contact_surface not in ["point", "broad", "whole_body"] and not long_blade_edge:
		return false
	var low_count := int(terminals.get("low_count", 0))
	var high_count := int(terminals.get("high_count", 0))
	var smaller := maxi(1, mini(low_count, high_count))
	var larger := maxi(low_count, high_count)
	var terminal_ratio := float(larger) / float(smaller)
	var guarded_grip := ""
	if long_blade_edge:
		var low_guard_score := float(terminals.get("low_guard_score", 0.0))
		var high_guard_score := float(terminals.get("high_guard_score", 0.0))
		# A long handle followed by a guard creates one isolated terminal-side
		# thickness step. Smoothly widening blade points do not. The rule uses
		# Alpha cross-sections only, so colors and object names cannot select it.
		if high_guard_score >= 1.35 and low_guard_score < 1.35:
			guarded_grip = "high"
		elif low_guard_score >= 1.35 and high_guard_score < 1.35:
			guarded_grip = "low"
	if guarded_grip.is_empty() and terminal_ratio < 1.18:
		return false
	# Long edged objects expose their point as independent evidence. Without a
	# guard decision, the narrower terminal is the point and the wider terminal
	# is the held fixture. Ambiguous silhouettes fail closed above.
	var strike_uses_low := (
		guarded_grip == "high"
		or (guarded_grip.is_empty() and (contact_surface == "point" or long_blade_edge) and low_count < high_count)
		or (guarded_grip.is_empty() and contact_surface not in ["point", "edge"] and low_count > high_count)
	)
	var strike_terminal := Vector2(terminals.get("low", Vector2.ZERO) if strike_uses_low else terminals.get("high", Vector2.ZERO))
	var grip_terminal := Vector2(terminals.get("high", Vector2.ZERO) if strike_uses_low else terminals.get("low", Vector2.ZERO))
	var centroid := Vector2(terminals.get("centroid", asset.spin_pivot))
	var span := float(terminals.get("span", 0.0))
	var grip_target := grip_terminal.lerp(centroid, 0.14)
	var resolved_grip := _nearest_opaque(asset.source_image, grip_target, clampi(roundi(span * 0.12), 6, 16))
	var resolved_strike := _nearest_opaque(asset.source_image, strike_terminal, 5)
	if resolved_grip.distance_to(resolved_strike) < maxf(12.0, span * 0.48):
		return false
	asset.grip_primary = resolved_grip
	asset.grip_secondary = _nearest_opaque(asset.source_image, resolved_grip.lerp(centroid, 0.26), 9)
	asset.tip = resolved_strike
	asset.muzzle = resolved_strike
	asset.rear_contact = resolved_grip
	asset.anchor_source = "alpha_principal_terminals+ai_contact_surface"
	asset.anchor_confidence = minf(asset.anchor_confidence, 0.82)
	return true


func _principal_terminal_analysis(image: Image, bounds: Rect2i) -> Dictionary:
	if image == null or image.is_empty() or bounds.size == Vector2i.ZERO:
		return {"ok": false}
	var centroid := ANCHOR_RESOLVER.alpha_centroid(image, bounds)
	var covariance_xx := 0.0
	var covariance_xy := 0.0
	var covariance_yy := 0.0
	var opaque_count := 0
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			if image.get_pixel(x, y).a <= 0.10:
				continue
			var delta := Vector2(float(x), float(y)) - centroid
			covariance_xx += delta.x * delta.x
			covariance_xy += delta.x * delta.y
			covariance_yy += delta.y * delta.y
			opaque_count += 1
	if opaque_count < 12:
		return {"ok": false}
	var angle := 0.5 * atan2(2.0 * covariance_xy, covariance_xx - covariance_yy)
	var axis := Vector2(cos(angle), sin(angle)).normalized()
	var minimum_projection := INF
	var maximum_projection := -INF
	var projection_profile: Array[int] = []
	projection_profile.resize(40)
	projection_profile.fill(0)
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			if image.get_pixel(x, y).a <= 0.10:
				continue
			var projection := (Vector2(float(x), float(y)) - centroid).dot(axis)
			minimum_projection = minf(minimum_projection, projection)
			maximum_projection = maxf(maximum_projection, projection)
	var span := maximum_projection - minimum_projection
	if span < 18.0:
		return {"ok": false}
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			if image.get_pixel(x, y).a <= 0.10:
				continue
			var projection := (Vector2(float(x), float(y)) - centroid).dot(axis)
			var bin := clampi(roundi((projection - minimum_projection) / span * float(projection_profile.size() - 1)), 0, projection_profile.size() - 1)
			projection_profile[bin] += 1
	var terminal_band := maxf(2.5, span * 0.045)
	var low_total := Vector2.ZERO
	var high_total := Vector2.ZERO
	var low_samples := 0
	var high_samples := 0
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			if image.get_pixel(x, y).a <= 0.10:
				continue
			var point := Vector2(float(x), float(y))
			var projection := (point - centroid).dot(axis)
			if projection <= minimum_projection + terminal_band:
				low_total += point
				low_samples += 1
			if projection >= maximum_projection - terminal_band:
				high_total += point
				high_samples += 1
	if low_samples == 0 or high_samples == 0:
		return {"ok": false}
	var low := low_total / float(low_samples)
	var high := high_total / float(high_samples)
	var radius := clampi(roundi(span * 0.16), 7, 18)
	return {
		"ok": true,
		"centroid": centroid,
		"axis": axis,
		"span": span,
		"low": low,
		"high": high,
		"low_count": _opaque_neighborhood_count(image, low, radius),
		"high_count": _opaque_neighborhood_count(image, high, radius),
		"low_guard_score": _terminal_guard_score(projection_profile),
		"high_guard_score": _terminal_guard_score(_reversed_profile(projection_profile)),
	}


func _terminal_guard_score(profile: Array[int]) -> float:
	if profile.size() < 20:
		return 0.0
	var outer := profile.slice(roundi(profile.size() * 0.05), roundi(profile.size() * 0.20))
	var guard := profile.slice(roundi(profile.size() * 0.20), roundi(profile.size() * 0.36))
	var inner := profile.slice(roundi(profile.size() * 0.36), roundi(profile.size() * 0.50))
	if outer.is_empty() or guard.is_empty() or inner.is_empty():
		return 0.0
	var guard_peak := 0
	for value: int in guard:
		guard_peak = maxi(guard_peak, value)
	return float(guard_peak) / maxf(1.0, maxf(_median_ints(outer), _median_ints(inner)))


func _median_ints(values: Array) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	var middle := sorted.size() / 2
	if sorted.size() % 2 == 1:
		return float(sorted[middle])
	return (float(sorted[middle - 1]) + float(sorted[middle])) * 0.5


func _reversed_profile(profile: Array[int]) -> Array[int]:
	var reversed := profile.duplicate()
	reversed.reverse()
	return reversed


func _opaque_neighborhood_count(image: Image, center: Vector2, radius: int) -> int:
	var count := 0
	var center_pixel := Vector2i(roundi(center.x), roundi(center.y))
	for y: int in range(maxi(0, center_pixel.y - radius), mini(image.get_height(), center_pixel.y + radius + 1)):
		for x: int in range(maxi(0, center_pixel.x - radius), mini(image.get_width(), center_pixel.x + radius + 1)):
			if Vector2i(x, y).distance_squared_to(center_pixel) <= radius * radius and image.get_pixel(x, y).a > 0.10:
				count += 1
	return count


func _normalize_asset_forward(asset: WeaponVisualAsset) -> void:
	asset.orientation_source = "GripPrimary->StrikePoint:alpha+ai_axes"
	if asset.tip.x >= asset.grip_primary.x:
		return
	var width := asset.source_image.get_width()
	var image_copy := Image.new()
	image_copy.copy_from(asset.source_image)
	image_copy.flip_x()
	asset.source_image = image_copy
	asset.texture = ImageTexture.create_from_image(image_copy)
	asset.opaque_bounds = Rect2i(
		width - asset.opaque_bounds.end.x,
		asset.opaque_bounds.position.y,
		asset.opaque_bounds.size.x,
		asset.opaque_bounds.size.y
	)
	asset.grip_primary = _flip_point_x(asset.grip_primary, width)
	asset.grip_secondary = _flip_point_x(asset.grip_secondary, width)
	asset.tip = _flip_point_x(asset.tip, width)
	asset.muzzle = _flip_point_x(asset.muzzle, width)
	asset.tether_origin = _flip_point_x(asset.tether_origin, width)
	asset.spin_pivot = _flip_point_x(asset.spin_pivot, width)
	asset.rear_contact = _flip_point_x(asset.rear_contact, width)
	asset.orientation_flipped = true


func _flip_point_x(point: Vector2, width: int) -> Vector2:
	return Vector2(float(width - 1) - point.x, point.y)


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
