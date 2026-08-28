extends Node

const MECHANISM_AXIS_RESOLVER := preload("res://scripts/combat_feel/mechanism_axis_resolver.gd")
const RANGED_AXIS_RESOLVER := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")

var _pending: Dictionary = {}


func store(blueprint: WeaponBlueprint, asset: WeaponVisualAsset, affordance_profile: Resource) -> String:
	if blueprint == null or asset == null or affordance_profile == null:
		return "MECHANISM_HANDOFF_INCOMPLETE"
	if blueprint.behavior_family != "heavy_melee":
		return "MECHANISM_HANDOFF_REQUIRES_HEAVY_MELEE"
	var errors: Array[String] = affordance_profile.validation_errors()
	if not errors.is_empty():
		return "MECHANISM_HANDOFF_INVALID_PROFILE:%s" % ",".join(errors)
	var automatic: Dictionary = MECHANISM_AXIS_RESOLVER.resolve_ai(
		asset,
		blueprint.affordance,
		blueprint.affordance_source
	)
	if not bool(automatic.get("ok", false)):
		return "MECHANISM_HANDOFF_AI_RESOLUTION_REQUIRED:%s" % str(automatic.get("error", "UNKNOWN"))
	var expected_profile := automatic.get("profile") as Resource
	if expected_profile == null or expected_profile.to_dict() != affordance_profile.to_dict():
		return "MECHANISM_HANDOFF_PROFILE_NOT_AI_RESOLVED"
	var uses_soft_visuals := str(affordance_profile.flex_topology) != "none" \
		or str(affordance_profile.tether_topology) != "none"
	if uses_soft_visuals and not asset.has_pixel_visual_rig():
		return "MECHANISM_HANDOFF_AI_VISUAL_RIG_REQUIRED"
	if asset.visual_rig != null:
		var visual_axis_errors := asset.visual_rig.axis_errors(affordance_profile)
		if not visual_axis_errors.is_empty():
			return "MECHANISM_HANDOFF_AI_VISUAL_RIG_AXIS_MISMATCH:%s" % ",".join(visual_axis_errors)
	_pending = {
		"ok": true,
		"kind": "heavy_melee",
		"blueprint": blueprint,
		"asset": asset,
		"affordance_profile": affordance_profile,
		"asset_id": blueprint.id,
		"fixture": false,
		"notice": "AI-RESOLVED MECHANISM AXES · RUNTIME HANDOFF",
		"mechanism_handoff": true,
		"mechanism_source": blueprint.affordance_source,
		"visual_rig_source": asset.visual_rig_source,
	}
	return ""


func store_ranged(
	blueprint: WeaponBlueprint,
	asset: WeaponVisualAsset,
	runtime_profile: Dictionary
) -> String:
	if blueprint == null or asset == null or runtime_profile.is_empty():
		return "RANGED_HANDOFF_INCOMPLETE"
	if (
		blueprint.behavior_family != "sustained_ranged"
		or str(blueprint.affordance.get("weapon_domain", "")) != "handheld_firearm"
	):
		return "RANGED_HANDOFF_REQUIRES_FIREARM"
	var compiled: Dictionary = RANGED_AXIS_RESOLVER.compile(
		blueprint.affordance,
		blueprint.affordance_source
	)
	if not bool(compiled.get("ok", false)):
		return "RANGED_HANDOFF_INVALID_AXES:%s" % str(compiled.get("error", "UNKNOWN"))
	if (
		str(runtime_profile.get("schema", "")) != RANGED_AXIS_RESOLVER.RUNTIME_SCHEMA
		or str(runtime_profile.get("axis_signature", "")) != str(compiled.get("axis_signature", ""))
		or runtime_profile.get("final_parameters", {}) != compiled.get("final_parameters", {})
	):
		return "RANGED_HANDOFF_PROFILE_NOT_AI_COMPILED"
	blueprint.modifiers["ranged_runtime_profile"] = compiled.duplicate(true)
	_pending = {
		"ok": true,
		"kind": "ranged_firearm",
		"blueprint": blueprint,
		"asset": asset,
		"ranged_runtime_profile": compiled.duplicate(true),
		"asset_id": blueprint.id,
		"fixture": false,
		"notice": "AI-COMPILED FIREARM · RUNTIME HANDOFF",
		"mechanism_handoff": true,
		"mechanism_source": blueprint.affordance_source,
	}
	return ""


func has_pending() -> bool:
	return not _pending.is_empty()


func take() -> Dictionary:
	var result := _pending
	_pending = {}
	return result


func take_ranged() -> Dictionary:
	if str(_pending.get("kind", "")) != "ranged_firearm":
		return {}
	return take()


func clear() -> void:
	_pending.clear()
