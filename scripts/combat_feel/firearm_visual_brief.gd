class_name FirearmVisualBrief
extends RefCounted

const AXES := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")
const IDENTITY_CARD := preload("res://scripts/combat_feel/firearm_visual_identity_card.gd")


static func compile(
	declaration: Dictionary,
	source: String,
	identity_card: Dictionary = {}
) -> Dictionary:
	var validation := AXES.validate_ai_declaration(declaration, source)
	if not bool(validation.get("ok", false)):
		return {
			"schema": "forge-firearm-visual-brief-v1",
			"ok": false,
			"error": str(validation.get("error", "AI_RANGED_AXES_INVALID")),
		}
	var clauses := PackedStringArray([
		"Render one finished readable 96px pixel-art firearm sprite in strict side view, facing right; the supplied scaffold is a hidden role-and-proportion guide, never the final artwork",
		_layout_clause(str(declaration.get("layout", ""))),
		_stock_clause(str(declaration.get("stock_structure", ""))),
		_feed_clause(str(declaration.get("feed_position", "")), str(declaration.get("magazine_shape", ""))),
		_barrel_clause(str(declaration.get("barrel_length", ""))),
		_upper_clause(str(declaration.get("upper_profile", ""))),
		_support_clause(str(declaration.get("support_mode", ""))),
		"Keep the muzzle, primary grip, support grip and magazine as separate visible structures; do not collapse the firearm into one long bar or copy the block scaffold as finished art",
	])
	return {
		"schema": "forge-firearm-visual-brief-v1",
		"ok": true,
		"automatic": true,
		"source": str(validation.get("source", source)),
		"axes": (validation.get("axes", {}) as Dictionary).duplicate(true),
		"required_visible_parts": _required_visible_parts(declaration),
		"required_roles": _required_visible_parts(declaration),
		"visual_identity_card": identity_card.duplicate(true),
		"prompt_clause": ". ".join(clauses) + ".",
		"structure_authority": "ai_ranged_axes",
		"generator_authority": "finished_identity_rendering_with_locked_roles",
		"scaffold_purpose": "hidden_structural_reference_only",
		"scaffold_presentable": false,
		"finished_art_requires_external_generator": true,
		"player_mechanism_input_used": false,
		"player_confirmation_required": false,
	}


static func validation_errors(brief: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if not bool(brief.get("ok", false)):
		errors.append(str(brief.get("error", "FIREARM_VISUAL_BRIEF_INVALID")))
	if str(brief.get("schema", "")) != "forge-firearm-visual-brief-v1":
		errors.append("FIREARM_VISUAL_BRIEF_SCHEMA_INVALID")
	if str(brief.get("source", "")).is_empty():
		errors.append("FIREARM_VISUAL_BRIEF_SOURCE_MISSING")
	if str(brief.get("prompt_clause", "")).is_empty():
		errors.append("FIREARM_VISUAL_BRIEF_PROMPT_MISSING")
	if not brief.get("required_visible_parts", []) is Array or (brief.get("required_visible_parts", []) as Array).is_empty():
		errors.append("FIREARM_VISUAL_BRIEF_PARTS_MISSING")
	if bool(brief.get("scaffold_presentable", true)):
		errors.append("FIREARM_VISUAL_SCAFFOLD_MUST_REMAIN_HIDDEN")
	var identity_card := brief.get("visual_identity_card", {}) as Dictionary
	if identity_card.is_empty() or not IDENTITY_CARD.validation_errors(identity_card).is_empty():
		errors.append("FIREARM_VISUAL_IDENTITY_CARD_INVALID")
	return errors


static func _required_visible_parts(declaration: Dictionary) -> Array[String]:
	var parts: Array[String] = ["primary_grip", "muzzle", "receiver"]
	match str(declaration.get("layout", "")):
		"pistol": parts.append_array(["slide", "grip_housed_magazine"])
		"bullpup": parts.append_array(["integrated_stock", "magazine_behind_grip", "support_hand_region"])
		"conventional_shotgun": parts.append_array(["rear_stock", "pump_fore_end", "tube_magazine", "loading_port"])
		"revolver": parts.append_array(["exposed_cylinder", "revolver_grip", "hammer"])
		"belt_fed_support": parts.append_array(["rear_stock", "feed_cover", "visible_ammunition_belt", "belt_box", "support_hand_region"])
		_: parts.append_array(["rear_stock", "magazine_ahead_of_grip", "support_hand_region"])
	match str(declaration.get("upper_profile", "")):
		"carry_handle": parts.append("carry_handle_gap")
		"top_rail": parts.append("straight_top_rail")
		"raised_gas_tube": parts.append("raised_gas_tube")
		"slide": parts.append("pistol_slide")
	return parts


static func _layout_clause(value: String) -> String:
	match value:
		"bullpup": return "Use a compact bullpup layout with the ammunition feed visibly behind the primary grip"
		"conventional_rifle": return "Use a conventional rifle layout with a rear stock and the ammunition feed visibly ahead of the primary grip"
		"pistol": return "Use a compact pistol layout with one grip under a short slide and no shoulder stock"
		"conventional_shotgun": return "Use a conventional shoulder-fired shotgun layout with a long barrel, a separate pump fore-end and a tube beneath the barrel"
		"revolver": return "Use a compact revolver layout with one exposed round cylinder between the grip and barrel, plus a visible hammer"
		"belt_fed_support": return "Use a heavy shoulder-fired support layout with a broad feed cover, visible ammunition belt and separate belt box"
	return "Keep the declared firearm layout visible"


static func _stock_clause(value: String) -> String:
	match value:
		"integrated": return "Make the rear receiver and stock one integrated mass"
		"telescoping": return "Show an identity-appropriate adjustable telescoping stock: collapsible polymer stock on a buffer tube or twin sliding rails, never a full fixed triangular stock"
		"fixed": return "Show a solid fixed rear stock"
		"none": return "Do not draw a shoulder stock"
	return "Preserve the declared rear structure"


static func _feed_clause(position: String, shape: String) -> String:
	var position_text: String = {
		"behind_grip": "behind the primary grip",
		"ahead_of_grip": "ahead of the primary grip",
		"in_grip": "inside the primary grip",
		"under_barrel": "beneath and parallel to the barrel",
		"cylinder_center": "between the primary grip and barrel",
		"side_feed": "at the side and underside of the receiver",
	}.get(position, "at the declared feed position")
	var shape_text: String = {
		"straight": "a straight detachable magazine",
		"curved": "a clearly curved detachable magazine",
		"in_grip": "a magazine contained by the grip silhouette",
		"tube": "a tube magazine beneath the barrel",
		"cylinder": "an exposed rotating cylinder",
		"belt_box": "a hanging ammunition belt and separate belt box",
	}.get(shape, "the declared magazine")
	return "Place %s %s" % [shape_text, position_text]


static func _barrel_clause(value: String) -> String:
	return {
		"short": "Use a short barrel and compact muzzle projection",
		"medium": "Use a medium barrel projection",
		"long": "Use a visibly long barrel projection",
	}.get(value, "Preserve the declared barrel length")


static func _upper_clause(value: String) -> String:
	return {
		"carry_handle": "Show a raised carry handle with a transparent gap beneath it",
		"top_rail": "Show a straight segmented top rail",
		"raised_gas_tube": "Show a raised gas-tube line above the receiver and handguard",
		"slide": "Show a single readable pistol slide above the frame",
	}.get(value, "Preserve the declared upper silhouette")


static func _support_clause(value: String) -> String:
	return "Leave distinct primary and support-hand regions" if value == "two_hand_shouldered" else "Keep one dominant pistol grip"
