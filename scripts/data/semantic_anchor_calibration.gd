class_name SemanticAnchorCalibration
extends RefCounted

var asset: WeaponVisualAsset
var case_id := ""
var run_id := ""
var source_sprite := ""
var behavior_family := ""
var grip_profile := ""
var required_anchor_types: Array[String] = []
var auto_anchors: Dictionary = {}
var auto_anchor_source: Dictionary = {}
var auto_confidence: Dictionary = {}
var corrected_anchors: Dictionary = {}
var anchor_source: Dictionary = {}
var confidence: Dictionary = {}
var confirmation_status: Dictionary = {}
var training_transform := {"flip_x": false}

func anchor_point(anchor_type: String) -> Vector2:
	return corrected_anchors.get(anchor_type, auto_anchors.get(anchor_type, Vector2.ZERO)) as Vector2

func set_manual_anchor(anchor_type: String, point: Vector2, placement_confidence: float = 0.95) -> void:
	corrected_anchors[anchor_type] = point
	anchor_source[anchor_type] = "manual_player_calibration"
	confidence[anchor_type] = clampf(placement_confidence, 0.0, 1.0)

func retain_auto_anchor(anchor_type: String) -> void:
	corrected_anchors.erase(anchor_type)
	anchor_source[anchor_type] = str(auto_anchor_source.get(anchor_type, "auto_suggestion_retained"))
	confidence[anchor_type] = float(auto_confidence.get(anchor_type, confidence.get(anchor_type, 0.0)))

func confirm_anchor(anchor_type: String, point: Vector2, was_adjusted: bool) -> void:
	if was_adjusted:
		set_manual_anchor(anchor_type, point)
		anchor_source[anchor_type] = "player_adjusted"
		confirmation_status[anchor_type] = "player_adjusted"
	else:
		retain_auto_anchor(anchor_type)
		confirmation_status[anchor_type] = "accepted_auto"

func apply_to_asset() -> WeaponVisualAsset:
	return build_asset_copy()

func build_asset_copy() -> WeaponVisualAsset:
	if asset == null or asset.source_image == null:
		return null
	var action_type := "EffectOrigin" if required_anchor_types.has("EffectOrigin") else "StrikePoint"
	var should_flip := required_anchor_types.has(action_type) and anchor_point(action_type).x < anchor_point("GripPrimary").x
	training_transform = {"flip_x": should_flip}
	var image_copy := Image.new()
	image_copy.copy_from(asset.source_image)
	if should_flip:
		image_copy.flip_x()
	var copy := WeaponVisualAsset.new()
	copy.source_image = image_copy
	copy.canvas_size = image_copy.get_size()
	copy.texture = ImageTexture.create_from_image(image_copy)
	copy.opaque_bounds = _transformed_bounds(asset.opaque_bounds, should_flip, copy.canvas_size.x)
	copy.grip_primary = training_anchor_point("GripPrimary")
	copy.grip_secondary = training_anchor_point("GripSecondary") if required_anchor_types.has("GripSecondary") else copy.grip_primary
	if required_anchor_types.has("EffectOrigin"):
		copy.muzzle = training_anchor_point("EffectOrigin")
		copy.tip = copy.muzzle
	elif required_anchor_types.has("StrikePoint"):
		copy.tip = training_anchor_point("StrikePoint")
		copy.muzzle = copy.tip if behavior_family == "returning_thrown" else copy.grip_primary
	else:
		copy.muzzle = copy.grip_primary
		copy.tip = copy.grip_primary
	copy.spin_pivot = training_anchor_point("SpinPivot") if required_anchor_types.has("SpinPivot") else _image_centroid_fallback(copy)
	copy.anchor_sources = anchor_source.duplicate(true)
	copy.anchor_auto_sources = auto_anchor_source.duplicate(true)
	copy.anchor_auto_confidence = auto_confidence.duplicate(true)
	copy.anchor_confirmation_status = confirmation_status.duplicate(true)
	copy.anchor_source = _confirmation_summary()
	copy.anchor_confidence = _minimum_required_auto_confidence()
	copy.orientation_flipped = should_flip
	copy.orientation_source = "GripPrimary->%s" % action_type
	return copy

func training_anchor_point(anchor_type: String) -> Vector2:
	var point := anchor_point(anchor_type)
	if bool(training_transform.get("flip_x", false)):
		return Vector2(float(asset.canvas_size.x - 1) - point.x, point.y)
	return point

func to_dict() -> Dictionary:
	return {
		"case_id": case_id,
		"run_id": run_id,
		"source_sprite": source_sprite,
		"auto_anchors": _points_to_arrays(auto_anchors),
		"auto_anchor_source": auto_anchor_source.duplicate(true),
		"auto_confidence": auto_confidence.duplicate(true),
		"corrected_anchors": _points_to_arrays(resolved_required_anchors()),
		"anchor_source": anchor_source.duplicate(true),
		"confidence": confidence.duplicate(true),
		"confirmation_status": confirmation_status.duplicate(true),
		"required_anchor_types": required_anchor_types.duplicate(),
		"behavior_family": behavior_family,
		"grip_profile": grip_profile,
		"training_transform": training_transform.duplicate(true)
	}

func resolved_required_anchors() -> Dictionary:
	var resolved: Dictionary = {}
	for anchor_type: String in required_anchor_types:
		resolved[anchor_type] = anchor_point(anchor_type)
	return resolved

func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if asset == null or asset.source_image == null:
		errors.append("SOURCE_ASSET_MISSING")
		return errors
	for anchor_type: String in required_anchor_types:
		if not corrected_anchors.has(anchor_type) and not auto_anchors.has(anchor_type):
			errors.append("REQUIRED_ANCHOR_MISSING:%s" % anchor_type)
			continue
		var point := anchor_point(anchor_type)
		if point.x < 0.0 or point.y < 0.0 or point.x >= asset.canvas_size.x or point.y >= asset.canvas_size.y:
			errors.append("ANCHOR_OUT_OF_BOUNDS:%s" % anchor_type)
	return errors

func save_json(path: String) -> Error:
	if not validation_errors().is_empty():
		return ERR_INVALID_DATA
	var absolute_path := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	var directory := absolute_path.get_base_dir()
	var directory_error := DirAccess.make_dir_recursive_absolute(directory)
	if directory_error != OK:
		return directory_error
	var temporary_path := absolute_path + ".tmp"
	var backup_path := absolute_path + ".previous"
	if FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(temporary_path)
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict(), "  ") + "\n")
	file.close()
	if FileAccess.file_exists(backup_path):
		var stale_backup_error := DirAccess.remove_absolute(backup_path)
		if stale_backup_error != OK:
			return stale_backup_error
	if FileAccess.file_exists(absolute_path):
		var backup_error := DirAccess.rename_absolute(absolute_path, backup_path)
		if backup_error != OK:
			return backup_error
	var promote_error := DirAccess.rename_absolute(temporary_path, absolute_path)
	if promote_error != OK:
		if FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(backup_path, absolute_path)
		return promote_error
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_path)
	return OK

func _minimum_required_confidence() -> float:
	var minimum := 1.0
	for anchor_type: String in required_anchor_types:
		minimum = minf(minimum, float(confidence.get(anchor_type, 0.0)))
	return minimum

func _minimum_required_auto_confidence() -> float:
	var minimum := 1.0
	for anchor_type: String in required_anchor_types:
		minimum = minf(minimum, float(auto_confidence.get(anchor_type, 0.0)))
	return minimum

func _confirmation_summary() -> String:
	for anchor_type: String in required_anchor_types:
		if str(confirmation_status.get(anchor_type, "")) == "player_adjusted":
			return "player_adjusted"
	if not confirmation_status.is_empty():
		return "accepted_auto"
	return str(anchor_source.get("GripPrimary", "none"))

static func _points_to_arrays(points: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in points.keys():
		var point: Vector2 = points[key]
		result[key] = [snappedf(point.x, 0.01), snappedf(point.y, 0.01)]
	return result

static func _transformed_bounds(bounds: Rect2i, flip_x: bool, width: int) -> Rect2i:
	if not flip_x:
		return bounds
	return Rect2i(width - bounds.end.x, bounds.position.y, bounds.size.x, bounds.size.y)

static func _image_centroid_fallback(value: WeaponVisualAsset) -> Vector2:
	return Vector2(value.opaque_bounds.get_center())
