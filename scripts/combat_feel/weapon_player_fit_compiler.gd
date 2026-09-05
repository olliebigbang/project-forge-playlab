class_name WeaponPlayerFitCompiler
extends RefCounted

const SCHEMA := "forge-weapon-player-fit-v1"


static func compile(blueprint: WeaponBlueprint, asset: WeaponVisualAsset) -> Dictionary:
	if blueprint == null or asset == null:
		return _failure("WEAPON_PLAYER_FIT_INPUT_MISSING")
	var axes := blueprint.affordance
	var firearm := str(axes.get("weapon_domain", "")) == "handheld_firearm"
	var support_mode := str(axes.get("support_mode", ""))
	var grip_topology := str(axes.get("grip_topology", ""))
	var one_hand := support_mode == "one_hand" or grip_topology == "one_hand_handle"
	var body_grip := grip_topology in ["body_grip", "clamp_grip"]
	var styled_links := str(blueprint.modifiers.get("art_style_id", "")) == "church_v1" and (str(axes.get("flex_topology", "none")) == "linked_segments" or str(axes.get("tether_topology", "none")) == "linked_segments")
	var support_required := not one_hand
	if not firearm and grip_topology.is_empty():
		support_required = blueprint.grip_profile == "two_hand_rear"
		one_hand = not support_required

	var visual_span := float(asset.opaque_bounds.size.x)
	if visual_span <= 0.0:
		visual_span = float(maxi(1, asset.canvas_size.x))
	var body_length := str(axes.get("body_length", "medium"))
	var target_span := float({"short": 48.0, "medium": 68.0, "long": 88.0}.get(body_length, 68.0))
	var minimum_scale := 0.42
	var maximum_scale := 1.18
	if firearm:
		target_span = 34.0 if one_hand else 70.0
		minimum_scale = 0.34 if one_hand else 0.58
		maximum_scale = 0.88
	elif body_grip:
		# Gripping the body does not make a long, thin object palm-sized. Only
		# compact/bulky silhouettes use the compact fit; length remains an axis.
		var slenderness := visual_span / maxf(1.0, float(asset.opaque_bounds.size.y))
		# A flexible linked body hanging below its grip is not a compact solid
		# lump. Keep its length-axis fit so link holes and terminal art survive.
		if slenderness < 4.0 and not styled_links: target_span = minf(target_span, 54.0)
	elif str(axes.get("flex_topology", "none")) != "none" or str(axes.get("tether_topology", "none")) != "none":
		# Only the solid part is fitted to the character. Deployed line length is
		# rendered by the soft-weapon rig and must not shrink the handle/body.
		target_span = minf(target_span, 76.0)
	var draw_scale := clampf(target_span / maxf(1.0, visual_span), minimum_scale, maximum_scale)

	var hand_offset := Vector2(18.0, -10.0)
	if support_required:
		hand_offset = Vector2(18.0, -7.0)
	elif body_grip:
		hand_offset = Vector2(15.0, -4.0)
	elif not firearm:
		hand_offset = Vector2(19.0, -10.0)

	var secondary_delta := (asset.grip_secondary - asset.grip_primary) * draw_scale
	if support_required and secondary_delta.length() < 8.0:
		secondary_delta = Vector2(28.0, 1.0)
	if secondary_delta.length() > 44.0:
		secondary_delta = secondary_delta.normalized() * 44.0
	var resting_support_offset := Vector2(-12.0, 15.0)
	if body_grip:
		resting_support_offset = Vector2(-8.0, 4.0)

	return {
		"ok": true,
		"schema": SCHEMA,
		"draw_scale": draw_scale,
		"visual_span_pixels": visual_span,
		"target_span_pixels": target_span,
		"rendered_span_pixels": visual_span * draw_scale,
		"primary_hand_offset": hand_offset,
		"secondary_grip_delta": secondary_delta,
		"resting_support_offset": resting_support_offset,
		"support_required": support_required,
		"one_hand": one_hand,
		"body_grip": body_grip,
		"weapon_between_arms": true,
		"identity_inputs_used": false,
		"player_confirmation_required": false,
	}


static func _failure(error: String) -> Dictionary:
	return {
		"ok": false,
		"schema": SCHEMA,
		"error": error,
		"identity_inputs_used": false,
		"player_confirmation_required": false,
	}
