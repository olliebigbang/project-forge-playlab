class_name FalFirearmVisualProvider
extends "res://scripts/services/forge_visual_provider.gd"

const OPEN_IDENTITY_PROMPT := preload("res://scripts/services/open_identity_visual_prompt.gd")
const FIREARM_SCAFFOLD_PIPELINE := preload("res://scripts/combat_feel/firearm_visual_scaffold_pipeline.gd")
const BRIDGE_SCRIPT := "res://tools/visual/fal_firearm_pixel_bridge.py"
const REQUEST_SCHEMA := "forge-fal-firearm-visual-request-v2"
const MANIFEST_SCHEMA := "forge-fal-firearm-visual-manifest-v1"
const OUTPUT_ROOT := "user://playlab/fal_firearm_visual/requests"
const CACHE_ROOT := "user://playlab/fal_firearm_visual/cache_v1"
const CACHE_SCHEMA := "forge-fal-firearm-visual-cache-v1"
const VISUAL_VERIFICATION_SCHEMA := "forge-firearm-ai-visual-verification-v1"
const VISUAL_PIPELINE_VERSION := "fal-gpt-image-1.5-image2pixel24-anthropic-identity-v3"
const CANVAS_SIZE := Vector2i(96, 96)
const SUBJECT_SPAN := 82

var python_executable := "python"
var timeout_seconds := 240.0
var process_id := -1
var active_revision := 0
var active_blueprint: WeaponBlueprint
var active_output_directory := ""
var active_preparation: Dictionary = {}
var started_msec := 0
var process_exited_msec := 0
var delivered := true
var failure_reason := ""
var active_request_payload: Dictionary = {}
var active_cache_key := ""
var active_cache_hit := false


func configure(next_python_executable: String = "python") -> Dictionary:
	python_executable = next_python_executable.strip_edges()
	if python_executable.is_empty():
		python_executable = "python"
	var bridge_path := ProjectSettings.globalize_path(BRIDGE_SCRIPT)
	if not FileAccess.file_exists(bridge_path):
		return _failure("FIREARM_VISUAL_FAL_BRIDGE_MISSING", false)
	if (
		not OS.has_environment("FAL_KEY")
		and not OS.has_environment("FAL_API_KEY")
	):
		return _failure("FIREARM_VISUAL_FAL_KEY_MISSING", false)
	if not OS.has_environment("ANTHROPIC_API_KEY"):
		return _failure("FIREARM_VISUAL_VERIFIER_KEY_MISSING", false)
	if (
		not OS.has_environment("FORGE_VISUAL_VERIFIER_MODEL")
		and not OS.has_environment("FORGE_SEMANTIC_MODEL")
	):
		return _failure("FIREARM_VISUAL_VERIFIER_MODEL_MISSING", false)
	return {"ok": true, "provider": MODE_FAL_FIREARM, "bridge_path": bridge_path}


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
		failure_reason = "FIREARM_VISUAL_FAL_REQUIRES_HANDHELD_FIREARM"
		return active_revision
	active_preparation = FIREARM_SCAFFOLD_PIPELINE.prepare(blueprint)
	if not bool(active_preparation.get("ok", false)):
		failure_reason = str(active_preparation.get("error", "FIREARM_VISUAL_PREPARE_FAILED"))
		return active_revision
	blueprint.visual_structure_brief = (
		active_preparation.get("visual_structure_brief", {}) as Dictionary
	).duplicate(true)
	blueprint.visual_structure_brief_source = str(blueprint.visual_structure_brief.get("source", ""))
	active_request_payload = _build_request_payload(blueprint, active_preparation)
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
		failure_reason = "FIREARM_VISUAL_FAL_OUTPUT_DIRECTORY_FAILED"
		return active_revision
	var persisted := FIREARM_SCAFFOLD_PIPELINE.persist_request_inputs(
		active_output_directory,
		"input",
		active_preparation
	)
	if not bool(persisted.get("ok", false)):
		failure_reason = str(persisted.get("error", "FIREARM_VISUAL_REQUEST_PERSIST_FAILED"))
		return active_revision
	var request_path := active_output_directory.path_join("request.json")
	if _write_json_atomic(request_path, active_request_payload) != OK:
		failure_reason = "FIREARM_VISUAL_FAL_REQUEST_WRITE_FAILED"
		return active_revision
	var arguments: Array[String] = [
		"-E", "-S", "-B",
		ProjectSettings.globalize_path(BRIDGE_SCRIPT),
		"--request", request_path,
		"--output-dir", active_output_directory,
	]
	process_id = OS.create_process(python_executable, arguments)
	if process_id <= 0:
		failure_reason = "FIREARM_VISUAL_FAL_PROCESS_START_FAILED"
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
		return _failure("FIREARM_VISUAL_FAL_TIMEOUT", true)
	var manifest_path := active_output_directory.path_join("manifest.json")
	if FileAccess.file_exists(manifest_path):
		return _load_completed_result(manifest_path)
	if process_id > 0 and OS.is_process_running(process_id):
		return {"status": "running", "revision": active_revision, "provider": MODE_FAL_FIREARM}
	if process_id > 0:
		if process_exited_msec == 0:
			process_exited_msec = Time.get_ticks_msec()
			return {"status": "running", "revision": active_revision, "provider": MODE_FAL_FIREARM}
		if Time.get_ticks_msec() - process_exited_msec < 1200:
			return {"status": "running", "revision": active_revision, "provider": MODE_FAL_FIREARM}
		delivered = true
		return _failure("FIREARM_VISUAL_FAL_EXITED_WITHOUT_MANIFEST", true)
	return {"status": "running", "revision": active_revision, "provider": MODE_FAL_FIREARM}


func load_atomic_result(directory: String, blueprint: WeaponBlueprint) -> Dictionary:
	active_blueprint = blueprint
	active_preparation = FIREARM_SCAFFOLD_PIPELINE.prepare(blueprint)
	if not bool(active_preparation.get("ok", false)):
		return active_preparation
	active_request_payload = _build_request_payload(blueprint, active_preparation)
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
	active_preparation.clear()
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
		return _failure("FIREARM_VISUAL_FAL_MANIFEST_INVALID_JSON", false)
	var manifest := parsed as Dictionary
	if str(manifest.get("schema", "")) != MANIFEST_SCHEMA:
		delivered = true
		return _failure("FIREARM_VISUAL_FAL_MANIFEST_SCHEMA_INVALID", false)
	if str(manifest.get("status", "")) != "success":
		delivered = true
		var bridge_error := str(manifest.get("failure_reason", "FIREARM_VISUAL_FAL_GENERATION_FAILED"))
		return _failure(bridge_error, _fal_error_is_retryable(bridge_error))
	var visual_verification := manifest.get("ai_visual_identity_verification", {}) as Dictionary
	if (
		str(visual_verification.get("schema", "")) != VISUAL_VERIFICATION_SCHEMA
		or not bool(visual_verification.get("ok", false))
		or not bool(visual_verification.get("passed", false))
	):
		var verification_error := "FIREARM_VISUAL_AI_IDENTITY_REJECTED"
		if str(visual_verification.get("schema", "")) != VISUAL_VERIFICATION_SCHEMA:
			verification_error = "FIREARM_VISUAL_AI_IDENTITY_VERIFICATION_MISSING"
		var rejection := {
			"ok": false,
			"error": verification_error,
			"retry_required": true,
			"retry_prompt": _visual_verification_retry_prompt(visual_verification),
			"metrics": {"ai_visual_identity_verification": visual_verification.duplicate(true)},
		}
		FIREARM_SCAFFOLD_PIPELINE.persist_generation_rejection(
			active_output_directory,
			active_preparation,
			rejection,
			manifest
		)
		delivered = true
		return _failure(
			verification_error,
			true,
			str(rejection.get("retry_prompt", ""))
		)
	var normalized := _normalize_pixel_candidate(
		active_output_directory.path_join("raw_pixel_art.png"),
		active_output_directory.path_join("processed_sprite.png")
	)
	var candidate_source := "fal_image2pixel"
	if not bool(normalized.get("ok", false)):
		var raw_fallback := _normalize_pixel_candidate(
			active_output_directory.path_join("ai_raw.png"),
			active_output_directory.path_join("processed_sprite.png")
		)
		if bool(raw_fallback.get("ok", false)):
			normalized = raw_fallback
			candidate_source = "fal_transparent_identity_art_local_pixel_fallback"
	if not bool(normalized.get("ok", false)):
		delivered = true
		return _failure(str(normalized.get("error", "FIREARM_VISUAL_FAL_NORMALIZE_FAILED")), true)
	manifest["candidate_source"] = candidate_source
	manifest["cache"] = {
		"schema": CACHE_SCHEMA,
		"hit": active_cache_hit,
		"key": active_cache_key,
		"pipeline_version": VISUAL_PIPELINE_VERSION,
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
		return _failure("FIREARM_VISUAL_FAL_NORMALIZATION_MANIFEST_FAILED", false)
	var image := normalized.get("image") as Image
	var resolution := FIREARM_SCAFFOLD_PIPELINE.resolve_asset(
		image,
		active_blueprint,
		active_preparation
	)
	if not bool(resolution.get("ok", false)):
		FIREARM_SCAFFOLD_PIPELINE.persist_generation_rejection(
			active_output_directory,
			active_preparation,
			resolution,
			manifest
		)
		delivered = true
		return _failure(
			str(resolution.get("error", "FIREARM_VISUAL_FAL_GATE_REJECTED")),
			bool(resolution.get("retry_required", true)),
			str(resolution.get("retry_prompt", ""))
		)
	var persisted := FIREARM_SCAFFOLD_PIPELINE.persist_generation_handoff(
		active_output_directory,
		active_preparation,
		resolution,
		manifest
	)
	if not bool(persisted.get("ok", false)):
		delivered = true
		return _failure(str(persisted.get("error", "FIREARM_VISUAL_FAL_HANDOFF_FAILED")), false)
	delivered = true
	var final_manifest := (persisted.get("manifest", {}) as Dictionary).duplicate(true)
	if not active_cache_hit:
		_persist_cache(active_output_directory, final_manifest)
	var gate := (resolution.get("visual_identity_gate", {}) as Dictionary).duplicate(true)
	return {
		"status": "success",
		"revision": active_revision,
		"provider": MODE_FAL_FIREARM,
		"asset": resolution.get("asset") as WeaponVisualAsset,
		"manifest": final_manifest,
		"output_directory": active_output_directory,
		"ai_affordance": active_blueprint.affordance.duplicate(true),
		"ai_affordance_source": active_blueprint.affordance_source,
		"ai_visual_rig": {},
		"ai_visual_rig_source": "",
		"firearm_visual_identity_gate": gate,
	}


func _build_request_payload(blueprint: WeaponBlueprint, preparation: Dictionary) -> Dictionary:
	var brief := preparation.get("visual_structure_brief", {}) as Dictionary
	var parts: Array[String] = []
	for feature: String in blueprint.preserved_visual_features:
		if feature.begins_with("required_visible_part="):
			parts.append(feature.trim_prefix("required_visible_part=").left(80))
	for raw_part: Variant in brief.get("required_visible_parts", []):
		var part := str(raw_part).strip_edges().left(80)
		if not part.is_empty() and part not in parts:
			parts.append(part)
		if parts.size() >= 12:
			break
	var declaration := blueprint.affordance
	var identity_card := (
		preparation.get("visual_identity_card", {}) as Dictionary
	).duplicate(true)
	identity_card.erase("ok")
	var axes := {
		"layout": str(declaration.get("layout", "")),
		"stock_structure": str(declaration.get("stock_structure", "")),
		"feed_position": str(declaration.get("feed_position", "")),
		"magazine_shape": str(declaration.get("magazine_shape", "")),
		"barrel_length": str(declaration.get("barrel_length", "")),
		"upper_profile": str(declaration.get("upper_profile", "")),
		"support_mode": str(declaration.get("support_mode", "")),
		"finish_palette": str(declaration.get("finish_palette", "")),
	}
	var identity := blueprint.player_identity_text.strip_edges()
	if identity.is_empty():
		identity = blueprint.source_identity.strip_edges()
	return {
		"schema": REQUEST_SCHEMA,
		"identity": identity,
		"identity_prompt_text": OPEN_IDENTITY_PROMPT._model_text(identity, 160),
		"canonical_name": blueprint.display_name,
		"visual_description": blueprint.visual_description,
		"required_identity_parts": parts,
		"structure_prompt": str(brief.get("prompt_clause", "")),
		"identity_card": identity_card,
		"identity_reference_id": str(
			blueprint.modifiers.get("firearm_visual_reference_id", "")
		).strip_edges().left(96),
		"axes": axes,
		"seed": randi_range(1, 2147483646),
		"retry_index": clampi(int(blueprint.modifiers.get("mechanism_visual_retry_count", 0)), 0, 2),
		"retry_prompt": str(blueprint.modifiers.get("mechanism_visual_retry_prompt", "")),
	}


func _cache_key(request_payload: Dictionary) -> String:
	var identity_card := (request_payload.get("identity_card", {}) as Dictionary).duplicate(true)
	identity_card.erase("requested_identity")
	var fingerprint := {
		"pipeline_version": VISUAL_PIPELINE_VERSION,
		"normalized_identity": _normalize_identity(str(request_payload.get("identity", ""))),
		"canonical_name": str(request_payload.get("canonical_name", "")),
		"identity_card": identity_card,
		"axes": (request_payload.get("axes", {}) as Dictionary).duplicate(true),
		"structure_prompt": str(request_payload.get("structure_prompt", "")),
	}
	var identity_reference_id := str(request_payload.get("identity_reference_id", "")).strip_edges()
	if not identity_reference_id.is_empty():
		fingerprint["identity_reference_id"] = identity_reference_id
	return JSON.stringify(fingerprint).sha256_text()


func _cache_entry_valid(directory: String, key: String) -> bool:
	var record_path := directory.path_join("cache_record.json")
	var manifest_path := directory.path_join("manifest.json")
	if (
		not FileAccess.file_exists(record_path)
		or not FileAccess.file_exists(manifest_path)
		or not FileAccess.file_exists(directory.path_join("raw_pixel_art.png"))
	):
		return false
	var record_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(record_path))
	var manifest_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not record_value is Dictionary or not manifest_value is Dictionary:
		return false
	var record := record_value as Dictionary
	var manifest := manifest_value as Dictionary
	var verification := manifest.get("ai_visual_identity_verification", {}) as Dictionary
	return (
		str(record.get("schema", "")) == CACHE_SCHEMA
		and str(record.get("key", "")) == key
		and str(record.get("pipeline_version", "")) == VISUAL_PIPELINE_VERSION
		and str(manifest.get("schema", "")) == MANIFEST_SCHEMA
		and str(manifest.get("status", "")) == "success"
		and bool(manifest.get("firearm_visual_gate_passed", false))
		and str(verification.get("schema", "")) == VISUAL_VERIFICATION_SCHEMA
		and bool(verification.get("passed", false))
	)


func _persist_cache(source_directory: String, manifest: Dictionary) -> Dictionary:
	if active_cache_key.is_empty():
		return {"ok": false, "error": "FIREARM_VISUAL_CACHE_KEY_MISSING"}
	var source_sprite := source_directory.path_join("processed_sprite.png")
	if not FileAccess.file_exists(source_sprite):
		return {"ok": false, "error": "FIREARM_VISUAL_CACHE_SPRITE_MISSING"}
	var cache_directory := _absolute_path(CACHE_ROOT.path_join(active_cache_key))
	if DirAccess.make_dir_recursive_absolute(cache_directory) != OK:
		return {"ok": false, "error": "FIREARM_VISUAL_CACHE_DIRECTORY_FAILED"}
	var sprite_bytes := FileAccess.get_file_as_bytes(source_sprite)
	if sprite_bytes.is_empty():
		return {"ok": false, "error": "FIREARM_VISUAL_CACHE_SPRITE_READ_FAILED"}
	if (
		_write_bytes_atomic(cache_directory.path_join("raw_pixel_art.png"), sprite_bytes) != OK
		or _write_bytes_atomic(cache_directory.path_join("processed_sprite.png"), sprite_bytes) != OK
	):
		return {"ok": false, "error": "FIREARM_VISUAL_CACHE_SPRITE_WRITE_FAILED"}
	var cached_manifest := manifest.duplicate(true)
	cached_manifest["cache"] = {
		"schema": CACHE_SCHEMA,
		"hit": false,
		"key": active_cache_key,
		"pipeline_version": VISUAL_PIPELINE_VERSION,
	}
	if _write_json_atomic(cache_directory.path_join("manifest.json"), cached_manifest) != OK:
		return {"ok": false, "error": "FIREARM_VISUAL_CACHE_MANIFEST_WRITE_FAILED"}
	var record := {
		"schema": CACHE_SCHEMA,
		"key": active_cache_key,
		"pipeline_version": VISUAL_PIPELINE_VERSION,
		"identity": str(active_request_payload.get("identity", "")),
		"canonical_name": str(active_request_payload.get("canonical_name", "")),
		"processed_sprite_sha256": _bytes_sha256(sprite_bytes),
		"player_confirmation_required": false,
	}
	if _write_json_atomic(cache_directory.path_join("cache_record.json"), record) != OK:
		return {"ok": false, "error": "FIREARM_VISUAL_CACHE_RECORD_WRITE_FAILED"}
	return {"ok": true, "directory": cache_directory, "key": active_cache_key}


func _visual_verification_retry_prompt(verification: Dictionary) -> String:
	var verdict := verification.get("verdict", {}) as Dictionary
	var missing: Array[String] = []
	for raw: Variant in verdict.get("required_landmarks_missing", []):
		missing.append(str(raw))
	var contradictions: Array[String] = []
	for raw: Variant in verdict.get("contradictions", []):
		contradictions.append(str(raw))
	var details := PackedStringArray()
	if not missing.is_empty():
		details.append("make these exact landmarks visible: %s" % "; ".join(missing))
	if not contradictions.is_empty():
		details.append("remove these lookalike conflicts: %s" % "; ".join(contradictions))
	var closest := str(verdict.get("closest_confusable_identity", "")).strip_edges()
	if not closest.is_empty() and closest.to_lower() != "none":
		details.append("do not resemble %s" % closest)
	if details.is_empty():
		details.append("redraw the exact named model so its identity remains readable at 96 pixels")
	return ("Automatic exact-identity redraw: %s." % ". ".join(details)).left(800)


func _normalize_identity(value: String) -> String:
	var normalized := value.strip_edges().to_upper()
	for separator: String in [" ", "-", "_", "·", ".", "/", "\\", "（", "）", "(", ")"]:
		normalized = normalized.replace(separator, "")
	return normalized


func _normalize_pixel_candidate(source_path: String, target_path: String) -> Dictionary:
	if not FileAccess.file_exists(source_path):
		return {"ok": false, "error": "FIREARM_VISUAL_FAL_PIXEL_OUTPUT_MISSING"}
	var source := Image.load_from_file(source_path)
	if source == null or source.is_empty():
		return {"ok": false, "error": "FIREARM_VISUAL_FAL_PIXEL_OUTPUT_INVALID"}
	if source.get_width() < 32 or source.get_height() < 32:
		return {"ok": false, "error": "FIREARM_VISUAL_FAL_PIXEL_OUTPUT_TOO_SMALL"}
	if source.get_format() != Image.FORMAT_RGBA8:
		source.convert(Image.FORMAT_RGBA8)
	var bounds := _alpha_bounds(source)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return {"ok": false, "error": "FIREARM_VISUAL_FAL_ALPHA_MISSING"}
	var cropped := source.get_region(bounds)
	var scale := minf(
		float(SUBJECT_SPAN) / float(cropped.get_width()),
		float(SUBJECT_SPAN) / float(cropped.get_height())
	)
	var resized_size := Vector2i(
		maxi(1, roundi(float(cropped.get_width()) * scale)),
		maxi(1, roundi(float(cropped.get_height()) * scale))
	)
	cropped.resize(resized_size.x, resized_size.y, Image.INTERPOLATE_NEAREST)
	var canvas := Image.create(CANVAS_SIZE.x, CANVAS_SIZE.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0.0, 0.0, 0.0, 0.0))
	var destination := Vector2i(
		(CANVAS_SIZE.x - resized_size.x) / 2,
		(CANVAS_SIZE.y - resized_size.y) / 2
	)
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
		return {"ok": false, "error": "FIREARM_VISUAL_FAL_PROCESSED_WRITE_FAILED"}
	return {
		"ok": true,
		"image": canvas,
		"source_size": [source.get_width(), source.get_height()],
		"source_bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
		"processed_bounds": [destination.x, destination.y, resized_size.x, resized_size.y],
		"opaque_colors_before": colors_before,
		"opaque_colors_after": colors_after,
	}


func _alpha_bounds(image: Image) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.10:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	return Rect2i() if max_x < min_x or max_y < min_y else Rect2i(
		min_x,
		min_y,
		max_x - min_x + 1,
		max_y - min_y + 1
	)


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
			var red_bin := clampi(int(pixel.r * 255.0) >> 5, 0, 7)
			var green_bin := clampi(int(pixel.g * 255.0) >> 5, 0, 7)
			var blue_bin := clampi(int(pixel.b * 255.0) >> 5, 0, 7)
			var key := red_bin * 64 + green_bin * 8 + blue_bin
			var group: Dictionary = bins.get(key, {
				"count": 0,
				"sum": Vector3.ZERO,
			})
			group["count"] = int(group["count"]) + 1
			group["sum"] = (group["sum"] as Vector3) + Vector3(pixel.r, pixel.g, pixel.b)
			bins[key] = group
	var groups: Array = bins.values()
	groups.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("count", 0)) > int(right.get("count", 0))
	)
	var palette: Array[Color] = []
	for index: int in range(mini(maximum_colors, groups.size())):
		var group := groups[index] as Dictionary
		var mean := (group.get("sum", Vector3.ZERO) as Vector3) / float(maxi(1, int(group.get("count", 1))))
		palette.append(Color(mean.x, mean.y, mean.z, 1.0))
	if palette.is_empty():
		return
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.10:
				continue
			var best := palette[0]
			var best_distance := INF
			for candidate: Color in palette:
				var difference := Vector3(pixel.r - candidate.r, pixel.g - candidate.g, pixel.b - candidate.b)
				var distance := difference.length_squared()
				if distance < best_distance:
					best_distance = distance
					best = candidate
			image.set_pixel(x, y, best)


func _is_supported_blueprint(blueprint: WeaponBlueprint) -> bool:
	return (
		blueprint != null
		and blueprint.behavior_family == "sustained_ranged"
		and str(blueprint.affordance.get("weapon_domain", "")) == "handheld_firearm"
	)


func _fal_error_is_retryable(error: String) -> bool:
	return (
		"NETWORK" in error
		or "HTTP_429" in error
		or "HTTP_500" in error
		or "HTTP_502" in error
		or "HTTP_503" in error
		or "HTTP_504" in error
	)


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


func _bytes_sha256(value: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value)
	return context.finish().hex_encode()


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


func _absolute_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path.simplify_path()


func _failure(error: String, retry_required: bool, retry_prompt: String = "") -> Dictionary:
	var result := {
		"ok": false,
		"status": "failed",
		"failure_reason": error,
		"error": error,
		"revision": active_revision,
		"provider": MODE_FAL_FIREARM,
		"output_directory": active_output_directory,
		"retry_required": retry_required,
		"player_confirmation_required": false,
	}
	if not retry_prompt.is_empty():
		result["retry_prompt"] = retry_prompt
	return result
