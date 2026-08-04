extends Node2D

const LOCAL_PROVIDER := preload("res://scripts/services/local_comfy_forge_visual_provider.gd")
const REQUIRED_VISUAL_PROVIDER := "LOCAL_COMFYUI"
const REQUIRED_PROFILE := "flux2_klein_4b"
const OUTPUT_ROOT := "res://tools/comfyui/flux2/output"

var visual_asset: WeaponVisualAsset
var loaded_blueprint: WeaponBlueprint
var loaded_manifest: Dictionary = {}
var profile_id := ""
var result_directory := ""
var verification_only := false
var capture_path := ""
var rendered_frames := 0


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("07111f"))
	verification_only = _has_argument("--verify-only")
	capture_path = _argument_value("--capture-path=", "")
	var visual_provider := _argument_value("--visual-provider=", "")
	profile_id = _argument_value("--comfy-profile=", "")
	result_directory = _argument_value("--comfy-result=", "")
	if visual_provider != REQUIRED_VISUAL_PROVIDER:
		_fail("EXPLICIT_LOCAL_COMFYUI_PROVIDER_REQUIRED")
		return
	if profile_id != REQUIRED_PROFILE:
		_fail("EXPLICIT_FLUX2_PROFILE_REQUIRED")
		return
	if result_directory.is_empty():
		_fail("FROZEN_RESULT_DIRECTORY_REQUIRED")
		return
	result_directory = _absolute_path(result_directory)
	if not _is_inside_frozen_output_root(result_directory):
		_fail("RESULT_OUTSIDE_FLUX2_OUTPUT_ROOT")
		return
	if "/.tmp/" in _normalized_path(result_directory):
		_fail("TEMPORARY_RESULT_REJECTED")
		return
	var projection_result := _load_projection(result_directory)
	if not bool(projection_result.get("ok", false)):
		_fail(str(projection_result.get("error", "BLUEPRINT_PROJECTION_INVALID")))
		return
	loaded_blueprint = projection_result.get("blueprint") as WeaponBlueprint
	var manifest_result := _load_manifest(result_directory)
	if not bool(manifest_result.get("ok", false)):
		_fail(str(manifest_result.get("error", "MANIFEST_INVALID")))
		return
	loaded_manifest = manifest_result.get("manifest", {}) as Dictionary
	var local_provider := LOCAL_PROVIDER.new() as LocalComfyForgeVisualProvider
	local_provider.requested_profile = profile_id
	var profile_config := "res://tools/comfyui/config/profiles/%s.runtime.local.json" % profile_id
	var configure_result: Dictionary = local_provider.configure(profile_config)
	if not bool(configure_result.get("ok", false)):
		_fail("PROFILE_CONFIG_REJECTED:%s" % str(configure_result.get("error", "UNKNOWN")))
		return
	var delivery_result: Dictionary = local_provider.load_atomic_result(result_directory, loaded_blueprint)
	if str(delivery_result.get("status", "")) != "success":
		_fail("ATOMIC_DELIVERY_REJECTED:%s" % str(delivery_result.get("failure_reason", "UNKNOWN")))
		return
	visual_asset = delivery_result.get("asset") as WeaponVisualAsset
	if not _asset_is_usable(visual_asset):
		_fail("DELIVERED_WEAPON_VISUAL_ASSET_INVALID")
		return
	print("FLUX2_GODOT_TRAINING_INTEGRATION=PASS")
	print("FLUX2_GODOT_PROVIDER=%s" % REQUIRED_VISUAL_PROVIDER)
	print("FLUX2_GODOT_PROFILE=%s" % profile_id)
	print("FLUX2_GODOT_CASE=%s SEED=%s" % [
		str(loaded_manifest.get("case_id", "")),
		str(int(loaded_manifest.get("seed", 0)))
	])
	print("FLUX2_GODOT_RESULT=%s" % result_directory)
	queue_redraw()
	if verification_only and capture_path.is_empty():
		get_tree().quit(0)


func _process(_delta: float) -> void:
	if visual_asset == null or capture_path.is_empty():
		return
	rendered_frames += 1
	if rendered_frames < 12:
		return
	var capture := get_viewport().get_texture().get_image()
	if capture == null:
		_fail("VIEWPORT_CAPTURE_UNAVAILABLE")
		return
	var absolute_capture := _absolute_path(capture_path)
	DirAccess.make_dir_recursive_absolute(absolute_capture.get_base_dir())
	var error := capture.save_png(absolute_capture)
	print("FLUX2_GODOT_CAPTURE=%s ERROR=%d SIZE=%s" % [absolute_capture, error, capture.get_size()])
	get_tree().quit(0 if error == OK else 1)


func _draw() -> void:
	_draw_training_stage()
	if visual_asset != null:
		_draw_player_holding_delivered_sprite()


func _draw_training_stage() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color("07111f"), true)
	draw_rect(Rect2(0, 450, 1280, 270), Color("101c2c"), true)
	draw_rect(Rect2(0, 448, 1280, 5), Color("2dd4bf"), true)
	for x: int in range(0, 1281, 80):
		draw_line(Vector2(x, 450), Vector2(640.0 + (float(x) - 640.0) * 1.8, 720), Color(0.18, 0.42, 0.48, 0.24), 2.0)
	for y: int in range(490, 721, 46):
		draw_line(Vector2(0, y), Vector2(1280, y), Color(0.18, 0.42, 0.48, 0.22), 2.0)
	for center: Vector2 in [Vector2(130, 230), Vector2(1150, 230)]:
		draw_circle(center, 90.0, Color(0.04, 0.16, 0.24, 0.86))
		draw_arc(center, 72.0, 0.0, TAU, 32, Color("2dd4bf"), 5.0)
		draw_arc(center, 54.0, 0.0, TAU, 24, Color(0.96, 0.62, 0.16, 0.72), 3.0)
		for spoke: int in range(8):
			var angle := TAU * float(spoke) / 8.0
			draw_line(center + Vector2.from_angle(angle) * 45.0, center + Vector2.from_angle(angle) * 80.0, Color("5eead4"), 4.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(520, 450), Vector2(565, 370), Vector2(715, 370), Vector2(760, 450)
	]), Color("16283a"))
	draw_line(Vector2(565, 370), Vector2(715, 370), Color("f59e0b"), 5.0)


func _draw_player_holding_delivered_sprite() -> void:
	var player_position := Vector2(435, 430)
	var hand_primary := player_position + Vector2(86, -48)
	var skin := Color("f2c7a5")
	draw_circle(player_position + Vector2(0, -112), 24.0, Color("dbeafe"))
	draw_circle(player_position + Vector2(0, -112), 19.0, skin)
	draw_colored_polygon(PackedVector2Array([
		player_position + Vector2(-28, -84),
		player_position + Vector2(30, -84),
		player_position + Vector2(37, -12),
		player_position + Vector2(-34, -12)
	]), Color("155e75"))
	draw_line(player_position + Vector2(-14, -10), player_position + Vector2(-23, 35), Color("94a3b8"), 12.0)
	draw_line(player_position + Vector2(17, -10), player_position + Vector2(29, 35), Color("94a3b8"), 12.0)
	draw_line(player_position + Vector2(-20, -66), hand_primary, skin, 12.0)
	var secondary_hand := hand_primary + Vector2(28, 17)
	draw_line(player_position + Vector2(20, -62), secondary_hand, skin, 12.0)
	var max_extent := maxf(float(visual_asset.opaque_bounds.size.x), float(visual_asset.opaque_bounds.size.y))
	var sprite_scale := clampf(160.0 / maxf(1.0, max_extent), 1.15, 1.65)
	draw_set_transform(hand_primary, -0.08, Vector2(sprite_scale, sprite_scale))
	draw_texture(visual_asset.texture, -visual_asset.grip_primary)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_circle(hand_primary, 7.0, skin)
	draw_circle(secondary_hand, 7.0, skin)
	# A subtle in-world forge aura; it is presentation, not an anchor/debug overlay.
	draw_arc(hand_primary + Vector2(95, 0), 135.0, -1.15, 1.15, 28, Color(0.18, 0.83, 0.75, 0.22), 4.0)


func _load_projection(directory: String) -> Dictionary:
	var path := directory.path_join("blueprint_projection.json")
	var parsed := _parse_json_dictionary(path)
	if not bool(parsed.get("ok", false)):
		return parsed
	var projection := parsed.get("value", {}) as Dictionary
	var canonical_name := str(projection.get("canonical_name_en", "")).strip_edges()
	var parts := _string_array(projection.get("required_identity_parts", []))
	if canonical_name.is_empty() or parts.size() < 2:
		return {"ok": false, "error": "FROZEN_IDENTITY_PROJECTION_INCOMPLETE"}
	var blueprint := WeaponBlueprint.from_dict({
		"id": "flux2-training-delivery",
		"display_name": canonical_name,
		"source_identity": canonical_name,
		"player_identity_text": canonical_name,
		"identity_confidence": 1.0,
		"preserved_visual_features": parts,
		"visual_description": str(projection.get("visual_prompt_en", "")),
		"visual_prompt": str(projection.get("visual_prompt_en", ""))
	})
	return {"ok": true, "blueprint": blueprint}


func _load_manifest(directory: String) -> Dictionary:
	var parsed := _parse_json_dictionary(directory.path_join("manifest.json"))
	if not bool(parsed.get("ok", false)):
		return parsed
	var manifest := parsed.get("value", {}) as Dictionary
	if str(manifest.get("status", "")) != "success":
		return {"ok": false, "error": "ONLY_SUCCESSFUL_ATOMIC_RESULT_ALLOWED"}
	if str(manifest.get("profile_id", "")) != profile_id:
		return {"ok": false, "error": "RESULT_PROFILE_MISMATCH"}
	if str(manifest.get("mode", "")) != "t2i":
		return {"ok": false, "error": "FORMAL_T2I_RESULT_REQUIRED"}
	if not str(manifest.get("output_group", "")).begins_with("flux2_matrix_"):
		return {"ok": false, "error": "FORMAL_MATRIX_RESULT_REQUIRED"}
	if not FileAccess.file_exists(directory.path_join("raw.png")):
		return {"ok": false, "error": "FROZEN_RAW_IMAGE_MISSING"}
	return {"ok": true, "manifest": manifest}


func _parse_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "REQUIRED_FILE_MISSING:%s" % path.get_file()}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {"ok": false, "error": "INVALID_JSON:%s" % path.get_file()}
	return {"ok": true, "value": parsed as Dictionary}


func _asset_is_usable(asset: WeaponVisualAsset) -> bool:
	if asset == null or asset.source_image == null or asset.texture == null:
		return false
	if asset.canvas_size != Vector2i(96, 96) or asset.source_image.get_size() != Vector2i(96, 96):
		return false
	if asset.opaque_bounds.size == Vector2i.ZERO:
		return false
	var has_foreground := false
	var has_transparency := false
	for y: int in range(asset.source_image.get_height()):
		for x: int in range(asset.source_image.get_width()):
			var alpha := asset.source_image.get_pixel(x, y).a
			has_foreground = has_foreground or alpha > 0.1
			has_transparency = has_transparency or alpha < 0.9
	return has_foreground and has_transparency


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item: Variant in value:
			var text := str(item).strip_edges()
			if not text.is_empty():
				result.append(text)
	return result


func _is_inside_frozen_output_root(path: String) -> bool:
	var output_root := _normalized_path(ProjectSettings.globalize_path(OUTPUT_ROOT))
	var candidate := _normalized_path(path)
	return candidate.begins_with(output_root + "/")


func _normalized_path(path: String) -> String:
	return path.simplify_path().replace("\\", "/").to_lower()


func _absolute_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path).simplify_path()
	return path.simplify_path()


func _argument_value(prefix: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return fallback


func _has_argument(expected: String) -> bool:
	return expected in OS.get_cmdline_user_args()


func _fail(reason: String) -> void:
	push_error("FLUX2_GODOT_TRAINING_INTEGRATION_FAILED:%s" % reason)
	print("FLUX2_GODOT_TRAINING_INTEGRATION=FAIL REASON=%s" % reason)
	get_tree().quit(1)
