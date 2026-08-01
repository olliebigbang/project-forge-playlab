class_name AnchorResolver
extends RefCounted

const DEFAULT_PROFILES := {
	"rear_grip": Vector2(0.20, 0.66),
	"bottom_handle": Vector2(0.18, 0.78),
	"center_shaft": Vector2(0.34, 0.68),
	"two_hand_rear": Vector2(0.18, 0.67),
	"throwable_center": Vector2(0.50, 0.50)
}

static func resolve(image: Image, blueprint: WeaponBlueprint) -> WeaponVisualAsset:
	var bounds := alpha_bounds(image)
	if bounds.size == Vector2i.ZERO:
		return null
	var asset := WeaponVisualAsset.new()
	asset.source_image = image
	asset.canvas_size = image.get_size()
	asset.opaque_bounds = bounds
	asset.texture = ImageTexture.create_from_image(image)
	var centroid := alpha_centroid(image, bounds)
	var normalized: Vector2 = DEFAULT_PROFILES.get(blueprint.grip_profile, Vector2(0.20, 0.66))
	var fallback := Vector2(normalized.x * image.get_width(), normalized.y * image.get_height())
	if blueprint.grip_profile == "throwable_center":
		fallback = centroid
	asset.grip_primary = _local_opaque_candidate(image, fallback, 18)
	asset.tip = _forward_tip(image, asset.grip_primary, bounds)
	asset.muzzle = _muzzle(image, centroid, bounds, blueprint.behavior_family)
	asset.spin_pivot = centroid
	asset.grip_secondary = _secondary_grip(image, asset.grip_primary, centroid, blueprint.grip_profile)
	asset.anchor_confidence = 0.88 if asset.grip_primary.distance_to(fallback) < 14.0 else 0.70
	asset.anchor_source = "alpha_local_search+profile"
	return asset

static func alpha_bounds(image: Image) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.1:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < min_x:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)

static func alpha_centroid(image: Image, bounds: Rect2i) -> Vector2:
	var total := Vector2.ZERO
	var count := 0
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			if image.get_pixel(x, y).a > 0.1:
				total += Vector2(x, y)
				count += 1
	return total / float(maxi(1, count))

static func _local_opaque_candidate(image: Image, desired: Vector2, radius: int) -> Vector2:
	var best := desired
	var best_score := INF
	for y: int in range(maxi(0, roundi(desired.y) - radius), mini(image.get_height(), roundi(desired.y) + radius + 1)):
		for x: int in range(maxi(0, roundi(desired.x) - radius), mini(image.get_width(), roundi(desired.x) + radius + 1)):
			if image.get_pixel(x, y).a <= 0.1:
				continue
			var cross_width := 0
			for check_y: int in range(maxi(0, y - 8), mini(image.get_height(), y + 9)):
				if image.get_pixel(x, check_y).a > 0.1:
					cross_width += 1
			var score := Vector2(x, y).distance_to(desired) + float(cross_width) * 0.22 + float(x) * 0.03
			if score < best_score:
				best_score = score
				best = Vector2(x, y)
	return best

static func _forward_tip(image: Image, grip: Vector2, bounds: Rect2i) -> Vector2:
	var best := grip
	var best_x := -1
	for x: int in range(bounds.position.x, bounds.end.x):
		for y: int in range(bounds.position.y, bounds.end.y):
			if image.get_pixel(x, y).a > 0.1 and x > best_x:
				best_x = x
				best = Vector2(x, y)
	return best

static func _muzzle(image: Image, centroid: Vector2, bounds: Rect2i, family: String) -> Vector2:
	if family != "sustained_ranged":
		return _forward_tip(image, centroid, bounds)
	var front_x := bounds.end.x - 1
	var best := Vector2(front_x + 2, centroid.y)
	var best_delta := INF
	for x: int in range(maxi(bounds.position.x, front_x - 5), bounds.end.x):
		for y: int in range(bounds.position.y, bounds.end.y):
			if image.get_pixel(x, y).a <= 0.1:
				continue
			var delta := absf(float(y) - centroid.y) - float(x) * 0.002
			if delta < best_delta:
				best_delta = delta
				best = Vector2(front_x + 2, y)
	return best

static func _secondary_grip(image: Image, primary: Vector2, centroid: Vector2, profile: String) -> Vector2:
	if profile != "two_hand_rear":
		return primary.lerp(centroid, 0.45)
	return _local_opaque_candidate(image, primary.lerp(centroid, 0.55), 12)

static func save_override(blueprint_id: String, asset: WeaponVisualAsset) -> Error:
	var directory := "user://playlab/anchors"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file := FileAccess.open(directory + "/%s.json" % blueprint_id.validate_filename(), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(asset.anchors_dict(), "  "))
	return OK

