class_name WeaponVisualAsset
extends RefCounted

const SILHOUETTE_MECHANICS := preload("res://scripts/combat_feel/silhouette_mechanics_analyzer.gd")

var texture: Texture2D
var source_image: Image
var canvas_size: Vector2i = Vector2i(96, 96)
var opaque_bounds: Rect2i = Rect2i()
var grip_primary: Vector2 = Vector2.ZERO
var grip_secondary: Vector2 = Vector2.ZERO
var muzzle: Vector2 = Vector2.ZERO
var tip: Vector2 = Vector2.ZERO
var tether_origin: Vector2 = Vector2.ZERO
var spin_pivot: Vector2 = Vector2.ZERO
var rear_contact: Vector2 = Vector2.ZERO
var anchor_confidence: float = 0.0
var anchor_source: String = "none"
var orientation_flipped := false
var orientation_source := "none"
var visual_rig: PixelWeaponVisualRig
var visual_rig_source := "none"

func anchors_dict() -> Dictionary:
	var result := {
		"grip_primary": [grip_primary.x, grip_primary.y],
		"grip_secondary": [grip_secondary.x, grip_secondary.y],
		"muzzle": [muzzle.x, muzzle.y],
		"tip": [tip.x, tip.y],
		"tether_origin": [tether_origin.x, tether_origin.y],
		"spin_pivot": [spin_pivot.x, spin_pivot.y],
		"rear_contact": [rear_contact.x, rear_contact.y],
		"orientation_flipped": orientation_flipped,
		"orientation_source": orientation_source,
		"confidence": anchor_confidence, "anchor_source": anchor_source
	}
	var mechanics := silhouette_mechanics()
	if not mechanics.is_empty():
		result["silhouette_mechanics"] = mechanics
	return result


func silhouette_mechanics() -> Dictionary:
	if source_image == null:
		return {}
	return SILHOUETTE_MECHANICS.analyze(source_image, grip_primary, tip)


func silhouette_mechanics_stability(anchor_delta: float = 2.0) -> Dictionary:
	if source_image == null:
		return {}
	return SILHOUETTE_MECHANICS.stability_report(source_image, grip_primary, tip, anchor_delta)


func has_pixel_visual_rig() -> bool:
	return visual_rig != null and visual_rig.validation_errors().is_empty()
