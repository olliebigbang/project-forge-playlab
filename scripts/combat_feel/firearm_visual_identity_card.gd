class_name FirearmVisualIdentityCard
extends RefCounted

const SCHEMA := "forge-firearm-visual-identity-card-v1"
const VISUAL_AXIS_KEYS: PackedStringArray = [
	"stock_profile",
	"upper_landmark",
	"magazine_profile",
	"fore_end_profile",
	"receiver_profile",
]


static func compile(blueprint: WeaponBlueprint) -> Dictionary:
	if blueprint == null or blueprint.behavior_family != "sustained_ranged":
		return _failure("FIREARM_VISUAL_IDENTITY_CARD_BLUEPRINT_UNSUPPORTED")
	var explicit: Dictionary = {}
	if blueprint.modifiers.get("firearm_visual_identity_card", {}) is Dictionary:
		explicit = (
			blueprint.modifiers.get("firearm_visual_identity_card", {}) as Dictionary
		).duplicate(true)
	var axes: Dictionary = {}
	if explicit.get("visual_axes", {}) is Dictionary:
		axes = (explicit.get("visual_axes", {}) as Dictionary).duplicate(true)
	if axes.is_empty():
		axes = _derived_visual_axes(blueprint.affordance)
	var required := _string_array(explicit.get("required_landmarks_en", []), 8, 180)
	if required.is_empty():
		required = _derived_required_landmarks(blueprint)
	var exclusions := _string_array(explicit.get("confusable_exclusions_en", []), 8, 220)
	if exclusions.is_empty():
		exclusions = _derived_confusable_exclusions(blueprint.affordance)
	var card := {
		"schema": SCHEMA,
		"identity_id": str(blueprint.modifiers.get("firearm_identity_id", "dynamic_firearm")).left(96),
		"requested_identity": blueprint.player_identity_text.strip_edges().left(160),
		"canonical_name": blueprint.display_name.strip_edges().left(96),
		"visual_axes": axes,
		"required_landmarks": required,
		"confusable_exclusions": exclusions,
		"confidence": clampf(blueprint.confidence, 0.0, 1.0),
		"source": blueprint.affordance_source.strip_edges().left(120),
		"mechanics_authority": false,
		"player_confirmation_required": false,
	}
	var errors := validation_errors(card)
	if not errors.is_empty():
		return _failure(errors[0])
	card["ok"] = true
	return card


static func validation_errors(card: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if str(card.get("schema", "")) != SCHEMA:
		errors.append("FIREARM_VISUAL_IDENTITY_CARD_SCHEMA_INVALID")
	for field: String in ["identity_id", "requested_identity", "canonical_name", "source"]:
		if str(card.get(field, "")).strip_edges().is_empty():
			errors.append("FIREARM_VISUAL_IDENTITY_CARD_FIELD_MISSING:%s" % field)
	var axes := card.get("visual_axes", {}) as Dictionary
	for axis: String in VISUAL_AXIS_KEYS:
		if str(axes.get(axis, "")).strip_edges().is_empty():
			errors.append("FIREARM_VISUAL_IDENTITY_CARD_AXIS_MISSING:%s" % axis)
	var required := card.get("required_landmarks", []) as Array
	if required.size() < 2 or required.size() > 8:
		errors.append("FIREARM_VISUAL_IDENTITY_CARD_LANDMARKS_INVALID")
	var exclusions := card.get("confusable_exclusions", []) as Array
	if exclusions.is_empty() or exclusions.size() > 8:
		errors.append("FIREARM_VISUAL_IDENTITY_CARD_EXCLUSIONS_INVALID")
	if bool(card.get("mechanics_authority", true)):
		errors.append("FIREARM_VISUAL_IDENTITY_CARD_MUST_NOT_OWN_MECHANICS")
	if bool(card.get("player_confirmation_required", true)):
		errors.append("FIREARM_VISUAL_IDENTITY_CARD_MUST_BE_AUTOMATIC")
	return errors


static func _derived_visual_axes(declaration: Dictionary) -> Dictionary:
	var stock := str(declaration.get("stock_structure", ""))
	var upper := str(declaration.get("upper_profile", ""))
	var feed := str(declaration.get("feed_position", ""))
	var magazine := str(declaration.get("magazine_shape", ""))
	var barrel := str(declaration.get("barrel_length", ""))
	var layout := str(declaration.get("layout", ""))
	return {
		"stock_profile": {
			"integrated": "identity_specific_integrated_stock",
			"telescoping": "identity_specific_telescoping_stock",
			"fixed": "identity_specific_fixed_stock",
			"none": "none",
		}.get(stock, "identity_specific_rear_structure"),
		"upper_landmark": {
			"carry_handle": "raised_bridge_with_open_gap",
			"top_rail": "low_flat_receiver_rail",
			"raised_gas_tube": "raised_gas_tube_and_sight_line",
			"slide": "compact_service_pistol_slide",
		}.get(upper, "identity_specific_upper_landmark"),
		"magazine_profile": "%s_magazine_%s" % [magazine, feed],
		"fore_end_profile": "%s_identity_specific_fore_end" % barrel,
		"receiver_profile": "%s_identity_specific_receiver" % layout,
	}


static func _derived_required_landmarks(blueprint: WeaponBlueprint) -> Array[String]:
	var landmarks: Array[String] = []
	for feature: String in blueprint.preserved_visual_features:
		if not feature.begins_with("required_visible_part="):
			continue
		var landmark := feature.trim_prefix("required_visible_part=").strip_edges().left(180)
		if not landmark.is_empty() and landmark not in landmarks:
			landmarks.append(landmark)
		if landmarks.size() >= 8:
			break
	if landmarks.size() < 2:
		landmarks.append_array(["readable primary grip and receiver", "distinct muzzle and ammunition feed"])
	return landmarks


static func _derived_confusable_exclusions(declaration: Dictionary) -> Array[String]:
	match str(declaration.get("layout", "")):
		"bullpup":
			return [
				"not a conventional rifle with the magazine ahead of the primary grip",
				"not a generic science-fiction bullpup",
			]
		"pistol":
			return [
				"not a revolver or stocked machine pistol",
				"not a generic block pistol when the named identity has visible distinguishing landmarks",
			]
	return [
		"not a bullpup with the magazine behind the primary grip",
		"not a generic rifle that contradicts the named identity's stock, upper, magazine or fore-end",
	]


static func _string_array(value: Variant, maximum_count: int, maximum_length: int) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for raw: Variant in value:
		var text := str(raw).strip_edges().left(maximum_length)
		if not text.is_empty() and text not in result:
			result.append(text)
		if result.size() >= maximum_count:
			break
	return result


static func _failure(error: String) -> Dictionary:
	return {
		"ok": false,
		"error": error,
		"mechanics_authority": false,
		"player_confirmation_required": false,
	}
