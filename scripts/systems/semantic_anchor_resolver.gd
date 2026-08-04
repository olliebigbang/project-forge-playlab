class_name SemanticAnchorResolver
extends RefCounted

const BASE_RESOLVER := preload("res://scripts/systems/anchor_resolver.gd")
const CALIBRATION := preload("res://scripts/data/semantic_anchor_calibration.gd")

static func required_anchor_types(blueprint: WeaponBlueprint) -> Array[String]:
	var required: Array[String] = ["GripPrimary"]
	if blueprint.grip_profile == "two_hand_rear":
		required.append("GripSecondary")
	match blueprint.behavior_family:
		"returning_thrown":
			required.append("SpinPivot")
			required.append("StrikePoint")
		"heavy_melee":
			required.append("StrikePoint")
		_:
			required.append("EffectOrigin")
	return required

static func resolve(image: Image, blueprint: WeaponBlueprint) -> RefCounted:
	var base_asset: WeaponVisualAsset = BASE_RESOLVER.resolve(image, blueprint)
	if base_asset == null:
		return null
	var calibration = CALIBRATION.new()
	calibration.asset = base_asset
	calibration.behavior_family = blueprint.behavior_family
	calibration.grip_profile = blueprint.grip_profile
	calibration.required_anchor_types = required_anchor_types(blueprint)
	calibration.auto_anchors["GripPrimary"] = base_asset.grip_primary
	calibration.anchor_source["GripPrimary"] = "AnchorResolver:%s" % base_asset.anchor_source
	calibration.confidence["GripPrimary"] = base_asset.anchor_confidence
	if calibration.required_anchor_types.has("GripSecondary"):
		calibration.auto_anchors["GripSecondary"] = suggest_secondary(image, base_asset.grip_primary)
		calibration.anchor_source["GripSecondary"] = "alpha_centroid_from_primary"
		calibration.confidence["GripSecondary"] = 0.76
	if calibration.required_anchor_types.has("SpinPivot"):
		calibration.auto_anchors["SpinPivot"] = alpha_centroid(image)
		calibration.anchor_source["SpinPivot"] = "alpha_centroid"
		calibration.confidence["SpinPivot"] = 0.96
	if calibration.required_anchor_types.has("EffectOrigin"):
		calibration.auto_anchors["EffectOrigin"] = base_asset.muzzle
		calibration.anchor_source["EffectOrigin"] = "AnchorResolver:muzzle"
		calibration.confidence["EffectOrigin"] = 0.58
	if calibration.required_anchor_types.has("StrikePoint"):
		calibration.auto_anchors["StrikePoint"] = base_asset.tip
		calibration.anchor_source["StrikePoint"] = "AnchorResolver:tip"
		calibration.confidence["StrikePoint"] = 0.58
	calibration.auto_anchor_source = calibration.anchor_source.duplicate(true)
	calibration.auto_confidence = calibration.confidence.duplicate(true)
	return calibration

static func recompute_derived(calibration: RefCounted, image: Image) -> void:
	if calibration.required_anchor_types.has("GripSecondary"):
		calibration.corrected_anchors["GripSecondary"] = suggest_secondary(image, calibration.anchor_point("GripPrimary"))
		calibration.anchor_source["GripSecondary"] = "derived_after_primary_calibration"
		calibration.confidence["GripSecondary"] = 0.90
	if calibration.required_anchor_types.has("SpinPivot"):
		calibration.corrected_anchors["SpinPivot"] = alpha_centroid(image)
		calibration.anchor_source["SpinPivot"] = "alpha_centroid_after_calibration"
		calibration.confidence["SpinPivot"] = 0.98

static func alpha_centroid(image: Image) -> Vector2:
	var bounds := BASE_RESOLVER.alpha_bounds(image)
	if bounds.size == Vector2i.ZERO:
		return Vector2.ZERO
	return BASE_RESOLVER.alpha_centroid(image, bounds)

static func suggest_secondary(image: Image, primary: Vector2) -> Vector2:
	var centroid := alpha_centroid(image)
	var to_center := centroid - primary
	if to_center.length() < 1.0:
		return _nearest_opaque(image, primary, 12)
	var travel := clampf(to_center.length() * 0.48, 9.0, 25.0)
	var desired := primary + to_center.normalized() * travel
	return _nearest_opaque(image, desired, 14)

static func is_on_or_near_alpha(image: Image, point: Vector2, radius: int = 3) -> bool:
	var center := Vector2i(roundi(point.x), roundi(point.y))
	for y: int in range(maxi(0, center.y - radius), mini(image.get_height(), center.y + radius + 1)):
		for x: int in range(maxi(0, center.x - radius), mini(image.get_width(), center.x + radius + 1)):
			if image.get_pixel(x, y).a > 0.1:
				return true
	return false

static func _nearest_opaque(image: Image, desired: Vector2, radius: int) -> Vector2:
	var best := desired.clamp(Vector2.ZERO, Vector2(image.get_size() - Vector2i.ONE))
	var best_distance := INF
	var center := Vector2i(roundi(desired.x), roundi(desired.y))
	for y: int in range(maxi(0, center.y - radius), mini(image.get_height(), center.y + radius + 1)):
		for x: int in range(maxi(0, center.x - radius), mini(image.get_width(), center.x + radius + 1)):
			if image.get_pixel(x, y).a <= 0.1:
				continue
			var candidate := Vector2(x, y)
			var distance := candidate.distance_squared_to(desired)
			if distance < best_distance:
				best_distance = distance
				best = candidate
	return best
