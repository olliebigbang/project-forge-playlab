class_name WeaponVisualAsset
extends RefCounted

const SILHOUETTE_ALPHA_THRESHOLD := 0.12

var texture: Texture2D
var source_image: Image
var canvas_size: Vector2i = Vector2i(96, 96)
var opaque_bounds: Rect2i = Rect2i()
var grip_primary: Vector2 = Vector2.ZERO
var grip_secondary: Vector2 = Vector2.ZERO
var muzzle: Vector2 = Vector2.ZERO
var tip: Vector2 = Vector2.ZERO
var spin_pivot: Vector2 = Vector2.ZERO
var rear_contact: Vector2 = Vector2.ZERO
var anchor_confidence: float = 0.0
var anchor_source: String = "none"
var anchor_sources: Dictionary = {}
var anchor_auto_sources: Dictionary = {}
var anchor_auto_confidence: Dictionary = {}
var anchor_confirmation_status: Dictionary = {}
var orientation_flipped := false
var orientation_source := "none"

func anchors_dict() -> Dictionary:
	return {
		"grip_primary": [roundi(grip_primary.x), roundi(grip_primary.y)],
		"grip_secondary": [roundi(grip_secondary.x), roundi(grip_secondary.y)],
		"muzzle": [roundi(muzzle.x), roundi(muzzle.y)],
		"tip": [roundi(tip.x), roundi(tip.y)],
		"spin_pivot": [roundi(spin_pivot.x), roundi(spin_pivot.y)],
		"rear_contact": [roundi(rear_contact.x), roundi(rear_contact.y)],
		"orientation_flipped": orientation_flipped,
		"orientation_source": orientation_source,
		"silhouette_grip_inertia_proxy_raw": calculate_silhouette_grip_inertia_proxy_raw(),
		"confidence": anchor_confidence,
		"anchor_source": anchor_source,
		"anchor_sources": anchor_sources.duplicate(true),
		"auto_anchor_source": anchor_auto_sources.duplicate(true),
		"auto_confidence": anchor_auto_confidence.duplicate(true),
		"confirmation_status": anchor_confirmation_status.duplicate(true),
	}


func calculate_silhouette_grip_inertia_proxy_raw() -> float:
	if source_image == null or source_image.is_empty():
		return 0.0
	var minimum := Vector2i(source_image.get_width(), source_image.get_height())
	var maximum := Vector2i(-1, -1)
	var mask_pixel_count := 0
	var squared_distance_sum := 0.0
	for y: int in range(source_image.get_height()):
		for x: int in range(source_image.get_width()):
			if source_image.get_pixel(x, y).a < SILHOUETTE_ALPHA_THRESHOLD:
				continue
			minimum.x = mini(minimum.x, x)
			minimum.y = mini(minimum.y, y)
			maximum.x = maxi(maximum.x, x)
			maximum.y = maxi(maximum.y, y)
			mask_pixel_count += 1
			squared_distance_sum += Vector2(float(x), float(y)).distance_squared_to(grip_primary)
	if mask_pixel_count == 0:
		return 0.0
	var mask_size := maximum - minimum + Vector2i.ONE
	var major_axis := float(maxi(mask_size.x, mask_size.y))
	if major_axis <= 0.0:
		return 0.0
	return squared_distance_sum / (float(mask_pixel_count) * major_axis * major_axis)
