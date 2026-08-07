class_name WeaponVisualAsset
extends RefCounted

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
		"confidence": anchor_confidence, "anchor_source": anchor_source
	}
