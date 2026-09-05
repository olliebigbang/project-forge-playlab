class_name WeaponEntryFactory
extends RefCounted

const AXES := preload("res://scripts/combat_feel/mechanism_axis_resolver.gd")
const RANGED := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")
const LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")
const READABILITY := preload("res://scripts/combat_feel/mechanism_visual_readability_gate.gd")
const MOTION := preload("res://scripts/combat_feel/melee_motion_compiler.gd")


static func finish(blueprint: WeaponBlueprint, visual_result: Dictionary) -> Dictionary:
	var asset := visual_result.get("asset") as WeaponVisualAsset
	var manifest := visual_result.get("manifest", {}) as Dictionary
	if blueprint == null or asset == null or manifest.is_empty():
		return _failure("WEAPON_FINISH_INPUT_MISSING")
	if bool(blueprint.modifiers.get("local_sample_only", false)) or str(manifest.get("visual_mode", "")).contains("fallback"):
		return _failure("WEAPON_FINISH_FINISHED_ART_REQUIRED")
	var entry := {"ok": true, "blueprint": blueprint, "asset": asset, "identity": blueprint.player_identity_text, "display_name": blueprint.display_name, "ranged_runtime_profile": {}, "accepted_visual": true, "source_kind": "general_weapon_generation"}
	if str(blueprint.affordance.get("weapon_domain", "")) == "handheld_firearm":
		var gate := manifest.get("firearm_visual_identity_gate", {}) as Dictionary
		if not bool(gate.get("ok", false)):
			return _failure("WEAPON_FINISH_FIREARM_VISUAL_GATE_REQUIRED")
		var runtime := RANGED.compile(blueprint.affordance, blueprint.affordance_source)
		if not bool(runtime.get("ok", false)):
			return runtime
		blueprint.modifiers["ranged_runtime_profile"] = runtime.duplicate(true)
		entry["ranged_runtime_profile"] = runtime
		entry["visual_evidence"] = {"source": "firearm_identity_gate", "gate": gate}
		return entry
	var resolved := AXES.resolve_ai(asset, blueprint.affordance, blueprint.affordance_source)
	if not bool(resolved.get("ok", false)):
		return resolved
	var profile := resolved.get("profile") as Resource
	if profile == null:
		return _failure("WEAPON_FINISH_PROFILE_MISSING")
	if asset.visual_rig == null:
		var attachment := {"ok": true}
		if not blueprint.visual_rig.is_empty():
			attachment = LOADER.new().attach_ai_visual_rig(asset, blueprint.visual_rig)
		elif str(profile.flex_topology) != "none" or str(profile.tether_topology) != "none":
			attachment = LOADER.new().build_automatic_visual_rig(asset, profile)
		if not bool(attachment.get("ok", false)):
			return attachment
	var gate := READABILITY.evaluate(asset, profile, blueprint.visual_structure_brief)
	if not bool(gate.get("ok", false)):
		return gate
	var motion: Variant = MOTION.new().compile(profile, asset.anchors_dict(), asset.opaque_bounds)
	if not motion is Resource or not motion.validation_errors().is_empty():
		return _failure("WEAPON_FINISH_MOTION_INVALID")
	entry["affordance_profile"] = profile
	entry["visual_evidence"] = {"source": "mechanism_readability_gate", "gate": gate, "semantic_source": blueprint.affordance_source}
	return entry


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error, "player_confirmation_required": false}
